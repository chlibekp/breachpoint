## Replay viewer (spec §14.4): plays a server .bpr replay on its map with a free camera, player POV
## and timeline scrubbing. Source: `Game.pending_replay` (downloaded from the Career tab) or
## `-- --replay=<path.bpr> [--replay-tick=N] [--pov=<index>]` for QA captures.
## Controls: Space play/pause · ←/→ ±5 s · 1–4 speed · Tab next POV · F free camera ·
## free camera: hold right mouse to look, WASD/QE move, Shift fast · Esc exit.
extends Node3D

const SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0]

var replay: ReplayFile
var map: MapRuntime
var camera: Camera3D
var players: Dictionary = {}  ## playerId -> RemotePlayer
var roster: Dictionary = {}  ## playerId -> {name, team, agent}
var weapon_ids: Array = []
var cur_tick := 0.0
var playing := true
var speed_i := 1
var pov_id := -1  ## -1 = free camera
var _free_yaw := 0.0
var _free_pitch := -0.3
var _kill_frames := PackedInt32Array()
var _phase_frames := PackedInt32Array()
var _charge_frames := PackedInt32Array()
var _charge_model: MeshInstance3D
var _eye := 1.62
var _eye_crouch := 1.05
var _snap_cache: Dictionary = {}  ## snapshot index -> decoded message (small LRU)
var _snap_order: Array[int] = []

var _ui: CanvasLayer
var _timeline: HSlider
var _time_label: Label
var _info_label: Label
var _round_label: Label
var _feed: VBoxContainer
var _play_btn: Button
var _scrubbing := false


func _ready() -> void:
	var args := Game.parse_user_args(OS.get_cmdline_user_args())
	var bytes := Game.pending_replay
	if args.has("replay"):
		bytes = FileAccess.get_file_as_bytes(str(args["replay"]))
	replay = ReplayFile.from_gzip(bytes)
	if replay.error != "":
		push_warning("replay: %s" % replay.error)
		_build_ui()
		_info_label.text = "Could not open replay: %s" % replay.error
		return
	for w: Dictionary in SharedConfig.read_json("res://data/config/weapons.json")["weapons"]:
		weapon_ids.append(w["id"])
	var mv: Dictionary = SharedConfig.read_json("res://data/config/movement.json")["capsule"]
	_eye = float(mv["eyeHeight"])
	_eye_crouch = float(mv["crouchEyeHeight"])
	var map_id := str(replay.header.get("map", "solstice"))
	map = (load("res://scenes/maps/%s.tscn" % map_id) as PackedScene).instantiate() as MapRuntime
	add_child(map)
	for i: int in replay.frames_of("MatchState"):
		for e: Dictionary in replay.message(i)["roster"]:
			roster[int(e["playerId"])] = e
	_kill_frames = replay.frames_of("Kill")
	_phase_frames = replay.frames_of("RoundPhase")
	_charge_frames = replay.frames_of("ChargeState")
	camera = Camera3D.new()
	camera.fov = float(Settings.get_value("video", "fov"))
	camera.current = true
	add_child(camera)
	camera.position = Vector3(0, 40, 60)
	_free_pitch = -0.6
	cur_tick = float(replay.first_tick())
	if args.has("replay-tick"):
		cur_tick = clampf(float(args["replay-tick"]), replay.first_tick(), replay.last_tick())
	_build_ui()
	if args.has("pov"):
		# --pov=N: the Nth player by id (ids are server-assigned, bots start high).
		_apply_tick()
		var ids: Array = players.keys()
		ids.sort()
		if not ids.is_empty():
			pov_id = ids[clampi(int(args["pov"]), 0, ids.size() - 1)]
	_info_label.text = "%s  ·  %s  ·  %s" % [str(replay.header.get("map", "?")).to_upper(), str(replay.header.get("mode", "?")).to_upper(), str(replay.header.get("matchId", ""))]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ playback

func _process(delta: float) -> void:
	if replay == null or replay.error != "":
		return
	if playing and not _scrubbing:
		cur_tick += delta * 64.0 * SPEEDS[speed_i]
		if cur_tick >= replay.last_tick():
			cur_tick = replay.last_tick()
			playing = false
	_apply_tick()
	_update_camera(delta)
	_update_ui()


