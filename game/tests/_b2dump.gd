extends SceneTree
## dump mesh positions / uvs / indices of Body, Coat, HeadMesh to raw float files

func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var m = (load("res://assets/characters/sol/sol_modular.scn") as PackedScene).instantiate()
	root.add_child(m)
	for nm in ["Body", "Coat", "HeadMesh"]:
		var mi := m.find_child(nm, true, false) as MeshInstance3D
		var a: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
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
		print(nm, " ", v.size(), " ", idx.size(), " tex ", mat.albedo_texture.resource_path if mat and mat.get("albedo_texture") else "-", " mo ", mi.material_override)
	quit()
