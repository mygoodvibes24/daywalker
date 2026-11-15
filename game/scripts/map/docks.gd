extends RefCounted
## The Docks (docs/concept_art/05_docks.jpg): the west quay on the black river. Gantry
## cranes with red beacons over the apron, a canyon of rusted container stacks, a row of
## corrugated warehouses (one hides a caged fight pit), an oil-tank farm in the north,
## Pier Nine in the south, a moored cargo ship and the river bridge on the skyline.

const Layout = preload("res://scripts/map/map_layout.gd")

const QX := -205.0 # quay edge
const WATER_Y := -1.6
const YARD := [-183.0, -139.0] # container yard x range
const ROAD_X := -133.0 # the dock road (N-S)
const WH := [-125.0, -87.0] # warehouse row x range
const CRANES := [-130.0, -20.0, 95.0]
const CONTAINER_COLS := [Color(0.42, 0.12, 0.08), Color(0.12, 0.2, 0.32), Color(0.16, 0.26, 0.17), Color(0.55, 0.3, 0.1),
	Color(0.35, 0.34, 0.33), Color(0.6, 0.58, 0.52), Color(0.3, 0.1, 0.12), Color(0.08, 0.22, 0.24)]


static func build(c) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3303
	# ground: quay concrete; the river beyond the quay wall (west) and round the south bend
	c.ground_rect("dock", QX, -240.0, -80.0, Layout.RIVER_Z, Color.WHITE, 0.02)
	_water(c)
	# streets: the Old Quarter's cross streets run on to the quay, the dock road runs north-south
	for k in range(-5, 6):
		var z := k * 40.0
		c.ground_path("asphalt", [Vector3(-80, 0, z), Vector3(QX + 2.0, 0, z)], 9.0, Color.WHITE, 0.035, 20.0)
	c.ground_path("asphalt", [Vector3(ROAD_X, 0, -215), Vector3(ROAD_X, 0, 215)], 11.0, Color.WHITE, 0.036, 20.0)
	c.ground_path("asphalt", [Vector3(-188, 0, -215), Vector3(-188, 0, 215)], 7.0, Color(0.9, 0.9, 0.9), 0.036, 25.0)
	_quay(c, r)
	_yard(c, r)
	_warehouses(c, r)
	_tank_farm(c, r)
	for z in CRANES:
		_crane(c, Vector3(-196, 0, z))
	_ship(c, r)
	_bridge(c)
	# flood masts along the dock road and the apron
	var z := -200.0
	var side := 1.0
	while z < 210.0:
		_mast(c, Vector3(ROAD_X + side * 7.0, 0, z + 12.0), Vector3(-side, 0, 0))
		side = -side
		z += 32.0
	# anchors for points of interest: yard aisles, dock-road crossings, the apron, the pit
	for k in range(-4, 5):
		c.add_anchor(Vector3(ROAD_X, 0, k * 40.0), "dockroad")
	for zz in [-150.0, -100.0, -60.0, 20.0, 60.0, 120.0]:
		c.add_anchor(Vector3(-161, 0, zz + 20.0), "yard")
	for zz in [-170.0, -85.0, 50.0, 140.0]:
		c.add_anchor(Vector3(-192, 0, zz), "apron")
	c.add_anchor(Vector3(-106, 0, 20), "pit")
	c.add_anchor(Vector3(-140, 0, -176), "tanks")
	# loot: crates on the quay and in the yard
	for p in [Vector3(-198, 0, -100), Vector3(-160, 0, -45), Vector3(-128, 0, 60), Vector3(-196, 0, 130), Vector3(-161, 0, 100), Vector3(-128, 0, -150), Vector3(-110, 0, 18)]:
		c.cache_spots.append({"pos": p + Vector3(0, 0.1, 0), "yaw": r.randf() * TAU, "coffin": false})


