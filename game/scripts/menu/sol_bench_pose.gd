extends Node
## Poses Sol at the workbench for the main-menu set: standing upright, leaning slightly into
## the work, head bowed over the blade. The left fist steadies the blade near the hilt; the
## right draws a whetstone along it toward the tip on a slow loop.
##
## On the modular rig (sol_modular.scn) the `idle` clip plays underneath as the base (legs,
## hips, breathing); the spine, neck and head get small additive overrides and the arms are
## solved with a two-bone IK so the fists land on the blade whatever the proportions. On the
## older sol.scn the same targets are used without a base clip.
## Targets are in skeleton space: +X = Sol's left, +Y up, +Z = forward (toward the bench).

var skel: Skeleton3D
var anim: AnimationPlayer
var bi := {}
var t := 0.0
var stone: Node3D # whetstone, kept under the right fist (skeleton space)

## Where the hands work, relative to Sol's feet (set by the set so it matches the bench).
var blade_y := 1.02 # top face of the blade
var blade_z := 0.27 # the blade line on the bench
var stroke_from := -0.04 # x along the blade (Sol's right is -x)
var stroke_to := -0.46
var left_x := 0.24 # where the left fist pins the blade
var stroke_period := 2.8

## The modular rig uses auto-rig bone names and non-identity rest bases; its bones are mapped
## to the names used here, and rotations are applied in character space.
const MODULAR_NAMES := {
	"Hips": "Hips", "Spine": "Spine02", "Chest": "Spine01", "UpperChest": "Spine",
	"Neck": "neck", "Head": "Head",
	"Shoulder.L": "LeftShoulder", "Shoulder.R": "RightShoulder",
	"UpperArm.L": "LeftArm", "ForeArm.L": "LeftForeArm", "Hand.L": "LeftHand",
	"UpperArm.R": "RightArm", "ForeArm.R": "RightForeArm", "Hand.R": "RightHand",
}
var modular := false
var touched := PackedInt32Array() # bones this script writes; reset to rest after the clip
var damped := PackedInt32Array() # bones that keep a little of the clip (hips, legs)
var fist_off := {"Hand.L": Vector3.ZERO, "Hand.R": Vector3.ZERO} # wrist -> fist centre (skeleton space)
var fist_local := {"Hand.L": Vector3.ZERO, "Hand.R": Vector3.ZERO} # fist centre in the hand bone frame


