extends RefCounted
## LAIR: what turns the menu's lair set (menu/lair_set.gd, concept 13) into Sol's walkable basement.
## The menu frames only the lab bay; the hub adds, behind where the menu camera stands:
##   * the front bay: the flagstone platform carried forward, the front wall, piers and ribbed vault
##   * the ARMOURY ALCOVE (front right): a long blade board with every blade Sol owns hung on it
##     (refreshed when he buys one) and a weapons trunk
##   * the WARDROBE CORNER (front left): an open armoire with his owned coats hanging in it, a coat
##     stand, a rug and a tall standing mirror
##   * candles (the set's candle / halo MultiMeshes), one more warm light over the front bay
##   * colliders for every wall, pier and piece of furniture, a ramped platform edge, the tunnel gate
##   * static batching: every plain opaque MeshInstance3D of the set is merged per material into one
##     mesh, which takes the set from several hundred draws to well under the web budget
## Station anchors (STATIONS) are where lair_hub.gd puts its interaction prompts and camera framings.

const U = preload("res://scripts/util.gd")
const ItemDB = preload("res://scripts/items/item_db.gd")
const WeaponVisual = preload("res://scripts/items/weapon_visual.gd")
const Meta = preload("res://scripts/hunt/hunt_meta.gd")
const Wardrobe = preload("res://scripts/items/wardrobe_data.gd")

const FRONT_Z := 4.4 # the front wall's centre line
const PLAT_FRONT := 3.8 # the platform's front edge
const LEFT_BOUND := -4.6 # an unseen wall: the dark left bay beyond stays out of reach
const RACK_POS := Vector3(4.25, 0.12, 1.9) # the armoury's blade board (faces -X)
const ARMOIRE_POS := Vector3(-0.15, 0.12, 3.62)
const MIRROR_POS := Vector3(-0.62, 0.12, 1.55)
## Station anchors: where Sol stands to use it (stand), what the prompt reads, how close he must be.
const STATIONS := {
	"rack": {"pos": Vector3(3.35, 0.12, 1.9), "radius": 1.5, "label": "WEAPON RACK", "verb": "choose your blade"},
	"bench": {"pos": Vector3(1.0, 0.12, -2.25), "radius": 1.5, "label": "WORKBENCH", "verb": "charms and contacts"},
	"mirror": {"pos": Vector3(0.35, 0.12, 2.05), "radius": 1.4, "label": "WARDROBE", "verb": "change clothes"},
	"table": {"pos": Vector3(0.55, 0.12, -5.75), "radius": 1.5, "label": "MAP TABLE", "verb": "tonight's briefing"},
	"gate": {"pos": Vector3(-1.9, -0.02, -7.4), "radius": 1.6, "label": "SUBWAY GATE", "verb": "begin the Hunt"},
	"nia": {"pos": Vector3(2.45, 0.12, -4.05), "radius": 1.7, "label": "NIA", "verb": "talk"},
}

var set_ # menu/lair_set.gd
var rack_root: Node3D # blades on the board (rebuilt by refresh_rack)
var armoire_root: Node3D # owned coats hanging in the armoire (refresh_wardrobe)
var colliders: StaticBody3D
var mirror: MeshInstance3D
var batched_from := 0 # MeshInstances merged
var batched_to := 0 # merged meshes made


# ---------------------------------------------------------------- build (before Nia and the lights)
func build(s) -> void:
	set_ = s
	set_.candle_xf.clear()
	set_.puddle_glows.clear()
	_front_bay()
	_armoury()
	_wardrobe_corner()
	set_._flush_candles() # this bay's candles and their halos (the set flushed its own already)
	set_._puddles()


