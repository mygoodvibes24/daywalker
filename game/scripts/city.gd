extends Node3D
## Port Vesper: procedural city geometry, materials and props.
##
## Everything static is merged into a handful of ArrayMesh surfaces (one per
## material per city chunk), repeated props are MultiMeshes, and each building
## gets one box collider. Generation is deterministic per SEED.
##
## main.gd reads `window_mat`, `lamp_mat` and `lamps` for the day/night cycle.

const GRID := 20.0
const ROAD_HALF := 3.75 # kerb line, measured from the street centre
const FACADE := 6.0 # building line, measured from the street centre
const LOT := GRID * 0.5 - FACADE # half-size of a block's building lot (4 m)
const WALK_TOP := 0.1 # sidewalks are visual only (no collider), so they stay this low
const Layout = preload("res://scripts/map/map_layout.gd")
const Docks = preload("res://scripts/map/docks.gd")
const Velvet = preload("res://scripts/map/velvet.gd")
const Wilds = preload("res://scripts/map/wilds.gd")
const Cemetery = preload("res://scripts/map/cemetery.gd")
const Terrain = preload("res://scripts/map/terrain.gd")
const SEED := 1859
const ATLAS_COLS := 4.0
const ATLAS_ROWS := 5.0

var window_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D
var lamps: Array[OmniLight3D] = []
## Every street lamp head, for whoever wants to place lights or light pools.
var lamp_positions := PackedVector3Array()

var rng := RandomNumberGenerator.new()
var M := {} # material name -> Material
var CASTS := {} # material names whose meshes cast shadows
var batches := {} # "chunk|material" -> Batch
var ck := "C" # chunk that new geometry goes into
var flicker_mat: StandardMaterial3D
var neon_mat: StandardMaterial3D
var neon_flicker_mat: StandardMaterial3D
var pool_mat: StandardMaterial3D
var far_mat: StandardMaterial3D
var stained_mat: StandardMaterial3D
var shop_mat: StandardMaterial3D
var crypt_mat: StandardMaterial3D
var halo_mat: ShaderMaterial
var uplight_mat: ShaderMaterial
var halo_xfs: Array = [] # lantern halos (one MultiMesh of camera-facing quads)
var halo_mm: MultiMesh
var alleys: Array = [] # [Vector3 centre, Vector3 along] of every back alley, for whoever wants them
## Layout data for other systems (points of interest, spawners...). Read after build().
## blocks: [{"centre": Vector2, "district": String, "lots": Array[Rect2], "heights": Array[float]}]
var blocks: Array = []
## lots: every building footprint (XZ Rect2) in the city, cathedral included.
var lots: Array[Rect2] = []
## The open cathedral plaza (XZ); the Undercroft well sits at its centre (radius PIT_R + balustrade).
const PLAZA_RECT := Rect2(-GRID + ROAD_HALF, -GRID + ROAD_HALF, 2.0 * (GRID - ROAD_HALF), 2.0 * (GRID - ROAD_HALF))
var collider_root: Node3D
var car_bodies: StaticBody3D
var signs_left := 16
## Map data for the Hunt, loot, the navmesh bake and the map screen (see map_layout.gd).
var bounds: Rect2 = Layout.BOUNDS
var play_rect: Rect2 = Layout.PLAY
var districts: Array = Layout.DISTRICTS
var landmarks: Array = Layout.LANDMARKS
var deploy_points: Array = Layout.DEPLOY_POINTS
var arenas: Array = Layout.ARENAS
var final_arena: Dictionary = Layout.FINAL_ARENA
## Open spots for points of interest: [{pos: Vector3, district: String, tag: String}]
var poi_anchors: Array = []
## Loot cache spots: [{pos, yaw, coffin}]
var cache_spots: Array = []
## Points on walkable roads/paths, for roaming spawns.
var road_points := PackedVector3Array()
## Block cells (Vector2i) that got buildings, and every cell whose edges are streets.
var block_cells: Array = []
## Old Quarter rows whose block runs on over the next row (40 m long blocks, no cross street).
const LONG_BLOCK_J := [-3, 1]
## Street segments built over by a long block: Vector3i(line, cell, axis) as in _build_streets.
var filled_segs := {}
## Sub-cell centre -> bitmask of its sides that face into its own long block (1 +z, 2 -z).
var inner_sides := {}
var street_cells := {}
var sign_spots: Array = []
var _t := 0.0

# Prop instances collected while building: name -> Array[Transform3D], colours
var props := {}
var prop_cols := {}


# ================================================================ geometry batches
class Batch:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	## a = bottom-left, b = top-left, d = top-right, e = bottom-right as seen from
	## the front. Winding is picked from the normal, so callers can't get it wrong.
	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, nrm: Vector3, col: Color, uv0 := Vector2.ZERO, uv1 := Vector2.ONE) -> void:
		var k := v.size()
		v.append(a); v.append(b); v.append(d); v.append(e)
		n.append(nrm); n.append(nrm); n.append(nrm); n.append(nrm)
		c.append(col); c.append(col); c.append(col); c.append(col)
		t.append(Vector2(uv0.x, uv1.y)); t.append(uv0); t.append(Vector2(uv1.x, uv0.y)); t.append(uv1)
		_wind(k, (b - a).cross(d - a).dot(nrm) > 0.0)

	func quad_sm(a: Vector3, b: Vector3, d: Vector3, e: Vector3, na: Vector3, nb: Vector3, nd: Vector3, ne: Vector3, col: Color, uv0 := Vector2.ZERO, uv1 := Vector2.ONE) -> void:
		var k := v.size()
		v.append(a); v.append(b); v.append(d); v.append(e)
		n.append(na); n.append(nb); n.append(nd); n.append(ne)
		c.append(col); c.append(col); c.append(col); c.append(col)
		t.append(Vector2(uv0.x, uv1.y)); t.append(uv0); t.append(Vector2(uv1.x, uv0.y)); t.append(uv1)
		_wind(k, (b - a).cross(d - a).dot(na + nb + nd + ne) > 0.0)

	func tri(a: Vector3, b: Vector3, d: Vector3, nrm: Vector3, col: Color, ua := Vector2.ZERO, ub := Vector2.ZERO, ud := Vector2.ZERO) -> void:
		var k := v.size()
		v.append(a); v.append(b); v.append(d)
		n.append(nrm); n.append(nrm); n.append(nrm)
		c.append(col); c.append(col); c.append(col)
		t.append(ua); t.append(ub); t.append(ud)
		if (b - a).cross(d - a).dot(nrm) > 0.0:
			i.append(k); i.append(k + 2); i.append(k + 1)
		else:
			i.append(k); i.append(k + 1); i.append(k + 2)

	func _wind(k: int, ccw: bool) -> void:
		# Godot treats clockwise triangles as front faces.
		if ccw:
			i.append(k); i.append(k + 2); i.append(k + 1)
			i.append(k); i.append(k + 3); i.append(k + 2)
		else:
			i.append(k); i.append(k + 1); i.append(k + 2)
			i.append(k); i.append(k + 2); i.append(k + 3)

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TEX_UV] = t
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_INDEX] = i
		return a


func new_batch() -> Batch:
	return Batch.new()


func new_facade() -> Facade:
	return Facade.new()


## Mesh from a set of batches: [[Batch, material name], ...].
func batches_mesh(parts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for part in parts:
		var bt: Batch = part[0]
		if bt.i.is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bt.arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, M[part[1]])
	return mesh


func _b(mat: String) -> Batch:
	var key := ck + "|" + mat
	var bt: Batch = batches.get(key)
	if bt == null:
		bt = Batch.new()
		batches[key] = bt
	return bt


const CHUNK := 80.0 # main geometry is merged per 80 m cell...
const MAIN_RANGE := 115.0
const HLOD_RANGE := 230.0 # HLOD boxes are dropped beyond this (scaled by the view distance)
## Web tier (Compatibility, phones): main chunks hand over to their HLOD boxes sooner and the
## detail chunks drop sooner (the frame-cost budget: <= 300 draws, <= 400k triangles).
var main_range := MAIN_RANGE
var detail_range := 72.0
var web_tier := false
const FOG_SCALE := 0.72 # atmosphere.gd's fog_scale for this map # ...drawn up to this far, then swapped for its HLOD boxes
var _near := true # the building being made is close to the hub: a little more relief


static func _chunk_of(x: float, z: float) -> String:
	return "K%d_%d" % [floori(x / CHUNK), floori(z / CHUNK)]


## Box with optional rotation. skip: bitmask of faces to leave out
## (1 +x, 2 -x, 4 +y, 8 -y, 16 +z, 32 -z).
static func box(bt: Batch, center: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY, skip := 0) -> void:
	var hx := basis.x * size.x * 0.5
	var hy := basis.y * size.y * 0.5
	var hz := basis.z * size.z * 0.5
	var nx := basis.x.normalized()
	var ny := basis.y.normalized()
	var nz := basis.z.normalized()
	if not skip & 1: _face(bt, center + hx, hy, -hz, nx, col, size.z, size.y)
	if not skip & 2: _face(bt, center - hx, hy, hz, -nx, col, size.z, size.y)
	if not skip & 4: _face(bt, center + hy, -hz, hx, ny, col, size.x, size.z)
	if not skip & 8: _face(bt, center - hy, hz, hx, -ny, col, size.x, size.z)
	if not skip & 16: _face(bt, center + hz, hy, hx, nz, col, size.x, size.y)
	if not skip & 32: _face(bt, center - hz, hy, -hx, -nz, col, size.x, size.y)


static func _face(bt: Batch, fc: Vector3, up: Vector3, right: Vector3, nrm: Vector3, col: Color, w: float, h: float) -> void:
	bt.quad(fc - right - up, fc - right + up, fc + right + up, fc + right - up, nrm, col, Vector2.ZERO, Vector2(w, h))


## Thin beam from p0 to p1.
static func beam(bt: Batch, p0: Vector3, p1: Vector3, w: float, h: float, col: Color, up := Vector3.UP) -> void:
	var dir := p1 - p0
	var length := dir.length()
	if length < 0.001:
		return
	var z := dir / length
	var x := up.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x)
	box(bt, (p0 + p1) * 0.5, Vector3(w, h, length), col, Basis(x, y, z))


## Cylinder (or cone/frustum) standing on `base`, smooth-shaded sides.
static func cyl(bt: Batch, base: Vector3, r_bot: float, r_top: float, h: float, segs: int, col: Color, caps := true, basis := Basis.IDENTITY) -> void:
	var up := basis.y.normalized()
	var top := base + basis.y * h
	var slope := (r_bot - r_top) / maxf(h, 0.001)
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var d0 := basis.x.normalized() * cos(a0) + basis.z.normalized() * sin(a0)
		var d1 := basis.x.normalized() * cos(a1) + basis.z.normalized() * sin(a1)
		var n0 := (d0 + up * slope).normalized()
		var n1 := (d1 + up * slope).normalized()
		bt.quad_sm(base + d0 * r_bot, top + d0 * r_top, top + d1 * r_top, base + d1 * r_bot, n0, n0, n1, n1, col,
			Vector2(float(s) / segs, 0), Vector2(float(s + 1) / segs, 1))
		if caps:
			if r_top > 0.001:
				bt.tri(top, top + d0 * r_top, top + d1 * r_top, up, col)
			if r_bot > 0.001:
				bt.tri(base, base + d1 * r_bot, base + d0 * r_bot, -up, col)


## Six-sided solid from 8 corners: p[0..3] bottom ring, p[4..7] the top ring above them.
static func hexa(bt: Batch, p: Array, col: Color) -> void:
	var ctr := Vector3.ZERO
	for q in p:
		ctr += q
	ctr /= 8.0
	_quad_out(bt, p[0], p[1], p[2], p[3], ctr, col)
	_quad_out(bt, p[4], p[5], p[6], p[7], ctr, col)
	for k in 4:
		var k1 := (k + 1) % 4
		_quad_out(bt, p[k], p[k + 4], p[k1 + 4], p[k1], ctr, col)


static func _quad_out(bt: Batch, a: Vector3, b: Vector3, d: Vector3, e: Vector3, ctr: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(e - a)
	if nrm.length() < 1e-6:
		nrm = (d - b).cross(e - b)
	nrm = nrm.normalized()
	if nrm.dot((a + b + d + e) * 0.25 - ctr) < 0.0:
		nrm = -nrm
	bt.quad(a, b, d, e, nrm, col, Vector2.ZERO, Vector2((e - a).length(), (b - a).length()))


static func _disc(bt: Batch, center: Vector3, r: float, segs: int, col: Color, uv_scale := 1.0) -> void:
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var p0 := center + Vector3(cos(a0), 0, sin(a0)) * r
		var p1 := center + Vector3(cos(a1), 0, sin(a1)) * r
		bt.tri(center, p0, p1, Vector3.UP, col, Vector2(0.5, 0.5),
			Vector2(0.5 + cos(a0) * 0.5 * uv_scale, 0.5 + sin(a0) * 0.5 * uv_scale),
			Vector2(0.5 + cos(a1) * 0.5 * uv_scale, 0.5 + sin(a1) * 0.5 * uv_scale))


static func _hash(a: int, b: int) -> float:
	var h := (a * 374761393 + b * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10007.0


# ================================================================ textures
func _noise_img(size: int, freq: float, seed_: int, octaves := 4, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> PackedByteArray:
	var fn := FastNoiseLite.new()
	fn.seed = seed_
	fn.noise_type = type
	fn.frequency = freq
	fn.fractal_octaves = octaves
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	var img := fn.get_seamless_image(size, size, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


static func _tex(w: int, h: int, fmt: int, data: PackedByteArray) -> ImageTexture:
	var img := Image.create_from_data(w, h, false, fmt, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Tangent-space normal map (OpenGL convention) from a tiling height field.
static func _normal_tex(w: int, h: int, height: PackedFloat32Array, strength: float) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(w * h * 3)
	var o := 0
	for y in h:
		var yu := ((y - 1 + h) % h) * w
		var yd := ((y + 1) % h) * w
		var row := y * w
		for x in w:
			var dx := (height[row + (x + 1) % w] - height[row + (x - 1 + w) % w]) * strength
			var dy := (height[yd + x] - height[yu + x]) * strength
			var inv := 1.0 / sqrt(dx * dx + dy * dy + 1.0)
			data[o] = int((-dx * inv * 0.5 + 0.5) * 255.0)
			data[o + 1] = int((dy * inv * 0.5 + 0.5) * 255.0)
			data[o + 2] = int((inv * 0.5 + 0.5) * 255.0)
			o += 3
	return _tex(w, h, Image.FORMAT_RGB8, data)


## Packs float colour channels into an RGB8 texture.
static func _put(data: PackedByteArray, o: int, r: float, g: float, b: float) -> void:
	data[o] = clampi(int(r * 255.0), 0, 255)
	data[o + 1] = clampi(int(g * 255.0), 0, 255)
	data[o + 2] = clampi(int(b * 255.0), 0, 255)


## Running-bond brick: 1 m tile, 16 courses of 4 bricks.
func _brick_textures() -> Array:
	var S := 256
	var fine := _noise_img(S, 0.09, 11, 3)
	var big := _noise_img(S, 0.012, 12, 3)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	var hgt := PackedFloat32Array(); hgt.resize(S * S)
	for y in S:
		var row := y >> 4
		var iny := y & 15
		var off := (row & 1) * 32
		for x in S:
			var p := y * S + x
			var bx := (x + off) & 63
			var bi := ((x + off) & 255) >> 6
			var f := fine[p] / 255.0
			var g := big[p] / 255.0
			var mortar := iny < 2 or bx < 2
			if mortar:
				var m := 0.42 + f * 0.12
				_put(alb, p * 3, m, m * 0.97, m * 0.93)
				rough[p] = 245
				hgt[p] = 0.0 + f * 0.1
			else:
				var hsh := _hash(bi + 7, row * 13 + (x + off) / 256)
				var k := 0.72 + hsh * 0.4 + (f - 0.5) * 0.18
				if hsh > 0.93:
					k *= 0.6 # the odd burnt brick
				k *= 0.8 + g * 0.3
				_put(alb, p * 3, 0.5 * k, 0.32 * k, 0.25 * k)
				rough[p] = int(clampf(0.7 + f * 0.25 - g * 0.15, 0.0, 1.0) * 255.0)
				var edge := minf(minf(float(iny - 2), float(15 - iny)), minf(float(bx - 2), float(63 - bx)))
				hgt[p] = clampf(edge / 2.0, 0.0, 1.0) * 0.8 + f * 0.25
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_L8, rough), _normal_tex(S, S, hgt, 2.5)]


## Ashlar stone blocks: 2 m tile, 0.5 m courses.
func _stone_textures() -> Array:
	var S := 256
	var fine := _noise_img(S, 0.06, 21, 4)
	var big := _noise_img(S, 0.015, 22, 3)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	var hgt := PackedFloat32Array(); hgt.resize(S * S)
	for y in S:
		var row := y >> 6
		var iny := y & 63
		var blen := 96 if row % 2 == 0 else 80
		var off := row * 37
		for x in S:
			var p := y * S + x
			var xx := (x + off) % 256
			var bx := xx % blen
			var bi := xx / blen
			var f := fine[p] / 255.0
			var g := big[p] / 255.0
			var joint := iny < 2 or bx < 2 or (xx >= (256 / blen) * blen and xx < (256 / blen) * blen + 2)
			if joint:
				var m := 0.25 + f * 0.1
				_put(alb, p * 3, m, m, m * 0.95)
				rough[p] = 240
				hgt[p] = 0.0
			else:
				var hsh := _hash(bi + 3, row + 17)
				var k := 0.75 + hsh * 0.3 + (f - 0.5) * 0.25
				k *= 0.75 + g * 0.35
				_put(alb, p * 3, 0.6 * k, 0.57 * k, 0.52 * k)
				rough[p] = int(clampf(0.65 + f * 0.3 - g * 0.2, 0.0, 1.0) * 255.0)
				var edge := minf(minf(float(iny - 2), float(63 - iny)), minf(float(bx - 2), float(blen - 1 - bx)))
				hgt[p] = clampf(edge / 4.0, 0.0, 1.0) + f * 0.4
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_L8, rough), _normal_tex(S, S, hgt, 3.0)]


## Concrete sidewalk slabs with joints: 1.5 m tile.
func _sidewalk_textures() -> Array:
	var S := 128
	var fine := _noise_img(S, 0.12, 41, 3)
	var big := _noise_img(S, 0.02, 42, 3)
	var crack := _noise_img(S, 0.03, 43, 3, FastNoiseLite.TYPE_PERLIN)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	var hgt := PackedFloat32Array(); hgt.resize(S * S)
	for y in S:
		for x in S:
			var p := y * S + x
			var f := fine[p] / 255.0
			var g := big[p] / 255.0
			var cr := absf(crack[p] / 255.0 - 0.5) < 0.012
			var joint := x < 2 or y < 2
			var k := (0.48 + f * 0.12) * (0.75 + g * 0.35)
			if joint or cr:
				k *= 0.45
			_put(alb, p * 3, k, k * 0.98, k * 0.95)
			rough[p] = int(clampf(0.55 + f * 0.3 - (1.0 - g) * 0.35, 0.05, 1.0) * 255.0)
			hgt[p] = 0.0 if joint or cr else 0.6 + f * 0.3
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_L8, rough), _normal_tex(S, S, hgt, 1.5)]


## Wet asphalt: aggregate, patches, cracks and puddle-smooth patches. 8 m tile.
func _asphalt_textures() -> Array:
	var S := 256
	var fine := _noise_img(S, 0.35, 51, 2)
	var mid := _noise_img(S, 0.04, 52, 4)
	var wet := _noise_img(S, 0.012, 53, 3)
	var crack := _noise_img(S, 0.02, 54, 4, FastNoiseLite.TYPE_PERLIN)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	var hgt := PackedFloat32Array(); hgt.resize(S * S)
	for p in S * S:
		var f := fine[p] / 255.0
		var m := mid[p] / 255.0
		var w := clampf((wet[p] / 255.0 - 0.5) * 5.0, 0.0, 1.0)
		var cr := absf(crack[p] / 255.0 - 0.5) < 0.01
		var k := 0.15 + (f - 0.5) * 0.08 + (m - 0.5) * 0.06
		if cr:
			k *= 0.5
		k *= 1.0 - w * 0.35
		_put(alb, p * 3, k, k, k * 1.04)
		rough[p] = int(clampf(lerpf(0.62 + f * 0.2, 0.06, w), 0.0, 1.0) * 255.0)
		hgt[p] = lerpf(f * 0.6 + m * 0.4, 0.5, w) - (0.4 if cr else 0.0)
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_L8, rough), _normal_tex(S, S, hgt, 1.2)]


## Painted plaster with mottling and rain streaks (tinted by vertex colour).
func _stucco_textures() -> Array:
	var S := 128
	var fine := _noise_img(S, 0.1, 61, 3)
	var big := _noise_img(S, 0.02, 62, 4)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	var hgt := PackedFloat32Array(); hgt.resize(S * S)
	for y in S:
		for x in S:
			var p := y * S + x
			var f := fine[p] / 255.0
			var g := big[p] / 255.0
			var streak := big[((y / 6) % S) * S + x] / 255.0 # stretched vertically: rain runs
			var k := (0.78 + f * 0.1) * (0.8 + g * 0.25) * (1.0 - clampf((streak - 0.55) * 1.5, 0.0, 0.35))
			_put(alb, p * 3, k, k * 0.98, k * 0.95)
			rough[p] = int(clampf(0.75 + f * 0.2 - streak * 0.25, 0.0, 1.0) * 255.0)
			hgt[p] = f * 0.6 + g * 0.4
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_L8, rough), _normal_tex(S, S, hgt, 1.2)]


## Concrete / tar roofs / generic smooth surfaces.
func _concrete_textures() -> Array:
	var S := 128
	var fine := _noise_img(S, 0.14, 71, 3)
	var big := _noise_img(S, 0.025, 72, 4)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	for p in S * S:
		var f := fine[p] / 255.0
		var g := big[p] / 255.0
		var k := (0.7 + f * 0.15) * (0.7 + g * 0.4)
		_put(alb, p * 3, k, k, k)
		rough[p] = int(clampf(0.6 + f * 0.3 - (1.0 - g) * 0.3, 0.05, 1.0) * 255.0)
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_L8, rough)]


## 4 x 5 atlas of 64 px window cells: rows 0-1 dark, 2-3 lit, 4 storefronts.
## Returns [albedo, emission].
func _window_textures() -> Array:
	var C := 64
	var W := C * 4
	var H := C * 5
	var alb := PackedByteArray(); alb.resize(W * H * 3)
	var emi := PackedByteArray(); emi.resize(W * H * 3)
	var fine := _noise_img(W, 0.08, 81, 2)
	var warm := [Color(1.0, 0.72, 0.4), Color(1.0, 0.62, 0.32), Color(1.0, 0.82, 0.55), Color(0.95, 0.55, 0.35)]
	var cool := [Color(0.5, 0.65, 1.0), Color(0.8, 0.95, 0.85), Color(0.9, 0.4, 0.3), Color(0.6, 0.5, 0.9)]
	var shop := [Color(1.0, 0.85, 0.6), Color(1.0, 0.35, 0.25), Color(0.75, 0.95, 1.0), Color(0, 0, 0)]
	for cy in 5:
		for cx in 4:
			var kind := cx + cy * 4
			for y in C:
				for x in C:
					var px := cx * C + x
					var py := cy * C + y
					var o := (py * W + px) * 3
					var f := fine[(py % W) * W + px] / 255.0
					var u := x / float(C)
					var v := y / float(C)
					if cy < 4:
						var frame := x < 4 or x >= C - 4 or y < 4 or y >= C - 4
						var mull := absi(x - C / 2) < 2 or absi(y - int(C * 0.45)) < 2
						if frame or mull:
							_put(alb, o, 0.62, 0.6, 0.55)
							_put(emi, o, 0, 0, 0)
							continue
						var blinds := (kind % 3 == 1) and (y % 6 < 2)
						var curtain := (kind % 4 == 2) and (u < 0.28 or u > 0.72)
						if cy < 2:
							# dark glass with a sky reflection gradient
							var r := 0.06 + (1.0 - v) * 0.16 + f * 0.04
							if blinds:
								_put(alb, o, 0.32, 0.31, 0.28)
							elif curtain:
								_put(alb, o, 0.2, 0.08 + (cx * 0.03), 0.07)
							else:
								_put(alb, o, r * 0.85, r * 0.92, r * 1.1)
							_put(emi, o, 0, 0, 0)
						else:
							var col: Color = warm[cx] if cy == 2 else cool[cx]
							var glow := (0.55 + (1.0 - v) * 0.35 + f * 0.1) * (1.0 - absf(u - 0.5) * 0.6)
							if blinds:
								glow *= 0.45 if y % 6 < 2 else 1.0
							if curtain:
								glow *= 0.35
								col = col.lerp(Color(0.9, 0.3, 0.2), 0.5)
							if cy == 3 and cx == 0 and (u - 0.3) * (u - 0.3) + (v - 0.65) * (v - 0.65) < 0.02:
								glow *= 0.15 # someone standing at the window
							_put(alb, o, col.r * 0.45 * glow, col.g * 0.45 * glow, col.b * 0.45 * glow)
							_put(emi, o, col.r * glow, col.g * glow, col.b * glow)
					else:
						# storefronts: thin frame, two mullions, shelves inside
						var frame := x < 2 or x >= C - 2 or y < 2 or y >= C - 2 or absi(x - C / 3) < 1 or absi(x - 2 * C / 3) < 1
						if frame:
							_put(alb, o, 0.08, 0.08, 0.08)
							_put(emi, o, 0, 0, 0)
							continue
						if cx == 3:
							# closed roller shutter
							var rib := 0.3 + 0.12 * float((y % 4) < 2) + f * 0.08
							_put(alb, o, rib, rib, rib * 1.02)
							_put(emi, o, 0, 0, 0)
							continue
						var col: Color = shop[cx]
						var g2 := 0.6 + (1.0 - v) * 0.3 + f * 0.15
						if cx == 0 and (y % 14) < 3 and v > 0.25:
							g2 *= 0.4 # shelving
						if cx == 2 and v > 0.55 and int(u * 6.0) % 2 == 0:
							g2 *= 0.5 # washing machines
						_put(alb, o, col.r * 0.35 * g2, col.g * 0.35 * g2, col.b * 0.35 * g2)
						_put(emi, o, col.r * g2, col.g * g2, col.b * g2)
	return [_tex(W, H, Image.FORMAT_RGB8, alb), _tex(W, H, Image.FORMAT_RGB8, emi)]


static func cell_uv(col: int, row: int) -> Array:
	var e := 0.004
	return [Vector2(col / ATLAS_COLS + e, row / ATLAS_ROWS + e), Vector2((col + 1) / ATLAS_COLS - e, (row + 1) / ATLAS_ROWS - e)]


## Wrought iron: top half an ornate balcony railing, bottom half plain fire-escape bars. 2 m x 1 m per half.
func _iron_texture() -> ImageTexture:
	var W := 256
	var H := 256
	var data := PackedByteArray(); data.resize(W * H * 4)
	for y in H:
		for x in W:
			var o := (y * W + x) * 4
			var solid := false
			if y < 128:
				var yy := y
				solid = yy < 6 or (yy > 118 and yy < 126) or (yy > 100 and yy < 104)
				solid = solid or (x % 16 < 2 and yy < 124)
				# scrolls: rings between the balusters
				var cxr := float(x % 16) - 8.5
				var cy1 := float(yy) - 22.0
				var cy2 := float(yy) - 86.0
				var r1 := sqrt(cxr * cxr + cy1 * cy1)
				var r2 := sqrt(cxr * cxr + cy2 * cy2)
				solid = solid or (r1 > 4.0 and r1 < 6.2) or (r2 > 4.0 and r2 < 6.2)
				solid = solid or (absi(yy - 54) < 2 and x % 32 < 30)
				var dx := float(x % 32) - 16.0
				var dy := float(yy) - 54.0
				var rr := sqrt(dx * dx + dy * dy)
				solid = solid or (rr > 7.0 and rr < 9.0)
			else:
				var yy := y - 128
				solid = yy < 6 or (yy > 60 and yy < 64) or yy > 120 or x % 20 < 2
			if solid:
				data[o] = 14; data[o + 1] = 13; data[o + 2] = 12; data[o + 3] = 255
			else:
				data[o + 3] = 0
	return _tex(W, H, Image.FORMAT_RGBA8, data)


