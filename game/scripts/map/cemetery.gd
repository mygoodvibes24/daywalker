extends RefCounted
## St. Roch Cemetery, the south end of the Old Quarter: a walled city of the dead. Dead, trampled
## grass between rows of weathered headstones (rounded, gothic, crosses, obelisks, broken and
## tilted ones, chest tombs), plots with sunken kerbs, mounds and iron railings, vases of dead
## flowers and grave candles; the old whitewashed tomb rows in the south-west, gothic family
## mausoleums along the cross avenue, the mortuary chapel, gnarled dead trees, low ground fog
## and crows. In the north-east corner the night groundskeeper's shed and a freshly dug grave.
##
## Everything is placed relative to the cemetery's own footprint (X0..X1, Z0..Z1). The repeated
## grave furniture is drawn as MultiMeshes (cemetery_kit.gd); one-off pieces (the shed, the dig
## site, the gates, the trees) go into city.gd's merged chunk batches.

const Layout = preload("res://scripts/map/map_layout.gd")
const Kit = preload("res://scripts/map/cemetery_kit.gd")
const Crows = preload("res://scripts/world/crows.gd")
const Keeper = preload("res://scripts/world/groundskeeper.gd")

const X0 := -66.0
const X1 := 66.0
const Z0 := 100.0
const Z1 := 200.0
const AVENUES_X := [-40.0, 0.0, 40.0]
const AVENUE_Z := 150.0
const CHAPEL := Vector3(0, 0, 178)
const MAUSOLEUM_H := 4.2
## The ground (and its mask) covers the walls' surroundings too.
const GROUND := Rect2(-70.0, 95.0, 140.0, 108.75)
const MASK_PX := 2.0 # mask pixels per metre
## The groundskeeper's yard (north-east corner) and the open grave.
const SHED := Vector3(57.0, 0, 106.0) # floor centre; door and porch face west
const SHED_SIZE := Vector2(4.0, 5.0) # x, z
const DIG := Vector3(52.0, 0, 127.0) # centre of the open grave (long axis along z)
const HOLE := Vector2(0.55, 1.15) # its half size
const HOLE_DEPTH := 1.8
const TREES := [[-55.0, 117.0, 7.5], [23.0, 110.0, 6.5], [-21.0, 172.0, 7.0], [55.5, 172.0, 6.0], [62.0, 120.0, 5.5]]
const DRAW_RANGE := 95.0


## Everything collected while laying out the grounds.
class Ctx:
	var r := RandomNumberGenerator.new()
	var mask: Image
	var stones := {} # kind -> [Transform3D]
	var stone_cust := {} # kind -> [Color]
	var mounds: Array = []
	var mound_cust: Array = []
	var kerbs: Array = []
	var kerb_cust: Array = []
	var fences: Array = []
	var vases: Array = []
	var candles: Array = []
	var tufts: Array = []
	var tuft_cust: Array = []
	var keep_out: Array[Rect2] = [] # no graves or grass here (yard, dig site, trees, lots)
	var nodes: Array = [] # draw nodes the cemetery made (budget checks)


static func build(c) -> void:
	var s := Ctx.new()
	s.r.seed = 6603
	var r := s.r
	s.mask = Image.create(int(GROUND.size.x * MASK_PX), int(GROUND.size.y * MASK_PX), false, Image.FORMAT_RGB8)
	s.mask.fill(Color(0, 0, 0))
	for k in Kit.STONE_KINDS:
		s.stones[k] = []
		s.stone_cust[k] = []
	_materials(c)
	var lot0: int = c.lots.size()
	for ax in AVENUES_X:
		c.ground_path("cobble_fan", [Vector3(ax, 0, Z0 - 4.0), Vector3(ax, 0, Z1 + 3.0)], 6.0, Color(0.5, 0.48, 0.45), 0.03, 16.0)
		_paint(s, Rect2(ax - 4.6, Z0, 9.2, Z1 - Z0), 0, 0.5) # trodden verges
	c.ground_path("cobble_fan", [Vector3(X0, 0, AVENUE_Z), Vector3(X1, 0, AVENUE_Z)], 7.0, Color(0.5, 0.48, 0.45), 0.031, 16.0)
	_paint(s, Rect2(X0, AVENUE_Z - 5.0, X1 - X0, 10.0), 0, 0.5)
	_walls(c)
	# keep-outs: the yard and the dig site, the trees, the chapel
	var yard := Rect2(SHED.x - 4.5, Z0, X1 - (SHED.x - 4.5), 14.0)
	var dig := Rect2(DIG.x - 3.4, DIG.z - 3.6, 7.4, 7.6)
	s.keep_out.append_array([yard, dig, Rect2(CHAPEL.x - 6.5, CHAPEL.z - 4.0, 13.0, 18.5)])
	for t in TREES:
		s.keep_out.append(Rect2(t[0] - 1.8, t[1] - 1.8, 3.6, 3.6))
	# the bands between the avenues, north and south of the cross avenue
	var bands := [[X0 + 2.0, -43.5], [-36.5, -3.5], [3.5, 36.5], [43.5, X1 - 2.0]]
	var mxfs: Array = [] # the mausoleums (one MultiMesh)
	for bi in bands.size():
		var b: Array = bands[bi]
		for zr in [[Z0 + 4.0, AVENUE_Z - 5.0], [AVENUE_Z + 5.0, Z1 - 4.0]]:
			if bi == 0 and zr[0] > AVENUE_Z:
				# the old section: whitewashed family tombs in narrow rows
				var z: float = zr[0]
				while z + 3.0 <= zr[1]:
					_tomb_row(c, r, b[0], b[1], z)
					z += 7.0
				continue
			var f0: float = zr[0]
			var f1: float = zr[1]
			if bi == 1 or bi == 2:
				# grand family mausoleums face the cross avenue, ordinary tombs in between
				if zr[0] < AVENUE_Z:
					_mausoleum_row(c, r, b[0], b[1], 139.0, 1.0, mxfs)
					f1 = 137.0
				else:
					_mausoleum_row(c, r, b[0], b[1], 155.0, -1.0, mxfs)
					f0 = 160.5
			_grave_field(c, s, b[0], b[1], f0, f1)
	c.glb_multimesh("mausoleum", MAUSOLEUM_H, mxfs, 80.0, 170.0, true)
	for xf: Transform3D in mxfs:
		# crows on the mausoleum roofs: the ridge over the front and the back corner
		for lp in [Vector3(0, 3.62, 0.9), Vector3(0.9, 3.25, -1.2)]:
			if r.randf() < 0.6:
				Crows.add_perch(c, xf * lp)
	_chapel(c)
	Crows.add_perch(c, CHAPEL + Vector3(0, 13.5, 6.0), PI * 0.5)
	Crows.add_perch(c, CHAPEL + Vector3(0, 13.5, 11.0), -PI * 0.5)
	# weeping angels on plinths round the crossing of the main avenues
	for p in [Vector3(-44.5, 0, 145.5), Vector3(44.5, 0, 145.5), Vector3(-44.5, 0, 154.5), Vector3(44.5, 0, 154.5)]:
		c.ck = c._chunk_of(p.x, p.z)
		c.box(c._b("stone"), p + Vector3(0, 0.8, 0), Vector3(1.3, 1.6, 1.3), Color(0.6, 0.58, 0.55))
		c.box_collider(p + Vector3(0, 1.5, 0), Vector3(1.3, 3.0, 1.3))
		var holder := Node3D.new()
		c.add_child(holder)
		c._glb_into(holder, "angel", 2.1, Transform3D(Basis(Vector3.UP, atan2(-p.x, 150.0 - p.z)), p + Vector3(0, 1.6, 0)), false)
		for mi in holder.get_children():
			(mi as GeometryInstance3D).visibility_range_end = 90.0
	for ax in AVENUES_X:
		var z := Z0 + 12.0
		while z < Z1:
			if absf(z - AVENUE_Z) > 8.0 and not (ax == 0.0 and z > 168.0):
				c.path_lamp(Vector3(ax + 3.4, 0.0, z), Vector3(-1, 0, 0))
			z += 26.0
	_gates(c)
	_trees(c, s)
	_yard(c, s)
	_dig_site(c, s)
	_puddles(s)
	# lots added here (tomb rows, mausoleums, shed) keep the grass out too
	for k in range(lot0, c.lots.size()):
		s.keep_out.append(c.lots[k])
	_grass(c, s)
	_ground(c, s)
	_furniture(c, s)
	_fog(c, s)
	# promenade along the river
	preload("res://scripts/map/velvet.gd")._promenade(c, r, -80.0, 60.0)
	# points of interest, loot, paths
	for p in [Vector3(-40, 0, 122), Vector3(40, 0, 122), Vector3(-40, 0, 178), Vector3(40, 0, 178), Vector3(-20, 0, 150), Vector3(20, 0, 150), Vector3(0, 0, 118)]:
		c.add_anchor(p, "cemetery")
	for p in [Vector3(-50, 0, 212), Vector3(30, 0, 212)]:
		c.add_anchor(p, "promenade")
	for ax in AVENUES_X:
		for z in [110.0, 130.0, 170.0, 190.0]:
			c.add_road(Vector3(ax, 0, z))
	for p in [Vector3(-38, 0, 140), Vector3(38, 0, 162), Vector3(2.5, 0, 132), Vector3(-58, 0, 150)]:
		c.cache_spots.append({"pos": p + Vector3(0, 0.1, 0), "yaw": PI * 0.5, "coffin": true})
	# crows: perches round the rest of the map are picked once the whole city exists
	Crows.add_provider(c, func() -> Array: return world_perches(c))
	Crows.spawn(c)
	c.set_meta("cemetery", {"nodes": s.nodes, "hole": Rect2(DIG.x - HOLE.x, DIG.z - HOLE.y, HOLE.x * 2.0, HOLE.y * 2.0),
		"shed": Rect2(SHED.x - SHED_SIZE.x * 0.5, SHED.z - SHED_SIZE.y * 0.5, SHED_SIZE.x, SHED_SIZE.y), "dig": DIG,
		"stones": _count(s.stones)})


