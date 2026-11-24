## Character review sheet (art pass): one agent as a turnaround (front, 3/4, side, back), a face
## close-up, or all eight in a row, on a neutral studio stage or on the Range. Prints triangle
## counts per agent. Usage:
##   -- --capture=res://scenes/dev/charsheet.tscn --agent=kestrel --view=turn|face|bust|all
##      [--pose=rest|aim] [--stage=studio|range] [--size=WxH] --out=<png>
extends Node3D

const IDS: Array[String] = ["kestrel", "mamba", "vesper", "haldor", "orin", "sable", "imani", "tomas"]


func _ready() -> void:
	var args := Game.parse_user_args(OS.get_cmdline_user_args())
	var agent := str(args.get("agent", "kestrel"))
	var view := str(args.get("view", "turn"))
	var pose := str(args.get("pose", "rest"))
	if str(args.get("stage", "studio")) == "range":
		add_child((load("res://scenes/maps/range.tscn") as PackedScene).instantiate())
	else:
		_studio()
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	match view:
		"face":
			_spawn(agent, Vector3.ZERO, 180.0 + float(args.get("yaw", "20")), pose)
			cam.fov = 22
			cam.position = Vector3(0, 1.69, 0.75)
			cam.look_at(Vector3(0, 1.68, 0))
		"bust":
			_spawn(agent, Vector3.ZERO, 180.0 + float(args.get("yaw", "25")), pose)
			cam.fov = 30
			cam.position = Vector3(0, 1.5, 1.6)
			cam.look_at(Vector3(0, 1.42, 0))
		"busts":
			var set_i := int(args.get("set", "0"))
			for i: int in 4:
				_spawn(IDS[set_i * 4 + i], Vector3(-1.35 + i * 0.9, 0, 0), 180.0 + float(args.get("yaw", "20")), pose)
			cam.fov = 30
			cam.position = Vector3(0, 1.48, 3.3)
			cam.look_at(Vector3(0, 1.4, 0))
		"all":
			for i: int in IDS.size():
				_spawn(IDS[i], Vector3(-4.2 + i * 1.2, 0, 0), 180.0 + float(args.get("yaw", "0")), pose)
			cam.fov = 40
			cam.position = Vector3(0, 1.2, 7.6)
			cam.look_at(Vector3(0, 0.95, 0))
		_:
			var yaws := [180.0, 225.0, 270.0, 0.0]
			for i: int in 4:
				_spawn(agent, Vector3(-1.95 + i * 1.3, 0, 0), yaws[i], pose)
			cam.fov = 32
			cam.position = Vector3(0, 1.0, 5.6)
			cam.look_at(Vector3(0, 0.92, 0))
	for id: String in (IDS if view in ["all", "busts"] else [agent]):
		var probe := AgentLooks.build(id)
		var meshes := probe.find_children("*", "MeshInstance3D", true, false).size()
		print("[charsheet] %s triangles: %d, mesh instances: %d" % [id, _tris(probe, args.has("parts")), meshes])


func _spawn(id: String, pos: Vector3, yaw: float, pose: String) -> void:
	var rig := AgentLooks.build(id)
	rig.position = pos
	rig.rotation_degrees.y = yaw
	add_child(rig)
	var anim := AgentAnimator.new()
	anim.setup(rig)
	if pose == "aim":
		anim.attach_weapon(WeaponBuilder.build("saber"))
	rig.add_child(anim)


func _tris(rig: AgentRig, per_part: bool = false) -> int:
	var n := 0
	var parts: Dictionary = {}
	for mi: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s: int in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var tri := idx.size() / 3 if not idx.is_empty() else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			n += tri
			var key := "%s/%s" % [mi.get_parent().name, mi.name]
			parts[key] = int(parts.get(key, 0)) + tri
	if per_part:
		var keys: Array = parts.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(parts[a]) > int(parts[b]))
		for key: Variant in keys.slice(0, 14):
			print("    %6d  %s" % [int(parts[key]), str(key)])
	rig.free()
	return n


func _studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#3A4250")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8C96AA")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#FFE8CC")
	key.light_energy = 1.5
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-38, 35, 0)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#9DB4FF")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-15, -140, 0)
	add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#59606B")
	fm.roughness = 0.9
	floor_mi.material_override = fm
	add_child(floor_mi)
