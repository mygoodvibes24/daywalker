extends Node3D
## The Hunt: a short co-op-roguelite style run through Port Vesper.
##   hub (main menu: the Undercroft) -> deploy (the Descent) -> DAY 1: explore -> the Red
##   Curfew closes (stage 1) -> hold -> closes (stage 2) -> NIGHT 1 boss -> DAY 2 ... ->
##   NIGHT 2 boss -> the Final Night boss -> results -> back to the hub.
## Owns spawning (POIs + a light roaming trickle) and the clock during a Hunt; main.gd
## only forwards a few HUNT HOOK calls. Rank, Tithe, Vows and the Coat are run-scoped;
## charms worn from the hub and Sunmarks persist (hunt_meta.gd).

const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const Meta = preload("res://scripts/hunt/hunt_meta.gd")
const POIScript = preload("res://scripts/hunt/poi.gd")
const Spawner = preload("res://scripts/hunt/poi_spawner.gd")
const RingScript = preload("res://scripts/hunt/curfew_ring.gd")
const DeployScript = preload("res://scripts/hunt/deploy.gd")
const ItemDB = preload("res://scripts/items/item_db.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HFx = preload("res://scripts/hunt/hunt_fx.gd")
const HuntHud = preload("res://scripts/ui/hunt_hud.gd")
const MapScreen = preload("res://scripts/ui/map_screen.gd")
const ResultsScreen = preload("res://scripts/ui/results_screen.gd")
const MerchantUI = preload("res://scripts/ui/merchant_ui.gd")

## Set by the hub's "Begin the Hunt" (or --hunt / ?hunt) before main.tscn loads.
static var requested := false
## Tests force the short timings; otherwise --shorthunt / ?shorthunt.
static var force_short := false
static var seed_override := -1

var main
var short := false
var T: Dictionary # timings
var seed := 0
var rng := RandomNumberGenerator.new()
var state := "idle" # idle, deploy, explore, shrink1, hold, shrink2, boss, victory, final_dusk, over
var phase_t := 0.0
var day := 0 # 0 = Day 1 / Night 1, 1 = Day 2 / Night 2, 2 = the Final Night
var arenas: Array = [] # per day
var arena: Dictionary
var ring: Node3D
var ring_full := 120.0
var pois: Array = []
var poi_root: Node3D
var deploy_dressing := {}
var deploy: Node3D
var deploy_point: Dictionary
var boss: Node3D # tonight's boss
var engaged_boss: Node3D # a field boss that has noticed you
var bosses_killed := 0
var revives := Cfg.REVIVES_PER_DAY
var revive_t := -1.0
var end_t := -1.0
var outside_t := 0.0
var outside_amount := 0.0
var roam_t := 8.0
var roamers: Array = []
var summons: Array = []
var last_day := true
var run_time := 0.0
var won := false
var summary := {}
var prompt := ""
var hud: CanvasLayer
var map_screen: CanvasLayer
var results: CanvasLayer
var merchant: CanvasLayer
var phase_banner := ""
var _interaction := {}


static func wanted(main_) -> bool:
	var args := OS.get_cmdline_user_args()
	return requested or force_short or "--hunt" in args or "--shorthunt" in args or main_._url_flag("hunt") or main_._url_flag("shorthunt")


static func short_flag(args: PackedStringArray, url_short := false) -> bool:
	return "--shorthunt" in args or url_short


# ---------------------------------------------------------------- world (before the navmesh bake)
func build_world() -> void:
	process_physics_priority = -10 # POIs hold idle enemies before enemy physics runs
	short = force_short or short_flag(OS.get_cmdline_user_args(), main._url_flag("shorthunt"))
	T = Cfg.timings(short)
	seed = seed_override if seed_override >= 0 else randi()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed = int(a.substr(7))
	rng.seed = seed
	main.time_of_day = Cfg.CLOCK.explore[0]
	# tonight's arenas: two different ones from the pool, then the Undercroft Plaza
	var pool: Array = Cfg.ARENAS.duplicate()
	for k in range(pool.size() - 1, 0, -1):
		var s := rng.randi_range(0, k)
		var t = pool[k]
		pool[k] = pool[s]
		pool[s] = t
	arenas = [pool[0], pool[1], Cfg.FINAL_ARENA]
	poi_root = Node3D.new()
	poi_root.name = "HuntPOIs"
	add_child(poi_root)
	for e in Spawner.generate(seed, main.city):
		var poi = POIScript.new()
		poi.setup(self, e.type, e.seed, e.get("boss", {}))
		poi.name = "POI_%s_%d" % [e.type, pois.size()]
		poi.position = e.pos
		poi_root.add_child(poi)
		poi.cleared_now.connect(on_poi_cleared)
		pois.append(poi)
	deploy_dressing = DeployScript.build_points(self)
	ring = RingScript.new()
	ring.name = "RedCurfew"
	ring.main = main
	add_child(ring)
	_set_arena(0)


# ---------------------------------------------------------------- start
## main.start_game() -> here: wipe the run state, wear the hub loadout, deploy.
func start() -> void:
	var prog = main.progression
	prog.persist = false # a Hunt never writes the free-roam save
	prog.reset()
	main.inventory.charms = Meta.loadout_charms()
	main.inventory.equipment_changed.emit()
	main.inventory.changed.emit()
	main.player.hp = main.player.max_hp
	main.loot.respawn_caches()
	main.loot._refresh_death_marker()
	main.lair_pos = Vector3(0, -500, 0) # Keep Vigil moves to the chapels during a Hunt
	main.hud.clock_label.visible = false
	main.hud.info_label.visible = false
	main.kills = 0
	hud = HuntHud.new()
	hud.director = self
	hud.main = main
	add_child(hud)
	map_screen = MapScreen.new()
	map_screen.director = self
	map_screen.main = main
	add_child(map_screen)
	merchant = MerchantUI.new()
	merchant.director = self
	merchant.main = main
	add_child(merchant)
	results = ResultsScreen.new()
	results.director = self
	add_child(results)
	deploy_point = Cfg.DEPLOY_POINTS[rng.randi() % Cfg.DEPLOY_POINTS.size()]
	deploy = DeployScript.new()
	deploy.main = main
	add_child(deploy)
	deploy.finished.connect(_on_deployed)
	state = "deploy"
	deploy.play(deploy_point, deploy_dressing)


func _on_deployed() -> void:
	_enter("explore")


func _set_arena(d: int) -> void:
	arena = arenas[d]
	var c: Vector3 = arena.pos
	ring_full = 0.0
	for corner in [Vector2(-82, -82), Vector2(82, -82), Vector2(-82, 82), Vector2(82, 82)]:
		ring_full = maxf(ring_full, corner.distance_to(Vector2(c.x, c.z)) + 6.0)
	ring.set_center(c)
	ring.set_radius(ring_full)


func _enter(s: String) -> void:
	state = s
	phase_t = 0.0
	match s:
		"explore":
			if main.hud != null:
				main.hud.announce("DAY %d\nThe Curfew falls at dusk. Hunt fast." % (day + 1))
		"shrink1":
			ring.shrink_to(Cfg.RING_STAGE1, T.shrink1)
			main.hud.announce("THE RED CURFEW FALLS\nGet inside the blood-fog before it takes you")
		"hold":
			pass
		"shrink2":
			ring.shrink_to(arena.radius, T.shrink2)
			main.hud.announce("THE CURFEW CLOSES\nMake for %s" % arena.name)
		"boss":
			_spawn_boss()
		"final_dusk":
			main.hud.announce("THE FINAL NIGHT\nSeraphine's work waits at the Undercroft")


# ---------------------------------------------------------------- frame
func _physics_process(delta: float) -> void:
	if state == "idle" or state == "over":
		return
	var p = main.player
	run_time += delta
	phase_t += delta
	_tick_pois(delta)
	match state:
		"explore":
			_clock("explore", phase_t / T.explore)
			_roam(delta)
			if phase_t >= T.explore:
				_enter("shrink1")
		"shrink1":
			_clock("shrink1", phase_t / T.shrink1)
			_roam(delta)
			if phase_t >= T.shrink1:
				_enter("hold")
		"hold":
			_clock("hold", phase_t / T.hold)
			_roam(delta)
			if phase_t >= T.hold:
				_enter("shrink2")
		"shrink2":
			_clock("shrink2", phase_t / T.shrink2)
			if phase_t >= T.shrink2:
				_enter("boss")
		"boss":
			main.time_of_day = Cfg.CLOCK.boss[0]
		"victory":
			if phase_t >= T.victory:
				_next_day()
		"final_dusk":
			main.time_of_day = Cfg.CLOCK.boss[0]
			if phase_t >= T.final_dusk:
				_final_night()
	_light_watch()
	if state != "deploy":
		_curfew_damage(delta, p)
		_interactions(p)
	if revive_t >= 0.0:
		revive_t -= delta
		if revive_t < 0.0:
			_revive()
	if end_t >= 0.0:
		end_t -= delta
		if end_t < 0.0:
			_end_run(false)
	if engaged_boss != null and (not is_instance_valid(engaged_boss) or engaged_boss.dead):
		engaged_boss = null


func _clock(phase: String, k: float) -> void:
	var c: Array = Cfg.CLOCK[phase]
	main.time_of_day = lerpf(c[0], c[1], clampf(k, 0.0, 1.0))


func _light_watch() -> void:
	var d: bool = main.is_day()
	if d == last_day:
		return
	last_day = d
	for poi in pois:
		poi.on_light_changed(d)
	if not d and state in ["shrink1", "hold", "shrink2"]:
		main.hud.announce(("FULL MOON" if is_full_moon() else "NIGHTFALL") + "\nThe nests wake. The Pack turns.")


func is_full_moon() -> bool:
	return not main.is_day() and bool(Cfg.BOSSES[mini(day, 2)].full_moon)


func living_enemies() -> int:
	return main.living_enemies()


func _tick_pois(delta: float) -> void:
	var p = main.player
	if p == null:
		return
	var budget := Cfg.MAX_ACTIVE_ENEMIES - living_enemies()
	if state in ["boss", "final_dusk", "deploy"]:
		budget = 0
	# nearest first, so the camp you're walking into wakes before a far one
	var order := pois.duplicate()
	order.sort_custom(func(a, b): return a.distance_to(p.global_position) < b.distance_to(p.global_position))
	for poi in order:
		budget -= poi.tick(delta, p.global_position, maxi(budget, 0))


func _roam(delta: float) -> void:
	roam_t -= delta
	if roam_t > 0.0:
		return
	roam_t = Cfg.ROAM_EVERY * (0.6 if not main.is_day() else 1.0)
	for i in range(roamers.size() - 1, -1, -1):
		if not is_instance_valid(roamers[i]) or roamers[i].dead:
			roamers.remove_at(i)
	if roamers.size() < Cfg.ROAM_CAP and living_enemies() < Cfg.MAX_ACTIVE_ENEMIES:
		main.spawn_enemy()
		roamers.append(main.enemies_root.get_child(main.enemies_root.get_child_count() - 1))


# ---------------------------------------------------------------- the Red Curfew
func _curfew_damage(delta: float, p) -> void:
	if p == null or p.dead:
		outside_amount = 0.0
		return
	var out: float = ring.outside_by(p.global_position)
	if out > 0.0:
		outside_t += delta
		var dps := minf(Cfg.RING_DAMAGE + Cfg.RING_RAMP * outside_t, Cfg.RING_DAMAGE_MAX)
		p.since_hurt = 0.0
		p.hp -= dps * delta
		if p.hp <= 0.0:
			p.hp = 0.01
			p.dash_t = 0.0
			p.invuln_t = 0.0
			p.take_damage(1.0, null)
		outside_amount = minf(outside_amount + delta * 2.0, 1.0)
	else:
		outside_t = 0.0
		outside_amount = maxf(outside_amount - delta * 2.0, 0.0)


func next_ring_radius() -> float:
	match state:
		"deploy", "explore":
			return Cfg.RING_STAGE1
		"shrink1", "hold", "shrink2":
			return arena.radius
	return -1.0


func time_left() -> float:
	match state:
		"explore":
			return T.explore - phase_t
		"shrink1":
			return T.shrink1 - phase_t
		"hold":
			return T.hold - phase_t
		"shrink2":
			return T.shrink2 - phase_t
		"final_dusk":
			return T.final_dusk - phase_t
	return 0.0


static func mmss(s: float) -> String:
	var n := maxi(int(ceil(s)), 0)
	return "%d:%02d" % [n / 60, n % 60]


## "DAY 1 — The Curfew falls in 2:10"
func phase_label() -> String:
	var dname := "FINAL NIGHT" if day >= 2 else "DAY %d" % (day + 1)
	match state:
		"deploy":
			return "DAY %d  —  the Descent" % (day + 1)
		"explore":
			return "%s  —  The Curfew falls in %s" % [dname, mmss(time_left())]
		"shrink1":
			return "%s  —  THE CURFEW IS CLOSING  %s" % [dname, mmss(time_left())]
		"hold":
			return "%s  —  The Curfew tightens in %s" % [dname, mmss(time_left())]
		"shrink2":
			return "%s  —  Reach %s  %s" % [dname, arena.name, mmss(time_left())]
		"boss":
			return ("NIGHT %d" % (day + 1) if day < 2 else "THE FINAL NIGHT") + "  —  " + (boss.boss_name if boss != null and is_instance_valid(boss) else "")
		"victory":
			return "DAWN IS COMING"
		"final_dusk":
			return "THE FINAL NIGHT falls in %s" % mmss(time_left())
	return ""


# ---------------------------------------------------------------- bosses
func _spawn_boss() -> void:
	var def: Dictionary = Cfg.BOSSES[mini(day, 2)]
	var b = load(def.script).new()
	b.main = main
	b.director = self
	b.boss_name = def.name
	b.boss_title = def.title
	b.max_hp = def.hp * T.boss_hp
	b.intro_t = 2.0
	b.arena_center = arena.pos
	b.arena_radius = arena.radius
	var p = main.player
	var to: Vector3 = p.global_position - arena.pos
	to.y = 0.0
	var off := -to.normalized() * 5.0 if to.length() > 1.0 else Vector3(0, 0, -5)
	b.position = arena.pos + off + Vector3(0, 0.1, 0)
	main.enemies_root.add_child(b)
	b.died.connect(_on_boss_died)
	boss = b
	ring.set_radius(arena.radius)
	main.hud.announce(def.name + "\n" + def.title)
	main.set_slowmo(0.4, 0.6)
	main.rumble(0.5, 0.8, 0.6)
	# whatever stands outside the arena wall won't join in
	var inside := func(e): return ring.outside_by(e.global_position) <= 0.0
	for poi in pois:
		poi.recall(inside)
	for e in main.enemies_root.get_children():
		if e != b and not e.dead and not e.is_queued_for_deletion() and ring.outside_by(e.global_position) > 0.0:
			main.release_attack_token(e)
			e.queue_free()


func boss_phase_text(_b, text: String) -> void:
	main.hud.announce(text)
	main.set_slowmo(0.35, 0.5)


func on_boss_woke(b) -> void:
	if b != boss:
		engaged_boss = b
		main.hud.popup(b.boss_name)


func summon(kind: int, pos: Vector3) -> void:
	if living_enemies() >= Cfg.MAX_ACTIVE_ENEMIES:
		return
	var e: CharacterBody3D = EnemyScript.new()
	e.main = main
	e.kind = kind
	var a := rng.randf() * TAU
	e.position = pos + Vector3(cos(a) * 3.5, 0.1, sin(a) * 3.5)
	main.enemies_root.add_child(e)
	summons.append(e)
	HFx.puff(main, e.position + Vector3(0, 1.0, 0), Color(0.6, 0.05, 0.05), 8, 0.2, 1.5)


func summons_alive() -> int:
	var n := 0
	for s in summons:
		if is_instance_valid(s) and not s.dead:
			n += 1
	return n


func _on_boss_died(b) -> void:
	bosses_killed += 1
	var def: Dictionary = Cfg.BOSSES[mini(day, 2)]
	main.loot.spawn_motes(b.global_position + Vector3(0, 1.5, 0), int(round(def.tithe * (1.0 + main.progression.stat("tithe_mult")))))
	main.loot.spawn_item(random_item(ItemDB.LEGENDARY, "blade"), b.global_position + Vector3(1.5, 0, 0))
	main.loot.spawn_item(random_item(ItemDB.LEGENDARY, "charm"), b.global_position + Vector3(-1.5, 0, 0))
	main.set_slowmo(0.25, 1.2)
	for s in summons:
		if is_instance_valid(s) and not s.dead:
			s._die(false)
	summons.clear()
	if day >= 2:
		won = true
		main.hud.announce("SERAPHINE'S ABOMINATION FALLS\nDawn breaks over Port Vesper")
		end_t = T.victory
		state = "victory_final"
	elif day == 1:
		main.hud.announce(def.name.split(",")[0] + " IS ASH\nThe Final Night is coming")
		_enter("final_dusk")
	else:
		main.hud.announce(def.name + " FALLS\nTake what it guarded. Dawn is coming.")
		_enter("victory")
	boss = null


## Dawn after Night 1: Day 2 begins where you stand.
func _next_day() -> void:
	day += 1
	revives = Cfg.REVIVES_PER_DAY
	ring.visible = true
	_set_arena(day)
	main.time_of_day = Cfg.CLOCK.explore[0]
	main.loot.respawn_caches()
	_light_watch()
	main.hud.announce("DAWN — DAY %d\nThe sun is up. The Curfew will fall again." % (day + 1))
	state = "explore"
	phase_t = 0.0


## After Night 2: through the blood-mist to the Undercroft Plaza for the last fight.
func _final_night() -> void:
	day = 2
	revives = Cfg.REVIVES_PER_DAY
	_set_arena(2)
	hud.fade_flash()
	var p = main.player
	var c: Vector3 = arena.pos
	p.global_position = c + Vector3(0, 0.3, arena.radius - 4.0)
	p.velocity = Vector3.ZERO
	p.facing = PI
	p.cam_yaw = 0.0
	for poi in pois:
		poi.recall()
	for e in main.enemies_root.get_children():
		if not e.dead:
			main.release_attack_token(e)
			e.queue_free()
	ring.set_radius(arena.radius)
	_enter("boss")


# ---------------------------------------------------------------- POIs
func on_poi_roused(_poi) -> void:
	pass


func on_poi_cleared(poi) -> void:
	var d: Dictionary = poi.def
	var pos: Vector3 = poi.global_position
	if int(d.tithe) > 0:
		main.loot.spawn_motes(pos + Vector3(0, 1.4, 0), int(round(d.tithe * (1.0 + main.progression.stat("tithe_mult")))))
	match int(d.reward):
		1:
			main.loot.spawn_item(random_item(ItemDB.UNCOMMON), pos + Vector3(0.8, 0, 0.8))
		2:
			main.loot.spawn_item(random_item(ItemDB.RARE), pos + Vector3(0.8, 0, 0.8))
		3:
			main.loot.spawn_item(random_item(ItemDB.LEGENDARY, "blade"), pos + Vector3(0.8, 0, 0.8))
	main.hud.popup("%s CLEARED" % poi.display_name.to_upper())


func coffin_loot(pos: Vector3, day_: bool) -> void:
	main.loot.spawn_motes(pos + Vector3(0, 0.8, 0), rng.randi_range(18, 34))
	if rng.randf() < (0.75 if day_ else 0.5):
		main.loot.spawn_item(random_item(ItemDB.UNCOMMON), pos + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)))
	main.hud.popup("THE SLEEPER'S HOARD")


