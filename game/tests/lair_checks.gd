extends RefCounted
## Smoke checks for the walkable lair (scenes/lair.tscn, scripts/lair/) and the wardrobe
## (items/wardrobe_data.gd, sol_outfit.gd): Start goes to the lair, Sol walks but can't fight there,
## every station opens its panel, the blade and each clothing slot change both the stats and the
## look, Begin the Hunt hands over to the Hunt, ?autohunt still skips the lair, results come home to
## the lair, and the lair stays inside the web budget. Run from tests/smoke_test.gd.

const Meta = preload("res://scripts/hunt/hunt_meta.gd")
const W = preload("res://scripts/items/wardrobe_data.gd")
const Rooms = preload("res://scripts/lair/lair_rooms.gd")
const FB = preload("res://tests/frame_budget.gd")
const DRAW_BUDGET := 350
const TRI_BUDGET := 600000

var tree: SceneTree
var check: Callable


func _ok(name: String, cond: bool) -> bool:
	return check.call(name, cond)


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func run(t: SceneTree, c: Callable) -> bool:
	tree = t
	check = c
	var ok := true
	var HD = load("res://scripts/hunt/hunt_director.gd")
	Meta.path = "user://smoke_lair_meta.json"
	if FileAccess.file_exists(Meta.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Meta.path))
	Meta.reset_meta()
	# ---- the data
	var n_items := W.ITEMS.size()
	var per_slot := true
	for s in W.SLOTS:
		per_slot = per_slot and W.items_for(s).size() >= 4
	ok = _ok("wardrobe: %d pieces over %d slots, 4+ each" % [n_items, W.SLOTS.size()], n_items >= 25 and W.SLOTS.size() == 7 and per_slot) and ok
	var defaults_clean := W.outfit_mods(W.DEFAULT_OUTFIT).is_empty()
	var all_start := true
	for s in W.DEFAULT_OUTFIT:
		all_start = all_start and Meta.owns_cloth(W.DEFAULT_OUTFIT[s])
	var sources := {"start": 0, "price": 0, "drop": 0}
	for id in W.ITEMS:
		var d: Dictionary = W.ITEMS[id]
		for k in sources:
			if d.get(k, false):
				sources[k] += 1
	ok = _ok("the default outfit is owned and stat-free; pieces come from the start / Sunmarks / Hunts %s" % sources,
		defaults_clean and all_start and sources.start >= 7 and sources.price >= 10 and sources.drop >= 6) and ok
	var s := {"speed": 0.9, "max_hp_pct": -2.0, "dmg_taken": -3.0}
	W.clamp_totals(s)
	var capped := W.outfit_mods({"hat": "flat_cap", "scarf": "no_scarf", "coat": "courier_coat", "shirt": "black_henley", "gloves": "bare_hands", "pants": "runner_slacks", "boots": "courier_boots"})
	ok = _ok("stat caps: totals clamp (speed %.2f, health %.2f, taken %.2f), an outfit's speed caps at %.2f (%.2f)" % [s.speed, s.max_hp_pct, s.dmg_taken, W.OUTFIT_CAP.speed, capped.speed],
		is_equal_approx(s.speed, 0.45) and is_equal_approx(s.max_hp_pct, -0.3) and is_equal_approx(s.dmg_taken, -0.6) and capped.speed <= W.OUTFIT_CAP.speed + 0.0001) and ok
	# ---- Start goes to the lair; ?autohunt still goes straight to a Hunt
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	for i in 3: await tree.process_frame
	menu.buttons[0].pressed.emit()
	var to_lair: bool = menu.target_scene == menu.LAIR_SCENE and menu.state == "loading"
	_kill_tweens() # stop the fade before it starts a (threaded) scene load
	menu.queue_free()
	await tree.process_frame
	var menu2 = load("res://scenes/main_menu.tscn").instantiate()
	tree.root.add_child(menu2)
	for i in 3: await tree.process_frame
	menu2._begin_hunt()
	var to_hunt: bool = menu2.target_scene == menu2.GAME_SCENE and HD.requested
	_kill_tweens()
	menu2.queue_free()
	HD.requested = false
	await tree.process_frame
	ok = _ok("main menu Start loads the playable lair (scenes/lair.tscn)", to_lair) and ok
	ok = _ok("?autohunt / --autohunt still skips the lair straight into a Hunt", to_hunt and FileAccess.get_file_as_string("res://scripts/menu/main_menu.gd").contains("_flag_wanted(\"lair\")")) and ok
	ok = _ok("a Hunt's results return to the lair, not the menu", HD.LAIR_SCENE == "res://scenes/lair.tscn" \
		and FileAccess.get_file_as_string("res://scripts/hunt/hunt_director.gd").contains("change_scene_to_file(LAIR_SCENE)")) and ok
	# ---- the lair
	Meta.data.sunmarks = 500
	var lair = load("res://scenes/lair.tscn").instantiate()
	tree.root.add_child(lair)
	await _frames(20)
	var p = lair.player
	ok = _ok("the lair builds: Sol (peaceful) on the floor, Nia, the stations, colliders (batched %d meshes -> %d)" % [lair.rooms.batched_from, lair.rooms.batched_to],
		p != null and p.peaceful and p.is_on_floor() and lair.set_.nia != null and lair.rooms.colliders.get_child_count() > 20 and lair.rooms.batched_to > 0) and ok
	ok = _ok("the sword stays on his back in the lair", p.sword_on_back()) and ok
	# walking
	var start: Vector3 = p.global_position
	Input.action_press("move_forward")
	await _frames(40)
	Input.action_release("move_forward")
	var moved: float = p.global_position.distance_to(start)
	ok = _ok("Sol walks around the lair (%.1f m)" % moved, moved > 1.0 and p.global_position.y > -0.1) and ok
	# no combat
	Input.action_press("attack")
	await _frames(3)
	Input.action_release("attack")
	await _frames(20)
	ok = _ok("combat is off in the lair: attack swings nothing, the blade stays sheathed", p.swing_t <= 0.0 and p.move_name == "" and p.sword_on_back()) and ok
	# prompts and stations
	var prompts := true
	for id in Rooms.STATIONS:
		p.global_position = Rooms.STATIONS[id].pos + Vector3(0, 0.1, 0)
		await _frames(3)
		prompts = prompts and lair.near == id
	ok = _ok("each station shows its prompt when Sol walks up", prompts) and ok
	var opened := []
	for id in ["rack", "bench", "mirror", "table", "gate"]:
		p.global_position = Rooms.STATIONS[id].pos + Vector3(0, 0.1, 0)
		await _frames(2)
		lair.use_station(id)
		await _frames(2)
		if lair.panel.visible and lair.panel.kind == id and lair.cam.current and lair.station == id and not p.is_physics_processing():
			opened.append(id)
		lair.panel.close()
		await _frames(30)
	ok = _ok("every station opens its panel with the camera framing it %s" % [opened], opened.size() == 5 and p.is_physics_processing() and lair.station == "") and ok
	var talked: bool = lair.nia_talks == 0
	lair.use_station("nia")
	ok = _ok("talking to Nia plays a line", talked and lair.nia_talks == 1) and ok
	# the blade
	p.global_position = Rooms.STATIONS.rack.pos + Vector3(0, 0.1, 0)
	await _frames(2)
	lair.use_station("rack")
	await _frames(2)
	var marks0 := int(Meta.data.sunmarks)
	lair.panel._rack_pick("ronin_katana") # bought (50) and carried
	await _frames(5)
	var carried: bool = String(p.weapon_item.get("id", "")) == "ronin_katana" and p.sheath != null and p.sheath.mount_name == "hip"
	ok = _ok("choosing a blade at the rack changes what Sol carries (katana at the hip, %d -> %d Sunmarks)" % [marks0, int(Meta.data.sunmarks)],
		carried and Meta.data.start_blade == "ronin_katana" and int(Meta.data.sunmarks) == marks0 - 50 and lair.rooms.rack_root.get_child_count() >= 1) and ok
	lair.panel._rack_pick("marrow_silver")
	await _frames(3)
	ok = _ok("...and back to Marrow's Silver on his back", String(p.weapon_item.get("id", "")) == "marrow_silver" and p.sheath.mount_name == "back") and ok
	lair.panel.close()
	await _frames(20)
	# the wardrobe: every slot changes the stats and the look
	lair.use_station("mirror")
	await _frames(2)
	var picks := {"hat": "wide_brim", "scarf": "wolfhide_scarf", "coat": "hunter_duster", "shirt": "silver_mesh", "gloves": "silver_gloves", "pants": "runner_slacks", "boots": "courier_boots"}
	var good := []
	for slot in W.SLOTS:
		var id: String = picks[slot]
		var before := _look(p, slot)
		var stats0: Dictionary = lair.progression.stats.duplicate()
		lair.panel._slot(slot)
		lair.panel._wear(id) # bought with Sunmarks and worn
		await _frames(2)
		var after := _look(p, slot)
		var stat_changed := false
		for k in W.get_def(id).mods:
			stat_changed = stat_changed or not is_equal_approx(float(lair.progression.stats.get(k, 0.0)), float(stats0.get(k, 0.0)))
		if Meta.outfit()[slot] == id and after != before and stat_changed:
			good.append(slot)
		else:
			print("    wardrobe %s: worn %s, look %s -> %s, stats %s" % [slot, Meta.outfit()[slot], before, after, stat_changed])
	ok = _ok("equipping each clothing slot changes both the stats and the visual %s" % [good], good.size() == 7) and ok
	var mhp: float = p.max_hp
	ok = _ok("the outfit's health reaches Sol (max blood %.0f with the duster)" % mhp, mhp > 100.0) and ok
	var saved = JSON.parse_string(FileAccess.get_file_as_string(Meta.path))
	ok = _ok("owned clothes and the outfit are saved", saved is Dictionary and "hunter_duster" in saved.get("clothes", []) and saved.get("outfit", {}).get("coat", "") == "hunter_duster") and ok
	lair.panel.close()
	await _frames(20)
	# the budget, from the walking camera at several spots and from every station framing
	var worst := {"draws": 0, "tris": 0, "lights": 0}
	var spots := [[lair.SPAWN, 0.0], [Vector3(1.0, 0.2, -0.6), 0.0], [Vector3(2.2, 0.2, -1.6), PI * 0.8 + PI], [Vector3(-1.2, 0.2, -4.5), 0.0], [Vector3(1.8, 0.2, -2.2), PI]]
	for sp in spots:
		p.global_position = sp[0]
		p.cam_yaw = sp[1]
		await _frames(4)
		_worst(worst, FB.estimate(lair, p.camera.global_transform, 75.0, 80.0))
	for id in lair.SHOTS:
		var sh: Array = lair.SHOTS[id]
		_worst(worst, FB.estimate(lair, Transform3D(Basis.looking_at(sh[1] - sh[0], Vector3.UP), sh[0]), sh[2], 80.0))
	ok = _ok("the lair stays within the web budget (worst %d draws / %d tris / %d lights; budget %d / %d)" % [worst.draws, worst.tris, worst.lights, DRAW_BUDGET, TRI_BUDGET],
		worst.draws <= DRAW_BUDGET and worst.tris <= TRI_BUDGET and worst.lights <= 8) and ok
	# Begin the Hunt: the seed the briefing showed goes to the Hunt
	lair.begin_hunt()
	var handed: bool = HD.requested and HD.next_seed == lair.hunt_seed and lair.leaving
	_kill_tweens()
	HD.next_seed = -1
	ok = _ok("Begin the Hunt asks main.tscn for a Hunt with the briefing's seed", handed) and ok
	lair.queue_free()
	await tree.process_frame
	HD.requested = false
	return ok


