extends RefCounted
## Procedural animation for Sol's skinned body (res://assets/characters/sol/sol.scn).
## All bones have identity rest bases, so a pose rotation is expressed in the
## parent's axes: +X is the character's left, +Y up, +Z forward.
## Drives: idle breathing, walk/run cycle (legs, arms, hips, torso), airborne tuck,
## Blood Dash lunge, bite lean, sword swing (from the player's arm_pivot) and coat flare.

const HANG := 1.22 # how far the T-pose arms drop toward the sides (radians)

var skel: Skeleton3D
var bi := {}
var hips_rest := Vector3.ZERO
var phase := 0.0
var t := 0.0
var run := 0.0
var air := 0.0
var dash := 0.0
var bite := 0.0
var swing_w := 0.0
var flare := 0.0


func setup(s: Skeleton3D) -> void:
	skel = s
	for i in skel.get_bone_count():
		bi[skel.get_bone_name(i)] = i
	hips_rest = skel.get_bone_rest(bi["Hips"]).origin


func _rot(bone: String, q: Quaternion) -> void:
	skel.set_bone_pose_rotation(bi[bone], q)


static func _qx(a: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, a)


static func _qy(a: float) -> Quaternion:
	return Quaternion(Vector3.UP, a)


static func _qz(a: float) -> Quaternion:
	return Quaternion(Vector3.BACK, a)


## s: speed (horizontal m/s), sprint (bool), on_floor (bool), dashing (bool),
## biting (bool), swinging (bool), swing_rot (Vector3 euler, old arm_pivot space).
func update(delta: float, s: Dictionary) -> void:
	if skel == null:
		return
	t += delta
	var speed: float = s.speed
	var k := clampf(14.0 * delta, 0.0, 1.0)
	run = lerpf(run, clampf(speed / 7.5, 0.0, 1.0), k)
	air = lerpf(air, 0.0 if s.on_floor else 1.0, clampf(10.0 * delta, 0.0, 1.0))
	dash = lerpf(dash, 1.0 if s.dashing else 0.0, clampf(22.0 * delta, 0.0, 1.0))
	bite = lerpf(bite, 1.0 if s.biting else 0.0, clampf(14.0 * delta, 0.0, 1.0))
	swing_w = 1.0 if s.swinging else maxf(swing_w - delta * 7.0, 0.0)
	flare = lerpf(flare, clampf(speed / 14.0, 0.0, 1.0), clampf(6.0 * delta, 0.0, 1.0))
	var sp := clampf((speed - 7.5) / 5.5, 0.0, 1.0)
	var grounded := run * (1.0 - air)
	# stride: one full cycle covers ~2.6 m at a run, ~3.4 m sprinting
	if speed > 0.2 and air < 0.5:
		phase = fmod(phase + delta * TAU * speed / (1.7 + 0.13 * speed), TAU)
	var sL := sin(phase)
	var cL := cos(phase)
	var breath := sin(t * 1.7) * (1.0 - run)

	# legs: swing forward = negative X; knee bends with positive X
	var amp := (0.55 + 0.25 * sp) * grounded
	var thigh_l := -amp * sL - air * 0.75 - dash * 0.55
	var thigh_r := amp * sL - air * 0.25 + dash * 0.5
	var knee_l := grounded * (0.15 + (0.95 + 0.4 * sp) * maxf(0.0, cL)) + air * 1.1 + dash * 0.4
	var knee_r := grounded * (0.15 + (0.95 + 0.4 * sp) * maxf(0.0, -cL)) + air * 0.55 + dash * 0.9
	_rot("Thigh.L", _qx(thigh_l) * _qz(0.03))
	_rot("Thigh.R", _qx(thigh_r) * _qz(-0.03))
	_rot("Shin.L", _qx(knee_l))
	_rot("Shin.R", _qx(knee_r))
	_rot("Foot.L", _qx(-(thigh_l + knee_l) * 0.6))
	_rot("Foot.R", _qx(-(thigh_r + knee_r) * 0.6))

	# hips: bob, twist with the stride, settle while breathing
	var drop := grounded * (0.025 + 0.05 * absf(sL)) + dash * 0.08 + bite * 0.05 - breath * 0.004
	skel.set_bone_pose_position(bi["Hips"], hips_rest + Vector3(0.0, -drop, 0.0))
	_rot("Hips", _qy(-0.14 * grounded * sL))

	# torso: lean into speed, counter-twist the chest, breathe
	var lean := 0.06 * run + 0.1 * sp + bite * 0.28 + dash * 0.1
	_rot("Spine", _qx(lean * 0.5 + breath * 0.012))
	var twist := 0.22 * grounded * sL
	if swing_w > 0.0:
		twist = lerpf(twist, -s.swing_rot.y * 0.25, swing_w)
	_rot("Chest", _qy(twist) * _qx(lean * 0.5 + breath * 0.02))
	_rot("Neck", _qy(-twist * 0.6) * _qx(-lean * 0.35))
	_rot("Head", _qx(-lean * 0.25 + bite * 0.3 + sin(t * 0.6) * 0.02 * (1.0 - run)))

	# arms: hang from the T-pose, swing opposite the legs, elbows bend with speed
	var arm_amp := grounded * (0.45 + 0.4 * sp)
	var bend := 0.3 + run * (0.45 + 0.6 * sp) + dash * 0.4
	var sway := breath * 0.03
	var arm_l := _qx(arm_amp * sL - bite * 1.0 + dash * 0.6 - air * 0.4) * _qz(-HANG + sway + air * 0.35 + dash * 0.2)
	var arm_r := _qx(-arm_amp * sL - bite * 1.0 + dash * 0.6 - air * 0.4) * _qz(HANG - sway - air * 0.35 - dash * 0.2)
	var fore_r := _qy(bend + bite * 0.5)
	if swing_w > 0.0:
		var e: Vector3 = s.swing_rot
		var swing_q := Basis.from_euler(e).get_rotation_quaternion() * _qz(PI / 2.0)
		arm_r = arm_r.slerp(swing_q, swing_w)
		fore_r = fore_r.slerp(_qy(0.12), swing_w)
	_rot("UpperArm.L", arm_l)
	_rot("UpperArm.R", arm_r)
	_rot("ForeArm.L", _qy(-bend - bite * 0.5))
	_rot("ForeArm.R", fore_r)
	_rot("Hand.L", _qz(-0.15))
	_rot("Hand.R", _qz(0.15))

	# long coat: back panel streams behind, front panels kick out, flutter at speed
	var f := maxf(flare, dash)
	var flutter := sin(t * 11.0) * 0.05 * f + sin(t * 7.3 + 1.0) * 0.03 * f
	_rot("CoatBack", _qx(0.12 * flare + 0.55 * dash + 0.35 * air + flutter + lean * 0.6))
	_rot("CoatFront.L", _qz(0.1 * f + 0.15 * air) * _qx(0.08 * f - flutter * 0.5))
	_rot("CoatFront.R", _qz(-0.1 * f - 0.15 * air) * _qx(0.08 * f + flutter * 0.5))
