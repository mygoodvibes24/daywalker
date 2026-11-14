extends SceneTree
## Offline builder for Sol's modular hero: res://assets/characters/sol/sol_modular.scn
## Run from game/:  godot --headless -s res://tools/build_sol_modular.gd
##
## Inputs (all in assets/characters/sol/, generated with Higgsfield; see CREDITS.md):
##   sol_mod_rig_idle.glb      the coatless body, auto-rigged (24-bone skeleton in centimetres) + idle clip
##   sol_mod_anim_<clip>.glb   one clip each on the same skeleton (run, sprint, slash, hit, death, jump)
##   sol_mod_body_src.glb      the unrigged body: its full-resolution PBR maps texture the rigged mesh
##   sol_mod_coat_src.glb      the open leather trenchcoat on its own
##   sol_mod_head_src.glb      a detailed head-and-neck bust
##   sol_mod_hand_src.glb      a right fist in a sword grip (mirrored for the left hand)
##   sol_mod_boot_src.glb      one combat boot (mirrored for the other foot)
##   sol_mod_sword_<name>.glb  four swords
## The Tripo parts face +X, are 1 unit tall and are fitted here; nothing is hand-placed in an editor.
##
## Output scene:
##   SolModular (Node3D)
##     Skeleton3D             body skeleton in metres (feet at y=0, facing +Z) + 8x4 coat spring bones
##       Body                 skinned body; head, hands (and boots, if replaced) cut away
##       Coat                 skinned coat: upper half on spine/shoulder/arm bones, skirt on the spring bones
##       Head (BoneAttachment3D) -> HeadMesh, Glasses
##       Hand.R / Hand.L      fists; Hand.R holds Blade -> the sword scene
##       Foot.L / Foot.R      (only if USE_BOOT_MODEL)
##     AnimationPlayer        clips: idle, run, sprint (looped), slash, slash_back, hit, death, jump
##     CoatSim                scripts/coat_sim.gd
## and the four sword scenes sol_sword_<name>.scn (origin = the grip, blade along +Z, flat facing +-X).

const D := "res://assets/characters/sol/"
const OUT := D + "sol_modular.scn"
const RIG := D + "sol_mod_rig_idle.glb"
const CLIPS := {
	"idle": D + "sol_mod_rig_idle.glb",
	"run": D + "sol_mod_anim_run.glb",
	"sprint": D + "sol_mod_anim_sprint.glb",
	"slash": D + "sol_mod_anim_slash.glb",
	"hit": D + "sol_mod_anim_hit.glb",
	"death": D + "sol_mod_anim_death.glb",
	"jump": D + "sol_mod_anim_jump.glb",
}
const LOOPED := ["idle", "run", "sprint"]
const SWORDS := {
	# name: [source, overall length (m)]
	"silver": [D + "sol_mod_sword_silver.glb", 1.05],
	"sabre": [D + "sol_mod_sword_sabre.glb", 1.0],
	"cleaver": [D + "sol_mod_sword_cleaver.glb", 0.82],
	"rapier": [D + "sol_mod_sword_rapier.glb", 1.12],
}
const USE_BOOT_MODEL := false

# ---- fitting constants (metres, skeleton space: +Y up, +Z forward, +X = Sol's left)
const NECK_CUT := 1.585 # body triangles above this (around the head) are removed
const HEAD_SCALE := 0.37
const HEAD_OFF := Vector3(-0.02, 1.699, -0.005)
const HEAD_CUT := -0.47 # bust units: everything below is cut (shirt, shoulders)
const HAND_SCALE := 0.15
const HAND_WRIST := Vector3(0.0, -0.3, 0.0) # point of the fist mesh (units) placed on the wrist joint
const GRIP_IN_FIST := Vector3(0.02, 0.17, 0.0) # sword grip centre in fist-mesh units
const COAT_SCALE := Vector3(1.2, 1.12, 1.32)
const COAT_TOP := 1.655 # collar height
const COAT_SKIRT_STRETCH := 1.12 # lengthens the skirt below the waist toward mid-shin
const COAT_WAIST := 1.0
const COAT_MARGIN := 0.014 # minimum gap kept between coat and body at rest
const CHAIN_ANGLES := [-160.0, -115.0, -70.0, -25.0, 25.0, 70.0, 115.0, 160.0]
const CHAIN_TOP := 0.98
const CHAIN_LINKS := 4

