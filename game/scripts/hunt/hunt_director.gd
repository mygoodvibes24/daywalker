class_name HuntDirector
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
const Terrain = preload("res://scripts/map/terrain.gd") # TERRAIN HOOK
const HuntHud = preload("res://scripts/ui/hunt_hud.gd")
const MapScreen = preload("res://scripts/ui/map_screen.gd")
const ResultsScreen = preload("res://scripts/ui/results_screen.gd")
const MerchantUI = preload("res://scripts/ui/merchant_ui.gd")
const Story = preload("res://scripts/hunt/hunt_story.gd")
const MicroScript = preload("res://scripts/hunt/micro_poi.gd")
const Rites = preload("res://scripts/hunt/blood_rite.gd")
const RiteUIScript = preload("res://scripts/ui/rite_ui.gd")
const POIClass = preload("res://scripts/hunt/poi.gd")

## Set by the hub's "Begin the Hunt" (or --hunt / ?hunt) before main.tscn loads. The Hunt is
## THE game: main.tscn runs one however it was reached, unless free roam was asked for.
static var requested := false
## Debug only: the old free-roam sandbox (--freeroam / ?freeroam). Tests set this directly.
static var force_freeroam := false
## Tests force the short timings; otherwise --shorthunt / ?shorthunt.
static var force_short := false
static var seed_override := -1

var main: Main
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
var night_bosses: Array = [] # tonight's boss defs per day: two from the pool, then the Final Night
var story: CanvasLayer # intro, night cards (hunt_story.gd)
var fell_to := "" # the boss id that ended the run, for the results epilogue
var _interaction := {}
## Micro-POIs between the camps (micro_poi.gd): one-use caches, captives, blood fridges, shrines.
var micros: Array = []
var _micros_checked := false
## Blood Rites waiting to be offered (names of what died), and the screen that offers them.
var rite_queue: Array = []
var rite_wait := 0.0
var rite_ui: CanvasLayer
var rites_offered := 0
## Tonight's modifier per night (hunt_config.gd NIGHT_MODIFIERS ids), and the map's own fog.
var night_mods: Array = []
var base_fog := 1.0


static func wanted(main_) -> bool:
	var args := OS.get_cmdline_user_args()
	if requested or force_short or "--hunt" in args or "--shorthunt" in args or main_._url_flag("hunt") or main_._url_flag("shorthunt"):
		return true
	return not freeroam_wanted(main_)


## Free roam (spawn at the plaza, roaming spawns that chase you) exists only behind a debug flag.
static func freeroam_wanted(main_) -> bool:
	return force_freeroam or "--freeroam" in OS.get_cmdline_user_args() or main_._url_flag("freeroam")


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
	arenas = [Terrain.grounded(pool[0]), Terrain.grounded(pool[1]), Cfg.FINAL_ARENA] # TERRAIN HOOK: on the ground
	_pick_bosses()
	_pick_modifiers()
	poi_root = Node3D.new()
	poi_root.name = "HuntPOIs"
	add_child(poi_root)
	for e in Spawner.generate(seed, main.city):
		var poi = POIScript.new()
		poi.setup(self, e.type, e.seed, e.get("boss", {}))
		poi.position = e.pos
		register_poi(poi)
	var avoid: Array = []
	for poi in pois:
		avoid.append(poi.position)
	for e in MicroScript.generate(seed, main.city, avoid):
		var mp = MicroScript.new()
		mp.setup(self, e.type, e.seed)
		mp.position = e.pos
		mp.rotation.y = e.yaw
		register_site(mp)
	deploy_dressing = DeployScript.build_points(self)
	ring = RingScript.new()
	ring.name = "RedCurfew"
	ring.main = main
	add_child(ring)
	_set_arena(0)
	# where Sol drops in is known up front, so he never stands in the plaza, even behind
	# the title overlay of a direct load
	deploy_point = Terrain.grounded(Cfg.DEPLOY_POINTS[rng.randi() % Cfg.DEPLOY_POINTS.size()]) # TERRAIN HOOK


