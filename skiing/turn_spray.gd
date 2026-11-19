extends MultiMeshInstance3D

# A turn releases a short sheet of snow. Each grain group inherits some of
# the rider's momentum, then flies in world space even as the rider turns away.
const CAPACITY := 128
const EMISSION_SECONDS := 0.36
const STEP := 0.026
static var _puff_mesh: QuadMesh

class Puff:
	var center: Vector3
	var velocity: Vector3
	var snow_origin: Vector3
	var snow_normal: Vector3
	var radius: float
	var stretch: float
	var age := 0.0
	var life: float
	var tint: Color

var _puffs: Array[Puff] = []
var _rng := RandomNumberGenerator.new()
var _rider: Node3D
var _edge := 0.0
var _previous_load := 0.0
var _peak_bend := 0.0
var _fired := false
var _strength := 0.0
var _speed := 0.0
var _outside := 1.0
var _board := false
var _release_time := EMISSION_SECONDS
var _until_next := 0.0


func setup(rider: Node3D, variant: int) -> void:
	_rider = rider
	_rng.seed = 104729 + 65537 * variant
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_process(false)


func load_edge(bank: float, speed: float, bend: float, snowboard: bool) -> void:
	var load := absf(bank)
	var edge := signf(bank)
	if edge != _edge or load < 0.10:
		_edge = edge
		_fired = false
		_peak_bend = 0.0
	_peak_bend = maxf(_peak_bend, absf(bend))
	var past_peak := load < _previous_load or absf(bend) < 0.90 * _peak_bend
	_previous_load = load
	if _fired or speed < 2.25 or load < 0.205:
		return
	if not past_peak and load < 0.46:
		return
	_fired = true
	_outside = -edge
	_strength = clampf(0.31 + 0.57 * smoothstep(0.205, 0.57, load) + 0.12 * smoothstep(2.25, 5.4, speed), 0.31, 1.0)
	_speed = speed
	_board = snowboard
	_release_time = 0.0
	_until_next = STEP
	if multimesh == null:
		_create_batch()
	_emit(10, 1.0)
	_draw_puffs()
	set_process(true)


func leave_snow() -> void:
	_release_time = EMISSION_SECONDS
	_edge = 0.0
	_previous_load = 0.0
	_peak_bend = 0.0
	_fired = false


func touch_down(speed: float, snowboard: bool) -> void:
	leave_snow()
	_board = snowboard
	_speed = speed
	_strength = 0.32
	if multimesh == null:
		_create_batch()
	for side: float in [-1.0, 1.0]:
		_outside = side
		_emit(5, 0.55)
	_draw_puffs()
	set_process(true)


func _create_batch() -> void:
	if _puff_mesh == null:
		_puff_mesh = QuadMesh.new()
		_puff_mesh.size = Vector2.ONE
		var mat := StandardMaterial3D.new()
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# The translucent furrow is on the ground, underneath every airborne grain.
		mat.render_priority = 3
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.albedo_texture = _puff_texture()
		_puff_mesh.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _puff_mesh
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0


static func _puff_texture() -> ImageTexture:
	# A tiny cluster of ice grains and a faint dusty center breaks up the
	# silhouette. At smaller sizes the same texture resolves as an individual grain.
	const SIZE := 64
	var rng := RandomNumberGenerator.new()
	rng.seed = 51719
	var grains: Array[Vector3] = [Vector3(-0.05, 0.01, 0.36), Vector3(0.29, -0.16, 0.21)]
	for i in 34:
		var center := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 0.79
		grains.append(Vector3(center.x, center.y, rng.randf_range(0.05, 0.19) * (1.04 - 0.4 * center.length())))
	var sprite := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / SIZE * 2.0 - Vector2.ONE
			var density := 0.16 * (1.0 - smoothstep(0.03, 0.80, p.length()))
			for grain in grains:
				var d := p.distance_to(Vector2(grain.x, grain.y)) / grain.z
				density = maxf(density, 1.0 - smoothstep(0.23, 1.0, d))
			var shade := smoothstep(-0.46, 0.51, p.y + 0.18 * p.x)
			var color := Color("#fffefa").lerp(Color("#b1c4d5"), 0.48 * shade)
			color.a = density
			sprite.set_pixel(x, y, color)
	return ImageTexture.create_from_image(sprite)


