## GDScript port of server/src/sim/movement.ts (spec §13.3 parity). Keep the operation order
## identical; golden vectors in shared/tests/movement/ must match the server to within 1 mm.
class_name SimMovement
extends RefCounted

const FORWARD := 1
const BACK := 2
const LEFT := 4
const RIGHT := 8
const JUMP := 16
const CROUCH := 32
const WALK := 64
const FIRE := 128
const ALT_FIRE := 256
const RELOAD := 512
const USE := 1024
const ABILITY_C := 2048
const ABILITY_Q := 4096
const ABILITY_E := 8192
const ABILITY_X := 16384

const SKIN := 0.001


## Movement state (plain doubles; mirrors MoveState in TypeScript).
class State:
	extends RefCounted
	var x: float = 0.0
	var y: float = 0.0
	var z: float = 0.0
	var vx: float = 0.0
	var vy: float = 0.0
	var vz: float = 0.0
	var grounded: bool = true
	var crouch: float = 0.0
	var landing_timer: float = 0.0
	var tag_timer: float = 0.0
	var tag_amount: float = 0.0
	var prev_buttons: int = 0

	func copy() -> State:
		var s := State.new()
		s.x = x
		s.y = y
		s.z = z
		s.vx = vx
		s.vy = vy
		s.vz = vz
		s.grounded = grounded
		s.crouch = crouch
		s.landing_timer = landing_timer
		s.tag_timer = tag_timer
		s.tag_amount = tag_amount
		s.prev_buttons = prev_buttons
		return s


static func new_state(px: float, py: float, pz: float) -> State:
	var s := State.new()
	s.x = px
	s.y = py
	s.z = pz
	return s


static func player_height(cfg: Dictionary, s: State) -> float:
	var cap: Dictionary = cfg["capsule"]
	return float(cap["height"]) + (float(cap["crouchHeight"]) - float(cap["height"])) * s.crouch


