extends RefCounted
## Port Vesper's ground: one heightmap over the whole map, built from layered noise plus the
## hand-placed features in map_layout.gd.
##
##   - The paved city (the Old Quarter, the Velvet Mile, the cemetery, the docks quay) sits on
##     level plates at y = 0 (Layout.PLATES), so the street grid, sidewalks and props stay put;
##     the terrain blends into them over Layout.PLATE_BLEND metres.
##   - Hollow Pines rolls in low hills with a ridge along the north edge, a hill for the water
##     tower, the Hollow (a bowl round the boss arena) and a pine-ringed lake you can wade into.
##   - The Bayou lies below the city's levee: a mud bed under shallow black water, islands and
##     boardwalk causeways just above it, a deep lagoon past the east edge.
##   - The river runs round the west and south below the quay walls, with a far bank beyond.
##
## height_at(x, z) samples exactly the triangles the collision shape and the meshes use, so
## everything placed with it sits on the ground. Everything is static and built once.

const Layout = preload("res://scripts/map/map_layout.gd")

const STEP := 2.0 # metres between height samples
const ORIGIN := -256.0 # the grid covers ORIGIN .. -ORIGIN on x and z
const N := 257 # samples per side
const CHUNK_CELLS := 32 # 64 m render chunks
const LOD1_EVERY := 4 # the far LOD keeps every 4th sample (8 m)
const LOD_RANGE := 120.0 # LOD0 up to here, LOD1 beyond
const TOWER := Vector3(25, 0, -190)

static var H := PackedFloat32Array() # heights, row-major (z * N + x)
static var C := PackedColorArray() # splat hints per sample: r path, g wet, b mud, a forest litter
static var _n1: FastNoiseLite
static var _n2: FastNoiseLite
static var _n3: FastNoiseLite
static var _clear_t := PackedFloat32Array() # each clearing's levelled height
static var _anchor_t := PackedFloat32Array() # deployment points, then arenas: their levelled height
static var _built := false
static var terrain_mat: ShaderMaterial
static var water_mat: ShaderMaterial
static var river_mat: ShaderMaterial


