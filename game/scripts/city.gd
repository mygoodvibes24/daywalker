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
const BLOCKS := 4 # blocks run from -BLOCKS..BLOCKS-1 on each axis
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
var collider_root: Node3D
var car_bodies: StaticBody3D
var signs_left := 7
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


func _b(mat: String) -> Batch:
	var key := ck + "|" + mat
	var bt: Batch = batches.get(key)
	if bt == null:
		bt = Batch.new()
		batches[key] = bt
	return bt


static func _chunk_of(x: float, z: float) -> String:
	if absf(x) > 84.0 or absf(z) > 84.0:
		return "F"
	if absf(x) <= 40.0 and absf(z) <= 40.0:
		return "C"
	if z < -40.0:
		return "N"
	if z > 40.0:
		return "S"
	return "W" if x < 0.0 else "E"


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


## Old Quarter cobbles from cellular noise: 2 m tile.
func _cobble_textures() -> Array:
	var S := 256
	var fn := FastNoiseLite.new()
	fn.seed = 31
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn.frequency = 0.055
	fn.fractal_type = FastNoiseLite.FRACTAL_NONE
	fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var edge_img := fn.get_seamless_image(S, S, false, false, 0.1, true)
	edge_img.convert(Image.FORMAT_L8)
	var edges := edge_img.get_data()
	fn.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var cell_img := fn.get_seamless_image(S, S, false, false, 0.1, true)
	cell_img.convert(Image.FORMAT_L8)
	var cells := cell_img.get_data()
	var fine := _noise_img(S, 0.15, 32, 2)
	var alb := PackedByteArray(); alb.resize(S * S * 3)
	var rough := PackedByteArray(); rough.resize(S * S)
	var hgt := PackedFloat32Array(); hgt.resize(S * S)
	for p in S * S:
		var e := edges[p] / 255.0
		var cv := cells[p] / 255.0
		var f := fine[p] / 255.0
		var stone := clampf((e - 0.08) * 6.0, 0.0, 1.0)
		var k := (0.55 + cv * 0.45 + (f - 0.5) * 0.2) * (0.35 + stone * 0.65)
		_put(alb, p * 3, 0.42 * k, 0.4 * k, 0.37 * k)
		rough[p] = int(lerpf(0.15, 0.55 + f * 0.25, stone) * 255.0) # wet gaps
		hgt[p] = sqrt(stone) * 0.9 + f * 0.15
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


func _make_materials() -> void:
	M["brick"] = _surface_mat(_brick_textures(), 1.0)
	M["stone"] = _surface_mat(_stone_textures(), 2.0)
	M["stucco"] = _surface_mat(_stucco_textures(), 3.0)
	var conc := _concrete_textures()
	M["concrete"] = _surface_mat(conc, 4.0)
	M["trim"] = _surface_mat(conc, 6.0, 0.7)
	M["sidewalk"] = _surface_mat(_sidewalk_textures(), 1.5)
	M["cobble"] = _surface_mat(_cobble_textures(), 2.0)
	var asphalt := _surface_mat(_asphalt_textures(), 8.0, 1.0, false)
	M["asphalt"] = asphalt
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
	lamp_mat.albedo_color = Color(1, 0.85, 0.6)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1, 0.78, 0.5)
	lamp_mat.emission_energy_multiplier = 0.2
	M["lamp"] = lamp_mat

	stained_mat = StandardMaterial3D.new()
	stained_mat.albedo_texture = nt
	stained_mat.emission_enabled = true
	stained_mat.emission_texture = nt
	stained_mat.emission = Color(1, 1, 1)
	stained_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	stained_mat.emission_energy_multiplier = 0.0
	stained_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	stained_mat.roughness = 0.2
	M["stained"] = stained_mat

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


