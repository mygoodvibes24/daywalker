extends RefCounted
## The outskirts: Hollow Pines (docs/concept_art/06_hollow_pines.jpg) and the Bayou
## (07_bayou.jpg). Built into city.gd's batches/MultiMeshes by `c` (the city node).
##
## Pines: a MultiMesh forest (cheap cone pines up close, crossed billboard cards far away)
## cut by muddy roads into clearings: the trailer park, the logging yard, the Hollow (boss
## arena) and the water tower, the landmark you steer by.
## Bayou: black shallows over mud you can wade, cypress islands hung with moss, boardwalks
## and the ruined Belle Rive plantation house on its drowned lawn.

const Layout = preload("res://scripts/map/map_layout.gd")

const PINE_NEAR := 105.0 # cone pines up to here, billboard cards beyond

const PINE_ROADS := [
	[Vector3(-40, 0, -62), Vector3(-40, 0, -118), Vector3(-30, 0, -150), Vector3(-38, 0, -182), Vector3(-40, 0, -222)],
	[Vector3(-40, 0, -100), Vector3(-92, 0, -100)],
	[Vector3(0, 0, -62), Vector3(8, 0, -100), Vector3(10, 0, -140), Vector3(22, 0, -172), Vector3(25, 0, -185)],
	[Vector3(40, 0, -62), Vector3(46, 0, -100), Vector3(75, 0, -128), Vector3(75, 0, -150), Vector3(108, 0, -150), Vector3(140, 0, -150)],
	[Vector3(-30, 0, -150), Vector3(10, 0, -140)],
	[Vector3(75, 0, -150), Vector3(98, 0, -180), Vector3(100, 0, -205)],
	[Vector3(25, 0, -185), Vector3(-38, 0, -182)],
	[Vector3(80, 0, -62), Vector3(95, 0, -90), Vector3(75, 0, -128)],
]
## [centre, radius, kind]. Trees keep out; POIs and the arena use them.
const PINE_CLEARINGS := [
	[Vector3(-30, 0, -150), 24.0, "trailers"],
	[Vector3(10, 0, -122), 19.0, "arena"],
	[Vector3(75, 0, -150), 22.0, "logging"],
	[Vector3(25, 0, -190), 13.0, "tower"],
	[Vector3(100, 0, -205), 11.0, "camp"],
	[Vector3(-56, 0, -196), 10.0, "camp"],
	[Vector3(46, 0, -96), 9.0, "camp"],
	[Vector3(-62, 0, -122), 9.0, "camp"],
	[Vector3(-8, 0, -176), 9.0, "camp"],
	[Vector3(-40, 0, -214), 7.0, "trail"],
	[Vector3(100, 0, -108), 9.0, "camp"],
]

const BAYOU_ISLANDS := [
	[Vector3(185, 0, -132), 21.0, "lawn"],
	[Vector3(185, 0, -170), 17.0, "house"],
	[Vector3(150, 0, -92), 10.0, "camp"],
	[Vector3(207, 0, -80), 9.0, "camp"],
	[Vector3(152, 0, -202), 11.0, "camp"],
	[Vector3(207, 0, -206), 10.0, "camp"],
	[Vector3(142, 0, -150), 9.0, "camp"],
	[Vector3(212, 0, -112), 7.0, "landing"],
	[Vector3(130, 0, -125), 7.0, "isle"],
	[Vector3(168, 0, -210), 6.0, "isle"],
]
const BOARDWALKS := [
	[Vector3(212, 0, -112), Vector3(198, 0, -122), Vector3(185, 0, -132)],
	[Vector3(185, 0, -132), Vector3(160, 0, -110), Vector3(150, 0, -92), Vector3(140, 0, -66)],
	[Vector3(185, 0, -132), Vector3(155, 0, -145), Vector3(142, 0, -150), Vector3(125, 0, -150)],
	[Vector3(185, 0, -170), Vector3(170, 0, -195), Vector3(152, 0, -202)],
	[Vector3(185, 0, -170), Vector3(200, 0, -190), Vector3(207, 0, -206)],
	[Vector3(185, 0, -132), Vector3(200, 0, -100), Vector3(207, 0, -80)],
]


