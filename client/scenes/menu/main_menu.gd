## Main menu (spec §15.3): 3D showroom with the selected agent on a lit plinth (idle + camera drift)
## and the front-end screens: PLAY (modes, party, queue, agent select), AGENTS, COLLECTION, CAREER,
## SETTINGS (video/audio/controls/crosshair/accessibility). All styling comes from the shared theme.
extends Node3D

const MODES := [["unrated", "UNRATED", "Standard rules, no rank on the line."], ["competitive", "COMPETITIVE", "Ranked. Registered accounts only."], ["custom", "CUSTOM", "Private lobby rules (bots fill empty slots)."], ["range", "THE RANGE", "Offline training facility."], ["quick", "QUICK PLAY", "Direct join to the dev server (no account needed)."]]

var _ui: Control
var _content: PanelContainer
var _status: Label
var _name_label: Label
var _showroom_rig: AgentRig
var _cam: Camera3D
var _t := 0.0
var _queue_mode := ""
var _queue_timer: Timer
var _select_overlay: Control
var _select_state: Dictionary = {}
var _agent := "kestrel"
var _key_wait := ""  ## action awaiting a rebind key


func _ready() -> void:
	_agent = str(Settings.get_value("gameplay", "agent"))
	_build_showroom()
	_build_ui()
	_show_tab("PLAY")
	Sfx.play_2d("music", "menu_theme", -10.0, "Music")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = "CONNECTING TO PRISM NETWORK…"
	var ok: bool = await Api.ensure_session()
	_status.text = ("SIGNED IN  ·  %s" % Api.display_name()) if ok else "OFFLINE  ·  %s  (The Range and Quick Play still work)" % Api.last_error
	_name_label.text = Api.display_name()
	_queue_timer = Timer.new()
	_queue_timer.wait_time = 1.0
	_queue_timer.timeout.connect(_poll_queue)
	add_child(_queue_timer)


# ------------------------------------------------------------------ 3D showroom

func _build_showroom() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0F1923")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#2A3A55")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color("#1A2A3A")
	env.fog_density = 0.03
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#FFE0B8")
	key.light_energy = 1.3
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#C8D6FF")
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(-10, 160, 0)
	add_child(fill)
	for spec: Array in [[Vector3(-2.2, 2.2, -1.5), Color("#3FE0D0")], [Vector3(2.4, 1.8, -1.2), Color("#FF4655")]]:
		var rim := OmniLight3D.new()
		rim.position = spec[0]
		rim.light_color = spec[1]
		rim.light_energy = 2.2
		rim.omni_range = 6.0
		add_child(rim)
	# Plinth: stepped chamfered discs with an emissive ring.
	var k := MeshKit.new()
	k.cylinder(1.3, 0.18, Vector3(0, 0.09, 0), 48, 0.04)
	k.cylinder(1.05, 0.1, Vector3(0, 0.23, 0), 48, 0.03)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#2A3440")
	pm.roughness = 0.35
	pm.metallic = 0.4
	var plinth := MeshInstance3D.new()
	plinth.mesh = k.commit(pm)
	add_child(plinth)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.07
	tm.outer_radius = 1.1
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.emission_enabled = true
	rm.emission = Color("#FF4655")
	rm.emission_energy_multiplier = 3.0
	rm.albedo_color = Color("#FF4655")
	ring.material_override = rm
	ring.position.y = 0.28
	add_child(ring)
	_cam = Camera3D.new()
	_cam.fov = 40
	add_child(_cam)
	_set_showroom_agent(_agent)


func _set_showroom_agent(agent_id: String) -> void:
	if _showroom_rig != null:
		_showroom_rig.queue_free()
	_showroom_rig = AgentLooks.build(agent_id)
	_showroom_rig.position = Vector3(0, 0.28, 0)
	_showroom_rig.rotation_degrees.y = 165
	add_child(_showroom_rig)
	var anim := AgentAnimator.new()
	anim.setup(_showroom_rig)
	anim.attach_weapon(WeaponBuilder.build("saber"))
	anim.aim_pitch = -0.35
	_showroom_rig.add_child(anim)