# ================================================================ build
func build() -> void:
	rng.seed = SEED
	_make_materials()
	collider_root = Node3D.new()
	collider_root.name = "Colliders"
	add_child(collider_root)
	car_bodies = StaticBody3D.new()
	car_bodies.name = "ParkedCars"
	add_child(car_bodies)
	_build_ground()
	for i in range(-BLOCKS, BLOCKS):
		for j in range(-BLOCKS, BLOCKS):
			var cx := i * GRID + GRID * 0.5
			var cz := j * GRID + GRID * 0.5
			if absf(cx) < GRID and absf(cz) < GRID:
				continue
			if cz == -30.0 and absf(cx) == 10.0:
				continue # the cathedral takes these two blocks
			_build_block(cx, cz)
	_build_plaza()
	_build_cathedral()
	_build_streets()
	_build_backdrop()
	_place_signs()
	_build_props()
	_flush()
	# boundary walls (invisible)
	var edge := BLOCKS * GRID + 2.0
	for s: float in [-1.0, 1.0]:
		_static_box(Vector3(2, 30, edge * 2.0), Vector3(s * edge, 15, 0))
		_static_box(Vector3(edge * 2.0, 30, 2), Vector3(0, 15, s * edge))


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
		var group := parts[0] + ("|cast" if casts else "|nocast")
		if not by_chunk.has(group):
			by_chunk[group] = []
		by_chunk[group].append(key)
	for group in by_chunk.keys():
		var mesh := ArrayMesh.new()
		var keys: Array = by_chunk[group]
		keys.sort()
		for key in keys:
			var bt: Batch = batches[key]
			if bt.i.is_empty():
				continue
			if offset != Vector3.ZERO:
				for k in bt.v.size():
					bt.v[k] -= offset
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
		(parent if parent else self).add_child(mi)


# ---------------------------------------------------------------- ground
func _build_ground() -> void:
	# Collision: one big slab. Visual: asphalt everywhere, with a hole for the Undercroft shaft.
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	add_child(ground)
	var gcol := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(240, 1, 240)
	gcol.shape = gshape
	gcol.position.y = -0.5
	ground.add_child(gcol)
	var bt := Batch.new()
	var E := 120.0
	var h := 1.9
	for r in [[-E, -E, E, -h], [-E, h, E, E], [-E, -h, -h, h], [h, -h, E, h]]:
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
	var d := maxf(absf(cx), absf(cz))
	if d <= 30.0:
		return "quarter"
	if cx >= 50.0:
		return "velvet"
	if cx <= -50.0:
		return "docks"
	return "midtown"


func _build_block(cx: float, cz: float) -> void:
	ck = _chunk_of(cx, cz)
	var dist := _district(cx, cz)
	var walk_col := Color(1, 1, 1) if dist != "quarter" else Color(0.92, 0.88, 0.82)
	_slab(cx - GRID * 0.5 + ROAD_HALF, cz - GRID * 0.5 + ROAD_HALF, cx + GRID * 0.5 - ROAD_HALF, cz + GRID * 0.5 - ROAD_HALF,
		"sidewalk" if dist != "quarter" else "cobble", walk_col, Color(0.62, 0.6, 0.57))
	# split the lot into parcels
	var L := LOT
	var parcels: Array = []
	var pattern := rng.randi_range(0, 4)
	if dist == "quarter":
		pattern = [1, 2, 3, 4][rng.randi() % 4]
	elif dist == "docks":
		pattern = [0, 0, 1, 2][rng.randi() % 4]
	match pattern:
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
	var body := StaticBody3D.new()
	body.name = "Block_%d_%d" % [cx, cz]
	collider_root.add_child(body)
	var far := clampf((maxf(absf(cx), absf(cz)) - 30.0) / 40.0, 0.0, 1.0)
	for p in parcels:
		var spec := _building_spec(dist, far)
		spec["x0"] = cx + p[0]
		spec["z0"] = cz + p[1]
		spec["x1"] = cx + p[2]
		spec["z1"] = cz + p[3]
		# which sides face a street
		spec["ext"] = [is_equal_approx(p[3], L), is_equal_approx(p[1], -L), is_equal_approx(p[2], L), is_equal_approx(p[0], -L)]
		var H := _building(spec)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(p[2] - p[0], H, p[3] - p[1])
		col.shape = shape
		col.position = Vector3(cx + (p[0] + p[2]) * 0.5, H * 0.5, cz + (p[1] + p[3]) * 0.5)
		body.add_child(col)


const STUCCO := [Color(0.85, 0.6, 0.55), Color(0.88, 0.72, 0.48), Color(0.6, 0.74, 0.64), Color(0.7, 0.64, 0.78),
	Color(0.9, 0.84, 0.72), Color(0.58, 0.68, 0.8), Color(0.78, 0.46, 0.36), Color(0.92, 0.9, 0.85)]
