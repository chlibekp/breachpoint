// M_Character (spec §5.5, §4.4): painterly toon-PBR for agents.
// - Detail: triplanar fabric/leather/metal/skin/hair detail (normal + variation) projected in mesh
//   space, so it sticks to the body parts while they animate (textures from tools/texgen/chargen.py).
// - Vertex colour RGB carries baked painted AO and the head-to-toe value gradient (AgentRig);
//   vertex alpha < 1 marks bevelled hard-surface edges for lighter worn edges.
// - Lighting: soft two-tone ramp with a warm terminator band and cool, lifted shadows; skin gets
//   extra subsurface warmth; low-roughness surfaces get a crisp stylised highlight; fresnel rim.
// - `reveal` drives the enemy-spotted fresnel outline; per-map lift / value floor (readability).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://shaders/include/quality.gdshaderinc"
#include "res://shaders/include/viewmodel.gdshaderinc"

global uniform vec4 team_enemy_color;
// Per-map readability lift (MapRuntime.character_lift): self-illumination as a fraction of albedo.
global uniform float character_lift;
// Per-map value floor (MapRuntime.character_value_floor): alb' = floor + (1 - floor)·alb.
global uniform float character_value_floor;

uniform vec4 base_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform bool use_albedo_tex = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float toon_mix : hint_range(0.0, 1.0) = 0.55;
uniform float ramp_softness : hint_range(0.01, 0.5) = 0.14;
uniform float wrap : hint_range(0.0, 1.0) = 0.4;
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.60, 0.78, 1.0);
uniform vec4 terminator_color : source_color = vec4(1.0, 0.55, 0.35, 1.0);
uniform float saturation_boost : hint_range(0.8, 1.5) = 1.12;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.88, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 emissive_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emissive_energy = 0.0;
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.25;
// Skin: warm subsurface glow along the light terminator (ears, nose, cheeks read alive).
uniform float sss : hint_range(0.0, 1.0) = 0.0;
// Fabric: soft albedo-tinted sheen at grazing angles (velvet/nylon read, painterly edge light).
uniform float sheen : hint_range(0.0, 1.0) = 0.0;
// Triplanar detail set (chargen): N = tangent normal, V = albedo var / roughness offset / cavity.
uniform bool use_detail = false;
uniform sampler2D detail_n : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_v : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 12.0;  // tiles per metre
uniform float detail_strength : hint_range(0.0, 2.0) = 0.6;
uniform float detail_albedo : hint_range(0.0, 1.0) = 0.35;
uniform float detail_cavity : hint_range(0.0, 1.0) = 0.5;
uniform float detail_rough : hint_range(0.0, 1.0) = 0.3;

varying vec3 v_pos;
varying vec3 v_nrm;

vec3 saturate_color(vec3 c, float s) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(l), c, s);
}

void vertex() {
	v_pos = VERTEX;
	v_nrm = NORMAL;
	viewmodel_project(VERTEX, MODELVIEW_MATRIX, PROJECTION_MATRIX, POSITION);
}

