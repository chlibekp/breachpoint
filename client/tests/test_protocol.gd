extends TestCase

const VECTORS := "res://tests/data/protocol/vectors.json"


## Converts the JSON vector form into the Dictionary form the GDScript codec uses.
static func _from_json(v: Variant, key: String = "") -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("$bytes"):
			return str(d["$bytes"]).hex_decode()
		if key in ["pos", "vel", "origin", "target", "fromPos", "hit"]:
			return Vector3(d["x"], d["y"], d["z"])
		var out: Dictionary = {}
		for k: Variant in d:
			out[k] = _from_json(d[k], str(k))
		return out
	if v is Array:
		var arr: Array = []
		for item: Variant in v:
			arr.append(_from_json(item))
		return arr
	if v is float and is_equal_approx(v, roundf(v)) and key not in ["yaw", "pitch", "clientTimeMs"]:
		return int(v)
	return v


func _approx(actual: Variant, expected: Variant, path: String) -> void:
	if expected is float or expected is int:
		check(actual is float or actual is int, "%s not numeric" % path)
		check_near(float(actual), float(expected), 1e-3, path)
	elif expected is Vector3:
		check((actual as Vector3).distance_to(expected) < 1e-3, "%s %s != %s" % [path, str(actual), str(expected)])
	elif expected is Array:
		check_eq((actual as Array).size(), (expected as Array).size(), path + " size")
		for i: int in (expected as Array).size():
			_approx((actual as Array)[i], (expected as Array)[i], "%s[%d]" % [path, i])
	elif expected is Dictionary:
		for k: Variant in expected:
			_approx((actual as Dictionary).get(k), (expected as Dictionary)[k], "%s.%s" % [path, str(k)])
	else:
		check_eq(actual, expected, path)


func test_golden_vectors_match_typescript() -> void:
	var file: Dictionary = SharedConfig.read_json(VECTORS)
	var vectors: Array = file["vectors"]
	check(vectors.size() == Protocol.MSG_NAMES.size(), "every message type has a vector")
	for v: Variant in vectors:
		var vec: Dictionary = v
		var msg: Dictionary = _from_json(vec["message"])
		var name: String = msg["type"]
		check_eq(Protocol.encode(msg).hex_encode(), str(vec["hex"]), name + " bytes")
		_approx(Protocol.decode(str(vec["hex"]).hex_decode()), msg, name)


func test_rejects_malformed_bytes() -> void:
	var bytes := Protocol.encode({"type": "Ping", "nonce": 1, "clientTimeMs": 2.0})
	check(Protocol.decode(bytes.slice(0, bytes.size() - 1)).is_empty(), "truncated rejected")
	var extra := bytes.duplicate()
	extra.append(0)
	check(Protocol.decode(extra).is_empty(), "trailing rejected")
	check(Protocol.decode(PackedByteArray([250])).is_empty(), "unknown id rejected")


func test_angle_quantisation() -> void:
	for a: float in [-PI, -2.5, -0.001, 0.0, 0.7, PI, 7.0]:
		var back := ProtocolCodec.dequantize_angle(ProtocolCodec.quantize_angle(a))
		check(absf(angle_difference(a, back)) < PI / 65536.0 + 1e-9, "angle %f" % a)
		check(back > -PI - 1e-9 and back <= PI + 1e-9, "range %f" % back)