const BRICK := [Color(1, 1, 1), Color(0.9, 0.82, 0.76), Color(0.78, 0.66, 0.6), Color(1.0, 0.92, 0.86), Color(0.68, 0.68, 0.7), Color(0.6, 0.5, 0.46)]
const SHUTTER := [Color(0.12, 0.25, 0.17), Color(0.1, 0.18, 0.28), Color(0.06, 0.06, 0.06), Color(0.35, 0.12, 0.1)]


func _building_spec(dist: String, far: float) -> Dictionary:
	var s := {"style": dist}
	match dist:
		"quarter":
			s["wall"] = "stucco"
			s["wcol"] = STUCCO[rng.randi() % STUCCO.size()]
			s["tcol"] = Color(0.9, 0.88, 0.82)
			s["floors"] = rng.randi_range(1, 3)
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
		if not ext[side]:
			# party wall: blank, slightly dirtier
			fq(wall, f, 0, 0, f.w, H + par, 0.0, dirt)
			continue
		var n_cols := maxi(1, int(f.w / bay))
		var margin := (f.w - n_cols * bay) * 0.5
		var centers: Array = []
		for k in n_cols:
			centers.append(margin + bay * (k + 0.5))
		_ground_floor(spec, f, gh, wall, wcol, trim, tcol, glass)
		# belt course
		fbox(stone, f, -0.05, gh - 0.12, f.w + 0.05, gh + 0.12, 0.0, 0.1, tcol)
		# upper floors
		var holes: Array = []
		for cu in centers:
			holes.append([cu - ww * 0.5, cu + ww * 0.5])
		for fl in floors:
			var y0 := gh + fl * fh
			var ya := y0 + sill
			var yb := ya + wh
			fq(wall, f, 0, y0, f.w, ya, 0.0, wcol)
			_wall_row(wall, f, ya, yb, holes, wcol)
			fq(wall, f, 0, yb, f.w, y0 + fh, 0.0, wcol)
			for cu in centers:
				var wuv: Array = _window_uv(style)
				_opening(f, cu - ww * 0.5, ya, cu + ww * 0.5, yb, depth, wall, wcol * Color(0.85, 0.85, 0.85), glass_f if wuv[1] else glass, wuv[0], style == "quarter")
				if style == "quarter":
					var sc: Color = spec.shutter
					fbox(trim, f, cu - ww * 0.5 - 0.5, ya, cu - ww * 0.5 - 0.04, yb, 0.0, 0.05, sc)
					fbox(trim, f, cu + ww * 0.5 + 0.04, ya, cu + ww * 0.5 + 0.5, yb, 0.0, 0.05, sc)
					fbox(stone, f, cu - ww * 0.5 - 0.12, yb, cu + ww * 0.5 + 0.12, yb + 0.22, 0.0, 0.08, tcol)
				else:
					fbox(stone, f, cu - ww * 0.5 - 0.1, ya - 0.08, cu + ww * 0.5 + 0.1, ya, 0.0, 0.12, tcol)
					if style == "midtown" or style == "docks":
						fbox(stone, f, cu - ww * 0.5 - 0.08, yb, cu + ww * 0.5 + 0.08, yb + 0.2, 0.0, 0.04, tcol)
			if style == "quarter":
				_balcony(f, y0, 0.15, f.w - 0.15)
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
		_opening(f, u0, 0.0, u1, top, 0.3, trim, dark, glass, cell_uv(cell, 4), false)
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
	ck = "C"
	var e := GRID - ROAD_HALF
	var h := 1.9
	var cob := _b("cobble")
	var y := WALK_TOP
	var col := Color(0.95, 0.92, 0.88)
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
	for s in 24:
		var a0 := TAU * s / 24.0
		var a1 := TAU * (s + 1) / 24.0
		var p := [Vector3(cos(a0) * 2.9, y + 0.006, sin(a0) * 2.9), Vector3(cos(a0) * 5.5, y + 0.006, sin(a0) * 5.5),
			Vector3(cos(a1) * 5.5, y + 0.006, sin(a1) * 5.5), Vector3(cos(a1) * 2.9, y + 0.006, sin(a1) * 2.9)]
		st.quad(p[0], p[1], p[2], p[3], Vector3.UP, Color(0.7, 0.68, 0.64))
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
	# live oaks at the corners
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_tree(Vector3(sx * 12.5, y, sz * 12.5))
	# ornate plaza lamps (these six carry real lights)
	for kk in range(6):
		var a := kk * TAU / 6.0 + 0.5
		var p := Vector3(cos(a) * 15.0, 0, sin(a) * 15.0)
		_ornate_lamp(p)
		var l := OmniLight3D.new()
		l.position = p + Vector3(0, 4.3, 0)
		l.omni_range = 13.0
		l.light_color = Color(1, 0.75, 0.45)
		add_child(l)
		lamps.append(l)


