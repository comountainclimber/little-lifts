extends RefCounted

const STEEL := Color("#455c71")
const RUBBER := Color("#344550")
const ENAMEL := Color("#638292")
const COPPER := Color("#cd795f")
const SNOW := Color("#deeced")
const SADDLE := Color("#307e78")
const SUMMIT := Color("#b94537")
const WINDOW := Color(0.36, 0.71, 0.77, 0.30)


static func chair(lift: Node, carrier: Node3D, tier: int) -> void:
	var double_chair := tier == 1
	var width := 1.43 if double_chair else 0.64
	var arm_offset := width * 0.46
	lift._box(carrier, Vector3(0, -0.47, 0), Vector3(0.067, 0.94, 0.075), STEEL)
	lift._box(carrier, Vector3(0, -0.91, 0), Vector3(width, 0.065, 0.09), STEEL)
	for side in [-1, 1]:
		lift._box(carrier, Vector3(arm_offset * side, -1.06, 0), Vector3(0.055, 0.33, 0.067), STEEL)
	lift._box(carrier, Vector3(0, -1.24, 0.05), Vector3(width, 0.10, 0.44), SADDLE if double_chair else ENAMEL)
	lift._box(carrier, Vector3(0, -1.08, -0.15), Vector3(width * 0.95, 0.23, 0.08), SADDLE if double_chair else ENAMEL)
	if double_chair:
		lift._box(carrier, Vector3(0, -1.18, 0.05), Vector3(0.047, 0.028, 0.41), RUBBER)
		lift._box(carrier, Vector3(0, -1.035, 0.24), Vector3(width * 0.99, 0.045, 0.05), STEEL)
		for side in [-1, 1]:
			lift._box(carrier, Vector3(side * arm_offset, -1.06, 0.12), Vector3(0.05, 0.05, 0.29), STEEL)
		# Stow the tinted hood behind the bench so both jackets are readable
		# from the valley - facing camera as they travel uphill.
		var shield: StandardMaterial3D = lift._material(WINDOW)
		shield.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shield.cull_mode = BaseMaterial3D.CULL_DISABLED
		var hood: MeshInstance3D = lift._mesh(carrier, lift._unit_box, Vector3(0, -0.93, -0.29), Vector3(width + 0.08, 0.34, 0.06), WINDOW)
		hood.rotation.x = -0.34
		lift._box(carrier, Vector3(0, -0.77, -0.35), Vector3(width + 0.10, 0.047, 0.075), SADDLE)
		for side in [-1, 1]:
			lift._box(carrier, Vector3(side * arm_offset, -0.95, -0.26), Vector3(0.060, 0.39, 0.07), SADDLE)


static func tram(lift: Node, carrier: Node3D) -> void:
	lift._rod(carrier, Vector3(0, -0.035, 0), Vector3(0, -0.76, 0), 0.094, STEEL)
	lift._box(carrier, Vector3(0, -0.085, 0), Vector3(0.21, 0.15, 0.50), RUBBER)
	lift._box(carrier, Vector3(0, -0.76, 0), Vector3(1.57, 0.13, 1.81), SUMMIT)
	lift._box(carrier, Vector3(0, -0.675, 0), Vector3(1.46, 0.058, 1.72), SNOW)
	lift._box(carrier, Vector3(0, -1.995, 0), Vector3(1.53, 0.080, 1.78), RUBBER)
	var glass: StandardMaterial3D = lift._material(WINDOW)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.32
	for signum in [-1, 1]:
		var x: float = signum * 0.73
		var z: float = signum * 0.84
		lift._box(carrier, Vector3(0, -1.86, z), Vector3(1.49, 0.25, 0.075), SUMMIT)
		lift._box(carrier, Vector3(0, -1.70, z), Vector3(1.49, 0.055, 0.06), SNOW)
		lift._box(carrier, Vector3(0, -1.26, z), Vector3(1.42, 0.80, 0.025), WINDOW)
		lift._box(carrier, Vector3(0, -1.26, z), Vector3(0.047, 0.83, 0.05), STEEL)
		for end in [-1, 1]:
			lift._box(carrier, Vector3(x, -1.39, 0.84 * end), Vector3(0.074, 1.16, 0.074), STEEL)
			lift._box(carrier, Vector3(x, -1.86, end * 0.64), Vector3(0.069, 0.25, 0.42), SUMMIT)
			lift._box(carrier, Vector3(x, -1.28, end * 0.64), Vector3(0.026, 0.86, 0.40), WINDOW)
			var door := Node3D.new()
			carrier.add_child(door)
			door.position.z = end * 0.21
			lift._box(door, Vector3(x, -1.85, 0), Vector3(0.07, 0.27, 0.41), SUMMIT)
			lift._box(door, Vector3(x, -1.27, 0), Vector3(0.026, 0.86, 0.40), WINDOW)
			lift._box(door, Vector3(x, -1.37, -end * 0.18), Vector3(0.054, 1.08, 0.044), STEEL)
			carrier.doors.append(door)


