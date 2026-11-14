extends Node3D
## Loot in the world: Tithe motes, dropped items with rarity light beams,
## cold coffins / smuggler crates (caches) and the Tithe lost at death.
## Beams and motes are unshaded additive meshes with shared materials, no lights.

const ItemDB = preload("res://scripts/items/item_db.gd")
const U = preload("res://scripts/util.gd")

const PICK_RANGE := 2.0
const CACHE_RANGE := 2.3
const LAIR_RANGE := 3.5
const MAGNET := 6.0
const MOTE_LIFE := 120.0
const CACHE_COUNT := 20
const CACHE_SEED := 6131
## Chance a kill drops an item, by enemy (night and luck raise it).
const DROP_CHANCE := {"vampire": 0.12, "civilian": 0.1, "werewolf": 0.25, "moon_wolf": 0.4}

var main
var rng := RandomNumberGenerator.new()
var motes: Array = [] # [{node, value, vel, t, home}]
var ground_items: Array = [] # [{node, inst, spin, base_y}]
var caches: Array = [] # [{node, lid, glow, pos, opened, type}]
var death_marker: Node3D
var prompt_text := ""
var was_near_lair := true
var clock := 0.0

static var _mote_mesh: Mesh
static var _mote_mat: StandardMaterial3D
static var _beam_mesh: Mesh
static var _core_mesh: Mesh
static var _beam_mats := {}
static var _disc_mesh: Mesh
static var _wood: StandardMaterial3D
static var _wood_dark: StandardMaterial3D
static var _silver: StandardMaterial3D


func _ready() -> void:
	rng.randomize()
	_shared_resources()
	_build_caches()
	_refresh_death_marker()


# ---------------------------------------------------------------- shared look
static func _shared_resources() -> void:
	if _mote_mesh != null:
		return
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	s.radial_segments = 6
	s.rings = 3
	_mote_mesh = s
	_mote_mat = StandardMaterial3D.new()
	_mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mote_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mote_mat.albedo_color = Color(1.0, 0.18, 0.12)
	var b := CylinderMesh.new()
	b.top_radius = 0.2
	b.bottom_radius = 0.2
	b.height = 7.0
	b.radial_segments = 10
	b.rings = 1
	b.cap_top = false
	b.cap_bottom = false
	_beam_mesh = b
	var c := CylinderMesh.new()
	c.top_radius = 0.035
	c.bottom_radius = 0.035
	c.height = 6.0
	c.radial_segments = 6
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	_core_mesh = c
	var d := CylinderMesh.new()
	d.top_radius = 0.6
	d.bottom_radius = 0.6
	d.height = 0.01
	d.radial_segments = 16
	d.rings = 1
	_disc_mesh = d
	_wood = U.mat(Color(0.16, 0.07, 0.05), 0.65)
	_wood_dark = U.mat(Color(0.05, 0.025, 0.02), 0.5)
	_silver = U.mat(Color(0.8, 0.8, 0.85), 0.25, 1.0)


