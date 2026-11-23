## Loads and validates the shared JSON configs mirrored into res://data by `npm run sync:client`.
## Pure (no autoload state) so tests and editor tools can use it directly.
class_name SharedConfig
extends RefCounted

const CONFIG_DIR := "res://data/config"
const SCHEMA_DIR := "res://data/schemas"
const NAMES: PackedStringArray = ["weapons", "agents", "economy", "movement", "match", "quality", "hitboxes", "materials", "skins", "voicelines"]


static func read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SharedConfig: cannot read %s" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("SharedConfig: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Loads every config. Returns {"data": {name: Dictionary}, "errors": PackedStringArray}.
static func load_all() -> Dictionary:
	var data: Dictionary = {}
	var errors := PackedStringArray()
	for config_name: String in NAMES:
		var value: Variant = read_json("%s/%s.json" % [CONFIG_DIR, config_name])
		var schema: Variant = read_json("%s/%s.schema.json" % [SCHEMA_DIR, config_name])
		if not (value is Dictionary) or not (schema is Dictionary):
			errors.append("%s: missing or unparsable" % config_name)
			continue
		var issues := JsonSchema.validate(value, schema)
		for issue: String in issues:
			errors.append("%s.json %s" % [config_name, issue])
		if issues.is_empty():
			data[config_name] = value
	return {"data": data, "errors": errors}
