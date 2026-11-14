extends SceneTree
## Offline tool: puts real skeletal animation on the enemy models.
##   cd game && godot --headless -s res://tools/build_enemy_anims.gd
##   (BUILD_ONLY=civilian to do one; CLIPS_DIR=/path/to/rig_glbs to re-extract the clips)
##
## Inputs
##  - res://assets/characters/<name>/rigged/<name>_rigged.glb: the enemy mesh turned to face +Z
##    (feet at 0, real height) and auto-rigged by Higgsfield's rigger, which gives a standard
##    24-bone humanoid skeleton (Hips, Spine02, Spine01, Spine, neck, Head, LeftArm, ...).
##    The folder has a .gdignore: the GLB is read here with GLTFDocument, never imported.
##  - res://assets/characters/clips/hero_clips.scn: seven clips (idle, run, sprint, slash, hit,
##    death, jump) rigged on the hero with the same skeleton, plus that skeleton's rest pose.
##    Rebuilt from the downloaded rig_<clip>.glb files when CLIPS_DIR is set.
##
## Retargeting is done per bone in skeleton space. The source and target skeletons have the
## same bone names but different rests (A-pose hero, T-pose enemies, different proportions), so:
##  1. each target bone's rest is first swung so it points along the source bone's rest
##     direction (bone -> child), which turns the T-pose into the hero's A-pose;
##  2. the source's world-space rotation away from its rest (pose * rest^-1) is applied to
##     that matched rest;
##  3. the result is turned back into local rotations down the target hierarchy.
## Position tracks are dropped except the hips, which are scaled by the hip-height ratio
## (height only for the looping clips, so they run in place).
##
## Output: res://assets/characters/<name>/<name>_anim.scn
##   <Name> (Node3D, metas: height, eye_l/eye_r/head_rest in metres, eye_*_local in head-bone
##           space, eye_radius, head_bone, strike_time)
##     Skeleton (Skeleton3D, metres)
##       Body (MeshInstance3D, skinned, the original PBR material, LODs)
##     AnimationPlayer (library "": idle, run, sprint, attack, hit, death, jump)

const CLIPS_SCN := "res://assets/characters/clips/hero_clips.scn"
const CLIPS := {
	# out name: [source file, loop]
	"idle": ["rig_idle", true],
	"run": ["rig_run", true],
	"sprint": ["rig_sprint", true],
	"attack": ["rig_slash", false],
	"hit": ["rig_hit", false],
	"death": ["rig_death", false],
	"jump": ["rig_jump", false],
}
const CHARS := {
	"vampire": {"eye_r": 0.0095},
	"werewolf": {"eye_r": 0.016},
	"civilian": {"eye_r": 0.011},
}
const FPS := 30.0
# bone -> child that gives its direction (used to match rest directions)
const AIM := {
	"Hips": "Spine02", "Spine02": "Spine01", "Spine01": "Spine", "Spine": "neck", "neck": "Head",
	"Head": "head_end",
	"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase",
}
const NO_SWING := ["Hips", "Head"] # keep the root and head orientation as rigged


func _initialize() -> void:
	var dir := OS.get_environment("CLIPS_DIR")
	if dir != "":
		_extract_clips(dir)
	var src: Node3D = (load(CLIPS_SCN) as PackedScene).instantiate()
	root.add_child(src)
	var only := OS.get_environment("BUILD_ONLY")
	for n in CHARS:
		if only != "" and only != n:
			continue
		var p := "res://assets/characters/%s/rigged/%s_rigged.glb" % [n, n]
		if not FileAccess.file_exists(p):
			print("build_enemy_anims: no rigged mesh for ", n, ", skipped")
			continue
		_build(n, p, src)
	quit()


