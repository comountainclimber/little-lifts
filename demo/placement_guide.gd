extends MeshInstance3D

const CLEAR := Color("#297e7c")
const WAITING := Color("#506c83")
const BLOCKED := Color("#ab6556")
var snow: Node
var ink := StandardMaterial3D.new()
var stroke := ArrayMesh.new()
var _vertices := PackedVector3Array()
var _written := 0
var _uploaded := 0
var _capacity := 0
var _camera_normal := Vector3.BACK
var _ring_points := PackedVector2Array()
var _pin_points := PackedVector2Array()
var ripple: Tween

func _ready() -> void:
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = ink
	for i in 28:
		_ring_points.append(Vector2.from_angle(TAU*i/28))
	for i in 24:
		_pin_points.append(Vector2.from_angle(TAU*i/24))
	mesh = stroke

func clear() -> void:
	if ripple:
		ripple.kill()
		ripple = null
	hide()

func preview(world: Node, start: Vector2, end: Vector2, valid: bool) -> void:
	clear()
	snow = world
	var span := end - start
	var tint := CLEAR if valid else BLOCKED
	if span.length() < 1.0:
		tint = WAITING
	_start(tint, 0.87)
	_ring(start, 0.44)
	var base := _surface(start)
	_beam(base, base + Vector3.UP * 1.2, 0.052)
	if span.length() > 1.0:
		var summit := _surface(end)
		_ring(end, 0.48)
		_beam(summit, summit + Vector3.UP * 1.2, 0.052)
		var side := Vector3(-span.y, 0.0, span.x).normalized()
		var previous := base + Vector3.UP * 1.2
		for i in range(1, 17):
			var f := float(i) / 16
			var point := _surface(start.lerp(end, f)) + Vector3.UP * (1.2 + sin(PI * f) * 0.52)
			_beam(previous, point, 0.045)
			previous = point
		for station in [base, summit]:
			var top: Vector3 = station + Vector3.UP * 1.2
			_beam(top - side * 0.29, top + side * 0.29, 0.065)
	_finish()

func placed(world: Node, base: Vector2, summit: Vector2) -> void:
	clear()
	snow = world
	ripple = create_tween().set_ignore_time_scale(true)
	ripple.tween_method(func(t: float):
		_start(CLEAR, 0.75 * (1.0 - t))
		_ring(base, 0.48 + 0.72 * t)
		_ring(summit, 0.48 + 0.72 * t)
		_finish()
	, 0.0, 1.0, 0.48)
	ripple.tween_callback(hide)

func _surface(p: Vector2) -> Vector3:
	return Vector3(p.x, snow.surface_height(p.x, p.y) + 0.10, p.y)

func _start(tint: Color, opacity: float) -> void:
	ink.albedo_color = Color(tint, opacity)
	_camera_normal = snow.camera.global_basis.z
	_written = 0

func _finish() -> void:
	if _written == 0:
		hide()
		return
	if _capacity != _vertices.size():
		# Indices never change. Each quad shares its two diagonal vertices.
		_capacity = _vertices.size()
		var indices := PackedInt32Array()
		indices.resize(_capacity/4*6)
		for q in range(_capacity/4):
			var i := q*6
			var v := q*4
			indices[i]=v
			indices[i+1]=v+1
			indices[i+2]=v+2
			indices[i+3]=v
			indices[i+4]=v+2
			indices[i+5]=v+3
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		stroke.clear_surfaces()
		stroke.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		# Streaming positions does not update the mesh's original bounds. All
		# guides lie on this playable snowfield, including elevated cliff pins.
		var extents: Vector2 = snow.SNOW_MAX-snow.SNOW_MIN
		stroke.custom_aabb = AABB(Vector3(snow.SNOW_MIN.x,-extents.length(),snow.SNOW_MIN.y),Vector3(extents.x,extents.length()*2.0,extents.y)).grow(4)
	else:
		# Collapse freed quads to a point when the next preview is shorter.
		# They contribute no fragments and a subsequent edit reuses the slots.
		for i in range(_written,_uploaded):
			_vertices[i] = Vector3.ZERO
		var end := maxi(_written,_uploaded)
		var bytes := _vertices.slice(0,end).to_byte_array() if end < _capacity else _vertices.to_byte_array()
		stroke.surface_update_vertex_region(0,0,bytes)
	_uploaded = _written
	show()