func _kill_tweens() -> void:
	for t in tree.get_processed_tweens():
		t.kill()


func _worst(w: Dictionary, e: Dictionary) -> void:
	w.draws = maxi(w.draws, int(e.draws))
	w.tris = maxi(w.tris, int(e.tris))
	w.lights = maxi(w.lights, int(e.get("lights", 0)))


## A short signature of what a slot looks like on Sol's model right now.
static func _look(p, slot: String) -> String:
	var m: Node = p.model_root
	if m == null:
		return ""
	match slot:
		"hat":
			return str(m.find_child("OutfitHat", true, false).get_child_count())
		"scarf":
			return str(m.find_child("OutfitScarf", true, false).get_child_count())
		"coat":
			var c := m.find_child("Coat", true, false) as MeshInstance3D
			var mat = c.material_override
			return str(mat.get_shader_parameter("tint")) if mat is ShaderMaterial else str(mat.albedo_color if mat != null else "")
		"gloves":
			var h := m.find_child("HandR", true, false).get_node("HandMesh") as MeshInstance3D
			return str(h.material_override.get_shader_parameter("tint")) if h.material_override is ShaderMaterial else "bare"
		_:
			var b := m.find_child("Body", true, false) as MeshInstance3D
			if not (b.material_override is ShaderMaterial):
				return "stock"
			var i := ["shirt", "pants", "boots"].find(slot)
			return "%s %s" % [b.material_override.get_shader_parameter("col%d" % (i + 1)), b.material_override.get_shader_parameter("amt")[i]]
	return ""