## Load a GLB at runtime (no import), add it to the tree. Returns [scene, skeleton, scale].
func _load_glb(path: String) -> Array:
	var d := GLTFDocument.new()
	var st := GLTFState.new()
	var err := d.append_from_file(ProjectSettings.globalize_path(path), st)
	if err != OK:
		push_error("can't read " + path)
		return []
	var scn: Node3D = d.generate_scene(st)
	root.add_child(scn)
	var sk: Skeleton3D = scn.find_children("*", "Skeleton3D", true, false)[0]
	# skeleton -> scene transform (walked by hand: the tree isn't live during _initialize)
	var xf := Transform3D()
	var nd: Node = sk
	while nd != null and nd != scn.get_parent():
		if nd is Node3D:
			xf = (nd as Node3D).transform * xf
		nd = nd.get_parent()
	var gs := xf.basis.get_scale()
	if absf(gs.x - gs.y) > 1e-5 or absf(gs.x - gs.z) > 1e-5 or not xf.basis.orthonormalized().is_equal_approx(Basis()):
		push_error("unexpected armature transform %s in %s" % [xf, path])
	return [scn, sk, gs.x]


## Copy a skeleton's rest into a new one, in metres.
func _metric_skeleton(sk: Skeleton3D, s: float) -> Skeleton3D:
	var out := Skeleton3D.new()
	out.name = "Skeleton"
	for i in sk.get_bone_count():
		out.add_bone(sk.get_bone_name(i))
	for i in sk.get_bone_count():
		out.set_bone_parent(i, sk.get_bone_parent(i))
		var r := sk.get_bone_rest(i)
		out.set_bone_rest(i, Transform3D(r.basis, r.origin * s))
	out.reset_bone_poses()
	return out


## Read the hero clips from rig_<clip>.glb and store them with the hero skeleton (metres).
func _extract_clips(dir: String) -> void:
	var lib := AnimationLibrary.new()
	var skel: Skeleton3D = null
	for out_name in CLIPS:
		var file: String = CLIPS[out_name][0]
		var r := _load_glb(dir.path_join(file + ".glb"))
		var scn: Node3D = r[0]
		var sk: Skeleton3D = r[1]
		var s: float = r[2]
		if skel == null:
			skel = _metric_skeleton(sk, s)
		var ap: AnimationPlayer = scn.find_children("*", "AnimationPlayer", true, false)[0]
		var a: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		for t in range(a.get_track_count() - 1, -1, -1):
			var bn := String(a.track_get_path(t).get_concatenated_subnames())
			if sk.find_bone(bn) < 0 or a.track_get_type(t) not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D]:
				a.remove_track(t)
				continue
			a.track_set_path(t, NodePath("Skeleton:" + bn))
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				for k in a.track_get_key_count(t):
					a.track_set_key_value(t, k, a.track_get_key_value(t, k) * s)
		a.resource_name = out_name
		lib.add_animation(out_name, a)
		print("clip ", out_name, " <- ", file, " len=", a.length, " tracks=", a.get_track_count())
		scn.free()
	var holder := Node3D.new()
	holder.name = "HeroClips"
	holder.add_child(skel)
	skel.owner = holder
	var ap2 := AnimationPlayer.new()
	ap2.name = "AnimationPlayer"
	holder.add_child(ap2)
	ap2.owner = holder
	ap2.add_animation_library("", lib)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLIPS_SCN.get_base_dir()))
	var ps := PackedScene.new()
	ps.pack(holder)
	var err := ResourceSaver.save(ps, CLIPS_SCN, ResourceSaver.FLAG_COMPRESS)
	print("clips saved ", CLIPS_SCN, " ", error_string(err))
	holder.free()


func _global_rests(sk: Skeleton3D) -> Array:
	var g := []
	g.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		g[i] = sk.get_bone_global_rest(i)
	return g