static func _count(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += (d[k] as Array).size()
	return n


static func _materials(c) -> void:
	if c.M.has("gy_dirt"):
		return
	var dirt := StandardMaterial3D.new()
	dirt.albedo_texture = Kit.tex("mud_albedo")
	dirt.normal_enabled = true
	dirt.normal_texture = Kit.tex("mud_normal")
	dirt.vertex_color_use_as_albedo = true
	dirt.uv1_triplanar = true
	dirt.uv1_world_triplanar = true
	dirt.uv1_scale = Vector3.ONE / 1.6
	dirt.roughness = 0.95
	c.M["gy_dirt"] = dirt
	c.CASTS["gy_dirt"] = true
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = Kit.tex("cliff_rock_albedo")
	bark.normal_enabled = true
	bark.normal_texture = Kit.tex("cliff_rock_normal")
	bark.vertex_color_use_as_albedo = true
	bark.uv1_triplanar = true
	bark.uv1_world_triplanar = true
	bark.uv1_scale = Vector3(1.0, 0.25, 1.0)
	bark.roughness = 0.95
	c.M["gy_bark"] = bark
	c.CASTS["gy_bark"] = true


# ================================================================ ground mask
## Paint channel ch (0 worn dirt, 1 wet mud, 2 fresh soil) up to v over a world rect.
static func _paint(s: Ctx, rect: Rect2, ch: int, v: float) -> void:
	var x0 := clampi(int((rect.position.x - GROUND.position.x) * MASK_PX), 0, s.mask.get_width())
	var x1 := clampi(int(ceilf((rect.end.x - GROUND.position.x) * MASK_PX)), 0, s.mask.get_width())
	var y0 := clampi(int((rect.position.y - GROUND.position.y) * MASK_PX), 0, s.mask.get_height())
	var y1 := clampi(int(ceilf((rect.end.y - GROUND.position.y) * MASK_PX)), 0, s.mask.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			var col := s.mask.get_pixel(x, y)
			col[ch] = maxf(col[ch], v)
			s.mask.set_pixel(x, y, col)


## A worn strip along a polyline.
static func _paint_path(s: Ctx, pts: Array, w: float, ch: int, v: float) -> void:
	for k in pts.size() - 1:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var n := int(a.distance_to(b) / (w * 0.4)) + 1
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			_paint(s, Rect2(p.x - w * 0.5, p.z - w * 0.5, w, w), ch, v)


static func _mask_at(s: Ctx, x: float, z: float) -> Color:
	var px := clampi(int((x - GROUND.position.x) * MASK_PX), 0, s.mask.get_width() - 1)
	var py := clampi(int((z - GROUND.position.y) * MASK_PX), 0, s.mask.get_height() - 1)
	return s.mask.get_pixel(px, py)


static func _blocked(s: Ctx, x: float, z: float, pad := 0.0) -> bool:
	for k: Rect2 in s.keep_out:
		if k.grow(pad).has_point(Vector2(x, z)):
			return true
	return false


static func _puddles(s: Ctx) -> void:
	# standing water and mud: along the avenue verges, in hollows, round the yard
	for k in 34:
		var x := s.r.randf_range(X0 + 2.0, X1 - 2.0)
		var z := s.r.randf_range(Z0 + 2.0, Z1 - 2.0)
		if k < 14:
			var ax: float = AVENUES_X[k % 3]
			x = ax + (3.6 if s.r.randf() < 0.5 else -3.6) + s.r.randf_range(-0.6, 0.6)
		var w := s.r.randf_range(0.8, 2.4)
		_paint(s, Rect2(x - w * 0.5, z - w * 0.35, w, w * 0.7), 1, s.r.randf_range(0.55, 0.9))
		_paint(s, Rect2(x - w, z - w * 0.6, w * 2.0, w * 1.2), 0, 0.7)


# ================================================================ graves
## Rows of graves between x0..x1, z0..z1. Each grave: the headstone at the row line, its
## inscription facing north (-z, the way visitors come in), the plot running south behind it;
## a trodden path in front of each row.
static func _grave_field(c, s: Ctx, x0: float, x1: float, z0: float, z1: float) -> void:
	var r := s.r
	var zh := z0 + 1.3
	while zh + 2.4 <= z1:
		_paint(s, Rect2(x0, zh - 1.15, x1 - x0, 0.95), 0, 0.62)
		var x := x0 + 0.9 + r.randf_range(0.0, 0.4)
		while x <= x1 - 0.8:
			var step := r.randf_range(1.7, 2.15)
			var gx := x
			x += step
			if r.randf() < 0.09 or _blocked(s, gx, zh + 1.0, 0.8) or _blocked(s, gx, zh - 0.6, 0.2):
				continue
			_grave(c, s, Vector3(gx, 0, zh + r.randf_range(-0.12, 0.12)))
		zh += 3.6


static func _grave(c, s: Ctx, p: Vector3) -> void:
	var r := s.r
	var roll := r.randf()
	var kind := "round"
	if roll < 0.28:
		kind = "round"
	elif roll < 0.46:
		kind = "gothic"
	elif roll < 0.63:
		kind = "cross"
	elif roll < 0.74:
		kind = "broken"
	elif roll < 0.82:
		kind = "obelisk"
	elif roll < 0.9:
		kind = "chest"
	else:
		kind = ""
	var yaw := PI + r.randf_range(-0.07, 0.07)
	var b := Basis(Vector3.UP, yaw)
	var sink := 0.0
	if kind != "" and kind != "chest" and r.randf() < (0.12 if kind == "obelisk" else 0.3):
		# settled ground: the stone leans, forward, back or sideways, and sinks a little
		var lean_x := r.randf_range(0.08, 0.24) * (1.0 if r.randf() < 0.6 else -1.0)
		var lean_z := r.randf_range(-0.12, 0.12)
		b = b * Basis(Vector3.RIGHT, lean_x) * Basis(Vector3.BACK, lean_z)
		sink = r.randf_range(0.02, 0.08)
	var xf := Transform3D(b, p - Vector3(0, sink, 0))
	var age := r.randf()
	if kind != "":
		s.stones[kind].append(xf)
		s.stone_cust[kind].append(Color(pow(age, 0.6), r.randf_range(0.35, 1.0), r.randf(), r.randf()))
		var top := {"round": 1.02, "gothic": 1.2, "cross": 1.5, "broken": 0.68, "obelisk": 2.42, "chest": 0.79}
		var chance := {"obelisk": 0.4, "cross": 0.25, "chest": 0.2}
		if r.randf() < float(chance.get(kind, 0.1)):
			var lp := Vector3(0, top[kind], 0)
			if kind == "broken":
				lp.x = -0.27
			elif kind == "chest":
				lp.z = -1.0
			Crows.add_perch(c, xf * lp)
		# worn ground where visitors stand, dead grass hugging the stone
		_paint(s, Rect2(p.x - 0.45, p.z - 0.85, 0.9, 0.7), 0, 0.85)
		for k in r.randi_range(1, 3):
			var side := -1.0 if k % 2 == 0 else 1.0
			_tuft(s, p + Vector3(side * r.randf_range(0.3, 0.5), 0, r.randf_range(-0.1, 0.25)), r.randf_range(0.6, 1.0))
	# the plot behind the stone
	if kind != "chest":
		var pxf := Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0, 0.18))
		var proll := r.randf()
		if proll < 0.13:
			s.kerbs.append(pxf)
			s.kerb_cust.append(Color(age, r.randf_range(0.4, 0.9), r.randf(), 0.0))
		elif proll < 0.68 or kind == "":
			s.mounds.append(pxf)
			s.mound_cust.append(Color(0.9 if r.randf() < 0.05 else r.randf_range(0.1, 0.55), 0, 0, 0))
		if proll > 0.92 and kind != "":
			var fxf := Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0, 0.0))
			s.fences.append(fxf)
			if r.randf() < 0.5:
				Crows.add_perch(c, fxf * Vector3(0.65, 0.84, -2.3))
	# offerings in front of the stone: dead flowers, a candle
	if kind != "" and r.randf() < 0.27:
		var vp := p + Vector3(r.randf_range(-0.28, 0.28), 0, -0.32)
		s.vases.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * r.randf_range(0.85, 1.15)), vp))
	if kind != "" and r.randf() < 0.08:
		s.candles.append(Transform3D(Basis(), p + Vector3(r.randf_range(-0.3, 0.3), 0, -0.28)))
		if r.randf() < 0.5:
			s.candles.append(Transform3D(Basis(), p + Vector3(r.randf_range(-0.3, 0.3), 0, -0.42)))