# ================================================================ height function
static func _ss(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _noise() -> void:
	if _n1 != null:
		return
	_n1 = FastNoiseLite.new()
	_n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n1.seed = 1859
	_n1.frequency = 1.0 / 170.0
	_n1.fractal_octaves = 3
	_n2 = FastNoiseLite.new()
	_n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n2.seed = 77
	_n2.frequency = 1.0 / 26.0
	_n2.fractal_octaves = 2
	_n3 = FastNoiseLite.new()
	_n3.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n3.seed = 311
	_n3.frequency = 1.0 / 9.0
	_n3.fractal_octaves = 1


## Distance on the ground to the nearest paved plate (0 inside one).
static func _plate_dist(x: float, z: float) -> float:
	var best := INF
	for r: Rect2 in Layout.PLATES:
		var dx := maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


static func _bayou_mask(x: float, z: float) -> float:
	return _ss(88.0, 140.0, x) * _ss(-58.0, -96.0, z)


static func _lake_r(x: float, z: float) -> float:
	var lp: Vector3 = Layout.LAKE.pos
	var a := atan2(z - lp.z, x - lp.x)
	return float(Layout.LAKE.radius) * (1.0 + 0.11 * sin(3.0 * a + 0.7) + 0.06 * sin(5.0 * a + 2.1))


## Rolling ground before any hand-placed feature (smooth: no fine detail).
static func _natural(x: float, z: float) -> float:
	var b := _bayou_mask(x, z)
	# Hollow Pines climbs northwards out of the city into real hills (rolling, 8-25 m) ...
	var hills := 4.0 + _ss(-80.0, -205.0, z) * 13.0 + _n1.get_noise_2d(x, z) * 8.5
	hills += maxf(0.0, _n1.get_noise_2d(x * 0.6 + 300.0, z * 0.6)) * 6.0 # a few higher knolls
	# ... and a forested ridge closes the map in the north (it reads over the roofs from the streets)
	hills += _ss(-224.0, -268.0, z) * (34.0 + 12.0 * _n1.get_noise_2d(x * 2.0, 40.0)) + _ss(-268.0, -420.0, z) * 25.0
	var bayou := -0.95 - _ss(214.0, 238.0, x) * 2.6 + _ss(300.0, 330.0, x) * 7.0
	var h := lerpf(hills, bayou, b)
	var urban := _ss(234.0, 246.0, x) * _ss(-70.0, -52.0, z)
	h = lerpf(h, _ss(335.0, 420.0, x) * (24.0 + 14.0 * _n1.get_noise_2d(x, z)), urban)
	# the water tower's hill
	var dt := Vector2(x - TOWER.x, z - TOWER.z).length()
	h += 9.0 * exp(-(dt * dt) / (30.0 * 30.0)) * (1.0 - b)
	# a gentle basin round the lake, so its rim is never lower than the water
	var lp: Vector3 = Layout.LAKE.pos
	var dl := Vector2(x - lp.x, z - lp.z).length()
	h = lerpf(h, float(Layout.LAKE.level) + 2.0, 1.0 - _ss(Layout.LAKE.radius + 14.0, Layout.LAKE.radius + 46.0, dl))
	return h


## The wilds with every feature applied (before the city plates). Also fills the splat hints.
static func _wild(x: float, z: float, hint: Array) -> float:
	var h := _natural(x, z) + _n2.get_noise_2d(x, z) * 0.7
	var b := _bayou_mask(x, z)
	var path := 0.0
	var mud := b * 0.85
	var wet := 0.0
	# clearings: levelled, trampled to mud and dirt in the middle
	var cl: Array = Layout.PINE_CLEARINGS
	for k in cl.size():
		var c: Vector3 = cl[k][0]
		var r: float = cl[k][1]
		var d := Vector2(x - c.x, z - c.z).length()
		if d < r + 36.0:
			var f := 1.0 - _ss(r * 0.85, r + 36.0, d)
			h = lerpf(h, _clear_t[k], f)
			var trod := 1.0 - _ss(r * 0.35, r * 0.95, d)
			path = maxf(path, trod * 0.55)
			mud = maxf(mud, trod * 0.35)
	# roads: level across, following the hills along their length
	for road: Array in Layout.PINE_ROADS:
		var q := _nearest_on(Vector2(x, z), road)
		var d: float = q.z
		if d < 10.0:
			var hc := _road_centre(q.x, q.y)
			h = lerpf(h, hc, 1.0 - _ss(4.0, 10.0, d))
			path = maxf(path, 1.0 - _ss(2.6, 4.6, d))
	# the bayou: islands and boardwalk causeways just above the water
	if b > 0.01:
		var top := 0.0
		for isl: Array in Layout.BAYOU_ISLANDS:
			var c: Vector3 = isl[0]
			var r: float = isl[1]
			var d := Vector2(x - c.x, z - c.z).length()
			if d < r + 8.0:
				var ip := -(maxf(d - r * 0.8, 0.0)) / (r * 0.2 + 5.0) * 1.1
				h = maxf(h, ip)
				top = maxf(top, 1.0 - _ss(r * 0.5, r * 0.95, d))
		mud *= 1.0 - 0.65 * top
		for bw: Array in Layout.BOARDWALKS:
			var q := _nearest_on(Vector2(x, z), bw)
			if q.z < 5.0:
				h = maxf(h, -maxf(q.z - 1.4, 0.0) / 2.6)
		wet = maxf(wet, (1.0 - _ss(0.05, 0.6, h - Layout.BAYOU_WATER)) * b)
	# deployment points and boss arenas in the wilds are level with the streets (y = 0)
	h = _level_anchors(x, z, h)
	# the lake: a gently sloping shore, a wading shelf, then the deep middle
	var lp: Vector3 = Layout.LAKE.pos
	var lv: float = Layout.LAKE.level
	var dl := Vector2(x - lp.x, z - lp.z).length()
	if dl < Layout.LAKE.radius * 1.3 + 30.0:
		var rr := _lake_r(x, z)
		var s := dl / rr
		var shore: float
		if s >= 1.0:
			shore = lv + (dl - rr) * 0.2
		elif s >= 0.72:
			shore = lv - (1.0 - s) / 0.28 * 0.85
		else:
			shore = lv - 0.85 - (0.72 - s) / 0.72 * 4.5
		var t := 1.0 - _ss(rr + 6.0, rr + 24.0, dl)
		h = lerpf(h, shore, t)
		if dl < rr + 6.0:
			h = shore
		h = maxf(h, lv + 0.3) if dl >= rr + 1.5 and dl < rr + 24.0 else h
		wet = maxf(wet, 1.0 - _ss(0.3, 1.8, h - lv))
		mud = maxf(mud, (1.0 - _ss(0.5, 2.6, h - lv)) * 0.95)
	hint[0] = path
	hint[1] = wet
	hint[2] = mud
	return h


## Deployment points and boss arenas sit on level ground at their own height (never below
## the streets / the swamp surface), so the Descent and the boss fights land on flat earth.
static func _level_anchors(x: float, z: float, h: float) -> float:
	var nd: int = Layout.DEPLOY_POINTS.size()
	for k in nd:
		var p: Vector3 = Layout.DEPLOY_POINTS[k].pos
		var dd := Vector2(x - p.x, z - p.z).length()
		if dd < 40.0:
			h = lerpf(h, _anchor_t[k], 1.0 - _ss(11.0, 40.0, dd))
	for k in Layout.ARENAS.size():
		var a: Dictionary = Layout.ARENAS[k]
		var da := Vector2(x - a.pos.x, z - a.pos.z).length()
		if da < a.radius + 50.0:
			h = lerpf(h, _anchor_t[nd + k], 1.0 - _ss(a.radius + 2.0, a.radius + 50.0, da))
	return h


## The level ground height for a deployment point or arena at p (0 on the city plates).
static func ground_target(p: Vector3) -> float:
	_noise()
	if _plate_dist(p.x, p.z) <= 0.0:
		return 0.0
	return maxf(_natural(p.x, p.z), 0.0)


## A copy of a deployment point / arena dictionary with pos.y on the ground.
static func grounded(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	out.pos = Vector3(d.pos.x, height_at(d.pos.x, d.pos.z), d.pos.z)
	return out


## A road's height at a centreline point: the smooth ground, levelled through the clearings.
static func _road_centre(x: float, z: float) -> float:
	var h := _natural(x, z)
	var cl: Array = Layout.PINE_CLEARINGS
	for k in cl.size():
		var c: Vector3 = cl[k][0]
		var r: float = cl[k][1]
		var d := Vector2(x - c.x, z - c.z).length()
		if d < r + 36.0:
			h = lerpf(h, _clear_t[k], 1.0 - _ss(r * 0.85, r + 36.0, d))
	h = _level_anchors(x, z, h)
	return h


## Nearest point on a polyline: (x, z, distance).
static func _nearest_on(q: Vector2, pts: Array) -> Vector3:
	var best := Vector3(0, 0, INF)
	for k in pts.size() - 1:
		var a := Vector2(pts[k].x, pts[k].z)
		var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var p := a + ab * t
		var d := q.distance_to(p)
		if d < best.z:
			best = Vector3(p.x, p.y, d)
	return best


## The full height function (the grid samples it; the far ring uses it directly).
static func _height(x: float, z: float, hint: Array) -> float:
	hint[0] = 0.0; hint[1] = 0.0; hint[2] = 0.0
	# the river round the west and south, then its far bank (where the backdrop stands)
	if x < Layout.QUAY_X - 0.5 or z > Layout.RIVER_Z + 0.5:
		var bank := maxf(_ss(-282.0, -294.0, x), _ss(268.0, 280.0, z))
		var land := 0.25 + _ss(40.0, 170.0, maxf(-290.0 - x, z - 276.0)) * (34.0 + 18.0 * _n1.get_noise_2d(x, z))
		hint[1] = 1.0 - _ss(0.0, 1.5, bank * 2.0)
		hint[2] = hint[1]
		return lerpf(-6.0, land, bank)
	var pd := _plate_dist(x, z)
	if pd <= 0.0:
		return 0.0
	var w := 1.0 - _ss(0.0, Layout.PLATE_BLEND, pd)
	var h := _wild(x, z, hint) * (1.0 - w)
	# the levee between the city and the bayou
	h += 1.1 * exp(-pow((pd - 7.0) / 5.0, 2.0)) * _ss(112.0, 132.0, x)
	for k in 3:
		hint[k] = hint[k] * (1.0 - w)
	return h


# ================================================================ the grid
static func build() -> void:
	if _built:
		return
	_built = true
	_noise()
	_clear_t.resize(Layout.PINE_CLEARINGS.size())
	for k in Layout.PINE_CLEARINGS.size():
		var c: Vector3 = Layout.PINE_CLEARINGS[k][0]
		var kind: String = Layout.PINE_CLEARINGS[k][2]
		_clear_t[k] = maxf(_natural(c.x, c.z), 0.0) if kind in ["arena", "trail"] else _natural(c.x, c.z)
	_anchor_t.clear()
	for d: Dictionary in Layout.DEPLOY_POINTS:
		_anchor_t.append(ground_target(d.pos))
	for a: Dictionary in Layout.ARENAS:
		_anchor_t.append(ground_target(a.pos))
	H.resize(N * N)
	C.resize(N * N)
	var hint := [0.0, 0.0, 0.0]
	for j in N:
		var z := ORIGIN + j * STEP
		for i in N:
			var x := ORIGIN + i * STEP
			var h := _height(x, z, hint)
			H[j * N + i] = h
			C[j * N + i] = Color(hint[0], hint[1], hint[2], 0.5 + 0.5 * _n2.get_noise_2d(x * 2.3, z * 2.3))


## Ground height at (x, z), on the same triangles as the collision shape and the meshes.
static func height_at(x: float, z: float) -> float:
	if not _built:
		build()
	var gx := (x - ORIGIN) / STEP
	var gz := (z - ORIGIN) / STEP
	if gx < 0.0 or gz < 0.0 or gx >= N - 1 or gz >= N - 1:
		var hint := [0.0, 0.0, 0.0]
		return _height(x, z, hint)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var h00 := H[j * N + i]
	var h10 := H[j * N + i + 1]
	var h01 := H[(j + 1) * N + i]
	var h11 := H[(j + 1) * N + i + 1]
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


## Ground normal at (x, z).
static func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


## Splat hints at (x, z) (nearest sample): r path, g wet, b mud.
static func hint_at(x: float, z: float) -> Color:
	var i := clampi(roundi((x - ORIGIN) / STEP), 0, N - 1)
	var j := clampi(roundi((z - ORIGIN) / STEP), 0, N - 1)
	return C[j * N + i]


static func in_plate(x: float, z: float) -> bool:
	for r: Rect2 in Layout.PLATES:
		if r.has_point(Vector2(x, z)):
			return true
	return false


static func _hs(i: int, j: int) -> float:
	return H[clampi(j, 0, N - 1) * N + clampi(i, 0, N - 1)]


static func _grid_normal(i: int, j: int, s: int) -> Vector3:
	return Vector3(_hs(i - s, j) - _hs(i + s, j), 2.0 * STEP * s, _hs(i, j - s) - _hs(i, j + s)).normalized()


# ================================================================ nodes
## Collision (layer 1, so the navmesh bakes the slopes), chunked render meshes with two LODs,
## the far ring, the water and the lake's deep-water fence. Called by city.gd.
static func build_nodes(parent: Node3D) -> void:
	build()
	_materials()
	# collision: one HeightMapShape3D, scaled 2x (uniformly) so a sample lands every 2 m
	var body := StaticBody3D.new()
	body.name = "Terrain"
	parent.add_child(body)
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	var half := PackedFloat32Array()
	half.resize(N * N)
	for k in N * N:
		half[k] = H[k] / STEP
	shape.map_data = half
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(STEP, STEP, STEP)
	body.add_child(cs)
	# render chunks
	var chunks := (N - 1) / CHUNK_CELLS
	for cj in chunks:
		for ci in chunks:
			_chunk(parent, ci, cj)
	_far_ring(parent)
	_lake_fence(body)
	_water(parent)


static func _chunk(parent: Node3D, ci: int, cj: int) -> void:
	var i0 := ci * CHUNK_CELLS
	var j0 := cj * CHUNK_CELLS
	var origin := Vector3(ORIGIN + (i0 + CHUNK_CELLS * 0.5) * STEP, 0.0, ORIGIN + (j0 + CHUNK_CELLS * 0.5) * STEP)
	var lods: Array = []
	var lo := INF
	var hi := -INF
	for s in [1, LOD1_EVERY]:
		var mesh := _grid_mesh(i0, j0, CHUNK_CELLS, s, origin)
		if mesh == null:
			return
		lods.append(mesh)
		var bb := mesh.get_aabb()
		lo = minf(lo, bb.position.y)
		hi = maxf(hi, bb.end.y)
	var half := CHUNK_CELLS * STEP * 0.5
	var aabb := AABB(Vector3(-half, lo, -half), Vector3(2.0 * half, hi - lo + 0.01, 2.0 * half))
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.name = "TerrainChunk_%d_%d_L%d" % [ci, cj, k]
		mi.mesh = lods[k]
		lods[k].custom_aabb = aabb
		mi.position = origin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if k == 0:
			mi.visibility_range_end = LOD_RANGE
		else:
			mi.visibility_range_begin = LOD_RANGE
		parent.add_child(mi)


## A grid patch of n cells (stride s samples), skipping cells on the paved plates and under the
## river; with skirts round the edge so LOD seams never show sky. Null when nothing is left.
static func _grid_mesh(i0: int, j0: int, n: int, s: int, origin: Vector3) -> ArrayMesh:
	var cells := n / s
	var vw := cells + 1
	var keep := PackedByteArray()
	keep.resize(cells * cells)
	var any := false
	for cj in cells:
		for ci in cells:
			var ia := i0 + ci * s
			var ja := j0 + cj * s
			var cx := ORIGIN + (ia + s * 0.5) * STEP
			var cz := ORIGIN + (ja + s * 0.5) * STEP
			var k := 1
			if in_plate(cx, cz):
				k = 0
			elif maxf(maxf(_hs(ia, ja), _hs(ia + s, ja)), maxf(_hs(ia, ja + s), _hs(ia + s, ja + s))) < Layout.RIVER_WATER - 0.6 \
					and (cx < Layout.QUAY_X or cz > Layout.RIVER_Z):
				k = 0
			keep[cj * cells + ci] = k
			if k == 1:
				any = true
	if not any:
		return null
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var tg := PackedFloat32Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for vj in vw:
		for vi in vw:
			var i := i0 + vi * s
			var j := j0 + vj * s
			_vert(v, nr, tg, uv, col, i, j, s, origin, 0.0)
	for cj in cells:
		for ci in cells:
			if keep[cj * cells + ci] == 0:
				continue
			var a := cj * vw + ci
			var b := a + 1
			var c := a + vw
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# skirts: hang a strip down from every kept edge cell's outer border
	var drop := 2.5 if s == 1 else 4.0
	for e in 4:
		for t in cells:
			var ci: int = [t, t, 0, cells - 1][e]
			var cj: int = [0, cells - 1, t, t][e]
			if keep[cj * cells + ci] == 0:
				continue
			var p0: Vector2i
			var p1: Vector2i
			match e:
				0: p0 = Vector2i(ci, 0); p1 = Vector2i(ci + 1, 0)
				1: p0 = Vector2i(ci + 1, cells); p1 = Vector2i(ci, cells)
				2: p0 = Vector2i(0, cj + 1); p1 = Vector2i(0, cj)
				_: p0 = Vector2i(cells, cj); p1 = Vector2i(cells, cj + 1)
			var top0 := p0.y * vw + p0.x
			var top1 := p1.y * vw + p1.x
			var base := v.size()
			_vert(v, nr, tg, uv, col, i0 + p0.x * s, j0 + p0.y * s, s, origin, drop)
			_vert(v, nr, tg, uv, col, i0 + p1.x * s, j0 + p1.y * s, s, origin, drop)
			idx.append_array([top0, top1, base, top1, base + 1, base])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TANGENT] = tg
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, terrain_mat)
	return mesh


