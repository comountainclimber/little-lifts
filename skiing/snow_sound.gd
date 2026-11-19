extends AudioStreamPlayer3D

# A single short band-limited noise bed serves every skier. Edge pressure opens
# the sound as the skis bite and the last metre of the run tapers to silence.
const SAMPLE_RATE := 22050
static var _snow_loop: AudioStreamWAV
var followed := false
var _focus_mix := 0.0


func start(variant: int) -> void:
	# Headless simulation has no sound device and may advance dozens of laps
	# between mixer ticks. Movie-maker output still receives a real mix.
	if DisplayServer.get_name() == "headless" and Engine.get_write_movie_path().is_empty():
		return
	if _snow_loop == null:
		_snow_loop = _bake_snow()
	stream = _snow_loop
	# The orthographic camera can zoom while its listener stays far above the snow.
	# Use angular panning and set the two listening distances explicitly in shape().
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	panning_strength = 0.55
	attenuation_filter_cutoff_hz = 18000.0
	volume_db = -70.0
	play(fmod(variant * 0.37, 1.6))


func release() -> void:
	if has_stream_playback():
		get_stream_playback().stop()
	stop()
	stream = null


func _exit_tree() -> void:
	release()


func shape(speed: float, bank: float, remaining: float, delta: float, airborne := false, impact := 0.0) -> void:
	_focus_mix = lerpf(_focus_mix, float(followed), 1.0 - exp(-7.0 * delta))
	var glide := smoothstep(1.0, 5.8, speed)
	var edge := smoothstep(0.07, 0.60, absf(bank))
	var level := (0.013 + 0.03 * glide + 0.075 * glide * edge) * smoothstep(0.0, 1.8, remaining)
	level = (0.0 if airborne else level + 0.025 * impact) * lerpf(1.0, 4.1, _focus_mix)
	volume_db = linear_to_db(maxf(level, 0.0003))
	pitch_scale = 0.78 + 0.27 * glide + 0.18 * edge


static func _bake_snow() -> AudioStreamWAV:
	const FRAMES := SAMPLE_RATE * 2
	const OVERLAP := 1400
	var noise := PackedFloat32Array()
	noise.resize(FRAMES + OVERLAP)
	var rng := RandomNumberGenerator.new()
	rng.seed = 37621
	var bass := 0.0
	var mid := 0.0
	var grain := 0.0
	for i in noise.size():
		var sample := rng.randf_range(-1.0, 1.0)
		mid = lerpf(mid, sample, 0.51)
		bass = lerpf(bass, mid, 0.12)
		grain = lerpf(grain, absf(sample), 0.016)
		noise[i] = clampf((mid - bass) * (1.4 + 3.2 * (grain - 0.45)), -1.0, 1.0)
	var pcm := PackedByteArray()
	pcm.resize(FRAMES * 2)
	for i in FRAMES:
		var value := noise[i]
		if i < OVERLAP:
			value = lerpf(noise[FRAMES + i], value, smoothstep(0, OVERLAP, i))
		pcm.encode_s16(i * 2, roundi(value * 28000))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = FRAMES
	wav.data = pcm
	return wav
