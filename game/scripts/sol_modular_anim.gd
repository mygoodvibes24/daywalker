extends RefCounted
## Animation for the modular Sol (res://assets/characters/sol/sol_modular.scn).
## Builds an AnimationTree over the scene's clip library:
##
##   loco (BlendSpace1D idle 0 / run 7.5 / sprint 13 m/s) --+
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

const SolMoves = preload("res://scripts/sol_moves.gd")

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
var _slot := 1
var _slot_left := [0.0, 0.0] # seconds of the move left in each slot
var _has_stance := false


func setup(model: Node) -> bool:
	var ap := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation_library(""):
		return false
	lib = ap.get_animation_library("")
	for need in ["idle", "run", "sprint", "slash", "hit", "death", "jump"]:
		if not lib.has_animation(need):
			return false
	_has_stance = lib.has_animation("stance")
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
	loco.add_blend_point(_clip("idle"), 0.0)
	loco.add_blend_point(_clip("run"), 7.5)
	loco.add_blend_point(_clip("sprint"), 13.0)
	bt.add_node("loco", loco)
	bt.add_node("stance", _clip("stance" if _has_stance else "idle"))
	bt.add_node("combat", AnimationNodeBlend2.new())
	bt.connect_node("combat", 0, "loco")
	bt.connect_node("combat", 1, "stance")
	bt.add_node("jump", _clip("jump"))
	bt.add_node("jump_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("jump_seek", 0, "jump")
	bt.add_node("air", AnimationNodeBlend2.new())
	bt.connect_node("air", 0, "combat")
	bt.connect_node("air", 1, "jump_seek")
	var prev := "air"
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
	tree.set("parameters/life/transition_request", "alive")
	return true


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


## s: speed (horizontal m/s), on_floor (bool); in_combat (enemies near) is set by the player.
func update(delta: float, s: Dictionary) -> void:
	if tree == null:
		return
	var speed := float(s.speed)
	tree.set("parameters/loco/blend_position", speed)
	var in_air := not bool(s.on_floor)
	if in_air and not was_air:
		tree.set("parameters/jump_seek/seek_request", 0.0)
	was_air = in_air
	air = move_toward(air, 1.0 if in_air else 0.0, delta * (7.0 if in_air else 9.0))
	tree.set("parameters/air/blend_amount", air)
	# the combat stance only while standing (it has no legs for running)
	var want := (1.0 - clampf(speed / 3.0, 0.0, 1.0)) if (in_combat and _has_stance) else 0.0
	combat = move_toward(combat, want, delta * 3.0)
	tree.set("parameters/combat/blend_amount", combat)
	# a move runs out: fade it back into locomotion
	for i in 2:
		if _slot_left[i] > 0.0:
			_slot_left[i] -= delta
			if _slot_left[i] <= 0.0:
				tree.set("parameters/%s/request" % ("actA" if i == 0 else "actB"), AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	if wrist != null:
		wrist.amount = move_toward(wrist.amount, 0.0 if (move_playing() or dead) else 1.0, delta * (12.0 if move_playing() else 3.0))
