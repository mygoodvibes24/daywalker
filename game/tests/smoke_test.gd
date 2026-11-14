extends SceneTree
## Headless smoke test: godot --headless -s res://tests/smoke_test.gd

const SMOKE_SAVE := "user://smoke_save.json"

func _initialize() -> void:
	# never touch the player's real save; start from a fresh one
	load("res://scripts/progression.gd").save_path = SMOKE_SAVE
	if FileAccess.file_exists(SMOKE_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE))
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
	await process_frame
	ok = _check("pad START opens the Coat", main.inventory_ui.visible and paused) and ok
	main.inventory_ui.close() # START opened the Coat during the button sweep
	main.levelup_ui.close()
	ok = await _gameplay_checks(main) and ok
	ok = await _progression_checks(main) and ok
	ok = await _menu_checks(main) and ok
	if FileAccess.file_exists(SMOKE_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE))
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


## Tithe, ranks, Vows, loot, the Coat, save/load and the death drop.
func _progression_checks(main) -> bool:
	var ItemDB = load("res://scripts/items/item_db.gd")
	var p = main.player
	var prog = main.progression
	var inv = main.inventory
	var loot = main.loot
	var ok := true
	main.time_of_day = 0.9
	main.night_count = 1
	main.spawn_timer = 9999.0
	_clear_enemies(main)
	p.dead = false
	p.frenzy_t = 0.0
	p.burn_t = 0.0
	p.global_position = Vector3(10.0, 0.1, 10.0)
	p.velocity = Vector3.ZERO

	# a kill grants Tithe (motes fly to Sol)
	var t0: int = prog.tithe
	var v = _spawn(main, 0, Vector3(10.0, 0.5, 11.0))
	for i in 3: await physics_frame
	ok = _check("drained kills pay more", prog.kill_value(v, true) > prog.kill_value(v, false)) and ok
	v._die(false)
	for i in 120: await physics_frame
	ok = _check("a kill grants Tithe (+%d)" % (prog.tithe - t0), prog.tithe - t0 == prog.KILL_TITHE.vampire) and ok
	_clear_enemies(main)

	# levelling up costs Tithe and raises max blood
	prog.tithe = 1000
	var hp0: float = p.max_hp
	var cost: int = prog.next_cost()
	ok = _check("rank 2 is cheap (%d), rank 14 costs more" % cost, cost <= 40 and prog.cost_for(14) > cost * 10) and ok
	ok = _check("level up", prog.level_up()) and ok
	ok = _check("level up spends Tithe and raises max blood", prog.level == 2 and prog.tithe == 1000 - cost and p.max_hp == hp0 + prog.PER_LEVEL.max_hp) and ok
	ok = _check("level up offers 3 Vows", prog.vow_choices.size() == 3) and ok
	ok = _check("no second rank before a Vow is chosen", not prog.can_level()) and ok

	# a Vow applies
	prog.vow_choices = ["thick_blood"]
	var hp1: float = p.max_hp
	prog.choose_vow("thick_blood")
	ok = _check("Vow Thick Blood adds 25 max blood", p.max_hp == hp1 + 25.0 and "thick_blood" in prog.vows) and ok
	ok = _check("at least 12 Vows and 30 items", prog.VOWS.size() >= 12 and ItemDB.ITEMS.size() >= 30) and ok

	# a drop spawns with a rarity and a beam
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var entry: Dictionary = loot.spawn_item(ItemDB.random_item(rng, true, true), Vector3(12.0, 0.1, 10.0))
	ok = _check("a drop spawns with a rarity (%s)" % ItemDB.RARITY_NAMES[entry.inst.r], entry.inst.r >= 0 and entry.inst.r <= 3 and is_instance_valid(entry.node) and entry.node.get_child_count() >= 3) and ok
	var legend: int = 0
	for i in 400:
		if ItemDB.roll_rarity(rng, true, true, 0.0) == 3:
			legend += 1
	var legend_day: int = 0
	for i in 400:
		if ItemDB.roll_rarity(rng, false, false, 0.0) == 3:
			legend_day += 1
	ok = _check("full moons drop better loot (%d vs %d legendary)" % [legend, legend_day], legend > legend_day) and ok

	# picking up adds it to the coat
	var bag0: int = inv.bag.size()
	p.global_position = Vector3(12.0, 0.1, 10.5)
	var near = loot.nearest_item(p.global_position)
	ok = _check("pickup in range", near != null and loot.pick_up(near)) and ok
	ok = _check("pickup adds to the inventory", inv.bag.size() == bag0 + 1 or ItemDB.is_stackable(entry.inst)) and ok

	# equipping a blade changes damage
	var hits: Array = []
	var rec := func(_e, d): hits.append(d)
	p.hit_enemy.connect(rec)
	var target = _spawn(main, 0, Vector3(12.0, 0.5, 11.6))
	for i in 3: await physics_frame
	target.max_hp = 1e6
	target.hp = 1e6
	p.facing = 0.0
	p.combo_t = 0.0
	p.attack_cd = 0.0
	p._attack()
	inv.add(ItemDB.make("foundry_cleaver", 2))
	inv.equip_from_bag(inv.bag.size() - 1)
	p.combo_t = 0.0
	p._attack()
	p.hit_enemy.disconnect(rec)
	main.clear_slowmo()
	ok = _check("equipping a blade changes damage (%s)" % str(hits), hits.size() == 2 and hits[1] > hits[0] and inv.weapon.id == "foundry_cleaver") and ok
	ok = _check("blade visual follows the weapon", p.weapon_visual != null or p._find_blade_mesh() == null) and ok
	_clear_enemies(main)

	# a quick-use vial heals
	inv.quick[0] = ItemDB.make("blood_vial", 0, 2)
	p.hp = 40.0
	ok = _check("quick-use vial heals", inv.use_quick(0) and p.hp == 75.0 and inv.quick[0].n == 1) and ok

	# save then load round-trips
	inv.add(ItemDB.make("eclipse_coin", 3))
	inv.equip_from_bag(inv.bag.size() - 1)
	prog.tithe = 321
	ok = _check("save written", prog.save()) and ok
	var before: Dictionary = prog.to_dict()
	prog.reset()
	ok = _check("reset clears progression", prog.level == 1 and prog.tithe == 0 and inv.weapon.id == "marrow_silver") and ok
	prog.load_save()
	var after: Dictionary = prog.to_dict()
	ok = _check("save/load round-trips", JSON.stringify(before) == JSON.stringify(after) and prog.level == 2 and inv.weapon.id == "foundry_cleaver" and inv.charms[0].id == "eclipse_coin") and ok

	# death drops half the Tithe where Sol fell; walking back recovers it
	var fall := Vector3(14.0, 0.1, 14.0)
	prog.tithe = 200
	prog.on_death(fall)
	ok = _check("death drops half the Tithe", prog.tithe == 100 and int(prog.death_drop.amount) == 100) and ok
	loot._refresh_death_marker()
	ok = _check("death drop has a beam", loot.death_marker != null) and ok
	p.global_position = fall + Vector3(0.5, 0, 0)
	for i in 3: await physics_frame
	ok = _check("death drop is recoverable", prog.tithe == 200 and prog.death_drop.is_empty() and loot.death_marker == null) and ok
	prog.tithe = 50
	prog.on_death(fall)
	prog.on_death(fall + Vector3(5, 0, 0))
	ok = _check("dying again before recovering loses the first drop", int(prog.death_drop.amount) == 12 and prog.tithe == 13) and ok

	# caches open and restock at sunrise
	var c = loot.caches[0]
	ok = _check("~20 caches placed", loot.caches.size() >= 18) and ok
	loot.open_cache(c)
	ok = _check("cache opens", c.opened) and ok
	loot.respawn_caches()
	ok = _check("caches restock at sunrise", not c.opened) and ok
	# the inventory and Vigil menus pause the world
	main.ui_block_until = 0
	main.inventory_ui.open()
	ok = _check("the Coat pauses the world", paused and main.inventory_ui.visible) and ok
	main.inventory_ui.close()
	ok = _check("closing the Coat resumes", not paused) and ok
	return ok


