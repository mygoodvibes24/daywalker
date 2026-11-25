extends "res://tests/smoke_test.gd"
## Local focus run (not committed): only Group B's checks.

func _initialize() -> void:
	load("res://scripts/progression.gd").save_path = SMOKE_SAVE
	var HD = load("res://scripts/hunt/hunt_director.gd")
	HD.force_freeroam = true
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	main.start_game()
	for i in 10: await physics_frame
	var ok := true
	var which := OS.get_cmdline_user_args()
	if which.is_empty() or "sheath" in which:
		ok = await _sheath_checks(main) and ok
	if which.is_empty() or "combat" in which:
		ok = await _combat_r3_checks(main) and ok
	if "moves" in which:
		ok = await _move_checks(main) and ok
	print("FOCUS: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
