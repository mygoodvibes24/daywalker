extends Node
## Poses Sol at the workbench for the main-menu set: leaning over the bench, head down,
## left hand pinning a silver blade, right hand stroking a whetstone along it on a slow loop.
## Works on any skeleton with Sol's bone names (sol.scn or the modular rig); it solves the
## arms with a small two-bone IK so the hands land on the bench whatever the proportions.
## Targets are in skeleton space: +X = Sol's left, +Y up, +Z = forward (toward the bench).

var skel: Skeleton3D
var bi := {}
var t := 0.0
var hips_rest := Vector3.ZERO
var stone: Node3D # whetstone, carried by the right hand

## Where the hands work, relative to Sol's feet (set by the set so it matches the bench).
var bench_top := 0.93
var bench_near := 0.36 # z of the blade line on the bench
var stroke_from := 0.02 # x along the blade (Sol's right is -x)
var stroke_to := -0.30
var left_hand := Vector3(0.24, 0.0, 0.0) # y/z filled from bench_top/bench_near


func setup(s: Skeleton3D) -> void:
	skel = s
	for i in skel.get_bone_count():
		bi[skel.get_bone_name(i)] = i
	if bi.has("Hips"):
		hips_rest = skel.get_bone_rest(bi["Hips"]).origin
	if bi.has("Hand.R"):
		var att := BoneAttachment3D.new()
		att.bone_name = "Hand.R"
		skel.add_child(att)
		stone = Node3D.new()
		att.add_child(stone)
	_pose(0.0)


func _process(delta: float) -> void:
	t += delta
	_pose(t)


func _has(names: Array) -> bool:
	for n in names:
		if not bi.has(n):
			return false
	return true


func _rot(bone: String, q: Quaternion) -> void:
	if bi.has(bone):
		skel.set_bone_pose_rotation(bi[bone], q)


func _pose(time: float) -> void:
	if skel == null or not _has(["Hips", "Spine", "Chest", "Neck", "Head"]):
		return
	var breath := sin(time * 1.5)
	# slow stroke: push the stone along the blade, lift slightly on the way back
	var cyc := fmod(time / 2.6, 1.0)
	var push := smoothstep(0.0, 0.55, cyc) * (1.0 - smoothstep(0.62, 1.0, cyc))
	var lift := sin(clampf((cyc - 0.55) / 0.45, 0.0, 1.0) * PI) * 0.025

	# lower body: weight settled, knees soft, hips dropped and pushed back a little
	skel.set_bone_pose_position(bi["Hips"], hips_rest + Vector3(0.0, -0.03 - breath * 0.003, -0.03))
	_rot("Hips", Quaternion(Vector3.RIGHT, 0.06))
	_rot("Thigh.L", Quaternion(Vector3.RIGHT, -0.12) * Quaternion(Vector3.BACK, 0.05))
	_rot("Thigh.R", Quaternion(Vector3.RIGHT, -0.1) * Quaternion(Vector3.BACK, -0.06))
	_rot("Shin.L", Quaternion(Vector3.RIGHT, 0.12))
	_rot("Shin.R", Quaternion(Vector3.RIGHT, 0.1))
	_rot("Foot.L", Quaternion(Vector3.RIGHT, -0.1))
	_rot("Foot.R", Quaternion(Vector3.RIGHT, -0.08))
	# torso: bent over the bench; the chest follows the stroke a touch
	_rot("Spine", Quaternion(Vector3.RIGHT, 0.16 + breath * 0.01))
	_rot("Chest", Quaternion(Vector3.UP, -0.05 - push * 0.06) * Quaternion(Vector3.RIGHT, 0.14 + breath * 0.015))
	_rot("Neck", Quaternion(Vector3.RIGHT, 0.2))
	# head down on the work, an occasional glance along the blade
	var glance := smoothstep(0.85, 1.0, sin(time * 0.21) * 0.5 + 0.5)
	_rot("Head", Quaternion(Vector3.UP, -0.12 - push * 0.08 + glance * 0.35) * Quaternion(Vector3.RIGHT, 0.38 - glance * 0.15))
	# coat panels hang straight down despite the lean
	_rot("CoatBack", Quaternion(Vector3.RIGHT, -0.2))
	_rot("CoatFront.L", Quaternion(Vector3.RIGHT, -0.24))
	_rot("CoatFront.R", Quaternion(Vector3.RIGHT, -0.24))

	if not _has(["UpperArm.L", "ForeArm.L", "Hand.L", "UpperArm.R", "ForeArm.R", "Hand.R"]):
		return
	var y := bench_top + 0.05
	var lh := Vector3(left_hand.x, y + 0.01, bench_near + 0.02)
	var rx := lerpf(stroke_from, stroke_to, push)
	var rh := Vector3(rx, y + 0.035 + lift, bench_near + 0.01)
	# elbows point out and back
	_ik("UpperArm.L", "ForeArm.L", "Hand.L", lh, Vector3(0.35, -0.6, -0.7))
	_ik("UpperArm.R", "ForeArm.R", "Hand.R", rh, Vector3(-0.35, -0.6, -0.7))
	# hands flat on the work
	_rot("Hand.L", Quaternion(Vector3.BACK, -0.25) * Quaternion(Vector3.UP, 0.2))
	_rot("Hand.R", Quaternion(Vector3.BACK, 0.35) * Quaternion(Vector3.UP, -0.1))


## Two-bone IK in skeleton space; `pole` is the direction the elbow should bend toward.
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
	# upper arm: rotate its rest direction onto shoulder->elbow, in the parent's frame
	var q_up := Quaternion(c1.normalized(), (pg.basis.inverse() * (elbow - s)).normalized())
	skel.set_bone_pose_rotation(iu, q_up)
	var ug := pg.basis * Basis(q_up)
	var q_fo := Quaternion(c2.normalized(), (ug.inverse() * (hand_p - elbow)).normalized())
	skel.set_bone_pose_rotation(i_f, q_fo)
