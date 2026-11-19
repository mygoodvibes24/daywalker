class_name Enemy
extends CharacterBody3D
## Vampires of the Velvet Court and the Hollow Pack (who change at night).

const U = preload("res://scripts/util.gd")
const HFx = preload("res://scripts/hunt/hunt_fx.gd") # ground telegraphs, shockwave, blood puff
enum { VAMPIRE, WEREWOLF }

## Second attacks, as data (the swipe is the first). Each telegraphs on the ground for its wind-up.
##   lunge (vampires): a crouched wind-up, then a straight dash of up to `dist` m at `speed`; the
##     first contact strikes. Dodge sideways or Blood Dash through it; a parry still turns it aside.
##   leap (wolves, changed): a crouch, then a jump onto where Sol stood (`radius` m slam ring).
## min / max: the distance band it is used from. cd: seconds before it can come again. dmg: x damage.
const SPECIALS := {
	"lunge": {"windup": 0.55, "dist": 7.5, "speed": 17.0, "width": 1.4, "dmg": 1.25,
		"min": 2.6, "max": 8.0, "cd": 4.5, "color": Color(1.0, 0.05, 0.15)},
	"leap": {"windup": 0.5, "air": 0.6, "height": 2.4, "radius": 2.4, "dmg": 1.4,
		"min": 3.2, "max": 10.0, "cd": 5.5, "color": Color(1.0, 0.35, 0.05)},
}
## QA2 #7: pressed up against Sol with the special ready, an enemy often hops back out of reach
## (BACKSTEP_CHANCE) and opens with it from there, so a player standing still sees it too.
const BACKSTEP_CHANCE := 0.55
const BACKSTEP_TIME := 0.4
const BACKSTEP_SPEED := 8.0
const STAGGER_FRAC := 0.25 # at or below this share of max hp a hit staggers (the bar turns red)
const BAR_SIZE := Vector2(0.9, 0.09)
const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;
uniform float frac = 1.0;
uniform vec4 fill_col : source_color = vec4(0.86, 0.82, 0.78, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	bool edge = UV.x < 0.015 || UV.x > 0.985 || UV.y < 0.16 || UV.y > 0.84;
	vec3 c = UV.x < frac ? fill_col.rgb : vec3(0.06, 0.05, 0.05);
	ALBEDO = edge ? vec3(0.0) : c;
	ALPHA = 0.92;
}
"""
static var _bar_shader: Shader
static var _bar_mesh: QuadMesh

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

# Character models. *_anim.scn (tools/build_enemy_anims.gd) carries an auto-rigged skeleton and
# real clips; *_rig.scn (tools/bake_rigs.gd) is the older hand-made rig posed procedurally; the
# primitive bodies are the last fallback.
const ANIM_PATHS := {
	"vampire": "res://assets/characters/vampire/vampire_anim.scn",
	"werewolf": "res://assets/characters/werewolf/werewolf_anim.scn",
	"civilian": "res://assets/characters/civilian/civilian_anim.scn",
}
const MODEL_PATHS := {
	"vampire": "res://assets/characters/vampire/vampire_rig.scn",
	"werewolf": "res://assets/characters/werewolf/werewolf_rig.scn",
	"civilian": "res://assets/characters/civilian/civilian_rig.scn",
}
static var _scene_cache := {} # shared PackedScenes (their AnimationLibraries are shared too)
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
# skeletal animation (only with an *_anim.scn model)
var anim: AnimationPlayer
var anim_state := "" # idle / run / sprint / attack / hit / stagger / death / transform
var anim_lock_t := 0.0 # one-shot clip time left before locomotion takes over again
var strike_time := 1.0 # clip time of the attack's strike
var anim_accum := 0.0
var anim_slot := 0
# second attack (SPECIALS): "" or "<name>_windup" / "<name>" / "<name>_recover"
var special := ""
var special_t := 0.0
var special_cd := 0.0
var special_from := Vector3.ZERO
var special_to := Vector3.ZERO
var special_hit := false # the lunge connects once
var telegraph: Node3D
# health bar over an engaged enemy (red at the stagger threshold)
var hp_bar: MeshInstance3D
var hp_bar_mat: ShaderMaterial
var engaged_t := 0.0
# the execution: seconds the victim's half of Sword Judgment still owns his animation
var exec_t := 0.0


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
	special_cd = randf_range(0.6, 1.8) # not the instant they arrive, but early enough to open with
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
		var ps: PackedScene = null
		for path in [ANIM_PATHS[n], MODEL_PATHS[n]]:
			if ResourceLoader.exists(path):
				ps = load(path) as PackedScene
				if ps != null:
					break
		_scene_cache[n] = ps
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
	anim = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	anim_state = ""
	anim_lock_t = 0.0
	if anim != null:
		# advanced by hand in _process so far-away enemies can update less often
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.playback_default_blend_time = 0.15
		strike_time = model.get_meta("strike_time", 1.0)
		anim_slot = randi() % 6
		_play("idle", 0.0)
		anim.seek(randf() * anim.current_animation_length, true)
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
	att.bone_name = model.get_meta("head_bone", "head")
	var head_rest: Vector3 = model.get_meta("head_rest", Vector3(0, 1.5, 0))
	att.visible = n != "civilian"
	for key in ["eye_l", "eye_r"]:
		var off: Vector3 = model.get_meta(key + "_local") if model.has_meta(key + "_local") else model.get_meta(key, head_rest) - head_rest
		var e := U.part(att, _eye_meshes[r], eye_mat, off)
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


func _play(clip: String, blend := -1.0, spd := 1.0, from := -1.0) -> void:
	anim_state = clip
	anim.play(clip, blend)
	anim.speed_scale = spd
	if from >= 0.0:
		anim.seek(from, true)


## Wind-up started: run the slash so its strike frame lands when the wind-up ends.
func _anim_attack(windup: float) -> void:
	if anim == null:
		return
	var lead := minf(strike_time, 0.9) # skip the clip's idle lead-in
	_play("attack", 0.08, lead / maxf(windup, 0.05), strike_time - lead)
	anim_lock_t = windup + 0.6


func _anim_strike() -> void:
	if anim != null and anim_state == "attack":
		anim.speed_scale = 1.5 # follow-through, then back to locomotion
		anim_lock_t = 0.45


func _anim_hit() -> void:
	if anim == null or dead:
		return
	if staggered:
		_play("hit", 0.08, 1.2, 0.0)
		anim_state = "stagger"
	else:
		_play("hit", 0.06, 1.6, 0.05)
		anim_lock_t = 0.45


## Skeletal animation: locomotion by speed, one-shots on top (driven from _animate).
func _anim_update(delta: float, spd: float) -> void:
	anim_lock_t = maxf(anim_lock_t - delta, 0.0)
	if dead:
		return
	if exec_t > 0.0:
		return # execution_victim() drives the clips until the killing cut
	if special != "":
		return # the second attack plays its own clips (_special_tick)
	if transform_t > 0.0:
		if anim_state != "transform":
			_play("hit", 0.1, 0.7, 0.2) # writhing through the change
			anim_state = "transform"
		return
	if staggered:
		if anim_state != "stagger":
			_play("hit", 0.1, 1.2, 0.0)
			anim_state = "stagger"
		# hold the slump at the bottom of the flinch
		anim.speed_scale = 0.0 if anim.current_animation_position >= 0.5 else 1.2
		return
	if anim_lock_t > 0.0 and anim_state in ["attack", "hit"]:
		return
	var want := "idle"
	if spd > 0.4:
		want = "sprint" if spd > (6.0 if anim_state != "sprint" else 5.4) else "run"
	if want != anim_state:
		_play(want, 0.2)
	match want:
		"run":
			anim.speed_scale = clampf(spd / 4.2, 0.6, 1.5)
		"sprint":
			anim.speed_scale = clampf(spd / 8.0, 0.8, 1.3)
		_:
			anim.speed_scale = 1.0


func _process(delta: float) -> void:
	if anim == null or not is_instance_valid(anim):
		return
	anim_accum += delta
	# full rate up close, every 2nd frame past 25 m, every 3rd past 45 m
	var step := 1
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var d2 := cam.global_position.distance_squared_to(global_position)
		step = 3 if d2 > 2025.0 else (2 if d2 > 625.0 else 1)
	if step > 1 and (Engine.get_process_frames() + anim_slot) % step != 0:
		return
	anim.advance(anim_accum)
	anim_accum = 0.0


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
	Audio.on_wolf_transform(global_position) # AUDIO HOOK


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
	if special != "":
		_cancel_special()
	if marker != null:
		marker.visible = false
	main.release_attack_token(self)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var player = main.player
	attack_cd = maxf(attack_cd - delta, 0.0)
	special_cd = maxf(special_cd - delta, 0.0)
	exec_t = maxf(exec_t - delta, 0.0)
	engaged_t = maxf(engaged_t - delta, 0.0)
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
	if special != "" and (transform_t > 0.0 or staggered or player == null or player.dead):
		_cancel_special()
	if transform_t > 0.0:
		transform_t -= delta
	elif special != "":
		_special_tick(player, delta) # moves the body itself (no avoidance steering mid-leap)
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(strike_dir.x, strike_dir.z), 14.0 * delta)
		engaged_t = 4.0
		_animate(delta, 0.0)
		_update_bar(player)
		return
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
			var sp := _special_name()
			var band: float = attack_range + 4.0
			if sp != "":
				band = maxf(band, float(SPECIALS[sp].max))
			var token: bool = dist < band and main.request_attack_token(self)
			if not token and dist >= band:
				main.release_attack_token(self)
			if token and sp != "" and special_cd <= 0.0 and attack_cd <= 0.0 and speed > 0.0 \
					and dist >= float(SPECIALS[sp].min) and dist <= float(SPECIALS[sp].max):
				_start_special(sp, player, to, dist)
				look = strike_dir
			elif token and sp != "" and special_cd <= 0.0 and attack_cd <= 0.0 and speed > 0.0 \
					and dist < float(SPECIALS[sp].min):
				if randf() < BACKSTEP_CHANCE:
					_start_backstep(sp, to, dist)
					look = strike_dir
				else:
					special_cd = randf_range(1.0, 2.0) # swipe for now, think about it again soon
			elif token and dist <= attack_range:
				if attack_cd <= 0.0:
					strike_dir = to / dist if dist > 0.01 else Vector3(sin(visual.rotation.y), 0, cos(visual.rotation.y))
					windup_t = 0.38 if kind == VAMPIRE else 0.45
					attack_cd = 1.1 if kind == VAMPIRE else 1.3
					_anim_attack(windup_t)
					Audio.enemy_bark(self) # AUDIO HOOK
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
	_update_bar(player)


# ---------------------------------------------------------------- second attacks (SPECIALS)
## This enemy's second attack: vampires lunge, changed wolves leap. "" for the rest (people by day).
func _special_name() -> String:
	if kind == VAMPIRE:
		return "lunge"
	if kind == WEREWOLF and transformed:
		return "leap"
	return ""


func _start_special(sp: String, player, to: Vector3, dist: float) -> void:
	var d: Dictionary = SPECIALS[sp]
	special = sp + "_windup"
	special_t = float(d.windup)
	special_cd = float(d.cd) * randf_range(0.85, 1.25)
	attack_cd = maxf(attack_cd, 0.8)
	special_hit = false
	strike_dir = to / maxf(dist, 0.01)
	special_from = global_position
	if telegraph != null and is_instance_valid(telegraph):
		telegraph.queue_free()
	if sp == "lunge":
		var reach := minf(dist + 1.5, float(d.dist))
		special_to = global_position + strike_dir * reach
		telegraph = HFx.line_telegraph(main, global_position, strike_dir, reach + 0.6, float(d.width), special_t, d.color)
		# rear back: the slash clip's own wind-up, slowed into a crouch
		if anim != null:
			_play("attack", 0.1, 0.45, maxf(strike_time - 0.9, 0.0))
	else:
		# onto where Sol is (a touch ahead of his run), never past the band
		var tgt: Vector3 = player.global_position + Vector3(player.velocity.x, 0, player.velocity.z) * 0.25
		var off := tgt - global_position
		off.y = 0.0
		if off.length() > float(d.max):
			off = off.normalized() * float(d.max)
		special_to = global_position + off
		telegraph = HFx.circle_telegraph(main, special_to, float(d.radius), special_t + float(d.air), d.color)
		# the crouch before the spring: the jump clip's take-off, slowed
		if anim != null:
			_play("jump", 0.1, 0.55, 0.0)
	Audio.enemy_bark(self) # AUDIO HOOK
	knockback = Vector3.ZERO


## Too close for the special: hop back (facing Sol) to open it from range (_special_tick).
func _start_backstep(sp: String, to: Vector3, dist: float) -> void:
	special = sp + "_back"
	special_t = BACKSTEP_TIME
	strike_dir = to / maxf(dist, 0.01) if dist > 0.01 else Vector3(sin(visual.rotation.y), 0, cos(visual.rotation.y))
	attack_cd = maxf(attack_cd, 0.4)
	if anim != null and anim.has_animation("run"):
		anim.play_backwards("run", 0.1)
		anim.speed_scale = 1.3
		anim_state = "run_back"


func _cancel_special() -> void:
	special = ""
	special_t = 0.0
	if telegraph != null and is_instance_valid(telegraph):
		telegraph.queue_free()
	telegraph = null
	anim_state = "" # locomotion picks up again


func _special_tick(player, delta: float) -> void:
	special_t -= delta
	var sp := special.get_slice("_", 0)
	var d: Dictionary = SPECIALS[sp]
	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	match special:
		"lunge_windup", "leap_windup":
			_apply_velocity(Vector3.ZERO, delta)
			if special_t <= 0.0:
				special = sp
				special_t = (special_from.distance_to(special_to) / float(d.speed)) if sp == "lunge" else float(d.air)
				special_from = global_position
				if anim != null:
					if sp == "lunge":
						_play("sprint", 0.05, 1.7)
					else:
						_play("jump", 0.05, 1.3, 0.35)
		"lunge":
			_apply_velocity(strike_dir * float(d.speed), delta)
			# the first contact strikes: Sol close and in front of the dash
			if not special_hit and to.length() < 1.3 and (to.length() < 0.5 or strike_dir.dot(to.normalized()) > 0.2):
				special_hit = true
				player.take_damage(damage * float(d.dmg), self) # a dash through it is a perfect dodge
				special_t = 0.0
			if special_t <= 0.0:
				if not special_hit and to.length() < 4.0 and player.dashed_recently(0.4):
					main.perfect_dodge() # he dashed out of the lunge's line
				_recover(0.45)
		"leap":
			var k := clampf(1.0 - special_t / float(d.air), 0.0, 1.0)
			var want := special_from.lerp(special_to, k) + Vector3.UP * 4.0 * float(d.height) * k * (1.0 - k)
			velocity = (want - global_position) / maxf(delta, 0.001)
			move_and_slide()
			if special_t <= 0.0:
				_slam(player, d)
				_recover(0.55)
		"lunge_back", "leap_back":
			_apply_velocity(-strike_dir * BACKSTEP_SPEED, delta)
			if special_t <= 0.0:
				special = ""
				var dist := to.length()
				_start_special(sp, player, to if dist > 0.01 else strike_dir, maxf(dist, 0.01))
		_: # recover: the follow-through, then back to the fight
			_apply_velocity(Vector3.ZERO, delta)
			if special_t <= 0.0:
				_cancel_special()


func _recover(t: float) -> void:
	special = special.get_slice("_", 0) + "_recover"
	special_t = t
	if telegraph != null and is_instance_valid(telegraph):
		telegraph.queue_free()
	telegraph = null
	if anim != null:
		_play("attack", 0.06, 1.5, maxf(strike_time - 0.12, 0.0)) # the swipe's follow-through


## The leap lands: a ring on the ground, damage inside it, a shake for Sol nearby.
func _slam(player, d: Dictionary) -> void:
	HFx.shockwave(main, global_position, float(d.radius), d.color, 0.4)
	var to: Vector3 = player.global_position - global_position
	var flat := Vector2(to.x, to.z).length()
	if flat < float(d.radius) and to.y < 1.4:
		player.take_damage(damage * float(d.dmg), self)
	elif flat < float(d.radius) + 2.5 and player.dashed_recently(0.4):
		main.perfect_dodge()
	if flat < 9.0:
		player.shake = maxf(player.shake, 0.22)
		main.rumble(0.3, 0.5, 0.15)
	Audio.play_at("wolf_growl", global_position, 2.0) # AUDIO HOOK


# ---------------------------------------------------------------- health bar
## A thin bar over an engaged enemy: pale while he fights, red at or below STAGGER_FRAC (the next
## heavy hit staggers him: bite or execute), pulsing while staggered.
func _update_bar(player) -> void:
	if dead:
		if hp_bar != null:
			hp_bar.visible = false
		return
	if player != null and not player.dead and speed > 0.0:
		if windup_t > 0.0 or main.attack_tokens.has(self) or global_position.distance_squared_to(player.global_position) < 64.0:
			engaged_t = maxf(engaged_t, 2.5)
	var show := engaged_t > 0.0 or staggered
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(global_position) < 6.25:
		show = false # right at the lens it would cover the screen (the bar draws over everything)
	if not show:
		if hp_bar != null:
			hp_bar.visible = false
		return
	if hp_bar == null:
		_build_bar()
	hp_bar.visible = true
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var low := frac <= STAGGER_FRAC + 0.001 or staggered
	var col := Color(0.86, 0.82, 0.78)
	if low:
		col = Color(0.95, 0.06, 0.05)
		if staggered:
			col = col.lerp(Color(1.0, 0.55, 0.45), 0.5 + 0.5 * sin(phase * 2.0))
	hp_bar_mat.set_shader_parameter("frac", frac)
	hp_bar_mat.set_shader_parameter("fill_col", col)
	var h := 2.95 if model_name == "werewolf" else 2.2
	var s := visual.scale.y
	if model != null:
		s *= model.scale.y
	hp_bar.position.y = h * s + 0.12


func _build_bar() -> void:
	if _bar_shader == null:
		_bar_shader = Shader.new()
		_bar_shader.code = BAR_SHADER
		_bar_mesh = QuadMesh.new()
		_bar_mesh.size = BAR_SIZE
	hp_bar_mat = ShaderMaterial.new()
	hp_bar_mat.shader = _bar_shader
	hp_bar_mat.render_priority = 2
	hp_bar = MeshInstance3D.new()
	hp_bar.name = "HealthBar"
	hp_bar.mesh = _bar_mesh
	hp_bar.material_override = hp_bar_mat
	hp_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hp_bar.extra_cull_margin = 1.0
	add_child(hp_bar)


# ---------------------------------------------------------------- the execution (player.gd _finisher)
## Sol starts Sword Judgment on this (staggered) enemy: face him, reel slowly on the wind-up, flinch
## again halfway in, then execution_death() on the strike frame.
func execution_victim(by: Node3D, strike_delay: float) -> void:
	if dead:
		return
	_cancel_special()
	exec_t = strike_delay + 0.6
	knockback = Vector3.ZERO
	var to := by.global_position - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		visual.rotation.y = atan2(to.x, to.z)
	if anim != null:
		_play("hit", 0.06, 0.5, 0.0)
		anim_state = "executed"
	var tw := create_tween()
	tw.tween_interval(strike_delay * 0.5)
	tw.tween_callback(func():
		if dead or anim == null:
			return
		_play("hit", 0.05, 0.9, 0.12)
		anim_state = "executed"
		flash_t = 0.12)


## The killing cut: thrown back along Sol's swing with a blood burst (the death clip is already playing).
func execution_death(fwd: Vector3) -> void:
	exec_t = 0.0
	var dir := Vector3(fwd.x, 0, fwd.z).normalized()
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position + dir * 1.3, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	HFx.puff(main, global_position + Vector3(0, 1.2, 0) + dir * 0.2, Color(0.55, 0.0, 0.03), 18, 0.2, 3.5)


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
	_anim_strike()
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
	var lean := 0.0
	if anim != null: # the clips carry the bob and most of the body language
		visual.position.y = 0.0
		if staggered:
			lean = 0.2
		elif windup_t > 0.0:
			lean = -0.1
		elif transformed:
			lean = 0.12
		# burning: a shiver on top of whatever clip is playing
		visual.rotation.z = (sin(phase * 9.0) * 0.035) if burning else 0.0
	else:
		visual.position.y = absf(sin(phase)) * 0.06 * clampf(spd / 5.0, 0.0, 1.0)
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
		if anim != null:
			_anim_update(delta, spd)
		else:
			_pose(delta, spd)
	eye_mat.emission_energy_multiplier = (9.0 if (windup_t > 0.0 or special.ends_with("_windup")) else 5.0) if (kind == VAMPIRE or transformed) else 0.0
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
	engaged_t = 5.0
	if special != "":
		_cancel_special() # a hit breaks the lunge / leap
	main.release_attack_token(self)
	knockback = dir * (6.0 if kind == VAMPIRE and not transformed else 3.0)
	if hp <= max_hp * STAGGER_FRAC:
		staggered = true
		stagger_t = 3.0
		marker.visible = true
		hp = maxf(hp, 1.0)
	_anim_hit()


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
	if hp_bar != null:
		hp_bar.visible = false
	if special != "":
		_cancel_special()
	main.release_attack_token(self)
	if agent != null:
		agent.avoidance_enabled = false
	collision_layer = 0
	collision_mask = 0
	main.on_enemy_killed(self, _drained)
	Audio.on_enemy_died(self) # AUDIO HOOK
	var tw := create_tween()
	if anim != null:
		visual.rotation.z = 0.0
		_play("death", 0.1, 2.0 if kind == VAMPIRE else 1.25, 0.0)
	if kind == VAMPIRE:
		if anim != null: # crumple into the fall while greying, then collapse to ash
			overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			_set_overlay(Color(0.3, 0.3, 0.3, 0.05))
			tw.tween_property(overlay_mat, "albedo_color", Color(0.3, 0.3, 0.3, 0.92), 0.7)
		elif model != null: # turn to ash: grey, shaded overlay
			overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			_set_overlay(Color(0.3, 0.3, 0.3, 0.05))
			tw.tween_property(overlay_mat, "albedo_color", Color(0.3, 0.3, 0.3, 0.92), 0.25)
			tw.parallel()
		tw.tween_property(body_mat, "albedo_color", Color(0.25, 0.25, 0.25), 0.25)
		tw.parallel().tween_property(skin_mat, "albedo_color", Color(0.3, 0.3, 0.3), 0.25)
		tw.tween_property(visual, "scale", Vector3(1.4, 0.02, 1.4), 0.45)
	else:
		_set_overlay(Color(1, 1, 1, 0))
		if anim != null: # the clip does the fall; lie there, then sink away
			tw.tween_interval(3.0)
		else:
			tw.tween_property(visual, "rotation:x", -1.5, 0.45).set_ease(Tween.EASE_IN)
			tw.tween_interval(1.2)
		tw.tween_property(visual, "scale", Vector3.ZERO, 0.4)
	tw.tween_callback(queue_free)
