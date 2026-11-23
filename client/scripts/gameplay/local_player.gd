## The local player: input -> shared deterministic sim at a fixed 64 Hz (spec §17.2), rendered with
## interpolation between ticks. Owns the first-person camera, viewmodel, weapons and footsteps.
## Offline, shots are resolved by the GameSession; online (milestone 4) the same inputs are sent to
## the server and reconciled (see Prediction in scripts/net/).
class_name LocalPlayer
extends Node3D

signal shot_fired(origin: Vector3, dirs: Array, weapon_id: String, shot_number: int)
signal weapon_changed(weapon_id: String)
signal reloaded

const SLOTS := ["primary", "secondary", "melee"]

var session: Node  ## GameSession (resolve_shot, seed)
var world: SimWorld
var cfg: Dictionary
var agent_id: String = "kestrel"
var player_id: int = 0
var team: int = 0

var move := SimMovement.State.new()
var prev_pos := Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var tick: int = 0
var sim_time: float = 0.0
var input_enabled := true
var alive := true
var health := 100.0
var shield := 0.0
var credits := 800

var loadout: Dictionary = {}  ## slot -> {def: Dictionary, st: SimWeapons.State}
var slot: String = "secondary"
var camera: Camera3D
var head: Node3D
var viewmodel: Viewmodel
var vm_anim: ViewmodelAnimator

var _mouse_delta := Vector2.ZERO
var _frame_mouse := Vector2.ZERO
var _punch := Vector2.ZERO  ## visual camera punch (pitch, yaw) radians
var _shake := 0.0
var _step_dist := 0.0
var _was_grounded := true
var _fire_prev := false
var _ads_held := false
var buttons: int = 0
var input_history: Array = []  ## [{seq, tick, buttons, yaw, pitch, slot, state: SimMovement.State}]
var seq: int = 0
var online := false
var server_tick_estimate := 0.0  ## set by the net session (clock sync)
var render_tick := 0.0  ## server tick remote players are rendered at
var _correction := Vector3.ZERO  ## visual offset smoothing small reconciliation errors
var reconcile_count := 0
var last_correction_m := 0.0


func setup(p_session: Node, p_world: SimWorld, spawn: Vector3, spawn_yaw: float) -> void:
	session = p_session
	world = p_world
	cfg = Data.movement
	move = SimMovement.new_state(spawn.x, spawn.y, spawn.z)
	prev_pos = spawn
	position = spawn
	yaw = spawn_yaw
	head = Node3D.new()
	head.name = "Head"
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.03
	camera.far = 900.0
	camera.current = true
	head.add_child(camera)
	viewmodel = Viewmodel.new()
	camera.add_child(viewmodel)
	viewmodel.setup(agent_id, "wasp")
	vm_anim = ViewmodelAnimator.new(viewmodel)
	give_weapon("melee", "knife")
	give_weapon("secondary", "wasp")
	equip("secondary")
	Sfx.listener = camera
	Sfx.world = world


func give_weapon(slot_name: String, weapon_id: String) -> void:
	var def: Dictionary = Data.get_weapon(weapon_id)
	loadout[slot_name] = {"def": def, "st": SimWeapons.new_state(def, sim_time)}


func equip(slot_name: String) -> void:
	if not loadout.has(slot_name):
		return
	slot = slot_name
	var entry: Dictionary = loadout[slot]
	var def: Dictionary = entry["def"]
	var st: SimWeapons.State = entry["st"]
	st.equip_end = sim_time + float(def["equipTime"])
	st.reload_end = 0.0
	viewmodel.equip(def["id"])
	vm_anim.on_equip(float(def["equipTime"]))
	Sfx.play_2d("weapons", "equip", -8.0, "Weapons")
	weapon_changed.emit(def["id"])


func current() -> Dictionary:
	return loadout.get(slot, {})