var skel: Skeleton3D
var bone_rest_g: Array[Transform3D] = []
var body_pts := PackedVector3Array()
var body_nrm := PackedVector3Array()
var grid := {}
const CELL := 0.05


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var root := Node3D.new()
	root.name = "SolModular"
	var src: Node = load(RIG).instantiate()
	var src_skel: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var src_mi: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
	var sk_xf := _node_xf(src_skel)
	var unit := sk_xf.basis.get_scale().x # 0.01: the rig is in centimetres
	print("rig skeleton scale ", unit)
	skel = Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	skel.owner = root
	for i in src_skel.get_bone_count():
		skel.add_bone(src_skel.get_bone_name(i))
	for i in src_skel.get_bone_count():
		skel.set_bone_parent(i, src_skel.get_bone_parent(i))
		var r := src_skel.get_bone_rest(i)
		r.origin *= unit
		skel.set_bone_rest(i, r)
	_add_coat_bones()
	skel.reset_bone_poses()
	for i in skel.get_bone_count():
		bone_rest_g.append(skel.get_bone_global_rest(i))

	# ---------------------------------------------------------------- body
	var body_arr := _weld(src_mi.mesh.surface_get_arrays(0))
	var src_skin: Skin = src_mi.skin
	var body_skin := Skin.new()
	var bind_bone := PackedInt32Array()
	var worst := 0.0
	for b in src_skin.get_bind_count():
		var bname: String = src_skin.get_bind_name(b)
		if bname == "":
			bname = src_skel.get_bone_name(src_skin.get_bind_bone(b))
		var pose := src_skin.get_bind_pose(b)
		pose = Transform3D(Basis.from_scale(Vector3.ONE * unit), Vector3.ZERO) * pose
		body_skin.add_named_bind(bname, pose)
		var bi := skel.find_bone(bname)
		bind_bone.append(bi)
		var chk := bone_rest_g[bi] * pose
		worst = maxf(worst, (chk.origin).length() + (chk.basis.x - Vector3.RIGHT).length())
	print("body binds ", src_skin.get_bind_count(), " rest*bind deviation ", worst)
	body_arr = _cut_body(body_arr, bind_bone)
	var body_mat := _material(D + "sol_mod_body_src.glb")
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _mesh(body_arr, body_mat, true)
	body.skin = body_skin
	skel.add_child(body)
	body.owner = root
	_index_body(body_arr, bind_bone)

	# ---------------------------------------------------------------- coat
	var coat := MeshInstance3D.new()
	coat.name = "Coat"
	var coat_res := _build_coat()
	coat.mesh = coat_res[0]
	coat.skin = coat_res[1]
	skel.add_child(coat)
	coat.owner = root

	# ---------------------------------------------------------------- head + glasses
	var head_att := _attach(root, "Head", "Head")
	var head_arr := _load_arrays(D + "sol_mod_head_src.glb", Transform3D(Basis(Vector3.UP, -PI / 2.0).scaled(Vector3.ONE * HEAD_SCALE), HEAD_OFF))
	head_arr = _cut_bust(head_arr, D + "sol_mod_head_src.glb")
	var head_mat := _material(D + "sol_mod_head_src.glb")
	head_mat.metallic_specular = 0.32 # the generated skin reads plastic at full specular
	_add_part(head_att, root, "HeadMesh", head_arr, head_mat, true)
	_add_glasses(head_att, root)

	# ---------------------------------------------------------------- hands + sword
	var fist_r := _fist_xf("Right")
	var hand_mat := _material(D + "sol_mod_hand_src.glb")
	hand_mat.metallic_specular = 0.32
	var hr := _attach(root, "Hand.R", "RightHand")
	_add_part(hr, root, "HandMesh", _load_arrays(D + "sol_mod_hand_src.glb", fist_r), hand_mat, false)
	var hl := _attach(root, "Hand.L", "LeftHand")
	_add_part(hl, root, "HandMesh", _load_arrays(D + "sol_mod_hand_src.glb", _fist_xf("Left")), hand_mat, false)
	# sword grip frame: blade (+Z) out of the thumb side (-Z of the fist mesh), edge along the fingers
	var grip_mesh := Transform3D(Basis(Vector3.UP, PI), GRIP_IN_FIST)
	var blade := Node3D.new()
	blade.name = "Blade"
	hr.add_child(blade)
	blade.owner = root
	blade.transform = bone_rest_g[skel.find_bone("RightHand")].affine_inverse() * fist_r * grip_mesh
	blade.transform.basis = blade.transform.basis.orthonormalized()
	for sname in SWORDS:
		_build_sword(sname, SWORDS[sname][0], SWORDS[sname][1])
	var sword: Node3D = (load(D + "sol_sword_silver.scn") as PackedScene).instantiate()
	sword.name = "Sword"
	blade.add_child(sword)
	sword.owner = root

	# ---------------------------------------------------------------- boots
	if USE_BOOT_MODEL:
		_add_boots(root)

	# ---------------------------------------------------------------- clips
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	ap.owner = root
	ap.root_node = NodePath("..")
	ap.add_animation_library("", _build_clips(unit))

	# ---------------------------------------------------------------- coat simulation
	var sim := Node.new()
	sim.name = "CoatSim"
	sim.set_script(load("res://scripts/coat_sim.gd"))
	root.add_child(sim)
	sim.owner = root
	sim.set("tails", _coat_tails)
	sim.set("links", CHAIN_LINKS)
	sim.set("chains", CHAIN_ANGLES.size())

	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, OUT, ResourceSaver.FLAG_COMPRESS)
	print("build_sol_modular: %s -> %s (%d ms)" % [OUT, error_string(err), Time.get_ticks_msec() - t0])
	quit(0 if err == OK else 1)


# =========================================================================== helpers

func _node_xf(n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Merge duplicate vertices (the rig round trip un-indexed many of them).
func _weld(arr: Array) -> Array:
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.index()
	var out := st.commit_to_arrays()
	if out[Mesh.ARRAY_TANGENT] == null and out[Mesh.ARRAY_TEX_UV] != null:
		st = SurfaceTool.new()
		st.create_from_arrays(out)
		st.generate_tangents()
		out = st.commit_to_arrays()
	return out


## The first mesh of a GLB, transformed by `xf` after its own node transform.
func _load_arrays(path: String, xf: Transform3D) -> Array:
	var scn: Node = load(path).instantiate()
	var mi: MeshInstance3D = scn.find_children("*", "MeshInstance3D", true, false)[0]
	var arr: Array = mi.mesh.surface_get_arrays(0)
	arr = _xform(arr, xf * _node_xf(mi))
	scn.free()
	return arr


func _xform(arr: Array, xf: Transform3D) -> Array:
	arr = arr.duplicate()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX].duplicate()
	for i in v.size():
		v[i] = xf * v[i]
	arr[Mesh.ARRAY_VERTEX] = v
	var nb := xf.basis.inverse().transposed()
	if arr[Mesh.ARRAY_NORMAL] != null:
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL].duplicate()
		for i in n.size():
			n[i] = (nb * n[i]).normalized()
		arr[Mesh.ARRAY_NORMAL] = n
	var flip := xf.basis.determinant() < 0.0
	if arr[Mesh.ARRAY_TANGENT] != null:
		var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT].duplicate()
		for i in range(0, tg.size(), 4):
			var tv := (xf.basis * Vector3(tg[i], tg[i + 1], tg[i + 2])).normalized()
			tg[i] = tv.x
			tg[i + 1] = tv.y
			tg[i + 2] = tv.z
			if flip:
				tg[i + 3] = -tg[i + 3]
		arr[Mesh.ARRAY_TANGENT] = tg
	if flip and arr[Mesh.ARRAY_INDEX] != null:
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX].duplicate()
		for i in range(0, idx.size(), 3):
			var tmp := idx[i + 1]
			idx[i + 1] = idx[i + 2]
			idx[i + 2] = tmp
		arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Keep the triangles for which keep.call(a, b, c) is true and drop unused vertices.
