## Binary primitives used by the generated Protocol codec.
## Quantisation rules MUST match shared/protocol/codec.ts exactly (golden vectors enforce it).
class_name ProtocolCodec
extends RefCounted


static func qround(x: float) -> int:
	return int(floor(x + 0.5))


static func quantize_angle(rad: float) -> int:
	return posmod(qround(rad / TAU * 65536.0), 65536)


static func dequantize_angle(q: int) -> float:
	var a: float = float(q) / 65536.0 * TAU
	return a - TAU if a > PI else a


class Writer:
	extends RefCounted
	var _buf := StreamPeerBuffer.new()

	func _init() -> void:
		_buf.big_endian = false

	func put_u8(v: int) -> void:
		_buf.put_u8(v)

	func put_i8(v: int) -> void:
		_buf.put_8(v)

	func put_u16(v: int) -> void:
		_buf.put_u16(v)

	func put_i16(v: int) -> void:
		_buf.put_16(v)

	func put_u32(v: int) -> void:
		_buf.put_u32(v)

	func put_i32(v: int) -> void:
		_buf.put_32(v)

	func put_f32(v: float) -> void:
		_buf.put_float(v)

	func put_bool(v: bool) -> void:
		_buf.put_u8(1 if v else 0)

	func put_bytes(v: PackedByteArray) -> void:
		assert(v.size() <= 65535, "byte field too long")
		_buf.put_u16(v.size())
		_buf.put_data(v)

	func put_string(v: String) -> void:
		put_bytes(v.to_utf8_buffer())

	func put_pos(v: Vector3) -> void:
		_buf.put_32(clampi(ProtocolCodec.qround(v.x * 1000.0), -2147483648, 2147483647))
		_buf.put_32(clampi(ProtocolCodec.qround(v.y * 1000.0), -2147483648, 2147483647))
		_buf.put_32(clampi(ProtocolCodec.qround(v.z * 1000.0), -2147483648, 2147483647))

	func put_vel(v: Vector3) -> void:
		_buf.put_16(clampi(ProtocolCodec.qround(v.x * 1000.0), -32767, 32767))
		_buf.put_16(clampi(ProtocolCodec.qround(v.y * 1000.0), -32767, 32767))
		_buf.put_16(clampi(ProtocolCodec.qround(v.z * 1000.0), -32767, 32767))

	func put_angle(rad: float) -> void:
		_buf.put_u16(ProtocolCodec.quantize_angle(rad))

	func array_len(n: int, max_len: int) -> void:
		assert(n <= max_len, "array length exceeds schema max")
		_buf.put_u16(n)

	func finish() -> PackedByteArray:
		return _buf.data_array


class Reader:
	extends RefCounted
	var _buf := StreamPeerBuffer.new()
	var _size: int = 0
	var error: bool = false

	func _init(bytes: PackedByteArray) -> void:
		_buf.big_endian = false
		_buf.data_array = bytes
		_size = bytes.size()

	func _need(n: int) -> bool:
		if error or _buf.get_position() + n > _size:
			error = true
			return false
		return true

	func get_u8() -> int:
		return _buf.get_u8() if _need(1) else 0

	func get_i8() -> int:
		return _buf.get_8() if _need(1) else 0

	func get_u16() -> int:
		return _buf.get_u16() if _need(2) else 0

	func get_i16() -> int:
		return _buf.get_16() if _need(2) else 0

	func get_u32() -> int:
		return _buf.get_u32() if _need(4) else 0

	func get_i32() -> int:
		return _buf.get_32() if _need(4) else 0

	func get_f32() -> float:
		return _buf.get_float() if _need(4) else 0.0

	func get_bool() -> bool:
		return get_u8() != 0

	func get_bytes() -> PackedByteArray:
		var n: int = get_u16()
		if not _need(n):
			return PackedByteArray()
		var res: Array = _buf.get_data(n)
		return res[1]

	func get_string() -> String:
		return get_bytes().get_string_from_utf8()

	func get_pos() -> Vector3:
		var x: int = get_i32()
		var y: int = get_i32()
		var z: int = get_i32()
		return Vector3(x / 1000.0, y / 1000.0, z / 1000.0)

	func get_vel() -> Vector3:
		var x: int = get_i16()
		var y: int = get_i16()
		var z: int = get_i16()
		return Vector3(x / 1000.0, y / 1000.0, z / 1000.0)

	func get_angle() -> float:
		return ProtocolCodec.dequantize_angle(get_u16())

	func array_len(max_len: int) -> int:
		var n: int = get_u16()
		if n > max_len:
			error = true
			return 0
		return n

	func ok_and_finished() -> bool:
		return not error and _buf.get_position() == _size
