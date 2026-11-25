extends RefCounted
## The Arsenal (round 4): the new weapon families modelled from a few generated meshes (faceted
## blades, extruded plates, turned shafts), so they cost no download and no credits. weapon_visual.gd
## calls build() for these families.
##
## Origin = the grip socket (the fist's tunnel centre); +Z runs out of the thumb side toward the blade,
## +Y is the edge side (the knuckles), +X the flat. Polearms carry their shaft back past the hand (-Z).
## Meshes and materials are cached and shared; a weapon is 5-12 small mesh instances without shadows.

const ItemDB = preload("res://scripts/items/item_db.gd")
const Arsenal = preload("res://scripts/items/arsenal_data.gd")
const WhipChain = preload("res://scripts/items/whip_chain.gd")

const FAMILIES := ["katana", "daggers", "greatsword", "halberd", "scythe", "hammer", "whip"]
## How far the striking end reaches from the grip (m), for the slash trail (arsenal.gd).
const TIP := {"katana": 0.82, "daggers": 0.37, "greatsword": 1.5, "halberd": 1.4, "scythe": 1.05, "hammer": 0.72, "whip": 1.6,
	"saber": 1.0, "cane": 1.1, "longblade": 1.05, "cleaver": 0.8, "machete": 0.8, "kukri": 0.8}

static var _mesh := {}
static var _mat := {}


static func mat(key: String, c: Color, metal: float, rough: float, rarity: int = 0, glow := Color(0, 0, 0)) -> StandardMaterial3D:
	var k := "%s_%d" % [key, rarity]
	if not _mat.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metal
		m.roughness = rough
		m.metallic_specular = 0.6 if metal > 0.5 else 0.35
		m.cull_mode = BaseMaterial3D.CULL_DISABLED # thin plates and blades read from both sides
		var e := glow
		if rarity >= ItemDB.RARE and metal > 0.5:
			e = e + ItemDB.RARITY_COLORS[rarity] * (0.12 if rarity == ItemDB.RARE else 0.25)
		if e.r + e.g + e.b > 0.001:
			m.emission_enabled = true
			m.emission = e
			m.emission_energy_multiplier = 1.0
		m.rim_enabled = metal > 0.5 # a thin rim keeps the steel readable from the follow camera
		m.rim = 0.35
		m.rim_tint = 0.6
		_mat[k] = m
	return _mat[k]


