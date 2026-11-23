## Port of server/src/sim/rng.ts (mulberry32 + hashSeed). Bit-exact with the TypeScript version.
class_name SimRng
extends RefCounted

const M32 := 0xFFFFFFFF

var _a: int = 0


func _init(seed_value: int) -> void:
	_a = seed_value & M32


## 32-bit multiply (Math.imul semantics) without 64-bit overflow.
static func imul(a: int, b: int) -> int:
	a &= M32
	b &= M32
	var lo := (a & 0xFFFF) * b
	var hi := ((a >> 16) * b) & 0xFFFF
	return (lo + (hi << 16)) & M32


func next() -> float:
	_a = (_a + 0x6D2B79F5) & M32
	var t := _a
	t = imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + imul(t ^ (t >> 7), t | 61)) & M32)) & M32
	return float((t ^ (t >> 14)) & M32) / 4294967296.0


static func hash_seed(a: int, b: int) -> int:
	var h := (a ^ 0x9E3779B9) & M32
	h = imul(h ^ (b & M32), 0x85EBCA6B)
	h ^= h >> 13
	h = imul(h, 0xC2B2AE35)
	h ^= h >> 16
	return h & M32
