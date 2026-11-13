extends SceneTree
## Headless smoke test: godot --headless -s res://tests/smoke_test.gd

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	var p = main.player
	var ok := true
	# vampire burns in daylight
	main.time_of_day = 0.5
	var v = load("res://scripts/enemy.gd").new()
	v.main = main; v.kind = 0; v.position = Vector3(30, 0.5, 0)
	main.enemies_root.add_child(v)
	for i in 180: await physics_frame
	ok = _check("vampire burns in sun", not is_instance_valid(v) or v.dead) and ok
	# werewolf transforms at night, can be staggered and bitten
	main.time_of_day = 0.9
	main.night_count = 1
	var w = load("res://scripts/enemy.gd").new()
	w.main = main; w.kind = 1; w.position = p.global_position + Vector3(0, 0, 2)
	main.enemies_root.add_child(w)
	for i in 10: await physics_frame
	ok = _check("wolf transformed under full moon", w.transformed and w.max_hp == 160.0) and ok
	while not w.staggered:
		w.take_hit(30.0, Vector3.FORWARD)
	ok = _check("wolf staggered", w.staggered) and ok
	p.hp = 50.0
	p._bite(w)
	ok = _check("bite heals (wolf +18)", p.hp == 68.0) and ok
	ok = _check("wolf blood gives rage", p.rage_t > 0.0) and ok
	ok = _check("wolf drained", w.dead) and ok
	p.add_hunger(100.0)
	ok = _check("hunger maxes into frenzy", p.frenzy_t > 0.0) and ok
	p.dash_t = 0.1
	var before: float = p.hp
	p.take_damage(20.0, null)
	ok = _check("dash dodges damage", p.hp == before) and ok
	# controller: left stick moves, right stick turns camera, buttons map to actions
	p.dash_t = 0.0
	p.frenzy_t = 0.0
	p.bite_t = 0.0
	p.swing_t = 0.0
	main.timescale_until = 0
	Engine.time_scale = 1.0
	p.hp = 100.0
	for e in main.enemies_root.get_children():
		e.queue_free()
	var start: Vector3 = p.global_position
	var yaw0: float = p.cam_yaw
	_pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	_pad_axis(JOY_AXIS_RIGHT_X, 1.0)
	for i in 30: await physics_frame
	ok = _check("left stick moves Sol", p.global_position.distance_to(start) > 1.0) and ok
	ok = _check("right stick turns camera", p.cam_yaw < yaw0) and ok
	_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
	_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	var mapping := {JOY_BUTTON_A: "jump", JOY_BUTTON_B: "dash", JOY_BUTTON_X: "attack", JOY_BUTTON_Y: "bite", JOY_BUTTON_LEFT_SHOULDER: "drink", JOY_BUTTON_START: "restart"}
	for b in mapping:
		_pad_button(b, true)
		var hit := Input.is_action_pressed(mapping[b])
		_pad_button(b, false)
		ok = _check("pad button -> " + mapping[b], hit) and ok
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	ok = _check("right trigger -> attack", Input.is_action_pressed("attack")) and ok
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	ok = _check("left trigger -> sprint", Input.is_action_pressed("sprint")) and ok
	_pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	print("SMOKE TEST: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _check(name: String, cond: bool) -> bool:
	print(("  ok   " if cond else "  FAIL ") + name)
	return cond


func _pad_axis(axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _pad_button(button: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
