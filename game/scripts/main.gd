class_name Main
extends Node3D
## Port Vesper: world, day/night cycle, spawning and game state.

const U = preload("res://scripts/util.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HudScript = preload("res://scripts/hud.gd")
const AtmosphereScript = preload("res://scripts/atmosphere.gd")
const Wet = preload("res://scripts/wet_materials.gd")
const CityScript = preload("res://scripts/city.gd")
# progression (Tithe, ranks, Vows, loot, the Coat)
const ProgressionScript = preload("res://scripts/progression.gd")
const InventoryScript = preload("res://scripts/inventory.gd")
const LootScript = preload("res://scripts/loot.gd")
const FxScript = preload("res://scripts/fx.gd")
const InventoryUI = preload("res://scripts/ui/inventory_ui.gd")
const LevelupUI = preload("res://scripts/ui/levelup_ui.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const Prewarm = preload("res://scripts/prewarm.gd") # PERF: first-use hitches (loads + shader compiles)
const BenchScript = preload("res://scripts/bench.gd") # PERF: ?bench / --bench benchmark route
const Depths = preload("res://scripts/map/undercroft.gd") # UNDERCROFT HOOK: the crypt under the plaza

const DAY_LENGTH := 240.0 # seconds for one full day/night cycle
const LAIR_MAX := 3
const GRID := 20.0

var lair_pos := Vector3(0, 0, 0)
var time_of_day := 0.55 # 0 = midnight, 0.5 = noon
var night_count := 0
var kills := 0
var lair_stock := LAIR_MAX
var game_over := false
var spawn_timer := 4.0
var slowmo_effects: Array = [] # [{scale, until_ms}] — the lowest active scale wins
var attack_tokens := {} # enemies currently allowed to strike
const MAX_ATTACKERS := 2

## Survives scene reloads so "Rise again" skips the title screen.
static var started_once := false

var sun: DirectionalLight3D
var env: Environment
var atmo: Node3D # lighting, fog, sky, rain and post FX (atmosphere.gd)
var player: Player
var hud: CanvasLayer
var enemies_root: Node3D
var lamps: Array[OmniLight3D] = []
var window_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()
var nav_region: NavigationRegion3D
var city: Node3D # city.gd: geometry, materials, props
var started := false
var progression: Progression
var inventory: Inventory
var loot: Loot
var fx: Node3D # fx.gd
var inventory_ui: CanvasLayer
var levelup_ui: CanvasLayer
var pause_menu: CanvasLayer # Esc: Resume / Options / Controls / Quit to Menu
var ui_block_until := 0 # ms; swallows the button press that closed a menu
var hunt: HuntDirector = null # HUNT HOOK: hunt_director.gd while a Hunt runs (null in free roam)
var free_roam := false # debug only (--freeroam / ?freeroam): plaza start + the old roaming spawner
var depths: Node3D # UNDERCROFT HOOK: map/undercroft.gd (the Undercroft Depths and its rival)


func _ready() -> void:
	rng.randomize()
	Engine.time_scale = 1.0
	if "--night" in OS.get_cmdline_user_args() or _url_flag("night"):
		time_of_day = 0.74 # debug: start right before nightfall
	_setup_input()
	if BenchScript.wanted() and HuntDirector.seed_override < 0:
		HuntDirector.seed_override = 4242 # PERF: the benchmark always runs the same Hunt
	_build_environment()
	_build_city()
	_build_lair()
	_setup_hunt() # HUNT HOOK: POIs and deployment points, before the navmesh bake
	_bake_navigation()
	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)
	player = PlayerScript.new()
	player.main = self
	player.position = Vector3(0, 0.2, 6)
	add_child(player)
	if hunt != null:
		hunt.stage_player() # HUNT HOOK: Sol waits at his deployment point, never the plaza
	hud = HudScript.new()
	hud.main = self
	add_child(hud)
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_progression() # PROGRESSION HOOK
	Audio.attach_world(self) # AUDIO HOOK
	pause_menu = PauseMenu.new()
	pause_menu.main = self
	add_child(pause_menu)
	_update_lighting()
	Input.joy_connection_changed.connect(_on_joy_changed)
	Prewarm.run(self) # PERF: load every body / clip / sound now and compile shaders behind a card
	if BenchScript.wanted() and get_node_or_null("/root/Bench") == null and get_parent().get_node_or_null("Bench") == null:
		var b = BenchScript.new()
		b.main = self
		add_child(b)
	if started_once:
		start_game()
	else:
		get_tree().paused = true # the world waits behind the title screen


## Called by the HUD on the first click / key / button (and right away after a restart).
func start_game() -> void:
	if started:
		return
	started = true
	started_once = true
	get_tree().paused = false
	hud.started = true
	if not OS.has_feature("web"): # R2-A: browsers refuse pointer lock without a click; the HUD asks for one
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.block_attack()
	if hunt != null:
		hunt.start() # HUNT HOOK: run-scoped reset, hub loadout, the Descent
		print("Daywalker: HUNT_READY") # the CI web render check waits for this line
	Dialogue.play("hunt_start") # AUDIO HOOK


## HUNT HOOK: the Hunt is the game. main.tscn always runs one (from the hub, a direct load,
## "Hunt again"), except behind the debug flag --freeroam / ?freeroam.
func _setup_hunt() -> void:
	if not HuntDirector.wanted(self):
		free_roam = true
		return
	hunt = HuntDirector.new()
	hunt.name = "Hunt"
	hunt.main = self
	add_child(hunt)
	hunt.build_world()


## True if the page URL has ?name or &name (or name=...) as its own parameter.
func _url_flag(name: String) -> bool:
	if not OS.has_feature("web"):
		return false
	var q := str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
	for part in q.split("&", false):
		if part.split("=")[0] == name:
			return true
	return false


func _on_joy_changed(_device: int, connected: bool) -> void:
	hud.popup("CONTROLLER CONNECTED" if connected else "CONTROLLER DISCONNECTED")


## Rumble every connected controller (ignored where unsupported).
func rumble(weak: float, strong: float, seconds: float) -> void:
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, weak, strong, seconds)


