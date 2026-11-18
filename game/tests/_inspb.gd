extends SceneTree
func _yaw(q: Quaternion) -> float:
	var f := Basis(q) * Vector3.BACK
	return rad_to_deg(atan2(f.x, f.z))

func _initialize() -> void:
	var sol: Node3D = load("res://assets/characters/sol/sol_modular.scn").instantiate()
	var ap := sol.get_node("AnimationPlayer") as AnimationPlayer
	var sk := sol.get_node("Skeleton3D") as Skeleton3D
	print("rest hips yaw ", _yaw(sk.get_bone_rest(sk.find_bone("Hips")).basis.get_rotation_quaternion()))
	for c in ["idle", "stance", "combo1", "combo2", "combo3", "heavy3", "judgment", "charged"]:
		var a := ap.get_animation(c)
		var t := a.find_track(NodePath("Skeleton3D:Hips"), Animation.TYPE_ROTATION_3D)
		var s := ""
		var tt := 0.0
		while tt <= a.length + 0.001:
			s += "%.2f:%.0f " % [tt, _yaw(a.rotation_track_interpolate(t, tt))]
			tt += 0.1
		print(c, " ", s)
	sol.free()
	quit()
