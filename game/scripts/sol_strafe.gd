extends SkeletonModifier3D
## Lock-on strafing without strafe clips: the run clip plays along the direction Sol moves, so the
## hips (and legs) are turned by `yaw` toward that direction while the spine turns back by the same
## amount, keeping chest, head and sword on the locked target. sol_modular_anim.gd sets `yaw`
## (radians, eased) and plays the run backwards for a backpedal. Nothing runs at yaw 0.

const SPINE := ["Spine", "Spine01", "Spine02"]
const SHARE := [0.4, 0.35, 0.25]
var yaw := 0.0
var _hips := -1
var _spine: Array[int] = []


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or absf(yaw) < 0.002:
		return
	if _hips < 0:
		_hips = sk.find_bone("Hips")
		for n in SPINE:
			_spine.append(sk.find_bone(n))
		if _hips < 0 or _spine.has(-1):
			yaw = 0.0
			return
	sk.set_bone_pose_rotation(_hips, Quaternion(Vector3.UP, yaw) * sk.get_bone_pose_rotation(_hips))
	for i in _spine.size():
		var b: int = _spine[i]
		var p := sk.get_bone_parent(b)
		var axis := (sk.get_bone_global_pose(p).basis.orthonormalized().inverse() * Vector3.UP).normalized()
		sk.set_bone_pose_rotation(b, Quaternion(axis, -yaw * float(SHARE[i])) * sk.get_bone_pose_rotation(b))
