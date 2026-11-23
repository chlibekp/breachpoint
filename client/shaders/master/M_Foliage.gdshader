// M_Foliage (spec §5.5): stylised leaf clumps with wind sway; alpha-scissor cards supported.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/include/quality.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.36, 0.52, 0.24, 1.0);
uniform vec4 color_b : source_color = vec4(0.55, 0.68, 0.30, 1.0);
uniform sampler2D mask : hint_default_white, filter_linear_mipmap;
uniform bool use_mask = false;
uniform float sway = 0.06;
uniform float sway_speed = 1.3;

varying float h;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	h = clamp(VERTEX.y, 0.0, 2.0) * 0.5;
	float w = sin(TIME * sway_speed + wp.x * 0.7 + wp.z * 0.5) + 0.5 * sin(TIME * sway_speed * 2.3 + wp.z);
	if (quality_tier >= QUALITY_WEB) VERTEX.xz += vec2(w, w * 0.6) * sway * h;
}

void fragment() {
	ALBEDO = mix(color_a.rgb, color_b.rgb, h) * COLOR.rgb;
	ROUGHNESS = 0.85;
	BACKLIGHT = vec3(0.25, 0.32, 0.12);
	if (use_mask) {
		ALPHA = texture(mask, UV).a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
