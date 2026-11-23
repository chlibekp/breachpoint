// M_Env_Blend (spec §5.5): up to three tiling materials blended by vertex colour (R -> layer B,
// G -> layer C) with a height-aware transition so dirt/moss/sand settles into cavities first.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/quality.gdshaderinc"

uniform sampler2D a_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D c_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D c_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D c_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float a_tile = 4.0;
uniform float b_tile = 4.0;
uniform float c_tile = 4.0;
// Vertex-colour painting is opt-in (MeshKit writes white by default).
uniform bool use_vertex_mask = false;
uniform float blend_contrast : hint_range(0.01, 1.0) = 0.15;
// Procedural mask so floors get natural patches without hand-painting (used when no vertex colour).
uniform float noise_b_amount : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale = 9.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float hblend(float mask, float height) {
	return smoothstep(0.5 - blend_contrast, 0.5 + blend_contrast, mask * 1.2 + (0.5 - height) * 0.6 - 0.1);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 aa = texture(a_albedo, p / a_tile).rgb;
	vec3 ao = texture(a_orm, p / a_tile).rgb;
	vec3 an = texture(a_normal, p / a_tile).rgb;
	float a_height = ao.r; // AO doubles as a cheap height proxy: cavities are dark.
	float nb = noise_b_amount > 0.0 ? smoothstep(0.45, 0.75, vnoise(p / noise_scale) * 0.7 + vnoise(p / noise_scale * 3.1) * 0.3) * noise_b_amount : 0.0;
	vec2 vmask = use_vertex_mask ? COLOR.rg : vec2(0.0);
	float mb = hblend(clamp(vmask.x + nb, 0.0, 1.0), a_height);
	float mc = hblend(vmask.y, a_height);
	vec3 alb = aa;
	vec3 orm = ao;
	vec3 nrm = an;
	if (mb > 0.001) {
		alb = mix(alb, texture(b_albedo, p / b_tile).rgb, mb);
		orm = mix(orm, texture(b_orm, p / b_tile).rgb, mb);
		nrm = mix(nrm, texture(b_normal, p / b_tile).rgb, mb);
	}
	if (mc > 0.001 && quality_tier >= QUALITY_WEB) {
		alb = mix(alb, texture(c_albedo, p / c_tile).rgb, mc);
		orm = mix(orm, texture(c_orm, p / c_tile).rgb, mc);
		nrm = mix(nrm, texture(c_normal, p / c_tile).rgb, mc);
	}
	ALBEDO = alb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	NORMAL_MAP = nrm;
}