# ---------------------------------------------------------------- main menu, pause, settings
func _key(code: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _menu_checks(main) -> bool:
	var ok := true
	# Esc opens the pause menu (and frees the mouse); Esc again resumes
	main.ui_block_until = 0
	_key(KEY_ESCAPE, true)
	await process_frame
	_key(KEY_ESCAPE, false)
	await process_frame
	ok = _check("Esc opens the pause menu", main.pause_menu.is_open() and paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED) and ok
	_key(KEY_TAB, true)
	await process_frame
	_key(KEY_TAB, false)
	await process_frame
	ok = _check("the Coat stays shut under the pause menu", not main.inventory_ui.visible) and ok
	_key(KEY_ESCAPE, true)
	await process_frame
	_key(KEY_ESCAPE, false)
	await process_frame
	ok = _check("Esc again resumes", not main.pause_menu.is_open() and not paused) and ok
	# the Coat's Pause entry hands over to the pause menu
	main.ui_block_until = 0
	main.inventory_ui.open()
	main.inventory_ui._pause()
	ok = _check("Pause inside the Coat opens the pause menu", main.pause_menu.is_open() and not main.inventory_ui.visible and paused) and ok
	main.pause_menu.close()

	# settings save / load round-trip (on a scratch file, then restored)
	var St = load("res://scripts/settings.gd")
	var path := "user://smoke_settings.cfg"
	var keep := [St.brightness, St.quality, St.rain, St.mouse_sensitivity, St.pad_sensitivity, St.invert_y, St.volume.duplicate()]
	St.brightness = 1.35
	St.quality = 0
	St.rain = false
	St.mouse_sensitivity = 1.8
	St.pad_sensitivity = 0.6
	St.invert_y = true
	St.volume["Music"] = 0.25
	var saved: bool = St.save_settings(path)
	St.brightness = 1.0
	St.quality = 2
	St.rain = true
	St.mouse_sensitivity = 1.0
	St.pad_sensitivity = 1.0
	St.invert_y = false
	St.volume["Music"] = 0.7
	var loaded: bool = St.load_settings(path)
	ok = _check("settings save/load round-trips", saved and loaded and is_equal_approx(St.brightness, 1.35) and St.quality == 0 and not St.rain
		and is_equal_approx(St.mouse_sensitivity, 1.8) and is_equal_approx(St.pad_sensitivity, 0.6) and St.invert_y
		and is_equal_approx(St.volume["Music"], 0.25)) and ok
	ok = _check("look sensitivity / invert feed the player", is_equal_approx(St.mouse_look(), 0.0025 * 1.8) and St.y_sign() == -1.0
		and is_equal_approx(St.pad_yaw(), 3.0 * 0.6) and is_equal_approx(St.pad_pitch(), 2.0 * 0.6)) and ok
	St.brightness = keep[0]; St.quality = keep[1]; St.rain = keep[2]
	St.mouse_sensitivity = keep[3]; St.pad_sensitivity = keep[4]; St.invert_y = keep[5]; St.volume = keep[6]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ok = _check("audio buses exist", AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0) and ok

	# the main menu scene loads, builds the lair and its screens
	main.queue_free()
	await process_frame
	ok = _check("main menu is the main scene", ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main_menu.tscn") and ok
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	for i in 5: await process_frame
	var set_ = menu.get_node("LairMenuSet")
	ok = _check("menu lair set builds with Sol and Nia", set_.sol_skel != null and set_.nia != null and set_.camera != null) and ok
	ok = _check("menu has Start / Controls / Options", menu.buttons.size() >= 3 and menu.buttons[0].text == "Start") and ok
	menu.debug_show("options")
	await process_frame
	ok = _check("Options screen opens", menu.options.visible and not menu.menu_box.visible) and ok
	menu._back()
	menu.debug_show("controls")
	await process_frame
	ok = _check("Controls screen opens", menu.controls.visible) and ok
	menu._back()
	ok = _check("Back returns to the menu", menu.menu_box.visible and menu.state == "menu") and ok
	menu.queue_free()
	await process_frame
	# coming from the menu, main.tscn starts at once without the title overlay
	var Main = load("res://scripts/main.gd")
	Main.started_once = true
	var m2 = load("res://scenes/main.tscn").instantiate()
	root.add_child(m2)
	await process_frame
	await process_frame
	ok = _check("main starts at once after the menu", m2.started and not paused and not m2.hud.start_overlay.visible) and ok
	m2.queue_free()
	await process_frame
	return ok
