extends RefCounted
## The walkable Undercroft stair (concept art 01): the sunken circular well in the cathedral
## plaza, now a real way down. Called from city.gd build_lair() (the "UNDERCROFT HOOK"), which
## keeps the balustrade, the arch, the angels and the red uplight; this builds what you walk on:
##
##   - a top landing under the arch (the balustrade's gap), then ONE spiral flight hugging the
##     shaft wall, 250 degrees round and 3.4 m down (20 steps of 0.17 m, ~20 degree slope), with a
##     low parapet on its open side; a ramp collider sits under the visible steps
##   - the well's floor, and a red-lit door under the landing that opens on the tunnel down to the
##     Undercroft Depths (map/undercroft.gd builds the tunnel and the crypt)
##   - colliders: the shaft wall (with the door gap), the balustrade ring (open under the arch), the
##     floor, and a flat cover at street level over the hollowed ground (below)
##
## The ground: the terrain's one HeightMapShape3D (map/terrain.gd) is hollowed out under the plaza
## (its collision copy only: Terrain.H, and so height_at(), are unchanged) so the stair, the tunnel
## and the crypt can live below street level; slab colliders put the walkable street back at y = 0
## everywhere above the hollow, except over the well itself.

const PIT_R := 3.0
const PIT_D := 3.4
const LAND_A0 := deg_to_rad(64.0) # the top landing spans the balustrade's gap under the arch
const LAND_A1 := deg_to_rad(116.0)
const SWEEP := deg_to_rad(250.0) # the flight: from LAND_A1 round to LAND_A1 + SWEEP
const STEPS := 20
const R_IN := 1.3 # parapet inside face
const R_WALK := 1.5 # the walkable band: R_WALK .. PIT_R
const DOOR_HALF := 1.0 # the door under the landing (at +z), half width
const DOOR_TOP := -1.0
## The hollow under the plaza (XZ, metres): the stair well, the tunnel and the crypt all fit
## inside it (see undercroft.gd). Terrain samples inside are dropped to HOLLOW_Y; the street-level
## cover spans HOLLOW grown by one terrain cell (the height field ramps back up over that cell).
const HOLLOW := Rect2(-12.0, -4.0, 28.0, 44.0)
const HOLLOW_Y := -14.0
const COVER_T := 0.5 # slab thickness (top at y = 0)

static var built := false


static func _dir(a: float) -> Vector3:
	return Vector3(cos(a), 0, sin(a))


