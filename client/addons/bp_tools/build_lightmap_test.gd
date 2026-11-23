## Builds res://scenes/dev/lightmap_test.tscn: a small SOLSTICE-palette courtyard used to verify
## LightmapGI baking and rendering on both renderers (milestone 1). Geometry is BLOCKOUT_ only.
## Run: godot --headless --path client -s res://addons/bp_tools/build_lightmap_test.gd
extends SceneTree

const OUT := "res://scenes/dev/lightmap_test.tscn"

# SOLSTICE palette (docs/art/maps/solstice.md): cream base, terracotta secondary, sea-teal accent.
const CREAM := Color("#EFE3C8")
const CREAM_SHADE := Color("#D9C9A8")
const TERRACOTTA := Color("#C8643B")
const TEAL := Color("#2BA6A4")
const STONE := Color("#B9AE9A")
const WOOD := Color("#8A5A3A")

var _root: Node3D
var _root_name := "LightmapTest"


func _init() -> void:
	_root = Node3D.new()
	_root.name = "LightmapTest"

	_environment()
	var static_root := Node3D.new()
	static_root.name = "BLOCKOUT_Static"
	_add(_root, static_root)

	# Floor 20 x 20 m, stone plaza.
	_box(static_root, "BLOCKOUT_Floor", Vector3(20, 0.4, 20), Vector3(0, -0.2, 0), _mat(STONE, 0.85))
	# Back wall (terracotta) and left wall (cream) to show coloured bounce.
	_box(static_root, "BLOCKOUT_WallBack", Vector3(20, 6, 0.6), Vector3(0, 3, -10), _mat(TERRACOTTA, 0.9))
	_box(static_root, "BLOCKOUT_WallLeft", Vector3(0.6, 6, 20), Vector3(-10, 3, 0), _mat(CREAM, 0.92))
	_box(static_root, "BLOCKOUT_WallRightA", Vector3(0.6, 4.5, 8), Vector3(10, 2.25, -6), _mat(CREAM_SHADE, 0.92))
	_box(static_root, "BLOCKOUT_WallRightB", Vector3(0.6, 4.5, 8), Vector3(10, 2.25, 6), _mat(CREAM_SHADE, 0.92))
	# Doorway lintel over the 4 m gap in the right wall.
	_box(static_root, "BLOCKOUT_Lintel", Vector3(0.8, 1.0, 4.4), Vector3(10, 4.0, 0), _mat(CREAM, 0.9))
	# Cornice trim (strong horizontal, spec 4.1).
	_box(static_root, "BLOCKOUT_CorniceBack", Vector3(20, 0.35, 1.0), Vector3(0, 6.1, -9.8), _mat(CREAM, 0.8))
	_box(static_root, "BLOCKOUT_CorniceLeft", Vector3(1.0, 0.35, 20), Vector3(-9.8, 6.1, 0), _mat(CREAM, 0.8))
	# Cover: crates, a low wall, a pillar, a teal-shuttered kiosk.
	_box(static_root, "BLOCKOUT_CrateA", Vector3(1.2, 1.2, 1.2), Vector3(-3, 0.6, -4), _mat(WOOD, 0.75))
	_box(static_root, "BLOCKOUT_CrateB", Vector3(1.2, 1.2, 1.2), Vector3(-1.75, 0.6, -4.2), _mat(WOOD, 0.75))
	_box(static_root, "BLOCKOUT_CrateC", Vector3(1.2, 1.2, 1.2), Vector3(-2.4, 1.8, -4.1), _mat(WOOD, 0.75))
	_box(static_root, "BLOCKOUT_LowWall", Vector3(5, 1.0, 0.6), Vector3(3, 0.5, 2), _mat(CREAM_SHADE, 0.9))
	_box(static_root, "BLOCKOUT_Pillar", Vector3(1.0, 6, 1.0), Vector3(-6, 3, -6), _mat(CREAM, 0.88))
	_box(static_root, "BLOCKOUT_Kiosk", Vector3(3, 2.6, 2), Vector3(5, 1.3, -7.5), _mat(CREAM, 0.9))
	_box(static_root, "BLOCKOUT_KioskShutter", Vector3(2.4, 1.6, 0.1), Vector3(5, 1.4, -6.45), _mat(TEAL, 0.6))
	_box(static_root, "BLOCKOUT_Awning", Vector3(3.4, 0.12, 1.4), Vector3(5, 2.75, -6.0), _mat(TERRACOTTA, 0.8))

	# Dynamic "agent" proxy lit by the lightmap probes: 1.8 m capsule in a saturated accent.
	var agent := MeshInstance3D.new()
	agent.name = "BLOCKOUT_AgentProxy"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	agent.mesh = capsule
	agent.material_override = _mat(Color("#FF7A1A"), 0.5)
	agent.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	agent.position = Vector3(0.5, 0.9, -1.5)
	_add(_root, agent)

	_lights()

	var lm := LightmapGI.new()
	lm.name = "LightmapGI"
	lm.quality = LightmapGI.BAKE_QUALITY_HIGH
	lm.bounces = 3
	lm.use_denoiser = true
	lm.directional = false
	lm.texel_scale = 2.0
	lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_SCENE
	lm.generate_probes_subdiv = LightmapGI.GENERATE_PROBES_SUBDIV_8
	_add(_root, lm)

	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 75.0
	cam.position = Vector3(7.5, 1.65, 7.5)
	_add(_root, cam)
	cam.look_at_from_position(cam.position, Vector3(-2.0, 1.4, -4.0))
	cam.current = true

	var packed := PackedScene.new()
	packed.pack(_root)
	var err := ResourceSaver.save(packed, OUT)
	_root.free()
	if err == OK:
		err = _attach_script(OUT, "res://scenes/dev/lightmap_test.gd")
	print("saved %s: %s" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = _root


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _box(parent: Node, node_name: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.add_uv2 = true
	mesh.uv2_padding = 4.0
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	_add(parent, mi)
	# Hand-authored simple collision (spec 8.1), mirrors the render box.
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_add(mi, body)
	_add(body, shape)


func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#5C86C9")
	sky_mat.sky_horizon_color = Color("#C9D6E3")
	sky_mat.ground_horizon_color = Color("#C9C2B5")
	sky_mat.ground_bottom_color = Color("#6E665A")
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.2
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_density = 0.0015
	env.fog_light_color = Color("#B8C7D9")
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(_root, we)


func _lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("#FFE2B8")  # ~5200 K, slightly golden
	sun.light_energy = 1.6
	sun.light_indirect_energy = 1.4
	sun.shadow_enabled = true
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC
	sun.directional_shadow_max_distance = 80.0
	sun.rotation_degrees = Vector3(-38, -52, 0)
	_add(_root, sun)


## The scene script uses autoload singletons, which do not exist in `-s` mode, so it is attached
## by editing the saved text scene instead of via set_script().
func _attach_script(scene_path: String, script_path: String) -> Error:
	var text := FileAccess.get_file_as_string(scene_path)
	var header_end := text.find("\n\n")
	var ext := '[ext_resource type="Script" path="%s" id="bp_script"]\n\n' % script_path
	text = text.substr(0, header_end + 2) + ext + text.substr(header_end + 2)
	var re := RegEx.create_from_string('(\\[node name="%s" type="Node3D"[^\\]]*\\]\\n)' % _root_name)
	text = re.sub(text, '$1script = ExtResource("bp_script")\n')
	var f := FileAccess.open(scene_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	return OK