## Nights 1 and 2 draw two different bosses from the pool; the Final Night is fixed. Its own
## RNG stream, so the boss draw doesn't move the deployment point or the POIs for a seed.
func _pick_bosses() -> void:
	var br := RandomNumberGenerator.new()
	br.seed = seed * 7919 + 13
	var pool: Array = Cfg.NIGHT_BOSS_POOL.duplicate()
	for k in range(pool.size() - 1, 0, -1):
		var s_ := br.randi_range(0, k)
		var t = pool[k]
		pool[k] = pool[s_]
		pool[s_] = t
	night_bosses = [pool[0], pool[1], Cfg.FINAL_BOSS]


func boss_def(d: int) -> Dictionary:
	if night_bosses.is_empty():
		_pick_bosses()
	return night_bosses[clampi(d, 0, 2)]


## main.gd, right after the player exists: park Sol at his deployment point (never the plaza).
func stage_player() -> void:
	var p = main.player
	if p == null or deploy_point.is_empty():
		return
	var pos: Vector3 = deploy_point.pos
	var face: Vector3 = deploy_point.face
	p.position = pos + face * 1.2 + Vector3(0, 0.2, 0)


# ---------------------------------------------------------------- start
## main.start_game() -> here: wipe the run state, wear the hub loadout, deploy.
func start() -> void:
	var prog = main.progression
	prog.persist = false # a Hunt never writes the free-roam save
	prog.reset()
	main.inventory.charms = Meta.loadout_charms()
	main.inventory.weapon = Meta.start_blade() # the blade chosen on Nia's rack (the Arsenal)
	main.inventory.equipment_changed.emit()
	main.inventory.changed.emit()
	main.player.hp = main.player.max_hp
	main.loot.respawn_caches()
	main.loot._refresh_death_marker()
	main.lair_pos = Vector3(0, -500, 0) # Keep Vigil moves to the chapels during a Hunt
	main.hud.clock_label.visible = false
	main.hud.info_label.visible = false
	main.hud.announce_label.anchor_top = 0.27 # clear of the compass and the phase line
	main.hud.announce_label.anchor_bottom = 0.27
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
	story = Story.new()
	story.director = self
	story.main = main
	add_child(story)
	rite_ui = RiteUIScript.new()
	rite_ui.main = main
	add_child(rite_ui)
	base_fog = main.atmo.fog_scale if main.atmo != null else 1.0
	_apply_modifier()
	if Story.intro_wanted(short):
		# STORY: the first Hunt opens on Nia's briefing; the Descent follows it
		state = "intro"
		main.player.set_physics_process(false)
		story.play_intro(_begin_deploy)
		return
	_begin_deploy()


func _begin_deploy() -> void:
	main.player.set_physics_process(true)
	if deploy_point.is_empty():
		deploy_point = Terrain.grounded(Cfg.DEPLOY_POINTS[rng.randi() % Cfg.DEPLOY_POINTS.size()]) # TERRAIN HOOK
	deploy = DeployScript.new()
	deploy.main = main
	add_child(deploy)
	deploy.finished.connect(_on_deployed)
	state = "deploy"
	deploy.play(deploy_point, deploy_dressing)
	Dialogue.play_group("hunt_deploy_") # AUDIO HOOK
	_deploy_sfx(String(deploy_point.get("type", "")))


## The Descent's sounds (deploy.gd belongs to the UI pass): timed to its tweens per type.
func _deploy_sfx(type: String) -> void:
	var cues := [] # [seconds, sfx, volume]
	match type:
		"manhole":
			cues = [[0.05, "manhole_clank", 2.0], [0.95, "land_thud", 0.0], [1.6, "manhole_clank", -6.0]]
		"rooftop":
			cues = [[0.8, "boss_swipe", -6.0], [1.45, "land_thud", 4.0], [1.45, "boss_slam", -8.0]]
		"boat":
			cues = [[2.6, "land_thud", -2.0]]
		"ladder":
			cues = [[0.2, "manhole_clank", -14.0], [0.9, "manhole_clank", -14.0], [2.1, "land_thud", -6.0]]
		"subway":
			cues = [[2.3, "land_thud", -8.0]]
		_:
			cues = [[2.2, "land_thud", -10.0]]
	for c in cues:
		get_tree().create_timer(c[0]).timeout.connect(func():
			if deploy != null and is_instance_valid(deploy) and main.player != null:
				Audio.play_at(c[1], main.player.global_position, c[2]))