func setup(s: Skeleton3D, player: AnimationPlayer = null) -> void:
	skel = s
	modular = skel.find_bone("LeftArm") >= 0 and skel.find_bone("UpperArm.L") < 0
	if modular:
		for k in MODULAR_NAMES:
			var i := skel.find_bone(MODULAR_NAMES[k])
			if i >= 0:
				bi[k] = i
	else:
		for i in skel.get_bone_count():
			bi[skel.get_bone_name(i)] = i
	for k in bi:
		if k != "Hips":
			touched.append(bi[k])
	if modular:
		for n in ["Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]:
			if skel.find_bone(n) >= 0:
				damped.append(skel.find_bone(n))
	# the idle clip as the base layer, advanced by hand so the overrides always land after it
	if player != null and player.has_animation("idle"):
		anim = player
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.play("idle")
		anim.seek(randf() * 2.0, true)
	# where the fist sits relative to the wrist bone: the centre of the hand mesh if there is one
	for side in ["L", "R"]:
		var key: String = "Hand." + side
		if not bi.has(key):
			continue
		var c := Vector3(0.0, -0.07, 0.0)
		for att in skel.get_children():
			if att is BoneAttachment3D and (att as BoneAttachment3D).bone_name == skel.get_bone_name(bi[key]):
				for mi in att.get_children():
					if mi is MeshInstance3D and String(mi.name).begins_with("Hand"):
						c = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb().get_center()
		fist_local[key] = c
	stone = Node3D.new()
	stone.name = "Whetstone"
	skel.add_child(stone)
	_pose(0.0, 0.0)


func _process(delta: float) -> void:
	t += delta
	_pose(t, delta)


func _has(names: Array) -> bool:
	for n in names:
		if not bi.has(n):
			return false
	return true


## Rotate a bone by `q`, given about character axes (+X left, +Y up, +Z forward), on top of
## whatever pose it has this frame (the clip, or rest).
func _rot(bone: String, q: Quaternion) -> void:
	if not bi.has(bone):
		return
	var b: int = bi[bone]
	if modular or anim != null:
		var par := skel.get_bone_parent(b)
		var pb := skel.get_bone_global_pose(par).basis.orthonormalized() if par >= 0 else Basis()
		var cur := Basis(skel.get_bone_pose_rotation(b))
		var local := pb.inverse() * Basis(q) * pb * cur
		skel.set_bone_pose_rotation(b, local.get_rotation_quaternion())
	else:
		skel.set_bone_pose_rotation(b, q * skel.get_bone_pose_rotation(b))


func _pose(time: float, delta: float) -> void:
	if skel == null or not _has(["Spine", "Chest", "Neck", "Head"]):
		return
	# start from rest on every bone we write, then let the clip lay its pose underneath
	for b in touched:
		skel.set_bone_pose_rotation(b, skel.get_bone_rest(b).basis.get_rotation_quaternion())
	if anim != null:
		anim.advance(delta)
		# the idle clip is a look-around idle (the hips swing ~80 degrees): at the bench only a
		# tenth of it is kept on the hips and legs, for life, and its vertical bob; the upper
		# body is posed from rest so his eyes and hands stay on the work
		for b in damped:
			var rest_q := skel.get_bone_rest(b).basis.get_rotation_quaternion()
			skel.set_bone_pose_rotation(b, rest_q.slerp(skel.get_bone_pose_rotation(b), 0.1))
		for b in touched:
			skel.set_bone_pose_rotation(b, skel.get_bone_rest(b).basis.get_rotation_quaternion())
		if bi.has("Hips"):
			var hr := skel.get_bone_rest(bi["Hips"]).origin
			var hp := skel.get_bone_pose_position(bi["Hips"])
			skel.set_bone_pose_position(bi["Hips"], Vector3(hr.x, lerpf(hr.y, hp.y, 0.5), hr.z))
	var breath := sin(time * 1.4)
	# slow stroke: draw the stone toward the tip, lift it a touch and bring it back
	var cyc := fmod(time / stroke_period, 1.0)
	var push := smoothstep(0.0, 0.6, cyc) * (1.0 - smoothstep(0.66, 1.0, cyc))
	var lift := sin(clampf((cyc - 0.62) / 0.38, 0.0, 1.0) * PI) * 0.03

	# torso: upright, leaning slightly into the work; the chest turns a touch with the stroke
	_rot("Spine", Quaternion(Vector3.RIGHT, 0.14 + breath * 0.006))
	_rot("Chest", Quaternion(Vector3.UP, -0.03 - push * 0.05) * Quaternion(Vector3.RIGHT, 0.09))
	_rot("UpperChest", Quaternion(Vector3.RIGHT, 0.05 + breath * 0.008))
	# shoulders roll forward a little, as when working with both hands in front
	_rot("Shoulder.L", Quaternion(Vector3.UP, 0.12))
	_rot("Shoulder.R", Quaternion(Vector3.UP, -0.12))
	_rot("Neck", Quaternion(Vector3.RIGHT, 0.3))
	# eyes on the edge, following the stone; now and then a glance along the blade
	var glance := smoothstep(0.85, 1.0, sin(time * 0.21) * 0.5 + 0.5)
	_rot("Head", Quaternion(Vector3.UP, -0.04 - push * 0.08 + glance * 0.25) * Quaternion(Vector3.RIGHT, 0.5 - glance * 0.15))

	if not _has(["UpperArm.L", "ForeArm.L", "Hand.L", "UpperArm.R", "ForeArm.R", "Hand.R"]):
		return
	var lfist := Vector3(left_x, blade_y + 0.045, blade_z + 0.01)
	var rx := lerpf(stroke_from, stroke_to, push)
	var rfist := Vector3(rx, blade_y + 0.035 + 0.05 + lift, blade_z + 0.0)
	# fists ride slightly over the blade; elbows point out and down
	_ik("UpperArm.L", "ForeArm.L", "Hand.L", lfist - fist_off["Hand.L"], Vector3(0.7, -0.7, -0.15))
	_ik("UpperArm.R", "ForeArm.R", "Hand.R", rfist - fist_off["Hand.R"], Vector3(-0.7, -0.7, -0.15))
	# wrists: knuckles down on the work
	_rot("Hand.L", Quaternion(Vector3.RIGHT, 0.35) * Quaternion(Vector3.BACK, 0.25))
	_rot("Hand.R", Quaternion(Vector3.RIGHT, 0.3) * Quaternion(Vector3.BACK, -0.3))
	# measure where the fists ended up, so next frame's wrist targets put them on the marks
	for key in ["Hand.L", "Hand.R"]:
		var g := skel.get_bone_global_pose(bi[key])
		var off: Vector3 = g.basis * (fist_local[key] as Vector3)
		fist_off[key] = (fist_off[key] as Vector3).lerp(off, 0.5 if time > 0.0 else 1.0)
	# the stone sits under the right fist, lying along the blade
	if stone != null:
		var rg := skel.get_bone_global_pose(bi["Hand.R"])
		var fc: Vector3 = rg * (fist_local["Hand.R"] as Vector3)
		stone.transform = Transform3D(Basis(Vector3.UP, 0.08), Vector3(fc.x, blade_y + 0.018 + lift, blade_z))


## Two-bone IK in skeleton space; `pole` is the direction the elbow should bend toward.
## Each bone swings from its current pose (clip or rest) by the smallest rotation, so the
## arm keeps its natural twist.
func _ik(upper: String, fore: String, hand: String, target: Vector3, pole: Vector3) -> void:
	var iu: int = bi[upper]
	var i_f: int = bi[fore]
	var ih: int = bi[hand]
	var parent := skel.get_bone_parent(iu)
	var pg: Transform3D = skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var s: Vector3 = pg * skel.get_bone_pose_position(iu)
	var c1 := skel.get_bone_pose_position(i_f) # forearm offset in the upper arm's frame
	var c2 := skel.get_bone_pose_position(ih)
	var a := c1.length()
	var b := c2.length()
	var to := target - s
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.005)
	var dir := to.normalized()
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var perp := (pole - dir * pole.dot(dir)).normalized()
	var elbow := s + dir * x + perp * h
	var hand_p := s + dir * d
	var pb := pg.basis.orthonormalized()
	var r_u := skel.get_bone_pose_rotation(iu)
	var d_cur := (r_u * c1).normalized()
	var d_want := (pb.inverse() * (elbow - s)).normalized()
	var q_up := (Quaternion(d_cur, d_want) * r_u).normalized()
	skel.set_bone_pose_rotation(iu, q_up)
	var ub := pb * Basis(q_up)
	var r_f := skel.get_bone_pose_rotation(i_f)
	d_cur = (r_f * c2).normalized()
	d_want = (ub.inverse() * (hand_p - elbow)).normalized()
	skel.set_bone_pose_rotation(i_f, (Quaternion(d_cur, d_want) * r_f).normalized())
