// M_RiftEnergy (spec §5.5): scrolling noise, fresnel and a refraction-like distortion of the
// emission. Additive-feeling but drawn opaque-ish so it works the same on both renderers.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

#include "res://shaders/include/quality.gdshaderinc"

uniform vec4 core_color : source_color = vec4(0.62, 0.42, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.35, 0.95, 1.0, 1.0);
uniform float energy = 1.6;
uniform float scroll_speed = 0.25;
uniform float noise_scale = 2.0;
uniform float fresnel_power = 2.5;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(17.1, 113.3, 71.7))) * 43758.5453); }
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i), n100 = hash3(i + vec3(1, 0, 0)), n010 = hash3(i + vec3(0, 1, 0)), n110 = hash3(i + vec3(1, 1, 0));
	float n001 = hash3(i + vec3(0, 0, 1)), n101 = hash3(i + vec3(1, 0, 1)), n011 = hash3(i + vec3(0, 1, 1)), n111 = hash3(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 p = obj * noise_scale + vec3(0.0, TIME * scroll_speed, TIME * scroll_speed * 0.4);
	float n = noise3(p) * 0.6 + noise3(p * 2.3 + 7.0) * 0.4;
	if (quality_tier >= QUALITY_MEDIUM) n = n * 0.8 + noise3(p * 5.1) * 0.2;
	float bands = smoothstep(0.45, 0.55, fract(n * 3.0 + TIME * 0.1));
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);
	vec3 col = mix(core_color.rgb * (0.35 + bands * 0.4), edge_color.rgb, fres);
	ALBEDO = col * energy * (0.4 + fres);
}
