extends CharacterBody3D
## Vampires of the Velvet Court and the Hollow Pack (who change at night).

const U = preload("res://scripts/util.gd")
enum { VAMPIRE, WEREWOLF }

var main
var kind: int = VAMPIRE
var max_hp := 40.0
var hp := 40.0
var speed := 7.0
var damage := 8.0
var attack_range := 1.5
var attack_cd := 0.0
var windup_t := 0.0
var staggered := false
var stagger_t := 0.0
var transformed := false
var transform_t := 0.0
var dead := false
var knockback := Vector3.ZERO
var flash_t := 0.0
var burning := false
var phase := 0.0
var agent: NavigationAgent3D
var repath_t := 0.0
var avoid_frames := 99 # physics frames since the last avoidance callback
var strike_dir := Vector3.FORWARD # locked when the wind-up starts
var orbit_sign := 1.0
var wolf_parts: Array[Node3D] = []
var human_stats := {}

var visual: Node3D
var body_mat: StandardMaterial3D
var skin_mat: StandardMaterial3D
var eye_mat: StandardMaterial3D
var body_color: Color
var skin_color: Color
var eye_color: Color
var marker: MeshInstance3D

# Character models (baked by tools/bake_rigs.gd). The primitive bodies stay as a fallback.
const MODEL_PATHS := {
	"vampire": "res://assets/characters/vampire/vampire_rig.scn",
	"werewolf": "res://assets/characters/werewolf/werewolf_rig.scn",
	"civilian": "res://assets/characters/civilian/civilian_rig.scn",
}
static var _scene_cache := {} # shared PackedScenes
static var _eye_meshes := {}
var model: Node3D
var model_name := ""
var skel: Skeleton3D
var body_mesh: MeshInstance3D
var overlay_mat: StandardMaterial3D # the only per-enemy material: flash / burn / death tint
var bone := {}
var run_blend := 0.0
var windup_blend := 0.0
var stagger_blend := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	visual = Node3D.new()
	add_child(visual)
	phase = randf() * TAU
	if kind == VAMPIRE:
		_build_vampire()
	else:
		_build_civilian()
	hp = max_hp
	human_stats = {"max_hp": max_hp, "speed": speed, "damage": damage, "range": attack_range, "body": body_color, "skin": skin_color, "eye": eye_color}
	orbit_sign = 1.0 if randf() < 0.5 else -1.0
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.2
	agent.radius = 0.5
	agent.height = 1.8
	agent.avoidance_enabled = true
	agent.neighbor_distance = 6.0
	agent.max_neighbors = 8
	agent.time_horizon_agents = 0.8
	agent.max_speed = 12.0
	add_child(agent)
	agent.velocity_computed.connect(_on_safe_velocity)
	marker = U.part(self, U.sphere(0.16), U.glow(Color(1, 0.05, 0.05), 5.0), Vector3(0, 2.7, 0))
	marker.visible = false


static func _model_scene(n: String) -> PackedScene:
	if not _scene_cache.has(n):
		var path: String = MODEL_PATHS[n]
		_scene_cache[n] = (load(path) as PackedScene) if ResourceLoader.exists(path) else null
	return _scene_cache[n]


## Swap the visible body for one of the character models. False if it can't be loaded.
func _set_model(n: String) -> bool:
	var ps := _model_scene(n)
	if ps == null:
		return false
	var inst := ps.instantiate() as Node3D
	var sk: Skeleton3D = null
	if inst != null:
		sk = inst.get_node_or_null("Skeleton") as Skeleton3D
	if sk == null or sk.get_node_or_null("Body") == null:
		if inst != null:
			inst.free()
		return false
	if model != null:
		visual.remove_child(model)
		model.queue_free()
	model = inst
	model_name = n
	skel = sk
	body_mesh = sk.get_node("Body")
	visual.add_child(model)
	bone.clear()
	for i in skel.get_bone_count():
		bone[skel.get_bone_name(i)] = i
	if overlay_mat == null:
		overlay_mat = StandardMaterial3D.new()
		overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay_mat.albedo_color = Color(1, 1, 1, 0)
	# glowing eyes ride the head bone
	var r: float = model.get_meta("eye_radius", 0.011)
	if not _eye_meshes.has(r):
		_eye_meshes[r] = U.sphere(r)
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_name = "head"
	var head_rest: Vector3 = model.get_meta("head_rest", Vector3(0, 1.5, 0))
	att.visible = n != "civilian"
	for key in ["eye_l", "eye_r"]:
		var e := U.part(att, _eye_meshes[r], eye_mat, model.get_meta(key, head_rest) - head_rest)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return true


