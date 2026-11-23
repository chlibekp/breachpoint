// Menu backdrop: deep navy gradient, cool-to-warm light split, faint angled grid and a slow Rift glow.
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.059, 0.098, 0.137, 1.0);
uniform vec4 cool_color : source_color = vec4(0.10, 0.20, 0.27, 1.0);
uniform vec4 warm_color : source_color = vec4(0.55, 0.26, 0.20, 1.0);
uniform vec4 rift_color : source_color = vec4(0.42, 0.25, 0.84, 1.0);
uniform float grid_scale = 42.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(cool_color.rgb, base_color.rgb, smoothstep(0.0, 1.0, uv.y * 0.9 + uv.x * 0.25));
	// Warm key glow from the upper right, like late sun through a doorway.
	float warm = exp(-3.0 * length(p - vec2(aspect * 0.86, 0.12)));
	col += warm_color.rgb * warm * 0.55;
	// Slow Rift pulse lower left.
	float rift = exp(-4.0 * length(p - vec2(aspect * 0.12, 0.92)));
	col += rift_color.rgb * rift * (0.32 + 0.08 * sin(TIME * 0.7));
	// Angled grid lines.
	vec2 g = vec2(p.x + p.y * 0.35, p.y) * grid_scale;
	vec2 f = abs(fract(g) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.03, min(f.x, f.y));
	col += vec3(0.85, 0.92, 1.0) * line * 0.018;
	// Vignette.
	col *= 1.0 - 0.45 * pow(length(uv - 0.5) * 1.25, 2.2);
	// Dither to avoid banding.
	col += (hash(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0);
}
