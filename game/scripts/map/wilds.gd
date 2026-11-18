extends RefCounted
## The outskirts: Hollow Pines (docs/concept_art/06_hollow_pines.jpg) and the Bayou
## (07_bayou.jpg). Built into city.gd's batches/MultiMeshes by `c` (the city node).
##
## Everything stands on the terrain (terrain.gd, sampled with c.height_at): the hills, the
## lake, the bayou's mud bed and islands. The ground itself is the terrain's splat shader.
##
## Pines: a MultiMesh forest (textured pines with needle cards up close, impostor cards far
## away) cut by dirt roads into clearings: the trailer park, the logging yard, the Hollow (boss
## arena) and the water tower, the landmark you steer by.
## Bayou: black shallows over mud you can wade, cypress islands hung with moss, boardwalks
## and the ruined Belle Rive plantation house on its drowned lawn.

const Layout = preload("res://scripts/map/map_layout.gd")
const Trees = preload("res://scripts/map/trees.gd")
const Terrain = preload("res://scripts/map/terrain.gd")

const PINE_NEAR := 95.0 # full pines up to here, impostor cards beyond
const PINE_H := 18.0
const CYPRESS_NEAR := 120.0

## The hand-placed features live in map_layout.gd (the terrain shapes itself round them too).
const PINE_ROADS := Layout.PINE_ROADS
const PINE_CLEARINGS := Layout.PINE_CLEARINGS
const BAYOU_ISLANDS := Layout.BAYOU_ISLANDS
const BOARDWALKS := Layout.BOARDWALKS


# ================================================================ Hollow Pines
static func build_pines(c) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4401
	# the ground (forest floor, dirt roads, trampled clearings, rock on the slopes) is the
	# terrain's splat shader; the roads still feed the roaming spawns
	for road in PINE_ROADS:
		for k in road.size() - 1:
			var a: Vector3 = road[k]
			var b: Vector3 = road[k + 1]
			var n := a.distance_to(b)
			var d := 0.0
			while d < n:
				c.add_road(a.lerp(b, d / n))
				d += 18.0
	for cl in PINE_CLEARINGS:
		if cl[2] in ["camp", "trailers", "logging"]:
			c.add_anchor(cl[0], "clearing")
	# the forest: full trees up close, impostor cards beyond, both on the hills
	var meshes: Array = []
	var lists: Array = []
	for v in 3:
		meshes.append(Trees.pine_mesh(PINE_H, 900 + v))
		lists.append([])
	var near_cols: Array = [[], [], []]
	var far_xfs: Array = []
	var cols: Array = []
	var step := 6.2
	var z := -330.0
	while z < -66.0:
		var x := -100.0
		while x < 160.0:
			var p := Vector3(x + r.randf_range(-2.4, 2.4), 0.0, z + r.randf_range(-2.4, 2.4))
			x += step
			var outside := p.z < -242.0 or p.x < -78.0 or (p.x > 125.0 and p.z > -240.0)
			if outside:
				if p.z > -242.0 or p.x < -96.0 or r.randf() < 0.35:
					continue # the ridge beyond the north edge: impostors only, thinner
			elif p.z > -72.0 and p.x > -64.0 and p.x < 120.0:
				continue # the Old Quarter's edge street
			elif Layout.district_at(p.x, p.z) != "pines" or not _pine_ok(p):
				continue
			p.y = c.height_at(p.x, p.z) - 0.15
			if Terrain.normal_at(p.x, p.z).y < 0.8:
				continue # bare rock on the steep faces
			var h := r.randf_range(14.0, 23.0)
			var lean := Basis(Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized(), r.randf_range(0.0, 0.05))
			var xf := Transform3D(lean * Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(h, h, h) / PINE_H), p)
			# hue: from blue-green to dry olive
			var g := r.randf_range(0.8, 1.1)
			var hue := Color(g * r.randf_range(0.88, 1.08), g, g * r.randf_range(0.82, 1.0))
			if not outside:
				var v := r.randi() % 3
				lists[v].append(xf)
				near_cols[v].append(hue)
				if p.z > Layout.PLAY.position.y + 1.0:
					c.post_collider(p, 0.45 * h / PINE_H, 4.0)
			far_xfs.append(xf)
			cols.append(hue * Color(0.9, 0.95, 0.9))
		z += step
	for v in 3:
		c.scatter_mm("Pines%d" % v, meshes[v], lists[v], 80.0, 0.0, PINE_NEAR, true, near_cols[v])
	var card_mat = Trees.impostor_material("pine", c.M["pine_card"].albedo_texture)
	c.scatter_mm("PineCards", Trees.impostor_mesh(PINE_H * 1.05, PINE_H * 0.6), far_xfs, 120.0, PINE_NEAR, 0.0, false, cols, card_mat)
	_trailer_park(c, r)
	_logging_yard(c, r)
	_water_tower(c, _g(c, Vector3(25, -0.1, -192)))
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
	var lp: Vector3 = Layout.LAKE.pos
	if Vector2(p.x - lp.x, p.z - lp.z).length() < Layout.LAKE.radius * 1.2 + 3.0:
		return false # the lake (its ring of pines stands just back from the shore)
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