static func _water(c) -> void:
	c.ck = "F"
	var w = c._b("water")
	var y := WATER_Y
	var e := Layout.HALF + 160.0
	# west river and the south bend, out to the far bank
	w.quad(Vector3(-e, y, Layout.RIVER_Z + 400.0), Vector3(-e, y, -e), Vector3(QX, y, -e), Vector3(QX, y, Layout.RIVER_Z + 400.0), Vector3.UP, Color.WHITE)
	w.quad(Vector3(QX, y, Layout.RIVER_Z + 400.0), Vector3(QX, y, Layout.RIVER_Z), Vector3(e, y, Layout.RIVER_Z), Vector3(e, y, Layout.RIVER_Z + 400.0), Vector3.UP, Color.WHITE)
	# quay walls down to the water
	var st = c._b("stone")
	var wall := Color(0.32, 0.31, 0.3)
	st.quad(Vector3(QX, y - 0.2, Layout.RIVER_Z), Vector3(QX, 0.12, Layout.RIVER_Z), Vector3(QX, 0.12, -e), Vector3(QX, y - 0.2, -e), Vector3(-1, 0, 0), wall)
	st.quad(Vector3(e, y - 0.2, Layout.RIVER_Z), Vector3(e, 0.12, Layout.RIVER_Z), Vector3(QX, 0.12, Layout.RIVER_Z), Vector3(QX, y - 0.2, Layout.RIVER_Z), Vector3(0, 0, 1), wall)


## Bollards, a granite edge, tyre fenders and mooring ropes along the quay.
static func _quay(c, r: RandomNumberGenerator) -> void:
	var z := -220.0
	while z < Layout.RIVER_Z:
		c.ck = c._chunk_of(QX, z)
		var st = c._b("stone")
		st.quad(Vector3(QX, 0.1, z + 10.0), Vector3(QX, 0.1, z), Vector3(QX + 0.7, 0.1, z), Vector3(QX + 0.7, 0.1, z + 10.0), Vector3.UP, Color(0.5, 0.48, 0.45))
		var m = c._b("metal")
		var bp := Vector3(QX + 1.3, 0.0, z + 5.0)
		c.cyl(m, bp, 0.32, 0.26, 0.6, 8, Color(0.16, 0.1, 0.07), false)
		c.cyl(m, bp + Vector3(0, 0.6, 0), 0.42, 0.42, 0.14, 8, Color(0.16, 0.1, 0.07))
		c.post_collider(bp, 0.4, 1.0)
		if int(z) % 20 == 0:
			c.cyl(c._b("paint"), Vector3(QX - 0.25, -0.9, z + 2.0), 0.55, 0.55, 0.35, 10, Color(0.04, 0.04, 0.04), true, Basis(Vector3.FORWARD, PI * 0.5))
		z += 10.0
	# loose containers on the apron and by the warehouses (generated model, close range only)
	var xfs: Array = []
	for k in 22:
		var p := Vector3(r.randf_range(-186.0, -184.0) if k % 2 == 0 else r.randf_range(-120.0, -92.0), 0.0, -190.0 + k * 17.5 + r.randf_range(-3.0, 3.0))
		if k % 2 == 1:
			p.x = ROAD_X + 8.5 + r.randf() * 1.0
		var near_street := absf(p.z - roundf(p.z / 40.0) * 40.0) < 8.0
		if near_street:
			continue
		var yaw := PI * 0.5 + r.randf_range(-0.15, 0.15)
		xfs.append(Transform3D(Basis(Vector3.UP, yaw), p))
	var size: Vector3 = c.glb_multimesh("shipping_container", 2.6, xfs, 80.0, 95.0, true)
	if size != Vector3.ZERO:
		for xf: Transform3D in xfs:
			c.box_collider(xf.origin + Vector3(0, 1.3, 0), Vector3(size.x * 0.95, 2.6, size.z * 0.95), xf.basis.get_euler().y)


