extends RefCounted
## St. Roch's grave furniture: the meshes, textures and shaders cemetery.gd scatters as MultiMeshes
## (headstones, plot mounds, kerbs, iron plot fences, vases of dead flowers, grave candles, grass
## tufts, ground fog) and the ground and open-grave shaders. All geometry is built in code with
## city.gd's Batch helpers; every mesh stands on y = 0 and faces +z.

const LIB := "res://assets/textures/library/"


static func tex(name: String) -> Texture2D:
	var p := LIB + name + ".jpg"
	return load(p) if ResourceLoader.exists(p) else null


# ================================================================ shaders
## Dead, patchy, trampled grass over the whole cemetery. `mask` (world-mapped over `rect`):
## r worn dirt (footpaths, verges), g standing water and mud, b freshly turned soil.
## Mound mode (plot mounds as a MultiMesh): INSTANCE_CUSTOM.x is how bare the earth is.
const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D mask : filter_linear;
uniform vec4 rect = vec4(-66.0, 100.0, 132.0, 100.0);
uniform sampler2D grass_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform bool mound = false;
varying vec3 wp;
varying float bare;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bare = mound ? INSTANCE_CUSTOM.x : 0.0;
}
void fragment() {
	vec2 p = wp.xz;
	float n1 = texture(noise, p * 0.043).r;
	float n2 = texture(noise, p * 0.17 + 0.37).r;
	float n3 = texture(noise, p * 0.83 + 0.11).r;
	vec3 m = vec3(0.0);
	if (!mound) {
		vec2 warp = (vec2(n2, texture(noise, p * 0.17 + 0.71).r) - 0.5) * 1.6;
		m = texture(mask, (p - rect.xy + warp) / rect.zw).rgb;
	} else {
		m = vec3(bare, 0.0, bare * bare);
	}
	vec3 ga = texture(grass_alb, p * 0.31).rgb;
	float gl = dot(ga, vec3(0.299, 0.587, 0.114));
	vec3 straw = vec3(0.40, 0.32, 0.16);
	vec3 brown = vec3(0.21, 0.15, 0.085);
	vec3 olive = vec3(0.17, 0.18, 0.085);
	vec3 g = mix(brown, straw, smoothstep(0.32, 0.72, n1));
	g = mix(g, olive, smoothstep(0.6, 0.82, n2) * 0.55);
	g *= 0.5 + gl * 1.5;
	// bare earth: the paths plus scabby patches where nothing grows
	float dirt = m.r * 1.25 + (n2 - 0.5) * 0.8 + (n3 - 0.5) * 0.45 + smoothstep(0.8, 0.92, n1) * 0.5;
	dirt = smoothstep(0.38, 0.62, dirt);
	vec3 ma = texture(mud_alb, p * 0.37).rgb;
	vec3 d = ma * vec3(0.78, 0.68, 0.58);
	vec3 col = mix(g, d, dirt);
	float fresh = smoothstep(0.25, 0.55, m.b + (n3 - 0.5) * 0.3);
	col = mix(col, ma * vec3(0.42, 0.36, 0.31), fresh);
	float wet = smoothstep(0.32, 0.6, m.g + (n2 - 0.5) * 0.5);
	col *= mix(1.0, 0.5, wet);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.96, 0.86, dirt), 0.16, wet);
	SPECULAR = 0.4;
	vec3 nm = mix(texture(grass_nrm, p * 0.31).rgb, texture(mud_nrm, p * 0.37).rgb, max(dirt, fresh));
	NORMAL_MAP = mix(nm, vec3(0.5, 0.5, 1.0), wet * 0.85);
}
"""

## Weathered headstone stone (limestone texture, mesh UVs in metres). Vertex colour tints the
## part; INSTANCE_CUSTOM: x moss, y brightness, z warm/cool, w lichen streaks.
const STONE_SHADER := """
shader_type spatial;
uniform sampler2D alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec4 cust;
varying vec3 lp;
varying vec3 ln;
void vertex() {
	cust = INSTANCE_CUSTOM;
	lp = VERTEX;
	ln = NORMAL;
}
void fragment() {
	vec2 uv = UV * 0.42 + cust.zw * 3.7;
	vec3 a = texture(alb, uv).rgb;
	float l = dot(a, vec3(0.333));
	vec3 base = mix(vec3(l), a, 0.35) * COLOR.rgb * (0.95 + cust.y * 0.6);
	base *= mix(vec3(0.95, 0.97, 1.03), vec3(1.05, 1.0, 0.92), cust.z);
	float up = clamp(ln.y, 0.0, 1.0);
	float m = cust.x * (up * 0.7 + 0.45 - lp.y * 0.35 + (l - 0.5) * 2.2);
	m = smoothstep(0.3, 0.62, m);
	base = mix(base, vec3(0.07, 0.095, 0.045) * (0.7 + l), m);
	// rain streaks below the top edge and soil splashed up the foot
	base *= mix(0.6, 1.0, smoothstep(0.0, 0.3, lp.y));
	base *= 1.0 - cust.w * 0.35 * smoothstep(0.55, 0.75, fract(UV.x * 3.1 + l * 0.3));
	ALBEDO = base;
	ROUGHNESS = mix(0.82, 0.95, m);
	NORMAL_MAP = texture(nrm, uv).rgb;
}
"""

## Dead grass tufts: crossed alpha cards that lean in the wind. INSTANCE_CUSTOM.rgb tints.
const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D blades : source_color, filter_linear_mipmap;
varying vec3 tint;
void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	float top = 1.0 - UV.y;
	vec3 o = MODEL_MATRIX[3].xyz;
	float w = sin(TIME * 1.6 + o.x * 0.45 + o.z * 0.3) * 0.5 + sin(TIME * 2.9 + o.z * 0.8) * 0.25;
	VERTEX.x += w * 0.06 * top * top;
	VERTEX.z += w * 0.03 * top * top;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec4 t = texture(blades, UV);
	ALBEDO = t.rgb * tint;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
"""

