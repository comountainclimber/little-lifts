shader_type sky;
uniform float cloud_cover = 0.0;
uniform float weather_time = 0.0;
uniform vec4 zenith : source_color = vec4(0.47,0.64,0.79,1.0);
uniform vec4 horizon : source_color = vec4(0.92,0.85,0.83,1.0);
uniform vec4 mist : source_color = vec4(0.71,0.78,0.85,1.0);
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453);
}
float noise2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1.,0.)),f.x),mix(hash21(i+vec2(0.,1.)),hash21(i+vec2(1.)),f.x),f.y);
}
void sky() {
	float height = max(EYEDIR.y,0.0);
	vec3 clear_sky = mix(horizon.rgb,zenith.rgb,smoothstep(-0.01,0.19,height));
	vec2 projected = EYEDIR.xz/max(0.05,EYEDIR.y+0.09);
	vec2 p = projected*vec2(1.6,2.4)+vec2(weather_time*0.0018,0.0);
	float banks = 0.65*noise2(p)+0.23*noise2(2.03*p)+0.12*noise2(p*4.1);
	float streak = smoothstep(0.50,0.81,banks)*smoothstep(0.0,0.09,height);
	clear_sky = mix(clear_sky,vec3(0.89,0.88,0.89),streak*0.30);
	vec3 cloud_sky = mix(mist.rgb,vec3(0.64,0.69,0.75),smoothstep(0.20,0.85,banks));
	COLOR = mix(clear_sky,cloud_sky,cloud_cover);
}
