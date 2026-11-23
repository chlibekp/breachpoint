## Procedural third-person animation for AgentRig (spec §6.3): idle breathing, 8-way walk/run via
## IK foot placement, crouch, jump/air pose, upper-body aim offsets (yaw ±90°, pitch ±80°),
## weapon holds per class through two-bone arm IK, and a short death reaction.
## Inputs are set every frame by the owner (local player view, remote interpolation, bots).
class_name AgentAnimator
extends Node

var rig: AgentRig
var weapon: Node3D  ## WeaponModel (has sockets grip / left_hand_ik)

## Inputs
var velocity_local := Vector3.ZERO  ## m/s in the rig's frame (-Z forward)
var crouch: float = 0.0  ## 0..1
var airborne: bool = false
var aim_pitch: float = 0.0  ## radians, + up
var aim_yaw_offset: float = 0.0  ## radians relative to the body
var weapon_class: String = "rifle"
var firing_kick: float = 0.0
var dead: bool = false

var _phase: float = 0.0
var _t: float = 0.0
var _death_t: float = 0.0
var _weapon_pivot: Node3D


func setup(target_rig: AgentRig) -> void:
	rig = target_rig
	_weapon_pivot = Node3D.new()
	_weapon_pivot.name = "weapon_pivot"
	rig.add_child(_weapon_pivot)


func attach_weapon(model: Node3D) -> void:
	if weapon != null:
		weapon.queue_free()
	weapon = model
	_weapon_pivot.add_child(model)


func _process(delta: float) -> void:
	if rig == null:
		return
	_t += delta
	var speed := Vector2(velocity_local.x, velocity_local.z).length()
	var run := clampf(speed / 6.75, 0.0, 1.0)
	_phase = fmod(_phase + delta * lerpf(1.6, 2.6, run) * (1.0 if speed > 0.25 else 0.0) * PI, TAU)
	firing_kick = move_toward(firing_kick, 0.0, delta * 8.0)
	rig.reset_pose()
	if dead:
		_pose_death(delta)
		return
	var bones := rig.bones
	var hips: Node3D = bones["hips"]
	var stride := clampf(speed * 0.11, 0.0, 0.42)
	var bob := absf(sin(_phase)) * 0.035 * run
	var breathe := sin(_t * 1.7) * 0.006
	hips.position.y = 0.96 - crouch * 0.36 - bob + breathe * 0.5 - (0.0 if not airborne else -0.02)
	# Body leans into the movement direction a little.
	var move_dir := Vector3(velocity_local.x, 0, velocity_local.z).normalized() if speed > 0.1 else Vector3.ZERO
	hips.rotation = Vector3(-move_dir.z * 0.05 * run + crouch * 0.12, 0, move_dir.x * 0.04 * run)
	# Aim offsets distributed over spine/chest/neck.
	var pitch := clampf(aim_pitch, deg_to_rad(-80), deg_to_rad(80))
	var yaw := clampf(aim_yaw_offset, deg_to_rad(-90), deg_to_rad(90))
	(bones["spine"] as Node3D).rotation = Vector3(pitch * 0.25 + breathe, yaw * 0.3, 0)
	(bones["chest"] as Node3D).rotation = Vector3(pitch * 0.35 - crouch * 0.1, yaw * 0.4, 0)
	(bones["neck"] as Node3D).rotation = Vector3(pitch * 0.25, yaw * 0.2, 0)
	(bones["head"] as Node3D).rotation = Vector3(pitch * 0.15 - (hips.rotation.x), yaw * 0.1, 0)
	_legs(stride, run, speed, move_dir)
	_arms(pitch, yaw)


func _legs(stride: float, run: float, speed: float, move_dir: Vector3) -> void:
	var rig_xf := rig.global_transform
	for side: String in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var ph := _phase + (0.0 if side == "l" else PI)
		var swing := sin(ph)
		var lift := maxf(0.0, cos(ph)) * (0.12 + 0.1 * run) if speed > 0.25 else 0.0
		var foot := Vector3(sx * (0.11 + crouch * 0.05), 0.09 + lift, 0.0) + move_dir * swing * stride
		if crouch > 0.0:
			foot.z += (0.12 if side == "l" else -0.18) * crouch
		if airborne:
			foot = Vector3(sx * 0.12, 0.35 + (0.1 if side == "l" else 0.0), -0.05 if side == "l" else 0.1)
		var target := rig_xf * foot
		var knee_pole := rig_xf * (Vector3(sx * 0.12, 0.5, -1.0))
		rig.solve_two_bone("thigh_" + side, "shin_" + side, "foot_" + side, target, knee_pole)
		# Keep feet flat-ish and pointing forward.
		var foot_bone: Node3D = rig.bones["foot_" + side]
		foot_bone.global_basis = rig_xf.basis * Basis(Vector3.RIGHT, -lift * 1.5)


func _arms(pitch: float, yaw: float) -> void:
	var rig_xf := rig.global_transform
	# Weapon pivot at the right shoulder pocket; rotates with aim.
	var hold := {"sidearm": Vector3(0.05, 1.42, -0.42), "melee": Vector3(0.2, 1.1, -0.25), "heavy": Vector3(0.16, 1.18, -0.3)}.get(weapon_class, Vector3(0.14, 1.42, -0.18)) as Vector3
	hold.y -= crouch * 0.36
	_weapon_pivot.position = hold + Vector3(0, 0, firing_kick * 0.04)
	_weapon_pivot.rotation = Vector3(pitch * 0.92 + firing_kick * 0.06, yaw * 0.95, 0)
	if weapon == null:
		return
	var grip := weapon.get_node_or_null("grip") as Node3D
	var support := weapon.get_node_or_null("left_hand_ik") as Node3D
	if grip != null:
		rig.solve_two_bone("upper_arm_r", "forearm_r", "hand_r", grip.global_position, rig_xf * Vector3(0.6, 0.7, 0.3))
		(rig.bones["hand_r"] as Node3D).global_basis = grip.global_basis
	if support != null and weapon_class != "melee":
		rig.solve_two_bone("upper_arm_l", "forearm_l", "hand_l", support.global_position, rig_xf * Vector3(-0.6, 0.7, 0.2))
		(rig.bones["hand_l"] as Node3D).global_basis = support.global_basis


func _pose_death(delta: float) -> void:
	_death_t = minf(_death_t + delta, 1.0)
	var e := ease(_death_t, 0.4)
	var hips: Node3D = rig.bones["hips"]
	hips.position.y = lerpf(0.96, 0.2, e)
	hips.rotation.x = lerpf(0.0, -1.35, e)
	(rig.bones["thigh_l"] as Node3D).rotation.x = lerpf(0.0, 1.0, e)
	(rig.bones["thigh_r"] as Node3D).rotation.x = lerpf(0.0, 0.5, e)
	(rig.bones["shin_l"] as Node3D).rotation.x = lerpf(0.0, -1.4, e)
	(rig.bones["upper_arm_l"] as Node3D).rotation.z = lerpf(0.0, -1.2, e)
	(rig.bones["upper_arm_r"] as Node3D).rotation.z = lerpf(0.0, 1.0, e)
	if weapon != null:
		weapon.visible = _death_t < 0.3
