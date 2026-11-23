// Stylised panoramic sky (spec §8.6): painted gradient, soft sun disc + halo, layered painterly
// clouds with stepped edges. Cheap enough for the web tier; the same sky on every renderer.
shader_type sky;
render_mode use_debanding;

uniform vec4 zenith_color : source_color = vec4(0.33, 0.52, 0.80, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.80, 0.86, 0.90, 1.0);
uniform vec4 ground_color : source_color = vec4(0.55, 0.60, 0.62, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.92, 0.78, 1.0);
uniform vec4 cloud_light : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.66, 0.70, 0.82, 1.0);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_speed = 0.004;
uniform float energy = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += vnoise(p) * a; p *= 2.07; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color.rgb, zenith_color.rgb, smoothstep(0.0, 0.6, h));
	col = mix(col, ground_color.rgb, smoothstep(0.0, -0.08, h));
	// Sun.
	float sd = dot(d, LIGHT0_DIRECTION);
	col += sun_color.rgb * (smoothstep(0.9994, 0.9998, sd) * 6.0 + pow(max(sd, 0.0), 24.0) * 0.35 + pow(max(sd, 0.0), 4.0) * 0.08);
	// Clouds on a virtual dome.
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.18) * 1.6 + vec2(TIME * cloud_speed, 0.0);
		float n = fbm(uv);
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.12, n);
		float lit = smoothstep(0.0, 0.3, fbm(uv + LIGHT0_DIRECTION.xz * 0.08) - n + 0.15);
		vec3 cc = mix(cloud_shadow.rgb, cloud_light.rgb, floor(lit * 3.0) / 3.0);
		col = mix(col, cc, c * smoothstep(0.0, 0.12, h) * 0.92);
	}
	COLOR = col * energy;
}
