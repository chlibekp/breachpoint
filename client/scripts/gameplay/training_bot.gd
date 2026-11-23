## Range training bot (spec §8.4): an agent-shaped target with the shared hitboxes. Modes:
## "static" (lane targets), "strafe" (A-D with counter-strafes on the strafe track), "patrol".
## Uses the same deterministic movement sim as players so strafes look and feel identical.
class_name TrainingBot
extends Node3D

signal died(bot: TrainingBot)

var bot_id: int = 100
var mode: String = "static"
var world: SimWorld
var move := SimMovement.State.new()
var prev_pos := Vector3.ZERO
var yaw: float = 0.0
var health: float = 100.0
var max_health: float = 100.0
var alive := true
var rig: AgentRig
var anim: AgentAnimator
var track_a := Vector3.ZERO
var track_b := Vector3.ZERO
var _dir := 1
var _hold_ticks := 0
var _respawn_t := 0.0
var _flash := 0.0
var _label: Label3D
var _spawn := Vector3.ZERO


func setup(p_world: SimWorld, p_id: int, pos: Vector3, face_yaw: float, p_mode: String) -> void:
	world = p_world
	bot_id = p_id
	mode = p_mode
	_spawn = pos
	yaw = face_yaw
	move = SimMovement.new_state(pos.x, pos.y, pos.z)
	prev_pos = pos
	position = pos
	rig = AgentLooks.build("training_dummy")
	rig.rotation.y = yaw
	add_child(rig)
	anim = AgentAnimator.new()
	anim.setup(rig)
	anim.attach_weapon(WeaponBuilder.build("saber"))
	rig.add_child(anim)
	# Bots are hostile targets: subtle enemy rim so they read on any background (spec §4.4).
	rig.set_rim(Color("#FF4655"), 0.5)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font = load("res://assets/fonts/ChakraPetch-Bold.ttf")
	_label.font_size = 48
	_label.pixel_size = 0.004
	_label.position = Vector3(0, 2.15, 0)
	_label.modulate = Color(1, 1, 1, 0)
	_label.no_depth_test = true
	add_child(_label)


func target_info() -> Dictionary:
	return {"id": bot_id, "pos": Vector3(move.x, move.y, move.z), "yaw": yaw, "crouch": move.crouch}


func _physics_process(_delta: float) -> void:
	if world == null:
		return
	if not alive:
		_respawn_t -= 1.0 / 64.0
		if _respawn_t <= 0.0:
			_respawn()
		return
	prev_pos = Vector3(move.x, move.y, move.z)
	var b := 0
	if mode == "strafe":
		var target := track_b if _dir > 0 else track_a
		var to := target.x - move.x
		if _hold_ticks > 0:
			_hold_ticks -= 1
		elif absf(to) < 0.4 or randf() < 0.012:
			_dir = -_dir
			_hold_ticks = randi_range(0, 10)  # counter-strafe pause, like a player peeking
		else:
			b = SimMovement.RIGHT if (to > 0.0) == (cos(yaw) > 0.0) else SimMovement.LEFT
	elif mode == "patrol":
		var to2 := (track_b if _dir > 0 else track_a) - Vector3(move.x, 0, move.z)
		if to2.length() < 0.5:
			_dir = -_dir
		b = SimMovement.FORWARD | SimMovement.WALK
		yaw = atan2(-to2.x, -to2.z)
		rig.rotation.y = yaw
	SimMovement.step(Data.movement, world, move, b, yaw, 6.75)


func _process(delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	position = prev_pos.lerp(Vector3(move.x, move.y, move.z), f)
	if anim != null:
		var v := Vector3(move.vx, 0, move.vz)
		anim.velocity_local = rig.global_basis.inverse() * v
		anim.dead = not alive
	_flash = move_toward(_flash, 0.0, delta * 6.0)
	if rig != null:
		rig.set_reveal(_flash)
	_label.modulate.a = move_toward(_label.modulate.a, 0.0, delta * 1.2)
	_label.position.y += delta * 0.4


func take_hit(damage: float, zone: String) -> bool:
	if not alive:
		return false
	health -= damage
	_flash = 1.0
	_label.text = str(int(round(damage)))
	_label.modulate = Color("#FFD37A") if zone == "head" else Color("#ECE8E1")
	_label.position = Vector3(randf_range(-0.2, 0.2), 2.15, 0)
	if health <= 0.0:
		alive = false
		_respawn_t = 1.6
		died.emit(self)
		return true
	return false


func _respawn() -> void:
	alive = true
	health = max_health
	move = SimMovement.new_state(_spawn.x, _spawn.y, _spawn.z)
	prev_pos = _spawn
	anim.revive()
