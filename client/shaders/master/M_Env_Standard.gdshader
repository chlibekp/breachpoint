// M_Env_Standard (spec §5.5): art-directed PBR for environment surfaces.
// - Albedo / Normal / ORM set with world-scale UVs (triplanar option for rocks and kit pieces)
// - Painted gradient: darker toward the floor, lighter toward the top (art bible §4.3)
// - Vertex colour: RGB = tint multiplier, A = edge mask written by MeshKit bevels -> painted edge wear
// - Top-down dust layer driven by world normal
// - Close-range detail normal skipped on the web tier
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/quality.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tile_size = 4.0; // metres per texture repeat
uniform bool triplanar = false;
uniform bool use_uv = false; // true: use mesh UV0 (unique hero assets) instead of world projection
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_mult : hint_range(0.0, 2.0) = 1.0;
uniform float metallic_mult : hint_range(0.0, 1.0) = 1.0;
// Painted vertical gradient in world space (object-relative heights).
uniform float gradient_bottom = 0.0;
uniform float gradient_top = 4.0;
uniform float gradient_strength : hint_range(0.0, 0.5) = 0.14;
// Edge wear from vertex alpha.
uniform vec4 edge_color : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform float edge_strength : hint_range(0.0, 1.0) = 0.35;
// Top-down dust.
uniform vec4 dust_color : source_color = vec4(0.86, 0.80, 0.68, 1.0);
uniform float dust_amount : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D detail_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.5;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_nrm;
varying float obj_height;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	obj_height = world_pos.y - MODEL_MATRIX[3].y;
}

vec2 box_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y > a.x && a.y > a.z) return p.xz;
	if (a.x > a.z) return vec2(p.z * sign(n.x), -p.y);
	return vec2(-p.x * sign(n.z), -p.y);
}

void fragment() {
	vec3 alb;
	vec3 nrm_ts;
	vec3 orm;
	if (triplanar) {
		vec3 w = pow(abs(world_nrm), vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec3 p = world_pos / tile_size;
		alb = texture(albedo_tex, p.zy).rgb * w.x + texture(albedo_tex, p.xz).rgb * w.y + texture(albedo_tex, p.xy).rgb * w.z;
		orm = texture(orm_tex, p.zy).rgb * w.x + texture(orm_tex, p.xz).rgb * w.y + texture(orm_tex, p.xy).rgb * w.z;
		nrm_ts = texture(normal_tex, p.zy).rgb * w.x + texture(normal_tex, p.xz).rgb * w.y + texture(normal_tex, p.xy).rgb * w.z;
	} else {
		vec2 uv = use_uv ? UV : box_uv(world_pos, world_nrm) / tile_size;
		alb = texture(albedo_tex, uv).rgb;
		orm = texture(orm_tex, uv).rgb;
		nrm_ts = texture(normal_tex, uv).rgb;
	}
	alb *= tint.rgb * COLOR.rgb;
	// Painted gradient: soft darkening near the ground, slight lift at the top.
	float g = clamp((obj_height - gradient_bottom) / max(gradient_top - gradient_bottom, 0.01), 0.0, 1.0);
	alb *= mix(1.0 - gradient_strength, 1.0 + gradient_strength * 0.35, smoothstep(0.0, 1.0, g));
	// Painted edge wear (bevel faces carry vertex alpha 1).
	float edge = (1.0 - COLOR.a) * edge_strength;
	alb = mix(alb, alb * edge_color.rgb * 1.25, edge);
	// Top-down dust.
	float dust = smoothstep(0.55, 0.95, world_nrm.y) * dust_amount;
	alb = mix(alb, dust_color.rgb, dust);

	ALBEDO = alb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = clamp(orm.g * roughness_mult + dust * 0.2, 0.0, 1.0);
	METALLIC = orm.b * metallic_mult;
	if (quality_tier >= QUALITY_MEDIUM && detail_strength > 0.0) {
		vec3 dn = texture(detail_normal_tex, world_pos.xz / detail_scale).rgb;
		nrm_ts = normalize(vec3(nrm_ts.xy + (dn.xy - 0.5) * detail_strength, nrm_ts.z));
	}
	NORMAL_MAP = nrm_ts;
	NORMAL_MAP_DEPTH = normal_strength;
}