# ---------------------------------------------------------------- input
func _setup_input() -> void:
	# keyboard/mouse + controller (Xbox / PlayStation / Switch Pro via standard mapping)
	_bind("move_forward", [KEY_W, KEY_UP], [], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("move_back", [KEY_S, KEY_DOWN], [], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("move_left", [KEY_A, KEY_LEFT], [], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("move_right", [KEY_D, KEY_RIGHT], [], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("look_left", [], [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_bind("look_right", [], [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_bind("look_up", [], [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_bind("look_down", [], [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_bind("jump", [KEY_SPACE], [], [JOY_BUTTON_A])
	_bind("sprint", [KEY_SHIFT], [], [JOY_BUTTON_LEFT_STICK], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind("dash", [KEY_Q], [MOUSE_BUTTON_RIGHT], [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER])
	_bind("attack", [KEY_J], [MOUSE_BUTTON_LEFT], [JOY_BUTTON_X], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind("bite", [KEY_E], [], [JOY_BUTTON_Y])
	_bind("drink", [KEY_F], [], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("restart", [KEY_R], [], [JOY_BUTTON_START])
	# progression: interact shares E / Y with bite (the bite wins while a staggered enemy is in reach)
	_bind("interact", [KEY_E], [], [JOY_BUTTON_Y])
	_bind("inventory", [KEY_TAB, KEY_I], [], [JOY_BUTTON_START]) # START restarts only after death
	_bind("quick_1", [KEY_1], [], [JOY_BUTTON_LEFT_SHOULDER]) # LB drinks bagged blood at the lair instead
	_bind("quick_2", [KEY_2], [], [JOY_BUTTON_RIGHT_STICK])


func _bind(action: String, keys: Array, buttons: Array = [], pad_buttons: Array = [], pad_axes: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.25) # stick deadzone
	for jb in pad_buttons:
		var pb := InputEventJoypadButton.new()
		pb.button_index = jb
		pb.device = -1 # any controller
		InputMap.action_add_event(action, pb)
	for ax in pad_axes:
		var pm := InputEventJoypadMotion.new()
		pm.axis = ax[0]
		pm.axis_value = ax[1]
		pm.device = -1
		InputMap.action_add_event(action, pm)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)


# ---------------------------------------------------------------- world
func _build_environment() -> void:
	# sky, fog, sun/moon, rain and the film look; quality tier follows the renderer
	atmo = AtmosphereScript.new()
	atmo.name = "Atmosphere"
	atmo.main = self
	add_child(atmo)
	env = atmo.env
	sun = atmo.sun


func _build_city() -> void:
	city = CityScript.new()
	city.name = "City"
	add_child(city)
	city.build()
	atmo.fog_scale = city.FOG_SCALE # MAP HOOK: thinner fog so landmarks read across the large map
	window_mat = city.window_mat
	lamp_mat = city.lamp_mat
	lamps = city.lamps


func _build_lair() -> void:
	# The Undercroft entrance: an old stone well-head in the cathedral plaza.
	var root := Node3D.new()
	root.name = "Undercroft"
	root.position = lair_pos
	add_child(root)
	city.build_lair(root)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.5, 0)
	light.light_color = Color(1, 0.1, 0.1)
	light.light_energy = 1.5
	light.omni_range = 7.0
	root.add_child(light)
	var sign := Label3D.new()
	sign.text = "THE UNDERCROFT"
	sign.font_size = 72
	sign.modulate = Color(0.9, 0.2, 0.2)
	sign.outline_size = 12
	sign.position = Vector3(0, 4.6, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(sign)
	# UNDERCROFT HOOK: the stair in the well leads down to the Undercroft Depths
	depths = Depths.new()
	depths.main = self
	add_child(depths)


## Bake a navmesh from the generated city so enemies path around buildings.
func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = 0.6 # a whole number of 0.3 m cells (0.5 was ceiled, with a warning every load)
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	var pr: Rect2 = city.play_rect # MAP HOOK: bake the whole large map
	nm.filter_baking_aabb = AABB(Vector3(pr.position.x - 1.0, -6.0, pr.position.y - 1.0), Vector3(pr.size.x + 2.0, 40.0, pr.size.y + 2.0)) # TERRAIN HOOK: the hills and the lake bed
	nm.agent_max_slope = 38.0 # TERRAIN HOOK: walkable hills, the steep faces stay out
	nm.cell_size = 0.3 # MAP HOOK: coarser cells keep the ~430 m bake fast (the map uses the same size)
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, nm.cell_size) # MAP HOOK
	var src := NavigationMeshSourceGeometryData3D.new()
	var t0 := Time.get_ticks_msec()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	var t1 := Time.get_ticks_msec()
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	print("navmesh: %d polys in %d ms (parse %d, bake %d)" % [nm.get_polygon_count(), Time.get_ticks_msec() - t0, t1 - t0, Time.get_ticks_msec() - t1]) # TERRAIN HOOK
	nav_region = NavigationRegion3D.new()
	nav_region.navigation_mesh = nm
	add_child(nav_region)


# ---------------------------------------------------------------- time
func is_day() -> bool:
	return time_of_day > 0.25 and time_of_day < 0.75


func daylight() -> float:
	return clampf(sin((time_of_day - 0.25) * TAU) * 1.6, 0.0, 1.0)


func is_full_moon() -> bool:
	if hunt != null:
		return hunt.is_full_moon() # HUNT HOOK
	return not is_day() and night_count > 0 and night_count % 3 == 0 # nights 3, 6, 9...


func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _process(delta: float) -> void:
	_update_slowmo()
	_fall_sweep(delta)
	if game_over:
		if Input.is_action_just_pressed("restart") and hunt == null: # HUNT HOOK: the results screen decides
			clear_slowmo()
			get_tree().reload_current_scene()
		return
	if hunt != null:
		_update_lighting() # HUNT HOOK: the director drives the clock and the spawning
		return
	var was_day := is_day()
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	if was_day and not is_day():
		night_count += 1
		if is_full_moon():
			hud.announce("FULL MOON\nThe Hollow Pack is turning")
			Audio.play("wolf_howl", -6.0); Dialogue.play("nia_full_moon") # AUDIO HOOK
		else:
			hud.announce("NIGHTFALL\nThe Velvet Court awakens")
			Dialogue.play("bark_nightfall") # AUDIO HOOK
	elif not was_day and is_day():
		lair_stock = LAIR_MAX
		loot.respawn_caches() # PROGRESSION HOOK
		hud.announce("SUNRISE\nVampires burn. The blood bank is restocked.\nCoffins and crates are full again.")
		Dialogue.play(["bark_sunrise", "nia_sunrise"].pick_random()) # AUDIO HOOK
	_update_lighting()
	if free_roam:
		_update_spawning(delta) # the old chase-the-player spawner: free roam (debug) only


func _update_lighting() -> void:
	var d := daylight()
	var angle := (time_of_day - 0.25) * TAU
	if d > 0.0:
		sun.rotation = Vector3(-clampf(angle, 0.2, PI - 0.2), 0.6, 0)
	else:
		sun.rotation = Vector3(-0.9, -0.7, 0) # the moon
	# colours, fog, lamps, windows and the full-moon look live in atmosphere.gd
	atmo.update_lighting(d, 1.0 - clampf(d * 2.0, 0.0, 1.0), is_full_moon())


# ---------------------------------------------------------------- enemies
func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	var cap := 4
	if is_day():
		spawn_timer = 5.0
	else:
		spawn_timer = 1.6 if is_full_moon() else 2.4
		cap = mini(6 + night_count * 2, 14)
	if living_enemies() < cap:
		spawn_enemy()


func living_enemies() -> int:
	var n := 0
	for e in enemies_root.get_children():
		if not e.dead:
			n += 1
	return n


func spawn_enemy() -> void:
	var e: CharacterBody3D = EnemyScript.new()
	e.main = self
	if is_day():
		e.kind = 1 # the Pack in human form; vampires sleep by day
	elif is_full_moon():
		e.kind = 1 if rng.randf() < 0.7 else 0
	else:
		e.kind = 0 if rng.randf() < 0.6 else 1
	e.position = _road_point_near(player.global_position)
	enemies_root.add_child(e)


func _road_point_near(center: Vector3) -> Vector3:
	if city != null and not city.road_points.is_empty():
		return city.road_point_near(center, rng) # MAP HOOK: roads and paths of the large map
	var best := Vector3(0, 0.5, -60)
	var best_score := INF
	for attempt in range(24):
		var along := rng.randf_range(-76.0, 76.0)
		var lane := rng.randi_range(-3, 3) * GRID + rng.randf_range(-2.0, 2.0)
		var p := Vector3(lane, 0.5, along) if rng.randf() < 0.5 else Vector3(along, 0.5, lane)
		var dist := p.distance_to(center)
		if dist > 18.0 and dist < 45.0:
			return p
		# fallback: never closer than 18 m; otherwise the one nearest the 18–45 m band
		var score := (18.0 - dist) * 100.0 if dist <= 18.0 else dist - 45.0
		if score < best_score:
			best_score = score
			best = p
	return best


# ---------------------------------------------------------------- safe ground (QA2 #5)
const KILL_DEPTH := 6.0 # this far below the ground under you: you fell out of the world
const KILL_Y := -25.0 # and never lower than this, whatever the terrain says


## True if `p` (feet height) is open ground: the first thing a ray from high above meets is the
## ground at p, so p is not inside a closed collider (a Docks tank, a crate stack) or under one.
func spot_clear(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 30.0, 0), p - Vector3(0, 1.5, 0), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false # nothing under it at all: a hole
	return absf(float(hit.position.y) - p.y) < 1.1


## The nearest open ground to `near`: the navmesh point if it is clear, else the nearest clear road
## point. Use for revives, deploy snaps and fall recovery (the navmesh is baked inside some solids).
func safe_ground(near: Vector3) -> Vector3:
	var to := near
	var nav_map: RID = get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		to = NavigationServer3D.map_get_closest_point(nav_map, near)
	var gy := ground_y(to.x, to.z)
	if absf(to.y - gy) < 1.5:
		to.y = gy # the navmesh floats a little over the ground
	if spot_clear(to):
		return to
	if city != null and not city.road_points.is_empty():
		var pts: Array = []
		for r in city.road_points:
			pts.append(r)
		pts.sort_custom(func(a, b): return a.distance_squared_to(near) < b.distance_squared_to(near))
		for i in mini(pts.size(), 40):
			var r: Vector3 = pts[i]
			if spot_clear(r):
				return r
		return pts[0]
	return Vector3(to.x, maxf(to.y, 0.0), to.z)


## Ground height under (x, z), for the kill plane: the terrain, or 0 on the flat test map.
func ground_y(x: float, z: float) -> float:
	if city != null and city.has_method("height_at"):
		return city.height_at(x, z)
	return 0.0


## Is this body below the world? (fell through a seam, spawned inside a solid and squeezed out)
func below_world(p: Vector3) -> bool:
	return p.y < KILL_Y or p.y < ground_y(p.x, p.z) - KILL_DEPTH


var _fall_sweep_t := 0.0


## Enemies and bosses that fell out of the world come back on the nearest open ground.
func _fall_sweep(delta: float) -> void:
	_fall_sweep_t -= delta
	if _fall_sweep_t > 0.0 or enemies_root == null:
		return
	_fall_sweep_t = 0.5
	for e in enemies_root.get_children():
		if not (e is Node3D) or e.get("dead") == true:
			continue
		if below_world(e.global_position):
			var home = e.get("arena_center")
			var aim: Vector3 = home if home is Vector3 and home != Vector3.ZERO else e.global_position
			var to := safe_ground(Vector3(aim.x, ground_y(aim.x, aim.z), aim.z))
			e.global_position = to + Vector3(0, 0.3, 0)
			if e is CharacterBody3D:
				e.velocity = Vector3.ZERO


## Attack tokens: only a couple of enemies may strike at once, the rest circle.
func request_attack_token(e: Node) -> bool:
	for k in attack_tokens.keys():
		if not is_instance_valid(k) or k.dead:
			attack_tokens.erase(k)
	if attack_tokens.has(e):
		return true
	if attack_tokens.size() >= MAX_ATTACKERS:
		return false
	attack_tokens[e] = true
	return true


func release_attack_token(e: Node) -> void:
	attack_tokens.erase(e)


func on_enemy_killed(_e: Node, _drained: bool) -> void:
	kills += 1
	loot.on_enemy_killed(_e, _drained) # PROGRESSION HOOK: Tithe motes, item drops


func on_wolf_transform(e: Node3D) -> void:
	if player != null and e.global_position.distance_to(player.global_position) < 20.0:
		player.shake = maxf(player.shake, 0.25)


# ---------------------------------------------------------------- player hooks
func drink_from_lair() -> void:
	if lair_stock <= 0:
		return
	lair_stock -= 1
	player.heal(45.0)
	player.hunger = maxf(player.hunger - 20.0, 0.0)
	hud.popup("BAGGED BLOOD  +45  (hunger eased)")


## Each slow-motion effect runs for its own real-time duration; the slowest
## active one wins, so a short hit-stop inside bullet-time ends on time.
func set_slowmo(scale: float, real_seconds: float) -> void:
	slowmo_effects.append({"scale": scale, "until": Time.get_ticks_msec() + int(real_seconds * 1000.0)})
	_update_slowmo()


func clear_slowmo() -> void:
	slowmo_effects.clear()
	Engine.time_scale = 1.0


func _update_slowmo() -> void:
	var now := Time.get_ticks_msec()
	var scale := 1.0
	for i in range(slowmo_effects.size() - 1, -1, -1):
		var fx: Dictionary = slowmo_effects[i]
		if now >= fx.until:
			slowmo_effects.remove_at(i)
		else:
			scale = minf(scale, fx.scale)
	Engine.time_scale = scale


func perfect_dodge() -> void:
	hud.popup("PERFECT DODGE")
	Audio.play("perfect_dodge"); Dialogue.play_group("bark_dodge_") # AUDIO HOOK
	player.dash_charges = minf(player.dash_charges + 1.0, player.MAX_DASH)
	set_slowmo(0.3, 0.8)
	progression.on_perfect_dodge() # PROGRESSION HOOK


func on_player_died() -> void:
	if hunt != null:
		hunt.on_player_died() # HUNT HOOK: revive charge or the end of the Hunt
		return
	game_over = true
	progression.on_death(player.global_position) # PROGRESSION HOOK: half the Tithe stays here
	clear_slowmo()
	hud.show_game_over()


# ---------------------------------------------------------------- progression hooks
## Tithe, ranks and Vows (progression.gd), the Coat (inventory.gd), loot in the world
## (loot.gd), Vow effects (fx.gd) and their two menus. Loads user://save.json.
func _setup_progression() -> void:
	inventory = InventoryScript.new()
	inventory.name = "Inventory"
	inventory.main = self
	add_child(inventory)
	progression = ProgressionScript.new()
	progression.name = "Progression"
	progression.main = self
	progression.inventory = inventory
	add_child(progression)
	progression.load_save()
	player.hp = player.max_hp
	inventory.equipment_changed.connect(_on_equipment_changed)
	progression.connect_player(player)
	fx = FxScript.new()
	fx.name = "Fx"
	fx.main = self
	add_child(fx)
	fx.connect_player(player)
	loot = LootScript.new()
	loot.name = "Loot"
	loot.main = self
	add_child(loot)
	inventory_ui = InventoryUI.new()
	inventory_ui.main = self
	add_child(inventory_ui)
	inventory_ui.closed.connect(_on_menu_closed)
	levelup_ui = LevelupUI.new()
	levelup_ui.main = self
	add_child(levelup_ui)
	levelup_ui.closed.connect(_on_menu_closed)
	player.set_weapon_visual(inventory.weapon)


func _on_equipment_changed() -> void:
	progression.recompute()
	player.set_weapon_visual(inventory.weapon)
	progression.save()


func _on_menu_closed() -> void:
	ui_block_until = Time.get_ticks_msec() + 250


## The Coat's "Pause" button (and pad Back inside the Coat) lands here.
func open_pause() -> void:
	if started and not game_over:
		pause_menu.open()


func menu_open() -> bool:
	return inventory_ui.is_open() or levelup_ui.is_open() or Time.get_ticks_msec() < ui_block_until \
		or (hunt != null and hunt.story != null and hunt.story.playing) \
		or (hunt != null and hunt.rite_ui != null and hunt.rite_ui.is_open()) # the first-Hunt intro (QA2 #3), the Blood Rite


func open_levelup() -> void:
	if started and not game_over and not menu_open():
		levelup_ui.open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and started and not game_over and not menu_open():
		get_viewport().set_input_as_handled()
		inventory_ui.open()
