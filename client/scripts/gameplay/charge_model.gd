## The Breach Charge (spec §10.3): a chunky Rift-tech device — carried on the back, planted with a
## pulsing emissive core and a visible beam. Built with MeshKit like every other prop.
class_name ChargeModel
extends RefCounted


static func build(planted: bool = false) -> MeshInstance3D:
	var body := MeshKit.new()
	body.with_color(Color(1, 0, 0))
	body.box(Vector3(0.36, 0.14, 0.26), Vector3(0, 0.07, 0), 0.03)
	body.cylinder(0.11, 0.2, Vector3(0, 0.22, 0), 12, 0.02)
	for sx: float in [-1.0, 1.0]:
		body.box(Vector3(0.04, 0.18, 0.28), Vector3(sx * 0.2, 0.09, 0), 0.01)
	body.with_color(Color(0, 0, 1))
	body.cylinder(0.075, 0.24, Vector3(0, 0.23, 0), 12, 0.01)
	body.with_color(Color(0, 1, 0))
	body.box(Vector3(0.3, 0.02, 0.06), Vector3(0, 0.145, 0.1), 0.005)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/master/M_Weapon.gdshader")
	mat.set_shader_parameter("accent_color", Color("#FF4655"))
	mat.set_shader_parameter("emissive_color", Color("#B77CFF"))
	mat.set_shader_parameter("emissive_energy", 3.5 if planted else 1.5)
	var mi := MeshInstance3D.new()
	mi.name = "BreachCharge"
	mi.mesh = body.commit(mat)
	if planted:
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.07
		cyl.height = 30.0
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bm.albedo_color = Color(0.7, 0.45, 1.0, 0.35)
		cyl.material = bm
		beam.mesh = cyl
		beam.position = Vector3(0, 15.2, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(beam)
		var light := OmniLight3D.new()
		light.light_color = Color("#B77CFF")
		light.omni_range = 3.0
		light.light_energy = 1.2
		light.position = Vector3(0, 0.4, 0)
		mi.add_child(light)
	return mi