## Container stacks forming corridors: two columns of 12 m boxes, bays of six rows.
static func _yard(c, r: RandomNumberGenerator) -> void:
	var z := -166.0
	var row := 0
	while z < 150.0:
		var street := absf(z - roundf(z / 40.0) * 40.0) < 7.5
		var aisle := row % 7 == 6
		row += 1
		if street or aisle:
			z += 2.7
			continue
		for cx in [-172.0, -150.0]:
			if r.randf() < 0.08:
				continue # a gap to slip through
			var h: int = [1, 2, 2, 3, 3, 4][r.randi() % 6]
			var p := Vector3(cx + r.randf_range(-0.3, 0.3), 0.0, z)
			c.ck = c._chunk_of(p.x, p.z)
			var bt = c._b("corrugated")
			for k in h:
				var col: Color = CONTAINER_COLS[r.randi() % CONTAINER_COLS.size()]
				var yaw := r.randf_range(-0.02, 0.02)
				c.box(bt, p + Vector3(r.randf_range(-0.15, 0.15), 1.3 + k * 2.6, 0), Vector3(12.2, 2.58, 2.44), col, Basis(Vector3.UP, yaw), 8)
				# door end: dark lock bars
				c.box(c._b("metal"), p + Vector3(6.12, 1.3 + k * 2.6, 0), Vector3(0.05, 2.3, 2.2), col * Color(0.6, 0.6, 0.6), Basis.IDENTITY, 8)
			c.box_collider(p + Vector3(0, h * 1.3, 0), Vector3(12.2, h * 2.6, 2.44))
			c.hlod_box(Rect2(p.x - 6.1, p.z - 1.22, 12.2, 2.44), h * 2.6, Color(0.5, 0.3, 0.25))
		z += 2.7
	# chain-link with razor wire along the yard's road side, gaps at the streets
	var fz := -166.0
	while fz < 150.0:
		var z0 := fz
		var z1 := fz + 10.0
		fz += 10.0
		if absf(z0 + 5.0 - roundf((z0 + 5.0) / 40.0) * 40.0) < 8.0:
			continue
		c.ck = c._chunk_of(YARD[1], z0)
		var iron = c._b("iron")
		var x := YARD[1] + 1.5
		iron.quad(Vector3(x, 0, z0), Vector3(x, 2.4, z0), Vector3(x, 2.4, z1), Vector3(x, 0, z1), Vector3(1, 0, 0), Color.WHITE, Vector2(0, 0.5), Vector2(5.0, 1.0))
		c.cyl(c._b("metal"), Vector3(x, 0, z0), 0.05, 0.05, 2.7, 5, Color(0.3, 0.3, 0.3), false)
		c.beam(c._b("metal"), Vector3(x, 2.7, z0), Vector3(x, 2.7, z1), 0.12, 0.12, Color(0.18, 0.18, 0.18))


static func _warehouses(c, r: RandomNumberGenerator) -> void:
	for k in range(-4, 5):
		var z0 := k * 40.0 + 6.0
		var z1 := k * 40.0 + 34.0
		var pit := k == 0
		_warehouse(c, r, WH[0], z0, WH[1], z1, pit)


