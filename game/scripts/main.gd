extends Node3D
## Port Vesper: world, day/night cycle, spawning and game state.

const U = preload("res://scripts/util.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HudScript = preload("res://scripts/hud.gd")
const PropsScript = preload("res://scripts/props.gd")

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
var player: CharacterBody3D
var hud: CanvasLayer
var enemies_root: Node3D
var lamps: Array[OmniLight3D] = []
var window_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()
var nav_region: NavigationRegion3D
var started := false


func _ready() -> void:
	rng.randomize()
	Engine.time_scale = 1.0
	if "--night" in OS.get_cmdline_user_args() or _url_flag("night"):
		time_of_day = 0.74 # debug: start right before nightfall
	_setup_input()
	_build_environment()
	_build_city()
	_build_lair()
	PropsScript.scatter(self, rng)
	_bake_navigation()
	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)
	player = PlayerScript.new()
	player.main = self
	player.position = Vector3(0, 0.2, 6)
	add_child(player)
	hud = HudScript.new()
	hud.main = self
	add_child(hud)
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	_update_lighting()
	Input.joy_connection_changed.connect(_on_joy_changed)
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.block_attack()


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
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.011
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_city() -> void:
	var asphalt := U.mat(Color(0.09, 0.09, 0.1), 0.35, 0.1) # wet street
	var walk := U.mat(Color(0.28, 0.27, 0.26), 0.9)
	window_mat = U.glow(Color(1.0, 0.75, 0.4), 0.0)
	var wall_mats: Array[StandardMaterial3D] = [
		U.mat(Color(0.22, 0.2, 0.19), 0.9),
		U.mat(Color(0.3, 0.22, 0.18), 0.9),
		U.mat(Color(0.16, 0.17, 0.2), 0.8),
		U.mat(Color(0.35, 0.33, 0.3), 0.9),
	]
	var neons: Array[Color] = [Color(1, 0.1, 0.4), Color(0.1, 0.9, 1), Color(0.8, 0.1, 1), Color(1, 0.15, 0.1)]

	# ground
	var ground := StaticBody3D.new()
	add_child(ground)
	var gcol := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(240, 1, 240)
	gcol.shape = gshape
	gcol.position.y = -0.5
	ground.add_child(gcol)
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	U.part(ground, plane, asphalt, Vector3.ZERO)

	# city blocks (plaza in the middle is left open)
	for i in range(-4, 4):
		for j in range(-4, 4):
			var cx := i * GRID + GRID * 0.5
			var cz := j * GRID + GRID * 0.5
			if absf(cx) < GRID and absf(cz) < GRID:
				continue
			# sidewalk: a thin visual slab with no collider, so nobody snags on a curb
			U.part(self, U.box(Vector3(13, 0.06, 13)), walk, Vector3(cx, 0.03, cz))
			var far := clampf(Vector2(cx, cz).length() / 90.0, 0.0, 1.0)
			var count := rng.randi_range(1, 2)
			for b in range(count):
				var w := rng.randf_range(5.0, 11.0) if count == 1 else rng.randf_range(4.5, 5.5)
				var d := rng.randf_range(6.0, 11.0)
				var h := rng.randf_range(7.0, 16.0) + far * rng.randf_range(4.0, 26.0)
				var ox := 0.0 if count == 1 else (-3.0 if b == 0 else 3.0)
				var pos := Vector3(cx + ox, h * 0.5, cz)
				var bld := U.static_box(self, Vector3(w, h, d), pos, wall_mats[rng.randi() % wall_mats.size()])
				# lit window bands
				var y := 3.0
				while y < h - 1.5:
					if rng.randf() < 0.6:
						U.part(bld, U.box(Vector3(w * 0.8, 0.9, d + 0.06)), window_mat, Vector3(0, y - h * 0.5, 0))
					y += 3.2
				# rooftop neon
				if rng.randf() < 0.45:
					var neon := U.glow(neons[rng.randi() % neons.size()], 3.0)
					U.part(bld, U.box(Vector3(w * 0.7, 0.35, 0.15)), neon, Vector3(0, h * 0.5 - 0.8, d * 0.5 + 0.1))

	# boundary walls
	var edge := 4.0 * GRID + 2.0
	for s in [-1.0, 1.0]:
		U.static_box(self, Vector3(2, 30, edge * 2.0), Vector3(s * edge, 15, 0), null)
		U.static_box(self, Vector3(edge * 2.0, 30, 2), Vector3(0, 15, s * edge), null)

	# street lamps around the plaza
	lamp_mat = U.glow(Color(1, 0.8, 0.5), 0.2)
	var post := U.mat(Color(0.05, 0.05, 0.05), 0.4, 0.6)
	for k in range(6):
		var a := k * TAU / 6.0 + 0.5
		var p := Vector3(cos(a) * 15.0, 0, sin(a) * 15.0)
		U.part(self, U.cyl(0.08, 0.12, 4.5), post, p + Vector3(0, 2.25, 0))
		U.part(self, U.sphere(0.3), lamp_mat, p + Vector3(0, 4.6, 0))
		var l := OmniLight3D.new()
		l.position = p + Vector3(0, 4.3, 0)
		l.omni_range = 13.0
		l.light_color = Color(1, 0.75, 0.45)
		add_child(l)
		lamps.append(l)