func _filter(arr: Array, keep: Callable) -> Array:
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nidx := PackedInt32Array()
	for i in range(0, idx.size(), 3):
		if keep.call(idx[i], idx[i + 1], idx[i + 2]):
			nidx.append(idx[i])
			nidx.append(idx[i + 1])
			nidx.append(idx[i + 2])
	var nv: int = arr[Mesh.ARRAY_VERTEX].size()
	var remap := PackedInt32Array()
	remap.resize(nv)
	remap.fill(-1)
	var order := PackedInt32Array()
	for i in nidx.size():
		var o := nidx[i]
		if remap[o] < 0:
			remap[o] = order.size()
			order.append(o)
		nidx[i] = remap[o]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		if a == Mesh.ARRAY_INDEX or arr[a] == null:
			continue
		var src = arr[a]
		var per: int = src.size() / nv
		var dst = src.duplicate()
		dst.resize(order.size() * per)
		for j in order.size():
			for k in per:
				dst[j * per + k] = src[order[j] * per + k]
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = nidx
	return out


func _mesh(arr: Array, mat: Material, lods: bool) -> ArrayMesh:
	var im := ImporterMesh.new()
	var flags := 0
	if arr[Mesh.ARRAY_WEIGHTS] != null and arr[Mesh.ARRAY_WEIGHTS].size() == arr[Mesh.ARRAY_VERTEX].size() * 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mat, "", flags)
	if lods:
		im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


## A fresh material using the GLB's extracted textures (external files, so the .scn stays small
## and the runtime never touches the GLB).
func _material(path: String) -> StandardMaterial3D:
	var scn: Node = load(path).instantiate()
	var mi: MeshInstance3D = scn.find_children("*", "MeshInstance3D", true, false)[0]
	var m := mi.mesh.surface_get_material(0) as BaseMaterial3D
	var o := StandardMaterial3D.new()
	o.albedo_texture = m.albedo_texture
	o.albedo_color = m.albedo_color
	o.metallic = m.metallic
	o.roughness = m.roughness
	o.metallic_texture = m.metallic_texture
	o.metallic_texture_channel = m.metallic_texture_channel
	o.roughness_texture = m.roughness_texture
	o.roughness_texture_channel = m.roughness_texture_channel
	if m.normal_enabled:
		o.normal_enabled = true
		o.normal_texture = m.normal_texture
		o.normal_scale = m.normal_scale
	if m.ao_enabled:
		o.ao_enabled = true
		o.ao_texture = m.ao_texture
		o.ao_texture_channel = m.ao_texture_channel
	o.cull_mode = BaseMaterial3D.CULL_BACK
	scn.free()
	return o


