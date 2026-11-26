extends SceneTree
## Offline builder for res://assets/characters/sol/sol_body_regions.png: a small mask in the
## body mesh's UV space that tells scripts/sol_outfit.gd's body shader which part of Sol's
## clothes a texel belongs to, so the wardrobe can recolour the shirt, trousers and boots
## without touching the mesh (its LODs and skin stay as tools/build_sol_modular.gd made them).
## Run from game/:  godot --headless -s res://tools/build_sol_regions.gd
##
##   R  region: 0 skin (kept), 85 shirt / torso, 170 trousers, 255 boots
##   G  255 on the shirt's open V at the chest (a waistcoat leaves it showing)
## Classified per triangle from its centroid in bind pose (skeleton space, metres, feet at y=0,
## facing +Z), rasterised at SIZE and dilated so texture filtering never reads past an island.

const SOL := "res://assets/characters/sol/sol_modular.scn"
const OUT := "res://assets/characters/sol/sol_body_regions.png"
const SIZE := 512
const BOOT_TOP := 0.3
const BELT := 0.985
const DILATE := 3


func _initialize() -> void:
	var m: Node = load(SOL).instantiate()
	var body := m.find_child("Body", true, false) as MeshInstance3D
	var a := body.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0))
	var written := PackedByteArray()
	written.resize(SIZE * SIZE)
	var conflicts := 0
	var counts := [0, 0, 0, 0]
	for t in range(0, idx.size(), 3):
		var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		var reg := region(c)
		var vee := 1.0 if reg == 1 and is_vee(c) else 0.0
		counts[reg] += 1
		var col := Color(reg / 3.0, vee, 0.0)
		conflicts += _raster(img, written, uv[idx[t]], uv[idx[t + 1]], uv[idx[t + 2]], col)
	for i in DILATE:
		_dilate(img, written)
	var err := img.save_png(ProjectSettings.globalize_path(OUT))
	print("build_sol_regions: tris per region %s, conflicting texels %d -> %s (%s)" % [counts, conflicts, OUT, error_string(err)])
	m.free()
	quit(0 if err == OK else 1)


static func region(c: Vector3) -> int:
	if c.y < BOOT_TOP:
		return 3
	if c.y < BELT:
		return 2
	# the neck and the open throat above the collarbones stay skin
	if c.y > 1.43 and absf(c.x) < 0.085 and c.z > -0.11:
		return 0
	return 1


## The chest V a waistcoat leaves open (the shirt and its placket show through).
static func is_vee(c: Vector3) -> bool:
	return c.z > -0.02 and c.y > 1.12 and absf(c.x) < (c.y - 1.12) * 0.32 + 0.012


func _raster(img: Image, written: PackedByteArray, a: Vector2, b: Vector2, c: Vector2, col: Color) -> int:
	var pa := a * SIZE
	var pb := b * SIZE
	var pc := c * SIZE
	var x0 := clampi(int(floor(minf(pa.x, minf(pb.x, pc.x)))), 0, SIZE - 1)
	var x1 := clampi(int(ceil(maxf(pa.x, maxf(pb.x, pc.x)))), 0, SIZE - 1)
	var y0 := clampi(int(floor(minf(pa.y, minf(pb.y, pc.y)))), 0, SIZE - 1)
	var y1 := clampi(int(ceil(maxf(pa.y, maxf(pb.y, pc.y)))), 0, SIZE - 1)
	var area := (pb - pa).cross(pc - pa)
	var n := 0
	if absf(area) < 1e-6:
		_put(img, written, clampi(int(pa.x), 0, SIZE - 1), clampi(int(pa.y), 0, SIZE - 1), col)
		return 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var w0 := (pb - p).cross(pc - p) / area
			var w1 := (pc - p).cross(pa - p) / area
			var w2 := 1.0 - w0 - w1
			if w0 >= -0.02 and w1 >= -0.02 and w2 >= -0.02:
				n += _put(img, written, x, y, col)
	return n


func _put(img: Image, written: PackedByteArray, x: int, y: int, col: Color) -> int:
	var i := y * SIZE + x
	var clash := 0
	if written[i] == 1 and not img.get_pixel(x, y).is_equal_approx(col):
		clash = 1
	img.set_pixel(x, y, col)
	written[i] = 1
	return clash


func _dilate(img: Image, written: PackedByteArray) -> void:
	var add: Array = []
	for y in SIZE:
		for x in SIZE:
			if written[y * SIZE + x] == 1:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < SIZE and ny < SIZE and written[ny * SIZE + nx] == 1:
					add.append([x, y, img.get_pixel(nx, ny)])
					break
	for e in add:
		img.set_pixel(e[0], e[1], e[2])
		written[e[1] * SIZE + e[0]] = 1