## One fixed tick. Mutates `s`.
static func step(cfg: Dictionary, w: SimWorld, s: State, buttons: int, yaw: float, run_speed: float) -> void:
	var dt := 1.0 / float(cfg["tickRate"])
	var cap: Dictionary = cfg["capsule"]
	var r: float = cap["radius"]
	var step_height: float = cfg["stepHeight"]
	var b := buttons
	# --- crouch
	var want_crouch := (b & CROUCH) != 0
	var crouch_rate := dt / float(cfg["crouchTransitionTime"])
	if want_crouch:
		s.crouch = minf(1.0, s.crouch + crouch_rate)
	else:
		var nxt := maxf(0.0, s.crouch - crouch_rate)
		var hh := float(cap["height"]) + (float(cap["crouchHeight"]) - float(cap["height"])) * nxt
		if not ceiling_blocked(w, s.x, s.y, s.z, r, hh):
			s.crouch = nxt
	# --- wish direction
	var fx := 0.0
	var fz := 0.0
	if b & FORWARD:
		fz -= 1.0
	if b & BACK:
		fz += 1.0
	if b & LEFT:
		fx -= 1.0
	if b & RIGHT:
		fx += 1.0
	var c := cos(yaw)
	var sn := sin(yaw)
	var wx := fx * c + fz * sn
	var wz := -fx * sn + fz * c
	var wl := sqrt(wx * wx + wz * wz)
	if wl > 0.0:
		wx /= wl
		wz /= wl
	# --- target speed
	var max_speed := run_speed
	if b & WALK:
		max_speed = minf(max_speed, float(cfg["walkSpeed"]))
	if s.crouch > 0.5:
		max_speed = minf(max_speed, float(cfg["crouchSpeed"]))
	if s.landing_timer > 0.0:
		max_speed *= float(cfg["landingSlow"]["multiplier"])
	if s.tag_timer > 0.0:
		max_speed *= 1.0 - s.tag_amount
	var tx := wx * max_speed
	var tz := wz * max_speed
	# --- horizontal acceleration
	var dvx := tx - s.vx
	var dvz := tz - s.vz
	var dl := sqrt(dvx * dvx + dvz * dvz)
	var rate: float
	if s.grounded:
		var opposing := tx * s.vx + tz * s.vz < 0.0
		rate = run_speed / float(cfg["decelerationTime"]) if (wl == 0.0 or opposing) else run_speed / float(cfg["accelerationTime"])
	else:
		rate = float(cfg["airAcceleration"])
	var max_dv := rate * dt
	if dl > max_dv:
		dvx = (dvx / dl) * max_dv
		dvz = (dvz / dl) * max_dv
	if s.grounded or wl > 0.0:
		s.vx += dvx
		s.vz += dvz
	# --- jump
	var jump_pressed := (b & JUMP) != 0 and (s.prev_buttons & JUMP) == 0
	if s.grounded and jump_pressed and s.crouch < 0.5:
		s.vy = sqrt(2.0 * float(cfg["gravity"]) * float(cfg["jumpHeight"]))
		s.grounded = false
	if not s.grounded:
		s.vy -= float(cfg["gravity"]) * dt
	# --- horizontal move + collision
	var h := player_height(cfg, s)
	s.x += s.vx * dt
	s.z += s.vz * dt
	for _pass: int in 3:
		var moved := false
		for i: int in w.count():
			var top := w.cy[i] + w.hy[i]
			var bottom := w.cy[i] - w.hy[i]
			if top <= s.y + step_height or bottom >= s.y + h:
				continue
			var ddx := s.x - w.cx[i]
			var ddz := s.z - w.cz[i]
			var reach := w.rxz[i] + r
			if ddx * ddx + ddz * ddz > reach * reach:
				continue
			var l := w.to_local(i, s.x, s.z)
			var lx := l[0]
			var lz := l[1]
			var ccx := maxf(-w.hx[i], minf(w.hx[i], lx))
			var ccz := maxf(-w.hz[i], minf(w.hz[i], lz))
			var nx := lx - ccx
			var nz := lz - ccz
			var d2 := nx * nx + nz * nz
			if d2 >= r * r:
				continue
			var push: float
			if d2 < 1e-12:
				var px := w.hx[i] - absf(lx)
				var pz := w.hz[i] - absf(lz)
				if px < pz:
					nx = 1.0 if lx >= 0.0 else -1.0
					nz = 0.0
					push = px + r
				else:
					nx = 0.0
					nz = 1.0 if lz >= 0.0 else -1.0
					push = pz + r
			else:
				var d := sqrt(d2)
				nx /= d
				nz /= d
				push = r - d
			var wn := w.to_world_dir(i, nx, nz)
			s.x += wn[0] * (push + SKIN)
			s.z += wn[1] * (push + SKIN)
			var vn := s.vx * wn[0] + s.vz * wn[1]
			if vn < 0.0:
				s.vx -= wn[0] * vn
				s.vz -= wn[1] * vn
			moved = true
		if not moved:
			break
	# --- vertical move
	var was_grounded := s.grounded
	var fall_speed := -s.vy
	s.y += s.vy * dt
	var ground := ground_height(w, s.x, s.y + step_height, s.z, r)
	if s.vy <= 0.0 and ground > -1e8 and s.y <= ground + (step_height if was_grounded else 0.0) + SKIN:
		s.y = ground
		s.vy = 0.0
		s.grounded = true
		if not was_grounded and fall_speed > 2.0:
			s.landing_timer = float(cfg["landingSlow"]["duration"])
	else:
		s.grounded = false
		if s.vy > 0.0 and ceiling_blocked(w, s.x, s.y, s.z, r, h):
			s.vy = 0.0
	# --- timers
	if s.landing_timer > 0.0:
		s.landing_timer = maxf(0.0, s.landing_timer - dt)
	if s.tag_timer > 0.0:
		s.tag_timer = maxf(0.0, s.tag_timer - dt)
	s.prev_buttons = b


static func ground_height(w: SimWorld, x: float, max_y: float, z: float, r: float) -> float:
	var best := -1e9
	for i: int in w.count():
		var top := w.cy[i] + w.hy[i]
		if top > max_y or top <= best:
			continue
		if not _circle_overlaps(w, i, x, z, r * 0.7):
			continue
		best = top
	return best


static func _circle_overlaps(w: SimWorld, i: int, x: float, z: float, r: float) -> bool:
	var ddx := x - w.cx[i]
	var ddz := z - w.cz[i]
	var reach := w.rxz[i] + r
	if ddx * ddx + ddz * ddz > reach * reach:
		return false
	var l := w.to_local(i, x, z)
	var ccx := maxf(-w.hx[i], minf(w.hx[i], l[0]))
	var ccz := maxf(-w.hz[i], minf(w.hz[i], l[1]))
	var nx := l[0] - ccx
	var nz := l[1] - ccz
	return nx * nx + nz * nz < r * r


static func ceiling_blocked(w: SimWorld, x: float, y: float, z: float, r: float, h: float) -> bool:
	for i: int in w.count():
		var bottom := w.cy[i] - w.hy[i]
		var top := w.cy[i] + w.hy[i]
		if bottom < y + 0.5 or bottom >= y + h or top <= y:
			continue
		if _circle_overlaps(w, i, x, z, r * 0.9):
			return true
	return false


static func speed_fraction(s: State, run_speed: float) -> float:
	return sqrt(s.vx * s.vx + s.vz * s.vz) / run_speed
