extends RefCounted
## Smoke checks for the Arsenal (round 4, items/arsenal.gd): every weapon type equips and plays its
## moveset, every Weapon Art fires and hits, every special combo route triggers, the ART touch button
## works, Bleed and stagger proc, the rack, the Rites and the drops. Run from tests/smoke_test.gd.

const ItemDB = preload("res://scripts/items/item_db.gd")
const ArsenalData = preload("res://scripts/items/arsenal_data.gd")
const ArsenalMoves = preload("res://scripts/items/arsenal_moves.gd")
const SolMoves = preload("res://scripts/sol_moves.gd")
const WeaponVisual = preload("res://scripts/items/weapon_visual.gd")

var tree: SceneTree
var main
var check: Callable
var hits: Array = []


func _ok(name: String, cond: bool) -> bool:
	return check.call(name, cond)


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


## The first item of each weapon type (a Street copy).
func _item_for(t: String) -> String:
	for id in ItemDB.ITEMS:
		var d: Dictionary = ItemDB.ITEMS[id]
		if d.kind == "blade" and not d.get("unique", false) and ArsenalData.type_of_family(d.family) == t:
			return id
	return ""


func _equip(id: String) -> void:
	main.inventory.weapon = ItemDB.make(id)
	main.inventory.equipment_changed.emit()


func _reset_player() -> void:
	var p = main.player
	main.clear_slowmo()
	p.dead = false
	p.hp = p.max_hp
	p.velocity = Vector3.ZERO
	p.walk_vel = Vector3.ZERO
	p.global_position = Vector3(10.0, 0.1, 10.0)
	p.facing = 0.0
	p.visual.rotation.y = 0.0
	p.attack_cd = 0.0
	p.combo = 0
	p.combo_t = 0.0
	p.swing_t = 0.0
	p.pending = {}
	p.hold_t = -1.0
	p.since_dash = 99.0
	p.dash_t = 0.0
	p.attack_block_until = 0
	p.arsenal.art_cd_t = 0.0
	p.arsenal.chain_t = 0.0
	p.stamina = p.stamina_max # the checks test moves, not the stamina bar
	p.exhausted = false
	p.arsenal._events.clear()


func _dummy(at: Vector3, kind := 0):
	var e = load("res://scripts/enemy.gd").new()
	e.main = main
	e.kind = kind
	e.position = at
	main.enemies_root.add_child(e)
	await _frames(3)
	e.max_hp = 1e6
	e.hp = 1e6
	e.attack_cd = 99.0
	e.special_cd = 99.0
	e.speed = 0.0 # a training dummy: stands where it is put
	return e


func _clear() -> void:
	for e in main.enemies_root.get_children():
		main.enemies_root.remove_child(e)
		e.free()
	main.attack_tokens.clear()


func _wait_idle(limit := 120) -> void:
	var p = main.player
	for i in limit:
		await tree.physics_frame
		if p.attack_cd <= 0.0 and p.pending.is_empty() and p.arsenal._events.is_empty() and not p.arsenal._plunging:
			break
	main.clear_slowmo()


