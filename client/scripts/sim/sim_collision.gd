## Port of server/src/sim/collision.ts: yaw-only boxes from <map>.collision.bin. Plain float
## arrays (64-bit) instead of Vector3 (32-bit) so results match the server to the millimetre.
class_name SimWorld
extends RefCounted

var cx := PackedFloat64Array()
var cy := PackedFloat64Array()
var cz := PackedFloat64Array()
var hx := PackedFloat64Array()
var hy := PackedFloat64Array()
var hz := PackedFloat64Array()
var cs := PackedFloat64Array()
var sn := PackedFloat64Array()
var rxz := PackedFloat64Array()
var tag := PackedInt32Array()


func count() -> int:
	return cx.size()


func add_box(px: float, py: float, pz: float, ex: float, ey: float, ez: float, yaw: float, t: int) -> void:
	cx.append(px)
	cy.append(py)
	cz.append(pz)
	hx.append(ex)
	hy.append(ey)
	hz.append(ez)
	cs.append(cos(yaw))
	sn.append(sin(yaw))
	rxz.append(sqrt(ex * ex + ez * ez))
	tag.append(t)


static func from_bytes(bytes: PackedByteArray) -> SimWorld:
	var w := SimWorld.new()
	if bytes.size() < 10 or bytes.slice(0, 6).get_string_from_ascii() != "BPCOL1":
		push_error("SimWorld: bad collision data")
		return w
	var n := bytes.decode_u32(6)
	var off := 10
	for i: int in n:
		w.add_box(bytes.decode_float(off), bytes.decode_float(off + 4), bytes.decode_float(off + 8), bytes.decode_float(off + 12), bytes.decode_float(off + 16), bytes.decode_float(off + 20), bytes.decode_float(off + 24), bytes[off + 28])
		off += 29
	return w


static func load_map(map_id: String) -> SimWorld:
	return from_bytes(FileAccess.get_file_as_bytes("res://data/maps/%s.collision.bin" % map_id))


## Box-local XZ of a world point. Returns [lx, lz].
func to_local(i: int, x: float, z: float) -> PackedFloat64Array:
	var dx := x - cx[i]
	var dz := z - cz[i]
	return PackedFloat64Array([dx * cs[i] - dz * sn[i], dx * sn[i] + dz * cs[i]])


func to_world_dir(i: int, lx: float, lz: float) -> PackedFloat64Array:
	return PackedFloat64Array([lx * cs[i] + lz * sn[i], -lx * sn[i] + lz * cs[i]])


## Ray vs box i. Returns [t_enter, t_exit, axis] or empty.
func ray_box(i: int, ox: float, oy: float, oz: float, dx: float, dy: float, dz: float) -> PackedFloat64Array:
	var lo := to_local(i, ox, oz)
	var o := [lo[0], oy - cy[i], lo[1]]
	var d := [dx * cs[i] - dz * sn[i], dy, dx * sn[i] + dz * cs[i]]
	var h := [hx[i], hy[i], hz[i]]
	var tmin := -INF
	var tmax := INF
	var axis := -1
	for k: int in 3:
		var ok: float = o[k]
		var dk: float = d[k]
		var hk: float = h[k]
		if absf(dk) < 1e-12:
			if ok < -hk or ok > hk:
				return PackedFloat64Array()
			continue
		var t1 := (-hk - ok) / dk
		var t2 := (hk - ok) / dk
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		if t1 > tmin:
			tmin = t1
			axis = k
		if t2 < tmax:
			tmax = t2
		if tmin > tmax:
			return PackedFloat64Array()
	return PackedFloat64Array([tmin, tmax, axis])


## Nearest blocking hit along a ray (ignores the "invisible" tag 6). Returns {t, nx, ny, nz, tag} or {}.
func raycast(ox: float, oy: float, oz: float, dx: float, dy: float, dz: float, max_t: float) -> Dictionary:
	var best := {}
	var best_t := max_t
	for i: int in count():
		if tag[i] == 6:
			continue
		var r := ray_box(i, ox, oy, oz, dx, dy, dz)
		if r.is_empty() or r[1] < 0.0 or r[0] > best_t:
			continue
		var t := maxf(r[0], 0.0)
		if t >= best_t:
			continue
		best_t = t
		var ld := [dx * cs[i] - dz * sn[i], dy, dx * sn[i] + dz * cs[i]]
		var ln := [0.0, 0.0, 0.0]
		var ax := int(r[2])
		if ax >= 0:
			ln[ax] = -signf(ld[ax])
		var wn := to_world_dir(i, ln[0], ln[2])
		best = {"t": t, "nx": wn[0], "ny": ln[1], "nz": wn[1], "tag": tag[i], "box": i}
	return best
