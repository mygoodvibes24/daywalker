extends SceneTree
## temp: render each map GLB
func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.32, 0.36)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	root.add_child(cam)
	for n in ["gantry_crane", "shipping_container", "trailer_home", "cypress_tree", "plantation_facade"]:
		var inst: Node3D = load("res://assets/props/map/%s.glb" % n).instantiate()
		root.add_child(inst)
		var bb := AABB()
		var first := true
		var tris := 0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			bb = b if first else bb.merge(b)
			first = false
			for s in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_array_index_len(s) / 3
		print("GLB %s size %s tris %d" % [n, bb.size, tris])
		var c := bb.get_center()
		var r := bb.size.length()
		cam.position = c + Vector3(r * 0.6, r * 0.3, r * 0.75)
		cam.look_at(c)
		for i in 4: await process_frame
		root.get_texture().get_image().save_png("%s/glb_%s.png" % [out, n])
		inst.queue_free()
		await process_frame
	quit()
