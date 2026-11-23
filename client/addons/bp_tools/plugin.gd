@tool
extends EditorPlugin
## Pipeline automation inside the editor. Godot exposes no scripting API for LightmapGI baking,
## so when BP_BAKE_SCENES is set this plugin opens each listed scene, selects its LightmapGI,
## presses the editor's own "Bake Lightmaps" button, saves the scene and quits.
##
##   BP_BAKE_SCENES="res://scenes/dev/lightmap_test.tscn" godot --editor --path client
## (needs a display + a RenderingDevice renderer: Forward+ or Mobile; tools/bake-lightmaps.sh wraps it)

const BAKE_TIMEOUT_S := 1800.0


func _enter_tree() -> void:
	var scenes := OS.get_environment("BP_BAKE_SCENES")
	if scenes.is_empty():
		return
	_bake_all.call_deferred(scenes.split(",", false))


func _bake_all(scenes: PackedStringArray) -> void:
	# Let the editor finish its first-scan before opening scenes.
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	for _i: int in 30:
		await get_tree().process_frame
	var failures := 0
	for path: String in scenes:
		if not await _bake_one(path.strip_edges()):
			failures += 1
	print("[bp_tools] bake finished, %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _bake_one(path: String) -> bool:
	print("[bp_tools] baking %s" % path)
	EditorInterface.open_scene_from_path(path)
	await get_tree().process_frame
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_error("[bp_tools] could not open %s" % path)
		return false
	var lm: LightmapGI = root.find_children("*", "LightmapGI", true, false).front() if not root.find_children("*", "LightmapGI", true, false).is_empty() else null
	if lm == null:
		push_error("[bp_tools] %s has no LightmapGI" % path)
		return false
	var before: LightmapGIData = lm.light_data
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(lm)
	EditorInterface.set_main_screen_editor("3D")
	for _i: int in 10:
		await get_tree().process_frame
	var button := _find_bake_button(EditorInterface.get_base_control())
	if button == null:
		push_error("[bp_tools] Bake Lightmaps button not found")
		return false
	var t0 := Time.get_ticks_msec()
	button.pressed.emit()
	# First bake of a scene: the editor asks where to save the .lmbake. Answer with the default
	# (next to the scene) by emitting the dialog's file_selected signal the bake plugin listens to.
	var lmbake := path.get_basename() + ".lmbake"
	while lm.light_data == before or lm.light_data == null:
		await get_tree().create_timer(0.5).timeout
		var dialog := _find_visible_dialog(EditorInterface.get_base_control())
		if dialog != null:
			dialog.hide()
			dialog.file_selected.emit(lmbake)
		if (Time.get_ticks_msec() - t0) / 1000.0 > BAKE_TIMEOUT_S:
			push_error("[bp_tools] bake timed out for %s" % path)
			return false
	EditorInterface.save_scene()
	print("[bp_tools] baked %s in %.1f s" % [path, (Time.get_ticks_msec() - t0) / 1000.0])
	return true


func _find_bake_button(node: Node) -> Button:
	if node is Button and (node as Button).text.strip_edges() == "Bake Lightmaps" and (node as Button).is_visible_in_tree():
		return node
	for child: Node in node.get_children():
		var found := _find_bake_button(child)
		if found != null:
			return found
	return null


func _find_visible_dialog(node: Node) -> EditorFileDialog:
	if node is EditorFileDialog and (node as EditorFileDialog).visible:
		return node
	for child: Node in node.get_children():
		var found := _find_visible_dialog(child)
		if found != null:
			return found
	return null