func _snapshot(i: int) -> Dictionary:
	if _snap_cache.has(i):
		return _snap_cache[i]
	var msg := replay.message(replay.snapshot_frames[i])
	_snap_cache[i] = msg
	_snap_order.append(i)
	if _snap_order.size() > 8:
		_snap_cache.erase(_snap_order.pop_front())
	return msg


func _apply_tick() -> void:
	var ia := replay.snapshot_at(cur_tick)
	var ib := mini(ia + 1, replay.snapshot_ticks.size() - 1)
	var a := _snapshot(ia)
	var b := _snapshot(ib)
	var in_b: Dictionary = {}
	for st: Dictionary in b["players"]:
		in_b[int(st["playerId"])] = st
	for st: Dictionary in a["players"]:
		var id := int(st["playerId"])
		var rp := _player(id)
		rp.buffer.clear()
		rp.push(int(a["tick"]), st)
		if in_b.has(id):
			rp.push(int(b["tick"]), in_b[id])
		rp.render_at(cur_tick, weapon_ids)
		if id == pov_id:
			rp.visible = false
	_apply_charge()


func _player(id: int) -> RemotePlayer:
	if players.has(id):
		return players[id]
	var info: Dictionary = roster.get(id, {"name": "Player %d" % id, "team": 0, "agent": "kestrel"})
	var rp := RemotePlayer.new()
	add_child(rp)
	# Spectator view: team A reads as "ally" colours, team B as enemy (names shown for both).
	rp.setup(id, int(info["team"]), str(info["agent"]), str(info["name"]), int(info["team"]) == 0)
	players[id] = rp
	return rp


func _latest(frames: PackedInt32Array) -> int:
	var found := -1
	for i: int in frames:
		if replay.ticks[i] > int(cur_tick):
			break
		found = i
	return found


func _apply_charge() -> void:
	var i := _latest(_charge_frames)
	var planted := false
	var pos := Vector3.ZERO
	if i >= 0:
		var m := replay.message(i)
		planted = int(m["state"]) == 3
		pos = m["pos"]
	if planted and _charge_model == null:
		_charge_model = ChargeModel.build(true)
		add_child(_charge_model)
	if _charge_model != null:
		_charge_model.visible = planted
		_charge_model.position = pos


# ------------------------------------------------------------------ camera

func _update_camera(delta: float) -> void:
	if pov_id >= 0 and players.has(pov_id):
		var rp: RemotePlayer = players[pov_id]
		camera.global_position = rp.global_position + Vector3(0, lerpf(_eye, _eye_crouch, rp.crouch), 0)
		camera.rotation = Vector3(rp.pitch, rp.yaw, 0)
		return
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S):
		dir.z += 1
	if Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_E):
		dir.y += 1
	if Input.is_physical_key_pressed(KEY_Q):
		dir.y -= 1
	var fast := 3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	camera.rotation = Vector3(_free_pitch, _free_yaw, 0)
	camera.position += camera.global_basis * dir * 12.0 * fast * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and pov_id < 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := event as InputEventMouseMotion
		_free_yaw -= mm.relative.x * 0.004
		_free_pitch = clampf(_free_pitch - mm.relative.y * 0.004, -1.5, 1.5)
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		match (event as InputEventKey).physical_keycode:
			KEY_SPACE:
				_toggle_play()
			KEY_LEFT:
				_seek(cur_tick - 5 * 64)
			KEY_RIGHT:
				_seek(cur_tick + 5 * 64)
			KEY_1, KEY_2, KEY_3, KEY_4:
				speed_i = (event as InputEventKey).physical_keycode - KEY_1
			KEY_TAB:
				_next_pov()
			KEY_F:
				_free_camera()
			KEY_ESCAPE:
				Game.goto("menu")


func _next_pov() -> void:
	var ids: Array = players.keys()
	ids.sort()
	if ids.is_empty():
		return
	var at := ids.find(pov_id)
	pov_id = ids[(at + 1) % ids.size()]


func _free_camera() -> void:
	if pov_id >= 0:
		_free_yaw = camera.rotation.y
		_free_pitch = camera.rotation.x
	pov_id = -1


func _seek(tick: float) -> void:
	cur_tick = clampf(tick, replay.first_tick(), replay.last_tick())