func _on_deployed() -> void:
	_enter("explore")
	_night_card()
	if "--debugcamp" in OS.get_cmdline_user_args() or main._url_flag("debugcamp"):
		debug_view_camp()


## Debug / screenshots (--debugcamp / ?debugcamp): stand Sol 22 m from the nearest enemy camp,
## looking at it, outside its aggro range.
func debug_view_camp() -> void:
	var p = main.player
	var best = null
	for poi in pois:
		if poi.type == "camp" and (best == null or poi.distance_to(p.global_position) < best.distance_to(p.global_position)):
			best = poi
	if best == null:
		return
	var c: Vector3 = best.global_position
	# back off along the camp's street (streets run on the GRID lines), towards the map centre
	var on_x_lane := absf(c.x - roundf(c.x / main.GRID) * main.GRID) < absf(c.z - roundf(c.z / main.GRID) * main.GRID)
	var dir := Vector3(0, 0, -signf(c.z) if c.z != 0.0 else 1.0) if on_x_lane else Vector3(-signf(c.x) if c.x != 0.0 else 1.0, 0, 0)
	var to: Vector3 = main.safe_ground(c + dir * 22.0) # QA2 #5: not inside a tank
	var look := Vector3(c.x - to.x, 0.0, c.z - to.z).normalized()
	var yaw := atan2(-look.x, -look.z)
	p.global_position = Vector3(to.x, main.city.height_at(to.x, to.z) + 0.2, to.z) # TERRAIN HOOK
	p.velocity = Vector3.ZERO
	p.cam_yaw = yaw
	p.facing = atan2(look.x, look.z)


func _set_arena(d: int) -> void:
	arena = arenas[d]
	var c: Vector3 = arena.pos
	ring_full = 0.0
	for corner in Cfg.MapLayout.corners(): # MAP HOOK: the Curfew opens round the whole map
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
			Dialogue.play("curfew_broadcast"); Dialogue.play("curfew_warning") # AUDIO HOOK
			main.hud.announce("THE RED CURFEW FALLS\nGet inside the blood-fog before it takes you")
		"hold":
			pass
		"shrink2":
			ring.shrink_to(arena.radius, T.shrink2)
			Dialogue.play("curfew_final"); Dialogue.play("reyes_scanner") # AUDIO HOOK
			main.hud.announce("THE CURFEW CLOSES\nMake for %s" % arena.name)
		"boss":
			_spawn_boss()
		"final_dusk":
			main.hud.announce("THE FINAL NIGHT\nSeraphine's work waits at the Undercroft")
			_night_card()


# ---------------------------------------------------------------- frame
func _physics_process(delta: float) -> void:
	if state == "idle" or state == "over" or state == "intro":
		return
	var p = main.player
	run_time += delta
	phase_t += delta
	if not _micros_checked:
		_check_micros()
	_tick_rite(delta)
	_tick_pois(delta)
	_hold_roamers()
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
	return not main.is_day() and bool(boss_def(day).full_moon)


func living_enemies() -> int:
	return main.living_enemies()


var _poi_acc := 0.0
var _poi_frame := 0
var _poi_order: Array = []
var _poi_sort_t := 0.0