static func _warehouse(c, r: RandomNumberGenerator, x0: float, z0: float, x1: float, z1: float, pit: bool) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	c.ck = c._chunk_of(cx, cz)
	var wall = c._b("corrugated")
	var col: Color = [Color(0.55, 0.45, 0.38), Color(0.42, 0.4, 0.38), Color(0.5, 0.36, 0.3), Color(0.38, 0.42, 0.44)][r.randi() % 4]
	var H := 10.0
	var ridge := 14.0
	var t := 0.3
	var door_w := 8.0 if pit else 6.0
	# walls (the west wall has a door; in the pit hall it's open)
	c.box(wall, Vector3(x1 - t * 0.5, H * 0.5, cz), Vector3(t, H, z1 - z0), col, Basis.IDENTITY, 8)
	c.box(wall, Vector3(cx, H * 0.5, z0 + t * 0.5), Vector3(x1 - x0, H, t), col, Basis.IDENTITY, 8)
	c.box(wall, Vector3(cx, H * 0.5, z1 - t * 0.5), Vector3(x1 - x0, H, t), col, Basis.IDENTITY, 8)
	var dz0 := cz - door_w * 0.5
	var dz1 := cz + door_w * 0.5
	c.box(wall, Vector3(x0 + t * 0.5, H * 0.5, (z0 + dz0) * 0.5), Vector3(t, H, dz0 - z0), col, Basis.IDENTITY, 8)
	c.box(wall, Vector3(x0 + t * 0.5, H * 0.5, (dz1 + z1) * 0.5), Vector3(t, H, z1 - dz1), col, Basis.IDENTITY, 8)
	c.box(wall, Vector3(x0 + t * 0.5, (H + 6.0) * 0.5, cz), Vector3(t, H - 6.0, door_w), col, Basis.IDENTITY, 8)
	# gable roof along z, gables at the ends
	var roof = c._b("corrugated")
	var rc := col * Color(0.6, 0.55, 0.5)
	var a0 := Vector3(x0 - 0.4, H, z0 - 0.4)
	var a1 := Vector3(x0 - 0.4, H, z1 + 0.4)
	var b0 := Vector3(cx, ridge, z0 - 0.4)
	var b1 := Vector3(cx, ridge, z1 + 0.4)
	var d0 := Vector3(x1 + 0.4, H, z0 - 0.4)
	var d1 := Vector3(x1 + 0.4, H, z1 + 0.4)
	roof.quad(a1, b1, b0, a0, Vector3(-(ridge - H), (x1 - x0) * 0.5, 0).normalized(), rc)
	roof.quad(d0, b0, b1, d1, Vector3((ridge - H), (x1 - x0) * 0.5, 0).normalized(), rc)
	roof.quad(a0, b0, b1, a1, Vector3((ridge - H), -(x1 - x0) * 0.5, 0).normalized(), rc * Color(0.5, 0.5, 0.5))
	roof.quad(d1, b1, b0, d0, Vector3(-(ridge - H), -(x1 - x0) * 0.5, 0).normalized(), rc * Color(0.5, 0.5, 0.5))
	for zz in [z0, z1]:
		var n := Vector3(0, 0, -1) if zz == z0 else Vector3(0, 0, 1)
		wall.tri(Vector3(x0, H, zz), Vector3(cx, ridge, zz), Vector3(x1, H, zz), n, col)
		wall.tri(Vector3(x0, H, zz), Vector3(cx, ridge, zz), Vector3(x1, H, zz), -n, col * Color(0.4, 0.4, 0.4))
	# clerestory windows (warm, grimy) along both long walls
	var glass = c._b("glass")
	for xx in [x0 - 0.02, x1 + 0.02]:
		var n := Vector3(-1, 0, 0) if xx == x0 - 0.02 else Vector3(1, 0, 0)
		var zz := z0 + 1.5
		while zz < z1 - 3.0:
			var uv: Array = c.cell_uv(r.randi() % 4, 2 if r.randf() < 0.5 else r.randi() % 2)
			glass.quad(Vector3(xx, 7.2, zz + (2.4 if n.x < 0 else 0.0)), Vector3(xx, 9.0, zz + (2.4 if n.x < 0 else 0.0)), Vector3(xx, 9.0, zz + (0.0 if n.x < 0 else 2.4)), Vector3(xx, 7.2, zz + (0.0 if n.x < 0 else 2.4)), n, Color.WHITE, uv[0], uv[1])
			zz += 3.2
	# the door: a dark opening (or the open pit) and a sodium lamp over it
	var dark := Color(0.03, 0.025, 0.02)
	if not pit:
		c._b("trim").quad(Vector3(x0 - 0.03, 0.0, dz1), Vector3(x0 - 0.03, 6.0, dz1), Vector3(x0 - 0.03, 6.0, dz0), Vector3(x0 - 0.03, 0.0, dz0), Vector3(-1, 0, 0), dark)
	var lamp := Vector3(x0 - 0.6, 6.8, cz)
	c.box(c._b("sodium"), lamp, Vector3(0.6, 0.18, 0.4), Color.WHITE)
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(1.6, 1.6, 1.6)), lamp - Vector3(0.2, 0.2, 0)))
	c._light_pool(Vector3(x0 - 3.5, 0, cz), 6.0)
	c._wall_glow(Vector3(x0 - 0.05, 0, cz), Vector3(-1, 0, 0), 9.0, 9.0)
	# colliders: four walls (gap at the door) so the pit hall can be entered
	if pit:
		c.box_collider(Vector3(x1 - t * 0.5, H * 0.5, cz), Vector3(t + 0.2, H, z1 - z0))
		c.box_collider(Vector3(cx, H * 0.5, z0 + t * 0.5), Vector3(x1 - x0, H, t + 0.2))
		c.box_collider(Vector3(cx, H * 0.5, z1 - t * 0.5), Vector3(x1 - x0, H, t + 0.2))
		c.box_collider(Vector3(x0 + t * 0.5, H * 0.5, (z0 + dz0) * 0.5), Vector3(t + 0.2, H, dz0 - z0))
		c.box_collider(Vector3(x0 + t * 0.5, H * 0.5, (dz1 + z1) * 0.5), Vector3(t + 0.2, H, z1 - dz1))
		_fight_pit(c, r, Vector3(cx, 0, cz), x0, x1, z0, z1, H)
	else:
		c.box_collider(Vector3(cx, H * 0.5, cz), Vector3(x1 - x0, H, z1 - z0))
		c.lots.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	c.hlod_box(Rect2(x0, z0, x1 - x0, z1 - z0), H + 2.0, col)
	if pit:
		c.lots.append(Rect2(x0, z0, x1 - x0, z1 - z0))


