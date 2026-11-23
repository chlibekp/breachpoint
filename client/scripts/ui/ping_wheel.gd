## Ping wheel (spec §15.4): hold the ping key, flick the mouse toward a segment, release to ping
## the point under the crosshair. Quick tap = "Look here". Markers are world-space labels that stay
## visible through walls for 4 s, coloured per ping type (voicelines.json → pings).
class_name PingWheel
extends Control

signal pinged(kind: int, pos: Vector3)

const RADIUS := 120.0
const DEAD_ZONE := 28.0
## Segment order clockwise from the top: enemy, help, planting, rotate (index = ping kind).
const SEGMENTS := 4
const GENERIC := 4

var pings: Array = []
var camera: Camera3D
var _open := false
var _cursor := Vector2.ZERO
var _hover := GENERIC


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pings = SharedConfig.read_json("res://data/config/voicelines.json")["pings"]
	visible = false


func open() -> void:
	_open = true
	_cursor = Vector2.ZERO
	_hover = GENERIC
	visible = true


func close_and_ping() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var target := _target()
	if target != Vector3.INF:
		pinged.emit(_hover, target)


func is_open() -> bool:
	return _open


func _input(event: InputEvent) -> void:
	if _open and event is InputEventMouseMotion:
		_cursor += (event as InputEventMouseMotion).relative
		_cursor = _cursor.limit_length(RADIUS)
		_hover = GENERIC
		if _cursor.length() > DEAD_ZONE:
			# 0 = up, clockwise. atan2 with screen y down.
			var a := fposmod(atan2(_cursor.x, -_cursor.y) + PI / SEGMENTS, TAU)
			_hover = int(a / (TAU / SEGMENTS)) % SEGMENTS
		queue_redraw()
		get_viewport().set_input_as_handled()


func _target() -> Vector3:
	if camera == null:
		return Vector3.INF
	var from := camera.global_position
	var to := from - camera.global_basis.z * 150.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else from - camera.global_basis.z * 30.0


func _draw() -> void:
	if not _open:
		return
	var c := size * 0.5
	draw_circle(c, RADIUS + 30, Color(0.06, 0.07, 0.1, 0.55))
	for i: int in SEGMENTS:
		var p: Dictionary = pings[i]
		var a := TAU * i / SEGMENTS
		var dir := Vector2(sin(a), -cos(a))
		var col := Color(str(p["color"]))
		var hot := i == _hover
		draw_circle(c + dir * RADIUS * 0.72, 34.0 if hot else 26.0, Color(col, 0.9 if hot else 0.45))
		var font := get_theme_default_font()
		var label := str(p["label"]).to_upper()
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
		draw_string(font, c + dir * (RADIUS + 12) - Vector2(w * 0.5, -5 if dir.y >= 0 else 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE if hot else Color(1, 1, 1, 0.7))
	draw_circle(c, DEAD_ZONE, Color(1, 1, 1, 0.9 if _hover == GENERIC else 0.3), false, 2.0)
	draw_line(c, c + _cursor, Color(1, 1, 1, 0.6), 2.0)


## World marker for a received ping (fades over 4 s, visible through walls).
static func spawn_marker(parent: Node3D, kind: int, pos: Vector3, who: String, defs: Array) -> void:
	var p: Dictionary = defs[clampi(kind, 0, defs.size() - 1)]
	var l := Label3D.new()
	l.text = "◆\n%s\n%s" % [str(p["label"]).to_upper(), who]
	l.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
	l.font_size = 40
	l.outline_size = 10
	l.modulate = Color(str(p["color"]))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.position = pos + Vector3(0, 0.6, 0)
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)
