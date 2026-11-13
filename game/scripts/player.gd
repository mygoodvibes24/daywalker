extends CharacterBody3D
## Elijah "Sol" Marrow — the Daywalker. Fast movement, blade combos, the bite.

const U = preload("res://scripts/util.gd")
const SolAnim = preload("res://scripts/sol_anim.gd")
const SOL_SCENE := "res://assets/characters/sol/sol.scn"

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

var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var visual: Node3D
var coat: MeshInstance3D # primitive fallback only
var arm_pivot: Node3D # swing driver; drawn directly only by the primitive fallback
var anim: SolAnim # procedural animator for the skinned model (null on the fallback)


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
	pivot = Node3D.new()
	pivot.position.y = 1.8 # a touch higher: reads the street and the lights better
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 4.8
	spring.collision_mask = 1
	spring.margin = 0.25
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
	if ResourceLoader.exists(SOL_SCENE) and _build_model():
		return
	_build_primitive_body()


## The generated, skinned Sol model (1.88 m, feet at y=0, facing +Z) with the silver
## blade in his right hand. Returns false if the asset can't be used.
func _build_model() -> bool:
	var scene := load(SOL_SCENE) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	var skel := model.get_node_or_null("Skeleton3D") as Skeleton3D
	if skel == null or skel.find_bone("Hand.R") < 0:
		model.free()
		return false
	visual.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	anim = SolAnim.new()
	anim.setup(skel)
	# the blade rides the right hand bone, angled along the forearm like a gripped sword
	var hand := BoneAttachment3D.new()
	hand.bone_name = "Hand.R"
	skel.add_child(hand)
	var grip := Node3D.new()
	grip.position = Vector3(-0.09, -0.01, 0.0)
	grip.rotation.y = -0.96
	hand.add_child(grip)
	var steel := U.mat(Color(0.85, 0.88, 0.92), 0.12, 1.0)
	U.part(grip, U.box(Vector3(0.012, 0.045, 1.0)), steel, Vector3(0, 0, 0.56))
	U.part(grip, U.box(Vector3(0.13, 0.03, 0.03)), U.mat(Color(0.035, 0.035, 0.04), 0.6), Vector3(0, 0, 0.05))
	U.part(grip, U.cyl(0.016, 0.016, 0.16), U.mat(Color(0.03, 0.025, 0.02), 0.7), Vector3(0, 0, -0.03), Vector3(PI / 2.0, 0, 0))
	# arm_pivot keeps its swing math; the animator turns it into the right arm's pose
	arm_pivot = Node3D.new()
	arm_pivot.position = Vector3(-0.19, 1.47, -0.06)
	visual.add_child(arm_pivot)
	return true


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
		cam_yaw -= mm.relative.x * 0.0025
		cam_pitch = clampf(cam_pitch - mm.relative.y * 0.0025, -1.1, 0.35)
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
	var day: bool = main.is_day()

	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(inp.x, 0.0, inp.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	sprinting = Input.is_action_pressed("sprint") and dir.length() > 0.1
	var spd := SPRINT if sprinting else WALK
	if speed_boost_t > 0.0:
		spd *= 1.3
	if frenzy_t > 0.0:
		spd *= 1.25

	# Blood Dash (recharges faster in sunlight)
	dash_charges = minf(dash_charges + delta / (0.7 if day else 1.1), MAX_DASH)
	if Input.is_action_just_pressed("dash") and dash_charges >= 1.0 and bite_t <= 0.0:
		dash_charges -= 1.0
		dash_t = DASH_TIME
		since_dash = 0.0
		invuln_t = maxf(invuln_t, DASH_TIME + 0.12)
		dash_dir = dir.normalized() if dir.length() > 0.1 else _forward()
		collision_mask = 1 # phase through enemies

	# jump / double jump
	if is_on_floor():
		jumps_left = 2
	else:
		velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("jump") and jumps_left > 0 and bite_t <= 0.0:
		velocity.y = JUMP if jumps_left == 2 else JUMP * 0.85
		jumps_left -= 1

	var hv := Vector3.ZERO
	if dash_t > 0.0:
		hv = dash_dir * DASH_SPEED
		velocity.y = maxf(velocity.y, 0.0)
	elif bite_t > 0.0:
		hv = Vector3.ZERO
	else:
		hv = dir * spd
		if swing_t > 0.0:
			hv *= 0.3
		if lunge_t > 0.0:
			hv += _forward() * 9.0
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()

	if dash_t > 0.0:
		facing = atan2(dash_dir.x, dash_dir.z)
	elif dir.length() > 0.1 and swing_t <= 0.0 and bite_t <= 0.0:
		facing = atan2(dir.x, dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, facing, 16.0 * delta)

	# actions
	if Input.is_action_just_pressed("attack") and attack_cd <= 0.0 and bite_t <= 0.0 and Time.get_ticks_msec() >= attack_block_until:
		_attack()
	var bite_target = _nearest_enemy(BITE_RANGE, 1)
	if Input.is_action_just_pressed("bite") and bite_t <= 0.0 and bite_target != null:
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
	if frenzy_t > 0.0:
		frenzy_t -= delta
		hp = minf(hp + 3.0 * delta, max_hp)
		if frenzy_t <= 0.0:
			hunger = 55.0
			main.hud.popup("The frenzy fades...")
	else:
		hunger = maxf(hunger - 0.6 * delta, 0.0)
	# Daywalker: stay human and the sun slowly heals you (out of combat)
	if hunger < 30.0 and main.daylight() > 0.3 and since_hurt > 4.0:
		hp = minf(hp + SUN_HEAL * delta, max_hp)
	if hp <= 0.0:
		_die()


func damage_mult() -> float:
	var m := 1.0
	if rage_t > 0.0:
		m *= 1.5
	if hunger >= 60.0:
		m *= 1.25
	if frenzy_t > 0.0:
		m *= 2.0
	return m


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


func _attack() -> void:
	combo = combo + 1 if (combo_t > 0.0 and combo < 3) else 1
	combo_t = 0.7
	attack_cd = 0.22 if combo < 3 else 0.4
	swing_t = 0.22
	lunge_t = 0.08
	# soft-lock prefers fighting enemies, so you don't kill the one you meant to bite
	var target = _nearest_enemy(5.0, -1)
	if target == null:
		target = _nearest_enemy(5.0, 1)
	if target != null:
		var tt: Vector3 = target.global_position - global_position
		facing = atan2(tt.x, tt.z)
		visual.rotation.y = facing
	var fwd := _forward()
	var dmg := (14.0 if combo < 3 else 28.0) * damage_mult()
	var reach := 2.7 if combo < 3 else 3.3
	var hit := false
	for e in main.enemies_root.get_children():
		if e.dead or (e.staggered and e != target):
			continue # a staggered enemy only dies to a swing aimed at it
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < reach and (d < 0.9 or fwd.dot(to / d) > 0.3):
			e.take_hit(dmg, to.normalized() if d > 0.01 else fwd)
			hit = true
	if hit:
		shake = maxf(shake, 0.12 if combo < 3 else 0.28)
		main.rumble(0.4, 0.0 if combo < 3 else 0.5, 0.08)
		main.set_slowmo(0.06, 0.05 if combo < 3 else 0.09)


func _bite(target) -> void:
	var to: Vector3 = target.global_position - global_position
	facing = atan2(to.x, to.z)
	visual.rotation.y = facing
	bite_t = 0.55
	shake = 0.22
	var blood: int = target.drain()
	match blood:
		0:
			heal(40.0)
			add_hunger(24.0)
			main.hud.popup("HUMAN BLOOD  +40\nthe hunger grows")
		1:
			heal(25.0)
			add_hunger(10.0)
			speed_boost_t = 6.0
			main.hud.popup("VAMPIRE BLOOD  +25\nSPEED UP")
		2:
			heal(18.0)
			add_hunger(14.0)
			rage_t = 7.0
			burn_t = 3.0
			main.hud.popup("WEREWOLF BLOOD  +18\nRAGE  (it burns)")
	main.set_slowmo(0.35, 0.35)
	main.rumble(0.3, 0.6, 0.25)


func heal(v: float) -> void:
	hp = minf(hp + v, max_hp)


func add_hunger(v: float) -> void:
	hunger = minf(hunger + v, 100.0)
	if hunger >= 100.0 and frenzy_t <= 0.0:
		frenzy_t = 8.0
		main.hud.announce("FRENZY\nThe beast is loose")


func take_damage(amount: float, _src) -> void:
	if dead:
		return
	if dash_t > 0.0:
		main.perfect_dodge()
		return
	if invuln_t > 0.0:
		return
	if frenzy_t > 0.0:
		amount *= 0.5
	hp -= amount
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
	var tw := create_tween()
	tw.tween_property(visual, "rotation:x", -1.45, 0.6).set_ease(Tween.EASE_IN)
	main.on_player_died()


func _process(delta: float) -> void:
	# controller right stick camera (unscaled so it stays responsive in slow-mo)
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.0:
		var curve := look * look.length() # finer control near center
		cam_yaw -= curve.x * 3.0 * real_dt
		cam_pitch = clampf(cam_pitch - curve.y * 2.0 * real_dt, -1.1, 0.35)
	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	if shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.25
		camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.25
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
	if anim != null:
		lean *= 0.4 # the skeleton bends the spine itself; keep only a light whole-body tilt
		anim.update(delta, {
			"speed": hs, "sprint": sprinting, "on_floor": is_on_floor(),
			"dashing": dash_t > 0.0, "biting": bite_t > 0.0,
			"swinging": swing_t > 0.0, "swing_rot": arm_pivot.rotation,
		})
	visual.rotation.x = lerpf(visual.rotation.x, lean, 12.0 * delta)

	if dash_t > 0.0 or (frenzy_t > 0.0 and hs > 3.0):
		ghost_t -= delta
		if ghost_t <= 0.0:
			ghost_t = 0.025 if dash_t > 0.0 else 0.09
			_spawn_ghost()


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
