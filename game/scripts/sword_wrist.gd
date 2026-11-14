extends SkeletonModifier3D
## Keeps the carried sword pointing where a carried sword points while Sol runs.
##
## The locomotion clips were made for an empty hand: in the run and the sprint the fist pumps up to
## the chest, and a hammer-gripped blade then points at the sky or straight across his body. After
## the clips are applied this modifier turns the sword hand at the wrist whenever the blade leaves a
## cone around "forward and a little down" (in the character's own space), by at most
## `max_correction`, so the blade trails forward like a carried sword. `amount` (0..1) is set by
## sol_modular_anim.gd: 1 in locomotion, eased to 0 while a sword move plays (the swings need their
## full wrist motion).

@export var bone_name := "RightHand"
## The blade's direction in the hand bone's space (the grip socket's +Z).
@export var blade_dir := Vector3.BACK
## The cone the carried blade stays in: its axis in skeleton space (+Z forward) and half-angle.
@export var cone_axis := Vector3(0.0, -0.45, 1.0)
@export var cone_angle := deg_to_rad(48.0)
@export var max_correction := deg_to_rad(70.0)
var amount := 1.0
var _bone := -1


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or amount <= 0.001:
		return
	if _bone < 0:
		_bone = sk.find_bone(bone_name)
		if _bone < 0:
			return
	var g := sk.get_bone_global_pose(_bone)
	var dir := (g.basis * blade_dir).normalized()
	var ca := cone_axis.normalized()
	var off := dir.angle_to(ca)
	if off <= cone_angle:
		return
	var axis := dir.cross(ca)
	if axis.length() < 1e-4:
		axis = Vector3.UP
	var ang := minf(off - cone_angle, max_correction) * amount
	var nb := Basis(axis.normalized(), ang) * g.basis
	var parent := sk.get_bone_parent(_bone)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	sk.set_bone_pose_rotation(_bone, (pg.basis.orthonormalized().inverse() * nb.orthonormalized()).get_rotation_quaternion())