## Beam material for a colour: additive, fading toward the top (gradient on V).
static func beam_mat(c: Color, strength := 1.0) -> StandardMaterial3D:
	var key := "%s_%.2f" % [c.to_html(), strength]
	if _beam_mats.has(key):
		return _beam_mats[key]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 1.0))
	g.add_point(0.75, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4
	tex.height = 64
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = tex
	m.texture_repeat = false # no wrap-around rim at the faded top
	m.albedo_color = Color(c.r * strength, c.g * strength, c.b * strength, 0.65)
	_beam_mats[key] = m
	return m


func _beam(parent: Node3D, c: Color, core: Color, legendary := false) -> void:
	var outer := U.part(parent, _beam_mesh, beam_mat(c, 1.0), Vector3(0, 3.5, 0))
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner := U.part(parent, _core_mesh, beam_mat(core, 0.9), Vector3(0, 3.0, 0))
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if legendary: # Eclipse: purple sheath, gold core, taller
		outer.scale = Vector3(1.4, 1.5, 1.4)
		outer.position.y = 5.25
		inner.scale = Vector3(1.2, 1.6, 1.2)
		inner.position.y = 4.8
	var disc := U.part(parent, _disc_mesh, beam_mat(c, 0.6), Vector3(0, 0.06, 0))
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- kills
func _enemy_key(e: Node) -> String:
	if e.kind == 0:
		return "vampire"
	if not e.transformed:
		return "civilian"
	return "moon_wolf" if e.max_hp >= 150.0 else "werewolf"


func on_enemy_killed(e: Node, drained: bool) -> void:
	var prog = main.progression
	var pos: Vector3 = e.global_position
	spawn_motes(pos + Vector3(0, 1.0, 0), prog.kill_value(e, drained))
	var chance: float = DROP_CHANCE[_enemy_key(e)]
	if not main.is_day():
		chance *= 1.25
	chance *= 1.0 + prog.stat("loot_luck")
	if rng.randf() < chance:
		var inst := ItemDB.random_item(rng, not main.is_day(), main.is_full_moon(), prog.stat("loot_luck"))
		spawn_item(inst, pos + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)))
	prog.on_kill(e)


# ---------------------------------------------------------------- motes
func spawn_motes(pos: Vector3, amount: int) -> void:
	if amount <= 0:
		return
	var n := clampi(amount / 4, 3, 10)
	var each := amount / n
	var extra := amount - each * n
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = _mote_mesh
		mi.material_override = _mote_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = pos
		var a := rng.randf() * TAU
		var v := Vector3(cos(a) * rng.randf_range(1.5, 3.5), rng.randf_range(2.5, 4.5), sin(a) * rng.randf_range(1.5, 3.5))
		motes.append({"node": mi, "value": each + (extra if i == 0 else 0), "vel": v, "t": 0.0, "home": false, "phase": rng.randf() * TAU})


func _update_motes(delta: float, p) -> void:
	var magnet := MAGNET * (2.0 if main.progression.has_flag("magnet") else 1.0)
	var target: Vector3 = p.global_position + Vector3(0, 1.1, 0) if p != null else Vector3.ZERO
	var gained := 0
	for i in range(motes.size() - 1, -1, -1):
		var m: Dictionary = motes[i]
		m.t += delta
		var node: MeshInstance3D = m.node
		var pos := node.global_position
		if p != null and not p.dead and (m.home or (m.t > 0.45 and pos.distance_to(target) < magnet)):
			m.home = true
			var to := target - pos
			var spd: float = 6.0 + m.t * 6.0
			m.vel = m.vel.lerp(to.normalized() * spd, minf(8.0 * delta, 1.0))
			if to.length() < 0.55:
				gained += m.value
				node.queue_free()
				motes.remove_at(i)
				continue
		else:
			# scatter, then hover and bob a little above the street
			m.vel.y -= 9.0 * delta
			m.vel.x *= 1.0 - minf(3.0 * delta, 1.0)
			m.vel.z *= 1.0 - minf(3.0 * delta, 1.0)
			var floor_y := 0.7 + sin(clock * 3.0 + m.phase) * 0.12
			if pos.y < floor_y and m.vel.y < 0.0:
				m.vel.y = (floor_y - pos.y) * 4.0
		node.global_position = pos + m.vel * delta
		if m.t > MOTE_LIFE:
			node.queue_free()
			motes.remove_at(i)
	if gained > 0:
		main.progression.add_tithe(gained)
		Audio.play("tithe_collect", -8.0, 0.15) # AUDIO HOOK


