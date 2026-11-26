extends RefCounted
## Animation for the modular Sol (res://assets/characters/sol/sol_modular.scn).
## Builds an AnimationTree over the scene's clip library:
##
##   loco (BlendSpace1D idle 0 / walk 1.1 / run 4.6-7.5 / sprint 13 m/s) --+
##   crouch_loco (crouch_idle / crouch_walk; only once those clips are installed) -- crouch (Blend2)
##   stance (combat idle, looped) ----------------------- combat (Blend2: near enemies, standing)
##   jump (re-seeked on take-off) ----------------------- air (Blend2)
##   actA: clip -> seek -> speed ------------------------ actA (OneShot)   sword moves alternate between
##   actB: clip -> seek -> speed ------------------------ actB (OneShot)   two slots so they cross-fade
##   hit ------------------------------------------------ hit (OneShot)
##   death ---------------------------------------------- life (Transition alive/dead) -> output
##
## Sword moves are data (scripts/sol_moves.gd): play_move() takes a row (clip, from, to, speed) and
## plays that stretch of the clip in the next free slot. The tree runs on the physics tick, so the
## coat simulation (process priority 100) always sees this frame's pose. A SwordWrist modifier on the
## skeleton keeps the blade from pointing at the sky in locomotion; it is eased off during moves.
##
## Round 3 (locomotion): the walk is a real blend point (the bought "walk" clip, Casual_Walk; without it
## sol_locomotion.gd bakes a stand-in from the run); ArmPose (sol_arm_pose.gd) lets the empty right arm
## hang and swing while the sword is sheathed; Crouch (sol_crouch_pose.gd) bends the pose into a
## crouch until "crouch_idle" / "crouch_walk" clips exist. Skeleton modifier order:
## Strafe, Crouch, ArmPose, DrawIK (sol_sheath.gd), SwordWrist.

const SolMoves = preload("res://scripts/sol_moves.gd")
const SolStrafe = preload("res://scripts/sol_strafe.gd")
const SolLoco = preload("res://scripts/sol_locomotion.gd")
const SolArmPose = preload("res://scripts/sol_arm_pose.gd")
const SolCrouchPose = preload("res://scripts/sol_crouch_pose.gd")

var tree: AnimationTree
var bt: AnimationNodeBlendTree
var lib: AnimationLibrary
var sim: Node
var wrist: Node
var air := 0.0
var was_air := false
var dead := false
var combat := 0.0
var in_combat := false
var strafe: Node # sol_strafe.gd: legs toward the move, chest on the lock-on target
var _strafe_yaw := 0.0
var _backpedal := false
var armed := true # the sword is in his hand (player.gd / sol_sheath.gd); sheathed, the wrist rests
var _slot := 1
var _slot_left := [0.0, 0.0] # seconds of the move left in each slot
var _has_stance := false
var _has_fidget := false
const FIDGET_AFTER := 12.0 # seconds standing still (out of combat) before the look-around fidget
var still_t := 0.0
var fidgeting := false
var arm_pose: Node # sol_arm_pose.gd: the relaxed right arm while sheathed
var crouch_pose: Node # sol_crouch_pose.gd: the procedural crouch (no crouch clips yet)
var relaxed := false # player.gd: the hand is empty (sheathed, or reaching for the hilt)
var crouching := false # player.gd: Sol is crouched
var crouch := 0.0 # eased 0..1
var relax := 0.0 # eased 0..1 (ArmPose amount)
var walk_clip := "walk_proc" # "walk" once a real walk clip is installed
var has_crouch_clips := false
const RELAX_IN := 5.0 # per second: the arm settles once the sword is away
const RELAX_OUT := 7.0 # per second: the grip comes back as the blade leaves the scabbard
const CROUCH_RATE := 5.0 # per second (about 0.2 s down or up)


