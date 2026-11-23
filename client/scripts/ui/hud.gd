## In-game HUD (spec §15.2). Layout is our own: bottom-centre vitals + ability bar, bottom-right
## weapon/ammo, top-centre round info, top-right killfeed, centre crosshair/hitmarker, directional
## damage arcs. All styling comes from the shared theme (type variations).
class_name Hud
extends CanvasLayer

var player: LocalPlayer
var crosshair: Crosshair
var _root: Control
var _health: Label
var _shield: Label
var _health_bar: ColorRect
var _ammo: Label
var _reserve: Label
var _weapon_name: Label
var _killfeed: VBoxContainer
var _hitmarker: Control
var _hit_t := 0.0
var _hit_kind := "body"
var _damage_arcs: Control
var _arcs: Array = []  ## [{dir: float (rad, screen space), t: float}]
var _center_msg: Label
var _msg_t := 0.0
var _timer: Label
var _score: Label
var _credits: Label
var abilities: HBoxContainer
var _fps: Label


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	crosshair = Crosshair.new()
	_root.add_child(crosshair)
	_build_vitals()
	_build_weapon()
	_build_top()
	_killfeed = VBoxContainer.new()
	_killfeed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_killfeed.position = Vector2(-520, 24)
	_killfeed.custom_minimum_size = Vector2(496, 0)
	_killfeed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_root.add_child(_killfeed)
	_hitmarker = Control.new()
	_hitmarker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hitmarker.draw.connect(_draw_hitmarker)
	_root.add_child(_hitmarker)
	_damage_arcs = Control.new()
	_damage_arcs.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_arcs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_arcs.draw.connect(_draw_arcs)
	_root.add_child(_damage_arcs)
	_center_msg = _label("", &"HeaderLarge")
	_center_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_center_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_msg.position = Vector2(-400, 220)
	_center_msg.custom_minimum_size = Vector2(800, 0)
	_root.add_child(_center_msg)
	_fps = _label("", &"MutedLabel")
	_fps.position = Vector2(8, 4)
	_root.add_child(_fps)


func _label(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_box() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"RowPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _build_vitals() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.position = Vector2(-430, -110)
	box.add_theme_constant_override("separation", 28)
	_root.add_child(box)
	var vit := VBoxContainer.new()
	vit.add_theme_constant_override("separation", 2)
	box.add_child(vit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	vit.add_child(row)
	_shield = _label("0", &"HeaderSmall")
	_shield.add_theme_color_override("font_color", Color("#8FB7D8"))
	_health = _label("100", &"TitleLabel")
	_health.add_theme_font_size_override("font_size", 64)
	row.add_child(_shield)
	row.add_child(_health)
	_health_bar = ColorRect.new()
	_health_bar.custom_minimum_size = Vector2(220, 5)
	_health_bar.color = Color("#ECE8E1")
	vit.add_child(_health_bar)
	abilities = HBoxContainer.new()
	abilities.add_theme_constant_override("separation", 10)
	box.add_child(abilities)
	for key: String in ["C", "Q", "E", "X"]:
		var p := _panel_box()
		p.custom_minimum_size = Vector2(76, 76)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var glyph := _label("◆", &"HeaderLarge")
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var k := _label(key, &"MutedLabel")
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(glyph)
		v.add_child(k)
		p.add_child(v)
		p.name = "Ability_%s" % key
		abilities.add_child(p)


func _build_weapon() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.position = Vector2(-330, -150)
	box.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(box)
	_weapon_name = _label("WASP", &"HeaderSmall")
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	_ammo = _label("12", &"TitleLabel")
	_ammo.add_theme_font_size_override("font_size", 64)
	_reserve = _label("/ 36", &"HeaderSmall")
	row.add_child(_ammo)
	row.add_child(_reserve)
	_credits = _label("¤ 800", &"MutedLabel")
	_credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_weapon_name)
	box.add_child(row)
	box.add_child(_credits)
	box.custom_minimum_size = Vector2(300, 0)


func _build_top() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-160, 18)
	top.custom_minimum_size = Vector2(320, 0)
	_root.add_child(top)
	_score = _label("", &"HeaderSmall")
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer = _label("", &"HeaderLarge")
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_timer)
	top.add_child(_score)


## Ability bar: icon glyph, key, charges as pips; X shows ult points / cost.
func set_abilities(agent_id: String, charges: Array, ult_points: int) -> void:
	var agent: Dictionary = Data.get_agent(agent_id)
	var list: Array = agent.get("abilities", [])
	for i: int in mini(4, list.size()):
		var ab: Dictionary = list[i]
		var p := abilities.get_child(i) as PanelContainer
		var v := p.get_child(0) as VBoxContainer
		var glyph := v.get_child(0) as Label
		var key := v.get_child(1) as Label
		glyph.text = str(ab["name"]).substr(0, 2).to_upper()
		var have := int(charges[i]) if i < charges.size() else 0
		if ab["slot"] == "X":
			var need := int(ab.get("ultPoints", 7))
			key.text = "X  %d/%d" % [mini(ult_points, need), need]
			p.modulate = Color(1, 1, 1, 1.0 if ult_points >= need else 0.55)
		else:
			key.text = "%s  %s" % [ab["slot"], "●".repeat(have) + "○".repeat(maxi(0, int(ab["charges"]) - have))]
			p.modulate = Color(1, 1, 1, 1.0 if have > 0 else 0.45)
		p.tooltip_text = str(ab["name"])