## PERF: the camps tick at 30 Hz (not every physics frame), the nearest-first order is re-sorted
## twice a second instead of duplicated and sorted every frame, and a waking camp brings its
## members in at most two per tick, so no single frame builds a whole camp.
func _tick_pois(delta: float) -> void:
	var p = main.player
	if p == null:
		return
	_poi_acc += delta
	_poi_frame += 1
	if _poi_frame % 2 != 0:
		return
	var dt := _poi_acc
	_poi_acc = 0.0
	var budget := Settings.max_enemies(Cfg.MAX_ACTIVE_ENEMIES) - living_enemies() # SETTINGS HOOK: crowd density
	if state in ["boss", "final_dusk", "deploy"]:
		budget = 0
	budget = mini(budget, 2)
	_poi_sort_t -= dt
	if _poi_sort_t <= 0.0 or _poi_order.size() != pois.size():
		_poi_sort_t = 0.5
		# nearest first, so the camp you're walking into wakes before a far one
		var pp: Vector3 = p.global_position
		_poi_order = pois.duplicate()
		_poi_order.sort_custom(func(a, b): return a.distance_to(pp) < b.distance_to(pp))
	for poi in _poi_order:
		if is_instance_valid(poi):
			budget -= poi.tick(dt, p.global_position, maxi(budget, 0))


## Stragglers between the camps: a light trickle that turns up out of sight (well away from
## Sol, on a street inside the Curfew) and then STAYS PUT, idle, like a camp's members: it
## only comes for him once he walks into it or hits it (_hold_roamers). Nothing hunts him
## from the start of a day; the trickle begins once he has had time to pick a direction.
func _roam(delta: float) -> void:
	var mod := modifier()
	if state == "explore" and phase_t < Cfg.ROAM_GRACE * float(mod.get("roam_grace", 1.0)):
		return
	roam_t -= delta
	if roam_t > 0.0:
		return
	roam_t = Cfg.ROAM_EVERY * (0.6 if not main.is_day() else 1.0) * float(mod.get("roam_every", 1.0))
	if roamers.size() < Cfg.ROAM_CAP + int(mod.get("roam_cap", 0)) and living_enemies() < Cfg.MAX_ACTIVE_ENEMIES:
		_spawn_roamer()


func _spawn_roamer() -> void:
	var p = main.player
	if p == null:
		return
	var pos := Vector3.INF
	var roads: PackedVector3Array = main.city.road_points if main.city != null else PackedVector3Array() # MAP HOOK: the large map's roads
	for attempt in 48:
		var c: Vector3
		if not roads.is_empty():
			c = roads[rng.randi() % roads.size()] + Vector3(rng.randf_range(-2.0, 2.0), 0.5, rng.randf_range(-2.0, 2.0))
		else:
			var along := rng.randf_range(-76.0, 76.0)
			var lane: float = rng.randi_range(-3, 3) * float(main.GRID) + rng.randf_range(-2.0, 2.0)
			c = Vector3(lane, 0.5, along) if rng.randf() < 0.5 else Vector3(along, 0.5, lane)
		var d := c.distance_to(p.global_position)
		if d > Cfg.ROAM_MIN_DIST and d < Cfg.ROAM_MAX_DIST and ring.outside_by(c) <= -4.0:
			pos = c
			break
	if pos == Vector3.INF:
		return # nowhere quiet enough this time
	var e: CharacterBody3D = EnemyScript.new()
	e.main = main
	if main.is_day() or modifier().get("roam_pack", false):
		e.kind = 1 # the Pack in human form; vampires sleep by day (a Hunting Party is all Pack)
	elif main.is_full_moon():
		e.kind = 1 if rng.randf() < 0.7 else 0
	else:
		e.kind = 0 if rng.randf() < 0.6 else 1
	e.position = pos
	main.enemies_root.add_child(e)
	e.visual.rotation.y = rng.randf() * TAU
	roamers.append({"e": e, "roused": false})


## Park idle stragglers (speed 0, standing in their idle clip) until Sol comes close or hurts
## one; runs every frame, before the enemies' own physics (process_physics_priority -10).
func _hold_roamers() -> void:
	var p = main.player
	var range_: float = aggro_range() if state == "explore" else aggro_range() * 1.5 # the Curfew makes them twitchy
	for i in range(roamers.size() - 1, -1, -1):
		var r: Dictionary = roamers[i]
		var e = r.e
		if not is_instance_valid(e) or e.dead:
			roamers.remove_at(i)
			continue
		if not r.roused and p != null:
			if e.global_position.distance_to(p.global_position) < range_ or e.hp < e.max_hp - 0.01 or e.staggered:
				r.roused = true
		if not r.roused:
			if e.speed > 0.0:
				r["speed"] = e.speed # also picks up a wolf transform's new speed
				e.speed = 0.0
		elif r.has("speed"):
			if e.speed <= 0.0:
				e.speed = r.speed
			r.erase("speed")


