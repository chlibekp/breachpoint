## Scoreboard (Tab, spec §15.2): K / D / A, score, credits, ultimate points, ping — split by team.
## Right-click while it is open frees the cursor for the REPORT buttons (spec §14.3: in-game report;
## the server keeps the match replay 14 days for review).
class_name Scoreboard
extends CanvasLayer

const REASONS: PackedStringArray = ["Cheating", "Griefing", "Abusive chat", "Inappropriate name"]

var entries: Array = []
var roster: Dictionary = {}
var match_id := ""
var my_id := -1
var _key := ""
var _reported: Dictionary = {}  ## playerId -> true
var _panel: PanelContainer
var _grid: GridContainer


func _ready() -> void:
	layer = 15
	visible = false
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(900, 0)
	_panel.position = Vector2(-450, -260)
	add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	var t := Label.new()
	t.text = "SCOREBOARD"
	t.theme_type_variation = &"HeaderLarge"
	v.add_child(t)
	_grid = GridContainer.new()
	_grid.columns = 9
	_grid.add_theme_constant_override("h_separation", 28)
	v.add_child(_grid)


func _process(_delta: float) -> void:
	if not visible:
		return
	var key := "%s|%s" % [str(entries), str(_reported)]
	if key == _key:
		return
	_key = key
	for c: Node in _grid.get_children():
		c.queue_free()
	for h: String in ["PLAYER", "TEAM", "K", "D", "A", "SCORE", "¤", "PING", ""]:
		_cell(h, &"AccentLabel")
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	for e: Dictionary in sorted:
		var id := int(e["playerId"])
		var info: Dictionary = roster.get(id, {})
		var player_name := str(info.get("name", id))
		_cell(player_name, &"ValueLabel")
		_cell("ALPHA" if int(info.get("team", 0)) == 0 else "BRAVO", &"MutedLabel")
		for k: String in ["kills", "deaths", "assists", "score", "credits", "pingMs"]:
			_cell(str(e[k]), &"ValueLabel")
		if id == my_id or player_name.ends_with("[BOT]") or not Api.online:
			_cell("", &"MutedLabel")
		elif _reported.has(id):
			_cell("REPORTED", &"MutedLabel")
		else:
			_grid.add_child(_report_button(id, player_name))


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()


func _report_button(id: int, player_name: String) -> MenuButton:
	var b := MenuButton.new()
	b.text = "REPORT"
	b.flat = false
	var pop := b.get_popup()
	for r: String in REASONS:
		pop.add_item(r)
	pop.id_pressed.connect(func(i: int) -> void:
		_reported[id] = true
		Api.request("POST", "/reports", {"target": player_name, "matchId": match_id, "reason": REASONS[i]}))
	return b


func _cell(text: String, variation: StringName) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	_grid.add_child(l)
