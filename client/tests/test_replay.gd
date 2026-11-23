extends TestCase

## Fixture written by the server recorder (server/src/match/replay.ts): 10 bots, one round.
const SAMPLE := "res://tests/data/replay/sample.bpr"


func test_reads_server_replay() -> void:
	var r := ReplayFile.from_gzip(FileAccess.get_file_as_bytes(SAMPLE))
	check_eq(r.error, "", "parse error")
	check_eq(str(r.header.get("map")), "solstice", "header map")
	check(r.snapshot_ticks.size() > 100, "has snapshots")
	var snap := r.message(r.snapshot_frames[10])
	check_eq(str(snap["type"]), "Snapshot", "snapshot decodes")
	check_eq((snap["players"] as Array).size(), 10, "spectator snapshot has every player")
	check(not r.frames_of("MatchState").is_empty(), "roster recorded")
	check(not r.frames_of("RoundEnd").is_empty(), "round end recorded")


func test_seek_finds_last_snapshot_at_or_before() -> void:
	var r := ReplayFile.from_gzip(FileAccess.get_file_as_bytes(SAMPLE))
	var t := r.snapshot_ticks[20]
	check_eq(r.snapshot_at(t), 20, "exact tick")
	check_eq(r.snapshot_at(t + 0.5), 20, "between snapshots")
	check_eq(r.snapshot_at(-5.0), 0, "clamped low")
	check_eq(r.snapshot_at(1e9), r.snapshot_ticks.size() - 1, "clamped high")


func test_rejects_garbage() -> void:
	var r := ReplayFile.from_gzip(PackedByteArray([1, 2, 3, 4]))
	check(r.error != "", "garbage rejected")