## Grave candles: COLOR.a < 0.5 marks the flame, which flickers per instance.
const CANDLE_SHADER := """
shader_type spatial;
uniform float energy = 3.0;
varying float flick;
void vertex() {
	float k = float(INSTANCE_ID) * 1.37;
	flick = 0.75 + 0.15 * sin(TIME * 13.0 + k) + 0.1 * sin(TIME * 23.0 + k * 2.1);
}
void fragment() {
	float flame = 1.0 - step(0.5, COLOR.a);
	ALBEDO = COLOR.rgb * (1.0 - flame * 0.5);
	ROUGHNESS = mix(0.35, 1.0, flame);
	EMISSION = COLOR.rgb * flame * energy * flick + COLOR.rgb * (1.0 - flame) * 0.25 * step(0.5, COLOR.r - COLOR.g) * flick;
}
"""

## The open grave: a flat quad over the hole, shaded as the inside of a box `depth` deep
## (interior mapping), so the ground can stay a solid plate. Dark, damp earth walls.
const HOLE_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec2 half_size = vec2(0.55, 1.15);
uniform float depth = 1.8;
uniform sampler2D dirt : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 lp;
varying vec3 cam;
void vertex() {
	lp = VERTEX;
	cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}
void fragment() {
	vec3 dir = normalize(lp - cam);
	vec3 d = dir;
	if (abs(d.x) < 1e-4) d.x = 1e-4;
	if (abs(d.z) < 1e-4) d.z = 1e-4;
	d.y = min(d.y, -1e-4);
	float tx = ((d.x > 0.0 ? half_size.x : -half_size.x) - lp.x) / d.x;
	float tz = ((d.z > 0.0 ? half_size.y : -half_size.y) - lp.z) / d.z;
	float ty = (-depth - lp.y) / d.y;
	float t = min(min(tx, tz), ty);
	vec3 h = lp + d * t;
	vec2 tuv;
	float shade;
	if (t == ty) {
		tuv = h.xz;
		shade = 0.55;
	} else if (t == tx) {
		tuv = vec2(h.z, h.y);
		shade = 0.8;
	} else {
		tuv = vec2(h.x, h.y);
		shade = 0.7;
	}
	float f = clamp(-h.y / depth, 0.0, 1.0);
	vec3 c = texture(dirt, tuv * 0.9).rgb * vec3(0.62, 0.52, 0.44);
	// spade cuts and clay strata on the walls
	c *= 0.85 + 0.15 * sin(h.y * 23.0 + tuv.x * 2.0);
	c *= shade * mix(1.0, 0.12, pow(f, 0.65));
	ALBEDO = c;
	ROUGHNESS = 0.97;
	SPECULAR = 0.15;
}
"""

## Low ground fog: soft sheets that drift, fade at their edges and near the camera.
const FOG_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.42, 0.47, 0.58, 1.0);
uniform float density = 0.32;
varying vec3 wp;
varying float a0;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	a0 = INSTANCE_CUSTOM.x;
}
void fragment() {
	vec2 p = wp.xz;
	float n = texture(noise, p * 0.035 + vec2(TIME * 0.006, TIME * 0.004)).r;
	float n2 = texture(noise, p * 0.11 - vec2(TIME * 0.011, 0.0)).r;
	float e = 1.0 - smoothstep(0.25, 0.5, length(UV - 0.5));
	float a = smoothstep(0.35, 0.8, n * 0.7 + n2 * 0.45) * e * density * a0;
	float dcam = length(VERTEX);
	a *= smoothstep(1.5, 7.0, dcam);
	ALBEDO = tint.rgb;
	ALPHA = a;
}
"""


