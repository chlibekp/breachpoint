// M_Water: stylised sea with scrolling normals, depth-free shoreline tint (works on web),
// painted foam bands from a world-space noise.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

#include "res://shaders/include/quality.gdshaderinc"

uniform vec4 shallow_color : source_color = vec4(0.17, 0.65, 0.64, 1.0);
uniform vec4 deep_color : source_color = vec4(0.07, 0.33, 0.45, 1.0);
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wave_scale = 18.0;
uniform float wave_speed = 0.02;

varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (quality_tier >= QUALITY_LOW) {
		VERTEX.y += sin(wp.x * 0.15 + TIME * 0.8) * 0.12 + cos(wp.z * 0.11 + TIME * 0.6) * 0.1;
	}
}

void fragment() {
	vec2 uv1 = wp.xz / wave_scale + vec2(TIME * wave_speed, TIME * wave_speed * 0.6);
	vec2 uv2 = wp.xz / (wave_scale * 0.6) - vec2(TIME * wave_speed * 0.8, -TIME * wave_speed * 0.3);
	vec3 n = normalize(texture(wave_normal, uv1).rgb + texture(wave_normal, uv2).rgb - 1.0);
	float d = clamp(vnoise(wp.xz * 0.02) * 1.2, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, d);
	float foam = step(0.78, vnoise(wp.xz * 0.35 + TIME * 0.05) * 0.6 + vnoise(wp.xz * 1.1 - TIME * 0.07) * 0.4);
	ALBEDO = mix(col, vec3(0.92, 0.95, 0.94), foam * 0.6);
	ROUGHNESS = 0.08 + foam * 0.4;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
}
