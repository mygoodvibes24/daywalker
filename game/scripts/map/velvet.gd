extends RefCounted
## The Velvet Mile (docs/concept_art/03_velvet_mile.jpg): the Court's neon boulevard.
## city.gd builds the Art Deco blocks either side; this adds the Mile itself (a palm median
## with the streetcar line down it), club entrances with fan marquees, brass stanchions
## and velvet ropes, the Palm Square (a boss arena), Le Velours opera house (the Courtier
## landmark) and the harbour promenade at the south end with a tall ship in the river.

const Layout = preload("res://scripts/map/map_layout.gd")

const MILE_X := 150.0
const Z0 := -60.0
const Z1 := 200.0
const SQUARE := Rect2(120, 100, 60, 40)
const OPERA := Rect2(176, 44, 20, 32) # the building; its forecourt runs out to x 160


static func build(c) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 2207
	_mile(c, r)
	_square(c, r)
	_opera(c)
	_clubs(c, r)
	_promenade(c, r, 60.0, 226.0)
	_tall_ship(c, Vector3(150, 0, 248))
	c.add_anchor(Vector3(166, 0, 60), "landmark")
	for p in [Vector3(135.2, 0, -28), Vector3(164.8, 0, 92), Vector3(135.2, 0, 172), Vector3(164.8, 0, 12)]:
		c.cache_spots.append({"pos": p + Vector3(0, 0.1, 0), "yaw": 0.0, "coffin": true})


## The boulevard's median: cobbles, palms, twin lanterns with crimson banners, rails.
static func _mile(c, r: RandomNumberGenerator) -> void:
	var z := Z0
	while z < Z1 - 0.1:
		var z1 := z + 20.0
		c.ck = c._chunk_of(MILE_X, z + 10.0)
		var in_square := z >= SQUARE.position.y - 0.1 and z1 <= SQUARE.end.y + 0.1
		if not in_square:
			c._slab(MILE_X - 2.6, z + 0.6, MILE_X + 2.6, z1 - 0.6, "cobble_fan", Color(0.6, 0.5, 0.48), Color(0.62, 0.6, 0.57))
			c._palm(Vector3(MILE_X, 0.1, z + 5.0))
			for sx in [-1.0, 1.0]:
				var lp := Vector3(MILE_X + sx * 1.6, 0.1, z + 15.0)
				c.path_lamp(lp, Vector3(sx, 0, 0))
				_banner(c, lp, sx)
		# streetcar rails in both carriageways
		var m = c._b("metal")
		for rx in [MILE_X - 5.4, MILE_X + 5.4]:
			for g in [-0.72, 0.72]:
				c._strip(m, Vector3(rx + g, 0.018, z), Vector3(rx + g, 0.018, z1), 0.09, Color(0.55, 0.52, 0.5))
		c.add_road(Vector3(MILE_X - 6.0, 0, z + 10.0))
		c.add_road(Vector3(MILE_X + 6.0, 0, z + 10.0))
		z = z1
	_streetcar(c, Vector3(MILE_X + 5.4, 0, 28.0))


static func _banner(c, lp: Vector3, sx: float) -> void:
	var p = c._b("paint")
	var top := lp + Vector3(0, 3.2, 0)
	var out := Vector3(sx * 0.75, 0, 0)
	p.quad(top + out * 0.1 - Vector3(0, 1.5, 0), top + out * 0.1, top + out, top + out - Vector3(0, 1.5, 0), Vector3(0, 0, 1), Color(0.45, 0.02, 0.05))
	p.quad(top + out - Vector3(0, 1.5, 0), top + out, top + out * 0.1, top + out * 0.1 - Vector3(0, 1.5, 0), Vector3(0, 0, -1), Color(0.45, 0.02, 0.05))
	c.box(c._b("neon"), top + out * 0.55 - Vector3(0, 0.08, 0), Vector3(0.6, 0.04, 0.04), Color.WHITE)
	var bt = c._b("neon")
	var k0: int = bt.v.size() - 24
	for q in range(maxi(k0, 0), bt.v.size()):
		bt.t[q] = c.neon_uv(0)