func _ring(center: Vector2, radius: float) -> void:
	var inner := _surface(center+_ring_points[0]*(radius-0.035))
	var outer := _surface(center+_ring_points[0]*(radius+0.035))
	var first_in := inner
	var first_out := outer
	for i in range(1,_ring_points.size()):
		var offset := _ring_points[i]
		var next_in := _surface(center+offset*(radius-0.035))
		var next_out := _surface(center+offset*(radius+0.035))
		_quad(inner,outer,next_out,next_in)
		inner = next_in
		outer = next_out
	_quad(inner,outer,first_out,first_in)

func _beam(start: Vector3, end: Vector3, half_width: float) -> void:
	var across := (end-start).cross(_camera_normal).normalized()*half_width
	_quad(start-across,start+across,end+across,end-across)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	if _written == _vertices.size():
		_vertices.resize(maxi(128,_written*2))
	_vertices[_written] = a
	_vertices[_written+1] = b
	_vertices[_written+2] = c
	_vertices[_written+3] = d
	_written += 4

func trail(world: Node, line: PackedVector2Array, tracing: bool, goal := Vector2.INF, bends := PackedVector2Array(), valid := true) -> void:
	clear()
	if line.size() < 1:
		return
	snow = world
	var tint := CLEAR if tracing else WAITING
	_start(tint if valid else BLOCKED,0.88 if tracing else 0.64)
	_ring(line[0], 0.85)
	if goal.is_finite():
		_ring(goal, 0.85)
	elif line.size() > 1:
		_ring(line[-1], 0.85)
	if tracing and bends.is_empty():
		_ring(line[-1], world.CUT_HALF_WIDTH)
	for bend in bends:
		_ring(bend,0.51)
	var along := 0.0
	for i in range(1, line.size()):
		var a := line[i-1]
		var b := line[i]
		var length := a.distance_to(b)
		var steps := maxi(1, ceili(length / 0.65))
		var edge: Vector2 = (b-a).normalized().orthogonal()*world.CUT_HALF_WIDTH if tracing else Vector2.ZERO
		for j in steps:
			var p := a.lerp(b, float(j)/steps)
			var q := a.lerp(b, float(j+1)/steps)
			if tracing and fmod(along, 2.0) < 1.35:
				_beam(_surface(p-edge),_surface(q-edge),0.065)
				_beam(_surface(p+edge),_surface(q+edge),0.065)
			if tracing or fmod(along, 2.0) < 1.15:
				_beam(_surface(p) + Vector3.UP * 0.08, _surface(q) + Vector3.UP * 0.08, 0.13 if tracing else 0.10)
			along += length / steps
	_finish()

func sites(world: Node, available: PackedVector2Array) -> void:
	clear()
	if available.is_empty():
		return
	snow = world
	_start(CLEAR, 0.92)
	for point in available:
		_ring(point, 1.48)
		var mid := _surface(point)
		_beam(mid - Vector3.RIGHT * 0.45, mid + Vector3.RIGHT * 0.45, 0.065)
		_beam(mid - Vector3.FORWARD * 0.52, mid + Vector3.FORWARD * 0.52, 0.065)
	_finish()

# Mark the exposed cap, which sits above the underlying snow surface.
func summit_sites(world: Node, available: Array) -> void:
	clear()
	if available.is_empty():
		return
	snow = world
	_start(CLEAR,0.98)
	for site in available:
		var point := Vector3(site.point.x,float(site.jumps[0].lip_height)+0.65,site.point.y)
		var up: Vector3 = world.camera.global_basis.y * 0.50
		var side: Vector3 = world.camera.global_basis.x * 0.50
		for i in 24:
			var a := _pin_points[i]
			var b := _pin_points[(i+1)%24]
			_beam(point+side*a.x+up*a.y,point+side*b.x+up*b.y,0.058)
		_beam(point-up*0.55,point-up*1.15,0.08)
	_finish()