static func _tuft(s: Ctx, p: Vector3, size: float) -> void:
	var r := s.r
	var b := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(size, size * r.randf_range(0.7, 1.3), size))
	s.tufts.append(Transform3D(b, p))
	var t := r.randf_range(0.75, 1.15)
	s.tuft_cust.append(Color(t, t * r.randf_range(0.92, 1.0), t * r.randf_range(0.8, 0.95)))


static func _grass(c, s: Ctx) -> void:
	var r := s.r
	var n := 0
	var tries := 0
	while n < 2600 and tries < 9000:
		tries += 1
		var x := r.randf_range(X0 + 0.6, X1 - 0.6)
		var z := r.randf_range(Z0 + 0.6, Z1 - 0.6)
		var on_avenue := false
		for ax in AVENUES_X:
			if absf(x - ax) < 3.3:
				on_avenue = true
		if on_avenue or absf(z - AVENUE_Z) < 3.8 or _blocked(s, x, z, 0.3):
			continue
		var m := _mask_at(s, x, z)
		if m.r > 0.45 or m.b > 0.2 or m.g > 0.4:
			continue
		_tuft(s, Vector3(x, 0, z), r.randf_range(0.7, 1.35))
		n += 1


## The ground: one quad per 80 m chunk with the dead-grass shader over the painted mask.
static func _ground(c, s: Ctx) -> void:
	# soften the painted edges (the shader warps and breaks them up further)
	var w := s.mask.get_width()
	var h := s.mask.get_height()
	s.mask.resize(w / 2, h / 2, Image.INTERPOLATE_BILINEAR)
	s.mask.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var mask := ImageTexture.create_from_image(s.mask)
	var noise := Kit.noise_texture(c, 811)
	c.set_meta("gy_noise", noise)
	var mat := Kit.ground_material(c, mask, GROUND, noise)
	c.set_meta("gy_mound_mat", Kit.ground_material(c, mask, GROUND, noise, true))
	var x := GROUND.position.x
	while x < GROUND.end.x - 0.01:
		var xe := minf(GROUND.end.x, (floorf(x / c.CHUNK) + 1.0) * c.CHUNK)
		var z := GROUND.position.y
		while z < GROUND.end.y - 0.01:
			var ze := minf(GROUND.end.y, (floorf(z / c.CHUNK) + 1.0) * c.CHUNK)
			var bt = c.new_batch()
			var steps := 4
			for i in steps:
				for j in steps:
					var ax := lerpf(x, xe, float(i) / steps)
					var bx := lerpf(x, xe, float(i + 1) / steps)
					var az := lerpf(z, ze, float(j) / steps)
					var bz := lerpf(z, ze, float(j + 1) / steps)
					bt.quad(Vector3(ax, 0.02, bz), Vector3(ax, 0.02, az), Vector3(bx, 0.02, az), Vector3(bx, 0.02, bz), Vector3.UP, Color.WHITE)
			var mi := MeshInstance3D.new()
			mi.name = "GraveyardGround"
			mi.mesh = Kit.mesh_of(bt)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.add_child(mi)
			s.nodes.append(mi)
			z = ze
		x = xe


## A MultiMesh with per-instance custom data, bucketed into cells for culling.
static func _mm(c, s: Ctx, name: String, mesh: Mesh, xfs: Array, cust: Array, mat: Material, range_end: float, shadow: bool, cell := 400.0) -> void:
	if xfs.is_empty():
		return
	var cells := {}
	for k in xfs.size():
		var o: Vector3 = (xfs[k] as Transform3D).origin
		var key := Vector2i(floori(o.x / cell), floori(o.z / cell))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(k)
	for key in cells:
		var idx: Array = cells[key]
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_custom_data = not cust.is_empty()
		m.mesh = mesh
		m.instance_count = idx.size()
		for k in idx.size():
			m.set_instance_transform(k, xfs[idx[k]])
			if not cust.is_empty():
				m.set_instance_custom_data(k, cust[idx[k]])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Gy_%s_%d_%d" % [name, key.x, key.y]
		mmi.multimesh = m
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if range_end > 0.0:
			mmi.visibility_range_end = range_end
			mmi.visibility_range_end_margin = 8.0
		c.add_child(mmi)
		s.nodes.append(mmi)


## The grave furniture as MultiMeshes: one per headstone kind, then mounds, kerbs, railings,
## vases, candles and the grass.
static func _furniture(c, s: Ctx) -> void:
	var stone := Kit.stone_material()
	for k in Kit.STONE_KINDS:
		_mm(c, s, "stone_" + k, Kit.headstone_mesh(c, k), s.stones[k], s.stone_cust[k], stone, DRAW_RANGE, k == "obelisk" or k == "chest" or k == "cross")
	_mm(c, s, "mound", Kit.mound_mesh(c), s.mounds, s.mound_cust, c.get_meta("gy_mound_mat"), 70.0, false)
	_mm(c, s, "kerb", Kit.kerb_mesh(c), s.kerbs, s.kerb_cust, stone, 80.0, false)
	_mm(c, s, "fence", Kit.plot_fence_mesh(c), s.fences, [], Kit.flat_material(0.5, 0.55), 60.0, false)
	_mm(c, s, "vase", Kit.vase_mesh(c), s.vases, [], Kit.flat_material(0.75, 0.2), 40.0, false)
	_mm(c, s, "candle", Kit.candle_mesh(c), s.candles, [], Kit.shader_mat(Kit.CANDLE_SHADER), 55.0, false)
	var grass := Kit.shader_mat(Kit.GRASS_SHADER, {"blades": Kit.blade_texture()})
	_mm(c, s, "grass", Kit.tuft_mesh(c), s.tufts, s.tuft_cust, grass, 42.0 if c.web_tier else 60.0, false, 70.0)


## Low ground fog: drifting sheets in two layers.
static func _fog(c, s: Ctx) -> void:
	var xfs: Array = []
	var cust: Array = []
	var r := s.r
	for k in 30:
		var p := Vector3(r.randf_range(X0 + 6.0, X1 - 6.0), [0.35, 0.75][k % 2], r.randf_range(Z0 + 6.0, Z1 - 6.0))
		var sz := r.randf_range(14.0, 22.0)
		xfs.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(sz, 1.0, sz * r.randf_range(0.6, 1.0))), p))
		cust.append(Color(r.randf_range(0.6, 1.0), 0, 0, 0))
	var mat := Kit.shader_mat(Kit.FOG_SHADER, {"noise": c.get_meta("gy_noise")})
	_mm(c, s, "fog", Kit.sheet_mesh(), xfs, cust, mat, 110.0, false)