## A faceted blade along +Z from z0, `length` long: a diamond section (edge +Y, flats +-X, back -Y)
## tapering to the point over `tip` of the length. `curve` bends it toward the back (a katana's sori),
## `back` < 1 thins the spine side (single-edged).
static func blade_mesh(length: float, width: float, thick: float, curve := 0.0, tip := 0.18, back := 1.0, z0 := 0.0, segs := 10) -> ArrayMesh:
	var key := "blade_%.3f_%.3f_%.3f_%.3f_%.2f_%.2f_%.3f_%d" % [length, width, thick, curve, tip, back, z0, segs]
	if _mesh.has(key):
		return _mesh[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # flat facets: crisp steel
	var rings: Array = []
	for i in segs + 1:
		var u := float(i) / segs
		var w := width * 0.5 * (1.0 - 0.18 * u)
		if u > 1.0 - tip:
			w *= clampf((1.0 - u) / tip, 0.0, 1.0)
		var y_off := -curve * u * u
		var z := z0 + length * u
		var t := thick * 0.5 * (1.0 - 0.5 * u)
		var ridge := -w * (1.0 - back) * 0.5
		rings.append([Vector3(0, y_off + w, z), Vector3(t, y_off + ridge, z), Vector3(0, y_off - w * back, z), Vector3(-t, y_off + ridge, z)])
	for i in segs:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for j in 4:
			var j2 := (j + 1) % 4
			st.add_vertex(a[j]); st.add_vertex(b[j2]); st.add_vertex(b[j])
			st.add_vertex(a[j]); st.add_vertex(a[j2]); st.add_vertex(b[j2])
	var r0: Array = rings[0]
	st.add_vertex(r0[0]); st.add_vertex(r0[1]); st.add_vertex(r0[2])
	st.add_vertex(r0[0]); st.add_vertex(r0[2]); st.add_vertex(r0[3])
	st.generate_normals()
	var m := st.commit()
	_mesh[key] = m
	return m


## A flat plate (axe head, scythe blade): polygon `poly` in the (y, z) plane, `thick` along X.
static func plate_mesh(key: String, poly: PackedVector2Array, thick: float) -> ArrayMesh:
	if _mesh.has(key):
		return _mesh[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var tris := Geometry2D.triangulate_polygon(poly)
	var h := thick * 0.5
	for k in range(0, tris.size(), 3):
		var p0 := poly[tris[k]]
		var p1 := poly[tris[k + 1]]
		var p2 := poly[tris[k + 2]]
		st.add_vertex(Vector3(h, p0.x, p0.y)); st.add_vertex(Vector3(h, p1.x, p1.y)); st.add_vertex(Vector3(h, p2.x, p2.y))
		st.add_vertex(Vector3(-h, p0.x, p0.y)); st.add_vertex(Vector3(-h, p2.x, p2.y)); st.add_vertex(Vector3(-h, p1.x, p1.y))
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var A := Vector3(h, a.x, a.y)
		var B := Vector3(h, b.x, b.y)
		var A2 := Vector3(-h, a.x, a.y)
		var B2 := Vector3(-h, b.x, b.y)
		st.add_vertex(A); st.add_vertex(A2); st.add_vertex(B2)
		st.add_vertex(A); st.add_vertex(B2); st.add_vertex(B)
	st.generate_normals()
	var m := st.commit()
	_mesh[key] = m
	return m


static func cyl_mesh(r0: float, r1: float, h: float, seg := 10) -> CylinderMesh:
	var key := "cyl_%.3f_%.3f_%.3f_%d" % [r0, r1, h, seg]
	if not _mesh.has(key):
		var c := CylinderMesh.new()
		c.top_radius = r1
		c.bottom_radius = r0
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		_mesh[key] = c
	return _mesh[key]


static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "box_%s" % str(size)
	if not _mesh.has(key):
		var b := BoxMesh.new()
		b.size = size
		_mesh[key] = b
	return _mesh[key]


static func sphere_mesh(r: float) -> SphereMesh:
	var key := "sph_%.3f" % r
	if not _mesh.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 10
		s.rings = 5
		_mesh[key] = s
	return _mesh[key]


static func put(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = rot
	if name != "":
		mi.name = name
	parent.add_child(mi)
	return mi


## A shaft along Z from z0 to z1 (CylinderMesh is along Y: turned onto Z).
static func shaft(parent: Node3D, z0: float, z1: float, r: float, m: Material, r_end := -1.0) -> MeshInstance3D:
	return put(parent, cyl_mesh(r, r if r_end < 0.0 else r_end, z1 - z0), m, Vector3(0, 0, (z0 + z1) * 0.5), Vector3(PI / 2.0, 0, 0))


const RING := Vector3(PI / 2.0, 0, 0) # a cylinder turned onto Z


## The weapon for an Arsenal item, tinted by rarity (Hallowed and Eclipse steel glows faintly, and the
## affinity colours the edge from Blooded up); `left` names the left-hand twin.
static func build(inst: Dictionary, left := false) -> Node3D:
	var d := ItemDB.get_def(inst.get("id", "marrow_silver"))
	var fam: String = d.get("family", "katana")
	var r := int(inst.get("r", 0))
	var look: Dictionary = ItemDB.BLADE_LOOK.get(fam, ItemDB.BLADE_LOOK.saber)
	var steel_c: Color = look.col
	if r > ItemDB.COMMON:
		steel_c = steel_c.lerp(ItemDB.RARITY_COLORS[r], 0.08 + 0.03 * r)
	var aff: String = Arsenal.get_type(Arsenal.type_of_family(fam)).affinity
	var aff_glow: Color = Arsenal.AFFINITY_COLOR.get(aff, Color.BLACK) * (0.0 if r < ItemDB.UNCOMMON else 0.05 * r)
	var steel := mat("steel_" + fam, steel_c, 0.95, 0.22, r, aff_glow)
	var iron := mat("iron", Color(0.09, 0.085, 0.08), 0.7, 0.55)
	var wood := mat("wood", Color(0.2, 0.12, 0.07), 0.0, 0.75)
	var wrap := mat("wrap_" + fam, Color(0.32, 0.03, 0.04) if fam in ["katana", "whip"] else Color(0.09, 0.06, 0.05), 0.0, 0.8)
	var brass := mat("brass", Color(0.62, 0.46, 0.2), 0.9, 0.35)
	var silver := mat("silver", Color(0.86, 0.88, 0.93), 1.0, 0.15, r)
	var root := Node3D.new()
	root.name = "WeaponVisualL" if left else "WeaponVisual"
	match fam:
		"katana":
			shaft(root, -0.24, 0.035, 0.016, wrap)
			put(root, cyl_mesh(0.019, 0.019, 0.02), iron, Vector3(0, 0, -0.25), RING)
			put(root, cyl_mesh(0.045, 0.045, 0.008, 12), brass if r >= ItemDB.RARE else iron, Vector3(0, 0, 0.045), RING)
			put(root, box_mesh(Vector3(0.012, 0.034, 0.03)), brass, Vector3(0, 0, 0.063))
			put(root, blade_mesh(0.76, 0.034, 0.008, 0.04, 0.12, 0.55, 0.05), steel, Vector3.ZERO, Vector3.ZERO, "Blade")
		"daggers":
			shaft(root, -0.11, 0.03, 0.015, wood, 0.017)
			put(root, sphere_mesh(0.02), silver, Vector3(0, 0, -0.115))
			put(root, box_mesh(Vector3(0.022, 0.1, 0.018)), silver, Vector3(0, 0, 0.038))
			put(root, blade_mesh(0.32, 0.036, 0.011, 0.0, 0.35, 1.0, 0.045, 8), steel, Vector3.ZERO, Vector3.ZERO, "Blade")
		"greatsword":
			shaft(root, -0.3, 0.04, 0.018, wrap)
			put(root, sphere_mesh(0.036), iron, Vector3(0, 0, -0.32))
			put(root, box_mesh(Vector3(0.045, 0.36, 0.045)), iron, Vector3(0, 0, 0.065))
			put(root, box_mesh(Vector3(0.03, 0.09, 0.09)), steel, Vector3(0, 0, 0.13))
			put(root, blade_mesh(1.42, 0.115, 0.022, 0.0, 0.1, 1.0, 0.09, 12), steel, Vector3.ZERO, Vector3.ZERO, "Blade")
		"halberd":
			shaft(root, -1.0, 1.05, 0.019, wood)
			put(root, cyl_mesh(0.024, 0.024, 0.06), iron, Vector3(0, 0, -1.01), RING)
			for z in [0.0, 0.92]:
				put(root, cyl_mesh(0.023, 0.023, 0.035), iron, Vector3(0, 0, z), RING)
			put(root, blade_mesh(0.36, 0.05, 0.014, 0.0, 0.45, 1.0, 1.05, 8), steel, Vector3.ZERO, Vector3.ZERO, "Blade")
			put(root, plate_mesh("halberd_axe", PackedVector2Array([Vector2(0.0, 0.92), Vector2(0.1, 0.9), Vector2(0.22, 0.84),
				Vector2(0.27, 0.98), Vector2(0.27, 1.12), Vector2(0.22, 1.24), Vector2(0.1, 1.15), Vector2(0.0, 1.13)]), 0.012), steel)
			put(root, plate_mesh("halberd_spike", PackedVector2Array([Vector2(0.0, 0.98), Vector2(0.0, 1.08), Vector2(-0.19, 1.0)]), 0.014), steel)
		"scythe":
			shaft(root, -0.9, 0.98, 0.018, wood)
			put(root, cyl_mesh(0.022, 0.022, 0.03), iron, Vector3.ZERO, RING)
			put(root, box_mesh(Vector3(0.03, 0.05, 0.08)), iron, Vector3(0, 0.02, 0.97))
			var pts := PackedVector2Array()
			for i in 13: # the spine, from the socket out to the point
				var u := i / 12.0
				pts.append(Vector2(u * 0.78, 0.99 + sin(u * PI) * 0.14 - u * 0.24))
			for i in range(12, -1, -1): # the edge, back in
				var u := i / 12.0
				pts.append(Vector2(u * 0.78, 0.99 + sin(u * PI) * 0.14 - u * 0.24 - (0.085 * (1.0 - u) + 0.006)))
			put(root, plate_mesh("scythe_blade", pts, 0.01), steel, Vector3.ZERO, Vector3.ZERO, "Blade")
		"hammer":
			shaft(root, -0.38, 0.6, 0.02, wood)
			for z in [-0.36, 0.05, 0.45]:
				put(root, cyl_mesh(0.024, 0.024, 0.03), iron, Vector3(0, 0, z), RING)
			put(root, box_mesh(Vector3(0.13, 0.26, 0.15)), iron, Vector3(0, 0.03, 0.64), Vector3.ZERO, "Blade")
			put(root, box_mesh(Vector3(0.15, 0.05, 0.17)), silver, Vector3(0, 0.18, 0.64)) # the silver striking face
			put(root, cyl_mesh(0.045, 0.0, 0.16, 8), steel, Vector3(0, -0.24, 0.64), Vector3(PI, 0, 0)) # the back spike
			put(root, blade_mesh(0.1, 0.04, 0.03, 0.0, 0.6, 1.0, 0.71, 4), steel) # the top spike
		"whip":
			shaft(root, -0.13, 0.06, 0.017, wrap)
			put(root, sphere_mesh(0.024), brass, Vector3(0, 0, -0.14))
			put(root, cyl_mesh(0.024, 0.02, 0.03), brass, Vector3(0, 0, 0.07), RING)
			var chain := Node3D.new()
			chain.name = "Chain"
			chain.set_script(WhipChain)
			root.add_child(chain)
			var link_mesh := blade_mesh(0.075, 0.026, 0.012, 0.0, 0.45, 1.0, -0.0375, 3)
			for i in WhipChain.LINKS:
				var link := put(chain, link_mesh, steel if i % 2 == 0 else iron, Vector3(0, 0, WhipChain.START + i * WhipChain.SEG))
				link.name = "Link%d" % i
				if i == WhipChain.LINKS - 1:
					link.mesh = blade_mesh(0.16, 0.05, 0.014, 0.0, 0.5, 1.0, -0.06, 5) # the barbed tip
	return root