# ================================================================ Hollow Pines
static func build_pines(c) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4401
	# ground: forest floor, rutted mud roads
	c.ground_rect("earth", -70.0, -240.0, 125.0, -70.0, Color.WHITE, 0.02)
	c.ground_rect("earth", -70.0, -70.0, 125.0, -62.0, Color.WHITE, 0.02)
	for road in PINE_ROADS:
		c.ground_path("mud", road, 7.0, Color.WHITE, 0.035)
	for cl in PINE_CLEARINGS:
		_mud_disc(c, cl[0], cl[1] * 0.75)
		if cl[2] in ["camp", "trailers", "logging"]:
			c.add_anchor(cl[0], "clearing")
	# the forest
	var near_xfs: Array = []
	var far_xfs: Array = []
	var cols: Array = []
	var step := 6.2
	var z := -240.0
	while z < -66.0:
		var x := -70.0
		while x < 125.0:
			var p := Vector3(x + r.randf_range(-2.4, 2.4), 0.0, z + r.randf_range(-2.4, 2.4))
			x += step
			if p.z > -72.0 and p.x > -64.0 and p.x < 120.0:
				continue # the Old Quarter's edge street
			if Layout.district_at(p.x, p.z) != "pines":
				continue
			if not _pine_ok(p):
				continue
			var h := r.randf_range(14.0, 23.0)
			var xf := Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(h, h, h) / 18.0), p)
			near_xfs.append(xf)
			far_xfs.append(xf)
			var g := r.randf_range(0.75, 1.15)
			cols.append(Color(g, g, g))
			if p.z > Layout.PLAY.position.y + 1.0:
				c.post_collider(p, 0.45 * h / 18.0, 4.0)
		z += step
	c.scatter_mm("Pines", _pine_mesh(c, 18.0), near_xfs, 60.0, 0.0, PINE_NEAR, true)
	c.scatter_mm("PineCards", _pine_card_mesh(c, 18.0), far_xfs, 80.0, PINE_NEAR, 0.0, false, cols, c.M["pine_card"])
	_trailer_park(c, r)
	_logging_yard(c, r)
	_water_tower(c, Vector3(25, 0, -192))
	# lamps along the roads into the woods (sodium, on wooden poles)
	for road in PINE_ROADS:
		for k in road.size() - 1:
			var a: Vector3 = road[k]
			var b: Vector3 = road[k + 1]
			var n := a.distance_to(b)
			var d := 14.0
			while d < n - 6.0:
				var p := a.lerp(b, d / n)
				var side := Vector3.UP.cross((b - a).normalized())
				_pole_lamp(c, p + side * 4.6, -side)
				d += 34.0
	c.cache_spots.append({"pos": Vector3(-20, 0.1, -160), "yaw": 0.3, "coffin": false})
	c.cache_spots.append({"pos": Vector3(85, 0.1, -140), "yaw": 1.2, "coffin": false})
	c.cache_spots.append({"pos": Vector3(30, 0.1, -182), "yaw": 0.0, "coffin": false})
	c.cache_spots.append({"pos": Vector3(-50, 0.1, -205), "yaw": 2.0, "coffin": false})


static func _pine_ok(p: Vector3) -> bool:
	for road in PINE_ROADS:
		if c_dist(p, road) < 6.0:
			return false
	for cl in PINE_CLEARINGS:
		if p.distance_to(cl[0]) < cl[1]:
			return false
	for d in Layout.DEPLOY_POINTS:
		if p.distance_to(d.pos) < 9.0:
			return false
	return true


static func c_dist(p: Vector3, pts: Array) -> float:
	var best := INF
	var q := Vector2(p.x, p.z)
	for k in pts.size() - 1:
		var a := Vector2(pts[k].x, pts[k].z)
		var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best