# ================================================================ the dig site
static func _dig_site(c, s: Ctx) -> void:
	var p := DIG
	c.ck = c._chunk_of(p.x, p.z)
	var dirt = c._b("gy_dirt")
	# trampled, turned earth all round, a muddy track to the shed
	_paint(s, Rect2(p.x - 3.0, p.z - 3.2, 6.4, 6.6), 0, 0.95)
	_paint(s, Rect2(p.x - 1.4, p.z - 2.0, 4.6, 4.0), 2, 0.9)
	_paint(s, Rect2(p.x - 1.0, p.z + 1.4, 2.2, 1.4), 1, 0.7)
	_paint_path(s, [p + Vector3(0, 0, -3.0), Vector3(p.x - 1.5, 0, 116.0), Vector3(SHED.x - 3.4, 0, SHED.z + 2.0)], 1.6, 0, 0.9)
	_paint_path(s, [Vector3(AVENUES_X[2] + 3.0, 0, p.z), p + Vector3(-2.5, 0, 0)], 1.4, 0, 0.8)
	# the hole: a flat quad shaded as a deep box of dark earth (interior mapping)
	var hole := MeshInstance3D.new()
	hole.name = "OpenGrave"
	var qm := QuadMesh.new()
	qm.size = Vector2(HOLE.x * 2.0, HOLE.y * 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	hole.mesh = qm
	hole.position = p + Vector3(0, 0.045, 0)
	hole.material_override = Kit.shader_mat(Kit.HOLE_SHADER, {"half_size": HOLE, "depth": HOLE_DEPTH, "dirt": Kit.tex("mud_albedo")})
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(hole)
	s.nodes.append(hole)
	# a lip of loose spoil round the cut
	var lip := Color(0.5, 0.42, 0.36)
	for sx in [-1.0, 1.0]:
		c.box(dirt, p + Vector3(sx * (HOLE.x + 0.14), 0.04, 0), Vector3(0.3, 0.08, HOLE.y * 2.0 + 0.6), lip, Basis.IDENTITY, 8)
		c.box(dirt, p + Vector3(0, 0.04, sx * (HOLE.y + 0.14)), Vector3(HOLE.x * 2.0, 0.08, 0.3), lip, Basis.IDENTITY, 8)
	# the spoil heap east of the hole, the spade driven into it
	Kit.dirt_heap(c, dirt, p + Vector3(1.75, 0, 0.1), Vector3(1.9, 0.95, 2.9), 0.1, 51)
	Kit.dirt_heap(c, dirt, p + Vector3(1.4, 0, 1.75), Vector3(1.1, 0.45, 1.0), 0.6, 52)
	Kit.shovel(c, p + Vector3(1.6, 0.62, -0.35), 0.3, 0.32)
	# the casket waiting beside the grave on two timbers, a pickaxe dropped by the heap
	var wood = c._b("wood")
	for z in [-0.6, 0.6]:
		c.box(wood, p + Vector3(-1.45, 0.06, z), Vector3(1.0, 0.12, 0.14), Color(0.35, 0.28, 0.2))
	Kit.casket(c, p + Vector3(-1.45, 0.12, 0.05), 0.04)
	c.box_collider(p + Vector3(-1.45, 0.4, 0.05), Vector3(0.7, 0.8, 2.1))
	_pickaxe(c, p + Vector3(2.6, 0.05, -1.4), 1.2, true)
	# lowering straps across the hole, a temporary wooden cross at its head
	for z in [-0.5, 0.5]:
		c.box(c._b("paint"), p + Vector3(0, 0.07, z), Vector3(HOLE.x * 2.0 + 1.2, 0.012, 0.07), Color(0.32, 0.27, 0.2))
	c.box(wood, p + Vector3(0, 0.55, -HOLE.y - 0.45), Vector3(0.07, 1.1, 0.05), Color(0.45, 0.35, 0.24))
	c.box(wood, p + Vector3(0, 0.82, -HOLE.y - 0.45), Vector3(0.5, 0.07, 0.05), Color(0.45, 0.35, 0.24))
	Crows.add_perch(c, p + Vector3(0, 1.1, -HOLE.y - 0.45), PI)
	# a lantern on the ground at the head of the grave
	var flame := Kit.lantern(c, p + Vector3(-0.85, 0.0, -HOLE.y - 0.5), 0.3)
	var lights: Array = [[_lamp_light(c, flame + Vector3(0, 0.15, 0), 7.0), 1.6]]
	lights.append_array(c.get_meta("gy_shed_lights", []))
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(0.45, 0.45, 0.45)), flame))
	# the hole is fenced off by an invisible steep ridge: Sol can't walk in, fall through or
	# balance over it (it is too steep to stand on), and the navmesh routes round it
	var body := StaticBody3D.new()
	body.name = "OpenGraveCollider"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var hx := HOLE.x + 0.12
	var hz := HOLE.y + 0.12
	shape.points = PackedVector3Array([Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz),
		Vector3(-hx, -2.0, -hz), Vector3(hx, -2.0, -hz), Vector3(hx, -2.0, hz), Vector3(-hx, -2.0, hz),
		Vector3(0, 1.6, -hz), Vector3(0, 1.6, hz)])
	cs.shape = shape
	body.add_child(cs)
	body.position = p
	c.collider_root.add_child(body)
	# old Amos, keeping an eye on his grave and his lantern
	var keeper: Node3D = Keeper.new()
	keeper.name = "Groundskeeper"
	keeper.position = p + Vector3(-1.5, 0, -2.1)
	keeper.rotation.y = 0.55
	c.add_child(keeper)
	c.set_meta("gy_keeper", keeper)
	for l in lights:
		keeper.lights.append(l[0])
		keeper.light_energy.append(l[1])