## A random item of at least `min_r` rarity, optionally of one kind (blade / charm / vial / flare).
func random_item(min_r: int, kind := "") -> Dictionary:
	var luck: float = main.progression.stat("loot_luck")
	var inst := {}
	for i in 40:
		inst = ItemDB.random_item(rng, true, false, luck)
		if kind == "" or ItemDB.kind_of(inst) == kind:
			break
	if min_r >= ItemDB.LEGENDARY and kind == "blade" and not ItemDB.kind_of(inst) == "blade":
		inst = ItemDB.make("dawnbreaker")
	return ItemDB.make(inst.id, maxi(int(inst.r), min_r), int(inst.get("n", 1)))


# ---------------------------------------------------------------- interaction (chapels, merchants, coffins)
func _interactions(p) -> void:
	prompt = ""
	_interaction = {}
	if p == null or p.dead or p.bite_ready or main.menu_open() or main.loot.prompt_text != "":
		return
	for poi in pois:
		if poi.distance_to(p.global_position) > 6.0:
			continue
		var it: Dictionary = poi.interaction(p.global_position)
		if not it.is_empty():
			_interaction = it
			_interaction["poi"] = poi
			break
	if _interaction.is_empty():
		return
	var key := "[Y]" if main.hud.using_pad else "[E]"
	prompt = "%s  %s" % [key, _interaction.text]
	if _interaction.act == "vigil":
		var prog = main.progression
		prompt += "\nRank %d → %d  ·  %d Tithe" % [prog.level, prog.level + 1, prog.next_cost()] if prog.level < prog.MAX_LEVEL else "\n(highest rank)"
	if Input.is_action_just_pressed("interact"):
		match _interaction.act:
			"vigil":
				main.open_levelup()
			"trade":
				merchant.open()
			"coffin":
				_interaction.poi.open_coffin(_interaction.coffin)


