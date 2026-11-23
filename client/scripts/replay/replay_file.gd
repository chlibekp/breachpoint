## ReplayFile: reader for server match replays (.bpr, spec §14.4; writer: server/src/match/replay.ts).
## gzip( "BPR1" | u32 headerLen | header JSON | frames… ), frame = u32 tick | u16 len | message bytes.
## Frames stay encoded; `message(i)` decodes on demand with the generated protocol codec, so loading a
## 30-minute match only costs one pass over the frame table.
class_name ReplayFile
extends RefCounted

var header: Dictionary = {}
var ticks := PackedInt32Array()  ## per frame
var _offsets := PackedInt32Array()
var _lengths := PackedInt32Array()
var _types := PackedByteArray()  ## message type id per frame
var _raw := PackedByteArray()
var snapshot_frames := PackedInt32Array()  ## frame indices of Snapshot messages, tick-ordered
var snapshot_ticks := PackedInt32Array()
var error := ""


static func from_gzip(gz: PackedByteArray) -> ReplayFile:
	var r := ReplayFile.new()
	if gz.size() < 18 or gz[0] != 0x1f or gz[1] != 0x8b:
		r.error = "not a gzip replay"
		return r
	var raw := gz.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	r._parse(raw)
	return r


func _parse(raw: PackedByteArray) -> void:
	_raw = raw
	if raw.size() < 8 or raw.slice(0, 4).get_string_from_ascii() != "BPR1":
		error = "not a replay file"
		return
	var hl := raw.decode_u32(4)
	var parsed: Variant = JSON.parse_string(raw.slice(8, 8 + hl).get_string_from_utf8())
	header = parsed if parsed is Dictionary else {}
	var snap_id: int = msg_id("Snapshot")
	var o := 8 + hl
	while o + 6 <= raw.size():
		var tick := raw.decode_u32(o)
		var length := raw.decode_u16(o + 4)
		o += 6
		if o + length > raw.size():
			break
		var type_id := raw[o] if length > 0 else 255
		if type_id == snap_id:
			snapshot_frames.append(ticks.size())
			snapshot_ticks.append(tick)
		ticks.append(tick)
		_offsets.append(o)
		_lengths.append(length)
		_types.append(type_id)
		o += length
	if snapshot_frames.is_empty():
		error = "replay has no snapshots"


static func msg_id(msg_type: String) -> int:
	for id: int in Protocol.MSG_NAMES:
		if Protocol.MSG_NAMES[id] == msg_type:
			return id
	return -1


func frame_count() -> int:
	return ticks.size()


func type_name(i: int) -> String:
	return Protocol.MSG_NAMES.get(_types[i], "?")


func message(i: int) -> Dictionary:
	return Protocol.decode(_raw.slice(_offsets[i], _offsets[i] + _lengths[i]))


func first_tick() -> int:
	return snapshot_ticks[0] if not snapshot_ticks.is_empty() else 0


func last_tick() -> int:
	return snapshot_ticks[snapshot_ticks.size() - 1] if not snapshot_ticks.is_empty() else 0


## Index into snapshot_ticks of the last snapshot at or before `tick` (binary search).
func snapshot_at(tick: float) -> int:
	var i := snapshot_ticks.bsearch(int(floorf(tick)), false) - 1
	return clampi(i, 0, snapshot_ticks.size() - 1)


## Frame indices of every message of `type_name` (in order).
func frames_of(msg_type: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var id: int = msg_id(msg_type)
	for i: int in _types.size():
		if _types[i] == id:
			out.append(i)
	return out
