class_name Player
extends CharacterBody3D
## Elijah "Sol" Marrow — the Daywalker. Fast movement, blade combos, the bite.

const U = preload("res://scripts/util.gd")
const SOL_MODULAR := "res://assets/characters/sol/sol_modular.scn"
const SolModularAnim = preload("res://scripts/sol_modular_anim.gd")
const SolMoves = preload("res://scripts/sol_moves.gd") # the sword moves as data (clips, timing, damage)
const WeaponVisual = preload("res://scripts/items/weapon_visual.gd")
const HFx = preload("res://scripts/hunt/hunt_fx.gd") # settings hooks (shake, sprint toggle)
const SolSheath = preload("res://scripts/sol_sheath.gd") # the sword on his back: draw / sheathe
const SHEATHE_AFTER := 7.0 # seconds of calm (no enemy near, no blows) before he puts the sword away
const THREAT_RANGE := 6.0 # an enemy winding up this close makes him draw
const HEAVY_HOLD := 0.4 # hold attack this long for the charged slash
const DASH_ATTACK_WINDOW := 0.3 # attack within this long after a Blood Dash ends: the thrust
const PARRY_WINDOW := 0.3 # seconds a parry press catches an enemy's wind-up
const COMBAT_RANGE := 10.0 # enemies this close put Sol in his combat stance
const ATTACK_BUFFER := 0.2 # an attack pressed this long before Sol can swing again still comes out
const ACCEL_TIME := 0.08 # seconds from standing to full speed
const STOP_TIME := 0.12 # seconds from full run to a stop
const CAM_RADIUS := 0.42 # the camera's collision sphere (keeps the lens out of trunks, posts and walls)
## The coat at runtime: matte black leather (the generated texture's metal map made it read silver).
const COAT_DARKEN := 0.35
const COAT_ROUGHNESS := 0.62
const COAT_SPECULAR := 0.3

const WALK := 7.5
const SPRINT := 13.0
const JUMP := 9.5
const GRAVITY := 26.0
const DASH_SPEED := 34.0
const DASH_TIME := 0.16
const MAX_DASH := 3.0
const BITE_RANGE := 2.6
const SUN_HEAL := 1.0 # HP/s in daylight while Hunger is low and out of combat
const GHOST_POOL := 6

# progression hooks: progression.gd / fx.gd listen to these
signal attacked(combo: int, fwd: Vector3)
signal hit_enemy(enemy: Node, dmg: float)
signal bit_enemy(enemy: Node, blood: int)
signal dashed(dir: Vector3)
signal hurt(amount: float, src)
signal parried(enemy: Node)
signal special_move(name: String) # charged / dash / sprint / finisher / parry started

var main
var max_hp := 100.0
var hp := 100.0
var hunger := 10.0
var dead := false
var dash_charges := 3.0
var dash_t := 0.0
var dash_dir := Vector3.FORWARD
var invuln_t := 0.0
var jumps_left := 2
var attack_cd := 0.0
var combo := 0
var combo_t := 0.0
var swing_t := 0.0
var lunge_t := 0.0
var bite_t := 0.0
var speed_boost_t := 0.0
var rage_t := 0.0
var burn_t := 0.0
var frenzy_t := 0.0
var shake := 0.0
var ghost_t := 0.0
var facing := PI
var sprinting := false
var prompt_text := ""
var cam_yaw := 0.0
var cam_pitch := -0.25
var since_dash := 99.0 # game seconds since the last Blood Dash started
var since_hurt := 99.0
var attack_block_until := 0 # ms; swallows the click that captures the mouse
var ghosts: Array[Node3D] = []
var ghost_mats: Array[StandardMaterial3D] = []
var ghost_tweens: Array = []
var ghost_next := 0
var bite_ready := false # a staggered enemy is in bite reach (the bite owns E / Y then)
var weapon_visual: Node3D # set_weapon_visual()
var weapon_item := {} # the equipped blade (picks the combo chain)
# sword moves (scripts/sol_moves.gd)
var move_name := "" # the move last started
var hold_t := -1.0 # seconds attack has been held since the press that started a combo (-1: not held)
var pending := {} # a strike waiting for its clip's strike frame: {t, move, target}
var lunge_speed := 9.0
var parry_t := 0.0
var parry_cd := 0.0
var finisher_t := 0.0
var attack_buffer_t := 0.0 # > 0: an attack press is waiting for the cooldown to end
var last_safe := Vector3.ZERO # the last open ground Sol stood on (fall recovery)
var has_safe := false
var safe_check_t := 0.0
var falls := 0 # times he was pulled back out of the world
const FALL_COST := 0.1 # share of max blood a fall-out recovery costs
var walk_vel := Vector3.ZERO # the ramped run velocity (acceleration / stop), before dash and lunge

var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var visual: Node3D
var coat: MeshInstance3D # primitive fallback only
var arm_pivot: Node3D # swing driver; drawn directly only by the primitive fallback
var mod_anim: SolModularAnim # clip blending for the modular model (null otherwise)
var sheath: SolSheath # the back scabbard and the draw (null on the older bodies: always in hand)
# ---- stamina (round 3, G4): light and fast. Dashes, sprinting, swings and the parry spend it; it comes
# back after STAMINA_DELAY at stamina_regen/s. Spent to zero he is EXHAUSTED: no sprint, dash or swing
# until it is back to EXHAUST_RECOVER, refilling slower. A move's cost is its sol_moves.gd "stamina".
# BLOOD RITE / PROGRESSION HOOKS: stamina_max and stamina_regen are plain fields a boon may raise, and
# stat("stamina") / stat("stamina_regen") / stat("stamina_cost") add on top (see max_stamina()).
var stamina_max := 100.0
var stamina_regen := 65.0 # per second
var stamina := 100.0
var exhausted := false
var _stamina_wait := 0.0
const STAMINA_DELAY := 0.4
const EXHAUST_DELAY := 0.9
const EXHAUST_RECOVER := 30.0
const DASH_STAMINA := 16.0
const SPRINT_STAMINA := 9.0 # per second at a sprint
# ---- Frenzy (round 3, G3): no longer free. While it runs: x frenzy_dmg_mult damage, +25% speed and no
# stamina cost, but blood drains frenzy_drain/s (never below FRENZY_FLOOR of max), he takes
# frenzy_dmg_taken more damage, and the beast neither parries nor stops to bite; every blow that lands gives back
# FRENZY_LEECH. Parries and executions feed the hunger (FRENZY_FEED), so it is earned by fighting well.
# BLOOD RITE HOOKS: frenzy_drain, frenzy_dmg_taken and frenzy_dmg_mult are fields a boon may change.
var frenzy_drain := 2.5
var frenzy_dmg_taken := 0.25
var frenzy_dmg_mult := 2.0
const FRENZY_FLOOR := 0.12
const FRENZY_LEECH := 1.5
const FRENZY_FEED := {"parry": 8.0, "finisher": 6.0}
var calm_t := 0.0 # seconds without combat (enemies near, swings, blows)
var auto_sheathe := true # false: keep the sword out (tests)
var _threat_t := 0.0
var _sprint_toggle := false
var _sprint_toggle_t := 0.0
var _sprint_latched := false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.85
	col.shape = cap
	col.position.y = 0.925
	add_child(col)
	_build_body()
	_setup_combat_input()
	pivot = Node3D.new()
	pivot.position.y = 1.8 # a touch higher: reads the street and the lights better
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 4.8
	# layer 1 is every static collider in the world: buildings, props, tree trunks and posts
	# (city.gd post_collider / box_collider). A sphere cast instead of a ray keeps the near plane
	# out of a trunk the ray only grazes.
	spring.collision_mask = 1 | 512 # + city.gd CAM_LAYER: camera-only blockers (awnings, overhangs)
	var cam_shape := SphereShape3D.new()
	cam_shape.radius = CAM_RADIUS
	spring.shape = cam_shape
	spring.add_excluded_object(get_rid())
	spring.margin = 0.12
	spring.position.x = 0.55
	pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.current = true
	spring.add_child(camera)
	visual.rotation.y = facing


func _build_body() -> void:
	visual = Node3D.new()
	add_child(visual)
	if ResourceLoader.exists(SOL_MODULAR) and _build_modular():
		return
	_build_primitive_body()


