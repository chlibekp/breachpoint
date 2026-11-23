## Look-dev scene (milestone 2): SOLSTICE B site + KESTREL with the Saber in several poses + the
## first-person viewmodel. Camera from map bookmarks; used by the QA capture
## (`-- --capture=res://scenes/dev/lookdev.tscn --bookmark=N [--fp]`).
extends Node3D

const MAP := "res://scenes/maps/solstice.tscn"

var map: MapRuntime
var camera: Camera3D
var viewmodel: Viewmodel
var agents: Array[AgentRig] = []


func _ready() -> void:
	map = (load(MAP) as PackedScene).instantiate() as MapRuntime
	add_child(map)
	var args := Game.parse_user_args(OS.get_cmdline_user_args())
	var b := Vector3(10, 0, -32)
	# Three KESTRELs: idle facing the plaza, walking/aiming, crouched behind cover.
	_spawn_agent(b + Vector3(22.5, 0, 26.5), 200.0, {"pitch": 0.0})
	_spawn_agent(b + Vector3(16.5, 0, 13.5), 135.0, {"walk": Vector3(0, 0, -3.0), "pitch": -0.05})
	_spawn_agent(b + Vector3(26.0, 0, 13.4), 160.0, {"crouch": 1.0, "pitch": 0.1})
	_spawn_agent(b + Vector3(-1.5, 0, 24.0), 270.0, {"pitch": 0.0})
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 75.0
	camera.cull_mask = 0xFFFFF
	add_child(camera)
	var idx := int(args.get("bookmark", "0"))
	set_bookmark(idx)
	if args.has("fp"):
		viewmodel = Viewmodel.new()
		camera.add_child(viewmodel)
		viewmodel.setup("kestrel", "saber")


func set_bookmark(idx: int) -> void:
	var marks: Array = map.bookmarks()
	if marks.is_empty():
		return
	var m: Dictionary = marks[clampi(idx, 0, marks.size() - 1)]
	camera.position = MapRuntime.vec(m["pos"])
	camera.look_at(MapRuntime.vec(m["lookAt"]))
	camera.fov = float(m.get("fov", 75.0))


func _spawn_agent(pos: Vector3, yaw_deg: float, pose: Dictionary) -> void:
	var rig := AgentLooks.build("kestrel")
	rig.position = pos
	rig.rotation_degrees.y = yaw_deg
	add_child(rig)
	var anim := AgentAnimator.new()
	anim.setup(rig)
	anim.attach_weapon(WeaponBuilder.build("saber"))
	anim.velocity_local = pose.get("walk", Vector3.ZERO)
	anim.crouch = pose.get("crouch", 0.0)
	anim.aim_pitch = pose.get("pitch", 0.0)
	rig.add_child(anim)
	agents.append(rig)
