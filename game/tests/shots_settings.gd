extends SceneTree
## PERF: screenshots of the settings panel (main menu + pause menu) and of the quality tiers.
##   xvfb-run godot --rendering-method gl_compatibility --resolution WxH -s res://tests/shots_settings.gd -- --out=DIR [--tiers]

var out := "user://shots"


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out + "/" + name + ".png")
	print("shot ", name)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var sz := root.get_visible_rect().size
	var tag := "%dx%d" % [int(sz.x), int(sz.y)]
	if "--tiers" in OS.get_cmdline_user_args():
		await _tiers(tag)
		quit()
		return
	# main menu -> Options
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	for i in 30: await process_frame
	menu.debug_show("options")
	for i in 10: await process_frame
	await _shot("menu_options_graphics_" + tag)
	var panel = menu.options.get_child(0)
	panel.show_tab(4)
	await _shot("menu_options_access_" + tag)
	menu.queue_free()
	await process_frame
	# in game -> pause -> Options (the world previews behind)
	load("res://scripts/main.gd").started_once = true
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	for i in 90: await process_frame
	if m.hunt != null and m.hunt.deploy != null and m.hunt.deploy.playing:
		m.hunt.deploy.finish()
	for i in 30: await process_frame
	m.pause_menu.open()
	await _shot("pause_list_" + tag)
	m.pause_menu._show("options")
	for i in 5: await process_frame
	await _shot("pause_options_graphics_" + tag)
	var p2 = m.pause_menu.options.get_child(0)
	p2.show_tab(1)
	await _shot("pause_options_display_" + tag)
	p2.show_tab(2)
	await _shot("pause_options_prefs_" + tag)
	p2.show_tab(3)
	await _shot("pause_options_audio_" + tag)
	quit()


func _tiers(tag: String) -> void:
	load("res://scripts/main.gd").started_once = true
	var hd = load("res://scripts/hunt/hunt_director.gd")
	hd.seed_override = 4242
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	for i in 90: await process_frame
	if m.hunt != null and m.hunt.deploy != null and m.hunt.deploy.playing:
		m.hunt.deploy.finish()
	if m.hunt != null:
		m.hunt.debug_view_camp()
	m.time_of_day = 0.85
	var st = root.get_node("Settings")
	for t in ["high", "veryLow", "low", "medium", "high"]:
		st.apply_tier_name(t, false)
		for i in 40: await process_frame
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		print("tier %s draws %d prims %d" % [t, draws, prims])
		await _shot("tier_%s_%s" % [t, tag])
