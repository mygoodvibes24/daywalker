extends "res://tools/build_enemy_anims.gd"
## Offline tool (asset round 3): wires the round-3 mocap into the character scenes.
##   cd game && godot --headless -s res://tools/build_r3_anims.gd
##   (R3_ONLY=creatures | bosses to do one half)
##
## 1. Creatures: the werewolf and vampire clips rigged on their own meshes
##    (res://assets/characters/<enemy>/clips_r3/*.glb, skeleton-only, centimetres; folder has a
##    .gdignore) are retargeted onto the skeletons already in <enemy>_anim.scn and replace or join
##    the hero-mocap clips there (the mesh, material and eyes are left as they are). The civilian
##    borrows the werewolf's heavy fall. The werewolf's roar also joins werewolf_boss_clips.res
##    (the Hollow Alpha's howl).
## 2. Bosses: Marcus Crane and Seraphine's Abomination get bodies of their own,
##    res://assets/characters/<boss>/<boss>_anim.scn, built like the enemies' (skinned mesh from
##    rigged/<x>_rigged.glb, PBR material from the imported <x>.glb) with the hero clips for
##    locomotion, their own clips where they have one, and <boss>_boss_clips.res for boss_base.gd.
##
## Root motion: every clip is baked in place. The hips keep their height (crouches, the fall onto
## the back) and rotation, but their travel over the ground is dropped, because the game moves the
## body itself (a clip that slid would drift away from the collider and snap back on the next clip).
## A clip whose travel runs diagonally (Marcus's lunge) gets a yaw correction on the hips so it
## strikes along the facing.
## Strike times come from the asset manifests (peak hand speed measured on the source clips).

const CR := "res://assets/characters/"
## slot -> {file, loop, trim (s, 0 = whole clip), strike (s, -1 = none), yaw (deg)}
const CREATURES := {
	"werewolf": {
		"attack": {"file": "werewolf/clips_r3/werewolf_anim_heavy_swipe.glb", "strike": 1.57},
		"sprint": {"file": "werewolf/clips_r3/werewolf_anim_run_feral.glb", "loop": true},
		# the code flies the arc of the leap: keep the crouch and the landing, drop the clip's rise
		"jump": {"file": "werewolf/clips_r3/werewolf_anim_pounce.glb", "strike": 1.3, "max_rise": 0.1},
		"death": {"file": "werewolf/clips_r3/werewolf_anim_death_heavy.glb"},
		"roar": {"file": "werewolf/clips_r3/werewolf_anim_roar.glb", "strike": 0.97},
	},
	"vampire": {
		# the first raking swipe of the four-hit combo; the whole string stays as claw_combo
		"attack": {"file": "vampire/clips_r3/vampire_anim_claw_combo.glb", "trim": 1.3, "strike": 0.57},
		"claw_combo": {"file": "vampire/clips_r3/vampire_anim_claw_combo.glb", "strike": 0.57},
		"lunge": {"file": "vampire/clips_r3/vampire_anim_lunge.glb", "trim": 1.6, "strike": 0.77},
		"backflip": {"file": "vampire/clips_r3/vampire_anim_backflip.glb"},
	},
	"civilian": {
		"death": {"file": "werewolf/clips_r3/werewolf_anim_death_heavy.glb"},
	},
}
const BOSS_LIB_ADD := {
	"werewolf": {"roar": {"file": "werewolf/clips_r3/werewolf_anim_roar.glb", "strike": 0.97}},
}
## Boss bodies. base: the hero clips (locomotion and flinches); own: slot overrides in the main
## library; boss: the boss library (the hero's sword moves, then the boss's own on top).
const BOSSES := {
	"marcus": {
		"rigged": "marcus/rigged/marcus_rigged.glb",
		"mat_glb": "marcus/marcus_crane.glb",
		# the velvet frock coat imports glossy (metallic 1 times the map): matte it
		"metallic": 0.0, "roughness": 0.72,
		"own": {
			"attack": {"file": "marcus/clips_r3/marcus_anim_slash_combo.glb", "strike": 0.83},
			"death": {"file": "marcus/clips_r3/marcus_anim_death.glb"},
		},
		"boss": {
			"thrust": {"file": "marcus/clips_r3/marcus_anim_dash_lunge.glb", "strike": 0.9, "yaw": -45.0},
			"combo": {"file": "marcus/clips_r3/marcus_anim_slash_combo.glb", "strike": 0.83},
		},
	},
	"abomination": {
		"rigged": "abomination/rigged/abomination_rigged.glb",
		"mat_glb": "abomination/abomination.glb",
		"metallic": 0.0, "roughness": -1.0, # keep the map's roughness, drop the metal
		"own": {
			"attack": {"file": "abomination/clips_r3/abomination_anim_grab_throw.glb", "strike": 3.5},
		},
		"boss": {
			"heavy": {"file": "abomination/clips_r3/abomination_anim_slam.glb", "strike": 1.67},
			"stance": {"file": "abomination/clips_r3/abomination_anim_roar.glb", "strike": 0.6},
			"roar": {"file": "abomination/clips_r3/abomination_anim_roar.glb", "strike": 0.6},
		},
	},
}