func setup(model: Node) -> bool:
	var ap := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation_library(""):
		return false
	lib = ap.get_animation_library("")
	for need in ["idle", "run", "sprint", "slash", "hit", "death", "jump"]:
		if not lib.has_animation(need):
			return false
	_has_stance = lib.has_animation("stance")
	_tame_root_yaw()
	walk_clip = SolLoco.bake_walk(lib, model.get_node_or_null("Skeleton3D") as Skeleton3D)
	has_crouch_clips = SolLoco.ensure_crouch_idle(lib)
	ap.active = false
	sim = model.get_node_or_null("CoatSim")
	wrist = model.find_child("SwordWrist", true, false)
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.add_animation_library("", lib)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	bt = AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 16.0
	loco.sync = true # every point keeps time: the two run points stay in step
	loco.add_blend_point(_clip("idle"), 0.0)
	loco.add_blend_point(_clip_at(walk_clip, SolLoco.clip_rate(walk_clip, SolLoco.WALK_SPEED)), SolLoco.WALK_SPEED)
	loco.add_blend_point(_clip("run"), SolLoco.RUN_POINT)
	loco.add_blend_point(_clip("run"), 7.5)
	loco.add_blend_point(_clip("sprint"), 13.0)
	bt.add_node("loco", loco)
	bt.add_node("loco_speed", AnimationNodeTimeScale.new()) # -1: the run backwards (lock-on backpedal)
	bt.connect_node("loco_speed", 0, "loco")
	var ground := "loco_speed"
	if has_crouch_clips:
		var cl := AnimationNodeBlendSpace1D.new()
		cl.sync = true
		cl.min_space = 0.0
		cl.max_space = 8.0
		cl.add_blend_point(_clip("crouch_idle"), 0.0)
		cl.add_blend_point(_clip_at("crouch_walk", SolLoco.clip_rate("crouch_walk", SolLoco.CROUCH_SPEED)), SolLoco.CROUCH_SPEED)
		bt.add_node("crouch_loco", cl)
		bt.add_node("crouch", AnimationNodeBlend2.new())
		bt.connect_node("crouch", 0, "loco_speed")
		bt.connect_node("crouch", 1, "crouch_loco")
		ground = "crouch"
	bt.add_node("stance", _clip("stance" if _has_stance else "idle"))
	bt.add_node("combat", AnimationNodeBlend2.new())
	bt.connect_node("combat", 0, ground)
	bt.connect_node("combat", 1, "stance")
	bt.add_node("jump", _clip("jump"))
	bt.add_node("jump_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("jump_seek", 0, "jump")
	bt.add_node("air", AnimationNodeBlend2.new())
	bt.connect_node("air", 0, "combat")
	bt.connect_node("air", 1, "jump_seek")
	var prev := "air"
	# the old look-around idle as a rare fidget after FIDGET_AFTER s standing still (round 2: the calm
	# Idle_02 breathing stance is the idle now)
	_has_fidget = lib.has_animation("idle_look")
	if _has_fidget:
		bt.add_node("fidget_clip", _clip("idle_look"))
		var fo := AnimationNodeOneShot.new()
		fo.fadein_time = 0.6
		fo.fadeout_time = 0.7
		bt.add_node("fidget", fo)
		bt.connect_node("fidget", 0, prev)
		bt.connect_node("fidget", 1, "fidget_clip")
		prev = "fidget"
	for s in ["actA", "actB"]:
		bt.add_node(s + "_clip", _clip("slash"))
		bt.add_node(s + "_seek", AnimationNodeTimeSeek.new())
		bt.connect_node(s + "_seek", 0, s + "_clip")
		bt.add_node(s + "_speed", AnimationNodeTimeScale.new())
		bt.connect_node(s + "_speed", 0, s + "_seek")
		var os := AnimationNodeOneShot.new()
		os.fadein_time = 0.06
		os.fadeout_time = 0.16
		bt.add_node(s, os)
		bt.connect_node(s, 0, prev)
		bt.connect_node(s, 1, s + "_speed")
		prev = s
	bt.add_node("hit_clip", _clip("hit"))
	bt.add_node("hit_speed", AnimationNodeTimeScale.new())
	bt.connect_node("hit_speed", 0, "hit_clip")
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.06
	hit.fadeout_time = 0.2
	bt.add_node("hit", hit)
	bt.connect_node("hit", 0, prev)
	bt.connect_node("hit", 1, "hit_speed")
	bt.add_node("death", _clip("death"))
	var life := AnimationNodeTransition.new()
	life.xfade_time = 0.2
	life.add_input("alive")
	life.add_input("dead")
	life.set_input_reset(1, true)
	bt.add_node("life", life)
	bt.connect_node("life", 0, "hit")
	bt.connect_node("life", 1, "death")
	bt.connect_node("output", 0, "life")
	tree.tree_root = bt
	tree.active = true
	tree.set("parameters/hit_speed/scale", 1.6)
	tree.set("parameters/loco_speed/scale", 1.0)
	for space in ["loco", "crouch_loco"]:
		if not bt.has_node(space):
			continue
		var bs := bt.get_node(space) as AnimationNodeBlendSpace1D
		for i in bs.get_blend_point_count():
			var n := bs.get_blend_point_node(i)
			if n.has_meta("rate"):
				tree.set("parameters/%s/%d/rate/scale" % [space, i], float(n.get_meta("rate")))
	var skel := model.get_node_or_null("Skeleton3D") as Skeleton3D
	if skel != null:
		strafe = SolStrafe.new()
		strafe.name = "Strafe"
		skel.add_child(strafe)
		skel.move_child(strafe, 0) # first: the draw reach and the wrist work on the twisted pose
		crouch_pose = SolCrouchPose.new()
		crouch_pose.name = "Crouch"
		skel.add_child(crouch_pose)
		skel.move_child(crouch_pose, 1)
		arm_pose = SolArmPose.new()
		arm_pose.name = "ArmPose"
		skel.add_child(arm_pose)
		skel.move_child(arm_pose, 2) # before DrawIK: the reach starts from the relaxed arm
	tree.set("parameters/life/transition_request", "alive")
	return true


## Clips whose mocap spins the whole body (the hips' yaw): the light combo's second and third cuts turn
## Sol up to ~140 deg off his gameplay facing (combo2 ends facing sideways, combo3 starts there and
## swings back), so the cut reads off-target and he drifts sideways. Their hips yaw is pulled toward
## the clip set's neutral facing, keeping only YAW_KEEP of the turn (at most YAW_MAX degrees).
const YAW_TAME := ["combo2", "combo3"]
const YAW_KEEP := 0.3
const YAW_MAX := 30.0


static func _hips_yaw(q: Quaternion) -> float:
	var f := Basis(q) * Vector3.BACK
	return atan2(f.x, f.z)


## Runs once per clip library (it is shared by every Sol instance; a meta flag marks it done).
func _tame_root_yaw() -> void:
	var ref := lib.get_animation("stance" if _has_stance else "idle")
	var rt := ref.find_track(NodePath("Skeleton3D:Hips"), Animation.TYPE_ROTATION_3D)
	if rt < 0 or ref.track_get_key_count(rt) == 0:
		return
	var neutral := _hips_yaw(ref.track_get_key_value(rt, 0))
	for cname in YAW_TAME:
		if not lib.has_animation(cname):
			continue
		var a := lib.get_animation(cname)
		if a.has_meta("yaw_tamed"):
			continue
		var t := a.find_track(NodePath("Skeleton3D:Hips"), Animation.TYPE_ROTATION_3D)
		if t < 0:
			continue
		for k in a.track_get_key_count(t):
			var q: Quaternion = a.track_get_key_value(t, k)
			var dev := wrapf(_hips_yaw(q) - neutral, -PI, PI)
			var keep := clampf(dev * YAW_KEEP, -deg_to_rad(YAW_MAX), deg_to_rad(YAW_MAX))
			a.track_set_key_value(t, k, (Quaternion(Vector3.UP, keep - dev) * q).normalized())
		a.set_meta("yaw_tamed", true)


## A clip played at `rate` (a small blend tree: clip -> time scale), for a blend point whose clip has a
## different pace from the ground speed it stands for.
static func _clip_at(name: String, rate: float) -> AnimationRootNode:
	if absf(rate - 1.0) < 0.02:
		return _clip(name)
	var t := AnimationNodeBlendTree.new()
	t.add_node("clip", _clip(name))
	var ts := AnimationNodeTimeScale.new()
	t.add_node("rate", ts)
	t.connect_node("rate", 0, "clip")
	t.connect_node("output", 0, "rate")
	t.set_meta("rate", rate) # the scale is a parameter: set after the tree is built (setup)
	return t


static func _clip(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a


## Play a move row from sol_moves.gd (clip, from, to, speed); `rate` is the blade's speed.
## Returns the seconds until the strike frame. Falls back to the old slash if the clip is missing.
func play_move(m: Dictionary, rate: float = 1.0, back: bool = false) -> float:
	if tree == null or dead:
		return 0.0
	if not lib.has_animation(m.get("clip", "")):
		m = SolMoves.FALLBACK_BACK if back else SolMoves.FALLBACK
	var spd := float(m.speed) * maxf(rate, 0.3)
	var from := float(m.from)
	var to := minf(float(m.to), lib.get_animation(m.clip).length)
	var other := "actA" if _slot == 1 else "actB"
	_slot = 1 - _slot
	var slot := "actA" if _slot == 0 else "actB"
	(bt.get_node(slot + "_clip") as AnimationNodeAnimation).animation = m.clip
	tree.set("parameters/%s_seek/seek_request" % slot, from)
	tree.set("parameters/%s_speed/scale" % slot, spd)
	tree.set("parameters/%s/request" % other, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	tree.set("parameters/%s/request" % slot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_slot_left[_slot] = (to - from) / spd
	_slot_left[1 - _slot] = 0.0
	return maxf(float(m.get("hit", from)) - from, 0.0) / spd


## Old entry point: combo step 1..3 of the light combo.
func swing(combo: int, weapon_speed: float = 1.0) -> void:
	play_move(SolMoves.move(SolMoves.combo_step("light", combo)), weapon_speed, combo == 2)


## Cut any move short (fades back to locomotion).
func stop_moves() -> void:
	if tree == null:
		return
	for s in ["actA", "actB"]:
		tree.set("parameters/%s/request" % s, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_slot_left = [0.0, 0.0]


func move_playing() -> bool:
	return _slot_left[0] > 0.0 or _slot_left[1] > 0.0


func hit() -> void:
	if tree == null or dead:
		return
	tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func die() -> void:
	if tree == null or dead:
		return
	dead = true
	for n in ["actA", "actB", "hit"]:
		tree.set("parameters/%s/request" % n, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.set("parameters/life/transition_request", "dead")


## Lock-on strafe: `rel` is the move direction relative to the facing (radians), `on` false eases back.
## Up to ~110 deg off the facing the legs turn toward the move; behind that he backpedals (the run
## played backwards, the legs turned toward the opposite of the move).
func set_strafe(rel: float, on: bool, delta: float) -> void:
	var want := 0.0
	var back := false
	if on:
		rel = wrapf(rel, -PI, PI)
		if absf(rel) <= deg_to_rad(110.0):
			want = clampf(rel, -1.25, 1.25)
		else:
			back = true
			want = clampf(wrapf(rel - PI, -PI, PI), -1.25, 1.25)
	if back != _backpedal:
		_backpedal = back
		if tree != null:
			tree.set("parameters/loco_speed/scale", -1.0 if back else 1.0)
	_strafe_yaw = lerp_angle(_strafe_yaw, want, minf(10.0 * delta, 1.0))
	if strafe != null:
		strafe.yaw = _strafe_yaw if absf(_strafe_yaw) > 0.002 else 0.0


## s: speed (horizontal m/s), on_floor (bool); in_combat (enemies near) is set by the player.
func update(delta: float, s: Dictionary) -> void:
	if tree == null:
		return
	var speed := float(s.speed)
	tree.set("parameters/loco/blend_position", speed)
	var in_air := not bool(s.on_floor)
	# the crouch: crouch clips when installed, else the procedural pose
	crouch = move_toward(crouch, 1.0 if (crouching and not dead) else 0.0, delta * CROUCH_RATE)
	if has_crouch_clips:
		tree.set("parameters/crouch/blend_amount", crouch)
		tree.set("parameters/crouch_loco/blend_position", speed)
	elif crouch_pose != null:
		crouch_pose.amount = crouch * (1.0 - air)
	# the empty right hand hangs and swings (sheathed); the sword's grip returns as it is drawn
	var want_relax := 1.0 if (relaxed and not dead) else 0.0
	relax = move_toward(relax, want_relax, delta * (RELAX_IN if want_relax > relax else RELAX_OUT))
	if arm_pose != null:
		arm_pose.amount = relax
		arm_pose.dt = delta
		arm_pose.swing = move_toward(arm_pose.swing, clampf(speed / 1.2, 0.0, 1.0) if not in_air else 0.0, delta * 4.0)
	if in_air and not was_air:
		tree.set("parameters/jump_seek/seek_request", 0.0)
	was_air = in_air
	air = move_toward(air, 1.0 if in_air else 0.0, delta * (7.0 if in_air else 9.0))
	tree.set("parameters/air/blend_amount", air)
	# the combat stance only while standing (it has no legs for running)
	var want := (1.0 - clampf(speed / 3.0, 0.0, 1.0)) if (in_combat and _has_stance) else 0.0
	combat = move_toward(combat, want, delta * 3.0)
	tree.set("parameters/combat/blend_amount", combat)
	# the long-idle fidget: only standing still, out of combat, no move playing
	if _has_fidget:
		var calm := speed < 0.2 and not in_air and not in_combat and not move_playing() and not dead
		if calm:
			still_t += delta
			if still_t >= FIDGET_AFTER:
				tree.set("parameters/fidget/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
				fidgeting = true
				still_t = -lib.get_animation("idle_look").length # the next one waits a full spell again
		else:
			still_t = 0.0
			if fidgeting:
				tree.set("parameters/fidget/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
				fidgeting = false
	# a move runs out: fade it back into locomotion
	for i in 2:
		if _slot_left[i] > 0.0:
			_slot_left[i] -= delta
			if _slot_left[i] <= 0.0:
				tree.set("parameters/%s/request" % ("actA" if i == 0 else "actB"), AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	if wrist != null:
		wrist.amount = move_toward(wrist.amount, 0.0 if (move_playing() or dead or not armed) else 1.0, delta * (12.0 if move_playing() or not armed else 3.0))
