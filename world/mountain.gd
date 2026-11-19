extends Node3D

const Weather = preload("res://world/weather.gd")
const Scenery = preload("scenery.gd")
const SNOW := Color("#edf1fb")
const CREST_SNOW := Color("#ffe9d7")
const SHADOW_SNOW := Color("#a7bbdc")
const MAP_SCALE := 1.5
const VIEW_CENTER := Vector3(0.0, 28.0, -40.0) * MAP_SCALE
const VIEW_DIRECTION := Vector3(0.27, 0.225, 1.0)
const SNOW_MIN := Vector2(-86.0, -124.0) * MAP_SCALE
const SNOW_MAX := Vector2(86.0, 46.0) * MAP_SCALE
const SNOW_COLUMNS := 191
const SNOW_ROWS := 145

var base_point := Vector2(0.0, 9.0) * MAP_SCALE
var left_summit := Vector2(-13.0, -7.5) * MAP_SCALE
var right_summit := Vector2(14.0, -10.5) * MAP_SCALE
const VIEW_DISTANCE := 780.0
var camera_rig := Node3D.new()
var camera: Camera3D
var map_inset := 0.0
var backcountry := preload("res://world/backcountry.gd").new()
var summit_ledges := preload("res://world/summit_ledges.gd").new()
var weather := Weather.new()
var environment := Environment.new()
var sun := DirectionalLight3D.new()
var sky_material := ShaderMaterial.new()
var _snow_samples := PackedFloat32Array()
const CUT_HALF_WIDTH := 2.5
const BASES := [Vector2(0, 9), Vector2(7, 8), Vector2(-16, 12)]
const TOPS := [Vector2(-13, -7.5), Vector2(18, -33), Vector2(-24, -68.5)]
var scenery: Node3D
var _last_cleared := PackedInt32Array()
var _last_sign: Node3D
var _footprint_cells := {}
const CELL_SIZE := 3.0


func _ready() -> void:
	_set_light()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 32.0
	camera.near = 0.2
	camera.far = 2400.0
	add_child(camera_rig)
	camera_rig.add_child(camera)
	camera_rig.position = VIEW_CENTER + VIEW_DIRECTION.normalized() * VIEW_DISTANCE
	camera_rig.look_at(VIEW_CENTER, Vector3.UP)
	camera.current = true
	set_camera_span(overview_size())

	_build_sky()
	_build_snow()
	scenery = Scenery.new()
	add_child(scenery)
	scenery.build(self)
	add_child(summit_ledges)
	summit_ledges.build(self)
	backcountry.plant_forests(self)
	add_child(weather)
	weather.setup(self)


func overview_size() -> float:
	var size := get_viewport().get_visible_rect().size
	var aspect := maxf(0.25,(size.x-map_inset)/maxf(1.0,size.y))
	return MAP_SCALE * maxf(135.0,162.0/aspect)

func camera_distance(span: float) -> float:
	return span/(2.0*tan(deg_to_rad(camera.fov)*0.5))

func set_camera_span(span: float) -> void:
	camera.size = span
	var height := maxf(1.0,get_viewport().get_visible_rect().size.y)
	camera.position = Vector3(-0.5*map_inset*span/height,0.0,camera_distance(span)-VIEW_DISTANCE)

func station_base(tier: int) -> Vector2:
	return BASES[clampi(tier, 0, BASES.size() - 1)] * MAP_SCALE


func station_top(tier: int) -> Vector2:
	return TOPS[clampi(tier, 0, TOPS.size() - 1)] * MAP_SCALE