func _attach(root: Node, name: String, bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.name = name
	a.bone_name = bone
	skel.add_child(a)
	a.owner = root
	a.transform = bone_rest_g[skel.find_bone(bone)]
	return a


## A rigid part whose arrays are in skeleton rest space, under a bone attachment.
func _add_part(att: BoneAttachment3D, root: Node, name: String, arr: Array, mat: Material, lods: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = _mesh(arr, mat, lods)
	att.add_child(mi)
	mi.owner = root
	mi.transform = att.transform.affine_inverse()
	return mi


# =========================================================================== body

func _cut_body(arr: Array, bind_bone: PackedInt32Array) -> Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := w.size() / v.size()
	var head_set := []
	for n in ["Head", "neck", "head_end", "headfront"]:
		head_set.append(skel.find_bone(n))
	var hand_l := skel.find_bone("LeftHand")
	var hand_r := skel.find_bone("RightHand")
	var wrist_l := bone_rest_g[hand_l].origin
	var wrist_r := bone_rest_g[hand_r].origin
	var fore_l := bone_rest_g[skel.find_bone("LeftForeArm")].origin
	var fore_r := bone_rest_g[skel.find_bone("RightForeArm")].origin
	var dl := (wrist_l - fore_l).normalized()
	var dr := (wrist_r - fore_r).normalized()
	var hidden := PackedByteArray()
	hidden.resize(v.size())
	var nh := 0
	for i in v.size():
		var wh := 0.0
		var whl := 0.0
		var whr := 0.0
		for k in per:
			var bb := bind_bone[bones[i * per + k]]
			if bb in head_set:
				wh += w[i * per + k]
			elif bb == hand_l:
				whl += w[i * per + k]
			elif bb == hand_r:
				whr += w[i * per + k]
		var p := v[i]
		var h := false
		if p.y > NECK_CUT and absf(p.x) < 0.16:
			h = true
		elif p.y > 1.28 and p.z < -0.125 and absf(p.x) < 0.13:
			h = true # the body's ponytail down its back (under the coat)
		elif wh > 0.5 and (p.y > NECK_CUT - 0.03 or p.z < -0.11):
			h = true # the body's own head and the ponytail down its back
		elif whl > 0.3 and (p - wrist_l).dot(dl) > -0.012:
			h = true
		elif whr > 0.3 and (p - wrist_r).dot(dr) > -0.012:
			h = true
		hidden[i] = 1 if h else 0
		nh += int(h)
	print("body: hiding %d of %d vertices" % [nh, v.size()])
	return _filter(arr, func(a, b, c): return hidden[a] == 0 and hidden[b] == 0 and hidden[c] == 0)


var body_w: Array[Dictionary] = [] # per body vertex: skeleton bone -> weight


func _index_body(arr: Array, bind_bone: PackedInt32Array) -> void:
	body_pts = arr[Mesh.ARRAY_VERTEX]
	body_nrm = arr[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := w.size() / body_pts.size()
	# the coat follows the forearm, not the fist; the collar follows the neck, not the head
	var remap := {}
	for pair in [["LeftHand", "LeftForeArm"], ["RightHand", "RightForeArm"], ["Head", "neck"], ["head_end", "neck"], ["headfront", "neck"]]:
		remap[skel.find_bone(pair[0])] = skel.find_bone(pair[1])
	for i in body_pts.size():
		var d := {}
		for k in per:
			var wt := w[i * per + k]
			if wt <= 0.0:
				continue
			var b := bind_bone[bones[i * per + k]]
			b = remap.get(b, b)
			d[b] = d.get(b, 0.0) + wt
		body_w.append(d)
	for i in body_pts.size():
		var key := Vector3i((body_pts[i] / CELL).floor())
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		grid[key].append(i)


## Nearest body vertex within ~1.5 cells, or -1.
func _nearest_body(p: Vector3) -> int:
	var c := Vector3i((p / CELL).floor())
	var best := -1
	var bd := INF
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				var key := c + Vector3i(x, y, z)
				if grid.has(key):
					for i in grid[key]:
						var d := p.distance_squared_to(body_pts[i])
						if d < bd:
							bd = d
							best = i
	return best


## Up to k nearest body vertices (searching outward up to ~20 cm): [[index, dist], ...].
func _knn_body(p: Vector3, k: int) -> Array:
	var c := Vector3i((p / CELL).floor())
	var found := []
	for ring in 5:
		found.clear()
		for x in range(-ring, ring + 1):
			for y in range(-ring, ring + 1):
				for z in range(-ring, ring + 1):
					var key := c + Vector3i(x, y, z)
					if grid.has(key):
						for i in grid[key]:
							found.append([i, p.distance_to(body_pts[i])])
		if found.size() >= k:
			break
	found.sort_custom(func(a, b): return a[1] < b[1])
	return found.slice(0, k)


## Skin weights sampled from the body under a coat point (inverse-distance blend of the
## nearest body vertices), then sharpened with a nearest-bone distance falloff over the same
## bones so the sleeves follow the arm bones cleanly.
func _upper_weights(p: Vector3) -> Dictionary:
	var nn := _knn_body(p, 8)
	var out := {}
	if nn.is_empty():
		return _bone_falloff(p, ["Hips", "Spine02", "Spine01", "Spine", "neck", "LeftShoulder", "RightShoulder"])
	var d0: float = nn[0][1]
	var tot := 0.0
	for e in nn:
		if e[1] > d0 + 0.03:
			continue
		var iw := 1.0 / pow(float(e[1]) + 0.01, 2.0)
		for b in body_w[e[0]]:
			out[b] = out.get(b, 0.0) + body_w[e[0]][b] * iw
		tot += iw
	var names := []
	for b in out:
		out[b] /= tot
		names.append(skel.get_bone_name(b))
	var fall := _bone_falloff(p, names)
	var res := {}
	for b in out:
		res[b] = out[b] * 0.8 + fall.get(b, 0.0) * 0.2
	return res


func _arm_share(w: Dictionary) -> float:
	var s := 0.0
	for b in w:
		var n := skel.get_bone_name(b)
		if n.ends_with("Arm") or n.ends_with("ForeArm") or n.ends_with("Hand"):
			s += w[b]
	return s


# =========================================================================== coat

var _coat_tails := PackedVector3Array()
var _chain_joints: Array = [] # [chain][k] skeleton-space joint positions (k = 0..links)


## Coat spring bones: 8 chains around the skirt, 4 links each, children of Hips.
## Joint positions are fitted to the coat surface later (_fit_chains); here they start on a cone.
func _add_coat_bones() -> void:
	var hips := skel.find_bone("Hips")
	for c in CHAIN_ANGLES.size():
		var parent := hips
		for k in CHAIN_LINKS:
			var b := skel.add_bone("Coat%d_%d" % [c, k])
			skel.set_bone_parent(b, parent)
			parent = b


func _set_chain_rests() -> void:
	var hips := skel.find_bone("Hips")
	var hips_g := skel.get_bone_global_rest(hips)
	_coat_tails = PackedVector3Array()
	for c in CHAIN_ANGLES.size():
		var j: Array = _chain_joints[c]
		for k in CHAIN_LINKS:
			var b := skel.find_bone("Coat%d_%d" % [c, k])
			if k == 0:
				# identity global basis: rest basis undoes the hips' rotation
				var r := Transform3D(hips_g.basis.inverse(), hips_g.affine_inverse() * (j[0] as Vector3))
				skel.set_bone_rest(b, r)
			else:
				skel.set_bone_rest(b, Transform3D(Basis(), (j[k] as Vector3) - (j[k - 1] as Vector3)))
		_coat_tails.append((j[CHAIN_LINKS] as Vector3) - (j[CHAIN_LINKS - 1] as Vector3))
	skel.reset_bone_poses()
	bone_rest_g.clear()
	for i in skel.get_bone_count():
		bone_rest_g.append(skel.get_bone_global_rest(i))


func _build_coat() -> Array:
	var raw := _load_arrays(D + "sol_mod_coat_src.glb", Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3.ZERO))
	var v: PackedVector3Array = raw[Mesh.ARRAY_VERTEX]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in v:
		lo = lo.min(p)
		hi = hi.max(p)
	# scale + place: collar top at COAT_TOP, centred on the body
	var off := Vector3(-(lo.x + hi.x) * 0.5 * COAT_SCALE.x, COAT_TOP - hi.y * COAT_SCALE.y, -(lo.z + hi.z) * 0.5 * COAT_SCALE.z + 0.005)
	var xf := Transform3D(Basis.from_scale(COAT_SCALE), off)
	var arr := _xform(raw, xf)
	v = arr[Mesh.ARRAY_VERTEX]
	# 1. lengthen the skirt toward mid-shin
	for i in v.size():
		if v[i].y < COAT_WAIST:
			v[i].y = COAT_WAIST - (COAT_WAIST - v[i].y) * COAT_SKIRT_STRETCH
	# 2. swing the sleeves onto the body's arms (the coat's sleeves hang a little steeper)
	var sleeve_t := PackedFloat32Array()
	sleeve_t.resize(v.size())
	var cn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for side: float in [1.0, -1.0]:
		var pre := "Left" if side > 0 else "Right"
		var sh_b := bone_rest_g[skel.find_bone(pre + "Arm")].origin
		var wr_b := bone_rest_g[skel.find_bone(pre + "Hand")].origin
		# the coat's own shoulder and cuff centre
		var cuff := Vector3.ZERO
		var n := 0
		var cuff_y := INF
		for p in v:
			if p.x * side > 0.31 and p.y < 1.35 and p.y > 0.8:
				cuff_y = minf(cuff_y, p.y)
		for p in v:
			if p.x * side > 0.31 and p.y < cuff_y + 0.05 and p.y > 0.8:
				cuff += p
				n += 1
		cuff /= maxf(n, 1)
		var sh_c := Vector3(sh_b.x * 0.92, sh_b.y + 0.005, sh_b.z)
		var a_dir := cuff - sh_c
		var b_dir := (wr_b + (wr_b - sh_b).normalized() * 0.02) - sh_b
		var a_len := a_dir.length()
		var ah := a_dir / a_len
		var q := Quaternion(ah, b_dir.normalized())
		var stretch := b_dir.length() / a_len
		print("coat sleeve %s: cuff %s, rotate %.1f deg, stretch %.3f" % [pre, cuff, rad_to_deg(q.get_angle()), stretch])
		for i in v.size():
			var p := v[i]
			if p.x * side < 0.1:
				continue
			var l := p - sh_c
			var along := l.dot(ah)
			var perp := l - ah * along
			var tt := along / a_len
			var r := perp.length()
			# sleeve: near the arm axis, below the shoulder. Where the sleeve brushes the coat's
			# side, the outward-facing side panel (inside the arm axis) stays with the torso.
			var outer := perp.x * side > 0.0
			var faces_in := cn[i].x * side < 0.15
			if tt > -0.05 and r < 0.09 and (outer or faces_in or tt < 0.15) and (tt > 0.12 or p.x * side > sh_b.x * side * 0.95):
				var wgt := smoothstep(0.0, 0.3, tt)
				var np: Vector3 = sh_b + q * (ah * along * stretch + perp) + (sh_c - sh_b) * (1.0 - wgt)
				v[i] = p.lerp(np, wgt) if wgt < 1.0 else np
				cn[i] = (Quaternion.IDENTITY.slerp(q, wgt) * cn[i]).normalized()
				sleeve_t[i] = clampf(tt, 0.0, 1.0) * side
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = cn
	# 3. keep it outside the body at rest
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var pushed := 0
	for i in v.size():
		var bi := _nearest_body(v[i])
		if bi < 0:
			continue
		var bn := body_nrm[bi]
		var dd := (v[i] - body_pts[bi]).dot(bn)
		if dd < COAT_MARGIN and (v[i] - body_pts[bi]).length() < 0.06:
			v[i] += bn * (COAT_MARGIN - dd)
			pushed += 1
	arr[Mesh.ARRAY_VERTEX] = v
	print("coat: pushed %d of %d vertices outside the body" % [pushed, v.size()])
	# 4. spring chains on the skirt surface
	_fit_chains(v)
	_set_chain_rests()
	# 5. skin weights
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(v.size() * 4)
	weights.resize(v.size() * 4)
	var wds: Array[Dictionary] = []
	for i in v.size():
		wds.append(_coat_weights(v[i], sleeve_t[i]))
	wds = _smooth_weights(wds, arr[Mesh.ARRAY_INDEX], 2)
	for i in v.size():
		var wd := wds[i]
		var keys: Array = wd.keys()
		keys.sort_custom(func(x, y): return wd[x] > wd[y])
		var tot := 0.0
		for k in mini(4, keys.size()):
			tot += wd[keys[k]]
		for k in 4:
			if k < keys.size():
				bones[i * 4 + k] = keys[k]
				weights[i * 4 + k] = wd[keys[k]] / tot
			else:
				bones[i * 4 + k] = 0
				weights[i * 4 + k] = 0.0
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	var skin := Skin.new()
	for b in skel.get_bone_count():
		skin.add_named_bind(skel.get_bone_name(b), bone_rest_g[b].affine_inverse())
	return [_mesh(arr, _material(D + "sol_mod_coat_src.glb"), true), skin]


## Average each vertex's weights with its mesh neighbours (removes stair-steps between
## body-sampled regions).
func _smooth_weights(wds: Array[Dictionary], idx: PackedInt32Array, iters: int) -> Array[Dictionary]:
	var nb: Array[PackedInt32Array] = []
	nb.resize(wds.size())
	for i in range(0, idx.size(), 3):
		for e in 3:
			var a := idx[i + e]
			var b := idx[i + (e + 1) % 3]
			nb[a].append(b)
			nb[b].append(a)
	for it in iters:
		var nw: Array[Dictionary] = []
		for i in wds.size():
			var d := {}
			for b in wds[i]:
				d[b] = wds[i][b] * 2.0
			var tot := 2.0
			for j in nb[i]:
				for b in wds[j]:
					d[b] = d.get(b, 0.0) + wds[j][b]
				tot += 1.0
			for b in d:
				d[b] /= tot
			nw.append(d)
		wds = nw
	return wds


## Place each chain's joints on the outside of the skirt at its angle.
func _fit_chains(v: PackedVector3Array) -> void:
	var hips := bone_rest_g[skel.find_bone("Hips")].origin
	var centre := Vector2(0.0, hips.z + 0.04)
	var lo_y := INF
	for p in v:
		lo_y = minf(lo_y, p.y)
	var hem := lo_y + 0.02
	_chain_joints.clear()
	for c in CHAIN_ANGLES.size():
		var th := deg_to_rad(CHAIN_ANGLES[c])
		var j := []
		for k in CHAIN_LINKS + 1:
			var y := lerpf(CHAIN_TOP, hem, float(k) / CHAIN_LINKS)
			var best := 0.0
			for p in v:
				if absf(p.y - y) > 0.03:
					continue
				var dx := p.x - centre.x
				var dz := p.z - centre.y
				var a := atan2(dx, dz)
				if absf(angle_difference(a, th)) < deg_to_rad(9.0):
					best = maxf(best, sqrt(dx * dx + dz * dz))
			if best <= 0.0:
				best = 0.2 + 0.1 * float(k) / CHAIN_LINKS
			j.append(Vector3(centre.x + sin(th) * best, y, centre.y + cos(th) * best))
		_chain_joints.append(j)


## Upper coat: nearest-bone weights with a smooth falloff (sleeves only see their arm chain);
## skirt: blended between the two nearest spring chains and their two nearest links.
func _coat_weights(p: Vector3, sleeve: float) -> Dictionary:
	var out := {}
	var b_skirt := 1.0 - smoothstep(CHAIN_TOP - 0.03, CHAIN_TOP + 0.09, p.y)
	var upper := {}
	if b_skirt < 1.0 or p.y < CHAIN_TOP + 0.2:
		upper = _upper_weights(p)
	if sleeve != 0.0 or _arm_share(upper) > 0.4 or absf(p.x) > 0.34:
		b_skirt = 0.0 # cuffs and sleeves never ride the skirt chains
	if b_skirt < 1.0:
		for k in upper:
			out[k] = out.get(k, 0.0) + upper[k] * (1.0 - b_skirt)
	if b_skirt > 0.0:
		var hips := bone_rest_g[skel.find_bone("Hips")].origin
		var a := atan2(p.x, p.z - (hips.z + 0.04))
		var n := CHAIN_ANGLES.size()
		var c0 := n - 1
		var c1 := 0
		var u := 0.0
		for c in n:
			var a0 := deg_to_rad(CHAIN_ANGLES[c])
			var a1 := deg_to_rad(CHAIN_ANGLES[(c + 1) % n])
			var span := fposmod(a1 - a0, TAU)
			var rel := fposmod(a - a0, TAU)
			if rel <= span:
				c0 = c
				c1 = (c + 1) % n
				u = rel / span
				break
		# the open front: don't bridge the two front panels
		if c0 == 3 and c1 == 4:
			u = 0.0 if u < 0.5 else 1.0
		u = smoothstep(0.0, 1.0, u)
		var seg := (CHAIN_TOP - float(_chain_joints[0][CHAIN_LINKS].y)) / CHAIN_LINKS
		var f := clampf((CHAIN_TOP - p.y) / seg - 0.5, 0.0, CHAIN_LINKS - 1.0)
		var k0 := int(floor(f))
		var k1 := mini(k0 + 1, CHAIN_LINKS - 1)
		var tt := f - k0
		var pairs := [[c0, k0, (1.0 - u) * (1.0 - tt)], [c0, k1, (1.0 - u) * tt], [c1, k0, u * (1.0 - tt)], [c1, k1, u * tt]]
		for pr in pairs:
			var b := skel.find_bone("Coat%d_%d" % [pr[0], pr[1]])
			out[b] = out.get(b, 0.0) + float(pr[2]) * b_skirt
	return out


## Inverse-distance weights to bone segments (bone -> its first child), smoothed.
func _bone_falloff(p: Vector3, names: Array) -> Dictionary:
	var d := {}
	var best := INF
	for nm in names:
		var b := skel.find_bone(nm)
		var a := bone_rest_g[b].origin
		var e := a
		for cb in skel.get_bone_children(b):
			if not skel.get_bone_name(cb).begins_with("Coat"):
				e = bone_rest_g[cb].origin
				break
		var ab := e - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var dist := p.distance_to(a + ab * t)
		d[b] = dist
		best = minf(best, dist)
	var out := {}
	var tot := 0.0
	for b in d:
		# falloff relative to the nearest bone: anything 6 cm farther than it gets nothing
		var rel: float = d[b] - best
		var w := pow(1.0 - smoothstep(0.0, 0.06, rel), 2.0) / pow(d[b] + 0.03, 2.0)
		if w > 1e-4:
			out[b] = w
			tot += w
	for b in out:
		out[b] /= tot
	return out


# =========================================================================== head

## Remove the bust's shoulders and white T-shirt (bright, unsaturated texels low on the bust).
func _cut_bust(arr: Array, path: String) -> Array:
	var mat := _material(path)
	var img: Image = mat.albedo_texture.get_image()
	if img.is_compressed():
		img.decompress()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var cut_y := HEAD_OFF.y + HEAD_CUT * HEAD_SCALE
	var shirt_y := HEAD_OFF.y + (-0.2) * HEAD_SCALE
	var drop := PackedByteArray()
	drop.resize(v.size())
	var w := img.get_width()
	var h := img.get_height()
	var nd := 0
	for i in v.size():
		var d := v[i].y < cut_y
		if not d and v[i].y < shirt_y:
			var c := img.get_pixel(clampi(int(uv[i].x * w), 0, w - 1), clampi(int(uv[i].y * h), 0, h - 1))
			if c.v > 0.55 and c.s < 0.22:
				d = true
		drop[i] = 1 if d else 0
		nd += int(d)
	print("head: dropping %d of %d vertices" % [nd, v.size()])
	return _filter(arr, func(a, b, c): return drop[a] == 0 and drop[b] == 0 and drop[c] == 0)


## Small round sunglasses: two thin rims, dark glossy lenses, a bridge and temple arms.
func _add_glasses(att: BoneAttachment3D, root: Node) -> void:
	var g := Node3D.new()
	g.name = "Glasses"
	att.add_child(g)
	g.owner = root
	var eye := Vector3(0.0, 1.741, 0.104) # between the eyes, just in front of the brow line
	g.transform = att.transform.affine_inverse() * Transform3D(Basis(), eye)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.09, 0.085, 0.08)
	frame.metallic = 1.0
	frame.roughness = 0.3
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.03, 0.025, 0.03)
	lens.metallic = 0.8
	lens.roughness = 0.08
	var r := 0.0175
	var dx := 0.0315
	for s in [-1.0, 1.0]:
		var rim := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r
		tm.outer_radius = r + 0.0028
		tm.rings = 24
		tm.ring_segments = 6
		rim.mesh = tm
		rim.material_override = frame
		rim.rotation = Vector3(PI / 2.0, 0, 0)
		rim.position = Vector3(dx * s, 0, 0)
		g.add_child(rim)
		rim.owner = root
		var ln := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r + 0.0005
		cm.bottom_radius = r + 0.0005
		cm.height = 0.002
		cm.radial_segments = 24
		cm.rings = 1
		ln.mesh = cm
		ln.material_override = lens
		ln.rotation = Vector3(PI / 2.0, 0, 0)
		ln.position = Vector3(dx * s, 0, 0.0)
		g.add_child(ln)
		ln.owner = root
		# temple arm back to the ear
		var arm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.0022, 0.0028, 0.1)
		arm.mesh = bm
		arm.material_override = frame
		arm.position = Vector3((dx + r + 0.003) * s, 0.002, -0.05)
		arm.rotation = Vector3(0, -0.07 * s, 0)
		g.add_child(arm)
		arm.owner = root
	var bridge := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(dx * 2.0 - r * 2.0 + 0.004, 0.0024, 0.0024)
	bridge.mesh = bb
	bridge.material_override = frame
	bridge.position = Vector3(0, 0.006, 0.002)
	g.add_child(bridge)
	bridge.owner = root