## The caged fight pit inside the hall: an iron cage ring, a crowd of silhouettes on
## benches round it, bare bulbs over the ring and an orange haze.
static func _fight_pit(c, r: RandomNumberGenerator, p: Vector3, x0: float, x1: float, z0: float, z1: float, H: float) -> void:
	var iron = c._b("iron")
	var m = c._b("metal")
	# interior wall faces (darker) and a floor
	c._b("dock").quad(Vector3(x0, 0.04, z1), Vector3(x0, 0.04, z0), Vector3(x1, 0.04, z0), Vector3(x1, 0.04, z1), Vector3.UP, Color.WHITE)
	var R := 7.5
	var segs := 16
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var q0 := p + Vector3(cos(a0), 0, sin(a0)) * R
		var q1 := p + Vector3(cos(a1), 0, sin(a1)) * R
		if s == 8:
			continue # the cage door, open
		var n := ((q0 + q1) * 0.5 - p).normalized()
		iron.quad(q0, q0 + Vector3(0, 3.0, 0), q1 + Vector3(0, 3.0, 0), q1, n, Color.WHITE, Vector2(0, 0.5), Vector2(1.5, 1.0))
		c.cyl(m, q0, 0.06, 0.06, 3.2, 5, Color(0.1, 0.1, 0.1), false)
	# the crowd: dark figures on the far side, lit from the ring
	for k in 26:
		var a := TAU * k / 26.0 + r.randf_range(-0.05, 0.05)
		var d := r.randf_range(10.0, 12.5)
		var fp := p + Vector3(cos(a) * d, 0, sin(a) * d * 0.9)
		if fp.x < x0 + 3.0 or absf(a - PI) < 0.5:
			continue # keep the doorway clear
		c.cyl(m, fp, 0.28, 0.22, 1.5, 6, Color(0.05, 0.045, 0.04), false)
		c.cyl(m, fp + Vector3(0, 1.5, 0), 0.13, 0.13, 0.26, 6, Color(0.06, 0.05, 0.045))
	# bulbs and the glow
	for k in 3:
		var bp := p + Vector3((k - 1) * 3.0, H - 3.0, 0)
		c.box(c._b("sodium"), bp, Vector3(0.3, 0.3, 0.3), Color.WHITE)
		c.beam(m, bp, bp + Vector3(0, 3.0, 0), 0.02, 0.02, Color(0.05, 0.05, 0.05))
		c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(2.2, 2.2, 2.2)), bp))
	c._light_pool(p, 9.0)
	c._light_pool(p, 5.0)
	var l := OmniLight3D.new()
	l.position = p + Vector3(0, 6.0, 0)
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 2.2
	l.omni_range = 16.0
	c.add_child(l)


static func _tank_farm(c, r: RandomNumberGenerator) -> void:
	for t in [Vector3(-180, 0, -208), Vector3(-158, 0, -210), Vector3(-104, 0, -206), Vector3(-176, 0, -184), Vector3(-104, 0, -182), Vector3(-156, 0, -186)]:
		c.ck = c._chunk_of(t.x, t.z)
		var m = c._b("concrete")
		var rr := 8.0
		var h := r.randf_range(10.0, 13.0)
		c.cyl(m, t, rr, rr, h, 20, Color(0.62, 0.6, 0.56), false)
		c.cyl(m, t + Vector3(0, h, 0), rr + 0.1, rr * 0.2, 1.6, 20, Color(0.45, 0.44, 0.42))
		for hy in [h * 0.33, h * 0.66]:
			c.cyl(c._b("metal"), t + Vector3(0, hy, 0), rr + 0.06, rr + 0.06, 0.15, 20, Color(0.3, 0.2, 0.15), false)
		c.post_collider(t, rr + 0.1, h)
		c.lots.append(Rect2(t.x - rr, t.z - rr, rr * 2.0, rr * 2.0))
		c.hlod_box(Rect2(t.x - rr * 0.8, t.z - rr * 0.8, rr * 1.6, rr * 1.6), h, Color(0.6, 0.6, 0.6))
	# a smokestack
	c.ck = "M"
	c.cyl(c._b("brick"), Vector3(-120, 0, -222), 2.2, 1.6, 34.0, 12, Color(0.7, 0.6, 0.55), false)
	c.box(c._b("beacon"), Vector3(-120, 34.5, -222), Vector3(0.4, 0.4, 0.4), Color.WHITE)
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(2.5, 2.5, 2.5)), Vector3(-120, 34.5, -222)))