## Retarget one clip from src skeleton to dst skeleton (both metres, same bone names).
func _retarget(a: Animation, ss: Skeleton3D, ds: Skeleton3D, loop: bool) -> Animation:
	var n := ds.get_bone_count()
	var sg := _global_rests(ss)
	var dg := _global_rests(ds)
	var smap := [] # dst bone -> src bone
	var match_q := [] # dst matched global rest rotation
	var srest_q := []
	for i in n:
		var bn := ds.get_bone_name(i)
		var si := ss.find_bone(bn)
		smap.append(si)
		var dq: Quaternion = dg[i].basis.get_rotation_quaternion()
		var sq: Quaternion = sg[si].basis.get_rotation_quaternion() if si >= 0 else dq
		srest_q.append(sq)
		var mq := dq
		if si >= 0 and AIM.has(bn) and bn not in NO_SWING:
			var dc := ds.find_bone(AIM[bn])
			var sc := ss.find_bone(AIM[bn])
			if dc >= 0 and sc >= 0:
				var dd: Vector3 = (dg[dc].origin - dg[i].origin).normalized()
				var sd: Vector3 = (sg[sc].origin - sg[si].origin).normalized()
				mq = (Quaternion(dd, sd) * dq).normalized()
		match_q.append(mq)
	# source tracks by bone
	var rot_t := {}
	var pos_t := {}
	for t in a.get_track_count():
		var bn := String(a.track_get_path(t).get_concatenated_subnames())
		var bi := ss.find_bone(bn)
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_t[bi] = t
		elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			pos_t[bi] = t
	var hips_s := ss.find_bone("Hips")
	var hips_d := ds.find_bone("Hips")
	var hr: float = dg[hips_d].origin.y / sg[hips_s].origin.y
	var out := Animation.new()
	out.length = a.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var tracks := {}
	for i in n:
		if smap[i] >= 0 and rot_t.has(smap[i]):
			var t := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(t, NodePath("Skeleton:" + ds.get_bone_name(i)))
			tracks[i] = t
	var hp_track := -1
	if pos_t.has(hips_s):
		hp_track = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hp_track, NodePath("Skeleton:Hips"))
	var frames := int(round(a.length * FPS))
	var sn := ss.get_bone_count()
	for f in frames + 1:
		var time := minf(f / FPS, a.length)
		# source global rotations at this time
		var sgq := []
		sgq.resize(sn)
		for b in sn:
			var lq: Quaternion = ss.get_bone_rest(b).basis.get_rotation_quaternion()
			if rot_t.has(b):
				lq = a.rotation_track_interpolate(rot_t[b], time)
			var p := ss.get_bone_parent(b)
			sgq[b] = (sgq[p] * lq) if p >= 0 else lq
		var dgq := []
		dgq.resize(n)
		for i in n:
			var si: int = smap[i]
			var q: Quaternion = match_q[i]
			if si >= 0:
				var delta: Quaternion = sgq[si] * (srest_q[i] as Quaternion).inverse()
				q = delta * match_q[i]
			dgq[i] = q.normalized()
		for i in tracks:
			var p := ds.get_bone_parent(i)
			var lq: Quaternion = ((dgq[p] as Quaternion).inverse() * dgq[i]) if p >= 0 else dgq[i]
			out.rotation_track_insert_key(tracks[i], time, lq.normalized())
		if hp_track >= 0:
			var sp: Vector3 = a.position_track_interpolate(pos_t[hips_s], time)
			var off: Vector3 = (sp - sg[hips_s].origin) * hr
			if loop:
				off = Vector3(0, off.y, 0)
			out.position_track_insert_key(hp_track, time, dg[hips_d].origin + off)
	return out


## Time of the fastest hand movement (the strike) in a retargeted clip.
func _strike_time(a: Animation, ds: Skeleton3D) -> float:
	var best := 0.0
	var best_t := a.length * 0.4
	var prev := {}
	var f := 0.0
	while f <= a.length:
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var bn := String(a.track_get_path(t).get_concatenated_subnames())
				ds.set_bone_pose_rotation(ds.find_bone(bn), a.rotation_track_interpolate(t, f))
		var speed := 0.0
		for h in ["LeftHand", "RightHand"]:
			var p := ds.get_bone_global_pose(ds.find_bone(h)).origin
			if prev.has(h):
				speed = maxf(speed, p.distance_to(prev[h]) * FPS)
			prev[h] = p
		if speed > best:
			best = speed
			best_t = f
		f += 1.0 / FPS
	ds.reset_bone_poses()
	return best_t


