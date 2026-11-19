shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float snowfall = 0.0;
uniform float weather_time = 0.0;
uniform float visible_height = 160.0;
uniform float wind_direction = 1.0;
varying float strength;
void vertex() {
	vec4 seed = INSTANCE_CUSTOM;
	float fall = fract(seed.y + weather_time * mix(0.075, 0.18, seed.w));
	float sway = sin(weather_time * mix(0.55, 1.05, seed.y) + seed.x * 39.0);
	vec3 drift = vec3(wind_direction * (fall * (1.4 + 1.4*seed.x) + sway * 0.21),
		(1.0-fall) * (8.0 + 6.0*seed.z), 0.32 * sin(weather_time * 0.48 + seed.z * 22.0));
	vec4 center = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz + drift, 1.0);
	float width = clamp(visible_height * 0.0021, 0.039, 0.63) * mix(0.68, 1.45, seed.z);
	POSITION = PROJECTION_MATRIX * (center + vec4(VERTEX.x * width, VERTEX.y * width * 1.18, 0., 0.));
	float density = clamp(0.070 * pow(240.0 / max(visible_height, 1.0), 1.38), 0.045, 1.0);
	strength = smoothstep(0., 0.08, fall) * (1.0 - smoothstep(0.88, 1.0, fall));
	strength *= smoothstep(0., 0.018, density * snowfall - seed.x) * smoothstep(0., 0.17, snowfall);
}
void fragment() {
	float dist = length(UV*2.-1.);
	ALBEDO = vec3(0.91, 0.95, 1.0);
	ALPHA = strength * (1.0-smoothstep(0.34, 1.0, dist)) * 0.89;
}
