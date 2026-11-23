## ChatBox: in-match text chat (spec §15.4). Bottom-left log of the last 8 lines (each fades after
## 10 s, all reappear while typing) and an input line opened with Enter (team) or T (all).
class_name ChatBox
extends Control

signal submitted(text: String, team_only: bool)
signal typing_changed(typing: bool)

const MAX_LINES := 8
const LINE_SECONDS := 10.0

var typing := false
var _team_only := true
var _log: VBoxContainer
var _edit: LineEdit
var _scope: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	position = Vector2(24, -360)
	custom_minimum_size = Vector2(520, 220)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log = VBoxContainer.new()
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.custom_minimum_size = Vector2(520, 180)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log)
	var row := HBoxContainer.new()
	row.position = Vector2(0, 186)
	row.custom_minimum_size = Vector2(520, 0)
	add_child(row)
	_scope = Label.new()
	_scope.theme_type_variation = &"AccentLabel"
	row.add_child(_scope)
	_edit = LineEdit.new()
	_edit.max_length = 120
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_submitted.connect(_on_submit)
	_edit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.is_pressed() and (e as InputEventKey).keycode == KEY_ESCAPE:
			close()
			accept_event())
	row.add_child(_edit)
	row.visible = false


func open(team_only: bool) -> void:
	_team_only = team_only
	_scope.text = "TEAM " if team_only else "ALL "
	_scope.add_theme_color_override("font_color", Color("#3FE0D0") if team_only else Color("#ECEFF4"))
	(_edit.get_parent() as Control).visible = true
	_edit.text = ""
	_edit.grab_focus()
	typing = true
	for l: Node in _log.get_children():
		(l as CanvasItem).modulate.a = 1.0
	typing_changed.emit(true)


func close() -> void:
	(_edit.get_parent() as Control).visible = false
	_edit.release_focus()
	typing = false
	typing_changed.emit(false)


func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	if t != "":
		submitted.emit(t, _team_only)
	close()


func add_line(sender: String, text: String, team_only: bool, ally: bool) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = false
	l.fit_content = true
	l.scroll_active = false
	l.custom_minimum_size = Vector2(520, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_col := Color("#3FE0D0") if ally else Color("#FF4655")
	l.push_color(Color("#9AA3B2"))
	l.add_text("[TEAM] " if team_only else "[ALL] ")
	l.pop()
	l.push_color(name_col)
	l.add_text(sender + ": ")
	l.pop()
	l.push_color(Color("#ECEFF4"))
	l.add_text(text)
	l.pop()
	_log.add_child(l)
	while _log.get_child_count() > MAX_LINES:
		_log.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(LINE_SECONDS)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func() -> void:
		if typing and is_instance_valid(l):
			l.modulate.a = 1.0)
