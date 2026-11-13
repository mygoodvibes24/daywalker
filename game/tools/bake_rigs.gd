extends SceneTree
## Offline tool: re-skins the generated character meshes onto a game skeleton.
##   godot --headless -s res://tools/bake_rigs.gd
## The source GLBs face +X with T-pose arms along Z, and the auto-rig that came
## with them does not line up with the mesh (its run clip tears the mesh apart), so
## its skeleton and clip are not used.
## This keeps the textured mesh, turns it to face +Z, measures the body, builds a
## simple 19-bone skeleton, computes distance-based skin weights and LODs, and saves
## res://assets/characters/<name>/<name>_rig.scn for enemy.gd to animate procedurally.

const CHARS := {
	"vampire": {"eye_drop": 0.081, "eye_dx": 0.017, "eye_r": 0.0095},
	"werewolf": {"eye_drop": 0.099, "eye_dx": 0.033, "eye_r": 0.016},
	"civilian": {"eye_drop": 0.08, "eye_dx": 0.017, "eye_r": 0.011},
}

# name, parent
const BONES := [
	["hips", ""], ["spine", "hips"], ["chest", "spine"], ["neck", "chest"], ["head", "neck"],
	["clav_l", "chest"], ["upper_l", "clav_l"], ["fore_l", "upper_l"], ["hand_l", "fore_l"],
	["clav_r", "chest"], ["upper_r", "clav_r"], ["fore_r", "upper_r"], ["hand_r", "fore_r"],
	["thigh_l", "hips"], ["shin_l", "thigh_l"], ["foot_l", "shin_l"],
	["thigh_r", "hips"], ["shin_r", "thigh_r"], ["foot_r", "shin_r"],
]


func _initialize() -> void:
	var only := OS.get_environment("BAKE_ONLY")
	for n in CHARS:
		if only != "" and only != n:
			continue
		_bake(n, CHARS[n])
	quit()