static func _lamp_light(c, p: Vector3, rng_: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = Color(1.0, 0.66, 0.34)
	l.omni_range = rng_
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.light_energy = 1.4
	c.add_child(l)
	return l


static func _pickaxe(c, p: Vector3, yaw: float, lying: bool) -> void:
	var b := Basis(Vector3.UP, yaw)
	if lying:
		b = b * Basis(Vector3.BACK, PI * 0.5 - 0.1)
	else:
		b = b * Basis(Vector3.BACK, 0.25)
	var wood = c._b("wood")
	var met = c._b("metal")
	c.box(wood, p + b * Vector3(0, 0.45, 0), Vector3(0.045, 0.9, 0.045), Color(0.5, 0.38, 0.25), b)
	var head := p + b * Vector3(0, 0.88, 0)
	c.beam(met, head + b * Vector3(-0.32, -0.06, 0), head, 0.04, 0.05, Color(0.14, 0.13, 0.12))
	c.beam(met, head, head + b * Vector3(0.3, -0.04, 0), 0.05, 0.05, Color(0.14, 0.13, 0.12))


# ================================================================ the groundskeeper's yard
## A weathered board shack with a porch facing west, a lit window to the dig site, tools
## against the wall, a wheelbarrow, a coffin cart and caskets stacked by the wall.
static func _yard(c, s: Ctx) -> void:
	var p := SHED
	c.ck = c._chunk_of(p.x, p.z)
	var wood = c._b("wood")
	var met = c._b("metal")
	var hx := SHED_SIZE.x * 0.5
	var hz := SHED_SIZE.y * 0.5
	var fy := 0.25 # floor
	var wh := 2.45 # wall height
	var plank := Color(0.5, 0.45, 0.4)
	var dark := Color(0.3, 0.26, 0.22)
	_paint(s, Rect2(p.x - hx - 3.5, p.z - hz - 1.0, SHED_SIZE.x + 5.5, SHED_SIZE.y + 3.0), 0, 0.85)
	_paint(s, Rect2(p.x - hx - 2.6, p.z - 1.0, 2.2, 2.4), 1, 0.65)
	_paint_path(s, [Vector3(AVENUES_X[2] + 3.0, 0, p.z), Vector3(p.x - hx - 1.6, 0, p.z)], 1.8, 0, 0.9)
	# floor on blocks
	c.box(wood, p + Vector3(0, fy * 0.5, 0), Vector3(SHED_SIZE.x + 0.2, fy, SHED_SIZE.y + 0.2), dark)
	# walls with a door and a window in the west front, a window in the south end
	var y0 := fy
	var y1 := fy + wh
	var t := 0.12
	# east and north walls: solid
	c.box(wood, p + Vector3(hx - t * 0.5, (y0 + y1) * 0.5, 0), Vector3(t, wh, SHED_SIZE.y), plank)
	c.box(wood, p + Vector3(0, (y0 + y1) * 0.5, -hz + t * 0.5), Vector3(SHED_SIZE.x, wh, t), plank)
	# west wall: door at z -0.9..0.1, window at z 0.9..1.8 (sill 1.15, head 1.85)
	var wx := p.x - hx + t * 0.5
	_wall_x(c, wood, wx, p.z - hz, p.z + hz, y0, y1, [[p.z - 0.95, p.z + 0.05, y0, y0 + 2.0], [p.z + 0.85, p.z + 1.75, y0 + 1.0, y0 + 1.75]], plank, t)
	# south wall: window facing the dig site
	_wall_z(c, wood, p.z + hz - t * 0.5, p.x - hx, p.x + hx, y0, y1, [[p.x - 0.6, p.x + 0.5, y0 + 1.0, y0 + 1.75]], plank, t)
	# battens over the board joints
	var k := 0.0
	while k <= SHED_SIZE.y:
		for sx in [-1.0, 1.0]:
			var bz := p.z - hz + k
			var skip: bool = sx < 0.0 and ((bz > p.z - 1.0 and bz < p.z + 0.1) or (bz > p.z + 0.8 and bz < p.z + 1.8))
			if not skip:
				c.box(wood, Vector3(p.x + sx * (hx + 0.01), (y0 + y1) * 0.5, bz), Vector3(0.04, wh, 0.07), dark)
		k += 0.5
	# the door, a hair ajar, and the lit windows (lamp material: amber at night)
	var door_b := Basis(Vector3.UP, -0.25)
	var hinge := Vector3(wx - 0.02, 0, p.z - 0.95)
	c.box(wood, hinge + door_b * Vector3(0, y0 + 1.0, 0.5), Vector3(0.05, 2.0, 1.0), Color(0.25, 0.2, 0.16), door_b)
	c.box(c._b("lamp"), Vector3(wx + 0.03, y0 + 1.0, p.z - 0.45), Vector3(0.02, 1.95, 0.95), Color.WHITE)
	for w in [[Vector3(wx - 0.01, y0 + 1.375, p.z + 1.3), Vector3(0.02, 0.75, 0.9), true], [Vector3(p.x - 0.05, y0 + 1.375, p.z + hz - t * 0.5 + 0.01), Vector3(1.1, 0.75, 0.02), false]]:
		c.box(c._b("lamp"), w[0], w[1], Color.WHITE)
		var along := Vector3(0, 0, 1) if w[2] else Vector3(1, 0, 0)
		var out := Vector3(-1, 0, 0) if w[2] else Vector3(0, 0, 1)
		var wl: float = (w[1] as Vector3).dot(along)
		for e in [-0.5, 0.5]:
			c.box(wood, w[0] + along * wl * e + out * 0.04 , Vector3(0.07, 0.85, 0.07) if not w[2] else Vector3(0.07, 0.85, 0.07), dark)
		c.box(wood, w[0] + out * 0.04 + Vector3(0, 0.4, 0), along * (wl + 0.14) + Vector3(0.07, 0.07, 0.07) - along * 0.07, dark)
		c.box(wood, w[0] + out * 0.06 - Vector3(0, 0.42, 0), along * (wl + 0.24) + Vector3(0.1, 0.05, 0.1) - along * 0.1, dark)
		c.box(wood, w[0] + out * 0.03, Vector3(0.03, 0.75, 0.03) if w[2] else Vector3(0.03, 0.75, 0.03), dark)
	# gabled tin roof, ridge along z, overhanging, and a lean-to over the porch
	var roof = c._b("corrugated")
	var eave := y1 + 0.05
	var ridge := y1 + 0.95
	var ov := 0.35
	var rc := Color(0.55, 0.5, 0.46)
	for sx in [-1.0, 1.0]:
		var e0 := Vector3(p.x + sx * (hx + ov), eave - ov * 0.45, p.z - hz - ov)
		var e1 := Vector3(p.x + sx * (hx + ov), eave - ov * 0.45, p.z + hz + ov)
		var r0 := Vector3(p.x, ridge, p.z - hz - ov)
		var r1 := Vector3(p.x, ridge, p.z + hz + ov)
		var n := Vector3(sx * (ridge - eave), hx, 0).normalized()
		roof.quad(e0, r0, r1, e1, n, rc)
		roof.quad(e1, r1, r0, e0, -n, rc * Color(0.6, 0.6, 0.6))
	for sz in [-1.0, 1.0]:
		c._b("wood").tri(Vector3(p.x - hx, eave, p.z + sz * hz), Vector3(p.x, ridge, p.z + sz * hz), Vector3(p.x + hx, eave, p.z + sz * hz), Vector3(0, 0, sz), plank)
	var px0 := p.x - hx - 1.7
	var pe0 := Vector3(px0, y1 - 0.45, p.z - hz)
	var pe1 := Vector3(px0, y1 - 0.45, p.z + hz)
	var pr0 := Vector3(p.x - hx, eave - 0.2, p.z - hz)
	var pr1 := Vector3(p.x - hx, eave - 0.2, p.z + hz)
	roof.quad(pe0, pr0, pr1, pe1, Vector3(-0.35, 1, 0).normalized(), rc * Color(0.9, 0.85, 0.8))
	roof.quad(pe1, pr1, pr0, pe0, Vector3(0.35, -1, 0).normalized(), rc * Color(0.5, 0.5, 0.5))
	Crows.add_perch(c, Vector3(p.x, ridge + 0.03, p.z - 1.4), 0.0)
	Crows.add_perch(c, Vector3(p.x, ridge + 0.03, p.z + 1.2), PI)
	# porch: deck, two posts, a bench under the window, the lantern by the door
	c.box(wood, Vector3(px0 + 0.85, 0.08, p.z), Vector3(1.7, 0.16, SHED_SIZE.y), dark * Color(1.2, 1.2, 1.2))
	for z in [p.z - hz + 0.15, p.z + hz - 0.15]:
		c.box(wood, Vector3(px0 + 0.12, y1 * 0.5, z), Vector3(0.12, y1 - 0.4, 0.12), dark)
		c.post_collider(Vector3(px0 + 0.12, 0, z), 0.1, 2.0)
	var bz := p.z + 1.3
	var bxp := p.x - hx - 0.35
	c.box(wood, Vector3(bxp, 0.6, bz), Vector3(0.4, 0.06, 1.5), Color(0.42, 0.34, 0.26))
	c.box(wood, Vector3(bxp + 0.16, 0.95, bz), Vector3(0.05, 0.4, 1.5), Color(0.42, 0.34, 0.26))
	for z in [bz - 0.65, bz + 0.65]:
		c.box(wood, Vector3(bxp, 0.38, z), Vector3(0.36, 0.44, 0.06), dark)
	c.box_collider(Vector3(bxp, 0.4, bz), Vector3(0.45, 0.8, 1.5))
	var lamp_p := Vector3(wx - 0.18, y0 + 1.85, p.z + 0.35)
	c.box(met, lamp_p + Vector3(0.1, 0.32, 0), Vector3(0.22, 0.03, 0.03), Color(0.08, 0.07, 0.06))
	var fl := Kit.lantern(c, lamp_p - Vector3(0, 0.12, 0), 0.0)
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(0.6, 0.6, 0.6)), fl))
	var porch_light := _lamp_light(c, fl + Vector3(-0.3, 0, 0), 8.0)
	var inner := _lamp_light(c, Vector3(p.x - 0.3, y0 + 1.7, p.z + 0.8), 5.5) # spills out of the windows
	c.set_meta("gy_shed_lights", [[porch_light, 1.8], [inner, 1.2]])
	# stovepipe
	c.cyl(met, Vector3(p.x + 0.9, ridge - 0.45, p.z - 1.3), 0.09, 0.09, 1.3, 6, Color(0.12, 0.11, 0.1))
	c.cyl(met, Vector3(p.x + 0.9, ridge + 0.85, p.z - 1.3), 0.17, 0.02, 0.18, 6, Color(0.12, 0.11, 0.1))
	# tools against the south wall: a rake, a pickaxe, a spare spade
	var sw := p.z + hz + 0.12
	var rake_b := Basis(Vector3.BACK, 0.2)
	c.box(wood, Vector3(p.x + 1.3, 0.95, sw), Vector3(0.04, 1.75, 0.04), Color(0.5, 0.38, 0.25), rake_b)
	var rh := Vector3(p.x + 1.3, 0.12, sw) + rake_b * Vector3(0, 0.0, 0) + Vector3(-0.17, 0, 0)
	c.box(met, rh + Vector3(0, 0.06, 0), Vector3(0.45, 0.04, 0.05), Color(0.12, 0.11, 0.1))
	for i in 7:
		c.box(met, rh + Vector3(-0.2 + i * 0.066, 0.0, 0.02), Vector3(0.012, 0.1, 0.012), Color(0.12, 0.11, 0.1))
	_pickaxe(c, Vector3(p.x + 0.85, 0.0, sw + 0.05), 0.0, false)
	Kit.shovel(c, Vector3(p.x + 1.65, 0.0, sw + 0.1), PI * 0.5, -0.18)
	# the wheelbarrow off the porch corner, the coffin cart with its casket, caskets stacked
	_wheelbarrow(c, Vector3(p.x - hx - 2.4, 0, p.z + hz + 1.4), 0.6)
	_coffin_cart(c, Vector3(p.x - 1.0, 0, p.z + hz + 2.2), PI * 0.5 + 0.08)
	var stack := Vector3(p.x + hx + 0.75, 0, p.z + 0.2)
	Kit.casket(c, stack, 0.0)
	Kit.casket(c, stack + Vector3(0.05, 0.6, -0.1), 0.06)
	c.box_collider(stack + Vector3(0, 0.6, 0), Vector3(0.75, 1.2, 2.2))
	Crows.add_perch(c, stack + Vector3(0.05, 1.32, 0.5))
	# colliders and footprint
	c.box_collider(p + Vector3(0, 1.4, 0), Vector3(SHED_SIZE.x, 2.8, SHED_SIZE.y))
	c.lots.append(Rect2(p.x - hx, p.z - hz, SHED_SIZE.x, SHED_SIZE.y))
	c.lots.append(Rect2(px0, p.z - hz, 1.7, SHED_SIZE.y))
	c.hlod_box(Rect2(p.x - hx, p.z - hz, SHED_SIZE.x, SHED_SIZE.y), 3.0, Color(0.4, 0.36, 0.32))
	var marker := Node3D.new()
	marker.name = "GroundskeeperShed"
	marker.position = p
	c.add_child(marker)