static func _mud_disc(c, p: Vector3, rad: float, mat := "mud", y := 0.032) -> void:
	c.ck = c._chunk_of(p.x, p.z)
	var bt = c._b(mat)
	var segs := 14
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var r0 := rad * (0.85 + 0.15 * sin(a0 * 3.0 + p.x))
		var r1 := rad * (0.85 + 0.15 * sin(a1 * 3.0 + p.x))
		bt.tri(p + Vector3(0, y, 0), p + Vector3(cos(a0) * r0, y, sin(a0) * r0), p + Vector3(cos(a1) * r1, y, sin(a1) * r1), Vector3.UP, Color.WHITE)


## A tall Southern pine: bare trunk, five tiers of needle cones. ~130 triangles.
static func _pine_mesh(c, h: float) -> ArrayMesh:
	var trunk = c.new_batch()
	var fol = c.new_batch()
	c.cyl(trunk, Vector3.ZERO, h * 0.024, h * 0.012, h * 0.8, 6, Color(0.3, 0.22, 0.17), false)
	for k in 5:
		var t := float(k) / 5.0
		var y0 := h * (0.36 + t * 0.5)
		var rr := h * 0.2 * (1.0 - t * 0.6)
		c.cyl(fol, Vector3(0, y0, 0), rr, 0.0, h * 0.22, 8, Color(1, 1, 1), true)
	return c.batches_mesh([[trunk, "paint"], [fol, "pine"]])


## Two crossed cards for the far forest. 4 triangles.
static func _pine_card_mesh(c, h: float) -> ArrayMesh:
	var bt = c.new_batch()
	var w := h * 0.42
	for a in [0.0, PI * 0.5]:
		var rt := Vector3(cos(a), 0, sin(a)) * w
		var n := Vector3(-sin(a), 0, cos(a))
		bt.quad(-rt, -rt + Vector3(0, h, 0), rt + Vector3(0, h, 0), rt, n, Color.WHITE, Vector2(0, 0), Vector2(1, 1))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bt.arrays())
	return mesh


## A sodium lamp on a leaning wooden pole.
static func _pole_lamp(c, p: Vector3, face: Vector3) -> void:
	c.ck = c._chunk_of(p.x, p.z)
	var m = c._b("metal")
	c.cyl(m, p, 0.14, 0.11, 7.0, 6, Color(0.24, 0.18, 0.12), false)
	var head := p + Vector3(0, 6.8, 0) + face * 1.4
	c.beam(m, p + Vector3(0, 6.6, 0), head, 0.08, 0.08, Color(0.06, 0.06, 0.06))
	c.box(c._b("sodium"), head - Vector3(0, 0.12, 0), Vector3(0.5, 0.14, 0.3), Color.WHITE, Basis(Vector3.UP, atan2(face.x, face.z)))
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(1.6, 1.6, 1.6)), head - Vector3(0, 0.25, 0)))
	c._light_pool(Vector3(head.x, 0, head.z), 5.5)
	c.lamp_positions.append(head)
	c.post_collider(p, 0.2, 3.0)