## Build the stair into the lair batch of `c` (city.gd, its current chunk is "L") and the
## colliders under `root`. y0 is the plaza walk level.
static func build(c, root: Node3D, y0: float) -> void:
	var st = c._b("stone")
	var glow = c._b("crypt_glow")
	var sc := Color(0.6, 0.58, 0.54)
	var tread_col := sc * Color(0.78, 0.76, 0.74)
	var dark := sc * Color(0.42, 0.4, 0.4)
	var R := PIT_R
	var D := PIT_D
	var y_land := y0 - 0.05
	# ---- shaft wall (seen from inside), open at the door
	var segs := 48
	var door_a := asin(DOOR_HALF / R)
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var am := (a0 + a1) * 0.5
		var d0 := _dir(a0)
		var d1 := _dir(a1)
		var in_door := absf(wrapf(am - PI * 0.5, -PI, PI)) < door_a
		var ybot := DOOR_TOP if in_door else -D
		st.quad_sm(d1 * R + Vector3(0, ybot, 0), d1 * R + Vector3(0, y0, 0), d0 * R + Vector3(0, y0, 0), d0 * R + Vector3(0, ybot, 0), -d1, -d1, -d0, -d0, dark)
	# the door: a pointed arch frame, red light breathing up out of the tunnel
	var f = c.new_facade()
	f.n = Vector3(0, 0, -1)
	f.r = Vector3(1, 0, 0)
	f.w = 2.0 * DOOR_HALF
	f.o = Vector3(-DOOR_HALF, -D, R * cos(door_a) - 0.02)
	c._pointed_arch(st, f, DOOR_HALF, DOOR_HALF + 0.05, 2.0, 0.22, 0.02, sc * Color(0.72, 0.7, 0.68), 0.3)
	# lintel fill above the arch head up to the landing
	st.quad(f.p(0.0, 2.4, 0.0), f.p(0.0, D - 0.3, 0.0), f.p(2.0 * DOOR_HALF, D - 0.3, 0.0), f.p(2.0 * DOOR_HALF, 2.4, 0.0), f.n, dark)
	# a carved arch on the free stretch of wall, glowing like the old arcade
	var a := deg_to_rad(33.0)
	var dd := _dir(a)
	var g = c.new_facade()
	g.n = -dd
	g.r = Vector3(-sin(a), 0, cos(a)) * -1.0
	g.w = 1.5
	g.o = dd * (R - 0.03) - g.r * g.w * 0.5 + Vector3(0, -D, 0)
	c.fq(glow, g, 0.2, 0.0, 1.3, 1.7, 0.01, Color(0.3, 0.3, 0.3))
	glow.tri(g.p(0.2, 1.7, 0.01), g.p(0.75, 2.4, 0.01), g.p(1.3, 1.7, 0.01), g.n, Color(0.3, 0.3, 0.3))
	c._pointed_arch(st, g, 0.75, 0.6, 1.7, 0.18, 0.16, sc * Color(0.7, 0.68, 0.66), 0.2)
	# ---- the well floor: wet flags lit red from the door
	c._disc(glow, Vector3(0, -D + 0.01, 0), R, segs, Color(0.2, 0.2, 0.2))
	# ---- top landing (a thick slab; the door opens under it)
	var lsegs := 8
	for q in lsegs:
		var a0 := lerpf(LAND_A0, LAND_A1, float(q) / lsegs)
		var a1 := lerpf(LAND_A0, LAND_A1, float(q + 1) / lsegs)
		var d0 := _dir(a0)
		var d1 := _dir(a1)
		st.quad(d0 * R_IN + Vector3(0, y_land, 0), d0 * (R + 0.3) + Vector3(0, y_land, 0), d1 * (R + 0.3) + Vector3(0, y_land, 0), d1 * R_IN + Vector3(0, y_land, 0), Vector3.UP, tread_col)
		st.quad(d1 * R_IN + Vector3(0, y_land - 0.4, 0), d1 * R + Vector3(0, y_land - 0.4, 0), d0 * R + Vector3(0, y_land - 0.4, 0), d0 * R_IN + Vector3(0, y_land - 0.4, 0), Vector3.DOWN, dark)
	# ---- the spiral flight: treads, risers, the solid inner face down to the floor
	var rise := (y_land + D) / STEPS
	var da := SWEEP / STEPS
	var sub := 3
	for k in STEPS:
		var a0 := LAND_A1 + k * da
		var a1 := a0 + da
		var yt := y_land - (k + 1) * rise
		var col := tread_col * (0.88 + 0.12 * float(k % 2))
		for q in sub:
			var b0 := lerpf(a0, a1, float(q) / sub)
			var b1 := lerpf(a0, a1, float(q + 1) / sub)
			var d0 := _dir(b0)
			var d1 := _dir(b1)
			st.quad(d0 * R_IN + Vector3(0, yt, 0), d0 * R + Vector3(0, yt, 0), d1 * R + Vector3(0, yt, 0), d1 * R_IN + Vector3(0, yt, 0), Vector3.UP, col)
			# the parapet's inside face, from the tread down to the floor
			st.quad_sm(d0 * R_IN + Vector3(0, -D, 0), d0 * R_IN + Vector3(0, yt, 0), d1 * R_IN + Vector3(0, yt, 0), d1 * R_IN + Vector3(0, -D, 0), -d0, -d0, -d1, -d1, dark)
		# riser at the leading edge
		var dr := _dir(a0)
		var tn := Vector3(-sin(a0), 0, cos(a0)) * -1.0 # faces back up the flight
		st.quad(dr * R_IN + Vector3(0, yt, 0), dr * R_IN + Vector3(0, yt + rise, 0), dr * R + Vector3(0, yt + rise, 0), dr * R + Vector3(0, yt, 0), tn, col * Color(0.7, 0.7, 0.7))
	# the end face of the flight on the floor
	var de := _dir(LAND_A1 + SWEEP)
	var te := Vector3(-sin(LAND_A1 + SWEEP), 0, cos(LAND_A1 + SWEEP))
	st.quad(de * R_IN + Vector3(0, -D, 0), de * R_IN + Vector3(0, -D + rise, 0), de * R + Vector3(0, -D + rise, 0), de * R + Vector3(0, -D, 0), te, dark)
	# ---- the parapet on the open side: along the flight, the landing's inner edge and its open end
	var ph := 0.85
	var pw := R_WALK - R_IN
	var n := STEPS * 2
	for k in n:
		var a0 := LAND_A1 + SWEEP * k / n
		var a1 := LAND_A1 + SWEEP * (k + 1) / n
		var y_a := _flight_y(a0, y_land) + ph
		var y_b := _flight_y(a1, y_land) + ph
		_parapet_seg(st, a0, a1, y_a, y_b, _flight_y(a0, y_land), _flight_y(a1, y_land), sc, dark, -D)
	for q in lsegs:
		var a0 := lerpf(LAND_A0, LAND_A1, float(q) / lsegs)
		var a1 := lerpf(LAND_A0, LAND_A1, float(q + 1) / lsegs)
		_parapet_seg(st, a0, a1, y_land + ph, y_land + ph, y_land, y_land, sc, dark, y_land - 0.4)
	# the landing's open end (at LAND_A0): a low wall across to the shaft
	var d64 := _dir(LAND_A0)
	var t64 := Vector3(-sin(LAND_A0), 0, cos(LAND_A0))
	c.box(st, d64 * (R_IN + R) * 0.5 + Vector3(0, y_land + ph * 0.5, 0) - t64 * pw * 0.5, Vector3(R - R_IN, ph, pw), sc, Basis(Vector3.UP, -LAND_A0 + PI * 0.5).orthonormalized())
	# newel posts: the head of the flight and its foot
	for p in [_dir(LAND_A0) * (R_IN + pw * 0.5) + Vector3(0, y_land, 0), _dir(LAND_A1 + SWEEP) * (R_IN + pw * 0.5) + Vector3(0, -D, 0)]:
		c.box(st, p + Vector3(0, 0.55, 0), Vector3(0.36, 1.1, 0.36), sc)
		c.cyl(st, p + Vector3(0, 1.1, 0), 0.16, 0.0, 0.35, 4, sc, true)
	_colliders(root, y0, y_land)


