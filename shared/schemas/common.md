Schemas use a deliberately small JSON Schema (2020-12) subset so the GDScript validator in
client/scripts/core/json_schema.gd can enforce exactly the same rules as Ajv on the server:
type (string or array), properties, required, additionalProperties (boolean), items, enum, const,
minimum, maximum, exclusiveMinimum, minItems, maxItems, minLength, pattern, $ref ("#/$defs/<name>").
Do not use other keywords.
