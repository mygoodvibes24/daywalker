extends Node
## Spring-bone simulation for the skirt of Sol's trenchcoat (sol_modular.scn).
##
## The coat's lower half is skinned to `chains` chains of `links` bones each, all children of
## the Hips bone (built by tools/build_sol_modular.gd, bones named "Coat<c>_<k>"). Every physics
## frame each chain is a little verlet rope in world space:
##   * joint 0 rides the animated Hips; joints 1..links are free particles;
##   * forces: gravity, a spring back toward the coat's tailored rest shape (stiffer near the
##     waist), air drag (so the hem trails when Sol runs or turns), an outward flare that grows
##     with speed, and a little wind/rain flutter noise;
##   * constraints: fixed link lengths, a swing limit, and capsules around the thighs, shins and
##     hips so the cloth never passes through the legs;
##   * the particle positions are then written back as bone rotations.
## Cost: 8 chains x 4 links, two constraint passes with 5 capsules = ~400 capsule tests and 32
## bone writes per physics frame, all plain float math (well under 0.2 ms in a web build).

@export var skeleton_path := NodePath("../Skeleton3D")
@export var chains := 8
@export var links := 4
## Hem offset from the last bone of each chain, in that bone's rest space (one per chain).
@export var tails := PackedVector3Array()
@export var gravity := 9.8
## Pull toward the rest shape (1/s^2), at the waist and at the hem.
@export var stiffness_top := 70.0
@export var stiffness_hem := 24.0
## Velocity kept per 1/60 s (verlet damping).
@export var damping := 0.86
## Air drag (1/s): makes the coat trail behind when Sol moves.
@export var drag := 0.45
## Outward flare acceleration per m/s of horizontal speed, at the hem.
@export var flare := 0.35
## Wind and rain flutter (m/s^2).
@export var flutter := 0.7
## Max angle (radians) a link may swing away from its rest direction.
@export var max_swing := 0.75
## Leg capsules: [bone_a, bone_b, radius]; the cloth keeps `cloth_margin` outside them.
@export var capsules := [
	["LeftUpLeg", "LeftLeg", 0.085], ["LeftLeg", "LeftFoot", 0.065],
	["RightUpLeg", "RightLeg", 0.085], ["RightLeg", "RightFoot", 0.065],
	["Hips", "Spine02", 0.14],
]
@export var cloth_margin := 0.02
## Simulation on/off (off = the coat holds its rest shape).
@export var enabled := true

var skel: Skeleton3D
var hips := -1
var bones: Array[PackedInt32Array] = [] # [chain][k] -> bone index
var rest_hips: Array[PackedVector3Array] = [] # [chain][k] joint rest position in Hips space (k = 0..links)
var seg_len: Array[PackedFloat32Array] = []
var pos: Array[PackedVector3Array] = [] # world space, k = 0..links
var prev: Array[PackedVector3Array] = []
var cap_bones: Array[PackedInt32Array] = []
var cap_r := PackedFloat32Array()
var t := 0.0
var ready_ok := false
var hips_vel := Vector3.ZERO
var last_hips := Vector3.ZERO
var _need_reset := true
var hips_rest_inv := Basis()


func _ready() -> void:
	process_physics_priority = 100 # after the player moved and the animation posed the body
	skel = get_node_or_null(skeleton_path) as Skeleton3D
	if skel == null:
		return
	hips = skel.find_bone("Hips")
	if hips < 0:
		return
	var hips_rest := skel.get_bone_global_rest(hips)
	hips_rest_inv = hips_rest.basis.orthonormalized().inverse()
	for c in chains:
		var bl := PackedInt32Array()
		var rh := PackedVector3Array()
		var sl := PackedFloat32Array()
		for k in links:
			var b := skel.find_bone("Coat%d_%d" % [c, k])
			if b < 0:
				return
			bl.append(b)
			rh.append(hips_rest.affine_inverse() * skel.get_bone_global_rest(b).origin)
		var last := skel.get_bone_global_rest(bl[links - 1])
		var tail: Vector3 = tails[c] if c < tails.size() else Vector3(0, -0.13, 0)
		rh.append(hips_rest.affine_inverse() * (last * tail))
		for k in links:
			sl.append(rh[k].distance_to(rh[k + 1]))
		bones.append(bl)
		rest_hips.append(rh)
		seg_len.append(sl)
		var p := PackedVector3Array()
		p.resize(links + 1)
		pos.append(p)
		prev.append(p.duplicate())
	for cap in capsules:
		var a := skel.find_bone(cap[0])
		var b := skel.find_bone(cap[1])
		if a >= 0 and b >= 0:
			cap_bones.append(PackedInt32Array([a, b]))
			cap_r.append(float(cap[2]))
	ready_ok = true


## Snap the cloth back to its rest shape (after a teleport or respawn).
func reset() -> void:
	_need_reset = true