## Striped awning canvas, 4 colourways stacked vertically.
func _awning_texture() -> ImageTexture:
	var W := 64
	var H := 64
	var data := PackedByteArray(); data.resize(W * H * 3)
	var pairs := [[Color(0.5, 0.08, 0.08), Color(0.85, 0.8, 0.7)], [Color(0.1, 0.3, 0.18), Color(0.8, 0.76, 0.6)],
		[Color(0.08, 0.12, 0.3), Color(0.82, 0.82, 0.8)], [Color(0.35, 0.06, 0.12), Color(0.35, 0.06, 0.12)]]
	var fine := _noise_img(64, 0.2, 91, 2)
	for y in H:
		var pr: Array = pairs[y / 16]
		for x in W:
			var c: Color = pr[0] if (x / 8) % 2 == 0 else pr[1]
			var k := 0.85 + fine[y * 64 + x] / 255.0 * 0.2
			_put(data, (y * W + x) * 3, c.r * k, c.g * k, c.b * k)
	return _tex(W, H, Image.FORMAT_RGB8, data)


## Neon tube colours, 8 cells across.
const NEON := [Color(1.0, 0.1, 0.45), Color(0.1, 0.85, 1.0), Color(0.75, 0.15, 1.0), Color(1.0, 0.18, 0.1),
	Color(1.0, 0.65, 0.15), Color(0.2, 1.0, 0.4), Color(1.0, 0.95, 0.85), Color(0.25, 0.35, 1.0)]


func _neon_texture() -> ImageTexture:
	var data := PackedByteArray(); data.resize(8 * 3)
	for k in 8:
		var c: Color = NEON[k]
		_put(data, k * 3, c.r, c.g, c.b)
	return ImageTexture.create_from_image(Image.create_from_data(8, 1, false, Image.FORMAT_RGB8, data))


static func neon_uv(k: int) -> Vector2:
	return Vector2((k + 0.5) / 8.0, 0.5)


## Distant skyline facade: 8 x 8 window grid, ~30% lit. Returns [albedo, emission].
func _far_textures() -> Array:
	var S := 256
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var emi := PackedByteArray(); emi.resize(S * S * 3)
	var fine := _noise_img(S, 0.05, 101, 3)
	for y in S:
		for x in S:
			var o := (y * S + x) * 3
			var f := fine[y * S + x] / 255.0
			var wx := x % 32
			var wy := y % 32
			var win := wx > 7 and wx < 25 and wy > 6 and wy < 24
			if win:
				var lit := _hash(x / 32, y / 32 + 50) < 0.3
				if lit:
					var warmth := _hash(x / 32 + 9, y / 32)
					var c := Color(1.0, 0.7, 0.4).lerp(Color(0.6, 0.75, 1.0), warmth * warmth)
					_put(alb, o, c.r * 0.4, c.g * 0.4, c.b * 0.4)
					_put(emi, o, c.r * (0.7 + f * 0.3), c.g * (0.7 + f * 0.3), c.b * (0.7 + f * 0.3))
				else:
					_put(alb, o, 0.07, 0.08, 0.1)
					_put(emi, o, 0, 0, 0)
			else:
				var k := 0.22 + f * 0.1
				_put(alb, o, k, k * 0.97, k * 0.94)
				_put(emi, o, 0, 0, 0)
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_RGB8, emi)]


## Soft round blob: light pools, puddle masks (alpha) and steam.
func _blob_texture(noisy: bool) -> ImageTexture:
	var S := 64
	var data := PackedByteArray(); data.resize(S * S * 4)
	var fine := _noise_img(S, 0.09, 111, 3)
	for y in S:
		for x in S:
			var dx := (x + 0.5) / S * 2.0 - 1.0
			var dy := (y + 0.5) / S * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - r, 0.0, 1.0)
			a = a * a
			if noisy:
				a = clampf((1.0 - r) * 1.6 + (fine[y * S + x] / 255.0 - 0.5) * 1.4 - 0.25, 0.0, 1.0)
			var o := (y * S + x) * 4
			data[o] = 255; data[o + 1] = 255; data[o + 2] = 255
			data[o + 3] = int(a * 255.0)
	return _tex(S, S, Image.FORMAT_RGBA8, data)


## Fan-pattern (segmental arc) cobbles for the cathedral plaza: 2 m tile,
## overlapping fans of radius 0.5 m, five courses of ~10 cm stones each.
func _fan_cobble_textures() -> Array:
	var S := 256
	var fine := _noise_img(S, 0.15, 33, 2)
	var big := _noise_img(S, 0.02, 34, 3)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	var hgt := PackedFloat32Array(); hgt.resize(S * S)
	for y in S:
		for x in S:
			var p := y * S + x
			var px := x / 128.0 # tile = 2 units: 2 fans across, 4 rows down
			var py := y / 128.0
			var best_j := -99
			var bi := 0
			var dv := Vector2.ZERO
			var j0 := int(floorf(py * 2.0)) - 1
			for j in range(j0, j0 + 3):
				var off := 0.5 if posmod(j, 2) == 1 else 0.0
				var cy := j * 0.5
				for i in range(int(floorf(px - off)) - 1, int(floorf(px - off)) + 2):
					var c := Vector2(i + off + 0.5, cy)
					var d := Vector2(px, py) - c
					if d.length() < 0.5 and j > best_j:
						best_j = j
						bi = i
						dv = d
			var r := dv.length() / 0.5 * 5.0 # 0..5 courses from the fan centre
			var ring := int(r)
			var a := atan2(dv.y, dv.x) # stones get shorter towards the centre
			var per := (ring + 1) * 2.4
			var sa := a / PI * per
			var stone_i := int(floorf(sa))
			var fr := r - ring
			var fa := sa - floorf(sa)
			var f := fine[p] / 255.0
			var g := big[p] / 255.0
			var joint := (fr < 0.13 and ring > 0) or fr > 0.93 or (fa < 0.08 or fa > 0.95) and ring > 0
			var h := _hash(posmod(bi, 2) * 31 + ring * 7 + 3, posmod(best_j, 4) * 97 + stone_i + 50)
			if joint:
				var m := 0.12 + f * 0.06
				_put(alb, p * 3, m, m * 0.98, m * 0.95)
				rough[p] = 20 # water in the joints
				hgt[p] = 0.0
			else:
				var k := (0.5 + h * 0.4 + (f - 0.5) * 0.2) * (0.75 + g * 0.35)
				var warm := 0.95 + h * 0.1
				_put(alb, p * 3, 0.42 * k * warm, 0.4 * k, 0.37 * k / warm)
				rough[p] = int(clampf(0.35 + f * 0.25 - g * 0.15, 0.05, 1.0) * 255.0)
				var edge := minf(minf(fr - 0.13, 0.93 - fr) * 5.0, minf(fa - 0.08, 0.95 - fa) * 3.0)
				hgt[p] = sqrt(clampf(edge * 4.0, 0.0, 1.0)) * 0.9 + f * 0.15
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_L8, rough), _normal_tex(S, S, hgt, 3.0)]


## French Quarter cast-iron lace. Top half: gallery railing (2 m x 1 m per tile);
## bottom half: the scalloped frieze hung under each gallery deck.
func _lace_texture() -> ImageTexture:
	var W := 256
	var H := 256
	var data := PackedByteArray(); data.resize(W * H * 4)
	for y in H:
		for x in W:
			var solid := false
			if y < 128:
				var yy := y
				solid = yy < 5 or yy > 121 or (yy > 27 and yy < 31) or (yy > 108 and yy < 111)
				# frieze of rings under the handrail
				var rx := float(x % 16) - 8.0
				var ry := float(yy) - 17.0
				var rr := sqrt(rx * rx + ry * ry)
				solid = solid or (rr > 5.0 and rr < 7.0)
				# balusters with lozenge medallions every 32 px
				var mx := float(x % 32) - 16.0
				var my := float(yy) - 70.0
				var md := absf(mx) * 1.4 + absf(my) * 0.75
				var in_med := md < 22.0
				solid = solid or (not in_med and x % 8 < 2 and yy > 30 and yy < 109)
				solid = solid or (md > 19.0 and md < 22.0) or (md > 9.0 and md < 11.5)
				var cr := sqrt(mx * mx + my * my)
				solid = solid or cr < 3.0
				# little scrolls at the foot
				var sx := float(x % 16) - 8.0
				var sy := float(yy) - 100.0
				var sr := sqrt(sx * sx + sy * sy)
				solid = solid or (sr > 3.5 and sr < 5.2 and sy < 0.0)
			else:
				var yy := y - 128
				solid = yy < 5
				# hanging scallops, a drop at each cusp
				var ax := float(x % 32) - 16.0
				var ay := float(yy) - 4.0
				var ar := sqrt(ax * ax + ay * ay)
				solid = solid or (ar > 13.0 and ar < 16.0 and ay > 0.0)
				solid = solid or (ar > 6.0 and ar < 8.0 and ay > 0.0)
				var dx := float((x + 16) % 32) - 16.0
				solid = solid or (absf(dx) < 1.5 and yy < 26) or (absf(dx) < 3.0 and yy > 22 and yy < 28)
				solid = solid or (x % 4 < 1 and yy < 12 and ar > 16.0)
			var o := (y * W + x) * 4
			if solid:
				data[o] = 18; data[o + 1] = 17; data[o + 2] = 16; data[o + 3] = 255
			else:
				data[o + 3] = 0
	# one atlas for the whole gallery (one draw per detail cell): lace on top, the fern below
	var img := Image.create(W, H * 2, false, Image.FORMAT_RGBA8)
	img.blit_rect(Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, data), Rect2i(0, 0, W, H), Vector2i.ZERO)
	var fern := _fern_image()
	fern.resize(W, H, Image.INTERPOLATE_BILINEAR)
	img.blit_rect(fern, Rect2i(0, 0, W, H), Vector2i(0, H))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Hanging Boston fern: drooping fronds from a basket at the top centre.
func _fern_image() -> Image:
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for k in 15:
		var ang := lerpf(-1.35, 1.35, (k + r.randf() * 0.6) / 15.0)
		var length := r.randf_range(52.0, 92.0)
		var dir := Vector2(sin(ang), -cos(ang) * 0.35).normalized()
		var p0 := Vector2(64 + r.randf_range(-6, 6), 12)
		var g := r.randf_range(0.65, 1.0)
		var col := Color(0.16 * g, 0.34 * g, 0.1 * g, 1.0)
		var steps := int(length)
		for s in steps:
			var t := float(s) / steps
			var p := p0 + dir * length * t * 0.8 + Vector2(0, length * t * t * 0.9)
			var tangent := (dir * 0.8 + Vector2(0, 1.8 * t)).normalized()
			var nrm := Vector2(-tangent.y, tangent.x)
			var leaf := (1.0 - t) * 9.0 + 2.0
			for side: float in [-1.0, 1.0]:
				for q in int(leaf):
					var lp := p + nrm * side * q + tangent * q * 0.45
					var ix := int(lp.x)
					var iy := int(lp.y)
					if ix >= 0 and ix < S and iy >= 0 and iy < S and (s % 3 != 0 or q < 2):
						img.set_pixel(ix, iy, col.lightened(0.15 * (1.0 - q / leaf)))
	# basket
	for y in range(4, 16):
		for x in range(50, 78):
			var dx := (x - 64) / 14.0
			var dy := (y - 4) / 12.0
			if dx * dx + dy * dy * 0.6 < 1.0 and y > 6:
				img.set_pixel(x, y, Color(0.12, 0.09, 0.06, 1.0))
	return img


## Stained glass atlas (512 x 256). Left: the rose window (radial tracery, amber
## and ruby with cobalt accents). Right: two lancet cells with leaded panes and a
## saint in a medallion. Returns [albedo, emission].
func _stained_textures() -> Array:
	var W := 512
	var H := 256
	var alb := PackedByteArray(); alb.resize(W * H * 3)
	var emi := PackedByteArray(); emi.resize(W * H * 3)
	var fine := _noise_img(256, 0.12, 121, 2)
	var pal := [Color(1.0, 0.62, 0.18), Color(1.0, 0.5, 0.12), Color(0.95, 0.72, 0.3), Color(0.85, 0.2, 0.08),
		Color(1.0, 0.58, 0.2), Color(0.2, 0.3, 0.75), Color(1.0, 0.8, 0.4), Color(0.75, 0.3, 0.1)]
	var stone := Color(0.3, 0.29, 0.27)
	for y in H:
		for x in W:
			var o := (y * W + x) * 3
			var f := fine[(y % 256) * 256 + (x % 256)] / 255.0
			var lead := false
			var trac := false
			var c := Color.BLACK
			if x < 256:
				var dx := x - 127.5
				var dy := y - 127.5
				var r := sqrt(dx * dx + dy * dy)
				var a := atan2(dy, dx) + PI
				var seg := 0
				if r > 125.0:
					trac = true
				elif r < 22.0:
					seg = 0
					trac = r > 19.0
					lead = absf(fmod(a * 6.0 / PI, 1.0) - 0.5) > 0.46
				elif r < 64.0:
					var sa := a * 12.0 / TAU
					seg = 1 + int(sa)
					trac = r < 25.0 or r > 61.0 or absf(sa - roundf(sa)) * (r * TAU / 12.0) < 2.2
					lead = absf(r - 43.0) < 1.0
				elif r < 100.0:
					# 24 trefoil-headed petals
					var sa := a * 24.0 / TAU
					var fa := sa - floorf(sa)
					seg = 20 + int(sa)
					var lobe := Vector2((fa - 0.5) * (r * TAU / 24.0), r - 88.0)
					trac = r > 97.0 or absf(fa - 0.5) * (r * TAU / 24.0) > (r * TAU / 48.0) - 2.0
					trac = trac or (lobe.length() > 7.5 and lobe.length() < 9.5)
					lead = absf(r - 76.0) < 1.0
				else:
					var sa := a * 48.0 / TAU
					seg = 60 + int(sa)
					var cc := Vector2((sa - floorf(sa) - 0.5) * (r * TAU / 48.0), r - 112.0)
					trac = r > 122.0 or cc.length() > 7.5 and cc.length() < 10.0
					lead = absf(sa - roundf(sa)) * (r * TAU / 48.0) < 0.8
				if not trac:
					c = pal[int(_hash(seg, 11) * 8.0) % 8]
					if seg == 0:
						c = Color(1.0, 0.85, 0.5)
			else:
				var lx := (x - 256) % 128
				var cell := (x - 256) / 128
				var ux := lx / 127.0
				var vy := y / 255.0
				trac = lx < 6 or lx > 121 or y > 250
				# diamond quarries with lead cames
				var qa := (lx + y * 0.6) / 16.0
				var qb := (lx - y * 0.6) / 16.0
				lead = absf(qa - roundf(qa)) < 0.07 or absf(qb - roundf(qb)) < 0.07
				var med := Vector2(ux - 0.5, (vy - 0.48) * 2.0)
				var md := med.length()
				c = pal[int(_hash(int(floorf(qa)) + cell * 7, int(floorf(qb)) + 3) * 5.0)]
				if md < 0.42:
					lead = absf(md - 0.4) < 0.02
					c = Color(0.2, 0.28, 0.7) if cell == 1 else Color(0.85, 0.22, 0.1)
					if cell == 0:
						# a robed saint with a gold halo
						var head := Vector2(ux - 0.5, (vy - 0.33) * 2.0).length()
						var robe := absf(ux - 0.5) < 0.05 + (vy - 0.36) * 0.5 and vy > 0.36 and vy < 0.64
						if head < 0.13:
							c = Color(1.0, 0.85, 0.4) if head > 0.08 else Color(0.95, 0.7, 0.5)
						elif robe:
							c = Color(0.95, 0.55, 0.15)
					else:
						var star := absf(sin(atan2(med.y, med.x) * 4.0)) * 0.22 + 0.08
						if md < star:
							c = Color(1.0, 0.7, 0.25)
			if trac:
				var k := 0.8 + f * 0.3
				_put(alb, o, stone.r * k, stone.g * k, stone.b * k)
				_put(emi, o, 0, 0, 0)
			elif lead:
				_put(alb, o, 0.03, 0.03, 0.03)
				_put(emi, o, 0, 0, 0)
			else:
				var gl := 0.75 + f * 0.4
				_put(alb, o, c.r * 0.22, c.g * 0.22, c.b * 0.22)
				_put(emi, o, c.r * gl, c.g * gl, c.b * gl)
	return [_tex(W, H, Image.FORMAT_RGB8, alb), _tex(W, H, Image.FORMAT_RGB8, emi)]


## Painted shop interiors seen through the glass, 4 x 2 cells of 128 px:
## 0 antiques, 1 hoodoo shop, 2 jazz bar, 3 cafe; 4 amber wall, 5 red wall,
## 6 door with a lit glass light, 7 closed board shutters. Returns [albedo, emission].
func _shop_textures() -> Array:
	var C := 128
	var img := Image.create(C * 4, C * 2, false, Image.FORMAT_RGB8)
	var em := Image.create(C * 4, C * 2, false, Image.FORMAT_RGB8)
	var fine := _noise_img(C, 0.1, 131, 2)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for cell in 8:
		var ox := (cell % 4) * C
		var oy := (cell / 4) * C
		for y in C:
			for x in C:
				var u := x / float(C)
				var v := y / float(C)
				var f := fine[y * C + x] / 255.0
				var c := Color.BLACK
				var e := 1.0
				match cell:
					0: # antiques: amber room, shelves of clutter, a lamp and a globe
						c = Color(1.0, 0.66, 0.32) * (0.55 + (1.0 - v) * 0.3 + f * 0.15)
						if v > 0.2 and int(v * 128.0) % 26 < 3:
							c = Color(0.12, 0.07, 0.04)
						elif v > 0.2 and v < 0.85 and _hash(int(u * 14.0), int(v * 5.0)) < 0.45:
							c *= 0.35 + _hash(int(u * 23.0), int(v * 9.0)) * 0.4
						var lamp := Vector2((u - 0.28) * 1.6, v - 0.42)
						if absf(lamp.x) < 0.12 + lamp.y * 0.5 and lamp.y > -0.08 and lamp.y < 0.08:
							c = Color(1.0, 0.85, 0.45) * 1.4
						elif absf(u - 0.28) < 0.015 and v > 0.5 and v < 0.75:
							c = Color(0.15, 0.1, 0.05)
						var gl := Vector2(u - 0.72, (v - 0.58) * 1.0).length()
						if gl < 0.11:
							c = Color(0.55, 0.45, 0.25) * (0.7 + f * 0.6)
					1: # hoodoo: oxblood room, rows of candles, skulls and a horned skull
						c = Color(0.75, 0.12, 0.06) * (0.45 + (1.0 - v) * 0.25 + f * 0.2)
						for row: float in [0.55, 0.78]:
							if absf(v - row) < 0.012:
								c = Color(0.1, 0.03, 0.02)
							var cx := fmod(u * 9.0 + row * 3.0, 1.0)
							if absf(cx - 0.5) < 0.12 and v < row and v > row - 0.08:
								c = Color(0.9, 0.82, 0.65) * 0.8
							if absf(cx - 0.5) < 0.06 and v < row - 0.08 and v > row - 0.12:
								c = Color(1.0, 0.75, 0.3) * 1.8
						var sk := Vector2((u - 0.5) * 1.3, v - 0.3)
						if sk.length() < 0.1 and not (Vector2(absf(sk.x) - 0.04, sk.y + 0.01).length() < 0.025):
							c = Color(0.85, 0.8, 0.7)
						if absf(sk.y + 0.05) < 0.025 and absf(sk.x) > 0.1 and absf(sk.x) < 0.25 + sk.y:
							c = Color(0.8, 0.75, 0.65)
					2: # jazz bar: amber-red haze, musicians in silhouette
						c = Color(1.0, 0.35, 0.12).lerp(Color(1.0, 0.7, 0.35), 1.0 - v) * (0.55 + f * 0.2)
						for m in 3:
							var mx := 0.22 + m * 0.28
							var head := Vector2((u - mx) * 1.2, v - 0.38).length()
							var body := absf(u - mx) < 0.07 + (v - 0.42) * 0.25 and v > 0.42
							if head < 0.055 or body:
								c = Color(0.04, 0.02, 0.02)
						if Vector2((u - 0.75) * 1.4, v - 0.62).length() < 0.11 or (absf(u - 0.79) < 0.01 and v > 0.3 and v < 0.6):
							c = Color(0.05, 0.02, 0.01) # the bass
					3: # cafe: pendant lamps over little tables
						c = Color(1.0, 0.75, 0.45) * (0.45 + (1.0 - v) * 0.3 + f * 0.15)
						for m in 3:
							var mx := 0.2 + m * 0.3
							if Vector2(u - mx, (v - 0.3) * 1.6).length() < 0.06:
								c = Color(1.0, 0.92, 0.7) * 1.6
							if absf(u - mx) < 0.1 and absf(v - 0.72) < 0.015 or absf(u - mx) < 0.012 and v > 0.72:
								c = Color(0.08, 0.05, 0.03)
					4:
						c = Color(1.0, 0.68, 0.36) * (0.45 + (1.0 - v) * 0.3 + f * 0.1)
					5:
						c = Color(0.8, 0.18, 0.08) * (0.4 + (1.0 - v) * 0.25 + f * 0.1)
					6: # door: dark planks, a lit glass light up top
						c = Color(0.16, 0.1, 0.06) * (0.7 + f * 0.5)
						e = 0.0
						if v > 0.08 and v < 0.4 and u > 0.15 and u < 0.85:
							c = Color(1.0, 0.7, 0.4) * (0.6 + f * 0.2)
							e = 1.0
						if absf(u - 0.5) < 0.015 or absf(v - 0.62) < 0.012:
							c = Color(0.06, 0.04, 0.02)
							e = 0.0
					_: # closed louvred board shutters, green
						var lou := 0.7 + 0.3 * float(int(v * 128.0) % 6 < 3)
						c = Color(0.1, 0.24, 0.16) * lou * (0.7 + f * 0.5)
						if absf(u - 0.5) < 0.012 or u < 0.05 or u > 0.95:
							c = Color(0.04, 0.08, 0.05)
						e = 0.0
				img.set_pixel(ox + x, oy + y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0)) * (0.35 if e > 0.0 else 1.0))
				em.set_pixel(ox + x, oy + y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0)) * e)
	img.generate_mipmaps()
	em.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(em)]


static func shop_uv(cell: int) -> Array:
	var e := 0.004
	var cx := cell % 4
	var cy := cell / 4
	return [Vector2(cx / 4.0 + e, cy / 2.0 + e), Vector2((cx + 1) / 4.0 - e, (cy + 1) / 2.0 - e)]


## Stone baluster band for the Undercroft balustrade (alpha scissor), 1 tile = 1 m wide.
func _baluster_texture() -> ImageTexture:
	var W := 64
	var H := 64
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var fine := _noise_img(64, 0.15, 141, 2)
	for y in H:
		for x in W:
			var u := (x % 16) / 16.0 - 0.5
			var v := y / float(H)
			# vase-shaped baluster profile
			var w := 0.16 + 0.14 * sin(clampf((v - 0.1) / 0.8, 0.0, 1.0) * PI * 1.15 + 0.4)
			var solid := absf(u) < w or v < 0.06 or v > 0.94
			if solid:
				var k := 0.55 + fine[y * 64 + x] / 255.0 * 0.25 - absf(u) * 0.4
				img.set_pixel(x, y, Color(k, k * 0.97, k * 0.92, 1.0))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.4, 1.0);
uniform float strength = 0.0;
void vertex() {
	// camera-facing quad, also inside a MultiMesh
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 2.4) + 0.6 * pow(clamp(1.0 - d * 2.6, 0.0, 1.0), 2.0);
	ALBEDO = tint.rgb;
	ALPHA = a * strength;
}
"""

const UPLIGHT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.08, 0.04, 1.0);
uniform float strength = 1.0;
uniform float y0 = -3.2;
uniform float y1 = 2.5;
varying float h;
void vertex() { h = VERTEX.y; }
void fragment() {
	float t = clamp((h - y0) / (y1 - y0), 0.0, 1.0);
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.8);
	ALBEDO = tint.rgb;
	ALPHA = strength * pow(1.0 - t, 1.8) * (0.25 + 0.75 * edge) * 0.55;
}
"""