func height_at(x: float, z: float) -> float:
	x /= MAP_SCALE
	z /= MAP_SCALE
	var weight := backcountry.blend_at(x,z)
	if weight >= 1.0:
		return MAP_SCALE * backcountry.elevation(x,z)
	# A continuous fall line connects the village, the forested shoulders and the alpine bowl.
	var climb := maxf(0.0, 13.0 - z)
	var crest := minf(climb, 88.0)
	var ridge := crest * (0.31 + 0.105 * smoothstep(9.0, 61.0, crest))
	var flank := exp(-pow(absf(x) / 49.0, 2.8))
	var left := Vector2((x + 16.0) / 13.5, (z + 11.0) / 19.0)
	var right := Vector2((x - 21.0) / 15.0, (z + 36.0) / 20.0)
	var summit := Vector2((x + 25.0) / 24.5, (z + 73.0) / 18.5)
	var relief := 4.1 * exp(-left.length_squared()) + 5.8 * exp(-right.length_squared()) + 9.8 * exp(-summit.length_squared())
	# Two wind-carved spurs border a shallow bowl above timberline. Each rib
	# enters the snow obliquely and melts away before the forest band.
	var west_rib := Vector2((x + 34.0 + 0.26 * (z + 54.0)) / 5.4, (z + 61.0) / 18.5)
	var east_rib := Vector2((x - 2.5 + 0.32 * (z + 53.0)) / 7.2, (z + 59.0) / 19.0)
	var bowl := Vector2((x + 12.0) / 10.5, (z + 51.0) / 14.0)
	relief += 5.0 * exp(-west_rib.length_squared()) + 4.0 * exp(-east_rib.length_squared()) - 2.25 * exp(-bowl.length_squared())
	var far_side := maxf(0.0, -z - 74.0)
	var front := smoothstep(0.0, 7.0, climb)
	var local := maxf(0.32, 0.4 + ridge * flank + relief + front * 0.16 * sin(x * 0.19 + z * 0.17) - far_side * smoothstep(0.0, 12.0, far_side) * 1.45)
	if weight > 0.0:
		local = lerpf(local, backcountry.elevation(x,z), weight)
	return MAP_SCALE * local


func surface_height(x: float, z: float) -> float:
	# Tracks and ski edges must touch the tessellated triangles, even when the
	# continuous height function bows a few centimeters above or below a face.
	var local := (Vector2(x, z) - SNOW_MIN) / (SNOW_MAX - SNOW_MIN)
	if _snow_samples.is_empty() or local.x < 0.0 or local.y < 0.0 or local.x > 1.0 or local.y > 1.0:
		return height_at(x, z)
	var uv := local * Vector2(SNOW_COLUMNS - 1, SNOW_ROWS - 1)
	var cell := Vector2i(mini(floori(uv.x), SNOW_COLUMNS - 2), mini(floori(uv.y), SNOW_ROWS - 2))
	var f := uv - Vector2(cell)
	var i := cell.y * SNOW_COLUMNS + cell.x
	var right := _snow_samples[i + 1]
	var down := _snow_samples[i + SNOW_COLUMNS]
	if f.x + f.y <= 1.0:
		return (1.0 - f.x - f.y) * _snow_samples[i] + f.x * right + f.y * down
	return (f.x + f.y - 1.0) * _snow_samples[i + SNOW_COLUMNS + 1] + (1.0 - f.x) * down + (1.0 - f.y) * right


func _in_bounds(p: Vector2) -> bool:
	p /= MAP_SCALE
	var u := absf(p.x / 53.0)
	var v := absf((p.y + 28.0) / 53.0)
	return u < 1.0 and v < 1.0 and pow(u, 6.0) + pow(v, 8.0) <= 1.0


func playable_at(p: Vector2) -> bool:
	if not _in_bounds(p):
		return false
	var cell := Vector2i((p / CELL_SIZE).floor())
	for obstacle: Vector3 in _footprint_cells.get(cell, []):
		if p.distance_squared_to(Vector2(obstacle.x, obstacle.y)) <= obstacle.z * obstacle.z:
			return false
	return scenery == null or scenery.forest_clear(p, p, 0.0)


func reserve_footprint(center: Vector2, radius: float) -> void:
	var footprint := Vector3(center.x, center.y, radius)
	var first := Vector2i(((center - Vector2.ONE * radius) / CELL_SIZE).floor())
	var last := Vector2i(((center + Vector2.ONE * radius) / CELL_SIZE).floor())
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, z)
			if not _footprint_cells.has(cell):
				_footprint_cells[cell] = []
			_footprint_cells[cell].append(footprint)


func _fixed_clear(a: Vector2, b: Vector2, margin: float) -> bool:
	if not _in_bounds(a) or not _in_bounds(b):
		return false
	var padding := Vector2.ONE * margin
	var first := Vector2i(((a.min(b) - padding) / CELL_SIZE).floor())
	var last := Vector2i(((a.max(b) + padding) / CELL_SIZE).floor())
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, z)
			if not _footprint_cells.has(cell):
				continue
			for obstacle: Vector3 in _footprint_cells[cell]:
				var center := Vector2(obstacle.x, obstacle.y)
				var closest := a if a.is_equal_approx(b) else Geometry2D.get_closest_point_to_segment(center, a, b)
				var radius := obstacle.z + margin
				if center.distance_squared_to(closest) <= radius * radius:
					return false
	return true


