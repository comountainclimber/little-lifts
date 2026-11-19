shader_type spatial;
render_mode cull_back, depth_draw_never, diffuse_burley, specular_disabled;

uniform float travelled = 0.0;
uniform float strength = 1.0;

void fragment() {
	// The terrain supplies the albedo. The local sun and ambient light shade
	// the actual pillow and the recessed normals on the floor of the trough.
	float compressed = smoothstep(0.005, 0.075, -UV2.x);
	float fresh = smoothstep(0.02, 0.13, UV2.x);
	ALBEDO = COLOR.rgb * mix(vec3(1.0), vec3(0.84, 0.89, 0.95), compressed);
	ALBEDO = mix(ALBEDO, min(COLOR.rgb * 1.055, vec3(1.0)), fresh * 0.65);
	ROUGHNESS = 1.0;
	// The fringes of a powder fan dissolve unevenly into undisturbed snow.
	// Keep this feather beyond the trough so the rider's path stays readable.
	float outside = smoothstep(0.20, 0.82, -sign(UV.y) * UV2.y);
	float fringe = 0.5 + 0.3 * sin(UV.x * 5.4 + UV.y * 2.0) + 0.2 * sin(UV.x * 9.7 - UV.y);
	float across = 1.0 - smoothstep(0.67 - 0.10 * outside * fringe, 1.0 - 0.07 * outside * fringe, abs(UV.y));
	float passed = 1.0 - smoothstep(travelled - 0.15, travelled, UV.x);
	float start = smoothstep(0.0, 0.30, UV.x);
	ALPHA = strength * passed * across * start * 0.94;
}
