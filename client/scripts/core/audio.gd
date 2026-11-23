## Autoload: builds the audio bus layout from spec section 16 at startup and handles the
## browser autoplay rule (audio unlocks after the first user click).
extends Node

## Bus name -> parent bus. Order matters: parents first.
const BUSES: Array[Dictionary] = [
	{"name": "SFX", "send": "Master"},
	{"name": "Weapons", "send": "SFX"},
	{"name": "Footsteps", "send": "SFX"},
	{"name": "Abilities", "send": "SFX"},
	{"name": "Voice", "send": "Master"},
	{"name": "Music", "send": "Master"},
	{"name": "UI", "send": "Master"},
]

var unlocked: bool = false


func _ready() -> void:
	_build_buses()
	_apply_volumes()
	Settings.changed.connect(func(section: String, _key: String, _value: Variant) -> void:
		if section == "audio":
			_apply_volumes())
	unlocked = not OS.has_feature("web")


func _build_buses() -> void:
	for spec: Dictionary in BUSES:
		var bus_name: String = spec["name"]
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, spec["send"])
	# Limiter on Master.
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.3
		AudioServer.add_bus_effect(master, limiter)
	# Sidechain ducking: music dips under voice.
	var music := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(music) == 0:
		var duck := AudioEffectCompressor.new()
		duck.sidechain = &"Voice"
		duck.threshold = -24.0
		duck.ratio = 6.0
		duck.attack_us = 5000.0
		duck.release_ms = 350.0
		AudioServer.add_bus_effect(music, duck)


func _apply_volumes() -> void:
	_set_linear("Master", Settings.get_value("audio", "master"))
	_set_linear("SFX", Settings.get_value("audio", "sfx"))
	_set_linear("Voice", Settings.get_value("audio", "voice"))
	_set_linear("Music", Settings.get_value("audio", "music"))


func _set_linear(bus_name: String, value: Variant) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(float(value), 0.0, 1.0)))


func _input(event: InputEvent) -> void:
	if not unlocked and (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		unlocked = true