void fragment() {
	vec3 alb = base_color.rgb * COLOR.rgb;
	if (use_albedo_tex) alb *= texture(albedo_tex, UV).rgb;
	float rough = roughness;
	if (use_detail) {
		vec3 n0 = normalize(v_nrm);
		vec3 w = pow(abs(n0), vec3(4.0));
		w /= (w.x + w.y + w.z + 1e-5);
		vec2 ux = v_pos.zy * detail_scale;
		vec2 uy = v_pos.xz * detail_scale;
		vec2 uz = v_pos.xy * detail_scale;
		vec2 tx = texture(detail_n, ux).rg * 2.0 - 1.0;
		vec2 ty = texture(detail_n, uy).rg * 2.0 - 1.0;
		vec2 tz = texture(detail_n, uz).rg * 2.0 - 1.0;
		vec3 perturb = (vec3(0.0, tx.y, tx.x) * w.x + vec3(ty.x, 0.0, ty.y) * w.y + vec3(tz.x, tz.y, 0.0) * w.z) * detail_strength;
		vec3 n_obj = normalize(n0 + perturb);
		NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(n_obj, 0.0))).xyz);
		vec3 dv = texture(detail_v, ux).rgb * w.x + texture(detail_v, uy).rgb * w.y + texture(detail_v, uz).rgb * w.z;
		alb *= 1.0 + (dv.r - 0.5) * 2.0 * detail_albedo;
		alb *= mix(1.0, dv.b, detail_cavity);
		rough = clamp(rough + (dv.g - 0.5) * 2.0 * detail_rough, 0.04, 1.0);
	}
	// Vertex alpha < 1 marks bevelled edges: paint a lighter worn edge.
	alb = mix(alb, min(alb * 1.35 + 0.04, vec3(1.0)), (1.0 - COLOR.a) * edge_wear);
	alb = character_value_floor + (1.0 - character_value_floor) * clamp(alb, 0.0, 1.0);
	ALBEDO = saturate_color(alb, saturation_boost);
	ROUGHNESS = rough;
	METALLIC = metallic;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, rim_power);
	vec3 emit = emissive_color.rgb * emissive_energy + ALBEDO * character_lift;
	emit += rim_color.rgb * fres * rim_strength * 0.25;
	emit += ALBEDO * pow(1.0 - ndv, 2.0) * sheen * 0.35;
	emit += team_enemy_color.rgb * smoothstep(0.35, 0.9, fres) * reveal * 2.5;
	EMISSION = emit;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// Painterly two-tone ramp: soft terminator, shadows lifted (never black) and cast shadows stepped.
	float lit = smoothstep(0.5 - ramp_softness, 0.5 + ramp_softness, wrapped);
	float att = smoothstep(0.15, 0.65, ATTENUATION);
	float toon = mix(0.32, 1.0, lit * att) * mix(0.85, 1.12, wrapped);
	float pbr = clamp(ndl, 0.0, 1.0) * ATTENUATION;
	float d = mix(pbr, toon, toon_mix);
	// Warm light / cool shade: lit side slightly warm, shaded side tinted toward shadow_tint.
	vec3 warm = mix(shadow_tint.rgb, vec3(1.04, 1.0, 0.95), lit * att);
	// Albedo is applied by the engine after light(); /PI matches the built-in Lambert energy.
	DIFFUSE_LIGHT += LIGHT_COLOR * warm * d / PI;
	DIFFUSE_LIGHT += LIGHT_COLOR * shadow_tint.rgb * (1.0 - d) * 0.05;
	// Terminator band: a narrow, saturated warm edge where light turns to shade (stronger on skin).
	float band = lit * (1.0 - lit) * 4.0 * mix(0.6, 1.0, att);
	DIFFUSE_LIGHT += LIGHT_COLOR * terminator_color.rgb * band * (0.035 + sss * 0.14);
	// Subsurface: warm light wrapping past the terminator.
	float term = smoothstep(-0.45, 0.05, ndl) * (1.0 - smoothstep(0.05, 0.55, ndl));
	DIFFUSE_LIGHT += LIGHT_COLOR * vec3(0.95, 0.38, 0.26) * term * sss * 0.12 * mix(0.5, 1.0, ATTENUATION);
	// Specular: soft GGX lobe plus a crisp stylised highlight on smooth surfaces (metal, visors).
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float a = max(ROUGHNESS * ROUGHNESS, 0.03);
	float spec = pow(ndh, 2.0 / (a * a) - 2.0) / (PI * a * a) * 0.08;
	float crisp = smoothstep(0.6, 0.66, pow(ndh, 2.0 / (a * a) - 2.0)) * (1.0 - smoothstep(0.25, 0.5, ROUGHNESS)) * 0.5;
	vec3 spec_col = mix(vec3(1.0), ALBEDO * 1.6 + 0.1, METALLIC);
	SPECULAR_LIGHT += LIGHT_COLOR * spec_col * (spec * mix(0.5, 1.0, METALLIC) + crisp) * ATTENUATION * clamp(ndl * 4.0, 0.0, 1.0);
}
