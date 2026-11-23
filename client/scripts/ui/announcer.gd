## Announcer and voice lines (spec §16): lines come from shared/config/voicelines.json. Placeholder
## delivery is the platform text-to-speech (DisplayServer.tts_*: Web Speech API in browsers, the OS
## voice on desktop where available) plus a subtitle scaled by Accessibility → subtitle size.
## Lines are skipped when the Voice volume is 0; subtitles always show.
class_name Announcer
extends CanvasLayer

var lines: Dictionary = {}
var _subtitle: Label
var _t := 0.0
var _voice_id := ""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 12
	lines = SharedConfig.read_json("res://data/config/voicelines.json")
	_subtitle = Label.new()
	_subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.custom_minimum_size = Vector2(900, 0)
	_subtitle.position = Vector2(-450, -230)
	_subtitle.theme_type_variation = &"ValueLabel"
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_subtitle.add_theme_constant_override("outline_size", 8)
	var sub_scale := float(Settings.get_value("accessibility", "subtitle_scale"))
	_subtitle.add_theme_font_size_override("font_size", int(22 * sub_scale))
	add_child(_subtitle)
	if _tts_ok():
		var voices := DisplayServer.tts_get_voices_for_language("en")
		if not voices.is_empty():
			_voice_id = voices[0]


func _tts_ok() -> bool:
	return OS.has_feature("web") or DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


## Speaks a random line from `section` (announcer | abilities) under `key`. `speaker` prefixes the
## subtitle ("" for the announcer).
func say(section: String, key: String, speaker: String = "") -> void:
	var pool: Array = (lines.get(section, {}) as Dictionary).get(key, [])
	if pool.is_empty():
		return
	_deliver(str(pool[_rng.randi() % pool.size()]), speaker)


func ping_line(kind: int, speaker: String) -> void:
	var pings: Array = lines.get("pings", [])
	if kind < 0 or kind >= pings.size():
		return
	var p: Dictionary = pings[kind]
	var pool: Array = p["lines"]
	_deliver(str(pool[_rng.randi() % pool.size()]), speaker)


func _deliver(text: String, speaker: String) -> void:
	_subtitle.text = ("%s: %s" % [speaker, text]) if speaker != "" else text
	_t = 3.0
	var vol := float(Settings.get_value("audio", "voice")) * float(Settings.get_value("audio", "master"))
	if vol > 0.01 and _tts_ok():
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(text, _voice_id, int(clampf(vol, 0.0, 1.0) * 100.0), 1.0, 1.1)


func _process(delta: float) -> void:
	_t -= delta
	_subtitle.modulate.a = clampf(_t, 0.0, 1.0)
