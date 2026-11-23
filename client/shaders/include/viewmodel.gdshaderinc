// First-person viewmodel projection (spec §7.2): fixed FOV independent of the world FOV, and depth
// squeezed toward the near plane so weapons/arms never clip into walls.
// NOTE: writing POSITION anywhere disables Godot's built-in projection, so this always writes it.
uniform bool viewmodel = false;
uniform float viewmodel_fov = 68.0;

void viewmodel_project(vec3 vertex, mat4 modelview, mat4 projection, inout vec4 position) {
	vec4 vpos = modelview * vec4(vertex, 1.0);
	if (!viewmodel) {
		position = projection * vpos;
		return;
	}
	float f = 1.0 / tan(radians(viewmodel_fov) * 0.5);
	// Keep the renderer's sign conventions (Vulkan flips Y in the projection).
	float aspect = abs(projection[1][1] / projection[0][0]);
	mat4 p = projection;
	p[0][0] = sign(projection[0][0]) * f / aspect;
	p[1][1] = sign(projection[1][1]) * f;
	position = p * vpos;
	// Godot 4.7 uses reversed-Z on every renderer (verified on Forward+ and Compatibility): near = w.
	position.z = mix(position.w, position.z, 0.06);
}
