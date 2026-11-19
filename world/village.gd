extends Node3D

const KINDS := ["Waffle hut", "Ski school", "Day lodge"]
const FOOTPRINT_RADII := [1.8, 1.95, 2.4]
const MAP_SCALE := preload("res://world/mountain.gd").MAP_SCALE
const PLOTS := [Vector2(6.2, 12.0) * MAP_SCALE, Vector2(9.2, 17.3) * MAP_SCALE,
	Vector2(14.1, 12.5) * MAP_SCALE, Vector2(18.6, 17.5) * MAP_SCALE, Vector2(3.0, 19.8) * MAP_SCALE]
const WOOD := Color("#79594b")
const CREAM := Color("#efd3a4")
const SNOW := Color("#f1eef1")
const SLATE := Color("#435c65")
var terrain: Node
var occupied := {}
var _details := 0
var _materials := {}
var _box := BoxMesh.new()
var _gable := PrismMesh.new()
var _round := CylinderMesh.new()

func setup(world: Node) -> void:
	terrain = world
	_round.top_radius = 0.5
	_round.bottom_radius = 0.5
	_round.radial_segments = 12
	_round.height = 1.0

func nearest_plot(point: Vector2) -> int:
	var closest := -1
	var distance := 3.4 * MAP_SCALE
	for i in PLOTS.size():
		var d: float = PLOTS[i].distance_to(point)
		if not occupied.has(i) and d < distance:
			distance = d
			closest = i
	return closest

func _frame(point: Vector2, yaw: float, label: String) -> Node3D:
	var frame := Node3D.new()
	frame.name = label
	add_child(frame)
	frame.position = Vector3(point.x, terrain.surface_height(point.x, point.y), point.y)
	frame.rotation.y = yaw
	return frame

func _part(parent: Node3D, pos: Vector3, size: Vector3, color: Color, shape: Mesh = null) -> MeshInstance3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.89
		if color == CREAM:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 0.4
		_materials[color] = material
	var piece := MeshInstance3D.new()
	piece.mesh = _box if shape == null else shape
	piece.material_override = _materials[color]
	parent.add_child(piece)
	piece.position = pos
	piece.scale = size
	return piece

func _house(frame: Node3D, at: Vector3, w: float, h: float, d: float, wall: Color, roof: Color) -> void:
	_part(frame, at + Vector3.UP * h * 0.5, Vector3(w, h, d), wall)
	_part(frame, at + Vector3.UP * (h + 0.25), Vector3(w + 0.2, 0.55, d + 0.24), roof, _gable)
	_part(frame, at + Vector3.UP * (h + 0.33), Vector3(w + 0.24, 0.47, d + 0.28), SNOW, _gable)
	for fraction in [-0.32, 0.32]:
		_part(frame, at + Vector3(w * fraction, h * 0.59, d * 0.5 + 0.025), Vector3(w * 0.18, h * 0.33, 0.05), CREAM)
	_part(frame, at + Vector3(0, h * 0.32, d * 0.5 + 0.04), Vector3(0.35, h * 0.64, 0.07), WOOD)

func _bench(frame: Node3D, pos: Vector3) -> void:
	_part(frame, pos + Vector3.UP * 0.23, Vector3(0.88, 0.09, 0.30), WOOD)
	for x in [-0.30, 0.30]:
		_part(frame, pos + Vector3(x, 0.11, 0.0), Vector3(0.09, 0.22, 0.21), SLATE)

func _rack(frame: Node3D, pos: Vector3, count: int) -> void:
	_part(frame, pos + Vector3.UP * 0.43, Vector3(1.25, 0.08, 0.10), WOOD)
	for x in [-0.53, 0.53]:
		_part(frame, pos + Vector3(x, 0.23, 0), Vector3(0.07, 0.46, 0.11), WOOD)
	for i in count:
		for dx in [-0.035, 0.035]:
			var ski := _part(frame, pos + Vector3(-0.42 + i * 0.24 + dx, 0.42, 0.05), Vector3(0.055, 0.80, 0.055), [Color("#c97c57"), SLATE, Color("#68918b")][i % 3])
			ski.rotation.x = 0.16
			ski.rotation.z = -0.12 + 0.06 * i

func build_at(kind: int, plot: int) -> bool:
	if kind < 0 or kind >= KINDS.size() or plot < 0 or plot >= PLOTS.size() or occupied.has(plot):
		return false
	var p: Vector2 = PLOTS[plot]
	var frame := _frame(p, [-0.26, 0.22, -0.12, 0.38, -0.42][plot], KINDS[kind])
	occupied[plot] = kind
	terrain.reserve_footprint(p, FOOTPRINT_RADII[kind])
	match kind:
		0:
			_house(frame, Vector3.ZERO, 1.65, 1.05, 1.30, Color("#b97854"), WOOD)
			for i in 7:
				var cloth := _part(frame, Vector3((i - 3) * 0.23, 0.89, 0.93), Vector3(0.23, 0.08, 0.55), CREAM if i % 2 == 0 else Color("#ce8751"))
				cloth.rotation.x = 0.19
			_part(frame, Vector3(0, 0.53, 0.82), Vector3(1.46, 0.09, 0.33), WOOD)
			_bench(frame, Vector3(0.30, 0, 1.46))
		1:
			_house(frame, Vector3.ZERO, 2.22, 1.22, 1.38, Color("#799693"), SLATE)
			_rack(frame, Vector3(-0.50, 0, 1.08), 4)
			for i in 3:
				_part(frame, Vector3(0.65 + i * 0.36, 0.54, 1.02), Vector3(0.04, 1.08, 0.04), WOOD)
				_part(frame, Vector3(0.75 + i * 0.36, 0.95, 1.02), Vector3(0.23, 0.16, 0.02), [Color("#e5aa55"), Color("#cd735c"), Color("#579595")][i])
		2:
			_house(frame, Vector3(-0.28, 0, 0), 2.74, 1.63, 1.78, WOOD, SLATE)
			_house(frame, Vector3(1.19, 0, -0.04), 1.12, 1.14, 1.35, Color("#a8846d"), SLATE)
			_part(frame, Vector3(-1.13, 1.57, -0.24), Vector3(0.36, 1.40, 0.35), Color("#8a8481"))
			_part(frame, Vector3(0, 0.08, 1.26), Vector3(3.2, 0.16, 0.89), WOOD)
			_bench(frame, Vector3(-0.79, 0.16, 1.30))
			_bench(frame, Vector3(0.65, 0.16, 1.30))
			_rack(frame, Vector3(1.55, 0, 0.85), 3)
	return true

func grow(stage: int) -> void:
	while _details < stage:
		_details += 1
		var p := Vector2(3.6 + 4.0 * (_details - 1), 14.2 + 0.3 * _details) * MAP_SCALE
		var corner := _frame(p, -0.15, "Village arrivals")
		_bench(corner, Vector3.ZERO)
		_rack(corner, Vector3(1.25, 0, 0.25), mini(_details + 1, 4))
		_part(corner, Vector3(-0.62, 0.55, 0.3), Vector3(0.09, 1.1, 0.09), WOOD)
		_part(corner, Vector3(-0.62, 1.16, 0.3), Vector3(0.15, 0.21, 0.15), CREAM)
