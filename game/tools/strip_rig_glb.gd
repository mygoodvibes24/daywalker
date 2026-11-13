extends SceneTree
## Shrinks an auto-rigged GLB before it goes into the repo.
## Run from game/:
##   godot --headless -s res://tools/strip_rig_glb.gd -- <src.glb> <dst.glb> <mesh|anim>
##
## "mesh": keeps the skinned mesh, skeleton and animation but drops the materials/textures (the build tool
##         re-applies the original full-resolution PBR material from the unrigged source).
## "anim": keeps only the skeleton and its animation clip (one clip per rigging call).

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(a[0], st)
	if err != OK:
		push_error("can't read " + a[0])
		quit(1)
		return
	var scn: Node = doc.generate_scene(st)
	for mi in scn.find_children("*", "MeshInstance3D", true, false):
		if a[2] == "anim":
			# keep a 1-triangle stub so the skin/skeleton survives the round trip
			var stub := ArrayMesh.new()
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3(0, 0.001, 0), Vector3(0.001, 0, 0)])
			arr[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
			arr[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
			stub.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			(mi as MeshInstance3D).mesh = stub
		else:
			var m: Mesh = (mi as MeshInstance3D).mesh
			var out := ArrayMesh.new()
			for s in m.get_surface_count():
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(s))
				out.surface_set_material(s, StandardMaterial3D.new())
			(mi as MeshInstance3D).mesh = out
	var doc2 := GLTFDocument.new()
	var st2 := GLTFState.new()
	err = doc2.append_from_scene(scn, st2)
	if err == OK:
		err = doc2.write_to_filesystem(st2, a[1])
	print("strip_rig_glb: %s -> %s (%s)" % [a[0], a[1], error_string(err)])
	quit(0 if err == OK else 1)
