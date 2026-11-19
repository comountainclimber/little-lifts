extends MeshInstance3D

# One ground-hugging strip covers both skis or the single board. The loaded
# outside edge pushes a bank of powder aside at the apex of each turn.
const FeatureLine := preload("res://skiing/feature_line.gd")
const GROOVE := preload("res://skiing/groove.gdshader")
const PROFILE_COLUMNS := 17
const MAX_OLD_TRAILS := 14
const SNOW_CLEARANCE := 0.013
const POWDER_RELIEF_SCALE := 0.84

static var _strip_indices := PackedInt32Array()
var is_snowboard_track := false
var _ink: ShaderMaterial
var _age := 0.0
var _complete := false


const ROWS_PER_CHUNK := 24
var points: PackedVector3Array
var distances: PackedFloat32Array
var terrain: Node
var snowboard: bool
var toe_side: float
var passes: Array[FeatureLine.Pass]
var speeds := PackedFloat32Array()
var pressures := PackedFloat32Array()
var last_row := -1
var _surfaces := []

func build(path: PackedVector3Array, lengths: PackedFloat32Array, mountain: Node, board := false, edge := 1.0, features: Array[FeatureLine.Pass] = [], stream := false) -> void:
	points = path
	distances = lengths
	terrain = mountain
	snowboard = board
	is_snowboard_track = board
	toe_side = edge
	passes = features
	speeds.resize(points.size())
	pressures.resize(points.size())
	var speed_sq := 1.2 * 1.2
	var pressure := 0.0
	for i in points.size():
		var prev := maxi(0, i - 1)
		var following := mini(i + 1, points.size() - 1)
		var direction := points[following] - points[prev]
		var side := Vector3(-direction.z, 0.0, direction.x).normalized()
		var ds := distances[i] - distances[prev]
		# Estimate speed from local slope energy for this baked cross section.
		# The motion simulation remains independent of its impression in the snow.
		var drop := points[prev].y - points[i].y
		speed_sq = clampf(speed_sq + 17.0 * drop - 2.0 * (0.24 + 0.09 * speed_sq) * ds, 1.56, 40.96)
		var speed := minf(sqrt(speed_sq), lerpf(1.25, 6.4, smoothstep(0.0, 3.5, distances[-1] - distances[i])))
		var look_back := maxi(0, i - 2)
		var look_ahead := mini(i + 2, points.size() - 1)
		var entry := (points[i] - points[look_back]).normalized()
		var exit := (points[look_ahead] - points[i]).normalized()
		var curvature := (exit - entry).dot(side) / maxf((distances[look_ahead] - distances[look_back]) * 0.5, 0.01)
		if i == 0 or following == i:
			curvature = 0.0
		pressure = lerpf(pressure, tanh(curvature * speed * speed / 8.4), 1.0 - exp(-ds * 4.5))

		speeds[i] = speed
		pressures[i] = pressure
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ink = ShaderMaterial.new()
	_ink.shader = GROOVE
	material_override = _ink
	set_process(false)
	if stream:
		_surfaces.resize(Mesh.ARRAY_MAX)
		_append_strip(mini(ROWS_PER_CHUNK, points.size()-1))
	else:
		mesh = _make_mesh(_strip_arrays(0, points.size()-1))
		last_row = points.size()-1

