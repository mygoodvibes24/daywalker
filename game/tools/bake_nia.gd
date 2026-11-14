extends SceneTree
## Offline tool: bakes Nia's generated GLB into res://assets/characters/nia/nia.scn.
##   godot --headless -s res://tools/bake_nia.gd
## Scales the mesh to 1.70 m, puts her feet on y=0 centred on the origin and turns her
## to face +Z. The GLB itself is excluded from the web export, like the other characters.

const SRC := "res://assets/characters/nia/nia.glb"
const DST := "res://assets/characters/nia/nia.scn"
const HEIGHT := 1.70
const YAW := -PI / 2.0 # the source mesh faces +X


func _initialize() -> void:
	var src: Node = load(SRC).instantiate()
	var mi: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: ArrayMesh = mi.mesh
	var arrays := mesh.surface_get_arrays(0)
	var mat: Material = mi.get_active_material(0).duplicate()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tans = arrays[Mesh.ARRAY_TANGENT]
	var xf: Transform3D = mi.global_transform if mi.is_inside_tree() else _chain(mi)
	var miny := INF
	var maxy := -INF
	for i in verts.size():
		verts[i] = xf * verts[i]
		miny = minf(miny, verts[i].y)
		maxy = maxf(maxy, verts[i].y)
	var s := HEIGHT / (maxy - miny)
	# centre on the feet (lowest 6% of the body)
	var c := Vector3.ZERO
	var n := 0
	for v in verts:
		if v.y - miny < 0.06 * (maxy - miny):
			c += v
			n += 1
	c /= maxf(n, 1)
	var rot := Basis(Vector3.UP, YAW)
	for i in verts.size():
		verts[i] = rot * (Vector3(verts[i].x - c.x, verts[i].y - miny, verts[i].z - c.z) * s)
		norms[i] = (rot * (xf.basis * norms[i])).normalized()
	if tans != null:
		var t: PackedFloat32Array = tans
		for i in range(0, t.size(), 4):
			var tv := rot * (xf.basis * Vector3(t[i], t[i + 1], t[i + 2])).normalized()
			t[i] = tv.x; t[i + 1] = tv.y; t[i + 2] = tv.z
		arrays[Mesh.ARRAY_TANGENT] = t
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, mat)
	var root := Node3D.new()
	root.name = "Nia"
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = out
	root.add_child(body)
	body.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, DST)
	print("baked ", DST, " err=", err, " verts=", verts.size(), " scale=", s)
	src.free()
	root.free()
	quit()


func _chain(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