# ================================================================ materials
func _surface_mat(texs: Array, tile_m: float, rough_scale := 1.0, triplanar := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = texs[0]
	m.roughness_texture = texs[1]
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = rough_scale
	if texs.size() > 2:
		m.normal_enabled = true
		m.normal_texture = texs[2]
		m.normal_scale = 1.0
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_triplanar_sharpness = 6.0
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _flat_mat(rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	return m


## The photographic material library (asset round 3, assets/textures/library: seamless 1024 px
## albedo / normal / roughness, imported Lossy). [albedo, roughness, normal], or [] if missing.
const LIB_DIR := "res://assets/textures/library/"
static func lib_textures(name: String) -> Array:
	var out := []
	for k in ["albedo", "roughness", "normal"]:
		var p := LIB_DIR + "%s_%s.jpg" % [name, k]
		if not ResourceLoader.exists(p):
			return []
		out.append(load(p))
	return out


## A surface material from the library, or from the procedural generator if it is missing.
func _lib_mat(name: String, tile_m: float, fallback: Callable, fallback_tile: float, rough_scale := 1.0) -> StandardMaterial3D:
	var t := lib_textures(name)
	if t.is_empty():
		return _surface_mat(fallback.call(), fallback_tile, rough_scale)
	return _surface_mat(t, tile_m, rough_scale)


func _make_materials() -> void:
	# walls and paving: the photographic library where it beats the procedural textures
	M["brick"] = _lib_mat("brick", 2.0, _brick_textures, 1.0)
	M["stone"] = _lib_mat("limestone", 3.0, _stone_textures, 2.0)
	M["stucco"] = _lib_mat("stucco", 3.0, _stucco_textures, 3.0)
	M["concrete"] = _lib_mat("weathered_concrete", 3.5, _concrete_textures, 4.0)
	M["trim"] = _lib_mat("weathered_concrete", 5.0, _concrete_textures, 6.0, 0.7)
	M["sidewalk"] = _surface_mat(_sidewalk_textures(), 1.5)
	M["asphalt"] = preload("res://scripts/wet_materials.gd").asphalt() # shared wet-street shader (puddles, rain ripples)
	M["metal"] = _flat_mat(0.45, 0.5)
	M["paint"] = _flat_mat(0.5)
	for k in ["brick", "stone", "stucco", "concrete", "trim"]:
		CASTS[k] = true

	var win := _window_textures()
	window_mat = StandardMaterial3D.new()
	window_mat.albedo_texture = win[0]
	window_mat.emission_enabled = true
	window_mat.emission = Color(1, 1, 1)
	window_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	window_mat.emission_texture = win[1]
	window_mat.emission_energy_multiplier = 0.0
	window_mat.roughness = 0.12
	window_mat.metallic = 0.25
	window_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	M["glass"] = window_mat
	flicker_mat = window_mat.duplicate()
	M["glass_flicker"] = flicker_mat

	var iron := StandardMaterial3D.new()
	iron.albedo_texture = _iron_texture()
	iron.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	iron.alpha_scissor_threshold = 0.5
	iron.cull_mode = BaseMaterial3D.CULL_DISABLED
	iron.roughness = 0.5
	iron.metallic = 0.6
	M["iron"] = iron
	var chain := iron.duplicate()
	chain.metallic = 0.15
	chain.roughness = 0.75
	chain.albedo_color = Color(0.55, 0.55, 0.52)
	M["chainlink"] = chain # fences out in the wilds (metallic iron mirrored the pink horizon)

	var awn := StandardMaterial3D.new()
	awn.albedo_texture = _awning_texture()
	awn.cull_mode = BaseMaterial3D.CULL_DISABLED
	awn.roughness = 0.6
	M["awning"] = awn

	neon_mat = StandardMaterial3D.new()
	var nt := _neon_texture()
	neon_mat.albedo_texture = nt
	neon_mat.emission_enabled = true
	neon_mat.emission_texture = nt
	neon_mat.emission = Color(1, 1, 1)
	neon_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	neon_mat.emission_energy_multiplier = 3.0
	neon_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	M["neon"] = neon_mat
	neon_flicker_mat = neon_mat.duplicate()
	M["neon_flicker"] = neon_flicker_mat

	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.9, 0.62, 0.3)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.52, 0.18) # gas-mantle amber, not white
	lamp_mat.emission_energy_multiplier = 0.2
	M["lamp"] = lamp_mat

	var stx := _stained_textures()
	stained_mat = StandardMaterial3D.new()
	stained_mat.albedo_texture = stx[0]
	stained_mat.emission_enabled = true
	stained_mat.emission_texture = stx[1]
	stained_mat.emission = Color(1, 1, 1)
	stained_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	stained_mat.emission_energy_multiplier = 0.0
	stained_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	stained_mat.roughness = 0.2
	M["stained"] = stained_mat

	M["cobble_fan"] = _lib_mat("wet_cobblestone", 2.0, _fan_cobble_textures, 1.5, 0.8)

	var lace := StandardMaterial3D.new()
	lace.albedo_texture = _lace_texture()
	lace.vertex_color_use_as_albedo = true
	lace.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	lace.alpha_scissor_threshold = 0.45
	lace.cull_mode = BaseMaterial3D.CULL_DISABLED
	lace.roughness = 0.55
	lace.metallic = 0.25
	M["lace"] = lace

	var bal := StandardMaterial3D.new()
	bal.albedo_texture = _baluster_texture()
	bal.vertex_color_use_as_albedo = true
	bal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	bal.alpha_scissor_threshold = 0.5
	bal.cull_mode = BaseMaterial3D.CULL_DISABLED
	bal.roughness = 0.75
	M["baluster"] = bal

	var shx := _shop_textures()
	shop_mat = StandardMaterial3D.new()
	shop_mat.albedo_texture = shx[0]
	shop_mat.emission_enabled = true
	shop_mat.emission = Color(1, 1, 1)
	shop_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	shop_mat.emission_texture = shx[1]
	shop_mat.emission_energy_multiplier = 0.0
	shop_mat.roughness = 0.9
	shop_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	M["shop"] = shop_mat

	crypt_mat = StandardMaterial3D.new()
	crypt_mat.albedo_color = Color(0.25, 0.01, 0.01)
	crypt_mat.emission_enabled = true
	crypt_mat.emission = Color(1.0, 0.06, 0.03)
	crypt_mat.emission_energy_multiplier = 2.2
	crypt_mat.vertex_color_use_as_albedo = true
	M["crypt_glow"] = crypt_mat

	halo_mat = ShaderMaterial.new()
	halo_mat.shader = Shader.new()
	halo_mat.shader.code = HALO_SHADER
	M["halo"] = halo_mat

	var far := _far_textures()
	far_mat = StandardMaterial3D.new()
	far_mat.albedo_texture = far[0]
	far_mat.emission_enabled = true
	far_mat.emission = Color(1, 1, 1)
	far_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	far_mat.emission_texture = far[1]
	far_mat.emission_energy_multiplier = 0.0
	far_mat.roughness = 0.8
	M["far"] = far_mat
	CASTS["far"] = false

	var puddle := StandardMaterial3D.new()
	puddle.albedo_color = Color(0.02, 0.022, 0.026)
	puddle.albedo_texture = _blob_texture(true)
	puddle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	puddle.alpha_scissor_threshold = 0.5
	puddle.roughness = 0.02
	puddle.metallic = 0.1
	M["puddle"] = puddle

	pool_mat = StandardMaterial3D.new()
	pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_mat.albedo_texture = _blob_texture(false)
	pool_mat.albedo_color = Color(0, 0, 0)
	pool_mat.disable_receive_shadows = true
	M["pool"] = pool_mat

	var leaves := StandardMaterial3D.new()
	leaves.albedo_texture = _blob_texture(true)
	leaves.albedo_color = Color(0.12, 0.17, 0.09)
	leaves.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaves.alpha_scissor_threshold = 0.4
	leaves.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaves.roughness = 0.8
	M["leaves"] = leaves
	_make_map_materials()


# ================================================================ build
func build() -> void:
	rng.seed = SEED
	web_tier = preload("res://scripts/atmosphere.gd").detect_tier() == "web"
	if web_tier:
		main_range = 80.0
		detail_range = 48.0
	Terrain.build_nodes(self) # the ground: heightmap collision, terrain chunks, water
	_make_materials()
	collider_root = Node3D.new()
	collider_root.name = "Colliders"
	add_child(collider_root)
	car_bodies = StaticBody3D.new()
	car_bodies.name = "ParkedCars"
	add_child(car_bodies)
	_build_ground()
	# the Old Quarter grid round the cathedral plaza
	# Owner's playtest: "in the city part the streets are too short". The north-south streets
	# now run unbroken past 40 m blocks (the cross streets at z = -40 and z = 40 are built over),
	# so each avenue reads as one long canyon of galleries out to the cathedral and the pines
	# (concept 12). Every crossing that remains is still a road point; the avenues are intact.
	var consumed := {}
	for i in range(Layout.OQ_I[0], Layout.OQ_I[1]):
		for j in range(Layout.OQ_J[0], Layout.OQ_J[1]):
			street_cells[Vector2i(i, j)] = true
			var cx := i * GRID + GRID * 0.5
			var cz := j * GRID + GRID * 0.5
			if absf(cx) < GRID and absf(cz) < GRID:
				continue
			if cz == -30.0 and absf(cx) == 10.0:
				continue # the cathedral takes these two blocks
			if consumed.has(Vector2i(i, j)):
				continue
			var span := 1
			if j in LONG_BLOCK_J and not (j == -3 and (i == -1 or i == 0)):
				span = 2 # (behind the cathedral the z = -40 street stays: it's its back lane)
			for k in range(1, span):
				consumed[Vector2i(i, j + k)] = true
				filled_segs[Vector3i(j + k, i, 1)] = true
			_build_block(cx, j * GRID + GRID * span * 0.5, "quarter", span)
	# the Velvet Mile: grand blocks either side of the boulevard
	for i in range(Layout.VM_I[0], Layout.VM_I[1]):
		if i == Layout.VM_MILE_I:
			continue
		for j in range(Layout.VM_J[0], Layout.VM_J[1]):
			var c := Vector2i(i, j)
			if Layout.VM_SQUARE.has_point(c) or Layout.VM_OPERA.has_point(c):
				continue # paved by velvet.gd
			street_cells[c] = true
			_build_block(i * GRID + GRID * 0.5, j * GRID + GRID * 0.5, "velvet")
	_near = true
	_build_plaza()
	_build_cathedral()
	_build_streets()
	Velvet.build(self)
	Docks.build(self)
	Wilds.build_pines(self)
	Wilds.build_bayou(self)
	Cemetery.build(self)
	_build_backdrop()
	_place_signs()
	_build_props()
	_flush()
	_build_walls()
	_collect_grid_spots()
	_settle_on_terrain()
	_register_quality()


## Ground height at (x, z): the one API everything placed on the map uses (terrain.gd).
## The paved plates (the Quarter, the Mile, the cemetery, the docks) are level at 0.
func height_at(x: float, z: float) -> float:
	return Terrain.height_at(x, z)


# ---------------------------------------------------------------- quality tiers and frame budget
## The web budget is <= 350 draws and <= 600k triangles from any spot at the default tier
## (tests/frame_budget.gd guards it in the smoke test). Every visibility range authored here is
## for the High tier; apply_quality() rescales them to Settings' view distance, thins the
## foliage and street clutter MultiMeshes, and re-runs whenever Settings changes.
const WQ = preload("res://scripts/map/world_quality.gd")
const LABEL_RANGE := 60.0 # neon blade-sign lettering and other world text
const PARTICLE_RANGE := 55.0 # steam from grates, fireflies
## MultiMeshes with no colliders under them, thinned by foliage_density (the near pines and
## cypress keep every tree: their trunks are solid, so they only shorten their range).
const FOLIAGE_THIN := ["PineCards", "CypressCards", "PineBush", "BayouBush"]
const PROPS_THIN := ["Glb_trash"]
var _q_ranges: Array = [] # [GeometryInstance3D, begin, end]
var _q_foliage: Array = [] # MultiMeshes thinned by foliage_density
var _q_props: Array = [] # ... and by prop_density


func _register_quality() -> void:
	for n in find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.visibility_range_end <= 0.0:
			if gi is Label3D:
				gi.visibility_range_end = LABEL_RANGE
			elif gi is CPUParticles3D or gi is GPUParticles3D:
				gi.visibility_range_end = PARTICLE_RANGE
		if gi.visibility_range_end > 0.0 or gi.visibility_range_begin > 0.0:
			_q_ranges.append([gi, gi.visibility_range_begin, gi.visibility_range_end])
		if gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			var nm := String(gi.name)
			for pre in FOLIAGE_THIN:
				if nm.begins_with(pre):
					_q_foliage.append((gi as MultiMeshInstance3D).multimesh)
			for pre in PROPS_THIN:
				if nm.begins_with(pre):
					_q_props.append((gi as MultiMeshInstance3D).multimesh)
	apply_quality()
	var st := get_node_or_null("/root/Settings")
	if st != null and st.has_signal("changed") and not st.is_connected("changed", apply_quality):
		st.connect("changed", apply_quality)


func apply_quality() -> void:
	var k := WQ.range_scale()
	for e in _q_ranges:
		var gi: GeometryInstance3D = e[0]
		if not is_instance_valid(gi):
			continue
		gi.visibility_range_begin = e[1] * k
		gi.visibility_range_end = e[2] * k
	var fd := WQ.foliage_density()
	for mm: MultiMesh in _q_foliage:
		mm.visible_instance_count = -1 if fd >= 0.999 else ceili(mm.instance_count * fd)
	var pd := WQ.prop_density()
	for mm: MultiMesh in _q_props:
		mm.visible_instance_count = -1 if pd >= 0.999 else ceili(mm.instance_count * pd)


## Spawn points, POI anchors and loot caches collected flat by the builders sit on the ground.
func _settle_on_terrain() -> void:
	for k in road_points.size():
		var p := road_points[k]
		road_points[k] = Vector3(p.x, height_at(p.x, p.z), p.z)
	for a in poi_anchors:
		a.pos = Vector3(a.pos.x, height_at(a.pos.x, a.pos.z), a.pos.z)
	for s in cache_spots:
		s.pos = Vector3(s.pos.x, height_at(s.pos.x, s.pos.z) + 0.1, s.pos.z)


## Invisible walls round the walkable area: the river (west, south), deep bayou water,
## dense forest (north) and the Velvet Mile's back streets (east).
func _build_walls() -> void:
	var r := play_rect
	var c := r.get_center()
	_static_box(Vector3(2, 40, r.size.y + 4.0), Vector3(r.position.x - 1.0, 20, c.y))
	_static_box(Vector3(2, 40, r.size.y + 4.0), Vector3(r.end.x + 1.0, 20, c.y))
	_static_box(Vector3(r.size.x + 4.0, 40, 2), Vector3(c.x, 20, r.position.y - 1.0))
	_static_box(Vector3(r.size.x + 4.0, 40, 2), Vector3(c.x, 20, r.end.y + 1.0))


## Points of interest, caches and roaming spawn points in the street grids.
func _collect_grid_spots() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = SEED + 7
	var seen := {}
	for cell: Vector2i in street_cells.keys():
		for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var q := Vector2((cell.x + corner.x) * GRID, (cell.y + corner.y) * GRID)
			var key := Vector2i(roundi(q.x), roundi(q.y))
			if seen.has(key):
				continue
			seen[key] = true
			if PLAZA_RECT.grow(4.0).has_point(q):
				continue
			if absf(q.x) <= GRID and q.y <= -GRID and q.y >= -2.0 * GRID:
				continue # the cathedral front
			road_points.append(Vector3(q.x, 0.0, q.y))
			var dist := Layout.district_at(q.x, q.y)
			poi_anchors.append({"pos": Vector3(q.x, 0.0, q.y), "district": dist, "tag": "crossing"})
	# caches on the sidewalks of the street grids (two in the plaza)
	cache_spots.append({"pos": Vector3(-14.0, 0.1, -3.0), "yaw": PI * 0.5, "coffin": true})
	cache_spots.append({"pos": Vector3(3.5, 0.1, 14.2), "yaw": 0.0, "coffin": true})
	var cells := block_cells.duplicate()
	for k in range(cells.size() - 1, 0, -1):
		var s := r.randi_range(0, k)
		var tmp = cells[k]
		cells[k] = cells[s]
		cells[s] = tmp
	for k in mini(cells.size(), 22):
		var b: Vector2 = cells[k]
		var side := r.randi_range(0, 3)
		if side < 2 and (int(inner_sides.get(b, 0)) & (1 << side)) != 0:
			side += 2 # the inside of a long block: put it on an avenue side instead
		var n: Vector3 = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)][side]
		var t := Vector3.UP.cross(n)
		var p: Vector3 = Vector3(b.x, 0.1, b.y) + n * 4.9 + t * r.randf_range(-3.5, 3.5)
		cache_spots.append({"pos": p, "yaw": atan2(t.x, t.z), "coffin": true})


## A walkable road point near `center` (18-45 m away if possible), for roaming spawns.
func road_point_near(center: Vector3, r: RandomNumberGenerator) -> Vector3:
	var best := Vector3(0, 0.5, -60)
	var best_score := INF
	for attempt in 40:
		var q: Vector3 = road_points[r.randi() % road_points.size()]
		var p := q + Vector3(r.randf_range(-2.0, 2.0), 0.5, r.randf_range(-2.0, 2.0))
		var dist := p.distance_to(center)
		if dist > 18.0 and dist < 45.0:
			return p
		var score := (18.0 - dist) * 100.0 if dist <= 18.0 else dist - 45.0
		if score < best_score:
			best_score = score
			best = p
	return best


## Point of interest anchor (open ground ~10 m round), cache spot and road point helpers
## for the district builders.
func add_anchor(p: Vector3, tag := "") -> void:
	poi_anchors.append({"pos": Vector3(p.x, 0.0, p.z), "district": Layout.district_at(p.x, p.z), "tag": tag})


func add_cache(p: Vector3, yaw: float, coffin: bool) -> void:
	cache_spots.append({"pos": Vector3(p.x, 0.1, p.z), "yaw": yaw, "coffin": coffin})


func add_road(p: Vector3) -> void:
	road_points.append(Vector3(p.x, 0.0, p.z))


func _static_box(size: Vector3, pos: Vector3, parent: Node3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	(parent if parent else collider_root).add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	return body


## One MeshInstance per chunk and shadow class, one surface per material.
func _flush(prefix := "", parent: Node3D = null, offset := Vector3.ZERO) -> void:
	var by_chunk := {}
	for key in batches.keys():
		var parts: PackedStringArray = key.split("|")
		if prefix != "" and parts[0] != prefix:
			continue
		var casts: bool = CASTS.get(parts[1], false)
		if parts[0].begins_with("H"):
			casts = false # frame budget: HLOD boxes never cast, so walls and roofs share one instance
		var group := parts[0] + ("|cast" if casts else "|nocast")
		if not by_chunk.has(group):
			by_chunk[group] = []
		by_chunk[group].append(key)
	for group in by_chunk.keys():
		var mesh := ArrayMesh.new()
		var keys: Array = by_chunk[group]
		keys.sort()
		# detail chunks ("D<x>_<z>", 40 m cells) and main chunks ("K<x>_<z>", 80 m cells) get a
		# local origin at the cell centre and a visibility range; their HLOD boxes ("H<x>_<z>")
		# take over beyond it. "M" (landmarks) and "F" (backdrop) are always drawn.
		var shift := offset
		var kind: String = group.substr(0, 1)
		var cell := 0.0
		match kind:
			"D": cell = DETAIL_CELL
			"K", "H": cell = CHUNK
		if cell > 0.0:
			var xz: PackedStringArray = group.split("|")[0].substr(1).split("_")
			shift = Vector3((int(xz[0]) + 0.5) * cell, 0, (int(xz[1]) + 0.5) * cell)
		for key in keys:
			var bt: Batch = batches[key]
			if bt.i.is_empty():
				continue
			if shift != Vector3.ZERO:
				for k in bt.v.size():
					bt.v[k] -= shift
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bt.arrays())
			mesh.surface_set_material(mesh.get_surface_count() - 1, M[key.split("|")[1]])
		for key in keys:
			batches.erase(key)
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_" + group.replace("|", "_")
		mi.mesh = mesh
		if group.ends_with("nocast"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if cell > 0.0:
			mi.position = shift
		match kind:
			"D":
				mi.visibility_range_end = detail_range
				mi.visibility_range_end_margin = 8.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"K":
				mi.visibility_range_end = main_range
				mi.visibility_range_end_margin = 10.0
			"H":
				mi.visibility_range_begin = main_range
				mi.visibility_range_begin_margin = 10.0
				# frame budget: beyond this the fog has swallowed a block (landmarks, "M", stay)
				mi.visibility_range_end = HLOD_RANGE
				mi.visibility_range_end_margin = 20.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(parent if parent else self).add_child(mi)


const DETAIL_CELL := 40.0
const DETAIL_RANGE := 72.0


## Detail chunk (galleries, lace, ferns, shutters...) for a point: hidden beyond DETAIL_RANGE.
static func _dk(x: float, z: float) -> String:
	return "D%d_%d" % [floori(x / DETAIL_CELL), floori(z / DETAIL_CELL)]


## Batch in the detail chunk around (x, z).
func _bd(mat: String, x: float, z: float) -> Batch:
	var save := ck
	ck = _dk(x, z)
	var bt := _b(mat)
	ck = save
	return bt


# ---------------------------------------------------------------- ground
func _build_ground() -> void:
	# Collision: the terrain's heightmap (terrain.gd; level at 0 under the city plates). Visual:
	# wet asphalt under the street grids (with a hole for the Undercroft shaft); the districts
	# lay their own ground over the rest, the terrain shader paints the wilds.
	var bt := Batch.new()
	var x0 := -80.0
	var z0 := -72.0
	var x1 := 240.0
	var z1 := Layout.RIVER_Z
	var h := PIT_HOLE
	for r in [[x0, z0, x1, -h], [x0, h, x1, z1], [x0, -h, -h, h], [h, -h, x1, h]]:
		var a := Vector3(r[0], 0, r[3])
		var b := Vector3(r[0], 0, r[1])
		var d := Vector3(r[2], 0, r[1])
		var e := Vector3(r[2], 0, r[3])
		bt.quad(a, b, d, e, Vector3.UP, Color.WHITE, Vector2(r[0], r[1]), Vector2(r[2], r[3]))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bt.arrays())
	mesh.surface_set_material(0, M["asphalt"])
	var mi := MeshInstance3D.new()
	mi.name = "Asphalt"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A flat ground quad (y slightly above 0) into the current chunk's `mat` batch, UVs in metres.
func ground_quad(mat: String, x0: float, z0: float, x1: float, z1: float, col := Color.WHITE, y := 0.02) -> void:
	var bt := _b(mat)
	bt.quad(Vector3(x0, y, z1), Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3.UP, col, Vector2(x0, z0) * 0.25, Vector2(x1, z1) * 0.25)


## Same, split into 80 m chunks so each part culls with its neighbourhood.
func ground_rect(mat: String, x0: float, z0: float, x1: float, z1: float, col := Color.WHITE, y := 0.02) -> void:
	var save := ck
	var x := x0
	while x < x1 - 0.01:
		var xe := minf(x1, (floorf(x / CHUNK) + 1.0) * CHUNK)
		var z := z0
		while z < z1 - 0.01:
			var ze := minf(z1, (floorf(z / CHUNK) + 1.0) * CHUNK)
			ck = _chunk_of((x + xe) * 0.5, (z + ze) * 0.5)
			ground_quad(mat, x, z, xe, ze, col, y)
			z = ze
		x = xe
	ck = save


## Raised (visual-only) paved slab with a kerb edge.
func _slab(x0: float, z0: float, x1: float, z1: float, top_mat: String, top_col: Color, kerb_col: Color) -> void:
	var t := _b(top_mat)
	var y := WALK_TOP
	t.quad(Vector3(x0, y, z1), Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3.UP, top_col)
	var k := _b("stone")
	# kerb sides and a granite kerb strip on top
	for s in [[Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(0, 0, 1)], [Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3(0, 0, -1)],
			[Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3(1, 0, 0)], [Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(-1, 0, 0)]]:
		var a: Vector3 = s[0]
		var e: Vector3 = s[1]
		k.quad(a, a + Vector3(0, y + 0.004, 0), e + Vector3(0, y + 0.004, 0), e, s[2], kerb_col)
		var inward: Vector3 = -s[2] * 0.22
		k.quad(a + Vector3(0, y + 0.004, 0) + inward, a + Vector3(0, y + 0.004, 0), e + Vector3(0, y + 0.004, 0), e + Vector3(0, y + 0.004, 0) + inward, Vector3.UP, kerb_col)


# ---------------------------------------------------------------- blocks
func _district(cx: float, cz: float) -> String:
	return Layout.district_at(cx, cz)


func _build_block(cx: float, cz: float, dist: String, span := 1) -> void:
	ck = _chunk_of(cx, cz)
	_near = maxf(absf(cx), absf(cz)) <= 40.0
	var hz := GRID * span * 0.5 # half the block's length along z
	for k in span:
		var sc := Vector2(cx, cz - hz + GRID * (k + 0.5))
		block_cells.append(sc)
		if span > 1:
			inner_sides[sc] = (1 if k < span - 1 else 0) | (2 if k > 0 else 0)
	var walk_col := Color(1, 1, 1) if dist != "quarter" else Color(0.72, 0.66, 0.6)
	_slab(cx - GRID * 0.5 + ROAD_HALF, cz - hz + ROAD_HALF, cx + GRID * 0.5 - ROAD_HALF, cz + hz - ROAD_HALF,
		"sidewalk" if dist != "quarter" else "cobble_fan", walk_col, Color(0.62, 0.6, 0.57))
	# split the lot into parcels
	var L := LOT
	var Lz := hz - FACADE
	var parcels: Array = []
	var pattern := rng.randi_range(0, 4)
	if dist == "quarter":
		pattern = [1, 2, 3, 4][rng.randi() % 4]
	elif dist == "docks":
		pattern = [0, 0, 1, 2][rng.randi() % 4]
	if span > 1:
		pattern = 9 # a long block: a terrace of townhouses down each avenue
	match pattern:
		9:
			# rows across the block, 6.5-10 m deep, some split into two houses back to back
			var z := -Lz
			while z < Lz - 0.01:
				var dz := rng.randf_range(6.5, 10.0)
				var z1 := Lz if Lz - (z + dz) < 5.0 else z + dz
				if rng.randf() < 0.55:
					var sx := rng.randf_range(-1.2, 1.2)
					parcels.append([-L, z, sx, z1]); parcels.append([sx, z, L, z1])
				else:
					parcels.append([-L, z, L, z1])
				z = z1
		0:
			parcels.append([-L, -L, L, L])
		1:
			var s := rng.randf_range(-1.2, 1.2)
			parcels.append([-L, -L, s, L]); parcels.append([s, -L, L, L])
		2:
			var s := rng.randf_range(-1.2, 1.2)
			parcels.append([-L, -L, L, s]); parcels.append([-L, s, L, L])
		3:
			var a := -L + rng.randf_range(2.4, 3.0)
			var b := L - rng.randf_range(2.4, 3.0)
			parcels.append([-L, -L, a, L]); parcels.append([a, -L, b, L]); parcels.append([b, -L, L, L])
		_:
			var sx := rng.randf_range(-1.0, 1.0)
			var sz := rng.randf_range(-1.0, 1.0)
			parcels.append([-L, -L, sx, sz]); parcels.append([sx, -L, L, sz])
			parcels.append([-L, sz, sx, L]); parcels.append([sx, sz, L, L])
	# a back alley through some two-parcel blocks (image 04): the split widens into a 2.8 m gap
	var alley_sides := {} # parcel index -> facade side that faces the alley
	var alley_p := {"quarter": 0.45, "midtown": 0.6, "docks": 0.6, "velvet": 0.35}
	# (never on the blocks lining the x = 0 avenue, which keeps its gallery fronts unbroken)
	if span == 1 and (pattern == 1 or pattern == 2) and rng.randf() < alley_p[dist] and not (dist == "quarter" and absf(cx) == 10.0):
		var AW := 2.8
		var s := clampf((parcels[0][2] if pattern == 1 else parcels[0][3]), -0.8, 0.8)
		if pattern == 1:
			parcels = [[-L, -L, s - AW * 0.5, L], [s + AW * 0.5, -L, L, L]]
			alley_sides = {0: 2, 1: 3}
			_alley_floor(Vector3(cx + s, 0, cz), Vector3(0, 0, 1), AW, 2.0 * L)
		else:
			parcels = [[-L, -L, L, s - AW * 0.5], [-L, s + AW * 0.5, L, L]]
			alley_sides = {0: 0, 1: 1}
			_alley_floor(Vector3(cx, 0, cz + s), Vector3(1, 0, 0), AW, 2.0 * L)
	var body := StaticBody3D.new()
	body.name = "Block_%d_%d" % [cx, cz]
	collider_root.add_child(body)
	var far := clampf((maxf(absf(cx), absf(cz)) - 30.0) / 40.0, 0.0, 1.0)
	if dist == "velvet":
		far = clampf(1.0 - absf(cx - 150.0) / 60.0, 0.0, 1.0) * 0.6 # taller towards the Mile
	var binfo := {"centre": Vector2(cx, cz), "district": dist, "lots": [], "heights": []}
	blocks.append(binfo)
	for pi in parcels.size():
		var p: Array = parcels[pi]
		var spec := _building_spec(dist, far)
		spec["x0"] = cx + p[0]
		spec["z0"] = cz + p[1]
		spec["x1"] = cx + p[2]
		spec["z1"] = cz + p[3]
		# the street-cell centre this parcel faces (a long block spans several; lamps stand at
		# each cell's mid-point and the gallery columns step round them)
		var pcz: float = cz + (p[1] + p[3]) * 0.5
		spec["bc"] = Vector2(cx, cz - hz + GRID * (clampi(floori((pcz - (cz - hz)) / GRID), 0, span - 1) + 0.5))
		spec["alley"] = alley_sides.get(pi, -1)
		if spec.alley >= 0 and dist == "quarter":
			spec["wall"] = "brick" # alley walls are bare brick even in the Quarter
			spec["wcol"] = BRICK[rng.randi() % BRICK.size()]
		# which sides face a street
		spec["ext"] = [is_equal_approx(p[3], Lz), is_equal_approx(p[1], -Lz), is_equal_approx(p[2], L), is_equal_approx(p[0], -L)]
		var H := _building(spec)
		var fp := Rect2(cx + p[0], cz + p[1], p[2] - p[0], p[3] - p[1])
		hlod_box(fp, H, spec.wcol)
		binfo.lots.append(fp)
		binfo.heights.append(H)
		lots.append(fp)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(p[2] - p[0], H, p[3] - p[1])
		col.shape = shape
		col.position = Vector3(cx + (p[0] + p[2]) * 0.5, H * 0.5, cz + (p[1] + p[3]) * 0.5)
		body.add_child(col)


