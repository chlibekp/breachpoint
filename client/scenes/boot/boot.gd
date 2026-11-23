## Boot / systems-check screen for milestone 1. Shows that every foundation piece is alive:
## engine pin, renderer + tier, shared data, protocol codec, physics tick, audio, server link.
extends Control

const MIN_ENGINE := [4, 5]

@onready var _rows: VBoxContainer = %Rows
@onready var _version: Label = %Version
@onready var _connect: Button = %ConnectButton

var _status_labels: Dictionary = {}  ## key -> [value Label, status Label]


func _ready() -> void:
	_version.text = Game.version_string()
	_connect.pressed.connect(_on_connect)
	%LightmapButton.pressed.connect(func() -> void: Game.goto("lightmap_test"))
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	%QuitButton.visible = not OS.has_feature("web")
	Net.state_changed.connect(func(_s: int) -> void: _refresh_server())
	Net.rtt_updated.connect(func(_rtt: float) -> void: _refresh_server())
	QualityManager.tier_changed.connect(func(_t: Dictionary) -> void: _refresh_static())
	_build_rows()
	_refresh_static()
	_refresh_server()
	_on_connect()


func _build_rows() -> void:
	for key: String in ["ENGINE", "RENDERER", "GPU", "QUALITY TIER", "SHARED DATA", "PROTOCOL", "PHYSICS TICK", "AUDIO", "LIGHTMAPS", "SERVER"]:
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"RowPanel"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var name_label := Label.new()
		name_label.theme_type_variation = &"HeaderSmall"
		name_label.text = key
		name_label.custom_minimum_size = Vector2(190, 0)
		var value := Label.new()
		value.theme_type_variation = &"ValueLabel"
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.clip_text = true
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var status := Label.new()
		status.custom_minimum_size = Vector2(72, 0)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name_label)
		row.add_child(value)
		row.add_child(status)
		panel.add_child(row)
		_rows.add_child(panel)
		_status_labels[key] = [value, status]


func _set_row(key: String, text: String, level: String) -> void:
	var labels: Array = _status_labels[key]
	var value: Label = labels[0]
	var status: Label = labels[1]
	value.text = text
	value.tooltip_text = text
	status.text = level
	status.theme_type_variation = {"OK": &"OkLabel", "WARN": &"WarnLabel", "FAIL": &"FailLabel"}.get(level, &"MutedLabel")


