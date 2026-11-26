extends Node
## Spring-bone simulation for the skirt of Sol's trenchcoat (sol_modular.scn).
##
## The coat's lower half is skinned to `chains` chains of `links` bones each, all children of the
## Hips bone (built by tools/build_sol_modular.gd, bones named "Coat<c>_<k>"; neighbouring chains
## share the vertices between them, so the skirt folds between chains instead of moving as panels).
## Every physics frame each chain is a little verlet rope in world space:
##   * joint 0 rides the animated Hips; joints 1..links are free particles;
##   * forces: gravity, a spring back toward the coat's tailored rest shape (firm at the waist, soft at
##     the hem, so the hem lags, overshoots a touch and settles like heavy leather), air drag (the hem
##     trails when Sol runs or turns), an outward flare that grows with speed but saturates, and a
##     wind / rain flutter with its own phase per chain;
##   * constraints: fixed link lengths, a per-link swing limit and a whole-chain cone (so sprinting or
##     a big slash can't throw the hem out horizontal), and soft capsules around the thighs, shins and
##     hips that push the cloth back and around a lifting knee rather than up;
##   * the particle positions are then written back as bone rotations.
## Cost (12 chains x 5 links = 60 bones): 60 particles, two constraint passes against 5 capsules =
## 600 capsule tests and 60 bone writes per physics frame, all plain float math (about 0.2 ms in a
## web build).

const SettingsScript = preload("res://scripts/settings.gd") # PERF: Settings.coat_quality tiers

@export var skeleton_path := NodePath("../Skeleton3D")
@export var chains := 12
@export var links := 5
## Hem offset from the last bone of each chain, in that bone's rest space (one per chain).
@export var tails := PackedVector3Array()
@export var gravity := 9.8
## Pull toward the rest shape (1/s^2), at the waist and at the hem (heavy leather: soft at the hem).
@export var stiffness_top := 80.0
@export var stiffness_hem := 11.0
## Velocity kept per 1/60 s (verlet damping): under-damped at the hem, so it overshoots slightly.
@export var damping := 0.935
## Air drag (1/s): makes the coat trail behind when Sol moves.
@export var drag := 0.55
## Outward flare acceleration per m/s of horizontal speed, at the hem, and the speed it saturates at.
@export var flare := 0.28
@export var flare_speed_cap := 8.0
## Wind and rain flutter (m/s^2).
@export var flutter := 0.6
## Max angle (radians) a link may swing away from its rest direction.
@export var max_swing := 0.55
## Max angle (radians) the whole chain (waist joint -> any joint) may swing away from its rest line.
@export var max_cone := 0.95
## Leg capsules: [bone_a, bone_b, radius]; the cloth keeps `cloth_margin` outside them.
@export var capsules := [
	["LeftUpLeg", "LeftLeg", 0.085], ["LeftLeg", "LeftFoot", 0.065],
	["RightUpLeg", "RightLeg", 0.085], ["RightLeg", "RightFoot", 0.065],
	["Hips", "Spine02", 0.14],
]
@export var cloth_margin := 0.025
## How much of a capsule penetration is resolved per pass (soft collision: < 1 lets the cloth give).
@export var collision_softness := 0.6
## share of a touching joint's sliding speed lost per step against a leg or the hips (cloth friction)
@export var contact_friction := 0.35
## Simulation on/off (off = the coat holds its rest shape).
@export var enabled := true