## The modular hero: skinned body, separate head, fists, sword and a spring-bone trenchcoat
## (built by tools/build_sol_modular.gd). Animated by clips (scripts/sol_modular_anim.gd).
func _build_modular() -> bool:
	var scene := load(SOL_MODULAR) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	var skel := model.get_node_or_null("Skeleton3D") as Skeleton3D
	if skel == null or skel.find_bone("RightHand") < 0 or model.find_child("Blade", true, false) == null:
		model.free()
		return false
	visual.add_child(model)
	var ma := SolModularAnim.new()
	if not ma.setup(model):
		model.queue_free()
		return false
	mod_anim = ma
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	matte_coat(model)
	hurt.connect(func(_amount, _src): mod_anim.hit())
	sheath = SolSheath.new()
	if sheath.setup(model):
		sheath.sheathe(true) # he walks in with the sword on his back
	else:
		sheath = null
	# arm_pivot keeps the swing math alive; the clips draw the actual swing
	arm_pivot = Node3D.new()
	visual.add_child(arm_pivot)
	return true


## The coat as darker, matte black leather: no metal map (it read as chrome under the rim light),
## albedo x0.35, roughness ~0.6, low specular. Static so the menu's Sol can use it too.
static func matte_coat(model: Node) -> void:
	var coat_mi := model.find_child("Coat", true, false) as MeshInstance3D
	if coat_mi == null or coat_mi.mesh == null:
		return
	var base := coat_mi.mesh.surface_get_material(0) as StandardMaterial3D
	if base == null:
		return
	var m := base.duplicate() as StandardMaterial3D
	m.metallic = 0.0
	m.metallic_texture = null
	m.metallic_specular = COAT_SPECULAR
	m.roughness = COAT_ROUGHNESS
	m.roughness_texture = null
	m.albedo_color = Color(COAT_DARKEN, COAT_DARKEN, COAT_DARKEN * 0.96)
	coat_mi.material_override = m