## Height of the flight's walking line at angle a (linear: the ramp under the steps).
static func _flight_y(a: float, y_land: float) -> float:
	var k := clampf((a - LAND_A1) / SWEEP, 0.0, 1.0)
	return lerpf(y_land, -PIT_D, k)


static func _parapet_seg(st, a0: float, a1: float, ya: float, yb: float, fa: float, fb: float, sc: Color, dark: Color, bottom: float) -> void:
	var d0 := _dir(a0)
	var d1 := _dir(a1)
	# top cap
	st.quad(d0 * R_IN + Vector3(0, ya, 0), d0 * R_WALK + Vector3(0, ya, 0), d1 * R_WALK + Vector3(0, yb, 0), d1 * R_IN + Vector3(0, yb, 0), Vector3.UP, sc)
	# the walk side
	st.quad_sm(d1 * R_WALK + Vector3(0, fb, 0), d1 * R_WALK + Vector3(0, yb, 0), d0 * R_WALK + Vector3(0, ya, 0), d0 * R_WALK + Vector3(0, fa, 0), d1, d1, d0, d0, sc * Color(0.85, 0.85, 0.85))
	# the well side (down to the floor)
	st.quad_sm(d0 * R_IN + Vector3(0, bottom, 0), d0 * R_IN + Vector3(0, ya, 0), d1 * R_IN + Vector3(0, yb, 0), d1 * R_IN + Vector3(0, bottom, 0), -d0, -d0, -d1, -d1, dark)