# =========================================================================== hands

## Skeleton-space transform of the right fist: wrist on the wrist joint, knuckles along the
## hand, palm toward the body, thumb forward (fitted to the body's own hand by PCA).
func _fist_xf(side: String) -> Transform3D:
	var hand := skel.find_bone(side + "Hand")
	var fore := skel.find_bone(side + "ForeArm")
	var wrist := bone_rest_g[hand].origin
	var d := (wrist - bone_rest_g[fore].origin).normalized()
	# palm faces the thigh: roughly +X for the right hand, then orthogonal to the arm
	var sgn := 1.0 if side == "Right" else -1.0
	var n := Vector3(sgn, 0, 0.15)
	n = (n - d * n.dot(d)).normalized()
	var z := n.cross(d)
	if side == "Left":
		z = -z # the left fist is the right one mirrored (thumb still forward)
	# fist mesh axes: +X palm/fingers, +Y wrist->knuckles, -Z thumb
	var b := Basis(n * HAND_SCALE, d * HAND_SCALE, z * HAND_SCALE)
	return Transform3D(b, wrist - b * HAND_WRIST)


# =========================================================================== swords

## Bake a sword into grip space: origin at the middle of the grip, blade along +Z, blade width
## along Y (flat faces +-X), overall length `length`. Axis and ends are found automatically:
## the longest principal axis is the blade, the widest cross-section is the guard, and the end
## nearer the guard is the pommel.
func _build_sword(sname: String, path: String, length: float) -> void:
	var arr := _load_arrays(path, Transform3D.IDENTITY)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c := Vector3.ZERO
	for p in v:
		c += p
	c /= v.size()
	var axis := _principal(v, c, Vector3.ZERO)
	var smin := INF
	var smax := -INF
	for p in v:
		var s := (p - c).dot(axis)
		smin = minf(smin, s)
		smax = maxf(smax, s)
	var bins := 48
	var ext := PackedFloat32Array()
	ext.resize(bins)
	for p in v:
		var s := (p - c).dot(axis)
		var bi := clampi(int((s - smin) / (smax - smin) * bins), 0, bins - 1)
		var r := ((p - c) - axis * s).length()
		ext[bi] = maxf(ext[bi], r)
	var gb := 0
	for i in bins:
		if ext[i] > ext[gb]:
			gb = i
	var guard_s := smin + (gb + 0.5) / bins * (smax - smin)
	var pommel_s := smin if (guard_s - smin) < (smax - guard_s) else smax
	var blade_dir := axis if pommel_s == smin else -axis
	var grip_s := lerpf(guard_s, pommel_s, 0.42)
	var grip := c + axis * grip_s
	# blade width: principal axis of the blade's cross-section
	var blade_pts := PackedVector3Array()
	for p in v:
		var s := (p - c).dot(blade_dir) - (guard_s if blade_dir == axis else -guard_s)
		if s > 0.15 * (smax - smin):
			blade_pts.append(p)
	var bc := Vector3.ZERO
	for p in blade_pts:
		bc += p
	bc /= maxf(blade_pts.size(), 1)
	var wdir := _principal(blade_pts, bc, blade_dir)
	var xdir := wdir.cross(blade_dir).normalized()
	wdir = blade_dir.cross(xdir).normalized()
	var scale := length / (smax - smin)
	var basis_in := Basis(xdir, wdir, blade_dir) # columns: where sword X/Y/Z point in mesh space
	var to_grip := Transform3D(basis_in.transposed().scaled(Vector3.ONE * scale), Vector3.ZERO)
	to_grip.origin = -(to_grip.basis * grip)
	arr = _xform(arr, to_grip)
	var mat := _material(path)
	var root := Node3D.new()
	root.name = "Sword_" + sname
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _mesh(arr, mat, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	mi.owner = root
	var tip := absf((smax if pommel_s == smin else smin) - grip_s) * scale
	root.set_meta("blade_len", tip)
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, D + "sol_sword_%s.scn" % sname, ResourceSaver.FLAG_COMPRESS)
	print("sword %s: guard bin %d/%d, grip->tip %.2f m, scale %.3f (%s)" % [sname, gb, bins, tip, scale, error_string(err)])
	root.free()