func _toggle_play() -> void:
	if cur_tick >= replay.last_tick():
		cur_tick = replay.first_tick()
	playing = not playing


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	_round_label = Label.new()
	_round_label.theme_type_variation = &"HeaderSmall"
	_round_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_round_label.position = Vector2(-160, 18)
	_round_label.custom_minimum_size = Vector2(320, 0)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_round_label)
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.position = Vector2(-460, 24)
	_feed.custom_minimum_size = Vector2(440, 0)
	root.add_child(_feed)
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -86
	bar.offset_left = 24
	bar.offset_right = -24
	bar.offset_bottom = -18
	root.add_child(bar)
	var v := VBoxContainer.new()
	bar.add_child(v)
	_timeline = HSlider.new()
	_timeline.min_value = replay.first_tick() if replay != null and replay.error == "" else 0
	_timeline.max_value = replay.last_tick() if replay != null and replay.error == "" else 1
	_timeline.step = 1
	_timeline.drag_started.connect(func() -> void: _scrubbing = true)
	_timeline.drag_ended.connect(func(_changed: bool) -> void: _scrubbing = false)
	_timeline.value_changed.connect(func(x: float) -> void:
		if _scrubbing:
			_seek(x))
	v.add_child(_timeline)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	_play_btn = Button.new()
	_play_btn.custom_minimum_size = Vector2(96, 0)
	_play_btn.pressed.connect(_toggle_play)
	row.add_child(_play_btn)
	var spd := OptionButton.new()
	for x: float in SPEEDS:
		spd.add_item("%sx" % str(x))
	spd.selected = speed_i
	spd.item_selected.connect(func(i: int) -> void: speed_i = i)
	row.add_child(spd)
	var pov := Button.new()
	pov.text = "NEXT POV  (TAB)"
	pov.pressed.connect(_next_pov)
	row.add_child(pov)
	var free := Button.new()
	free.text = "FREE CAM  (F)"
	free.pressed.connect(_free_camera)
	row.add_child(free)
	_time_label = Label.new()
	_time_label.theme_type_variation = &"ValueLabel"
	row.add_child(_time_label)
	_info_label = Label.new()
	_info_label.theme_type_variation = &"MutedLabel"
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_info_label)
	var exit := Button.new()
	exit.text = "EXIT"
	exit.pressed.connect(func() -> void: Game.goto("menu"))
	row.add_child(exit)


func _update_ui() -> void:
	if not _scrubbing:
		_timeline.set_value_no_signal(cur_tick)
	_play_btn.text = "PAUSE" if playing else "PLAY"
	var t := (cur_tick - replay.first_tick()) / 64.0
	var total := (replay.last_tick() - replay.first_tick()) / 64.0
	var who := "FREE CAMERA"
	if pov_id >= 0:
		who = "POV  %s" % str(roster.get(pov_id, {}).get("name", pov_id))
	_time_label.text = "%d:%02d / %d:%02d   ·   %s" % [floori(t / 60.0), posmod(int(t), 60), floori(total / 60.0), posmod(int(total), 60), who]
	var phase_i := _latest(_phase_frames)
	if phase_i >= 0:
		var ph := replay.message(phase_i)
		_round_label.text = "ROUND %d   ·   %d : %d" % [int(ph["round"]), int(ph["scoreAttack"]), int(ph["scoreDefense"])]
	_update_feed()


func _update_feed() -> void:
	var recent: Array[int] = []
	for i: int in _kill_frames:
		var dt := cur_tick - replay.ticks[i]
		if dt < 0:
			break
		if dt <= 6 * 64:
			recent.append(i)
	recent = recent.slice(maxi(0, recent.size() - 5))
	var key := str(recent)
	if _feed.get_meta("key", "") == key:
		return
	_feed.set_meta("key", key)
	for c: Node in _feed.get_children():
		c.queue_free()
	for i: int in recent:
		var k := replay.message(i)
		var l := Label.new()
		l.theme_type_variation = &"ValueLabel"
		var killer: Dictionary = roster.get(int(k["killerId"]), {"name": "?"})
		var victim: Dictionary = roster.get(int(k["victimId"]), {"name": "?"})
		l.text = "%s  ›  %s  ›  %s%s" % [killer["name"], str(Data.get_weapon(k["weapon"]).get("name", k["weapon"])).to_upper(), victim["name"], "  ◎" if k["headshot"] else ""]
		_feed.add_child(l)