## HLOD stand-in for a building: a far-textured box (no roof clutter) drawn beyond MAIN_RANGE.
func hlod_box(fp: Rect2, h: float, tint: Color) -> void:
	var save := ck
	var c := fp.get_center()
	ck = "H" + _chunk_of(c.x, c.y).substr(1)
	var bt := _b("far")
	var x0 := fp.position.x
	var z0 := fp.position.y
	var x1 := fp.end.x
	var z1 := fp.end.y
	var uo := Vector2(rng.randi_range(0, 7) / 8.0, rng.randi_range(0, 7) / 8.0)
	var s := 1.0 / 25.6
	var t := tint.lerp(Color(1, 1, 1), 0.5)
	bt.quad(Vector3(x0, 0, z1), Vector3(x0, h, z1), Vector3(x1, h, z1), Vector3(x1, 0, z1), Vector3(0, 0, 1), t, uo, uo + Vector2((x1 - x0) * s, h * s))
	bt.quad(Vector3(x1, 0, z0), Vector3(x1, h, z0), Vector3(x0, h, z0), Vector3(x0, 0, z0), Vector3(0, 0, -1), t, uo, uo + Vector2((x1 - x0) * s, h * s))
	bt.quad(Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x1, h, z0), Vector3(x1, 0, z0), Vector3(1, 0, 0), t, uo, uo + Vector2((z1 - z0) * s, h * s))
	bt.quad(Vector3(x0, 0, z0), Vector3(x0, h, z0), Vector3(x0, h, z1), Vector3(x0, 0, z1), Vector3(-1, 0, 0), t, uo, uo + Vector2((z1 - z0) * s, h * s))
	_b("concrete").quad(Vector3(x0, h, z1), Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3.UP, Color(0.2, 0.2, 0.2))
	ck = save


const STUCCO := [Color(0.85, 0.6, 0.55), Color(0.88, 0.72, 0.48), Color(0.6, 0.74, 0.64), Color(0.7, 0.64, 0.78),
	Color(0.9, 0.84, 0.72), Color(0.58, 0.68, 0.8), Color(0.78, 0.46, 0.36), Color(0.92, 0.9, 0.85)]
const BRICK := [Color(1, 1, 1), Color(0.9, 0.82, 0.76), Color(0.78, 0.66, 0.6), Color(1.0, 0.92, 0.86), Color(0.68, 0.68, 0.7), Color(0.6, 0.5, 0.46)]
const SHUTTER := [Color(0.12, 0.25, 0.17), Color(0.08, 0.16, 0.11), Color(0.05, 0.055, 0.05), Color(0.16, 0.3, 0.24)]


func _building_spec(dist: String, far: float) -> Dictionary:
	var s := {"style": dist}
	match dist:
		"quarter":
			# faded pastel stucco or old brick townhouses (images 02 and 12)
			s["wall"] = "stucco" if rng.randf() < 0.65 else "brick"
			s["wcol"] = STUCCO[rng.randi() % STUCCO.size()] * Color(0.82, 0.8, 0.78) if s["wall"] == "stucco" else BRICK[rng.randi() % 4]
			s["tcol"] = Color(0.9, 0.88, 0.82)
			s["floors"] = [2, 2, 3, 3, 3, 1][rng.randi() % 6]
			s["gh"] = 4.4
			s["fh"] = 3.7
			s["shutter"] = SHUTTER[rng.randi() % SHUTTER.size()]
		"velvet":
			s["wall"] = ["stone", "stucco", "brick"][rng.randi() % 3]
			s["wcol"] = Color(0.75, 0.72, 0.7) if s["wall"] != "brick" else BRICK[rng.randi() % BRICK.size()]
			if s["wall"] == "stucco":
				s["wcol"] = Color(0.32, 0.3, 0.34).lerp(Color(0.7, 0.66, 0.62), rng.randf())
			s["tcol"] = Color(0.7, 0.68, 0.64)
			s["floors"] = rng.randi_range(4, 8) + int(far * rng.randf_range(0.0, 7.0))
			s["gh"] = 4.6
			s["fh"] = 3.4
		"docks":
			s["wall"] = "brick"
			s["wcol"] = BRICK[rng.randi() % BRICK.size()] * Color(0.9, 0.85, 0.85)
			s["tcol"] = Color(0.5, 0.5, 0.48)
			s["floors"] = rng.randi_range(1, 4)
			s["gh"] = 5.0
			s["fh"] = 4.0
		_:
			s["wall"] = "brick" if rng.randf() < 0.75 else "stucco"
			s["wcol"] = BRICK[rng.randi() % BRICK.size()] if s["wall"] == "brick" else Color(0.62, 0.6, 0.56).lerp(Color(0.82, 0.78, 0.7), rng.randf())
			s["tcol"] = Color(0.78, 0.75, 0.68)
			s["floors"] = rng.randi_range(3, 7) + int(far * rng.randf_range(0.0, 5.0))
			s["gh"] = 4.4
			s["fh"] = 3.2
	return s


class Facade:
	var o: Vector3
	var r: Vector3
	var n: Vector3
	var w: float

	func p(u: float, y: float, d: float) -> Vector3:
		return o + r * u + Vector3(0, y, 0) + n * d


func _facade(spec: Dictionary, side: int) -> Facade:
	var f := Facade.new()
	var x0: float = spec.x0
	var x1: float = spec.x1
	var z0: float = spec.z0
	var z1: float = spec.z1
	match side:
		0:
			f.o = Vector3(x0, 0, z1); f.r = Vector3(1, 0, 0); f.n = Vector3(0, 0, 1); f.w = x1 - x0
		1:
			f.o = Vector3(x1, 0, z0); f.r = Vector3(-1, 0, 0); f.n = Vector3(0, 0, -1); f.w = x1 - x0
		2:
			f.o = Vector3(x1, 0, z1); f.r = Vector3(0, 0, -1); f.n = Vector3(1, 0, 0); f.w = z1 - z0
		_:
			f.o = Vector3(x0, 0, z0); f.r = Vector3(0, 0, 1); f.n = Vector3(-1, 0, 0); f.w = z1 - z0
	return f


## Flat rectangle on the facade plane, offset d along the normal.
static func fq(bt: Batch, f: Facade, u0: float, y0: float, u1: float, y1: float, d: float, col: Color, uv0 := Vector2.ZERO, uv1 := Vector2.ONE) -> void:
	bt.quad(f.p(u0, y0, d), f.p(u0, y1, d), f.p(u1, y1, d), f.p(u1, y0, d), f.n, col, uv0, uv1)


## Box sitting on the facade: u/y ranges, protruding from d0 to d1.
static func fbox(bt: Batch, f: Facade, u0: float, y0: float, u1: float, y1: float, d0: float, d1: float, col: Color, skip_back := true) -> void:
	var c := f.p((u0 + u1) * 0.5, (y0 + y1) * 0.5, (d0 + d1) * 0.5)
	var basis := Basis(f.r, Vector3.UP, f.n)
	box(bt, c, Vector3(u1 - u0, y1 - y0, d1 - d0), col, basis, 32 if skip_back else 0)


## A recessed opening: reveals in `rev`, glass (or whatever) at the back.
func _opening(f: Facade, u0: float, y0: float, u1: float, y1: float, depth: float, rev: Batch, rev_col: Color, back: Batch, uv: Array, bottom := true) -> void:
	var d := -depth
	rev.quad(f.p(u0, y0, d), f.p(u0, y1, d), f.p(u0, y1, 0), f.p(u0, y0, 0), f.r, rev_col)
	rev.quad(f.p(u1, y0, 0), f.p(u1, y1, 0), f.p(u1, y1, d), f.p(u1, y0, d), -f.r, rev_col)
	rev.quad(f.p(u0, y1, d), f.p(u0, y1, 0), f.p(u1, y1, 0), f.p(u1, y1, d), Vector3.DOWN, rev_col)
	if bottom:
		rev.quad(f.p(u0, y0, 0), f.p(u0, y0, d), f.p(u1, y0, d), f.p(u1, y0, 0), Vector3.UP, rev_col)
	fq(back, f, u0, y0, u1, y1, d, Color.WHITE, uv[0], uv[1])


## Wall strip with a row of holes in it.
static func _wall_row(bt: Batch, f: Facade, y0: float, y1: float, holes: Array, col: Color) -> void:
	var u := 0.0
	for h in holes:
		if h[0] > u + 0.001:
			fq(bt, f, u, y0, h[0], y1, 0.0, col)
		u = h[1]
	if f.w > u + 0.001:
		fq(bt, f, u, y0, f.w, y1, 0.0, col)


func _window_uv(style: String) -> Array:
	var lit_p := 0.32 if style != "docks" else 0.15
	var r := rng.randf()
	if r < 0.025:
		return [cell_uv(rng.randi() % 4, 2), true] # flickering
	if r < lit_p:
		return [cell_uv(rng.randi() % 4, 2 if rng.randf() < 0.72 else 3), false]
	return [cell_uv(rng.randi() % 4, rng.randi() % 2), false]


## Builds one building; returns its collider height.
func _building(spec: Dictionary) -> float:
	var style: String = spec.style
	var floors: int = spec.floors
	var gh: float = spec.gh
	var fh: float = spec.fh
	var H := gh + floors * fh
	var par := 0.9 if style != "quarter" else 0.7
	var wall := _b(spec.wall)
	var wcol: Color = spec.wcol
	var tcol: Color = spec.tcol
	var trim := _b("trim")
	var stone := _b("stone")
	var glass := _b("glass")
	var glass_f := _b("glass_flicker")
	var ext: Array = spec.ext
	var dirt := wcol * Color(0.82, 0.8, 0.78)

	# window layout per style
	var bay := 2.5
	var ww := 1.15
	var wh := 1.7
	var sill := 0.85
	var depth := 0.18
	match style:
		"quarter":
			bay = 2.1; ww = 1.05; wh = fh - 0.9; sill = 0.12; depth = 0.14
		"velvet":
			bay = 2.0; ww = 1.35; wh = 2.0; sill = 0.7
		"docks":
			bay = 3.0; ww = 2.0; wh = 2.2; sill = 0.95
		_:
			bay = rng.randf_range(2.2, 2.8); ww = rng.randf_range(1.0, 1.3)

	for side in 4:
		var f := _facade(spec, side)
		if side == spec.get("alley", -1):
			_alley_wall(spec, f, H, par)
			continue
		if not ext[side]:
			# party wall: blank, slightly dirtier
			fq(wall, f, 0, 0, f.w, H + par, 0.0, dirt)
			continue
		if style == "quarter":
			_quarter_facade(spec, f, H, par)
			continue
		var n_cols := maxi(1, int(f.w / bay))
		var margin := (f.w - n_cols * bay) * 0.5
		var centers: Array = []
		for k in n_cols:
			centers.append(margin + bay * (k + 0.5))
		_ground_floor(spec, f, gh, wall, wcol, trim, tcol, glass)
		# belt course
		fbox(stone, f, -0.05, gh - 0.12, f.w + 0.05, gh + 0.12, 0.0, 0.1, tcol)
		# upper floors: one wall quad per storey, flush glass with a painted frame and a
		# flat sill/lintel strip in front (no reveals: the window atlas carries the depth)
		var near: bool = _near
		var upper_h := floors * fh
		fq(wall, f, 0, gh, f.w, gh + upper_h, 0.0, wcol, Vector2.ZERO, Vector2(f.w, upper_h))
		for fl in floors:
			var y0 := gh + fl * fh
			var ya := y0 + sill
			var yb := ya + wh
			for cu in centers:
				var wuv: Array = _window_uv(style)
				fq(glass_f if wuv[1] and _near else glass, f, cu - ww * 0.5, ya, cu + ww * 0.5, yb, 0.012, Color.WHITE, wuv[0][0], wuv[0][1])
				if near:
					fbox(stone, f, cu - ww * 0.5 - 0.1, ya - 0.08, cu + ww * 0.5 + 0.1, ya, 0.0, 0.12, tcol)
				else:
					fq(stone, f, cu - ww * 0.5 - 0.1, ya - 0.1, cu + ww * 0.5 + 0.1, ya, 0.02, tcol)
				if style == "midtown" or style == "docks":
					fq(stone, f, cu - ww * 0.5 - 0.08, yb, cu + ww * 0.5 + 0.08, yb + 0.2, 0.02, tcol)
		if style == "velvet":
			# Art Deco piers between the window columns
			for k in n_cols + 1:
				var pu := margin + bay * k
				fbox(stone, f, pu - 0.18, gh, pu + 0.18, H + par + 0.6, 0.0, 0.16, tcol)
		# parapet + cornice
		fq(wall, f, 0, H, f.w, H + par, 0.0, wcol)
		var corn := tcol if style != "docks" else wcol * Color(0.8, 0.8, 0.8)
		fbox(stone, f, -0.3, H - 0.55, f.w + 0.3, H - 0.25, 0.0, 0.38, corn)
		fbox(stone, f, -0.15, H - 0.85, f.w + 0.15, H - 0.55, 0.0, 0.2, corn)
		if style == "midtown" and floors >= 4 and rng.randf() < 0.45:
			_fire_escape(f, centers[rng.randi() % centers.size()], gh, fh, floors, sill, bay)
		if spec.style != "docks" and spec.style != "quarter" or rng.randf() < 0.3:
			sign_spots.append([f, gh, spec.style, Vector3((spec.x0 + spec.x1) * 0.5, 0, (spec.z0 + spec.z1) * 0.5)])
	_roof(spec, H, par)
	return H + par


func _ground_floor(spec: Dictionary, f: Facade, gh: float, wall: Batch, wcol: Color, trim: Batch, tcol: Color, glass: Batch) -> void:
	var style: String = spec.style
	var stone := _b("stone")
	var n_bays := maxi(1, int(f.w / (3.2 if style != "quarter" else 2.4)))
	var bw := f.w / n_bays
	var top := 3.1 if style != "quarter" else 3.5
	var holes: Array = []
	for k in n_bays:
		holes.append([k * bw + 0.35, (k + 1) * bw - 0.35])
	_wall_row(wall, f, 0.0, top, holes, wcol)
	fq(wall, f, 0, top, f.w, gh, 0.0, wcol)
	var dark := Color(0.12, 0.11, 0.1)
	var awn := _b("awning")
	var neon := _b("neon")
	for h in holes:
		var u0: float = h[0]
		var u1: float = h[1]
		var cell: int
		if style == "docks":
			cell = 3 if rng.randf() < 0.7 else rng.randi() % 3
		else:
			cell = rng.randi() % 3 if rng.randf() < 0.8 else 3
		# painted shop interiors (antiques, hoodoo, jazz, cafe) or a closed shutter
		_opening(f, u0, 0.0, u1, top, 0.3, trim, dark, _b("shop"), shop_uv(cell if cell != 3 else 7), false)
		if cell != 3 and style != "quarter":
			# bulkhead under the shop window
			fq(trim, f, u0, 0.0, u1, 0.55, -0.28, Color(0.15, 0.13, 0.12))
		if style == "quarter":
			fbox(stone, f, u0 - 0.15, top, u1 + 0.15, top + 0.3, 0.0, 0.1, tcol)
			continue
		# sign band
		var band := Color(0.08, 0.08, 0.09) if rng.randf() < 0.5 else tcol * Color(0.5, 0.45, 0.4)
		fbox(trim, f, u0 - 0.2, top + 0.15, u1 + 0.2, top + 0.85, 0.0, 0.1, band)
		if rng.randf() < (0.55 if style == "velvet" else 0.25):
			var nk := rng.randi() % 8
			var nuv := neon_uv(nk)
			var y := top + 0.5
			var k0 := neon.v.size()
			fbox(neon, f, u0 - 0.1, y - 0.04, u1 + 0.1, y + 0.04, 0.1, 0.16, Color.WHITE)
			for q in range(k0, neon.v.size()):
				neon.t[q] = nuv
		if cell != 3 and style != "docks" and rng.randf() < 0.6:
			_awning(awn, f, u0 - 0.1, u1 + 0.1, top + 0.1, rng.randi() % 4)


## Old Quarter street front (image 12): lit shopfronts at street level, tall
## shuttered French windows above and two levels of cast-iron galleries on thin
## columns over the sidewalk. Windows are flat textured quads; the depth comes
## from the galleries, which live in visibility-ranged detail chunks.
func _quarter_facade(spec: Dictionary, f: Facade, H: float, par: float) -> void:
	var wall := _b(spec.wall)
	var wcol: Color = spec.wcol
	var tcol: Color = spec.tcol
	var trim := _b("trim")
	var stone := _b("stone")
	var glass := _b("glass")
	var glass_f := _b("glass_flicker")
	var shop := _b("shop")
	var floors: int = spec.floors
	var gh: float = spec.gh
	var fh: float = spec.fh
	var mid := f.p(f.w * 0.5, 0, 0)
	# --- street level: shops, doors and boarded bays
	var n_bays := maxi(1, int(f.w / 2.5))
	var bw := f.w / n_bays
	var top := 3.3
	var holes: Array = []
	for k in n_bays:
		holes.append([k * bw + 0.3, (k + 1) * bw - 0.3])
	_wall_row(wall, f, 0.0, top, holes, wcol * Color(0.85, 0.85, 0.85))
	fq(wall, f, 0, top, f.w, gh + floors * fh, 0.0, wcol, Vector2.ZERO, Vector2(f.w, gh + floors * fh - top))
	var dark := Color(0.08, 0.07, 0.06)
	for h in holes:
		var u0: float = h[0]
		var u1: float = h[1]
		var r := rng.randf()
		if r < 0.58:
			# lit shop: a shallow room with glowing walls and a painted interior at the back
			var cell := rng.randi() % 4
			var wcell := 5 if cell == 1 or cell == 2 else 4
			var wuv := shop_uv(wcell)
			var d := -0.45
			shop.quad(f.p(u0, 0.0, d), f.p(u0, top, d), f.p(u0, top, 0), f.p(u0, 0.0, 0), f.r, Color.WHITE, wuv[0], wuv[1])
			shop.quad(f.p(u1, 0.0, 0), f.p(u1, top, 0), f.p(u1, top, d), f.p(u1, 0.0, d), -f.r, Color.WHITE, wuv[0], wuv[1])
			shop.quad(f.p(u0, top, d), f.p(u0, top, 0), f.p(u1, top, 0), f.p(u1, top, d), Vector3.DOWN, Color(0.6, 0.6, 0.6), wuv[0], wuv[1])
			var cuv := shop_uv(cell)
			fq(shop, f, u0, 0.0, u1, top, d, Color.WHITE, cuv[0], cuv[1])
			trim.quad(f.p(u0, 0.0, 0), f.p(u0, 0.0, d), f.p(u1, 0.0, d), f.p(u1, 0.0, 0), Vector3.UP, dark)
			# shop window frame: bulkhead, transom bar and two mullions
			fq(trim, f, u0, 0.0, u1, 0.55, 0.0, Color(0.1, 0.12, 0.1))
			fq(trim, f, u0, top - 0.75, u1, top - 0.68, 0.01, dark)
			for t: float in [0.333, 0.667]:
				var um := lerpf(u0, u1, t)
				fq(trim, f, um - 0.03, 0.55, um + 0.03, top, 0.01, dark)
			# warm spill on the wet sidewalk
			var spill := f.p((u0 + u1) * 0.5, 0, 0.9)
			_light_pool(spill, 1.7)
			_wall_glow(f.p((u0 + u1) * 0.5, -1.6, 0.05), f.n, (u1 - u0) + 2.2, 4.4)
		elif r < 0.78:
			var duv := shop_uv(6)
			_opening(f, u0 + 0.2, 0.0, u1 - 0.2, top - 0.2, 0.22, trim, dark, shop, duv, false)
			fq(wall, f, u0, 0.0, u0 + 0.2, top, 0.0, wcol * Color(0.85, 0.85, 0.85))
			fq(wall, f, u1 - 0.2, 0.0, u1, top, 0.0, wcol * Color(0.85, 0.85, 0.85))
			fq(wall, f, u0 + 0.2, top - 0.2, u1 - 0.2, top, 0.0, wcol * Color(0.85, 0.85, 0.85))
		else:
			var suv := shop_uv(7)
			_opening(f, u0, 0.0, u1, top, 0.12, trim, dark, shop, suv, false)
		fq(stone, f, u0 - 0.12, top, u1 + 0.12, top + 0.22, 0.03, tcol)
	# --- upper floors: tall French windows with louvred shutters (flat quads)
	var bay := 2.1
	var n_cols := maxi(1, int(f.w / bay))
	var margin := (f.w - n_cols * bay) * 0.5
	var sc: Color = spec.shutter
	for fl in floors:
		var y0 := gh + fl * fh
		var ya := y0 + 0.12
		var yb := y0 + fh - 0.75
		for k in n_cols:
			var cu := margin + bay * (k + 0.5)
			var wuv: Array = _window_uv("quarter")
			fq(glass_f if wuv[1] and _near else glass, f, cu - 0.52, ya, cu + 0.52, yb, 0.012, Color.WHITE, wuv[0][0], wuv[0][1])
			var open := rng.randf() < 0.3
			var sw := 0.5 if not open else 0.42
			fq(trim, f, cu - 0.54 - sw, ya, cu - 0.54, yb, 0.03, sc)
			fq(trim, f, cu + 0.54, ya, cu + 0.54 + sw, yb, 0.03, sc)
			fq(stone, f, cu - 0.66, yb, cu + 0.66, yb + 0.24, 0.035, tcol)
	# --- parapet and cornice
	fq(wall, f, 0, H, f.w, H + par, 0.0, wcol)
	fbox(stone, f, -0.2, H - 0.4, f.w + 0.2, H - 0.1, 0.0, 0.3, tcol)
	# --- galleries
	_gallery(spec, f, mini(floors, 2))
	if rng.randf() < 0.3:
		sign_spots.append([f, gh, "quarter", mid])


const GAL_DEP := 1.95 # galleries reach almost to the kerb (sidewalks are 2.25 m)


func _gallery(spec: Dictionary, f: Facade, levels: int) -> void:
	if levels <= 0:
		return
	var gh: float = spec.gh
	var fh: float = spec.fh
	var c := f.p(f.w * 0.5, 0, 0)
	var lace := _bd("lace", c.x, c.z) # lace, columns and ferns share one atlas: one draw per cell
	var metal := lace
	var fern := lace
	var deck := _b("trim")
	var deck_col := Color(0.3, 0.27, 0.22)
	var iron := Color(0.035, 0.035, 0.035)
	var D := GAL_DEP
	var roof_y := gh + levels * fh - 0.2
	for k in levels + 1:
		var y := gh + k * fh if k < levels else roof_y
		# deck (or the roof over the top gallery)
		fbox(deck, f, 0.0, y - 0.14, f.w, y, 0.0, D, deck_col)
		# scalloped lace frieze under the front edge
		lace.quad(f.p(0, y - 0.6, D - 0.03), f.p(0, y - 0.14, D - 0.03), f.p(f.w, y - 0.14, D - 0.03), f.p(f.w, y - 0.6, D - 0.03),
			f.n, Color.WHITE, Vector2(0, 0.25), Vector2(f.w * 0.5, 0.34))
		if k == levels:
			break
		# railing on the front and both ends, with a handrail
		var rh := 1.05
		lace.quad(f.p(0, y, D - 0.05), f.p(0, y + rh, D - 0.05), f.p(f.w, y + rh, D - 0.05), f.p(f.w, y, D - 0.05), f.n, Color.WHITE, Vector2(0, 0), Vector2(f.w * 0.5, 0.25))
		lace.quad(f.p(0.02, y, 0.0), f.p(0.02, y + rh, 0.0), f.p(0.02, y + rh, D - 0.05), f.p(0.02, y, D - 0.05), -f.r, Color.WHITE, Vector2(0, 0), Vector2(D * 0.5, 0.25))
		lace.quad(f.p(f.w - 0.02, y, D - 0.05), f.p(f.w - 0.02, y + rh, D - 0.05), f.p(f.w - 0.02, y + rh, 0.0), f.p(f.w - 0.02, y, 0.0), f.r, Color.WHITE, Vector2(0, 0), Vector2(D * 0.5, 0.25))
		var k0 := lace.v.size()
		fbox(metal, f, 0.0, y + rh - 0.02, f.w, y + rh + 0.04, D - 0.09, D - 0.01, Color.WHITE, true)
		_solid_uv(lace, k0)
	# thin cast-iron columns at the kerb edge (none where a street lamp stands)
	var bc: Vector2 = spec.bc
	var n_col := maxi(2, int(roundf(f.w / 2.6)) + 1)
	var cols: Array = []
	for k in n_col:
		var u := lerpf(0.1, f.w - 0.1, float(k) / (n_col - 1))
		var wp := f.p(u, 0, D - 0.1)
		var along := wp.x - bc.x if absf(f.n.z) > 0.5 else wp.z - bc.y
		if absf(along) < 0.6:
			continue
		cols.append(u)
		var k1 := lace.v.size()
		fbox(metal, f, u - 0.05, 0.0, u + 0.05, roof_y - 0.14, D - 0.15, D - 0.05, Color.WHITE, false)
		_solid_uv(lace, k1)
		# QA2 #8: the iron columns were ghosts (Sol, enemies and the camera passed through them)
		post_collider(f.p(u, 0, D - 0.1), 0.09, roof_y)
	# ... and the gallery decks stop the camera arm instead of letting it poke through the floor
	cam_blocker(f.p(f.w * 0.5, gh - 0.07, D * 0.5), Vector3(f.w, 0.3, D), Basis(f.r, Vector3.UP, f.n))
	# hanging ferns in baskets between the columns
	for k in levels:
		var y := gh + (k + 1) * fh - 0.14 if k + 1 < levels else roof_y - 0.14
		for j in cols.size() - 1:
			if rng.randf() < 0.45:
				continue
			var u: float = (cols[j] + cols[j + 1]) * 0.5 + rng.randf_range(-0.3, 0.3)
			var top := f.p(u, y, D - 0.45)
			var g := rng.randf_range(0.75, 1.15)
			var fc := Color(g, g * rng.randf_range(0.95, 1.1), g * 0.9)
			var k2 := lace.v.size()
			beam(metal, top, top - Vector3(0, 0.25, 0), 0.015, 0.015, Color.WHITE)
			_solid_uv(lace, k2)
			var s := rng.randf_range(0.85, 1.15)
			for q in 2:
				var a := q * PI * 0.5 + rng.randf() * 0.4
				var rv := Vector3(cos(a), 0, sin(a)) * 0.55 * s
				var t := top - Vector3(0, 0.15, 0)
				var bot := t - Vector3(0, 1.1 * s, 0)
				fern.quad(bot - rv, t - rv, t + rv, bot + rv, Vector3(-sin(a), 0, cos(a)), fc, Vector2(0, 0.5), Vector2(1, 1))
	# potted ferns on the lowest gallery rail
	var y1 := gh
	for j in int(f.w / 3.0):
		if rng.randf() < 0.5:
			continue
		var p := f.p(rng.randf_range(0.5, f.w - 0.5), y1 + 0.95, D - 0.25)
		var fc := Color(0.9, 1.0, 0.85)
		for q in 2:
			var a := q * PI * 0.5 + 0.4
			var rv := Vector3(cos(a), 0, sin(a)) * 0.5
			fern.quad(p - rv - Vector3(0, 0.9, 0), p - rv + Vector3(0, 0.15, 0), p + rv + Vector3(0, 0.15, 0), p + rv - Vector3(0, 0.9, 0), Vector3(-sin(a), 0, cos(a)), fc, Vector2(0, 0.5), Vector2(1, 1))


## Points the vertices added since k0 at a solid-iron texel of the lace atlas.
static func _solid_uv(bt: Batch, k0: int) -> void:
	for q in range(k0, bt.t.size()):
		bt.t[q] = Vector2(0.5, 0.004)