## After Nia and the lights: the front bay's light, colliders, then batching.
func finish(s) -> void:
	set_ = s
	# the front bay: one warm candle light over the rug, and (above the lowest light setting) a lantern
	# in the armoury alcove; everything else there glows through emission and halos
	_light(Vector3(1.0, 2.4, 2.0), 3.4, 7.5)
	if Settings.light_quality >= 1:
		_light(Vector3(2.9, 2.6, 2.0), 1.1, 4.0)
	_colliders()
	batch()
	refresh_rack()
	refresh_wardrobe()


func _light(pos: Vector3, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = Color(1.0, 0.62, 0.34)
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.1
	set_.add_child(l)
	set_.flicker_lights.append([l, energy, pos.x * 3.1])


# ---------------------------------------------------------------- the front bay
func _front_bay() -> void:
	var s = set_
	# the flagstone platform carried forward, with its kerbs
	s._box(s, Vector3(5.2, 0.24, 5.4), Vector3(1.7, 0.0, 1.1), s.m_floor)
	s._box(s, Vector3(5.3, 0.07, 0.14), Vector3(1.7, 0.1, PLAT_FRONT), s.m_stone)
	s._box(s, Vector3(0.14, 0.07, 5.4), Vector3(-0.9, 0.1, 1.1), s.m_stone)
	# walls: the right wall carried on, the front wall
	s._box(s, Vector3(0.6, 9, 6.0), Vector3(4.6, 4.5, 3.5), s.m_stone_dark)
	s._box(s, Vector3(14.0, 9, 0.6), Vector3(-1.6, 4.5, FRONT_Z), s.m_stone_dark)
	# piers and the vault over the bay
	s._pillar(Vector3(-2.7, 0, 3.75), s.VAULT_SPRING - 0.15)
	for z in [0.8, 3.95]:
		s._box(s, Vector3(0.4, s.VAULT_SPRING, 0.6), Vector3(4.2, s.VAULT_SPRING * 0.5, z), s.m_vault)
	s._arch(Vector3(0.95, 0, 0.8), 7.3, s.VAULT_SPRING, Vector3.RIGHT, 0.3, 0.42, s.m_vault, 12, 0.6)
	s._arch(Vector3(0.95, 0, 3.95), 7.3, s.VAULT_SPRING, Vector3.RIGHT, 0.3, 0.42, s.m_vault, 12, 0.6)
	s._arch(Vector3(-2.7, 0, 2.3), 3.0, s.VAULT_SPRING, Vector3.FORWARD, 0.28, 0.4, s.m_vault, 8, 0.75)
	var c := Vector3(0.95, 0, 2.35)
	var span := Vector2(7.3, 3.15).length()
	s._arch(c, span, s.VAULT_SPRING, Vector3(7.3, 0, 3.15).normalized(), 0.18, 0.26, s.m_vault, 12, 0.56)
	s._arch(c, span, s.VAULT_SPRING, Vector3(7.3, 0, -3.15).normalized(), 0.18, 0.26, s.m_vault, 12, 0.56)
	# a carved wall of names along the front wall, candles at its foot (concept 08)
	var names_ := U.mat(Color(0.3, 0.28, 0.25), 0.9)
	for i in 6:
		for j in 3:
			s._box(s, Vector3(0.42, 0.18, 0.03), Vector3(-2.3 + i * 0.5, 1.0 + j * 0.3, FRONT_Z - 0.31), names_)
	for i in 9:
		s._candle(Vector3(-2.4 + i * 0.33 + fmod(i * 0.37, 0.12), 0.0, FRONT_Z - 0.45 - fmod(i * 0.21, 0.15)), 0.08 + fmod(i * 0.13, 0.2))
	s._halo(Vector3(-1.1, 1.2, FRONT_Z - 0.4), 2.2, Color(1.0, 0.6, 0.3, 0.12))
	s._halo(Vector3(0.95, 3.6, 2.3), 3.6, Color(1.0, 0.58, 0.3, 0.08)) # bounce over the bay
	s.puddle_glows.append([Vector3(1.3, 0.12, 1.4), Color(1.0, 0.55, 0.25)])


# ---------------------------------------------------------------- the armoury alcove
func _armoury() -> void:
	var s = set_
	var board := Node3D.new()
	board.name = "ArmouryBoard"
	board.position = RACK_POS
	board.rotation.y = -PI * 0.5 # its face (+Z) toward the room (-X)
	s.add_child(board)
	var peg := U.mat(Color(0.2, 0.14, 0.1), 0.85)
	s._box(board, Vector3(3.1, 2.3, 0.05), Vector3(0, 1.65, -0.03), peg)
	s._box(board, Vector3(3.2, 0.08, 0.12), Vector3(0, 2.84, 0.0), s.m_wood_dark)
	s._box(board, Vector3(3.2, 0.08, 0.12), Vector3(0, 0.5, 0.0), s.m_wood_dark)
	for i in Meta.BLADE_RACK.size():
		var x := _rack_x(i)
		for dx in [-0.05, 0.05]:
			s._cyl(board, 0.01, 0.01, 0.07, Vector3(x + dx, 2.6, 0.03), s.m_brass, Vector3(PI * 0.5, 0, 0), 6)
		s._box(board, Vector3(0.16, 0.05, 0.01), Vector3(x, 2.72, 0.005), s.m_brass) # a brass plate per blade
	rack_root = Node3D.new()
	rack_root.name = "RackBlades"
	board.add_child(rack_root)
	rack_root.set_meta("no_batch", true)
	# a weapons trunk and a crate of stakes under the board
	var trunk := Node3D.new()
	trunk.position = Vector3(3.75, 0.12, 3.25)
	trunk.rotation.y = -0.2
	s.add_child(trunk)
	s._box(trunk, Vector3(1.0, 0.5, 0.55), Vector3(0, 0.25, 0), s.m_wood_dark)
	s._box(trunk, Vector3(1.04, 0.06, 0.59), Vector3(0, 0.5, 0), s.m_iron)
	for x in [-0.35, 0.35]:
		s._box(trunk, Vector3(0.06, 0.52, 0.6), Vector3(x, 0.25, 0), s.m_iron)
	for i in 4:
		s._candle(trunk.to_global(Vector3(-0.3 + i * 0.16, 0.53, 0.05 * (i % 2))), 0.1 + fmod(i * 0.29, 0.14))
	var crate := Node3D.new()
	crate.position = Vector3(3.7, 0.12, 0.55)
	s.add_child(crate)
	s._box(crate, Vector3(0.6, 0.45, 0.5), Vector3(0, 0.225, 0), s.m_wood)
	for i in 7:
		s._cyl(crate, 0.004, 0.02, 0.5, Vector3(-0.2 + i * 0.065, 0.6, fmod(i * 0.37, 0.2) - 0.1), s.m_wood, Vector3(0.08 * (i % 3), 0, 0.1 * (i % 2)), 6)
	s._halo(Vector3(4.0, 2.2, 1.9), 2.4, Color(1.0, 0.6, 0.32, 0.1))


static func _rack_x(i: int) -> float:
	return -1.35 + i * 0.3


## Hang every owned blade on the armoury board; the one Sol carries is the empty pair of pegs.
func refresh_rack() -> void:
	if rack_root == null:
		return
	for c in rack_root.get_children():
		rack_root.remove_child(c)
		c.queue_free()
	var carried := String(Meta.ensure().get("start_blade", "marrow_silver"))
	# blade (+Z) hanging down, its flat facing out of the board
	var hang := Basis(Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0))
	for i in Meta.BLADE_RACK.size():
		var id: String = Meta.BLADE_RACK[i].id
		if not Meta.owns_blade(id) or id == carried:
			continue
		var holder := Node3D.new()
		holder.name = id
		holder.transform = Transform3D(hang, Vector3(_rack_x(i), 2.56, 0.06))
		rack_root.add_child(holder)
		var w := WeaponVisual.build(ItemDB.make(id), 0.014, true)
		if w != null:
			holder.add_child(w)
			for mi in w.find_children("*", "GeometryInstance3D", true, false):
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- the wardrobe corner
func _wardrobe_corner() -> void:
	var s = set_
	# the armoire: a tall dark-oak cabinet against the front wall, both doors swung open
	var arm := Node3D.new()
	arm.name = "Armoire"
	arm.position = ARMOIRE_POS
	arm.rotation.y = PI # its front (+Z) to the room
	s.add_child(arm)
	var oak := s.m_wood.duplicate() as StandardMaterial3D
	oak.albedo_color = Color(0.32, 0.2, 0.12)
	var inner := U.mat(Color(0.05, 0.035, 0.03), 0.9)
	s._box(arm, Vector3(1.4, 2.25, 0.05), Vector3(0, 1.2, -0.3), oak) # back
	for x in [-0.68, 0.68]:
		s._box(arm, Vector3(0.05, 2.25, 0.62), Vector3(x, 1.2, 0), oak)
	s._box(arm, Vector3(1.46, 0.08, 0.68), Vector3(0, 2.36, 0), oak) # cornice
	s._box(arm, Vector3(1.5, 0.05, 0.7), Vector3(0, 2.42, 0), s.m_wood_dark)
	s._box(arm, Vector3(1.36, 0.14, 0.6), Vector3(0, 0.12, 0), oak) # plinth drawer
	s._box(arm, Vector3(1.32, 2.0, 0.02), Vector3(0, 1.22, -0.27), inner)
	s._box(arm, Vector3(1.32, 0.03, 0.55), Vector3(0, 1.95, 0), oak) # hat shelf
	s._cyl(arm, 0.012, 0.012, 1.3, Vector3(0, 1.82, 0.0), s.m_brass, Vector3(0, 0, PI * 0.5), 6) # rail
	for side: float in [-1.0, 1.0]:
		var door := Node3D.new()
		door.position = Vector3(side * 0.7, 0, 0.31)
		door.rotation.y = side * 1.9
		arm.add_child(door)
		s._box(door, Vector3(0.68, 2.1, 0.04), Vector3(-side * 0.34, 1.2, 0), oak)
		s._box(door, Vector3(0.5, 1.6, 0.01), Vector3(-side * 0.34, 1.25, 0.022), s.m_wood_dark)
	armoire_root = Node3D.new()
	armoire_root.name = "ArmoireClothes"
	arm.add_child(armoire_root)
	armoire_root.set_meta("no_batch", true)
	# a coat stand by the armoire
	var stand := Node3D.new()
	stand.position = Vector3(1.05, 0.12, 3.45)
	s.add_child(stand)
	s._cyl(stand, 0.02, 0.025, 1.85, Vector3(0, 0.93, 0), s.m_wood_dark, Vector3.ZERO, 8)
	s._cyl(stand, 0.2, 0.22, 0.04, Vector3(0, 0.02, 0), s.m_iron, Vector3.ZERO, 10)
	for k in 4:
		var a := k * PI * 0.5
		s._cyl(stand, 0.008, 0.008, 0.2, Vector3(cos(a) * 0.08, 1.8, sin(a) * 0.08), s.m_brass, Vector3(sin(a) * 0.9, 0, -cos(a) * 0.9), 5)
	# a worn red rug under the mirror spot
	var rug := U.mat(Color(0.24, 0.035, 0.04), 0.95)
	var r: MeshInstance3D = s._box(s, Vector3(1.9, 0.012, 1.3), Vector3(0.25, 0.126, 2.15), rug, Vector3(0, 0.12, 0))
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s._box(s, Vector3(1.7, 0.013, 1.1), Vector3(0.25, 0.127, 2.15), U.mat(Color(0.12, 0.02, 0.025), 0.95), Vector3(0, 0.12, 0))
	# the standing mirror: an oval of old silvered glass in an iron frame, angled to the room
	var mroot := Node3D.new()
	mroot.name = "Mirror"
	mroot.position = MIRROR_POS
	mroot.rotation.y = 0.85 # faces Sol's spot on the rug
	s.add_child(mroot)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.055, 0.06)
	glass.metallic = 0.9
	glass.roughness = 0.08
	glass.metallic_specular = 1.0
	glass.emission_enabled = true
	glass.emission = Color(0.16, 0.13, 0.11) # a dim silvered sheen, so it reads as glass in the dark
	glass.emission_energy_multiplier = 0.6
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.02
	disc.radial_segments = 24
	disc.rings = 1
	mirror = U.part(mroot, disc, glass, Vector3(0, 1.25, 0), Vector3(PI * 0.5, 0, 0), Vector3(0.62, 1.0, 1.25))
	var frame := TorusMesh.new()
	frame.inner_radius = 0.48
	frame.outer_radius = 0.54
	frame.rings = 28
	frame.ring_segments = 6
	U.part(mroot, frame, s.m_iron, Vector3(0, 1.25, 0), Vector3(PI * 0.5, 0, 0), Vector3(0.62, 1.0, 1.25))
	for x in [-0.36, 0.36]:
		s._cyl(mroot, 0.018, 0.022, 1.25, Vector3(x, 0.62, -0.05), s.m_iron, Vector3(0.06, 0, 0), 6)
	s._box(mroot, Vector3(0.9, 0.04, 0.32), Vector3(0, 0.02, -0.05), s.m_iron)
	s._halo(MIRROR_POS + Vector3(0.2, 1.6, 0.2), 1.0, Color(1.0, 0.7, 0.45, 0.12))
	# candles on the armoire's top and a tall candle stand by the mirror
	for i in 5:
		s._candle(arm.to_global(Vector3(-0.5 + i * 0.25, 2.445, 0.1 - fmod(i * 0.31, 0.2))), 0.08 + fmod(i * 0.17, 0.16))
	s._cyl(s, 0.015, 0.02, 1.2, Vector3(-1.2, 0.72, 2.6), s.m_iron, Vector3.ZERO, 6)
	s._cyl(s, 0.12, 0.08, 0.04, Vector3(-1.2, 1.33, 2.6), s.m_iron, Vector3.ZERO, 8)
	for i in 3:
		s._candle(Vector3(-1.25 + i * 0.05, 1.35, 2.58 + (i % 2) * 0.05), 0.12 + i * 0.05)