static func _trailer_park(c, r: RandomNumberGenerator) -> void:
	var centre: Vector3 = PINE_CLEARINGS[0][0]
	var xfs: Array = []
	var size := Vector3.ZERO
	for k in 9:
		var a := TAU * k / 9.0 + 0.2
		var p := centre + Vector3(cos(a), 0, sin(a)) * 17.0
		var ok := true
		for road in PINE_ROADS:
			if c_dist(p, road) < 8.0:
				ok = false
		if not ok:
			continue
		var yaw := -a + PI * 0.5 + r.randf_range(-0.25, 0.25) # long side to the fire
		xfs.append(Transform3D(Basis(Vector3.UP, yaw), p))
	size = c.glb_multimesh("trailer_home", 4.3, xfs, 60.0, 120.0, true)
	if size == Vector3.ZERO:
		size = Vector3(11, 4, 4.4)
	for xf: Transform3D in xfs:
		c.box_collider(xf.origin + Vector3(0, 1.8, 0), Vector3(size.x * 0.9, 3.6, size.z * 0.75), xf.basis.get_euler().y)
		# porch light
		var porch: Vector3 = xf.origin + xf.basis.z * (size.z * 0.5 + 0.4) + Vector3(0, 2.4, 0)
		c.ck = c._chunk_of(porch.x, porch.z)
		c.box(c._b("lamp"), porch, Vector3(0.18, 0.18, 0.18), Color.WHITE)
		c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(0.9, 0.9, 0.9)), porch))
		c._light_pool(Vector3(porch.x, 0, porch.z) + xf.basis.z * 1.2, 3.0)
		if r.randf() < 0.6:
			c._car(xf.origin + xf.basis.z * 6.5 + xf.basis.x * r.randf_range(-3.0, 3.0), xf.basis.get_euler().y + PI * 0.5 + r.randf_range(-0.3, 0.3))
	# torn chain-link round the park, with claw-ripped gaps
	var iron = null
	for k in 24:
		if k % 6 == 2 or k % 6 == 3:
			continue
		var a0 := TAU * k / 24.0
		var a1 := TAU * (k + 1) / 24.0
		var p0 := centre + Vector3(cos(a0), 0, sin(a0)) * 25.0
		var p1 := centre + Vector3(cos(a1), 0, sin(a1)) * 25.0
		var mid := (p0 + p1) * 0.5
		var blocked := false
		for road in PINE_ROADS:
			if c_dist(mid, road) < 5.0:
				blocked = true
		if blocked:
			continue
		c.ck = c._chunk_of(mid.x, mid.z)
		iron = c._b("iron")
		var n := Vector3.UP.cross(p1 - p0).normalized()
		var len := p0.distance_to(p1)
		iron.quad(p0, p0 + Vector3(0, 2.2, 0), p1 + Vector3(0, 2.2, 0), p1, n, Color.WHITE, Vector2(0, 0.5), Vector2(len * 0.5, 1.0))
		c.cyl(c._b("metal"), p0, 0.05, 0.05, 2.3, 5, Color(0.25, 0.24, 0.22), false)


static func _logging_yard(c, r: RandomNumberGenerator) -> void:
	var centre: Vector3 = PINE_CLEARINGS[2][0]
	# log piles: pyramids of logs lying along x or z
	for pile in [[Vector3(62, 0, -138), 0.0], [Vector3(90, 0, -160), PI * 0.5], [Vector3(88, 0, -138), 0.3], [Vector3(60, 0, -164), PI * 0.5 + 0.2]]:
		var p: Vector3 = pile[0]
		var yaw: float = pile[1]
		var b := Basis(Vector3.UP, yaw)
		c.ck = c._chunk_of(p.x, p.z)
		var m = c._b("wood")
		var rows := 3
		for row in rows:
			for k in rows - row + 1:
				var off := b * Vector3((k - (rows - row) * 0.5) * 0.9, 0.42 + row * 0.75, 0)
				c.cyl(m, p + off - b.z * 4.0, 0.42, 0.42, 8.0, 8, Color(0.55, 0.42, 0.3), true, Basis(b.x, b.z, -b.y))
		c.box_collider(p + Vector3(0, 1.1, 0), Vector3(3.6, 2.2, 8.2), yaw)
	# the sawmill shed: an open timber frame under a tin roof, one sodium lamp
	var sp := Vector3(62, 0, -172)
	c.ck = c._chunk_of(sp.x, sp.z)
	var w = c._b("wood")
	for x in [-6.0, 0.0, 6.0]:
		for zz in [-3.5, 3.5]:
			c.box(w, sp + Vector3(x, 2.5, zz), Vector3(0.35, 5.0, 0.35), Color(0.5, 0.4, 0.3))
			c.post_collider(sp + Vector3(x, 0, zz), 0.3, 3.0)
	c.box(c._b("corrugated"), sp + Vector3(0, 5.3, 0), Vector3(14.0, 0.15, 9.0), Color(0.5, 0.36, 0.28), Basis(Vector3.RIGHT, 0.12))
	c.box(c._b("metal"), sp + Vector3(0, 0.9, 0), Vector3(6.0, 1.8, 1.6), Color(0.3, 0.28, 0.26))
	c.box_collider(sp + Vector3(0, 0.9, 0), Vector3(6.0, 1.8, 1.6))
	c.cyl(c._b("metal"), sp + Vector3(1.0, 1.8, 0.85), 1.1, 1.1, 0.05, 16, Color(0.6, 0.6, 0.62), true, Basis(Vector3.RIGHT, PI * 0.5))
	_pole_lamp(c, sp + Vector3(-8.5, 0, 5.0), Vector3(1, 0, 0))
	c._car(centre + Vector3(10, 0, 6), 1.2)
	c._car(centre + Vector3(-12, 0, -4), -0.5)