func eye_position() -> Vector3:
	return Vector3(move.x, move.y + lerpf(1.62, 1.05, move.crouch), move.z)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens: float = float(Settings.get_value("controls", "sensitivity")) * 0.07
		if vm_anim.ads > 0.5:
			sens *= float(Settings.get_value("controls", "ads_multiplier")) / _ads_zoom()
		var rel := mm.screen_relative
		_mouse_delta += rel
		yaw -= deg_to_rad(rel.x * sens)
		var inv := -1.0 if Settings.get_value("controls", "invert_y") else 1.0
		pitch = clampf(pitch - deg_to_rad(rel.y * sens) * inv, deg_to_rad(-89), deg_to_rad(89))
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("weapon_primary"):
		equip("primary")
	elif event.is_action_pressed("weapon_secondary"):
		equip("secondary")
	elif event.is_action_pressed("weapon_melee"):
		equip("melee")
	elif event.is_action_pressed("inspect"):
		vm_anim.on_inspect()
	elif event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ads_zoom() -> float:
	var def: Dictionary = current().get("def", {})
	return float(def["ads"]["zoom"]) if def.get("ads") is Dictionary else 1.0


func read_buttons() -> int:
	if not input_enabled or not alive:
		return 0
	var b := 0
	var map := {"move_forward": SimMovement.FORWARD, "move_back": SimMovement.BACK, "move_left": SimMovement.LEFT, "move_right": SimMovement.RIGHT, "jump": SimMovement.JUMP, "crouch": SimMovement.CROUCH, "walk": SimMovement.WALK, "fire": SimMovement.FIRE, "alt_fire": SimMovement.ALT_FIRE, "reload": SimMovement.RELOAD, "use": SimMovement.USE, "ability_c": SimMovement.ABILITY_C, "ability_q": SimMovement.ABILITY_Q, "ability_e": SimMovement.ABILITY_E, "ability_x": SimMovement.ABILITY_X}
	for action: String in map:
		if Input.is_action_pressed(action):
			b |= int(map[action])
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		b &= ~(SimMovement.FIRE | SimMovement.ALT_FIRE)
	return b


func run_speed() -> float:
	var def: Dictionary = current().get("def", {})
	var s := float(def.get("runSpeed", 6.75))
	if vm_anim != null and vm_anim.ads > 0.5 and def.get("ads") is Dictionary:
		s *= float(def["ads"]["moveSpeedMult"])
	return s * float(get_meta("speed_mult", 1.0))


func _physics_process(_delta: float) -> void:
	if world == null:
		return
	buttons = read_buttons()
	simulate_tick(buttons)


## One authoritative-equivalent tick (also used for replay during reconciliation).
func simulate_tick(b: int) -> void:
	var dt := 1.0 / float(cfg["tickRate"])
	prev_pos = Vector3(move.x, move.y, move.z)
	_was_grounded = move.grounded
	var fall_speed := -move.vy
	SimMovement.step(cfg, world, move, b, yaw, run_speed())
	tick += 1
	sim_time += dt
	seq += 1
	input_history.append({"seq": seq, "tick": int(server_tick_estimate) if online else tick, "buttons": b, "yaw": yaw, "pitch": pitch, "slot": SLOTS.find(slot), "state": move.copy()})
	if input_history.size() > 128:
		input_history.pop_front()
	if move.grounded and not _was_grounded:
		vm_anim.on_land(clampf(fall_speed / 8.0, 0.2, 1.0))
		Sfx.play_3d("footsteps", "stone_land", Vector3(move.x, move.y, move.z), -4.0, "Footsteps")
	_footsteps(b, dt)
	_weapons(b, dt)


func _footsteps(b: int, dt: float) -> void:
	var speed := Vector2(move.vx, move.vz).length()
	if not move.grounded or (b & SimMovement.WALK) != 0 or move.crouch > 0.5 or speed < 3.5:
		_step_dist = 0.0
		return
	_step_dist += speed * dt
	if _step_dist > 2.1:
		_step_dist = 0.0
		Sfx.play_3d("footsteps", "stone", Vector3(move.x, move.y + 0.05, move.z), -8.0, "Footsteps", 40.0)