func set_round_info(timer_text: String, score_text: String) -> void:
	_timer.text = timer_text
	_score.text = score_text


func message(text: String, seconds: float = 2.0) -> void:
	_center_msg.text = text.to_upper()
	_msg_t = seconds


func hit(kind: String) -> void:
	_hit_kind = kind
	_hit_t = 0.28 if kind == "kill" else 0.16
	match kind:
		"head":
			Sfx.play_2d("ui", "headshot", -3.0)
		"kill":
			Sfx.play_2d("ui", "kill", -2.0)
		_:
			Sfx.play_2d("ui", "hitmarker", -6.0)


func damage_from(world_dir: Vector3) -> void:
	if player == null:
		return
	var local := player.camera.global_basis.inverse() * world_dir
	_arcs.append({"dir": atan2(local.x, -local.z), "t": 1.0})


func killfeed(killer: String, victim: String, weapon: String, headshot: bool, wallbang: bool, killer_ally: bool) -> void:
	var p := _panel_box()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var k := _label(killer, &"ValueLabel")
	k.add_theme_color_override("font_color", Color("#3FE0D0") if killer_ally else Color("#FF4655"))
	var w := _label("%s%s%s" % [weapon.to_upper(), "  ◎" if headshot else "", "  ▥" if wallbang else ""], &"MutedLabel")
	var v := _label(victim, &"ValueLabel")
	v.add_theme_color_override("font_color", Color("#FF4655") if killer_ally else Color("#3FE0D0"))
	row.add_child(k)
	row.add_child(w)
	row.add_child(v)
	p.add_child(row)
	_killfeed.add_child(p)
	if _killfeed.get_child_count() > 5:
		_killfeed.get_child(0).queue_free()
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


func _process(delta: float) -> void:
	_fps.text = "%d fps" % Engine.get_frames_per_second()
	if player != null:
		_health.text = str(int(ceil(player.health)))
		_shield.text = str(int(player.shield)) if player.shield > 0 else ""
		_health_bar.custom_minimum_size.x = 220.0 * player.health / 100.0
		_health_bar.color = Color("#ECE8E1") if player.health > 30 else Color("#FF4655")
		_credits.text = "¤ %d" % player.credits
		var entry: Dictionary = player.current()
		if not entry.is_empty():
			var def: Dictionary = entry["def"]
			var st: SimWeapons.State = entry["st"]
			_weapon_name.text = str(def["name"]).to_upper()
			_ammo.text = str(st.ammo) if int(def["magazine"]) > 0 else "—"
			_reserve.text = "/ %d" % st.reserve if int(def["magazine"]) > 0 else ""
			_ammo.add_theme_color_override("font_color", Color("#FF4655") if st.ammo <= int(def["magazine"]) / 4 and int(def["magazine"]) > 0 else Color("#ECE8E1"))
			var spread := SimWeapons.current_spread(def, st, SimMovement.speed_fraction(player.move, float(def["runSpeed"])), 0.2, player.move.crouch > 0.5, not player.move.grounded, player.vm_anim.ads > 0.5)
			crosshair.spread_px = clampf(spread * 6.0, 0.0, 60.0)
			crosshair.hidden_for_scope = def.get("ads") is Dictionary and def["ads"].get("scoped", false) and player.vm_anim.ads > 0.6
	_hit_t = maxf(0.0, _hit_t - delta)
	_hitmarker.queue_redraw()
	for a: Dictionary in _arcs:
		a["t"] = float(a["t"]) - delta * 0.8
	_arcs = _arcs.filter(func(a: Dictionary) -> bool: return float(a["t"]) > 0.0)
	_damage_arcs.queue_redraw()
	_msg_t = maxf(0.0, _msg_t - delta)
	_center_msg.modulate.a = clampf(_msg_t * 3.0, 0.0, 1.0)


func _draw_hitmarker() -> void:
	if _hit_t <= 0.0:
		return
	var c := _hitmarker.size * 0.5
	var col := Color("#FF4655") if _hit_kind == "kill" else (Color("#FFD37A") if _hit_kind == "head" else Color("#ECE8E1"))
	var r0 := 9.0 if _hit_kind != "kill" else 11.0
	var r1 := r0 + (8.0 if _hit_kind == "body" else 12.0)
	var w := 2.0 if _hit_kind == "body" else 3.0
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var n := d.normalized()
		draw_line_on(_hitmarker, c + n * r0, c + n * r1, Color(col, minf(1.0, _hit_t * 8.0)), w)
	if _hit_kind == "head":
		# Distinct crit flash for headshots.
		_hitmarker.draw_arc(c, r1 + 6.0, 0, TAU, 32, Color(col, _hit_t * 3.0), 2.0)


static func draw_line_on(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(a, b, Color(0, 0, 0, col.a * 0.6), w + 2.0)
	ci.draw_line(a, b, col, w)


func _draw_arcs() -> void:
	var c := _damage_arcs.size * 0.5
	for a: Dictionary in _arcs:
		var ang := float(a["dir"]) - PI * 0.5
		_damage_arcs.draw_arc(c, 150.0, ang - 0.35, ang + 0.35, 24, Color(1.0, 0.27, 0.33, float(a["t"]) * 0.85), 6.0)
