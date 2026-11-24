## Readability capture (spec definition of done: character contrast 3:1 or better everywhere).
## For every bookmark camera: stand an enemy agent ~10 m ahead on the floor, facing the camera, render
## with and without it, and measure silhouette-edge contrast: the median WCAG ratio between the agent's
## outline pixels and the background just outside them (see _measure). Writes a JSON report and a PNG
## per bookmark (`--overlay` draws the measured outline in cyan).
##   godot --path client res://scenes/dev/readability.tscn -- --map=neon --out=../qa/readability/<dir>
## Optional: --agent=<id> (default kestrel), --size=1920x1080 (measure at 1080p: outline widths are
## specified at 1080p), --only=<bookmark index>, --overlay.
extends Node3D

const PASS_RATIO := 3.0
const DIFF := 10  ## per-channel byte difference that marks an agent pixel
## Below this many agent pixels at 1080p the agent is mostly hidden (a fully visible one at 10 m is ~5k).
const MIN_PIXELS := 1500

var debug_overlay := false
var map: MapRuntime
var camera: Camera3D
var _lut := PackedFloat32Array()


func _ready() -> void:
	var args := Game.parse_user_args(OS.get_cmdline_user_args())
	var map_id := str(args.get("map", "solstice"))
	var out_dir := str(args.get("out", "user://readability"))
	var agent_id := str(args.get("agent", "kestrel"))
	debug_overlay = args.has("overlay")
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
	# TAA would blend history from the previous agent placement into these single frames; a
	# converged TAA image of a static scene is close to MSAA, so measure with MSAA instead.
	get_viewport().use_taa = false
	get_viewport().msaa_3d = Viewport.MSAA_4X
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
		# Full silhouette with the map hidden: edges where props cover the agent are occlusion
		# edges, not silhouette edges, and are left out of the measurement.
		map.visible = false
		var sky_only := await _grab()
		rig.global_position = at
		var agent_only := await _grab()
		map.visible = true
		var r := _measure(with_agent, without, box, _silhouette(agent_only, sky_only))
		if r.get("hidden", false):
			print("[readability] %-18s skipped (agent mostly hidden: %d px)" % [m["name"], r["pixels"]])
			continue
		if args.has("debug"):
			print("box ", box, " img ", with_agent.get_size(), " pixels ", r["pixels"], " rig ", rig.global_position)
		r["bookmark"] = m["name"]
		r["agent"] = agent_id
		r["pass"] = float(r["ratio"]) >= PASS_RATIO
		results.append(r)
		var file_base := "%02d_%s" % [idx, str(m["name"]).to_lower().replace(" ", "_")]
		with_agent.save_png(out_dir.path_join(file_base + ".png"))
		print("[readability] %-18s edge %.2f  p25 %.2f  outline>=3:1 %3d%%  fill %.2f  %s" % [m["name"], r["ratio"], r["p25"], int(float(r["edge_pass_share"]) * 100.0), r["fill_ratio"], "PASS" if r["pass"] else "FAIL"])
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
	# Chest and knees must both be visible: edges against occluding props are not silhouette edges.
	for hgt: float in [1.3, 0.45]:
		var p := rig.global_position + Vector3(0, hgt, 0)
		var q := PhysicsRayQueryParameters3D.create(camera.global_position, p)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(p) > 0.8:
			return false
	return true


func _grab() -> Image:
	for _i: int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _lum(d: PackedByteArray, i: int) -> float:
	return 0.2126 * _lut[d[i]] + 0.7152 * _lut[d[i + 1]] + 0.0722 * _lut[d[i + 2]]


## Silhouette-edge contrast (owner decision 2026-11-24). For every pixel on the agent's outline,
## take the boundary band (4 px at 1080p: the full two-tone outline), pair each band pixel with the
## background pixel 2 px outside, and keep the best WCAG ratio, i.e. the strongest edge the eye finds
## at that point of the silhouette. `ratio` is the median over the outline: what
## decides whether the silhouette separates from what is behind it, even when the average
## brightness matches (a dark-on-light half and a light-on-dark half both count).
## 4-connected flood fill over the mask's bounding box; returns the largest component only.
func _largest_region(mask: PackedByteArray, w: int, h: int, lo: Vector2i, hi: Vector2i) -> Dictionary:
	var label := PackedInt32Array()
	label.resize(w * h)
	var best := -1
	var best_size := 0
	var next := 1
	var stack := PackedInt32Array()
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			var start := y * w + x
			if mask[start] == 0 or label[start] != 0:
				continue
			var size := 0
			stack.append(start)
			label[start] = next
			while not stack.is_empty():
				var p: int = stack[stack.size() - 1]
				stack.remove_at(stack.size() - 1)
				size += 1
				var px := p % w
				var py := p / w
				for q: int in [p - 1 if px > 0 else -1, p + 1 if px < w - 1 else -1, p - w if py > 0 else -1, p + w if py < h - 1 else -1]:
					if q >= 0 and mask[q] != 0 and label[q] == 0:
						label[q] = next
						stack.append(q)
			if size > best_size:
				best_size = size
				best = next
			next += 1
	var out := PackedByteArray()
	out.resize(w * h)
	var nlo := Vector2i(w, h)
	var nhi := Vector2i(-1, -1)
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			if label[y * w + x] == best:
				out[y * w + x] = 1
				nlo = Vector2i(mini(nlo.x, x), mini(nlo.y, y))
				nhi = Vector2i(maxi(nhi.x, x), maxi(nhi.y, y))
	return {"mask": out, "lo": nlo, "hi": nhi}


