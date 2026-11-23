## GDScript port of server/src/sim/weapons.ts: the client predicts fire timing, ammo and the exact
## shot direction (pattern + seeded spread) that the server will compute (spec §13.4).
class_name SimWeapons
extends RefCounted

const DEG := PI / 180.0


class State:
	extends RefCounted
	var id: String = ""
	var ammo: int = 0
	var reserve: int = 0
	var next_fire: float = 0.0
	var reload_end: float = 0.0
	var equip_end: float = 0.0
	var recoil_index: float = 0.0
	var last_shot: float = -1e9
	var burst_left: int = 0
	var shot_counter: int = 0
	var spin_time: float = 0.0
	var trigger_held: bool = false


static func new_state(def: Dictionary, now: float = 0.0) -> State:
	var s := State.new()
	s.id = def["id"]
	s.ammo = int(def["magazine"])
	s.reserve = int(def["reserveAmmo"])
	s.next_fire = now
	s.equip_end = now + float(def["equipTime"])
	return s


static func current_spread(def: Dictionary, st: State, speed_frac: float, standing_threshold: float, crouched: bool, airborne: bool, ads: bool) -> float:
	var sp: Dictionary = def["spread"]
	var s := float(sp["base"]) + minf(float(sp["max"]), st.recoil_index * float(sp["perShot"]))
	var over := maxf(0.0, speed_frac - standing_threshold) / (1.0 - standing_threshold)
	s += over * float(def["movementSpreadMult"])
	if airborne:
		s += float(def["movementSpreadMult"]) * 1.5 + 2.0
	if crouched:
		s *= 0.85
	var a: Variant = def["ads"]
	if a is Dictionary:
		var ad: Dictionary = a
		if ads:
			s *= 1.0 - float(ad["accuracyBonus"])
		elif ad.get("scoped", false) and ad.has("unscopedSpread"):
			s += float(ad["unscopedSpread"])
	return s


static func _fire_interval(def: Dictionary, st: State, ads: bool) -> float:
	var rate := float(def["fireRate"])
	if def["spinUp"] is Dictionary:
		var su: Dictionary = def["spinUp"]
		rate = float(su["startRate"]) + (float(su["endRate"]) - float(su["startRate"])) * minf(1.0, st.spin_time / float(su["time"]))
	if ads and def["ads"] is Dictionary:
		rate *= float(def["ads"]["fireRateMult"])
	return 1.0 / rate


static func update(def: Dictionary, st: State, now: float, dt: float, trigger_held: bool) -> void:
	if st.reload_end > 0.0 and now >= st.reload_end:
		var take := mini(int(def["magazine"]) - st.ammo, st.reserve)
		st.ammo += take
		st.reserve -= take
		st.reload_end = 0.0
	if now - st.last_shot > float(def["spread"]["recoveryDelay"]):
		st.recoil_index = maxf(0.0, st.recoil_index - float(def["spread"]["recoveryRate"]) * dt)
	if def["spinUp"] is Dictionary:
		st.spin_time = st.spin_time + dt if trigger_held else maxf(0.0, st.spin_time - dt * 2.0)
	if not trigger_held:
		st.burst_left = 0


static func start_reload(def: Dictionary, st: State, now: float) -> bool:
	if st.reload_end > 0.0 or st.ammo >= int(def["magazine"]) or st.reserve <= 0 or int(def["magazine"]) == 0:
		return false
	st.reload_end = now + float(def["reloadTime"])
	st.burst_left = 0
	return true


## Returns {} or {yaw, pitch (pattern offsets, rad), pellets: [[yaw, pitch], ...], shot}.
static func try_fire(def: Dictionary, st: State, now: float, speed_frac: float, standing_threshold: float, crouched: bool, airborne: bool, ads: bool, seed_value: int, player_id: int, pressed: bool, held: bool) -> Dictionary:
	if now < st.equip_end or st.reload_end > 0.0 or now < st.next_fire:
		st.trigger_held = held
		return {}
	if int(def["magazine"]) > 0 and st.ammo <= 0:
		st.trigger_held = held
		return {}
	var mode: String = "semi" if (def["ads"] is Dictionary and ads and def["id"] == "lancer") else str(def["fireMode"])
	var fire := false
	if st.burst_left > 0:
		fire = true
	elif mode == "auto":
		fire = held
	else:
		fire = pressed
	st.trigger_held = held
	if not fire:
		return {}
	var spread_deg := current_spread(def, st, speed_frac, standing_threshold, crouched, airborne, ads)
	var pattern: Array = def["recoil"]["pattern"]
	var idx := mini(int(floorf(st.recoil_index)), pattern.size() - 1)
	var pat: Array = pattern[idx]
	var frac: float = st.recoil_index - floorf(st.recoil_index)
	var nxt: Array = pattern[mini(idx + 1, pattern.size() - 1)]
	var px: float = float(pat[0]) + (float(nxt[0]) - float(pat[0])) * frac
	var py: float = float(pat[1]) + (float(nxt[1]) - float(pat[1])) * frac
	var rng := SimRng.new(SimRng.hash_seed(seed_value, player_id * 65536 + st.shot_counter))
	var pellets: Array = []
	for _i: int in int(def["damage"]["pellets"]):
		var a := rng.next() * PI * 2.0
		var r := sqrt(rng.next()) * spread_deg
		pellets.append([(px + cos(a) * r) * DEG, (py + sin(a) * r) * DEG])
	var shot := {"yaw": px * DEG, "pitch": py * DEG, "pellets": pellets, "shot": st.shot_counter}
	st.shot_counter += 1
	if int(def["magazine"]) > 0:
		st.ammo -= 1
	st.recoil_index = minf(st.recoil_index + 1.0, pattern.size() - 1 + 0.999)
	st.last_shot = now
	if mode == "burst" and def["burst"] is Dictionary:
		var burst: Dictionary = def["burst"]
		if st.burst_left == 0:
			st.burst_left = int(burst["count"]) - 1
		else:
			st.burst_left -= 1
		st.next_fire = now + (float(burst["interval"]) if st.burst_left > 0 else _fire_interval(def, st, ads))
	else:
		st.next_fire = now + _fire_interval(def, st, ads)
	return shot


static func damage_at(def: Dictionary, distance: float, zone: String) -> float:
	var mult := 1.0
	for step: Dictionary in def["damage"]["falloff"]:
		if distance >= float(step["range"]):
			mult = float(step["multiplier"])
	var zm := float(def["damage"]["headMult"]) if zone == "head" else (float(def["damage"]["legMult"]) if zone == "leg" else 1.0)
	return float(def["damage"]["body"]) * mult * zm


## View direction from yaw/pitch (yaw 0 = -Z, pitch + up).
static func view_dir(yaw: float, pitch: float) -> Vector3:
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)
