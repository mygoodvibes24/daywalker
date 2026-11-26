extends RefCounted
## Sol's ground speeds and the stop-gap walk (round 3, the owner: "fix the slow walk animation to an
## actual slow walking animation").
##
## Speeds (m/s): a walk (stick tilted part way, the walk toggle, or WALK_SPEED cap), the run
## (player.gd WALK, 7.5), the sprint (13) and the crouch walk. sol_modular_anim.gd blends idle / walk /
## run / sprint in a BlendSpace1D on these speeds.
##
## THE WALK CLIP. Sol owns no walk clip yet. If the clip library has a "walk" animation (a bought
## Meshy library clip installed as sol_mod_anim_walk.glb, see docs/animation_reference/README.md) it
## is used as is. Until then bake_walk() builds "walk_proc" once from the run: played at WALK_RATE of
## its speed, each joint pulled back toward a calm pose (legs toward the straight rest legs, spine,
## head and arms toward the idle), so the stride shortens, the knees lift less, the forward lean and
## the bounce mostly go. The same goes for "crouch_idle" / "crouch_walk": both are bought now
## (sol_crouch_pose.gd is the stand-in without them).

const WALK_SPEED := 1.1 # the walk (a slow, calm walk)
const CROUCH_SPEED := 1.0 # the crouch walk
## Each walk clip's own planted-foot speed (m/s): the clip plays at WALK_SPEED / this, so the feet don't
## slide. "walk": Casual_Walk_inplace (library id 613, a slow stroll, ~1.4 s a stride); "walk_proc": the
## stand-in baked below; "crouch_walk": Cautious_Crouch_Walk_Forward_inplace (616, 1.17 s a cycle, planted
## foot measured at 1.30 m/s, so it plays at 0.77x for the 1.0 m/s crouch walk).
const CLIP_SPEED := {"walk": 0.73, "walk_proc": 1.6, "crouch_walk": 1.3}
const RUN_POINT := 4.6 # where the blend is all run (the run clip's own pace is ~3-4 m/s)
const WALK_RATE := 0.62 # walk_proc plays the run's cycle at this share of its speed (1.18 s a cycle)
const STICK_WALK := 0.55 # stick tilt up to here walks; full speed from STICK_RUN
const STICK_RUN := 0.8

## Share of the run's motion each joint keeps in walk_proc (the rest comes from the calm pose).
const KEEP := {
	"Hips": 0.35, "Spine02": 0.3, "Spine01": 0.3, "Spine": 0.3, "neck": 0.3, "Head": 0.3,
	"LeftUpLeg": 0.78, "RightUpLeg": 0.78, "LeftLeg": 0.5, "RightLeg": 0.5,
	"LeftFoot": 0.55, "RightFoot": 0.55, "LeftToeBase": 0.5, "RightToeBase": 0.5,
	"LeftShoulder": 0.4, "LeftArm": 0.45, "LeftForeArm": 0.4, "LeftHand": 0.4,
	"RightShoulder": 0.4, "RightArm": 0.45, "RightForeArm": 0.4, "RightHand": 0.4,
}
const LEG_BONES := ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]
const HIP_LEAN_KEEP := 0.3 # share of the run's forward hips offset (x / z) kept
const HIP_DROP_KEEP := 0.5 # share of the run's mean hip height change kept
const BOUNCE_KEEP := 0.3 # share of the run's hip bounce kept


## The ground speed for a stick tilt (0..1): part way walks, a full push runs at `run`. `cap` limits
## it (the walk toggle, the crouch). Keyboard keys give a tilt of 1.
static func speed_for_tilt(tilt: float, run: float, cap: float = INF) -> float:
	if tilt <= 0.001:
		return 0.0
	var v: float
	if tilt <= STICK_WALK:
		v = lerpf(0.5, WALK_SPEED, tilt / STICK_WALK)
	else:
		v = lerpf(WALK_SPEED, run, clampf((tilt - STICK_WALK) / (STICK_RUN - STICK_WALK), 0.0, 1.0))
	if cap < INF:
		v = minf(v, cap * clampf(tilt / STICK_WALK, 0.3, 1.0))
	return v


## The playback rate that matches clip `name` to the ground `speed`.
static func clip_rate(name: String, speed: float) -> float:
	return speed / float(CLIP_SPEED.get(name, speed))


