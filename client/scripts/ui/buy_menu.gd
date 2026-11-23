## Buy menu (spec §10.4, §15.2): full-screen grid by weapon class + shields, costs, current credits
## and predicted next-round credits. Purchases are requests; the server validates (phase, zone, cost).
class_name BuyMenu
extends CanvasLayer

signal purchase(item: String)

var credits := 0
var loss_streak := 0
var _root: Control
var _credits_label: Label
var _predict_label: Label
var _buttons: Dictionary = {}  ## item -> Button
var _ability_col: VBoxContainer
var _agent := ""


func _ready() -> void:
	layer = 20
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	_root.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	margin.add_child(v)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "ARMORY"
	title.theme_type_variation = &"HeaderLarge"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_credits_label = Label.new()
	_credits_label.theme_type_variation = &"HeaderLarge"
	_predict_label = Label.new()
	_predict_label.theme_type_variation = &"MutedLabel"
	head.add_child(title)
	head.add_child(_predict_label)
	head.add_child(_credits_label)
	v.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var by_class: Dictionary = {}
	for w: Dictionary in SharedConfig.read_json("res://data/config/weapons.json")["weapons"]:
		if w["class"] == "melee":
			continue
		(by_class.get_or_add(w["class"], []) as Array).append(w)
	for cls: String in ["sidearm", "smg", "shotgun", "rifle", "sniper", "heavy"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		lbl.text = cls.to_upper() + ("S" if cls != "heavy" else "")
		lbl.theme_type_variation = &"AccentLabel"
		col.add_child(lbl)
		for w: Dictionary in by_class.get(cls, []):
			var wb := _item_button(w["id"], str(w["name"]), int(w["cost"]))
			_add_icon(wb, str(w["id"]))
			col.add_child(wb)
		cols.add_child(col)
	var shields := VBoxContainer.new()
	shields.add_theme_constant_override("separation", 8)
	var sl := Label.new()
	sl.text = "SHIELDS"
	sl.theme_type_variation = &"AccentLabel"
	shields.add_child(sl)
	for s: Dictionary in SharedConfig.read_json("res://data/config/economy.json")["shields"]:
		shields.add_child(_item_button(s["id"], str(s["name"]), int(s["cost"])))
	cols.add_child(shields)
	_ability_col = VBoxContainer.new()
	_ability_col.add_theme_constant_override("separation", 8)
	cols.add_child(_ability_col)
	var hint := Label.new()
	hint.text = "B  close    ·    purchases carry over if you survive"
	hint.theme_type_variation = &"MutedLabel"
	v.add_child(hint)


## Weapon silhouette (rendered from the model) on the right side of a buy button.
func _add_icon(b: Button, weapon_id: String) -> void:
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	icon.offset_left = -96
	icon.offset_right = -6
	icon.offset_top = 6
	icon.offset_bottom = -6
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1, 1, 1, 0.85)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	b.custom_minimum_size.x = 220
	icon.ready.connect(func() -> void: WeaponIcons.apply(icon, weapon_id), CONNECT_ONE_SHOT)


func _item_button(item: String, label: String, cost: int) -> Button:
	var b := Button.new()
	b.text = "%s\n¤ %d" % [label.to_upper(), cost]
	b.custom_minimum_size = Vector2(170, 74)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.set_meta("cost", cost)
	b.pressed.connect(func() -> void:
		Sfx.play_2d("ui", "click", -4.0)
		purchase.emit(item))
	b.mouse_entered.connect(func() -> void: Sfx.play_2d("ui", "hover", -10.0))
	_buttons[item] = b
	return b


## Agent-specific purchasable abilities (C and Q, spec §10.5).
func set_agent(agent_id: String) -> void:
	if agent_id == _agent or _ability_col == null:
		return
	_agent = agent_id
	for c: Node in _ability_col.get_children():
		c.queue_free()
	var l := Label.new()
	l.text = "ABILITIES"
	l.theme_type_variation = &"AccentLabel"
	_ability_col.add_child(l)
	for ab: Dictionary in Data.get_agent(agent_id).get("abilities", []):
		if ab["slot"] in ["C", "Q"]:
			_ability_col.add_child(_item_button("ability_%s" % ab["slot"], "%s · %s" % [ab["slot"], ab["name"]], int(ab["cost"])))


func toggle() -> void:
	visible = not visible


func close() -> void:
	visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	_credits_label.text = "   ¤ %d" % credits
	var econ: Dictionary = Data.economy
	var loss: Array = econ.get("roundLossStreak", [1900])
	_predict_label.text = "next round: win ¤%d · loss ¤%d" % [mini(9000, credits + int(econ.get("roundWin", 3000))), mini(9000, credits + int(loss[clampi(loss_streak, 0, loss.size() - 1)]))]
	for item: String in _buttons:
		var b: Button = _buttons[item]
		b.disabled = int(b.get_meta("cost")) > credits
