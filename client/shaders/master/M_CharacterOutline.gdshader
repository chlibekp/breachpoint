// M_CharacterOutline: inverted-hull silhouette outline for third-person characters (readability,
// spec definition of done: silhouette contrast >= 3:1). Drawn as next_pass of every AgentRig material.
// Back faces are pushed out along the screen-space normal by a constant pixel width, so the line is
// equally thick near and far. Colour and width come from per-map globals set by MapRuntime;
// alpha 0 (the default) collapses the hull so nothing is drawn.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;

global uniform vec4 character_outline;        // inner (dark) line: rgb = colour, a = on (> 0)
global uniform vec4 character_outline_light;  // outer (light) line, drawn at twice the width
global uniform float character_outline_px;    // inner width in pixels at 1080p
// Two-tone outline: the light pass is wider and drawn first, the dark pass overwrites its inner
// half, so the silhouette separates from both bright and dark backgrounds.
uniform bool light_pass = false;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n_view = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec2 n_clip = normalize((PROJECTION_MATRIX * vec4(n_view, 0.0)).xy + vec2(1e-6));
	float px = character_outline_px * VIEWPORT_SIZE.y / 1080.0 * (light_pass ? 2.0 : 1.0);
	vec4 col = light_pass ? character_outline_light : character_outline;
	vec2 offset = n_clip * px * 2.0 / VIEWPORT_SIZE * clip.w;
	// Always write POSITION (a conditional write breaks the Compatibility renderer).
	POSITION = col.a > 0.0 ? clip + vec4(offset, 0.0, 0.0) : vec4(2.0, 2.0, 2.0, 1.0);
}

void fragment() {
	ALBEDO = light_pass ? character_outline_light.rgb : character_outline.rgb;
}