func _set_overlay(c: Color) -> void:
	if body_mesh == null:
		return
	if c.a <= 0.01:
		if body_mesh.material_overlay != null:
			body_mesh.material_overlay = null # no extra pass when there is nothing to show
		return
	overlay_mat.albedo_color = c
	if body_mesh.material_overlay == null:
		body_mesh.material_overlay = overlay_mat


func _rot(b: String, q: Quaternion) -> void:
	skel.set_bone_pose_rotation(bone[b], q)


## Procedural pose on the baked skeleton (rest pose is a T-pose, +Z forward).
func _pose(delta: float, spd: float) -> void:
	var wolf := model_name == "werewolf"
	run_blend = lerpf(run_blend, clampf(spd / 4.0, 0.0, 1.0), minf(8.0 * delta, 1.0))
	windup_blend = lerpf(windup_blend, 1.0 if windup_t > 0.0 else 0.0, minf(14.0 * delta, 1.0))
	stagger_blend = lerpf(stagger_blend, 1.0 if staggered else 0.0, minf(8.0 * delta, 1.0))
	var r := run_blend * (1.0 - stagger_blend)
	var up := windup_blend
	var sl := stagger_blend
	var s := sin(phase)
	var c := cos(phase)
	var idle := sin(phase * 0.35) * (1.0 - r)
	var stride := 0.75 if wolf else 0.65
	_rot("thigh_l", Quaternion(Vector3.RIGHT, (-s * stride - 0.12) * r + 0.08 * sl))
	_rot("thigh_r", Quaternion(Vector3.RIGHT, (s * stride - 0.12) * r - 0.1 * sl))
	_rot("shin_l", Quaternion(Vector3.RIGHT, (0.2 + 0.9 * maxf(c, 0.0)) * r + 0.2 * sl))
	_rot("shin_r", Quaternion(Vector3.RIGHT, (0.2 + 0.9 * maxf(-c, 0.0)) * r + 0.15 * sl))
	var down := (1.05 if wolf else 1.25) + 0.15 * sl - 0.45 * up + idle * 0.02
	var swing := s * 0.6 * r
	var raise := -1.35 * up + 0.12 * sl
	_rot("upper_l", Quaternion(Vector3.RIGHT, swing + raise) * Quaternion(Vector3.BACK, -down))
	_rot("upper_r", Quaternion(Vector3.RIGHT, -swing + raise) * Quaternion(Vector3.BACK, down))
	var bend := (0.55 if wolf else 0.2) + 0.9 * r + 0.5 * up
	_rot("fore_l", Quaternion(Vector3.UP, -bend))
	_rot("fore_r", Quaternion(Vector3.UP, bend))
	_rot("spine", Quaternion(Vector3.RIGHT, 0.1 * r + 0.3 * sl - 0.12 * up) * Quaternion(Vector3.BACK, idle * 0.035))
	_rot("chest", Quaternion(Vector3.UP, s * 0.14 * r) * Quaternion(Vector3.RIGHT, 0.15 * sl))
	_rot("head", Quaternion(Vector3.RIGHT, 0.45 * sl - 0.1 * r - (0.2 if wolf else 0.0)) * Quaternion(Vector3.UP, idle * 0.08))


func _limbs(leg_mat: Material, torso_mat: Material, arm_mat: Material) -> void:
	U.part(visual, U.capsule(0.12, 0.9), leg_mat, Vector3(-0.13, 0.45, 0))
	U.part(visual, U.capsule(0.12, 0.9), leg_mat, Vector3(0.13, 0.45, 0))
	U.part(visual, U.capsule(0.26, 0.9), torso_mat, Vector3(0, 1.2, 0))
	U.part(visual, U.capsule(0.08, 0.75), arm_mat, Vector3(-0.34, 1.15, 0), Vector3(0, 0, 0.15))
	U.part(visual, U.capsule(0.08, 0.75), arm_mat, Vector3(0.34, 1.15, 0), Vector3(0, 0, -0.15))
	U.part(visual, U.sphere(0.17), skin_mat, Vector3(0, 1.78, 0))
	U.part(visual, U.sphere(0.03), eye_mat, Vector3(-0.06, 1.8, 0.155))
	U.part(visual, U.sphere(0.03), eye_mat, Vector3(0.06, 1.8, 0.155))


