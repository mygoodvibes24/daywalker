extends SkeletonModifier3D
## The draw / sheathe reach: a two-bone IK on Sol's right arm that pulls the hand to the sword's grip
## on his back (scripts/sol_sheath.gd sets `target` and eases `weight` 0..1). Runs after the
## AnimationTree pose, before SwordWrist; one analytic solve per frame, and nothing at weight 0.

@export var upper_name := "RightArm"
@export var lower_name := "RightForeArm"
@export var hand_name := "RightHand"
## Where the elbow goes while reaching over the shoulder (skeleton space, from the shoulder): up and
## out to Sol's right (-X), a little back.
@export var pole := Vector3(-0.55, 0.75, -0.25)
var weight := 0.0
var target := Transform3D() # the hand's wanted GLOBAL transform (origin = wrist, basis = hand frame)
var orient := 0.0 # 0..1: how much of the hand's rotation follows target.basis (the grip)
var _ub := -1
var _lb := -1
var _hb := -1


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or weight <= 0.001:
		return
	if _ub < 0:
		_ub = sk.find_bone(upper_name)
		_lb = sk.find_bone(lower_name)
		_hb = sk.find_bone(hand_name)
		if _ub < 0 or _lb < 0 or _hb < 0:
			weight = 0.0
			return
	var to_sk := sk.global_transform.affine_inverse()
	var t_sk := to_sk * target
	var gu := sk.get_bone_global_pose(_ub)
	var gl := sk.get_bone_global_pose(_lb)
	var gh := sk.get_bone_global_pose(_hb)
	var a := gu.origin
	var b := gl.origin
	var c := gh.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	# blend the goal from the clip's own wrist toward the target, so the arm travels there
	var goal := c.lerp(t_sk.origin, weight)
	var to_goal := goal - a
	var d := clampf(to_goal.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.005)
	var n := to_goal.normalized() if to_goal.length() > 1e-4 else (c - a).normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var m := pole - n * pole.dot(n)
	if m.length() < 1e-4:
		m = Vector3.UP - n * n.y
	m = m.normalized()
	var e := a + n * (l1 * cos_a) + m * (l1 * sqrt(1.0 - cos_a * cos_a))
	# upper arm: swing (b - a) onto (e - a)
	var nu := Basis(_arc(b - a, e - a)) * gu.basis
	var pu := sk.get_bone_parent(_ub)
	var pg := sk.get_bone_global_pose(pu) if pu >= 0 else Transform3D()
	sk.set_bone_pose_rotation(_ub, (pg.basis.orthonormalized().inverse() * nu.orthonormalized()).get_rotation_quaternion())
	# forearm: where it sits under the new upper arm, then swing its hand onto the goal
	var gu2 := Transform3D(nu, a)
	var gl2 := gu2 * (gu.affine_inverse() * gl)
	var c2 := (gl2 * (gl.affine_inverse() * gh)).origin
	var nl := Basis(_arc(c2 - e, goal - e)) * gl2.basis
	sk.set_bone_pose_rotation(_lb, (nu.orthonormalized().inverse() * nl.orthonormalized()).get_rotation_quaternion())
	# hand: keep the clip's wrist relative to the forearm, then turn toward the grip
	if orient > 0.001:
		var gh2 := Transform3D(nl, e) * (gl.affine_inverse() * gh)
		var want := gh2.basis.orthonormalized().get_rotation_quaternion().slerp(t_sk.basis.orthonormalized().get_rotation_quaternion(), orient * weight)
		sk.set_bone_pose_rotation(_hb, (nl.orthonormalized().inverse() * Basis(want)).get_rotation_quaternion())


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var f := from.normalized()
	var t := to.normalized()
	var cr := f.cross(t)
	var dt := f.dot(t)
	if cr.length() < 1e-6:
		return Quaternion() if dt > 0.0 else Quaternion(Vector3.UP, PI)
	return Quaternion(cr.normalized(), acos(clampf(dt, -1.0, 1.0)))
