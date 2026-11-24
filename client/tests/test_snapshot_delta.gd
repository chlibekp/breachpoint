extends TestCase

const SAMPLE := "res://tests/data/protocol/snapshot-delta.json"


func test_rebuilds_golden_sample_from_typescript() -> void:
	var g: Dictionary = SharedConfig.read_json(SAMPLE)
	var base := str(g["base"]).hex_decode()
	var full := SnapshotDelta.apply(str(g["delta"]).hex_decode(), base)
	check_eq(full.hex_encode(), str(g["full"]), "delta applied to base")


func test_rejects_payload_that_does_not_fit() -> void:
	var base := PackedByteArray([1, 2, 3])
	check(SnapshotDelta.apply(PackedByteArray([0, 5]), base).is_empty(), "run past the end")
	check(SnapshotDelta.apply(PackedByteArray([7]), base).is_empty(), "too short")
