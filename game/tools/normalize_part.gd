extends SceneTree
## Bakes a generated GLB into game space and writes it back out as a GLB.
## Run from game/:
##   godot --headless -s res://tools/normalize_part.gd -- <src.glb> <dst.glb> <yaw_deg> <height_m> [ground|center] [tex_px]
##
## yaw_deg turns the mesh about +Y before anything else (Tripo meshes face +X, so -90 makes them face +Z).
## height_m scales the mesh so its tallest axis-aligned height is that many meters.
## "ground" puts the lowest vertex at y=0 and centres x/z (characters, boots); "center" centres all axes.
## The result is a single mesh, transform baked into the vertices, textures embedded (optionally downscaled
## to tex_px for uploads). This is the orientation fix the auto-rigger needs: +Z forward, Y up, feet at 0.

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 4:
		push_error("usage: <src> <dst> <yaw_deg> <height_m> [ground|center] [tex_px]")
		quit(1)
		return
	var src: Node = load(a[0]).instantiate()
	var yaw := deg_to_rad(float(a[2]))
	var height := float(a[3])
	var mode: String = a[4] if a.size() > 4 else "ground"
	var tex_px := int(a[5]) if a.size() > 5 else 0
	var mi: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
	var node_xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n is Node3D:
		node_xf = (n as Node3D).transform * node_xf
		n = n.get_parent()
	var rot := Basis(Vector3.UP, yaw)
	var out_mesh := ArrayMesh.new()
	# first pass: bounds after rotation
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for s in mi.mesh.get_surface_count():
		for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var p: Vector3 = rot * (node_xf * v)
			lo = lo.min(p)
			hi = hi.max(p)
	var sc := height / (hi.y - lo.y)
	var off := -Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5) * sc
	if mode == "center":
		off = -(lo + hi) * 0.5 * sc
	var nb := (rot * node_xf.basis).orthonormalized()
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = rot * (node_xf * verts[i]) * sc + off
		arr[Mesh.ARRAY_VERTEX] = verts
		if arr[Mesh.ARRAY_NORMAL] != null:
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in nn.size():
				nn[i] = (nb * nn[i]).normalized()
			arr[Mesh.ARRAY_NORMAL] = nn
		if arr[Mesh.ARRAY_TANGENT] != null:
			var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for i in range(0, t.size(), 4):
				var tv := nb * Vector3(t[i], t[i + 1], t[i + 2])
				t[i] = tv.x
				t[i + 1] = tv.y
				t[i + 2] = tv.z
			arr[Mesh.ARRAY_TANGENT] = t
		out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat: Material = mi.get_active_material(s)
		if mat is BaseMaterial3D:
			mat = _plain_material(mat as BaseMaterial3D, tex_px)
		out_mesh.surface_set_material(s, mat)
	var root_node := Node3D.new()
	root_node.name = "Part"
	var out_mi := MeshInstance3D.new()
	out_mi.name = "Mesh"
	out_mi.mesh = out_mesh
	root_node.add_child(out_mi)
	out_mi.owner = root_node
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root_node, state)
	if err == OK:
		err = doc.write_to_filesystem(state, a[1])
	print("normalize_part: scale=%.5f size=%s -> %s (%s)" % [sc, (hi - lo) * sc, a[1], error_string(err)])
	quit(0 if err == OK else 1)


## Copies a material with its textures turned into plain (decompressed, optionally downscaled) images,
## so the GLTF exporter can embed them.
func _plain_material(m: BaseMaterial3D, px: int) -> StandardMaterial3D:
	var o := StandardMaterial3D.new()
	o.albedo_color = m.albedo_color
	o.metallic = m.metallic
	o.roughness = m.roughness
	o.albedo_texture = _plain(m.albedo_texture, px)
	if m.normal_enabled and m.normal_texture != null:
		o.normal_enabled = true
		o.normal_texture = _plain(m.normal_texture, px)
	if m.metallic_texture != null:
		o.metallic_texture = _plain(m.metallic_texture, px)
		o.metallic_texture_channel = m.metallic_texture_channel
	if m.roughness_texture != null:
		o.roughness_texture = _plain(m.roughness_texture, px)
		o.roughness_texture_channel = m.roughness_texture_channel
	return o


func _plain(t: Texture2D, px: int) -> Texture2D:
	if t == null:
		return null
	var img := t.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if px > 0 and img.get_width() > px:
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)
