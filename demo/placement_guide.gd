extends MeshInstance3D

const CLEAR := Color("#297e7c")
const WAITING := Color("#506c83")
const BLOCKED := Color("#ab6556")
var snow: Node
var ink := StandardMaterial3D.new()
var stroke: ImmediateMesh
var ripple: Tween

func _ready() -> void:
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = ink

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
	return Vector3(p.x, snow.height_at(p.x, p.y) + 0.10, p.y)

func _start(tint: Color, opacity: float) -> void:
	ink.albedo_color = Color(tint, opacity)
	stroke = ImmediateMesh.new()
	stroke.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

func _finish() -> void:
	stroke.surface_end()
	mesh = stroke
	show()

func _ring(center: Vector2, radius: float) -> void:
	for i in 28:
		var a := Vector2.from_angle(TAU * i / 28)
		var b := Vector2.from_angle(TAU * (i + 1) / 28)
		var i0 := _surface(center + a * (radius - 0.035))
		var i1 := _surface(center + b * (radius - 0.035))
		var o0 := _surface(center + a * (radius + 0.035))
		var o1 := _surface(center + b * (radius + 0.035))
		_quad(i0, o0, o1, i1)

func _beam(start: Vector3, end: Vector3, half_width: float) -> void:
	var across := (end - start).cross(snow.camera.global_basis.z).normalized() * half_width
	_quad(start - across, start + across, end + across, end - across)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		stroke.surface_add_vertex(v)

func trail(world: Node, line: PackedVector2Array, tracing: bool, goal := Vector2.INF) -> void:
	clear()
	if line.size() < 1:
		return
	snow = world
	_start(CLEAR if tracing else WAITING, 0.88 if tracing else 0.64)
	_ring(line[0], 0.85)
	if goal.is_finite():
		_ring(goal, 0.85)
	elif line.size() > 1:
		_ring(line[-1], 0.85)
	if tracing:
		_ring(line[-1], world.CUT_HALF_WIDTH)
	var along := 0.0
	for i in range(1, line.size()):
		var a := line[i-1]
		var b := line[i]
		var length := a.distance_to(b)
		var steps := maxi(1, ceili(length / 0.65))
		for j in steps:
			var p := a.lerp(b, float(j)/steps)
			var q := a.lerp(b, float(j+1)/steps)
			if tracing and fmod(along, 2.0) < 1.35:
				var edge: Vector2 = (b - a).normalized().orthogonal() * world.CUT_HALF_WIDTH
				for signum: float in [-1.0, 1.0]:
					_beam(_surface(p + edge * signum), _surface(q + edge * signum), 0.065)
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
			var a := Vector2.from_angle(TAU*i/24)
			var b := Vector2.from_angle(TAU*(i+1)/24)
			_beam(point+side*a.x+up*a.y,point+side*b.x+up*b.y,0.058)
		_beam(point-up*0.55,point-up*1.15,0.08)
	_finish()