func _build_vampire() -> void:
	body_color = Color(0.08, 0.02, 0.03)
	skin_color = Color(0.86, 0.83, 0.82)
	eye_color = Color(1, 0.05, 0.05)
	body_mat = U.mat(body_color, 0.35, 0.1)
	skin_mat = U.mat(skin_color, 0.5)
	eye_mat = U.glow(eye_color, 5.0)
	if not _set_model("vampire"):
		_limbs(body_mat, body_mat, body_mat)
		U.part(visual, U.sphere(0.175), U.mat(Color(0.02, 0.02, 0.02), 0.15), Vector3(0, 1.83, -0.03), Vector3.ZERO, Vector3(1, 0.75, 1))
		U.part(visual, U.box(Vector3(0.75, 1.35, 0.04)), U.mat(Color(0.45, 0.0, 0.05), 0.5), Vector3(0, 1.0, -0.3), Vector3(0.12, 0, 0))
		U.part(visual, U.box(Vector3(0.6, 0.25, 0.05)), U.mat(Color(0.45, 0.0, 0.05), 0.5), Vector3(0, 1.62, -0.18), Vector3(-0.3, 0, 0))
	max_hp = 40.0
	speed = 7.6
	damage = 8.0


func _build_civilian() -> void:
	var shirts: Array[Color] = [Color(0.25, 0.3, 0.45), Color(0.4, 0.2, 0.15), Color(0.2, 0.35, 0.2), Color(0.5, 0.45, 0.35), Color(0.3, 0.3, 0.3)]
	var skins: Array[Color] = [Color(0.36, 0.23, 0.15), Color(0.55, 0.38, 0.26), Color(0.8, 0.62, 0.5), Color(0.25, 0.16, 0.1)]
	body_color = shirts[randi() % shirts.size()]
	skin_color = skins[randi() % skins.size()]
	eye_color = Color(0.05, 0.05, 0.05)
	body_mat = U.mat(body_color, 0.9)
	skin_mat = U.mat(skin_color, 0.6)
	eye_mat = U.glow(eye_color, 0.0)
	if not _set_model("civilian"):
		_limbs(U.mat(Color(0.15, 0.18, 0.3), 0.9), body_mat, body_mat)
		U.part(visual, U.sphere(0.175), U.mat(Color(0.08, 0.06, 0.05), 0.9), Vector3(0, 1.84, -0.02), Vector3.ZERO, Vector3(1, 0.7, 1))
	max_hp = 50.0
	speed = 5.4
	damage = 7.0


