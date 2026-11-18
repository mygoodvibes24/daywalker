extends RefCounted
## Hollow Pines' pines and the Bayou's bald cypress, as single-surface meshes for MultiMeshes.
##
## One texture atlas (assets/textures/terrain/tree_atlas.png: bark | pine-needle spray |
## Spanish moss) and one shader draw the whole tree in a single call: a bark-textured tapered
## trunk, layered alpha-scissor branch cards and moss strands. The vertex shader sways the
## crown in the wind (more towards the top, phase from the instance position) and flutters the
## cards. Per-instance colour (MultiMesh colours) varies the hue. Beyond the near range the
## forest swaps to crossed billboard impostors (impostor_mesh) of the same trees.

const SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float wind = 1.0;
uniform float tree_h = 18.0;

varying float layer;

void vertex() {
	layer = UV2.x;
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = o.x * 0.13 + o.z * 0.17;
	float k = clamp(VERTEX.y / tree_h, 0.0, 1.3);
	float sway = (sin(TIME * 1.05 + ph) * 0.65 + sin(TIME * 2.3 + ph * 1.7) * 0.2) * wind * k * k;
	VERTEX.xz += vec2(sway, sway * 0.55) * 0.45;
	if (layer > 0.5) {
		// cards flutter; moss (layer 2) swings from where it hangs (UV.y 0 top .. 1 bottom)
		float f = sin(TIME * 3.2 + VERTEX.y * 1.3 + VERTEX.x * 0.7 + ph) * 0.05;
		VERTEX += NORMAL * f * wind;
		if (layer > 1.5) {
			VERTEX.xz += vec2(sin(TIME * 1.7 + ph + VERTEX.y), cos(TIME * 1.3 + ph)) * 0.18 * UV.y * UV.y * wind;
		}
	}
}

