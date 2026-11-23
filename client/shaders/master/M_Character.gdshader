// M_Character (spec §5.5, §4.4): toon-PBR for agents.
// - Wrap (softened half-Lambert) diffuse with a 2-step soft ramp, mixed ~35% with PBR-like Lambert
// - Soft GGX-ish specular, fresnel rim (team-tinted option) so characters never sink into shadow
// - Mask-driven Rift emissive; `reveal` drives the enemy-spotted red fresnel outline
// - Slightly boosted saturation/contrast versus the environment (readability contract)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://shaders/include/quality.gdshaderinc"
#include "res://shaders/include/viewmodel.gdshaderinc"

global uniform vec4 team_enemy_color;

uniform vec4 base_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform bool use_albedo_tex = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float toon_mix : hint_range(0.0, 1.0) = 0.35;
uniform float ramp_softness : hint_range(0.01, 0.5) = 0.12;
uniform float wrap : hint_range(0.0, 1.0) = 0.45;
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.60, 0.78, 1.0);
uniform float saturation_boost : hint_range(0.8, 1.5) = 1.12;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.88, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 emissive_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emissive_energy = 0.0;
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.25;

vec3 saturate_color(vec3 c, float s) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(l), c, s);
}

void vertex() {
	if (viewmodel) viewmodel_project(VERTEX, MODELVIEW_MATRIX, PROJECTION_MATRIX, POSITION);
}

void fragment() {
	vec3 alb = base_color.rgb * COLOR.rgb;
	if (use_albedo_tex) alb *= texture(albedo_tex, UV).rgb;
	// Vertex alpha < 1 marks bevelled edges: paint a lighter worn edge.
	alb = mix(alb, min(alb * 1.35 + 0.04, vec3(1.0)), (1.0 - COLOR.a) * edge_wear);
	ALBEDO = saturate_color(alb, saturation_boost);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	vec3 emit = emissive_color.rgb * emissive_energy;
	emit += rim_color.rgb * fres * rim_strength * 0.25;
	emit += team_enemy_color.rgb * smoothstep(0.35, 0.9, fres) * reveal * 2.5;
	EMISSION = emit;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float ramp = mix(0.3, 1.0, smoothstep(0.5 - ramp_softness, 0.5 + ramp_softness, wrapped));
	float pbr = clamp(ndl, 0.0, 1.0);
	float d = mix(pbr, ramp * wrapped * 1.15, toon_mix) * ATTENUATION;
	// Albedo is applied by the engine after light(); /PI matches the built-in Lambert energy.
	DIFFUSE_LIGHT += LIGHT_COLOR * d / PI;
	// Shadows are tinted and lifted, never grey-black (art bible §4.2).
	DIFFUSE_LIGHT += LIGHT_COLOR * shadow_tint.rgb * (1.0 - d) * 0.05;
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float a = max(ROUGHNESS * ROUGHNESS, 0.03);
	float spec = pow(ndh, 2.0 / (a * a) - 2.0) / (PI * a * a) * 0.08;
	SPECULAR_LIGHT += LIGHT_COLOR * spec * ATTENUATION * pbr * mix(0.5, 1.0, METALLIC);
}