## Adds "walk_proc" to the clip library (once; it is shared by every Sol). `skel` gives the rest pose.
static func bake_walk(lib: AnimationLibrary, skel: Skeleton3D) -> String:
	if lib.has_animation("walk"):
		return "walk"
	if lib.has_animation("walk_proc"):
		return "walk_proc"
	if not lib.has_animation("run") or not lib.has_animation("idle") or skel == null:
		return "run"
	var run := lib.get_animation("run")
	var idle := lib.get_animation("idle")
	var out := Animation.new()
	out.length = run.length / WALK_RATE
	out.loop_mode = Animation.LOOP_LINEAR
	var steps := int(ceil(out.length * 30.0))
	for t in run.get_track_count():
		var path := run.track_get_path(t)
		var bone := str(path).get_slice(":", 1)
		var type := run.track_get_type(t)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D:
			continue
		var bi := skel.find_bone(bone)
		var nt := out.add_track(type)
		out.track_set_path(nt, path)
		out.track_set_interpolation_loop_wrap(nt, true)
		var it := idle.find_track(path, type)
		if type == Animation.TYPE_ROTATION_3D:
			var keep: float = KEEP.get(bone, 0.5)
			var calm := Quaternion()
			if bone in LEG_BONES and bi >= 0:
				calm = skel.get_bone_rest(bi).basis.get_rotation_quaternion()
			elif it >= 0:
				calm = idle.rotation_track_interpolate(it, 0.0)
			elif bi >= 0:
				calm = skel.get_bone_rest(bi).basis.get_rotation_quaternion()
			for s in steps + 1:
				var tw := out.length * s / steps
				var q := run.rotation_track_interpolate(t, fposmod(tw * WALK_RATE, run.length))
				out.rotation_track_insert_key(nt, tw, calm.slerp(q, keep).normalized())
		else:
			var calm_p: Vector3 = idle.position_track_interpolate(it, 0.0) if it >= 0 else (skel.get_bone_rest(bi).origin if bi >= 0 else Vector3.ZERO)
			var mean := Vector3.ZERO
			for s in 24:
				mean += run.position_track_interpolate(t, run.length * s / 24.0)
			mean /= 24.0
			for s in steps + 1:
				var tw := out.length * s / steps
				var p := run.position_track_interpolate(t, fposmod(tw * WALK_RATE, run.length))
				var w := Vector3(
					calm_p.x + (p.x - calm_p.x) * HIP_LEAN_KEEP,
					calm_p.y + (mean.y - calm_p.y) * HIP_DROP_KEEP + (p.y - mean.y) * BOUNCE_KEEP,
					calm_p.z + (p.z - calm_p.z) * HIP_LEAN_KEEP)
				out.position_track_insert_key(nt, tw, w)
	lib.add_animation("walk_proc", out)
	return "walk_proc"


## True when the library can carry the crouch with clips. A bought crouch walk alone is enough: the
## crouch idle is then its first frame, held (added to the library once as "crouch_idle"; a bought one
## wins).
static func ensure_crouch_idle(lib: AnimationLibrary) -> bool:
	if not lib.has_animation("crouch_walk"):
		return false
	if lib.has_animation("crouch_idle"):
		_unbow_crouch_idle(lib)
		return true
	var walk := lib.get_animation("crouch_walk")
	var out := Animation.new()
	out.length = 1.0
	out.loop_mode = Animation.LOOP_LINEAR
	for t in walk.get_track_count():
		var type := walk.track_get_type(t)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D:
			continue
		var nt := out.add_track(type)
		out.track_set_path(nt, walk.track_get_path(t))
		for k in [0.0, 1.0]:
			if type == Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(nt, k, walk.rotation_track_interpolate(t, 0.0))
			else:
				out.position_track_insert_key(nt, k, walk.position_track_interpolate(t, 0.0))
	lib.add_animation("crouch_idle", out)
	return true


## The bought crouch idle (CrouchLookAroundBow, library 258) holds a bow: both arms reach forward at
## chest height. Its arm joints (clavicle to hand, both sides) are replaced, once per library, with the
## arms of clip `from` at its first frame, held. The standing idle's arms won the side-by-side: they hang
## loose, the fists by the knees, a crouched rest; the crouch walk's arms (reaching forward at shoulder
## height, tried too) read as a sleepwalker when held still. sol_arm_pose.gd still rebuilds the right arm
## (the mirror of this left arm) while the sword is sheathed, and the crouch walk's own arms come in as he
## moves off (the crouch BlendSpace). Its head and spine keep the clip's slow look around.
const CROUCH_ARMS_FROM := "idle"
const ARM_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]


static func _unbow_crouch_idle(lib: AnimationLibrary, from: String = CROUCH_ARMS_FROM) -> void:
	var a := lib.get_animation("crouch_idle")
	if a.has_meta("unbowed") or not lib.has_animation(from):
		return
	var src := lib.get_animation(from)
	for bone in ARM_BONES:
		var path := NodePath("Skeleton3D:" + bone)
		var st := src.find_track(path, Animation.TYPE_ROTATION_3D)
		var t := a.find_track(path, Animation.TYPE_ROTATION_3D)
		if st < 0 or t < 0:
			continue
		var q := src.rotation_track_interpolate(st, 0.0)
		for k in range(a.track_get_key_count(t) - 1, -1, -1):
			a.track_remove_key(t, k)
		a.rotation_track_insert_key(t, 0.0, q)
	# the bow stance stands ~20 deg further side-on than the crouch walk: turn its hips to the walk's
	var d := _mean_hips_yaw(src if from == "crouch_walk" else lib.get_animation("crouch_walk")) - _mean_hips_yaw(a)
	var turn := Quaternion(Vector3.UP, d)
	var hr := a.find_track(NodePath("Skeleton3D:Hips"), Animation.TYPE_ROTATION_3D)
	if hr >= 0:
		for k in a.track_get_key_count(hr):
			a.track_set_key_value(hr, k, (turn * (a.track_get_key_value(hr, k) as Quaternion)).normalized())
	var hp := a.find_track(NodePath("Skeleton3D:Hips"), Animation.TYPE_POSITION_3D)
	if hp >= 0:
		for k in a.track_get_key_count(hp):
			a.track_set_key_value(hp, k, turn * (a.track_get_key_value(hp, k) as Vector3))
	a.set_meta("unbowed", true)
	a.set_meta("yaw_fit", rad_to_deg(d))


## The mean facing (radians about +Y) of a clip's hips: its side axis, averaged over the keys.
static func _mean_hips_yaw(a: Animation) -> float:
	var t := a.find_track(NodePath("Skeleton3D:Hips"), Animation.TYPE_ROTATION_3D)
	if t < 0:
		return 0.0
	var s := Vector2.ZERO
	for k in a.track_get_key_count(t):
		var v := Basis(a.track_get_key_value(t, k) as Quaternion) * Vector3.RIGHT
		s += Vector2(v.x, -v.z).normalized()
	return atan2(s.y, s.x)