func _initialize() -> void:
	var only := OS.get_environment("R3_ONLY")
	if only == "" or only == "creatures":
		for n in CREATURES:
			_creature(n)
		for n in BOSS_LIB_ADD:
			_boss_lib_add(n)
	if only == "" or only == "bosses":
		for n in BOSSES:
			_boss_body(n)
	quit()


## A clip GLB (skeleton-only) -> [animation with Skeleton:<bone> tracks in metres, metric skeleton].
func _read_clip(file: String, trim: float) -> Array:
	var r := _load_glb(CR + file)
	if r.is_empty():
		return []
	var scn: Node3D = r[0]
	var sk: Skeleton3D = r[1]
	var s: float = r[2]
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
	if trim > 0.0 and trim < a.length:
		a.length = trim
	var msk := _metric_skeleton(sk, s)
	scn.free()
	return [a, msk]


## Retarget one manifest clip onto `ds`, in place, with the optional hips yaw correction.
func _clip_onto(cfg: Dictionary, ds: Skeleton3D) -> Animation:
	var rc := _read_clip(cfg.file, float(cfg.get("trim", 0.0)))
	if rc.is_empty():
		return null
	var src_sk: Skeleton3D = rc[1]
	var out := _retarget(rc[0], src_sk, ds, bool(cfg.get("loop", false)), true)
	src_sk.free()
	var rise := float(cfg.get("max_rise", -1.0))
	if rise >= 0.0:
		var hy := ds.get_bone_rest(ds.find_bone("Hips")).origin.y + rise
		for t in out.get_track_count():
			if out.track_get_type(t) == Animation.TYPE_POSITION_3D:
				for k in out.track_get_key_count(t):
					var v: Vector3 = out.track_get_key_value(t, k)
					out.track_set_key_value(t, k, Vector3(v.x, minf(v.y, hy), v.z))
	var yaw := deg_to_rad(float(cfg.get("yaw", 0.0)))
	if yaw != 0.0:
		var turn := Quaternion(Vector3.UP, yaw)
		for t in out.get_track_count():
			if String(out.track_get_path(t).get_concatenated_subnames()) == "Hips":
				if out.track_get_type(t) == Animation.TYPE_ROTATION_3D:
					for k in out.track_get_key_count(t):
						out.track_set_key_value(t, k, (turn * out.track_get_key_value(t, k)).normalized())
	return out


func _creature(n: String) -> void:
	var path := CR + "%s/%s_anim.scn" % [n, n]
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	var sk: Skeleton3D = inst.get_node("Skeleton")
	var ap: AnimationPlayer = inst.get_node("AnimationPlayer")
	var old: AnimationLibrary = ap.get_animation_library("")
	var lib := AnimationLibrary.new()
	for k in old.get_animation_list():
		lib.add_animation(k, old.get_animation(k))
	var strikes: Dictionary = inst.get_meta("strike_times", {})
	var clips: Dictionary = CREATURES[n]
	for slot in clips:
		var cfg: Dictionary = clips[slot]
		var a := _clip_onto(cfg, sk)
		if a == null:
			push_error("%s: can't read %s" % [n, cfg.file])
			continue
		a.resource_name = slot
		if lib.has_animation(slot):
			lib.remove_animation(slot)
		lib.add_animation(slot, a)
		if float(cfg.get("strike", -1.0)) >= 0.0:
			strikes[slot] = float(cfg.strike)
		print("%s: %s <- %s len=%.2f" % [n, slot, String(cfg.file).get_file(), a.length])
	ap.remove_animation_library("")
	ap.add_animation_library("", lib)
	inst.set_meta("strike_times", strikes)
	inst.set_meta("r3_clips", clips.keys())
	if strikes.has("attack"):
		inst.set_meta("strike_time", strikes.attack)
	var ps := PackedScene.new()
	ps.pack(inst)
	var err := ResourceSaver.save(ps, path, ResourceSaver.FLAG_COMPRESS)
	print("%s -> %s %s strikes=%s" % [n, path, error_string(err), strikes])
	inst.free()