# ---------------------------------------------------------------- ground items
func spawn_item(inst: Dictionary, pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "Drop_" + str(inst.id)
	add_child(root)
	root.global_position = Vector3(pos.x, 0.1, pos.z)
	var r := int(inst.get("r", 0))
	_beam(root, ItemDB.RARITY_COLORS[r], ItemDB.RARITY_ACCENT[r] if r == ItemDB.LEGENDARY else ItemDB.RARITY_COLORS[r], r == ItemDB.LEGENDARY)
	var spin := Node3D.new()
	spin.position.y = 0.75
	root.add_child(spin)
	var glow := U.glow(ItemDB.RARITY_COLORS[r], 2.5)
	var d := ItemDB.get_def(inst.id)
	match d.kind:
		"blade":
			U.part(spin, U.box(Vector3(0.03, 0.07, 0.8)), glow, Vector3(0, 0, 0.15), Vector3(0.6, 0, 0))
			U.part(spin, U.box(Vector3(0.18, 0.04, 0.04)), _wood_dark, Vector3(0, -0.1, -0.18), Vector3(0.6, 0, 0))
		"charm":
			var t := TorusMesh.new()
			t.inner_radius = 0.09
			t.outer_radius = 0.14
			U.part(spin, t, glow, Vector3.ZERO, Vector3(PI / 2.0, 0, 0))
			U.part(spin, U.sphere(0.06), glow, Vector3(0, -0.17, 0))
		"vial":
			U.part(spin, U.cyl(0.05, 0.06, 0.22), U.glow(Color(0.8, 0.02, 0.05), 3.0), Vector3.ZERO)
			U.part(spin, U.cyl(0.03, 0.03, 0.05), _wood, Vector3(0, 0.13, 0))
		"flare":
			U.part(spin, U.cyl(0.04, 0.04, 0.3), U.glow(Color(0.7, 0.5, 1.0), 3.0), Vector3.ZERO, Vector3(0, 0, 0.4))
	for mi in spin.get_children():
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var entry := {"node": root, "inst": inst.duplicate(), "spin": spin, "phase": rng.randf() * TAU}
	ground_items.append(entry)
	Audio.on_loot_dropped(r, root.global_position) # AUDIO HOOK
	return entry


func _remove_item(entry: Dictionary) -> void:
	ground_items.erase(entry)
	if is_instance_valid(entry.node):
		entry.node.queue_free()


## Drop an item from the coat in front of Sol.
func drop_from_player(inst: Dictionary) -> void:
	if inst.is_empty():
		return
	var p = main.player
	var a := rng.randf_range(-0.8, 0.8)
	var fwd: Vector3 = p._forward()
	spawn_item(inst, p.global_position + fwd.rotated(Vector3.UP, a) * 1.4)


func nearest_item(pos: Vector3, max_d: float = PICK_RANGE):
	var best = null
	var bd := max_d
	for g in ground_items:
		var d: float = Vector2(g.node.global_position.x - pos.x, g.node.global_position.z - pos.z).length()
		if d < bd:
			bd = d
			best = g
	return best


func pick_up(entry: Dictionary) -> bool:
	if not main.inventory.add(entry.inst):
		main.hud.popup("YOUR COAT IS FULL\n[Tab] to drop something")
		return false
	var inst: Dictionary = entry.inst
	var label := ItemDB.display_name(inst) + ("  x%d" % inst.n if inst.get("n", 1) > 1 else "")
	main.hud.popup("%s  ·  %s" % [label.to_upper(), ItemDB.RARITY_NAMES[inst.r].to_upper()])
	Audio.on_loot_picked(int(inst.r)) # AUDIO HOOK
	_remove_item(entry)
	return true


# ---------------------------------------------------------------- caches
## Cold coffins and smuggler crates on the sidewalks (never in a road), plus two in the plaza.
func cache_spots() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = CACHE_SEED
	var blocks: Array = []
	for i in range(-4, 4):
		for j in range(-4, 4):
			var cx := i * 20.0 + 10.0
			var cz := j * 20.0 + 10.0
			if absf(cx) < 20.0 and absf(cz) < 20.0:
				continue
			if cz == -30.0 and absf(cx) == 10.0:
				continue # cathedral
			blocks.append(Vector2(cx, cz))
	# shuffle deterministically
	for k in range(blocks.size() - 1, 0, -1):
		var s := r.randi_range(0, k)
		var tmp = blocks[k]
		blocks[k] = blocks[s]
		blocks[s] = tmp
	var out: Array = [{"pos": Vector3(-14.0, 0.1, -3.0), "yaw": PI * 0.5}, {"pos": Vector3(3.5, 0.1, 14.2), "yaw": 0.0}]
	for b in blocks:
		if out.size() >= CACHE_COUNT:
			break
		var side := r.randi_range(0, 3)
		var n: Vector3 = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)][side]
		var t := Vector3.UP.cross(n)
		# sidewalk band: building line at 4 m from the block centre, kerb at 6.25 m
		var p: Vector3 = Vector3(b.x, 0.1, b.y) + n * 4.9 + t * r.randf_range(-3.5, 3.5)
		out.append({"pos": p, "yaw": atan2(t.x, t.z)})
	return out


