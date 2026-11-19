extends Node3D

enum Phase { CLEAR, CLOUDING, SNOWING, CLEARING }
var phase := Phase.CLEAR
var elapsed := 0.0
var duration := 0.0
var clock_seconds := 0.0
var cloud_cover := 0.0
var snowfall := 0.0
var _peak := 0.85
var _random := RandomNumberGenerator.new()
var _mountain: Node3D
var _compatibility := false
var _flakes := MultiMeshInstance3D.new()
var _material := ShaderMaterial.new()

func setup(mountain: Node3D) -> void:
	_mountain = mountain
	_compatibility = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if _compatibility:
		_configure_compatibility_light()
	duration = _random.randf_range(38.0, 58.0)
	_make_flakes()
	_apply()

func _process(delta: float) -> void:
	advance(delta / Engine.time_scale)

func advance(seconds: float) -> void:
	if _mountain == null:
		return
	clock_seconds += seconds
	elapsed += seconds
	while elapsed >= duration:
		elapsed -= duration
		phase = ((phase + 1) % Phase.size()) as Phase
		match phase:
			Phase.CLEAR:
				duration = _random.randf_range(68.0, 125.0)
			Phase.CLOUDING:
				duration = _random.randf_range(32.0, 55.0)
				_peak = _random.randf_range(0.70, 1.0)
				_material.set_shader_parameter("wind_direction", -1.0 if _random.randf() < 0.5 else 1.0)
			Phase.SNOWING:
				duration = _random.randf_range(55.0, 95.0)
			Phase.CLEARING:
				duration = _random.randf_range(38.0, 65.0)
	var t := elapsed / duration
	match phase:
		Phase.CLEAR:
			cloud_cover = 0.0
			snowfall = 0.0
		Phase.CLOUDING:
			cloud_cover = smoothstep(0.0, 0.95, t)
			snowfall = _peak * 0.68 * smoothstep(0.45, 1.0, t)
		Phase.SNOWING:
			cloud_cover = 1.0
			snowfall = _peak * (0.68 + 0.32 * sin(PI * t) * (0.80 + 0.20 * cos(t * TAU * 2.0)))
		Phase.CLEARING:
			cloud_cover = 1.0 - smoothstep(0.16, 1.0, t)
			snowfall = _peak * 0.68 * (1.0 - smoothstep(0.0, 0.70, t))
	_apply()

func _apply() -> void:
	var env: Environment = _mountain.environment
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = _mountain.camera_distance(_mountain.camera.size) + lerpf(52,8,cloud_cover)
	env.fog_depth_end = _mountain.camera_distance(_mountain.camera.size) + lerpf(570,345,cloud_cover)
	env.fog_density = lerpf(0.62, 0.83, cloud_cover)
	env.fog_light_color = Color("#b9c9d8").lerp(Color("#c9d4df"),cloud_cover)
	_mountain.sun.light_color = Color("#ffe2c9").lerp(Color("#e4ebf7"), cloud_cover)
	_mountain.sun.light_energy = lerpf(0.20,0.13,cloud_cover) if _compatibility else lerpf(0.78, 0.48, cloud_cover)
	_mountain.sun.shadow_opacity = lerpf(1.0, 0.56, cloud_cover)
	_mountain.environment.ambient_light_color = Color("#cdd5f2").lerp(Color("#d5e0ef"), cloud_cover)
	_mountain.environment.ambient_light_energy = lerpf(0.78,0.88,cloud_cover) if _compatibility else lerpf(0.72, 0.91, cloud_cover)
	_mountain.sky_material.set_shader_parameter("cloud_cover", cloud_cover)
	_mountain.sky_material.set_shader_parameter("weather_time", clock_seconds)
	_flakes.visible = snowfall > 0.001
	if _flakes.visible:
		_material.set_shader_parameter("snowfall", snowfall)
		_material.set_shader_parameter("visible_height", _mountain.camera.size)
		_material.set_shader_parameter("weather_time", clock_seconds)

# The compatibility backend lights in sRGB. Soften its shadow ramp and leave
# headroom for pink snow in direct sunlight without tinting the CanvasLayer HUD.
func _configure_compatibility_light() -> void:
	var curve := Gradient.new()
	curve.offsets = PackedFloat32Array([0.0,0.125,0.25,0.45,0.60,0.75,0.875,1.0])
	var stops := PackedFloat32Array([0.0,0.20,0.43,0.54,0.62,0.75,0.855,0.985])
	var shades := PackedColorArray()
	for level in stops:
		shades.append(Color(level,level,level))
	curve.colors = shades
	var texture := GradientTexture1D.new()
	texture.gradient = curve
	_mountain.environment.adjustment_color_correction = texture
	_mountain.environment.adjustment_enabled = true

func _make_flakes() -> void:
	var mesh := QuadMesh.new()
	_material.shader = preload("res://world/flurries.gdshader")
	mesh.material = _material
	var field := MultiMesh.new()
	field.transform_format = MultiMesh.TRANSFORM_3D
	field.use_custom_data = true
	field.mesh = mesh
	field.instance_count = 32000
	field.custom_aabb = AABB(Vector3(-242,-15,-267) * _mountain.MAP_SCALE, Vector3(485,150,490) * _mountain.MAP_SCALE)
	var scatter := RandomNumberGenerator.new()
	scatter.seed = 7919
	for i in field.instance_count:
		var x: float = scatter.randf_range(-83, 83) * _mountain.MAP_SCALE
		var z: float = scatter.randf_range(-117, 43) * _mountain.MAP_SCALE
		if i >= 18000:
			x = scatter.randf_range(-237,237) * _mountain.MAP_SCALE
			z = scatter.randf_range(-260,215) * _mountain.MAP_SCALE
		var y: float = _mountain.height_at(x,z)
		field.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
		field.set_instance_custom_data(i, Color(scatter.randf(), scatter.randf(), scatter.randf(), scatter.randf()))
	_flakes.multimesh = field
	_flakes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flakes)