# ---------------------------------------------------------------- collision
static func _colliders(root: Node3D, y0: float, y_land: float) -> void:
	var body := StaticBody3D.new()
	body.name = "UndercroftStairCol"
	root.add_child(body)
	var faces := PackedVector3Array()
	var R := PIT_R
	var D := PIT_D
	var yl := y_land - 0.05 # the collider sits a hair under the visible stone
	# landing top (out to the plaza) and the flight ramp, R_WALK .. R (walls and parapets below)
	var lsegs := 8
	for q in lsegs:
		var a0 := lerpf(LAND_A0, LAND_A1, float(q) / lsegs)
		var a1 := lerpf(LAND_A0, LAND_A1, float(q + 1) / lsegs)
		_quad(faces, _dir(a0) * R_IN + Vector3(0, yl, 0), _dir(a0) * (R + 0.6) + Vector3(0, yl, 0), _dir(a1) * (R + 0.6) + Vector3(0, yl, 0), _dir(a1) * R_IN + Vector3(0, yl, 0))
	var n := 50
	for k in n:
		var a0 := LAND_A1 + SWEEP * k / n
		var a1 := LAND_A1 + SWEEP * (k + 1) / n
		var y_a := _flight_y(a0, yl)
		var y_b := _flight_y(a1, yl)
		_quad(faces, _dir(a0) * R_WALK + Vector3(0, y_a, 0), _dir(a0) * R + Vector3(0, y_a, 0), _dir(a1) * R + Vector3(0, y_b, 0), _dir(a1) * R_WALK + Vector3(0, y_b, 0))
		# parapet: a wall from the ramp up 0.9 m on the walk side, and down to the floor
		var ph := 0.9
		_quad(faces, _dir(a0) * R_WALK + Vector3(0, -D, 0), _dir(a0) * R_WALK + Vector3(0, y_a + ph, 0), _dir(a1) * R_WALK + Vector3(0, y_b + ph, 0), _dir(a1) * R_WALK + Vector3(0, -D, 0))
		_quad(faces, _dir(a0) * R_IN + Vector3(0, -D, 0), _dir(a0) * R_IN + Vector3(0, y_a + ph, 0), _dir(a1) * R_IN + Vector3(0, y_b + ph, 0), _dir(a1) * R_IN + Vector3(0, -D, 0))
		_quad(faces, _dir(a0) * R_IN + Vector3(0, y_a + ph, 0), _dir(a0) * R_WALK + Vector3(0, y_a + ph, 0), _dir(a1) * R_WALK + Vector3(0, y_b + ph, 0), _dir(a1) * R_IN + Vector3(0, y_b + ph, 0))
	# landing parapet (inner edge, and the open end at LAND_A0)
	for q in lsegs:
		var a0 := lerpf(LAND_A0, LAND_A1, float(q) / lsegs)
		var a1 := lerpf(LAND_A0, LAND_A1, float(q + 1) / lsegs)
		_quad(faces, _dir(a0) * R_WALK + Vector3(0, yl - 0.4, 0), _dir(a0) * R_WALK + Vector3(0, yl + 0.9, 0), _dir(a1) * R_WALK + Vector3(0, yl + 0.9, 0), _dir(a1) * R_WALK + Vector3(0, yl - 0.4, 0))
	var d64 := _dir(LAND_A0)
	_quad(faces, d64 * R_IN + Vector3(0, yl - 0.4, 0), d64 * R_IN + Vector3(0, yl + 0.9, 0), d64 * R + Vector3(0, yl + 0.9, 0), d64 * R + Vector3(0, yl - 0.4, 0))
	# the shaft wall, open at the door (from the floor to the street)
	var segs := 48
	var door_a := asin(DOOR_HALF / R)
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var am := (a0 + a1) * 0.5
		var ybot := DOOR_TOP if absf(wrapf(am - PI * 0.5, -PI, PI)) < door_a else -D - 0.5
		# under the landing the wall stops at its underside (the landing runs out onto the plaza)
		var ytop := yl - 0.4 if (am > LAND_A0 and am < LAND_A1) else y0 + 0.2
		_quad(faces, _dir(a0) * R + Vector3(0, ybot, 0), _dir(a0) * R + Vector3(0, ytop, 0), _dir(a1) * R + Vector3(0, ytop, 0), _dir(a1) * R + Vector3(0, ybot, 0))
	# the floor
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		faces.append_array([Vector3(0, -D, 0), _dir(a0) * (R + 0.2) + Vector3(0, -D, 0), _dir(a1) * (R + 0.2) + Vector3(0, -D, 0)])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# the balustrade ring (the old solid ring over the well is gone): wedges, open under the arch
	var bsegs := 32
	for s in bsegs:
		var a0 := TAU * s / bsegs
		var a1 := TAU * (s + 1) / bsegs
		var am := (a0 + a1) * 0.5
		if am > LAND_A0 + 0.02 and am < LAND_A1 - 0.02:
			continue
		_wedge(body, a0, a1, R, 3.45, y0 - 0.1, y0 + 1.1)
	_street_cover(root, y0)


