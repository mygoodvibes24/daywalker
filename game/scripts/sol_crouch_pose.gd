extends SkeletonModifier3D
## The procedural crouch (round 3, the owner: "I definitely want a crouch option"). Until real crouch
## clips are installed (docs/animation_reference/README.md), this bends whatever the AnimationTree
## plays (idle, or the walk for the crouch walk) into a low, stalking crouch:
##   - the hips drop DROP m, sit back a little and tip forward;
##   - each leg is re-solved with a two-bone IK so the foot stays exactly where the clip put it (a
##     planted foot stays planted, a stepping foot still steps) and the knee bends forward;
##   - the spine leans forward over the knees and the neck tips back so he still looks ahead.
## `amount` (0..1) is eased by sol_modular_anim.gd; with crouch clips present it stays 0 (the clips
## carry the pose). Runs after Strafe, before ArmPose / DrawIK / SwordWrist. Nothing at amount 0.

const DROP := 0.3 # m the hips sink at full crouch
const SIT_BACK := 0.05 # m the hips move back
const HIP_PITCH := 0.22 # rad the pelvis tips forward
const SPINE := ["Spine02", "Spine01", "Spine"]
const SPINE_PITCH := [0.13, 0.11, 0.08] # rad, bottom to top
const HEAD := ["neck", "Head"]
const HEAD_PITCH := [-0.18, -0.16] # look back up
const LEGS := [["LeftUpLeg", "LeftLeg", "LeftFoot"], ["RightUpLeg", "RightLeg", "RightFoot"]]
const KNEE_OUT := 0.25 # the knees open a little outward (share of the pole)
const FOOT_OUT := 0.03 # m each foot widens at full crouch (a steadier base)
const ANKLE_Y := 0.16 # the ankle bone's height with the foot flat (skeleton space)
const LIFT_CUT := 0.55 # share of a stepping foot's lift removed at full crouch
const STRIDE_CUT := 0.15 # share of the feet's reach fore and aft removed at full crouch

var amount := 0.0
var last_drop := 0.0 # m the hips went down on the last pass (smoke test)
var _hips := -1
var _hips_rest_inv := Basis()
var _spine := PackedInt32Array()
var _head := PackedInt32Array()
var _legs: Array[PackedInt32Array] = []