## A back-alley wall (image 04): bare brick, small grimy windows, a zig-zag fire
## escape on one side; a steel door under a caged bulb, AC units, posters, a
## drainpipe, dumpsters and bags on the other.
func _alley_wall(spec: Dictionary, f: Facade, H: float, par: float) -> void:
	var wall := _b(spec.wall)
	var wcol: Color = spec.wcol * Color(0.72, 0.68, 0.64)
	var floors: int = spec.floors
	var gh: float = spec.gh
	var fh: float = spec.fh
	var c := f.p(f.w * 0.5, 0, 0)
	var save := ck
	fq(wall, f, 0, 0, f.w, H + par, 0.0, wcol)
	var glass := _b("glass")
	var stone := _b("stone")
	var n_cols := maxi(1, int(f.w / 2.2))
	var margin := (f.w - n_cols * 2.2) * 0.5
	for fl in floors:
		var ya := gh + fl * fh + 0.9
		for k in n_cols:
			var cu := margin + 2.2 * (k + 0.5)
			var uv := cell_uv(rng.randi() % 4, 2 if rng.randf() < 0.18 else rng.randi() % 2)
			fq(glass, f, cu - 0.45, ya, cu + 0.45, ya + 1.5, 0.01, Color.WHITE, uv[0], uv[1])
			fq(stone, f, cu - 0.55, ya - 0.1, cu + 0.55, ya, 0.02, Color(0.45, 0.43, 0.4))
	var first: bool = spec.alley == 2 or spec.alley == 0
	var metal := _b("metal")
	var rust := Color(0.22, 0.12, 0.07)
	if first:
		if floors >= 1 and f.w > 2.5:
			_fire_escape(f, f.w * 0.5, gh, fh, maxi(floors, 2), 0.9, 1.6)
		if rng.randf() < 0.5 and absf(c.x) < 70.0 and absf(c.z) < 70.0:
			var nk := 0 if rng.randf() < 0.7 else 2
			_blade_sign(f, f.w - 0.35, gh + 0.4, ["HOTEL", "BAR", "ROOMS"][rng.randi() % 3], nk)
		return
	# steel door with a caged bulb over it
	var du := clampf(f.w * 0.3, 0.7, f.w - 0.7)
	fq(_b("trim"), f, du - 0.5, 0.0, du + 0.5, 2.2, 0.02, rust)
	fq(_b("trim"), f, du - 0.6, 2.2, du + 0.6, 2.3, 0.03, Color(0.1, 0.09, 0.08))
	var bulb := f.p(du, 2.65, 0.32)
	box(_b("lamp"), bulb, Vector3(0.14, 0.2, 0.14), Color.WHITE)
	for s in 4:
		var a := s * PI * 0.5 + PI * 0.25
		var o := Vector3(cos(a), 0, sin(a)) * 0.1
		beam(metal, bulb + o + Vector3(0, -0.13, 0), bulb + o + Vector3(0, 0.13, 0), 0.015, 0.015, Color(0.05, 0.05, 0.05))
	beam(metal, f.p(du, 2.8, 0.0), bulb + Vector3(0, 0.12, 0), 0.03, 0.03, Color(0.05, 0.05, 0.05))
	halo_xfs.append(Transform3D(Basis().scaled(Vector3(0.8, 0.8, 0.8)), bulb))
	_light_pool(f.p(du, 0, 0.9), 2.2)
	_wall_glow(f.p(du, -0.6, 0.03), f.n, 4.0, 4.5)
	# wall AC units dripping onto the bricks
	for k in mini(floors, 2):
		var au := rng.randf_range(0.6, f.w - 0.6)
		var ay := gh + k * fh + 0.4
		fbox(metal, f, au - 0.35, ay, au + 0.35, ay + 0.5, 0.0, 0.55, Color(0.42, 0.42, 0.4), true)
		fq(metal, f, au - 0.28, ay + 0.06, au + 0.28, ay + 0.44, 0.56, Color(0.08, 0.08, 0.08))
	# torn posters
	for k in rng.randi_range(1, 3):
		var pu := rng.randf_range(0.3, f.w - 0.9)
		var py := rng.randf_range(0.8, 1.4)
		var g := rng.randf_range(0.45, 0.75)
		fq(_b("paint"), f, pu, py, pu + rng.randf_range(0.45, 0.7), py + rng.randf_range(0.6, 0.9), 0.015, Color(g, g * 0.92, g * 0.8))
	# drainpipe
	var pu2 := f.w - 0.25
	beam(metal, f.p(pu2, 0.0, 0.12), f.p(pu2, H, 0.12), 0.1, 0.1, Color(0.15, 0.13, 0.12))
	# dumpster and bags against the wall
	var yaw := atan2(f.r.x, f.r.z)
	var dp := f.p(clampf(du + 1.6, 1.0, f.w - 0.6), WALK_TOP, 0.62)
	_add_prop("alley_dumpster", Transform3D(Basis(Vector3.UP, yaw + PI * 0.5 + rng.randf_range(-0.08, 0.08)), dp), Color(0.13, 0.24, 0.14))
	for k in rng.randi_range(2, 4):
		_trash(dp + f.r * rng.randf_range(-1.6, 1.6) + f.n * rng.randf_range(-0.2, 0.4))
	if rng.randf() < 0.35 and absf(c.x) < 60.0 and absf(c.z) < 60.0:
		_steam(f.p(rng.randf_range(0.5, f.w - 0.5), 0.1, 1.0))


## Wet asphalt floor of a back alley, with oily puddles.
func _alley_floor(c: Vector3, along: Vector3, w: float, length: float) -> void:
	var across := Vector3.UP.cross(along)
	var a := c - along * length * 0.5
	var b := c + along * length * 0.5
	var y := Vector3(0, WALK_TOP + 0.004, 0)
	var bt := _b("cobble_fan" if _district(c.x, c.z) == "quarter" else "sidewalk")
	var hw := across * w * 0.5
	bt.quad(a - hw + y, a + hw + y, b + hw + y, b - hw + y, Vector3.UP, Color(0.42, 0.4, 0.38))
	for k in rng.randi_range(1, 3):
		_puddle(c + along * rng.randf_range(-length * 0.4, length * 0.4) + across * rng.randf_range(-0.6, 0.6) + Vector3(0, WALK_TOP + 0.008, 0), rng.randf_range(0.5, 1.0))
	alleys.append([c, along])


func _awning(bt: Batch, f: Facade, u0: float, u1: float, y: float, row: int) -> void:
	var dep := 1.3
	var drop := 0.6
	var v0 := row / 4.0 + 0.01
	var v1 := (row + 1) / 4.0 - 0.01
	var w := (u1 - u0) / 1.0
	var a := f.p(u0, y - drop, dep)
	var b := f.p(u0, y, 0.0)
	var c := f.p(u1, y, 0.0)
	var d := f.p(u1, y - drop, dep)
	var nrm := (f.n * drop + Vector3.UP * dep).normalized()
	bt.quad(a, b, c, d, nrm, Color.WHITE, Vector2(0, v0), Vector2(w, v1))
	# valance
	bt.quad(f.p(u0, y - drop - 0.25, dep), a, d, f.p(u1, y - drop - 0.25, dep), f.n, Color.WHITE, Vector2(0, v0), Vector2(w, v1))
	# side cheeks
	bt.tri(f.p(u0, y, 0.0), a, f.p(u0, y - drop, 0.0), -f.r, Color.WHITE, Vector2(0, v0), Vector2(0.5, v0), Vector2(0, v1))
	bt.tri(f.p(u1, y, 0.0), d, f.p(u1, y - drop, 0.0), f.r, Color.WHITE, Vector2(0, v0), Vector2(0.5, v0), Vector2(0, v1))
	# the camera can't pass through it (camera-only, Sol walks under it): QA2 #8
	cam_blocker(f.p((u0 + u1) * 0.5, y - (drop + 0.25) * 0.5, dep * 0.5), Vector3(absf(u1 - u0), drop + 0.25, dep), Basis(f.r, Vector3.UP, f.n))
	# a couple of thin iron arms
	var m := _b("metal")
	beam(m, f.p(u0 + 0.1, y - 0.9, 0.0), f.p(u0 + 0.1, y - drop, dep - 0.05), 0.03, 0.03, Color(0.05, 0.05, 0.05))
	beam(m, f.p(u1 - 0.1, y - 0.9, 0.0), f.p(u1 - 0.1, y - drop, dep - 0.05), 0.03, 0.03, Color(0.05, 0.05, 0.05))


## French Quarter gallery: slab on brackets, wrought-iron railing on three sides.
func _balcony(f: Facade, y: float, u0: float, u1: float) -> void:
	var dep := 1.05
	var m := _b("metal")
	var iron := _b("iron")
	var black := Color(0.06, 0.06, 0.06)
	fbox(_b("stone"), f, u0, y - 0.14, u1, y, 0.0, dep, Color(0.55, 0.53, 0.5))
	var hgt := 1.0
	var len := u1 - u0
	iron.quad(f.p(u0, y, dep), f.p(u0, y + hgt, dep), f.p(u1, y + hgt, dep), f.p(u1, y, dep), f.n, Color.WHITE, Vector2(0, 0.0), Vector2(len * 0.5, 0.5))
	iron.quad(f.p(u0, y, 0.02), f.p(u0, y + hgt, 0.02), f.p(u0, y + hgt, dep), f.p(u0, y, dep), -f.r, Color.WHITE, Vector2(0, 0), Vector2(dep * 0.5, 0.5))
	iron.quad(f.p(u1, y, dep), f.p(u1, y + hgt, dep), f.p(u1, y + hgt, 0.02), f.p(u1, y, 0.02), f.r, Color.WHITE, Vector2(0, 0), Vector2(dep * 0.5, 0.5))
	# handrail and brackets
	fbox(m, f, u0, y + hgt - 0.02, u1, y + hgt + 0.03, dep - 0.03, dep + 0.03, black, false)
	var nb := maxi(2, int(len / 1.8) + 1)
	for k in nb:
		var u := lerpf(u0 + 0.1, u1 - 0.1, float(k) / (nb - 1))
		beam(m, f.p(u, y - 0.75, 0.0), f.p(u, y - 0.14, dep * 0.8), 0.04, 0.04, black)


func _fire_escape(f: Facade, cu: float, gh: float, fh: float, floors: int, sill: float, bay: float) -> void:
	var m := _b("metal")
	var iron := _b("iron")
	var black := Color(0.07, 0.065, 0.06)
	var u0 := cu - bay * 0.8
	var u1 := cu + bay * 0.8
	var dep := 1.15
	for fl in floors:
		var y := gh + fl * fh + sill - 0.85
		fbox(m, f, u0, y - 0.06, u1, y, 0.0, dep, black, false)
		var hgt := 0.95
		iron.quad(f.p(u0, y, dep), f.p(u0, y + hgt, dep), f.p(u1, y + hgt, dep), f.p(u1, y, dep), f.n, Color.WHITE, Vector2(0, 0.5), Vector2((u1 - u0) * 0.5, 1.0))
		iron.quad(f.p(u0, y, 0.0), f.p(u0, y + hgt, 0.0), f.p(u0, y + hgt, dep), f.p(u0, y, dep), -f.r, Color.WHITE, Vector2(0, 0.5), Vector2(dep * 0.5, 1.0))
		iron.quad(f.p(u1, y, dep), f.p(u1, y + hgt, dep), f.p(u1, y + hgt, 0.0), f.p(u1, y, 0.0), f.r, Color.WHITE, Vector2(0, 0.5), Vector2(dep * 0.5, 1.0))
		fbox(m, f, u0, y + hgt - 0.03, u1, y + hgt + 0.02, dep - 0.04, dep + 0.01, black, false)
		# brackets
		beam(m, f.p(u0 + 0.1, y - 0.7, 0.0), f.p(u0 + 0.1, y - 0.06, dep * 0.9), 0.05, 0.05, black)
		beam(m, f.p(u1 - 0.1, y - 0.7, 0.0), f.p(u1 - 0.1, y - 0.06, dep * 0.9), 0.05, 0.05, black)
		if fl < floors - 1:
			# stair up to the next landing, alternating direction
			var ya := y
			var yb := y + fh
			var left := fl % 2 == 0
			var ua := (u0 + 0.35) if left else (u1 - 0.35)
			var ub := (u1 - 0.55) if left else (u0 + 0.55)
			var d := dep * 0.55
			beam(m, f.p(ua, ya, d), f.p(ub, yb - 0.02, d), 0.6, 0.05, black, f.n)
			beam(m, f.p(ua, ya + 0.9, d + 0.3), f.p(ub, yb + 0.9, d + 0.3), 0.03, 0.03, black)
	# drop ladder below the first landing
	var y0 := gh + sill - 0.85
	for s: float in [-0.22, 0.22]:
		beam(m, f.p(cu + s, y0 - 2.2, dep - 0.2), f.p(cu + s, y0, dep - 0.2), 0.04, 0.04, black)
	var rung := y0 - 2.0
	while rung < y0:
		beam(m, f.p(cu - 0.22, rung, dep - 0.2), f.p(cu + 0.22, rung, dep - 0.2), 0.025, 0.025, black)
		rung += 0.3


func _roof(spec: Dictionary, H: float, par: float) -> void:
	var x0: float = spec.x0
	var x1: float = spec.x1
	var z0: float = spec.z0
	var z1: float = spec.z1
	var conc := _b("concrete")
	var wall := _b(spec.wall)
	var wcol: Color = spec.wcol
	var roof_col := Color(0.28, 0.27, 0.27)
	conc.quad(Vector3(x0, H, z1), Vector3(x0, H, z0), Vector3(x1, H, z0), Vector3(x1, H, z1), Vector3.UP, roof_col)
	# parapet inner faces and coping
	var t := 0.25
	var top := H + par
	var cop := Color(0.6, 0.58, 0.55)
	var st := _b("stone")
	conc.quad(Vector3(x0 + t, H, z1 - t), Vector3(x0 + t, top, z1 - t), Vector3(x1 - t, top, z1 - t), Vector3(x1 - t, H, z1 - t), Vector3(0, 0, -1), wcol * Color(0.6, 0.6, 0.6))
	conc.quad(Vector3(x1 - t, H, z0 + t), Vector3(x1 - t, top, z0 + t), Vector3(x0 + t, top, z0 + t), Vector3(x0 + t, H, z0 + t), Vector3(0, 0, 1), wcol * Color(0.6, 0.6, 0.6))
	conc.quad(Vector3(x1 - t, H, z1 - t), Vector3(x1 - t, top, z1 - t), Vector3(x1 - t, top, z0 + t), Vector3(x1 - t, H, z0 + t), Vector3(-1, 0, 0), wcol * Color(0.6, 0.6, 0.6))
	conc.quad(Vector3(x0 + t, H, z0 + t), Vector3(x0 + t, top, z0 + t), Vector3(x0 + t, top, z1 - t), Vector3(x0 + t, H, z1 - t), Vector3(1, 0, 0), wcol * Color(0.6, 0.6, 0.6))
	box(st, Vector3((x0 + x1) * 0.5, top + 0.05, z1 - t * 0.5), Vector3(x1 - x0 + 0.06, 0.1, t + 0.06), cop, Basis.IDENTITY, 8)
	box(st, Vector3((x0 + x1) * 0.5, top + 0.05, z0 + t * 0.5), Vector3(x1 - x0 + 0.06, 0.1, t + 0.06), cop, Basis.IDENTITY, 8)
	box(st, Vector3(x1 - t * 0.5, top + 0.05, (z0 + z1) * 0.5), Vector3(t + 0.06, 0.1, z1 - z0 - 2.0 * t), cop, Basis.IDENTITY, 8)
	box(st, Vector3(x0 + t * 0.5, top + 0.05, (z0 + z1) * 0.5), Vector3(t + 0.06, 0.1, z1 - z0 - 2.0 * t), cop, Basis.IDENTITY, 8)
	var w := x1 - x0
	var d := z1 - z0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var m := _b("metal")
	if spec.style == "quarter":
		return
	# stair bulkhead
	if rng.randf() < 0.6 and w > 3.5 and d > 3.5:
		var bx := cx + rng.randf_range(-w * 0.2, w * 0.2)
		var bz := cz + rng.randf_range(-d * 0.2, d * 0.2)
		box(wall, Vector3(bx, H + 1.3, bz), Vector3(2.0, 2.6, 2.2), wcol * Color(0.85, 0.85, 0.85), Basis.IDENTITY, 8)
		box(st, Vector3(bx, H + 2.65, bz), Vector3(2.2, 0.1, 2.4), cop, Basis.IDENTITY, 8)
	# AC units
	for k in rng.randi_range(0, 3):
		var ax := cx + rng.randf_range(-w * 0.35, w * 0.35)
		var az := cz + rng.randf_range(-d * 0.35, d * 0.35)
		var g := rng.randf_range(0.45, 0.65)
		box(m, Vector3(ax, H + 0.5, az), Vector3(1.1, 1.0, 0.9), Color(g, g, g * 1.02), Basis.IDENTITY, 8)
		cyl(m, Vector3(ax, H + 1.0, az), 0.34, 0.34, 0.04, 10, Color(0.08, 0.08, 0.08))
	# vent pipes and antennas
	for k in rng.randi_range(1, 3):
		var px := cx + rng.randf_range(-w * 0.4, w * 0.4)
		var pz := cz + rng.randf_range(-d * 0.4, d * 0.4)
		cyl(m, Vector3(px, H, pz), 0.12, 0.12, rng.randf_range(0.8, 1.6), 6, Color(0.3, 0.3, 0.3))
	if rng.randf() < 0.3:
		var ax := cx + rng.randf_range(-w * 0.3, w * 0.3)
		var ah := rng.randf_range(3.0, 7.0)
		beam(m, Vector3(ax, H, cz), Vector3(ax, H + ah, cz), 0.06, 0.06, Color(0.1, 0.1, 0.1))
		beam(m, Vector3(ax - 0.6, H + ah * 0.8, cz), Vector3(ax + 0.6, H + ah * 0.8, cz), 0.03, 0.03, Color(0.1, 0.1, 0.1))
	# water tower
	var wt_p := 0.45 if spec.style == "midtown" or spec.style == "docks" else 0.15
	if rng.randf() < wt_p and w > 3.8 and d > 3.8:
		_water_tower(Vector3(cx + rng.randf_range(-0.6, 0.6), H, cz + rng.randf_range(-0.6, 0.6)))


func _water_tower(base: Vector3) -> void:
	var m := _b("metal")
	var wood := Color(0.36, 0.26, 0.18).lerp(Color(0.25, 0.22, 0.2), rng.randf())
	var leg := 2.6
	var r := 1.35
	var steel := Color(0.12, 0.11, 0.1)
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var off := Vector3(cos(a), 0, sin(a)) * r * 0.85
		beam(m, base + off * 1.1, base + off + Vector3(0, leg, 0), 0.12, 0.12, steel)
	for k in 2:
		var a := k * PI / 2.0 + PI / 4.0
		var off := Vector3(cos(a), 0, sin(a)) * r * 0.9
		beam(m, base - off + Vector3(0, 0.4, 0), base + off + Vector3(0, leg - 0.2, 0), 0.05, 0.05, steel)
	box(m, base + Vector3(0, leg, 0), Vector3(r * 2.1, 0.12, r * 2.1), steel)
	var tank := base + Vector3(0, leg + 0.06, 0)
	cyl(m, tank, r, r, 2.8, 14, wood, false)
	for hy: float in [0.4, 1.2, 2.0, 2.6]:
		cyl(m, tank + Vector3(0, hy, 0), r + 0.03, r + 0.03, 0.06, 14, steel, false)
	cyl(m, tank + Vector3(0, 2.8, 0), r + 0.12, 0.0, 1.0, 14, Color(0.2, 0.18, 0.17))
	cyl(m, tank + Vector3(0, 3.8, 0), 0.06, 0.02, 0.4, 5, steel)


# ---------------------------------------------------------------- neon blade signs
const SIGN_WORDS := ["JAZZ", "HOTEL", "BAR", "VOODOO", "OYSTERS", "PAWN", "LIQUOR", "BLUES", "VELVET", "BAIL", "DANCING", "GUMBO"]


func _place_signs() -> void:
	var placed: Array[Vector3] = []
	var words := SIGN_WORDS.duplicate()
	var order := range(sign_spots.size())
	for k in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp = order[k]
		order[k] = order[j]
		order[j] = tmp
	for idx in order:
		if signs_left <= 0:
			break
		var s: Array = sign_spots[idx]
		var f: Facade = s[0]
		if f.w < 3.0:
			continue
		var at := f.p(0.7, 0, 0)
		var ok := true
		for q in placed:
			if q.distance_to(at) < 22.0:
				ok = false
		if not ok:
			continue
		placed.append(at)
		signs_left -= 1
		ck = _chunk_of(at.x, at.z)
		_blade_sign(f, 0.7, s[1] + 1.0, words.pop_back() if not words.is_empty() else "BAR", rng.randi() % 8)


func _blade_sign(f: Facade, u: float, y0: float, word: String, nk: int) -> void:
	var m := _b("metal")
	var neon := _b("neon_flicker" if rng.randf() < 0.2 else "neon")
	var hgt := 0.62 * word.length() + 0.5
	var d0 := 0.35
	var d1 := 1.35
	# panel perpendicular to the wall
	var c := f.p(u, y0 + hgt * 0.5, (d0 + d1) * 0.5)
	box(m, c, Vector3(0.14, hgt, d1 - d0), Color(0.05, 0.05, 0.06), Basis(f.r, Vector3.UP, f.n))
	beam(m, f.p(u, y0 + hgt - 0.2, 0.0), f.p(u, y0 + hgt - 0.2, d0), 0.06, 0.06, Color(0.05, 0.05, 0.05))
	beam(m, f.p(u, y0 + 0.2, 0.0), f.p(u, y0 + 0.2, d0), 0.06, 0.06, Color(0.05, 0.05, 0.05))
	# neon border on both faces
	var uv := neon_uv(nk)
	var k0 := neon.v.size()
	for s: float in [-1.0, 1.0]:
		var uu := u + s * 0.09
		beam(neon, f.p(uu, y0 + 0.08, d0 + 0.08), f.p(uu, y0 + hgt - 0.08, d0 + 0.08), 0.04, 0.04, Color.WHITE)
		beam(neon, f.p(uu, y0 + 0.08, d1 - 0.08), f.p(uu, y0 + hgt - 0.08, d1 - 0.08), 0.04, 0.04, Color.WHITE)
		beam(neon, f.p(uu, y0 + 0.08, d0 + 0.08), f.p(uu, y0 + 0.08, d1 - 0.08), 0.04, 0.04, Color.WHITE)
		beam(neon, f.p(uu, y0 + hgt - 0.08, d0 + 0.08), f.p(uu, y0 + hgt - 0.08, d1 - 0.08), 0.04, 0.04, Color.WHITE)
	for q in range(k0, neon.v.size()):
		neon.t[q] = uv
	var txt := ""
	for ch in word:
		txt += ch + "\n"
	var col: Color = NEON[nk]
	for s: float in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = txt.strip_edges()
		l.font_size = 64
		l.pixel_size = 0.0085
		l.line_spacing = -18.0
		l.outline_size = 0
		l.modulate = Color(minf(col.r * 1.6, 1.0), minf(col.g * 1.6, 1.0), minf(col.b * 1.6, 1.0))
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		l.double_sided = false
		l.shaded = false
		var face := f.r * s
		l.transform = Transform3D(Basis(Vector3.UP.cross(face), Vector3.UP, face), c + face * 0.075)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(l)


# ---------------------------------------------------------------- plaza and cathedral
func _build_plaza() -> void:
	ck = "K0_0"
	var e := GRID - ROAD_HALF
	var h := PIT_HOLE
	var cob := _b("cobble_fan")
	var y := WALK_TOP
	var col := Color(0.66, 0.6, 0.53)
	for r in [[-e, -e, e, -h], [-e, h, e, e], [-e, -h, -h, h], [h, -h, e, h]]:
		cob.quad(Vector3(r[0], y, r[3]), Vector3(r[0], y, r[1]), Vector3(r[2], y, r[1]), Vector3(r[2], y, r[3]), Vector3.UP, col)
	# kerb all round
	var k := _b("stone")
	var kc := Color(0.62, 0.6, 0.57)
	for s in [[Vector3(-e, 0, e), Vector3(e, 0, e), Vector3(0, 0, 1)], [Vector3(e, 0, -e), Vector3(-e, 0, -e), Vector3(0, 0, -1)],
			[Vector3(e, 0, e), Vector3(e, 0, -e), Vector3(1, 0, 0)], [Vector3(-e, 0, -e), Vector3(-e, 0, e), Vector3(-1, 0, 0)]]:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		k.quad(a, a + Vector3(0, y, 0), b + Vector3(0, y, 0), b, s[2], kc)
	# a ring of granite paving around the Undercroft
	var st := _b("stone")
	for s in 32:
		var a0 := TAU * s / 32.0
		var a1 := TAU * (s + 1) / 32.0
		var p := [Vector3(cos(a0) * PIT_R, y + 0.006, sin(a0) * PIT_R), Vector3(cos(a0) * 4.8, y + 0.006, sin(a0) * 4.8),
			Vector3(cos(a1) * 4.8, y + 0.006, sin(a1) * 4.8), Vector3(cos(a1) * PIT_R, y + 0.006, sin(a1) * PIT_R)]
		st.quad(p[0], p[1], p[2], p[3], Vector3.UP, Color(0.5, 0.48, 0.45))
	# benches facing the Undercroft
	var m := _b("metal")
	var wood := Color(0.24, 0.16, 0.1)
	for kk in 8:
		var a := kk * TAU / 8.0 + PI / 8.0
		var c := Vector3(cos(a) * 9.5, y, sin(a) * 9.5)
		var fwd := -Vector3(cos(a), 0, sin(a))
		var right := Vector3.UP.cross(fwd).normalized()
		var basis := Basis(right, Vector3.UP, fwd)
		box(m, c + Vector3(0, 0.45, 0), Vector3(1.8, 0.06, 0.45), wood, basis)
		box(m, c + Vector3(0, 0.75, 0) - fwd * 0.22, Vector3(1.8, 0.4, 0.05), wood, basis * Basis(Vector3.RIGHT, -0.2))
		for sx: float in [-0.8, 0.8]:
			box(m, c + right * sx + Vector3(0, 0.22, 0), Vector3(0.06, 0.45, 0.5), Color(0.04, 0.04, 0.04), basis)
	# palms by the cathedral (image 02), live oaks on the south side
	for sx: float in [-1.0, 1.0]:
		_palm(Vector3(sx * 12.5, y, -12.5))
		_tree(Vector3(sx * 12.5, y, 12.5))
	# a steaming grate and standing water on the flagstones (image 01)
	var grate := Vector3(7.2, y + 0.008, 6.4)
	box(_b("metal"), grate, Vector3(1.4, 0.02, 0.9), Color(0.05, 0.05, 0.05), Basis(Vector3.UP, 0.5))
	_steam(grate)
	for q in [[-5.5, 8.0, 1.6], [4.0, 10.5, 1.2], [-9.5, -3.0, 1.4], [8.5, -6.0, 1.0], [0.5, 12.5, 1.1], [-3.0, -10.0, 1.3]]:
		_puddle(Vector3(q[0], y + 0.009, q[1]), q[2])
	# lantern lamps around the square (these six carry real lights)
	for kk in range(6):
		var a := kk * TAU / 6.0 + 0.5
		var p := Vector3(cos(a) * 15.0, y, sin(a) * 15.0)
		_ornate_lamp(p)
		var l := OmniLight3D.new()
		l.position = p + Vector3(0, LANTERN_Y * 1.2, 0)
		l.omni_range = 13.0
		l.light_color = Color(1, 0.75, 0.45)
		add_child(l)
		lamps.append(l)
	# a Victorian post clock on the south-east corner (asset round 3 prop), outside the arena ring
	street_clock(Vector3(14.0, y, 15.0), -PI * 0.75)


## A cast-iron Victorian post clock (asset round 3 prop, 4 m, dials on both faces) at ground p.
func street_clock(p: Vector3, yaw: float) -> void:
	if place_glb("street_clock", 4.0, Transform3D(Basis(Vector3.UP, yaw), p), true, 110.0) != Vector3.ZERO:
		post_collider(p, 0.3, 3.0)