func _process(delta: float) -> void:
	_t += delta
	# Subtle camera drift (spec §15.3).
	_cam.position = Vector3(-1.35 + sin(_t * 0.15) * 0.2, 1.35 + sin(_t * 0.11) * 0.05, 4.1 + cos(_t * 0.13) * 0.15)
	_cam.look_at(Vector3(-0.95, 1.0, 0))
	if _select_overlay != null and _select_overlay.visible:
		_update_select_timer()


# ------------------------------------------------------------------ UI scaffold

func _lbl(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _btn(text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.theme_type_variation = &"PrimaryButton"
	b.pressed.connect(func() -> void:
		Sfx.play_2d("ui", "click", -4.0)
		cb.call())
	b.mouse_entered.connect(func() -> void: Sfx.play_2d("ui", "hover", -12.0))
	return b


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	# Top navigation bar.
	var nav := PanelContainer.new()
	nav.set_anchors_preset(Control.PRESET_TOP_WIDE)
	nav.custom_minimum_size = Vector2(0, 72)
	_ui.add_child(nav)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 26)
	nav.add_child(nh)
	nh.add_child(_lbl("BREACHPOINT", &"HeaderLarge"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(spacer)
	for tab: String in ["PLAY", "AGENTS", "COLLECTION", "CAREER", "SETTINGS"]:
		var b := _btn(tab, func() -> void: _show_tab(tab), tab == "PLAY")
		b.flat = tab != "PLAY"
		nh.add_child(b)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(sp2)
	_name_label = _lbl("", &"ValueLabel")
	nh.add_child(_name_label)
	# Left content panel (the agent stands on the right in the 3D view).
	_content = PanelContainer.new()
	_content.position = Vector2(64, 112)
	_content.custom_minimum_size = Vector2(760, 820)
	_ui.add_child(_content)
	_status = _lbl("", &"MutedLabel")
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(64, -48)
	_ui.add_child(_status)


func _clear() -> VBoxContainer:
	for c: Node in _content.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_content.add_child(v)
	return v


func _show_tab(tab: String) -> void:
	match tab:
		"PLAY":
			_tab_play()
		"AGENTS":
			_tab_agents()
		"COLLECTION":
			_tab_collection()
		"CAREER":
			_tab_career()
		"SETTINGS":
			_tab_settings()


# ------------------------------------------------------------------ PLAY

func _tab_play() -> void:
	var v := _clear()
	v.add_child(_lbl("PLAY", &"HeaderLarge"))
	for m: Array in MODES:
		var row := HBoxContainer.new()
		var b := _btn(str(m[1]), func() -> void: _start_mode(str(m[0])), m[0] == "unrated")
		b.custom_minimum_size = Vector2(240, 0)
		row.add_child(b)
		var d := _lbl(str(m[2]), &"MutedLabel")
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(d)
		v.add_child(row)
	v.add_child(HSeparator.new())
	v.add_child(_lbl("PARTY", &"HeaderSmall"))
	var inv := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Name#1234"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv.add_child(name_edit)
	inv.add_child(_btn("INVITE", func() -> void:
		var r: Dictionary = await Api.request("POST", "/party/invite", {"nameTag": name_edit.text})
		_status.text = "Invite sent." if r["ok"] else "Invite failed: %s" % Api.last_error))
	inv.add_child(_btn("READY", func() -> void: await Api.request("POST", "/party/ready", {"ready": true})))
	inv.add_child(_btn("LEAVE", func() -> void: await Api.request("POST", "/party/leave", {})))
	v.add_child(inv)
	var invites_btn := _btn("CHECK INVITES", func() -> void:
		var r: Dictionary = await Api.request("GET", "/party/invites")
		if r["ok"] and r["body"] is Array and not (r["body"] as Array).is_empty():
			await Api.request("POST", "/party/join", {"partyId": (r["body"] as Array)[0]})
			_status.text = "Joined party."
		else:
			_status.text = "No invites.")
	v.add_child(invites_btn)


func _start_mode(mode: String) -> void:
	match mode:
		"range":
			Game.goto("range")
		"quick":
			Net.token = Api.access_token
			Game.goto("online")
		_:
			if not Api.online:
				_status.text = "Matchmaking needs the API server (npm run server:dev with DATABASE_URL/REDIS_URL)."
				return
			var r: Dictionary = await Api.request("POST", "/queue", {"mode": mode})
			if not r["ok"]:
				_status.text = "Queue failed: %s" % Api.last_error
				return
			_queue_mode = mode
			_queue_timer.start()
			_status.text = "SEARCHING  ·  %s" % mode.to_upper()


func _poll_queue() -> void:
	var r: Dictionary = await Api.request("GET", "/queue/status")
	if not r["ok"]:
		return
	var st: Dictionary = r["body"]
	match str(st.get("state", "idle")):
		"queued":
			_status.text = "SEARCHING  ·  %s  ·  %d:%02d   (ESC to cancel)" % [_queue_mode.to_upper(), int(st["waitSec"]) / 60, int(st["waitSec"]) % 60]
		"agent_select":
			_select_state = st
			_show_select()
		"ready":
			_queue_timer.stop()
			Sfx.play_2d("ui", "lockin", -2.0)
			Net.token = Api.access_token
			Net.pending_ticket = str(st["ticket"])
			Settings.set_value("net", "server_url", str(st["server"]))
			Game.goto("online")


# ------------------------------------------------------------------ agent select (spec §15.3)

func _show_select() -> void:
	if _select_overlay == null:
		_select_overlay = Control.new()
		_select_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ui.add_child(_select_overlay)
	_select_overlay.visible = true
	for c: Node in _select_overlay.get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_select_overlay.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 18)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 60)
	margin.add_child(v)
	_select_overlay.add_child(margin)
	var head := HBoxContainer.new()
	head.add_child(_lbl("SELECT AGENT  ·  %s" % str(_select_state.get("map", "")).to_upper(), &"HeaderLarge"))
	var timer := _lbl("", &"TitleLabel")
	timer.name = "SelectTimer"
	timer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(timer)
	v.add_child(head)
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 12)
	for p: Dictionary in _select_state.get("roster", []):
		team_row.add_child(_lbl("%s  %s%s" % [p["name"], str(p["agent"]).to_upper() if p["agent"] != "" else "…", "  ✓" if p["locked"] else ""], &"ValueLabel"))
	v.add_child(team_row)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	var taken := {}
	for p: Dictionary in _select_state.get("roster", []):
		if p["locked"]:
			taken[p["agent"]] = true
	for a: Dictionary in Data.agents.values():
		grid.add_child(_agent_card(a, taken.has(a["id"])))
	var lock := _btn("LOCK IN", func() -> void:
		var r: Dictionary = await Api.request("POST", "/select", {"agent": _agent, "lock": true})
		if r["ok"]:
			Sfx.play_2d("ui", "lockin", 0.0)
		else:
			_status.text = "Lock failed: %s" % Api.last_error, true)
	lock.custom_minimum_size = Vector2(320, 64)
	v.add_child(lock)