void fragment() {
	vec2 uv = UV;
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 tc;
	if (layer < 0.5) {
		tc = vec2(fract(uv.x) / 3.0, fract(uv.y));
	} else {
		tc = vec2((floor(layer + 0.5) + clamp(uv.x, 0.004, 0.996)) / 3.0, clamp(uv.y, 0.004, 0.996));
	}
	vec2 sc = vec2(1.0 / 3.0, 1.0);
	vec4 c = textureGrad(atlas, tc, dx * sc, dy * sc);
	// keep thin cards from dissolving in the distance (alpha averages away in the mips)
	float mip = max(0.0, 0.5 * log2(max(dot(dx * 512.0, dx * 512.0), dot(dy * 512.0, dy * 512.0))));
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = layer < 0.5 ? 1.0 : clamp(c.a * (1.0 + mip * 0.35), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (layer < 0.5) {
		NORMAL_MAP = textureGrad(bark_nrm, fract(uv), dx, dy).rgb;
		NORMAL_MAP_DEPTH = 1.2;
	}
	ROUGHNESS = layer < 0.5 ? 0.9 : 0.75;
	SPECULAR = 0.3;
}
"""

const CARD_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.85;
}
"""

static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("atlas", load("res://assets/textures/terrain/tree_atlas.png"))
		_mat.set_shader_parameter("bark_nrm", load("res://assets/textures/terrain/bark_normal.jpg"))
	return _mat


## Crossed-card impostor material for a pre-rendered tree (falls back to `fallback`).
static func impostor_material(name: String, fallback: Texture2D) -> ShaderMaterial:
	var path := "res://assets/textures/terrain/%s_impostor.png" % name
	var sh := Shader.new()
	sh.code = CARD_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", load(path) if ResourceLoader.exists(path) else fallback)
	return m


class Mb:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func vert(p: Vector3, nr: Vector3, t: Vector2, layer: float, col: Color) -> int:
		v.append(p)
		n.append(nr)
		uv.append(t)
		uv2.append(Vector2(layer, 0))
		c.append(col)
		return v.size() - 1

	## A tapered tube along a polyline of centres with radii, `segs` sides, bark UVs.
	func tube(pts: Array, radii: Array, segs: int, col: Color, around := 2.0, along := 3.0, jitter: Array = []) -> void:
		var base := v.size()
		var vlen := 0.0
		for k in pts.size():
			if k > 0:
				vlen += (pts[k] as Vector3).distance_to(pts[k - 1])
			var dir: Vector3 = ((pts[mini(k + 1, pts.size() - 1)] as Vector3) - (pts[maxi(k - 1, 0)] as Vector3)).normalized()
			var side := dir.cross(Vector3.FORWARD if absf(dir.y) > 0.9 else Vector3.UP).normalized()
			if absf(dir.y) > 0.9:
				side = Vector3.RIGHT
			var fwd := side.cross(dir).normalized()
			for s in segs + 1:
				var a := TAU * s / segs
				var r: float = radii[k] * (1.0 + (jitter[k] * sin(a * 3.0 + k) if not jitter.is_empty() else 0.0))
				var off := side * cos(a) + fwd * sin(a)
				var shade := col * (0.75 + 0.25 * float(k) / maxf(pts.size() - 1, 1))
				vert(pts[k] + off * r, off, Vector2(around * s / segs, vlen / along), 0.0, shade)
		for k in pts.size() - 1:
			for s in segs:
				var a := base + k * (segs + 1) + s
				var b := a + segs + 1
				i.append_array([a, b, a + 1, a + 1, b, b + 1])

	## A bent card from `root` out along `dir` (length L, width W), drooping by `droop`, rolled
	## round its length by `roll`. UV v: 1 at the root .. 0 at the tip. layer: 1 needles, 2 moss.
	func card(root: Vector3, dir: Vector3, L: float, W: float, droop: float, roll: float, layer: float, col: Color, nrm_bias := Vector3.UP) -> void:
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		var side := Vector3.UP.cross(flat).normalized() if flat.length() > 0.01 else Vector3.RIGHT
		var up := flat.cross(side).normalized() if flat.length() > 0.01 else Vector3.FORWARD
		var wv := (side * cos(roll) + up * sin(roll)) * W * 0.5
		var rows := [0.0, 0.5, 1.0]
		var base := v.size()
		for t: float in rows:
			var p := root + dir * L * t - Vector3(0, droop * t * t, 0)
			var nr := (flat * 0.55 + nrm_bias).normalized()
			var shade := col * (0.6 + 0.4 * t)
			vert(p - wv * (0.6 + 0.4 * t), nr, Vector2(0.0, 1.0 - t), layer, shade)
			vert(p + wv * (0.6 + 0.4 * t), nr, Vector2(1.0, 1.0 - t), layer, shade)
		for r in 2:
			var a := base + r * 2
			i.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])

	## A hanging strand of moss: two crossed vertical cards, UV v 0 top .. 1 bottom.
	func strand(top: Vector3, L: float, W: float, yaw: float, col: Color) -> void:
		for k in 2:
			var a := yaw + k * PI * 0.5
			var rv := Vector3(cos(a), 0, sin(a)) * W * 0.5
			var nr := Vector3(-sin(a), 0.3, cos(a)).normalized()
			var base := v.size()
			vert(top - rv, nr, Vector2(0, 0), 2.0, col)
			vert(top + rv, nr, Vector2(1, 0), 2.0, col)
			vert(top - rv * 0.6 - Vector3(0, L, 0), nr, Vector2(0, 1), 2.0, col * 0.85)
			vert(top + rv * 0.6 - Vector3(0, L, 0), nr, Vector2(1, 1), 2.0, col * 0.85)
			i.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])

	func mesh(mat: Material) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = i
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		return m