func _weapons(b: int, dt: float) -> void:
	var entry: Dictionary = current()
	if entry.is_empty() or not alive:
		return
	var def: Dictionary = entry["def"]
	var st: SimWeapons.State = entry["st"]
	var held := (b & SimMovement.FIRE) != 0
	var pressed := held and not _fire_prev
	_fire_prev = held
	_ads_held = (b & SimMovement.ALT_FIRE) != 0 and def.get("ads") is Dictionary
	var was_reloading := st.reload_end > 0.0
	SimWeapons.update(def, st, sim_time, dt, held)
	if was_reloading and st.reload_end == 0.0:
		reloaded.emit()
	if (b & SimMovement.RELOAD) != 0 or (st.ammo == 0 and int(def["magazine"]) > 0 and pressed):
		if SimWeapons.start_reload(def, st, sim_time):
			vm_anim.on_reload(float(def["reloadTime"]), st.ammo == 0)
			Sfx.play_2d("weapons", "mag_out", -6.0, "Weapons")
			get_tree().create_timer(float(def["reloadTime"]) * 0.55).timeout.connect(func() -> void: Sfx.play_2d("weapons", "mag_in", -6.0, "Weapons"))
	if st.ammo == 0 and int(def["magazine"]) > 0 and pressed and st.reload_end == 0.0:
		Sfx.play_2d("weapons", "dry_fire", -8.0, "Weapons")
	var speed_frac := SimMovement.speed_fraction(move, float(def["runSpeed"]))
	var seed_value: int = int(session.get("round_seed")) if session != null else 1
	var shot := SimWeapons.try_fire(def, st, sim_time, speed_frac, float(Data.movement["standingAccuracyThreshold"]), move.crouch > 0.5, not move.grounded, vm_anim.ads > 0.5, seed_value, player_id, pressed, held)
	if shot.is_empty():
		return
	var origin := eye_position()
	var dirs: Array = []
	for p: Array in shot["pellets"]:
		dirs.append(SimWeapons.view_dir(yaw - float(p[0]), pitch + float(p[1])))
	shot_fired.emit(origin, dirs, def["id"], int(shot["shot"]))
	_on_local_fire(def, origin, dirs)


func _on_local_fire(def: Dictionary, _origin: Vector3, _dirs: Array) -> void:
	var punch := float(def["recoil"]["cameraPunch"])
	var reduced: bool = Settings.get_value("accessibility", "reduced_shake")
	_punch += Vector2(deg_to_rad(0.35 * punch), deg_to_rad(randf_range(-0.12, 0.12) * punch))
	_shake = minf(1.0, _shake + float(def["recoil"]["shake"]) * (0.4 if reduced else 1.0))
	vm_anim.on_fire(punch)
	if def["class"] == "melee":
		Sfx.play_2d("weapons", "equip", -4.0, "Weapons")
		return
	Sfx.gunshot(def["id"], eye_position(), true)
	var muzzle := viewmodel.weapon.get_node_or_null("muzzle") as Node3D
	var fx := session.get("effects") as Effects if session != null else null
	if muzzle != null and fx != null and not def.get("silenced", false):
		fx.muzzle_flash(muzzle.global_transform, 1.0, true)
	var eject := viewmodel.weapon.get_node_or_null("eject") as Node3D
	if eject != null and fx != null:
		fx.eject_shell(eject.global_transform, camera.global_basis.x)