## Primitive-built fallback body (used if the generated model is missing).
func _build_primitive_body() -> void:
	var black := U.mat(Color(0.035, 0.035, 0.04), 0.6)
	var leather := U.mat(Color(0.025, 0.022, 0.022), 0.25, 0.2)
	var skin := U.mat(Color(0.33, 0.21, 0.14), 0.55)
	var hair := U.mat(Color(0.06, 0.04, 0.03), 0.85)
	var shades := U.mat(Color(0.01, 0.01, 0.01), 0.05, 0.9)
	# slim legs and torso
	U.part(visual, U.capsule(0.1, 0.95), black, Vector3(-0.12, 0.47, 0))
	U.part(visual, U.capsule(0.1, 0.95), black, Vector3(0.12, 0.47, 0))
	U.part(visual, U.capsule(0.21, 0.85), black, Vector3(0, 1.22, 0))
	# long black leather trenchcoat
	coat = U.part(visual, U.cyl(0.26, 0.46, 1.3), leather, Vector3(0, 0.98, -0.02))
	U.part(visual, U.cyl(0.19, 0.27, 0.2), leather, Vector3(0, 1.6, 0))
	# head
	U.part(visual, U.cyl(0.065, 0.075, 0.14), skin, Vector3(0, 1.67, 0))
	U.part(visual, U.sphere(0.155), skin, Vector3(0, 1.83, 0.01), Vector3.ZERO, Vector3(0.95, 1.12, 1.0))
	U.part(visual, U.box(Vector3(0.27, 0.055, 0.03)), shades, Vector3(0, 1.86, 0.15))
	U.part(visual, U.sphere(0.16), hair, Vector3(0, 1.89, -0.02), Vector3.ZERO, Vector3(1.02, 0.72, 1.02))
	# dreadlocks
	var loc_mesh := U.cyl(0.022, 0.028, 0.5)
	for i in range(15):
		var a := lerpf(-2.3, 2.3, i / 14.0)
		var pos := Vector3(sin(a) * 0.15, 1.66, -cos(a) * 0.14)
		U.part(visual, loc_mesh, hair, pos, Vector3(0.22 * cos(a), 0, 0.2 * sin(a)))
	# arms and silver blade
	U.part(visual, U.capsule(0.07, 0.72), leather, Vector3(-0.3, 1.2, 0), Vector3(0, 0, 0.1))
	arm_pivot = Node3D.new()
	arm_pivot.position = Vector3(0.3, 1.52, 0)
	visual.add_child(arm_pivot)
	U.part(arm_pivot, U.capsule(0.07, 0.72), leather, Vector3(0, -0.3, 0))
	U.part(arm_pivot, U.box(Vector3(0.035, 0.05, 1.05)), U.mat(Color(0.85, 0.88, 0.92), 0.12, 1.0), Vector3(0, -0.62, 0.5))
	U.part(arm_pivot, U.box(Vector3(0.14, 0.05, 0.05)), black, Vector3(0, -0.62, -0.02))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		block_attack()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		if lock_target != null:
			lock_flick(mm.relative.x) # locked: a mouse flick switches targets
			return
		cam_yaw -= mm.relative.x * Settings.mouse_look()
		cam_pitch = clampf(cam_pitch - mm.relative.y * Settings.mouse_look() * Settings.y_sign(), -1.1, 0.35)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if dead:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	_timers(delta)
	_sheath_tick(delta)
	var day: bool = main.is_day()

	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(inp.x, 0.0, inp.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var sprint_held := Input.is_action_pressed("sprint")
	if _sprint_toggle_t <= 0.0:
		_sprint_toggle_t = 1.0
		_sprint_toggle = bool(HFx.opt("toggle_sprint", false)) # settings: tap to toggle (polled 1/s)
	_sprint_toggle_t -= delta
	if _sprint_toggle:
		if Input.is_action_just_pressed("sprint"):
			_sprint_latched = not _sprint_latched
		if dir.length() <= 0.1 or exhausted:
			_sprint_latched = false # stopping (or running out of breath) ends the run
		sprint_held = _sprint_latched
	sprinting = sprint_held and dir.length() > 0.1 and (not exhausted or frenzy_t > 0.0)
	if sprinting and frenzy_t <= 0.0 and walk_vel.length() > WALK:
		_drain_stamina(SPRINT_STAMINA * delta, 0.25)
	_lock_tick(delta)
	var spd := SPRINT if sprinting else WALK
	if lock_target != null and not sprinting:
		spd = WALK * LOCK_STRAFE # locked on: a measured strafe (sprint breaks into a run)
	if speed_boost_t > 0.0:
		spd *= 1.3
	if frenzy_t > 0.0:
		spd *= 1.25
	spd *= 1.0 + stat("speed") # PROGRESSION HOOK

	# Blood Dash (recharges faster in sunlight)
	dash_charges = minf(dash_charges + delta / (0.7 if day else 1.1) * (1.0 + stat("dash_rate")), MAX_DASH) # PROGRESSION HOOK
	if Input.is_action_just_pressed("dash") and dash_charges >= 1.0 and bite_t <= 0.0 and spend_stamina(DASH_STAMINA):
		dash_charges -= 1.0
		dash_t = DASH_TIME
		since_dash = 0.0
		invuln_t = maxf(invuln_t, DASH_TIME + 0.12)
		dash_dir = dir.normalized() if dir.length() > 0.1 else _forward()
		collision_mask = 1 # phase through enemies
		dashed.emit(dash_dir)

	# jump / double jump
	if is_on_floor():
		jumps_left = 2
	else:
		velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("jump") and jumps_left > 0 and bite_t <= 0.0:
		velocity.y = JUMP if jumps_left == 2 else JUMP * 0.85
		jumps_left -= 1

	# the run ramps up over ACCEL_TIME and down over STOP_TIME (dash, lunge and the bite stay instant)
	var want := dir * spd
	if swing_t > 0.0:
		want *= 0.3
	var ramp := spd / ACCEL_TIME if want.length() >= walk_vel.length() - 0.01 else maxf(walk_vel.length(), WALK) / STOP_TIME
	walk_vel = walk_vel.move_toward(want, ramp * delta)
	var hv := Vector3.ZERO
	if dash_t > 0.0:
		hv = dash_dir * DASH_SPEED
		velocity.y = maxf(velocity.y, 0.0)
		walk_vel = want # out of a dash at full stride
	elif bite_t > 0.0:
		hv = Vector3.ZERO
		walk_vel = Vector3.ZERO
	elif finisher_t > 0.0:
		hv = _forward() * lunge_speed if lunge_t > 0.0 else Vector3.ZERO # rooted in the execution
		walk_vel = Vector3.ZERO
	else:
		hv = walk_vel
		if lunge_t > 0.0:
			hv += _forward() * lunge_speed
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()
	_track_safe_ground(delta)

	var strafing := false
	if dash_t > 0.0:
		facing = atan2(dash_dir.x, dash_dir.z)
	elif lock_target != null and not sprinting and bite_t <= 0.0:
		var tl: Vector3 = lock_target.global_position - global_position
		if Vector2(tl.x, tl.z).length() > 0.3:
			facing = atan2(tl.x, tl.z) # locked on: he keeps his chest on the target and strafes
		strafing = dir.length() > 0.1
	elif dir.length() > 0.1 and swing_t <= 0.0 and bite_t <= 0.0:
		facing = atan2(dir.x, dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, facing, 16.0 * delta)
	if mod_anim != null:
		mod_anim.set_strafe(atan2(dir.x, dir.z) - facing if strafing else 0.0, strafing and swing_t <= 0.0, delta)

	# actions
	_combat_tick(delta)
	# input buffer: a press up to ATTACK_BUFFER s early (mid-swing, mid-bite) comes out the moment Sol can
	if Input.is_action_just_pressed("attack") and Time.get_ticks_msec() >= attack_block_until:
		attack_buffer_t = ATTACK_BUFFER
	if attack_buffer_t > 0.0:
		if attack_cd <= 0.0 and bite_t <= 0.0 and finisher_t <= 0.0 and (not exhausted or frenzy_t > 0.0) and _sword_ready():
			attack_buffer_t = 0.0
			_attack_pressed()
			if hold_t >= 0.0 and not Input.is_action_pressed("attack"):
				hold_t = -1.0 # a buffered tap, not a hold
		elif sheath == null or not sheath.busy():
			attack_buffer_t = maxf(attack_buffer_t - delta, 0.0) # (the draw holds the press until the grab)
	if Input.is_action_just_pressed("parry") and parry_cd <= 0.0 and bite_t <= 0.0 and finisher_t <= 0.0 and frenzy_t <= 0.0 \
			and spend_stamina(SolMoves.stamina_cost("parry")):
		draw_sword()
		_parry()
	var bite_target = _nearest_enemy(BITE_RANGE, 1)
	bite_ready = bite_target != null
	if Input.is_action_just_pressed("bite") and bite_t <= 0.0 and bite_target != null and frenzy_t <= 0.0:
		_bite(bite_target)
	var near_lair: bool = global_position.distance_to(main.lair_pos) < 3.5
	if Input.is_action_just_pressed("drink") and near_lair:
		main.drink_from_lair()

	prompt_text = ""
	if bite_target != null:
		prompt_text = ("[Y]" if main.hud.using_pad else "[E]") + "  BITE"
	elif near_lair:
		if main.lair_stock > 0:
			prompt_text = ("[LB]" if main.hud.using_pad else "[F]") + "  DRINK BAGGED BLOOD  (%d left)" % main.lair_stock
		else:
			prompt_text = "BLOOD BANK EMPTY  —  restocks at sunrise"


# ---------------------------------------------------------------- the sword on his back (sol_sheath.gd)
## Can a swing start now? Sheathed: start the draw and say no (the buffered press fires on the grab).
func _sword_ready() -> bool:
	if sheath == null:
		return true
	if sheath.busy():
		return false
	if not sheath.drawn:
		sheath.draw()
		calm_t = 0.0
		return false
	return true


## Pull the sword if it is on his back (attack, parry, lock-on, an enemy winding up close by).
func draw_sword() -> void:
	calm_t = 0.0
	if sheath != null and (not sheath.drawn or sheath.phase == "stow"):
		sheath.draw()


## True while the sword rides in the scabbard (smoke test, HUD).
func sword_on_back() -> bool:
	return sheath != null and sheath.on_back()


func sword_in_hand() -> bool:
	return sheath == null or sheath.in_hand()


func _sheath_tick(delta: float) -> void:
	if sheath == null:
		return
	sheath.tick(delta)
	calm_t += delta
	if swing_t > 0.0 or since_hurt < 0.5 or finisher_t > 0.0:
		calm_t = 0.0
	_threat_t -= delta
	if _threat_t <= 0.0:
		_threat_t = 0.15
		var near := false
		for e in main.enemies_root.get_children():
			if e.get("dead") != false:
				continue
			var d2: float = e.global_position.distance_squared_to(global_position)
			if d2 > COMBAT_RANGE * COMBAT_RANGE:
				continue
			near = true
			if d2 < THREAT_RANGE * THREAT_RANGE and _winding_up(e):
				draw_sword()
				break
		if near:
			calm_t = 0.0
	if auto_sheathe and calm_t >= SHEATHE_AFTER and sheath.drawn and sheath.phase == "" and swing_t <= 0.0 and pending.is_empty() and not dead:
		sheath.sheathe()


static func _winding_up(e) -> bool:
	var w = e.get("windup_t")
	if w != null and float(w) > 0.0:
		return true
	var sp = e.get("special")
	if sp is String and (sp.ends_with("_windup") or sp == "claw"):
		return true
	return e.get("state") == "windup" # a boss


## QA2 #5: remember the last open ground Sol stood on; if he ever drops out of the world (a seam,
## a spawn inside a solid), put him back there (or on the nearest road) for a small blood cost.
func _track_safe_ground(delta: float) -> void:
	if main.below_world(global_position):
		recover_from_fall()
		return
	safe_check_t -= delta
	if safe_check_t <= 0.0 and is_on_floor():
		safe_check_t = 0.5
		if main.spot_clear(global_position):
			last_safe = global_position
			has_safe = true


func recover_from_fall() -> void:
	var to: Vector3 = main.safe_ground(last_safe if has_safe else global_position)
	global_position = to + Vector3(0, 0.3, 0)
	velocity = Vector3.ZERO
	walk_vel = Vector3.ZERO
	dash_t = 0.0
	collision_mask = 1 | 4
	hp = maxf(hp - max_hp * FALL_COST, 1.0)
	invuln_t = maxf(invuln_t, 1.0)
	shake = maxf(shake, 0.3)
	falls += 1
	main.hud.popup("You claw back out of the dark")


## QA2 #8: the lens never sits inside a body. A street enemy the camera is inside is hidden for
## those frames; a boss (too big to hide) pulls the camera arm in short of its body instead.
var cam_hidden := {} # enemy -> true while its visual is hidden from the lens


func _camera_obstruction() -> void:
	if main == null or main.enemies_root == null:
		return
	var o: Vector3 = spring.global_position
	var dirv: Vector3 = spring.global_transform.basis.z.normalized()
	var want: float = spring.spring_length
	var cp: Vector3 = camera.global_position
	for e in main.enemies_root.get_children():
		if not (e is Node3D) or e.get("dead") == true:
			continue
		var ep: Vector3 = e.global_position
		if ep.distance_squared_to(o) > 81.0:
			continue
		if e.has_method("parry_open"): # a boss
			var t := _ray_cylinder(o, dirv, ep, float(e.get("body_radius")) + 0.4, float(e.get("body_height")) + 0.3, want)
			if t >= 0.0:
				want = minf(want, maxf(t - 0.15, 0.9))
		else:
			var v = e.get("visual")
			if v is Node3D:
				var d := Vector2(cp.x - ep.x, cp.z - ep.z).length()
				if d < 0.8 and cp.y > ep.y - 0.3 and cp.y < ep.y + 2.7:
					_cam_hide(e, true)
	want = minf(want, _cam_clear_length(o, dirv, want))
	if want < spring.spring_length:
		spring.spring_length = want
	# give back the ones the lens has left
	cp = o + dirv * minf(spring.spring_length, spring.get_hit_length())
	for e in cam_hidden.keys():
		if not is_instance_valid(e):
			cam_hidden.erase(e)
			continue
		var ep: Vector3 = e.global_position
		var d := Vector2(cp.x - ep.x, cp.z - ep.z).length()
		if e.get("dead") == true or d >= 0.9 or cp.y <= ep.y - 0.4 or cp.y >= ep.y + 2.8:
			_cam_hide(e, false)


func _cam_hide(e, on: bool) -> void:
	var v = e.get("visual")
	if v is Node3D:
		v.visible = not on
	var bar = e.get("hp_bar") # its own visibility belongs to enemy.gd; fade it instead
	if bar is GeometryInstance3D:
		bar.transparency = 1.0 if on else 0.0
	if on:
		cam_hidden[e] = true
	else:
		cam_hidden.erase(e)


## QA2 #8: how far out the camera can sit along the arm with CAM_CLEAR of open air round the lens
## (the sphere cast only guards the line; posts, gallery columns and walls just beside it still
## filled the frame). Binary search, only when the full length is crowded.
const CAM_CLEAR := 0.6
var _cam_probe: PhysicsShapeQueryParameters3D


func _cam_crowded(pt: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var above: float = pt.y - main.ground_y(pt.x, pt.z)
	var r := clampf(above - 0.15, 0.25, CAM_CLEAR) # never "crowded" by the street under it
	(_cam_probe.shape as SphereShape3D).radius = r
	_cam_probe.transform = Transform3D(Basis(), pt)
	return not space.intersect_shape(_cam_probe, 1).is_empty()


func _cam_clear_length(o: Vector3, dirv: Vector3, length: float) -> float:
	if not is_inside_tree() or length <= 1.0:
		return length
	var space := get_world_3d().direct_space_state
	if _cam_probe == null:
		_cam_probe = PhysicsShapeQueryParameters3D.new()
		_cam_probe.shape = SphereShape3D.new()
		_cam_probe.collision_mask = 1 | 512
		_cam_probe.exclude = [get_rid()]
	if not _cam_crowded(o + dirv * length, space):
		return length
	var lo := 1.0
	var hi := length
	for i in 5:
		var mid := (lo + hi) * 0.5
		if _cam_crowded(o + dirv * mid, space):
			hi = mid
		else:
			lo = mid
	return lo


## Distance along the ray (o, unit dir) to where it enters an upright cylinder at base c, or -1.
static func _ray_cylinder(o: Vector3, dir: Vector3, c: Vector3, r: float, h: float, max_t: float) -> float:
	var f := Vector2(o.x - c.x, o.z - c.z)
	var d := Vector2(dir.x, dir.z)
	var a := d.dot(d)
	var cc := f.dot(f) - r * r
	if cc <= 0.0:
		return 0.0 # the pivot itself is inside (pressed against it)
	if a < 1e-5:
		return -1.0
	var b := 2.0 * f.dot(d)
	var disc := b * b - 4.0 * a * cc
	if disc < 0.0:
		return -1.0
	var t := (-b - sqrt(disc)) / (2.0 * a)
	if t < 0.0 or t > max_t:
		return -1.0
	var y := o.y + dir.y * t
	if y < c.y - 0.2 or y > c.y + h:
		return -1.0
	return t


## Ignore attack input briefly (the click that starts the game or grabs the mouse).
func block_attack() -> void:
	attack_block_until = Time.get_ticks_msec() + 200


## True if Sol started a Blood Dash within the last `window` game seconds.
func dashed_recently(window: float = 0.22) -> bool:
	return since_dash <= window


func _forward() -> Vector3:
	return Vector3(sin(facing), 0.0, cos(facing))


func _timers(delta: float) -> void:
	if dash_t > 0.0:
		dash_t -= delta
		if dash_t <= 0.0:
			collision_mask = 1 | 4
	invuln_t = maxf(invuln_t - delta, 0.0)
	since_dash += delta
	since_hurt += delta
	attack_cd = maxf(attack_cd - delta, 0.0)
	combo_t = maxf(combo_t - delta, 0.0)
	swing_t = maxf(swing_t - delta, 0.0)
	lunge_t = maxf(lunge_t - delta, 0.0)
	bite_t = maxf(bite_t - delta, 0.0)
	speed_boost_t = maxf(speed_boost_t - delta, 0.0)
	rage_t = maxf(rage_t - delta, 0.0)
	if burn_t > 0.0:
		burn_t -= delta
		hp -= 3.0 * delta
	_stamina_tick(delta)
	if frenzy_t > 0.0:
		frenzy_t -= delta
		# the cost: blood drains while the beast is loose (it never kills on its own)
		var floor_hp := max_hp * FRENZY_FLOOR
		if hp > floor_hp:
			hp = maxf(hp - frenzy_drain * delta, floor_hp)
		if frenzy_t <= 0.0:
			hunger = 55.0
			main.hud.popup("The frenzy fades...")
	else:
		hunger = maxf(hunger - 0.6 * delta, 0.0)
	# Daywalker: stay human and the sun slowly heals you (out of combat)
	if hunger < 30.0 and main.daylight() > 0.3 and since_hurt > 4.0:
		hp = minf(hp + SUN_HEAL * (1.0 + stat("sun_heal")) * delta, max_hp) # PROGRESSION HOOK
	if hp <= 0.0:
		_die()


func damage_mult() -> float:
	var m := 1.0
	if rage_t > 0.0:
		m *= 1.5
	if hunger >= 60.0:
		m *= 1.25
	if frenzy_t > 0.0:
		m *= frenzy_dmg_mult
	# PROGRESSION HOOK: rank, Vows and charms
	m *= 1.0 + stat("dmg")
	if main != null and not main.is_day():
		m *= 1.0 + stat("night_dmg")
	return m


# ---------------------------------------------------------------- progression hooks
## A stat from progression.gd (rank + Vows + equipment); 0 when there is none.
func stat(key: String) -> float:
	if main == null or main.get("progression") == null:
		return 0.0
	return main.progression.stat(key)


## The equipped blade's numbers: {dmg, spd, reach}. Sol's own silver blade is 14 / 1.0 / 0.
func weapon_stats() -> Dictionary:
	if main == null or main.get("progression") == null:
		return {"dmg": 14.0, "spd": 1.0, "reach": 0.0}
	return main.progression.weapon_stats()


## Extra damage against a kind of enemy (silver vs the Pack, sun-steel vs the Court).
func _vs_mult(e) -> float:
	return 1.0 + (stat("vs_vamp") if e.kind == 0 else stat("vs_wolf"))


func _bite_mult() -> float:
	return 1.0 + stat("bite_heal")


## Show the equipped weapon in Sol's hand. Hides the default blade mesh and puts the
## item's blade (items/weapon_visual.gd — swap in a real sword model there) in its place.
func set_weapon_visual(item: Dictionary) -> void:
	weapon_item = item
	if weapon_visual != null and is_instance_valid(weapon_visual):
		weapon_visual.queue_free()
		weapon_visual = null
	# modular model: "Blade" is the grip frame in the right fist; swap the sword scene under it
	var grip: Node = visual.find_child("Blade", true, false) if visual != null else null
	if sheath != null:
		grip = sheath.carrier # in the hand or on his back: the swap goes wherever the sword is
	if grip != null and not grip is MeshInstance3D:
		for c in grip.get_children():
			(c as Node3D).visible = false
		weapon_visual = preload("res://scripts/items/weapon_visual.gd").build(item, 0.014, true)
		grip.add_child(weapon_visual)
		if sheath != null:
			sheath.use_item(item) # its mount (back, belt: sol_sheath.gd MOUNTS) and a scabbard that fits it
		return
	var blade := _find_blade_mesh()
	if blade == null:
		return
	var size: Vector3 = (blade.mesh as BoxMesh).size
	blade.visible = false
	weapon_visual = preload("res://scripts/items/weapon_visual.gd").build(item, size.x)
	blade.get_parent().add_child(weapon_visual)
	# the default blade box is centred on its length; the new one starts at the hilt
	weapon_visual.transform = blade.transform
	weapon_visual.position = blade.position - blade.transform.basis.z * (size.z * 0.5)


## The default blade: a node tagged "blade" / named "Blade" if the body provides one,
## otherwise the long thin box mesh in Sol's hand.
func _find_blade_mesh() -> MeshInstance3D:
	if visual == null:
		return null
	for n in visual.find_children("*", "MeshInstance3D", true, false):
		if n.name == "Blade" or n.has_meta("blade"):
			return n
	for n in visual.find_children("*", "MeshInstance3D", true, false):
		if n.get_parent() == weapon_visual or (weapon_visual != null and weapon_visual.is_ancestor_of(n)):
			continue
		if n.mesh is BoxMesh and (n.mesh as BoxMesh).size.z > 0.9 and (n.mesh as BoxMesh).size.x < 0.06:
			return n
	return null


## staggered: 1 = only staggered enemies, -1 = skip staggered ones, 0 = any.
func _nearest_enemy(max_dist: float, staggered: int):
	var best = null
	var best_d := max_dist
	for e in main.enemies_root.get_children():
		if e.dead or (staggered == 1 and not e.staggered) or (staggered == -1 and e.staggered):
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## Who a swing turns to: the lock-on target when it is in reach, else the nearest fighting enemy.
func _swing_target():
	if lock_target != null and _lock_valid(lock_target) and lock_target.global_position.distance_to(global_position) < 6.0 \
			and lock_target.get("staggered") != true:
		return lock_target
	return _nearest_enemy(5.0, -1)


func _attack() -> void:
	combo = combo + 1 if (combo_t > 0.0 and combo < 3) else 1
	combo_t = 0.7
	move_name = SolMoves.combo_step(WeaponVisual.combo_for(weapon_item), combo)
	var step := SolMoves.move(move_name)
	spend_stamina(SolMoves.stamina_cost(move_name))
	attack_cd = 0.22 if combo < 3 else 0.4
	swing_t = 0.22
	_lunge(float(step.lunge), 0.08)
	# soft-lock prefers fighting enemies, so you don't kill the one you meant to bite
	var target = _swing_target()
	if target == null:
		target = _nearest_enemy(5.0, 1)
	if target != null:
		var tt: Vector3 = target.global_position - global_position
		facing = atan2(tt.x, tt.z)
		visual.rotation.y = facing
	var fwd := _forward()
	# PROGRESSION HOOK: the equipped blade sets damage, swing speed and reach
	var w := weapon_stats()
	attack_cd /= maxf(w.spd, 0.3)
	attacked.emit(combo, fwd)
	Audio.play("sword_swing", -2.0 if combo < 3 else 1.0, 0.1) # AUDIO HOOK
	# the damage waits for the clip's strike frame (~0.1 s), like the special moves
	var delay := (float(step.hit) - float(step.from)) / (float(step.speed) * maxf(w.spd, 0.3))
	if mod_anim != null:
		delay = mod_anim.play_move(step, w.spd, combo == 2)
	_flush_pending() # a strike still in flight from the last press lands now, not never
	pending = {"t": delay, "move": move_name, "target": target, "combo": combo}


## The combo's strike frame: damage, hit-stop, shake and rumble for step `n` (1..3) of the chain.
func _combo_strike(name: String, n: int, target) -> void:
	var m := SolMoves.move(name)
	var fwd := _forward()
	var w := weapon_stats() # PROGRESSION HOOK: blade damage and reach
	var dmg: float = w.dmg * (1.0 if n < 3 else 2.0 * (1.0 + stat("finisher"))) * damage_mult()
	var reach: float = (2.7 if n < 3 else 3.3) + w.reach
	var hit := false
	for e in main.enemies_root.get_children():
		if e.dead or (e.staggered and e != target):
			continue # a staggered enemy only dies to a swing aimed at it
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < reach and (d < 0.9 or fwd.dot(to / d) > 0.3):
			var hd: float = dmg * _vs_mult(e)
			e.take_hit(hd, to.normalized() if d > 0.01 else fwd)
			hit_enemy.emit(e, hd)
			_on_blow_landed()
			Audio.play_at("sword_hit", e.global_position, 0.0 if n < 3 else 3.0) # AUDIO HOOK
			hit = true
	if hit:
		shake = maxf(shake, float(m.shake))
		main.rumble(0.4, 0.0 if n < 3 else 0.5, 0.08)
		main.set_slowmo(0.06, float(m.stop)) # hit-stop


## Land a waiting strike right away (a new move is replacing it).
func _flush_pending() -> void:
	if pending.is_empty():
		return
	var p := pending
	pending = {}
	_resolve_pending(p)


func _resolve_pending(p: Dictionary) -> void:
	if p.has("combo"):
		_combo_strike(p.move, int(p.combo), p.target)
	else:
		_strike(p.move, p.target)


# ---------------------------------------------------------------- sword moves (sol_moves.gd)
## The combat bindings that live with the moves they drive (like atmosphere.gd's rain toggle):
##   parry    C / mouse side button, L3 on a pad (sprint keeps LT)
##   lock_on  Q / middle mouse, R3 on a pad (the soulslike layout). Q used to be a second Blood Dash
##            key: the dash keeps right mouse and gains K; on a pad it keeps B, and RB (also a dash
##            before) now takes quick-use slot 2, which R3 had.
func _setup_combat_input() -> void:
	if InputMap.has_action("parry"):
		return
	InputMap.add_action("parry", 0.25)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_C
	InputMap.action_add_event("parry", k)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	InputMap.action_add_event("parry", mb)
	var pb := InputEventJoypadButton.new()
	pb.button_index = JOY_BUTTON_LEFT_STICK
	InputMap.action_add_event("parry", pb)
	if InputMap.has_action("sprint"):
		for ev in InputMap.action_get_events("sprint"):
			if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_LEFT_STICK:
				InputMap.action_erase_event("sprint", ev) # sprint is LT on a pad now
	if not InputMap.has_action("lock_on"):
		InputMap.add_action("lock_on", 0.25)
		var lk := InputEventKey.new()
		lk.physical_keycode = KEY_Q
		InputMap.action_add_event("lock_on", lk)
		var lm := InputEventMouseButton.new()
		lm.button_index = MOUSE_BUTTON_MIDDLE
		InputMap.action_add_event("lock_on", lm)
		var lp := InputEventJoypadButton.new()
		lp.button_index = JOY_BUTTON_RIGHT_STICK
		lp.device = -1
		InputMap.action_add_event("lock_on", lp)
	if InputMap.has_action("dash"):
		for ev in InputMap.action_get_events("dash"):
			if (ev is InputEventKey and ev.physical_keycode == KEY_Q) or (ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_RIGHT_SHOULDER):
				InputMap.action_erase_event("dash", ev)
		var dk := InputEventKey.new()
		dk.physical_keycode = KEY_K
		InputMap.action_add_event("dash", dk)
	if InputMap.has_action("quick_2"):
		for ev in InputMap.action_get_events("quick_2"):
			if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_RIGHT_STICK:
				InputMap.action_erase_event("quick_2", ev)
		var qb := InputEventJoypadButton.new()
		qb.button_index = JOY_BUTTON_RIGHT_SHOULDER
		qb.device = -1
		InputMap.action_add_event("quick_2", qb)


# ---------------------------------------------------------------- lock-on
## Q / middle mouse / R3 / the touch LOCK button toggles it. Locked: the camera frames Sol and the
## target, he faces it and strafes (sol_strafe.gd turns the legs), attacks go to it, and a flick of
## the mouse or right stick (a swipe on touch) switches to the next target on that side. It breaks on
## distance, on the target's death, or after LOCK_LOS_GRACE s without line of sight.
const LOCK_RANGE := 18.0
const LOCK_BREAK := 24.0
const LOCK_LOS_GRACE := 1.0
const LOCK_STRAFE := 0.8 # walk speed share while strafing locked on
const FLICK_PX := 70.0 # mouse pixels in a quick flick that switch the target
var lock_target = null
var lock_reticle: MeshInstance3D
var locks := 0 # targets acquired (smoke test)
var _lock_los_t := 0.0
var _lock_check_t := 0.0
var _flick_x := 0.0
var _flick_cd := 0.0
var _stick_armed := true


func _lock_tick(delta: float) -> void:
	if Input.is_action_just_pressed("lock_on"):
		toggle_lock()
	_flick_cd = maxf(_flick_cd - delta, 0.0)
	_flick_x = move_toward(_flick_x, 0.0, 400.0 * delta) # a slow drag never adds up to a flick
	if lock_target == null:
		return
	if not _lock_valid(lock_target):
		release_lock()
		return
	var d: float = lock_target.global_position.distance_to(global_position)
	if d > LOCK_BREAK:
		release_lock()
		return
	_lock_check_t -= delta
	if _lock_check_t <= 0.0:
		_lock_check_t = 0.15
		if _sees(lock_target):
			_lock_los_t = 0.0
		else:
			_lock_los_t += 0.15
			if _lock_los_t >= LOCK_LOS_GRACE:
				release_lock()
				return
	# right stick flick
	var lx := Input.get_axis("look_left", "look_right")
	if _stick_armed and absf(lx) > 0.75:
		_stick_armed = false
		switch_lock(signf(lx))
	elif absf(lx) < 0.3:
		_stick_armed = true


func toggle_lock() -> void:
	if lock_target != null:
		release_lock()
		return
	var t = _pick_lock(0.0)
	if t == null:
		cam_yaw = facing + PI # nothing to lock: recentre the camera behind him
		return
	_set_lock(t)


func _set_lock(t) -> void:
	lock_target = t
	locks += 1
	_lock_los_t = 0.0
	_lock_check_t = 0.0
	draw_sword()
	if lock_reticle == null:
		_build_reticle()
	lock_reticle.visible = true


func release_lock() -> void:
	lock_target = null
	if lock_reticle != null:
		lock_reticle.visible = false


## Mouse x (or a touch swipe) while locked: a quick flick past FLICK_PX switches to that side.
func lock_flick(dx: float) -> void:
	_flick_x += dx
	if absf(_flick_x) >= FLICK_PX and _flick_cd <= 0.0:
		switch_lock(signf(_flick_x))
		_flick_x = 0.0
		_flick_cd = 0.3


## The next target to the right (side 1) or left (-1) of the current one on screen.
func switch_lock(side: float) -> void:
	if lock_target == null:
		return
	var t = _pick_lock(side)
	if t != null:
		lock_target = t
		_lock_los_t = 0.0


func _lock_valid(e) -> bool:
	if e == null or not is_instance_valid(e) or not e.is_inside_tree() or e.get("dead") != false:
		return false
	return e.get("dormant") != true


## side 0: the best new target (near the screen centre, close); +-1: the nearest on that side of the
## current target in screen x.
func _pick_lock(side: float):
	if main == null or main.enemies_root == null:
		return null
	var cam_fwd := -camera.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized() if cam_fwd.length() > 0.01 else _forward()
	var cur_x := 0.0
	if side != 0.0 and lock_target != null:
		cur_x = camera.unproject_position(_lock_point(lock_target)).x
	var best = null
	var best_s := INF
	for e in main.enemies_root.get_children():
		if not _lock_valid(e) or e == lock_target or not (e is Node3D):
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > LOCK_RANGE:
			continue
		var ang := acos(clampf(cam_fwd.dot(to / maxf(d, 0.01)), -1.0, 1.0))
		var s := 0.0
		if side == 0.0:
			if ang > deg_to_rad(80.0) and d > 4.0:
				continue # behind the camera and not right on top of him
			s = ang * 6.0 + d * 0.25
		else:
			if camera.is_position_behind(_lock_point(e)):
				continue
			var dx: float = (camera.unproject_position(_lock_point(e)).x - cur_x) * side
			if dx <= 4.0:
				continue
			s = dx + d * 4.0
		if s < best_s and _sees(e):
			best_s = s
			best = e
	return best


## Where the camera and the reticle look on a target: chest height (bosses: their own body height).
func _lock_point(e) -> Vector3:
	var h := 1.25
	var bh = e.get("body_height")
	if bh != null:
		h = float(bh) * 0.62
	elif e.get("model_name") == "werewolf":
		h = 1.7
	return e.global_position + Vector3(0, h, 0)


## Line of sight from Sol's chest to the target's chest, against the world (layer 1).
func _sees(e) -> bool:
	if not is_inside_tree():
		return true
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.4, 0), _lock_point(e), 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _build_reticle() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, blend_mix;
uniform vec4 col : source_color = vec4(0.95, 0.78, 0.45, 0.95);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = abs(UV - 0.5) * 2.0;
	float d = p.x + p.y; // a diamond
	float ring = smoothstep(0.62, 0.7, d) * (1.0 - smoothstep(0.86, 0.94, d));
	float dot_ = 1.0 - smoothstep(0.16, 0.24, d);
	float a = max(ring, dot_ * 0.9);
	if (a < 0.02) discard;
	ALBEDO = mix(col.rgb, vec3(0.8, 0.05, 0.06), dot_);
	ALPHA = a * col.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = 4
	var q := QuadMesh.new()
	q.size = Vector2(0.26, 0.26)
	lock_reticle = MeshInstance3D.new()
	lock_reticle.name = "LockReticle"
	lock_reticle.mesh = q
	lock_reticle.material_override = m
	lock_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lock_reticle.top_level = true
	lock_reticle.extra_cull_margin = 2.0
	add_child(lock_reticle)


## Attack pressed: an execution on a staggered enemy in reach, the thrust out of a Blood Dash, the
## running slash while sprinting, else the next step of the combo (held on, it becomes the charged slash).
func _attack_pressed() -> void:
	hold_t = -1.0
	var fin = _finisher_target()
	if fin != null:
		_finisher(fin)
	elif dash_t > 0.0 or dashed_recently(DASH_TIME + DASH_ATTACK_WINDOW):
		_special("dash")
	elif sprinting and Vector2(velocity.x, velocity.z).length() > WALK + 1.0:
		_special("sprint")
	else:
		_attack()
		hold_t = 0.0


func _lunge(dist: float, t: float) -> void:
	lunge_t = t
	lunge_speed = dist / maxf(t, 0.02)


## Heavy-blade family swords (the cleavers) swing the heavy combo.
func _combo_chain() -> String:
	return WeaponVisual.combo_for(weapon_item)


## The charged / dash / sprint moves: play the clip now, strike on its strike frame.
func _special(name: String) -> void:
	var m := SolMoves.move(name)
	spend_stamina(SolMoves.stamina_cost(name))
	move_name = name
	combo = 0
	combo_t = 0.0
	hold_t = -1.0
	var target = _swing_target()
	if target != null:
		var tt: Vector3 = target.global_position - global_position
		facing = atan2(tt.x, tt.z)
		visual.rotation.y = facing
	# PROGRESSION HOOK: the blade's speed scales the move like the combo
	var w := weapon_stats()
	attack_cd = float(m.cd) / maxf(w.spd, 0.3)
	swing_t = float(m.lock)
	var delay := (float(m.hit) - float(m.from)) / (float(m.speed) * maxf(w.spd, 0.3))
	if mod_anim != null:
		delay = mod_anim.play_move(m, w.spd)
	_lunge(float(m.lunge), maxf(delay, 0.1))
	if name == "charged" and pending.has("combo"):
		pending = {} # the held press's light strike became this charge: one heavy hit (QA2 #10)
	_flush_pending()
	pending = {"t": delay, "move": name, "target": target}
	attacked.emit(3 if name == "charged" else 1, _forward())
	special_move.emit(name)
	Audio.play("sword_swing", 1.0 if name == "charged" else -1.0, 0.1) # AUDIO HOOK


## A staggered enemy close in front, nearer than any enemy still fighting: the execution target.
func _finisher_target():
	var st = _nearest_enemy(3.0, 1)
	if st == null:
		return null
	var to: Vector3 = st.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var fighter = _nearest_enemy(d, -1)
	if fighter != null:
		return null
	return st


## Sword Judgment: Sol closes in and executes a staggered enemy (the kill and its drops come from the
## enemy's own death path on the strike frame). Rooted, untouchable, camera pulled in.
func _finisher(e) -> void:
	var m := SolMoves.move("finisher")
	move_name = "finisher"
	combo = 0
	combo_t = 0.0
	var to: Vector3 = e.global_position - global_position
	to.y = 0.0
	facing = atan2(to.x, to.z)
	visual.rotation.y = facing
	e.stagger_t = maxf(e.stagger_t, float(m.lock) + 0.5) # he stays down for it
	finisher_t = float(m.lock)
	swing_t = float(m.lock)
	invuln_t = maxf(invuln_t, float(m.lock))
	attack_cd = float(m.lock) + float(m.cd)
	var delay := (float(m.hit) - float(m.from)) / float(m.speed)
	if mod_anim != null:
		delay = mod_anim.play_move(m, 1.0)
	_lunge(maxf(to.length() - 1.2, 0.0), maxf(delay * 0.7, 0.1))
	_flush_pending()
	pending = {"t": delay, "move": "finisher", "target": e}
	# the victim plays his half: faces Sol, reels on the first cut, dies on the strike frame
	if e.has_method("execution_victim"):
		e.execution_victim(self, delay)
	attacked.emit(1, _forward())
	special_move.emit("finisher")
	Audio.play("sword_swing", 0.0, 0.1) # AUDIO HOOK


## The strike frame of a delayed move: damage, hit-stop, shake (the same rules as the combo).
func _strike(name: String, target) -> void:
	var m := SolMoves.move(name)
	var fwd := _forward()
	var w := weapon_stats()
	if name == "finisher":
		if target == null or not is_instance_valid(target) or target.dead:
			return
		var fd: float = w.dmg * 2.0 * (1.0 + stat("finisher")) * damage_mult() * _vs_mult(target)
		target.take_hit(fd, fwd) # staggered: this is the kill (death, drops and Tithe as usual)
		if target.has_method("execution_death"):
			target.execution_death(fwd) # thrown back along Sol's cut, with a blood burst
		Audio.play_at("sword_hit", target.global_position, 4.0) # AUDIO HOOK
		hit_enemy.emit(target, fd)
		_on_blow_landed()
		add_hunger(float(FRENZY_FEED.finisher)) # an execution feeds the beast
		shake = maxf(shake, float(m.shake))
		main.rumble(0.6, 0.9, 0.2)
		main.set_slowmo(0.15, float(m.stop) * 2.0)
		return
	var dmg: float = w.dmg * float(m.dmg) * damage_mult()
	if name == "charged":
		dmg *= 1.0 + stat("finisher") # PROGRESSION HOOK: the heavy hit counts as a finisher
	var reach: float = float(m.reach) + w.reach
	var hit := false
	for e in main.enemies_root.get_children():
		if e.dead or (e.staggered and e != target):
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < reach and (d < 0.9 or fwd.dot(to / d) > 0.3):
			var hd: float = dmg * _vs_mult(e)
			e.take_hit(hd, to.normalized() if d > 0.01 else fwd)
			hit_enemy.emit(e, hd)
			_on_blow_landed()
			hit = true
			Audio.play_at("sword_hit", e.global_position, 3.0 if name == "charged" else 0.0) # AUDIO HOOK
			if name == "charged" and not e.dead:
				_stagger_enemy(e, 2.5) # the heavy hit knocks them reeling
	if hit:
		shake = maxf(shake, float(m.shake))
		main.rumble(0.5, 0.6, 0.12)
		main.set_slowmo(0.06, float(m.stop))


## Parry: a short guard; an enemy whose wind-up is under way in reach is turned aside.
func _parry() -> void:
	var m := SolMoves.move("parry")
	move_name = "parry"
	parry_t = PARRY_WINDOW
	parry_cd = float(m.cd)
	swing_t = float(m.lock)
	if mod_anim != null:
		mod_anim.play_move(m, 1.0)
	special_move.emit("parry")


func _parry_success(e) -> void:
	parry_t = 0.0
	parry_cd = 0.0
	var to: Vector3 = e.global_position - global_position
	facing = atan2(to.x, to.z)
	_stagger_enemy(e, 2.5)
	shake = maxf(shake, 0.25)
	main.rumble(0.6, 0.4, 0.15)
	main.set_slowmo(0.25, 0.45)
	main.hud.popup("PARRY")
	add_hunger(float(FRENZY_FEED.parry)) # a clean parry feeds the beast
	parried.emit(e)
	Audio.play_at("sword_hit", e.global_position, 2.0, 0.15) # AUDIO HOOK


## Put an enemy into its stagger (the state the bite and the execution need), from outside enemy.gd.
func _stagger_enemy(e, t: float) -> void:
	if e.dead:
		return
	if e.has_method("on_parried"):
		e.on_parried(t) # bosses never stagger: the parry breaks the attack and opens a punish window
		return
	if e.get("windup_t") == null:
		return
	e.windup_t = 0.0
	main.release_attack_token(e)
	e.staggered = true
	e.stagger_t = maxf(e.stagger_t, t)
	if e.marker != null:
		e.marker.visible = true
	if e.has_method("_anim_hit"):
		e._anim_hit()


## Per physics frame: the charge hold, the pending strike, the parry window and the move timers.
func _combat_tick(delta: float) -> void:
	parry_cd = maxf(parry_cd - delta, 0.0)
	finisher_t = maxf(finisher_t - delta, 0.0)
	if hold_t >= 0.0:
		if Input.is_action_pressed("attack"):
			hold_t += delta
			if hold_t >= HEAVY_HOLD:
				if exhausted and frenzy_t <= 0.0:
					hold_t = -1.0 # no breath left for the heavy cut: the light one stands
				else:
					_special("charged")
		else:
			hold_t = -1.0
	if not pending.is_empty():
		pending.t -= delta
		# QA2 #10: while the press that swung it is still held, the light strike waits: it may yet
		# become the charged slash (which drops it), else it lands on release
		var held: bool = pending.has("combo") and hold_t >= 0.0 and Input.is_action_pressed("attack")
		if pending.t <= 0.0 and not held:
			var p := pending
			pending = {}
			_resolve_pending(p)
	if parry_t > 0.0:
		parry_t -= delta
		for e in main.enemies_root.get_children():
			if not _parryable(e):
				continue
			var to: Vector3 = e.global_position - global_position
			to.y = 0.0
			if to.length() < _parry_reach(e):
				_parry_success(e)
				break


## Is this enemy (street enemy or boss) in an attack the parry can turn aside right now?
func _parryable(e) -> bool:
	if e == null or not is_instance_valid(e) or e.get("dead") != false:
		return false
	if e.has_method("parry_open"):
		return e.parry_open() # bosses: the last part of a swipe or dash wind-up, or the dash itself
	var w = e.get("windup_t")
	if w != null and float(w) > 0.0:
		return true
	var sp = e.get("special") # the lunge / leap wind-up and the lunge itself
	return sp is String and (sp.ends_with("_windup") or sp == "lunge")


## How close (flat metres) an enemy in a parryable attack must be for the parry to catch it.
func _parry_reach(e) -> float:
	if e.has_method("parry_reach"):
		return e.parry_reach()
	var sp = e.get("special")
	if sp is String and sp != "" and not sp.ends_with("_recover"):
		return 3.0 # the lunge / leap closes the gap itself
	var r = e.get("attack_range")
	return (float(r) if r != null else 1.5) + 1.4


func _bite(target) -> void:
	var to: Vector3 = target.global_position - global_position
	facing = atan2(to.x, to.z)
	visual.rotation.y = facing
	bite_t = 0.55
	shake = 0.22
	var blood: int = target.drain()
	match blood:
		0:
			heal(40.0 * _bite_mult())
			add_hunger(24.0)
			main.hud.popup("HUMAN BLOOD  +40\nthe hunger grows")
		1:
			heal(25.0 * _bite_mult())
			add_hunger(10.0)
			speed_boost_t = 6.0
			main.hud.popup("VAMPIRE BLOOD  +25\nSPEED UP")
		2:
			heal(18.0 * _bite_mult())
			add_hunger(14.0)
			rage_t = 7.0
			burn_t = 3.0
			main.hud.popup("WEREWOLF BLOOD  +18\nRAGE  (it burns)")
	main.set_slowmo(0.35, 0.35)
	main.rumble(0.3, 0.6, 0.25)
	bit_enemy.emit(target, blood)
	Audio.play("bite"); Dialogue.play_group("bark_bite_") # AUDIO HOOK


func heal(v: float) -> void:
	hp = minf(hp + v, max_hp)


# ---------------------------------------------------------------- stamina
func max_stamina() -> float:
	return maxf(stamina_max + stat("stamina"), 20.0) # PROGRESSION / BLOOD RITE HOOK


## Spend `cost` for an action. False (and nothing spent) while exhausted. Frenzy pays nothing.
func spend_stamina(cost: float) -> bool:
	if frenzy_t > 0.0 or cost <= 0.0:
		return true
	if exhausted:
		return false
	_drain_stamina(cost * maxf(1.0 + stat("stamina_cost"), 0.2), STAMINA_DELAY) # PROGRESSION HOOK
	return true


func _drain_stamina(v: float, wait: float) -> void:
	stamina -= v
	_stamina_wait = maxf(_stamina_wait, wait)
	if stamina <= 0.0:
		stamina = 0.0
		exhausted = true
		_stamina_wait = EXHAUST_DELAY


func _stamina_tick(delta: float) -> void:
	var top := max_stamina()
	if _stamina_wait > 0.0:
		_stamina_wait -= delta
	elif stamina < top:
		stamina = minf(stamina + stamina_regen * (1.0 + stat("stamina_regen")) * (0.65 if exhausted else 1.0) * delta, top)
	if exhausted and stamina >= EXHAUST_RECOVER:
		exhausted = false
	stamina = minf(stamina, top)


## A blow landed: Frenzy feeds on it.
func _on_blow_landed() -> void:
	if frenzy_t > 0.0:
		heal(FRENZY_LEECH)


func add_hunger(v: float) -> void:
	hunger = minf(hunger + v, 100.0)
	if hunger >= 100.0 and frenzy_t <= 0.0:
		frenzy_t = 8.0 * (1.0 + stat("frenzy_time")) # PROGRESSION HOOK
		main.hud.announce("FRENZY\nThe beast is loose")
		Dialogue.play("bark_frenzy") # AUDIO HOOK


func take_damage(amount: float, _src) -> void:
	if dead:
		return
	if dash_t > 0.0:
		main.perfect_dodge()
		return
	if invuln_t > 0.0:
		return
	if parry_t > 0.0 and _src != null and is_instance_valid(_src) and (_src.get("windup_t") != null or (_src.has_method("parry_open") and _src.parry_open())):
		_parry_success(_src) # the strike landed inside the parry window: turned aside
		return
	if frenzy_t > 0.0:
		amount *= 1.0 + frenzy_dmg_taken # the beast doesn't guard
	amount *= maxf(1.0 + stat("dmg_taken"), 0.2) # PROGRESSION HOOK
	hp -= amount
	hurt.emit(amount, _src)
	Dialogue.on_player_hurt(hp / max_hp) # AUDIO HOOK
	since_hurt = 0.0
	invuln_t = 0.4
	shake = maxf(shake, 0.32)
	main.hud.on_damage()
	main.rumble(0.5, 0.8, 0.2)
	if hp <= 0.0:
		_die()


func _die() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	Audio.on_player_died() # AUDIO HOOK
	if mod_anim != null:
		mod_anim.die()
		visual.rotation.x = 0.0
	else:
		var tw := create_tween()
		tw.tween_property(visual, "rotation:x", -1.45, 0.6).set_ease(Tween.EASE_IN)
	main.on_player_died()


func _process(delta: float) -> void:
	# controller right stick camera (unscaled so it stays responsive in slow-mo)
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if lock_target != null and _lock_valid(lock_target):
		_lock_camera(real_dt) # the stick flicks between targets instead (_lock_tick)
	elif look.length() > 0.0:
		var curve := look * look.length() # finer control near center
		cam_yaw -= curve.x * Settings.pad_yaw() * real_dt
		cam_pitch = clampf(cam_pitch - curve.y * Settings.pad_pitch() * Settings.y_sign() * real_dt, -1.1, 0.35)
	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	if shake > 0.0:
		var sk := shake * 0.25 * HFx.shake_scale() # settings: reduced camera shake
		camera.h_offset = randf_range(-1.0, 1.0) * sk
		camera.v_offset = randf_range(-1.0, 1.0) * sk
		shake = maxf(shake - delta * 1.6, 0.0)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	var target_fov := 70.0
	if dash_t > 0.0:
		target_fov = 90.0
	elif sprinting:
		target_fov = 78.0
	camera.fov = lerpf(camera.fov, target_fov, 10.0 * delta)
	# the execution: the camera arm pulls in tight, then eases back out
	if finisher_t > 0.0:
		camera.fov = lerpf(camera.fov, 55.0, 8.0 * delta)
	var arm := 4.8
	if lock_target != null and _lock_valid(lock_target):
		var br = lock_target.get("body_radius")
		arm = 5.3 + (clampf(float(br) * 0.9, 0.0, 1.6) if br != null else 0.0) # a boss: pull out to frame him
	spring.spring_length = lerpf(spring.spring_length, 2.7 if finisher_t > 0.0 else arm, (7.0 if finisher_t > 0.0 else 3.0) * delta)
	_camera_obstruction()
	if dead:
		return

	var hs := Vector2(velocity.x, velocity.z).length()
	var flare := clampf(hs / 14.0, 0.0, 1.0)
	if coat != null:
		coat.scale = Vector3(1.0 + flare * 0.2, 1.0, 1.0 + flare * 0.35)
		coat.rotation.x = flare * 0.22

	if swing_t > 0.0:
		var k := 1.0 - swing_t / 0.22
		if combo == 3:
			arm_pivot.rotation = Vector3(lerpf(-2.9, -0.5, k), 0.0, 0.0)
		else:
			var side := 1.0 if combo == 1 else -1.0
			arm_pivot.rotation = Vector3(-1.45, lerpf(1.4 * side, -1.4 * side, k), 0.0)
	else:
		arm_pivot.rotation = arm_pivot.rotation.lerp(Vector3(-0.35, 0.0, 0.08), 12.0 * delta)

	var lean := flare * 0.12
	if bite_t > 0.0:
		lean = 0.6
	elif dash_t > 0.0:
		lean = 0.35
	if mod_anim != null:
		lean *= 0.5 # small additive tilt on top of the clips (dash lunge, bite lean)
		mod_anim.armed = sheath == null or sheath.drawn
		mod_anim.in_combat = mod_anim.armed and _nearest_enemy(COMBAT_RANGE, 0) != null # the sword stance needs the sword
		mod_anim.update(delta, {"speed": hs, "on_floor": is_on_floor()})
	visual.rotation.x = lerpf(visual.rotation.x, lean, 12.0 * delta)

	if dash_t > 0.0 or (frenzy_t > 0.0 and hs > 3.0):
		ghost_t -= delta
		if ghost_t <= 0.0:
			ghost_t = 0.025 if dash_t > 0.0 else 0.09
			_spawn_ghost()


## Locked on: the camera swings behind Sol to look past him at the target, pitched to keep both in
## frame (lower for a tall boss close by), and the reticle sits on the target's chest.
func _lock_camera(dt: float) -> void:
	var lp := _lock_point(lock_target)
	var to := lp - pivot.global_position
	var flat := Vector2(to.x, to.z).length()
	var want_yaw := atan2(-to.x, -to.z)
	cam_yaw = lerp_angle(cam_yaw, want_yaw, minf(7.0 * dt, 1.0))
	var want_pitch := clampf(atan2(to.y, maxf(flat, 0.5)) * 0.6 - 0.2, -0.7, 0.15)
	cam_pitch = lerpf(cam_pitch, want_pitch, minf(5.0 * dt, 1.0))
	if lock_reticle != null:
		lock_reticle.global_position = lp


## After-images come from a small pool of 3-mesh silhouettes (cheap on web GPUs).
func _build_ghosts() -> void:
	var body := U.capsule(0.22, 1.85)
	var coat_mesh := U.cyl(0.26, 0.5, 1.3)
	var head := U.sphere(0.17)
	for i in range(GHOST_POOL):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var g := Node3D.new()
		g.top_level = true
		g.visible = false
		for part in [[body, Vector3(0, 0.95, 0)], [coat_mesh, Vector3(0, 0.98, -0.02)], [head, Vector3(0, 1.85, 0)]]:
			var mi := U.part(g, part[0], m, part[1])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		ghosts.append(g)
		ghost_mats.append(m)
		ghost_tweens.append(null)


func _spawn_ghost() -> void:
	if ghosts.is_empty():
		_build_ghosts()
	var i := ghost_next
	ghost_next = (ghost_next + 1) % GHOST_POOL
	var g := ghosts[i]
	var m := ghost_mats[i]
	if ghost_tweens[i] != null:
		(ghost_tweens[i] as Tween).kill()
	m.albedo_color = Color(0.7, 0.0, 0.05, 0.4) if (frenzy_t > 0.0 or rage_t > 0.0) else Color(0.08, 0.06, 0.12, 0.45)
	g.global_transform = visual.global_transform
	g.visible = true
	var tw := create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(g.hide)
	ghost_tweens[i] = tw
