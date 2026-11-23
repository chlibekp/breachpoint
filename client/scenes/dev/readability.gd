## Readability capture (spec definition of done: character contrast 3:1 or better everywhere).
## For every bookmark camera: stand an enemy agent ~10 m ahead on the floor, facing the camera, render
## with and without it, and compare the mean relative luminance of the agent's pixels with the same
## pixels behind it (WCAG contrast ratio). Writes a JSON report and an annotated PNG per bookmark.
##   godot --path client res://scenes/dev/readability.tscn -- --map=neon --out=../qa/readability/<dir>
## Optional: --agent=<id> (default kestrel), --size=960x540.
extends Node3D

const PASS_RATIO := 3.0
const DIFF := 10  ## per-channel byte difference that marks an agent pixel

var map: MapRuntime
var camera: Camera3D
var _lut := PackedFloat32Array()


func _ready() -> void:
	var args := Game.parse_user_args(OS.get_cmdline_user_args())
	var map_id := str(args.get("map", "solstice"))
	var out_dir := str(args.get("out", "user://readability"))
	var agent_id := str(args.get("agent", "kestrel"))
	if args.has("size"):
		var wh := str(args["size"]).split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	for i: int in 256:
		var c := i / 255.0
		_lut.append(c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4))
	map = (load("res://scenes/maps/%s.tscn" % map_id) as PackedScene).instantiate() as MapRuntime
	add_child(map)
	# Freeze everything that animates so the only change between the two renders is the agent.
	map.freeze_ambient()
	var we := map.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null:
		# Glow halos and SSR reflections of the agent are not the agent: keep them out of the mask.
		we.environment.glow_enabled = false
		we.environment.ssr_enabled = false
	if we != null and we.environment.sky != null and we.environment.sky.sky_material is ShaderMaterial:
		(we.environment.sky.sky_material as ShaderMaterial).set_shader_parameter("cloud_speed", 0.0)
	for n: Node in map.find_children("*", "GPUParticles3D", true, false) + map.find_children("*", "CPUParticles3D", true, false):
		(n as Node3D).visible = false
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rig := AgentLooks.build(agent_id)
	add_child(rig)
	var anim := AgentAnimator.new()
	anim.setup(rig)
	anim.attach_weapon(WeaponBuilder.build("saber"))
	rig.add_child(anim)
	rig.set_rim(Color(1, 0.95, 0.88), 0.3)  # enemy look: neutral rim, no team highlight
	# The agent's shadow is not the agent: keep it out of the diff mask.
	for mi: Node in rig.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Let shaders compile and the lightmap stream in before measuring.
	for _i: int in 20:
		await get_tree().process_frame
	var results: Array = []
	var marks: Array = map.bookmarks()
	for idx: int in marks.size():
		if args.has("only") and idx != int(args["only"]):
			continue
		var m: Dictionary = marks[idx]
		if float(m.get("fov", 75.0)) < 70.0 or MapRuntime.vec(m["pos"]).y > 12.0:
			continue  # overview / sky shots: no player stands there
		camera.position = MapRuntime.vec(m["pos"])
		camera.look_at(MapRuntime.vec(m["lookAt"]))
		camera.fov = float(m.get("fov", 75.0))
		if camera.global_rotation.x > 0.5:
			continue  # sky shots (e.g. the monolith): nobody stands in that view
		if not _place(rig) or not _in_sight(rig):
			print("[readability] %-18s skipped (no clear spot in view)" % m["name"])
			continue
		var box := Rect2i(0, 0, 100000, 100000)
		var with_agent := await _grab()
		# Some rig parts are not under the rig's visibility, so move it out of view instead.
		var at := rig.global_position
		rig.global_position = at + Vector3(0, -500, 0)
		var without := await _grab()
		rig.global_position = at
		var r := _measure(with_agent, without, box)
		if args.has("debug"):
			print("box ", box, " img ", with_agent.get_size(), " pixels ", r["pixels"], " rig ", rig.global_position)
		r["bookmark"] = m["name"]
		r["agent"] = agent_id
		r["pass"] = float(r["ratio"]) >= PASS_RATIO
		results.append(r)
		var file_base := "%02d_%s" % [idx, str(m["name"]).to_lower().replace(" ", "_")]
		with_agent.save_png(out_dir.path_join(file_base + ".png"))
		print("[readability] %-18s ratio %.2f  agent L %.3f  behind L %.3f  %s" % [m["name"], r["ratio"], r["agent_l"], r["behind_l"], "PASS" if r["pass"] else "FAIL"])
	var worst := 99.0
	for r: Dictionary in results:
		worst = minf(worst, float(r["ratio"]))
	var report := {"map": map_id, "agent": agent_id, "renderer": RenderingServer.get_current_rendering_method(), "pass_ratio": PASS_RATIO, "worst": worst, "results": results}
	var f := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[readability] %s worst %.2f (%d bookmarks) -> %s" % [map_id, worst, results.size(), out_dir])
	get_tree().quit(0 if worst >= PASS_RATIO else 2)


## Puts the agent ~10 m ahead (or before the first wall), on the floor, facing the camera.
func _place(rig: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var fwd := -camera.global_basis.z
	fwd.y = 0
	if fwd.length() < 0.1:
		return false
	fwd = fwd.normalized()
	var from := camera.global_position
	var dist := 10.0
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 12.0)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		dist = maxf(2.5, from.distance_to(hit["position"]) - 1.2)
	var p := from + fwd * dist
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP, p + Vector3.DOWN * 6.0))
	if down.is_empty():
		return false
	rig.global_position = (down["position"] as Vector3)
	rig.look_at(Vector3(from.x, rig.global_position.y, from.z), Vector3.UP, true)
	return true


## Clear line from the camera to the agent's chest (placement did not drop it behind cover).
func _in_sight(rig: Node3D) -> bool:
	var chest := rig.global_position + Vector3(0, 1.3, 0)
	var q := PhysicsRayQueryParameters3D.create(camera.global_position, chest)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(chest) < 0.8


func _grab() -> Image:
	for _i: int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _lum(d: PackedByteArray, i: int) -> float:
	return 0.2126 * _lut[d[i]] + 0.7152 * _lut[d[i + 1]] + 0.0722 * _lut[d[i + 2]]


func _measure(a: Image, b: Image, box: Rect2i) -> Dictionary:
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var da := a.get_data()
	var db := b.get_data()
	var w := a.get_width()
	box = box.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var la := 0.0
	var lb := 0.0
	var n := 0
	for y: int in range(box.position.y, box.end.y):
		for x: int in range(box.position.x, box.end.x):
			var i := (y * w + x) * 3
			if absi(da[i] - db[i]) > DIFF or absi(da[i + 1] - db[i + 1]) > DIFF or absi(da[i + 2] - db[i + 2]) > DIFF:
				la += _lum(da, i)
				lb += _lum(db, i)
				n += 1
				# Tint the mask in the saved image for review.
				a.set_pixel(x, y, a.get_pixel(x, y).lerp(Color(1, 0, 1), 0.25))
	if n < 200:
		return {"ratio": 0.0, "agent_l": 0.0, "behind_l": 0.0, "pixels": n}
	la /= n
	lb /= n
	var ratio := (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
	return {"ratio": ratio, "agent_l": la, "behind_l": lb, "pixels": n}