## A board wall along z at x (y0..y1), with rectangular openings [[z0, z1, y0, y1]].
static func _wall_x(c, bt, x: float, z0: float, z1: float, y0: float, y1: float, holes: Array, col: Color, t: float) -> void:
	var z := z0
	for h in holes:
		if h[0] > z:
			c.box(bt, Vector3(x, (y0 + y1) * 0.5, (z + h[0]) * 0.5), Vector3(t, y1 - y0, h[0] - z), col)
		if h[2] > y0:
			c.box(bt, Vector3(x, (y0 + h[2]) * 0.5, (h[0] + h[1]) * 0.5), Vector3(t, h[2] - y0, h[1] - h[0]), col)
		if h[3] < y1:
			c.box(bt, Vector3(x, (h[3] + y1) * 0.5, (h[0] + h[1]) * 0.5), Vector3(t, y1 - h[3], h[1] - h[0]), col)
		z = h[1]
	if z < z1:
		c.box(bt, Vector3(x, (y0 + y1) * 0.5, (z + z1) * 0.5), Vector3(t, y1 - y0, z1 - z), col)


static func _wall_z(c, bt, z: float, x0: float, x1: float, y0: float, y1: float, holes: Array, col: Color, t: float) -> void:
	var x := x0
	for h in holes:
		if h[0] > x:
			c.box(bt, Vector3((x + h[0]) * 0.5, (y0 + y1) * 0.5, z), Vector3(h[0] - x, y1 - y0, t), col)
		if h[2] > y0:
			c.box(bt, Vector3((h[0] + h[1]) * 0.5, (y0 + h[2]) * 0.5, z), Vector3(h[1] - h[0], h[2] - y0, t), col)
		if h[3] < y1:
			c.box(bt, Vector3((h[0] + h[1]) * 0.5, (h[3] + y1) * 0.5, z), Vector3(h[1] - h[0], y1 - h[3], t), col)
		x = h[1]
	if x < x1:
		c.box(bt, Vector3((x + x1) * 0.5, (y0 + y1) * 0.5, z), Vector3(x1 - x, y1 - y0, t), col)