func _ornate_lamp(p: Vector3) -> void:
	_lantern_post(_b("metal"), _b("lamp"), p, 1.2)
	lamp_positions.append(p + Vector3(0, LANTERN_Y * 1.2, 0))
	halo_xfs.append(Transform3D(Basis().scaled(Vector3(1.2, 1.2, 1.2)), p + Vector3(0, LANTERN_Y * 1.2, 0)))
	_light_pool(p, 4.5)


## Cabbage palm: a leaning ringed trunk and a crown of drooping fronds (alpha cards).
func _palm(p: Vector3) -> void:
	var m := _b("metal")
	var bark := Color(0.32, 0.27, 0.22)
	var lean := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
	var prev := p
	var h := 8.5
	for k in 6:
		var t := (k + 1) / 6.0
		var q := p + Vector3(0, h * t, 0) + lean * t * t * 1.5
		cyl(m, prev, 0.26 - k * 0.02, 0.24 - k * 0.02, prev.distance_to(q), 6, bark * (0.9 + 0.1 * (k % 2)), false)
		prev = q
	var lv := _b("lace")
	var top := prev
	for k in 9:
		var a := k * TAU / 9.0 + rng.randf() * 0.3
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x) * 0.55
		var tip := top + d * 3.0 + Vector3(0, -1.6, 0)
		var midp := top + d * 1.6 + Vector3(0, 0.3, 0)
		lv.quad(top - side * 0.3, midp - side, midp + side, top + side * 0.3, Vector3.UP, Color(1.0, 1.0, 0.8), Vector2(0, 0.5), Vector2(1, 0.75))
		lv.quad(midp - side, tip - side * 0.4, tip + side * 0.4, midp + side, Vector3.UP, Color(1.0, 1.0, 0.8), Vector2(0, 0.75), Vector2(1, 1))
	var body := StaticBody3D.new()
	body.position = p
	collider_root.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.4
	sh.height = 3.0
	cs.shape = sh
	cs.position.y = 1.5
	body.add_child(cs)


## V6 (critic R2): the plaza's trees were flat black cards. Now a live oak hung with Spanish
## moss, from the same textured tree builder as the bayou cypress (one draw, plus a cheap
## shadow proxy), each one turned and scaled a little differently.
var _oak_mesh: ArrayMesh
var _oak_shadow: ArrayMesh


func _tree(p: Vector3) -> void:
	const Trees = preload("res://scripts/map/trees.gd")
	if _oak_mesh == null:
		_oak_mesh = Trees.cypress_mesh(9.5, 811)
		_oak_shadow = Trees.shadow_mesh(9.5, 4.0, 4.5)
	var s := rng.randf_range(0.95, 1.12)
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.15, s, s * 1.15)), p - Vector3(0, 0.1, 0))
	var oak := MeshInstance3D.new()
	oak.name = "PlazaOak"
	oak.mesh = _oak_mesh
	oak.transform = xf
	oak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	oak.visibility_range_end = 140.0
	add_child(oak)
	var sh_mi := MeshInstance3D.new()
	sh_mi.mesh = _oak_shadow
	sh_mi.transform = xf
	sh_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	sh_mi.visibility_range_end = 60.0
	add_child(sh_mi)
	var body := StaticBody3D.new()
	body.position = p
	collider_root.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 1.0 * s # the flared buttress roots of the trunk (QA2: colliders match the mesh)
	sh.height = 3.0
	cs.shape = sh
	cs.position.y = 1.5
	body.add_child(cs)


## Leafy clump: crossed alpha-scissor cards.
func _foliage(bt: Batch, c: Vector3, r: float) -> void:
	for k in 3:
		var a := k * PI / 3.0 + rng.randf() * 0.4
		var right := Vector3(cos(a), 0, sin(a)) * r
		var up := Vector3(0, r * 0.75, 0)
		var nrm := Vector3(-sin(a), 0, cos(a))
		bt.quad(c - right - up, c - right + up, c + right + up, c + right - up, nrm, Color.WHITE, Vector2(0, 0), Vector2(1, 1))
	var right := Vector3(r, 0, 0)
	var fwd := Vector3(0, 0, r)
	bt.quad(c - right + fwd, c - right - fwd, c + right - fwd, c + right + fwd, Vector3.UP, Color.WHITE)


## St. Jerome Cathedral: a Gothic west front facing the plaza. Its two towers fill
## the blocks either side of the x = 0 street, which passes under the great arch.
func _build_cathedral() -> void:
	ck = "M"
	var st := _b("stone")
	var sc := Color(0.8, 0.75, 0.66)
	var dark := Color(0.5, 0.47, 0.42)
	var zf := -GRID - FACADE # facade plane, z = -26
	var zb := zf - 2.0 * LOT # back, z = -34
	var tower_h := 27.0
	var body := StaticBody3D.new()
	body.name = "Cathedral"
	collider_root.add_child(body)
	for sx: float in [-1.0, 1.0]:
		var x0 := sx * FACADE
		var x1 := sx * (FACADE + 2.0 * LOT)
		var lo := minf(x0, x1)
		var hi := maxf(x0, x1)
		var cx := (lo + hi) * 0.5
		# tower body, set back in stages
		box(st, Vector3(cx, tower_h * 0.5, (zf + zb) * 0.5), Vector3(hi - lo - 0.6, tower_h, zf - zb - 0.6), sc, Basis.IDENTITY, 8)
		box(st, Vector3(cx, tower_h + 2.5, (zf + zb) * 0.5), Vector3(hi - lo - 2.2, 5.0, zf - zb - 2.2), sc, Basis.IDENTITY, 8)
		# corner buttresses, stepped
		for bx in [lo, hi]:
			for bz in [zf, zb]:
				for stage in 3:
					var bh := tower_h * (1.0 - stage * 0.28)
					var bw := 1.3 - stage * 0.3
					box(st, Vector3(bx, bh * 0.5, bz), Vector3(bw, bh, bw), sc * Color(0.95, 0.95, 0.95), Basis.IDENTITY, 8)
				# pinnacle
				cyl(st, Vector3(bx, tower_h, bz), 0.5, 0.0, 3.2, 4, sc)
		# octagonal spire ringed by four pinnacles, belfry lancets below
		var sp := Vector3(cx, tower_h + 5.0, (zf + zb) * 0.5)
		cyl(st, sp, 2.7, 0.0, 16.0, 8, Color(0.46, 0.45, 0.45))
		for k in 4:
			var a := k * PI * 0.5 + PI * 0.25
			var pp := sp + Vector3(cos(a), 0, sin(a)) * 2.9
			cyl(st, pp - Vector3(0, 0.6, 0), 0.4, 0.4, 1.4, 4, sc, false, Basis(Vector3.UP, PI * 0.25))
			cyl(st, pp + Vector3(0, 0.8, 0), 0.45, 0.0, 4.0, 4, sc, true, Basis(Vector3.UP, PI * 0.25))
		var bf := Facade.new()
		bf.o = Vector3(lo + 1.1, 0, zf - 1.1)
		bf.r = Vector3(1, 0, 0)
		bf.n = Vector3(0, 0, 1)
		bf.w = hi - lo - 2.2
		for k in 2:
			var bu := bf.w * (0.3 + 0.4 * k)
			fq(_b("trim"), bf, bu - 0.45, tower_h + 0.6, bu + 0.45, tower_h + 3.6, 0.02, Color(0.05, 0.05, 0.06))
			_pointed_arch(st, bf, bu, 0.55, tower_h + 3.6, 0.18, 0.12, sc, 0.2)
		cyl(_b("metal"), sp + Vector3(0, 16.0, 0), 0.05, 0.05, 1.6, 4, Color(0.1, 0.1, 0.1))
		box(_b("metal"), sp + Vector3(0, 17.1, 0), Vector3(0.8, 0.06, 0.06), Color(0.1, 0.1, 0.1))
		# portal: recessed pointed-arch door with stepped archivolts
		var f := Facade.new()
		f.o = Vector3(lo + 0.3, 0, zf - 0.3)
		f.r = Vector3(1, 0, 0)
		f.n = Vector3(0, 0, 1)
		f.w = hi - lo - 0.6
		var pc := f.w * 0.5
		# a gabled porch with stepped archivolts, statues and broad steps up to the doors
		var PD := 1.4
		var pw := 2.0
		var pcol := sc * Color(0.9, 0.9, 0.9)
		fbox(st, f, pc - pw - 0.7, 0.0, pc - pw, 5.6, 0.0, PD, pcol, false)
		fbox(st, f, pc + pw, 0.0, pc + pw + 0.7, 5.6, 0.0, PD, pcol, false)
		for ring in 3:
			_pointed_arch(st, f, pc, pw - 0.1 - ring * 0.3, 3.4, 0.28, PD - ring * 0.4, pcol, 0.4)
		for i in 3:
			fbox(st, f, pc - pw, 0.0, pc + pw, 0.15 * (i + 1), 0.0, PD - i * 0.45, dark, false)
		fq(_b("trim"), f, pc - 1.0, 0.45, pc + 1.0, 3.3, -0.1, Color(0.16, 0.09, 0.06))
		_lancet(f, pc, 4.4, 1.0, 0.5, 1.1) # glow in the tympanum
		var gab_l := f.p(pc - pw - 0.8, 5.6, PD)
		var gab_r := f.p(pc + pw + 0.8, 5.6, PD)
		var gab_t := f.p(pc, 9.6, PD)
		st.tri(gab_l, gab_t, gab_r, f.n, pcol)
		_b("concrete").quad(gab_l + Vector3(0, 0, -PD), gab_t + Vector3(0, 0, -PD), gab_t, gab_l, (f.r * -4.0 + Vector3.UP * 2.8).normalized(), Color(0.3, 0.3, 0.33))
		_b("concrete").quad(gab_r, gab_t, gab_t + Vector3(0, 0, -PD), gab_r + Vector3(0, 0, -PD), (f.r * 4.0 + Vector3.UP * 2.8).normalized(), Color(0.3, 0.3, 0.33))
		cyl(st, gab_t, 0.25, 0.0, 1.4, 4, pcol)
		for sd: float in [-1.0, 1.0]:
			cyl(st, f.p(pc + sd * (pw + 0.35), 5.6, PD - 0.35), 0.32, 0.0, 2.2, 4, pcol)
			# jamb saints inside the porch and one on each pier front
			for k in 2:
				_statue(st, f.p(pc + sd * (pw - 0.25), 0.45 + 0.15 * (1 - k), 0.35 + k * 0.6), 1.55, sc * Color(0.85, 0.85, 0.82))
			box(st, f.p(pc + sd * (pw + 0.35), 2.35, PD + 0.12), Vector3(0.5, 0.15, 0.3), pcol)
			_statue(st, f.p(pc + sd * (pw + 0.35), 2.42, PD + 0.12), 1.5, sc * Color(0.85, 0.85, 0.82))
		for k in 5:
			_statue(st, f.p(pc - 0.9 + k * 0.45, 3.35, 0.08), 0.85, sc * Color(0.8, 0.8, 0.78))
		var porch := CollisionShape3D.new()
		var porch_shape := BoxShape3D.new()
		porch_shape.size = Vector3(2.0 * pw + 1.4, 5.6, PD - 0.3)
		porch.shape = porch_shape
		porch.position = Vector3(cx, 2.8, zf + (PD - 0.3) * 0.5)
		body.add_child(porch)
		# tall lancet windows up the tower
		for row in 2:
			var y := 11.0 + row * 7.5
			for k in 2:
				_lancet(f, pc + (k - 0.5) * 2.4, y, 1.15, 5.0, 1.5)
		# string courses
		for y: float in [10.2, 18.0, 25.5]:
			fbox(st, f, -0.3, y, f.w + 0.3, y + 0.35, 0.0, 0.25, dark)
		lots.append(Rect2(lo, zb, hi - lo, zf - zb))
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(hi - lo, tower_h, zf - zb)
		cs.shape = shape
		cs.position = Vector3(cx, tower_h * 0.5, (zf + zb) * 0.5)
		body.add_child(cs)
	# warm light from the plaza lamps washing the west front
	for gx: float in [-10.0, 0.0, 10.0]:
		_wall_glow(Vector3(gx, 0.0, zf + (1.2 if gx != 0.0 else 0.1)), Vector3(0, 0, 1), 9.0, 11.0)
	# central screen over the street: great arch, rose window, gable
	var f := Facade.new()
	f.o = Vector3(-FACADE, 0, zf)
	f.r = Vector3(1, 0, 0)
	f.n = Vector3(0, 0, 1)
	f.w = 2.0 * FACADE
	var arch_y := 7.0
	var top := 22.0
	# solid wall above the arch, stepped back from the street opening
	fbox(st, f, 0.0, arch_y + 2.4, f.w, top, -1.2, 0.0, sc, false)
	for ring in 3:
		_pointed_arch(st, f, f.w * 0.5, 5.6 - ring * 0.35, arch_y, 0.45, 0.25 - ring * 0.18, sc * Color(0.92, 0.92, 0.92), 1.2 + ring * 0.2)
	# underside of the vault
	st.quad(f.p(0, arch_y + 2.4, -8.0), f.p(0, arch_y + 2.4, 0.0), f.p(f.w, arch_y + 2.4, 0.0), f.p(f.w, arch_y + 2.4, -8.0), Vector3.DOWN, dark)
	# gable
	st.tri(f.p(-0.5, top, 0.0), f.p(f.w * 0.5, top + 7.0, 0.0), f.p(f.w + 0.5, top, 0.0), Vector3(0, 0, 1), sc)
	st.tri(f.p(-0.5, top, -8.0), f.p(f.w * 0.5, top + 7.0, -8.0), f.p(f.w + 0.5, top, -8.0), Vector3(0, 0, -1), sc)
	var roof := Color(0.3, 0.3, 0.33)
	var c := _b("concrete")
	var ridge_l := f.p(-0.5, top, 0.0)
	var apex := f.p(f.w * 0.5, top + 7.0, 0.0)
	var ridge_r := f.p(f.w + 0.5, top, 0.0)
	var back := Vector3(0, 0, -8.0)
	c.quad(ridge_l + back, apex + back, apex, ridge_l, (Vector3(-7.0, 6.5, 0)).normalized(), roof)
	c.quad(ridge_r, apex, apex + back, ridge_r + back, (Vector3(7.0, 6.5, 0)).normalized(), roof)
	fbox(st, f, 0.0, arch_y + 2.4, f.w, top, -8.0, -7.0, sc, false)
	# great rose window: leaded glass disc with a carved stone rim
	var rose := f.p(f.w * 0.5, 15.6, 0.06)
	var sg := _b("stained")
	var RR := 4.3
	for s in 32:
		var a0 := TAU * s / 32.0
		var a1 := TAU * (s + 1) / 32.0
		var p0 := rose + Vector3(cos(a0), sin(a0), 0) * RR
		var p1 := rose + Vector3(cos(a1), sin(a1), 0) * RR
		# atlas left half: u 0..0.5, v 0..1 (image y runs down)
		sg.tri(rose, p0, p1, Vector3(0, 0, 1), Color.WHITE, Vector2(0.25, 0.5),
			Vector2(0.25 + cos(a0) * 0.245, 0.5 - sin(a0) * 0.49), Vector2(0.25 + cos(a1) * 0.245, 0.5 - sin(a1) * 0.49))
		if s % 2 == 0:
			var q0 := rose + Vector3(cos(a0), sin(a0), 0) * (RR + 0.25) + Vector3(0, 0, 0.12)
			var q1 := rose + Vector3(cos(TAU * (s + 2) / 32.0), sin(TAU * (s + 2) / 32.0), 0) * (RR + 0.25) + Vector3(0, 0, 0.12)
			beam(st, q0, q1, 0.55, 0.35, sc, Vector3(0, 0, 1))
	# a square frame with carved spandrels around the rose
	fbox(st, f, f.w * 0.5 - RR - 0.9, 15.6 - RR - 0.9, f.w * 0.5 + RR + 0.9, 15.6 - RR - 0.5, 0.0, 0.3, sc, false)
	fbox(st, f, f.w * 0.5 - RR - 0.9, 15.6 + RR + 0.5, f.w * 0.5 + RR + 0.9, 15.6 + RR + 0.9, 0.0, 0.3, sc, false)
	# pinnacled gable crown over the screen
	for sd: float in [-1.0, 1.0]:
		cyl(st, f.p(f.w * 0.5 + sd * (f.w * 0.5 + 0.2), top, 0.0), 0.45, 0.0, 4.5, 4, sc)
	cyl(st, f.p(f.w * 0.5, top + 7.0, -0.3), 0.35, 0.0, 2.5, 4, sc)


## Simple carved saint: robed body, shoulders and head.
static func _statue(bt: Batch, base: Vector3, h: float, col: Color) -> void:
	cyl(bt, base, 0.2 * h / 1.5, 0.13 * h / 1.5, h * 0.78, 6, col)
	cyl(bt, base + Vector3(0, h * 0.78, 0), 0.13 * h / 1.5, 0.08 * h / 1.5, h * 0.08, 6, col)
	cyl(bt, base + Vector3(0, h * 0.86, 0), 0.075 * h / 1.5, 0.06 * h / 1.5, h * 0.14, 5, col)


## Pointed (two-centred) arch of voussoir blocks springing at y, half-width hw.
func _pointed_arch(bt: Batch, f: Facade, cu: float, hw: float, y: float, thick: float, d: float, col: Color, depth := 0.3) -> void:
	var r := hw * 1.6
	var segs := 7
	for side: float in [-1.0, 1.0]:
		var centre_u := cu - side * (r - hw)
		var a_end := acos((r - hw) / r)
		for s in segs:
			var a0 := a_end * s / segs
			var a1 := a_end * (s + 1) / segs
			var p0 := Vector2(centre_u + side * r * cos(a0), y + r * sin(a0))
			var p1 := Vector2(centre_u + side * r * cos(a1), y + r * sin(a1))
			var c3 := f.p((p0.x + p1.x) * 0.5, (p0.y + p1.y) * 0.5, d - depth * 0.5)
			var dir := f.p(p1.x, p1.y, 0) - f.p(p0.x, p0.y, 0)
			var z := dir.normalized()
			var x := f.n.cross(z).normalized()
			box(bt, c3, Vector3(thick, dir.length() + 0.04, depth), col, Basis(x, z, f.n))
	# jambs
	for side: float in [-1.0, 1.0]:
		fbox(bt, f, cu + side * hw - thick * 0.5, 0.0, cu + side * hw + thick * 0.5, y, d - depth, d, col, false)


## Lancet window: leaded glass with a pointed head, glowing amber at night.
func _lancet(f: Facade, cu: float, y: float, w: float, h: float, head: float) -> void:
	var sg := _b("stained")
	var cell := rng.randi() % 2
	var ua := 0.5 + cell * 0.25 + 0.003
	var ub := 0.75 + cell * 0.25 - 0.003
	var vh := head / (h + head)
	var u0 := cu - w * 0.5
	var u1 := cu + w * 0.5
	sg.quad(f.p(u0, y, 0.04), f.p(u0, y + h, 0.04), f.p(u1, y + h, 0.04), f.p(u1, y, 0.04), f.n, Color.WHITE, Vector2(ua, vh), Vector2(ub, 0.99))
	sg.tri(f.p(u0, y + h, 0.04), f.p(cu, y + h + head, 0.04), f.p(u1, y + h, 0.04), f.n, Color.WHITE, Vector2(ua, vh), Vector2((ua + ub) * 0.5, 0.0), Vector2(ub, vh))
	var st := _b("stone")
	var sc := Color(0.7, 0.68, 0.64)
	fbox(st, f, cu - 0.05, y, cu + 0.05, y + h, 0.04, 0.12, sc, false)
	beam(st, f.p(u0 - 0.1, y + h, 0.1), f.p(cu, y + h + head + 0.1, 0.1), 0.18, 0.16, sc, f.n)
	beam(st, f.p(u1 + 0.1, y + h, 0.1), f.p(cu, y + h + head + 0.1, 0.1), 0.18, 0.16, sc, f.n)
	fbox(st, f, u0 - 0.15, y, u0, y + h, 0.0, 0.16, sc, false)
	fbox(st, f, u1, y, u1 + 0.15, y + h, 0.0, 0.16, sc, false)
	fbox(st, f, u0 - 0.2, y - 0.15, u1 + 0.2, y, 0.0, 0.2, sc, false)


# ---------------------------------------------------------------- streets
func _build_streets() -> void:
	var yellow := Color(0.85, 0.65, 0.15)
	var white := Color(0.85, 0.85, 0.82)
	var plaza := GRID - ROAD_HALF
	# every edge of a street cell is a 20 m street segment: [line coordinate, segment start, axis]
	var segs := {}
	for cell: Vector2i in street_cells.keys():
		segs[Vector3i(cell.x, cell.y, 0)] = true
		segs[Vector3i(cell.x + 1, cell.y, 0)] = true
		segs[Vector3i(cell.y, cell.x, 1)] = true
		segs[Vector3i(cell.y + 1, cell.x, 1)] = true
	var keys := segs.keys()
	keys.sort()
	for sk: Vector3i in keys:
		var a := sk.x
		var b := sk.y
		var axis := sk.z
		if filled_segs.has(sk):
			continue # built over by a long block
		var s := a * GRID
		if true:
			var g0 := b * GRID
			if true:
				var mid := g0 + GRID * 0.5
				var px := s if axis == 0 else mid
				var pz := mid if axis == 0 else s
				if absf(px) < plaza and absf(pz) < plaza:
					continue
				ck = _chunk_of(px, pz)
				var paint := _b("paint")
				var along := Vector3(0, 0, 1) if axis == 0 else Vector3(1, 0, 0)
				var across := Vector3(1, 0, 0) if axis == 0 else Vector3(0, 0, 1)
				var base := Vector3(px, 0.012, pz) - along * GRID * 0.5
				# double yellow centre line between the crosswalks
				for off: float in [-0.12, 0.12]:
					_strip(paint, base + across * off + along * 6.6, base + across * off + along * (GRID - 6.6), 0.1, yellow)
				# cobbled crosswalks (pale bands of granite setts, image 12) and stop lines
				var setts := _b("stone")
				for end: float in [0.0, 1.0]:
					var e0 := base + along * (GRID * end)
					var sgn := 1.0 if end == 0.0 else -1.0
					var c0 := e0 + along * sgn * 3.9 + Vector3(0, 0.002, 0)
					var c1 := e0 + along * sgn * 6.1 + Vector3(0, 0.002, 0)
					_strip(setts, c0, c1, ROAD_HALF * 2.0, Color(0.42, 0.41, 0.39))
					var k := -ROAD_HALF + 0.3
					while k < ROAD_HALF - 0.3:
						_strip(setts, c0 + across * (k + 0.25) + Vector3(0, 0.003, 0), c1 + across * (k + 0.25) + Vector3(0, 0.003, 0), 0.5, Color(1.0, 0.98, 0.94))
						k += 1.0
					var stop_side := -1.0 if end == 0.0 else 1.0
					# worn stop line (a clean white bar read as a floating quad in daylight)
					_strip(paint, e0 + along * sgn * 6.4 + across * stop_side * 0.2, e0 + along * sgn * 6.4 + across * stop_side * (ROAD_HALF - 0.2), 0.0, white * Color(0.55, 0.55, 0.55), 0.22)
				# manhole, sometimes steaming
				if rng.randf() < 0.55:
					var mp := Vector3(px, 0.0, pz) + along * rng.randf_range(-2.0, 2.0) + across * rng.randf_range(-1.5, 1.5)
					cyl(_b("metal"), mp, 0.42, 0.42, 0.018, 12, Color(0.13, 0.12, 0.11))
					if rng.randf() < 0.12:
						_steam(mp)
				# puddles near the kerbs
				for q in rng.randi_range(0, 3):
					var side := -1.0 if rng.randf() < 0.5 else 1.0
					var pp := Vector3(px, 0.016, pz) + along * rng.randf_range(-8.0, 8.0) + across * side * rng.randf_range(1.0, ROAD_HALF - 0.4)
					_puddle(pp, rng.randf_range(0.8, 2.2))
				# parked cars, one per kerb at most, clear of the corners
				for side: float in [-1.0, 1.0]:
					if rng.randf() < 0.42:
						var cp := Vector3(px, 0.0, pz) + across * side * 2.85 + along * rng.randf_range(-1.2, 1.2)
						var yaw := atan2(along.x, along.z) + (PI if side < 0 else 0.0)
						_car(cp, yaw)
				# street lamps on one kerb
				if true:
					var lside := 1.0 if (a + b) % 2 == 0 else -1.0
					var lp := Vector3(px, WALK_TOP, pz) + across * lside * (ROAD_HALF + 0.45)
					_add_prop("lamp", Transform3D(Basis(Vector3.UP, atan2(-across.x * lside, -across.z * lside)), lp), Color.WHITE)
					lamp_positions.append(lp + Vector3(0, LANTERN_Y, 0))
					halo_xfs.append(Transform3D(Basis(), lp + Vector3(0, LANTERN_Y, 0)))
					_light_pool(lp - across * lside * 0.6, 4.4)
					# the lantern washes the facade behind it
					_wall_glow(Vector3(px, 0.0, pz) + across * lside * (FACADE - 0.04), -across * lside, 7.0, 7.5)
				# telephone poles and sagging wires on the outer, older streets
				if (absf(s) == 60.0 and absf(mid) < 60.0 and px < 100.0) or (a == 0 and axis == 0 and mid > 20.0 and mid < 70.0):
					_pole_span(Vector3(px, 0.0, pz) - along * GRID * 0.5 - across * (ROAD_HALF + 0.4), along)


## Flat painted strip from a to b, width w (or depth along the strip `len_w`).
func _strip(bt: Batch, a: Vector3, b: Vector3, w: float, col: Color, len_w := 0.0) -> void:
	var dir := (b - a)
	var side := Vector3.UP.cross(dir.normalized()) * (w * 0.5)
	if len_w > 0.0:
		side = dir.normalized() * 0.0
		var perp := Vector3.UP.cross(dir.normalized())
		var o := perp * len_w * 0.5
		bt.quad(a - o, a + o, b + o, b - o, Vector3.UP, col)
		return
	bt.quad(a - side, a + side, b + side, b - side, Vector3.UP, col)


func _puddle(p: Vector3, r: float) -> void:
	var bt := _b("puddle")
	var a := rng.randf() * TAU
	var right := Vector3(cos(a), 0, sin(a)) * r
	var fwd := Vector3(-sin(a), 0, cos(a)) * r * rng.randf_range(0.5, 0.9)
	var u := Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15))
	bt.quad(p - right - fwd, p - right + fwd, p + right + fwd, p + right - fwd, Vector3.UP, Color.WHITE, u, u + Vector2.ONE)


## Additive splash of lamplight on a wall: centre on the wall at ground level, n = facing.
func _wall_glow(base: Vector3, n: Vector3, w: float, h: float) -> void:
	var bt := _b("pool")
	var r := Vector3.UP.cross(n) * w * 0.5
	var c := base + Vector3(0, 3.4, 0)
	var up := Vector3(0, h * 0.5, 0)
	bt.quad(c - r - up, c - r + up, c + r + up, c + r - up, n, Color.WHITE)


func _light_pool(p: Vector3, r: float) -> void:
	var bt := _b("pool")
	var y := Vector3(0, WALK_TOP + 0.012, 0)
	bt.quad(p + y + Vector3(-r, 0, r), p + y + Vector3(-r, 0, -r), p + y + Vector3(r, 0, -r), p + y + Vector3(r, 0, r), Vector3.UP, Color.WHITE)