var skel: Skeleton3D
var hips := -1
var bones: Array[PackedInt32Array] = [] # [chain][k] -> bone index
var rest_hips: Array[PackedVector3Array] = [] # [chain][k] joint rest position in Hips space (k = 0..links)
var seg_len: Array[PackedFloat32Array] = []
var pos: Array[PackedVector3Array] = [] # world space, k = 0..links
var prev: Array[PackedVector3Array] = []
var phase := PackedFloat32Array() # per-chain flutter phase
var cap_bones: Array[PackedInt32Array] = []
var cap_r := PackedFloat32Array()
var t := 0.0
var ready_ok := false
var hips_vel := Vector3.ZERO
var last_hips := Vector3.ZERO
var _need_reset := true
var _motion := 0.0
var hips_rest_inv := Basis()
# PERF: quality tiers (Settings.coat_quality): 2 full (60 Hz, two constraint passes), 1 cheap
# (30 Hz, one pass), 0 static (rest shape written once, then nothing per frame)
var _static_done := false
var _half := false
var _acc := 0.0
# PERF: capsules in world space, reused every step (no per-frame array allocation)
var _caps_a := PackedVector3Array()
var _caps_b := PackedVector3Array()
var _caps_c := PackedVector3Array() # bounding sphere centre
var _caps_r2 := PackedFloat32Array() # bounding sphere radius squared


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
		var tail: Vector3 = tails[c] if c < tails.size() else Vector3(0, -0.11, 0)
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
		phase.append(fmod(c * 2.39996, TAU)) # golden-angle spread: no two neighbours flutter in step
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
	# PERF / SETTINGS HOOK: coat physics quality
	var cq: int = SettingsScript.coat_quality
	if cq <= 0 and enabled:
		if not _static_done or _need_reset:
			_static_done = true
			_need_reset = false
			var sx0 := skel.global_transform
			_snap(sx0 * skel.get_bone_global_pose(hips))
			_write(sx0)
		return
	if _static_done:
		_static_done = false
		_need_reset = true
	if cq == 1:
		_acc += delta
		_half = not _half
		if _half:
			return
		delta = _acc
		_acc = 0.0
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
	var flare_spd := flare_speed_cap * (1.0 - exp(-hspeed / flare_speed_cap)) # saturates
	var keep := pow(damping, dt * 60.0)
	# gravity minus the share the tailored rest shape already carries (the rest pose was cut
	# hanging upright): upright this nets to ~0, but when the hips tip over (a lunge, a fall)
	# the coat drapes toward the ground
	var g_world := Vector3(0, -gravity, 0)
	var g := g_world - (sx.basis.orthonormalized() * skel.get_bone_global_pose(hips).basis.orthonormalized() * hips_rest_inv) * g_world * 0.85
	# wind gusts: slow, mostly sideways
	var gust := Vector3(sin(t * 0.7) + 0.5 * sin(t * 1.9 + 1.3), 0.0, cos(t * 0.5) * 0.6) * flutter
	var axis := hips_g.origin
	# capsules in world space
	var ncap := cap_bones.size()
	if _caps_a.size() != ncap:
		_caps_a.resize(ncap)
		_caps_b.resize(ncap)
		_caps_c.resize(ncap)
		_caps_r2.resize(ncap)
	for ci in ncap:
		var a := sx * skel.get_bone_global_pose(cap_bones[ci][0]).origin
		var b := sx * skel.get_bone_global_pose(cap_bones[ci][1]).origin
		_caps_a[ci] = a
		_caps_b[ci] = b
		_caps_c[ci] = (a + b) * 0.5
		var br := a.distance_to(b) * 0.5 + cap_r[ci] + cloth_margin
		_caps_r2[ci] = br * br
	var passes := 2 if cq >= 2 else 1
	var msum := 0.0
	var move_amt := 0.04 + 0.96 * clampf(hspeed / 8.0, 0.0, 1.0) # a breath of wind standing, a flutter running
	for c in pos.size():
		var p := pos[c]
		var q := prev[c]
		var rh := rest_hips[c]
		var ph := phase[c]
		var was := p.duplicate() # where each joint really was last step (the motion measure)
		p[0] = hips_g * rh[0]
		q[0] = p[0]
		for k in range(1, links + 1):
			var f := float(k) / links
			var target := hips_g * rh[k]
			var vel := (p[k] - q[k]) / dt
			var radial := Vector3(p[k].x - axis.x, 0.0, p[k].z - axis.z)
			radial = radial.normalized() if radial.length() > 0.001 else Vector3.ZERO
			var noise := Vector3(
				sin(t * 5.3 + ph + k * 0.9), sin(t * 3.1 + ph * 1.3) * 0.3, cos(t * 4.7 + ph * 0.7 + k * 1.3)
			) * flutter * move_amt
			# stiffness falls off toward the hem faster than linearly (the hem is the heavy, free part)
			var stiff := lerpf(stiffness_top, stiffness_hem, sqrt(f))
			var acc := g + (target - p[k]) * stiff
			acc += -vel * drag + gust * f * 0.35 * (0.15 + 0.85 * move_amt) + noise * f
			acc += radial * flare * flare_spd * f
			var np := p[k] + (p[k] - q[k]) * keep + acc * dt * dt
			q[k] = p[k]
			p[k] = np
		for it in passes:
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
				d = _clamp_dir(d, rest_dir, max_swing)
				p[k] = parent + d * seg_len[c][k - 1]
				# whole-chain cone: the hem can flare but never fly out flat
				var rest_line := (hips_g.basis * (rh[k] - rh[0])).normalized()
				var line := p[k] - p[0]
				var ll := line.length()
				if ll > 1e-4:
					var nd := _clamp_dir(line / ll, rest_line, max_cone)
					p[k] = p[0] + nd * ll
				# legs and hips: soft push out of each capsule, sideways and back, never up
				for ci in ncap:
					var before := p[k]
					if before.distance_squared_to(_caps_c[ci]) > _caps_r2[ci]:
						continue # PERF: outside the capsule's bounding sphere, no push possible
					p[k] = _push_out(p[k], _caps_a[ci], _caps_b[ci], cap_r[ci] + cloth_margin, collision_softness)
					# inelastic contact: the push-out moves the cloth but adds no velocity, otherwise the
					# spring pulls it back in, the capsule pushes it out, and it buzzes against the legs forever
					var push := p[k] - before
					if push.length_squared() > 1e-12:
						q[k] += push
						# contact friction: cloth lying on a leg drags on it instead of skating around it
						q[k] = q[k].lerp(p[k], contact_friction)
		pos[c] = p
		prev[c] = q
		for k in range(1, links + 1):
			msum += p[k].distance_to(was[k]) / dt
	_motion = msum / maxf(pos.size() * links, 1)
	_write(sx)


