extends SceneTree
## Offline rig builder for Sol's generated mesh.
## Run from game/:  godot --headless -s res://tools/build_sol_rig.gd
##
## The source GLB is an unrigged, textured T-pose mesh (PBR maps intact) that
## faces +X and is 1 unit tall. This script bakes it into meters (1.88 m, feet at
## y=0, facing +Z like the player's `visual`), builds a 20-bone humanoid skeleton
## (plus three coat-panel bones for flare) with identity rest bases, computes
## smooth region-based skin weights, and saves res://assets/characters/sol/sol.scn.

const SRC := "res://assets/characters/sol/sol_unrigged.glb"
const OUT := "res://assets/characters/sol/sol.scn"
const HEIGHT := 1.88

# name, parent, joint position (meters, +Z forward, character's left = +X)
const BONES := [
	["Hips", "", Vector3(0, 0.98, -0.03)],
	["Spine", "Hips", Vector3(0, 1.14, -0.03)],
	["Chest", "Spine", Vector3(0, 1.32, -0.04)],
	["Neck", "Chest", Vector3(0, 1.58, -0.02)],
	["Head", "Neck", Vector3(0, 1.66, 0.0)],
	["UpperArm.L", "Chest", Vector3(0.19, 1.47, -0.06)],
	["ForeArm.L", "UpperArm.L", Vector3(0.47, 1.47, -0.06)],
	["Hand.L", "ForeArm.L", Vector3(0.73, 1.48, -0.05)],
	["UpperArm.R", "Chest", Vector3(-0.19, 1.47, -0.06)],
	["ForeArm.R", "UpperArm.R", Vector3(-0.47, 1.47, -0.06)],
	["Hand.R", "ForeArm.R", Vector3(-0.73, 1.48, -0.05)],
	["Thigh.L", "Hips", Vector3(0.10, 0.94, -0.04)],
	["Shin.L", "Thigh.L", Vector3(0.13, 0.50, -0.05)],
	["Foot.L", "Shin.L", Vector3(0.155, 0.10, -0.07)],
	["Thigh.R", "Hips", Vector3(-0.10, 0.94, -0.04)],
	["Shin.R", "Thigh.R", Vector3(-0.13, 0.50, -0.05)],
	["Foot.R", "Shin.R", Vector3(-0.155, 0.10, -0.07)],
	["CoatBack", "Hips", Vector3(0, 0.95, -0.14)],
	["CoatFront.L", "Hips", Vector3(0.12, 0.95, 0.10)],
	["CoatFront.R", "Hips", Vector3(-0.12, 0.95, 0.10)],
]

var idx := {}


func _ss(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x) if e0 < e1 else 1.0 - smoothstep(e1, e0, x)


func _add(w: Dictionary, bone: String, v: float) -> void:
	if v <= 0.0001:
		return
	var b: int = idx[bone]
	w[b] = w.get(b, 0.0) + v


## Leg axis (x, z) at height y for one side (+1 = left).
func _leg_axis(y: float, side: float) -> Vector2:
	var x := lerpf(0.155, 0.13, clampf((y - 0.10) / 0.40, 0.0, 1.0))
	if y > 0.5:
		x = lerpf(0.13, 0.10, clampf((y - 0.5) / 0.44, 0.0, 1.0))
	return Vector2(x * side, -0.055)


func _torso(w: Dictionary, y: float, amt: float) -> void:
	# vertical chain: Hips < Spine < Chest < Neck < Head, smooth blends at the joints
	var k_spine := _ss(1.00, 1.10, y)
	var k_chest := _ss(1.18, 1.30, y)
	var k_neck := _ss(1.54, 1.60, y)
	var k_head := _ss(1.62, 1.68, y)
	_add(w, "Hips", amt * (1.0 - k_spine))
	_add(w, "Spine", amt * (k_spine - k_chest))
	_add(w, "Chest", amt * (k_chest - k_neck))
	_add(w, "Neck", amt * (k_neck - k_head))
	_add(w, "Head", amt * k_head)