func _bake(n: String, cfg: Dictionary) -> void:
	var src: Node = load("res://assets/characters/%s/%s.glb" % [n, n]).instantiate()
	var mi: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: ArrayMesh = mi.mesh
	var arrays := mesh.surface_get_arrays(0)
	var mat: Material = mi.get_active_material(0).duplicate() # embedded copy; textures stay external
	# mesh space (+X forward) -> +Z forward
	var rot := Basis(Vector3.UP, -PI / 2.0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tans: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	for i in verts.size():
		verts[i] = rot * verts[i]
		norms[i] = rot * norms[i]
	for i in range(0, tans.size(), 4):
		var t := rot * Vector3(tans[i], tans[i + 1], tans[i + 2])
		tans[i] = t.x; tans[i + 1] = t.y; tans[i + 2] = t.z
	var miny := INF
	for v in verts:
		miny = minf(miny, v.y)
	var H := -INF
	for v in verts:
		H = maxf(H, v.y - miny)
	# centre the feet on the origin
	var feet := _centroid(verts, func(v): return v.y - miny < 0.08 * H)
	for i in verts.size():
		verts[i] -= Vector3(feet.x, miny, feet.z)

	var J := _measure(verts, H)
	var eye := _eyes(verts, H, J, cfg)
	print(n, " H=", H, " joints=", J)
	print(n, " eyes=", eye)

	# skeleton
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	var joint := {
		"hips": J.hips, "spine": J.spine, "chest": J.chest, "neck": J.neck, "head": J.head,
		"clav_l": J.clav_l, "upper_l": J.sh_l, "fore_l": J.el_l, "hand_l": J.wr_l,
		"clav_r": J.clav_r, "upper_r": J.sh_r, "fore_r": J.el_r, "hand_r": J.wr_r,
		"thigh_l": J.hip_l, "shin_l": J.kn_l, "foot_l": J.an_l,
		"thigh_r": J.hip_r, "shin_r": J.kn_r, "foot_r": J.an_r,
	}
	var tip := {
		"hips": J.spine, "spine": J.chest, "chest": J.neck, "neck": J.head, "head": J.top,
		"clav_l": J.sh_l, "upper_l": J.el_l, "fore_l": J.wr_l, "hand_l": J.ft_l,
		"clav_r": J.sh_r, "upper_r": J.el_r, "fore_r": J.wr_r, "hand_r": J.ft_r,
		"thigh_l": J.kn_l, "shin_l": J.an_l, "foot_l": J.toe_l,
		"thigh_r": J.kn_r, "shin_r": J.an_r, "foot_r": J.toe_r,
	}
	var seg_a: Array[Vector3] = []
	var seg_b: Array[Vector3] = []
	for b in BONES:
		var idx := sk.add_bone(b[0])
		var par: int = -1 if b[1] == "" else sk.find_bone(b[1])
		sk.set_bone_parent(idx, par)
		var origin: Vector3 = joint[b[0]] - (Vector3.ZERO if par < 0 else joint[b[1]])
		sk.set_bone_rest(idx, Transform3D(Basis(), origin))
		seg_a.append(joint[b[0]])
		seg_b.append(tip[b[0]])
	seg_a[0] = Vector3(0, J.hip_l.y - 0.04 * H, J.hips.z) # pelvis reaches down to the crotch
	sk.reset_bone_poses()
	var skin := Skin.new()
	for i in sk.get_bone_count():
		skin.add_named_bind(sk.get_bone_name(i), Transform3D(Basis(), -joint[sk.get_bone_name(i)]))

	# weights
	var side := [0, 0, 0, 0, 0, 1, 1, 1, 1, -1, -1, -1, -1, 1, 1, 1, -1, -1, -1]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(verts.size() * 4)
	weights.resize(verts.size() * 4)
	var nb := BONES.size()
	var d := PackedFloat32Array()
	d.resize(nb)
	var arm_root: float = J.sh_l.x
	var legtop: float = J.hip_l.y
	for vi in verts.size():
		var v := verts[vi]
		for bi in nb:
			var s: int = side[bi]
			if s != 0 and v.x * s < -0.015 * H:
				d[bi] = INF
				continue
			var dist := _seg_dist(v, seg_a[bi], seg_b[bi])
			if bi in [6, 10] and absf(v.x) < arm_root: # torso skin should not follow the arms
				dist *= 1.0 + 6.0 * (arm_root - absf(v.x)) / arm_root
			if bi in [13, 16] and v.y > legtop:
				dist *= 1.0 + 8.0 * (v.y - legtop) / H
			if bi in [5, 9]:
				dist *= 1.6 # collarbones barely own any skin
			d[bi] = dist
		# top 4 by distance
		var best := [-1, -1, -1, -1]
		var bestd := [INF, INF, INF, INF]
		for bi in nb:
			var dd := d[bi]
			if dd < bestd[3]:
				var k := 3
				while k > 0 and dd < bestd[k - 1]:
					bestd[k] = bestd[k - 1]; best[k] = best[k - 1]
					k -= 1
				bestd[k] = dd; best[k] = bi
		var wsum := 0.0
		var w := [0.0, 0.0, 0.0, 0.0]
		for k in 4:
			if best[k] >= 0:
				w[k] = 1.0 / pow(bestd[k] + 0.01, 5.0)
				wsum += w[k]
		for k in 4:
			bones[vi * 4 + k] = maxi(best[k], 0)
			weights[vi * 4 + k] = w[k] / wsum if wsum > 0.0 else (1.0 if k == 0 else 0.0)

	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	if tans.size() > 0:
		out[Mesh.ARRAY_TANGENT] = tans
	out[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]
	out[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, mat, "body")
	im.generate_lods(60.0, 25.0, [])
	var new_mesh := im.get_mesh()
	new_mesh.resource_name = n

	var root := Node3D.new()
	root.name = n.capitalize()
	root.add_child(sk)
	sk.owner = root
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = new_mesh
	body.skin = skin
	sk.add_child(body)
	body.owner = root
	body.skeleton = NodePath("..")
	root.set_meta("height", H)
	root.set_meta("eye_l", eye[0])
	root.set_meta("eye_r", eye[1])
	root.set_meta("eye_radius", cfg.eye_r)
	root.set_meta("head_rest", J.head)
	var ps := PackedScene.new()
	ps.pack(root)
	var path := "res://assets/characters/%s/%s_rig.scn" % [n, n]
	var err := ResourceSaver.save(ps, path, ResourceSaver.FLAG_COMPRESS)
	print(n, " saved ", path, " err=", err, " lods=", new_mesh.surface_get_format(0))
	root.free()
	src.free()


func _centroid(verts: PackedVector3Array, pred: Callable) -> Vector3:
	var s := Vector3.ZERO
	var c := 0
	for v in verts:
		if pred.call(v):
			s += v
			c += 1
	return s / maxf(c, 1)


func _percentile(vals: Array, p: float) -> float:
	if vals.is_empty():
		return 0.0
	vals.sort()
	return vals[clampi(int(p * (vals.size() - 1)), 0, vals.size() - 1)]


func _measure(verts: PackedVector3Array, H: float) -> Dictionary:
	var J := {}
	var span_l := 0.0
	var span_r := 0.0
	for v in verts:
		span_l = maxf(span_l, v.x)
		span_r = maxf(span_r, -v.x)
	var arm_l := _centroid(verts, func(v): return v.x > 0.55 * span_l and v.x < 0.8 * span_l)
	var arm_r := _centroid(verts, func(v): return -v.x > 0.55 * span_r and -v.x < 0.8 * span_r)
	var ys := (arm_l.y + arm_r.y) * 0.5
	var below := []
	for v in verts:
		if v.y > ys - 0.13 * H and v.y < ys - 0.09 * H:
			below.append(absf(v.x))
	var tw := _percentile(below, 0.93)
	var chest_c := _centroid(verts, func(v): return v.y > ys - 0.14 * H and v.y < ys - 0.06 * H and absf(v.x) < tw)
	var belly_c := _centroid(verts, func(v): return v.y > 0.5 * H and v.y < 0.58 * H and absf(v.x) < tw)
	var head_c := _centroid(verts, func(v): return v.y > ys + 0.07 * H and absf(v.x) < tw)
	var top := -INF
	for v in verts:
		if absf(v.x) < tw:
			top = maxf(top, v.y)
	J.hips = Vector3(0, 0.53 * H, belly_c.z)
	J.spine = Vector3(0, 0.62 * H, lerpf(belly_c.z, chest_c.z, 0.4))
	J.chest = Vector3(0, ys - 0.1 * H, chest_c.z)
	J.neck = Vector3(0, ys + 0.015 * H, lerpf(chest_c.z, head_c.z, 0.5))
	J.head = Vector3(0, ys + 0.055 * H, head_c.z)
	J.top = Vector3(0, top, head_c.z)
	J.head_x = head_c.x
	for s in [1.0, -1.0]:
		var k := "l" if s > 0 else "r"
		var span: float = span_l if s > 0 else span_r
		var arm: Vector3 = arm_l if s > 0 else arm_r
		var sh_x: float = tw * 0.9
		var wr_x: float = span - 0.1 * H
		J["clav_" + k] = Vector3(s * 0.035 * H, ys, chest_c.z)
		J["sh_" + k] = Vector3(s * sh_x, arm.y, arm.z)
		J["el_" + k] = Vector3(s * lerpf(sh_x, wr_x, 0.5), arm.y, arm.z)
		J["wr_" + k] = Vector3(s * wr_x, arm.y, arm.z)
		J["ft_" + k] = Vector3(s * span, arm.y, arm.z)
		var ank := _centroid(verts, func(v): return v.y < 0.1 * H and v.y > 0.03 * H and v.x * s > 0.0)
		var knee := _centroid(verts, func(v): return v.y > 0.25 * H and v.y < 0.31 * H and v.x * s > 0.0 and absf(v.x) < tw)
		var toe_z := -INF
		for v in verts:
			if v.y < 0.05 * H and v.x * s > 0.0:
				toe_z = maxf(toe_z, v.z)
		J["hip_" + k] = Vector3(s * maxf(absf(ank.x) * 0.85, 0.045 * H), 0.5 * H, belly_c.z)
		J["kn_" + k] = Vector3(knee.x, 0.28 * H, knee.z)
		J["an_" + k] = Vector3(ank.x, 0.065 * H, ank.z - 0.02 * H)
		J["toe_" + k] = Vector3(ank.x, 0.02 * H, toe_z - 0.02 * H)
	return J


func _eyes(verts: PackedVector3Array, H: float, J: Dictionary, cfg: Dictionary) -> Array:
	var ey: float = J.top.y - cfg.eye_drop * H
	var out := []
	for s in [1.0, -1.0]:
		var ex: float = J.head_x + s * cfg.eye_dx * H
		var best := -INF
		for v in verts:
			if absf(v.x - ex) < 0.01 and absf(v.y - ey) < 0.01:
				best = maxf(best, v.z)
		out.append(Vector3(ex, ey, best - cfg.eye_r * 0.55))
	return out


func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)