## p lifted onto the terrain (plus its own y as an offset).
static func _g(c, p: Vector3) -> Vector3:
	return Vector3(p.x, c.height_at(p.x, p.z) + p.y, p.z)


## A pool of lamplight laid over the terrain (additive decal that follows the slope).
static func _pool(c, p: Vector3, r: float) -> void:
	c.ck = c._chunk_of(p.x, p.z)
	Terrain.conform_quad(c._b("pool"), p, r, 0.05, Color.WHITE, 3)


## A sodium lamp on a leaning wooden pole.
static func _pole_lamp(c, p: Vector3, face: Vector3) -> void:
	p = _g(c, p) - Vector3(0, 0.1, 0)
	c.ck = c._chunk_of(p.x, p.z)
	var m = c._b("metal")
	c.cyl(m, p, 0.14, 0.11, 7.0, 6, Color(0.24, 0.18, 0.12), false)
	var head := p + Vector3(0, 6.8, 0) + face * 1.4
	c.beam(m, p + Vector3(0, 6.6, 0), head, 0.08, 0.08, Color(0.06, 0.06, 0.06))
	c.box(c._b("sodium"), head - Vector3(0, 0.12, 0), Vector3(0.5, 0.14, 0.3), Color.WHITE, Basis(Vector3.UP, atan2(face.x, face.z)))
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(1.6, 1.6, 1.6)), head - Vector3(0, 0.25, 0)))
	_pool(c, Vector3(head.x, 0, head.z), 5.5)
	c.lamp_positions.append(head)
	c.post_collider(p, 0.2, 3.0)


static func _trailer_park(c, r: RandomNumberGenerator) -> void:
	var centre: Vector3 = PINE_CLEARINGS[0][0]
	var xfs: Array = []
	var size := Vector3.ZERO
	for k in 9:
		var a := TAU * k / 9.0 + 0.2
		var p := _g(c, centre + Vector3(cos(a), 0, sin(a)) * 17.0)
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
		_pool(c, Vector3(porch.x, 0, porch.z) + xf.basis.z * 1.2, 3.0)
		if r.randf() < 0.6:
			c._car(_g(c, xf.origin + xf.basis.z * 6.5 + xf.basis.x * r.randf_range(-3.0, 3.0)), xf.basis.get_euler().y + PI * 0.5 + r.randf_range(-0.3, 0.3))
	# torn chain-link round the park, with claw-ripped gaps
	var iron = null
	for k in 24:
		if k % 6 == 2 or k % 6 == 3:
			continue
		var a0 := TAU * k / 24.0
		var a1 := TAU * (k + 1) / 24.0
		var p0 := _g(c, centre + Vector3(cos(a0), 0, sin(a0)) * 25.0) - Vector3(0, 0.1, 0)
		var p1 := _g(c, centre + Vector3(cos(a1), 0, sin(a1)) * 25.0) - Vector3(0, 0.1, 0)
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
		var p: Vector3 = _g(c, pile[0])
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
	var sp := _g(c, Vector3(62, 0, -172))
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
	c._car(_g(c, centre + Vector3(10, 0, 6)), 1.2)
	c._car(_g(c, centre + Vector3(-12, 0, -4)), -0.5)


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
	_pool(c, base + Vector3(0, 0, 4), 9.0)


