// M_AbilityWall (spec §9.4): smokes, walls and barriers. Opaque, painterly, crisp silhouette;
// fresnel edge glows in the owner's team colour (ally cyan / enemy red) for readability.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/include/quality.gdshaderinc"

uniform vec4 body_color : source_color = vec4(0.55, 0.50, 0.70, 1.0);
uniform vec4 body_color_b : source_color = vec4(0.38, 0.34, 0.55, 1.0);
uniform vec4 team_color : source_color = vec4(0.25, 0.88, 0.82, 1.0);
uniform float edge_glow = 1.4;
uniform float scroll_speed = 0.08;
uniform float pattern_scale = 1.6;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.0; // dissolve-in/out progress

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(wp.x + wp.z, wp.y) * pattern_scale + vec2(TIME * scroll_speed, -TIME * scroll_speed * 0.6);
	float n = vnoise(p) * 0.65 + vnoise(p * 2.7) * 0.35;
	// Stepped (painterly) bands instead of soft gradients.
	float stepped = floor(n * 4.0) / 4.0;
	ALBEDO = mix(body_color_b.rgb, body_color.rgb, stepped);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = team_color.rgb * fres * edge_glow;
	if (alpha_cut > 0.0 && n < alpha_cut) discard;
}
