extends SceneTree
## PERF: native benchmark runner (scripts/bench.gd has the route).
##   godot --headless --fixed-fps 60 -s res://tests/bench_run.gd -- [--tier=verylow|low|medium|high] [--out=/path.json]
## Headless with --fixed-fps measures pure CPU (script + physics + navigation) cost per frame.
## Under xvfb with --rendering-method gl_compatibility it includes the (software) renderer.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	load("res://scripts/progression.gd").save_path = "user://bench_save.json"
	var Meta = load("res://scripts/hunt/hunt_meta.gd")
	Meta.path = "user://bench_hunt_meta.json"
	var Story = load("res://scripts/hunt/hunt_story.gd")
	Story.never_intro = true
	var HD = load("res://scripts/hunt/hunt_director.gd")
	HD.force_freeroam = false
	HD.requested = true
	HD.seed_override = 4242
	load("res://scripts/main.gd").started_once = true
	var st = root.get_node_or_null("Settings")
	load("res://scripts/settings.gd").uncapped = true # raw frame cost, no FPS cap
	for a in args:
		if a.begins_with("--tier=") and st != null and st.has_method("apply_tier_name"):
			st.apply_tier_name(a.substr(7), false)
	var main = load("res://scenes/main.tscn").instantiate()
	var B = load("res://scripts/bench.gd")
	if B == null or not B.can_instantiate():
		push_error("bench.gd failed to load")
		quit(2)
		return
	var b = B.new()
	b.main = main
	root.add_child(b)
	root.add_child(main)
	var res: Dictionary = await b.done
	for a in args:
		if a.begins_with("--out="):
			var f := FileAccess.open(a.substr(6), FileAccess.WRITE)
			f.store_string(JSON.stringify(res, "  "))
	quit(0)