## A parked streetcar: a long red-and-cream body with lit windows.
static func _streetcar(c, p: Vector3) -> void:
	c.ck = c._chunk_of(p.x, p.z)
	var paint = c._b("paint")
	var L := 14.0
	c.box(paint, p + Vector3(0, 0.95, 0), Vector3(2.6, 1.3, L), Color(0.42, 0.04, 0.05), Basis.IDENTITY, 8)
	c.box(paint, p + Vector3(0, 3.05, 0), Vector3(2.6, 0.5, L), Color(0.42, 0.04, 0.05))
	c.box(paint, p + Vector3(0, 3.45, 0), Vector3(2.2, 0.3, L - 1.0), Color(0.18, 0.17, 0.16))
	var glass = c._b("glass")
	for sx in [-1.0, 1.0]:
		var x := p.x + sx * 1.31
		var n := Vector3(sx, 0, 0)
		var zz := -L * 0.5 + 0.6
		while zz < L * 0.5 - 1.4:
			var uv: Array = c.cell_uv(1, 2)
			glass.quad(Vector3(x, 1.6, p.z + zz + (1.1 if sx < 0 else 0.0)), Vector3(x, 2.8, p.z + zz + (1.1 if sx < 0 else 0.0)), Vector3(x, 2.8, p.z + zz + (0.0 if sx < 0 else 1.1)), Vector3(x, 1.6, p.z + zz + (0.0 if sx < 0 else 1.1)), n, Color.WHITE, uv[0], uv[1])
			c.box(paint, Vector3(x, 2.2, p.z + zz + 1.2), Vector3(0.04, 1.2, 0.16), Color(0.8, 0.75, 0.62))
			zz += 1.35
	c.beam(c._b("metal"), p + Vector3(0, 3.6, -3.0), p + Vector3(0, 6.0, 0.5), 0.05, 0.05, Color(0.1, 0.1, 0.1))
	c.box_collider(p + Vector3(0, 1.8, 0), Vector3(2.7, 3.6, L))


## The Palm Square: fan cobbles, palms at the corners, lanterns round an open centre.
static func _square(c, r: RandomNumberGenerator) -> void:
	var s := SQUARE
	c.ck = c._chunk_of(s.get_center().x, s.get_center().y)
	c._slab(s.position.x + 3.75, s.position.y + 3.75, s.end.x - 3.75, s.end.y - 3.75, "cobble_fan", Color(0.62, 0.52, 0.5), Color(0.62, 0.6, 0.57))
	var ctr := Vector3(s.get_center().x, 0.1, s.get_center().y)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			c._palm(ctr + Vector3(sx * 24.0, 0, sz * 13.0))
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		c._ornate_lamp(ctr + Vector3(cos(a) * 19.5, 0, sin(a) * 15.5))
	# a bronze figure on a plinth at the north edge (out of the arena)
	var sp := ctr + Vector3(0, 0, -16.0)
	c.box(c._b("stone"), sp + Vector3(0, 0.9, 0), Vector3(2.0, 1.8, 2.0), Color(0.55, 0.52, 0.48))
	c._statue(c._b("metal"), sp + Vector3(0, 1.8, 0), 2.4, Color(0.25, 0.2, 0.12))
	c.box_collider(sp + Vector3(0, 1.5, 0), Vector3(2.0, 3.0, 2.0))
	c.add_road(ctr + Vector3(0, 0, 8))