static func _vert(v: PackedVector3Array, nr: PackedVector3Array, tg: PackedFloat32Array, uv: PackedVector2Array, col: PackedColorArray, i: int, j: int, s: int, origin: Vector3, drop: float) -> void:
	var x := ORIGIN + i * STEP
	var z := ORIGIN + j * STEP
	v.append(Vector3(x, _hs(i, j) - drop, z) - origin)
	var n := _grid_normal(i, j, s)
	nr.append(n)
	var t := Vector3(n.y, -n.x, 0.0).normalized() # +x along the surface
	tg.append_array([t.x, t.y, t.z, 1.0])
	uv.append(Vector2(x, z))
	col.append(C[clampi(j, 0, N - 1) * N + clampi(i, 0, N - 1)])


## Low-detail hills, river bed and far banks past the grid, out to the horizon (one mesh).
static func _far_ring(parent: Node3D) -> void:
	var step := 16.0
	var ext := 768.0
	var cells := int(ext * 2.0 / step)
	var vw := cells + 1
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var tg := PackedFloat32Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var hint := [0.0, 0.0, 0.0]
	var hs := PackedFloat32Array()
	hs.resize(vw * vw)
	for j in vw:
		for i in vw:
			var x := -ext + i * step
			var z := -ext + j * step
			hs[j * vw + i] = height_at(x, z)
	for j in vw:
		for i in vw:
			var x := -ext + i * step
			var z := -ext + j * step
			var h := hs[j * vw + i]
			var n := Vector3(hs[j * vw + maxi(i - 1, 0)] - hs[j * vw + mini(i + 1, cells)], 2.0 * step,
				hs[maxi(j - 1, 0) * vw + i] - hs[mini(j + 1, cells) * vw + i]).normalized()
			v.append(Vector3(x, h, z))
			nr.append(n)
			var t := Vector3(n.y, -n.x, 0.0).normalized()
			tg.append_array([t.x, t.y, t.z, 1.0])
			uv.append(Vector2(x, z))
			_height(x, z, hint)
			col.append(Color(hint[0], hint[1], hint[2], 0.5))
	var idx := PackedInt32Array()
	var lim := -ORIGIN
	for cj in cells:
		for ci in cells:
			var x0 := -ext + ci * step
			var z0 := -ext + cj * step
			if x0 >= -lim and x0 + step <= lim and z0 >= -lim and z0 + step <= lim:
				continue # the detailed grid covers this
			var cx := x0 + step * 0.5
			var cz := z0 + step * 0.5
			var a := cj * vw + ci
			if maxf(maxf(hs[a], hs[a + 1]), maxf(hs[a + vw], hs[a + vw + 1])) < Layout.RIVER_WATER - 0.6 and (cx < Layout.QUAY_X or cz > Layout.RIVER_Z):
				continue
			if in_plate(cx, cz):
				continue
			idx.append_array([a, a + 1, a + vw, a + 1, a + vw + 1, a + vw])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TANGENT] = tg
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, terrain_mat)
	var mi := MeshInstance3D.new()
	mi.name = "TerrainFar"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## An invisible fence round the lake's deep middle: wade the shelf, never drown.