# ---------------------------------------------------------------- the Red Curfew
func _curfew_damage(delta: float, p) -> void:
	if p == null or p.dead:
		outside_amount = 0.0
		return
	var out: float = ring.outside_by(p.global_position)
	if out > 0.0:
		outside_t += delta
		var dps := minf(Cfg.RING_DAMAGE + Cfg.RING_RAMP * outside_t, Cfg.RING_DAMAGE_MAX)
		dps *= clampf(1.0 - main.progression.stat("curfew_resist"), 0.1, 1.0) # Blood Rite: Curfew-Born
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


## "DAY 1 — The Curfew falls in 2:10   ◆ BLOOD MOON"
func phase_label() -> String:
	var base := _phase_text()
	var mod := modifier()
	if base != "" and not mod.is_empty() and state != "victory":
		return base + "   ◆ " + String(mod.name)
	return base


func _phase_text() -> String:
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
	var def: Dictionary = boss_def(day)
	var b = load(def.script).new()
	b.main = main
	b.director = self
	b.boss_id = def.id
	b.boss_name = def.name
	b.boss_title = _night_heading() + "  ·  " + def.title
	b.max_hp = def.hp * T.boss_hp * (Cfg.NIGHT2_HP_MULT if day == 1 else 1.0)
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
	Audio.set_boss(true, def.id) # AUDIO HOOK: the boss theme (Audio.boss_context)
	if def.intro != "":
		Dialogue.play(def.intro)
	Audio.play_at(def.intro_sfx, b.position, 3.0) # AUDIO HOOK
	main.hud.announce(def.name + "\n" + b.boss_title)
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
	e.position.y = maxf(e.position.y, main.city.height_at(e.position.x, e.position.z) + 0.1) # TERRAIN HOOK
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
	var def: Dictionary = boss_def(day)
	Audio.set_boss(false) # AUDIO HOOK
	Audio.on_boss_died(def.id, b.global_position) # AUDIO HOOK: the body hits the ground
	if def.death != "":
		Dialogue.play(def.death)
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
	if day < 2:
		queue_rite(POIClass.title_case(def.name.split(",")[0]))
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
	_apply_modifier()
	_night_card()


func _night_heading() -> String:
	return "THE FINAL NIGHT" if day >= 2 else "NIGHT %d" % (day + 1)


## STORY: who tonight's boss is and why it's after Sol.
func _night_card() -> void:
	if story != null:
		story.night_card(_night_heading() + "  ·  TONIGHT YOU HUNT", boss_def(day), modifier())


## After Night 2: through the blood-mist to the Undercroft Plaza for the last fight.
func _final_night() -> void:
	day = 2
	revives = Cfg.REVIVES_PER_DAY
	_set_arena(2)
	_apply_modifier()
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


# ---------------------------------------------------------------- the site API
## Add a point of interest to the Hunt (poi.gd or anything with the same shape): it is parented
## under HuntPOIs, ticked every frame (tick(delta, ppos, budget) -> spawned), told about dusk and
## dawn (on_light_changed), recalled at the boss wall (recall), drawn on the map and compass
## (type, def.color, cleared), offered for [E] (interaction(ppos) -> {text, act, ...}) and paid
## out through on_poi_cleared when it emits cleared_now(poi). Call before the navmesh bake
## (build_world) if it has colliders.
func register_poi(poi: Node3D) -> void:
	if poi.name == "" or poi.name.begins_with("@"):
		poi.name = "POI_%s_%d" % [poi.type, pois.size()]
	if poi.get_parent() == null:
		poi_root.add_child(poi)
	if poi.has_signal("cleared_now") and not poi.cleared_now.is_connected(on_poi_cleared):
		poi.cleared_now.connect(on_poi_cleared)
	pois.append(poi)


