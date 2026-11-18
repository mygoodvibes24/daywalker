extends SceneTree
## temp capture script (deleted before commit)
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var mode: String = a[1]
	load("res://scripts/hunt/hunt_director.gd").force_freeroam = true
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	main.time_of_day = 0.9
	main.spawn_timer = 9999.0
	for e in main.enemies_root.get_children():
		e.queue_free()
	var p = main.player
	p.global_position = Vector3(10, 0.1, 10)
	p.facing = 0.0
	p.visual.rotation.y = 0.0
	for i in 30: await physics_frame
	var cam := Camera3D.new()
	root.add_child(cam)
	if mode == "sol_front" or mode == "sol_34" or mode == "blade":
		var off := Vector3(0, 1.3, 3.2)
		var look := Vector3(0, 1.1, 0)
		if mode == "sol_34":
			off = Vector3(2.2, 1.5, 2.4)
		elif mode == "blade":
			off = Vector3(-1.4, 1.2, 1.4)
			look = Vector3(-0.3, 1.0, 0.2)
		cam.global_position = p.global_position + off
		cam.look_at(p.global_position + look)
		cam.fov = 45.0
		cam.current = true
		for i in 30: await process_frame
	elif mode == "follow":
		cam.queue_free()
		p.cam_yaw = 0.6
		for i in 40: await process_frame
	else:
		cam.queue_free()
		await _fight(main, p, mode, out)
		quit()
		return
	root.get_texture().get_image().save_png(out)
	quit()


func _spawn(main, kind: int, pos: Vector3):
	var e = load("res://scripts/enemy.gd").new()
	e.main = main
	e.kind = kind
	e.position = pos
	main.enemies_root.add_child(e)
	return e


func _shot(out: String, k: int) -> void:
	root.get_texture().get_image().save_png(out.replace(".png", "_%d.png" % k))


func _fight(main, p, mode: String, out: String) -> void:
	p.hp = 1e9
	p.max_hp = 1e9
	p.cam_yaw = PI * 0.75
	p.cam_pitch = -0.2
	if mode == "exec":
		var e = _spawn(main, 1, p.global_position + Vector3(0, 0.3, 1.8))
		for i in 20: await physics_frame
		e.attack_cd = 99.0
		while not e.staggered:
			e.take_hit(10.0, Vector3.FORWARD)
		for i in 10: await physics_frame
		p.attack_cd = 0.0
		p._attack_pressed()
		var shots := [0.2, 0.5, 0.8, 1.1, 1.5]
		var t0 := Time.get_ticks_msec()
		var k := 0
		while k < shots.size():
			await process_frame
			if (Time.get_ticks_msec() - t0) / 1000.0 >= shots[k]:
				_shot(out, k)
				k += 1
	elif mode == "lunge" or mode == "leap":
		var kind := 0 if mode == "lunge" else 1
		var e = _spawn(main, kind, p.global_position + Vector3(1.0, 0.3, 7.0))
		for i in 20: await physics_frame
		p.invuln_t = 99.0
		e.attack_cd = 0.0
		e.special_cd = 0.0
		for i in 600:
			await physics_frame
			if e.special != "":
				break
		var t0 := Time.get_ticks_msec()
		var k := 0
		var shots := [0.05, 0.3, 0.55, 0.8, 1.05]
		while k < shots.size():
			await process_frame
			if (Time.get_ticks_msec() - t0) / 1000.0 >= shots[k]:
				_shot(out, k)
				k += 1
	elif mode == "bars":
		var es := []
		for k in 3:
			es.append(_spawn(main, k % 2, p.global_position + Vector3(-2.2 + k * 2.2, 0.3, 4.5)))
		for i in 30: await physics_frame
		for e in es:
			e.attack_cd = 99.0
			e.special_cd = 99.0
		es[0].take_hit(12.0, Vector3.FORWARD)
		es[2].take_hit(30.0, Vector3.FORWARD)
		for i in 40: await process_frame
		root.get_texture().get_image().save_png(out)