## Le Velours: a Beaux-Arts opera house with a colonnade, a fan marquee, a dome and a
## crown of crimson neon. Faces west across its forecourt onto the Mile.
static func _opera(c) -> void:
	var o := OPERA
	c.ck = "M"
	var st = c._b("stone")
	var sc := Color(0.66, 0.6, 0.55)
	var x0 := o.position.x
	var x1 := o.end.x
	var z0 := o.position.y
	var z1 := o.end.y
	var zc := o.get_center().y
	var H := 18.0
	# forecourt (cobbles) between the street and the steps
	c._slab(163.75, z0 - 0.0, x0, z1, "cobble_fan", Color(0.6, 0.48, 0.46), Color(0.62, 0.6, 0.57))
	# main block
	c.box(st, Vector3((x0 + x1) * 0.5, H * 0.5, zc), Vector3(x1 - x0, H, z1 - z0), sc, Basis.IDENTITY, 8)
	c.box(st, Vector3((x0 + x1) * 0.5 + 2.0, H + 2.5, zc), Vector3(x1 - x0 - 6.0, 5.0, z1 - z0 - 6.0), sc * Color(0.9, 0.9, 0.9), Basis.IDENTITY, 8)
	# colonnade and entablature on the west front
	var cx := x0 - 2.4
	for k in 8:
		var zz := z0 + 4.0 + k * (z1 - z0 - 8.0) / 7.0
		c.cyl(st, Vector3(cx, 1.2, zz), 0.55, 0.48, 11.0, 10, sc * Color(1.05, 1.05, 1.05), false)
		c.box(st, Vector3(cx, 0.6, zz), Vector3(1.4, 1.2, 1.4), sc)
		c.post_collider(Vector3(cx, 0, zz), 0.6, 4.0)
	c.box(st, Vector3(cx + 0.6, 13.0, zc), Vector3(4.0, 1.8, z1 - z0 - 2.0), sc)
	c.box(st, Vector3(cx + 1.0, 14.6, zc), Vector3(3.2, 1.4, z1 - z0 - 4.0), sc * Color(0.85, 0.85, 0.85))
	# pediment
	st.tri(Vector3(cx - 0.8, 15.3, z0 + 3.0), Vector3(cx - 0.8, 20.5, zc), Vector3(cx - 0.8, 15.3, z1 - 3.0), Vector3(-1, 0, 0), sc)
	# steps up to the doors
	for i in 4:
		c.box(st, Vector3(x0 - 4.5 + i * 0.6, 0.06 + i * 0.05, zc), Vector3(1.0, 0.1 + i * 0.1, z1 - z0 - 6.0), sc * Color(0.8, 0.8, 0.8))
	# tall arched windows and doors, lit warm
	var glass = c._b("shop")
	for k in 5:
		var zz := z0 + 6.0 + k * (z1 - z0 - 12.0) / 4.0
		var uv: Array = c.shop_uv(k % 4)
		glass.quad(Vector3(x0 - 0.03, 0.3, zz + 1.2), Vector3(x0 - 0.03, 5.5, zz + 1.2), Vector3(x0 - 0.03, 5.5, zz - 1.2), Vector3(x0 - 0.03, 0.3, zz - 1.2), Vector3(-1, 0, 0), Color.WHITE, uv[0], uv[1])
		var wuv: Array = c.cell_uv(k % 4, 2)
		c._b("glass").quad(Vector3(x0 - 0.03, 7.5, zz + 1.0), Vector3(x0 - 0.03, 11.0, zz + 1.0), Vector3(x0 - 0.03, 11.0, zz - 1.0), Vector3(x0 - 0.03, 7.5, zz - 1.0), Vector3(-1, 0, 0), Color.WHITE, wuv[0], wuv[1])
	# drum, dome, lantern and the neon crown
	var dc := Vector3((x0 + x1) * 0.5 + 2.0, H + 5.0, zc)
	c.cyl(st, dc, 7.5, 7.5, 4.0, 20, sc, false)
	var dome = c._b("metal")
	var steps := 6
	for k in steps:
		var a0 := PI * 0.5 * k / steps
		var a1 := PI * 0.5 * (k + 1) / steps
		c.cyl(dome, dc + Vector3(0, 4.0 + sin(a0) * 8.0, 0), 7.6 * cos(a0), 7.6 * cos(a1), (sin(a1) - sin(a0)) * 8.0, 20, Color(0.2, 0.28, 0.24), false)
	c.cyl(st, dc + Vector3(0, 12.0, 0), 1.2, 1.0, 3.0, 8, sc)
	c.cyl(st, dc + Vector3(0, 15.0, 0), 1.2, 0.0, 2.0, 8, sc)
	var neon = c._b("neon")
	var k0: int = neon.v.size()
	for k in 24:
		var a0 := TAU * k / 24.0
		var a1 := TAU * (k + 1) / 24.0
		c.beam(neon, dc + Vector3(cos(a0) * 7.7, 4.1, sin(a0) * 7.7), dc + Vector3(cos(a1) * 7.7, 4.1, sin(a1) * 7.7), 0.18, 0.18, Color.WHITE)
		c.beam(neon, dc + Vector3(cos(a0) * 7.65, 4.0, sin(a0) * 7.65), dc + Vector3(cos(a0) * 1.2, 12.0, sin(a0) * 1.2), 0.1, 0.1, Color.WHITE)
	for q in range(k0, neon.v.size()):
		neon.t[q] = c.neon_uv(0)
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(4.0, 4.0, 4.0)), dc + Vector3(0, 17.5, 0)))
	# the fan marquee over the doors
	_marquee(c, Vector3(x0 - 0.2, 6.0, zc), Vector3(-1, 0, 0), 7.0, 2)
	var sign := Label3D.new()
	sign.text = "LE VELOURS"
	sign.font_size = 160
	sign.pixel_size = 0.012
	sign.modulate = Color(1.0, 0.35, 0.6)
	sign.outline_size = 0
	sign.shaded = false
	sign.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(cx - 1.1, 13.0, zc))
	c.add_child(sign)
	# colliders and footprint
	c.box_collider(Vector3((x0 + x1) * 0.5, H * 0.5, zc), Vector3(x1 - x0, H, z1 - z0))
	c.lots.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	c.ck = c._chunk_of(x0 - 6.0, zc)
	c._light_pool(Vector3(x0 - 6.0, 0, zc), 8.0)
	c._wall_glow(Vector3(x0 - 0.1, 0, zc), Vector3(-1, 0, 0), 18.0, 10.0)
	_ropes(c, Vector3(x0 - 6.5, 0.1, zc), Vector3(0, 0, 1), 9.0)