## Add a small interactive site with no camp (micro_poi.gd shape): distance_to(p),
## interaction(ppos) -> {text, act: "micro"} and use(). Shown on the map as a diamond.
func register_site(site: Node3D) -> void:
	if site.name == "" or site.name.begins_with("@"):
		site.name = "Micro_%s_%d" % [site.type, micros.size()]
	if site.get_parent() == null:
		poi_root.add_child(site)
	micros.append(site)


# ---------------------------------------------------------------- night modifiers
## One modifier per night (Day 1, Day 2, the Final Night), on its own seeded stream so the draw
## never moves the POIs or the bosses; no night repeats the one before it.
func _pick_modifiers() -> void:
	var mr := RandomNumberGenerator.new()
	mr.seed = seed * 104729 + 71
	var ids: Array = Cfg.NIGHT_MODIFIERS.keys()
	night_mods = []
	for d in 3:
		var pick: String = ids[mr.randi() % ids.size()]
		if not night_mods.is_empty() and pick == night_mods[-1]:
			pick = ids[(ids.find(pick) + 1 + mr.randi() % (ids.size() - 1)) % ids.size()]
		night_mods.append(pick)


## Tonight's modifier def ({} before the Hunt has drawn them).
func modifier() -> Dictionary:
	if night_mods.is_empty():
		return {}
	return Cfg.NIGHT_MODIFIERS.get(night_mods[clampi(day, 0, night_mods.size() - 1)], {})


func modifier_id() -> String:
	return "" if night_mods.is_empty() else String(night_mods[clampi(day, 0, night_mods.size() - 1)])


## Push tonight's modifier into the stat table (progression.gd) and the world (fog).
func _apply_modifier() -> void:
	var mod := modifier()
	main.progression.set_night_mods(mod.get("mods", {}))
	if main.atmo != null:
		main.atmo.fog_scale = base_fog * float(mod.get("fog", 1.0))


## How close Sol can come before an idle camp or straggler notices him (the Fog shortens it, and so
## does a crouch: player.gd detect_mult).
func aggro_range() -> float:
	var stealth := 1.0
	if main != null and main.player != null and main.player.has_method("detect_mult"):
		stealth = main.player.detect_mult()
	return Cfg.AGGRO_RANGE * float(modifier().get("aggro", 1.0)) * stealth


# ---------------------------------------------------------------- the Blood Rite
## A boss died: offer a Rite once the death has played out (and no menu is up).
func queue_rite(from: String) -> void:
	if state == "over" or won:
		return
	rite_queue.append(from)
	rite_wait = maxf(rite_wait, 2.2)


func _tick_rite(delta: float) -> void:
	if rite_queue.is_empty() or rite_ui == null or rite_ui.is_open():
		return
	rite_wait -= delta
	var p = main.player
	if rite_wait > 0.0 or p == null or p.dead or main.menu_open() or (map_screen != null and map_screen.is_open()) or end_t >= 0.0:
		return
	var from: String = rite_queue.pop_front()
	var offer: Array = main.progression.offer_rites(3)
	if offer.is_empty():
		return # every Rite already taken
	rites_offered += 1
	rite_ui.open(offer, from)


## The first frame of the Hunt (physics is live): drop micro-POIs that landed inside or under
## something solid (a parked car, a crate stack) on a road point.
func _check_micros() -> void:
	_micros_checked = true
	for i in range(micros.size() - 1, -1, -1):
		var mp = micros[i]
		var pos: Vector3 = mp.global_position
		if not main.spot_clear(Vector3(pos.x, main.ground_y(pos.x, pos.z), pos.z)):
			micros.remove_at(i)
			mp.queue_free()


# ---------------------------------------------------------------- POIs
func on_poi_roused(_poi) -> void:
	Dialogue.play("hunt_poi_found") # AUDIO HOOK (has its own cooldown)


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
	if poi.type == "fieldboss":
		queue_rite(poi.display_name) # a Landmark horror's blood is worth a Rite too
	# AUDIO HOOK: the nest line names a nest; anything else gets the generic one
	if poi.type == "nest":
		Dialogue.play_group("poi_cleared_")
	else:
		Dialogue.play("poi_cleared_2")


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
	for poi in _interactables():
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
			"micro":
				_interaction.poi.use()