func _init_bones(sk: Skeleton3D) -> bool:
	_hips = sk.find_bone("Hips")
	if _hips < 0:
		return false
	_hips_rest_inv = sk.get_bone_global_rest(_hips).basis.orthonormalized().inverse()
	for n in SPINE:
		_spine.append(sk.find_bone(n))
	for n in HEAD:
		_head.append(sk.find_bone(n))
	for leg in LEGS:
		var ids := PackedInt32Array()
		for n in leg:
			ids.append(sk.find_bone(n))
		_legs.append(ids)
	for arr in [_spine, _head] + _legs:
		if (arr as PackedInt32Array).has(-1):
			_hips = -1
			return false
	return true


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or amount <= 0.001:
		return
	if _hips < 0 and not _init_bones(sk):
		amount = 0.0
		return
	var c := amount * amount * (3.0 - 2.0 * amount)
	var gh := sk.get_bone_global_pose(_hips)
	# the facing (hips' yaw only) and its side axis
	var fwd := gh.basis.orthonormalized() * _hips_rest_inv * Vector3.BACK
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.BACK
	var side := Vector3.UP.cross(fwd).normalized() # +X at rest: his left
	# the leg chains as the clip left them
	var chains: Array = []
	for ids in _legs:
		chains.append([sk.get_bone_global_pose(ids[0]), sk.get_bone_global_pose(ids[1]), sk.get_bone_global_pose(ids[2])])
	# hips: down, back and tipped forward (rotating about +side takes the top forward)
	var nh := Transform3D(Basis(side, HIP_PITCH * c) * gh.basis, gh.origin + Vector3(0, -DROP * c, 0) - fwd * (SIT_BACK * c))
	sk.set_bone_pose_position(_hips, nh.origin)
	last_drop = gh.origin.y - nh.origin.y
	sk.set_bone_pose_rotation(_hips, nh.basis.get_rotation_quaternion())
	var to_new := nh * gh.affine_inverse()
	# legs: keep each foot where the clip had it, knees forward (and a little out)
	for k in 2:
		var ids: PackedInt32Array = _legs[k]
		var ch: Array = chains[k]
		var gu: Transform3D = to_new * ch[0]
		var gl: Transform3D = to_new * ch[1]
		var gf: Transform3D = ch[2] # the foot's goal: unchanged
		var out := side * (1.0 if k == 0 else -1.0)
		# a stepping foot lifts less and reaches less far than in the upright walk (the bent legs
		# would otherwise fold the knee up to the chest)
		var goal := gf.origin + out * (FOOT_OUT * c)
		var lift := goal.y - ANKLE_Y
		if lift > 0.0:
			goal.y = ANKLE_Y + lift * (1.0 - LIFT_CUT * c)
		var reach := (goal - gh.origin).dot(fwd)
		goal -= fwd * (reach * STRIDE_CUT * c)
		var r := _two_bone(gu, gl, (to_new * gf).origin, goal, fwd + out * KNEE_OUT)
		var nu: Basis = r[0]
		var nl: Basis = r[1]
		sk.set_bone_pose_rotation(ids[0], (nh.basis.orthonormalized().inverse() * nu).get_rotation_quaternion())
		sk.set_bone_pose_rotation(ids[1], (nu.inverse() * nl).get_rotation_quaternion())
		sk.set_bone_pose_rotation(ids[2], (nl.inverse() * gf.basis.orthonormalized()).get_rotation_quaternion())
	# spine forward, neck and head back up
	var pg := nh.basis.orthonormalized()
	for i in _spine.size():
		pg = _tilt(sk, _spine[i], pg, side, SPINE_PITCH[i] * c)
	for i in _head.size():
		pg = _tilt(sk, _head[i], pg, side, HEAD_PITCH[i] * c)


## Turns bone `b` by `ang` about the skeleton-space `axis`, given its parent's global basis `pg`.
## Returns the bone's new global basis (the next child's parent).
static func _tilt(sk: Skeleton3D, b: int, pg: Basis, axis: Vector3, ang: float) -> Basis:
	var local := sk.get_bone_pose_rotation(b)
	var a := (pg.inverse() * axis).normalized()
	var nq := (Quaternion(a, ang) * local).normalized()
	sk.set_bone_pose_rotation(b, nq)
	return pg * Basis(nq)


## Analytic two-bone IK. gu / gl: the thigh and shin globals (moved with the hips), c0: the ankle under
## them, goal: where the ankle must go, pole: the knee's direction. Returns [thigh basis, shin basis].
static func _two_bone(gu: Transform3D, gl: Transform3D, c0: Vector3, goal: Vector3, pole: Vector3) -> Array:
	var a := gu.origin
	var b := gl.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c0)
	var to_goal := goal - a
	var d := clampf(to_goal.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.002)
	var n := to_goal.normalized() if to_goal.length() > 1e-4 else Vector3.DOWN
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var m := pole - n * pole.dot(n)
	if m.length() < 1e-4:
		m = Vector3.FORWARD
	m = m.normalized()
	var e := a + n * (l1 * cos_a) + m * (l1 * sqrt(1.0 - cos_a * cos_a))
	var nu := Basis(_arc(b - a, e - a)) * gu.basis.orthonormalized()
	var gl2 := Transform3D(nu, a) * (gu.affine_inverse() * gl)
	var c2 := gl2 * (gl.affine_inverse() * c0)
	var nl := Basis(_arc(c2 - e, a + n * d - e)) * gl2.basis.orthonormalized()
	return [nu, nl]


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var f := from.normalized()
	var t := to.normalized()
	var cr := f.cross(t)
	var dt := f.dot(t)
	if cr.length() < 1e-6:
		return Quaternion() if dt > 0.0 else Quaternion(Vector3.UP, PI)
	return Quaternion(cr.normalized(), acos(clampf(dt, -1.0, 1.0)))