func _build(n: String, path: String, src: Node3D) -> void:
	var cfg: Dictionary = CHARS[n]
	var r := _load_glb(path)
	var scn: Node3D = r[0]
	var rsk: Skeleton3D = r[1]
	var s: float = r[2]
	var sk := _metric_skeleton(rsk, s)
	var rmi: MeshInstance3D = rsk.find_children("*", "MeshInstance3D", true, false)[0]
	# Godot skins: world = armature * bone_pose * bind * vertex. With the armature scale S folded
	# into the bones (pose' = S * pose * S^-1) the vertices stay put and bind' = S * bind.
	var arrays := rmi.mesh.surface_get_arrays(0)
	var fmt: int = rmi.mesh.surface_get_format(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in verts.size():
		lo = lo.min(verts[i])
		hi = hi.max(verts[i])
	var skin := Skin.new()
	var rskin: Skin = rmi.skin
	for b in rskin.get_bind_count():
		var bx := rskin.get_bind_pose(b)
		var bname := rskin.get_bind_name(b)
		if bname == "":
			bname = rsk.get_bone_name(rskin.get_bind_bone(b))
		skin.add_named_bind(bname, Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO) * bx)
	# the game's material for this character (all PBR maps, VRAM-compressed textures)
	var game: Node = (load("res://assets/characters/%s/%s.glb" % [n, n]) as PackedScene).instantiate()
	var gmi: MeshInstance3D = game.find_children("*", "MeshInstance3D", true, false)[0]
	var mat: Material = gmi.get_active_material(0).duplicate()
	game.free()
	var flags: int = fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat, "body", flags)
	im.generate_lods(60.0, 25.0, [])
	var mesh := im.get_mesh()
	mesh.resource_name = n

	var out := Node3D.new()
	out.name = n.capitalize()
	out.add_child(sk)
	sk.owner = out
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh
	body.skin = skin
	sk.add_child(body)
	body.owner = out
	body.skeleton = NodePath("..")

	# eyes: reuse the measured positions from the hand-made rig, shifted onto this mesh
	var head := sk.find_bone("Head")
	var head_g := sk.get_bone_global_rest(head)
	var old_ps := load("res://assets/characters/%s/%s_rig.scn" % [n, n]) as PackedScene
	var eye_l := head_g.origin + Vector3(-0.03, 0.08, 0.1)
	var eye_r := head_g.origin + Vector3(0.03, 0.08, 0.1)
	if old_ps != null:
		var old := old_ps.instantiate()
		var omi: MeshInstance3D = old.find_children("*", "MeshInstance3D", true, false)[0]
		var ov: PackedVector3Array = omi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var olo := Vector3(INF, INF, INF)
		var ohi := -olo
		for v in ov:
			olo = olo.min(v)
			ohi = ohi.max(v)
		var shift := Vector3((lo.x + hi.x - olo.x - ohi.x) * 0.5, lo.y - olo.y, (lo.z + hi.z - olo.z - ohi.z) * 0.5)
		eye_l = old.get_meta("eye_l") + shift
		eye_r = old.get_meta("eye_r") + shift
		old.free()
	out.set_meta("height", hi.y - lo.y)
	out.set_meta("eye_l", eye_l)
	out.set_meta("eye_r", eye_r)
	out.set_meta("eye_l_local", head_g.affine_inverse() * eye_l)
	out.set_meta("eye_r_local", head_g.affine_inverse() * eye_r)
	out.set_meta("eye_radius", cfg.eye_r)
	out.set_meta("head_rest", head_g.origin)
	out.set_meta("head_bone", "Head")

	# clips
	var src_sk: Skeleton3D = src.get_node("Skeleton")
	var src_ap: AnimationPlayer = src.get_node("AnimationPlayer")
	var lib := AnimationLibrary.new()
	root.add_child(out) # global poses for the strike search
	for clip in CLIPS:
		var a := _retarget(src_ap.get_animation(clip), src_sk, sk, CLIPS[clip][1])
		a.resource_name = clip
		lib.add_animation(clip, a)
	var st := _strike_time(lib.get_animation("attack"), sk)
	out.set_meta("strike_time", st)
	root.remove_child(out)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	out.add_child(ap)
	ap.owner = out
	ap.add_animation_library("", lib)

	var ps := PackedScene.new()
	ps.pack(out)
	var dst := "res://assets/characters/%s/%s_anim.scn" % [n, n]
	var err := ResourceSaver.save(ps, dst, ResourceSaver.FLAG_COMPRESS)
	print("%s: bones=%d verts=%d h=%.3f strike=%.2fs eyes=%s,%s -> %s %s" % [n, sk.get_bone_count(), verts.size(), hi.y - lo.y, st, eye_l, eye_r, dst, error_string(err)])
	out.free()
	scn.free()