## A rail-mounted gantry crane over the apron (generated model), with red beacons on top
## and sodium floods under the beam. The big landmark silhouette of the docks.
static func _crane(c, p: Vector3) -> void:
	var size: Vector3 = c.place_glb("gantry_crane", 34.0, Transform3D(Basis.IDENTITY, p), true)
	if size == Vector3.ZERO:
		size = Vector3(10.6, 34.0, 48.0)
		c.ck = "M"
		var m = c._b("metal")
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				c.box(m, p + Vector3(sx * 5.0, 16.0, sz * 22.0), Vector3(1.2, 32.0, 1.2), Color(0.45, 0.16, 0.08))
		c.box(m, p + Vector3(0, 32.0, 0), Vector3(11.0, 2.4, 48.0), Color(0.45, 0.16, 0.08))
	var hx := size.x * 0.5 - 0.8
	var hz := size.z * 0.5 - 1.2
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			c.post_collider(p + Vector3(sx * hx, 0, sz * hz), 0.9, 8.0)
	c.ck = "M"
	for sz in [-1.0, 1.0]:
		var b := p + Vector3(0, size.y + 0.4, sz * (size.z * 0.5 - 1.0))
		c.box(c._b("beacon"), b, Vector3(0.6, 0.6, 0.6), Color.WHITE)
		c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(3.5, 3.5, 3.5)), b))
		var f := p + Vector3(0, size.y * 0.78, sz * 9.0)
		c.box(c._b("sodium"), f, Vector3(0.8, 0.3, 0.8), Color.WHITE)
		c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(2.5, 2.5, 2.5)), f - Vector3(0, 0.4, 0)))
		c.ck = c._chunk_of(p.x, p.z)
		c._light_pool(Vector3(p.x, 0, f.z), 8.0)
		c.ck = "M"


## The cargo ship moored off the quay: hull, deck stacks, bridge house, lights.
static func _ship(c, r: RandomNumberGenerator) -> void:
	c.ck = "M"
	var x := -226.0
	var z0 := -80.0
	var z1 := 40.0
	var hull = c._b("metal")
	var hc := Color(0.16, 0.06, 0.05)
	var y0 := WATER_Y - 1.0
	var top := 9.0
	var hw := 10.0
	# hull box with a pointed bow (north)
	c.box(hull, Vector3(x, (y0 + top) * 0.5, (z0 + 12.0 + z1) * 0.5), Vector3(hw * 2.0, top - y0, z1 - z0 - 12.0), hc, Basis.IDENTITY, 8)
	c.hexa(hull, [Vector3(x - hw, y0, z0 + 12.0), Vector3(x + hw, y0, z0 + 12.0), Vector3(x + 0.5, y0, z0), Vector3(x - 0.5, y0, z0),
		Vector3(x - hw, top, z0 + 12.0), Vector3(x + hw, top, z0 + 12.0), Vector3(x + 0.5, top + 1.5, z0 - 3.0), Vector3(x - 0.5, top + 1.5, z0 - 3.0)], hc)
	c._b("paint").quad(Vector3(x + hw + 0.02, y0 + 2.2, z1), Vector3(x + hw + 0.02, y0 + 3.0, z1), Vector3(x + hw + 0.02, y0 + 3.0, z0 + 12.0), Vector3(x + hw + 0.02, y0 + 2.2, z0 + 12.0), Vector3(1, 0, 0), Color(0.6, 0.55, 0.5))
	# containers on deck
	var bt = c._b("corrugated")
	var zz := z0 + 14.0
	while zz < z1 - 22.0:
		for k in 6:
			var h := r.randi_range(1, 4)
			for s in h:
				c.box(bt, Vector3(x - hw + 1.8 + k * 2.75, top + 1.3 + s * 2.6, zz + 6.1), Vector3(2.44, 2.58, 12.2), CONTAINER_COLS[r.randi() % CONTAINER_COLS.size()], Basis.IDENTITY, 8)
		zz += 13.0
	# bridge house at the stern
	var bh := Vector3(x, top, z1 - 9.0)
	c.box(c._b("concrete"), bh + Vector3(0, 7.0, 0), Vector3(hw * 1.8, 14.0, 12.0), Color(0.75, 0.73, 0.68), Basis.IDENTITY, 8)
	var glass = c._b("glass")
	for fl in 4:
		var uv: Array = c.cell_uv(fl % 4, 2)
		glass.quad(Vector3(x + hw * 0.9 + 0.02, top + 2.0 + fl * 3.2, z1 - 3.5), Vector3(x + hw * 0.9 + 0.02, top + 3.6 + fl * 3.2, z1 - 3.5),
			Vector3(x + hw * 0.9 + 0.02, top + 3.6 + fl * 3.2, z1 - 14.5), Vector3(x + hw * 0.9 + 0.02, top + 2.0 + fl * 3.2, z1 - 14.5), Vector3(1, 0, 0), Color.WHITE, uv[0], Vector2(uv[1].x * 3.0, uv[1].y))
	c.cyl(c._b("metal"), bh + Vector3(0, 14.0, 2.0), 1.4, 1.2, 6.0, 10, Color(0.3, 0.08, 0.06))
	c.box(c._b("beacon"), bh + Vector3(0, 21.0, 0), Vector3(0.4, 0.4, 0.4), Color.WHITE)
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(2.5, 2.5, 2.5)), bh + Vector3(0, 21.0, 0)))
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(1.5, 1.5, 1.5)), Vector3(x, top + 2.5, z0 - 2.0)))


