extends SceneTree
## Headless smoke test: godot --headless -s res://tests/smoke_test.gd

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	var p = main.player
	var ok := true
	# the world waits behind the title screen
	var t0: float = main.time_of_day
	for i in 20: await physics_frame
	ok = _check("world paused on title screen", paused and main.time_of_day == t0) and ok
	main.start_game()
	ok = _check("start unpauses", not paused and main.hud.started) and ok
	ok = _check("first night is not a full moon", _full_moon_on(main, 1) == false and _full_moon_on(main, 3)) and ok
	# vampire burns in daylight
	main.time_of_day = 0.5
	var v = load("res://scripts/enemy.gd").new()
	v.main = main; v.kind = 0; v.position = Vector3(30, 0.5, 0)
	main.enemies_root.add_child(v)
	for i in 180: await physics_frame
	ok = _check("vampire burns in sun", not is_instance_valid(v) or v.dead) and ok
	# werewolf transforms at night, can be staggered and bitten
	main.time_of_day = 0.9
	main.night_count = 3
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
	main.clear_slowmo()
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
	ok = await _gameplay_checks(main) and ok
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


func _full_moon_on(main, night: int) -> bool:
	var keep: Array = [main.time_of_day, main.night_count]
	main.time_of_day = 0.9
	main.night_count = night
	var full: bool = main.is_full_moon()
	main.time_of_day = keep[0]
	main.night_count = keep[1]
	return full


func _clear_enemies(main) -> void:
	for e in main.enemies_root.get_children():
		main.enemies_root.remove_child(e)
		e.free()
	main.attack_tokens.clear()


func _spawn(main, kind: int, pos: Vector3):
	var e = load("res://scripts/enemy.gd").new()
	e.main = main
	e.kind = kind
	e.position = pos
	main.enemies_root.add_child(e)
	return e


## Regression checks for the critic report's bugs.
func _gameplay_checks(main) -> bool:
	var p = main.player
	var ok := true
	main.spawn_timer = 9999.0
	main.time_of_day = 0.9 # night, so vampires don't burn
	main.night_count = 1
	p.frenzy_t = 0.0
	p.hunger = 10.0
	_clear_enemies(main)

	# 1. Sol walks straight across a sidewalk (no curb snag). Block (30,30) spans x 23.5..36.5.
	p.global_position = Vector3(20.0, 0.1, 22.0)
	p.velocity = Vector3.ZERO
	p.cam_yaw = -PI / 2.0 # camera faces +x, so "forward" walks east
	_pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	for i in 40: await physics_frame
	_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
	ok = _check("walks onto the sidewalk (x=%.1f)" % p.global_position.x, p.global_position.x > 24.5) and ok

	# 2. Enemies path around buildings and reach the player.
	p.global_position = Vector3(10.0, 0.1, 10.0)
	p.velocity = Vector3.ZERO
	p.hp = 1e9
	p.max_hp = 1e9
	# all on streets (x or z on a multiple of 20), each with buildings in the way
	var spots := [Vector3(40, 0.5, 52), Vector3(-20, 0.5, 48), Vector3(52, 0.5, -40), Vector3(-40, 0.5, -48),
		Vector3(60, 0.5, 33), Vector3(33, 0.5, 60), Vector3(-60, 0.5, 32), Vector3(32, 0.5, -60)]
	var pack: Array = []
	for s in spots:
		pack.append(_spawn(main, 0, s))
	var reached := {}
	for i in 60 * 15:
		await physics_frame
		for e in pack:
			if e.global_position.distance_to(p.global_position) < 6.0:
				reached[e] = true
	ok = _check("enemies path to the player (%d/%d reached)" % [reached.size(), pack.size()], reached.size() >= pack.size() - 1) and ok
	var attackers := 0
	for e in pack:
		if e.windup_t > 0.0:
			attackers += 1
	ok = _check("attack tokens cap simultaneous attackers", main.attack_tokens.size() <= main.MAX_ATTACKERS and attackers <= main.MAX_ATTACKERS) and ok
	_clear_enemies(main)
	p.max_hp = 100.0
	p.hp = 100.0

	# 3. Hit-stop inside bullet-time ends on time.
	main.clear_slowmo()
	main.set_slowmo(0.3, 0.8)
	main.set_slowmo(0.06, 0.05)
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 200:
		await process_frame
	ok = _check("hit-stop ends inside bullet-time (scale %.2f)" % Engine.time_scale, is_equal_approx(Engine.time_scale, 0.3)) and ok
	main.clear_slowmo()

	# 4. Strikes can be sidestepped, and dashing out of one is a perfect dodge.
	p.global_position = Vector3(10.0, 0.1, 10.0)
	var v = _spawn(main, 0, Vector3(10.0, 0.5, 11.2))
	for i in 3: await physics_frame
	v.strike_dir = Vector3(0, 0, -1)
	p.global_position = Vector3(11.4, 0.1, 11.2) # beside him, outside the strike arc
	p.invuln_t = 0.0
	p.since_dash = 99.0
	var hp0: float = p.hp
	v._resolve_strike(p)
	ok = _check("strike misses a player who stepped aside", p.hp == hp0) and ok
	p.global_position = Vector3(10.0, 0.1, 10.0)
	ok = _check("strike still hits a player in front", (func(): v._resolve_strike(p); return p.hp < hp0).call()) and ok
	p.hp = 100.0
	p.global_position = Vector3(10.0, 0.1, 6.0)
	p.since_dash = 0.1
	var charges: float = p.dash_charges
	p.dash_charges = 1.0
	v._resolve_strike(p)
	ok = _check("dashing out of a strike = perfect dodge", p.dash_charges == 2.0 and p.hp == 100.0) and ok
	p.dash_charges = charges
	main.clear_slowmo()
	_clear_enemies(main)

	# 7 + 16. Wolves change back at sunrise; transforming clears stagger.
	var w = _spawn(main, 1, Vector3(30.0, 0.5, 10.0))
	main.time_of_day = 0.4
	for i in 3: await physics_frame
	w.take_hit(40.0, Vector3.FORWARD)
	ok = _check("civilian staggered by day", w.staggered) and ok
	main.time_of_day = 0.9
	for i in 3: await physics_frame
	ok = _check("transform clears stagger", w.transformed and not w.staggered) and ok
	w.transform_t = 0.0
	main.time_of_day = 0.4
	for i in 3: await physics_frame
	ok = _check("wolf reverts at sunrise", not w.transformed and w.max_hp == 50.0 and w.wolf_parts.is_empty()) and ok
	_clear_enemies(main)

	# 8. A combo aimed at one enemy doesn't kill the staggered one beside it.
	main.time_of_day = 0.9
	p.global_position = Vector3(10.0, 0.1, 10.0)
	p.facing = 0.0
	var fighter = _spawn(main, 0, Vector3(10.0, 0.5, 11.5))
	var weak = _spawn(main, 0, Vector3(10.6, 0.5, 11.3))
	for i in 3: await physics_frame
	weak.take_hit(35.0, Vector3.FORWARD)
	p.attack_cd = 0.0
	p._attack()
	ok = _check("combo spares the staggered enemy", weak.staggered and not weak.dead) and ok
	main.clear_slowmo()
	_clear_enemies(main)
	return ok