static func _lake_fence(body: StaticBody3D) -> void:
	var lp: Vector3 = Layout.LAKE.pos
	var lv: float = Layout.LAKE.level
	var segs := 28
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var p0 := lp + Vector3(cos(a0), 0, sin(a0)) * _lake_r(lp.x + cos(a0) * 10.0, lp.z + sin(a0) * 10.0) * 0.74
		var p1 := lp + Vector3(cos(a1), 0, sin(a1)) * _lake_r(lp.x + cos(a1) * 10.0, lp.z + sin(a1) * 10.0) * 0.74
		var mid := (p0 + p1) * 0.5
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(p0.distance_to(p1) + 0.6, 6.0, 0.4)
		cs.shape = sh
		var dir := (p1 - p0).normalized()
		cs.transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), Vector3(mid.x, lv - 2.0, mid.z))
		body.add_child(cs)


# ================================================================ water
## The lake (a polar grid that follows the shore) and the bayou (a grid over the low ground).
## Vertex alpha carries the depth (0 at the shore .. 1 deep): no depth texture on the web.
static func _water(parent: Node3D) -> void:
	# the lake
	var lp: Vector3 = Layout.LAKE.pos
	var lv: float = Layout.LAKE.level
	var rings := [0.0, 0.25, 0.5, 0.7, 0.82, 0.92, 1.0, 1.08, 1.18]
	var segs := 56
	var v := PackedVector3Array()
	var col := PackedColorArray()
	for ring in rings.size():
		for k in segs:
			var a := TAU * k / segs
			var dir := Vector3(cos(a), 0, sin(a))
			var rr := _lake_r(lp.x + dir.x * 10.0, lp.z + dir.z * 10.0)
			var p: Vector3 = lp + dir * rr * float(rings[ring])
			v.append(Vector3(p.x, lv, p.z))
			col.append(Color(1, 1, 1, clampf((lv - height_at(p.x, p.z)) / 2.2, 0.0, 1.0)))
	var idx := PackedInt32Array()
	for ring in rings.size() - 1:
		for k in segs:
			var a := ring * segs + k
			var b := ring * segs + (k + 1) % segs
			var c := a + segs
			var d := b + segs
			idx.append_array([a, c, b, b, c, d])
	parent.add_child(_water_mi("Lake", v, col, idx, water_mat))
	# the bayou: 4 m cells wherever the ground dips below the swamp's surface
	var wy: float = Layout.BAYOU_WATER
	var step := 4.0
	var x0 := 108.0
	var z0 := -320.0
	var cw := int((340.0 - x0) / step)
	var chh := int((-64.0 - z0) / step)
	v = PackedVector3Array()
	col = PackedColorArray()
	idx = PackedInt32Array()
	var vw := cw + 1
	var hs := PackedFloat32Array()
	hs.resize(vw * (chh + 1))
	for j in chh + 1:
		for i in vw:
			var x := x0 + i * step
			var z := z0 + j * step
			var h := height_at(x, z)
			hs[j * vw + i] = h
			v.append(Vector3(x, wy, z))
			col.append(Color(1, 1, 1, clampf((wy - h) / 1.6, 0.0, 1.0)))
	for j in chh:
		for i in cw:
			var a := j * vw + i
			if minf(minf(hs[a], hs[a + 1]), minf(hs[a + vw], hs[a + vw + 1])) > wy + 0.05:
				continue
			idx.append_array([a, a + 1, a + vw, a + 1, a + vw + 1, a + vw])
	parent.add_child(_water_mi("BayouWater", v, col, idx, water_mat))