# ================================================================ the Bayou
static func build_bayou(c) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 5507
	var x0 := 125.0
	var z1 := -60.0
	# the mud bed, the water over it and the islands are the terrain's (terrain.gd)
	for isl in BAYOU_ISLANDS:
		if isl[2] == "camp":
			c.add_anchor(isl[0], "island")
	for bw in BOARDWALKS:
		_boardwalk(c, bw)
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
	for v in 2:
		meshes.append(Trees.cypress_mesh(14.0 + v * 2.5, 700 + v))
	var lists: Array = [[], []]
	var cyp_cols: Array = [[], []]
	var step := 8.5
	var z := -240.0
	while z < z1 - 3.0:
		var x := x0 + 3.0
		while x < 240.0:
			var p := Vector3(x + r.randf_range(-3.0, 3.0), 0.0, z + r.randf_range(-3.0, 3.0))
			x += step
			if Layout.district_at(p.x, p.z) != "bayou" or not _cypress_ok(p):
				continue
			p.y = c.height_at(p.x, p.z)
			var s := r.randf_range(0.85, 1.2)
			var xf := Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s * r.randf_range(0.9, 1.15), s)), p)
			var v := r.randi() % 2
			lists[v].append(xf)
			var g := r.randf_range(0.82, 1.08)
			cyp_cols[v].append(Color(g * r.randf_range(0.9, 1.05), g, g * r.randf_range(0.8, 0.95)))
			if Layout.PLAY.has_point(Vector2(p.x, p.z)):
				c.post_collider(p, 0.7 * s, 4.0)
			# cypress knees round the trunk
			c.ck = c._chunk_of(p.x, p.z)
			for k in r.randi_range(1, 4):
				var kp := _g(c, p + Vector3(r.randf_range(-3.0, 3.0), -0.15, r.randf_range(-3.0, 3.0)))
				c.cyl(c._b("paint"), kp, r.randf_range(0.12, 0.22), 0.02, r.randf_range(0.3, 0.8), 5, Color(0.28, 0.22, 0.17), false)
		z += step
	for v in 2:
		c.scatter_mm("Cypress%d" % v, meshes[v], lists[v], 80.0, 0.0, CYPRESS_NEAR, true, cyp_cols[v])
	# impostor cards beyond (the same cypress, pre-rendered by tools/bake_tree_impostors.gd)
	var far_c: Array = []
	var far_cols: Array = []
	for v in 2:
		for k in lists[v].size():
			var xf: Transform3D = lists[v][k]
			far_c.append(xf.scaled_local(Vector3.ONE * ((14.0 + v * 2.5) / 15.5)))
			far_cols.append(cyp_cols[v][k])
	c.scatter_mm("CypressCards", Trees.impostor_mesh(15.5 * 1.05, 15.5 * 1.05 * 384.0 / 448.0), far_c, 120.0, CYPRESS_NEAR, 0.0, false, far_cols,
		Trees.impostor_material("cypress", c.M["pine_card"].albedo_texture))
	var hero: Array = []
	for k in 12:
		var a := TAU * k / 12.0 + 0.2
		var p := Vector3(185, 0, -152) + Vector3(cos(a) * 38.0, 0, sin(a) * 34.0)
		if not _cypress_ok(p) or Layout.district_at(p.x, p.z) != "bayou":
			continue
		hero.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU), _g(c, p) - Vector3(0, 0.2, 0)))
		c.post_collider(p, 0.9, 4.0)
	c.glb_multimesh("cypress_tree", 17.0, hero, 80.0, 140.0, true)
	_plantation(c)
	# fireflies over the water
	for f in [Vector3(165, 1.2, -120), Vector3(200, 1.2, -150), Vector3(160, 1.2, -185), Vector3(185, 1.2, -100)]:
		_fireflies(c, Vector3(f.x, maxf(c.height_at(f.x, f.z), Layout.BAYOU_WATER) + f.y, f.z))
	# fireflies over the lake in the pines too
	var lp: Vector3 = Layout.LAKE.pos
	_fireflies(c, lp + Vector3(0, Layout.LAKE.level + 1.0, 0))
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


## A boardwalk: planks a hand above the terrain's causeway, on posts down into the mud.
static func _boardwalk(c, bw: Array) -> void:
	var pts: Array = []
	for k in bw.size() - 1:
		var a: Vector3 = bw[k]
		var b: Vector3 = bw[k + 1]
		var n := a.distance_to(b)
		var steps := maxi(1, int(ceilf(n / 4.0)))
		for s in steps:
			pts.append(a.lerp(b, float(s) / steps))
	pts.append(bw[bw.size() - 1])
	for k in pts.size():
		var p: Vector3 = pts[k]
		pts[k] = Vector3(p.x, maxf(c.height_at(p.x, p.z), Layout.BAYOU_WATER + 0.05), p.z)
	c.ground_path("wood", pts, 2.4, Color(0.75, 0.7, 0.62), 0.12, 1000.0)
	for k in range(0, pts.size() - 1):
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var side := Vector3.UP.cross((b - a).normalized()) * 1.15
		c.ck = c._chunk_of(a.x, a.z)
		for sd in [-1.0, 1.0]:
			var q: Vector3 = a + side * sd
			var bed: float = c.height_at(q.x, q.z)
			c.cyl(c._b("wood"), Vector3(q.x, bed - 0.3, q.z), 0.09, 0.08, a.y + 0.12 - bed + 0.3, 5, Color(0.4, 0.34, 0.28), false)


static func _lantern_post(c, p: Vector3) -> void:
	p = _g(c, p) - Vector3(0, 0.1, 0)
	c.ck = c._chunk_of(p.x, p.z)
	var m = c._b("metal")
	c.cyl(m, p, 0.08, 0.07, 2.4, 5, Color(0.2, 0.16, 0.12), false)
	c.beam(m, p + Vector3(0, 2.3, 0), p + Vector3(0.6, 2.3, 0), 0.05, 0.05, Color(0.05, 0.05, 0.05))
	var l := p + Vector3(0.6, 1.95, 0)
	c.box(c._b("lamp"), l, Vector3(0.2, 0.3, 0.2), Color.WHITE)
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(0.8, 0.8, 0.8)), l))
	_pool(c, Vector3(l.x, 0.0, l.z), 2.6)


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