func _agent_card(a: Dictionary, taken: bool) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(380, 150)
	var sb := StyleBoxFlat.new()
	var col := Color(str(a["signatureColor"]))
	sb.bg_color = col.darkened(0.7) if not taken else Color(0.1, 0.1, 0.12)
	sb.border_color = col if str(a["id"]) == _agent else Color(col, 0.35)
	sb.set_border_width_all(3 if str(a["id"]) == _agent else 1)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_child(_lbl("%s  ·  %s" % [a["name"], str(a["role"]).to_upper()], &"HeaderSmall"))
	for ab: Dictionary in a["abilities"]:
		v.add_child(_lbl("%s  %s" % [ab["slot"], ab["name"]], &"MutedLabel"))
	p.add_child(v)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.is_pressed() and not taken:
			_agent = str(a["id"])
			Settings.set_value("gameplay", "agent", _agent)
			_set_showroom_agent(_agent)
			await Api.request("POST", "/select", {"agent": _agent, "lock": false})
			_poll_queue())
	if taken:
		p.modulate = Color(1, 1, 1, 0.4)
	return p


func _update_select_timer() -> void:
	var t := _select_overlay.find_child("SelectTimer", true, false) as Label
	if t != null:
		var left := maxf(0.0, (float(_select_state.get("deadline", 0)) - Time.get_unix_time_from_system() * 1000.0) / 1000.0)
		t.text = "%d" % int(left)


