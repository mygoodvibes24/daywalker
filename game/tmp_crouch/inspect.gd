extends SceneTree
func _initialize() -> void:
	var m: Node3D = (load("res://assets/characters/sol/sol_modular.scn") as PackedScene).instantiate()
	root.add_child(m)
	print("HandMeshOpen: ", m.find_child("HandMeshOpen", true, false) != null, "  BladeL: ", m.find_child("BladeL", true, false) != null)
	var ap: AnimationPlayer = m.get_node("AnimationPlayer")
	var lib := ap.get_animation_library("")
	print("clips: ", lib.get_animation_list())
	var sk: Skeleton3D = m.get_node("Skeleton3D")
	for cn in ["walk", "crouch_walk", "crouch_idle", "idle"]:
		if not lib.has_animation(cn):
			continue
		var a := lib.get_animation(cn)
		ap.play(cn)
		print(a.track_get_path(0), " ", a.track_get_type(0), " ", sk.get_bone_count(), " ", sk.get_bone_name(0))
		var N := 240
		var dt := a.length / N
		var prev := {}
		var samples := []
		var hipmin := 9.0
		var hipmax := -9.0
		for s in N + 1:
			_pose(sk, a, a.length * s / N)
			var hy := sk.get_bone_global_pose(sk.find_bone("Hips")).origin.y
			hipmin = minf(hipmin, hy)
			hipmax = maxf(hipmax, hy)
			for f in ["LeftFoot", "RightFoot"]:
				var p := sk.get_bone_global_pose(sk.find_bone(f)).origin
				if prev.has(f):
					var d: Vector3 = p - prev[f]
					samples.append([p.y, Vector2(d.x, d.z).length() / dt, d.z / dt])
				prev[f] = p
		var ymin := 9.0
		var ymax := -9.0
		for x in samples:
			ymin = minf(ymin, x[0])
			ymax = maxf(ymax, x[0])
		var sp := 0.0
		var sz := 0.0
		var n := 0
		for x in samples:
			if x[0] < ymin + (ymax - ymin) * 0.15:
				sp += x[1]
				sz += x[2]
				n += 1
		print("%s: len %.2f s  hips y %.3f..%.3f  foot y %.3f..%.3f  planted speed %.3f m/s (z %.3f) n=%d loop=%d" % [cn, a.length, hipmin, hipmax, ymin, ymax, sp / maxi(n, 1), sz / maxi(n, 1), n, a.loop_mode])
	quit()


func _pose(sk: Skeleton3D, a: Animation, t: float) -> void:
	for i in a.get_track_count():
		var b := sk.find_bone(str(a.track_get_path(i)).get_slice(":", 1))
		if b < 0:
			continue
		match a.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(b, a.rotation_track_interpolate(i, t))
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(b, a.position_track_interpolate(i, t))
