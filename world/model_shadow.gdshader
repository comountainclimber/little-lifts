shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
void fragment() {
	vec2 d = abs((UV - 0.5) * 220.0) - vec2(74.0, 73.0);
	float distance_to_edge = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - 9.0;
	ALBEDO = vec3(0.13, 0.16, 0.23);
	ALPHA = 0.27 * (1.0 - smoothstep(-4.0, 13.0, distance_to_edge));
}