## The Hollow Pines water tower: a tank on a tall steel trestle with a red beacon. Landmark.
static func _water_tower(c, base: Vector3) -> void:
	c.ck = "M"
	var m = c._b("metal")
	var steel := Color(0.16, 0.15, 0.14)
	var leg := 20.0
	var rr := 4.2
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var off := Vector3(cos(a), 0, sin(a))
		c.beam(m, base + off * rr * 1.25, base + off * rr * 0.8 + Vector3(0, leg, 0), 0.35, 0.35, steel)
		c.post_collider(base + off * rr * 1.25, 0.4, 4.0)
	for y in [5.0, 10.0, 15.0]:
		for k in 4:
			var a0 := k * TAU / 4.0 + PI / 4.0
			var a1 := (k + 1) * TAU / 4.0 + PI / 4.0
			var s: float = rr * (1.25 - 0.45 * y / leg)
			c.beam(m, base + Vector3(cos(a0) * s, y, sin(a0) * s), base + Vector3(cos(a1) * s, y, sin(a1) * s), 0.15, 0.15, steel)
			c.beam(m, base + Vector3(cos(a0) * s, y, sin(a0) * s), base + Vector3(cos(a1) * s, y + 5.0, sin(a1) * s) * Vector3(1, 1, 1), 0.08, 0.08, steel)
	var tank := base + Vector3(0, leg, 0)
	c.box(m, tank, Vector3(rr * 2.4, 0.3, rr * 2.4), steel)
	c.cyl(m, tank + Vector3(0, 0.15, 0), rr, rr, 6.5, 16, Color(0.42, 0.4, 0.36), false)
	for hy in [1.0, 3.2, 5.4]:
		c.cyl(m, tank + Vector3(0, hy, 0), rr + 0.05, rr + 0.05, 0.12, 16, Color(0.25, 0.14, 0.08), false)
	c.cyl(m, tank + Vector3(0, 6.65, 0), rr + 0.3, 0.3, 2.4, 16, Color(0.3, 0.29, 0.28))
	var top := tank + Vector3(0, 9.2, 0)
	c.cyl(m, tank + Vector3(0, 9.0, 0), 0.08, 0.08, 0.5, 4, steel)
	c.box(c._b("beacon"), top + Vector3(0, 0.25, 0), Vector3(0.45, 0.45, 0.45), Color.WHITE)
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(3.0, 3.0, 3.0)), top + Vector3(0, 0.25, 0)))
	# a floodlight on the tank washing the clearing
	c._light_pool(base + Vector3(0, 0, 4), 9.0)


