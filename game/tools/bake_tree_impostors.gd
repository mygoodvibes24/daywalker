extends SceneTree
## Renders the pine and the cypress (scripts/map/trees.gd) from the side on a transparent
## background into assets/textures/terrain/<name>_impostor.png, for the far forest's crossed
## billboard cards. Needs a renderer (not --headless):
##   xvfb-run -a godot --rendering-method gl_compatibility -s res://tools/bake_tree_impostors.gd

const Trees = preload("res://scripts/map/trees.gd")
## name: [mesh height, image w, image h] (the card's width/height ratio is w/h)
const BAKES := {"pine": [18.0, 256, 448], "cypress": [15.5, 384, 448]}


func _initialize() -> void:
	for name in BAKES.keys():
		var spec: Array = BAKES[name]
		var h: float = spec[0]
		var vp := SubViewport.new()
		vp.size = Vector2i(spec[1], spec[2])
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.own_world_3d = true
		root.add_child(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_CLEAR_COLOR
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.55, 0.58, 0.6)
		env.environment.ambient_light_energy = 0.6
		vp.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-0.7, 0.5, 0)
		sun.light_energy = 1.1
		vp.add_child(sun)
		var mi := MeshInstance3D.new()
		var mesh: ArrayMesh = Trees.cypress_mesh(h, 700) if name == "cypress" else Trees.pine_mesh(h, 900)
		var mat: ShaderMaterial = Trees.material().duplicate()
		mat.set_shader_parameter("wind", 0.0)
		mi.material_override = mat
		mi.mesh = mesh
		vp.add_child(mi)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		var top := h * 1.05
		cam.size = top
		cam.position = Vector3(0, top * 0.5, 60)
		vp.add_child(cam)
		cam.current = true
		for i in 6:
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.adjust_bcs(1.9, 1.0, 1.0) # the cards are lit again in game: store albedo, not the lit render
		var out := "res://assets/textures/terrain/%s_impostor.png" % name
		img.save_png(ProjectSettings.globalize_path(out))
		print("baked ", out, " ", img.get_size())
		vp.queue_free()
	quit()
