extends TestCase

const SCHEMA := {
	"type": "object",
	"required": ["id", "n"],
	"additionalProperties": false,
	"properties": {
		"id": {"type": "string", "pattern": "^[a-z]+$"},
		"n": {"type": "integer", "minimum": 0, "maximum": 10},
		"tags": {"type": "array", "maxItems": 2, "items": {"enum": ["a", "b"]}},
		"opt": {"type": ["object", "null"]},
		"ref": {"$ref": "#/$defs/thing"},
	},
	"$defs": {"thing": {"type": "number", "exclusiveMinimum": 0}},
}


func test_accepts_valid() -> void:
	check(JsonSchema.validate({"id": "abc", "n": 3.0, "tags": ["a"], "opt": null, "ref": 0.5}, SCHEMA).is_empty(), "valid doc")


func test_rejects_each_rule() -> void:
	check(not JsonSchema.validate({"id": "abc"}, SCHEMA).is_empty(), "required")
	check(not JsonSchema.validate({"id": "ABC", "n": 1}, SCHEMA).is_empty(), "pattern")
	check(not JsonSchema.validate({"id": "a", "n": 1.5}, SCHEMA).is_empty(), "integer")
	check(not JsonSchema.validate({"id": "a", "n": 11}, SCHEMA).is_empty(), "maximum")
	check(not JsonSchema.validate({"id": "a", "n": 1, "x": 1}, SCHEMA).is_empty(), "additionalProperties")
	check(not JsonSchema.validate({"id": "a", "n": 1, "tags": ["a", "b", "a"]}, SCHEMA).is_empty(), "maxItems")
	check(not JsonSchema.validate({"id": "a", "n": 1, "tags": ["c"]}, SCHEMA).is_empty(), "enum")
	check(not JsonSchema.validate({"id": "a", "n": 1, "ref": 0}, SCHEMA).is_empty(), "$ref exclusiveMinimum")
