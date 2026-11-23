## Scoreboard (Tab, spec §15.2): K / D / A, score, credits, ultimate points, ping — split by team.
class_name Scoreboard
extends CanvasLayer

var entries: Array = []
var roster: Dictionary = {}
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
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 28)
	v.add_child(_grid)


func _process(_delta: float) -> void:
	if not visible:
		return
	for c: Node in _grid.get_children():
		c.queue_free()
	for h: String in ["PLAYER", "TEAM", "K", "D", "A", "SCORE", "¤", "PING"]:
		_cell(h, &"AccentLabel")
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	for e: Dictionary in sorted:
		var info: Dictionary = roster.get(int(e["playerId"]), {})
		_cell(str(info.get("name", e["playerId"])), &"ValueLabel")
		_cell("ALPHA" if int(info.get("team", 0)) == 0 else "BRAVO", &"MutedLabel")
		for k: String in ["kills", "deaths", "assists", "score", "credits", "pingMs"]:
			_cell(str(e[k]), &"ValueLabel")


func _cell(text: String, variation: StringName) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	_grid.add_child(l)