func _emit(count: int, release: float) -> void:
	var frame := _rider.global_transform
	var outward := frame.basis.x * _outside
	var up := frame.basis.y
	var forward := -frame.basis.z
	# Powder peels off the tail of the board's tipped edge, or the loaded
	# outside ski. Follow its actual roll and fore/aft stance through the turn.
	var deck: Node3D
	var contact_x := -_outside * 0.028
	if _board:
		deck = _rider.board
		contact_x = -_outside * 0.14
	else:
		deck = _rider.ski_decks[0 if _outside < 0.0 else 1]
	var source := deck.to_global(Vector3(contact_x, 0.042, 0.42 if _board else 0.37))
	for i in count:
		if _puffs.size() >= CAPACITY:
			break
		var p := Puff.new()
		# The fine grains lead the fan, the broader soft clumps hang nearer the edge.
		var fine := _rng.randf() < 0.72
		var kick := _strength * (0.40 + 0.60 * release)
		var reach := _rng.randf_range(1.35, 4.6) if fine else _rng.randf_range(0.72, 2.6)
		p.center = source + outward * _rng.randf_range(-0.012, 0.036) + forward * _rng.randf_range(-0.026, 0.072)
		p.velocity = outward * reach * (0.46 + 1.17 * kick)
		p.velocity += up * _rng.randf_range(1.15, 3.52) * (0.48 + 0.66 * kick)
		# Snow leaves the moving edge with some forward speed. The final grains
		# retain more of it and stay near the tail as the rider releases the edge.
		p.velocity += forward * _speed * (_rng.randf_range(0.23, 0.70) + (1.0 - release) * 0.19)
		p.snow_origin = frame.origin
		p.snow_normal = up
		p.radius = _rng.randf_range(0.12, 0.22) if fine else _rng.randf_range(0.29, 0.50)
		p.radius *= (0.65 + 0.50 * kick)
		p.stretch = _rng.randf_range(0.88, 1.22)
		p.life = _rng.randf_range(0.55, 0.83)
		p.tint = Color.WHITE
		p.tint.a = _rng.randf_range(0.80, 1.0) * (0.68 + 0.32 * release)
		_puffs.append(p)


func _process(dt: float) -> void:
	_release_time += dt
	_until_next -= dt
	while _release_time < EMISSION_SECONDS and _until_next <= 0.0:
		var weight := 1.0 - _release_time / EMISSION_SECONDS
		_emit(4 if weight > 0.52 else 2, weight)
		_until_next += STEP
	for i in range(_puffs.size() - 1, -1, -1):
		var p := _puffs[i]
		p.age += dt
		if p.age >= p.life:
			_puffs.remove_at(i)
			continue
		p.velocity *= exp(-1.1 * dt)
		p.velocity += Vector3.DOWN * 7.3 * dt
		p.center += p.velocity * dt
		var clearance := (p.center - p.snow_origin).dot(p.snow_normal)
		if clearance < 0.05:
			p.center += p.snow_normal * (0.05 - clearance)
			p.velocity = p.velocity.slide(p.snow_normal) * exp(-8.0 * dt)
	_draw_puffs()
	if _puffs.is_empty() and _release_time >= EMISSION_SECONDS:
		set_process(false)


func _draw_puffs() -> void:
	var bounds := AABB(_rider.global_position, Vector3.ZERO)
	for i in _puffs.size():
		var p := _puffs[i]
		var t := p.age / p.life
		var size := p.radius * (0.61 + 0.78 * smoothstep(0.0, 0.75, t))
		var scale3 := Vector3(size * p.stretch, size, size)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(scale3), p.center))
		var color := p.tint
		color.a *= 1.0 - smoothstep(0.33, 1.0, t)
		multimesh.set_instance_color(i, color)
		bounds = bounds.expand(p.center)
	multimesh.custom_aabb = bounds.grow(0.9)
	multimesh.visible_instance_count = _puffs.size()