# ================================================================ textures
## Dead-grass blades on a transparent card (straw, tan and grey-brown, a few green-grey).
static func blade_texture() -> ImageTexture:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 4417
	var cols := [Color(0.55, 0.45, 0.24), Color(0.45, 0.34, 0.17), Color(0.36, 0.3, 0.2), Color(0.62, 0.53, 0.32), Color(0.3, 0.32, 0.2)]
	for b in 46:
		var x0 := r.randf_range(6.0, w - 6.0)
		var len := r.randf_range(0.45, 0.98) * h
		var lean := r.randf_range(-0.55, 0.55)
		var droop := r.randf_range(-0.4, 0.4) if r.randf() < 0.4 else 0.0
		var col: Color = cols[r.randi() % cols.size()]
		var steps := int(len)
		for s in steps:
			var t := float(s) / len
			var x := x0 + lean * s + droop * t * t * len * 0.6
			var y := h - 1 - s
			var bw := maxf(0.6, 2.2 * (1.0 - t))
			var c := col.darkened(0.35 * (1.0 - t)).lightened(0.1 * t)
			for dx in range(int(-bw), int(bw) + 1):
				var xi := int(x) + dx
				if xi >= 0 and xi < w and y >= 0:
					img.set_pixel(xi, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A tileable value-noise texture (L8) for patches, warps and fog.
static func noise_texture(c, seed_: int) -> ImageTexture:
	var data: PackedByteArray = c._noise_img(256, 0.02, seed_, 4)
	var img := Image.create_from_data(256, 256, false, Image.FORMAT_L8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ================================================================ materials
static func ground_material(c, mask: Texture2D, rect: Rect2, noise: Texture2D, mound := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = GROUND_SHADER
	m.set_shader_parameter("mask", mask)
	m.set_shader_parameter("rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	m.set_shader_parameter("grass_alb", tex("forest_floor_albedo"))
	m.set_shader_parameter("grass_nrm", tex("forest_floor_normal"))
	m.set_shader_parameter("mud_alb", tex("mud_albedo"))
	m.set_shader_parameter("mud_nrm", tex("mud_normal"))
	m.set_shader_parameter("noise", noise)
	m.set_shader_parameter("mound", mound)
	return m


static func shader_mat(code: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = code
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func stone_material() -> ShaderMaterial:
	return shader_mat(STONE_SHADER, {"alb": tex("limestone_albedo"), "nrm": tex("limestone_normal")})


static func flat_material(rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	return m


# ================================================================ mesh helpers
## A flat polygon (CCW in x/y) extruded `t` thick along z, centred on z = 0. UVs in metres.
static func extrude(bt, pts: PackedVector2Array, t: float, col: Color, xf := Transform3D.IDENTITY) -> void:
	var idx := Geometry2D.triangulate_polygon(pts)
	var zf := t * 0.5
	var nb := xf.basis.orthonormalized()
	for k in range(0, idx.size(), 3):
		var a := pts[idx[k]]
		var b := pts[idx[k + 1]]
		var d := pts[idx[k + 2]]
		bt.tri(xf * Vector3(a.x, a.y, zf), xf * Vector3(b.x, b.y, zf), xf * Vector3(d.x, d.y, zf), nb * Vector3(0, 0, 1), col, a, b, d)
		bt.tri(xf * Vector3(a.x, a.y, -zf), xf * Vector3(b.x, b.y, -zf), xf * Vector3(d.x, d.y, -zf), nb * Vector3(0, 0, -1), col, a, b, d)
	var n := pts.size()
	var u := 0.0
	for k in n:
		var a := pts[k]
		var b := pts[(k + 1) % n]
		var e := b - a
		var en := Vector2(e.y, -e.x).normalized()
		if Geometry2D.is_polygon_clockwise(pts):
			en = -en
		var nrm := nb * Vector3(en.x, en.y, 0)
		var l := e.length()
		bt.quad(xf * Vector3(a.x, a.y, -zf), xf * Vector3(a.x, a.y, zf), xf * Vector3(b.x, b.y, zf), xf * Vector3(b.x, b.y, -zf), nrm, col, Vector2(u, 0), Vector2(u + l, t))
		u += l


static func mesh_of(bt) -> ArrayMesh:
	var m := ArrayMesh.new()
	if not bt.i.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bt.arrays())
	return m


# ================================================================ headstones
const STONE_KINDS := ["round", "cross", "obelisk", "gothic", "broken", "chest"]


## One headstone mesh of the given kind (base at y = 0, inscription face +z).
static func headstone_mesh(c, kind: String) -> ArrayMesh:
	var bt = c.new_batch()
	var s := Color(0.78, 0.77, 0.74)
	var dark := Color(0.6, 0.59, 0.57)
	match kind:
		"round":
			c.box(bt, Vector3(0, 0.06, 0.02), Vector3(0.78, 0.12, 0.3), dark)
			var pts := PackedVector2Array([Vector2(-0.31, 0.1), Vector2(0.31, 0.1), Vector2(0.31, 0.72)])
			for k in range(1, 8):
				var a := PI * k / 8.0
				pts.append(Vector2(cos(a) * 0.31, 0.72 + sin(a) * 0.31))
			pts.append(Vector2(-0.31, 0.72))
			extrude(bt, pts, 0.12, s)
			# a sunk panel for the inscription
			c.box(bt, Vector3(0, 0.55, 0.062), Vector3(0.4, 0.42, 0.01), s * Color(0.8, 0.8, 0.8))
		"cross":
			c.box(bt, Vector3(0, 0.1, 0), Vector3(0.62, 0.2, 0.42), dark)
			c.box(bt, Vector3(0, 0.27, 0), Vector3(0.44, 0.14, 0.3), dark * Color(1.05, 1.05, 1.05))
			c.box(bt, Vector3(0, 0.34 + 0.58, 0), Vector3(0.13, 1.16, 0.13), s)
			c.box(bt, Vector3(0, 1.18, 0), Vector3(0.64, 0.13, 0.13), s)
		"obelisk":
			c.box(bt, Vector3(0, 0.12, 0), Vector3(0.8, 0.24, 0.8), dark)
			c.box(bt, Vector3(0, 0.24 + 0.3, 0), Vector3(0.56, 0.6, 0.56), s)
			c.box(bt, Vector3(0, 0.86, 0), Vector3(0.62, 0.06, 0.62), dark)
			var y0 := 0.89
			var y1 := 2.15
			var a0 := 0.21
			var a1 := 0.14
			c.hexa(bt, [Vector3(-a0, y0, -a0), Vector3(a0, y0, -a0), Vector3(a0, y0, a0), Vector3(-a0, y0, a0),
				Vector3(-a1, y1, -a1), Vector3(a1, y1, -a1), Vector3(a1, y1, a1), Vector3(-a1, y1, a1)], s)
			c.cyl(bt, Vector3(0, y1, 0), a1 * 1.41, 0.0, 0.26, 4, s, false, Basis(Vector3.UP, PI * 0.25))
		"gothic":
			c.box(bt, Vector3(0, 0.07, 0.02), Vector3(0.86, 0.14, 0.34), dark)
			var pts := PackedVector2Array([Vector2(-0.34, 0.12), Vector2(0.34, 0.12), Vector2(0.34, 0.86), Vector2(0.24, 1.0), Vector2(0.0, 1.14), Vector2(-0.24, 1.0), Vector2(-0.34, 0.86)])
			extrude(bt, pts, 0.13, s)
			c.box(bt, Vector3(0, 1.17, 0), Vector3(0.05, 0.16, 0.06), s)
			c.box(bt, Vector3(0, 1.2, 0), Vector3(0.14, 0.04, 0.06), s)
		"broken":
			c.box(bt, Vector3(0, 0.06, 0.02), Vector3(0.74, 0.12, 0.3), dark)
			var pts := PackedVector2Array([Vector2(-0.3, 0.1), Vector2(0.3, 0.1), Vector2(0.3, 0.46), Vector2(0.18, 0.58), Vector2(0.09, 0.44), Vector2(-0.02, 0.62), Vector2(-0.12, 0.5), Vector2(-0.3, 0.69)])
			extrude(bt, pts, 0.11, s)
			# the snapped-off top lying in the grass in front
			var top := PackedVector2Array([Vector2(-0.3, 0.0), Vector2(0.3, 0.0), Vector2(0.3, 0.28), Vector2(0.0, 0.5), Vector2(-0.3, 0.28)])
			extrude(bt, top, 0.1, s * Color(0.92, 0.92, 0.9), Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, -PI * 0.5 + 0.08), Vector3(0.12, 0.06, 0.62)))
		"chest":
			# a chest tomb: plinth, body and an overhanging lid slab, lying along z behind the head
			c.box(bt, Vector3(0, 0.07, -1.0), Vector3(1.0, 0.14, 2.1), dark)
			c.box(bt, Vector3(0, 0.14 + 0.27, -1.0), Vector3(0.84, 0.54, 1.92), s)
			c.box(bt, Vector3(0, 0.74, -1.0), Vector3(1.0, 0.1, 2.08), s * Color(0.95, 0.95, 0.95))
			for z in [-0.25, -1.75]:
				c.box(bt, Vector3(0, 0.41, -1.0 + (z + 1.0)), Vector3(0.86, 0.4, 0.04), dark)
	return mesh_of(bt)


# ================================================================ plots
## An elongated earth mound over a grave, 1 x 2.1 m, its head at z = 0 running to -z.
static func mound_mesh(c) -> ArrayMesh:
	var bt = c.new_batch()
	var nx := 6
	var nz := 10
	var hx := 0.55
	var hz := 1.1
	var hmax := 0.2
	var hf := func(u: float, v: float) -> float:
		return hmax * maxf(0.0, 1.0 - u * u) * maxf(0.0, 1.0 - pow(absf(v), 4.0))
	for i in nx:
		for j in nz:
			var u0 := -1.0 + 2.0 * i / nx
			var u1 := -1.0 + 2.0 * (i + 1) / nx
			var v0 := -1.0 + 2.0 * j / nz
			var v1 := -1.0 + 2.0 * (j + 1) / nz
			var pts := []
			var nrms := []
			for q in [[u0, v1], [u0, v0], [u1, v0], [u1, v1]]:
				var u: float = q[0]
				var v: float = q[1]
				var y: float = hf.call(u, v)
				var e := 0.05
				var dx: float = (hf.call(u + e, v) - hf.call(u - e, v)) / (2.0 * e * hx)
				var dz: float = (hf.call(u, v + e) - hf.call(u, v - e)) / (2.0 * e * hz)
				pts.append(Vector3(u * hx, y + 0.01, v * hz - hz))
				nrms.append(Vector3(-dx, 1.0, -dz).normalized())
			bt.quad_sm(pts[0], pts[1], pts[2], pts[3], nrms[0], nrms[1], nrms[2], nrms[3], Color.WHITE)
	return mesh_of(bt)


## A stone kerb round a sunken plot (1.1 x 2.2 m) with dark gravel inside.
static func kerb_mesh(c) -> ArrayMesh:
	var bt = c.new_batch()
	var s := Color(0.72, 0.71, 0.68)
	var w := 1.1
	var l := 2.2
	var t := 0.11
	var h := 0.16
	c.box(bt, Vector3(0, h * 0.5, -t * 0.5), Vector3(w, h, t), s, Basis.IDENTITY, 8)
	c.box(bt, Vector3(0, h * 0.5, -l + t * 0.5), Vector3(w, h, t), s, Basis.IDENTITY, 8)
	for sx in [-1.0, 1.0]:
		c.box(bt, Vector3(sx * (w - t) * 0.5, h * 0.5, -l * 0.5), Vector3(t, h, l - 2.0 * t), s, Basis.IDENTITY, 8)
	bt.quad(Vector3(-w * 0.5 + t, 0.07, -t), Vector3(-w * 0.5 + t, 0.07, -l + t), Vector3(w * 0.5 - t, 0.07, -l + t), Vector3(w * 0.5 - t, 0.07, -t), Vector3.UP, Color(0.25, 0.23, 0.21), Vector2.ZERO, Vector2(w, l))
	return mesh_of(bt)


## A low cast-iron railing round a plot (1.3 x 2.4 m): corner posts with ball finials, two
## rails and spear pickets, open at the head end.
static func plot_fence_mesh(c) -> ArrayMesh:
	var bt = c.new_batch()
	var col := Color(0.06, 0.055, 0.05)
	var w := 1.3
	var l := 2.4
	var h := 0.7
	var corners := [Vector3(-w * 0.5, 0, 0.1), Vector3(w * 0.5, 0, 0.1), Vector3(w * 0.5, 0, -l + 0.1), Vector3(-w * 0.5, 0, -l + 0.1)]
	for p: Vector3 in corners:
		c.box(bt, p + Vector3(0, h * 0.5 + 0.05, 0), Vector3(0.06, h + 0.1, 0.06), col, Basis.IDENTITY, 8)
		c.box(bt, p + Vector3(0, h + 0.15, 0), Vector3(0.08, 0.08, 0.08), col, Basis(Vector3(1, 0, 1).normalized(), 0.6))
	# sides and foot (the head end stays open, like a gate)
	for side in [[corners[1], corners[2]], [corners[2], corners[3]], [corners[3], corners[0]]]:
		var a: Vector3 = side[0]
		var b: Vector3 = side[1]
		for y in [0.18, h - 0.06]:
			c.beam(bt, a + Vector3(0, y, 0), b + Vector3(0, y, 0), 0.025, 0.025, col)
		var n := int(a.distance_to(b) / 0.13)
		for k in range(1, n):
			var p := a.lerp(b, float(k) / n)
			c.box(bt, p + Vector3(0, (h - 0.02) * 0.5 + 0.06, 0), Vector3(0.016, h - 0.1, 0.016), col, Basis.IDENTITY, 12)
			c.cyl(bt, p + Vector3(0, h - 0.02, 0), 0.022, 0.0, 0.07, 3, col, false)
	return mesh_of(bt)


## A bronze grave vase of dead flowers: dry stems, drooping brown heads.
static func vase_mesh(c) -> ArrayMesh:
	var bt = c.new_batch()
	var bronze := Color(0.2, 0.22, 0.15)
	c.cyl(bt, Vector3.ZERO, 0.075, 0.06, 0.08, 6, bronze)
	c.cyl(bt, Vector3(0, 0.08, 0), 0.06, 0.1, 0.18, 6, bronze, false)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var heads := [Color(0.22, 0.07, 0.05), Color(0.3, 0.2, 0.1), Color(0.18, 0.1, 0.08), Color(0.35, 0.28, 0.14)]
	for k in 7:
		var a := TAU * k / 7.0 + r.randf() * 0.4
		var lean := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.06, 0.16)
		var top := Vector3(0, r.randf_range(0.32, 0.5), 0) + lean
		var mid := Vector3(0, 0.22, 0) + lean * 0.3
		c.beam(bt, Vector3(0, 0.12, 0), mid, 0.012, 0.012, Color(0.22, 0.2, 0.1))
		var droop := top + lean.normalized() * 0.05 - Vector3(0, r.randf_range(0.0, 0.12), 0)
		c.beam(bt, mid, droop, 0.01, 0.01, Color(0.24, 0.2, 0.1))
		c.box(bt, droop, Vector3(0.05, 0.04, 0.05), heads[k % heads.size()], Basis(Vector3(1, 0, 0.3).normalized(), r.randf()))
	return mesh_of(bt)


## A red-glass grave candle; the flame (COLOR.a 0) glows through CANDLE_SHADER.
static func candle_mesh(c) -> ArrayMesh:
	var bt = c.new_batch()
	c.cyl(bt, Vector3.ZERO, 0.045, 0.05, 0.11, 6, Color(0.55, 0.06, 0.04))
	c.cyl(bt, Vector3(0, 0.11, 0), 0.05, 0.035, 0.015, 6, Color(0.2, 0.2, 0.18))
	var f := Color(1.0, 0.62, 0.22, 0.0)
	for k in 2:
		var b := Basis(Vector3.UP, k * PI * 0.5)
		var x := b.x * 0.012
		var p := Vector3(0, 0.115, 0)
		bt.quad(p - x, p - x + Vector3(0, 0.03, 0), p + x + Vector3(0, 0.03, 0), p + x, b.z, f)
		bt.tri(p - x + Vector3(0, 0.03, 0), p + Vector3(0, 0.07, 0), p + x + Vector3(0, 0.03, 0), b.z, f)
	return mesh_of(bt)


## A dead-grass tuft: three crossed cards, 0.6 m across and 0.45 m tall.
static func tuft_mesh(c) -> ArrayMesh:
	var bt = c.new_batch()
	for k in 3:
		var b := Basis(Vector3.UP, k * PI / 3.0)
		var x := b.x * 0.3
		bt.quad(-x, -x + Vector3(0, 0.45, 0), x + Vector3(0, 0.45, 0), x, b.z, Color.WHITE)
	return mesh_of(bt)


## A fog sheet: one horizontal quad, 1 x 1 (scaled per instance).
static func sheet_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uv[k])
		st.add_vertex(v[k])
	return st.commit()


# ================================================================ dig site and shed props (into city batches)
## A plain wooden casket (0.66 x 0.6 x 2.05 m) lying along local z, centred at p.
static func casket(c, p: Vector3, yaw: float, lid_open := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var wood = c._b("wood")
	var met = c._b("metal")
	var cw := Color(0.42, 0.3, 0.2)
	c.box(wood, p + b * Vector3(0, 0.25, 0), Vector3(0.62, 0.46, 2.0), cw, b)
	c.box(wood, p + b * Vector3(0, 0.03, 0), Vector3(0.66, 0.06, 2.04), cw * Color(0.8, 0.8, 0.8), b)
	var lb := b * Basis(Vector3.RIGHT, -lid_open)
	var hinge := p + b * Vector3(0, 0.48, -1.0)
	c.box(wood, hinge + lb * Vector3(0, 0.05, 1.01), Vector3(0.68, 0.1, 2.04), cw * Color(1.08, 1.05, 1.0), lb)
	c.box(wood, hinge + lb * Vector3(0, 0.12, 1.01), Vector3(0.54, 0.05, 1.9), cw * Color(1.12, 1.1, 1.05), lb)
	for sx in [-1.0, 1.0]:
		for z in [-0.6, 0.0, 0.6]:
			c.box(met, p + b * Vector3(sx * 0.335, 0.27, z), Vector3(0.03, 0.04, 0.26), Color(0.1, 0.09, 0.08), b)


## A spade stuck into the ground at p, leaning `lean` rad toward local +x.
static func shovel(c, p: Vector3, yaw: float, lean: float) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -lean)
	var wood = c._b("wood")
	var met = c._b("metal")
	c.box(met, p + b * Vector3(0, 0.08, 0), Vector3(0.24, 0.3, 0.025), Color(0.16, 0.15, 0.14), b)
	c.box(met, p + b * Vector3(0, 0.26, 0), Vector3(0.06, 0.1, 0.04), Color(0.12, 0.11, 0.1), b)
	c.box(wood, p + b * Vector3(0, 0.75, 0), Vector3(0.04, 0.9, 0.04), Color(0.5, 0.38, 0.25), b)
	c.box(wood, p + b * Vector3(0, 1.24, 0), Vector3(0.16, 0.035, 0.035), Color(0.45, 0.34, 0.22), b)
	c.box(wood, p + b * Vector3(-0.07, 1.2, 0), Vector3(0.025, 0.1, 0.03), Color(0.45, 0.34, 0.22), b)
	c.box(wood, p + b * Vector3(0.07, 1.2, 0), Vector3(0.025, 0.1, 0.03), Color(0.45, 0.34, 0.22), b)


## A hand lantern (glass lit by the lamp material), base at p. Returns the flame position.
static func lantern(c, p: Vector3, yaw := 0.0) -> Vector3:
	var b := Basis(Vector3.UP, yaw)
	var met = c._b("metal")
	var col := Color(0.08, 0.07, 0.06)
	c.box(met, p + Vector3(0, 0.02, 0), Vector3(0.2, 0.04, 0.2), col, b)
	c.box(c._b("lamp"), p + Vector3(0, 0.16, 0), Vector3(0.14, 0.22, 0.14), Color.WHITE, b)
	for k in 4:
		var d := b * Vector3(cos(k * PI * 0.5 + PI * 0.25), 0, sin(k * PI * 0.5 + PI * 0.25)) * 0.1
		c.box(met, p + d + Vector3(0, 0.16, 0), Vector3(0.02, 0.26, 0.02), col)
	c.cyl(met, p + Vector3(0, 0.29, 0), 0.12, 0.03, 0.08, 4, col, true, b * Basis(Vector3.UP, PI * 0.25))
	c.beam(met, p + Vector3(-0.06, 0.37, 0), p + Vector3(0, 0.44, 0), 0.012, 0.012, col)
	c.beam(met, p + Vector3(0.06, 0.37, 0), p + Vector3(0, 0.44, 0), 0.012, 0.012, col)
	return p + Vector3(0, 0.16, 0)


## A lumpy heap of dug earth: a rough dome `size` across (x, height, z), into the given batch.
static func dirt_heap(c, bt, p: Vector3, size: Vector3, yaw: float, seed_: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var b := Basis(Vector3.UP, yaw)
	var nu := 10
	var nv := 5
	var bumps := []
	for k in 7:
		bumps.append([r.randf_range(0, TAU), r.randf_range(0.6, 1.4), r.randf_range(0.05, 0.14)])
	var pt := func(u: float, v: float) -> Vector3:
		# u around, v from the top (0) to the rim (1)
		var a := u * TAU
		var rr := sin(v * PI * 0.5)
		var wob := 1.0
		for bp in bumps:
			wob += bp[2] * cos(a * 2.0 + bp[0]) * sin(v * PI) * bp[1]
		var y := cos(v * PI * 0.5) * size.y * (0.9 + 0.2 * sin(a * 3.0 + bumps[0][0]))
		return p + b * Vector3(cos(a) * rr * size.x * 0.5 * wob, y - 0.05 * v, sin(a) * rr * size.z * 0.5 * wob)
	for i in nu:
		for j in nv:
			var u0 := float(i) / nu
			var u1 := float(i + 1) / nu
			var v0 := float(j) / nv
			var v1 := float(j + 1) / nv
			var a: Vector3 = pt.call(u0, v1)
			var bb: Vector3 = pt.call(u0, v0)
			var d: Vector3 = pt.call(u1, v0)
			var e: Vector3 = pt.call(u1, v1)
			var nrm := (d - a).cross(bb - e).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			var col := Color(0.68, 0.55, 0.44) * (0.85 + 0.15 * r.randf())
			bt.quad(a, bb, d, e, nrm, col, Vector2(u0 * 4.0, v0 * 2.0), Vector2(u1 * 4.0, v1 * 2.0))


## A gnarled dead tree: a leaning trunk forking into crooked, tapering limbs. Returns the
## branch tips (perches for crows).
static func dead_tree(c, bt, p: Vector3, height: float, seed_: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var tips: Array = []
	var col := Color(0.32, 0.27, 0.23)
	_limb(c, bt, r, p, Vector3(r.randf_range(-0.15, 0.15), 1, r.randf_range(-0.15, 0.15)).normalized(), height * 0.42, 0.24 * height / 7.0, 0, col, tips)
	return tips


static func _limb(c, bt, r: RandomNumberGenerator, base: Vector3, dir: Vector3, length: float, rad: float, depth: int, col: Color, tips: Array) -> void:
	var segs := 3
	var p := base
	var d := dir
	var rr := rad
	for s in segs:
		d = (d + Vector3(r.randf_range(-0.35, 0.35), r.randf_range(-0.1, 0.15), r.randf_range(-0.35, 0.35))).normalized()
		var q := p + d * length / segs
		var r1 := rr * 0.82
		var up := d
		var side := up.cross(Vector3(0.3, 0.1, 1.0)).normalized()
		var basis := Basis(side, up, side.cross(up)).orthonormalized()
		c.cyl(bt, p, rr, r1, p.distance_to(q) + rr * 0.3, 5, col, false, basis)
		p = q
		rr = r1
	if depth >= 3 or rr < 0.025:
		tips.append(p)
		return
	var n := 2 if depth > 0 else 3
	for k in n:
		var a := TAU * k / n + r.randf_range(-0.6, 0.6)
		var nd := (d * 0.8 + Vector3(cos(a), r.randf_range(-0.05, 0.45), sin(a)) * 0.75).normalized()
		_limb(c, bt, r, p, nd, length * r.randf_range(0.55, 0.72), rr * 0.75, depth + 1, col, tips)