func _strip_arrays(first: int, last: int) -> Array:
	# One extra snow sample at either end gives neighboring strips the exact
	# same normals along their shared boundary.
	var low := maxi(0,first-1)
	var high := mini(points.size()-1,last+1)
	var origin_phase := points[0].x * 0.38 + points[0].z * 0.72
	var vertices := PackedVector3Array()
	var physical_profile := PackedVector3Array()
	var colors := PackedColorArray()
	var coords := PackedVector2Array()
	var relief_and_load := PackedVector2Array()
	for i in range(low,high+1):
		var speed := speeds[i]
		var pressure := pressures[i]
		var direction := points[mini(i+1,points.size()-1)] - points[maxi(0,i-1)]
		var side := Vector3(-direction.z,0,direction.x).normalized()
		var raised_snow := 0.0
		if not passes.is_empty():
			raised_snow = maxf(0.0,points[i].y-terrain.surface_height(points[i].x,points[i].z))
		var flow := smoothstep(1.25, 5.6, speed)
		var heel := maxf(0.0, -pressure * toe_side) if snowboard else 0.0
		var d := distances[i]
		# A loaded edge throws a few scallops, separated by untouched snow.
		# Vary their spacing, volume and distance from the line along each turn.
		var throw_phase := d * 4.75 + origin_phase + 0.72 * sin(d * 1.83 + origin_phase)
		var pocket_size := 0.78 + 0.22 * sin(d * 1.48 + origin_phase * 1.71)
		var loaded := smoothstep(0.16, 0.77, absf(pressure)) * (0.45 + 0.55 * flow)
		var pulse := smoothstep(0.12, 0.89, 0.5 + 0.5 * cos(throw_phase))
		var pocket := loaded * pulse * pocket_size
		var half_width := (0.46 if snowboard else 0.37) + 0.043 * flow
		var base_depth := (0.052 if snowboard else 0.043) + flow * 0.019
		var pile_center := 0.52 + 0.17 * pocket + 0.032 * sin(d * 2.0 + origin_phase)
		var pile_width := 0.24 + 0.054 * pocket
		var nx: float = terrain.surface_height(points[i].x - 0.3, points[i].z) - terrain.surface_height(points[i].x + 0.3, points[i].z)
		var nz: float = terrain.surface_height(points[i].x, points[i].z - 0.3) - terrain.surface_height(points[i].x, points[i].z + 0.3)
		var normal := Vector3(nx, 0.6, nz).normalized()
		var pigment: Color = terrain.snow_pigment(points[i].x, points[i].z, points[i].y, normal)
		for column in PROFILE_COLUMNS:
			var u := -1.0 + 2.0 * column / (PROFILE_COLUMNS - 1.0)
			var r := absf(u)
			var outward := maxf(0.0, -signf(u) * pressure)
			var loose_edge := smoothstep(0.18, 0.84, outward)
			var lip_width := (0.08 + 0.13 * heel) * outward + 0.52 * loose_edge * pulse * pocket_size
			# Only the outside of the swath fans out. Its floor retains the
			# natural width of the rider's equipment through each deposit.
			var across := u * half_width + signf(u) * lip_width * smoothstep(0.19, 0.98, r)
			# The center is pressed below undisturbed snow. The displaced side
			# is a real low mound, with the broadest deposits outside loaded turns.
			var bowl_x := (u + 0.045 * pressure) / 0.48
			var bowl := exp(-bowl_x * bowl_x)
			var depth := base_depth * (0.9 + 0.22 * absf(pressure)) * bowl
			if not snowboard:
				# Two overlapping hollows remain visible in a shallow traverse.
				# As the edges load, both skis settle into one ploughed trough.
				var left_x := (across + 0.105) / 0.083
				var right_x := (across - 0.105) / 0.083
				var left := exp(-left_x * left_x)
				var right := exp(-right_x * right_x)
				depth += 0.022 * (1.0 - 0.82 * absf(pressure)) * (left + right)
			var pile_height := 0.003 + 0.012 * outward + (0.18 + 0.035 * heel) * loose_edge * pocket
			var pile_x := (r - pile_center) / pile_width
			var mound := pile_height * exp(-pile_x * pile_x)
			var relief := (mound - depth) * POWDER_RELIEF_SCALE
			var point := points[i] + side * across
			var snow_y: float = terrain.surface_height(point.x, point.z) + raised_snow
			point.y = snow_y + SNOW_CLEARANCE + maxf(0.0, relief)
			vertices.append(point)
			# A mesh cannot cut a hole in the underlying snow. Preserve its
			# recessed normals while keeping its lowest fragments on the surface.
			physical_profile.append(Vector3(point.x, snow_y + relief, point.z))
			colors.append(pigment)
			coords.append(Vector2(d, u))
			relief_and_load.append(Vector2(relief, pressure))

	var normals := PackedVector3Array()
	for i in range(first,last+1):
		var row := (i-low) * PROFILE_COLUMNS
		var back_row := (maxi(low,i-1)-low) * PROFILE_COLUMNS
		var next_row := (mini(high,i+1)-low) * PROFILE_COLUMNS
		for j in PROFILE_COLUMNS:
			var across := physical_profile[row + mini(j+1,PROFILE_COLUMNS-1)] - physical_profile[row + maxi(0,j-1)]
			var along := physical_profile[next_row+j] - physical_profile[back_row+j]
			var n := across.cross(along).normalized()
			normals.append(n if n.y > 0 else -n)
	var start_vertex := (first-low)*PROFILE_COLUMNS
	var end_vertex := (last-low+1)*PROFILE_COLUMNS
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices.slice(start_vertex,end_vertex)
	result[Mesh.ARRAY_NORMAL] = normals
	result[Mesh.ARRAY_COLOR] = colors.slice(start_vertex,end_vertex)
	result[Mesh.ARRAY_TEX_UV] = coords.slice(start_vertex,end_vertex)
	result[Mesh.ARRAY_TEX_UV2] = relief_and_load.slice(start_vertex,end_vertex)
	result[Mesh.ARRAY_INDEX] = _ground_indices(first,last)
	return result

