extends SceneTree

const Skier := preload("res://skiing/skier.gd")
const Mountain := preload("res://world/mountain.gd")
var failures := 0
var completed_runs := 0
const Chairlift := preload("res://lift/chairlift.gd")


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1


func _check_powder_surface(mesh: ArrayMesh, rows: int, terrain: Node) -> void:
	var surface := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = surface[Mesh.ARRAY_NORMAL]
	var columns := floori(float(vertices.size()) / rows)
	_check(columns >= 5 and columns * rows == vertices.size(), "Each row needs a shaped powder cross-section")
	_check(normals.size() == vertices.size(), "Powder banks should respond to the valley lighting")
	var min_width := INF
	var max_width := 0.0
	var tallest_bank := 0.0
	for i in rows:
		var first := i * columns
		var width := vertices[first].distance_to(vertices[first + columns - 1])
		min_width = minf(min_width, width)
		max_width = maxf(max_width, width)
		for j in columns:
			var v := vertices[first + j]
			tallest_bank = maxf(tallest_bank, v.y - terrain.surface_height(v.x, v.z))
	_check(tallest_bank > 0.02, "A loaded turn should push up a bank of powder")
	_check(max_width > min_width * 1.06, "Turns should disturb a wider swath than the glide")


func _distance_to_run(p: Vector2, line: PackedVector2Array) -> float:
	var nearest := INF
	for i in range(1, line.size()):
		nearest = minf(nearest, Geometry2D.get_closest_point_to_segment(p, line[i-1], line[i]).distance_to(p))
	return nearest


func _ride_cut(lift: Node, line: PackedVector2Array, terrain: Node, effects: Node, guest: int) -> PackedVector2Array:
	var rider := Skier.new()
	root.add_child(rider)
	rider.start_run(lift._ski_exit, lift._queue_xz(4), guest, terrain, effects, 0, lift._right, line)
	_check(rider.used_cut_run, "A rider should use the opened run")
	var actual := PackedVector2Array()
	var max_offset := 0.0
	for p in rider._points:
		var flat := Vector2(p.x, p.z)
		if not actual.is_empty():
			_check(terrain.route_clear(actual[-1], flat, 0.17), "Carve should clear trees and rocks")
		actual.append(flat)
		max_offset = maxf(max_offset, _distance_to_run(flat, line))
	_check(max_offset > 0.55 and max_offset < 2.25, "Linked turns should weave within the drawn corridor")
	_check(actual[0].distance_to(lift._ski_exit) < 0.01 and actual[-1].distance_to(lift._queue_xz(4)) < 0.01, "Course endpoints must meet the real lift transfer")
	var left := 0.0
	var right := 0.0
	for frame in 4500:
		rider.step(1.0 / 30.0)
		left = minf(left, rider._bank)
		right = maxf(right, rider._bank)
		if not rider._active:
			break
	_check(not rider._active and left < -0.16 and right > 0.16, "Both edges should engage on a complete cut run")
	rider.free()
	return actual


func _check_forest_runs(terrain: Node, effects: Node) -> void:
	for tier in 3:
		var lift := Chairlift.new()
		root.add_child(lift)
		lift.configure(terrain.station_base(tier), terrain.station_top(tier), terrain)
		var line: PackedVector2Array = terrain.suggested_run(tier)
		if tier == 0:
			var fallback := Skier.new()
			root.add_child(fallback)
			fallback.start_run(lift._ski_exit, lift._queue_xz(4), 0, terrain, effects, 0, lift._right, line)
			_check(not fallback.used_cut_run and fallback._active, "An uncut forest corridor must fall back without taking credit")
			fallback.free()
		_check(terrain.cut_run(line) > 0, "Suggested route should create a real forest cut")
		var primary := _ride_cut(lift, line, terrain, effects, 0)
		_ride_cut(lift, line, terrain, effects, 6)
		_ride_cut(lift, line, terrain, effects, 7)
		if tier == 0:
			# Branch around a separate stand before rejoining the lower run.
			var branch := line.duplicate()
			for i in branch.size():
				var t := clampf((float(i) / (branch.size() - 1) - 0.22) / 0.56, 0.0, 1.0)
				branch[i] += Vector2(6.0 * pow(sin(PI * t), 2.0), 0.0)
			_check(terrain.cut_run(branch) > 0, "An alternate branch should remove different trees")
			var alternate := _ride_cut(lift, branch, terrain, effects, 6)
			var separation := 0.0
			for p in alternate:
				separation = maxf(separation, _distance_to_run(p, primary))
			_check(separation > 3.0 and alternate[-1].is_equal_approx(primary[-1]), "Branching should make distinct tracks before both runs merge at the lift")
			var reversed := line.duplicate()
			reversed.reverse()
			_check(Skier.cut_run_spine(lift._ski_exit, lift._queue_xz(4), reversed, terrain).is_empty(), "A reversed run is impassable")
		lift.free()