func _boss_lib_add(n: String) -> void:
	var path := CR + "%s/%s_boss_clips.res" % [n, n]
	var lib: AnimationLibrary = load(path)
	var inst: Node3D = (load(CR + "%s/%s_anim.scn" % [n, n]) as PackedScene).instantiate()
	var sk: Skeleton3D = inst.get_node("Skeleton")
	var strikes: Dictionary = lib.get_meta("strike_times", {})
	for slot in BOSS_LIB_ADD[n]:
		var cfg: Dictionary = BOSS_LIB_ADD[n][slot]
		var a := _clip_onto(cfg, sk)
		a.resource_name = slot
		if lib.has_animation(slot):
			lib.remove_animation(slot)
		lib.add_animation(slot, a)
		strikes[slot] = float(cfg.get("strike", 0.6))
	lib.set_meta("strike_times", strikes)
	var err := ResourceSaver.save(lib, path, ResourceSaver.FLAG_COMPRESS)
	print("%s boss clips -> %s %s %s" % [n, path, error_string(err), lib.get_animation_list()])
	inst.free()


## The hero's sword clips (as in BOSS_CLIPS mode), read straight from the GLBs.
func _hero_boss_clips() -> Dictionary:
	var hero := {}
	for out_name in BOSS_CLIPS:
		var file: String = BOSS_CLIPS[out_name][0]
		var r := _load_glb(SOL_DIR + "sol_mod_anim_%s.glb" % file)
		if r.is_empty():
			continue
		var scn: Node3D = r[0]
		var sk: Skeleton3D = r[1]
		var s: float = r[2]
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
		hero[out_name] = a
		scn.free()
	return hero


## Web budget for the boss bodies (critic round 2): about 20k triangles each.
const BOSS_TRIS := 20000


## Decimate a skinned surface to about `target` triangles: Godot's LOD simplifier (meshoptimizer)
## picks the index buffer, then unreferenced vertices are dropped so the file shrinks too.
func _decimate(arrays: Array, flags: int, target: int) -> Array:
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if idx.size() / 3 <= target:
		return arrays
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "", flags)
	# a finer LOD chain than the default so one lands near the target
	im.generate_lods(60.0, 25.0, [])
	var best := idx
	for l in im.get_surface_lod_count(0):
		var li: PackedInt32Array = im.get_surface_lod_indices(0, l)
		if li.size() / 3 >= target * 0.8 and li.size() < best.size():
			best = li
	# compact
	var remap := {}
	var order := PackedInt32Array()
	var nidx := PackedInt32Array()
	nidx.resize(best.size())
	for i in best.size():
		var v := best[i]
		if not remap.has(v):
			remap[v] = order.size()
			order.append(v)
		nidx[i] = remap[v]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var nv: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for a in Mesh.ARRAY_MAX:
		var src = arrays[a]
		if src == null or a == Mesh.ARRAY_INDEX:
			continue
		var per: int = src.size() / nv # components per vertex (tangents 4, bones/weights 4 or 8)
		var dst = src.duplicate()
		dst.resize(order.size() * per)
		for k in order.size():
			for c in per:
				dst[k * per + c] = src[order[k] * per + c]
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = nidx
	print("decimated %d -> %d triangles, %d -> %d vertices" % [idx.size() / 3, nidx.size() / 3, nv, order.size()])
	return out


