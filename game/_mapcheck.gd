extends SceneTree
## temp: build the map headless, time it, dump layout stats
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	print("MAP total ready ms: ", Time.get_ticks_msec() - t0)
	var c = main.city
	var t1 := Time.get_ticks_msec()
	var t2 := Time.get_ticks_msec()
	main._bake_navigation()
	print("MAP nav bake ms: ", Time.get_ticks_msec() - t2)
	var nm: NavigationMesh = main.nav_region.navigation_mesh
	print("MAP nav polys: ", nm.get_polygon_count(), " verts ", nm.get_vertices().size())
	print("MAP anchors ", c.poi_anchors.size(), " caches ", c.cache_spots.size(), " roads ", c.road_points.size(), " lots ", c.lots.size())
	var dcount := {}
	for a in c.poi_anchors:
		dcount[a.district] = dcount.get(a.district, 0) + 1
	print("MAP anchors per district ", dcount)
	var pois = load("res://scripts/hunt/poi_spawner.gd").generate(4242, c)
	var per := {}
	for e in pois:
		per[e.type + "@" + e.district] = per.get(e.type + "@" + e.district, 0) + 1
	print("MAP pois ", pois.size(), " ", per)
	var meshes := 0
	var tris := 0
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
		var m: Mesh = mi.mesh
		for s in m.get_surface_count():
			tris += m.surface_get_array_index_len(s) / 3
	print("MAP mesh instances ", meshes, " static tris ", tris, " mmis ", c.find_children("*", "MultiMeshInstance3D", true, false).size())
	# reachability: path from plaza to each deploy point and arena
	await physics_frame
	await physics_frame
	var map_rid: RID = main.get_world_3d().navigation_map
	for d in c.deploy_points + c.arenas:
		var path := NavigationServer3D.map_get_path(map_rid, Vector3(0, 0.1, 8), d.pos, true)
		var end: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3.INF
		print("MAP path to %s: %d pts, end gap %.1f" % [d.name, path.size(), end.distance_to(d.pos)])
	quit()
