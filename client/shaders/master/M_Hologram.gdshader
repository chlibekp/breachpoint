// M_Hologram (spec §5.5): scanlines, flicker and occasional glitch offsets for signage/ads.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D image : source_color, hint_default_white, filter_linear;
uniform vec4 color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float energy = 1.5;
uniform float glitch = 0.15;

float hash(float x) { return fract(sin(x * 91.7) * 43758.5453); }

void fragment() {
	float t = floor(TIME * 12.0);
	float g = step(1.0 - glitch * 0.2, hash(t)) * (hash(t + UV.y * 20.0) - 0.5) * 0.08;
	vec2 uv = UV + vec2(g, 0.0);
	vec4 img = texture(image, uv);
	float scan = 0.75 + 0.25 * sin(UV.y * 400.0 + TIME * 8.0);
	float flicker = 0.9 + 0.1 * hash(t * 1.3);
	ALBEDO = img.rgb * color.rgb * energy * scan * flicker * img.a;
}