func _boss_body(n: String) -> void:
	var cfg: Dictionary = BOSSES[n]
	var r := _load_glb(CR + cfg.rigged)
	if r.is_empty():
		return
	var scn: Node3D = r[0]
	var rsk: Skeleton3D = r[1]
	var s: float = r[2]
	var sk := _metric_skeleton(rsk, s)
	var rmi: MeshInstance3D = rsk.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays := rmi.mesh.surface_get_arrays(0)
	var fmt: int = rmi.mesh.surface_get_format(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	# armature scale folded into the binds (see build_enemy_anims._build)
	var skin := Skin.new()
	var rskin: Skin = rmi.skin
	for b in rskin.get_bind_count():
		var bname := rskin.get_bind_name(b)
		if bname == "":
			bname = rsk.get_bone_name(rskin.get_bind_bone(b))
		skin.add_named_bind(bname, Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO) * rskin.get_bind_pose(b))
	# the PBR material from the imported (unrigged) model, its textures imported Lossy
	var game: Node = (load(CR + cfg.mat_glb) as PackedScene).instantiate()
	var gmi: MeshInstance3D = game.find_children("*", "MeshInstance3D", true, false)[0]
	var mat: StandardMaterial3D = gmi.get_active_material(0).duplicate()
	game.free()
	if float(cfg.metallic) >= 0.0:
		mat.metallic = float(cfg.metallic)
		mat.metallic_texture = null
	if float(cfg.roughness) >= 0.0:
		mat.roughness = float(cfg.roughness)
		mat.roughness_texture = null
	mat.resource_name = n
	var flags: int = fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	arrays = _decimate(arrays, flags, BOSS_TRIS)
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
	var head := sk.find_bone("Head")
	var head_g := sk.get_bone_global_rest(head)
	out.set_meta("height", hi.y - lo.y)
	out.set_meta("feet", lo.y)
	out.set_meta("head_rest", head_g.origin)
	out.set_meta("head_bone", "") # the eyes are in the texture: no glowing eye spheres
	out.set_meta("eye_radius", 0.0)

	root.add_child(out)
	# main library: the hero's locomotion and flinches, then the boss's own clips
	var src: Node3D = (load(CLIPS_SCN) as PackedScene).instantiate()
	root.add_child(src)
	var src_sk: Skeleton3D = src.get_node("Skeleton")
	var src_ap: AnimationPlayer = src.get_node("AnimationPlayer")
	var lib := AnimationLibrary.new()
	for clip in CLIPS:
		var a := _retarget(src_ap.get_animation(clip), src_sk, sk, CLIPS[clip][1])
		a.resource_name = clip
		lib.add_animation(clip, a)
	var strike := _strike_time(lib.get_animation("attack"), sk)
	for slot in cfg.own:
		var a := _clip_onto(cfg.own[slot], sk)
		a.resource_name = slot
		lib.remove_animation(slot)
		lib.add_animation(slot, a)
		if slot == "attack":
			strike = float(cfg.own[slot].strike)
	out.set_meta("strike_time", strike)
	# boss library
	var blib := AnimationLibrary.new()
	var strikes := {}
	var hero := _hero_boss_clips()
	for k in hero:
		var a := _retarget(hero[k], src_sk, sk, BOSS_CLIPS[k][1], true)
		a.resource_name = k
		blib.add_animation(k, a)
		strikes[k] = _strike_time(a, sk)
	for k in cfg.boss:
		var a := _clip_onto(cfg.boss[k], sk)
		a.resource_name = k
		if blib.has_animation(k):
			blib.remove_animation(k)
		blib.add_animation(k, a)
		strikes[k] = float(cfg.boss[k].get("strike", 0.6))
	blib.set_meta("strike_times", strikes)
	src.free()
	root.remove_child(out)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	out.add_child(ap)
	ap.owner = out
	ap.add_animation_library("", lib)
	var ps := PackedScene.new()
	ps.pack(out)
	var dst := CR + "%s/%s_anim.scn" % [n, n]
	var err := ResourceSaver.save(ps, dst, ResourceSaver.FLAG_COMPRESS)
	var bdst := CR + "%s/%s_boss_clips.res" % [n, n]
	var err2 := ResourceSaver.save(blib, bdst, ResourceSaver.FLAG_COMPRESS)
	print("%s: verts=%d h=%.3f feet=%.3f strike=%.2f -> %s %s; boss %s %s strikes=%s" % [n, verts.size(), hi.y - lo.y, lo.y, strike, dst, error_string(err), blib.get_animation_list(), error_string(err2), strikes])
	out.free()
	scn.free()
