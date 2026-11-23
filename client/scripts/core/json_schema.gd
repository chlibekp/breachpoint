## Minimal JSON Schema validator covering exactly the keyword subset documented in
## shared/schemas/common.md, so the client enforces the same rules as Ajv on the server.
class_name JsonSchema
extends RefCounted


## Returns a list of human-readable errors (empty when valid).
static func validate(value: Variant, schema: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	_validate(value, schema, schema, "", errors)
	return errors


static func _type_matches(value: Variant, type_name: String) -> bool:
	match type_name:
		"object":
			return value is Dictionary
		"array":
			return value is Array
		"string":
			return value is String
		"boolean":
			return value is bool
		"null":
			return value == null
		"number":
			return value is float or value is int
		"integer":
			# Godot's JSON parser returns every number as float.
			return (value is int) or (value is float and is_equal_approx(value, roundf(value)))
	return false


static func _values_equal(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b


static func _resolve(schema: Dictionary, root: Dictionary) -> Dictionary:
	if not schema.has("$ref"):
		return schema
	var ref: String = schema["$ref"]
	var prefix := "#/$defs/"
	if not ref.begins_with(prefix):
		push_error("JsonSchema: unsupported $ref %s" % ref)
		return {}
	var defs: Dictionary = root.get("$defs", {})
	return defs.get(ref.substr(prefix.length()), {})


static func _validate(value: Variant, raw_schema: Dictionary, root: Dictionary, path: String, errors: PackedStringArray) -> void:
	var schema: Dictionary = _resolve(raw_schema, root)
	var at: String = path if path != "" else "/"

	if schema.has("type"):
		var types: Array = schema["type"] if schema["type"] is Array else [schema["type"]]
		var ok := false
		for t: Variant in types:
			if _type_matches(value, str(t)):
				ok = true
				break
		if not ok:
			errors.append("%s must be %s" % [at, " or ".join(PackedStringArray(types))])
			return
	if schema.has("const") and not _values_equal(value, schema["const"]):
		errors.append("%s must equal %s" % [at, str(schema["const"])])
	if schema.has("enum"):
		var found := false
		for option: Variant in schema["enum"]:
			if _values_equal(value, option):
				found = true
				break
		if not found:
			errors.append("%s must be one of %s" % [at, str(schema["enum"])])
	if value is float or value is int:
		var n := float(value)
		if schema.has("minimum") and n < float(schema["minimum"]):
			errors.append("%s must be >= %s" % [at, str(schema["minimum"])])
		if schema.has("maximum") and n > float(schema["maximum"]):
			errors.append("%s must be <= %s" % [at, str(schema["maximum"])])
		if schema.has("exclusiveMinimum") and n <= float(schema["exclusiveMinimum"]):
			errors.append("%s must be > %s" % [at, str(schema["exclusiveMinimum"])])
	if value is String:
		var s: String = value
		if schema.has("minLength") and s.length() < int(schema["minLength"]):
			errors.append("%s is shorter than %d" % [at, int(schema["minLength"])])
		if schema.has("pattern"):
			var re := RegEx.create_from_string(str(schema["pattern"]))
			if re.search(s) == null:
				errors.append("%s does not match %s" % [at, str(schema["pattern"])])
	if value is Array:
		var arr: Array = value
		if schema.has("minItems") and arr.size() < int(schema["minItems"]):
			errors.append("%s needs at least %d items" % [at, int(schema["minItems"])])
		if schema.has("maxItems") and arr.size() > int(schema["maxItems"]):
			errors.append("%s allows at most %d items" % [at, int(schema["maxItems"])])
		if schema.has("items"):
			for i: int in arr.size():
				_validate(arr[i], schema["items"], root, "%s/%d" % [path, i], errors)
	if value is Dictionary:
		var obj: Dictionary = value
		var props: Dictionary = schema.get("properties", {})
		for key: Variant in schema.get("required", []):
			if not obj.has(key):
				errors.append("%s is missing required property '%s'" % [at, str(key)])
		for key: Variant in obj.keys():
			if props.has(key):
				_validate(obj[key], props[key], root, "%s/%s" % [path, str(key)], errors)
			else:
				var extra: Variant = schema.get("additionalProperties", true)
				if extra is bool and extra == false:
					errors.append("%s has unexpected property '%s'" % [at, str(key)])
				elif extra is Dictionary:
					_validate(obj[key], extra, root, "%s/%s" % [path, str(key)], errors)