## Fan-shaped neon marquee (image 03): a half-disc canopy edged and rayed in neon.
static func _marquee(c, at: Vector3, n: Vector3, w: float, nk: int) -> void:
	var rt := Vector3.UP.cross(n).normalized()
	var neon = c._b("neon")
	var trim = c._b("trim")
	var k0: int = neon.v.size()
	var R := w * 0.5
	var segs := 10
	for s in segs:
		var a0 := PI * s / segs
		var a1 := PI * (s + 1) / segs
		var p0 := at + rt * cos(a0) * R + n * sin(a0) * R * 0.5
		var p1 := at + rt * cos(a1) * R + n * sin(a1) * R * 0.5
		trim.tri(at, p0, p1, Vector3.UP, Color(0.35, 0.05, 0.1))
		trim.tri(at - Vector3(0, 0.05, 0), p1 - Vector3(0, 0.05, 0), p0 - Vector3(0, 0.05, 0), Vector3.DOWN, Color(0.6, 0.15, 0.2))
		c.beam(neon, p0, p1, 0.12, 0.12, Color.WHITE)
		c.beam(neon, at + Vector3(0, 0.08, 0), p0 + Vector3(0, 0.08, 0), 0.06, 0.06, Color.WHITE)
		# rising fan rays on the wall above
		c.beam(neon, at + Vector3(0, 0.3, 0) + n * 0.05, at + rt * cos(a0) * R * 0.7 + Vector3(0, 0.3 + sin(a0) * R * 0.6, 0) + n * 0.05, 0.08, 0.08, Color.WHITE)
	for q in range(k0, neon.v.size()):
		neon.t[q] = c.neon_uv(nk)
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(2.6, 2.6, 2.6)), at + n * 1.0))


## Brass stanchions with a velvet rope, along `dir`, and a red carpet beside them.
static func _ropes(c, start: Vector3, dir: Vector3, length: float) -> void:
	var m = c._b("metal")
	var gold := Color(0.75, 0.55, 0.2)
	var n := int(length / 1.5)
	var prev := Vector3.ZERO
	for k in n + 1:
		var p := start + dir * (k * length / n)
		c.cyl(m, p, 0.16, 0.16, 0.05, 8, gold)
		c.cyl(m, p, 0.035, 0.035, 0.95, 6, gold, false)
		c.cyl(m, p + Vector3(0, 0.95, 0), 0.07, 0.0, 0.1, 6, gold)
		if k > 0:
			var a := prev + Vector3(0, 0.85, 0)
			var b := p + Vector3(0, 0.85, 0)
			var mid := (a + b) * 0.5 - Vector3(0, 0.18, 0)
			c.beam(c._b("paint"), a, mid, 0.05, 0.05, Color(0.5, 0.02, 0.04))
			c.beam(c._b("paint"), mid, b, 0.05, 0.05, Color(0.5, 0.02, 0.04))
		prev = p


