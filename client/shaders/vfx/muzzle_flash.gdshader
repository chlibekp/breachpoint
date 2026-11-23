// Muzzle flash flipbook card (spec §7.3 #2): 3 frames, additive, always faces the camera,
// optional viewmodel projection so first-person flashes sit on the weapon.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/include/viewmodel.gdshaderinc"

uniform sampler2D flipbook : source_color, filter_linear;
uniform float frame = 0.0;
uniform float energy = 3.0;

void vertex() {
	// Billboard.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
	viewmodel_project(VERTEX, MODELVIEW_MATRIX, PROJECTION_MATRIX, POSITION);
}

void fragment() {
	vec2 uv = vec2((UV.x + frame) / 3.0, UV.y);
	vec4 c = texture(flipbook, uv);
	ALBEDO = c.rgb * c.a * energy;
}
