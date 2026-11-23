// M_Glass: tinted glass with fresnel; screen-space refraction only on medium+ tiers.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

#include "res://shaders/include/quality.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.55, 0.72, 0.78, 0.35);
uniform float roughness : hint_range(0.0, 1.0) = 0.05;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = tint.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	ALPHA = clamp(tint.a + fres * 0.5, 0.0, 1.0);
}