func _build_lair() -> void:
	# The Undercroft entrance: a sunken stone ring in the cathedral plaza.
	var stone := U.mat(Color(0.32, 0.3, 0.28), 0.95)
	var dark := U.mat(Color(0.0, 0.0, 0.0), 1.0)
	var root := Node3D.new()
	root.position = lair_pos
	add_child(root)
	U.part(root, U.cyl(2.6, 2.8, 0.5), stone, Vector3(0, 0.25, 0))
	var ring := StaticBody3D.new()
	root.add_child(ring)
	var ring_col := CollisionShape3D.new()
	var ring_shape := CylinderShape3D.new()
	ring_shape.radius = 2.8
	ring_shape.height = 0.5
	ring_col.shape = ring_shape
	ring_col.position.y = 0.25
	ring.add_child(ring_col)
	U.part(root, U.cyl(2.0, 2.0, 0.52), dark, Vector3(0, 0.26, 0))
	U.part(root, U.cyl(1.0, 1.0, 0.54), U.glow(Color(0.8, 0.0, 0.05), 2.5), Vector3(0, 0.27, 0))
	for k in range(4):
		var a := k * TAU / 4.0 + PI / 4.0
		U.static_box(root, Vector3(0.6, 3.5, 0.6), Vector3(cos(a) * 3.2, 1.75, sin(a) * 3.2), stone)
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


## Bake a navmesh from the generated city so enemies path around buildings.
func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	var edge := 4.0 * GRID + 1.0
	nm.filter_baking_aabb = AABB(Vector3(-edge, -1.0, -edge), Vector3(edge * 2.0, 4.0, edge * 2.0))
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	nav_region = NavigationRegion3D.new()
	nav_region.navigation_mesh = nm
	add_child(nav_region)


# ---------------------------------------------------------------- time
func is_day() -> bool:
	return time_of_day > 0.25 and time_of_day < 0.75


func daylight() -> float:
	return clampf(sin((time_of_day - 0.25) * TAU) * 1.6, 0.0, 1.0)


func is_full_moon() -> bool:
	return not is_day() and night_count > 0 and night_count % 3 == 0 # nights 3, 6, 9...


func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _process(delta: float) -> void:
	_update_slowmo()
	if game_over:
		if Input.is_action_just_pressed("restart"):
			clear_slowmo()
			get_tree().reload_current_scene()
		return
	var was_day := is_day()
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	if was_day and not is_day():
		night_count += 1
		if is_full_moon():
			hud.announce("FULL MOON\nThe Hollow Pack is turning")
		else:
			hud.announce("NIGHTFALL\nThe Velvet Court awakens")
	elif not was_day and is_day():
		lair_stock = LAIR_MAX
		hud.announce("SUNRISE\nVampires burn. The blood bank is restocked.")
	_update_lighting()
	_update_spawning(delta)


func _update_lighting() -> void:
	var d := daylight()
	var night_sky := Color(0.02, 0.025, 0.06) if not is_full_moon() else Color(0.05, 0.04, 0.08)
	var dusk := Color(0.55, 0.3, 0.25)
	var noon := Color(0.42, 0.48, 0.56) # overcast, rain-soaked
	var sky := night_sky.lerp(dusk, clampf(d * 3.0, 0.0, 1.0)).lerp(noon, clampf((d - 0.3) / 0.7, 0.0, 1.0))
	env.background_color = sky
	env.fog_light_color = sky
	env.ambient_light_color = Color(0.35, 0.4, 0.6).lerp(Color(0.7, 0.72, 0.78), d)
	env.ambient_light_energy = 0.35 + d * 0.3
	var angle := (time_of_day - 0.25) * TAU
	if d > 0.0:
		sun.rotation = Vector3(-clampf(angle, 0.2, PI - 0.2), 0.6, 0)
		sun.light_color = Color(1.0, 0.6, 0.4).lerp(Color(1.0, 0.96, 0.9), d)
		sun.light_energy = 0.25 + d * 0.85
	else:
		sun.rotation = Vector3(-0.9, -0.7, 0)
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun.light_energy = 0.45 if is_full_moon() else 0.25
	var night_amt := 1.0 - clampf(d * 2.0, 0.0, 1.0)
	window_mat.emission_energy_multiplier = night_amt * 1.6
	lamp_mat.emission_energy_multiplier = 0.2 + night_amt * 4.0
	for l in lamps:
		l.light_energy = night_amt * 2.2
		l.visible = night_amt > 0.02


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
	player.dash_charges = minf(player.dash_charges + 1.0, player.MAX_DASH)
	set_slowmo(0.3, 0.8)


func on_player_died() -> void:
	game_over = true
	clear_slowmo()
	hud.show_game_over()