# ================================================================ the Bayou
static func build_bayou(c) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 5507
	var x0 := 125.0
	var z1 := -60.0
	# mud bed, black water over it (wadeable), islands of earth above the waterline
	c.ground_rect("mud", x0, -240.0, 240.0, z1, Color.WHITE, 0.02)
	c.ground_rect("swamp", x0, -240.0, 240.0, z1, Color.WHITE, 0.065)
	for isl in BAYOU_ISLANDS:
		_mud_disc(c, isl[0], isl[1], "earth", 0.09)
		if isl[2] == "camp":
			c.add_anchor(isl[0], "island")
	for bw in BOARDWALKS:
		c.ground_path("wood", bw, 2.4, Color(0.75, 0.7, 0.62), 0.1, 14.0)
		for k in bw.size() - 1:
			var a: Vector3 = bw[k]
			var b: Vector3 = bw[k + 1]
			var n := a.distance_to(b)
			var d := 6.0
			while d < n - 3.0:
				var p := a.lerp(b, d / n)
				var side := Vector3.UP.cross((b - a).normalized())
				_lantern_post(c, p + side * 1.6)
				d += 22.0
	# cypress trees: procedural ones everywhere, generated hero trees round the house
	var meshes: Array = []
	for v in 3:
		meshes.append(_cypress_mesh(c, r, 13.0 + v * 2.5))
	var lists: Array = [[], [], []]
	var step := 8.5
	var z := -240.0
	while z < z1 - 3.0:
		var x := x0 + 3.0
		while x < 240.0:
			var p := Vector3(x + r.randf_range(-3.0, 3.0), 0.0, z + r.randf_range(-3.0, 3.0))
			x += step
			if Layout.district_at(p.x, p.z) != "bayou" or not _cypress_ok(p):
				continue
			var s := r.randf_range(0.85, 1.2)
			var xf := Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s, s)), p)
			lists[r.randi() % 3].append(xf)
			if Layout.PLAY.has_point(Vector2(p.x, p.z)):
				c.post_collider(p, 0.7 * s, 4.0)
			# cypress knees round the trunk
			c.ck = c._chunk_of(p.x, p.z)
			for k in r.randi_range(1, 4):
				var kp := p + Vector3(r.randf_range(-3.0, 3.0), 0, r.randf_range(-3.0, 3.0))
				c.cyl(c._b("paint"), kp, r.randf_range(0.12, 0.22), 0.02, r.randf_range(0.3, 0.8), 5, Color(0.28, 0.22, 0.17), false)
		z += step
	for v in 3:
		c.scatter_mm("Cypress%d" % v, meshes[v], lists[v], 60.0, 0.0, 170.0, true)
	var hero: Array = []
	for k in 12:
		var a := TAU * k / 12.0 + 0.2
		var p := Vector3(185, 0, -152) + Vector3(cos(a) * 38.0, 0, sin(a) * 34.0)
		if not _cypress_ok(p) or Layout.district_at(p.x, p.z) != "bayou":
			continue
		hero.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU), p))
		c.post_collider(p, 0.9, 4.0)
	c.glb_multimesh("cypress_tree", 17.0, hero, 80.0, 140.0, true)
	_plantation(c)
	# fireflies over the water
	for f in [Vector3(165, 1.2, -120), Vector3(200, 1.2, -150), Vector3(160, 1.2, -185), Vector3(185, 1.2, -100)]:
		_fireflies(c, f)
	c.cache_spots.append({"pos": Vector3(150, 0.1, -88), "yaw": 0.5, "coffin": false})
	c.cache_spots.append({"pos": Vector3(205, 0.1, -210), "yaw": 1.5, "coffin": true})
	c.cache_spots.append({"pos": Vector3(174, 0.1, -158), "yaw": 0.0, "coffin": true})
	for isl in BAYOU_ISLANDS:
		c.add_road(isl[0] + Vector3(4, 0, 0))


static func _cypress_ok(p: Vector3) -> bool:
	for isl in BAYOU_ISLANDS:
		if p.distance_to(isl[0]) < isl[1] - 1.5:
			return false
	for bw in BOARDWALKS:
		if c_dist(p, bw) < 4.0:
			return false
	for d in Layout.DEPLOY_POINTS:
		if p.distance_to(d.pos) < 10.0:
			return false
	return true


