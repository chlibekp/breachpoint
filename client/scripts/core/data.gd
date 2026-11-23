## Autoload: shared, schema-validated game data (weapons, agents, economy, movement, match, quality).
## No balance number may live in code; read it from here.
extends Node

signal loaded

var weapons: Dictionary = {}  ## id -> weapon Dictionary
var agents: Dictionary = {}  ## id -> agent Dictionary
var economy: Dictionary = {}
var movement: Dictionary = {}
var match_rules: Dictionary = {}
var quality: Dictionary = {}
var errors := PackedStringArray()
var is_loaded: bool = false


func _ready() -> void:
	reload()


func reload() -> void:
	var result: Dictionary = SharedConfig.load_all()
	errors = result["errors"]
	var data: Dictionary = result["data"]
	weapons = _index(data.get("weapons", {}).get("weapons", []))
	agents = _index(data.get("agents", {}).get("agents", []))
	economy = data.get("economy", {})
	movement = data.get("movement", {})
	match_rules = data.get("match", {})
	quality = data.get("quality", {})
	is_loaded = errors.is_empty()
	for e: String in errors:
		push_error("Data: %s" % e)
	loaded.emit()


func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})


func get_agent(id: String) -> Dictionary:
	return agents.get(id, {})


static func _index(items: Array) -> Dictionary:
	var out: Dictionary = {}
	for item: Variant in items:
		var d: Dictionary = item
		out[d["id"]] = d
	return out