func _ground_indices(first: int,last: int) -> PackedInt32Array:
	var indices := _indices_for(last-first+1)
	if passes.is_empty():
		return indices
	var on_snow := PackedInt32Array()
	var from := first
	var per_row := (PROFILE_COLUMNS-1)*6
	for feature in passes:
		if feature.landing_row <= first or feature.lip_row >= last:
			continue
		var lip := maxi(first,feature.lip_row)
		on_snow.append_array(indices.slice((from-first)*per_row,(lip-first)*per_row))
		from = mini(last, feature.landing_row)
	on_snow.append_array(indices.slice((from-first)*per_row))
	return on_snow

func _make_mesh(arrays: Array) -> ArrayMesh:
	var ribbon := ArrayMesh.new()
	if not arrays[Mesh.ARRAY_INDEX].is_empty():
		ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return ribbon

func _append_strip(last: int) -> void:
	var first := maxi(0,last_row)
	var arrays := _strip_arrays(first,last)
	var ribbon := _make_mesh(arrays)
	for slot: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		if first == 0:
			_surfaces[slot] = arrays[slot]
		else:
			_surfaces[slot].append_array(arrays[slot].slice(PROFILE_COLUMNS))
	if first == 0:
		mesh = ribbon
	elif ribbon.get_surface_count() > 0:
		var strip := MeshInstance3D.new()
		strip.mesh = ribbon
		strip.material_override = _ink
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)
	last_row = last

func finish_baking() -> void:
	if _surfaces.is_empty():
		return
	while last_row < points.size()-1:
		_append_strip(mini(last_row+ROWS_PER_CHUNK,points.size()-1))
	_surfaces[Mesh.ARRAY_INDEX] = _ground_indices(0,points.size()-1)
	mesh = _make_mesh(_surfaces)
	for child in get_children():
		child.hide()
		child.queue_free()
	_surfaces.clear()


static func _indices_for(rows: int) -> PackedInt32Array:
	# Every route shares the same cross-section topology. Extend this cache
	# only when a new descent has more samples than the longest previous run.
	var row_indices := (PROFILE_COLUMNS - 1) * 6
	var count := (rows - 1) * row_indices
	if count > _strip_indices.size():
		var first_row := _strip_indices.size() / row_indices
		_strip_indices.resize(count)
		for row in range(first_row, rows - 1):
			for j in PROFILE_COLUMNS - 1:
				var a := row * PROFILE_COLUMNS + j
				var b := a + PROFILE_COLUMNS
				var k := row * row_indices + j * 6
				_strip_indices[k] = a
				_strip_indices[k+1] = b
				_strip_indices[k+2] = a+1
				_strip_indices[k+3] = a+1
				_strip_indices[k+4] = b
				_strip_indices[k+5] = b+1
	return _strip_indices.slice(0, count)


func reveal(travelled: float) -> void:
	while last_row < points.size()-1 and distances[last_row] < travelled + 1.5:
		_append_strip(mini(last_row+ROWS_PER_CHUNK,points.size()-1))
	_ink.set_shader_parameter("travelled", travelled)


func finish() -> void:
	finish_baking()
	_complete = true
	set_process(true)
	var old: Array[Node] = []
	for child in get_parent().get_children():
		if child.get_script() == get_script() and child._complete and not child.is_queued_for_deletion():
			old.append(child)
	while old.size() > MAX_OLD_TRAILS:
		old.pop_front().queue_free()


func _process(delta: float) -> void:
	_age += delta
	_ink.set_shader_parameter("strength", 1.0 - smoothstep(5.0, 33.0, _age))
	if _age >= 33.0:
		queue_free()
