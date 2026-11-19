extends SceneTree

const Mountain := preload("res://world/mountain.gd")
const Resort := preload("res://demo/resort.gd")
const Feature := preload("res://world/slope_feature.gd")
const CarveTrack := preload("res://skiing/carve_track.gd")
const DT := 1.0 / 30.0

var errors := 0

func _initialize() -> void:
	call_deferred("_check")

func expect(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		errors += 1

func check_mesh(rider: Node, count: int) -> void:
	expect(rider._passes.size() == count, "The whole feature line must appear in this lap")
	var indices: PackedInt32Array = rider._track.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var used := PackedByteArray()
	used.resize(rider._points.size())
	for index in indices:
		used[index / CarveTrack.PROFILE_COLUMNS] = 1
	for feature in rider._passes:
		if feature.kind == Feature.EXTREME:
			var lip: Vector3 = rider._points[feature.lip_row]
			var landing: Vector3 = rider._points[feature.landing_row]
			expect(lip.y - landing.y > 6.0 and Vector2(lip.x - landing.x, lip.z - landing.z).length() > 6.0, "The summit cliff needs a major vertical drop and a clear landing")
		expect(used[feature.lip_row] == 1 and used[feature.landing_row] == 1, "Tracks should reach the lip and resume at touchdown")
		for row in range(feature.lip_row + 1, feature.landing_row):
			expect(used[row] == 0, "No triangles should paint a line underneath an airborne rider")

func check_rocks(rider: Node, terrain: Node) -> void:
	var geology: Node = terrain.summit_ledges
	var failure := ""
	for row in rider._points.size():
		var p: Vector3 = rider._points[row]
		var flat := Vector2(p.x, p.z)
		var riding := ""
		for jump in rider._passes:
			if jump.ledge_id.is_empty():
				continue
			var approach: Vector3 = rider._points[jump.ramp_row]
			if (row >= jump.ramp_row and row <= jump.landing_row) or p.distance_to(approach) < 1.3:
				riding = jump.ledge_id
		if row > 0:
			var last: Vector3 = rider._points[row - 1]
			if not terrain.route_clear(Vector2(last.x, last.z), flat, 0.14):
				failure = "Feature connector crosses a tree or boulder at " + str(flat)
				break
		if geology.contains(flat, 0.16, riding):
			failure = "Route to %s clips an unopened/other ledge at %.2f, %.2f (variant %s, row %d)" % [riding, p.x, p.z, rider._model._variant, row]
			break
	expect(failure.is_empty(), failure)
	for jump in rider._passes:
		if jump.ledge_id.is_empty():
			continue
		var site: Dictionary
		for candidate: Dictionary in geology.sites:
			if candidate.ledge_id == jump.ledge_id:
				site = candidate
				break
		expect(not site.is_empty(), "A summit takeoff needs a matching permanent rock")
		if site.is_empty():
			continue
		var lip: Vector3 = rider._points[jump.lip_row]
		var landing: Vector3 = rider._points[jump.landing_row]
		expect(Vector2(lip.x,lip.z).distance_to(site.point) < 0.01 and Vector2(landing.x,landing.z).distance_to(site.landing) < 0.01, "Equipment must hit the actual takeoff and landing")
		for row in range(jump.ramp_row, jump.lip_row + 1):
			var p: Vector3 = rider._points[row]
			expect(absf(p.y - geology.cap_height(site,Vector2(p.x,p.z))) < 0.008, "Climb the existing snow cap into takeoff")

func check_laps(lift: Node, terrain: Node, kind: int, count: int, alternatives: Array = []) -> void:
	var observed := {}
	var disciplines := {}
	var arrivals := {}
	var bypass := false
	var first_air := 1000.0
	var checked := {}
	var newest: String = alternatives.back() if not alternatives.is_empty() else ""
	lift.returned.connect(func(id: int): arrivals[id] = true)
	for frame in 30 * (150 if alternatives.is_empty() else 260 * alternatives.size()):
		lift._process(DT)
		for rider in lift.get_node("Skiers").get_children():
			var id: int = rider.get_instance_id()
			if kind == Feature.EXTREME and not checked.has(id):
				check_rocks(rider, terrain)
				checked[id] = true
			if rider._passes.is_empty():
				bypass = true
				continue
			if not observed.has(id):
				check_mesh(rider, count)
				var ledge := ""
				for jump in rider._passes:
					if not jump.ledge_id.is_empty():
						ledge = jump.ledge_id
				observed[id] = {"ledge":ledge, "kind":-1, "in_air":false, "flights":0, "peaks":[], "lengths":[], "time":0.0, "height":0.0, "done":false}
			var track: Dictionary = observed[id]
			if rider.airborne:
				if first_air == 1000.0 and not newest.is_empty():
					expect(track.ledge == newest, "The first rider should discover the most recently opened line")
				first_air = minf(first_air, frame * DT)
				if not track.in_air:
					track.flights += 1
					track.kind = rider.air_kind
					track.time = 0.0
					track.height = 0.0
					track.in_air = true
				track.time += DT
				var p: Vector3 = rider.global_position
				track.height = maxf(track.height, p.y - terrain.surface_height(p.x, p.z))
				expect(rider.air_kind == kind or (count == 3 and rider.air_kind == Feature.PARK), "The rider must take the feature that was placed")
				expect(rider._model._powder._release_time >= rider._model._powder.EMISSION_SECONDS, "Airborne decks must stop emitting turn powder")
				expect(rider._sound.volume_db < -65, "Airborne equipment must stop making contact sound")
			elif track.in_air:
				track.in_air = false
				track.peaks.append(track.height)
				track.lengths.append(track.time)
				if track.kind == Feature.EXTREME:
					expect(track.height > 2.25 and track.time > 1.12, "The summit cliff must carry higher and longer than either park kicker")
				else:
					expect(track.height > 1.35 and track.time > 0.70, "A full-size park jump needs a visible sustained flight")
				expect(rider._landing_age < 0.05 and rider._model._powder._puffs.size() >= 10, "Landing must compress and feather powder")
			if not rider._active and not track.done:
				track.done = true
				expect(track.flights == count and track.peaks.size() == count, "Every feature needs its own takeoff and landing")
				var end: Vector2 = lift.run_end()
				expect(Vector2(rider.position.x, rider.position.z).distance_to(end) < 0.02 and arrivals.has(rider._model._variant), "Airborne lap must rejoin the base queue")
				var line: String = track.ledge
				var key := "%s:%s" % [rider.is_snowboarder, line]
				if not disciplines.has(key):
					print("Feature %d %s, %s: %s s airborne, %s m above snow, returned to queue" % [kind, line, "boarder" if rider.is_snowboarder else "skier", track.lengths, track.peaks])
					disciplines[key] = true
		if disciplines.size() == 2 * maxi(1, alternatives.size()):
			break
		if frame % 30 == 0:
			await process_frame
	expect(disciplines.size() == 2 * maxi(1, alternatives.size()) and bypass, "Skiers and boarders must use the feature while other guests still ski ordinary laps")
	expect(first_air < 28.0, "Players should be able to see the first jump shortly after placing it")
	print("First takeoff after placement: %.2f s" % first_air)

func _check() -> void:
	var terrain := Mountain.new()
	root.add_child(terrain)
	var resort := Resort.new()
	resort.save_path = ""
	root.add_child(resort)
	resort.setup(terrain)
	for tier in 3:
		if tier > 0:
			expect(resort.place_lift(terrain.station_base(tier), terrain.station_top(tier), tier), "Next lift should become available")
			if resort.lifts.size() <= tier:
				break
		var lift = resort.lifts[tier]
		lift.set_process(false)
		expect(resort.cut(tier, resort.suggestion(tier)).is_empty(), "Surveyed run should open")
		if tier == 1:
			for i in 2700:
				lift._process(DT)
				if resort.unlocked == 2:
					break
				if i % 30 == 0:
					await process_frame
			continue
		var kind := Feature.PARK if tier == 0 else Feature.EXTREME
		var alternatives: Array = []
		if tier == 2:
			expect(resort.add_feature(Feature.PARK, tier).is_empty(), "A two-jump park fits below the natural summit headwall")
			for site: Dictionary in resort.feature_sites(kind).duplicate():
				var result := resort.add_feature(kind, tier, site.ledge_id)
				expect(result.is_empty(), result)
				if result.is_empty():
					alternatives.append(site.ledge_id)
			expect(alternatives.size() >= 2, "Two or more real summit ledges should connect to the main cut")
		else:
			expect(resort.add_feature(kind,tier).is_empty(), "Open the two-jump park")
		if tier == 0 or not alternatives.is_empty():
			await check_laps(lift, terrain, kind, 2 if tier == 0 else 3, alternatives)
	resort.free()
	terrain.free()
	if errors == 0:
		print("PASS: real park and summit cliff flights, gaps in tracks, landings and returns for skiers and boarders.")
	quit(1 if errors else 0)