func _physics_process(delta: float) -> void:
	if not ready_ok or delta <= 0.0:
		return
	var sx := skel.global_transform
	var hips_g := sx * skel.get_bone_global_pose(hips)
	if _need_reset or hips_g.origin.distance_to(last_hips) > 3.0:
		_snap(hips_g)
		_need_reset = false
	if not enabled:
		_snap(hips_g)
		_write(sx)
		return
	t += delta
	var dt := minf(delta, 1.0 / 30.0)
	var v_now := (hips_g.origin - last_hips) / maxf(delta, 1e-4)
	hips_vel = hips_vel.lerp(v_now, clampf(delta * 12.0, 0.0, 1.0))
	last_hips = hips_g.origin
	var hspeed := Vector2(hips_vel.x, hips_vel.z).length()
	var keep := pow(damping, dt * 60.0)
	# gravity minus the share the tailored rest shape already carries (the rest pose was cut
	# hanging upright): upright this nets to ~0, but when the hips tip over (a lunge, a fall)
	# the coat drapes toward the ground
	var g_world := Vector3(0, -gravity, 0)
	var g := g_world - (sx.basis.orthonormalized() * skel.get_bone_global_pose(hips).basis.orthonormalized() * hips_rest_inv) * g_world * 0.85
	# wind gusts: slow, mostly sideways; stronger at night rain doesn't matter here
	var gust := Vector3(sin(t * 0.7) + 0.5 * sin(t * 1.9 + 1.3), 0.0, cos(t * 0.5) * 0.6) * flutter
	var axis := hips_g.origin
	# capsules in world space
	var caps: Array[PackedVector3Array] = []
	for cb in cap_bones:
		caps.append(PackedVector3Array([sx * skel.get_bone_global_pose(cb[0]).origin, sx * skel.get_bone_global_pose(cb[1]).origin]))
	for c in pos.size():
		var p := pos[c]
		var q := prev[c]
		var rh := rest_hips[c]
		p[0] = hips_g * rh[0]
		q[0] = p[0]
		for k in range(1, links + 1):
			var f := float(k) / links
			var target := hips_g * rh[k]
			var vel := (p[k] - q[k]) / dt
			var radial := Vector3(p[k].x - axis.x, 0.0, p[k].z - axis.z)
			radial = radial.normalized() if radial.length() > 0.001 else Vector3.ZERO
			var noise := Vector3(
				sin(t * 5.3 + c * 1.7 + k * 0.9), sin(t * 3.1 + c * 2.3) * 0.3, cos(t * 4.7 + c * 1.1 + k * 1.3)
			) * flutter * (0.25 + 0.75 * clampf(hspeed / 8.0, 0.0, 1.0))
			var acc := g + (target - p[k]) * lerpf(stiffness_top, stiffness_hem, f)
			acc += -vel * drag + gust * f * 0.35 + noise * f
			acc += radial * flare * hspeed * f
			var np := p[k] + (p[k] - q[k]) * keep + acc * dt * dt
			q[k] = p[k]
			p[k] = np
		for it in 2:
			for k in range(1, links + 1):
				var parent := p[k - 1]
				var d := p[k] - parent
				var len := d.length()
				if len < 1e-5:
					d = hips_g.basis * (rh[k] - rh[k - 1])
					len = d.length()
				d /= len
				# swing limit around the posed rest direction
				var rest_dir := (hips_g.basis * (rh[k] - rh[k - 1])).normalized()
				var ang := d.angle_to(rest_dir)
				if ang > max_swing:
					var ax := rest_dir.cross(d)
					if ax.length() > 1e-5:
						d = rest_dir.rotated(ax.normalized(), max_swing)
				p[k] = parent + d * seg_len[c][k - 1]
				# legs and hips: push the cloth point out of each capsule
				for ci in caps.size():
					p[k] = _push_out(p[k], caps[ci][0], caps[ci][1], cap_r[ci] + cloth_margin)
		pos[c] = p
		prev[c] = q
	_write(sx)


func _snap(hips_g: Transform3D) -> void:
	for c in pos.size():
		var p := pos[c]
		for k in links + 1:
			p[k] = hips_g * rest_hips[c][k]
		pos[c] = p
		prev[c] = p.duplicate()
	last_hips = hips_g.origin
	hips_vel = Vector3.ZERO


static func _push_out(p: Vector3, a: Vector3, b: Vector3, r: float) -> Vector3:
	var ab := b - a
	var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var c := a + ab * tt
	var d := p - c
	var l := d.length()
	if l >= r:
		return p
	if l < 1e-5:
		return c + Vector3(0, 0, r)
	return c + d / l * r


## Turn the particle chain into bone rotations (in skeleton space, parent first).
func _write(sx: Transform3D) -> void:
	var inv := sx.affine_inverse()
	var hips_pose := skel.get_bone_global_pose(hips)
	for c in pos.size():
		var gp := hips_pose
		var p := pos[c]
		for k in links:
			var b := bones[c][k]
			var rest := skel.get_bone_rest(b)
			var cur_basis := gp.basis * rest.basis
			var origin := gp * rest.origin
			var child_local: Vector3 = skel.get_bone_rest(bones[c][k + 1]).origin if k + 1 < links else (tails[c] if c < tails.size() else Vector3(0, -0.13, 0))
			var cur_dir := (cur_basis * child_local).normalized()
			var want := (inv * p[k + 1]) - origin
			var new_basis := cur_basis
			if want.length() > 1e-4:
				want = want.normalized()
				var dotv := cur_dir.dot(want)
				if dotv < 0.9999:
					var ax := cur_dir.cross(want)
					if ax.length() > 1e-6:
						new_basis = Basis(ax.normalized(), acos(clampf(dotv, -1.0, 1.0))) * cur_basis
			var local := gp.basis.inverse() * new_basis
			skel.set_bone_pose_rotation(b, local.get_rotation_quaternion())
			gp = Transform3D(new_basis, origin)


## How far (radians) the coat bones are swung away from their rest pose, averaged: 0 at rest.
func swing_amount() -> float:
	if not ready_ok:
		return 0.0
	var s := 0.0
	var n := 0
	for bl in bones:
		for b in bl:
			s += skel.get_bone_pose_rotation(b).angle_to(skel.get_bone_rest(b).basis.get_rotation_quaternion())
			n += 1
	return s / maxf(n, 1)
