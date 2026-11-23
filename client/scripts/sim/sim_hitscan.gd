## GDScript port of server/src/sim/hitscan.ts. Used offline (the Range, practice) as the authority
## and online for instant local effects (impact decals) while waiting for server confirmation.
class_name SimHitscan
extends RefCounted

static var _hitboxes: Dictionary = {}
static var _tags: Array = []


static func hitboxes() -> Dictionary:
	if _hitboxes.is_empty():
		_hitboxes = SharedConfig.read_json("res://data/config/hitboxes.json")
	return _hitboxes


static func tags() -> Array:
	if _tags.is_empty():
		_tags = SharedConfig.read_json("res://data/config/materials.json")["tags"]
	return _tags


static func ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var l := o - c
	var b := l.dot(d)
	var cc := l.dot(l) - r * r
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var s := sqrt(disc)
	var t0 := -b - s
	if t0 >= 0.0:
		return t0
	return 0.0 if -b + s >= 0.0 else -1.0


static func ray_capsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var best := -1.0
	for i: int in 7:
		var t := ray_sphere(o, d, a.lerp(b, i / 6.0), r)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


static func hb_point(p: Array, pos: Vector3, yaw: float, crouch: float) -> Vector3:
	var sy := 1.0 + (float(hitboxes()["crouchScale"]) - 1.0) * crouch
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector3(pos.x + float(p[0]) * c + float(p[2]) * s, pos.y + float(p[1]) * sy, pos.z - float(p[0]) * s + float(p[2]) * c)


## targets: Array of {id, pos: Vector3, yaw, crouch}. Returns hit dictionary (see hitscan.ts).
static func trace(world: SimWorld, targets: Array, shooter_id: int, tier: String, o: Vector3, d: Vector3, range_m: float) -> Dictionary:
	var p_t := INF
	var p_id := -1
	var p_zone := "body"
	for tgt: Dictionary in targets:
		if int(tgt["id"]) == shooter_id:
			continue
		var pos: Vector3 = tgt["pos"]
		var to := pos + Vector3(0, 1, 0) - o
		var along := to.dot(d)
		if along < -1.0 or along > range_m + 1.0:
			continue
		if (to - d * along).length_squared() > 4.0:
			continue
		for cap: Dictionary in hitboxes()["capsules"]:
			var a := hb_point(cap["a"], pos, float(tgt["yaw"]), float(tgt.get("crouch", 0.0)))
			var b := hb_point(cap["b"], pos, float(tgt["yaw"]), float(tgt.get("crouch", 0.0)))
			var t := ray_capsule(o, d, a, b, float(cap["r"]))
			if t < 0.0 or t > range_m:
				continue
			var zone: String = "head" if cap["zone"] == "head" else ("leg" if cap["zone"] == "leg" else "body")
			if t < p_t - 1e-4 or (absf(t - p_t) <= 1e-4 and zone == "head"):
				p_t = t
				p_id = int(tgt["id"])
				p_zone = zone
	# Walls between the muzzle and the target (or the max range), with penetration.
	var scale := 1.0
	var wallbang := false
	var limit := minf(range_m, p_t)
	var hits: Array = []
	for i: int in world.count():
		var r := world.ray_box(i, o.x, o.y, o.z, d.x, d.y, d.z)
		if r.is_empty() or r[1] < 0.0 or r[0] > limit:
			continue
		hits.append([maxf(r[0], 0.0), minf(r[1], limit) - maxf(r[0], 0.0), i, int(r[2])])
	hits.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[2] < y[2]))
	for h: Array in hits:
		var box: int = h[2]
		var tag: Dictionary = tags()[world.tag[box]]
		if tag["id"] == "invisible":
			continue
		var thick: float = h[1]
		var block := thick > float(tag["maxThickness"][tier])
		if not block:
			scale *= maxf(0.0, 1.0 - float(tag["damageLossPerCm"][tier]) * thick * 100.0)
			wallbang = true
			block = scale <= 0.05
		if block:
			var t: float = h[0]
			var ld := [d.x * world.cs[box] - d.z * world.sn[box], d.y, d.x * world.sn[box] + d.z * world.cs[box]]
			var ln := [0.0, 0.0, 0.0]
			if int(h[3]) >= 0:
				ln[int(h[3])] = -signf(ld[int(h[3])])
			var wn := world.to_world_dir(box, ln[0], ln[2])
			return {"kind": "world", "t": t, "pos": o + d * t, "normal": Vector3(wn[0], ln[1], wn[1]), "impact": tag["impact"], "tag": tag["id"]}
	if p_id >= 0:
		return {"kind": "player", "t": p_t, "pos": o + d * p_t, "normal": -d, "player": p_id, "zone": p_zone, "scale": scale, "wallbang": wallbang, "impact": "flesh"}
	return {"kind": "none", "t": range_m, "pos": o + d * range_m}
