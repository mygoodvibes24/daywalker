extends RefCounted
## St. Roch Cemetery, the south end of the Old Quarter: a walled city of the dead with
## whitewashed above-ground tombs in narrow rows, gravel avenues, weeping angels at the
## crossing, a mortuary chapel with a lit lancet, and the riverside promenade beyond.

const Layout = preload("res://scripts/map/map_layout.gd")

const X0 := -66.0
const X1 := 66.0
const Z0 := 100.0
const Z1 := 200.0
const AVENUES_X := [-40.0, 0.0, 40.0]
const AVENUE_Z := 150.0
const CHAPEL := Vector3(0, 0, 178)
const MAUSOLEUM_H := 4.2


static func build(c) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 6603
	c.ground_rect("earth", -70.0, 95.0, 70.0, 203.75, Color.WHITE, 0.02)
	for ax in AVENUES_X:
		c.ground_path("cobble_fan", [Vector3(ax, 0, Z0 - 4.0), Vector3(ax, 0, Z1 + 3.0)], 6.0, Color(0.5, 0.48, 0.45), 0.03, 16.0)
	c.ground_path("cobble_fan", [Vector3(X0, 0, AVENUE_Z), Vector3(X1, 0, AVENUE_Z)], 7.0, Color(0.5, 0.48, 0.45), 0.031, 16.0)
	_walls(c)
	# tomb rows in the four bands between the avenues, north and south of the cross avenue
	var bands := [[X0 + 2.0, -43.5], [-36.5, -3.5], [3.5, 36.5], [43.5, X1 - 2.0]]
	var mxfs: Array = [] # the mausoleums (one MultiMesh)
	for bi in bands.size():
		var b: Array = bands[bi]
		for zr in [[Z0 + 4.0, AVENUE_Z - 5.0], [AVENUE_Z + 5.0, Z1 - 4.0]]:
			var z: float = zr[0]
			while z + 3.0 <= zr[1]:
				# the inner bands' rows either side of the cross avenue: grand family mausoleums
				# facing the avenue, with ordinary tombs in between
				var face := 0.0
				if bi == 1 or bi == 2:
					if zr[0] < AVENUE_Z and z + 10.0 > zr[1]:
						face = 1.0
					elif zr[0] > AVENUE_Z and z == zr[0]:
						face = -1.0
				if face != 0.0:
					_mausoleum_row(c, r, b[0], b[1], z, face, mxfs)
				else:
					_tomb_row(c, r, b[0], b[1], z)
				z += 7.0
	c.glb_multimesh("mausoleum", MAUSOLEUM_H, mxfs, 80.0, 170.0, true)
	_chapel(c)
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