func _process(delta: float) -> void:
	if world == null:
		return
	var f := Engine.get_physics_interpolation_fraction()
	var cur := Vector3(move.x, move.y, move.z)
	_correction = _correction.lerp(Vector3.ZERO, 1.0 - exp(-delta / 0.1 * 3.0))
	position = prev_pos.lerp(cur, f) + _correction
	var eye_h := lerpf(1.62, 1.05, move.crouch)
	head.position = Vector3(0, eye_h, 0)
	# Visual punch decays; shake is a small high-frequency jitter.
	_punch = _punch.lerp(Vector2.ZERO, 1.0 - exp(-delta * 14.0))
	_shake = move_toward(_shake, 0.0, delta * 5.0)
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * deg_to_rad(0.25)
	head.rotation = Vector3(pitch + _punch.x + jitter.x, yaw + _punch.y + jitter.y, 0)
	var fov := float(Settings.get_value("video", "fov"))
	var zoom := lerpf(1.0, _ads_zoom(), ease(vm_anim.ads, -2.0))
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) * 0.5) / zoom))
	var vel_local := head.global_basis.inverse() * Vector3(move.vx, move.vy, move.vz)
	_frame_mouse = _mouse_delta
	_mouse_delta = Vector2.ZERO
	var def: Dictionary = current().get("def", {})
	viewmodel.visible = not (def.get("ads") is Dictionary and def["ads"].get("scoped", false) and vm_anim.ads > 0.6)
	vm_anim.update(delta, _frame_mouse, vel_local, move.grounded, SimMovement.speed_fraction(move, 6.75), _ads_held)


## Server reconciliation (spec §13.3): rewind to the authoritative state for `last_seq` and replay
## the inputs the server has not processed yet. Errors under 2 cm are smoothed over 100 ms.
func reconcile(last_seq: int, st: Dictionary) -> void:
	var idx := -1
	for i: int in input_history.size():
		if int(input_history[i]["seq"]) == last_seq:
			idx = i
			break
	if idx < 0:
		return
	var predicted: SimMovement.State = input_history[idx]["state"]
	var server_pos: Vector3 = st["pos"]
	var err := Vector3(predicted.x, predicted.y, predicted.z).distance_to(server_pos)
	# Quantisation (1 mm) means we never match exactly; only act on real divergence.
	if err < 0.004 and not (st.has("force") and st["force"]):
		input_history = input_history.slice(idx)
		return
	reconcile_count += 1
	last_correction_m = err
	var before := Vector3(move.x, move.y, move.z)
	var s := SimMovement.State.new()
	s.x = server_pos.x
	s.y = server_pos.y
	s.z = server_pos.z
	var v: Vector3 = st["vel"]
	s.vx = v.x
	s.vy = v.y
	s.vz = v.z
	var flags := int(st["flags"])
	s.grounded = (flags & 1) != 0
	s.crouch = float((flags >> 8) & 0xFF) / 255.0
	s.prev_buttons = int(input_history[idx]["buttons"])
	s.landing_timer = predicted.landing_timer
	s.tag_timer = predicted.tag_timer
	s.tag_amount = predicted.tag_amount
	input_history[idx]["state"] = s.copy()
	for i: int in range(idx + 1, input_history.size()):
		var e: Dictionary = input_history[i]
		SimMovement.step(cfg, world, s, int(e["buttons"]), float(e["yaw"]), run_speed())
		e["state"] = s.copy()
	move = s
	var after := Vector3(move.x, move.y, move.z)
	if err < 0.02:
		_correction += before - after  # smoothed: rendered position eases back over ~100 ms
	else:
		prev_pos = after  # large error: snap
	input_history = input_history.slice(idx)


## Teleport (spawn/round start): resets prediction history.
func teleport(pos: Vector3, new_yaw: float) -> void:
	move = SimMovement.new_state(pos.x, pos.y, pos.z)
	prev_pos = pos
	yaw = new_yaw
	pitch = 0.0
	input_history.clear()
	_correction = Vector3.ZERO
	alive = true
	health = 100.0


func take_damage(amount: float, _from: Vector3) -> void:
	if not alive:
		return
	var absorbed := minf(shield, amount * 0.66)
	shield -= absorbed
	health -= amount - absorbed
	Sfx.play_2d("ui", "damage_taken", -4.0)
	if health <= 0.0:
		health = 0.0
		alive = false
