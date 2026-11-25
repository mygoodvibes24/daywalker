extends SceneTree
## Local capture helper (not committed). Run with --fixed-fps 30 under xvfb:
##   godot --rendering-method gl_compatibility --fixed-fps 30 -s res://tests/_capb2.gd -- <outdir> <mode>
## modes: draw (calm -> attack -> swing -> sheathe), loco (idle/run/sprint with the sword on the back),
## lock (lock-on strafe), tells (enemy tells + hit feedback), look (Sol close: neck, boots, hem)

var cam: Camera3D
var p
var main
var out := ""
var view := Vector3(1.6, 1.5, -2.2) # camera offset in Sol's facing frame (x right, z forward)
var look_h := 1.25
var n := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var mode: String = a[1]
	DirAccess.make_dir_recursive_absolute(out)
	var HD = load("res://scripts/hunt/hunt_director.gd")
	HD.force_freeroam = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	main.time_of_day = 0.42 if mode != "night" else 0.9
	main.spawn_timer = 9999.0
	p = main.player
	for e in main.enemies_root.get_children():
		e.queue_free()
	cam = Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.current = true
	for i in 30: await process_frame
	match mode:
		"draw": await _draw_seq()
		"loco": await _loco_seq()
		"look": await _look_seq()
		"lock": await _lock_seq()
		"tells": await _tells_seq()
		"weapons": await _weapons_seq()
		"abhead": await _abhead_seq()
	quit()


func _place() -> void:
	var f: float = p.visual.rotation.y
	var b := Basis(Vector3.UP, f)
	var o: Vector3 = p.global_position
	# view.z forward of Sol (+z of his facing), x to his left
	cam.global_position = o + b * view
	cam.look_at(o + Vector3(0, look_h, 0), Vector3.UP)


func _shot(tag: String) -> void:
	_place()
	await process_frame
	_place()
	await process_frame
	root.get_texture().get_image().save_png("%s/%03d_%s.png" % [out, n, tag])
	n += 1


func _frames(k: int, tag: String, every := 1) -> void:
	for i in k:
		for j in every:
			_place()
			await process_frame
		_place()
		root.get_texture().get_image().save_png("%s/%03d_%s.png" % [out, n, tag])
		n += 1


func _draw_seq() -> void:
	p.sheath.sheathe(true)
	view = Vector3(1.3, 1.6, -2.4) # behind-right: the back and the shoulder
	await _shot("calm_back")
	view = Vector3(-2.2, 1.5, 1.2)
	await _shot("calm_front34")
	view = Vector3(1.5, 1.6, -2.0)
	p.attack_cd = 0.0
	p.attack_block_until = 0
	p.attack_buffer_t = p.ATTACK_BUFFER
	await _frames(12, "draw")
	await _frames(4, "swing", 3)
	for i in 30: await process_frame
	p.calm_t = p.SHEATHE_AFTER - 0.02
	await _frames(16, "sheathe")
	await _shot("after")


func _loco_seq() -> void:
	p.sheath.sheathe(true)
	view = Vector3(2.4, 1.5, 0.6)
	await _shot("idle_side")
	view = Vector3(1.2, 1.6, -2.4)
	await _shot("idle_back")
	Input.action_press("move_forward")
	for i in 30: await process_frame
	view = Vector3(2.6, 1.4, 0.4)
	await _frames(6, "run", 3)
	Input.action_press("sprint")
	for i in 20: await process_frame
	await _frames(6, "sprint", 3)
	Input.action_release("sprint")
	Input.action_release("move_forward")


func _look_seq() -> void:
	p.sheath.sheathe(true)
	look_h = 1.55
	view = Vector3(0.0, 1.65, 0.9)
	cam.fov = 40.0
	await _shot("neck_front")
	view = Vector3(0.6, 1.6, 0.7)
	await _shot("neck_34")
	look_h = 0.3
	view = Vector3(0.6, 0.6, 1.4)
	await _shot("feet")
	view = Vector3(0.4, 0.7, -1.6)
	await _shot("hem_back")
	look_h = 1.0
	cam.fov = 50.0
	view = Vector3(0.0, 1.3, 3.2)
	await _shot("full_front")
	view = Vector3(0.0, 1.4, -3.2)
	await _shot("full_back")


func _spawn(kind: int, pos: Vector3):
	var e = load("res://scripts/enemy.gd").new()
	e.main = main
	e.kind = kind
	e.position = pos
	main.enemies_root.add_child(e)
	return e


