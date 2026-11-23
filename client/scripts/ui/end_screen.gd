## End-of-match screen (spec §15): VICTORY / DEFEAT, MVP card, per-player stats by team and a round
## timeline (each round coloured by winner, with how it was won). Built from the RoundEnd messages
## and the last Scoreboard the client received.
class_name EndScreen
extends CanvasLayer

signal leave

const REASON_ICON := {"elimination": "✕", "time": "◷", "detonated": "✹", "defused": "◇"}


func _ready() -> void:
	layer = 30
	visible = false


func show_result(won: bool, my_team: int, rounds: Array, entries: Array, roster: Dictionary) -> void:
	for c: Node in get_children():
		c.queue_free()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.07, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.custom_minimum_size = Vector2(1100, 0)
	v.position = Vector2(-550, -330)
	v.add_theme_constant_override("separation", 18)
	add_child(v)
	var title := Label.new()
	title.text = "VICTORY" if won else "DEFEAT"
	title.theme_type_variation = &"HeaderLarge"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color("#3FE0D0") if won else Color("#FF4655"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(_timeline(rounds, my_team))
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	if not sorted.is_empty():
		v.add_child(_mvp(sorted[0], roster))
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 30)
	v.add_child(teams)
	for team: int in [my_team, 1 - my_team]:
		teams.add_child(_team_table(team, team == my_team, sorted, roster))
	var back := Button.new()
	back.text = "MAIN MENU"
	back.custom_minimum_size = Vector2(240, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: leave.emit())
	v.add_child(back)


func _timeline(rounds: Array, my_team: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	for r: Dictionary in rounds:
		var ours := int(r["winnerTeam"]) == my_team
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#3FE0D0") if ours else Color("#FF4655")
		sb.bg_color.a = 0.85
		p.add_theme_stylebox_override("panel", sb)
		p.custom_minimum_size = Vector2(34, 40)
		p.tooltip_text = "Round %d: %s" % [int(r["round"]), str(r["reason"])]
		var l := Label.new()
		l.text = "%d\n%s" % [int(r["round"]), REASON_ICON.get(str(r["reason"]), "•")]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color("#0B0E14"))
		p.add_child(l)
		row.add_child(p)
	return row


func _mvp(e: Dictionary, roster: Dictionary) -> Control:
	var info: Dictionary = roster.get(int(e["playerId"]), {})
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	p.add_child(h)
	var tag := Label.new()
	tag.text = "MATCH MVP"
	tag.theme_type_variation = &"AccentLabel"
	h.add_child(tag)
	var n := Label.new()
	n.text = "%s  ·  %s" % [str(info.get("name", e["playerId"])), str(info.get("agent", "")).to_upper()]
	n.theme_type_variation = &"HeaderSmall"
	h.add_child(n)
	var s := Label.new()
	s.text = "%d / %d / %d   ·   %d PTS" % [int(e["kills"]), int(e["deaths"]), int(e["assists"]), int(e["score"])]
	s.theme_type_variation = &"ValueLabel"
	h.add_child(s)
	return p


func _team_table(team: int, mine: bool, sorted: Array, roster: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Label.new()
	head.text = "YOUR TEAM" if mine else "ENEMY TEAM"
	head.theme_type_variation = &"AccentLabel"
	head.add_theme_color_override("font_color", Color("#3FE0D0") if mine else Color("#FF4655"))
	col.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 20)
	col.add_child(grid)
	for h: String in ["PLAYER", "AGENT", "K", "D", "A", "SCORE"]:
		grid.add_child(_cell(h, &"MutedLabel"))
	for e: Dictionary in sorted:
		var info: Dictionary = roster.get(int(e["playerId"]), {})
		if int(info.get("team", -1)) != team:
			continue
		grid.add_child(_cell(str(info.get("name", e["playerId"])), &"ValueLabel"))
		grid.add_child(_cell(str(info.get("agent", "")).to_upper(), &"MutedLabel"))
		for k: String in ["kills", "deaths", "assists", "score"]:
			grid.add_child(_cell(str(e[k]), &"ValueLabel"))
	return col


func _cell(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l