## Club entrances on the frontages facing the Mile: marquee, curtains, ropes, carpet.
static func _clubs(c, r: RandomNumberGenerator) -> void:
	for j in range(Layout.VM_J[0], Layout.VM_J[1]):
		var cz := j * 20.0 + 10.0
		for side in [-1.0, 1.0]:
			if (j + (1 if side > 0 else 0)) % 2 != 0:
				continue
			if Layout.VM_SQUARE.has_point(Vector2i(6, j)):
				continue
			if side > 0 and Layout.VM_OPERA.has_point(Vector2i(8, j)):
				continue
			var fx := MILE_X + side * 16.0 # the frontage line (x 134 / 166)
			var n := Vector3(-side, 0, 0) # facing the Mile
			c.ck = c._chunk_of(fx, cz)
			var door := Vector3(fx, 0, cz)
			# velvet curtains drawn back either side of the doorway
			var rt := Vector3.UP.cross(n).normalized()
			var p = c._b("paint")
			for s in [-1.0, 1.0]:
				var a := door + n * 0.08 + rt * s * 1.4
				var b := door + n * 0.08 + rt * s * 0.6
				p.quad(a, a + Vector3(0, 3.2, 0), b + Vector3(0, 3.2, 0), b, n, Color(0.5, 0.02, 0.05))
			c._b("shop").quad(door + n * 0.05 - rt * 0.6, door + n * 0.05 - rt * 0.6 + Vector3(0, 3.2, 0), door + n * 0.05 + rt * 0.6 + Vector3(0, 3.2, 0), door + n * 0.05 + rt * 0.6, n, Color.WHITE, c.shop_uv(2)[0], c.shop_uv(2)[1])
			_marquee(c, door + Vector3(0, 3.7, 0) + n * 0.1, n, 4.2, [0, 2, 3][r.randi() % 3])
			# a red carpet to the kerb and ropes along it
			c._b("paint").quad(door + rt * 0.8 + Vector3(0, 0.105, 0), door + rt * 0.8 + n * 2.0 + Vector3(0, 0.105, 0), door - rt * 0.8 + n * 2.0 + Vector3(0, 0.105, 0), door - rt * 0.8 + Vector3(0, 0.105, 0), Vector3.UP, Color(0.35, 0.02, 0.04))
			_ropes(c, door + Vector3(0, 0.1, 0) + n * 1.2 + rt * 1.2, rt, 4.5)
			c._light_pool(door + n * 1.5, 3.0)


## The harbour promenade along the south waterfront: flagstones, a railing, lanterns.
static func _promenade(c, r: RandomNumberGenerator, x0: float, x1: float) -> void:
	var z0 := 203.75
	var z1 := Layout.RIVER_Z
	var x := x0
	while x < x1 - 0.1:
		var xe := minf(x + 20.0, x1)
		c.ck = c._chunk_of(x + 10.0, z1)
		c._slab(x, z0, xe, z1, "sidewalk", Color(0.85, 0.82, 0.8), Color(0.55, 0.54, 0.52))
		var iron = c._b("iron")
		iron.quad(Vector3(xe, 0.1, z1 - 0.3), Vector3(xe, 1.1, z1 - 0.3), Vector3(x, 1.1, z1 - 0.3), Vector3(x, 0.1, z1 - 0.3), Vector3(0, 0, -1), Color.WHITE, Vector2(0, 0), Vector2((xe - x) * 0.5, 0.5))
		c.beam(c._b("metal"), Vector3(x, 1.12, z1 - 0.3), Vector3(xe, 1.12, z1 - 0.3), 0.06, 0.06, Color(0.05, 0.05, 0.05))
		c.path_lamp(Vector3(x + 10.0, 0.1, z1 - 1.0), Vector3(0, 0, -1))
		c.add_road(Vector3(x + 10.0, 0, 212.0))
		x = xe


## A three-masted ship riding in the river past the promenade.
static func _tall_ship(c, p: Vector3) -> void:
	c.ck = "F"
	var m = c._b("metal")
	var hull := Color(0.08, 0.06, 0.05)
	var y0 := -2.6
	c.hexa(m, [p + Vector3(-22, y0, -4), p + Vector3(22, y0, -4), p + Vector3(22, y0, 4), p + Vector3(-22, y0, 4),
		p + Vector3(-25, 3.0, -5), p + Vector3(24, 4.0, -5.5), p + Vector3(24, 4.0, 5.5), p + Vector3(-25, 3.0, 5)], hull)
	c.hexa(m, [p + Vector3(22, y0, -4), p + Vector3(30, 1.0, -0.4), p + Vector3(30, 1.0, 0.4), p + Vector3(22, y0, 4),
		p + Vector3(24, 4.0, -5.5), p + Vector3(33, 5.0, -0.3), p + Vector3(33, 5.0, 0.3), p + Vector3(24, 4.0, 5.5)], hull)
	for k in 3:
		var mx := p + Vector3(-14.0 + k * 13.0, 3.5, 0)
		c.cyl(m, mx, 0.35, 0.18, 30.0 - absf(k - 1) * 4.0, 6, hull, false)
		for y in [10.0, 18.0, 24.0]:
			c.beam(m, mx + Vector3(0, y, -6.0 + y * 0.12), mx + Vector3(0, y, 6.0 - y * 0.12), 0.18, 0.18, hull)
		c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(1.4, 1.4, 1.4)), mx + Vector3(0, 6.0, 0)))
	c.beam(m, p + Vector3(30, 5.0, 0), p + Vector3(42, 10.0, 0), 0.2, 0.2, hull)