# ------------------------------------------------------------------ AGENTS / COLLECTION / CAREER

func _tab_agents() -> void:
	var v := _clear()
	v.add_child(_lbl("AGENTS", &"HeaderLarge"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for a: Dictionary in Data.agents.values():
		var card := _agent_card(a, false)
		card.custom_minimum_size = Vector2(350, 140)
		grid.add_child(card)


func _tab_collection() -> void:
	var v := _clear()
	v.add_child(_lbl("COLLECTION", &"HeaderLarge"))
	v.add_child(_lbl("Weapon skins — PRISM Standard, Lumen and Hazard lines. Pick one to preview on the plinth.", &"MutedLabel"))
	var grid := GridContainer.new()
	grid.columns = 3
	v.add_child(grid)
	for w: Dictionary in Data.weapons.values():
		if w["class"] == "melee":
			continue
		for skin: String in ["standard", "lumen", "hazard"]:
			grid.add_child(_btn("%s · %s" % [str(w["name"]).to_upper(), skin.to_upper()], func() -> void: _preview_weapon(str(w["id"]), skin)))


func _preview_weapon(weapon_id: String, skin: String) -> void:
	if _showroom_rig != null:
		_showroom_rig.visible = false
	var old := get_node_or_null("WeaponPreview")
	if old != null:
		old.queue_free()
	var piv := Node3D.new()
	piv.name = "WeaponPreview"
	piv.position = Vector3(0.6, 1.2, 0.6)
	add_child(piv)
	var model := WeaponBuilder.build(weapon_id, WeaponSkins.get_skin(skin, weapon_id))
	model.scale = Vector3.ONE * 2.2
	piv.add_child(model)
	var tw := create_tween().set_loops()
	tw.tween_property(piv, "rotation:y", TAU, 8.0).from(0.0)


func _tab_career() -> void:
	var v := _clear()
	v.add_child(_lbl("CAREER", &"HeaderLarge"))
	var prof: Dictionary = Api.profile
	var rating: Dictionary = prof.get("rating", {}) if prof.get("rating") is Dictionary else {}
	v.add_child(_lbl("%s   ·   LEVEL %s   ·   RANK %s" % [Api.display_name(), str(prof.get("level", 1)), str(rating.get("tier", "Unranked")).to_upper()], &"HeaderSmall"))
	var list := VBoxContainer.new()
	v.add_child(list)
	if not Api.online:
		list.add_child(_lbl("Offline — match history needs the API server.", &"MutedLabel"))
		return
	var r: Dictionary = await Api.request("GET", "/matches")
	if not r["ok"] or not (r["body"] is Array) or (r["body"] as Array).is_empty():
		list.add_child(_lbl("No matches yet.", &"MutedLabel"))
		return
	for m: Dictionary in r["body"]:
		var won: bool = m["winner"] != null and int(m["winner"]) == int(m["team"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.add_child(_lbl("%s  %s  %s  ·  %d-%d  ·  %s  ·  %d/%d/%d" % ["VICTORY" if won else "DEFEAT", str(m["mode"]).to_upper(), str(m["map"]).to_upper(), int(m["score_a"]), int(m["score_b"]), str(m["agent"]).to_upper(), int(m["kills"]), int(m["deaths"]), int(m["assists"])], &"ValueLabel"))
		# Replays are kept 14 days on the server (spec §14.3/14.4).
		var watch := Button.new()
		watch.text = "REPLAY"
		var match_id := str(m["id"])
		watch.pressed.connect(func() -> void:
			watch.disabled = true
			watch.text = "LOADING…"
			var bytes := await Api.download("/replays/%s" % match_id.uri_encode())
			if bytes.is_empty():
				watch.text = "UNAVAILABLE"
				return
			Game.pending_replay = bytes
			Game.goto("replay"))
		row.add_child(watch)
		list.add_child(row)


# ------------------------------------------------------------------ SETTINGS (spec §15.3)

func _tab_settings() -> void:
	var v := _clear()
	v.add_child(_lbl("SETTINGS", &"HeaderLarge"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 700)
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	body.add_child(_lbl("VIDEO", &"AccentLabel"))
	body.add_child(_option("Quality tier", ["auto", "low", "medium", "high", "ultra"], str(Settings.get_value("video", "tier")), func(s: String) -> void: Settings.set_value("video", "tier", s)))
	body.add_child(_slider("Field of view", 80, 103, 1, float(Settings.get_value("video", "fov")), func(x: float) -> void: Settings.set_value("video", "fov", x)))
	body.add_child(_lbl("AUDIO", &"AccentLabel"))
	for key: String in ["master", "sfx", "voice", "music"]:
		body.add_child(_slider(key.capitalize(), 0, 1, 0.01, float(Settings.get_value("audio", key)), func(x: float) -> void: Settings.set_value("audio", key, x)))
	body.add_child(_lbl("CONTROLS", &"AccentLabel"))
	body.add_child(_slider("Sensitivity", 0.05, 2.0, 0.01, float(Settings.get_value("controls", "sensitivity")), func(x: float) -> void: Settings.set_value("controls", "sensitivity", x)))
	body.add_child(_slider("ADS sensitivity multiplier", 0.2, 2.0, 0.01, float(Settings.get_value("controls", "ads_multiplier")), func(x: float) -> void: Settings.set_value("controls", "ads_multiplier", x)))
	body.add_child(_toggle("Invert Y", bool(Settings.get_value("controls", "invert_y")), func(b: bool) -> void: Settings.set_value("controls", "invert_y", b)))
	body.add_child(_toggle("Raw input", bool(Settings.get_value("controls", "raw_input")), func(b: bool) -> void: Settings.set_value("controls", "raw_input", b)))
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "jump", "crouch", "walk", "reload", "use", "ability_c", "ability_q", "ability_e", "ability_x"]:
		var row := HBoxContainer.new()
		var n := _lbl(action.replace("_", " ").capitalize(), &"")
		n.custom_minimum_size = Vector2(260, 0)
		row.add_child(n)
		var ev: Array = InputMap.action_get_events(action)
		var b := _btn(ev[0].as_text().replace(" (Physical)", "") if not ev.is_empty() else "—", func() -> void:
			_key_wait = action
			_status.text = "Press a key for %s…" % action)
		row.add_child(b)
		body.add_child(row)
	body.add_child(_lbl("CROSSHAIR", &"AccentLabel"))
	body.add_child(_crosshair_editor())
	body.add_child(_lbl("ACCESSIBILITY", &"AccentLabel"))
	body.add_child(_option("Colour-blind mode", ["off", "deuteranopia", "protanopia", "tritanopia"], str(Settings.get_value("accessibility", "colorblind")), func(s: String) -> void: Settings.set_value("accessibility", "colorblind", s)))
	body.add_child(_toggle("Reduced camera shake", bool(Settings.get_value("accessibility", "reduced_shake")), func(b: bool) -> void: Settings.set_value("accessibility", "reduced_shake", b)))
	body.add_child(_slider("Subtitle size", 0.75, 2.0, 0.05, float(Settings.get_value("accessibility", "subtitle_scale")), func(x: float) -> void: Settings.set_value("accessibility", "subtitle_scale", x)))
	body.add_child(_toggle("Viewmodel sway", bool(Settings.get_value("gameplay", "viewmodel_sway")), func(b: bool) -> void: Settings.set_value("gameplay", "viewmodel_sway", b)))
	body.add_child(_toggle("Strafe tilt", bool(Settings.get_value("gameplay", "strafe_tilt")), func(b: bool) -> void: Settings.set_value("gameplay", "strafe_tilt", b)))
	body.add_child(_btn("SYSTEMS CHECK", func() -> void: Game.goto("boot")))


func _unhandled_input(event: InputEvent) -> void:
	if _key_wait != "" and event is InputEventKey and event.is_pressed():
		Settings.set_value("bindings", _key_wait, [(event as InputEventKey).physical_keycode])
		Settings.apply_bindings()
		_status.text = "Bound %s." % _key_wait
		_key_wait = ""
		_tab_settings()
	elif event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE and _queue_mode != "":
		_queue_mode = ""
		_queue_timer.stop()
		await Api.request("DELETE", "/queue")
		_status.text = "Queue cancelled."


func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _lbl(label, &"")
	l.custom_minimum_size = Vector2(260, 0)
	row.add_child(l)
	return row


func _slider(label: String, lo: float, hi: float, step: float, value: float, cb: Callable) -> Control:
	var row := _row(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(300, 24)
	var val := _lbl(str(snappedf(value, step)), &"MutedLabel")
	s.value_changed.connect(func(x: float) -> void:
		val.text = str(snappedf(x, step))
		cb.call(x))
	row.add_child(s)
	row.add_child(val)
	return row


func _toggle(label: String, value: bool, cb: Callable) -> Control:
	var row := _row(label)
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(func(b: bool) -> void: cb.call(b))
	row.add_child(c)
	return row


func _option(label: String, options: Array, value: String, cb: Callable) -> Control:
	var row := _row(label)
	var o := OptionButton.new()
	for i: int in options.size():
		o.add_item(str(options[i]).capitalize())
		if options[i] == value:
			o.select(i)
	o.item_selected.connect(func(i: int) -> void: cb.call(str(options[i])))
	row.add_child(o)
	return row


func _crosshair_editor() -> Control:
	var v := VBoxContainer.new()
	var prof: Dictionary = Settings.get_value("crosshair", "profile") if Settings.get_value("crosshair", "profile") is Dictionary else Crosshair.DEFAULT.duplicate()
	var preview_bg := ColorRect.new()
	preview_bg.color = Color("#6E7F8C")
	preview_bg.custom_minimum_size = Vector2(260, 140)
	var preview := Crosshair.new()
	preview.profile = prof
	preview_bg.add_child(preview)
	v.add_child(preview_bg)
	var save := func() -> void:
		Settings.set_value("crosshair", "profile", prof)
		preview.queue_redraw()
	var cp := ColorPickerButton.new()
	cp.color = Color(str(prof["color"]))
	cp.custom_minimum_size = Vector2(80, 32)
	cp.color_changed.connect(func(c: Color) -> void:
		prof["color"] = "#" + c.to_html(false)
		save.call())
	var crow := _row("Colour")
	crow.add_child(cp)
	v.add_child(crow)
	for key: String in ["outline", "dot", "inner", "outer", "movement_error", "firing_error"]:
		v.add_child(_toggle(key.replace("_", " ").capitalize(), bool(prof[key]), func(b: bool) -> void:
			prof[key] = b
			save.call()))
	for spec: Array in [["inner_length", 0, 20], ["inner_thickness", 1, 10], ["inner_offset", 0, 20], ["inner_opacity", 0, 1], ["outer_length", 0, 20], ["outer_offset", 0, 40], ["dot_size", 1, 8]]:
		var key2: String = spec[0]
		v.add_child(_slider(key2.replace("_", " ").capitalize(), spec[1], spec[2], 0.05 if float(spec[2]) <= 1.0 else 1.0, float(prof[key2]), func(x: float) -> void:
			prof[key2] = x
			save.call()))
	var code := LineEdit.new()
	code.text = preview.export_code()
	code.custom_minimum_size = Vector2(500, 0)
	var crow2 := _row("Code")
	crow2.add_child(code)
	crow2.add_child(_btn("IMPORT", func() -> void:
		if preview.import_code(code.text):
			prof.merge(preview.profile, true)
			save.call()))
	v.add_child(crow2)
	return v
