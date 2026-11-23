## WeaponIcons: killfeed / buy-menu icons rendered from the real weapon models (spec §9.2) at
## runtime, so icons never drift from the models and ship no image assets. Each weapon is drawn once
## as a flat white silhouette (side view, barrel pointing right) into a small transparent
## SubViewport, copied to an ImageTexture and cached. UI tints the silhouette with modulate.
class_name WeaponIcons
extends RefCounted

const SIZE := Vector2i(256, 96)

static var _cache: Dictionary = {}  ## weapon id -> Texture2D
static var _pending: Dictionary = {}  ## weapon id -> Array[Callable]
static var _silhouette: StandardMaterial3D


static func cached(weapon_id: String) -> Texture2D:
	return _cache.get(weapon_id) as Texture2D


## Calls `done(texture)` once the icon exists (immediately when cached). `host` must be in the tree.
static func request(host: Node, weapon_id: String, done: Callable) -> void:
	if _cache.has(weapon_id):
		done.call(_cache[weapon_id])
		return
	if _pending.has(weapon_id):
		(_pending[weapon_id] as Array).append(done)
		return
	_pending[weapon_id] = [done]
	_render(host.get_tree(), weapon_id)


## Fills a TextureRect when the icon is ready (safe if the rect is freed first).
static func apply(rect: TextureRect, weapon_id: String) -> void:
	request(rect, weapon_id, func(tex: Texture2D) -> void:
		if is_instance_valid(rect):
			rect.texture = tex)


static func _render(tree: SceneTree, weapon_id: String) -> void:
	if _silhouette == null:
		_silhouette = StandardMaterial3D.new()
		_silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_silhouette.albedo_color = Color.WHITE
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var model := WeaponBuilder.build(weapon_id)
	vp.add_child(model)
	var aabb := AABB()
	var first := true
	for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_override = _silhouette
		var box := m.transform * m.get_aabb()
		var p := m.get_parent()
		while p != null and p != model:
			box = (p as Node3D).transform * box
			p = p.get_parent()
		aabb = box if first else aabb.merge(box)
		first = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Side view from +X: camera right = -Z (barrel), so the muzzle points right on screen.
	cam.rotation.y = PI * 0.5
	var c := aabb.get_center()
	cam.position = c + Vector3(2.0, 0, 0)
	var aspect := float(SIZE.x) / SIZE.y
	cam.size = maxf(aabb.size.y, aabb.size.z / aspect) * 1.12
	cam.near = 0.05
	cam.far = 10.0
	vp.add_child(cam)
	tree.root.add_child.call_deferred(vp)
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var tex: Texture2D = null
	if img != null and not img.is_empty():
		tex = ImageTexture.create_from_image(img)
	vp.queue_free()
	if tex != null:
		_cache[weapon_id] = tex
	var waiters: Array = _pending.get(weapon_id, [])
	_pending.erase(weapon_id)
	for cb: Callable in waiters:
		cb.call(tex)