func run(t: SceneTree, m, c: Callable) -> bool:
	tree = t
	main = m
	check = c
	var p = main.player
	var ok := true
	main.time_of_day = 0.9 # night: vampires don't burn
	_clear()
	_reset_player()
	var rec := func(_e, d): hits.append(d)
	p.hit_enemy.connect(rec)
	var lib: AnimationLibrary = p.mod_anim.lib if p.mod_anim != null else null

	# ---- the data: 8+ types, each with blades at every rarity, an art, a chain, a mount, clips
	ok = _ok("the Arsenal has at least 8 weapon types (%d)" % ArsenalData.TYPES.size(), ArsenalData.TYPES.size() >= 8) and ok
	var clips_ok := true
	var missing: Array = []
	for tn in ArsenalData.TYPES:
		var td: Dictionary = ArsenalData.TYPES[tn]
		var moves: Array = SolMoves.chain(td.chain).duplicate()
		moves.append(td.heavy)
		moves.append(ArsenalMoves.ARTS[td.art].move)
		for r in td.routes.values():
			moves.append(r)
		for mv in moves:
			if not SolMoves.has_move(mv) or (lib != null and not lib.has_animation(SolMoves.move(mv).clip)):
				clips_ok = false
				missing.append("%s:%s" % [tn, mv])
		var SolSheath = load("res://scripts/sol_sheath.gd")
		var inst := ItemDB.make(_item_for(tn))
		if _item_for(tn) == "" or not SolSheath.MOUNTS.has(WeaponVisual.mount_name(inst)) or SolSheath.mount_name_for(inst) != WeaponVisual.mount_name(inst):
			clips_ok = false
			missing.append(tn + ":item/mount")
	ok = _ok("every type has blades, a mount and real clips for its moves %s" % str(missing), clips_ok) and ok
	ok = _ok("the three Arsenal clips are in Sol's library", lib != null and lib.has_animation("hammer") and lib.has_animation("axe_spin") and lib.has_animation("dspin")) and ok

	# ---- each weapon equips and its moveset plays and lands
	for tn in ArsenalData.TYPES:
		_reset_player()
		var id := _item_for(tn)
		_equip(id)
		await _frames(2)
		var wv: Node3D = p.weapon_visual
		var dual_ok: bool = not ArsenalData.TYPES[tn].get("dual", false) or (p.arsenal._left_visual != null and p.arsenal._left_visual.is_inside_tree())
		var e = await _dummy(p.global_position + Vector3(0, 0.4, 1.6))
		hits.clear()
		var chain: Array = SolMoves.chain(ArsenalData.TYPES[tn].chain)
		var played: Array = []
		for i in chain.size():
			p.attack_cd = 0.0
			p._attack()
			played.append(p.move_name)
			e.global_position = p.global_position + Vector3(0, 0.4, 1.6)
			for f in 40:
				await tree.physics_frame
				if p.pending.is_empty() and p.arsenal._events.is_empty():
					break
			main.clear_slowmo()
			p.combo_t = 0.5
		ok = _ok("%s (%s) equips and plays its chain %s, %d hits" % [tn, id, str(played), hits.size()],
			wv != null and is_instance_valid(wv) and dual_ok and played == chain and hits.size() >= chain.size()) and ok
		# its held heavy
		await _wait_idle()
		p.combo = 0
		p.combo_t = 0.0
		p.stamina = p.stamina_max
		p.exhausted = false
		hits.clear()
		e.global_position = p.global_position + Vector3(0, 0.4, 1.6)
		Input.action_press("attack")
		var heavy_seen := false
		for f in 150:
			await tree.physics_frame
			heavy_seen = heavy_seen or p.move_name == ArsenalData.TYPES[tn].heavy
			if OS.has_environment("ARS_DEBUG") and f % 6 == 0:
				print("  dbg %s f%d move %s hold %.2f st %.0f exh %s d %.2f stag %s pend %s cd %.2f" % [tn, f, p.move_name, p.hold_t, p.stamina, p.exhausted, e.global_position.distance_to(p.global_position), e.staggered, str(p.pending.keys()), p.attack_cd])
			if heavy_seen and p.pending.is_empty() and p.arsenal._events.is_empty():
				break
		Input.action_release("attack")
		main.clear_slowmo()
		ok = _ok("%s heavy (%s) lands (%d hits)" % [tn, ArsenalData.TYPES[tn].heavy, hits.size()], heavy_seen and hits.size() >= 1) and ok
		await _wait_idle()
		_clear()

	# ---- each Weapon Art fires and hits
	for tn in ArsenalData.TYPES:
		_reset_player()
		_equip(_item_for(tn))
		await _frames(2)
		var art: Dictionary = ArsenalMoves.ARTS[ArsenalData.TYPES[tn].art]
		var dist: float = {"wave": 7.0, "lash": 6.5, "rush": 3.5, "flurry": 3.0, "cleave": 4.0}.get(art.fx, 2.0)
		var e = await _dummy(p.global_position + Vector3(0, 0.4, dist))
		hits.clear()
		var n0: int = p.arsenal.art_count
		var hp0: float = p.hp
		var fired: bool = p.arsenal.art_pressed()
		for f in 150:
			await tree.physics_frame
			if not hits.is_empty() and p.arsenal._events.is_empty() and p.arsenal._waves.is_empty():
				break
		main.clear_slowmo()
		ok = _ok("%s art %s fires and hits (%d hits, cooldown %.1f s, blood %d)" % [tn, art.name, hits.size(), p.arsenal.art_cd_t, roundi(hp0 - p.hp)],
			fired and p.arsenal.art_count == n0 + 1 and hits.size() >= 1 and p.arsenal.art_cd_t > 0.0 and absf((hp0 - p.hp) - float(art.blood)) < 0.5) and ok
		ok = _ok("%s art is on cooldown after use" % tn, not p.arsenal.art_pressed()) and ok
		await _wait_idle()
		_clear()

	# ---- the special combo routes (Silver Longsword)
	_reset_player()
	_equip("marrow_silver")
	await _frames(2)
	var rc: Dictionary = p.arsenal.route_count
	# L, L, HOLD -> the chain finisher
	var e = await _dummy(p.global_position + Vector3(0, 0.4, 1.6))
	hits.clear()
	p._attack()
	await _frames(14)
	p.attack_cd = 0.0
	p._attack()
	await _frames(14)
	p.attack_cd = 0.0
	Input.action_press("attack")
	for f in 70:
		await tree.physics_frame
		if rc.has("ls_llh") and p.arsenal._events.is_empty():
			break
	Input.action_release("attack")
	main.clear_slowmo()
	ok = _ok("tap, tap, HOLD is the chain finisher (Silver Lance, hits %d)" % hits.size(), rc.has("ls_llh") and hits.size() >= 3) and ok
	await _wait_idle()
	# a heavy after a dodge: dash, then hold attack through the thrust
	_reset_player()
	e.global_position = p.global_position + Vector3(0, 0.4, 2.0)
	hits.clear()
	p.since_dash = 0.2
	Input.action_press("attack")
	for f in 70:
		await tree.physics_frame
		if rc.has("ls_dodge") and p.arsenal._events.is_empty():
			break
	Input.action_release("attack")
	main.clear_slowmo()
	ok = _ok("dash, then hold attack: the thrust then the dodge heavy (hits %d)" % hits.size(), rc.has("ls_dodge") and hits.size() >= 2) and ok
	await _wait_idle()
	# the sprint heavy: sprint, then hold attack through the running slash
	_reset_player()
	_clear()
	e = await _dummy(p.global_position + Vector3(0, 0.4, 9.0))
	hits.clear()
	p.cam_yaw = PI # forward input runs along +Z
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_press("attack")
	for f in 60:
		await tree.physics_frame
		if rc.has("ls_sprint"):
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	for f in 60:
		await tree.physics_frame
		if rc.has("ls_sprint") and p.arsenal._events.is_empty():
			break
	Input.action_release("attack")
	main.clear_slowmo()
	ok = _ok("sprint, then hold attack: the sprint heavy (Leaping Cut)", rc.has("ls_sprint")) and ok
	p.cam_yaw = 0.0
	await _wait_idle()
	# the jump cut, and holding it in the air: the plunge, which bursts on landing
	_reset_player()
	_clear()
	e = await _dummy(p.global_position + Vector3(0, 0.4, 1.4))
	hits.clear()
	p.global_position += Vector3(0, 3.5, 0)
	p.velocity.y = 4.0
	await _frames(3)
	Input.action_press("attack")
	await _frames(2)
	var jumped: bool = rc.has("jump_cut")
	for f in 120:
		await tree.physics_frame
		if rc.has("plunge") and not p.arsenal._plunging:
			break
	Input.action_release("attack")
	main.clear_slowmo()
	ok = _ok("attack in the air is the jump cut, holding it plunges (landed %s, hits %d)" % [p.is_on_floor(), hits.size()], jumped and rc.has("plunge") and not p.arsenal._plunging and hits.size() >= 1) and ok
	await _wait_idle()
	# the riposte: attack right after a parry
	_reset_player()
	_clear()
	e = await _dummy(p.global_position + Vector3(0, 0.4, 2.0))
	hits.clear()
	p.parried.emit(e)
	p._attack_pressed()
	var rip: bool = p.move_name == "riposte"
	await _wait_idle()
	ok = _ok("attack after a parry is the riposte (hits %s)" % str(hits), rip and hits.size() >= 1 and hits[0] > 40.0) and ok
	# the blood-chain: the Weapon Art button right after the third hit spends blood for a finisher
	_reset_player()
	e.global_position = p.global_position + Vector3(0, 0.4, 1.6)
	hits.clear()
	for i in 3:
		p.attack_cd = 0.0
		p._attack()
		await _frames(12)
	var hp0: float = p.hp
	var window: bool = p.arsenal.chain_t > 0.0
	p.attack_cd = 0.0
	var chained: bool = p.arsenal.art_pressed()
	await _wait_idle()
	ok = _ok("the Weapon Art after the third hit is the Blood Chain (window %s, blood %d, hits %d)" % [window, roundi(hp0 - p.hp), hits.size()],
		window and chained and rc.has("blood_chain") and absf(hp0 - p.hp - ArsenalMoves.BLOOD_CHAIN_COST) < 0.5 and hits.size() >= 4) and ok
	_clear()

	# ---- Bleed and stagger
	_reset_player()
	_equip(_item_for("katana"))
	await _frames(2)
	e = await _dummy(p.global_position + Vector3(0, 0.4, 1.6))
	e.max_hp = 400.0
	e.hp = 400.0
	p.arsenal._add_bleed(e, 120.0)
	ok = _ok("Bleed bursts into a Hemorrhage (hp %.0f / 400)" % e.hp, e.hp <= 400.0 - 59.0 and float(e.get_meta("bleed", 0.0)) == 0.0) and ok
	_equip(_item_for("hammer"))
	await _frames(2)
	var w2 = await _dummy(p.global_position + Vector3(1.0, 0.4, 1.6), 1)
	w2.max_hp = 400.0
	w2.hp = 400.0
	for i in 6:
		if w2.staggered:
			break
		p.hit_enemy.emit(w2, 30.0)
	ok = _ok("the war hammer breaks a werewolf's stance (staggered %s)" % w2.staggered, w2.staggered) and ok
	_clear()

	# ---- touch: the ART button sends weapon_art
	var touch = tree.root.get_node_or_null("Touch")
	var has_btn := false
	if touch != null:
		for b in touch.buttons:
			if b.id == "art" and "weapon_art" in b.actions:
				has_btn = true
		touch._send(["weapon_art"], true)
	Input.flush_buffered_events()
	var pressed := Input.is_action_pressed("weapon_art")
	if touch != null:
		touch._send(["weapon_art"], false)
		Input.flush_buffered_events()
	p.arsenal.art_buffer_t = 0.0
	ok = _ok("the ART touch button presses the Weapon Art", has_btn and pressed) and ok
	var art_keys: Array = InputMap.action_get_events("weapon_art").map(func(ev): return ev.as_text())
	var fwd_dpad: bool = InputMap.action_get_events("move_forward").any(func(ev): return ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_DPAD_UP)
	ok = _ok("Weapon Art is on V, mouse side button 2 and D-pad Up, clear of the other bindings %s" % str(art_keys), art_keys.size() == 3 and not fwd_dpad and not InputMap.action_get_events("parry").any(func(ev): return ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_XBUTTON2)) and ok

	# ---- the rack, the Rites, the drops
	var Meta = load("res://scripts/hunt/hunt_meta.gd")
	var saved_path: String = Meta.path
	Meta.path = "user://smoke_arsenal_meta.json"
	Meta.reset_meta()
	Meta.data.sunmarks = 200
	var bought: bool = Meta.buy_blade("ronin_katana")
	ok = _ok("Nia's rack sells a katana and it is carried in", bought and Meta.start_blade().id == "ronin_katana" and Meta.data.sunmarks == 150) and ok
	Meta.reset_meta()
	Meta.path = saved_path
	if FileAccess.file_exists("user://smoke_arsenal_meta.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://smoke_arsenal_meta.json"))
	var Rites = load("res://scripts/hunt/blood_rite.gd")
	var rng := RandomNumberGenerator.new()
	var suits := true
	for i in 20:
		rng.seed = i
		var offer: Array = Rites.roll([], 3, rng, "hammer")
		suits = suits and offer.any(func(id): return Rites.resonates(id, "hammer"))
	ok = _ok("Blood Rite offers always include one that suits the blade", suits) and ok
	var blades := 0
	rng.seed = 7
	for i in 400:
		var inst: Dictionary = ItemDB.random_item(rng, true, true, 0.0)
		if ItemDB.kind_of(inst) == "blade" and ArsenalData.type_of_family(ItemDB.get_def(inst.id).family) in ["katana", "daggers", "greatsword", "halberd", "scythe", "hammer", "whip"]:
			blades += 1
	ok = _ok("the new weapon types drop as loot (%d in 400 rolls)" % blades, blades >= 20) and ok

	p.hit_enemy.disconnect(rec)
	_equip("marrow_silver")
	_reset_player()
	_clear()
	return ok
