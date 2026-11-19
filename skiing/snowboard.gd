extends Node3D

# The board's nose is -Z. Build one closed deck from its waist, wider
# shoulders and curved tips. The colored topsheet follows the same surface.
const SECTIONS := [
	Vector3(-0.579, 0.016, 0.105), Vector3(-0.570, 0.070, 0.097),
	Vector3(-0.544, 0.124, 0.078), Vector3(-0.494, 0.159, 0.049),
	Vector3(-0.433, 0.172, 0.023), Vector3(-0.410, 0.173, 0.019),
	Vector3(-0.329, 0.166, 0.013), Vector3(-0.203, 0.150, 0.015),
	Vector3(0.000, 0.135, 0.020), Vector3(0.201, 0.148, 0.015),
	Vector3(0.346, 0.164, 0.016), Vector3(0.407, 0.169, 0.023),
	Vector3(0.427, 0.167, 0.029), Vector3(0.500, 0.145, 0.057),
	Vector3(0.539, 0.104, 0.078), Vector3(0.557, 0.048, 0.089),
	Vector3(0.561, 0.012, 0.091)
]

var bindings: Array[Node3D] = []
var boots: Array[Node3D] = []
var _stance: float
static var _mesh_by_stance := {}


func build(rig: Node3D, stance: float) -> void:
	_stance = stance
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	if not _mesh_by_stance.has(stance):
		_mesh_by_stance[stance] = _deck_mesh(stance)
	deck.mesh = _mesh_by_stance[stance]
	add_child(deck)
	for i in 2:
		var binding := Node3D.new()
		binding.name = "FrontBinding" if i == 0 else "RearBinding"
		add_child(binding)
		binding.position = Vector3(0.0, 0.037, -0.196 if i == 0 else 0.196)
		binding.rotation.y = -stance * deg_to_rad(71.0 if i == 0 else 101.0)
		bindings.append(binding)
		rig._piece(binding, rig._box, Vector3(0, 0.007, 0), Vector3(0.129, 0.025, 0.241), Color("#40525c"))
		var highback: MeshInstance3D = rig._piece(binding, rig._box, Vector3(0, 0.072, 0.097), Vector3(0.124, 0.13, 0.028), Color("#465766"))
		highback.rotation.x = 0.09

		# Boots live in rig space so the rear one can lift clear of its binding on the chair.
		var boot := Node3D.new()
		rig.add_child(boot)
		boots.append(boot)
		rig._piece(boot, rig._box, Vector3(0, 0.039, -0.012), Vector3(0.103, 0.069, 0.197), Color("#243448"))
		rig._piece(boot, rig._orb, Vector3(0, 0.088, 0.025), Vector3(0.118, 0.144, 0.129), Color("#384755"))
		rig._piece(boot, rig._box, Vector3(0, 0.08, -0.047), Vector3(0.116, 0.028, 0.047), Color("#bac9c6"))


func tilt(bank: float, sitting: float) -> void:
	var edge := -bank * 1.07
	var roll := Basis(Vector3.BACK, edge)
	var edge_pivot := Vector3(-signf(edge) * 0.145, 0, 0)
	var grounded := Transform3D(roll, edge_pivot - roll * edge_pivot)
	# Passengers carry the board on the lead foot. Its tail hangs down and
	# across the open chair while the free boot draws back under the other knee.
	var hanging_basis := Basis(Vector3.UP, 0.98 * _stance) * Basis(Vector3.RIGHT, 0.39)
	var lead_target := Vector3(-0.125 * _stance, -0.045, -0.040)
	var hanging := Transform3D(hanging_basis, lead_target - hanging_basis * bindings[0].position)
	transform = grounded.interpolate_with(hanging, sitting)
	for i in 2:
		var fixed := transform * bindings[i].transform
		if i == 1 and sitting > 0:
			var free := Transform3D(Basis(Vector3.UP, -0.12 * _stance), Vector3(0.135 * _stance, -0.012, 0.015))
			fixed = fixed.interpolate_with(free, smoothstep(0.10, 0.87, sitting))
		boots[i].transform = fixed


func ankle(i: int) -> Vector3:
	return boots[i].transform * Vector3(0, 0.123, 0.028)


static func _deck_mesh(stance: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	paint.roughness = 0.74
	surface.set_material(paint)
	var pigment := Color("#157b82") if stance > 0.0 else Color("#624b7a")
	var accent := Color("#ffb85b") if stance > 0.0 else Color("#8ce3cd")
	var edge := Color("#263c4a")
	var thickness := Vector3.UP * 0.027
	for i in range(SECTIONS.size() - 1):
		var near: Vector3 = SECTIONS[i]
		var far: Vector3 = SECTIONS[i + 1]
		var a := Vector3(-near.y, near.z + 0.012, near.x)
		var b := Vector3(near.y, a.y, near.x)
		var c := Vector3(far.y, far.z + 0.012, far.x)
		var d := Vector3(-far.y, c.y, far.x)
		var panel := pigment
		if near.x < -0.433 or near.x >= 0.427:
			panel = accent
		elif near.x < -0.410 or (near.x >= 0.407 and near.x < 0.427):
			panel = Color("#f6ead5")
		_quad(surface, a, b, c, d, panel)
		_quad(surface, d - thickness, c - thickness, b - thickness, a - thickness, pigment.darkened(0.35))
		_quad(surface, a - thickness, a, d, d - thickness, edge)
		_quad(surface, c - thickness, c, b, b - thickness, edge)
		if i == 0:
			_quad(surface, b - thickness, b, a, a - thickness, edge)
		if i == SECTIONS.size() - 2:
			_quad(surface, d - thickness, d, c, c - thickness, edge)
	return surface.commit()


static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal := (d - a).cross(b - a).normalized()
	for vertex in [a, b, c, a, c, d]:
		surface.set_color(color)
		surface.set_normal(normal)
		surface.add_vertex(vertex)