func _pole_span(p: Vector3, along: Vector3) -> void:
	var m := _b("metal")
	var wood := Color(0.22, 0.17, 0.12)
	var h := 9.0
	cyl(m, p, 0.16, 0.12, h, 6, wood, false)
	var across := Vector3.UP.cross(along)
	box(m, p + Vector3(0, h - 0.6, 0), Vector3(0.12, 0.12, 2.2), wood, Basis(along, Vector3.UP, across).orthonormalized())
	cyl(m, p + Vector3(0, h - 1.6, 0) + across * 0.25, 0.22, 0.22, 0.7, 8, Color(0.3, 0.3, 0.32))
	var q := p + along * GRID
	for off: float in [-0.9, 0.0, 0.9]:
		var a := p + Vector3(0, h - 0.55, 0) + across * off
		var b := q + Vector3(0, h - 0.55, 0) + across * off
		var sag := 0.7 + absf(off) * 0.2
		var prev := a
		for s in range(1, 9):
			var t := s / 8.0
			var pt := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
			beam(m, prev, pt, 0.025, 0.025, Color(0.02, 0.02, 0.02))
			prev = pt


func _steam(p: Vector3) -> void:
	var ps := CPUParticles3D.new()
	ps.position = p + Vector3(0, 0.05, 0)
	ps.amount = 10
	ps.lifetime = 3.5
	ps.preprocess = 3.5
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = 0.3
	ps.direction = Vector3.UP
	ps.spread = 12.0
	ps.gravity = Vector3(0.15, 0.25, 0)
	ps.initial_velocity_min = 0.6
	ps.initial_velocity_max = 1.0
	ps.scale_amount_min = 0.8
	ps.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 2.4))
	ps.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.8, 0.82, 0.0))
	grad.set_color(1, Color(0.8, 0.8, 0.82, 0.0))
	grad.add_point(0.15, Color(0.8, 0.8, 0.82, 0.22))
	ps.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _steam_tex()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	q.material = mat
	ps.mesh = q
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)


var _steam_texture: ImageTexture
func _steam_tex() -> ImageTexture:
	if _steam_texture == null:
		_steam_texture = _blob_texture(false)
	return _steam_texture


# ---------------------------------------------------------------- backdrop
## Visual-only skyline beyond the boundary walls, so the city doesn't just end.
func _build_backdrop() -> void:
	ck = "F"
	var bt := _b("far")
	var roof := _b("concrete")
	# the Velvet Mile's back street: a row of solid frontages past the east wall
	for j in range(Layout.VM_J[0], Layout.VM_J[1]):
		var cx := 230.0
		var cz := j * GRID + GRID * 0.5
		_slab(cx - GRID * 0.5 + ROAD_HALF, cz - GRID * 0.5 + ROAD_HALF, cx + GRID * 0.5, cz + GRID * 0.5 - ROAD_HALF,
			"sidewalk", Color(0.9, 0.9, 0.9), Color(0.55, 0.54, 0.52))
		_far_box(bt, roof, Rect2(226.0, cz - LOT, 20.0, 2.0 * LOT), rng.randf_range(16.0, 34.0))
	# the far bank across the river (west and south) and the city beyond the east wall
	for k in 26:
		var z := -230.0 + k * 19.0
		_far_box(bt, roof, Rect2(-300.0 - rng.randf_range(0.0, 30.0), z, rng.randf_range(14.0, 26.0), rng.randf_range(12.0, 18.0)), rng.randf_range(10.0, 40.0))
	for k in 24:
		var x := -230.0 + k * 20.0
		_far_box(bt, roof, Rect2(x, 280.0 + rng.randf_range(0.0, 30.0), rng.randf_range(12.0, 18.0), rng.randf_range(14.0, 24.0)), rng.randf_range(10.0, 34.0))
	for k in 12:
		var z := -40.0 + k * 22.0
		_far_box(bt, roof, Rect2(250.0 + rng.randf_range(0.0, 20.0), z, rng.randf_range(14.0, 22.0), rng.randf_range(12.0, 18.0)), rng.randf_range(24.0, 60.0))


func _far_box(bt: Batch, roof: Batch, r: Rect2, h: float) -> void:
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var uo := Vector2(rng.randi_range(0, 7) / 8.0, rng.randi_range(0, 7) / 8.0)
	var s := 1.0 / 25.6
	var tint := Color(1, 1, 1).lerp(Color(0.8, 0.75, 0.7), rng.randf())
	bt.quad(Vector3(x0, 0, z1), Vector3(x0, h, z1), Vector3(x1, h, z1), Vector3(x1, 0, z1), Vector3(0, 0, 1), tint, uo, uo + Vector2((x1 - x0) * s, h * s))
	bt.quad(Vector3(x1, 0, z0), Vector3(x1, h, z0), Vector3(x0, h, z0), Vector3(x0, 0, z0), Vector3(0, 0, -1), tint, uo, uo + Vector2((x1 - x0) * s, h * s))
	bt.quad(Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x1, h, z0), Vector3(x1, 0, z0), Vector3(1, 0, 0), tint, uo, uo + Vector2((z1 - z0) * s, h * s))
	bt.quad(Vector3(x0, 0, z0), Vector3(x0, h, z0), Vector3(x0, h, z1), Vector3(x0, 0, z1), Vector3(-1, 0, 0), tint, uo, uo + Vector2((z1 - z0) * s, h * s))
	roof.quad(Vector3(x0, h, z1), Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3.UP, Color(0.2, 0.2, 0.2))


# ---------------------------------------------------------------- props (MultiMesh)
func _add_prop(kind: String, xf: Transform3D, col: Color) -> void:
	if not props.has(kind):
		props[kind] = []
		prop_cols[kind] = []
	props[kind].append(xf)
	prop_cols[kind].append(col)


const CAR_COLS := [Color(0.5, 0.05, 0.05), Color(0.08, 0.1, 0.16), Color(0.75, 0.75, 0.72), Color(0.05, 0.05, 0.05),
	Color(0.18, 0.25, 0.2), Color(0.35, 0.33, 0.3), Color(0.6, 0.5, 0.3), Color(0.15, 0.2, 0.35)]


func _car(p: Vector3, yaw: float) -> void:
	var van := rng.randf() < 0.25
	var xf := Transform3D(Basis(Vector3.UP, yaw), p)
	_add_prop("van" if van else "sedan", xf, CAR_COLS[rng.randi() % CAR_COLS.size()])
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.8, 1.4, 4.6) if not van else Vector3(1.95, 2.0, 4.9)
	cs.shape = sh
	cs.transform = xf.translated_local(Vector3(0, sh.size.y * 0.5, 0))
	car_bodies.add_child(cs)


## Street furniture along the sidewalks: hydrants, newspaper boxes, dumpsters, trash.
func _sidewalk_props() -> void:
	for bc: Vector2 in block_cells:
		var cx := bc.x
		var cz := bc.y
		if true:
			for side in 4:
				if side < 2 and (int(inner_sides.get(bc, 0)) & (1 << side)) != 0:
					continue # that side is the inside of a long block
				var n: Vector3 = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)][side]
				var r := Vector3.UP.cross(n)
				var face := Vector3(cx, WALK_TOP, cz) + n * LOT
				var kerb := Vector3(cx, WALK_TOP, cz) + n * (GRID * 0.5 - ROAD_HALF - 0.35)
				var yaw_out := atan2(n.x, n.z)
				if rng.randf() < 0.3:
					_add_prop("hydrant", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), kerb + r * rng.randf_range(-4.5, 4.5)), Color.WHITE)
				if rng.randf() < 0.3:
					var at := kerb + r * (rng.randf_range(3.0, 5.0) * (1.0 if rng.randf() < 0.5 else -1.0)) - n * 0.15
					for k in rng.randi_range(1, 3):
						var nc: Color = [Color(0.15, 0.3, 0.6), Color(0.7, 0.12, 0.1), Color(0.85, 0.7, 0.15), Color(0.2, 0.45, 0.25)][rng.randi() % 4]
						_add_prop("newsbox", Transform3D(Basis(Vector3.UP, yaw_out + rng.randf_range(-0.08, 0.08)), at + r * k * 0.5), nc)
				if rng.randf() < 0.35:
					var dp := face + n * 0.65 + r * rng.randf_range(-2.5, 2.5)
					var dc: Color = [Color(0.15, 0.3, 0.18), Color(0.12, 0.2, 0.35), Color(0.3, 0.3, 0.3)][rng.randi() % 3]
					_add_prop("dumpster", Transform3D(Basis(Vector3.UP, yaw_out + PI * 0.5 + rng.randf_range(-0.1, 0.1)), dp), dc)
					for k in rng.randi_range(2, 5):
						var tp := dp + r * rng.randf_range(1.0, 2.0) * (1.0 if k % 2 == 0 else -1.0) + n * rng.randf_range(-0.3, 0.4)
						_trash(tp)
				elif rng.randf() < 0.4:
					var tp0 := face + n * 0.45 + r * rng.randf_range(-3.0, 3.0)
					for k in rng.randi_range(1, 4):
						_trash(tp0 + r * rng.randf_range(-0.6, 0.6) + n * rng.randf_range(-0.1, 0.3))
				# sidewalk puddles
				if rng.randf() < 0.25:
					ck = _chunk_of(cx, cz)
					_puddle(face + n * rng.randf_range(0.8, 1.8) + r * rng.randf_range(-4.0, 4.0) + Vector3(0, 0.006, 0), rng.randf_range(0.5, 1.1))


func _trash(p: Vector3) -> void:
	var s := rng.randf_range(0.8, 1.25)
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.1), s))
	var g := rng.randf_range(0.6, 1.2)
	_add_prop("trash", Transform3D(b, p), Color(g, g, g))


func _build_props() -> void:
	_sidewalk_props()
	var paint := _flat_mat(0.3, 0.55)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.03, 0.035, 0.045)
	glass.roughness = 0.05
	glass.metallic = 0.4
	var rubber := _flat_mat(0.7)
	var prop := _flat_mat(0.5, 0.2)
	var bag := _flat_mat(0.25)
	for kind in props.keys():
		var meshes: Array = [] # [mesh, material, use_colors]
		match kind:
			"sedan", "van":
				var parts := _car_mesh(kind == "van")
				meshes = [[parts[0], paint, true], [parts[1], glass, false], [parts[2], rubber, false]]
			"lamp":
				var lp := _lamp_mesh()
				meshes = [[lp[0], M["metal"], false], [lp[1], lamp_mat, false]]
			"hydrant":
				meshes = [[_hydrant_mesh(), prop, false]]
			"newsbox":
				meshes = [[_newsbox_mesh(), prop, true]]
			"dumpster", "alley_dumpster":
				meshes = [[_dumpster_mesh(), prop, true]]
			"trash":
				meshes = [[_trash_mesh(), bag, true]]
		var xfs: Array = props[kind]
		var cols: Array = prop_cols[kind]
		# generated (GLB) models replace the procedural stand-ins where we have them
		var glb: Dictionary = PropsScript._load_prop(GLB_PROPS[kind]) if GLB_PROPS.has(kind) else {}
		if not glb.is_empty():
			# the generated models are dense (7k-27k triangles), so thin the small clutter
			var step: int = GLB_THIN.get(kind, 1)
			var kept: Array = []
			for k in range(0, xfs.size(), step):
				kept.append(xfs[k])
			_glb_multimeshes(kind, glb, kept)
			continue
		# bucketed into PROP_CELL cells so off-screen ones are culled, with a visibility range
		var cells := {}
		for k in xfs.size():
			var xf: Transform3D = xfs[k]
			var key := Vector2i(floori(xf.origin.x / PROP_CELL), floori(xf.origin.z / PROP_CELL))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(k)
		var big: bool = kind == "sedan" or kind == "van" or kind == "dumpster"
		for key in cells.keys():
			var idx: Array = cells[key]
			for entry in meshes:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = entry[2]
				mm.mesh = entry[0]
				mm.instance_count = idx.size()
				for k in idx.size():
					mm.set_instance_transform(k, xfs[idx[k]])
					if entry[2]:
						mm.set_instance_color(k, cols[idx[k]])
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "Props_%s_%d_%d" % [kind, key.x, key.y]
				mmi.multimesh = mm
				mmi.material_override = entry[1]
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if big and entry[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mmi.visibility_range_end = (100.0 if kind == "lamp" else 80.0) * (0.7 if web_tier else 1.0)
				WQ.tag_bounds(mmi, idx.map(func(i): return xfs[i]))
				add_child(mmi)
	# warm halos round every lantern: camera-facing quads in one MultiMesh
	if not halo_xfs.is_empty():
		var hm := MultiMesh.new()
		hm.transform_format = MultiMesh.TRANSFORM_3D
		var q := QuadMesh.new()
		q.size = Vector2(1.7, 1.7)
		hm.mesh = q
		hm.instance_count = halo_xfs.size()
		for k in halo_xfs.size():
			hm.set_instance_transform(k, halo_xfs[k])
		halo_mm = hm
		var hmi := MultiMeshInstance3D.new()
		hmi.name = "LanternHalos"
		hmi.multimesh = hm
		hmi.material_override = halo_mat
		hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hmi)


const PropsScript = preload("res://scripts/props.gd")
const GLB_PROPS := {"sedan": "sedan", "hydrant": "hydrant", "newsbox": "news_box", "dumpster": "dumpster", "trash": "trash_pile"}
const GLB_THIN := {"trash": 6, "newsbox": 3, "hydrant": 2, "dumpster": 2}
const PROP_CELL := 80.0 # instances are bucketed into quadrants so off-screen ones are culled (fewer draw calls than 40 m cells)


func _glb_multimeshes(kind: String, glb: Dictionary, xfs: Array) -> void:
	var cells := {}
	for xf: Transform3D in xfs:
		var key := Vector2i(floori(xf.origin.x / PROP_CELL), floori(xf.origin.z / PROP_CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(xf)
	var big: bool = kind == "sedan" or kind == "dumpster"
	var shuf := RandomNumberGenerator.new()
	shuf.seed = hash(kind)
	for key in cells.keys():
		var list: Array = cells[key]
		for k in range(list.size() - 1, 0, -1): # shuffled: the prop density setting thins a prefix
			var j := shuf.randi_range(0, k)
			var tmp = list[k]
			list[k] = list[j]
			list[j] = tmp
		for part in glb.meshes:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = list.size()
			for k in list.size():
				var xf: Transform3D = list[k]
				mm.set_instance_transform(k, Transform3D(xf.basis.orthonormalized(), xf.origin) * part[1])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Glb_%s_%d_%d" % [kind, key.x, key.y]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if big else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 55.0 if big else 40.0
			WQ.tag_bounds(mmi, list.map(func(xf): return Transform3D(xf.basis.orthonormalized(), xf.origin) * part[1]))
			add_child(mmi)
	print("city props: %d x %s (generated model)" % [xfs.size(), kind])


static func _mesh_of(bt: Batch) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bt.arrays())
	return mesh


## Returns [body, glass, rubber] meshes. Car faces +z; origin on the ground at its centre.
func _car_mesh(van: bool) -> Array:
	var body := Batch.new()
	var glass := Batch.new()
	var rub := Batch.new()
	var W := 1.78 if not van else 1.92
	var hw := W * 0.5
	var L := 4.5 if not van else 4.8
	var hl := L * 0.5
	var white := Color.WHITE
	if not van:
		# lower body with a gently tapered nose and tail
		hexa(body, [Vector3(-hw, 0.3, -hl), Vector3(hw, 0.3, -hl), Vector3(hw, 0.3, hl), Vector3(-hw, 0.3, hl),
			Vector3(-hw, 0.82, -hl + 0.1), Vector3(hw, 0.82, -hl + 0.1), Vector3(hw, 0.78, hl - 0.05), Vector3(-hw, 0.78, hl - 0.05)], white)
		# glasshouse
		var ch := 0.52
		hexa(glass, [Vector3(-hw + 0.06, 0.8, -1.25), Vector3(hw - 0.06, 0.8, -1.25), Vector3(hw - 0.06, 0.8, 1.05), Vector3(-hw + 0.06, 0.8, 1.05),
			Vector3(-hw + 0.2, 0.8 + ch, -0.75), Vector3(hw - 0.2, 0.8 + ch, -0.75), Vector3(hw - 0.2, 0.8 + ch, 0.35), Vector3(-hw + 0.2, 0.8 + ch, 0.35)], white)
		box(body, Vector3(0, 0.8 + ch + 0.02, -0.2), Vector3(W - 0.42, 0.05, 1.12), white)
		# pillars
		for sx: float in [-1.0, 1.0]:
			beam(body, Vector3(sx * (hw - 0.08), 0.8, 1.02), Vector3(sx * (hw - 0.21), 0.8 + ch, 0.33), 0.07, 0.07, white)
			beam(body, Vector3(sx * (hw - 0.08), 0.8, -1.22), Vector3(sx * (hw - 0.21), 0.8 + ch, -0.73), 0.07, 0.07, white)
			beam(body, Vector3(sx * (hw - 0.13), 0.8, -0.2), Vector3(sx * (hw - 0.2), 0.8 + ch, -0.2), 0.05, 0.05, white)
	else:
		hexa(body, [Vector3(-hw, 0.35, -hl), Vector3(hw, 0.35, -hl), Vector3(hw, 0.35, hl), Vector3(-hw, 0.35, hl),
			Vector3(-hw, 2.0, -hl), Vector3(hw, 2.0, -hl), Vector3(hw, 1.95, hl - 0.9), Vector3(-hw, 1.95, hl - 0.9)], white)
		hexa(body, [Vector3(-hw, 0.35, hl - 0.9), Vector3(hw, 0.35, hl - 0.9), Vector3(hw, 0.35, hl), Vector3(-hw, 0.35, hl),
			Vector3(-hw, 1.1, hl - 0.9), Vector3(hw, 1.1, hl - 0.9), Vector3(hw, 1.0, hl), Vector3(-hw, 1.0, hl)], white)
		# windscreen and cab side windows
		glass.quad(Vector3(-hw + 0.1, 1.15, hl - 0.86), Vector3(-hw + 0.1, 1.85, hl - 0.92), Vector3(hw - 0.1, 1.85, hl - 0.92), Vector3(hw - 0.1, 1.15, hl - 0.86),
			Vector3(0, 0.3, 1).normalized(), white)
		for sx: float in [-1.0, 1.0]:
			glass.quad(Vector3(sx * (hw + 0.005), 1.15, hl - 1.9), Vector3(sx * (hw + 0.005), 1.75, hl - 1.9), Vector3(sx * (hw + 0.005), 1.75, hl - 1.0), Vector3(sx * (hw + 0.005), 1.15, hl - 1.0),
				Vector3(sx, 0, 0), white)
	# wheels, bumpers, lights
	var dark := Color(0.04, 0.04, 0.04)
	var wb := hl - 0.8
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			cyl(rub, Vector3(sx * (hw - 0.12), 0.33, sz * wb), 0.33, 0.33, 0.24, 12, dark, true, Basis(Vector3(0, 1, 0), Vector3(sx, 0, 0), Vector3(0, 0, 1)))
			cyl(rub, Vector3(sx * (hw + 0.115), 0.33, sz * wb), 0.18, 0.18, 0.01, 8, Color(0.4, 0.4, 0.42), true, Basis(Vector3(0, 1, 0), Vector3(sx, 0, 0), Vector3(0, 0, 1)))
	box(rub, Vector3(0, 0.38, hl + 0.03), Vector3(W + 0.02, 0.18, 0.12), dark)
	box(rub, Vector3(0, 0.38, -hl - 0.03), Vector3(W + 0.02, 0.18, 0.12), dark)
	for sx: float in [-1.0, 1.0]:
		box(glass, Vector3(sx * (hw - 0.25), 0.68 if not van else 0.85, hl + 0.005), Vector3(0.35, 0.12, 0.02), Color.WHITE)
		box(rub, Vector3(sx * (hw - 0.22), 0.7 if not van else 1.2, -hl - 0.005), Vector3(0.3, 0.14, 0.02), Color(0.5, 0.03, 0.02))
	return [_mesh_of(body), _mesh_of(glass), _mesh_of(rub)]


## Gas lantern on a cast-iron post (images 01 and 12). Returns [post, lantern glass].
## Origin at the foot of the post; the flame sits LANTERN_Y up.
const LANTERN_Y := 3.7


func _lamp_mesh() -> Array:
	var post := Batch.new()
	var head := Batch.new()
	_lantern_post(post, head, Vector3.ZERO, 1.0)
	return [_mesh_of(post), _mesh_of(head)]


## Writes a lantern post into two batches; s scales the whole thing.
static func _lantern_post(post: Batch, head: Batch, p: Vector3, s: float) -> void:
	var c := Color(0.045, 0.05, 0.05)
	cyl(post, p, 0.2 * s, 0.17 * s, 0.35 * s, 6, c)
	cyl(post, p + Vector3(0, 0.35, 0) * s, 0.15 * s, 0.07 * s, 0.6 * s, 6, c, false)
	cyl(post, p + Vector3(0, 0.95, 0) * s, 0.065 * s, 0.05 * s, 2.15 * s, 6, c, false)
	# ladder rest and collar under the lantern
	box(post, p + Vector3(0, 2.75, 0) * s, Vector3(0.62, 0.04, 0.04) * s, c)
	cyl(post, p + Vector3(0, 3.1, 0) * s, 0.06 * s, 0.17 * s, 0.25 * s, 6, c)
	# lantern: tapered glass body with corner bars, a pagoda cap and a finial
	var y0 := 3.35 * s
	var y1 := 4.05 * s
	cyl(head, p + Vector3(0, y0, 0), 0.15 * s, 0.24 * s, y1 - y0, 4, Color.WHITE, true, Basis(Vector3.UP, PI * 0.25))
	for k in 4:
		var a := k * PI * 0.5
		var d := Vector3(cos(a), 0, sin(a))
		beam(post, p + Vector3(0, y0, 0) + d * 0.15 * s, p + Vector3(0, y1, 0) + d * 0.24 * s, 0.025 * s, 0.025 * s, c)
	cyl(post, p + Vector3(0, y0 - 0.06 * s, 0), 0.19 * s, 0.19 * s, 0.07 * s, 4, c, true, Basis(Vector3.UP, PI * 0.25))
	cyl(post, p + Vector3(0, y1, 0), 0.33 * s, 0.06 * s, 0.3 * s, 4, c, true, Basis(Vector3.UP, PI * 0.25))
	cyl(post, p + Vector3(0, y1 + 0.3 * s, 0), 0.05 * s, 0.0, 0.25 * s, 4, c)


func _hydrant_mesh() -> ArrayMesh:
	var bt := Batch.new()
	var red := Color(0.55, 0.08, 0.06)
	cyl(bt, Vector3.ZERO, 0.17, 0.17, 0.06, 10, red)
	cyl(bt, Vector3(0, 0.06, 0), 0.13, 0.12, 0.5, 10, red)
	cyl(bt, Vector3(0, 0.56, 0), 0.15, 0.15, 0.05, 10, red)
	cyl(bt, Vector3(0, 0.61, 0), 0.12, 0.03, 0.14, 10, red)
	for sx: float in [-1.0, 1.0]:
		cyl(bt, Vector3(sx * 0.1, 0.4, 0), 0.05, 0.05, 0.1, 6, Color(0.6, 0.55, 0.3), true, Basis(Vector3(0, sx, 0), Vector3(sx, 0, 0), Vector3(0, 0, 1)))
	cyl(bt, Vector3(0, 0.4, 0.1), 0.065, 0.065, 0.09, 6, Color(0.6, 0.55, 0.3), true, Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)))
	return _mesh_of(bt)


func _newsbox_mesh() -> ArrayMesh:
	var bt := Batch.new()
	box(bt, Vector3(0, 0.62, 0), Vector3(0.48, 0.62, 0.42), Color.WHITE)
	box(bt, Vector3(0, 0.95, 0), Vector3(0.5, 0.06, 0.44), Color(0.8, 0.8, 0.8))
	box(bt, Vector3(0, 0.7, 0.215), Vector3(0.38, 0.3, 0.01), Color(0.25, 0.25, 0.27))
	for sx: float in [-0.18, 0.18]:
		for sz: float in [-0.15, 0.15]:
			box(bt, Vector3(sx, 0.15, sz), Vector3(0.04, 0.3, 0.04), Color(0.2, 0.2, 0.2))
	return _mesh_of(bt)


func _dumpster_mesh() -> ArrayMesh:
	var bt := Batch.new()
	hexa(bt, [Vector3(-0.85, 0.15, -0.5), Vector3(0.85, 0.15, -0.5), Vector3(0.85, 0.15, 0.45), Vector3(-0.85, 0.15, 0.45),
		Vector3(-0.92, 1.2, -0.55), Vector3(0.92, 1.2, -0.55), Vector3(0.92, 1.2, 0.62), Vector3(-0.92, 1.2, 0.62)], Color.WHITE)
	for sx: float in [-0.46, 0.46]:
		box(bt, Vector3(sx, 1.26, 0.03), Vector3(0.9, 0.05, 1.2), Color(0.25, 0.25, 0.25), Basis(Vector3.RIGHT, 0.12))
	for sx: float in [-0.7, 0.7]:
		for sz: float in [-0.35, 0.35]:
			cyl(bt, Vector3(sx, 0.0, sz), 0.08, 0.08, 0.15, 6, Color(0.1, 0.1, 0.1))
	return _mesh_of(bt)


func _trash_mesh() -> ArrayMesh:
	var bt := Batch.new()
	var c := Color(0.05, 0.05, 0.055)
	var rings := 5
	var segs := 8
	var pts: Array = []
	for r in rings + 1:
		var ph := PI * r / rings
		var row: Array = []
		for s in segs:
			var th := TAU * s / segs
			var rad := 0.3 * sin(ph) * (1.0 + 0.12 * sin(th * 3.0 + r))
			row.append(Vector3(cos(th) * rad, 0.28 - cos(ph) * 0.28, sin(th) * rad))
		pts.append(row)
	for r in rings:
		for s in segs:
			var s1 := (s + 1) % segs
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r + 1][s]
			var d: Vector3 = pts[r + 1][s1]
			var e: Vector3 = pts[r][s1]
			var ctr := Vector3(0, 0.28, 0)
			bt.quad_sm(a, b, d, e, (a - ctr).normalized(), (b - ctr).normalized(), (d - ctr).normalized(), (e - ctr).normalized(), c)
	cyl(bt, Vector3(0, 0.54, 0), 0.05, 0.02, 0.12, 5, c)
	return _mesh_of(bt)


# ================================================================ map districts: materials and helpers
const WetMats = preload("res://scripts/wet_materials.gd")


func _make_map_materials() -> void:
	M["mud"] = WetMats._make(Color(0.085, 0.062, 0.042), 0.62, 0.45) # rutted wet dirt roads
	M["earth"] = WetMats._make(Color(0.04, 0.038, 0.03), 0.08, 0.4) # forest floor, cemetery gravel
	M["earth"].set_shader_parameter("damp_roughness", 0.7)
	M["dock"] = WetMats.concrete(Color(0.16, 0.155, 0.15)) # quay and tank-farm concrete
	# open water: near-black with a weak, glossy sheen (a full mirror reads as snow at grazing angles)
	M["water"] = Terrain.river_mat # the river: the terrain's water shader (moving normals, fresnel)
	M["swamp"] = Terrain.water_mat
	M["corrugated"] = _surface_mat(_corrugated_textures(), 2.0, 0.9)
	M["wood"] = _lib_mat("wood_planks", 2.0, _plank_textures, 2.0) # piers, boardwalks, porches
	M["pine"] = _surface_mat(_needle_textures(), 2.0)
	for k in ["corrugated", "wood", "pine"]:
		CASTS[k] = true
	var card := StandardMaterial3D.new()
	card.albedo_texture = _pine_card_texture()
	card.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	card.alpha_scissor_threshold = 0.5
	card.cull_mode = BaseMaterial3D.CULL_DISABLED
	card.roughness = 0.9
	card.vertex_color_use_as_albedo = true
	M["pine_card"] = card
	var moss := StandardMaterial3D.new()
	moss.albedo_texture = _moss_texture()
	moss.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	moss.alpha_scissor_threshold = 0.45
	moss.cull_mode = BaseMaterial3D.CULL_DISABLED
	moss.roughness = 0.85
	moss.vertex_color_use_as_albedo = true
	M["moss"] = moss
	var beacon := StandardMaterial3D.new()
	beacon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon.albedo_color = Color(1.0, 0.08, 0.05)
	beacon.vertex_color_use_as_albedo = true
	M["beacon"] = beacon # always-lit signal lamps (crane tops, the water tower), read through fog
	var pn := StandardMaterial3D.new()
	pn.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pn.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pn.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pn.albedo_texture = pool_mat.albedo_texture
	pn.albedo_color = Color(0.55, 0.04, 0.22)
	pn.disable_receive_shadows = true
	M["pool_neon"] = pn # magenta neon spill on wet ground and walls (the Velvet Mile)
	var sodium := StandardMaterial3D.new()
	sodium.albedo_color = Color(1.0, 0.6, 0.25)
	sodium.emission_enabled = true
	sodium.emission = Color(1.0, 0.5, 0.15)
	sodium.emission_energy_multiplier = 4.0
	M["sodium"] = sodium