static func _wheelbarrow(c, p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var met = c._b("metal")
	var wood = c._b("wood")
	var tray := Color(0.24, 0.26, 0.24)
	var pts := [Vector3(-0.3, 0.32, -0.45), Vector3(0.3, 0.32, -0.45), Vector3(0.3, 0.32, 0.25), Vector3(-0.3, 0.32, 0.25),
		Vector3(-0.38, 0.62, -0.62), Vector3(0.38, 0.62, -0.62), Vector3(0.38, 0.62, 0.48), Vector3(-0.38, 0.62, 0.48)]
	var wp := []
	for q in pts:
		wp.append(p + b * q)
	c.hexa(met, wp, tray)
	c.box(c._b("gy_dirt"), p + b * Vector3(0, 0.6, -0.05), Vector3(0.66, 0.06, 0.95), Color(0.5, 0.42, 0.36), b)
	c.cyl(met, p + b * Vector3(-0.05, 0.2, 0.75), 0.2, 0.2, 0.1, 8, Color(0.08, 0.08, 0.08), true, b * Basis(Vector3.BACK, PI * 0.5))
	for sx in [-1.0, 1.0]:
		c.beam(wood, p + b * Vector3(sx * 0.2, 0.22, 0.72), p + b * Vector3(sx * 0.28, 0.5, -1.15), 0.05, 0.05, Color(0.45, 0.35, 0.24))
		c.beam(met, p + b * Vector3(sx * 0.22, 0.32, -0.4), p + b * Vector3(sx * 0.24, 0.0, -0.5), 0.03, 0.03, Color(0.1, 0.1, 0.1))
	c.box_collider(p + b * Vector3(0, 0.35, -0.1), Vector3(0.8, 0.7, 1.6), yaw)


static func _coffin_cart(c, p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var wood = c._b("wood")
	var met = c._b("metal")
	c.box(wood, p + b * Vector3(0, 0.55, 0), Vector3(0.85, 0.07, 2.3), Color(0.38, 0.3, 0.22), b)
	for sx in [-1.0, 1.0]:
		c.box(wood, p + b * Vector3(sx * 0.45, 0.65, 0), Vector3(0.05, 0.15, 2.3), Color(0.32, 0.25, 0.18), b)
		c.cyl(met, p + b * Vector3(sx * 0.52, 0.42, 0.25), 0.42, 0.42, 0.06, 10, Color(0.1, 0.09, 0.08), true, b * Basis(Vector3.BACK, PI * 0.5))
	c.beam(met, p + b * Vector3(-0.55, 0.42, 0.25), p + b * Vector3(0.55, 0.42, 0.25), 0.04, 0.04, Color(0.1, 0.09, 0.08))
	c.box(wood, p + b * Vector3(0, 0.27, -1.0), Vector3(0.06, 0.55, 0.06), Color(0.32, 0.25, 0.18), b)
	for sx in [-1.0, 1.0]:
		c.beam(wood, p + b * Vector3(sx * 0.35, 0.58, -1.1), p + b * Vector3(sx * 0.3, 0.8, -1.9), 0.05, 0.05, Color(0.42, 0.33, 0.24))
	Kit.casket(c, p + b * Vector3(0, 0.59, 0.05), yaw)
	c.box_collider(p + b * Vector3(0, 0.6, 0), Vector3(1.1, 1.2, 2.4), yaw)


# ================================================================ gates and trees
## Wrought-iron gates in the gateways, standing open; an iron arch with a cross over the main
## (north, centre) entrance.
static func _gates(c) -> void:
	var col := Color(0.05, 0.048, 0.045)
	for z in [Z0, Z1]:
		for ax in AVENUES_X:
			var main: bool = z == Z0 and ax == 0.0
			c.ck = c._chunk_of(ax, z)
			var met = c._b("metal")
			var inward := 1.0 if z == Z0 else -1.0
			for side in [-1.0, 1.0]:
				var hinge := Vector3(ax + side * 3.1, 0, z)
				var open: float = (1.25 if main else 1.0 + absf(ax) * 0.004) * side * inward
				var b := Basis(Vector3.UP, open)
				var w := 3.0
				var h := 2.5 if main else 2.2
				var o: float = -side
				for y in [0.15, 1.0, h - 0.15]:
					c.box(met, hinge + b * Vector3(o * w * 0.5, y, 0), Vector3(w, 0.05, 0.05), col, b)
				var n := 19
				for i in n + 1:
					var bx: float = o * w * float(i) / n
					var bh := h + 0.12 * sin(PI * float(i) / n) * (2.0 if main else 1.0)
					c.box(met, hinge + b * Vector3(bx, bh * 0.5, 0), Vector3(0.025, bh, 0.025), col, b, 12)
					c.cyl(met, hinge + b * Vector3(bx, bh, 0), 0.035, 0.0, 0.12, 3, col, false)
				# scrollwork rings between the lower rails
				for i in 4:
					var cx: float = o * w * (0.15 + i * 0.23)
					c.cyl(met, hinge + b * Vector3(cx, 0.58, 0), 0.16, 0.16, 0.03, 8, col, false, b * Basis(Vector3.RIGHT, PI * 0.5))
			if main:
				# the arch over the piers: two curved bars, a nameplate and a cross
				var prev_a := Vector3.ZERO
				var prev_b := Vector3.ZERO
				for i in 13:
					var t := float(i) / 12.0
					var x: float = ax - 3.6 + 7.2 * t
					var y := 3.4 + sin(t * PI) * 1.6
					var pa := Vector3(x, y, z)
					var pb := Vector3(x, y - 0.35, z)
					if i > 0:
						c.beam(met, prev_a, pa, 0.06, 0.06, col)
						c.beam(met, prev_b, pb, 0.05, 0.05, col)
						c.beam(met, pa, pb, 0.025, 0.025, col)
					prev_a = pa
					prev_b = pb
				c.box(met, Vector3(ax, 4.55, z), Vector3(2.6, 0.42, 0.05), Color(0.09, 0.085, 0.08))
				c.box(met, Vector3(ax, 5.55, z), Vector3(0.07, 0.75, 0.07), col)
				c.box(met, Vector3(ax, 5.7, z), Vector3(0.42, 0.07, 0.07), col)
				Crows.add_perch(c, Vector3(ax + 1.4, 4.8 + 0.03, z), PI * 0.5)
			for s in [-1.0, 1.0]:
				if c.rng.randf() < 0.5:
					Crows.add_perch(c, Vector3(ax + s * 3.6, 3.6, z))


static func _trees(c, s: Ctx) -> void:
	for k in TREES.size():
		var t: Array = TREES[k]
		var p := Vector3(t[0], 0, t[1])
		c.ck = c._chunk_of(p.x, p.z)
		var tips := Kit.dead_tree(c, c._b("gy_bark"), p, t[2], 900 + k)
		c.post_collider(p, 0.3, 3.0)
		_paint(s, Rect2(p.x - 1.5, p.z - 1.5, 3.0, 3.0), 0, 0.7)
		tips.shuffle()
		for i in mini(4, tips.size()):
			Crows.add_perch(c, tips[i] + Vector3(0, 0.02, 0))


# ================================================================ crows round the map
## Perches outside the cemetery, picked once the whole city is built: lamp posts (on the
## ladder rest under the lantern), rooftop corners and lamp poles out in the wilds.
static func world_perches(c) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var out: Array = []
	var lamps: Array = c.props.get("lamp", [])
	var foot := Rect2(X0, Z0, X1 - X0, Z1 - Z0)
	var picks := 0
	for k in lamps.size():
		var xf: Transform3D = lamps[k]
		if foot.has_point(Vector2(xf.origin.x, xf.origin.z)) and r.randf() < 0.5:
			continue
		if r.randf() < 0.12 and picks < 28:
			out.append([xf * Vector3(0.24 if r.randf() < 0.5 else -0.24, 2.79, 0), INF])
			picks += 1
	var roofs := 0
	for b in c.blocks:
		for i in (b.lots as Array).size():
			if r.randf() < 0.035 and roofs < 16:
				var lot: Rect2 = b.lots[i]
				var hgt: float = b.heights[i]
				var corner := Vector2(lot.position.x + 0.35 if r.randf() < 0.5 else lot.end.x - 0.35, lot.position.y + 0.35 if r.randf() < 0.5 else lot.end.y - 0.35)
				out.append([Vector3(corner.x, hgt + 0.02, corner.y), INF])
				roofs += 1
	return out


## Whitewashed perimeter walls with gates on the avenues.
static func _walls(c) -> void:
	var h := 2.6
	var t := 0.5
	var col := Color(0.82, 0.8, 0.74)
	var segs: Array = []
	# north and south walls, broken by the avenue gates
	for z in [Z0, Z1]:
		var x := X0
		for ax in AVENUES_X:
			segs.append([Vector3(x, 0, z), Vector3(ax - 3.5, 0, z)])
			x = ax + 3.5
		segs.append([Vector3(x, 0, z), Vector3(X1, 0, z)])
	for x in [X0, X1]:
		segs.append([Vector3(x, 0, Z0), Vector3(x, 0, AVENUE_Z - 4.0)])
		segs.append([Vector3(x, 0, AVENUE_Z + 4.0), Vector3(x, 0, Z1)])
	for s in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var m := (a + b) * 0.5
		var size := Vector3(absf(b.x - a.x) + t, h, absf(b.z - a.z) + t)
		c.ck = c._chunk_of(m.x, m.z)
		c.box(c._b("stucco"), m + Vector3(0, h * 0.5, 0), size, col, Basis.IDENTITY, 8)
		c.box(c._b("stone"), m + Vector3(0, h + 0.08, 0), size + Vector3(0.2, 0.16, 0.2), Color(0.6, 0.58, 0.55))
		c.box_collider(m + Vector3(0, h * 0.5, 0), size)
		c.lots.append(Rect2(minf(a.x, b.x) - t * 0.5, minf(a.z, b.z) - t * 0.5, size.x, size.z))
	# gate piers with urns
	for z in [Z0, Z1]:
		for ax in AVENUES_X:
			for s in [-1.0, 1.0]:
				var p := Vector3(ax + s * 3.6, 0, z)
				c.ck = c._chunk_of(p.x, p.z)
				c.box(c._b("stucco"), p + Vector3(0, 1.7, 0), Vector3(0.9, 3.4, 0.9), col)
				c.cyl(c._b("stone"), p + Vector3(0, 3.4, 0), 0.35, 0.2, 0.6, 8, Color(0.55, 0.53, 0.5))


## A tomb row with two mausoleums (asset round 3 prop, gothic stone, 4.2 m) facing the cross
## avenue (face +1: south, -1: north); family tombs fill the gaps either side.
static func _mausoleum_row(c, r: RandomNumberGenerator, x0: float, x1: float, z: float, face: float, xfs: Array) -> void:
	var w := x1 - x0
	var mx := [x0 + w * 0.25, x0 + w * 0.75]
	var hw := 2.0 # half the footprint's width plus a gap
	var segs := [[x0, mx[0] - hw], [mx[0] + hw, mx[1] - hw], [mx[1] + hw, x1]]
	for s in segs:
		if s[1] - s[0] >= 2.2:
			_tomb_row(c, r, s[0], s[1], z)
	var depth := 4.2 # the model scaled to MAUSOLEUM_H is about 3.3 x 4.2 m
	var cz := z + 3.0 - depth * 0.5 + 0.2 if face > 0.0 else z + depth * 0.5 - 0.1
	for x: float in mx:
		var p := Vector3(x, -0.05, cz)
		xfs.append(Transform3D(Basis(Vector3.UP, 0.0 if face > 0.0 else PI), p))
		c.box_collider(p + Vector3(0, 1.7, 0), Vector3(3.2, 3.4, depth - 0.2))
		c.lots.append(Rect2(x - 1.7, cz - depth * 0.5, 3.4, depth))
		c.hlod_box(Rect2(x - 1.6, cz - depth * 0.5, 3.2, depth), MAUSOLEUM_H * 0.8, Color(0.6, 0.58, 0.55))


## One row of family tombs between x0 and x1, their doors facing south (+z).
static func _tomb_row(c, r: RandomNumberGenerator, x0: float, x1: float, z: float) -> void:
	var cx := (x0 + x1) * 0.5
	c.ck = c._chunk_of(cx, z)
	var st = c._b("stucco")
	var stone = c._b("stone")
	var trim = c._b("trim")
	var d := 3.0
	var x := x0
	var hmax := 0.0
	while x + 2.2 <= x1:
		var w := r.randf_range(2.2, 3.0)
		if x + w > x1:
			w = x1 - x
		var h := r.randf_range(2.0, 3.2)
		hmax = maxf(hmax, h)
		var g := r.randf_range(0.7, 0.95)
		var col := Color(g, g * 0.98, g * 0.92) if r.randf() < 0.8 else Color(0.55, 0.5, 0.46)
		var p := Vector3(x + w * 0.5, 0, z + d * 0.5)
		var dark := col * Color(0.62, 0.6, 0.58)
		# a stepped plinth, the vault, a cornice and pilasters framing the door
		c.box(stone, p + Vector3(0, 0.18, 0), Vector3(w - 0.05, 0.36, d + 0.25), dark, Basis.IDENTITY, 8)
		c.box(st, p + Vector3(0, h * 0.5 + 0.18, 0), Vector3(w - 0.25, h - 0.36, d), col, Basis.IDENTITY, 8)
		c.box(stone, p + Vector3(0, h - 0.05, 0), Vector3(w - 0.08, 0.2, d + 0.16), col * Color(0.92, 0.92, 0.9))
		for sx in [-1.0, 1.0]:
			c.box(st, p + Vector3(sx * (w * 0.5 - 0.3), h * 0.5, d * 0.5 + 0.05), Vector3(0.26, h - 0.2, 0.12), col * Color(0.95, 0.95, 0.95), Basis.IDENTITY, 8)
		var hw := (w - 0.1) * 0.5
		var y := h + 0.05
		var top := h + 0.05 + minf(w * 0.32, 0.85)
		if r.randf() < 0.75:
			# a pitched roof over a pediment, a cross on the ridge
			c.hexa(stone, [p + Vector3(-hw, y, -d * 0.5 - 0.08), p + Vector3(hw, y, -d * 0.5 - 0.08), p + Vector3(hw, y, d * 0.5 + 0.08), p + Vector3(-hw, y, d * 0.5 + 0.08),
				p + Vector3(-0.05, top, -d * 0.5 - 0.08), p + Vector3(0.05, top, -d * 0.5 - 0.08), p + Vector3(0.05, top, d * 0.5 + 0.08), p + Vector3(-0.05, top, d * 0.5 + 0.08)], col * Color(0.85, 0.85, 0.85))
			if r.randf() < 0.8:
				var cp := p + Vector3(0, top, d * 0.5 - 0.1)
				var ch := r.randf_range(0.8, 1.2)
				c.box(stone, cp + Vector3(0, 0.1, 0), Vector3(0.3, 0.2, 0.3), dark)
				c.box(stone, cp + Vector3(0, 0.2 + ch * 0.5, 0), Vector3(0.12, ch, 0.12), Color(0.55, 0.53, 0.5))
				c.box(stone, cp + Vector3(0, 0.2 + ch * 0.7, 0), Vector3(ch * 0.55, 0.11, 0.12), Color(0.55, 0.53, 0.5))
		else:
			# a flat top with a balustrade and an urn
			c.box(stone, p + Vector3(0, h + 0.2, 0), Vector3(w - 0.2, 0.3, d), col * Color(0.88, 0.88, 0.86))
			c.cyl(stone, p + Vector3(0, h + 0.35, d * 0.5 - 0.5), 0.12, 0.22, 0.5, 8, dark)
			c.cyl(stone, p + Vector3(0, h + 0.85, d * 0.5 - 0.5), 0.22, 0.08, 0.25, 8, dark)
		# sealed door tablet with an iron grille in front
		trim.quad(p + Vector3(-0.5, 0.36, d * 0.5 + 0.02), p + Vector3(-0.5, 1.8, d * 0.5 + 0.02), p + Vector3(0.5, 1.8, d * 0.5 + 0.02), p + Vector3(0.5, 0.36, d * 0.5 + 0.02), Vector3(0, 0, 1), Color(0.26, 0.25, 0.23))
		for gx in 5:
			c.box(c._b("metal"), p + Vector3(-0.4 + gx * 0.2, 1.05, d * 0.5 + 0.09), Vector3(0.03, 1.4, 0.03), Color(0.05, 0.05, 0.05))
		if r.randf() < 0.08:
			c.box(c._b("lamp"), p + Vector3(0.7, 0.2, d * 0.5 + 0.25), Vector3(0.1, 0.16, 0.1), Color.WHITE) # a grave candle
		x += w
	c.box_collider(Vector3(cx, 1.6, z + d * 0.5), Vector3(x1 - x0, 3.2, d))
	c.lots.append(Rect2(x0, z, x1 - x0, d))
	c.hlod_box(Rect2(x0, z, x1 - x0, d), hmax, Color(0.85, 0.83, 0.78))


## The mortuary chapel at the head of the centre avenue: a steep gable, a bell turret with
## a spire and a lancet that glows at night.
static func _chapel(c) -> void:
	var p := CHAPEL
	c.ck = "M"
	var st = c._b("stucco")
	var col := Color(0.84, 0.82, 0.76)
	var w := 9.0
	var d := 14.0
	var h := 8.0
	c.box(st, p + Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, d), col, Basis.IDENTITY, 8)
	var roof = c._b("concrete")
	var rc := Color(0.25, 0.25, 0.28)
	var hw := w * 0.5 + 0.4
	var ridge := h + 5.5
	roof.quad(p + Vector3(-hw, h, d + 0.4), p + Vector3(0, ridge, d + 0.4), p + Vector3(0, ridge, -0.4), p + Vector3(-hw, h, -0.4), Vector3(-5.5, hw, 0).normalized(), rc)
	roof.quad(p + Vector3(hw, h, -0.4), p + Vector3(0, ridge, -0.4), p + Vector3(0, ridge, d + 0.4), p + Vector3(hw, h, d + 0.4), Vector3(5.5, hw, 0).normalized(), rc)
	st.tri(p + Vector3(-w * 0.5, h, 0), p + Vector3(0, ridge, 0), p + Vector3(w * 0.5, h, 0), Vector3(0, 0, -1), col)
	st.tri(p + Vector3(-w * 0.5, h, d), p + Vector3(0, ridge, d), p + Vector3(w * 0.5, h, d), Vector3(0, 0, 1), col)
	# bell turret and spire over the north (entrance) gable
	var tp := p + Vector3(0, ridge - 1.0, 1.2)
	c.box(st, tp + Vector3(0, 1.8, 0), Vector3(2.2, 3.6, 2.2), col)
	c.cyl(c._b("concrete"), tp + Vector3(0, 3.6, 0), 1.6, 0.0, 6.5, 8, rc)
	c.box(c._b("metal"), tp + Vector3(0, 10.6, 0), Vector3(0.08, 1.4, 0.08), Color(0.1, 0.1, 0.1))
	c.box(c._b("metal"), tp + Vector3(0, 10.9, 0), Vector3(0.7, 0.08, 0.08), Color(0.1, 0.1, 0.1))
	# door and a glowing lancet above it on the north face
	var f = c.new_facade()
	f.o = p + Vector3(w * 0.5, 0, -0.01)
	f.r = Vector3(-1, 0, 0)
	f.n = Vector3(0, 0, -1)
	f.w = w
	c._lancet(f, w * 0.5, 4.2, 1.6, 2.8, 1.4)
	c._b("trim").quad(p + Vector3(1.0, 0, -0.03), p + Vector3(1.0, 3.0, -0.03), p + Vector3(-1.0, 3.0, -0.03), p + Vector3(-1.0, 0, -0.03), Vector3(0, 0, -1), Color(0.15, 0.08, 0.05))
	c.box_collider(p + Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, d))
	c.lots.append(Rect2(p.x - w * 0.5, p.z, w, d))
	c.ck = c._chunk_of(p.x, p.z)
	c._light_pool(p + Vector3(0, 0, -3.0), 4.0)
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(1.5, 1.5, 1.5)), p + Vector3(0, 3.4, -0.6)))
