## Crosshair (spec §15.2): fully data-driven by a profile dictionary, importable/exportable as a
## short code. Movement and firing error widen the outer lines when enabled.
class_name Crosshair
extends Control

const DEFAULT := {
	"color": "#3FE0D0", "outline": true, "outline_opacity": 0.6, "outline_thickness": 1.0,
	"dot": false, "dot_size": 2.0, "inner": true, "inner_length": 5.0, "inner_thickness": 2.0,
	"inner_offset": 3.0, "inner_opacity": 1.0, "outer": false, "outer_length": 2.0,
	"outer_thickness": 2.0, "outer_offset": 10.0, "outer_opacity": 0.5,
	"movement_error": false, "firing_error": true,
}

var profile: Dictionary = DEFAULT.duplicate()
var spread_px: float = 0.0  ## current error expansion set by the HUD
var hidden_for_scope := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if hidden_for_scope:
		return
	var c := size * 0.5
	var col := Color(str(profile["color"]))
	var out_col := Color(0, 0, 0, float(profile["outline_opacity"]))
	var ot := float(profile["outline_thickness"]) if profile["outline"] else 0.0
	if profile["dot"]:
		var d := float(profile["dot_size"])
		if ot > 0.0:
			draw_rect(Rect2(c - Vector2(d, d) * 0.5 - Vector2(ot, ot), Vector2(d + ot * 2, d + ot * 2)), out_col)
		draw_rect(Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)), col)
	var err := spread_px if profile["firing_error"] else 0.0
	if profile["inner"]:
		_lines(c, float(profile["inner_length"]), float(profile["inner_thickness"]), float(profile["inner_offset"]) + err * 0.5, Color(col, float(profile["inner_opacity"])), out_col, ot)
	if profile["outer"]:
		_lines(c, float(profile["outer_length"]), float(profile["outer_thickness"]), float(profile["outer_offset"]) + err, Color(col, float(profile["outer_opacity"])), out_col, ot)


func _lines(c: Vector2, length: float, thick: float, offset: float, col: Color, out_col: Color, ot: float) -> void:
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var start := c + dir * offset
		var rect: Rect2
		if dir.x != 0:
			rect = Rect2(Vector2(minf(start.x, start.x + dir.x * length), c.y - thick * 0.5), Vector2(length, thick))
		else:
			rect = Rect2(Vector2(c.x - thick * 0.5, minf(start.y, start.y + dir.y * length)), Vector2(thick, length))
		if ot > 0.0:
			draw_rect(rect.grow(ot), out_col)
		draw_rect(rect, col)


## Export/import as a compact code (base64 of JSON) for sharing crosshairs.
func export_code() -> String:
	return Marshalls.utf8_to_base64(JSON.stringify(profile))


func import_code(code: String) -> bool:
	var parsed: Variant = JSON.parse_string(Marshalls.base64_to_utf8(code))
	if not (parsed is Dictionary):
		return false
	for k: String in DEFAULT:
		if (parsed as Dictionary).has(k):
			profile[k] = parsed[k]
	return true