## Corrugated sheet steel: vertical ridges with rust bleeding down. 2 m tile.
func _corrugated_textures() -> Array:
	var S := 256
	var fine := _noise_img(S, 0.05, 41, 4)
	var streak := _noise_img(S, 0.02, 42, 3)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	var hgt := PackedFloat32Array(); hgt.resize(S * S)
	for y in S:
		for x in S:
			var p := y * S + x
			var ridge := sin(float(x) / S * TAU * 16.0)
			var f := fine[p] / 255.0
			var st := streak[(y / 8) * S + x] / 255.0
			var rust := clampf((st - 0.45) * 2.5 + (f - 0.5) * 0.6, 0.0, 1.0)
			var k := 0.62 + ridge * 0.1 + (f - 0.5) * 0.2
			var base := Vector3(k, k, k).lerp(Vector3(0.42, 0.22, 0.12), rust * 0.85)
			_put(alb, p * 3, base.x, base.y, base.z)
			rough[p] = int(clampf(0.55 + rust * 0.35 + f * 0.1, 0.0, 1.0) * 255.0)
			hgt[p] = ridge * 0.5 + 0.5
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_L8, rough), _normal_tex(S, S, hgt, 3.0)]


## Weathered planks: 0.25 m boards, 2 m tile.
func _plank_textures() -> Array:
	var S := 256
	var fine := _noise_img(S, 0.08, 51, 3)
	var grain := _noise_img(S, 0.03, 52, 2)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	var hgt := PackedFloat32Array(); hgt.resize(S * S)
	for y in S:
		var board := y / 32
		var iny := y % 32
		for x in S:
			var p := y * S + x
			var f := fine[p] / 255.0
			var g := grain[(y % 32) * S + ((x * 4 + board * 37) % S)] / 255.0
			var seam := iny < 2 or (x + board * 61) % 192 < 2
			var k := (0.55 + _hash(board, (x + board * 61) / 192) * 0.35) * (0.8 + g * 0.35)
			if seam:
				k = 0.12
			_put(alb, p * 3, 0.42 * k, 0.33 * k, 0.25 * k)
			rough[p] = int(clampf(0.7 + f * 0.3, 0.0, 1.0) * 255.0)
			hgt[p] = 0.0 if seam else 0.6 + f * 0.4
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_L8, rough), _normal_tex(S, S, hgt, 2.0)]


## Pine needles for the foliage cones: dark, tufted.
func _needle_textures() -> Array:
	var S := 128
	var fine := _noise_img(S, 0.18, 61, 3, FastNoiseLite.TYPE_CELLULAR)
	var big := _noise_img(S, 0.04, 62, 2)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	for p in S * S:
		var f := fine[p] / 255.0
		var g := big[p] / 255.0
		var k := 0.35 + f * 0.6 + g * 0.2
		_put(alb, p * 3, 0.07 * k, 0.12 * k, 0.07 * k)
		rough[p] = 230
	return [_tex(S, S, Image.FORMAT_RGB8, alb), _tex(S, S, Image.FORMAT_L8, rough)]


## Far pine: a tiered silhouette for the crossed billboard cards. 64 x 128, RGBA.
func _pine_card_texture() -> ImageTexture:
	var W := 64
	var H := 128
	var fine := _noise_img(128, 0.15, 71, 3)
	var data := PackedByteArray(); data.resize(W * H * 4)
	for y in H:
		var t := float(y) / H # 0 top .. 1 bottom
		var half := 0.0
		if t < 0.8:
			var tier := fmod(t * 5.0, 1.0)
			half = (0.08 + t * 0.48) * (0.55 + tier * 0.45)
		for x in W:
			var o := (y * W + x) * 4
			var u := absf((x + 0.5) / W - 0.5) * 2.0
			var n := fine[(y % 128) * 128 + x] / 255.0
			var a := 1.0 if u < half * (0.75 + n * 0.5) else 0.0
			var trunk := t > 0.55 and u < 0.06
			var k := 0.55 + n * 0.5
			if trunk:
				a = 1.0
				_put(data, o, 0.16, 0.11, 0.08)
			else:
				_put(data, o, 0.07 * k, 0.12 * k, 0.07 * k)
			data[o + 3] = int(a * 255.0)
	return _tex(W, H, Image.FORMAT_RGBA8, data)


## Spanish moss: ragged hanging strands. 64 x 128, RGBA (white; tinted by vertex colour).
func _moss_texture() -> ImageTexture:
	var W := 64
	var H := 128
	var fine := _noise_img(128, 0.2, 81, 2)
	var data := PackedByteArray(); data.resize(W * H * 4)
	for x in W:
		var strand_len := 0.35 + _hash(x / 3, 5) * 0.65
		var on := _hash(x / 2, 9) > 0.35
		for y in H:
			var o := (y * W + x) * 4
			var t := float(y) / H
			var n := fine[(y % 128) * 128 + (x * 2) % 128] / 255.0
			var a := 1.0 if on and t < strand_len * (0.8 + n * 0.4) else 0.0
			if t < 0.08:
				a = 1.0 if n > 0.3 else a
			var k := 0.5 + n * 0.5
			_put(data, o, 0.55 * k, 0.6 * k, 0.48 * k)
			data[o + 3] = int(a * 255.0)
	return _tex(W, H, Image.FORMAT_RGBA8, data)


## MultiMesh instances of `mesh` (its own surface materials), bucketed per `cell` metres so
## off-screen ones cull, each bucket drawn between range_begin and range_end (0 = always).
func scatter_mm(name: String, mesh: Mesh, xfs: Array, cell: float, range_begin := 0.0, range_end := 0.0, shadow := false, cols: Array = [], mat: Material = null, shadow_only := false) -> void:
	var cells := {}
	for k in xfs.size():
		var o: Vector3 = (xfs[k] as Transform3D).origin
		var key := Vector2i(floori(o.x / cell), floori(o.z / cell))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(k)
	var shuf := RandomNumberGenerator.new()
	shuf.seed = hash(name)
	for key in cells.keys():
		var idx: Array = cells[key]
		# shuffled, so any prefix (MultiMesh.visible_instance_count) is an even thinning
		for k in range(idx.size() - 1, 0, -1):
			var j := shuf.randi_range(0, k)
			var tmp = idx[k]
			idx[k] = idx[j]
			idx[j] = tmp
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = not cols.is_empty()
		mm.mesh = mesh
		mm.instance_count = idx.size()
		for k in idx.size():
			mm.set_instance_transform(k, xfs[idx[k]])
			if not cols.is_empty():
				mm.set_instance_color(k, cols[idx[k]])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [name, key.x, key.y]
		mmi.multimesh = mm
		if mat != null:
			mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if shadow_only:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		if range_begin > 0.0:
			mmi.visibility_range_begin = range_begin
			mmi.visibility_range_begin_margin = 8.0
		if range_end > 0.0:
			mmi.visibility_range_end = range_end
			mmi.visibility_range_end_margin = 8.0
		WQ.tag_bounds(mmi, idx.map(func(i): return xfs[i]))
		add_child(mmi)


var _trees_body: StaticBody3D


## A cylinder collider (tree trunks, posts, tanks) on one shared static body.
func post_collider(p: Vector3, r: float, h: float) -> void:
	if _trees_body == null:
		_trees_body = StaticBody3D.new()
		_trees_body.name = "Trunks"
		collider_root.add_child(_trees_body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = p + Vector3(0, h * 0.5, 0)
	_trees_body.add_child(cs)


## Layer of camera-only colliders: awnings and other overhangs Sol walks under but the camera
## arm must not pass through (player.gd's spring mask includes it; nothing else collides with it).
const CAM_LAYER := 512
var _cam_body: StaticBody3D


func cam_blocker(c: Vector3, size: Vector3, basis := Basis()) -> void:
	if _cam_body == null:
		_cam_body = StaticBody3D.new()
		_cam_body.name = "CameraBlockers"
		_cam_body.collision_layer = CAM_LAYER
		_cam_body.collision_mask = 0
		collider_root.add_child(_cam_body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = Transform3D(basis, c)
	_cam_body.add_child(cs)


## An axis-aligned or yawed box collider on the shared static body.
func box_collider(c: Vector3, size: Vector3, yaw := 0.0) -> void:
	if _trees_body == null:
		post_collider(Vector3(0, -50, 0), 0.1, 0.1)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), c)
	_trees_body.add_child(cs)


## A gas-lantern street lamp (procedural lamp prop, halo and light pool) at ground point p.
func path_lamp(p: Vector3, face := Vector3(0, 0, 1)) -> void:
	_add_prop("lamp", Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), p), Color.WHITE)
	lamp_positions.append(p + Vector3(0, LANTERN_Y, 0))
	halo_xfs.append(Transform3D(Basis(), p + Vector3(0, LANTERN_Y, 0)))
	var save := ck
	ck = _chunk_of(p.x, p.z)
	_light_pool(p + face * 0.6, 4.4)
	ck = save


## A flat strip of ground along a polyline (dirt roads, paths), chunked per segment.
func ground_path(mat: String, pts: Array, w: float, col := Color.WHITE, y := 0.03, spacing := 18.0) -> void:
	var save := ck
	for k in pts.size() - 1:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var dir := (b - a)
		dir.y = 0.0
		var n := dir.length()
		var side := Vector3.UP.cross(dir / n) * w * 0.5
		var steps := maxi(1, int(ceilf(n / 20.0)))
		for st in steps:
			var p0 := a.lerp(b, float(st) / steps)
			var p1 := a.lerp(b, float(st + 1) / steps)
			var m := (p0 + p1) * 0.5
			ck = _chunk_of(m.x, m.z)
			var e0 := p0 - dir / n * (w * 0.5 if st == 0 else 0.0)
			var e1 := p1 + dir / n * (w * 0.5 if st == steps - 1 else 0.0)
			var yy := Vector3(0, y, 0)
			_b(mat).quad(e0 - side + yy, e1 - side + yy, e1 + side + yy, e0 + side + yy, Vector3.UP, col)
		var d := 0.0
		while d < n:
			add_road(a + dir / n * d)
			d += spacing
	ck = save


## Distance on the ground plane from p to a polyline.
static func dist_to_path(p: Vector3, pts: Array) -> float:
	var best := INF
	var q := Vector2(p.x, p.z)
	for k in pts.size() - 1:
		var a := Vector2(pts[k].x, pts[k].z)
		var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best


## A generated GLB placed in the world (not instanced): returns its world-axis size.
func place_glb(name: String, height: float, xf: Transform3D, shadow := true, range_end := 0.0) -> Vector3:
	var holder := Node3D.new()
	holder.name = name
	add_child(holder)
	var size := _glb_into(holder, "map/" + name, height, xf, shadow)
	if range_end > 0.0:
		for mi in holder.get_children():
			(mi as GeometryInstance3D).visibility_range_end = range_end
	return size


## A generated GLB as MultiMesh instances (one per mesh part), bucketed for culling.
## `height` scales the model; each xf is applied on top of the normalised model.
func glb_multimesh(name: String, height: float, xfs: Array, cell: float, range_end: float, shadow := false) -> Vector3:
	var path := "res://assets/props/map/%s.glb" % name
	if not ResourceLoader.exists(path) or xfs.is_empty():
		return Vector3.ZERO
	var inst: Node = (load(path) as PackedScene).instantiate()
	var found: Array = []
	PropsScript._collect_meshes(inst, Transform3D.IDENTITY, found)
	inst.free()
	if found.is_empty():
		return Vector3.ZERO
	var bb := AABB()
	for k in found.size():
		var b: AABB = found[k][1] * (found[k][0] as Mesh).get_aabb()
		bb = b if k == 0 else bb.merge(b)
	var s := height / maxf(bb.size.y, 0.0001)
	var c := bb.get_center()
	var norm := Transform3D(Basis().scaled(Vector3(s, s, s)), -Vector3(c.x, bb.position.y, c.z) * s)
	for f in found:
		var part: Transform3D = norm * f[1]
		var list: Array = []
		for xf: Transform3D in xfs:
			list.append(xf * part)
		scatter_mm("Glb_" + name, f[0], list, cell, 0.0, range_end, shadow)
	return bb.size * s


# ================================================================ lair
const PIT_R := 3.0 # radius of the stair well (inside the balustrade)
const PIT_HOLE := 3.05 # half-size of the square hole left in the plaza paving
const PIT_DEPTH := 3.4


## The Undercroft entrance (image 01): a sunken circular stair well under a carved
## balustrade, curved steps sweeping down to a crypt arcade glowing red, a gothic
## arch (generated model) over the head of the stairs, flanked by two weeping
## angels on pedestals. A solid ring collider keeps everyone out of the well; the
## drink prompt stays reachable at the ring (radius ~3.4 m).
func build_lair(root: Node3D) -> void:
	var save_ck := ck
	ck = "L"
	var st := _b("stone")
	var sc := Color(0.6, 0.58, 0.54)
	var moss := Color(0.42, 0.46, 0.37)
	var dark := sc * Color(0.42, 0.4, 0.4)
	var R := PIT_R
	var D := PIT_DEPTH
	var y0 := WALK_TOP
	var segs := 32
	var dirs: Array = []
	for s in segs + 1:
		var a := TAU * s / segs
		dirs.append(Vector3(cos(a), 0, sin(a)))
	# shaft wall, seen from inside
	for s in segs:
		var d0: Vector3 = dirs[s]
		var d1: Vector3 = dirs[s + 1]
		st.quad_sm(d1 * R + Vector3(0, -D, 0), d1 * R + Vector3(0, y0, 0), d0 * R + Vector3(0, y0, 0), d0 * R + Vector3(0, -D, 0), -d1, -d1, -d0, -d0, dark)
	# curved steps sweeping down the south half of the well (an amphitheatre stair)
	var N := 11
	var tread := (R - 1.0) / N
	var rise := (D + y0) / N
	var a_lo := PI * 0.5 - 1.3
	var a_hi := PI * 0.5 + 1.3
	var ss := 14
	for k in N:
		var ro := R - k * tread
		var ri := R - (k + 1) * tread
		var yt := y0 - (k + 1) * rise
		var col := sc * Color(0.78, 0.76, 0.74) * (0.85 + 0.15 * float(k % 2))
		for q in ss:
			var a0 := lerpf(a_lo, a_hi, float(q) / ss)
			var a1 := lerpf(a_lo, a_hi, float(q + 1) / ss)
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			st.quad(d0 * ri + Vector3(0, yt, 0), d0 * ro + Vector3(0, yt, 0), d1 * ro + Vector3(0, yt, 0), d1 * ri + Vector3(0, yt, 0), Vector3.UP, col)
			st.quad_sm(d0 * ri + Vector3(0, yt - rise, 0), d0 * ri + Vector3(0, yt, 0), d1 * ri + Vector3(0, yt, 0), d1 * ri + Vector3(0, yt - rise, 0), -d0, -d0, -d1, -d1, col * Color(0.7, 0.7, 0.7))
		for a: float in [a_lo, a_hi]:
			var d := Vector3(cos(a), 0, sin(a))
			var t := Vector3(-sin(a), 0, cos(a)) * (1.0 if a == a_lo else -1.0)
			st.quad(d * ri + Vector3(0, -D, 0), d * ri + Vector3(0, yt, 0), d * ro + Vector3(0, yt, 0), d * ro + Vector3(0, -D, 0), -t, dark)
	# the crypt arcade on the far side: three pointed arches breathing red light
	var glow := _b("crypt_glow")
	for k in 3:
		var a := -PI * 0.5 + (k - 1) * 0.62
		var d := Vector3(cos(a), 0, sin(a))
		var f := Facade.new()
		f.n = -d
		f.r = Vector3(-sin(a), 0, cos(a)) * -1.0
		f.w = 1.7
		f.o = d * (R - 0.03) - f.r * f.w * 0.5 + Vector3(0, -D, 0)
		fq(glow, f, 0.2, 0.0, 1.5, 1.9, 0.01, Color(0.3, 0.3, 0.3))
		glow.tri(f.p(0.2, 1.9, 0.01), f.p(0.85, 2.7, 0.01), f.p(1.5, 1.9, 0.01), f.n, Color(0.3, 0.3, 0.3))
		_pointed_arch(st, f, 0.85, 0.68, 1.9, 0.2, 0.18, sc * Color(0.7, 0.68, 0.66), 0.2)
	# floor of the well: wet flags lit from the crypt
	_disc(glow, Vector3(0, -D + 0.01, 0), R, segs, Color(0.22, 0.22, 0.22))
	# carved balustrade around the well, open under the arch at the south
	var bal := _b("baluster")
	var gap := 0.45 # radians either side of +z
	for s in segs:
		var am := TAU * (s + 0.5) / segs
		if absf(wrapf(am - PI * 0.5, -PI, PI)) < gap:
			continue
		var d0: Vector3 = dirs[s]
		var d1: Vector3 = dirs[s + 1]
		var arc := TAU * 3.2 / segs
		# plinth
		st.quad_sm(d0 * 3.42 + Vector3(0, y0, 0), d0 * 3.42 + Vector3(0, y0 + 0.24, 0), d1 * 3.42 + Vector3(0, y0 + 0.24, 0), d1 * 3.42 + Vector3(0, y0, 0), d0, d0, d1, d1, moss)
		st.quad(d0 * (R - 0.02) + Vector3(0, y0 + 0.24, 0), d0 * 3.42 + Vector3(0, y0 + 0.24, 0), d1 * 3.42 + Vector3(0, y0 + 0.24, 0), d1 * (R - 0.02) + Vector3(0, y0 + 0.24, 0), Vector3.UP, sc)
		st.quad_sm(d1 * (R - 0.02) + Vector3(0, y0, 0), d1 * (R - 0.02) + Vector3(0, y0 + 0.24, 0), d0 * (R - 0.02) + Vector3(0, y0 + 0.24, 0), d0 * (R - 0.02) + Vector3(0, y0, 0), -d1, -d1, -d0, -d0, dark)
		# balusters (alpha-scissor band)
		bal.quad(d0 * 3.2 + Vector3(0, y0 + 0.24, 0), d0 * 3.2 + Vector3(0, y0 + 0.86, 0), d1 * 3.2 + Vector3(0, y0 + 0.86, 0), d1 * 3.2 + Vector3(0, y0 + 0.24, 0),
			(d0 + d1).normalized(), sc * Color(1.15, 1.15, 1.15), Vector2(0, 0), Vector2(arc, 1))
		# moulded rail
		var ry := y0 + 0.86
		st.quad_sm(d0 * 3.4 + Vector3(0, ry, 0), d0 * 3.4 + Vector3(0, ry + 0.16, 0), d1 * 3.4 + Vector3(0, ry + 0.16, 0), d1 * 3.4 + Vector3(0, ry, 0), d0, d0, d1, d1, sc)
		st.quad(d0 * R + Vector3(0, ry + 0.16, 0), d0 * 3.4 + Vector3(0, ry + 0.16, 0), d1 * 3.4 + Vector3(0, ry + 0.16, 0), d1 * R + Vector3(0, ry + 0.16, 0), Vector3.UP, sc * Color(1.05, 1.05, 1.05))
		st.quad_sm(d1 * R + Vector3(0, ry, 0), d1 * R + Vector3(0, ry + 0.16, 0), d0 * R + Vector3(0, ry + 0.16, 0), d0 * R + Vector3(0, ry, 0), -d1, -d1, -d0, -d0, sc * Color(0.8, 0.8, 0.8))
		st.quad(d1 * R + Vector3(0, ry, 0), d1 * 3.4 + Vector3(0, ry, 0), d0 * 3.4 + Vector3(0, ry, 0), d0 * R + Vector3(0, ry, 0), Vector3.DOWN, dark)
		if s % 4 == 0:
			box(st, d0 * 3.2 + Vector3(0, y0 + 0.55, 0), Vector3(0.36, 0.62, 0.36), sc, Basis(Vector3.UP, -TAU * s / segs))
	# newel posts at the head of the stairs
	for sd: float in [-1.0, 1.0]:
		var a := PI * 0.5 + sd * gap
		var d := Vector3(cos(a), 0, sin(a))
		box(st, d * 3.2 + Vector3(0, y0 + 0.6, 0), Vector3(0.5, 1.2, 0.5), sc, Basis(Vector3.UP, -a))
		cyl(st, d * 3.2 + Vector3(0, y0 + 1.2, 0), 0.22, 0.0, 0.5, 4, sc, true, Basis(Vector3.UP, PI * 0.25 - a))
	# two angel pedestals flanking the arch
	var ped_pos: Array = []
	for sd: float in [-1.0, 1.0]:
		var pp := Vector3(sd * 3.75, y0, 2.35)
		ped_pos.append(pp)
		box(st, pp + Vector3(0, 0.15, 0), Vector3(1.35, 0.3, 1.35), moss)
		box(st, pp + Vector3(0, 0.95, 0), Vector3(1.0, 1.3, 1.0), sc, Basis.IDENTITY, 12)
		box(st, pp + Vector3(0, 1.67, 0), Vector3(1.22, 0.16, 1.22), sc * Color(1.05, 1.05, 1.05))
	# a lantern hanging in the arch
	var lt := Vector3(0, 4.15, R + 0.15)
	box(_b("lamp"), lt, Vector3(0.22, 0.36, 0.22), Color.WHITE)
	beam(_b("metal"), lt + Vector3(0, 0.18, 0), lt + Vector3(0, 1.0, 0), 0.03, 0.03, Color(0.04, 0.04, 0.04))
	box(_b("metal"), lt + Vector3(0, 0.22, 0), Vector3(0.3, 0.06, 0.3), Color(0.04, 0.04, 0.04))
	_flush("L", root)
	ck = save_ck
	# generated props: the arch over the stair head and the two weeping angels
	var arch := _glb_into(root, "gothic_arch", 6.4, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, y0 - 0.05, R + 0.15)))
	for k in 2:
		var pp: Vector3 = ped_pos[k]
		var sd := -1.0 if k == 0 else 1.0
		_glb_into(root, "angel", 2.25, Transform3D(Basis(Vector3.UP, -PI * 0.5 - sd * 0.35), pp + Vector3(0, 1.75, 0)), false)
	_add_halo(root.global_transform * lt)
	# red light rising out of the well
	uplight_mat = ShaderMaterial.new()
	uplight_mat.shader = Shader.new()
	uplight_mat.shader.code = UPLIGHT_SHADER
	var col_h := D + 2.6
	uplight_mat.set_shader_parameter("y0", -col_h * 0.5)
	uplight_mat.set_shader_parameter("y1", col_h * 0.5)
	var cm := CylinderMesh.new()
	cm.top_radius = R - 0.1
	cm.bottom_radius = R - 0.4
	cm.height = col_h
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 24
	cm.rings = 1
	var up := MeshInstance3D.new()
	up.mesh = cm
	up.material_override = uplight_mat
	up.position = Vector3(0, -D + col_h * 0.5, 0)
	up.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(up)
	var pit_light := OmniLight3D.new()
	pit_light.position = Vector3(0, -1.8, -0.8)
	pit_light.light_color = Color(1.0, 0.12, 0.06)
	pit_light.light_energy = 2.2
	pit_light.omni_range = 6.5
	root.add_child(pit_light)
	# colliders: a solid ring over the well, the pedestals and the arch piers
	var ring := StaticBody3D.new()
	root.add_child(ring)
	var ring_col := CollisionShape3D.new()
	var ring_shape := CylinderShape3D.new()
	ring_shape.radius = R + 0.05
	ring_shape.height = 1.0
	ring_col.shape = ring_shape
	ring_col.position.y = 0.5
	ring.add_child(ring_col)
	for pp in ped_pos:
		_static_box(Vector3(1.2, 4.0, 1.2), pp + Vector3(0, 2.0, 0), root)
	var aw: float = arch.x if arch != Vector3.ZERO else 5.0
	for sd: float in [-1.0, 1.0]:
		_static_box(Vector3(0.8, 5.0, 1.0), Vector3(sd * (aw * 0.5 - 0.45), 2.5, R + 0.15), root)


## Adds one more lantern halo after the city is built (the Undercroft's lantern).
func _add_halo(p: Vector3) -> void:
	halo_xfs.append(Transform3D(Basis(), p))
	if halo_mm == null:
		return
	halo_mm.instance_count = halo_xfs.size()
	for k in halo_xfs.size():
		halo_mm.set_instance_transform(k, halo_xfs[k])


## Places a generated GLB under `parent`, scaled to `height` m with its base at the
## transform's origin. Returns its scaled size in world axes, or ZERO.
func _glb_into(parent: Node3D, name: String, height: float, xf: Transform3D, shadow := true) -> Vector3:
	var path := "res://assets/props/%s.glb" % name
	if not ResourceLoader.exists(path):
		return Vector3.ZERO
	var scene := load(path) as PackedScene
	if scene == null:
		return Vector3.ZERO
	var inst := scene.instantiate()
	var found: Array = []
	PropsScript._collect_meshes(inst, Transform3D.IDENTITY, found)
	inst.free()
	if found.is_empty():
		return Vector3.ZERO
	var bb := AABB()
	for k in found.size():
		var b: AABB = found[k][1] * (found[k][0] as Mesh).get_aabb()
		bb = b if k == 0 else bb.merge(b)
	var s := height / maxf(bb.size.y, 0.0001)
	var c := bb.get_center()
	var norm := Transform3D(Basis().scaled(Vector3(s, s, s)), -Vector3(c.x, bb.position.y, c.z) * s)
	for fnd in found:
		var mi := MeshInstance3D.new()
		mi.mesh = fnd[0]
		mi.transform = xf * norm * fnd[1]
		mi.name = name
		if not shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	return (xf.basis * bb.size).abs() * s


# ================================================================ animation
func _process(delta: float) -> void:
	_t += delta
	if window_mat == null:
		return
	var win := window_mat.emission_energy_multiplier
	var night := clampf((lamp_mat.emission_energy_multiplier - 0.2) / 4.0, 0.0, 1.0)
	# a few windows and signs buzz and stutter
	var buzz := sin(_t * 23.0) + sin(_t * 7.3) * 0.8 + sin(_t * 1.7) * 0.6
	flicker_mat.emission_energy_multiplier = win * (0.15 if buzz > 1.2 else 1.0)
	var nbuzz := sin(_t * 31.0 + 1.0) + sin(_t * 3.1) * 1.1
	var neon_e := 0.8 + night * 3.2
	neon_mat.emission_energy_multiplier = neon_e
	neon_flicker_mat.emission_energy_multiplier = neon_e * (0.05 if nbuzz > 1.4 else 1.0)
	far_mat.emission_energy_multiplier = win * 0.9
	stained_mat.emission_energy_multiplier = 0.15 + night * 2.6
	shop_mat.emission_energy_multiplier = 0.15 + win * 0.5
	halo_mat.set_shader_parameter("strength", night * 0.55)
	if uplight_mat != null:
		uplight_mat.set_shader_parameter("strength", 0.35 + night * 0.5)
	crypt_mat.emission_energy_multiplier = 0.5 + night * 0.7
	var pool := night * 0.42
	pool_mat.albedo_color = Color(1.0 * pool, 0.72 * pool, 0.42 * pool)
	M["pool_neon"].albedo_color = Color(0.55, 0.04, 0.22) * (0.25 + night * 0.75)