static func _quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append_array([a, b, c, a, c, d])


## A convex ring segment between radii r0..r1, angles a0..a1, heights y_lo..y_hi.
static func _wedge(body: StaticBody3D, a0: float, a1: float, r0: float, r1: float, y_lo: float, y_hi: float) -> void:
	var pts := PackedVector3Array()
	for r in [r0, r1]:
		for a in [a0, a1]:
			for y in [y_lo, y_hi]:
				pts.append(_dir(a) * r + Vector3(0, y, 0))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## The street over the hollow: flat slabs (top at y0's ground, 0) everywhere in the hollow's
## footprint (grown one terrain cell), except the well.
static func _street_cover(root: Node3D, _y0: float) -> void:
	var body := StaticBody3D.new()
	body.name = "UndercroftStreetCover"
	root.add_child(body)
	var g := HOLLOW.grow(2.0)
	var x0 := g.position.x
	var z0 := g.position.y
	var x1 := g.end.x
	var z1 := g.end.y
	var h := 3.05
	for r in [[x0, z0, -h, z1], [h, z0, x1, z1], [-h, z0, h, -h], [-h, h, h, z1]]:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(r[2] - r[0], COVER_T, r[3] - r[1])
		cs.shape = b
		cs.position = Vector3((r[0] + r[2]) * 0.5, -COVER_T * 0.5, (r[1] + r[3]) * 0.5)
		body.add_child(cs)
	# between the well's circle and the square hole: a ring of wedges
	var segs := 32
	for s in segs:
		_wedge(body, TAU * s / segs, TAU * (s + 1) / segs, PIT_R, 4.4, -COVER_T, 0.0)


## Hollow out the terrain's collision under the plaza (its HeightMapShape3D map data only).
## `city` is city.gd after build(): the terrain body is its child "Terrain".
static func hollow_terrain(city: Node) -> bool:
	var body := city.find_child("Terrain", true, false)
	if body == null:
		return false
	for cs in body.get_children():
		if not cs is CollisionShape3D or not (cs as CollisionShape3D).shape is HeightMapShape3D:
			continue
		var shape := (cs as CollisionShape3D).shape as HeightMapShape3D
		var Terrain = load("res://scripts/map/terrain.gd")
		var step: float = Terrain.STEP
		var origin: float = Terrain.ORIGIN
		var w := shape.map_width
		var data := shape.map_data
		var i0 := ceili((HOLLOW.position.x - origin) / step)
		var i1 := floori((HOLLOW.end.x - origin) / step)
		var j0 := ceili((HOLLOW.position.y - origin) / step)
		var j1 := floori((HOLLOW.end.y - origin) / step)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				data[j * w + i] = HOLLOW_Y / step
		shape.map_data = data
		built = true
		return true
	return false