static func _clamp_dir(d: Vector3, rest: Vector3, lim: float) -> Vector3:
	var ang := d.angle_to(rest)
	if ang <= lim:
		return d
	var ax := rest.cross(d)
	if ax.length() < 1e-5:
		return d
	return rest.rotated(ax.normalized(), lim)


func _snap(hips_g: Transform3D) -> void:
	for c in pos.size():
		var p := pos[c]
		for k in links + 1:
			p[k] = hips_g * rest_hips[c][k]
		pos[c] = p
		prev[c] = p.duplicate()
	last_hips = hips_g.origin
	hips_vel = Vector3.ZERO


## Push p out of the capsule a-b (radius r). The push loses its upward part, so a knee coming up
## slides the hem aside and back around the leg instead of lifting it; `soft` < 1 resolves only part
## of the overlap per pass (the cloth gives a little, no popping).
static func _push_out(p: Vector3, a: Vector3, b: Vector3, r: float, soft: float) -> Vector3:
	var ab := b - a
	var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var c := a + ab * tt
	var d := p - c
	var l := d.length()
	if l >= r:
		return p
	var n := d / l if l > 1e-5 else Vector3(0, 0, 1)
	if n.y > 0.0:
		n.y = 0.0
		if n.length() < 1e-3:
			return p
		n = n.normalized()
	# the depth along the (now horizontal) push direction that clears the capsule
	var perp := d - ab.normalized() * d.dot(ab.normalized()) if ab.length_squared() > 1e-8 else d
	var depth := r - maxf(perp.dot(n), 0.0)
	return p + n * maxf(depth, 0.0) * soft


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
			var child_local: Vector3 = skel.get_bone_rest(bones[c][k + 1]).origin if k + 1 < links else (tails[c] if c < tails.size() else Vector3(0, -0.11, 0))
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


## Mean speed (m/s) of the free cloth points over the last frame: ~0 once the coat has settled.
func motion_amount() -> float:
	return _motion
