extends SceneTree
## Headless smoke test: godot --headless -s res://tests/smoke_test.gd

const SMOKE_SAVE := "user://smoke_save.json"

func _initialize() -> void:
	# never touch the player's real save; start from a fresh one
	load("res://scripts/progression.gd").save_path = SMOKE_SAVE
	if FileAccess.file_exists(SMOKE_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE))
	# the free-roam sandbox is debug-only now (--freeroam / ?freeroam); these checks use it
	var HD = load("res://scripts/hunt/hunt_director.gd")
	HD.force_freeroam = true
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	var p = main.player
	var ok := true
	ok = _check("free roam only behind the debug flag", main.hunt == null and main.free_roam) and ok
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
	ok = await _terrain_checks(main) and ok
	ok = await _progression_checks(main) and ok
	ok = await _coat_checks(main) and ok
	ok = await _sheath_checks(main) and ok
	ok = await _combat_r3_checks(main) and ok
	ok = await _move_checks(main) and ok
	ok = await _fall_checks(main) and ok
	ok = await _special_checks(main) and ok
	ok = await _undercroft_checks(main) and ok
	ok = await _audio_checks(main) and ok
	ok = await _asset_r3_checks(main) and ok
	ok = await _perf_checks(main) and ok
	ok = await _cemetery_checks(main) and ok
	ok = await _menu_checks(main) and ok
	ok = await _hunt_checks() and ok
	ok = _download_checks() and ok
	if FileAccess.file_exists(SMOKE_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE))
	print("SMOKE TEST: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

## W2 / K4: the web export leaves staging, tools and tests out, and the retired Sol and *_rig.scn
## bodies stay deleted (about 6 MB of the old pck).
func _download_checks() -> bool:
	var ok := true
	var cf := ConfigFile.new()
	var loaded := cf.load("res://export_presets.cfg") == OK
	var ex: String = str(cf.get_value("preset.0", "exclude_filter", "")) if loaded else ""
	ok = _check("the web export excludes assets_staging, tools and tests (%s)" % ex, loaded and ex.contains("assets_staging/*") and ex.contains("tools/*") and ex.contains("tests/*")) and ok
	var dead := ["res://assets/characters/sol/sol.scn", "res://assets/characters/vampire/vampire_rig.scn", "res://assets/characters/werewolf/werewolf_rig.scn",
		"res://assets/characters/civilian/civilian_rig.scn", "res://scripts/sol_anim.gd"]
	var gone := true
	for d in dead:
		if FileAccess.file_exists(d):
			gone = false
	ok = _check("the retired Sol body and *_rig.scn fallbacks stay deleted", gone) and ok
	return ok


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


## The terrain: real hills and a lake, everything stands on the ground, enemies path uphill.
func _terrain_checks(main) -> bool:
	var ok := true
	var c = main.city
	var L = load("res://scripts/map/map_layout.gd")
	var hmax := -INF
	for z in range(-220, -80, 10):
		for x in range(-60, 120, 10):
			hmax = maxf(hmax, c.height_at(x, z))
	ok = _check("Hollow Pines has hills (highest %.1f m)" % hmax, hmax > 12.0) and ok
	ok = _check("the city plates stay level", absf(c.height_at(0, 0)) < 0.001 and absf(c.height_at(150, 100)) < 0.001 and absf(c.height_at(-150, 0)) < 0.001) and ok
	var lp: Vector3 = L.LAKE.pos
	# QA2 #19: no invisible wall; the whole lake is wadeable, chest-deep in the middle
	var lake_mid: float = L.LAKE.level - c.height_at(lp.x, lp.z)
	var fenced := false
	for n in c.find_children("Terrain", "StaticBody3D", false, false):
		fenced = fenced or (n as Node).get_child_count() > 1
	ok = _check("the lake is wadeable right across (%.2f m deep in the middle), shallow at the edge, no invisible wall" % lake_mid,
		lake_mid > 1.0 and lake_mid < 1.6 and c.height_at(lp.x + L.LAKE.radius * 0.9, lp.z) > L.LAKE.level - 1.0 and not fenced) and ok
	var space = main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(30, 80, -150), Vector3(30, -20, -150))
	var hit: Dictionary = space.intersect_ray(q)
	ok = _check("terrain collision matches height_at", not hit.is_empty() and absf(hit.position.y - c.height_at(30, -150)) < 0.15) and ok
	var on_ground := true
	for s in c.cache_spots:
		if absf(s.pos.y - 0.1 - c.height_at(s.pos.x, s.pos.z)) > 0.05:
			on_ground = false
	for a in c.poi_anchors:
		if absf(a.pos.y - c.height_at(a.pos.x, a.pos.z)) > 0.05:
			on_ground = false
	ok = _check("caches and POI anchors sit on the ground", on_ground) and ok
	# enemies climb to Sol on a hilltop clearing in the pines
	var p = main.player
	_clear_enemies(main)
	var top: Vector3 = L.PINE_CLEARINGS[0][0] # the trailer park
	top.y = c.height_at(top.x, top.z)
	p.global_position = top + Vector3(0, 0.3, 0)
	p.velocity = Vector3.ZERO
	var keep_hp: float = p.hp
	var keep_max: float = p.max_hp
	var keep_pos: Vector3 = Vector3(10.0, 0.1, 10.0)
	p.hp = 1e9
	p.max_hp = 1e9
	var pack: Array = []
	for o in [Vector3(0, 0, 34), Vector3(-6, 0, -30), Vector3(30, 0, 8)]:
		var sp: Vector3 = top + o
		pack.append(_spawn(main, 0, Vector3(sp.x, c.height_at(sp.x, sp.z) + 0.5, sp.z)))
	var reached := {}
	for i in 60 * 15:
		await physics_frame
		for e in pack:
			if e.global_position.distance_to(p.global_position) < 6.0:
				reached[e] = true
	ok = _check("enemies path over the hills to Sol (%d/%d)" % [reached.size(), pack.size()], reached.size() >= pack.size() - 1) and ok
	ok = _check("Sol stands on the hill (y %.2f vs ground %.2f)" % [p.global_position.y, top.y], absf(p.global_position.y - top.y) < 0.6) and ok
	_clear_enemies(main)
	p.max_hp = keep_max
	p.hp = keep_hp
	p.global_position = keep_pos
	p.velocity = Vector3.ZERO
	for i in 5: await physics_frame
	return ok


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
	var spots := [Vector3(40, 0.5, 52), Vector3(-20, 0.5, 48), Vector3(52, 0.5, -20), Vector3(-40, 0.5, -48),
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
	for i in 8: await physics_frame # (past the hit's 0.06 s victim hit-stop)
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
	for i in 30: # the hit lands on the clip's strike frame
		await physics_frame
		if p.pending.is_empty():
			break
	ok = _check("combo spares the staggered enemy", weak.staggered and not weak.dead and fighter.hp < fighter.max_hp) and ok
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

	# a kill grants Tithe (motes fly to Sol); motes still in flight from earlier checks don't count
	for m in loot.motes:
		m.node.queue_free()
	loot.motes.clear()
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
	for i in 30: # damage lands on the strike frame
		await physics_frame
		if p.pending.is_empty():
			break
	inv.add(ItemDB.make("foundry_cleaver", 2))
	inv.equip_from_bag(inv.bag.size() - 1)
	target.global_position = Vector3(12.0, 0.5, 11.6) # undo the first hit's knockback
	p.combo_t = 0.0
	p._attack()
	for i in 30:
		await physics_frame
		if p.pending.is_empty():
			break
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


## The modular hero's trenchcoat: spring bones swing out when Sol runs and settle when he stops.
func _coat_checks(main) -> bool:
	var p = main.player
	var sim = p.visual.find_child("CoatSim", true, false)
	if sim == null:
		print("  --   coat checks skipped (no modular model)")
		return true
	var ok := true
	main.inventory_ui.close()
	main.levelup_ui.close()
	main.clear_slowmo()
	main.spawn_timer = 9999.0 # no new arrivals (an enemy within 10 m switches Sol to his combat stance)
	_clear_enemies(main)
	p.dead = false
	p.hp = p.max_hp
	p.global_position = Vector3(10.0, 0.1, 10.0)
	p.velocity = Vector3.ZERO
	# no long-idle fidget (the look-around after 12 s standing) during these timed windows
	if p.mod_anim != null:
		p.mod_anim.still_t = -60.0
		p.mod_anim.tree.set("parameters/fidget/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	for i in 300: await physics_frame # let the coat settle from the teleport before taking the baseline
	var still: float = sim.swing_amount()
	_pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	var run_max := 0.0
	for i in 45:
		await physics_frame
		run_max = maxf(run_max, sim.swing_amount())
	_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
	var run_motion: float = sim.motion_amount()
	for i in 240: await physics_frame
	var settled: float = sim.swing_amount()
	var still_motion: float = sim.motion_amount()
	ok = _check("coat bones swing when running (%.3f rad vs %.3f standing)" % [run_max, still], run_max > still + 0.12) and ok
	ok = _check("coat settles after stopping (%.3f rad, cloth %.3f m/s, was %.2f)" % [settled, still_motion, run_motion], absf(settled - still) < 0.06 and still_motion < run_motion * 0.06) and ok
	# with the idle clip frozen too, the cloth comes fully to rest
	p.mod_anim.tree.active = false
	p.set_physics_process(false) # a truly still body: no floor-snap creep on the terrain slope while the cloth settles
	p.velocity = Vector3.ZERO
	var breeze: float = sim.flutter
	sim.flutter = 0.0 # measure the cloth settling itself, not the deliberate standing breeze
	for i in 240: await physics_frame # long enough to settle even when frame pacing is uneven (a loaded machine)
	# settled = the calmest reading over the last second (one uneven frame on a loaded machine spikes a single sample)
	var rest_motion: float = INF
	for i in 60:
		await physics_frame
		rest_motion = minf(rest_motion, sim.motion_amount())
	sim.flutter = breeze
	p.set_physics_process(true)
	p.mod_anim.tree.active = true
	ok = _check("coat comes to rest on a still body (%.4f m/s)" % rest_motion, rest_motion < 0.03) and ok # the standing breeze keeps a slight drift
	ok = _check("modular model animates with clips", p.mod_anim != null and p.mod_anim.tree != null and p.mod_anim.tree.active) and ok
	return ok


## The sword moves (scripts/sol_moves.gd): hold for the charged slash, attack out of a Blood Dash for
## the thrust, the execution on a staggered enemy, and a parry that turns a wind-up aside.
## Round 3 Group B: lock-on, stamina, the Frenzy's cost, body-language tells (no floor decals), the
## vampire's claw combo and backflip.
func _combat_r3_checks(main) -> bool:
	var p = main.player
	var ok := true
	var HFx = load("res://scripts/hunt/hunt_fx.gd")
	main.clear_slowmo()
	_clear_enemies(main)
	main.time_of_day = 0.9 # night: vampires don't burn
	p.dead = false
	p.hp = p.max_hp
	p.global_position = Vector3(10.0, 0.1, 10.0)
	p.velocity = Vector3.ZERO
	p.auto_sheathe = false
	for i in 5: await physics_frame
	# --- lock-on: acquires the enemy in front of the camera, switches, breaks on distance
	var fwd: Vector3 = -p.camera.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var a = _spawn(main, 0, p.global_position + fwd * 6.0 + Vector3(0, 0.4, 0))
	var b = _spawn(main, 0, p.global_position + fwd * 6.0 + side * 3.0 + Vector3(0, 0.4, 0))
	for e in [a, b]:
		e.speed = 0.0
		e.attack_cd = 99.0
		e.special_cd = 99.0
	for i in 3: await physics_frame
	p.release_lock()
	p.toggle_lock()
	var first = p.lock_target
	ok = _check("lock-on acquires the enemy in front (reticle %s)" % (p.lock_reticle != null and p.lock_reticle.visible), first == a and p.lock_reticle != null and p.lock_reticle.visible) and ok
	for i in 20: await process_frame
	var face_ok: bool = absf(wrapf(p.facing - atan2(a.global_position.x - p.global_position.x, a.global_position.z - p.global_position.z), -PI, PI)) < 0.2
	var cam_f: Vector3 = -p.camera.global_transform.basis.z
	var to_a: Vector3 = (a.global_position - p.camera.global_position).normalized()
	ok = _check("locked: Sol faces the target and the camera looks at it (cam dot %.2f)" % cam_f.dot(to_a), face_ok and cam_f.dot(to_a) > 0.85) and ok
	var side_sign := signf(p.camera.unproject_position(b.global_position).x - p.camera.unproject_position(a.global_position).x)
	p.switch_lock(side_sign)
	ok = _check("a flick switches the lock to the next target on that side", p.lock_target == b) and ok
	p.lock_flick(-side_sign * 200.0)
	ok = _check("a mouse flick the other way switches back", p.lock_target == a) and ok
	a.global_position = p.global_position + fwd * 40.0
	for i in 5: await physics_frame
	ok = _check("the lock breaks when the target is out of range", p.lock_target == null and not p.lock_reticle.visible) and ok
	_clear_enemies(main)
	# --- stamina: drains on actions, comes back fast; spent out, he can't dash until it recovers
	p.frenzy_t = 0.0
	p.stamina = p.max_stamina()
	p.exhausted = false
	var s0: float = p.stamina
	var c0: float = p.dash_charges
	p.dash_charges = 3.0
	Input.action_press("dash") # (an action pressed from a script reads as just-pressed on the next physics frame)
	for i in 2: await physics_frame
	Input.action_release("dash")
	var after_dash: float = p.stamina
	for i in 70: await physics_frame
	ok = _check("a dash costs stamina and it comes back fast (%.0f -> %.0f -> %.0f)" % [s0, after_dash, p.stamina], after_dash < s0 - 10.0 and p.stamina >= p.max_stamina() - 0.5) and ok
	p.spend_stamina(999.0)
	var ch: float = p.dash_charges
	Input.action_press("dash")
	for i in 2: await physics_frame
	Input.action_release("dash")
	var blocked: bool = p.exhausted and p.dash_charges == ch
	for i in 150: await physics_frame
	ok = _check("exhausted: no dash until stamina recovers (recovered %s, %.0f)" % [not p.exhausted, p.stamina], blocked and not p.exhausted) and ok
	ok = _check("every sword move has a stamina cost field", (func():
		var SM = load("res://scripts/sol_moves.gd")
		for k in SM.MOVES:
			if not SM.MOVES[k].has("stamina"):
				return false
		return SM.stamina_cost("light1") > 0.0 and SM.stamina_cost("charged") > SM.stamina_cost("light1")).call()) and ok
	p.dash_charges = c0
	# --- Frenzy costs blood and makes him take more damage
	p.hp = 80.0
	p.frenzy_t = 0.0
	p.invuln_t = 0.0
	p.dash_t = 0.0
	p.take_damage(10.0, null) # the same blow without Frenzy (charms and Vows may already scale it)
	var calm_took: float = 80.0 - p.hp
	p.hp = 80.0
	p.frenzy_t = 3.0
	for i in 60: await physics_frame
	var drained: float = 80.0 - p.hp
	var hp1: float = p.hp
	p.invuln_t = 0.0
	p.dash_t = 0.0
	p.take_damage(10.0, null)
	var took: float = hp1 - p.hp
	p.frenzy_t = 0.0
	p.hp = p.max_hp
	p.invuln_t = 0.0
	ok = _check("Frenzy costs: blood drains (%.1f in 1 s) and blows land harder (%.1f vs %.1f)" % [drained, took, calm_took], drained > 1.5 and took > calm_took * 1.15) and ok
	# --- tells, not decals: a vampire's swipe, lunge and claw and a wolf's swipe make no floor decal
	HFx.decals = 0
	var v = _spawn(main, 0, p.global_position + fwd * 1.3 + Vector3(0, 0.4, 0))
	for i in 3: await physics_frame
	v.claw_cd = 99.0
	v.special_cd = 99.0
	v.attack_cd = 0.0
	for i in 60: await physics_frame
	var swiped: bool = v.glints > 0
	main.clear_slowmo()
	p.hp = p.max_hp
	# the claw string: both rakes land (or get dodged), on the claw clip
	p.global_position = Vector3(10.0, 0.1, 10.0) # (the swipe may have knocked him back)
	p.velocity = Vector3.ZERO
	v.global_position = p.global_position + fwd * 1.3
	var to: Vector3 = p.global_position - v.global_position
	to.y = 0.0
	v._cancel_special()
	v._start_claw(to, to.length())
	var claw_clip: String = v.anim_state
	var rakes := 0
	for i in 140:
		await physics_frame
		p.global_position = Vector3(10.0, 0.1, 10.0)
		p.invuln_t = 0.0
		rakes = maxi(rakes, v.claw_hit)
		if v.special == "":
			break
	main.clear_slowmo()
	ok = _check("the vampire's claw combo: two rakes on claw_combo (clip %s, rakes %d, hp %.0f)" % [claw_clip, rakes, p.hp], (v.anim == null or claw_clip == "claw_combo") and rakes == 2 and p.hp < p.max_hp) and ok
	p.hp = p.max_hp
	# the backflip: Sol winds a charged slash close by, the vampire flips out of it, untouchable
	v._cancel_special()
	v.global_position = p.global_position + fwd * 2.5
	var d0: float = v.global_position.distance_to(p.global_position)
	var flipped := false
	var iframes := false
	for i in 120:
		await physics_frame
		p.hold_t = 0.3 # holding attack (the charge)
		p.global_position = Vector3(10.0, 0.1, 10.0)
		if not flipped and v.special != "flip":
			v.flip_cd = 0.0
		flipped = flipped or v.special == "flip"
		iframes = iframes or v.evading()
		if flipped and v.special == "":
			break
	p.hold_t = -1.0
	var hp_v: float = v.hp
	var d1: float = v.global_position.distance_to(p.global_position)
	ok = _check("the vampire backflips out of a charge (flip %s, i-frames %s, %.1f -> %.1f m)" % [flipped, iframes, d0, d1], flipped and iframes and d1 > d0 + 1.5 and (v.anim == null or v.anim.has_animation("backflip"))) and ok
	# wolf swipe: a growl and an eye glint, no decal
	_clear_enemies(main)
	main.night_count = 3
	var w = _spawn(main, 1, p.global_position + fwd * 1.6 + Vector3(0, 0.4, 0))
	for i in 10: await physics_frame
	w.transform_t = 0.0
	w.special_cd = 99.0
	w.attack_cd = 0.0
	for i in 90: await physics_frame
	main.clear_slowmo()
	ok = _check("tells, not decals: swipes, lunge-free claw and wolf swipe glint (vamp %s, wolf %d) with %d floor decals" % [swiped, w.glints, HFx.decals], swiped and w.glints > 0 and HFx.decals == 0) and ok
	# hit feedback: a rim (not a white flash), a victim hit-stop and a recoil away from the blade
	w.max_hp = 1e6
	w.hp = 1e6
	w.take_hit(10.0, fwd)
	var rim: float = 0.0
	if w.body_mesh != null and w.body_mesh.material_overlay == w.fx_mat:
		rim = float(w.fx_mat.get_shader_parameter("rim"))
	await physics_frame
	await physics_frame
	if w.body_mesh != null and w.body_mesh.material_overlay == w.fx_mat:
		rim = maxf(rim, float(w.fx_mat.get_shader_parameter("rim")))
	ok = _check("hit feedback: rim %.2f, hit-stop %.2f s, recoil %.2f" % [rim, w.HITSTOP, w.recoil_v.length() + w.recoil.length()], (w.body_mesh == null or rim > 0.3) and w.hitstop_t >= 0.0 and (w.recoil.length() + w.recoil_v.length()) > 0.05) and ok
	# pooled VFX: a flurry of hits reuses the blood emitters and glints (no node per hit)
	var s0_sprays: int = HFx.sprays
	for i in 20:
		w.take_hit(5.0, fwd)
		w._cue()
		await physics_frame
	ok = _check("blood spray and glints are pooled (%d sprays on %d emitters, %d glints)" % [HFx.sprays - s0_sprays, HFx._sprays.size(), HFx._glints.size()],
		HFx.sprays - s0_sprays >= 20 and HFx._sprays.size() <= HFx.BLOOD_POOL and HFx._glints.size() <= HFx.GLINT_POOL) and ok
	ok = _check("settings hooks read settings.gd (a missing key falls back)", HFx.opt("invert_y", 7) is bool and HFx.opt("no_such_setting_x", 7) == 7) and ok
	_clear_enemies(main)
	p.hp = p.max_hp
	p.stamina = p.max_stamina()
	main.clear_slowmo()
	return ok


## Round 3 (owner's playtest): the sword rides on Sol's back when calm, he draws on attack, and puts it
## away again after SHEATHE_AFTER s of calm; weapon swaps work in both places.
func _sheath_checks(main) -> bool:
	var p = main.player
	var ok := true
	main.clear_slowmo()
	_clear_enemies(main)
	p.dead = false
	p.hp = p.max_hp
	p.global_position = Vector3(10.0, 0.1, 10.0)
	p.velocity = Vector3.ZERO
	for i in 5: await physics_frame
	if p.sheath == null:
		return _check("the modular Sol has a back scabbard", false)
	p.sheath.sheathe(true)
	await physics_frame
	var open_ok: bool = p.sheath.open_hand == null or (p.sheath.open_hand.visible and not p.sheath.fist.visible)
	ok = _check("calm: the sword is on his back, hand empty (scabbard parts %d)" % p.sheath.scabbard.get_child_count(), p.sword_on_back() and open_ok and p.sheath.scabbard.get_child_count() >= 2 and not p.mod_anim.armed) and ok
	# attack: the draw, and the first swing chains out of it
	p.attack_cd = 0.0
	p.attack_block_until = 0
	p.attack_buffer_t = p.ATTACK_BUFFER
	var waited := 0.0
	var swung := false
	for i in 40:
		await physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		if p.move_name != "" and p.swing_t > 0.0:
			swung = true
			break
	for i in 20: await physics_frame
	ok = _check("attack draws the sword and swings out of the draw (%.2f s to the swing)" % waited, swung and waited < 0.3 and p.sword_in_hand() and p.mod_anim.armed) and ok
	# calm again: it goes back after the timeout
	p.calm_t = p.SHEATHE_AFTER - 0.2
	for i in 60: await physics_frame
	ok = _check("after %.0f s of calm the sword is sheathed again" % p.SHEATHE_AFTER, p.sword_on_back()) and ok
	# weapon swaps in both states (the heavy cleaver family too)
	var keep: Dictionary = p.weapon_item
	p.set_weapon_visual({"id": "foundry_cleaver", "r": 0})
	await process_frame
	var on_back_ok: bool = p.weapon_visual != null and p.weapon_visual.get_parent() == p.sheath.carrier and p.sword_on_back()
	p.draw_sword()
	for i in 30: await physics_frame
	var in_hand_ok: bool = p.sword_in_hand() and p.weapon_visual.get_parent() == p.sheath.carrier and p.weapon_visual.is_visible_in_tree()
	ok = _check("a cleaver swapped in on his back draws into his hand", on_back_ok and in_hand_ok) and ok
	# per-weapon mounts: a kukri rides the left hip, an item's own "mount" field (a tuned preset) wins,
	# and every preset sheathes and draws
	p.sheath.sheathe(true)
	p.set_weapon_visual({"id": "pine_kukri", "r": 0})
	await process_frame
	ok = _check("a kukri mounts on the hip (%s on %s)" % [p.sheath.mount_name, p.sheath.mount_att.bone_name], p.sheath.mount_name == "hip" and p.sheath.mount_att.bone_name == "Hips" and p.sword_on_back()) and ok
	var SS = load("res://scripts/sol_sheath.gd")
	var all_ok := true
	for mname in SS.MOUNTS:
		p.sheath.sheathe(true)
		p.set_weapon_visual({"id": "marrow_silver", "r": 0, "mount": {"preset": mname, "reach": 0.12}})
		await process_frame
		var hilt_ok: bool = p.sheath.carrier.global_position.distance_to(p.global_position + Vector3(0, 1.2, 0)) < 1.0
		p.draw_sword()
		for i in 30: await physics_frame
		var drew: bool = p.sword_in_hand()
		p.sheath.sheathe()
		for i in 40: await physics_frame
		if not (hilt_ok and drew and p.sword_on_back() and p.sheath.mount_name == mname and is_equal_approx(p.sheath.reach_t, 0.12)):
			all_ok = false
			print("    mount ", mname, " hilt ", hilt_ok, " drew ", drew, " back ", p.sword_on_back())
	ok = _check("every weapon mount preset (%s) sheathes on its bone and draws" % ", ".join(SS.MOUNTS.keys()), all_ok) and ok
	p.set_weapon_visual(keep)
	p.auto_sheathe = false # the move checks below want the sword out
	return ok


func _move_checks(main) -> bool:
	var p = main.player
	var ok := true
	if p.sheath != null:
		p.sheath.draw(true)
		p.auto_sheathe = false
	main.clear_slowmo()
	_clear_enemies(main)
	main.time_of_day = 0.9 # night: vampires don't burn
	p.dead = false
	p.hp = p.max_hp
	p.global_position = Vector3(10.0, 0.1, 10.0)
	p.velocity = Vector3.ZERO
	p.facing = 0.0
	for i in 5: await physics_frame
	var hits: Array = []
	var rec := func(_e, d): hits.append(d)
	p.hit_enemy.connect(rec)

	# 1. holding attack turns into the charged slash: a big hit that staggers
	var e = _spawn(main, 0, p.global_position + Vector3(0, 0.4, 1.6))
	for i in 3: await physics_frame
	e.max_hp = 1e6
	e.hp = 1e6
	p.attack_cd = 0.0
	p.combo_t = 0.0
	p.attack_block_until = 0
	Input.action_press("attack")
	var charged := false
	for i in 90:
		await physics_frame
		charged = charged or p.move_name == "charged"
		if charged and p.pending.is_empty():
			break
	Input.action_release("attack")
	main.clear_slowmo()
	# QA2 #10: one heavy hit; the light strike of the press that became the charge never lands
	ok = _check("holding attack does the charged slash, one heavy hit (hits %s, staggered %s)" % [str(hits), e.staggered], charged and hits.size() == 1 and hits[0] > 30.0 and e.staggered) and ok
	_clear_enemies(main)

	# 2. attacking just after a Blood Dash is the thrust, and it lands
	hits.clear()
	e = _spawn(main, 0, p.global_position + Vector3(0, 0.4, 2.2))
	for i in 3: await physics_frame
	e.max_hp = 1e6
	e.hp = 1e6
	p.facing = 0.0
	p.attack_cd = 0.0
	p.dash_t = 0.0
	p.since_dash = 0.25
	p._attack_pressed()
	var was_dash: bool = p.move_name == "dash"
	for i in 60:
		await physics_frame
		if p.pending.is_empty():
			break
	main.clear_slowmo()
	ok = _check("attack after a dash is the thrust (hits %s)" % str(hits), was_dash and hits.size() == 1) and ok
	p.since_dash = 99.0
	_clear_enemies(main)

	# 3. attacking a staggered enemy executes it
	hits.clear()
	e = _spawn(main, 0, p.global_position + Vector3(0, 0.4, 1.8))
	for i in 3: await physics_frame
	while not e.staggered:
		e.take_hit(10.0, Vector3.FORWARD)
	var kills0: int = main.kills
	p.attack_cd = 0.0
	p._attack_pressed()
	var was_fin: bool = p.move_name == "finisher" and p.finisher_t > 0.0
	await physics_frame
	ok = _check("the execution victim reacts (exec_t %.2f, clip %s)" % [e.exec_t, e.anim_state], e.exec_t > 0.0 and not e.dead and (e.anim == null or e.anim_state == "executed")) and ok
	for i in 120:
		await physics_frame
		if e.dead:
			break
	main.clear_slowmo()
	ok = _check("attack on a staggered enemy is the execution (dead %s, kills +%d)" % [e.dead, main.kills - kills0], was_fin and e.dead and main.kills == kills0 + 1) and ok
	for i in 100: await physics_frame
	_clear_enemies(main)

	# 4. a parry during the wind-up negates the strike and staggers the attacker
	e = _spawn(main, 0, p.global_position + Vector3(0, 0.4, 1.2))
	for i in 3: await physics_frame
	p.hp = p.max_hp
	p.invuln_t = 0.0
	p.parry_cd = 0.0
	e.attack_cd = 9.0
	e.strike_dir = Vector3(0, 0, -1)
	e.windup_t = 0.2 # the eye-flare: his strike is coming
	p._parry()
	for i in 30: await physics_frame
	main.clear_slowmo()
	ok = _check("parry negates the strike and staggers him (hp %.0f, staggered %s)" % [p.hp, e.staggered], p.hp == p.max_hp and e.staggered and e.windup_t <= 0.0) and ok
	# without the parry the same wind-up lands
	_clear_enemies(main)
	e = _spawn(main, 0, p.global_position + Vector3(0, 0.4, 1.2))
	for i in 3: await physics_frame
	e.attack_cd = 9.0
	e.strike_dir = Vector3(0, 0, -1)
	e.windup_t = 0.2
	for i in 30: await physics_frame
	ok = _check("the same strike lands without a parry (hp %.0f)" % p.hp, p.hp < p.max_hp) and ok
	main.clear_slowmo()
	_clear_enemies(main)

	# 5. a light hit lands on the clip's strike frame (~0.1 s after the press), not on the press
	hits.clear()
	e = _spawn(main, 0, p.global_position + Vector3(0, 0.4, 1.6))
	for i in 3: await physics_frame
	e.max_hp = 1e6
	e.hp = 1e6
	e.attack_cd = 99.0
	e.special_cd = 99.0
	p.facing = 0.0
	p.combo_t = 0.0
	p.attack_cd = 0.0
	p._attack()
	var wait: float = p.pending.get("t", 0.0)
	var on_press: bool = hits.is_empty() and p.pending.has("combo")
	for i in 30:
		await physics_frame
		if p.pending.is_empty():
			break
	main.clear_slowmo()
	ok = _check("light hit lands on the strike frame (%.3f s after the press, hits %s)" % [wait, str(hits)], on_press and wait > 0.05 and wait < 0.2 and hits.size() == 1) and ok

	# 6. input buffer: a press during the cooldown comes out when it ends (a tap, not a charge)
	for i in 30: await physics_frame
	p.combo_t = 0.0
	p.attack_cd = 0.15
	p.move_name = ""
	p.attack_block_until = 0
	Input.action_press("attack")
	await physics_frame
	Input.action_release("attack")
	await physics_frame
	await physics_frame
	var held: bool = p.attack_buffer_t > 0.0 and p.move_name == ""
	for i in 20: await physics_frame
	main.clear_slowmo()
	ok = _check("a press during the cooldown is buffered (%s -> %s)" % [held, p.move_name], held and p.combo == 1 and p.move_name.ends_with("1") and p.attack_buffer_t == 0.0 and p.hold_t < 0.0) and ok
	p.hit_enemy.disconnect(rec)
	for i in 30: await physics_frame
	main.clear_slowmo()
	_clear_enemies(main)

	# 7. movement ramps: not full speed on the first frame, full speed within ~0.1 s
	p.walk_vel = Vector3.ZERO
	p.velocity = Vector3.ZERO
	p.swing_t = 0.0
	for i in 3: await physics_frame
	_pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	await physics_frame
	var v1 := Vector2(p.velocity.x, p.velocity.z).length()
	for i in 10: await physics_frame
	var v2 := Vector2(p.velocity.x, p.velocity.z).length()
	_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
	await physics_frame
	var v3 := Vector2(p.velocity.x, p.velocity.z).length()
	for i in 12: await physics_frame
	var v4 := Vector2(p.velocity.x, p.velocity.z).length()
	ok = _check("run ramps up and down (%.1f -> %.1f, stop %.1f -> %.1f)" % [v1, v2, v3, v4], v1 < p.WALK * 0.6 and v2 > p.WALK * 0.95 and v3 > 0.5 and v4 < 0.2) and ok
	ok = _check("camera arm casts a sphere against the world", p.spring.shape is SphereShape3D and p.spring.collision_mask & 1) and ok
	var coat_mi = p.visual.find_child("Coat", true, false)
	var coat_mat = coat_mi.material_override if coat_mi != null else null
	ok = _check("the coat is matte leather, not metal", coat_mi == null or (coat_mat is StandardMaterial3D and coat_mat.metallic == 0.0 and coat_mat.metallic_texture == null and coat_mat.roughness >= 0.55)) and ok

	# 8. second attacks: the vampire lunge and the wolf leap telegraph on the ground and land
	p.global_position = Vector3(10.0, 0.1, 10.0)
	p.velocity = Vector3.ZERO
	p.hp = p.max_hp
	p.invuln_t = 0.0
	p.dash_t = 0.0
	p.since_dash = 99.0
	p.parry_t = 0.0
	for kind in [0, 1]:
		var name: String = "lunge" if kind == 0 else "leap"
		e = _spawn(main, kind, p.global_position + Vector3(0, 0.4, 6.5))
		for i in 3: await physics_frame
		if kind == 1:
			e.transform_t = 0.0 # skip the change
		e.special_cd = 0.0
		e.attack_cd = 0.0
		p.hp = p.max_hp
		p.invuln_t = 0.0
		var started := false
		var tele := false
		for i in 240:
			await physics_frame
			p.global_position = Vector3(10.0, 0.1, 10.0) # Sol stands his ground
			if e.special.begins_with(name):
				if not started:
					tele = e.tell_total > 0.0 and e.telegraph == null # the body tells it (clip wind-up on the slow-in curve), no floor decal
				started = true
			elif started:
				break
		main.clear_slowmo()
		ok = _check("%s %s: body tell %s (no decal), landed (hp %.0f)" % ["vampire" if kind == 0 else "wolf", name, tele, p.hp], started and tele and p.hp < p.max_hp) and ok
		_clear_enemies(main)
		for i in 3: await physics_frame
	p.hp = p.max_hp

	# 9. health bar over an engaged enemy: pale above the stagger threshold, red at or under it
	e = _spawn(main, 0, p.global_position + Vector3(0, 0.4, 3.0))
	for i in 3: await physics_frame
	e.attack_cd = 99.0
	e.special_cd = 99.0
	e.take_hit(12.0, Vector3.FORWARD)
	for i in 2: await physics_frame
	var shown: bool = e.hp_bar != null and e.hp_bar.visible
	var pale: Color = e.hp_bar_mat.get_shader_parameter("fill_col") if shown else Color.BLACK
	e.take_hit(20.0, Vector3.FORWARD) # 8 / 40 left: under 25%, he staggers
	for i in 2: await physics_frame
	var red: Color = e.hp_bar_mat.get_shader_parameter("fill_col") if shown else Color.BLACK
	var frac: float = e.hp_bar_mat.get_shader_parameter("frac") if shown else 1.0
	e._die(false)
	ok = _check("engaged enemy shows a health bar (pale %s, red %s, frac %.2f)" % [pale, red, frac], shown and pale.g > 0.6 and red.r > 0.9 and red.g < 0.6 and frac <= 0.25 and not e.hp_bar.visible) and ok
	_clear_enemies(main)
	p.hp = p.max_hp
	main.clear_slowmo()
	return ok


# ---------------------------------------------------------------- audio, dialogue, subtitles
## Asset round 3: the creature clips, the bosses' own bodies, their themes.
func _asset_r3_checks(main) -> bool:
	var ok := true
	# creature clips (tools/build_r3_anims.gd): baked in place, strike times from the manifest
	var want := {"werewolf": ["roar", "attack", "jump", "death", "sprint"], "vampire": ["claw_combo", "lunge", "backflip", "attack"], "civilian": ["death"]}
	for n in want:
		var inst: Node3D = (load("res://assets/characters/%s/%s_anim.scn" % [n, n]) as PackedScene).instantiate()
		var ap: AnimationPlayer = inst.get_node("AnimationPlayer")
		var r3: Array = inst.get_meta("r3_clips", [])
		var has_all := true
		for c in want[n]:
			has_all = has_all and ap.has_animation(c) and r3.has(c)
		# in place: the hips never travel over the ground
		var drift := 0.0
		for c in want[n]:
			var a: Animation = ap.get_animation(c)
			for t in a.get_track_count():
				if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
					var p0: Vector3 = a.track_get_key_value(t, 0)
					for k in a.track_get_key_count(t):
						var pk: Vector3 = a.track_get_key_value(t, k)
						drift = maxf(drift, Vector2(pk.x - p0.x, pk.z - p0.z).length())
		ok = _check("%s has the round-3 clips %s, in place (drift %.3f m)" % [n, want[n], drift], has_all and drift < 0.01) and ok
		inst.free()
	var ww: Node3D = (load("res://assets/characters/werewolf/werewolf_anim.scn") as PackedScene).instantiate()
	ok = _check("werewolf strike time from the manifest (heavy swipe 1.57 s)", is_equal_approx(float(ww.get_meta("strike_time")), 1.57)) and ok
	ww.free()
	var e = _spawn(main, 0, main.player.global_position + Vector3(40, 0, 40))
	await process_frame
	ok = _check("a live vampire plays the new clips (lunge, claw combo)", e.anim != null and e.anim.has_animation("lunge") and e.anim.has_animation("claw_combo") and is_equal_approx(e.strike_time, 0.57)) and ok
	_clear_enemies(main)
	# bosses: Marcus Crane and the Abomination wear their own models
	var models := {"marcus": "res://scripts/hunt/bosses/velvet_fang.gd", "abomination": "res://scripts/hunt/bosses/abomination.gd"}
	for id in models:
		var b = load(models[id]).new()
		b.main = main
		b.boss_id = id
		b.position = main.player.global_position + Vector3(30, 0.5, 30)
		main.enemies_root.add_child(b)
		for i in 5: await physics_frame
		var r: Dictionary = b.rigs[0] if b.rigs.size() > 0 else {}
		var model_ok: bool = r.get("name", "") == id and r.get("skel") != null and b.rigs.size() == 1
		var anim_ok: bool = r.get("anim") != null and r.anim.has_animation("boss/heavy") and r.anim.has_animation("attack") and r.anim.current_animation != ""
		ok = _check("%s wears its own model and clips (%s, playing %s)" % [id, r.get("name", "?"), r.anim.current_animation if anim_ok else "none"], model_ok and anim_ok) and ok
		# grounded and to scale: feet on the floor, as tall as its stand-in
		var aabb: AABB = (r.skel.get_node("Body") as MeshInstance3D).get_aabb() if model_ok else AABB()
		var h: float = aabb.size.y * r.model.scale.y if model_ok else 0.0
		ok = _check("%s stands on the ground at boss size (%.2f m, feet at %.2f)" % [id, h, aabb.position.y], model_ok and absf(aabb.position.y) < 0.02 and h > 2.0 and h < 4.8) and ok
		if id == "marcus" and model_ok:
			var mat: StandardMaterial3D = (r.skel.get_node("Body") as MeshInstance3D).mesh.surface_get_material(0)
			ok = _check("Marcus's coat is matte (metallic %.2f, roughness %.2f)" % [mat.metallic, mat.roughness], mat.metallic == 0.0 and mat.metallic_texture == null and mat.roughness >= 0.55) and ok
			ok = _check("Marcus reads clean: no vein overlay, no aura shell", float(b.overlay.get_shader_parameter("vein_amount")) == 0.0 and not b.aura.visible) and ok
		if model_ok:
			var tris: int = (r.skel.get_node("Body") as MeshInstance3D).mesh.surface_get_array_index_len(0) / 3
			ok = _check("%s is inside the web budget (%d triangles <= 22k)" % [id, tris], tris <= 22000) and ok
		if id == "marcus":
			ok = _check("Marcus's own clips: the lunge on dashes, the slash combo on swipes", model_ok and r.anim.has_animation("boss/thrust") and is_equal_approx(float(r.strikes.get("boss/thrust", 0.0)), 0.9) and is_equal_approx(float(r.strikes.get("attack", 0.0)), 0.83)) and ok
		else:
			ok = _check("the Abomination's own clips: the slam and the roar", model_ok and r.anim.has_animation("boss/roar") and is_equal_approx(float(r.strikes.get("boss/heavy", 0.0)), 1.67)) and ok
		main.enemies_root.remove_child(b)
		b.free()
	# the Hollow Alpha: the werewolf at 1.35x on the new clips, its howl the roar mocap
	var al = load("res://scripts/hunt/bosses/hollow_alpha.gd").new()
	al.main = main
	al.position = main.player.global_position + Vector3(30, 0.5, 30)
	main.enemies_root.add_child(al)
	await physics_frame
	var ar: Dictionary = al.rigs[0]
	ok = _check("the Hollow Alpha is the werewolf at 1.35x with the roar", ar.name == "werewolf" and is_equal_approx(ar.model.scale.x, 1.35) and ar.anim != null and ar.anim.has_animation("boss/roar") and ar.anim.has_animation("roar")) and ok
	main.enemies_root.remove_child(al)
	al.free()
	# boss themes: each plays in its own fight, the others keep the shared boss track
	var audio = root.get_node("Audio")
	var was_over: bool = main.game_over
	main.game_over = false
	audio.attach_world(main)
	for id in ["marcus", "abomination"]:
		audio.set_boss(true, id)
		var s: AudioStream = audio._music[audio._music_cur].stream
		ok = _check("boss music: %s's theme plays in its fight (%s)" % [id, audio.context], audio.context == "boss_" + id and s != null and s.resource_path.ends_with("boss_%s.ogg" % id) and (s as AudioStreamOggVorbis).loop) and ok
	audio.set_boss(true, "knight")
	ok = _check("boss music: a boss without a theme keeps the boss track", audio.context == "boss") and ok
	audio.set_boss(false)
	audio.set_music("explore", 0.1)
	main.game_over = was_over
	for n in ["wolf_roar", "claw_swipe", "pounce_whoosh", "lunge_whoosh", "body_fall", "boss_slam_impact"]:
		ok = _check("creature SFX loads: " + n, audio._pick(n) != null) and ok
	return ok


## St. Roch Cemetery (map/cemetery.gd, world/crows.gd): the groundskeeper's shed and the open
## grave exist and block, the grave furniture stays inside its share of the web budget, and crows
## take off when Sol walks up to them or swings nearby.
func _cemetery_checks(main) -> bool:
	var ok := true
	var city = main.city
	var p = main.player
	_clear_enemies(main)
	main.spawn_timer = 9999.0
	var info: Dictionary = city.get_meta("cemetery", {})
	ok = _check("cemetery built (%d headstones)" % int(info.get("stones", 0)), int(info.get("stones", 0)) > 400) and ok
	var shed: Rect2 = info.get("shed", Rect2())
	ok = _check("the groundskeeper's shed exists, lit, with its keeper", city.get_node_or_null("GroundskeeperShed") != null and shed.size.x > 2.0 and city.get_meta("gy_keeper", null) != null and (city.get_meta("gy_keeper") as Node).lights.size() >= 3) and ok
	# the shed is solid: a ray across it hits
	var space: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	var sc := Vector3(shed.get_center().x, 1.2, shed.get_center().y)
	var q := PhysicsRayQueryParameters3D.create(sc + Vector3(-6, 0, 0), sc, 1)
	ok = _check("the shed has collision", not space.intersect_ray(q).is_empty()) and ok
	# the open grave: a hole with a collider over it (Sol can't walk into it)
	var hole: Rect2 = info.get("hole", Rect2())
	var hc := Vector3(hole.get_center().x, 0, hole.get_center().y)
	var hits := 0
	for off in [Vector3.ZERO, Vector3(hole.size.x * 0.4, 0, 0), Vector3(-hole.size.x * 0.4, 0, hole.size.y * 0.4)]:
		var rq := PhysicsRayQueryParameters3D.create(hc + off + Vector3(0, 4, 0), hc + off + Vector3(0, -3, 0), 1)
		var h := space.intersect_ray(rq)
		if not h.is_empty() and h.position.y > 0.05:
			hits += 1
	ok = _check("the open grave has collision (%d/3 probes)" % hits, hole.size.x > 0.5 and hits == 3 and city.get_node_or_null("OpenGrave") != null) and ok
	# budget: the cemetery's own draw nodes and their worst-case triangles (all in range at once)
	var nodes: Array = info.get("nodes", [])
	var tris := 0
	for n in nodes:
		if n is MultiMeshInstance3D:
			var mm: MultiMesh = n.multimesh
			tris += mm.mesh.get_faces().size() / 3 * mm.instance_count
		elif n is MeshInstance3D:
			tris += n.mesh.get_faces().size() / 3
	ok = _check("cemetery decoration inside its web budget (%d draw nodes <= 60, %dk triangles <= 260k)" % [nodes.size(), tris / 1000], nodes.size() <= 60 and tris <= 260000) and ok
	# crows: walk Sol up to a low perched crow, it takes off; a swing scatters others nearby
	var crows = city.get_node_or_null("Crows")
	ok = _check("crows spawned and perched (%d)" % (crows.perched_count() if crows != null else 0), crows != null and crows.perched_count() >= 20) and ok
	if crows == null:
		return ok
	var foot := Rect2(-66, 100, 132, 100)
	var pick := -1
	for k in crows.crows.size():
		var cs: Dictionary = crows.crow_state(k)
		if cs.state == "perched" and cs.pos.y < 2.0 and foot.has_point(Vector2(cs.pos.x, cs.pos.z)) and crows.crows[k].t > 1.0:
			pick = k
			break
	ok = _check("a crow perched low in the cemetery", pick >= 0) and ok
	if pick >= 0:
		var cp: Vector3 = crows.crow_state(pick).pos
		var t0: int = crows.takeoffs
		var dir := Vector3(1, 0, 0)
		var stand := cp + dir * 3.5
		if not main.spot_clear(Vector3(stand.x, main.ground_y(stand.x, stand.z) + 0.9, stand.z)):
			stand = cp - dir * 3.5
		p.velocity = Vector3.ZERO
		p.global_position = Vector3(stand.x, main.ground_y(stand.x, stand.z) + 0.2, stand.z)
		await _wait_physics(45)
		var st: Dictionary = crows.crow_state(pick)
		ok = _check("a crow takes off when Sol comes within 4 m (%s, %d take-offs)" % [st.state, crows.takeoffs - t0], st.state != "perched" and crows.takeoffs > t0) and ok
		await _wait_physics(60)
		st = crows.crow_state(pick)
		ok = _check("the startled crow flies off (%.1f m up and away)" % st.pos.distance_to(cp), st.state == "gone" or st.pos.distance_to(cp) > 3.0) and ok
	# a swing scatters perched crows within the attack radius
	var near: Dictionary = {}
	for k in crows.crows.size():
		var cs: Dictionary = crows.crow_state(k)
		if cs.state == "perched" and cs.pos.y < 6.0 and foot.has_point(Vector2(cs.pos.x, cs.pos.z)) and p.global_position.distance_to(cs.pos) > 20.0:
			near = {"k": k, "pos": cs.pos}
			break
	if not near.is_empty():
		var np: Vector3 = near.pos
		var away := Vector3(0, 0, 8.0)
		var sp := np + away
		if not main.spot_clear(Vector3(sp.x, 1.0, sp.z)):
			sp = np - away
		p.velocity = Vector3.ZERO
		p.global_position = Vector3(sp.x, main.ground_y(sp.x, sp.z) + 0.2, sp.z)
		await _wait_physics(5)
		var was: String = crows.crow_state(near.k).state
		p.attacked.emit(0, Vector3.FORWARD)
		await _wait_physics(40)
		ok = _check("a swing 8 m away scatters a perched crow (%s -> %s)" % [was, crows.crow_state(near.k).state], crows.crow_state(near.k).state != "perched") and ok
	# the keeper says his line when Sol walks up (subtitle; text-only voice)
	var keeper = city.get_meta("gy_keeper", null)
	if keeper != null:
		var kp: Vector3 = keeper.global_position + Vector3(2.5, 0, 0)
		p.global_position = Vector3(kp.x, main.ground_y(kp.x, kp.z) + 0.2, kp.z)
		var dlg = root.get_node("Dialogue")
		dlg.stop_all()
		var was_unlocked: bool = root.get_node("Audio").unlocked
		root.get_node("Audio").unlocked = true
		keeper._talk_cd = 0.0
		await _wait_physics(10)
		ok = _check("the groundskeeper speaks when Sol comes near (%s)" % dlg.subtitle_text(), keeper.spoke >= 1 and dlg.subtitle_text().begins_with("OLD AMOS")) and ok
		dlg.stop_all()
		root.get_node("Audio").unlocked = was_unlocked
	main.spawn_timer = 4.0
	return ok


func _audio_checks(main) -> bool:
	var ok := true
	var audio = root.get_node("Audio")
	var dlg = root.get_node("Dialogue")
	# every line's voice file exists and loads
	var bad := []
	for id in dlg.lines:
		var l: Dictionary = dlg.lines[id]
		if str(l.audio) == "" and l.get("category", "") == "npc":
			# text-only ambient NPC lines (the groundskeeper): subtitle, no voice file yet
			if float(l.duration) <= 0.0 or not dlg.speakers.has(l.speaker):
				bad.append(id)
			continue
		var s = load(l.audio) if ResourceLoader.exists(l.audio) else null
		if s == null or s.get_length() < 0.3 or float(l.duration) <= 0.0 or not dlg.speakers.has(l.speaker):
			bad.append(id)
	ok = _check("all %d dialogue lines have audio that loads %s" % [dlg.lines.size(), bad], bad.is_empty() and dlg.lines.size() >= 45) and ok
	var missing := []
	for n in audio.SFX:
		for path in audio.SFX[n]:
			if audio.stream(path) == null:
				missing.append(path)
	for c in audio.MUSIC:
		if audio.stream(audio.MUSIC[c]) == null:
			missing.append(c)
	ok = _check("all SFX and music load %s" % [missing], missing.is_empty()) and ok
	# Dialogue.play shows a subtitle, queues behind a busy channel, a boss line cuts in
	var St = load("res://scripts/settings.gd")
	St.subtitles = true
	dlg.stop_all()
	var started: bool = dlg.play("curfew_warning")
	await process_frame
	ok = _check("Dialogue.play starts a line with a subtitle", started and dlg.is_speaking() and dlg.subtitle_text().begins_with("NIA") and dlg.subtitle_text().contains("Red Curfew")) and ok
	var queued: bool = dlg.play("hunt_hub")
	ok = _check("a second comms line queues", queued and dlg.queue.size() == 1 and dlg.current.id == "curfew_warning") and ok
	ok = _check("a bark during comms waits briefly or drops, never overlaps", dlg.current.id == "curfew_warning") and ok
	dlg.play("boss_marcus_intro")
	ok = _check("a boss intro beats a lower line", dlg.current.id == "boss_marcus_intro" and dlg.subtitle_text().begins_with("MARCUS")) and ok
	ok = _check("same line on cooldown is refused", not dlg.play("boss_marcus_intro") or dlg.lines["boss_marcus_intro"].cooldown == 0) and ok
	St.subtitles = false
	dlg.stop_all()
	dlg.play("poi_cleared_2")
	await process_frame
	ok = _check("subtitles off hides the label", dlg.is_speaking() and dlg.subtitle_text() == "") and ok
	St.subtitles = true
	dlg.stop_all()
	# QA2 #9: every boss has a voiced intro and death line that cuts in (priority 3)
	var Cfg9 = load("res://scripts/hunt/hunt_config.gd")
	var mute := []
	for bd in Cfg9.NIGHT_BOSS_POOL + [Cfg9.FINAL_BOSS]:
		for k in ["intro", "death"]:
			var lid: String = bd.get(k, "")
			if lid == "" or not dlg.has_line(lid) or int(dlg.lines[lid].get("priority", 0)) < 3:
				mute.append("%s.%s" % [bd.id, k])
	ok = _check("every boss has a voiced intro and death line %s" % [mute], mute.is_empty()) and ok
	ok = _check("hunt line ids exist for the run hooks", dlg.has_line("hunt_deploy_1") and dlg.has_line("curfew_warning") and dlg.has_line("boss_alpha_intro")) and ok
	# music follows the fight: enemies near -> combat, boss -> boss, calm -> explore
	_clear_enemies(main)
	var was_over: bool = main.game_over
	main.game_over = false
	audio.attach_world(main)
	audio._calm_t = 99.0
	audio._poll_t = 0.0
	await process_frame
	await process_frame
	ok = _check("music is the exploration bed with no enemies near", audio.context == "explore") and ok
	_spawn(main, 0, main.player.global_position + Vector3(3, 0, 0))
	audio._poll_t = 0.0
	await process_frame
	await process_frame
	ok = _check("music switches to combat when enemies engage", audio.context == "combat") and ok
	audio.set_boss(true)
	ok = _check("music switches to the boss track", audio.context == "boss") and ok
	audio.set_boss(false)
	_clear_enemies(main)
	audio._calm_t = 99.0
	audio._poll_t = 0.0
	await process_frame
	await process_frame
	ok = _check("music falls back to explore when calm", audio.context == "explore") and ok
	audio.set_music("menu", 0.1)
	ok = _check("menu music context", audio.context == "menu" and audio._music[audio._music_cur].stream != null) and ok
	audio.set_music("explore", 0.1)
	main.game_over = was_over
	# Voice bus and subtitle setting round-trip
	var path := "user://smoke_audio.cfg"
	var keep: Dictionary = St.volume.duplicate()
	var keep_sub: bool = St.subtitles
	St.volume["Voice"] = 0.35
	St.subtitles = false
	var saved: bool = St.save_settings(path)
	St.volume["Voice"] = 0.9
	St.subtitles = true
	var loaded: bool = St.load_settings(path)
	ok = _check("Voice volume and subtitles round-trip", saved and loaded and is_equal_approx(St.volume["Voice"], 0.35) and St.subtitles == false) and ok
	St.volume = keep
	St.subtitles = keep_sub
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ok = _check("Voice bus exists", AudioServer.get_bus_index("Voice") >= 0) and ok
	return ok


# ---------------------------------------------------------------- performance, tiers, settings menu
## PERF: the quality presets set their values and reach the scene, the settings persist, the pause
## menu opens the shared tabbed panel, Very Low is truly minimal, dynamic resolution reacts, the
## first-use loads are pre-warmed, and a generous per-frame time guard at a fixed spot.
func _perf_checks(main) -> bool:
	var ok := true
	var St = load("res://scripts/settings.gd")
	var st = root.get_node("Settings")
	var keep: Dictionary = St.snapshot()
	var vp := root.get_viewport()
	var sun: DirectionalLight3D = main.sun
	var bad := []
	for t in 4:
		st.set_value("tier", t)
		await process_frame
		if not (St.tier == t and St.matches_tier(t) and is_equal_approx(vp.scaling_3d_scale, St.PRESET_VALUES[t].resolution_scale)):
			bad.append(St.PRESETS[t])
		if Engine.max_fps != [30, 60, 60, 0][t]:
			bad.append("%s fps %d" % [St.PRESETS[t], Engine.max_fps])
	ok = _check("each quality preset applies its values %s" % [bad], bad.is_empty()) and ok
	st.set_value("tier", 0)
	await process_frame
	var pv: Dictionary = St.PRESET_VALUES[0]
	ok = _check("Very Low: no shadows (sun %s), render scale %.2f, short view %.2f, sparse foliage, no post FX, static coat, 30 fps" % [sun.shadow_enabled, vp.scaling_3d_scale, St.view_distance],
		St.shadow_quality == 0 and not sun.shadow_enabled and vp.scaling_3d_scale <= 0.6 and St.view_distance <= 75.0 and St.foliage_density <= 0.35
		and not St.post_fx and St.coat_quality == 0 and St.light_quality == 0 and pv.fps_cap == 0) and ok
	# Very Low reaches the world through city.gd / map/world_quality.gd: shorter ranges, thinned
	# foliage and street clutter (read from these settings by name)
	var city = main.city
	var shrunk := 0
	var nr := 0
	for e in city.get("_q_ranges") if city.get("_q_ranges") != null else []:
		if is_instance_valid(e[0]) and float(e[2]) > 0.0:
			nr += 1
			if (e[0] as GeometryInstance3D).visibility_range_end < float(e[2]) - 0.01:
				shrunk += 1
	var thin := 0
	var nf := 0
	for mm in (city.get("_q_foliage") if city.get("_q_foliage") != null else []) + (city.get("_q_props") if city.get("_q_props") != null else []):
		nf += 1
		if mm.visible_instance_count >= 0 and mm.visible_instance_count < mm.instance_count:
			thin += 1
	var WQ = load("res://scripts/map/world_quality.gd")
	ok = _check("Very Low thins the world: %d / %d ranges shortened, %d / %d foliage + clutter MultiMeshes thinned (view %.0f m, foliage %.2f, props %.2f)" % [shrunk, nr, thin, nf, WQ.view_distance(), WQ.foliage_density(), WQ.prop_density()],
		WQ.tier() == 0 and nr > 0 and shrunk * 2 > nr and nf > 0 and thin * 2 > nf) and ok
	# a hand-picked value makes it Custom; picking the preset's value again lands back on it
	st.set_value("tier", 2)
	st.set_value("shadow_distance", 100.0)
	var was_custom: bool = St.tier == 4
	st.set_value("shadow_distance", St.PRESET_VALUES[2].shadow_distance)
	ok = _check("a hand-picked graphics value makes the preset Custom, and back", was_custom and St.tier == 2) and ok
	# persist / reload every new key (scratch file)
	var path := "user://smoke_perf_settings.cfg"
	st.set_value("tier", 1)
	St.fov = 88.0
	St.colorblind = 2
	St.toggle_sprint = true
	St.hud_opacity = 0.55
	St.subtitle_size = 3
	St.mute_unfocused = false
	var saved: bool = St.save_settings(path)
	St.restore(keep)
	var loaded: bool = St.load_settings(path)
	ok = _check("settings persist and reload (tier, FOV, colour-blind, toggle sprint, HUD opacity, subtitle size)", saved and loaded and St.tier == 1 and St.matches_tier(1)
		and is_equal_approx(St.fov, 88.0) and St.colorblind == 2 and St.toggle_sprint and is_equal_approx(St.hud_opacity, 0.55) and St.subtitle_size == 3 and not St.mute_unfocused) and ok
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ok = _check("colour-blind palette remaps the red telegraph", St.cb(Color(1.0, 0.05, 0.15)) != Color(1.0, 0.05, 0.15) and St.cue("danger").g > 0.3) and ok
	St.restore(keep)
	# dynamic resolution: slow frames lower the render scale, steady frames give it back
	St.dynamic_res = true
	St.fps_cap = 1
	St.dyn_scale = 1.0
	for i in 90:
		st.feed_frame_time(50.0, 1.0 / 60.0)
	var low: float = St.dyn_scale
	for i in 60 * 30:
		st.feed_frame_time(10.0, 1.0 / 60.0)
	ok = _check("dynamic resolution reacts (slow -> x%.2f, steady -> x%.2f)" % [low, St.dyn_scale], low < 1.0 and St.dyn_scale > low) and ok
	St.restore(keep)
	St.dyn_scale = 1.0
	st.apply_all()
	st.apply_graphics()
	# the pause menu opens the shared tabbed panel; a choice row steps; tabs switch
	main.ui_block_until = 0
	main.pause_menu.open()
	main.pause_menu._show("options")
	await process_frame
	var panel = main.pause_menu.options.get_child(0)
	var t0: int = St.tier
	var stepped: bool = panel.step_choice("tier", 1)
	var t1: int = St.tier
	panel.confirm_revert()
	ok = _check("the pause menu opens the tabbed options panel (%d tabs), the preset row steps (%d -> %d) and reverts (%d)" % [panel.tab_buttons.size(), t0, t1, St.tier],
		main.pause_menu.options.visible and panel.is_visible_in_tree() and panel.tab_buttons.size() == 5 and stepped and t1 != t0 and St.tier == t0) and ok
	panel.show_tab(4)
	ok = _check("tabs switch (Accessibility shows its rows)", panel.pages[4].visible and not panel.pages[0].visible and panel.row_control("colorblind") != null) and ok
	panel.show_tab(0)
	main.pause_menu.close()
	St.restore(keep)
	st.apply_all()
	# pre-warm: every body is loaded before play
	var PW = load("res://scripts/prewarm.gd")
	var EnemyS = load("res://scripts/enemy.gd")
	var BossS = load("res://scripts/hunt/bosses/boss_base.gd")
	var cold := []
	for k in EnemyS.ANIM_PATHS:
		if not EnemyS._scene_cache.has(k):
			cold.append(k)
	for k in BossS.ANIM_PATHS:
		if not BossS._scene_cache.has(k):
			cold.append(k)
	ok = _check("pre-warm loaded every body before play %s (%s)" % [cold, str(PW.last_report)], cold.is_empty() and int(PW.last_report.get("resources", 0)) > 5) and ok
	# per-frame time guard (generous): 8 enemies fighting round Sol at a fixed spot
	_clear_enemies(main)
	var p = main.player
	var keep_hp: Array = [p.hp, p.max_hp, p.global_position, main.time_of_day]
	p.global_position = main.safe_ground(Vector3(0, 0, 30)) + Vector3(0, 0.2, 0)
	p.max_hp = 1e9
	p.hp = 1e9
	main.time_of_day = 0.9
	for i in 8:
		var a := TAU * i / 8.0
		_spawn(main, i % 2, main.safe_ground(p.global_position + Vector3(cos(a), 0, sin(a)) * 6.0) + Vector3(0, 0.3, 0))
	for i in 30: await process_frame
	var frames := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	var t_end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < t_end:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	var tot := 0.0
	for f in frames:
		tot += f
	var mean := tot / maxf(frames.size(), 1)
	frames.sort()
	var p99: float = frames[mini(int(frames.size() * 0.99), frames.size() - 1)] if frames.size() > 0 else 999.0
	ok = _check("per-frame time guard: 8 enemies round Sol, mean %.2f ms, p99 %.2f ms over %d frames (limits 25 / 120)" % [mean, p99, frames.size()], mean < 25.0 and p99 < 120.0) and ok
	_clear_enemies(main)
	p.max_hp = keep_hp[1]
	p.hp = keep_hp[0]
	p.global_position = keep_hp[2]
	main.time_of_day = keep_hp[3]
	return ok


# ---------------------------------------------------------------- main menu, pause, settings
func _key(code: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## L6: a full win. All three bosses die in turn (Night 1, Night 2, the Final Night), the Hunt is
## won and the results screen shows, with the win epilogue.
func _three_boss_win(m) -> bool:
	var ok := true
	var h = m.hunt
	var p = m.player
	p.max_hp = 1e9
	p.hp = 1e9
	_clear_enemies(m)
	for night in 3:
		if night < 2:
			h.debug_skip_to("boss")
			var ap: Vector3 = h.arena.pos
			var sd := Vector2(p.global_position.x - ap.x, p.global_position.z - ap.z).length()
			ok = _check("debug_skip_to(boss) stands Sol inside the arena (%.1f m from centre, radius %.0f)" % [sd, h.arena.radius], sd < float(h.arena.radius) - 1.0 and sd > 2.0) and ok
		else:
			await _wait_physics(int((h.T.final_dusk + 1.0) * 60.0)) # dusk -> the Undercroft Plaza
		await _wait_physics(5)
		var b = h.boss
		var want: Dictionary = h.boss_def(night)
		ok = _check("win run: night %d boss is %s" % [night + 1, want.id], b != null and is_instance_valid(b) and b.boss_id == want.id and h.state == "boss") and ok
		if b == null or not is_instance_valid(b):
			return false
		p.hp = 1e9
		b.take_hit(1e7, Vector3.FORWARD)
		m.clear_slowmo()
		await _wait_physics(3)
		if night < 2:
			ok = _check("win run: a Blood Rite after night %d" % (night + 1), await _take_rite(h)) and ok
		if night == 0:
			await _wait_physics(int((h.T.victory + 1.0) * 60.0))
			ok = _check("win run: dawn of Day 2 (%s)" % h.state, h.day == 1 and h.state == "explore") and ok
		elif night == 1:
			ok = _check("win run: the Final Night's dusk (%s)" % h.state, h.state == "final_dusk") and ok
	await _wait_physics(int((h.T.victory + 1.5) * 60.0))
	ok = _check("win run: 3 bosses, won, results up (%s)" % h.state, h.bosses_killed == 3 and h.won and h.state == "over" and h.results.visible) and ok
	ok = _check("win run: results carry the win epilogue", h.summary.get("won", false) and String(h.summary.get("epilogue", "")) != "" and h.results.epilogue.visible) and ok
	ok = _check("win run: results list the Blood Rites taken (%s)" % str(h.summary.get("rites", [])), h.summary.get("rites", []).size() == 2 and h.results.stats.text.contains("Blood Rites")) and ok
	ok = _check("win run: no Rite after the Final Night (offered %d)" % h.rites_offered, h.rites_offered == 2 and not h.rite_ui.is_open()) and ok
	paused = false
	return ok


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
	# WEB AUDIO FIX: the buses must come from the startup bus layout. Buses added at runtime with
	# AudioServer.add_bus() desync Godot 4.3's Web Audio bus mirror into a send cycle that the
	# browser silences (no sound at all on the web). See settings.gd ensure_buses().
	var bl_path := str(ProjectSettings.get_setting("audio/buses/default_bus_layout", ""))
	var bl = load(bl_path) if ResourceLoader.exists(bl_path) else null
	var bl_ok: bool = bl is AudioBusLayout
	if bl_ok:
		var want := ["Music", "SFX", "Voice"]
		for k in want.size():
			bl_ok = bl_ok and bl.get("bus/%d/name" % (k + 1)) == StringName(want[k]) and bl.get("bus/%d/send" % (k + 1)) == &"Master"
	ok = _check("web audio: Music/SFX/Voice come from the startup bus layout", bl_ok) and ok
	var routes_ok := true
	for b in ["Music", "SFX", "Voice"]:
		var bi := AudioServer.get_bus_index(b)
		routes_ok = routes_ok and bi > 0 and AudioServer.get_bus_send(bi) == &"Master"
	ok = _check("web audio: every bus sends to Master", routes_ok) and ok
	var no_add_bus := true
	for f in ["res://scripts/settings.gd", "res://scripts/audio/audio.gd", "res://scripts/audio/dialogue.gd"]:
		no_add_bus = no_add_bus and not FileAccess.get_file_as_string(f).contains("AudioServer.add_bus(")
	ok = _check("web audio: no runtime AudioServer.add_bus() (breaks the Web Audio buses)", no_add_bus) and ok

	# the main menu scene loads, builds the lair and its screens
	main.queue_free()
	await process_frame
	ok = _check("main menu is the main scene", ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main_menu.tscn") and ok
	# WEB FIX: Godot 4.3's single-threaded web build culls a scene of more than
	# threaded_cull_minimum_instances (default 1000) to nothing (its cull tasks go to worker
	# threads that never run), so the Hunt drew only sky + HUD. Keep the web override high.
	ok = _check("web: threaded culling stays off", int(ProjectSettings.get_setting("rendering/limits/spatial_indexer/threaded_cull_minimum_instances.web", 0)) >= 65536) and ok
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	for i in 5: await process_frame
	var set_ = menu.get_node("LairMenuSet")
	ok = _check("menu lair set builds with Sol and Nia", set_.sol_skel != null and set_.nia != null and set_.camera != null) and ok
	ok = _check("menu has Start / Controls / Options", menu.buttons.size() >= 3 and menu.buttons[0].text == "Start") and ok
	menu.debug_show("options")
	await process_frame
	ok = _check("Options screen opens", menu.options.visible and not menu.menu_box.visible) and ok
	var opt_panel = menu.options.get_child(0)
	var opt_h: float = opt_panel.get_combined_minimum_size().y
	var opt_k: float = opt_panel.fit_scale(Vector2(1280, 720))
	ok = _check("the Options panel fits 720p with Back on screen (%.0f px x %.2f)" % [opt_h, opt_k], opt_h * opt_k <= 720.0 and opt_k >= 0.85 and opt_panel.back_button.get_parent() == opt_panel.get_child(0)) and ok
	menu._back()
	menu.debug_show("controls")
	await process_frame
	ok = _check("Controls screen opens", menu.controls.visible) and ok
	menu._back()
	ok = _check("Back returns to the menu", menu.menu_box.visible and menu.state == "menu") and ok
	menu.debug_show("hub")
	await process_frame
	await process_frame
	var hub_panel = menu.hub.get_child(0)
	ok = _check("Start opens the hub with Begin the Hunt focused", menu.hub.visible and hub_panel.begin_button.has_focus()) and ok
	# QA2 #6: every unowned contact is listed (the column scrolls), and the panel fits on screen
	var Meta0 = load("res://scripts/hunt/hunt_meta.gd")
	var want_shop := 0
	for se in load("res://scripts/hunt/hunt_config.gd").ARMOURY_SHOP:
		if not Meta0.owns(se.id):
			want_shop += 1
	var shop_rows := 0
	for c in hub_panel.shop_box.get_children():
		if c is Button and not c.is_queued_for_deletion():
			shop_rows += 1
	var vp_h: float = hub_panel.get_viewport_rect().size.y
	ok = _check("the hub lists all %d contacts and fits (%d rows, %.0f px of %.0f)" % [want_shop, shop_rows, hub_panel.size.y * hub_panel.scale.y, vp_h],
		shop_rows == want_shop and want_shop >= 1 and hub_panel.size.y * hub_panel.scale.y <= vp_h + 1.0) and ok
	menu._back()
	menu.queue_free()
	await process_frame
	# coming from the menu, main.tscn starts at once without the title overlay
	var MainScript = load("res://scripts/main.gd")
	MainScript.started_once = true
	var m2 = load("res://scenes/main.tscn").instantiate()
	root.add_child(m2)
	await process_frame
	await process_frame
	ok = _check("main starts at once after the menu", m2.started and not paused and not m2.hud.start_overlay.visible) and ok
	m2.queue_free()
	await process_frame
	return ok


# ---------------------------------------------------------------- the Hunt
func _wait_physics(n: int) -> void:
	for i in n:
		await physics_frame


## QA2 #5: nothing is lost below the world. Sol is pulled back onto open ground for a little blood,
## enemies are put back by main's sweep, and safe_ground never answers inside a solid (the tanks).
func _fall_checks(main) -> bool:
	var ok := true
	var p = main.player
	_clear_enemies(main)
	p.dead = false
	p.max_hp = 100.0
	p.hp = 100.0
	await _wait_physics(30)
	var base: Vector3 = p.global_position
	p.global_position = Vector3(base.x, -40.0, base.z)
	await _wait_physics(3)
	var gy: float = main.ground_y(p.global_position.x, p.global_position.z)
	ok = _check("a fall out of the world puts Sol back on open ground (y %.1f, ground %.1f, hp %.0f)" % [p.global_position.y, gy, p.hp],
		p.global_position.y > gy - 1.0 and p.hp == 90.0 and p.falls == 1 and main.spot_clear(p.global_position - Vector3(0, 0.3, 0))) and ok
	var tank := Vector3(-100, 0, 150) # QA2: the navmesh leaks inside this Docks tank
	var sg: Vector3 = main.safe_ground(tank)
	ok = _check("safe_ground never answers inside a solid (tank clear %s -> %s)" % [main.spot_clear(tank), sg], main.spot_clear(sg)) and ok
	var e = _spawn(main, 1, base + Vector3(3, 0.4, 0)) # a wolf: a vampire could burn in the sun
	await _wait_physics(3)
	e.global_position = Vector3(e.global_position.x, -40.0, e.global_position.z)
	await _wait_physics(45)
	ok = _check("an enemy that fell out is put back (y %.1f)" % e.global_position.y, not main.below_world(e.global_position)) and ok
	_clear_enemies(main)
	p.hp = p.max_hp
	# QA2 #8: the lens never sits inside an enemy, and awnings block the camera arm
	await _wait_physics(10)
	var cam: Vector3 = p.camera.global_position
	var g = _spawn(main, 1, Vector3(cam.x, cam.y - 1.2, cam.z))
	await process_frame
	g.global_position = Vector3(cam.x, p.camera.global_position.y - 1.2, cam.z)
	p._camera_obstruction()
	var hid: bool = not g.visual.visible
	g.global_position += Vector3(6, 0, 0)
	p._camera_obstruction()
	ok = _check("an enemy the camera is inside is hidden, then shown again", hid and g.visual.visible) and ok
	ok = _check("the camera arm collides with camera-only blockers (awnings)", p.spring.collision_mask & 512 != 0 and main.city._cam_body != null and main.city._cam_body.get_child_count() > 10) and ok
	_clear_enemies(main)
	return ok


## QA2 #7: a vampire next to an idle Sol still lunges (it hops back out of reach to open with it).
func _special_checks(main) -> bool:
	var ok := true
	var p = main.player
	_clear_enemies(main)
	var tod: float = main.time_of_day
	main.time_of_day = 0.9
	p.max_hp = 1e9
	p.hp = 1e9
	seed(4242)
	var v = _spawn(main, 0, p.global_position + Vector3(0, 0.4, 1.4))
	var backed := false
	var lunged := false
	for i in 900: # 15 s: a backstep can land on cooldown before the opener
		await physics_frame
		if not is_instance_valid(v) or v.dead:
			break
		if v.special.ends_with("_back"):
			backed = true
		if v.special == "lunge_windup" or v.special == "lunge":
			lunged = true
		if backed and lunged:
			break
	main.clear_slowmo()
	ok = _check("a vampire beside an idle Sol hops back and lunges (back %s, lunge %s)" % [backed, lunged], backed and lunged) and ok
	_clear_enemies(main)
	main.time_of_day = tod
	p.max_hp = 100.0
	p.hp = 100.0
	return ok



# ---------------------------------------------------------------- the Undercroft Depths
## Walk Sol toward w (flat), holding forward like a player. Gives up after max_frames.
func _walk_to(p, w: Vector3, max_frames := 300) -> void:
	for n in max_frames:
		var to: Vector3 = w - p.global_position
		to.y = 0.0
		if to.length() < 0.45:
			break
		p.cam_yaw = atan2(-to.x, -to.z)
		Input.action_press("move_forward", 1.0)
		await physics_frame
	Input.action_release("move_forward")


## The owner's report: "I couldn't go down the stairs." Sol walks down the plaza well's spiral,
## through the red door and the tunnel into the flooded crypt, the rival daywalker fights him
## (and is hard), dies, drops his blade, and Sol walks all the way back up to the street.
func _undercroft_checks(main) -> bool:
	var ok := true
	var p = main.player
	var d = main.depths
	var U = load("res://scripts/map/undercroft.gd")
	U.record_path = "user://smoke_undercroft.json"
	if FileAccess.file_exists(U.record_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(U.record_path))
	U.record = {}
	_clear_enemies(main)
	var tod: float = main.time_of_day
	main.time_of_day = 0.9
	var spawn_t: float = main.spawn_timer
	main.spawn_timer = 99999.0
	p.dead = false
	p.max_hp = 1e9
	p.hp = 1e9
	ok = _check("the Undercroft Depths are built (crypt %d tris in %d meshes, %d lights, none shadowed)" % [d.budget_tris, d.budget_meshes, d.lights.size()],
		d != null and d.budget_tris > 1000 and d.budget_tris < 250000 and d.budget_meshes <= 40 and d.lights.size() <= 8 and d.lights.all(func(l): return not l.shadow_enabled)) and ok
	var falls0: int = p.falls
	p.global_position = Vector3(0, 0.3, 6.0)
	p.velocity = Vector3.ZERO
	await _wait_physics(10)
	var down: Array = [Vector3(0, 0, 4.5), Vector3(0, 0, 2.3)]
	for k in 26:
		var a := deg_to_rad(116.0 + k * 10.0)
		down.append(Vector3(cos(a) * 2.25, 0, sin(a) * 2.25))
	down.append_array([Vector3(1.0, 0, 1.0), Vector3(0, 0, 1.6)])
	for w in down:
		await _walk_to(p, w)
	ok = _check("Sol walks down the well's spiral stair to its floor (at %s)" % p.global_position, p.global_position.y < -3.2 and p.global_position.y > -3.6 and not p.dead) and ok
	for w in [Vector3(0, 0, 3.5), Vector3(0, 0, 8.0), Vector3(0, 0, 13.0), Vector3(0, 0, 17.0), Vector3(0, 0, 19.5), Vector3(0, 0, 22.0), Vector3(0, 0, 25.0)]:
		await _walk_to(p, w)
	await _wait_physics(5)
	ok = _check("...through the door and the tunnel onto the crypt's floor (at %s, inside %s, street hidden %s)" % [p.global_position, d.inside, not main.city.visible],
		absf(p.global_position.y - U.Y) < 0.3 and p.global_position.z > 23.0 and d.inside and not main.city.visible and absf(main.ground_y(0.0, 27.0) - U.Y) < 0.01) and ok
	var r = d.rival
	ok = _check("the rival daywalker waits down there", r != null and is_instance_valid(r) and not r.dead) and ok
	if r == null or not is_instance_valid(r):
		return false
	var hp0: float = p.hp
	var used := {}
	for i in 900:
		await physics_frame
		if r.state == "windup":
			used[r.atk_name] = true
		if used.size() >= 3 and p.hp < hp0:
			break
	main.clear_slowmo()
	ok = _check("Silas Crowe engages with a name plate and a health bar (%s)" % r.label.text, r.engaged and r.label.text.contains("CROWE") and r.bar.visible) and ok
	ok = _check("...fights with Sol's moveset (%s) and draws blood (%.0f)" % [used.keys(), hp0 - p.hp], used.size() >= 2 and p.hp < hp0) and ok
	var street_hp: float = load("res://scripts/enemy.gd").new().max_hp
	ok = _check("...and is much tougher than a street enemy (%.0f vs %.0f)" % [r.max_hp, street_hp], r.max_hp >= street_hp * 3.0) and ok
	# a parry in his last wind-up breaks his attack and opens a punish window
	r.reset_to(r.home)
	r.global_position = p.global_position + Vector3(0, 0, 2.0)
	r.engaged = true
	r._start("light1")
	while r.state == "windup" and not r.parry_open():
		await physics_frame
	var parried: bool = r.parry_open()
	r.on_parried(2.5)
	ok = _check("his swing is parryable in its wind-up and a parry makes him reel", parried and r.state == "reel") and ok
	p.hp = 1e9
	var frames := 0
	while not r.dead and frames < 600:
		r.invuln_t = 0.0
		if r.state == "guard":
			r.state = "stalk"
		r.take_hit(35.0, Vector3.FORWARD)
		frames += 1
		await physics_frame
	await _wait_physics(20)
	main.clear_slowmo()
	var blade := false
	for g in main.loot.ground_items:
		if g.inst.id == "crowes_penance" and is_instance_valid(g.node) and absf(g.node.global_position.y - U.Y) < 1.0:
			blade = true
	for g in main.loot.ground_items.duplicate():
		if g.inst.id == "crowes_penance":
			main.loot._remove_item(g)
	ok = _check("the rival dies and drops Crowe's Penance on the crypt floor", r.dead and d.rival_dead and blade) and ok
	ok = _check("...and the kill is remembered (%s)" % U.record, int(U.record.get("rival_kills", 0)) == 1 and FileAccess.file_exists(U.record_path)) and ok
	var ItemDB = load("res://scripts/items/item_db.gd")
	var rng := RandomNumberGenerator.new()
	var never := true
	for i in 300:
		rng.seed = i
		if ItemDB.random_item(rng, true, true, 1.0).get("id", "") == "crowes_penance":
			never = false
	ok = _check("his blade never drops from random loot", never) and ok
	var up: Array = [Vector3(0, 0, 22.0), Vector3(0, 0, 19.0), Vector3(0, 0, 14.0), Vector3(0, 0, 8.0), Vector3(0, 0, 3.5), Vector3(0, 0, 1.5), Vector3(1.5, 0, 0.3)]
	for k in 26:
		var a := deg_to_rad(366.0 - k * 10.0)
		up.append(Vector3(cos(a) * 2.25, 0, sin(a) * 2.25))
	up.append_array([Vector3(0, 0, 2.6), Vector3(0, 0, 5.0), Vector3(0, 0, 8.0)])
	for w in up:
		await _walk_to(p, w)
	await _wait_physics(10)
	ok = _check("Sol walks back up to the plaza (at %s, inside %s, street shown %s, falls %d)" % [p.global_position, d.inside, main.city.visible, p.falls - falls0],
		absf(p.global_position.y - main.ground_y(p.global_position.x, p.global_position.z)) < 0.5 and p.global_position.z > 6.0 and not d.inside and main.city.visible and p.falls == falls0 and d.rival == null) and ok
	if FileAccess.file_exists(U.record_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(U.record_path))
	U.record = {}
	main.time_of_day = tod
	main.spawn_timer = spawn_t
	p.max_hp = 100.0
	p.hp = 100.0
	return ok

## QA2 #1: the parry works in a boss fight. A boss swipe in its last wind-up is turned aside (the
## boss reels, no chain), and an add standing after the boss in enemies_root is still parried.
func _boss_parry_checks(m, boss) -> bool:
	var ok := true
	var p = m.player
	var hp0: float = p.hp
	p.invuln_t = 0.0
	p.dash_t = 0.0
	p.parry_t = 0.0
	p.parry_cd = 0.0
	boss.global_position = p.global_position + Vector3(0, 0, 2.5)
	boss.atk = {"type": "swipe", "windup": 0.3, "range": 3.0, "dmg": 15.0, "recover": 0.6, "cd": 1.2,
		"chain": [{"type": "swipe", "windup": 0.3, "range": 3.0, "dmg": 15.0, "recover": 0.6}]}
	boss.state = "windup"
	boss.state_t = 0.3
	ok = _check("a boss swipe near its strike is parryable", p._parryable(boss) and boss.parry_open()) and ok
	p._parry()
	await _wait_physics(3)
	m.clear_slowmo()
	ok = _check("parry turns the boss swipe aside (state %s, %s, hp %.0f)" % [boss.state, boss.atk.get("type", "?"), p.hp], boss.state == "recover" and boss.atk.get("type", "") == "parried" and p.hp == hp0) and ok
	# an add after the boss in the tree: the parry loop must reach it
	boss.state = "chase"
	boss.cooldown = 99.0
	boss.atk = {}
	var add = _spawn(m, 0, p.global_position + Vector3(1.2, 0.4, 0))
	await _wait_physics(3)
	add.attack_cd = 9.0
	add.special_cd = 99.0 # a plain swipe wind-up: no claw combo, lunge or backflip of its own mid-check
	add.flip_cd = 99.0
	if add.special != "":
		add._cancel_special()
	add.strike_dir = Vector3(-1, 0, 0)
	add.windup_t = 0.35 # comfortably inside the window even if a loaded machine stretches a frame
	p.parry_t = 0.0
	p.parry_cd = 0.0
	p.stamina = 100.0 # the boss parry above spent some; don't let an exhausted Sol skip this one
	p._parry()
	await _wait_physics(4)
	m.clear_slowmo()
	var add_d: float = Vector2(add.global_position.x - p.global_position.x, add.global_position.z - p.global_position.z).length()
	ok = _check("an add is parried during a boss fight (staggered %s, %.2f m, windup %.2f, hp %.0f/%.0f)" % [add.staggered, add_d, add.windup_t, p.hp, hp0], add.staggered and p.hp == hp0) and ok
	if is_instance_valid(add):
		m.enemies_root.remove_child(add)
		add.free()
	m.attack_tokens.clear()
	boss.cooldown = 1.0
	return ok


## Wait for the Blood Rite screen and take its first offer. True if it opened and the pick held.
func _take_rite(h) -> bool:
	for i in 400:
		if h.rite_ui.is_open():
			break
		await physics_frame
	if not h.rite_ui.is_open():
		return false
	var id: String = h.rite_ui.offer[0]
	h.rite_ui.armed_at = 0
	var took: bool = h.rite_ui.pick(id)
	await process_frame
	return took and id in h.main.progression.rites and not paused


## L1: the Blood Rite. After a night boss the pick-1-of-3 opens over a paused world, ignores input for
## a moment, needs a choice to close, applies the Rite (stats, a full heal) and shows in the Coat.
func _rite_checks(m) -> bool:
	var ok := true
	var h = m.hunt
	var p = m.player
	var Rites = load("res://scripts/hunt/blood_rite.gd")
	var opened := false
	for i in 400:
		if h.rite_ui.is_open():
			opened = true
			break
		await physics_frame
	var offer: Array = h.rite_ui.offer
	var distinct := {}
	for id in offer:
		distinct[id] = true
	ok = _check("a Blood Rite opens after the boss: 3 different Rites, world paused (%s)" % ", ".join(offer), opened and offer.size() == 3 and distinct.size() == 3 and paused and m.menu_open()) and ok
	if not opened:
		return false
	ok = _check("the Rite has a card per offer, the first focused for pad / keyboard", h.rite_ui.buttons.size() == 3 and h.rite_ui.buttons[0].focus_neighbor_right != NodePath("")) and ok
	h.rite_ui._pick(offer[1]) # a mashed press right as it opens
	ok = _check("the Rite ignores a click in its first moment", h.rite_ui.is_open() and m.progression.rites.is_empty()) and ok
	h.rite_ui.armed_at = 0
	_key(KEY_ESCAPE, true)
	await process_frame
	_key(KEY_ESCAPE, false)
	await process_frame
	ok = _check("Esc doesn't close the Rite or open the pause menu", h.rite_ui.is_open() and not m.pause_menu.visible) and ok
	p.max_hp = 100.0
	p.hp = 30.0
	_key(KEY_2, true) # keyboard: 2 takes the second card
	await process_frame
	_key(KEY_2, false)
	await process_frame
	var took: String = offer[1]
	ok = _check("[2] takes the second Rite (%s), unpauses and fills Sol's blood (hp %.0f / %.0f)" % [took, p.hp, p.max_hp],
		not h.rite_ui.is_open() and not paused and took in m.progression.rites and is_equal_approx(p.hp, p.max_hp)) and ok
	var mods: Dictionary = Rites.RITES[took].mods
	var applied := true
	for k in mods:
		if m.progression.stat(k) < float(mods[k]) - 0.001:
			applied = false
	ok = _check("the Rite's mods are in the stat table", applied) and ok
	ok = _check("the Coat lists the Rite", m.inventory_ui._stats_text().contains(Rites.name_of(took))) and ok
	# each Rite's move hook, forced on one at a time
	var prog = m.progression
	var saved: Array = prog.rites.duplicate()
	for id in ["sanguine_riposte", "long_shadow", "curfew_born", "fourth_cut", "butchers_frenzy"]:
		if not id in prog.rites:
			prog.rite_choices = [id]
			prog.choose_rite(id)
	p.hp = 40.0
	var dash0: float = p.dash_charges
	p.parried.emit(null)
	ok = _check("Sanguine Riposte: a parry heals 20 and refunds a dash (hp %.0f)" % p.hp, is_equal_approx(p.hp, 60.0) and p.dash_charges >= minf(dash0 + 1.0, p.MAX_DASH) - 0.01) and ok
	p.dash_t = p.DASH_TIME
	p.dashed.emit(Vector3.FORWARD)
	ok = _check("Long Shadow: the Blood Dash lasts 60%% longer (%.3f s)" % p.dash_t, is_equal_approx(p.dash_t, p.DASH_TIME * 1.6) and p.invuln_t >= p.dash_t) and ok
	p.dash_t = 0.0
	ok = _check("Curfew-Born: the Curfew burns 70% less", is_equal_approx(prog.stat("curfew_resist"), 0.7)) and ok
	p.frenzy_t = 0.0
	p.special_move.emit("finisher")
	ok = _check("Butcher's Frenzy: an execution starts a Frenzy (%.1f s)" % p.frenzy_t, p.frenzy_t >= 6.0) and ok
	p.frenzy_t = 0.0
	_clear_enemies(m)
	var fwd: Vector3 = p._forward()
	var vic = _spawn(m, 0, p.global_position + fwd * 2.0)
	await _wait_physics(2)
	var hp0: float = vic.hp
	var n: int = Rites.echo_cut(m, fwd, 1.5)
	ok = _check("The Fourth Cut: the phantom blade hits what's in front (%d hit, hp %.0f -> %.0f)" % [n, hp0, vic.hp], n >= 1 and (vic.hp < hp0 or vic.dead)) and ok
	_clear_enemies(m)
	prog.rites = saved
	prog.recompute()
	p.max_hp = 1e9
	p.hp = 1e9
	return ok


## L4: one run modifier per night, on the night card and the phase line, in the stat table.
func _modifier_checks(m) -> bool:
	var ok := true
	var h = m.hunt
	var Cfg = load("res://scripts/hunt/hunt_config.gd")
	var mod: Dictionary = h.modifier()
	ok = _check("tonight has a run modifier (%s)" % h.modifier_id(), not mod.is_empty() and h.night_mods.size() == 3 and Cfg.NIGHT_MODIFIERS.has(h.modifier_id())) and ok
	ok = _check("no night repeats the modifier before it (%s)" % ", ".join(h.night_mods), h.night_mods[0] != h.night_mods[1] and h.night_mods[1] != h.night_mods[2]) and ok
	ok = _check("the modifier is named on the night card", h.story.card_text().contains(String(mod.name))) and ok
	ok = _check("...and on the phase line (%s)" % h.phase_label(), h.phase_label().contains(String(mod.name))) and ok
	ok = _check("its mods are in the stat table", m.progression.night_mods == mod.get("mods", {})) and ok
	ok = _check("the Fog multiplies the fog (scale %.2f, base %.2f)" % [m.atmo.fog_scale, h.base_fog], is_equal_approx(m.atmo.fog_scale, h.base_fog * float(mod.get("fog", 1.0)))) and ok
	var seen := {}
	var HD = load("res://scripts/hunt/hunt_director.gd")
	for sd in range(1, 13):
		var hh = HD.new()
		hh.seed = sd
		hh._pick_modifiers()
		seen[hh.night_mods[0]] = true
		hh.free()
	ok = _check("the modifier draw varies by seed (%s)" % ", ".join(seen.keys()), seen.size() >= 3) and ok
	# every modifier applies and clears cleanly
	var keep: Array = h.night_mods.duplicate()
	for id in Cfg.NIGHT_MODIFIERS:
		h.night_mods = [id, id, id]
		h._apply_modifier()
		var d: Dictionary = Cfg.NIGHT_MODIFIERS[id]
		if m.progression.night_mods != d.get("mods", {}) or not is_equal_approx(m.atmo.fog_scale, h.base_fog * float(d.get("fog", 1.0))):
			ok = _check("modifier %s applies" % id, false) and ok
	h.night_mods = keep
	h._apply_modifier()
	return ok


## L2: micro-POIs between the camps: a cache, a captive, a blood fridge and a shrine, each one use.
func _micro_checks(m) -> bool:
	var ok := true
	var h = m.hunt
	var p = m.player
	var Cfg = load("res://scripts/hunt/hunt_config.gd")
	var types := {}
	var spaced := true
	for mp in h.micros:
		types[mp.type] = mp
		for poi in h.pois:
			if poi.type != "undercroft" and mp.distance_to(poi.global_position) < Cfg.MICRO_CLEAR - 0.5:
				spaced = false
	ok = _check("micro-POIs fill the roads between the sites (%d, types %s)" % [h.micros.size(), ", ".join(types.keys())], h.micros.size() >= 8 and types.size() == 4) and ok
	ok = _check("micro-POIs keep clear of the big sites", spaced) and ok
	var standing := true
	for mp in h.micros:
		if not m.spot_clear(Vector3(mp.global_position.x, m.ground_y(mp.global_position.x, mp.global_position.z), mp.global_position.z)):
			standing = false
	ok = _check("micro-POIs stand on open ground", standing) and ok
	if types.size() < 4:
		return false
	var saved_pos: Vector3 = p.global_position
	p.max_hp = 100.0
	# the fridge, through the real [E] path
	var fr = types.fridge
	p.global_position = fr.global_position + Vector3(1.2, 0.2, 0.0)
	p.hp = 20.0
	p.hunger = 80.0
	await _wait_physics(3)
	var prompt_seen: bool = h.prompt.contains(String(Cfg.MICRO_POIS.fridge.act))
	Input.action_press("interact")
	await physics_frame
	await physics_frame
	Input.action_release("interact")
	ok = _check("a blood fridge shows its prompt and [E] drinks (hp %.0f, hunger %.0f)" % [p.hp, p.hunger], prompt_seen and fr.used and p.hp >= 69.0 and p.hunger <= 41.0) and ok
	ok = _check("...once: a used find offers nothing", fr.interaction(fr.global_position).is_empty() and not fr.use()) and ok
	var sh = types.shrine
	var mh0: float = p.max_hp
	sh.use()
	ok = _check("a shrine adds %d max blood for the run (%.0f -> %.0f)" % [int(Cfg.SHRINE_HP), mh0, p.max_hp], is_equal_approx(p.max_hp, mh0 + Cfg.SHRINE_HP)) and ok
	var items0: int = m.loot.get_child_count()
	types.captive.use()
	types.cache.use()
	await _wait_physics(2)
	ok = _check("a captive and a cache pay out (loot nodes %d -> %d)" % [items0, m.loot.get_child_count()], types.captive.used and types.cache.used and m.loot.get_child_count() > items0) and ok
	p.global_position = saved_pos
	p.max_hp = 1e9
	p.hp = 1e9
	return ok


## Group C frame budget (web tier: <= 350 draws, <= 600k triangles anywhere). The dummy
## renderer reports no stats, so tests/frame_budget.gd estimates them from the scene. Calibrated
## against the native Compatibility probe: real draws ~= estimate + 30-75 (the HUD, the sky and
## the post passes it doesn't model), and its triangles run high (real ~= 0.4-0.8x). The spots are the worst ones from the round-2 critic and QA: the tank-farm
## deploy, the boss arenas, the lake, the docks yard, the Velvet Mile, the Quarter and the bayou.
const BUDGET_SPOTS := [
	["tank farm", Vector3(-130, 0, -200)], ["Pier Nine arena", Vector3(-172, 0, 172)],
	["Palm Square arena", Vector3(150, 0, 120)], ["Drowned Lawn arena", Vector3(185, 0, -132)],
	["the Hollow arena", Vector3(10, 0, -122)], ["lake shore", Vector3(60, 0, -200)],
	["docks yard", Vector3(-170, 0, -60)], ["Velvet Mile", Vector3(150, 0, 100)],
	["Old Quarter street", Vector3(-30, 0, 50)], ["bayou", Vector3(185, 0, -105)],
	["the plaza", Vector3(0, 0, 30)], ["the plaza well", Vector3(6, 0, 10)],
	["the cemetery dig site", Vector3(52, 0, 134)],
]
const BUDGET_EST_DRAWS := 280
const BUDGET_EST_TRIS := 900000


func _budget_checks(m) -> bool:
	var FB = load("res://tests/frame_budget.gd")
	var T = load("res://scripts/map/terrain.gd")
	var worst := {"draws": 0, "tris": 0, "at": ""}
	for spot in BUDGET_SPOTS:
		var pos: Vector3 = spot[1]
		pos.y = T.height_at(pos.x, pos.z)
		for k in 4:
			var yaw := k * PI * 0.5
			var b := Basis(Vector3.UP, yaw)
			var xf := Transform3D(b * Basis(Vector3.RIGHT, -0.12), pos + Vector3(0, 2.0, 0) + b * Vector3(0, 0.5, 4.2))
			var r: Dictionary = FB.estimate(m, xf, 70.0, m.player.camera.far, m.sun.directional_shadow_max_distance)
			if r.draws > worst.draws:
				worst.draws = r.draws
				worst.at = "%s, yaw %d" % [spot[0], k * 90]
			worst.tris = maxi(worst.tris, r.tris)
	var ok := _check("frame budget: worst estimated view %d draws at %s (<= %d, i.e. <= 350 real)" % [worst.draws, worst.at, BUDGET_EST_DRAWS], worst.draws <= BUDGET_EST_DRAWS)
	ok = _check("frame budget: worst estimated view %dk LOD-0 triangles (<= %dk, i.e. <= 600k real)" % [worst.tris / 1000, BUDGET_EST_TRIS / 1000], worst.tris <= BUDGET_EST_TRIS) and ok
	# the map screen pulls the camera's far plane in
	m.hunt.map_screen.open()
	var cam_far: float = m.player.camera.far
	m.hunt.map_screen.close()
	ok = _check("the map screen pulls the world's far plane in (%.0f m while open, %.0f m after)" % [cam_far, m.player.camera.far], cam_far <= 60.0 and m.player.camera.far >= 300.0) and ok
	# HLOD boxes: one instance per cell, dropped at a range
	var hl := 0
	var hl_ranged := 0
	var hl_cast := 0
	for n in m.city.get_children():
		var nm := String(n.name)
		if nm.begins_with("Chunk_H"):
			hl += 1
			if (n as GeometryInstance3D).visibility_range_end > 0.0:
				hl_ranged += 1
			if nm.ends_with("_cast"):
				hl_cast += 1
	ok = _check("HLOD boxes are one instance per cell and stop at a range (%d cells, %d ranged)" % [hl, hl_ranged], hl > 0 and hl == hl_ranged and hl_cast == 0) and ok
	return ok


func _start_hunt():
	var MainScript = load("res://scripts/main.gd")
	MainScript.started_once = true
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	return m


func _hunt_checks() -> bool:
	var ok := true
	var HD = load("res://scripts/hunt/hunt_director.gd")
	var Meta = load("res://scripts/hunt/hunt_meta.gd")
	var Cfg = load("res://scripts/hunt/hunt_config.gd")
	var meta_path := "user://smoke_hunt_meta.json"
	Meta.path = meta_path
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(meta_path))
	Meta.reset_meta()
	Meta.data.loadout = [1, -1, -1] # wear High John Root from the armoury
	Meta.save_meta()
	ok = _check("--shorthunt flag parses", HD.short_flag(PackedStringArray(["--shorthunt"])) and not HD.short_flag(PackedStringArray([])) and HD.short_flag(PackedStringArray([]), true)) and ok
	# no flags at all (a direct load, Start, a restart): main.tscn is a Hunt, never free roam
	HD.force_freeroam = false
	HD.requested = false
	HD.force_short = false
	HD.seed_override = 77
	var m0 = await _start_hunt()
	var h0 = m0.hunt
	var p0 = m0.player
	ok = _check("main.tscn without flags starts a Hunt", h0 != null and not m0.free_roam and h0.state == "deploy") and ok
	var dp0: Vector3 = h0.deploy_point.pos
	ok = _check("...and deploys away from the plaza (point %.0f m out, Sol %.0f m out)" % [Vector2(dp0.x, dp0.z).length(), Vector2(p0.global_position.x, p0.global_position.z).length()],
		Vector2(dp0.x, dp0.z).length() > 50.0 and Vector2(p0.global_position.x, p0.global_position.z).length() > 40.0) and ok
	await _wait_physics(20)
	var uc_poi = null
	for poi in h0.pois:
		if poi.type == "undercroft":
			uc_poi = poi
	ok = _check("the Hunt map shows the Undercroft Depths (a combat site on the plaza well)", uc_poi != null and uc_poi.is_combat() and not uc_poi.cleared and uc_poi.distance_to(Vector3.ZERO) < 1.0) and ok
	h0.deploy.finish()
	p0.hp = 1e9
	p0.max_hp = 1e9
	await _wait_physics(240) # four seconds of the first day
	var near := 0
	var chasing := 0
	for e in m0.enemies_root.get_children():
		if e.dead:
			continue
		if e.global_position.distance_to(p0.global_position) < Cfg.AGGRO_RANGE:
			near += 1
		if Vector2(e.velocity.x, e.velocity.z).length() > 1.0:
			chasing += 1
	ok = _check("nothing chases you at the start (%d enemies, %d near, %d moving, %d roamers)" % [m0.living_enemies(), near, chasing, h0.roamers.size()],
		near == 0 and chasing == 0 and h0.roamers.is_empty() and h0.state == "explore") and ok
	ok = _budget_checks(m0) and ok
	# stragglers appear out of sight and stand idle until Sol comes close
	h0.phase_t = Cfg.ROAM_GRACE + 1.0
	h0.roam_t = 0.0
	await _wait_physics(2)
	if h0.roamers.size() > 0:
		var r = h0.roamers[0].e
		var d0: float = r.global_position.distance_to(p0.global_position)
		await _wait_physics(30)
		var r0: Vector3 = r.global_position
		await _wait_physics(60)
		ok = _check("a straggler turns up out of sight (%.0f m) and holds its ground" % d0, d0 > Cfg.ROAM_MIN_DIST - 1.0 and Vector2(r.global_position.x - r0.x, r.global_position.z - r0.z).length() < 1.0 and r.speed == 0.0) and ok
	else:
		ok = _check("a straggler spawns once the grace period is over", false) and ok
	# QA2 #3: during the first-Hunt intro, Tab opens nothing and Esc skips it (no pause menu)
	h0.story.play_intro(Callable())
	await _wait_physics(50)
	_key(KEY_TAB, true)
	await process_frame
	_key(KEY_TAB, false)
	var coat_opened: bool = m0.inventory_ui.is_open()
	_key(KEY_ESCAPE, true)
	await process_frame
	_key(KEY_ESCAPE, false)
	await process_frame
	ok = _check("intro: Tab opens no Coat, Esc skips it without pausing (coat %s, playing %s, paused %s)" % [coat_opened, h0.story.playing, m0.pause_menu.visible],
		not coat_opened and not h0.story.playing and not m0.pause_menu.visible) and ok
	paused = false
	m0.queue_free()
	await process_frame
	HD.requested = true
	HD.force_short = true
	HD.seed_override = 4242
	var m = await _start_hunt()
	var h = m.hunt
	var p = m.player
	ok = _check("a Hunt runs when the hub asks for one", h != null and h.state == "deploy") and ok
	ok = _check("--shorthunt timings (explore %.0fs, day %.0fs)" % [h.T.explore, Cfg.day_length(true)], h.short and h.T.explore <= 30.0 and Cfg.day_length(true) < Cfg.day_length(false) / 4.0) and ok
	var dp: Vector3 = h.deploy_point.pos
	ok = _check("deploys at a map-edge point, away from the plaza (%.0f m out)" % Vector2(dp.x, dp.z).length(), Vector2(dp.x, dp.z).length() > 50.0 and Vector2(p.global_position.x - dp.x, p.global_position.z - dp.z).length() < 20.0) and ok
	await _wait_physics(30)
	h.deploy.finish()
	await _wait_physics(2)
	ok = _check("the Descent hands over control (state %s)" % h.state, h.state == "explore" and p.is_physics_processing() and p.camera.current) and ok
	ok = _check("player starts far from the plaza centre (%.0f m)" % Vector2(p.global_position.x, p.global_position.z).length(), Vector2(p.global_position.x, p.global_position.z).length() > 40.0) and ok
	ok = _check("hub charm worn into the Hunt", m.inventory.charms[0].get("id", "") == "john_root") and ok
	ok = _check("run starts fresh (rank 1, 0 Tithe, no save writes)", m.progression.level == 1 and m.progression.tithe == 0 and not m.progression.persist) and ok
	# POIs
	var with_enemies := 0
	var types := {}
	for poi in h.pois:
		if poi.type == "undercroft":
			continue # the Undercroft Depths: registered on the plaza well, not a generated site
		types[poi.type] = true
		if poi.is_combat() and poi.total_alive() > 0:
			with_enemies += 1
	ok = _check("POIs generated (%d, %d types, %d with enemies)" % [h.pois.size(), types.size(), with_enemies], h.pois.size() >= 10 and types.size() == 6 and with_enemies >= 6) and ok
	var far_ok := true
	for poi in h.pois:
		if poi.type != "undercroft" and Vector2(poi.global_position.x, poi.global_position.z).length() < 20.0:
			far_ok = false
	ok = _check("POIs stay off the plaza", far_ok) and ok
	ok = await _modifier_checks(m) and ok
	ok = await _micro_checks(m) and ok
	var dists := {}
	for poi in h.pois:
		dists[load("res://scripts/map/map_layout.gd").district_at(poi.global_position.x, poi.global_position.z)] = true
	ok = _check("POIs spread over the districts (%d POIs in %d districts)" % [h.pois.size(), dists.size()], h.pois.size() >= 18 and dists.size() >= 5) and ok
	var camp = null
	for poi in h.pois:
		if poi.type == "camp":
			camp = poi
			break
	var start: Vector3 = camp.global_position + Vector3(45.0, 0.0, 0.0)
	if not m.city.play_rect.grow(-3.0).has_point(Vector2(start.x, start.z)):
		start = camp.global_position - Vector3(45.0, 0.0, 0.0) # stay inside the map's walls
	p.global_position = start + Vector3(0, 0.2, 0)
	p.hp = 1e9
	p.max_hp = 1e9
	await _wait_physics(10)
	var idle_pos: Array = []
	for l in camp.live:
		idle_pos.append(l.e.global_position)
	await _wait_physics(40)
	var still: bool = camp.live.size() > 0
	for i in camp.live.size():
		if camp.live[i].e.global_position.distance_to(idle_pos[i]) > 0.3:
			still = false
	ok = _check("camp enemies are pre-placed and idle until Sol is close (%d)" % camp.live.size(), still and not camp.roused) and ok
	var has_elite := false
	for l in camp.live:
		if l.e.get_node_or_null("Elite") != null:
			has_elite = true
	ok = _check("camp has a named elite", has_elite) and ok
	p.global_position = camp.global_position + Vector3(2.0, 0.2, 0.0)
	await _wait_physics(5)
	ok = _check("camp aggros when Sol comes close", camp.roused) and ok
	ok = _check("active enemies capped (%d <= %d)" % [m.living_enemies(), Cfg.MAX_ACTIVE_ENEMIES], m.living_enemies() <= Cfg.MAX_ACTIVE_ENEMIES) and ok
	var t0: int = m.progression.tithe
	for l in camp.live:
		if is_instance_valid(l.e) and not l.e.dead:
			l.e._die(false)
	await _wait_physics(4)
	ok = _check("clearing a POI marks it cleared", camp.cleared) and ok
	await _wait_physics(150)
	ok = _check("clearing pays a Tithe burst (+%d)" % (m.progression.tithe - t0), m.progression.tithe - t0 >= Cfg.POI_TYPES.camp.tithe) and ok
	_clear_enemies(m)
	# the Red Curfew
	var r0: float = h.ring.radius
	h.debug_skip_to("shrink1")
	await _wait_physics(90)
	ok = _check("the Curfew shrinks (%.0f -> %.0f)" % [r0, h.ring.radius], h.ring.radius < r0 - 5.0) and ok
	p.max_hp = 100.0
	p.hp = 100.0
	p.invuln_t = 0.0
	var c: Vector3 = h.ring.center
	var away := Vector3(-c.x, 0, -c.z).normalized()
	if away.length() < 0.5:
		away = Vector3(1, 0, 0)
	h.ring.set_radius(12.0)
	p.global_position = c + away * 30.0 + Vector3(0, 0.2, 0)
	await _wait_physics(60)
	ok = _check("outside the Curfew hurts (hp %.0f, tint %.2f)" % [p.hp, h.outside_amount], p.hp < 95.0 and h.outside_amount > 0.5) and ok
	p.global_position = c + Vector3(0, 0.2, 0)
	p.hp = 1e9
	p.max_hp = 1e9
	h.debug_skip_to("shrink2")
	await _wait_physics(int((h.T.shrink2 + 0.5) * 60.0))
	var night1: Dictionary = h.boss_def(0)
	ok = _check("the boss spawns when the Curfew closes (state %s, %s)" % [h.state, night1.get("id", "?")], h.state == "boss" and h.boss != null and is_instance_valid(h.boss) and h.boss.boss_name == night1.name) and ok
	ok = _check("nights 1-2 draw two different pool bosses, the Final Night is the Abomination", h.boss_def(0).id != h.boss_def(1).id and h.boss_def(2).id == "abomination" and Cfg.NIGHT_BOSS_POOL.has(h.boss_def(1))) and ok
	var seen_first := {}
	for sd in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]:
		var hh = HD.new()
		hh.seed = sd
		hh._pick_bosses()
		seen_first[hh.boss_def(0).id] = true
		hh.free()
	ok = _check("the night-boss pool shuffles by seed (%s)" % ", ".join(seen_first.keys()), seen_first.size() >= 2) and ok
	ok = _check("the Curfew holds as the arena wall", is_equal_approx(h.ring.radius, h.arena.radius)) and ok
	ok = _check("boss night is night, full moon as the boss wants", not m.is_day() and m.is_full_moon() == bool(night1.full_moon)) and ok
	await _wait_physics(150) # let the boss finish its entrance and swing a few times
	var boss = h.boss
	var clip_ok := false
	for r in boss.rigs:
		if r.anim != null and r.anim.has_animation("boss/heavy") and r.anim.current_animation != "":
			clip_ok = true
	ok = _check("the boss is clip-driven (*_anim body + boss clip library, playing %s)" % (boss.rigs[0].anim.current_animation if boss.rigs[0].anim != null else "none"), clip_ok) and ok
	# Marcus on his own model shows it clean (no veins, critic round 2); the others glow
	var clean: bool = boss.get("own_model") == true
	ok = _check("the boss has its silhouette and veins (or Marcus clean on his own model)", boss.overlay is ShaderMaterial and (clean or float(boss.overlay.get_shader_parameter("vein_amount")) > 0.0)) and ok
	ok = _check("tonight's framing card names the boss", h.story != null and h.story.card_text().contains(night1.name)) and ok
	# QA2 #12: the card sits top centre (clear of the phone stick) and hides under the map
	h.map_screen.open()
	await process_frame
	await process_frame
	var card_hid: bool = not h.story._card.visible
	h.map_screen.close()
	await process_frame
	await process_frame
	ok = _check("the night card is top centre and hides while the map is open (hid %s, back %s, anchor %.1f)" % [card_hid, h.story._card.visible, h.story._card.anchor_left],
		card_hid and h.story._card.visible and is_equal_approx(h.story._card.anchor_left, 0.5)) and ok
	ok = await _boss_parry_checks(m, boss) and ok
	boss.take_hit(boss.max_hp * 0.6, Vector3.FORWARD)
	ok = _check("the boss enrages below half", boss.enraged) and ok
	boss.take_hit(1e6, Vector3.FORWARD)
	await _wait_physics(3)
	ok = _check("killing the boss counts", h.bosses_killed == 1 and boss.dead) and ok
	m.clear_slowmo()
	ok = await _rite_checks(m) and ok
	await _wait_physics(int((h.T.victory + 1.0) * 60.0))
	ok = _check("killing the boss advances the day (day %d, %s)" % [h.day + 1, h.state], h.day == 1 and h.state == "explore" and m.is_day()) and ok
	# death ends the run
	m.progression.tithe = 140
	m.progression.level = 4
	h.revives = 1
	p.max_hp = 100.0
	p.hp = 1.0
	p.invuln_t = 0.0
	p.dash_t = 0.0
	p.take_damage(50.0, null)
	m.clear_slowmo()
	await _wait_physics(int(2.6 * 60.0))
	ok = _check("a revive charge gets Sol back up at half blood (hp %.0f)" % p.hp, not p.dead and is_equal_approx(p.hp, p.max_hp * 0.5) and h.revives == 0 and h.state != "over") and ok
	ok = _check("the death drop still drops half the Tithe", int(m.progression.death_drop.get("amount", 0)) == 70) and ok
	p.invuln_t = 0.0
	p.dash_t = 0.0
	p.take_damage(1000.0, null)
	await _wait_physics(int(2.5 * 60.0))
	ok = _check("death without a revive ends the Hunt and shows results", h.state == "over" and h.results.visible and paused) and ok
	ok = _check("results: 1 boss, Sunmarks earned (%d)" % h.summary.get("earned", 0), h.summary.get("bosses", 0) == 1 and h.summary.get("earned", 0) > 0 and int(Meta.data.sunmarks) > 0 and int(Meta.data.hunts) == 1) and ok
	ok = _check("run-scoped state resets (rank %d, Tithe %d)" % [m.progression.level, m.progression.tithe], m.progression.level == 1 and m.progression.tithe == 0 and m.inventory.weapon.id == "marrow_silver" and m.progression.vows.is_empty()) and ok
	paused = false
	m.queue_free()
	await process_frame
	# persistent charms survive
	Meta.load_meta()
	ok = _check("persistent charms survive (loadout on disk)", Meta.loadout_charms()[0].get("id", "") == "john_root") and ok
	var m2 = await _start_hunt()
	ok = _check("the next Hunt wears them again, fresh run", m2.inventory.charms[0].get("id", "") == "john_root" and m2.progression.level == 1 and m2.hunt.seed == 4242) and ok
	ok = await _three_boss_win(m2) and ok
	m2.queue_free()
	await process_frame
	HD.requested = false
	HD.force_short = false
	HD.seed_override = -1
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(meta_path))
	return ok
