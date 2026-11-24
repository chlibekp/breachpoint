// FXAA for the web tier (spec 9.2: MSAA 2x + FXAA). Godot 4.7's Compatibility renderer has no
// built-in screen-space AA, so QualityManager draws this full-screen pass on a canvas layer that
// sits above the 3D view and below the HUD. Luma-based edge detection + directional blur along
// the edge (FXAA 3.11 "console" style), cheap enough for integrated GPUs.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float edge_threshold = 0.125;
uniform float edge_threshold_min = 0.0312;
uniform float span_max = 8.0;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 rgb_m = texture(screen_tex, uv).rgb;
	float l_nw = luma(texture(screen_tex, uv + vec2(-1.0, -1.0) * px).rgb);
	float l_ne = luma(texture(screen_tex, uv + vec2(1.0, -1.0) * px).rgb);
	float l_sw = luma(texture(screen_tex, uv + vec2(-1.0, 1.0) * px).rgb);
	float l_se = luma(texture(screen_tex, uv + vec2(1.0, 1.0) * px).rgb);
	float l_m = luma(rgb_m);
	float l_min = min(l_m, min(min(l_nw, l_ne), min(l_sw, l_se)));
	float l_max = max(l_m, max(max(l_nw, l_ne), max(l_sw, l_se)));
	if (l_max - l_min < max(edge_threshold_min, l_max * edge_threshold)) {
		COLOR = vec4(rgb_m, 1.0);
	} else {
		vec2 dir = vec2(-((l_nw + l_ne) - (l_sw + l_se)), (l_nw + l_sw) - (l_ne + l_se));
		float reduce = max((l_nw + l_ne + l_sw + l_se) * 0.03125, 0.0078125);
		float rcp = 1.0 / (min(abs(dir.x), abs(dir.y)) + reduce);
		dir = clamp(dir * rcp, vec2(-span_max), vec2(span_max)) * px;
		vec3 a = 0.5 * (texture(screen_tex, uv + dir * (1.0 / 3.0 - 0.5)).rgb
				+ texture(screen_tex, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
		vec3 b = a * 0.5 + 0.25 * (texture(screen_tex, uv - dir * 0.5).rgb
				+ texture(screen_tex, uv + dir * 0.5).rgb);
		float l_b = luma(b);
		COLOR = vec4((l_b < l_min || l_b > l_max) ? a : b, 1.0);
	}
}