func _build_caches() -> void:
	var spots := cache_spots()
	for i in spots.size():
		var s: Dictionary = spots[i]
		var root := Node3D.new()
		root.name = "Cache_%d" % i
		add_child(root)
		root.position = s.pos
		root.rotation.y = s.yaw
		var coffin := absf(s.pos.x) < 40.0 or i % 2 == 0 # coffins in the Quarter, crates out by the docks
		var lid: Node3D = Node3D.new()
		root.add_child(lid)
		if coffin:
			U.part(root, U.box(Vector3(0.62, 0.42, 1.85)), _wood, Vector3(0, 0.21, 0))
			lid.position = Vector3(0.31, 0.44, 0)
			U.part(lid, U.box(Vector3(0.7, 0.08, 1.95)), _wood_dark, Vector3(-0.31, 0, 0))
			U.part(lid, U.box(Vector3(0.08, 0.02, 0.9)), _silver, Vector3(-0.31, 0.05, 0.25))
			U.part(lid, U.box(Vector3(0.42, 0.02, 0.08)), _silver, Vector3(-0.31, 0.05, 0.45))
		else:
			U.part(root, U.box(Vector3(0.9, 0.7, 0.9)), _wood, Vector3(0, 0.35, 0))
			for y in [0.12, 0.58]:
				U.part(root, U.box(Vector3(0.94, 0.07, 0.94)), _wood_dark, Vector3(0, y, 0))
			lid.position = Vector3(0.45, 0.72, 0)
			U.part(lid, U.box(Vector3(0.94, 0.06, 0.94)), _wood_dark, Vector3(-0.45, 0, 0))
		var glow := MeshInstance3D.new()
		glow.mesh = _mote_mesh
		glow.material_override = _mote_mat
		glow.position = Vector3(0, 1.2, 0)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(glow)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if mi != glow:
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		caches.append({"node": root, "lid": lid, "glow": glow, "pos": s.pos, "opened": false, "coffin": coffin})


func nearest_cache(pos: Vector3, max_d: float = CACHE_RANGE):
	var best = null
	var bd := max_d
	for c in caches:
		if c.opened:
			continue
		var d: float = Vector2(c.pos.x - pos.x, c.pos.z - pos.z).length()
		if d < bd:
			bd = d
			best = c
	return best