## Dominant direction of a point cloud (power iteration on the covariance), optionally with
## `exclude` projected out first.
func _principal(pts: PackedVector3Array, c: Vector3, exclude: Vector3) -> Vector3:
	var xx := 0.0; var xy := 0.0; var xz := 0.0; var yy := 0.0; var yz := 0.0; var zz := 0.0
	for p in pts:
		var d := p - c
		if exclude != Vector3.ZERO:
			d -= exclude * d.dot(exclude)
		xx += d.x * d.x; xy += d.x * d.y; xz += d.x * d.z
		yy += d.y * d.y; yz += d.y * d.z; zz += d.z * d.z
	var m := Basis(Vector3(xx, xy, xz), Vector3(xy, yy, yz), Vector3(xz, yz, zz))
	var e := Vector3(0.57, 0.58, 0.59)
	if exclude != Vector3.ZERO:
		e -= exclude * e.dot(exclude)
	for i in 64:
		e = (m * e)
		if exclude != Vector3.ZERO:
			e -= exclude * e.dot(exclude)
		e = e.normalized()
	return e


# =========================================================================== boots

func _add_boots(root: Node) -> void:
	var mat := _material(D + "sol_mod_boot_src.glb")
	for side in ["Left", "Right"]:
		var foot := skel.find_bone(side + "Foot")
		var toe := skel.find_bone(side + "ToeBase")
		var fp := bone_rest_g[foot].origin
		var tp := bone_rest_g[toe].origin
		var fwd := Vector3(tp.x - fp.x, 0, tp.z - fp.z).normalized()
		var bas := Basis(Vector3.UP.cross(fwd).normalized() * -1.0, Vector3.UP, fwd)
		var xf := Transform3D(bas.scaled(Vector3.ONE * 0.3), Vector3(fp.x, 0.15, fp.z + 0.04))
		if side == "Right":
			xf = Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO) * Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO) * xf
		var att := _attach(root, "Foot." + side.substr(0, 1), side + "Foot")
		_add_part(att, root, "BootMesh", _load_arrays(D + "sol_mod_boot_src.glb", xf), mat, false)


