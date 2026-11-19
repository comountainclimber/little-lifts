shader_type spatial;
render_mode cull_back, depth_draw_never, diffuse_burley, specular_disabled;

uniform float run_length;

void fragment() {
	float edge = 1.0 - smoothstep(0.63, 1.0, abs(UV.y));
	float end_fade = smoothstep(0.0, 1.3, min(UV.x, run_length - UV.x));
	// Groomer ridges disappear at valley scale. Checking the pixel
	// footprint prevents the fine parallel lines from shimmering while moving.
	float phase = UV.y * 152.0;
	float ridges = cos(phase) * (1.0 - smoothstep(0.6, 2.6, fwidth(phase)));
	ALBEDO = COLOR.rgb * vec3(0.893, 0.932, 0.969) * (1.0 + 0.035 * ridges);
	ALPHA = edge * end_fade * 0.71;
	ROUGHNESS = 1.0;
}