func _start_transform() -> void:
	transformed = true
	transform_t = 1.4
	_clear_combat_state()
	var full: bool = main.is_full_moon()
	max_hp = 160.0 if full else 110.0
	hp = max_hp
	speed = 9.2 if full else 8.2
	damage = 18.0 if full else 14.0
	attack_range = 1.9
	body_color = Color(0.24, 0.16, 0.1) if randf() < 0.5 else Color(0.32, 0.32, 0.34)
	skin_color = body_color.darkened(0.25)
	eye_color = Color(1.0, 0.75, 0.1)
	eye_mat.albedo_color = eye_color
	eye_mat.emission = eye_color
	eye_mat.emission_energy_multiplier = 5.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(body_mat, "albedo_color", body_color, 1.0)
	tw.tween_property(skin_mat, "albedo_color", skin_color, 1.0)
	if model != null and _set_model("werewolf"):
		# the wolf model is already 2.4 m: start it man-sized and let it burst up
		visual.scale = Vector3(0.7, 0.72, 0.7)
		tw.tween_property(visual, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(visual, "scale", Vector3(1.45, 1.35, 1.45), 1.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		if model == null:
			wolf_parts = [
				U.part(visual, U.cyl(0.0, 0.06, 0.2), skin_mat, Vector3(-0.1, 1.98, 0), Vector3(0, 0, 0.3)),
				U.part(visual, U.cyl(0.0, 0.06, 0.2), skin_mat, Vector3(0.1, 1.98, 0), Vector3(0, 0, -0.3)),
				U.part(visual, U.box(Vector3(0.14, 0.12, 0.24)), skin_mat, Vector3(0, 1.73, 0.18)),
			]
	main.on_wolf_transform(self)


## Sunrise: the wolf shrinks back into a person with civilian stats.
func _revert_transform() -> void:
	transformed = false
	transform_t = 1.0
	_clear_combat_state()
	max_hp = human_stats.max_hp
	hp = max_hp
	speed = human_stats.speed
	damage = human_stats.damage
	attack_range = human_stats.range
	body_color = human_stats.body
	skin_color = human_stats.skin
	eye_color = human_stats.eye
	for part in wolf_parts:
		part.queue_free()
	wolf_parts.clear()
	eye_mat.albedo_color = eye_color
	eye_mat.emission = eye_color
	if model_name == "werewolf" and _set_model("civilian"):
		visual.scale = Vector3(1.3, 1.3, 1.3)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(visual, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(body_mat, "albedo_color", body_color, 0.9)
	tw.tween_property(skin_mat, "albedo_color", skin_color, 0.9)


func _clear_combat_state() -> void:
	staggered = false
	stagger_t = 0.0
	windup_t = 0.0
	if marker != null:
		marker.visible = false
	main.release_attack_token(self)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var player = main.player
	attack_cd = maxf(attack_cd - delta, 0.0)
	flash_t = maxf(flash_t - delta, 0.0)
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = -0.5
	var day: bool = main.is_day()
	if kind == WEREWOLF and not transformed and not day:
		_start_transform()
	elif kind == WEREWOLF and transformed and day and transform_t <= 0.0:
		_revert_transform()
	burning = kind == VAMPIRE and main.daylight() > 0.15
	if burning:
		hp -= 20.0 * delta
		if hp <= 0.0:
			_die(false)
			return

	var hvel := Vector3.ZERO
	if transform_t > 0.0:
		transform_t -= delta
	elif staggered:
		stagger_t -= delta
		if stagger_t <= 0.0:
			staggered = false
			marker.visible = false
			hp = max_hp * 0.45
			flash_t = 0.12 # "recovered" flash: the bite window is gone
	elif player != null and not player.dead:
		var to: Vector3 = player.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		var look := to
		if windup_t > 0.0:
			look = strike_dir # committed: the strike goes where he was
			windup_t -= delta
			if windup_t <= 0.0:
				_resolve_strike(player)
		else:
			var token: bool = dist < attack_range + 4.0 and main.request_attack_token(self)
			if not token and dist >= attack_range + 4.0:
				main.release_attack_token(self)
			if token and dist <= attack_range:
				if attack_cd <= 0.0:
					strike_dir = to / dist if dist > 0.01 else Vector3(sin(visual.rotation.y), 0, cos(visual.rotation.y))
					windup_t = 0.38 if kind == VAMPIRE else 0.45
					attack_cd = 1.1 if kind == VAMPIRE else 1.3
			elif not token and dist < 5.5:
				hvel = _circle(to, dist) # wait for a turn: ring the player
			else:
				hvel = _chase(player.global_position, to, dist, delta)
		if look.length() > 0.01:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(look.x, look.z), 10.0 * delta)
	else:
		main.release_attack_token(self)

	_move(hvel, delta)
	_animate(delta, hvel.length())


## Path along the navmesh; straight in when close.
func _chase(goal: Vector3, to: Vector3, dist: float, delta: float) -> Vector3:
	if dist < 3.0 or agent == null:
		return to / dist * speed
	repath_t -= delta
	if repath_t <= 0.0:
		repath_t = 0.25
		agent.target_position = goal
	var nxt := agent.get_next_path_position() - global_position
	nxt.y = 0.0
	if nxt.length() < 0.05:
		return to / dist * speed if agent.is_navigation_finished() else Vector3.ZERO
	return nxt.normalized() * speed


func _circle(to: Vector3, dist: float) -> Vector3:
	var radial := to / maxf(dist, 0.01)
	var tangent := Vector3(-radial.z, 0.0, radial.x) * orbit_sign
	var err := clampf(dist - 3.8, -1.0, 1.0)
	return (tangent + radial * err * 1.5).normalized() * speed * 0.45


func _resolve_strike(player) -> void:
	main.release_attack_token(self)
	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var in_arc := dist < attack_range + 0.7 and (dist < 0.6 or strike_dir.dot(to / dist) > 0.5)
	if in_arc:
		player.take_damage(damage, self) # a dash in progress counts as a perfect dodge there
	elif dist < attack_range + 4.0 and player.dashed_recently():
		main.perfect_dodge() # he dashed out of a strike that was coming


func _move(hvel: Vector3, delta: float) -> void:
	var desired := hvel
	avoid_frames += 1
	if agent != null and avoid_frames <= 2:
		agent.velocity = desired # steering comes back through _on_safe_velocity
		return
	if agent != null:
		agent.velocity = desired # (re)start the avoidance callbacks
	_apply_velocity(desired, delta)


func _on_safe_velocity(safe: Vector3) -> void:
	avoid_frames = 0
	if dead:
		return
	_apply_velocity(safe, get_physics_process_delta_time())


func _apply_velocity(hvel: Vector3, delta: float) -> void:
	hvel += knockback
	knockback = knockback.move_toward(Vector3.ZERO, 25.0 * delta)
	velocity.x = hvel.x
	velocity.z = hvel.z
	move_and_slide()


func _animate(delta: float, spd: float) -> void:
	phase += delta * (4.0 + spd * 1.2)
	visual.position.y = absf(sin(phase)) * 0.06 * clampf(spd / 5.0, 0.0, 1.0)
	var lean := 0.0
	if staggered:
		lean = 0.55
	elif windup_t > 0.0:
		lean = -0.25 # rear back before the strike
	elif transformed:
		lean = 0.3
	visual.rotation.x = lerpf(visual.rotation.x, lean, 10.0 * delta)
	if transform_t <= 0.0:
		var c := body_color
		if burning:
			c = c.lerp(Color(1.0, 0.35, 0.05), 0.5 + 0.5 * sin(phase * 3.0))
		if flash_t > 0.0:
			c = c.lerp(Color.WHITE, flash_t / 0.12)
		body_mat.albedo_color = c
	if model != null:
		var o := Color(1, 1, 1, 0)
		if transform_t > 0.0: # the change: dark fur colour washing off
			o = Color(body_color.r, body_color.g, body_color.b, clampf(transform_t, 0.0, 1.0) * 0.7)
		if burning:
			o = Color(1.0, 0.35, 0.05, 0.4 + 0.3 * sin(phase * 3.0))
		if flash_t > 0.0:
			o = o.lerp(Color(1, 1, 1, 0.9), flash_t / 0.12)
		_set_overlay(o)
		_pose(delta, spd)
	eye_mat.emission_energy_multiplier = (9.0 if windup_t > 0.0 else 5.0) if (kind == VAMPIRE or transformed) else 0.0
	if staggered:
		marker.position.y = 2.7 + sin(phase * 0.6) * 0.12


func take_hit(amount: float, dir: Vector3) -> void:
	if dead:
		return
	if staggered:
		_die(false)
		return
	hp -= amount
	flash_t = 0.12
	windup_t = 0.0
	main.release_attack_token(self)
	knockback = dir * (6.0 if kind == VAMPIRE and not transformed else 3.0)
	if hp <= max_hp * 0.25:
		staggered = true
		stagger_t = 3.0
		marker.visible = true
		hp = maxf(hp, 1.0)


## Called when the Daywalker bites. Returns blood type: 0 human, 1 vampire, 2 wolf.
func drain() -> int:
	var blood := 1 if kind == VAMPIRE else (2 if transformed else 0)
	_die(true)
	return blood


func _die(_drained: bool) -> void:
	if dead:
		return
	dead = true
	marker.visible = false
	main.release_attack_token(self)
	if agent != null:
		agent.avoidance_enabled = false
	collision_layer = 0
	collision_mask = 0
	main.on_enemy_killed(self, _drained)
	var tw := create_tween()
	if kind == VAMPIRE:
		if model != null: # turn to ash: grey, shaded overlay
			overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			_set_overlay(Color(0.3, 0.3, 0.3, 0.05))
			tw.tween_property(overlay_mat, "albedo_color", Color(0.3, 0.3, 0.3, 0.92), 0.25)
			tw.parallel()
		tw.tween_property(body_mat, "albedo_color", Color(0.25, 0.25, 0.25), 0.25)
		tw.parallel().tween_property(skin_mat, "albedo_color", Color(0.3, 0.3, 0.3), 0.25)
		tw.tween_property(visual, "scale", Vector3(1.4, 0.02, 1.4), 0.45)
	else:
		_set_overlay(Color(1, 1, 1, 0))
		tw.tween_property(visual, "rotation:x", -1.5, 0.45).set_ease(Tween.EASE_IN)
		tw.tween_interval(1.2)
		tw.tween_property(visual, "scale", Vector3.ZERO, 0.4)
	tw.tween_callback(queue_free)
