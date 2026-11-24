## Snapshot delta decoder (spec §13). Mirror of server/src/match/snapshot-delta.ts: the payload is
## a zero-run-length encoding of (encoded Snapshot XOR encoded base Snapshot).
##   0x00 n → n unchanged bytes · b ≠ 0 → base byte XOR b
class_name SnapshotDelta
extends RefCounted


## Returns the full encoded Snapshot, or an empty array if the payload does not fit the base.
static func apply(delta: PackedByteArray, base: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(base.size())
	var o := 0
	var i := 0
	while i < delta.size():
		var b := delta[i]
		if b == 0:
			if i + 1 >= delta.size():
				return PackedByteArray()
			var run := delta[i + 1]
			if o + run > base.size():
				return PackedByteArray()
			for k: int in run:
				out[o + k] = base[o + k]
			o += run
			i += 2
		else:
			if o >= base.size():
				return PackedByteArray()
			out[o] = base[o] ^ b
			o += 1
			i += 1
	return out if o == base.size() else PackedByteArray()