# ---------------------------------------------------------------- death
## HUNT HOOK target: Sol fell. Half the Tithe stays where he fell (the death drop); with a
## revive left he gets back up at half blood, otherwise the Hunt ends.
func on_player_died() -> void:
	var p = main.player
	main.progression.on_death(p.global_position)
	main.loot._refresh_death_marker()
	main.clear_slowmo()
	if revives > 0 and state != "over":
		revives -= 1
		revive_t = 2.2
		main.hud.announce("YOU FALL...\nthe blood remembers")
	else:
		main.hud.announce("THE HUNT IS OVER")
		end_t = 2.0


func _revive() -> void:
	var p = main.player
	p.dead = false
	p.hp = p.max_hp * 0.5
	p.invuln_t = 3.0
	p.velocity = Vector3.ZERO
	p.visual.rotation.x = 0.0
	var ma = p.get("mod_anim")
	if ma != null:
		ma.dead = false
		if ma.tree != null:
			ma.tree.set("parameters/life/transition_request", "alive")
	for e in main.enemies_root.get_children():
		if not e.dead and e.global_position.distance_to(p.global_position) < 7.0 and "knockback" in e:
			var d: Vector3 = e.global_position - p.global_position
			d.y = 0.0
			e.knockback = d.normalized() * 14.0
	HFx.shockwave(main, p.global_position, 7.0, Color(1.0, 0.1, 0.1), 0.5)
	main.hud.announce("YOU RISE AGAIN\n%d revive%s left today" % [revives, "" if revives == 1 else "s"])