# =========================================================================== clips

func _build_clips(unit: float) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for cname in CLIPS:
		var scn: Node = load(CLIPS[cname]).instantiate()
		var ap: AnimationPlayer = scn.find_children("*", "AnimationPlayer", true, false)[0]
		var A: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		scn.free()
		for t in A.get_track_count():
			var path := String(A.track_get_path(t))
			var bone := path.get_slice(":", 1)
			A.track_set_path(t, NodePath("Skeleton3D:" + bone))
			if A.track_get_type(t) == Animation.TYPE_POSITION_3D:
				for k in A.track_get_key_count(t):
					A.track_set_key_value(t, k, A.track_get_key_value(t, k) * unit)
		_strip_root_motion(A, cname)
		match cname:
			"slash":
				var win := _slash_window(A)
				A = _trim(A, win.x, win.y)
				lib.add_animation("slash_back", _reverse(A))
			"hit":
				A = _trim(A, 0.0, minf(A.length, 0.8))
			"jump":
				A = _trim(A, 0.42, minf(A.length, 0.92))
		A.loop_mode = Animation.LOOP_LINEAR if cname in LOOPED else Animation.LOOP_NONE
		lib.add_animation(cname, A)
		print("clip %s: %.2f s, %d tracks" % [cname, A.length, A.get_track_count()])
	return lib


