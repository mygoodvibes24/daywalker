extends SceneTree
## Dumps the built Sol's Body, Coat and HeadMesh (skeleton-space positions, normals, UVs, indices) to
## <out>/<name>.bin for tools/sol_texture_fixes.py:
##   godot --headless -s res://tools/dump_sol_meshes.gd -- <out_dir>
## Format: u32 vertex count, u32 index count, then float32 xyz * n, float32 normal * n, float32 uv * n,
## u32 indices.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	var m = (load("res://assets/characters/sol/sol_modular.scn") as PackedScene).instantiate()
	root.add_child(m)
	for nm in ["Body", "Coat", "HeadMesh"]:
		var mi := m.find_child(nm, true, false) as MeshInstance3D
		var a: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var f := FileAccess.open("%s/%s.bin" % [out, nm], FileAccess.WRITE)
		f.store_32(v.size())
		f.store_32(idx.size())
		for p in v:
			f.store_float(p.x); f.store_float(p.y); f.store_float(p.z)
		for p in nrm:
			f.store_float(p.x); f.store_float(p.y); f.store_float(p.z)
		for p in uv:
			f.store_float(p.x); f.store_float(p.y)
		for i in idx:
			f.store_32(i)
		f.close()
		var mat = mi.mesh.surface_get_material(0)
		print(nm, ": ", v.size(), " verts, albedo ", mat.albedo_texture.resource_path if mat is StandardMaterial3D and mat.albedo_texture else "-")
	quit()