func _ornate_lamp(p: Vector3) -> void:
	var m := _b("metal")
	var black := Color(0.04, 0.04, 0.045)
	cyl(m, p, 0.22, 0.18, 0.5, 8, black)
	cyl(m, p + Vector3(0, 0.5, 0), 0.09, 0.07, 3.6, 8, black, false)
	cyl(m, p + Vector3(0, 4.1, 0), 0.16, 0.22, 0.12, 8, black)
	var lamp := _b("lamp")
	cyl(lamp, p + Vector3(0, 4.22, 0), 0.17, 0.24, 0.55, 6, Color.WHITE)
	cyl(m, p + Vector3(0, 4.77, 0), 0.3, 0.05, 0.3, 6, black)
	lamp_positions.append(p + Vector3(0, 4.5, 0))


func _tree(p: Vector3) -> void:
	var m := _b("metal")
	var bark := Color(0.2, 0.16, 0.13)
	cyl(m, p, 0.42, 0.3, 2.6, 8, bark, false)
	var lv := _b("leaves")
	# low, spreading boughs
	for k in 5:
		var a := k * TAU / 5.0 + rng.randf() * 0.5
		var tip := p + Vector3(cos(a) * 3.0, rng.randf_range(3.3, 4.3), sin(a) * 3.0)
		beam(m, p + Vector3(0, 2.4, 0), tip, 0.22, 0.22, bark)
		_foliage(lv, tip + Vector3(0, 0.3, 0), rng.randf_range(1.6, 2.2))
	_foliage(lv, p + Vector3(0, 5.0, 0), 2.6)
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
	ck = "C"
	var st := _b("stone")
	var sc := Color(0.78, 0.76, 0.72)
	var dark := Color(0.5, 0.48, 0.46)
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
		# octagonal spire
		cyl(st, Vector3(cx, tower_h + 5.0, (zf + zb) * 0.5), 2.6, 0.0, 12.0, 8, Color(0.42, 0.42, 0.44))
		cyl(_b("metal"), Vector3(cx, tower_h + 17.0, (zf + zb) * 0.5), 0.05, 0.05, 1.6, 4, Color(0.1, 0.1, 0.1))
		box(_b("metal"), Vector3(cx, tower_h + 18.1, (zf + zb) * 0.5), Vector3(0.8, 0.06, 0.06), Color(0.1, 0.1, 0.1))
		# portal: recessed pointed-arch door with stepped archivolts
		var f := Facade.new()
		f.o = Vector3(lo + 0.3, 0, zf - 0.3)
		f.r = Vector3(1, 0, 0)
		f.n = Vector3(0, 0, 1)
		f.w = hi - lo - 0.6
		var pc := f.w * 0.5
		for ring in 3:
			var hw := 1.5 - ring * 0.25
			_pointed_arch(st, f, pc, hw, 3.2, 0.25, 0.2 - ring * 0.12, sc * Color(0.9, 0.9, 0.9))
		fq(_b("trim"), f, pc - 1.0, 0.0, pc + 1.0, 3.0, -0.1, Color(0.16, 0.09, 0.06))
		_lancet(f, pc, 3.9, 1.2, 0.5, 1.6) # tympanum glow
		# tall lancet windows up the tower
		for row in 2:
			var y := 9.0 + row * 8.0
			for k in 2:
				_lancet(f, pc + (k - 0.5) * 2.2, y, 0.8, 5.0, 1.2)
		# string courses
		for y: float in [7.5, 15.5, 23.5]:
			fbox(st, f, -0.3, y, f.w + 0.3, y + 0.35, 0.0, 0.25, dark)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(hi - lo, tower_h, zf - zb)
		cs.shape = shape
		cs.position = Vector3(cx, tower_h * 0.5, (zf + zb) * 0.5)
		body.add_child(cs)
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
	# rose window
	var rose := f.p(f.w * 0.5, 16.0, 0.05)
	var sg := _b("stained")
	for s in 16:
		var a0 := TAU * s / 16.0
		var a1 := TAU * (s + 1) / 16.0
		var p0 := rose + (Vector3(cos(a0), sin(a0), 0)) * 3.2
		var p1 := rose + (Vector3(cos(a1), sin(a1), 0)) * 3.2
		var uvc := neon_uv([0, 7, 3, 4, 7, 2, 1, 4][s % 8])
		sg.tri(rose, p0, p1, Vector3(0, 0, 1), Color.WHITE, uvc, uvc, uvc)
		# tracery spokes and rim
		beam(st, rose + Vector3(0, 0, 0.05), rose + Vector3(cos(a0), sin(a0), 0) * 3.2 + Vector3(0, 0, 0.05), 0.12, 0.12, sc, Vector3(0, 0, 1))
		beam(st, p0 + Vector3(0, 0, 0.05), p1 + Vector3(0, 0, 0.05), 0.35, 0.3, sc, Vector3(0, 0, 1))
	cyl(st, rose, 0.5, 0.5, 0.25, 12, sc, true, Basis(Vector3.RIGHT, Vector3(0, 0, 1), Vector3(0, -1, 0)))
	# a row of blind arcading under the rose
	for k in 7:
		var u := 1.6 + k * 1.47
		_pointed_arch(st, f, u, 0.45, 11.0, 0.1, 0.12, dark, 1.6)


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