func _end_run(won_: bool) -> void:
	if state == "over":
		return
	won = won or won_
	state = "over"
	main.game_over = true
	main.clear_slowmo()
	var inv = main.inventory
	var carried: Array = []
	for c in inv.charms:
		if not c.is_empty():
			carried.append(c)
	for b in inv.bag:
		if ItemDB.kind_of(b) == "charm":
			carried.append(b)
	summary = {"won": won, "bosses": bosses_killed, "kills": main.kills, "rank": main.progression.level,
		"day": day + 1, "time": run_time, "tithe": main.progression.tithe}
	summary["earned"] = Meta.record_hunt(summary, carried)
	summary["kept"] = Meta.data.last.get("kept", [])
	main.progression.reset() # run-scoped: rank, Tithe, Vows and the Coat start over next Hunt
	main.player.hp = maxf(main.player.hp, 0.0)
	if map_screen != null:
		map_screen.close()
	results.show_results(summary)


## Results -> "Hunt again": a fresh city, a fresh seed, straight back in.
func hunt_again() -> void:
	requested = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


## Results -> back to the Undercroft (the hub in the main menu).
func return_to_hub() -> void:
	Meta.return_to_hub = true
	requested = false
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ---------------------------------------------------------------- debug / tests / screenshots
## Jump the run forward: "shrink1", "boss", "victory"...
func debug_skip_to(s: String) -> void:
	if deploy != null and deploy.playing:
		deploy.finish()
	if s == "boss" or s == "shrink2":
		ring.set_radius(Cfg.RING_STAGE1)
	_enter(s)


func _unhandled_input(event: InputEvent) -> void:
	# skip the Descent with any attack / jump / interact press
	if state == "deploy" and deploy != null and deploy.playing and deploy.t > 0.6 and (event.is_action_pressed("jump") or event.is_action_pressed("attack")):
		get_viewport().set_input_as_handled()
		deploy.finish()
