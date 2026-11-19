extends Node3D

const GroomedTrail := preload("res://world/groomed_trail.gd")

var terrain: Node
var pieces := {}
var transforms := {}
var random := RandomNumberGenerator.new()
var smoke_mesh: QuadMesh

const FOREST_CELL := 4.0
const MAX_TREE_RADIUS := 1.55
const TREE_PARTS := ["trunk", "spruce dark", "spruce blue", "needles", "snow on needles"]
var trees: Array[Dictionary] = []
var _cells := {}
var _felled := {}
var _forest_batches := {}
var _rock_footprints := PackedVector3Array()
var _stable_tree_count := 0



func build(mountain: Node) -> void:
	terrain = mountain
	random.seed = 1841
	_define_pieces()
	_village()
	_place_rocks()
	_make_batches()
	_plant_trees()
	_rebuild_forest()


func _define_pieces() -> void:
	_register("timber", BoxMesh.new(), "#765c53")
	_register("trunk", BoxMesh.new(), "#735c4f")
	_register("plaster", BoxMesh.new(), "#c6a79a")
	_register("dark wall", BoxMesh.new(), "#795c51")
	_register("warm wall", BoxMesh.new(), "#ac7761")
	_register("roof gable", PrismMesh.new(), "#75584e")
	_register("roof eave", BoxMesh.new(), "#7c6260")
	_register("snow", BoxMesh.new(), "#e8edf5")
	_register("window", BoxMesh.new(), "#ffc878", 0.55)
	_register("chimney", BoxMesh.new(), "#9c8380")
	_register("path", BoxMesh.new(), "#bdc8da")
	_register("lantern", BoxMesh.new(), "#ffd99a", 1.25)
	var spruce := CylinderMesh.new()
	spruce.top_radius = 0.0
	spruce.bottom_radius = 0.5
	spruce.height = 1.0
	spruce.radial_segments = 7
	spruce.rings = 0
	_register("spruce dark", spruce, "#567c80")
	_register("spruce blue", spruce.duplicate(), "#668d90")
	_register("needles", spruce.duplicate(), "#74949a")
	_register("snow on needles", spruce.duplicate(), "#c4d4dc")
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 1.0
	rock.radial_segments = 6
	rock.rings = 2
	_register("rock", rock, "#929cae")


func _register(id: String, mesh: PrimitiveMesh, color: String, glow := 0.0) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 1.0
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = Color(color)
		material.emission_energy_multiplier = glow
	mesh.material = material
	pieces[id] = mesh
	transforms[id] = []