## Lancet window: glass rectangle with a pointed head, glowing at night.
func _lancet(f: Facade, cu: float, y: float, w: float, h: float, head: float) -> void:
	var sg := _b("stained")
	var uv := neon_uv([7, 0, 4, 2][rng.randi() % 4])
	var u0 := cu - w * 0.5
	var u1 := cu + w * 0.5
	sg.quad(f.p(u0, y, 0.04), f.p(u0, y + h, 0.04), f.p(u1, y + h, 0.04), f.p(u1, y, 0.04), f.n, Color.WHITE, uv, uv)
	sg.tri(f.p(u0, y + h, 0.04), f.p(cu, y + h + head, 0.04), f.p(u1, y + h, 0.04), f.n, Color.WHITE, uv, uv, uv)
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
	var lim := BLOCKS * GRID
	var yellow := Color(0.85, 0.65, 0.15)
	var white := Color(0.85, 0.85, 0.82)
	var plaza := GRID - ROAD_HALF
	for a in range(-BLOCKS, BLOCKS + 1):
		var s := a * GRID
		for b in range(-BLOCKS, BLOCKS):
			var g0 := b * GRID
			# a segment of street running along z at x = s, and its twin along x at z = s
			for axis in 2:
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
				# zebra crossings and stop lines at both ends
				for end: float in [0.0, 1.0]:
					var e0 := base + along * (GRID * end)
					var sgn := 1.0 if end == 0.0 else -1.0
					var k := -ROAD_HALF + 0.35
					while k < ROAD_HALF - 0.3:
						_strip(paint, e0 + across * k + along * sgn * 4.0, e0 + across * k + along * sgn * 6.0, 0.4, white)
						k += 0.85
					var stop_side := -1.0 if end == 0.0 else 1.0
					_strip(paint, e0 + along * sgn * 6.4 + across * stop_side * 0.2, e0 + along * sgn * 6.4 + across * stop_side * (ROAD_HALF - 0.2), 0.0, white, 0.3)
				# manhole, sometimes steaming
				if rng.randf() < 0.55:
					var mp := Vector3(px, 0.0, pz) + along * rng.randf_range(-2.0, 2.0) + across * rng.randf_range(-1.5, 1.5)
					cyl(_b("metal"), mp, 0.42, 0.42, 0.018, 12, Color(0.13, 0.12, 0.11))
					if rng.randf() < 0.18 and absf(mp.x) < 70 and absf(mp.z) < 70:
						_steam(mp)
				# puddles near the kerbs
				for q in rng.randi_range(0, 3):
					var side := -1.0 if rng.randf() < 0.5 else 1.0
					var pp := Vector3(px, 0.016, pz) + along * rng.randf_range(-8.0, 8.0) + across * side * rng.randf_range(1.0, ROAD_HALF - 0.4)
					_puddle(pp, rng.randf_range(0.8, 2.2))
				# parked cars, one per kerb at most, clear of the corners
				for side: float in [-1.0, 1.0]:
					if rng.randf() < 0.42 and absf(s) < lim:
						var cp := Vector3(px, 0.0, pz) + across * side * 2.85 + along * rng.randf_range(-1.2, 1.2)
						var yaw := atan2(along.x, along.z) + (PI if side < 0 else 0.0)
						_car(cp, yaw)
				# street lamps on one kerb
				if absf(s) <= lim:
					var lside := 1.0 if (a + b) % 2 == 0 else -1.0
					var lp := Vector3(px, 0.0, pz) + across * lside * (ROAD_HALF + 0.45)
					_add_prop("lamp", Transform3D(Basis(Vector3.UP, atan2(-across.x * lside, -across.z * lside)), lp), Color.WHITE)
					lamp_positions.append(lp + Vector3(0, 4.9, 0) - across * lside * 1.0)
					_light_pool(lp - across * lside * 1.0, 4.2)
				# telephone poles and sagging wires on the outer, older streets
				if (absf(s) == 60.0 or absf(s) == 80.0) and absf(mid) < lim:
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
	for i in range(-BLOCKS - 2, BLOCKS + 2):
		for j in range(-BLOCKS - 2, BLOCKS + 2):
			if i >= -BLOCKS and i < BLOCKS and j >= -BLOCKS and j < BLOCKS:
				continue
			var cx := i * GRID + GRID * 0.5
			var cz := j * GRID + GRID * 0.5
			var ring2 := i < -BLOCKS - 1 or i > BLOCKS or j < -BLOCKS - 1 or j > BLOCKS
			if not ring2:
				_slab(cx - GRID * 0.5 + ROAD_HALF, cz - GRID * 0.5 + ROAD_HALF, cx + GRID * 0.5 - ROAD_HALF, cz + GRID * 0.5 - ROAD_HALF,
					"sidewalk", Color(0.9, 0.9, 0.9), Color(0.55, 0.54, 0.52))
			var L := LOT + (2.5 if ring2 else 0.0)
			var h := rng.randf_range(14.0, 30.0) + (rng.randf_range(10.0, 35.0) if ring2 else 0.0)
			var x0 := cx - L
			var x1 := cx + L
			var z0 := cz - L
			var z1 := cz + L
			var uo := Vector2(rng.randi_range(0, 7) / 8.0, rng.randi_range(0, 7) / 8.0)
			var s := 1.0 / 25.6
			var tint := Color(1, 1, 1).lerp(Color(0.8, 0.75, 0.7), rng.randf())
			bt.quad(Vector3(x0, 0, z1), Vector3(x0, h, z1), Vector3(x1, h, z1), Vector3(x1, 0, z1), Vector3(0, 0, 1), tint, uo, uo + Vector2((x1 - x0) * s, h * s))
			bt.quad(Vector3(x1, 0, z0), Vector3(x1, h, z0), Vector3(x0, h, z0), Vector3(x0, 0, z0), Vector3(0, 0, -1), tint, uo, uo + Vector2((x1 - x0) * s, h * s))
			bt.quad(Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x1, h, z0), Vector3(x1, 0, z0), Vector3(1, 0, 0), tint, uo, uo + Vector2((z1 - z0) * s, h * s))
			bt.quad(Vector3(x0, 0, z0), Vector3(x0, h, z0), Vector3(x0, h, z1), Vector3(x0, 0, z1), Vector3(-1, 0, 0), tint, uo, uo + Vector2((z1 - z0) * s, h * s))
			roof.quad(Vector3(x0, h, z1), Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3.UP, Color(0.2, 0.2, 0.2))
			if not ring2 and rng.randf() < 0.3:
				_water_tower(Vector3(cx, h, cz))


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
	for i in range(-BLOCKS, BLOCKS):
		for j in range(-BLOCKS, BLOCKS):
			var cx := i * GRID + GRID * 0.5
			var cz := j * GRID + GRID * 0.5
			if absf(cx) < GRID and absf(cz) < GRID:
				continue
			if cz == -30.0 and absf(cx) == 10.0:
				continue
			for side in 4:
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
			"dumpster":
				meshes = [[_dumpster_mesh(), prop, true]]
			"trash":
				meshes = [[_trash_mesh(), bag, true]]
		var xfs: Array = props[kind]
		var cols: Array = prop_cols[kind]
		for entry in meshes:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = entry[2]
			mm.mesh = entry[0]
			mm.instance_count = xfs.size()
			for k in xfs.size():
				mm.set_instance_transform(k, xfs[k])
				if entry[2]:
					mm.set_instance_color(k, cols[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Props_" + kind
			mmi.multimesh = mm
			mmi.material_override = entry[1]
			var big: bool = kind == "sedan" or kind == "van" or kind == "dumpster"
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if big and entry[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)


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


## Returns [post, lantern]. Faces +z: the arm reaches over the road.
func _lamp_mesh() -> Array:
	var post := Batch.new()
	var head := Batch.new()
	var c := Color(0.06, 0.065, 0.07)
	cyl(post, Vector3.ZERO, 0.2, 0.16, 0.6, 8, c)
	cyl(post, Vector3(0, 0.6, 0), 0.08, 0.06, 4.5, 8, c, false)
	beam(post, Vector3(0, 4.8, 0), Vector3(0, 5.05, 1.0), 0.06, 0.06, c)
	beam(post, Vector3(0, 4.3, 0), Vector3(0, 4.95, 0.7), 0.035, 0.035, c)
	box(post, Vector3(0, 5.1, 1.05), Vector3(0.45, 0.1, 0.7), c)
	box(head, Vector3(0, 4.98, 1.05), Vector3(0.36, 0.14, 0.58), Color.WHITE)
	return [_mesh_of(post), _mesh_of(head)]


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


# ================================================================ lair
## The Undercroft entrance: a weathered stone well-head under a Gothic stone canopy,
## an iron grate over the shaft and a red glow far below. Colliders match the old ones.
func build_lair(root: Node3D) -> void:
	var save_ck := ck
	ck = "L"
	var st := _b("stone")
	var sc := Color(0.72, 0.7, 0.66)
	var moss := Color(0.45, 0.5, 0.4)
	# well-head ring: outer wall, coping annulus, inner shaft wall
	var segs := 24
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		st.quad_sm(d0 * 2.8, d0 * 2.65 + Vector3(0, 0.5, 0), d1 * 2.65 + Vector3(0, 0.5, 0), d1 * 2.8, d0, d0, d1, d1, moss)
		st.quad(d0 * 1.8 + Vector3(0, 0.5, 0), d0 * 2.65 + Vector3(0, 0.5, 0), d1 * 2.65 + Vector3(0, 0.5, 0), d1 * 1.8 + Vector3(0, 0.5, 0), Vector3.UP, sc)
		st.quad_sm(d1 * 1.8 + Vector3(0, -3.2, 0), d1 * 1.8 + Vector3(0, 0.5, 0), d0 * 1.8 + Vector3(0, 0.5, 0), d0 * 1.8 + Vector3(0, -3.2, 0), -d1, -d1, -d0, -d0, sc * Color(0.5, 0.5, 0.5))
	# stone steps spiralling down the shaft
	for k in 14:
		var a := k * 0.42
		var d := Vector3(cos(a), 0, sin(a))
		var basis := Basis(Vector3.UP, -a)
		box(st, d * 1.35 + Vector3(0, 0.1 - k * 0.24, 0), Vector3(0.9, 0.18, 0.7), sc * Color(0.6, 0.6, 0.6), basis)
	# iron grate over the shaft
	var iron := _b("iron")
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 1.82
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 1.82
		var y := Vector3(0, 0.46, 0)
		iron.tri(y, y + p0, y + p1, Vector3.UP, Color.WHITE, Vector2(0.5, 0.75), Vector2(0.5 + p0.x * 0.45, 0.75 + p0.z * 0.12), Vector2(0.5 + p1.x * 0.45, 0.75 + p1.z * 0.12))
	# four Gothic piers carrying pointed arches and a stone spirelet
	var r := 3.2
	var pts: Array = []
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		pts.append(p)
		box(st, p + Vector3(0, 0.2, 0), Vector3(0.85, 0.4, 0.85), moss)
		box(st, p + Vector3(0, 1.95, 0), Vector3(0.6, 3.1, 0.6), sc, Basis.IDENTITY, 12)
		box(st, p + Vector3(0, 3.55, 0), Vector3(0.78, 0.25, 0.78), sc)
		# lantern on each pier, facing out
		var out := Vector3(cos(a), 0, sin(a))
		box(_b("metal"), p + out * 0.36 + Vector3(0, 2.6, 0), Vector3(0.08, 0.08, 0.08), Color(0.05, 0.05, 0.05))
		box(_b("lamp"), p + out * 0.45 + Vector3(0, 2.45, 0), Vector3(0.18, 0.28, 0.18), Color.WHITE)
	for k in 4:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % 4]
		var f := Facade.new()
		var mid := (a + b) * 0.5
		f.r = (b - a).normalized()
		f.n = mid.normalized()
		f.w = a.distance_to(b)
		f.o = a + f.n * 0.0
		_pointed_arch(st, f, f.w * 0.5, f.w * 0.5 - 0.3, 3.67, 0.4, 0.2, sc, 0.5)
		# low wrought-iron fence on three sides; the side facing +z stays open
		if mid.z < 1.0:
			var y0 := 0.0
			iron.quad(f.p(0.45, y0, 0.0), f.p(0.45, y0 + 1.0, 0.0), f.p(f.w - 0.45, y0 + 1.0, 0.0), f.p(f.w - 0.45, y0, 0.0), f.n, Color.WHITE, Vector2(0, 0), Vector2((f.w - 0.9) * 0.5, 0.5))
	# lintel ring and spirelet
	var top := 6.3
	for k in 4:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % 4]
		beam(st, a + Vector3(0, top, 0), b + Vector3(0, top, 0), 0.5, 0.4, sc)
	cyl(st, Vector3(0, top + 0.2, 0), 3.2, 0.0, 4.5, 4, Color(0.5, 0.49, 0.47), true, Basis(Vector3.UP, PI / 4.0))
	for p in pts:
		cyl(st, p + Vector3(0, top - 0.1, 0), 0.4, 0.0, 1.6, 4, sc)
	var m := _b("metal")
	beam(m, Vector3(0, top + 4.6, 0), Vector3(0, top + 5.8, 0), 0.08, 0.08, Color(0.05, 0.05, 0.05))
	beam(m, Vector3(-0.35, top + 5.4, 0), Vector3(0.35, top + 5.4, 0), 0.07, 0.07, Color(0.05, 0.05, 0.05))
	_flush("L", root)
	ck = save_ck
	# red glow at the bottom of the shaft
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.8, 0.0, 0.05)
	glow.emission_enabled = true
	glow.emission = Color(0.8, 0.0, 0.05)
	glow.emission_energy_multiplier = 2.5
	var disc := CylinderMesh.new()
	disc.top_radius = 1.8
	disc.bottom_radius = 1.8
	disc.height = 0.05
	disc.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.material_override = glow
	mi.position = Vector3(0, -3.15, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# colliders: the stone ring and the four piers
	var ring := StaticBody3D.new()
	root.add_child(ring)
	var ring_col := CollisionShape3D.new()
	var ring_shape := CylinderShape3D.new()
	ring_shape.radius = 2.8
	ring_shape.height = 0.5
	ring_col.shape = ring_shape
	ring_col.position.y = 0.25
	ring.add_child(ring_col)
	for p in pts:
		_static_box(Vector3(0.6, 3.5, 0.6), p + Vector3(0, 1.75, 0), root)


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
	stained_mat.emission_energy_multiplier = night * 1.4
	var pool := night * 0.22
	pool_mat.albedo_color = Color(1.0 * pool, 0.72 * pool, 0.42 * pool)