static func _island(lift: Node, frame: Node3D, height: float) -> void:
	# The aisle between the cabins meets the sill of both sliding doors.
	var floor_y := height - 1.955
	lift._box(frame, Vector3(0.0, floor_y - 0.095, 0.0), Vector3(0.91, 0.15, 2.24), STEEL)
	lift._box(frame, Vector3(0.0, floor_y - 0.033, 0.0), Vector3(0.92, 0.064, 2.25), SNOW)
	for signum: float in [-1.0, 1.0]:
		lift._box(frame, Vector3(signum * 0.42, floor_y + 0.002, 0.0), Vector3(0.045, 0.012, 1.71), COPPER)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var corners := PackedVector3Array()
		for z: float in [1.12, 2.70]:
			for x: float in [-0.44, 0.44]:
				var vertex := Vector3(x, floor_y, signum * z)
				if z > 2.0:
					var world := frame.to_global(vertex)
					vertex.y = lift._ground(Vector2(world.x, world.z)) - frame.position.y + 0.025
				corners.append(vertex)
		var order := [0, 2, 1, 1, 2, 3] if signum < 0 else [0, 1, 2, 1, 3, 2]
		for index: int in order:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(corners[index])
		var apron := MeshInstance3D.new()
		apron.mesh = surface.commit()
		apron.material_override = lift._material(SNOW)
		frame.add_child(apron)


static func support(lift: Node, frame: Node3D, height: float, terminal: bool, tier: int, radius: float) -> void:
	if tier == 2:
		if terminal:
			_island(lift, frame, height)
			for edge in [-1, 1]:
				for end in [-1, 1]:
					var corner := frame.to_global(Vector3(edge * 2.03, 0, end * 1.05))
					var foot: float = lift._ground(Vector2(corner.x, corner.z)) - frame.position.y
					lift._box(frame, Vector3(edge * 2.03, foot + 0.065, end * 1.05), Vector3(0.39, 0.14, 0.40), ENAMEL)
					lift._box(frame, Vector3(edge * 2.03, (foot + height) * 0.5, end * 1.05), Vector3(0.20, height - foot, 0.20), STEEL)
				lift._box(frame, Vector3(edge * 1.97, height, -0.02), Vector3(0.18, 0.22, 2.38), SUMMIT)
			lift._box(frame, Vector3(0, height + 0.15, 0), Vector3(4.39, 0.26, 2.54), SUMMIT)
			lift._box(frame, Vector3(0, height + 0.32, 0), Vector3(4.51, 0.11, 2.62), SNOW)
		else:
			for signum in [-1, 1]:
				var foot := Vector3(signum * 0.77, 0.08, 0)
				var head := Vector3(signum * 0.33, height - 0.18, 0.0)
				lift._box(frame, foot, Vector3(0.54, 0.32, 0.68), ENAMEL)
				lift._rod(frame, foot, head, 0.185, STEEL)
				lift._rod(frame, foot.lerp(head, 0.22), Vector3(-signum * 0.42, height * 0.72, 0), 0.08, ENAMEL)
				lift._box(frame, Vector3(signum * radius, height - 0.09, 0), Vector3(0.25, 0.23, 1.30), RUBBER)
			lift._box(frame, Vector3(0, height - 0.18, 0), Vector3(radius * 2 + 0.42, 0.23, 0.47), SUMMIT)
		return
	lift._box(frame, Vector3(0, 0.12, 0), Vector3(0.56, 0.28, 0.48), ENAMEL)
	lift._box(frame, Vector3(0, height / 2, 0), Vector3(0.24 if tier == 1 else 0.19, height, 0.24), STEEL)
	if terminal:
		lift._mesh(frame, lift._unit_cylinder, Vector3(0, height, 0), Vector3(radius * 2, 0.15, radius * 2), RUBBER)
		if tier == 0:
			lift._mesh(frame, lift._unit_cylinder, Vector3(0, height + 0.12, 0), Vector3(0.95, 0.13, 0.95), ENAMEL)
			lift._box(frame, Vector3(0, height + 0.27, 0), Vector3(0.70, 0.24, 0.86), COPPER)
			lift._box(frame, Vector3(0, height + 0.41, 0), Vector3(0.82, 0.09, 0.98), SNOW)
		else:
			lift._box(frame, Vector3(0, height + 0.20, 0), Vector3(2.10, 0.46, 2.09), SADDLE)
			lift._box(frame, Vector3(0, height + 0.46, 0), Vector3(2.21, 0.10, 2.24), SNOW)
			for side in [-1, 1]:
				lift._box(frame, Vector3(0, height + 0.19, side * 1.05), Vector3(1.60, 0.18, 0.028), ENAMEL)
	else:
		lift._box(frame, Vector3(0, height - 0.12, 0), Vector3(radius * 2 + 0.29, 0.17, 0.18), STEEL)
		for side in [-1, 1]:
			lift._box(frame, Vector3(side * radius, height - 0.061, 0), Vector3(0.17, 0.16, 0.72 if tier == 1 else 0.52), RUBBER)
		if tier == 1:
			lift._box(frame, Vector3(0, height - 0.29, 0), Vector3(0.46, 0.25, 0.29), SADDLE)