func route_clear(start: Vector2, end: Vector2, margin := 0.0) -> bool:
	return _fixed_clear(start, end, margin) and (scenery == null or scenery.forest_clear(start, end, margin))


func pick_snow(screen_pos: Vector2) -> Variant:
	var point = pick_ground(screen_pos)
	if point != null and playable_at(point):
		return point
	return null


func pick_ground(screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var previous_t := 0.0
	var limit := minf(camera.far, camera_distance(camera.size) + 500.0)
	if direction.y < -0.01:
		previous_t = maxf(0.0,(245.0-origin.y)/direction.y)
		limit = minf(limit,(-42.0-origin.y)/direction.y)
	# March from the camera to take the first terrain crossing, including a shoulder
	# that occludes the valley behind it. Refine within that bracket for stable dragging.
	for step in range(floori(previous_t) + 1, ceili(limit) + 1):
		var t := float(step)
		var p := origin + direction * t
		if p.y <= height_at(p.x, p.z):
			var low := previous_t
			var high := t
			for iteration in 12:
				var middle := (low + high) * 0.5
				var point := origin + direction * middle
				if point.y > height_at(point.x, point.z):
					low = middle
				else:
					high = middle
			var hit := origin + direction * high
			var flat := Vector2(hit.x, hit.z)
			if _in_bounds(flat):
				return flat
			return null
		previous_t = t
	return null


func suggested_run(tier: int, shape := 0, variation := 0) -> PackedVector2Array:
	var top := station_top(tier)
	var bottom := station_base(tier)
	var forward := (top - bottom).normalized()
	var side := Vector2(forward.y, -forward.x)
	var mid := top.lerp(bottom, 0.5)
	if absf(mid.x - side.x * 3.0) < absf(mid.x + side.x * 3.0):
		side = -side
	var start := top + side * 1.85 - forward * 0.23
	var end := bottom + side * 2.06 - forward * 1.14
	var bow: float = [8.0, 12.0, 13.0][clampi(tier, 0, 2)] * MAP_SCALE
	var points := PackedVector2Array()
	var steps := ceili(start.distance_to(end) / 1.30)
	for i in range(steps + 1):
		var t := float(i) / steps
		var sweep := bow * sin(PI * t) * (0.87 + 0.13 * sin(t * TAU))
		if shape == 0 and variation > 0:
			var offset := ceili(variation / 2.0) * 0.13
			sweep *= 1.0 + (offset if variation % 2 == 1 else -offset)
		elif shape != 0:
			var count := 1.15 if shape == 1 else 1.95
			var phase := 0.3 + (variation % 3 - 1) * 0.64
			var width := 1.0 - 0.12 * floori(variation / 3.0)
			sweep = bow * sin(PI * t) * width * (0.94 + 0.67 * sin(count * TAU * t + phase))
		points.append(start.lerp(end, t) + Vector2(signf(side.x) * sweep, 0.0))
	return points


func cut_issue(points: PackedVector2Array, require_standing_trees := true) -> String:
	if points.size() < 2:
		return "Draw downhill through a stand of pines."
	var drop := surface_height(points[0].x, points[0].y) - surface_height(points[-1].x, points[-1].y)
	if drop < 1.0:
		return "Start above the trees and finish farther downhill."
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		if not _fixed_clear(a, b, 0.45):
			return "Give the buildings and rocks a little room."
	if not preload("res://world/run_profile.gd").flows_downhill(points, self):
		return "Keep the long traverses falling gently toward the village."
	if require_standing_trees and scenery.trees_along(points, CUT_HALF_WIDTH).is_empty():
		return "Bend the run through a stand of pines to open new snow."
	return ""


func cut_run(points: PackedVector2Array, require_standing_trees := true) -> int:
	if not cut_issue(points, require_standing_trees).is_empty():
		return 0
	_last_cleared = scenery.trees_along(points, CUT_HALF_WIDTH)
	scenery.set_cleared(_last_cleared, true)
	_last_sign = scenery.trail_sign(points, CUT_HALF_WIDTH)
	return _last_cleared.size()


func undo_last_cut() -> void:
	if _last_cleared.is_empty() and not is_instance_valid(_last_sign):
		return
	scenery.set_cleared(_last_cleared, false)
	_last_cleared.clear()
	if is_instance_valid(_last_sign):
		_last_sign.queue_free()
	_last_sign = null


func _set_light() -> void:
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#bdccdf")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#cdd5f2")
	environment.ambient_light_energy = 0.72
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var sky := WorldEnvironment.new()
	sky.environment = environment
	add_child(sky)
	sun.light_color = Color("#ffe2c9")
	sun.light_energy = 0.78
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 660.0
	sun.shadow_bias = 0.035
	sun.rotation_degrees = Vector3(-30.0, -49.0, 0.0)
	add_child(sun)


func _build_sky() -> void:
	sky_material.shader = preload("res://world/alpine_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.fog_sky_affect = 0.1

func snow_pigment(x: float, z: float, y: float, normal: Vector3) -> Color:
	# Last light lies on the high, west-facing lips. Cool reflected light
	# stays down in the sheltered folds. Both are quiet around moving skiers.
	var hollow := 0.30 * (1.0 - smoothstep(1.0, 8.0, y))
	var leeward := 0.25 * smoothstep(-0.32, 0.45, normal.x)
	var drifts := 0.10 * (0.5 + 0.5 * sin(x * 0.37 + sin(z * 0.52) + z * 1.20))
	var pigment := SNOW.lerp(SHADOW_SNOW, hollow + leeward + drifts)
	var alpenglow := smoothstep(5.0, 11.5, y) * (0.36 + 0.56 * smoothstep(0.25, 0.85, 0.5 - normal.x))
	return pigment.lerp(CREST_SNOW, alpenglow).srgb_to_linear()


func _terrain_axis(low: float, high: float, count: int) -> PackedFloat32Array:
	var offsets := PackedFloat32Array()
	var distance := 0.0
	while distance < 980.0 * MAP_SCALE:
		distance += clampf(1.5 * MAP_SCALE + distance * 0.045, 1.5 * MAP_SCALE, 30.0 * MAP_SCALE)
		offsets.append(distance)
	var axis := PackedFloat32Array()
	for i in range(offsets.size()-1,-1,-1):
		axis.append(low-offsets[i])
	for i in count:
		axis.append(lerpf(low,high,float(i)/(count-1)))
	for offset in offsets:
		axis.append(high+offset)
	return axis

func _build_snow() -> void:
	var xs := _terrain_axis(SNOW_MIN.x,SNOW_MAX.x,SNOW_COLUMNS)
	var zs := _terrain_axis(SNOW_MIN.y,SNOW_MAX.y,SNOW_ROWS)
	var columns := xs.size()
	var rows := zs.size()
	var first_x := xs.find(SNOW_MIN.x)
	var first_z := zs.find(SNOW_MIN.y)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var triangles := PackedInt32Array()
	for row in rows:
		for column in columns:
			var x := xs[column]
			var z := zs[row]
			var h := height_at(x,z)
			vertices.append(Vector3(x,h,z))
			if column >= first_x and column < first_x + SNOW_COLUMNS and row >= first_z and row < first_z + SNOW_ROWS:
				_snow_samples.append(h)
	for row in rows:
		var up := maxi(row-1,0)
		var down := mini(row+1,rows-1)
		for column in columns:
			var i := row * columns + column
			var left := maxi(column-1,0)
			var right := mini(column+1,columns-1)
			var dx := (vertices[row*columns+right].y-vertices[row*columns+left].y)/(xs[right]-xs[left])
			var dz := (vertices[down*columns+column].y-vertices[up*columns+column].y)/(zs[down]-zs[up])
			var normal := Vector3(-dx,1.0,-dz).normalized()
			var p := vertices[i] / MAP_SCALE
			normals.append(normal)
			colors.append(backcountry.snow_color(Vector2(p.x,p.z),p.y,normal,snow_pigment(p.x,p.z,p.y,normal)))
			if row+1 < rows and column+1 < columns:
				triangles.append_array(PackedInt32Array([i,i+1,i+columns,i+1,i+columns+1,i+columns]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	mesh.surface_set_material(0,material)
	var instance := MeshInstance3D.new()
	instance.name = "Alpine basin"
	instance.mesh = mesh
	add_child(instance)