func _weights(p: Vector3) -> Dictionary:
	var w := {}
	var ax := absf(p.x)
	var side := 1.0 if p.x >= 0.0 else -1.0
	var sfx := ".L" if side > 0.0 else ".R"
	# arms (T-pose, along +-X)
	if p.y > 1.28 and p.y < 1.66 and ax > 0.14:
		var s := _ss(0.15, 0.27, ax)
		if ax < 0.32:
			s *= _ss(1.30, 1.40, p.y) * _ss(1.64, 1.58, p.y)
		var k_fore := _ss(0.43, 0.51, ax)
		var k_hand := _ss(0.70, 0.76, ax)
		_add(w, "UpperArm" + sfx, s * (1.0 - k_fore))
		_add(w, "ForeArm" + sfx, s * (k_fore - k_hand))
		_add(w, "Hand" + sfx, s * k_hand)
		_torso(w, p.y, 1.0 - s)
		return w
	if p.y >= 1.0:
		_torso(w, p.y, 1.0)
		return w
	# lower body
	var axis := _leg_axis(p.y, side)
	var d := Vector2(p.x, p.z).distance_to(axis)
	var is_leg := p.y < 0.40 or d < 0.105
	if is_leg:
		var to_hips := _ss(0.86, 1.0, p.y)
		var k_shin := _ss(0.56, 0.44, p.y)
		var k_foot := _ss(0.15, 0.08, p.y)
		var leg := 1.0 - to_hips
		_add(w, "Thigh" + sfx, leg * (1.0 - k_shin))
		_add(w, "Shin" + sfx, leg * (k_shin - k_foot))
		_add(w, "Foot" + sfx, leg * k_foot)
		_add(w, "Hips", to_hips)
		return w
	# coat skirt: hangs from the waist on three panel bones, front follows the thighs a little
	var c := _ss(0.97, 0.80, p.y)
	var back := _ss(0.03, -0.12, p.z)
	var wl := _ss(-0.06, 0.06, p.x)
	var follow := 0.35 * _ss(0.85, 0.5, p.y) * (1.0 - back)
	var panel := c * (1.0 - follow)
	_add(w, "CoatBack", panel * back)
	_add(w, "CoatFront.L", panel * (1.0 - back) * wl)
	_add(w, "CoatFront.R", panel * (1.0 - back) * (1.0 - wl))
	_add(w, "Thigh.L", c * follow * wl)
	_add(w, "Thigh.R", c * follow * (1.0 - wl))
	_add(w, "Hips", 1.0 - c)
	return w


func _initialize() -> void:
	for i in BONES.size():
		idx[BONES[i][0]] = i
	var src: Node = load(SRC).instantiate()
	var src_mi: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
	var src_mesh: Mesh = src_mi.mesh
	var arrays: Array = src_mesh.surface_get_arrays(0)
	var mat: Material = src_mesh.surface_get_material(0)
	if src_mi.get_surface_override_material(0) != null:
		mat = src_mi.get_surface_override_material(0)
	mat = mat.duplicate()

	# bake: rotate -90 deg about Y (+X -> +Z), scale to HEIGHT, feet at 0
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var min_y := INF
	var max_y := -INF
	for v in verts:
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
	var sc := HEIGHT / (max_y - min_y)
	var rot := Basis(Vector3.UP, -PI / 2.0)
	var xf := Transform3D(rot.scaled(Vector3.ONE * sc), Vector3(0, -min_y * sc, 0))
	for i in verts.size():
		verts[i] = xf * verts[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in n.size():
			n[i] = rot * n[i]
		arrays[Mesh.ARRAY_NORMAL] = n
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var t: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for i in range(0, t.size(), 4):
			var tv := rot * Vector3(t[i], t[i + 1], t[i + 2])
			t[i] = tv.x
			t[i + 1] = tv.y
			t[i + 2] = tv.z
		arrays[Mesh.ARRAY_TANGENT] = t

	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(verts.size() * 4)
	weights.resize(verts.size() * 4)
	for i in verts.size():
		var w := _weights(verts[i])
		var keys := w.keys()
		keys.sort_custom(func(a, b): return w[a] > w[b])
		var total := 0.0
		for k in range(mini(4, keys.size())):
			total += w[keys[k]]
		for k in 4:
			if k < keys.size() and total > 0.0:
				bones[i * 4 + k] = keys[k]
				weights[i * 4 + k] = w[keys[k]] / total
			else:
				bones[i * 4 + k] = 0
				weights[i * 4 + k] = 0.0
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)

	var root := Node3D.new()
	root.name = "Sol"
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	skel.owner = root
	var skin := Skin.new()
	for i in BONES.size():
		skel.add_bone(BONES[i][0])
	for i in BONES.size():
		var parent_name: String = BONES[i][1]
		var pos: Vector3 = BONES[i][2]
		var local := pos
		if parent_name != "":
			var pi: int = idx[parent_name]
			skel.set_bone_parent(i, pi)
			local = pos - (BONES[pi][2] as Vector3)
		skel.set_bone_rest(i, Transform3D(Basis(), local))
		skin.add_named_bind(BONES[i][0], Transform3D(Basis(), -pos))
	skel.reset_bone_poses()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.skin = skin
	skel.add_child(mi)
	mi.owner = root
	mi.skeleton = NodePath("..")
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT, ResourceSaver.FLAG_COMPRESS)
	print("build_sol_rig: verts=%d scale=%.4f save=%s -> %s" % [verts.size(), sc, error_string(err), OUT])
	quit()
