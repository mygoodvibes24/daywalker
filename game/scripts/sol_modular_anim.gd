extends RefCounted
## Animation for the modular Sol (res://assets/characters/sol/sol_modular.scn).
## Builds an AnimationTree over the scene's clip library:
##
##   loco (BlendSpace1D idle 0 / run 7.5 / sprint 13 m/s)  --+
##   jump (re-seeked on take-off) ----------------------- air (Blend2)
##   slash (time-scaled) ------------------------------ swing1 (OneShot)
##   slash_back (the same cut played backwards) ------- swing2 (OneShot)   combo 2 is the backhand
##   hit ------------------------------------------------ hit (OneShot)
##   death ---------------------------------------------- life (Transition alive/dead) -> output
##
## The tree runs on the physics tick, so the coat simulation (process priority 100) always sees
## this frame's pose.

const SWING_TIME := 0.34 # seconds for combo 1 and 2 (the game's swing_t is 0.22 + recovery)
const FINISHER_TIME := 0.5

var tree: AnimationTree
var sim: Node
var slash_len := 0.65
var air := 0.0
var was_air := false
var dead := false


func setup(model: Node) -> bool:
	var ap := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation_library(""):
		return false
	var lib := ap.get_animation_library("")
	for need in ["idle", "run", "sprint", "slash", "slash_back", "hit", "death", "jump"]:
		if not lib.has_animation(need):
			return false
	ap.active = false
	slash_len = lib.get_animation("slash").length
	sim = model.get_node_or_null("CoatSim")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.add_animation_library("", lib)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 16.0
	loco.add_blend_point(_clip("idle"), 0.0)
	loco.add_blend_point(_clip("run"), 7.5)
	loco.add_blend_point(_clip("sprint"), 13.0)
	bt.add_node("loco", loco)
	bt.add_node("jump", _clip("jump"))
	bt.add_node("jump_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("jump_seek", 0, "jump")
	bt.add_node("air", AnimationNodeBlend2.new())
	bt.connect_node("air", 0, "loco")
	bt.connect_node("air", 1, "jump_seek")
	var prev := "air"
	for s in [["swing1", "slash"], ["swing2", "slash_back"]]:
		bt.add_node(s[1], _clip(s[1]))
		bt.add_node(s[0] + "_speed", AnimationNodeTimeScale.new())
		bt.connect_node(s[0] + "_speed", 0, s[1])
		var os := AnimationNodeOneShot.new()
		os.fadein_time = 0.04
		os.fadeout_time = 0.14
		bt.add_node(s[0], os)
		bt.connect_node(s[0], 0, prev)
		bt.connect_node(s[0], 1, s[0] + "_speed")
		prev = s[0]
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
	return true


static func _clip(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a


## A sword swing for combo step 1..3 (2 is the backhand return).
func swing(combo: int, weapon_speed: float = 1.0) -> void:
	if tree == null or dead:
		return
	var dur := (FINISHER_TIME if combo >= 3 else SWING_TIME) / maxf(weapon_speed, 0.3)
	var node := "swing2" if combo == 2 else "swing1"
	var other := "swing1" if combo == 2 else "swing2"
	tree.set("parameters/%s_speed/scale" % node, slash_len / dur)
	tree.set("parameters/%s/request" % other, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	tree.set("parameters/%s/request" % node, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func hit() -> void:
	if tree == null or dead:
		return
	tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func die() -> void:
	if tree == null or dead:
		return
	dead = true
	for n in ["swing1", "swing2", "hit"]:
		tree.set("parameters/%s/request" % n, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.set("parameters/life/transition_request", "dead")


## s: speed (horizontal m/s), on_floor (bool).
func update(delta: float, s: Dictionary) -> void:
	if tree == null:
		return
	tree.set("parameters/loco/blend_position", float(s.speed))
	var in_air := not bool(s.on_floor)
	if in_air and not was_air:
		tree.set("parameters/jump_seek/seek_request", 0.0)
	was_air = in_air
	air = move_toward(air, 1.0 if in_air else 0.0, delta * (7.0 if in_air else 9.0))
	tree.set("parameters/air/blend_amount", air)