## Hang the coats Sol owns (but isn't wearing) in the armoire, hats on its shelf.
func refresh_wardrobe() -> void:
	if armoire_root == null:
		return
	for c in armoire_root.get_children():
		armoire_root.remove_child(c)
		c.queue_free()
	var worn := Meta.outfit()
	var coats: Array = []
	var hats: Array = []
	for id in Meta.ensure().clothes:
		var slot := Wardrobe.slot_of(id)
		if id == worn.get(slot, ""):
			continue
		if slot == "coat":
			coats.append(id)
		elif slot == "hat" and String(Wardrobe.get_def(id).look.get("kind", "none")) != "none":
			hats.append(id)
	for i in coats.size():
		var look: Dictionary = Wardrobe.get_def(coats[i]).look
		var col: Color = look.get("col", Color(0.1, 0.1, 0.1))
		if look.get("tex", true):
			col = col * 0.55 # the textured leathers read darker than their tint
		var m := U.mat(col, float(look.get("rough", 0.6)), float(look.get("metal", 0.0)) * 0.5)
		var x := -0.5 + i * (1.0 / maxf(coats.size() - 1, 1)) if coats.size() > 1 else 0.0
		var hem := float(look.get("hem", 1.0))
		var coat := Node3D.new()
		coat.position = Vector3(x, 1.8, 0.0)
		coat.rotation.y = 1.25 + fmod(i * 0.37, 0.3) # side-on, like coats on a rail
		armoire_root.add_child(coat)
		U.part(coat, U.box(Vector3(0.42, 0.06, 0.07)), U.mat(Color(0.3, 0.22, 0.12), 0.6), Vector3(0, -0.03, 0)) # hanger
		U.part(coat, U.cyl(0.2, 0.26, 1.15 * hem), m, Vector3(0, -0.06 - 0.575 * hem, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.32))
	for i in hats.size():
		var look: Dictionary = Wardrobe.get_def(hats[i]).look
		var felt := U.mat(look.get("col", Color(0.05, 0.05, 0.05)), 0.85)
		var p := Vector3(-0.42 + i * 0.32, 1.97, 0.02)
		U.part(armoire_root, U.cyl(0.13, 0.135, 0.012), felt, p)
		U.part(armoire_root, U.cyl(0.07, 0.075, 0.09), felt, p + Vector3(0, 0.05, 0))