func _run() -> void:
	var terrain := Mountain.new()
	root.add_child(terrain)
	var effects := Node3D.new()
	root.add_child(effects)
	for summit: Vector2 in [terrain.left_summit, terrain.right_summit]:
		var lift := Chairlift.new()
		root.add_child(lift)
		lift.configure(terrain.base_point, summit, terrain)
		var arrival: Vector2 = lift._queue_xz(4)
		var exit: Vector2 = lift._ski_exit
		var closest_tower := INF
		for variant in 16:
			var skier := Skier.new()
			root.add_child(skier)
			skier.finished.connect(func(): completed_runs += 1)
			skier.start_run(exit, arrival, variant % 8, terrain, effects, floori(variant / 8.0), lift._right)
			# Guest identity, equipment and trail geometry must agree from lap to lap.
			var expects_board := variant % 8 in [6, 7]
			_check(skier.is_snowboarder == expects_board, "Guest changed equipment between laps")
			var trail_mesh: ArrayMesh = skier._track.mesh
			_check(skier._track.is_snowboard_track == expects_board, "Trail profile must match the rider's equipment")
			_check_powder_surface(trail_mesh, skier._points.size(), terrain)
			var previous := exit
			for point: Vector3 in skier._points:
				var flat := Vector2(point.x, point.z)
				_check(terrain.route_clear(previous, flat), "Tracks intersect an obstacle")
				previous = flat
				for j in range(1, lift._heights.size() - 1):
					var tower: Vector2 = terrain.base_point.lerp(summit, float(j) / (lift._heights.size() - 1))
					closest_tower = minf(closest_tower, tower.distance_to(Vector2(point.x, point.z)))
			var slowest_bank := 0.0
			var fastest_bank := 0.0
			var top_speed := 0.0
			var largest_climb := 0.0
			var sprayed_left := false
			var sprayed_right := false
			var frame := 0
			while skier._active and frame < 1000:
				var last_height := skier.position.y
				skier.step(1.0 / 60.0)
				# This test advances the rider without yielding an engine frame.
				# Advance the airborne snow on the same clock as the normal descent.
				var spray := skier._model._powder
				if spray != null and spray.is_processing():
					if spray.multimesh.visible_instance_count > 0:
						sprayed_left = sprayed_left or skier._bank < -0.20
						sprayed_right = sprayed_right or skier._bank > 0.20
						for puff in spray._puffs:
							if puff.age == 0.0:
								var deck: Node3D = skier._model.board if expects_board else skier._model.ski_decks[0 if spray._outside < 0.0 else 1]
								var origin := deck.to_local(puff.center)
								_check(origin.z > 0.24 and origin.z < 0.55, "Powder should leave the tail of the loaded ski or board")
								_check(absf(origin.x + spray._outside * (0.14 if expects_board else 0.028)) < 0.07, "Powder should take off from the engaged edge")
					spray._process(1.0 / 60.0)
				top_speed = maxf(top_speed, skier._speed)
				slowest_bank = minf(slowest_bank, skier._bank)
				fastest_bank = maxf(fastest_bank, skier._bank)
				largest_climb = maxf(largest_climb, skier.position.y - last_height)
				_check(terrain.playable_at(Vector2(skier.position.x, skier.position.z)), "Left snow area")
				frame += 1
			_check(not skier._active, "Run timed out")
			_check(skier.position.distance_to(Vector3(arrival.x, terrain.surface_height(arrival.x, arrival.y), arrival.y)) < 0.01, "Missed base")
			_check(slowest_bank < -0.16 and fastest_bank > 0.16, "Both edges should load")
			_check(sprayed_left and sprayed_right, "Both turn directions should kick up powder")
			_check(top_speed > 4 and skier._speed < 1.35, "Speed should build and then ease")
			_check(largest_climb < 0.006, "Unexpected uphill movement")
			_check(skier._track._complete, "Trail should outlive the rider")
			skier.step(0.1)
			skier.free()
			print("Shoulder %s %s %d: %.1fs, peak speed %.2f, banks %.0f°/%.0f°" % [summit, "boarder" if expects_board else "skier", variant % 8, frame / 60.0, top_speed, rad_to_deg(slowest_bank), rad_to_deg(fastest_bank)])
		_check(closest_tower > 1.15, "Run passed too close to a tower")
		print("Closest tower: %.2f world units" % closest_tower)
		lift.free()
	_check(completed_runs == 32, "Each arrival must signal once")
	for trail in effects.get_children():
		trail._process(34.0)
		_check(trail.is_queued_for_deletion(), "Tracks must expire")
	_check_forest_runs(terrain, effects)
	if failures == 0:
		print("PASS: all three tiers accept cut-run carving with both equipment types; a wooded branch rejoins the queue; blocked routes receive no credit.")
	terrain.free()
	effects.free()
	quit(0 if failures == 0 else 1)