var _inter_list: Array = []
var _inter_n := -1


## PERF: pois + micros without building a new array every physics frame.
func _interactables() -> Array:
	if _inter_n != pois.size() * 10000 + micros.size():
		_inter_n = pois.size() * 10000 + micros.size()
		_inter_list = pois + micros
	return _inter_list


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
		if boss != null and is_instance_valid(boss) and not boss.dead:
			fell_to = boss.boss_id


func _revive() -> void:
	var p = main.player
	p.dead = false
	p.hp = p.max_hp * 0.5
	p.invuln_t = 3.0
	p.velocity = Vector3.ZERO
	p.visual.rotation.x = 0.0
	# he comes to a few metres away from where he fell (and from whatever killed him):
	# the Lost Tithe stays behind, to be fought back for
	var from: Vector3 = p.global_position
	var away := Vector3.ZERO
	for e in main.enemies_root.get_children():
		if not e.dead and e.global_position.distance_to(from) < 15.0:
			away += (from - e.global_position).normalized()
	if away.length() < 0.1:
		away = ring.center - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)
	var to: Vector3 = main.safe_ground(from + away * 8.0) # never inside a solid the navmesh leaks into (QA2 #5)
	p.global_position = to + Vector3(0, 0.2, 0)
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
		"day": day + 1, "time": run_time, "tithe": main.progression.tithe,
		"rites": main.progression.rites.map(func(id): return Rites.name_of(id)),
		"micros": micros.filter(func(m): return is_instance_valid(m) and m.used).size()}
	summary["earned"] = Meta.record_hunt(summary, carried)
	summary["kept"] = Meta.data.last.get("kept", [])
	for d in [Cfg.FINAL_BOSS] + Cfg.NIGHT_BOSS_POOL:
		if d.id == fell_to:
			summary["fell_to_epitaph"] = d.epitaph
	summary["epilogue"] = Story.epilogue(summary)
	if won:
		Dialogue.play("hunt_extract") # AUDIO HOOK
	main.progression.reset() # run-scoped: rank, Tithe, Vows, Rites and the Coat start over next Hunt
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
	if story != null and story.playing:
		story.finish_intro()
	if deploy != null and deploy.playing:
		deploy.finish()
	if s == "boss" or s == "shrink2":
		ring.set_radius(Cfg.RING_STAGE1)
	if s == "boss":
		_place_in_arena() # L5: QA and screenshots want Sol inside tonight's arena, not outside it
	_enter(s)


## Stand Sol on open ground 6 m from the arena centre, facing it (the boss spawns across from him).
func _place_in_arena() -> void:
	var p = main.player
	if p == null:
		return
	var c: Vector3 = arena.pos
	var dir := Vector3(-c.x, 0.0, -c.z) # towards the map centre: the side Sol usually comes from
	dir = dir.normalized() if dir.length() > 1.0 else Vector3(0, 0, 1)
	var to: Vector3 = main.safe_ground(c + dir * 6.0)
	if Vector2(to.x - c.x, to.z - c.z).length() > float(arena.radius) - 1.0:
		var x := c.x + dir.x * 6.0
		var z := c.z + dir.z * 6.0
		to = Vector3(x, main.ground_y(x, z), z)
	p.global_position = to + Vector3(0, 0.2, 0)
	p.velocity = Vector3.ZERO
	var look := Vector3(c.x - to.x, 0.0, c.z - to.z).normalized()
	p.facing = atan2(look.x, look.z)
	p.cam_yaw = atan2(-look.x, -look.z)
	if p.visual != null:
		p.visual.rotation.y = p.facing


func _unhandled_input(event: InputEvent) -> void:
	# skip the Descent with any attack / jump / interact press
	if state == "deploy" and deploy != null and deploy.playing and deploy.t > 0.6 and (event.is_action_pressed("jump") or event.is_action_pressed("attack")):
		get_viewport().set_input_as_handled()
		deploy.finish()
