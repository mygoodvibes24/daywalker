extends SceneTree
## temp: main-menu framing capture. args: out.png [zoom_on_nia 0|1]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var m = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(m)
	for i in 90:
		await process_frame
	if a.size() > 1 and a[1] != "0":
		var cam := root.get_viewport().get_camera_3d()
		var set_ = m.find_child("*", true, false)
		var nia: Node3D = null
		for n in root.find_children("*", "Node3D", true, false):
			if n.name == "Nia":
				nia = n
		if nia and cam:
			var target := nia.global_transform * Vector3(0, 1.55, 0)
			var c2 := Camera3D.new()
			c2.fov = 25.0
			root.add_child(c2)
			var fwd := (nia.global_transform.basis * Vector3(0, 0, 1)).normalized()
			if a[1] == "2":
				# Sol's face at the bench
				for n in root.find_children("*", "Skeleton3D", true, false):
					var sk := n as Skeleton3D
					var hb := sk.find_bone("Head")
					if hb >= 0:
						target = sk.global_transform * sk.get_bone_global_pose(hb).origin + Vector3(0, 0.05, 0)
						fwd = (sk.global_transform.basis * Vector3(0, -0.3, 1)).normalized()
			c2.global_position = target + fwd * 0.75 + Vector3(0, 0.03, 0)
			c2.look_at(target, Vector3.UP)
			c2.current = true
		for i in 10:
			await process_frame
	root.get_texture().get_image().save_png(a[0])
	quit()
