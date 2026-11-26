extends SkeletonModifier3D
## The empty right arm (round 3, the owner's playtest: "he still has his right arm up like he's holding a
## sword, but he's not holding a sword"). Every locomotion clip was captured with a sword grip, so with
## the sword on his back the right fist still hovers at his chest. While `amount` > 0 this modifier
## rebuilds the right arm (clavicle, upper arm, forearm, hand) as the MIRROR of the left arm, which
## the clips animate as a free arm: down by his side with a slight bend at idle, pumping when he runs.
##
## Mirroring alone would swing both arms forward together, so the swing is flipped: the left upper
## arm's forward pitch (in the chest's frame) is tracked against its running mean, and the right arm
## is turned about the shoulder's side axis by twice that deviation. A natural gait: right arm back
## while the left is forward. `swing` (0..1) scales that flip (sol_modular_anim.gd eases it to 0 off
## the ground, so a jump's raised arms stay symmetric).
##
## Order on the skeleton: Strafe, Crouch, ArmPose, DrawIK, SwordWrist. The draw reach therefore starts
## from this relaxed pose, and sol_modular_anim.gd eases `amount` in and out with the sheath state.
## Cost: 8 bone reads and 4 writes per frame while active; nothing at amount 0.

const LEFT := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand"]
const RIGHT := ["RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const CHEST := "Spine" # the top spine bone (both clavicles hang from it)
const MIR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)) # skeleton space: +X is his left
const MEAN_TIME := 0.6 # seconds: the running mean of the left arm's swing
const MAX_DEV := 0.9 # radians of swing deviation honoured

var amount := 0.0
var swing := 0.0
var swing_gain := 1.0
var dt := 1.0 / 60.0 # sol_modular_anim.gd sets the frame's delta
var _l := PackedInt32Array()
var _r := PackedInt32Array()
var _chest := -1
var _l_rest_inv: Array[Basis] = []
var _r_rest: Array[Basis] = []
var _chest_rest_inv := Basis()
var _mean := 0.0
var _have_mean := false
var record := false # smoke test: store last_drop after each pass
var last_drop := 0.0


func _init_bones(sk: Skeleton3D) -> bool:
	_chest = sk.find_bone(CHEST)
	if _chest < 0:
		return false
	for i in 4:
		var l := sk.find_bone(LEFT[i])
		var r := sk.find_bone(RIGHT[i])
		if l < 0 or r < 0:
			return false
		_l.append(l)
		_r.append(r)
		_l_rest_inv.append(sk.get_bone_global_rest(l).basis.orthonormalized().inverse())
		_r_rest.append(sk.get_bone_global_rest(r).basis.orthonormalized())
	_chest_rest_inv = sk.get_bone_global_rest(_chest).basis.orthonormalized().inverse()
	return true


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if amount <= 0.001:
		_have_mean = false
		return
	if _chest < 0 and not _init_bones(sk):
		amount = 0.0
		return
	var chest := sk.get_bone_global_pose(_chest)
	var f := chest.basis.orthonormalized() * _chest_rest_inv # the chest's turn from rest
	var fi := f.inverse()
	var gl: Array[Transform3D] = []
	var gr: Array[Basis] = [] # the clip's right arm (read before any write moves the children)
	for i in 4:
		gl.append(sk.get_bone_global_pose(_l[i]))
		gr.append(sk.get_bone_global_pose(_r[i]).basis.orthonormalized())
	# the left arm's forward swing in the chest frame, against its running mean
	var d := fi * (gl[2].origin - gl[1].origin)
	var pitch := atan2(d.z, -d.y)
	if not _have_mean:
		_mean = pitch
		_have_mean = true
	_mean = lerpf(_mean, pitch, 1.0 - exp(-dt / MEAN_TIME))
	var dev := clampf(pitch - _mean, -MAX_DEV, MAX_DEV) * swing * swing_gain
	var flip := Basis(f * Vector3.RIGHT, 2.0 * dev) # rotating about +X takes the arm back
	var parent_g := chest.basis.orthonormalized()
	for i in 4:
		# the left bone's turn from its rest (chest frame), mirrored onto the right bone's rest
		var delta := fi * gl[i].basis.orthonormalized() * _l_rest_inv[i]
		var want := f * (MIR * delta * MIR) * _r_rest[i]
		if i > 0:
			want = flip * want
		var q := gr[i].get_rotation_quaternion().slerp(want.orthonormalized().get_rotation_quaternion(), amount)
		var g := Basis(q)
		sk.set_bone_pose_rotation(_r[i], (parent_g.inverse() * g).get_rotation_quaternion())
		parent_g = g
	if record:
		last_drop = hand_drop(sk)


## The right hand's height above (positive) or below the right shoulder, in skeleton space (smoke test).
func hand_drop(sk: Skeleton3D) -> float:
	var s := sk.find_bone("RightArm")
	var h := sk.find_bone("RightHand")
	return sk.get_bone_global_pose(s).origin.y - sk.get_bone_global_pose(h).origin.y