## Bald cypress: buttressed trunk, crooked limbs, flat canopy clumps, curtains of moss.
static func _cypress_mesh(c, r: RandomNumberGenerator, h: float) -> ArrayMesh:
	var bark = c.new_batch()
	var lv = c.new_batch()
	var moss = c.new_batch()
	var col := Color(0.3, 0.25, 0.2)
	c.cyl(bark, Vector3.ZERO, 1.3, 0.5, 2.4, 8, col, false)
	c.cyl(bark, Vector3(0, 2.4, 0), 0.5, 0.25, h * 0.75 - 2.4, 7, col, false)
	var save_rng = c.rng
	c.rng = r
	for k in 5:
		var a := TAU * k / 5.0 + r.randf() * 0.6
		var y := h * r.randf_range(0.45, 0.72)
		var tip := Vector3(cos(a) * r.randf_range(3.0, 5.0), y + r.randf_range(1.0, 2.5), sin(a) * r.randf_range(3.0, 5.0))
		c.beam(bark, Vector3(0, y, 0), tip, 0.28, 0.28, col)
		c._foliage(lv, tip + Vector3(0, 0.8, 0), r.randf_range(2.2, 3.0))
		# moss curtains hanging off the limb
		for q in 2:
			var mp := Vector3(0, y, 0).lerp(tip, 0.4 + q * 0.4)
			var ma := a + PI * 0.5 + q
			var rv := Vector3(cos(ma), 0, sin(ma)) * 0.9
			var ml := r.randf_range(2.5, 4.5)
			moss.quad(mp - rv - Vector3(0, ml, 0), mp - rv, mp + rv, mp + rv - Vector3(0, ml, 0), Vector3(-sin(ma), 0, cos(ma)), Color(0.75, 0.8, 0.68), Vector2(0, 0), Vector2(1, 1))
	c._foliage(lv, Vector3(0, h * 0.85, 0), 3.2)
	c.rng = save_rng
	return c.batches_mesh([[bark, "paint"], [lv, "leaves"], [moss, "moss"]])


static func _lantern_post(c, p: Vector3) -> void:
	c.ck = c._chunk_of(p.x, p.z)
	var m = c._b("metal")
	c.cyl(m, p, 0.08, 0.07, 2.4, 5, Color(0.2, 0.16, 0.12), false)
	c.beam(m, p + Vector3(0, 2.3, 0), p + Vector3(0.6, 2.3, 0), 0.05, 0.05, Color(0.05, 0.05, 0.05))
	var l := p + Vector3(0.6, 1.95, 0)
	c.box(c._b("lamp"), l, Vector3(0.2, 0.3, 0.2), Color.WHITE)
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(0.8, 0.8, 0.8)), l))
	c._light_pool(Vector3(l.x, 0.0, l.z), 2.6)


## Belle Rive: the ruined plantation house (generated model, with a procedural stand-in).
static func _plantation(c) -> void:
	var p := Vector3(185, 0.09, -174)
	var size: Vector3 = c.place_glb("plantation_facade", 15.0, Transform3D(Basis(Vector3.UP, -PI * 0.5), p), true)
	if size == Vector3.ZERO:
		size = Vector3(19, 15, 16)
		c.ck = "M"
		c.box(c._b("stucco"), p + Vector3(0, 6, 0), Vector3(19, 12, 14), Color(0.8, 0.78, 0.72))
	c.box_collider(p + Vector3(0, 4.0, 0), Vector3(size.x * 0.82, 8.0, size.z * 0.7))
	c.lots.append(Rect2(p.x - size.x * 0.45, p.z - size.z * 0.4, size.x * 0.9, size.z * 0.8))
	c.add_anchor(Vector3(185, 0, p.z + size.z * 0.5 + 8.0), "landmark")
	# lanterns on the porch steps and a light in a downstairs window
	for sx in [-4.0, 4.0]:
		_lantern_post(c, p + Vector3(sx, 0, size.z * 0.5 + 2.5))
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(2.4, 2.4, 2.4)), p + Vector3(0, 4.0, size.z * 0.5)))


static func _fireflies(c, p: Vector3) -> void:
	var ps := CPUParticles3D.new()
	ps.position = p
	ps.amount = 24
	ps.lifetime = 4.0
	ps.preprocess = 4.0
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ps.emission_box_extents = Vector3(10, 1.2, 10)
	ps.gravity = Vector3.ZERO
	ps.initial_velocity_min = 0.1
	ps.initial_velocity_max = 0.4
	ps.direction = Vector3(0, 1, 0)
	ps.spread = 180.0
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.95, 0.45)
	q.material = mat
	ps.mesh = q
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ps.visibility_range_end = 70.0
	c.add_child(ps)