# ---------------------------------------------------------------- colliders
func _colliders() -> void:
	colliders = StaticBody3D.new()
	colliders.name = "LairColliders"
	colliders.collision_layer = 1
	colliders.collision_mask = 0
	set_.add_child(colliders)
	var s = set_
	# the water: shallow standing water over the crypt floor (walkable)
	_box(Vector3(30, 0.2, 30), Vector3(-2, -0.12, -6))
	# the raised platform, its edges ramped so he can step up from the water
	var top := 0.12
	var lo := -0.02
	var x0 := -0.9
	var x1 := 4.3
	var z0 := -8.2
	var z1 := PLAT_FRONT
	var e := 0.45
	var shp := ConvexPolygonShape3D.new()
	shp.points = PackedVector3Array([Vector3(x0, top, z0), Vector3(x1, top, z0), Vector3(x0, top, z1), Vector3(x1, top, z1),
		Vector3(x0 - e, lo, z0 - e), Vector3(x1 + e, lo, z0 - e), Vector3(x0 - e, lo, z1 + e), Vector3(x1 + e, lo, z1 + e),
		Vector3(x0 - e, lo - 0.3, z0 - e), Vector3(x1 + e, lo - 0.3, z0 - e), Vector3(x0 - e, lo - 0.3, z1 + e), Vector3(x1 + e, lo - 0.3, z1 + e)])
	var cs := CollisionShape3D.new()
	cs.shape = shp
	colliders.add_child(cs)
	# walls (inner faces: right 4.3, back -8.2, front 4.1) and the unseen left bound
	_box(Vector3(0.6, 6, 16), Vector3(4.6, 3, -2.0))
	_box(Vector3(0.6, 6, 16), Vector3(4.6, 3, 3.0))
	_box(Vector3(5.0, 6, 0.8), Vector3(2.35, 3, -8.6)) # back, right of the tunnel
	_box(Vector3(2.0, 6, 0.8), Vector3(-4.4, 3, -8.6)) # back, left of it
	_box(Vector3(10.0, 6, 0.6), Vector3(0.0, 3, FRONT_Z))
	_box(Vector3(0.4, 6, 14.0), Vector3(LEFT_BOUND - 0.2, 3, -2.0))
	_box(Vector3(3.6, 3.2, 0.3), Vector3(s.TUNNEL_X, 1.6, -8.3)) # the tunnel gate: locked until the Hunt
	for p in [Vector3(-2.7, 0, -4.4), Vector3(s.TUNNEL_X + 2.05, 0, -7.7), Vector3(-2.7, 0, 0.8), Vector3(-2.7, 0, 3.75)]:
		_cyl(0.48, p + Vector3(0, 1.5, 0), 3.0)
	_box(Vector3(0.6, 1.0, 0.5), Vector3(s.TUNNEL_X - 1.95, 0.5, -8.0))
	_box(Vector3(0.6, 1.0, 0.5), Vector3(s.TUNNEL_X + 1.95, 0.5, -8.0))
	# furniture
	_box(Vector3(s.BENCH_LEN + 0.1, 1.1, 1.05), s.BENCH_POS + Vector3(0, 0.55, 0)) # the workbench
	_box(Vector3(2.45, 2.4, 0.8), Vector3(2.3, 1.2, -7.82)) # the blood fridges
	_box(Vector3(1.9, 1.0, 1.0), Vector3(0.45, 0.6, -6.9) + Basis(Vector3.UP, 0.12) * Vector3(0, 0, 0.45), 0.12) # planning desk
	_box(Vector3(2.4, 3.0, 0.5), Vector3(4.2, 1.5, -5.7), -1.05) # the pegboard and its rack
	_box(Vector3(0.6, 0.95, 6.0), Vector3(4.15, 0.5, -4.2)) # the stone ledge on the right
	_box(Vector3(0.45, 3.0, 3.2), RACK_POS + Vector3(-0.1, 1.5, 0)) # the armoury board
	_box(Vector3(1.0, 0.6, 0.6), Vector3(3.75, 0.4, 3.25), -0.2) # trunk
	_box(Vector3(0.6, 0.6, 0.5), Vector3(3.7, 0.4, 0.55)) # stake crate
	_box(Vector3(1.6, 2.5, 0.75), ARMOIRE_POS + Vector3(0, 1.25, 0)) # armoire
	_box(Vector3(0.95, 2.0, 0.35), MIRROR_POS + Vector3(0, 1.0, 0), 0.85) # mirror
	_cyl(0.22, Vector3(1.05, 1.0, 3.45), 2.0) # coat stand
	_cyl(0.2, Vector3(-1.2, 0.7, 2.6), 1.4) # candle stand
	_cyl(0.32, s.NIA_POS + Vector3(0, 0.9, 0), 1.8) # Nia herself