func _strip_root_motion(A: Animation, cname: String) -> void:
	var t := A.find_track(NodePath("Skeleton3D:Hips"), Animation.TYPE_POSITION_3D)
	if t < 0:
		return
	var n := A.track_get_key_count(t)
	var first: Vector3 = A.track_get_key_value(t, 0)
	var last: Vector3 = A.track_get_key_value(t, n - 1)
	var drift := Vector3(last.x - first.x, 0, last.z - first.z)
	for k in n:
		var v: Vector3 = A.track_get_key_value(t, k)
		var f := A.track_get_key_time(t, k) / maxf(A.length, 1e-3)
		if cname in LOOPED:
			v -= drift * f # in-place loop, keeps the sway
		else:
			var d := Vector2(v.x - first.x, v.z - first.z)
			if d.length() > 0.12:
				d = d.normalized() * 0.12
			v.x = first.x + d.x
			v.z = first.z + d.y
		if cname == "jump":
			v.y = minf(v.y, first.y) # the character body does the rising, not the hips
		A.track_set_key_value(t, k, v)


## The fastest stretch of the right hand: wind-up end to follow-through.
func _slash_window(A: Animation) -> Vector2:
	var hand := skel.find_bone("RightHand")
	var best_t := 0.0
	var best_v := 0.0
	var prev := _bone_pos_at(A, hand, 0.0)
	var step := 1.0 / 30.0
	var tt := step
	while tt <= A.length:
		var p := _bone_pos_at(A, hand, tt)
		var sp := p.distance_to(prev) / step
		if sp > best_v:
			best_v = sp
			best_t = tt
		prev = p
		tt += step
	var w := Vector2(maxf(best_t - 0.32, 0.0), minf(best_t + 0.36, A.length))
	print("slash: peak hand speed %.1f m/s at %.2f s -> window %s" % [best_v, best_t, w])
	return w


func _bone_pos_at(A: Animation, bone: int, t: float) -> Vector3:
	var xf := Transform3D.IDENTITY
	var b := bone
	while b >= 0:
		var rest := skel.get_bone_rest(b)
		var pos := rest.origin
		var rot := rest.basis.get_rotation_quaternion()
		var bn := skel.get_bone_name(b)
		var tp := A.find_track(NodePath("Skeleton3D:" + bn), Animation.TYPE_POSITION_3D)
		var tr := A.find_track(NodePath("Skeleton3D:" + bn), Animation.TYPE_ROTATION_3D)
		if tp >= 0:
			pos = A.position_track_interpolate(tp, t)
		if tr >= 0:
			rot = A.rotation_track_interpolate(tr, t)
		xf = Transform3D(Basis(rot), pos) * xf
		b = skel.get_bone_parent(b)
	return xf.origin


func _trim(A: Animation, t0: float, t1: float) -> Animation:
	var B := Animation.new()
	B.length = t1 - t0
	for t in A.get_track_count():
		var ty := A.track_get_type(t)
		var nt := B.add_track(ty)
		B.track_set_path(nt, A.track_get_path(t))
		B.track_set_interpolation_type(nt, A.track_get_interpolation_type(t))
		var times := [t0]
		for k in A.track_get_key_count(t):
			var kt := A.track_get_key_time(t, k)
			if kt > t0 + 1e-4 and kt < t1 - 1e-4:
				times.append(kt)
		times.append(t1)
		for kt in times:
			var val
			match ty:
				Animation.TYPE_POSITION_3D:
					val = A.position_track_interpolate(t, kt)
				Animation.TYPE_ROTATION_3D:
					val = A.rotation_track_interpolate(t, kt)
				Animation.TYPE_SCALE_3D:
					val = A.scale_track_interpolate(t, kt)
				_:
					continue
			B.track_insert_key(nt, kt - t0, val)
	return B


func _reverse(A: Animation) -> Animation:
	var B := Animation.new()
	B.length = A.length
	for t in A.get_track_count():
		var nt := B.add_track(A.track_get_type(t))
		B.track_set_path(nt, A.track_get_path(t))
		for k in A.track_get_key_count(t):
			B.track_insert_key(nt, A.length - A.track_get_key_time(t, k), A.track_get_key_value(t, k))
	return B
