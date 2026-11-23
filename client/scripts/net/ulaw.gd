## G.711 µ-law codec for team voice (8-bit samples, ~13-bit dynamic range). Pure, no autoloads.
class_name Ulaw
extends RefCounted

static var _table := PackedFloat32Array()


static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	for i: int in samples.size():
		var pcm := clampi(int(samples[i] * 32767.0), -32767, 32767)
		var sgn := 0x80 if pcm < 0 else 0
		var mag := mini(absi(pcm) + 132, 32767)
		var exponent := 7
		var mask := 0x4000
		while exponent > 0 and (mag & mask) == 0:
			exponent -= 1
			mask >>= 1
		var mantissa := (mag >> (exponent + 3)) & 0x0F
		out[i] = ~(sgn | (exponent << 4) | mantissa) & 0xFF
	return out


static func decode(code: int) -> float:
	if _table.is_empty():
		_build_table()
	return _table[code & 0xFF]


static func _build_table() -> void:
	_table.resize(256)
	for b: int in 256:
		var u := ~b & 0xFF
		var exponent := (u >> 4) & 0x07
		var mantissa := u & 0x0F
		var mag := (((mantissa << 3) + 132) << exponent) - 132
		_table[b] = float(-mag if (u & 0x80) != 0 else mag) / 32767.0
