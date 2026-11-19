extends MeshInstance3D

const SHADER := preload("res://world/groomed_trail.gdshader")
const COLUMNS := 9


func build(terrain: Node, path: PackedVector2Array, half_width: float) -> void:
	# Follow the same tessellated snow as the rides, including across the width
	# of a bank. Low mesh density would cut under the surface on a convex slope.
	var centers := PackedVector2Array([path[0]])
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		if a.distance_squared_to(b) < 0.0001:
			continue
		var count := maxi(1, ceili(a.distance_to(b) / 0.72))
		for j in range(1, count + 1):
			centers.append(a.lerp(b, float(j) / count))
	if centers.size() < 2:
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var distance := 0.0
	for i in centers.size():
		if i > 0:
			distance += centers[i].distance_to(centers[i - 1])
		var tangent := centers[mini(i + 1, centers.size() - 1)] - centers[maxi(0, i - 1)]
		var side := tangent.normalized().orthogonal()
		for j in COLUMNS:
			var across := lerpf(-1, 1, float(j) / (COLUMNS - 1))
			var p := centers[i] + side * half_width * across
			var y: float = terrain.surface_height(p.x, p.y)
			var nx: float = terrain.height_at(p.x - 0.3, p.y) - terrain.height_at(p.x + 0.3, p.y)
			var nz: float = terrain.height_at(p.x, p.y - 0.3) - terrain.height_at(p.x, p.y + 0.3)
			var normal := Vector3(nx, 0.6, nz).normalized()
			vertices.append(Vector3(p.x, y + 0.014, p.y))
			normals.append(normal)
			colors.append(terrain.snow_pigment(p.x, p.y, y, normal))
			uvs.append(Vector2(distance, across))
			if i > 0 and j > 0:
				var b := i * COLUMNS + j
				var a := b - COLUMNS
				indices.append_array(PackedInt32Array([a - 1, a, b - 1, a, b, b - 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var surface := ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = surface
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = -3
	mat.set_shader_parameter("run_length", distance)
	material_override = mat