func _box(size: Vector3, pos: Vector3, yaw := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	colliders.add_child(cs)


func _cyl(r: float, pos: Vector3, h: float) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	cs.position = pos
	colliders.add_child(cs)


# ---------------------------------------------------------------- static batching
## Merge every plain, opaque, static MeshInstance3D of the set into one mesh per material. Skipped:
## Nia, the dynamic racks (meta "no_batch"), shader materials (some read MODEL_MATRIX or local
## VERTEX), transparent or billboard materials, mirrored transforms (their winding would flip) and
## MultiMeshes (candles, halos: already one draw each).
func batch() -> void:
	var groups := {} # key -> {mat, shadow, items: [[mesh, xf]]}
	var to_free: Array = []
	var inv: Transform3D = set_.global_transform.affine_inverse()
	for n in set_.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not _batchable(mi):
			continue
		var mat: Material = mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(0)
		var key := "%d_%d" % [mat.get_instance_id(), mi.cast_shadow]
		if not groups.has(key):
			groups[key] = {"mat": mat, "shadow": mi.cast_shadow, "items": []}
		groups[key].items.append([mi.mesh, inv * mi.global_transform])
		to_free.append(mi)
	for key in groups:
		var g: Dictionary = groups[key]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for it in g.items:
			st.append_from(it[0], 0, it[1])
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var out := MeshInstance3D.new()
		out.name = "Batched"
		out.mesh = mesh
		out.material_override = g.mat
		out.cast_shadow = g.shadow
		set_.add_child(out)
		batched_to += 1
	batched_from = to_free.size()
	for mi in to_free:
		mi.get_parent().remove_child(mi)
		mi.free()


func _batchable(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or not mi.visible or mi.mesh.get_surface_count() != 1 or mi.skin != null:
		return false
	var p: Node = mi
	while p != null and p != set_:
		if p.has_meta("no_batch") or p == set_.nia:
			return false
		p = p.get_parent()
	if mi.global_transform.basis.determinant() <= 0.0:
		return false
	var mat: Material = mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(0)
	if not (mat is StandardMaterial3D):
		return false
	var sm := mat as StandardMaterial3D
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return false
	return true
