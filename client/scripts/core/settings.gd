## Autoload: player settings persisted to user://settings.cfg, plus default input bindings.
## Every option in spec section 15.3 gets a key here as its feature lands.
extends Node

signal changed(section: String, key: String, value: Variant)

const PATH := "user://settings.cfg"

## Colour-blind presets for enemy highlight / HUD / minimap (spec 4.2). Values are hex strings.
const COLORBLIND_PRESETS: Dictionary = {
	"off": {"ally": "#3FE0D0", "enemy": "#FF4655"},
	"deuteranopia": {"ally": "#3FA9F5", "enemy": "#FFB000"},
	"protanopia": {"ally": "#3FA9F5", "enemy": "#F5E62A"},
	"tritanopia": {"ally": "#3FE0D0", "enemy": "#FF2E9A"},
}

const DEFAULTS: Dictionary = {
	"video": {
		"tier": "auto",  # auto | web | low | medium | high | ultra
		"fov": 90.0,  # 80–103 (horizontal, spec 15.3)
		"max_fps": 0,
		"vsync": false,
	},
	"audio": {"master": 1.0, "sfx": 1.0, "voice": 1.0, "music": 0.6},
	"controls": {"sensitivity": 0.35, "ads_multiplier": 1.0, "raw_input": true, "invert_y": false},
	"accessibility": {"colorblind": "off", "reduced_shake": false, "subtitle_scale": 1.0},
	"gameplay": {"viewmodel_sway": true, "strafe_tilt": true, "agent": "kestrel"},
	"net": {"server_url": "ws://127.0.0.1:7350", "show_net_graph": false},
	# Team voice / text chat (spec 15.4). stun_server empty = host candidates only (relay fallback).
	"comms": {"voice_enabled": true, "stun_server": "", "muted": [], "volumes": {}, "chat_muted": []},
}

## action -> default keycodes / mouse buttons. Rebinding writes overrides into section "bindings".
const DEFAULT_BINDINGS: Dictionary = {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"crouch": [KEY_CTRL],
	"walk": [KEY_SHIFT],
	"fire": [MOUSE_BUTTON_LEFT],
	"alt_fire": [MOUSE_BUTTON_RIGHT],
	"reload": [KEY_R],
	"use": [KEY_F],
	"inspect": [KEY_Y],
	"weapon_primary": [KEY_1],
	"weapon_secondary": [KEY_2],
	"weapon_melee": [KEY_3],
	"weapon_charge": [KEY_4],
	"ability_c": [KEY_C],
	"ability_q": [KEY_Q],
	"ability_e": [KEY_E],
	"ability_x": [KEY_X],
	"buy_menu": [KEY_B],
	"scoreboard": [KEY_TAB],
	"ping_wheel": [KEY_Z],
	"voice_ptt": [KEY_V],
	"chat_team": [KEY_ENTER],
	"chat_all": [KEY_T],
	"debug_greyscale": [KEY_F6],
	"debug_silhouette": [KEY_F7],
	"debug_overlay": [KEY_F3],
}

var _cfg := ConfigFile.new()


func _ready() -> void:
	var err := _cfg.load(PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("Settings: could not load %s (%s); using defaults" % [PATH, error_string(err)])
	apply_bindings()


func get_value(section: String, key: String) -> Variant:
	var fallback: Variant = DEFAULTS.get(section, {}).get(key)
	return _cfg.get_value(section, key, fallback)


func set_value(section: String, key: String, value: Variant, persist: bool = true) -> void:
	_cfg.set_value(section, key, value)
	if persist:
		_cfg.save(PATH)
	changed.emit(section, key, value)


func team_colors() -> Dictionary:
	var preset: String = get_value("accessibility", "colorblind")
	var colors: Dictionary = COLORBLIND_PRESETS.get(preset, COLORBLIND_PRESETS["off"])
	return {"ally": Color(colors["ally"]), "enemy": Color(colors["enemy"])}


func apply_bindings() -> void:
	for action: String in DEFAULT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		var codes: Array = _cfg.get_value("bindings", action, DEFAULT_BINDINGS[action])
		for code: Variant in codes:
			InputMap.action_add_event(action, _event_for(int(code), action))


static func _event_for(code: int, action: String) -> InputEvent:
	# Mouse buttons share small integers with nothing in Key, so actions bound to the
	# fire/alt buttons are stored as MouseButton values.
	if action in ["fire", "alt_fire"] and code <= MOUSE_BUTTON_XBUTTON2:
		var mb := InputEventMouseButton.new()
		mb.button_index = code as MouseButton
		return mb
	var key := InputEventKey.new()
	key.physical_keycode = code as Key
	return key
