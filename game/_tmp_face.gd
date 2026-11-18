extends SceneTree
## temp: face close-up capture. args: out.png yaw_deg light(day|night|flat) glasses(0|1) clip time dist [scn]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var yaw := deg_to_rad(float(a[1]))
	var light: String = a[2]
	var glasses := a[3] == "1"
	var clip: String = a[4]
	var t := float(a[5])
	var dist := float(a[6])
	var scn: String = a[7] if a.size() > 7 else "res://assets/characters/sol/sol_modular.scn"
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	if light == "day":
		env.background_color = Color(0.55, 0.6, 0.68)
		env.ambient_light_color = Color(0.55, 0.6, 0.7)
		env.ambient_light_energy = 0.6
		var sun := DirectionalLight3D.new()
		sun.light_energy = 1.6
		sun.light_color = Color(1.0, 0.95, 0.88)
		sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(35), 0)
		sun.shadow_enabled = true
		w.add_child(sun)
	elif light == "night":
		env.background_color = Color(0.03, 0.035, 0.05)
		env.ambient_light_color = Color(0.25, 0.3, 0.45)
		env.ambient_light_energy = 0.25
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.72, 0.42)
		lamp.light_energy = 2.2
		lamp.omni_range = 6.0
		lamp.position = Vector3(0.9, 2.3, 1.0)
		lamp.shadow_enabled = true
		w.add_child(lamp)
		var moon := DirectionalLight3D.new()
		moon.light_color = Color(0.5, 0.6, 0.9)
		moon.light_energy = 0.35
		moon.rotation = Vector3(deg_to_rad(-30), deg_to_rad(-140), 0)
		w.add_child(moon)
	else:
		env.background_color = Color(0.45, 0.45, 0.45)
		env.ambient_light_color = Color(1, 1, 1)
		env.ambient_light_energy = 1.0
	var sol: Node3D = load(scn).instantiate()
	w.add_child(sol)
	var skel: Skeleton3D = sol.find_children("*", "Skeleton3D", true, false)[0]
	var flags: String = a[8] if a.size() > 8 else ""
	var hm := sol.find_child("HeadMesh", true, false) as MeshInstance3D
	if hm and flags != "":
		var m := (hm.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
		if "N" in flags: m.normal_enabled = false
		if "D" in flags: m.detail_enabled = false
		if "R" in flags: m.roughness_texture = null; m.roughness = 0.6
		if "A" in flags: m.ao_enabled = false
		if "S" in flags: m.rim_enabled = false
		hm.material_override = m
	var g := sol.find_child("Glasses", true, false)
	if g and not glasses:
		g.visible = false
	var ap: AnimationPlayer = sol.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation(clip):
		ap.play(clip)
		ap.seek(t, true)
		ap.pause()
	await process_frame
	await process_frame
	var hb := skel.find_bone("Head")
	var hp: Vector3 = skel.global_transform * skel.get_bone_global_pose(hb).origin
	var target := hp + Vector3(0, 0.07, 0.02)
	if dist > 1.2:
		target = hp + Vector3(0, -0.25, 0)
	if dist > 2.5:
		target = skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin + Vector3(0, 0.3, 0)
	var cam := Camera3D.new()
	cam.fov = 30.0
	w.add_child(cam)
	cam.position = target + Vector3(sin(yaw), 0.02, cos(yaw)) * dist
	cam.look_at(target, Vector3.UP)
	cam.current = true
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png(out)
	quit()