func _lock_seq() -> void:
	main.time_of_day = 0.9
	var fwd := Vector3(sin(p.visual.rotation.y), 0, cos(p.visual.rotation.y))
	var a = _spawn(0, p.global_position + fwd * 6.0 + Vector3(0, 0.4, 0))
	var b = _spawn(0, p.global_position + fwd * 6.0 + Vector3(fwd.z, 0, -fwd.x) * 3.5 + Vector3(0, 0.4, 0))
	for e in [a, b]:
		e.speed = 0.0
		e.attack_cd = 99.0
		e.special_cd = 99.0
	for i in 10: await process_frame
	cam.current = false
	p.camera.current = true
	p.toggle_lock()
	for i in 30: await process_frame
	root.get_texture().get_image().save_png("%s/%03d_lock_game.png" % [out, n]); n += 1
	Input.action_press("move_right")
	for i in 20: await process_frame
	for k in 4:
		for i in 4: await process_frame
		root.get_texture().get_image().save_png("%s/%03d_lock_strafe.png" % [out, n]); n += 1
	Input.action_release("move_right")
	p.switch_lock(1.0)
	for i in 30: await process_frame
	root.get_texture().get_image().save_png("%s/%03d_lock_switch.png" % [out, n]); n += 1
	cam.current = true
	view = Vector3(2.8, 1.6, 1.0)
	Input.action_press("move_left")
	for i in 15: await process_frame
	await _frames(5, "strafe_side", 3)
	Input.action_release("move_left")


func _tells_seq() -> void:
	main.time_of_day = 0.9
	var fwd := Vector3(sin(p.visual.rotation.y), 0, cos(p.visual.rotation.y))
	var v = _spawn(0, p.global_position + fwd * 1.6 + Vector3(0, 0.4, 0))
	p.auto_sheathe = false
	for i in 5: await process_frame
	v.claw_cd = 99.0
	v.special_cd = 99.0
	v.attack_cd = 0.0
	view = Vector3(2.6, 1.5, 0.8)
	await _frames(14, "vamp_swipe", 2)
	var to: Vector3 = p.global_position - v.global_position
	to.y = 0.0
	v._cancel_special()
	v._start_claw(to, to.length())
	await _frames(16, "claw", 2)
	v._cancel_special()
	v.attack_cd = 99.0
	p.hp = p.max_hp
	p.sheath.draw(true)
	p.attack_cd = 0.0
	p.attack_buffer_t = p.ATTACK_BUFFER
	await _frames(14, "hit", 1)


func _weapons_seq() -> void:
	var ids := ["marrow_silver", "foundry_cleaver", "velvet_rapier", "belltower_great", "pine_kukri"]
	for id in ids:
		p.set_weapon_visual({"id": id, "r": 0})
		p.sheath.sheathe(true)
		for i in 4: await process_frame
		view = Vector3(1.3, 1.6, -2.4)
		await _shot("back_" + id)
		view = Vector3(2.4, 1.4, 0.3)
		await _shot("side_" + id)


## A/B of the heads: stylised (as shipped), the scanned head with its current albedo, and with the
## cleaned albedo (arg 3: path to it). The scan head rides the Head bone rigidly (a preview, not the
## build's skinned neck).
func _scan_head(alb_path: String) -> Node3D:
	var sk: Skeleton3D = p.visual.find_child("Skeleton3D", true, false)
	var scn = (load("res://assets/characters/sol/sol_scan_head.glb") as PackedScene).instantiate()
	var mi: MeshInstance3D = scn.find_children("*", "MeshInstance3D", true, false)[0]
	var m := StandardMaterial3D.new()
	if alb_path != "":
		m.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(alb_path))
	else:
		m.albedo_texture = load("res://assets/characters/sol/sol_scan_head_albedo.jpg")
	m.normal_enabled = true
	m.normal_texture = load("res://assets/characters/sol/sol_scan_head_normal.png")
	var orm: Texture2D = load("res://assets/characters/sol/sol_scan_head_orm.png")
	m.roughness_texture = orm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.ao_enabled = true
	m.ao_texture = orm
	m.ao_light_affect = 0.25
	m.metallic_specular = 0.38
	m.rim_enabled = true
	m.rim = 0.12
	m.rim_tint = 0.55
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	sk.add_child(att)
	var head := MeshInstance3D.new()
	head.mesh = mi.mesh
	head.material_override = m
	att.add_child(head)
	head.transform = sk.get_bone_global_rest(sk.find_bone("Head")).affine_inverse()
	scn.free()
	var hm: Node3D = sk.get_node("HeadMesh")
	hm.visible = false
	return att


func _abhead_seq() -> void:
	var a := OS.get_cmdline_user_args()
	var variant: String = a[2]
	p.sheath.sheathe(true)
	if variant != "stylised":
		_scan_head(a[3] if a.size() > 3 else "")
	for tod in [0.42, 0.9]:
		main.time_of_day = tod
		for i in 10: await process_frame
		var tag := "day" if tod < 0.5 else "night"
		cam.fov = 30.0
		look_h = 1.72
		view = Vector3(0.0, 1.74, 0.75)
		await _shot(tag + "_front")
		view = Vector3(0.5, 1.74, 0.55)
		await _shot(tag + "_34")
		view = Vector3(0.62, 1.72, 0.05)
		await _shot(tag + "_profile")
		cam.fov = 50.0
		look_h = 1.3
		view = Vector3(-1.2, 2.0, 3.6)
		await _shot(tag + "_gamecam")