static func _water_mi(name: String, v: PackedVector3Array, col: PackedColorArray, idx: PackedInt32Array, mat: Material) -> MeshInstance3D:
	var nr := PackedVector3Array()
	var tg := PackedFloat32Array()
	var uv := PackedVector2Array()
	for p in v:
		nr.append(Vector3.UP)
		tg.append_array([1.0, 0.0, 0.0, 1.0])
		uv.append(Vector2(p.x, p.z))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TANGENT] = tg
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ================================================================ materials
const TERRAIN_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D forest_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.8, 0.8, 0.7);
uniform float wetness = 0.5;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float lum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

// height-aware blend: the layer with the taller texel wins near the transition
float hb(float w, float h, float sharp) {
	return clamp((w - 0.5) * sharp + (h - 0.5) * 1.6 + 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 p = wp.xz;
	float n1 = texture(mask_noise, p * 0.011).r;
	float n2 = texture(mask_noise, p * 0.057 + vec2(0.31, 0.17)).r;
	// two scales of the forest floor, broken up by the noise mask (no visible tiling)
	vec2 rp = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	vec3 fa = mix(texture(forest_alb, p * 0.21).rgb, texture(forest_alb, rp * 0.083 + 0.37).rgb, smoothstep(0.3, 0.7, n1));
	vec3 fn = mix(texture(forest_nrm, p * 0.21).rgb, texture(forest_nrm, rp * 0.083 + 0.37).rgb, smoothstep(0.3, 0.7, n1));
	// leaf litter / moss variation from the vertex hint and the mask
	fa *= mix(vec3(0.82, 0.78, 0.7), vec3(1.0, 1.04, 0.92), COLOR.a * 0.6 + n2 * 0.4);
	vec3 ma = texture(mud_alb, p * 0.24).rgb;
	vec3 mn = texture(mud_nrm, p * 0.24).rgb;
	vec3 da = texture(dirt_alb, rp * 0.2).rgb;
	vec3 dn = texture(dirt_nrm, rp * 0.2).rgb;
	// rock: triplanar on steep faces (x and z projections), top projection on the flats
	vec3 bw = pow(abs(wn), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 ra = texture(rock_alb, wp.zy * 0.13).rgb * bw.x + texture(rock_alb, wp.xy * 0.13).rgb * bw.z + texture(rock_alb, p * 0.13).rgb * bw.y;
	vec3 rn = texture(rock_nrm, wp.zy * 0.13).rgb * bw.x + texture(rock_nrm, wp.xy * 0.13).rgb * bw.z + texture(rock_nrm, p * 0.13).rgb * bw.y;
	float slope = 1.0 - wn.y;
	float w_rock = hb(smoothstep(0.17, 0.32, slope + (n2 - 0.5) * 0.1), lum(ra), 3.0);
	float w_mud = hb(clamp(COLOR.b + (n1 - 0.5) * 0.5, 0.0, 1.0), lum(ma) * 1.4, 2.5);
	float w_path = hb(clamp(COLOR.r + (n2 - 0.5) * 0.35, 0.0, 1.0), lum(da) * 1.3, 3.0);
	vec3 alb = fa;
	vec3 nm = fn;
	alb = mix(alb, ma, w_mud); nm = mix(nm, mn, w_mud);
	alb = mix(alb, da * vec3(0.85, 0.8, 0.75), w_path); nm = mix(nm, dn, w_path);
	alb = mix(alb, ra * vec3(0.8, 0.82, 0.85), w_rock); nm = mix(nm, rn, w_rock);
	// soaked ground: darker and glossy; standing wet at the shores
	float wet = clamp(max(COLOR.g, wetness * (0.35 + 0.4 * n2) * (1.0 - w_rock * 0.5)), 0.0, 1.0);
	alb *= tint * mix(1.0, 0.55, wet);
	ALBEDO = alb;
	ROUGHNESS = mix(0.92, 0.32, wet) - w_rock * 0.1;
	SPECULAR = mix(0.35, 0.55, wet);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = mix(1.0, 0.45, COLOR.g);
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D wave_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_col : source_color = vec3(0.006, 0.012, 0.012);
uniform vec3 shallow_col : source_color = vec3(0.06, 0.055, 0.04);
uniform vec3 sky_col : source_color = vec3(0.1, 0.11, 0.12);
uniform float shallow_alpha = 0.35;
uniform float deep_alpha = 0.94;
uniform float flow = 1.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	vec3 a = texture(wave_nrm, p * 0.045 + TIME * vec2(0.011, 0.006) * flow).rgb;
	vec3 b = texture(wave_nrm, p * 0.13 + TIME * vec2(-0.009, 0.014) * flow).rgb;
	vec3 nm = normalize((a + b) - 1.0) * 0.5 + 0.5;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 0.55;
	float depth = COLOR.a;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 5.0);
	vec3 col = mix(shallow_col, deep_col, smoothstep(0.0, 0.8, depth));
	// a thin pale line where the water meets the shore
	float edge = 1.0 - smoothstep(0.0, 0.07, depth);
	col += vec3(0.08, 0.08, 0.075) * edge * (0.5 + 0.5 * a.r);
	ALBEDO = mix(col, sky_col, fres * 0.35);
	ALPHA = clamp(mix(shallow_alpha, deep_alpha, smoothstep(0.0, 0.6, depth)) + fres * 0.35, 0.0, 1.0) * smoothstep(-0.02, 0.05, depth + 0.04);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.4;
}
"""

## Splat layers drawn from the photographic material library (asset round 3) instead of the
## older 512 px terrain set (kept as sources in assets/textures/terrain_src, not shipped); a layer
## not listed here reads assets/textures/terrain.
const LIBRARY_LAYERS := {"forest": "forest_floor", "mud": "mud", "rock": "cliff_rock"}


static func _tex(name: String) -> Texture2D:
	var path := "res://assets/textures/terrain/%s.jpg" % name
	if not ResourceLoader.exists(path):
		path = "res://assets/textures/terrain/%s.png" % name
	return load(path) as Texture2D


static func _materials() -> void:
	if terrain_mat != null:
		return
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = sh
	for layer in ["forest", "mud", "dirt", "rock"]:
		var lib: String = LIBRARY_LAYERS.get(layer, "")
		var la := "res://assets/textures/library/%s_albedo.jpg" % lib
		if lib != "" and ResourceLoader.exists(la):
			terrain_mat.set_shader_parameter(layer + "_alb", load(la))
			terrain_mat.set_shader_parameter(layer + "_nrm", load("res://assets/textures/library/%s_normal.jpg" % lib))
		else:
			terrain_mat.set_shader_parameter(layer + "_alb", _tex(layer + "_albedo"))
			terrain_mat.set_shader_parameter(layer + "_nrm", _tex(layer + "_normal"))
	var mn := FastNoiseLite.new()
	mn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mn.frequency = 0.02
	mn.fractal_octaves = 3
	mn.seed = 21
	var mt := NoiseTexture2D.new()
	mt.width = 256
	mt.height = 256
	mt.seamless = true
	mt.normalize = true
	mt.noise = mn
	terrain_mat.set_shader_parameter("mask_noise", mt)
	var wsh := Shader.new()
	wsh.code = WATER_SHADER
	var wn := FastNoiseLite.new()
	wn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wn.frequency = 0.03
	wn.fractal_octaves = 3
	wn.seed = 5
	var wt := NoiseTexture2D.new()
	wt.width = 256
	wt.height = 256
	wt.seamless = true
	wt.as_normal_map = true
	wt.bump_strength = 4.0
	wt.noise = wn
	water_mat = ShaderMaterial.new()
	water_mat.shader = wsh
	water_mat.set_shader_parameter("wave_nrm", wt)
	water_mat.render_priority = 1
	river_mat = ShaderMaterial.new()
	river_mat.shader = wsh
	river_mat.set_shader_parameter("wave_nrm", wt)
	river_mat.set_shader_parameter("flow", 2.5)
	river_mat.set_shader_parameter("deep_alpha", 1.0)
	river_mat.set_shader_parameter("shallow_alpha", 1.0)


## Ground-hugging flat decal geometry (light pools, mud discs) as a small grid over the terrain.
static func conform_quad(bt, center: Vector3, half: float, lift: float, col := Color.WHITE, cells := 4) -> void:
	var k: int = bt.v.size()
	for j in cells + 1:
		for i in cells + 1:
			var x := center.x - half + 2.0 * half * i / cells
			var z := center.z - half + 2.0 * half * j / cells
			bt.v.append(Vector3(x, height_at(x, z) + lift, z))
			bt.n.append(normal_at(x, z))
			bt.c.append(col)
			bt.t.append(Vector2(float(i) / cells, float(j) / cells))
	for j in cells:
		for i in cells:
			var a: int = k + j * (cells + 1) + i
			bt.i.append_array([a, a + 1, a + cells + 1, a + 1, a + cells + 2, a + cells + 1])