func open_cache(c: Dictionary) -> void:
	if c.opened:
		return
	c.opened = true
	c.glow.visible = false
	var tw := create_tween()
	tw.tween_property(c.lid, "rotation:z", -1.9, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var prog = main.progression
	var luck: float = prog.stat("loot_luck") + 0.25
	var night: bool = not main.is_day()
	spawn_motes(c.pos + Vector3(0, 0.8, 0), int(round(rng.randi_range(15, 35) * (1.0 + prog.stat("tithe_mult")) * (1.4 if night else 1.0))))
	var n := 1 + (1 if rng.randf() < 0.3 + prog.stat("loot_luck") * 0.5 else 0)
	for k in n:
		var side: Vector3 = c.node.global_transform.basis.x * (1.0 if k == 0 else -1.0)
		spawn_item(ItemDB.random_item(rng, night, main.is_full_moon(), luck), c.pos + side * 1.1)
	main.hud.popup("THE " + ("COFFIN" if c.coffin else "CRATE") + " GIVES UP ITS SECRETS")
	Audio.play("loot_pickup", 0.0, 0.0) # AUDIO HOOK


## Sunrise: every cache is sealed and stocked again.
func respawn_caches() -> void:
	for c in caches:
		c.opened = false
		c.lid.rotation.z = 0.0
		c.glow.visible = true


# ---------------------------------------------------------------- death drop
func _refresh_death_marker() -> void:
	if death_marker != null:
		death_marker.queue_free()
		death_marker = null
	var dd: Dictionary = main.progression.death_drop
	if dd.is_empty():
		return
	death_marker = Node3D.new()
	death_marker.name = "LostTithe"
	add_child(death_marker)
	var pp: Array = dd.pos
	death_marker.global_position = Vector3(pp[0], 0.1, pp[2])
	_beam(death_marker, Color(1.0, 0.08, 0.1), Color(1.0, 0.75, 0.3), true)
	var l := Label3D.new()
	l.text = "LOST TITHE  %d" % int(dd.amount)
	l.font_size = 48
	l.outline_size = 10
	l.modulate = Color(1.0, 0.35, 0.3)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, 2.4, 0)
	death_marker.add_child(l)
	var orb := U.part(death_marker, U.sphere(0.22), U.glow(Color(1, 0.1, 0.1), 4.0), Vector3(0, 1.0, 0))
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _check_death_drop(p) -> void:
	if death_marker == null:
		return
	var d := Vector2(death_marker.global_position.x - p.global_position.x, death_marker.global_position.z - p.global_position.z).length()
	if d < 1.8:
		var n: int = main.progression.recover_death_drop()
		main.hud.popup("TITHE RECOVERED  +%d" % n)
		_refresh_death_marker()


# ---------------------------------------------------------------- per frame
func _physics_process(delta: float) -> void:
	clock += delta
	var p = main.player
	_update_motes(delta, p)
	for g in ground_items:
		g.spin.rotation.y += delta * 1.6
		g.spin.position.y = 0.75 + sin(clock * 2.2 + g.phase) * 0.12
	for c in caches:
		if not c.opened:
			c.glow.position.y = 1.2 + sin(clock * 2.0 + c.pos.x) * 0.1
	prompt_text = ""
	if p == null or p.dead or not main.started:
		return
	_check_death_drop(p)
	var near_lair: bool = p.global_position.distance_to(main.lair_pos) < LAIR_RANGE
	if near_lair and not was_near_lair:
		main.progression.save() # returning to the lair keeps your progress safe
	was_near_lair = near_lair
	if p.bite_ready:
		return # the bite owns the button while a staggered enemy is in reach
	var pad: bool = main.hud.using_pad
	var key := "[Y]" if pad else "[E]"
	var pressed := Input.is_action_just_pressed("interact")
	var item = nearest_item(p.global_position)
	if item != null:
		var inst: Dictionary = item.inst
		prompt_text = "%s  TAKE  %s  (%s)" % [key, ItemDB.display_name(inst).to_upper(), ItemDB.RARITY_NAMES[inst.r]]
		if pressed:
			pick_up(item)
		return
	var cache = nearest_cache(p.global_position)
	if cache != null:
		prompt_text = "%s  OPEN THE %s" % [key, "COFFIN" if cache.coffin else "CRATE"]
		if pressed:
			open_cache(cache)
		return
	if near_lair:
		var prog = main.progression
		if prog.level >= prog.MAX_LEVEL:
			prompt_text = "%s  KEEP VIGIL  (highest rank)" % key
		else:
			prompt_text = "%s  KEEP VIGIL  ·  Rank %d → %d  ·  %d Tithe" % [key, prog.level, prog.level + 1, prog.next_cost()]
		if pressed:
			main.open_levelup()