## A tall Southern pine (height h): bare bark trunk, a crown of drooping needle sprays in
## whorls, a tuft on top. ~200 triangles, one surface.
static func pine_mesh(h: float, seed_: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var b := Mb.new()
	var s := h / 18.0
	var lean := Vector3(r.randf_range(-0.3, 0.3), 0, r.randf_range(-0.3, 0.3)) * s
	var pts: Array = []
	var radii: Array = []
	for k in 6:
		var t := k / 5.0
		pts.append(Vector3(0, h * 0.95 * t, 0) + lean * t * t)
		radii.append(lerpf(0.34, 0.05, t) * s * (1.25 if k == 0 else 1.0))
	b.tube(pts, radii, 7, Color(1, 1, 1), 1.0, 2.2 * s)
	var whorls := 7
	var ga := r.randf() * TAU
	for w in whorls:
		var t := float(w) / (whorls - 1)
		var y := h * lerpf(0.5, 0.93, t)
		var root := Vector3(0, y, 0) + lean * pow(y / h, 2.0)
		var L := h * lerpf(0.21, 0.08, t) * r.randf_range(0.85, 1.1)
		var cards := 5 if t < 0.7 else 4
		for k in cards:
			ga += 2.39996 # golden angle
			var tilt := r.randf_range(-0.05, 0.25)
			var dir := Vector3(cos(ga), tilt, sin(ga)).normalized()
			b.card(root, dir, L, L * 0.62, L * 0.28, r.randf_range(-0.45, 0.45), 1.0, Color(1, 1, 1))
	# the top tuft: crossed upright sprays
	var top := Vector3(0, h * 0.95, 0) + lean
	for k in 3:
		var a := ga + k * PI / 3.0
		b.card(top - Vector3(0, h * 0.06, 0), Vector3(cos(a) * 0.25, 1.0, sin(a) * 0.25).normalized(), h * 0.11, h * 0.07, 0.0, 0.0, 1.0, Color(1, 1, 1))
	return b.mesh(material())


## A bald cypress (height h): a buttressed trunk, crooked limbs, flat feathery pads and
## curtains of Spanish moss. ~350 triangles, one surface.
static func cypress_mesh(h: float, seed_: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var b := Mb.new()
	var bark := Color(0.82, 0.78, 0.74)
	var pts := [Vector3(0, -0.6, 0), Vector3(0, 0.6, 0), Vector3(0, 1.8, 0), Vector3(0.2, h * 0.4, 0.1), Vector3(-0.1, h * 0.7, 0.2), Vector3(0.1, h * 0.92, 0)]
	var radii := [1.35, 0.95, 0.55, 0.38, 0.26, 0.1]
	b.tube(pts, radii, 8, bark, 2.0, 2.5, [0.35, 0.3, 0.12, 0.05, 0.0, 0.0])
	var foliage := Color(0.78, 0.86, 0.6)
	var moss := Color(1, 1, 1)
	var limbs := 5
	for k in limbs:
		var a := TAU * k / limbs + r.randf_range(-0.4, 0.4)
		var y := h * r.randf_range(0.42, 0.72)
		var reach := r.randf_range(3.0, 5.2)
		var base := Vector3(0, y, 0)
		var mid := base + Vector3(cos(a) * reach * 0.5, r.randf_range(0.6, 1.4), sin(a) * reach * 0.5)
		var tip := base + Vector3(cos(a + r.randf_range(-0.3, 0.3)) * reach, r.randf_range(1.2, 2.6), sin(a) * reach)
		b.tube([base, mid, tip], [0.26, 0.17, 0.07], 4, bark, 1.0, 2.0)
		# a flat pad of feathery foliage at the tip
		for q in 5:
			var qa := a + TAU * q / 5.0 + r.randf() * 0.5
			b.card(tip + Vector3(0, 0.4, 0), Vector3(cos(qa), r.randf_range(-0.05, 0.15), sin(qa)).normalized(), r.randf_range(2.0, 2.9), 1.9, 0.5, r.randf_range(-0.3, 0.3), 1.0, foliage)
		# moss curtains off the limb
		for q in 3:
			var mp: Vector3 = base.lerp(tip, 0.3 + q * 0.3) + Vector3(0, -0.1, 0)
			b.strand(mp, r.randf_range(2.2, 4.2), r.randf_range(0.8, 1.2), r.randf() * TAU, moss)
	var crown := Vector3(0.1, h * 0.9, 0)
	for q in 6:
		var qa := TAU * q / 6.0 + r.randf() * 0.4
		b.card(crown, Vector3(cos(qa), r.randf_range(0.05, 0.3), sin(qa)).normalized(), r.randf_range(2.4, 3.3), 2.1, 0.4, r.randf_range(-0.3, 0.3), 1.0, foliage)
	for q in 3:
		b.strand(crown + Vector3(r.randf_range(-1.5, 1.5), -0.4, r.randf_range(-1.5, 1.5)), r.randf_range(2.0, 3.5), 1.0, r.randf() * TAU, moss)
	return b.mesh(material())


## Two crossed cards for the far forest (4 triangles); UV covers the impostor image.
static func impostor_mesh(h: float, w: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for a in [0.0, PI * 0.5]:
		var rt := Vector3(cos(a), 0, sin(a)) * w * 0.5
		var k := v.size()
		for p in [[-rt, Vector2(0, 1)], [-rt + Vector3(0, h, 0), Vector2(0, 0)], [rt + Vector3(0, h, 0), Vector2(1, 0)], [rt, Vector2(1, 1)]]:
			v.append(p[0])
			n.append(Vector3(0, 1, 0).lerp(Vector3(-sin(a), 0, cos(a)), 0.4).normalized())
			uv.append(p[1])
			c.append(Color.WHITE)
		idx.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
