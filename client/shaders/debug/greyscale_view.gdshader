// Debug value-check view (spec 9.5): full-screen luminance so value structure can be judged.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(vec3(l), 1.0);
}