## Full (unoccluded) agent silhouette from the map-hidden pair of frames.
func _silhouette(a: Image, b: Image) -> PackedByteArray:
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var da := a.get_data()
	var db := b.get_data()
	var out := PackedByteArray()
	out.resize(a.get_width() * a.get_height())
	for p: int in out.size():
		var i := p * 3
		if absi(da[i] - db[i]) > DIFF or absi(da[i + 1] - db[i + 1]) > DIFF or absi(da[i + 2] - db[i + 2]) > DIFF:
			out[p] = 1
	return out


func _measure(a: Image, b: Image, box: Rect2i, full: PackedByteArray) -> Dictionary:
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var da := a.get_data()
	var db := b.get_data()
	var w := a.get_width()
	var h := a.get_height()
	box = box.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var mask := PackedByteArray()
	mask.resize(w * h)
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	var la := 0.0
	var lb := 0.0
	var n := 0
	for y: int in range(box.position.y, box.end.y):
		for x: int in range(box.position.x, box.end.x):
			var i := (y * w + x) * 3
			# Agent pixel = changed AND inside the agent-only silhouette (sky/cloud drift, lighting
			# noise and reflections elsewhere in the frame can never qualify).
			if full[y * w + x] != 0 and (absi(da[i] - db[i]) > DIFF or absi(da[i + 1] - db[i + 1]) > DIFF or absi(da[i + 2] - db[i + 2]) > DIFF):
				mask[y * w + x] = 1
				la += _lum(da, i)
				lb += _lum(db, i)
				n += 1
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if n < MIN_PIXELS * h / 1080:
		return {"ratio": 0.0, "p25": 0.0, "edge_pass_share": 0.0, "fill_ratio": 0.0, "edge_pixels": 0, "pixels": n, "hidden": true}
	# Keep only the largest connected region: temporal/lighting noise leaves isolated specks.
	var keep := _largest_region(mask, w, h, lo, hi)
	mask = keep["mask"]
	lo = keep["lo"]
	hi = keep["hi"]
	la /= n
	lb /= n
	# Boundary band: 4 px at 1080p, the full width of the two-tone outline (2 px light + 2 px dark).
	var band := maxi(2, roundi(4.0 * h / 1080.0))
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	var ratios := PackedFloat32Array()
	for y: int in range(maxi(lo.y, 2), mini(hi.y + 1, h - 2)):
		for x: int in range(maxi(lo.x, 2), mini(hi.x + 1, w - 2)):
			if mask[y * w + x] == 0:
				continue
			for d: Vector2i in dirs:
				if mask[(y + d.y) * w + x + d.x] != 0:
					continue
				# Edge found: agent sample one step inward (if still agent), background two steps out.
				var ix := x - d.x
				var iy := y - d.y
				if mask[iy * w + ix] == 0:
					ix = x
					iy = y
				var ox := x + d.x * 2
				var oy := y + d.y * 2
				if mask[oy * w + ox] != 0:
					continue
				if full[(y + d.y) * w + x + d.x] != 0 or full[oy * w + ox] != 0:
					continue  # occlusion edge: a prop covers the agent here
				# The silhouette boundary is a 2 px band (outermost pixel + one inside): an outline
				# or rim lives there. Take whichever of the two separates more from the background.
				var l_out := _lum(db, (oy * w + ox) * 3)
				var best := 1.0
				for k: int in band:
					var bx := x - d.x * k
					var by := y - d.y * k
					if bx < 0 or by < 0 or bx >= w or by >= h or mask[by * w + bx] == 0:
						break
					var l_in := _lum(da, (by * w + bx) * 3)
					best = maxf(best, (maxf(l_in, l_out) + 0.05) / (minf(l_in, l_out) + 0.05))
				ratios.append(best)
				if debug_overlay:
					a.set_pixel(x, y, Color(0.2, 1.0, 0.9))  # measured outline in the debug image
				break
	if ratios.size() < 30:
		return {"ratio": 0.0, "p25": 0.0, "edge_pass_share": 0.0, "fill_ratio": 0.0, "edge_pixels": ratios.size(), "pixels": n}
	ratios.sort()
	var passing := 0
	for r: float in ratios:
		if r >= PASS_RATIO:
			passing += 1
	return {
		"ratio": ratios[ratios.size() >> 1],
		"p25": ratios[ratios.size() >> 2],
		"edge_pass_share": float(passing) / ratios.size(),
		"fill_ratio": (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05),
		"agent_l": la,
		"behind_l": lb,
		"edge_pixels": ratios.size(),
		"pixels": n,
	}