func _piece(id: String, origin: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	transforms[id].append(Transform3D(basis.scaled_local(size), origin))


func _height(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func _village() -> void:
	# A lane gives the bottom terminal an obvious relationship to the little neighborhood.
	var lane := [Vector2(-0.4, 10.4), Vector2(1.2, 12.2), Vector2(4.5, 13.3), Vector2(7.6, 14.2), Vector2(10.6, 14.0), Vector2(13.4, 15.5), Vector2(17.5, 16.2)]
	for i in range(1, lane.size()):
		var start: Vector2 = lane[i - 1] * terrain.MAP_SCALE
		var end: Vector2 = lane[i] * terrain.MAP_SCALE
		var p := Vector3(start.x, _height(start.x, start.y) + 0.025, start.y)
		var q := Vector3(end.x, _height(end.x, end.y) + 0.025, end.y)
		var axis_z := (q - p).normalized()
		var axis_x := Vector3.UP.cross(axis_z).normalized()
		_piece("path", (p + q) * 0.5, Vector3(0.64, 0.022, p.distance_to(q) + 0.035), Basis(axis_x, axis_z.cross(axis_x), axis_z))
	_cabin(Vector2(2.1, 15.0) * terrain.MAP_SCALE, -0.47, Vector3(1.31, 1.08, 1.17), "warm wall", true)
	for point: Vector2 in [Vector2(1.0,12.8) * terrain.MAP_SCALE]:
		terrain.reserve_footprint(point, 0.37)
		var foot := Vector3(point.x, _height(point.x, point.y), point.y)
		_piece("timber", foot + Vector3.UP * 0.42, Vector3(0.065, 0.88, 0.065))
		_piece("lantern", foot + Vector3.UP * 0.90, Vector3(0.15, 0.18, 0.15))
		var glow := OmniLight3D.new()
		glow.light_color = Color("#ffb067")
		glow.light_energy = 0.94
		glow.omni_range = 2.3
		glow.position = foot + Vector3.UP * 0.96
		add_child(glow)


func _cabin(point: Vector2, angle: float, proportions: Vector3, wall: String, hearth := false) -> void:
	terrain.reserve_footprint(point, Vector2(1.08 * proportions.x, 0.91 * proportions.z).length() + 0.24)
	var basis := Basis(Vector3.UP, angle)
	var anchor := Vector3(point.x, _height(point.x, point.y) - 0.10, point.y)
	var frame := Transform3D(basis.scaled_local(proportions), anchor)
	_house_piece(frame, wall, Vector3(0, 0.52, 0), Vector3(1.68, 1.11, 1.39))
	_house_piece(frame, "roof gable", Vector3(0, 1.36, 0), Vector3(1.66, 0.60, 1.39))
	for side in [-1, 1]:
		var tilt := Basis(Vector3.BACK, -side * 0.60)
		_house_piece(frame, "roof eave", Vector3(side * 0.51, 1.34, 0), Vector3(1.24, 0.12, 1.74), tilt)
		_house_piece(frame, "snow", Vector3(side * 0.50, 1.40, 0), Vector3(1.26, 0.12, 1.77), tilt)
		var win := Vector3(side * 0.53, 0.62, 0.70)
		_house_piece(frame, "timber", win, Vector3(0.36, 0.42, 0.032))
		_house_piece(frame, "window", win + Vector3.BACK * 0.02, Vector3(0.26, 0.32, 0.025))
		_house_piece(frame, "timber", win + Vector3.BACK * 0.035, Vector3(0.026, 0.32, 0.012))
		var side_win := Vector3(side * 0.85, 0.64, -0.08)
		_house_piece(frame, "window", side_win, Vector3(0.024, 0.32, 0.29))
	if hearth:
		# South-facing balcony and little gable window distinguish the two family lodges.
		_house_piece(frame, "timber", Vector3(0, 1.05, 0.83), Vector3(1.62, 0.08, 0.38))
		_house_piece(frame, "timber", Vector3(0, 1.29, 0.98), Vector3(1.62, 0.075, 0.075))
		for x in [-0.73, -0.37, 0.0, 0.37, 0.73]:
			_house_piece(frame, "timber", Vector3(x, 1.18, 0.98), Vector3(0.054, 0.24, 0.054))
		_house_piece(frame, "window", Vector3(0.0, 1.28, 0.713), Vector3(0.26, 0.27, 0.025))
		_hearth_smoke(frame * Vector3(0.32, 2.05, -0.29))
	_house_piece(frame, "timber", Vector3(0, 0.35, 0.70), Vector3(0.33, 0.70, 0.04))
	_house_piece(frame, "window", Vector3(0, 0.49, 0.731), Vector3(0.19, 0.20, 0.022))
	_house_piece(frame, "chimney", Vector3(0.32, 1.72, -0.29), Vector3(0.25, 0.57, 0.26))
	_house_piece(frame, "snow", Vector3(0.32, 2.00, -0.29), Vector3(0.30, 0.07, 0.31))


func _hearth_smoke(top: Vector3) -> void:
	if not smoke_mesh:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
		gradient.colors = PackedColorArray([Color(0.94, 0.91, 0.91, 0.44), Color(0.93, 0.90, 0.93, 0.22), Color(0.94, 0.92, 0.95, 0.0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = texture
		smoke_mesh = QuadMesh.new()
		smoke_mesh.material = material
	var smoke := CPUParticles3D.new()
	smoke.name = "Hearth smoke"
	smoke.mesh = smoke_mesh
	smoke.amount = 9
	smoke.lifetime = 2.4
	smoke.preprocess = 2.4
	smoke.direction = Vector3(0.33, 1.0, 0.0).normalized()
	smoke.spread = 9.0
	smoke.initial_velocity_min = 0.51
	smoke.initial_velocity_max = 0.70
	smoke.gravity = Vector3(0.19, 0.06, 0.0)
	smoke.scale_amount_min = 0.48
	smoke.scale_amount_max = 0.72
	var expansion := Curve.new()
	expansion.add_point(Vector2(0.0,0.40))
	expansion.add_point(Vector2(1.0,1.0))
	smoke.scale_amount_curve = expansion
	var opacity := Gradient.new()
	opacity.offsets = PackedFloat32Array([0.0,0.12,0.58,1.0])
	opacity.colors = PackedColorArray([Color(1,1,1,0),Color.WHITE,Color(1,1,1,0.75),Color(1,1,1,0)])
	smoke.color_ramp = opacity
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.position = top
	add_child(smoke)


func _house_piece(frame: Transform3D, id: String, origin: Vector3, size: Vector3, rotation_basis := Basis.IDENTITY) -> void:
	transforms[id].append(frame * Transform3D(rotation_basis.scaled_local(size), origin))


func _plant_trees() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 1837
	noise.frequency = 0.057
	var map_scale: float = terrain.MAP_SCALE
	# Reproduce the original groves in map coordinates before adding new trees.
	for i in 8000:
		_try_tree(noise, map_scale, false)
	_stable_tree_count = trees.size()
	# Keep a beautiful, cuttable grove at the center of each optional line.
	# A few companion trees surround each seed so clearing a passage reads as a choice.
	for tier in 3:
		var line: PackedVector2Array = terrain.suggested_run(tier)
		for j in 45:
			var index := random.randi_range(line.size() / 3, line.size() * 2 / 3)
			var p := line[index] + Vector2.from_angle(random.randf() * TAU) * random.randf_range(0.3, 5.5) * map_scale
			if _height(p.x, p.y) > 30.0 * map_scale or _on_home_trail(p) or not _trees_near(p, p, 0.65 * map_scale, {}, true, map_scale):
				continue
			_add_tree(p, random.randf_range(1.75, 3.30))
	var original_tree_count := trees.size()
	for i in original_tree_count:
		if _near_rock(trees[i].point, trees[i].radius):
			_felled[i] = true
	var target := roundi(original_tree_count * map_scale * map_scale * 1.38)
	random.seed = 5019
	for attempt in 42000:
		if trees.size() - _felled.size() >= target:
			break
		_try_tree(noise, 1.0, true)


func _try_tree(noise: FastNoiseLite, spacing_scale: float, infill: bool) -> void:
	var sample := Vector2(random.randf_range(-74.0, 74.0), random.randf_range(-75.0, 39.0))
	var point: Vector2 = sample * terrain.MAP_SCALE
	var h: float = _height(point.x, point.y) / terrain.MAP_SCALE
	var threshold := -0.17 + 0.14 * sin(sample.y * 0.21 + sin(sample.x * 0.15))
	if noise.get_noise_2d(sample.x, sample.y) < threshold:
		return
	var timberline := 29.5 + 2.5 * sin(sample.x * 0.12)
	if h > timberline or (h > timberline - 4.5 and random.randf() > (timberline - h) / 4.5):
		return
	var village_edge := 8.0 + 1.6 * sin(0.21 * sample.x)
	if sample.y > village_edge and sample.y < 24.0 + 2.5 * sin(0.12 * sample.x) and sample.x > -12.0 - 2.5 * sin(0.22 * sample.y) and sample.x < 23.3 + 1.3 * sin(0.18 * sample.y):
		return
	var spacing := (0.45 if infill else 0.78) * spacing_scale
	if _on_home_trail(point) or not _trees_near(point, point, spacing, {}, true, spacing_scale):
		return
	var size := random.randf_range(1.65, 3.8) * lerpf(1.0, 0.65, smoothstep(timberline - 7.0, timberline, h))
	if infill and _near_rock(point, size * 0.29 + 0.22):
		return
	_add_tree(point, size)


func _near_rock(point: Vector2, radius: float) -> bool:
	for rock in _rock_footprints:
		if point.distance_squared_to(Vector2(rock.x, rock.y)) < (rock.z + radius) * (rock.z + radius):
			return true
	return false


func _on_home_trail(p: Vector2) -> bool:
	for tier in 3:
		var b: Vector2 = terrain.station_base(tier)
		var a: Vector2 = terrain.station_top(tier)
		var near := Geometry2D.get_closest_point_to_segment(p, a, b)
		if near.distance_to(p) < 5.05 * terrain.MAP_SCALE:
			return true
	return false


func _add_tree(p: Vector2, h: float) -> void:
	var idx := trees.size()
	var radius := h * 0.29 + 0.22
	trees.append({"point": p, "origin": Vector3(p.x, terrain.surface_height(p.x, p.y) - 0.07, p.y),
		"height": h, "radius": radius, "yaw": Basis(Vector3.UP, random.randf() * TAU),
		"blue": random.randf()>0.54, "snow": random.randf()>0.22})
	var cell := Vector2i((p / FOREST_CELL).floor())
	if not _cells.has(cell):
		_cells[cell] = []
	_cells[cell].append(idx)


func forest_clear(a: Vector2, b: Vector2, margin: float) -> bool:
	return _trees_near(a, b, margin, {}, true)


func trees_along(path: PackedVector2Array, width: float) -> PackedInt32Array:
	var hits := {}
	for i in range(1, path.size()):
		_trees_near(path[i - 1], path[i], width, hits, false)
	return PackedInt32Array(hits.keys())


func _trees_near(a: Vector2, b: Vector2, margin: float, hits: Dictionary, first_hit: bool, radius_scale := 1.0) -> bool:
	var reach := Vector2.ONE * (MAX_TREE_RADIUS * radius_scale + margin)
	var low := Vector2i(((a.min(b) - reach) / FOREST_CELL).floor())
	var high := Vector2i(((a.max(b) + reach) / FOREST_CELL).floor())
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var cell := Vector2i(x, z)
			if not _cells.has(cell):
				continue
			for idx: int in _cells[cell]:
				if _felled.has(idx):
					continue
				var tree := trees[idx]
				var pos: Vector2 = tree.point
				var closest := a if a.is_equal_approx(b) else Geometry2D.get_closest_point_to_segment(pos, a, b)
				var radius: float = tree.radius * radius_scale + margin
				if pos.distance_squared_to(closest) <= radius * radius:
					if first_hit:
						return false
					hits[idx] = true
	return true


func set_cleared(ids: PackedInt32Array, cleared: bool) -> void:
	for id in ids:
		if cleared:
			_felled[id] = true
		else:
			_felled.erase(id)
	_rebuild_forest()


func clear_legacy_corridor(line: PackedVector2Array, width: float) -> void:
	var removed := PackedInt32Array()
	for idx in trees_along(line, width):
		# Survey groves follow the new route geometry; they can also cross old lifts.
		if idx >= _stable_tree_count:
			removed.append(idx)
	if not removed.is_empty():
		set_cleared(removed, true)


func _rebuild_forest() -> void:
	for part in TREE_PARTS:
		transforms[part].clear()
	for i in trees.size():
		if _felled.has(i):
			continue
		var tree := trees[i]
		var h: float = tree.height
		var p: Vector3 = tree.origin
		var yaw: Basis = tree.yaw
		_piece("trunk", p + Vector3.UP * h * 0.16, Vector3(0.074, 0.33, 0.074) * h, yaw)
		_piece("spruce blue" if tree.blue else "spruce dark", p + Vector3.UP * h * 0.42, Vector3(0.62, 0.62, 0.62) * h, yaw)
		_piece("needles", p + Vector3.UP * h * 0.68, Vector3(0.47, 0.65, 0.47) * h, yaw)
		if tree.snow:
			_piece("snow on needles", p + Vector3.UP * h * 0.83, Vector3(0.235, 0.36, 0.235) * h, yaw)
	for key in TREE_PARTS:
		if not _forest_batches.has(key):
			var node := MultiMeshInstance3D.new()
			node.name = "Forest " + key
			node.multimesh = MultiMesh.new()
			node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			node.multimesh.mesh = pieces[key]
			_forest_batches[key] = node
			add_child(node)
		var batch: MultiMesh = _forest_batches[key].multimesh
		batch.instance_count = transforms[key].size()
		for i in batch.instance_count:
			batch.set_instance_transform(i, transforms[key][i])


func trail_sign(points: PackedVector2Array, width: float) -> Node3D:
	var signs := Node3D.new()
	signs.name = "Timber trail"
	add_child(signs)
	var piste := GroomedTrail.new()
	piste.name = "Groomed snow"
	signs.add_child(piste)
	piste.build(terrain, points, width)
	var last := points[0]
	var distance := 0.0
	var next_sign := 1.7
	for i in range(1, points.size()):
		var span := points[i] - last
		if span.length_squared() <= 0.0001:
			continue
		var finish := distance + span.length()
		var side := span.normalized().orthogonal()
		while next_sign <= finish:
			var at := last.lerp(points[i], (next_sign - distance) / span.length()) + side * (width - 0.24)
			var foot := Vector3(at.x, terrain.surface_height(at.x, at.y), at.y)
			var yaw := Basis(Vector3.UP, atan2(side.x, side.y) - 0.55)
			_sign_piece(signs,"timber", foot + Vector3.UP * 0.43, Vector3(0.085, 0.95, 0.085), yaw)
			_sign_piece(signs,"spruce blue", foot + Vector3.UP * 0.78, Vector3(0.15, 0.20, 0.15), yaw)
			if next_sign < 2.0:
				_sign_piece(signs,"dark wall", foot + Vector3.UP * 0.90, Vector3(0.72, 0.28, 0.10), yaw)
				_sign_piece(signs,"snow", foot + Vector3.UP * 1.055, Vector3(0.75, 0.05, 0.13), yaw)
			next_sign += 9.5
		distance = finish
		last = points[i]
	return signs


func _sign_piece(host: Node3D, key: String, pos: Vector3, size: Vector3, yaw: Basis) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = pieces[key]
	mesh.transform = Transform3D(yaw.scaled_local(size), pos)
	host.add_child(mesh)


func _place_rocks() -> void:
	# Granite breaks through along the high divide and in ribs outside the ski lines.
	for cl: Vector3 in [Vector3(-34, -69, 11), Vector3(-10, -75, 12), Vector3(-42, -49, 9), Vector3(-32, -57, 6), Vector3(-1, -64, 10), Vector3(-38, -47, 7),
			Vector3(29, -47, 8), Vector3(39, -28, 7), Vector3(-34, -11, 5), Vector3(28, -4, 3)]:
		for i in int(cl.z):
			var p := Vector2(cl.x + random.randf_range(-4.4, 4.4), cl.y + random.randf_range(-2.0, 2.0))
			var width := random.randf_range(0.6, 3.6) if p.y < -42 else random.randf_range(0.6, 1.8)
			p *= terrain.MAP_SCALE
			var yaw := Basis(Vector3.UP, random.randf() * TAU)
			_rock_footprints.append(Vector3(p.x, p.y, width * 0.55))
			terrain.reserve_footprint(p, width * 0.55)
			var foot := Vector3(p.x, terrain.surface_height(p.x, p.y), p.y)
			_piece("rock", foot, Vector3(width, width * 0.55, width * 0.69), yaw)


func _make_batches() -> void:
	for id in transforms:
		var instances: Array = transforms[id]
		if instances.is_empty():
			continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = pieces[id]
		batch.instance_count = instances.size()
		for i in instances.size():
			batch.set_instance_transform(i, instances[i])
		var node := MultiMeshInstance3D.new()
		node.name = str(id).capitalize()
		node.multimesh = batch
		add_child(node)
