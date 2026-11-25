extends SceneTree

func _initialize() -> void:
	var m = (load("res://assets/characters/sol/sol_modular.scn") as PackedScene).instantiate()
	root.add_child(m)
	var sk := m.get_node("Skeleton3D") as Skeleton3D
	print("skel xf ", sk.transform, " model xf ", m.transform)
	for bn in ["Hips", "Spine02", "RightArm", "Neck", "Head", "LeftUpLeg"]:
		print(bn, " rest ", sk.get_bone_global_rest(sk.find_bone(bn)).origin)
	for nm in ["Coat", "Body"]:
		var mi := m.find_child(nm, true, false) as MeshInstance3D
		if mi == null:
			print("no ", nm)
			continue
		print(nm, " xf ", mi.transform, " parent ", mi.get_parent().name)
		var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for band in [[0.9, 1.1], [1.1, 1.3], [1.3, 1.56], [1.56, 1.7]]:
			var mn := 9.0
			var mx := -9.0
			var xmax := 0.0
			for p in v:
				if p.y > band[0] and p.y < band[1]:
					if absf(p.x) < 0.15:
						mn = minf(mn, p.z)
						mx = maxf(mx, p.z)
					xmax = maxf(xmax, absf(p.x))
			print("  ", nm, " y", band, " z ", mn, "..", mx, " |x|max ", xmax)
	for c in m.get_children():
		print("child ", c.name, " ", c.get_class())
	for c in sk.get_children():
		print("skchild ", c.name, " ", c.get_class())
	quit()