## The river bridge on the north-west skyline: piers, a deck and a truss with red lights.
static func _bridge(c) -> void:
	c.ck = "F"
	var m = c._b("metal")
	var z := -205.0
	var x0 := -212.0
	var x1 := -420.0
	var y := 24.0
	var col := Color(0.12, 0.12, 0.13)
	c.box(m, Vector3((x0 + x1) * 0.5, y, z), Vector3(x0 - x1, 1.6, 14.0), col)
	for k in 5:
		var x := x0 - 20.0 - k * 45.0
		c.box(c._b("concrete"), Vector3(x, (y + WATER_Y) * 0.5, z), Vector3(6.0, y - WATER_Y, 10.0), Color(0.35, 0.35, 0.36))
	var k := 0
	var x := x0
	while x > x1:
		var nx := x - 15.0
		for sz in [-6.5, 6.5]:
			c.beam(m, Vector3(x, y, z + sz), Vector3(nx, y + 14.0 if k % 2 == 0 else y, z + sz), 0.5, 0.5, col)
			c.beam(m, Vector3(x, y + 14.0, z + sz), Vector3(nx, y + 14.0, z + sz), 0.6, 0.6, col)
		if k % 3 == 0:
			c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(3.0, 3.0, 3.0)), Vector3(x, y + 14.6, z)))
		x = nx
		k += 1


## A tall sodium flood mast on the docks.
static func _mast(c, p: Vector3, face: Vector3) -> void:
	c.ck = c._chunk_of(p.x, p.z)
	var m = c._b("metal")
	c.cyl(m, p, 0.2, 0.14, 11.0, 6, Color(0.2, 0.2, 0.2), false)
	var head := p + Vector3(0, 10.8, 0) + face * 1.2
	c.beam(m, p + Vector3(0, 10.6, 0), head, 0.1, 0.1, Color(0.1, 0.1, 0.1))
	c.box(c._b("sodium"), head - Vector3(0, 0.15, 0), Vector3(0.9, 0.2, 0.5), Color.WHITE, Basis(Vector3.UP, atan2(face.x, face.z)))
	c.halo_xfs.append(Transform3D(Basis().scaled(Vector3(2.2, 2.2, 2.2)), head - Vector3(0, 0.3, 0)))
	c._light_pool(Vector3(head.x, 0, head.z) + face * 2.0, 8.0)
	c.lamp_positions.append(head)
	c.post_collider(p, 0.25, 3.0)