func _refresh_static() -> void:
	var v: Dictionary = Engine.get_version_info()
	var engine_ok: bool = int(v["major"]) > MIN_ENGINE[0] or (int(v["major"]) == MIN_ENGINE[0] and int(v["minor"]) >= MIN_ENGINE[1])
	_set_row("ENGINE", "Godot %s" % v["string"], "OK" if engine_ok else "FAIL")

	var method := RenderingServer.get_current_rendering_method()
	var nice: String = {"forward_plus": "Forward+", "gl_compatibility": "Compatibility (GL)", "mobile": "Mobile"}.get(method, method)
	var expected := "gl_compatibility" if OS.has_feature("web") else "forward_plus"
	_set_row("RENDERER", "%s · %s" % [nice, "web" if OS.has_feature("web") else OS.get_name()], "OK" if method == expected else "WARN")
	_set_row("GPU", "%s · API %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()], "OK")

	var t: Dictionary = QualityManager.tier
	if t.is_empty():
		_set_row("QUALITY TIER", "not selected", "FAIL")
	else:
		_set_row("QUALITY TIER", "%s · shadows %d×%d · MSAA %dx%s%s · %d fps target" % [
			str(t["id"]).to_upper(), int(t["shadowCascades"]), int(t["shadowSize"]), int(t["msaa"]),
			" + FXAA" if t["fxaa"] else "", " · TAA" if t["taa"] else "", int(t["targetFps"])], "OK")

	if Data.is_loaded:
		_set_row("SHARED DATA", "%d weapons · %d agents · economy, movement, match, quality" % [Data.weapons.size(), Data.agents.size()], "OK")
	else:
		_set_row("SHARED DATA", "%d schema errors (see log)" % Data.errors.size(), "FAIL")

	_set_row("PROTOCOL", "v%d · %d message types · codec self-test %s" % [Protocol.PROTOCOL_VERSION, Protocol.MSG_NAMES.size(), "passed" if _protocol_self_test() else "FAILED"], "OK" if _protocol_self_test() else "FAIL")

	var ticks: int = Engine.physics_ticks_per_second
	var want: int = int(Data.movement.get("tickRate", 64))
	var interp: bool = ProjectSettings.get_setting("physics/common/physics_interpolation", false)
	_set_row("PHYSICS TICK", "%d Hz · interpolation %s" % [ticks, "on" if interp else "off"], "OK" if ticks == want and interp else "FAIL")

	var bus_names := PackedStringArray()
	for i: int in AudioServer.bus_count:
		bus_names.append(AudioServer.get_bus_name(i))
	_set_row("AUDIO", "%d buses · %s" % [bus_names.size(), ", ".join(bus_names)], "OK" if Audio.unlocked else "WARN")

	var baked := ResourceLoader.exists("res://scenes/dev/lightmap_test.lmbake")
	_set_row("LIGHTMAPS", "LightmapGI test scene %s" % ("baked" if baked else "not baked yet"), "OK" if baked else "WARN")


func _refresh_server() -> void:
	match Net.state:
		Net.State.ONLINE:
			_set_row("SERVER", "%s · RTT %s · tick %d" % [Net.display_name, ("%.1f ms" % Net.rtt_ms) if Net.rtt_ms >= 0.0 else "…", Net.server_tick], "OK")
		Net.State.CONNECTING, Net.State.HANDSHAKE:
			_set_row("SERVER", "connecting to %s…" % _server_url(), "WARN")
		Net.State.FAILED:
			_set_row("SERVER", "offline (%s) — run npm run server:dev" % Net.last_error, "WARN")
		_:
			_set_row("SERVER", "not connected", "WARN")
	_connect.text = "RECONNECT" if Net.state == Net.State.ONLINE else "CONNECT"


func _protocol_self_test() -> bool:
	var msg := {
		"type": "Snapshot", "tick": 77, "baseTick": 70, "lastProcessedSeq": 12,
		"players": [{"playerId": 3, "pos": Vector3(1.5, 0.25, -9.125), "vel": Vector3(6.75, 0, -1), "yaw": 1.0, "pitch": -0.5,
			"flags": 5, "health": 100, "shield": 25, "weapon": 10}],
	}
	var back := Protocol.decode(Protocol.encode(msg))
	if back.is_empty():
		return false
	var p: Dictionary = back["players"][0]
	return int(back["tick"]) == 77 and (p["pos"] as Vector3).is_equal_approx(Vector3(1.5, 0.25, -9.125)) and absf(float(p["yaw"]) - 1.0) < 0.001


func _server_url() -> String:
	if OS.has_feature("web"):
		var from_query: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || ''", true)
		if str(from_query) != "":
			return str(from_query)
		var host: Variant = JavaScriptBridge.eval("location.hostname || '127.0.0.1'", true)
		var scheme: Variant = JavaScriptBridge.eval("location.protocol === 'https:' ? 'wss' : 'ws'", true)
		return "%s://%s:7350" % [scheme, host]
	return str(Settings.get_value("net", "server_url"))


func _on_connect() -> void:
	Net.connect_to(_server_url())
	_refresh_server()


func _process(_delta: float) -> void:
	# Audio unlock can only happen after a click on web; keep the row honest.
	if Audio.unlocked and _status_labels.has("AUDIO") and (_status_labels["AUDIO"][1] as Label).text == "WARN":
		_refresh_static()
