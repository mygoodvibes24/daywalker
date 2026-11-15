extends SceneTree
## temp: perf at camera points. args: out_prefix "x,z,yaw;x,z,yaw;..." [height]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	print("PERF load ms: ", Time.get_ticks_msec() - t0)
	main.start_game()
	main.time_of_day = 0.9
	main.spawn_timer = 9999.0
	var p = main.player
	var k := 0
	for spec in a[1].split(";"):
		var v := spec.split(",")
		p.global_position = Vector3(float(v[0]), 0.2, float(v[1]))
		p.cam_yaw = float(v[2])
		p.cam_pitch = -0.1
		for i in 30: await process_frame
		var tri := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var ob := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		print("PERF cam %s tris %d draws %d objects %d" % [spec, tri, dc, ob])
		root.get_texture().get_image().save_png("%s_%d.png" % [a[0], k])
		k += 1
	quit()
