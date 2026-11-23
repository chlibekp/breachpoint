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
		if not _place(rig):
			continue
		var box := _screen_box(rig)
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


func _grab() -> Image:
	for _i: int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _screen_box(rig: Node3D) -> Rect2i:
	var pts: Array[Vector2] = []
	for y: float in [0.0, 1.0, 1.95]:
		for o: Vector3 in [Vector3(-0.6, 0, -0.6), Vector3(0.6, 0, 0.6), Vector3(-0.6, 0, 0.6), Vector3(0.6, 0, -0.6)]:
			pts.append(camera.unproject_position(rig.global_position + o + Vector3(0, y, 0)))
	var r := Rect2(pts[0], Vector2.ZERO)
	for p: Vector2 in pts:
		r = r.expand(p)
	return Rect2i(r)


func _lum(d: PackedByteArray, i: int) -> float:
	return 0.2126 * _lut[d[i]] + 0.7152 * _lut[d[i + 1]] + 0.0722 * _lut[d[i + 2]]


func _measure(a: Image, b: Image, box: Rect2i) -> Dictionary:
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var da := a.get_data()
	var db := b.get_data()
	var w := a.get_width()
	# The box is in viewport (stretch) space; the grabbed image is in window pixels.
	var k := Vector2(a.get_size()) / get_viewport().get_visible_rect().size
	box = Rect2i(Vector2i(Vector2(box.position) * k), Vector2i((Vector2(box.size) * k).ceil()))
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
				# Outline the mask in the saved image for review.
				a.set_pixel(x, y, a.get_pixel(x, y).lerp(Color(1, 0, 1), 0.15))
	if n < 200:
		return {"ratio": 0.0, "agent_l": 0.0, "behind_l": 0.0, "pixels": n}
	la /= n
	lb /= n
	var ratio := (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
	return {"ratio": ratio, "agent_l": la, "behind_l": lb, "pixels": n}
