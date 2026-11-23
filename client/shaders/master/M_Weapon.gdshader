// M_Weapon (spec §5.5, §7.4): first-person weapon PBR with skin-ready masks.
// Vertex colour channels are the mask: R = base finish, G = accent, B = emissive (Rift tech).
// A skin is just data: base/accent/emissive colours, roughness/metal, an optional pattern texture.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/quality.gdshaderinc"
#include "res://shaders/include/viewmodel.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.16, 0.17, 0.18, 1.0); // matte graphite polymer
uniform float base_roughness : hint_range(0.0, 1.0) = 0.62;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 metal_color : source_color = vec4(0.24, 0.25, 0.27, 1.0); // satin dark metal
uniform float metal_roughness : hint_range(0.0, 1.0) = 0.38;
uniform vec4 accent_color : source_color = vec4(0.83, 0.39, 0.23, 1.0);
uniform float accent_roughness : hint_range(0.0, 1.0) = 0.45;
uniform vec4 emissive_color : source_color = vec4(1.0, 0.55, 0.25, 1.0);
uniform float emissive_energy = 2.0;
uniform sampler2D pattern_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_pattern = false;
uniform float pattern_scale = 6.0;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.3;
uniform float edge_highlight : hint_range(0.0, 1.0) = 0.35;
// UV.x carries the "metal" part flag from WeaponBuilder (1 = machined metal, 0 = polymer).

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
	if (viewmodel) viewmodel_project(VERTEX, MODELVIEW_MATRIX, PROJECTION_MATRIX, POSITION);
}

void fragment() {
	float m_base = COLOR.r;
	float m_accent = COLOR.g;
	float m_emit = COLOR.b;
	float is_metal = UV2.x;
	vec3 base = mix(base_color.rgb, metal_color.rgb, is_metal);
	if (use_pattern) {
		vec3 p = texture(pattern_tex, obj_pos.zy * pattern_scale).rgb;
		base *= p;
	}
	vec3 alb = base * m_base + accent_color.rgb * m_accent + emissive_color.rgb * 0.3 * m_emit;
	float edge = 1.0 - COLOR.a;
	alb = mix(alb, alb * 1.6 + 0.05, edge * edge_highlight);
	ALBEDO = alb;
	ROUGHNESS = mix(mix(base_roughness, metal_roughness, is_metal), accent_roughness, m_accent) - edge * 0.12;
	METALLIC = mix(base_metallic, 0.85, is_metal) * (1.0 - m_accent);
	if (quality_tier >= QUALITY_MEDIUM) {
		CLEARCOAT = clearcoat_amount * m_accent;
		CLEARCOAT_ROUGHNESS = 0.2;
	}
	EMISSION = emissive_color.rgb * emissive_energy * m_emit;
}
