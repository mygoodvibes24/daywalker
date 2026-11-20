extends Node3D
## The Undercroft Depths (concept art 08): the flooded gothic crypt under the cathedral plaza,
## reached down the plaza well (map/undercroft_stair.gd) and a red-lit tunnel stair. Home of the
## rival daywalker (map/undercroft_rival.gd).
##
##   the tunnel   door at the well's foot (z 3) -> vestibule -> stair down to a landing (z 12)
##   the crypt    x -9..9, z 14..38, floor y -9: three aisles of ribbed groin vaults on clustered
##                piers; a grand stair flanked by weeping angels down into black water; stepping
##                stones across to a dry dais (the duel floor); a crypt wall of carved names lined
##                with candles (west); blood fridges glowing red and the gated 1890s subway tunnel
##                (east); a stained lancet lit from the cathedral above (south)
##
## Web budget: every surface is merged into a few meshes (one per material and z-band), lit mostly
## by a baked vertex "lightmap" (candle pools, the red fridges, the cold window: COLOR drives the
## emission of the crypt shader), with seven real omni lights and no shadows; candles, flames and
## halos are three MultiMeshes. While the camera is down here the city, the sky, the sun and the
## rain are switched off (the camera gets the crypt's Environment), so the frame only pays for the
## crypt; on the street the crypt is hidden.
##
## Hooks: main.gd builds this next to the lair (UNDERCROFT HOOK); map/terrain.gd answers
## height_at() with the crypt floor while Sol is down here (loot, motes, telegraphs, kill plane);
## the Hunt gets a map POI (map/undercroft_poi.gd via hunt_director.register_poi).

const Stair = preload("res://scripts/map/undercroft_stair.gd")
const Rival = preload("res://scripts/map/undercroft_rival.gd")
const PoiScript = preload("res://scripts/map/undercroft_poi.gd")
const Terrain = preload("res://scripts/map/terrain.gd")
const PropsScript = preload("res://scripts/props.gd")

const Y := -9.0 # the crypt's dry floor
const BED := -9.25 # the flooded floor (ankle deep)
const WATER := -9.08 # the water surface
const LAND_Y := -7.4 # the tunnel's landing above the grand stair
const YS := -5.0 # vault springing
const YC := -1.45 # vault crown (the street's cover slab starts at -0.5)
const HALL := Rect2(-9.0, 14.0, 18.0, 24.0) # XZ
const XS := [-9.0, -4.5, 4.5, 9.0] # aisle / nave lines
const ZS := [14.0, 20.0, 26.0, 32.0, 38.0] # bays along the crypt
const DAIS := Rect2(-6.5, 25.5, 13.0, 12.0)
const START := Vector3(0.0, Y, 19.4) # ?undercroft drops Sol here (the stair's foot)
const RIVAL_HOME := Vector3(0.0, Y, 33.5)
## The zone where the crypt replaces the world (the camera's position, with hysteresis).
const ENTER_Y := -4.9
const EXIT_Y := -4.4
const ZONE := Rect2(-10.0, 4.0, 24.5, 35.0)

var main
var tunnel_root: Node3D
var hall_root: Node3D
var env: Environment
var inside := false
var rival: CharacterBody3D
var rival_dead := false # this Hunt / session
var poi: Node3D
var lights: Array[OmniLight3D] = []
var light_base: Array = []
var _hidden := {} # main's children we hid on the way in -> their old visibility
var _flag_done := false
var _died_inside := false
var _t := 0.0
var bake: Array = [] # [pos, Color (rgb * strength), radius]
var candle_xfs: Array = [] # Transform3D per candle
var halo_xfs: Array = []
var mats := {}
static var record := {} # user://undercroft.json: {"rival_kills": n}
static var record_path := "user://undercroft.json"


# ================================================================ build
func _ready() -> void:
	name = "UndercroftDepths"
	load_record()
	_plan_lights()
	_make_materials()
	tunnel_root = Node3D.new()
	tunnel_root.name = "Tunnel"
	add_child(tunnel_root)
	hall_root = Node3D.new()
	hall_root.name = "Crypt"
	add_child(hall_root)
	_build_tunnel()
	_build_hall()
	_build_candles()
	_build_lights()
	_build_env()
	tunnel_root.visible = false
	hall_root.visible = false


## Where the candle pools are (they also bake into the vertex light) and the other glows.
func _plan_lights() -> void:
	var warm := Color(1.0, 0.56, 0.24)
	var clusters: Array = [] # [pos, n, spread, strength]
	# the vestibule and the tunnel stair
	clusters.append([Vector3(-0.72, -3.4, 4.4), 4, 0.18, 0.9])
	clusters.append([Vector3(0.72, _tunnel_floor(8.0), 8.0), 3, 0.15, 0.8])
	clusters.append([Vector3(-0.72, _tunnel_floor(10.8), 10.8), 3, 0.15, 0.8])
	clusters.append([Vector3(0.75, LAND_Y, 13.0), 5, 0.2, 1.0])
	clusters.append([Vector3(-0.75, LAND_Y, 13.0), 5, 0.2, 1.0])
	# both sides of the grand stair
	for k in 4:
		var z := 14.6 + k * 1.15
		for sx in [-2.25, 2.25]:
			clusters.append([Vector3(sx, _grand_y(z), z), 4 - (k % 2), 0.16, 0.9])
	# the crypt wall of names: a ledge of candles
	for k in 8:
		var z := 19.5 + k * 2.45
		clusters.append([Vector3(-8.55, Y + 0.8, z), 7, 0.5, 1.0])
	# round the duel floor and on the stepping stones
	for p in [Vector3(-6.0, Y, 26.0), Vector3(6.0, Y, 26.0), Vector3(-6.1, Y, 37.1), Vector3(6.1, Y, 37.1), Vector3(-2.6, Y, 25.9), Vector3(2.6, Y, 25.9)]:
		clusters.append([p, 6, 0.35, 1.0])
	clusters.append([Vector3(0.35, Y + 0.02, 22.3), 3, 0.14, 0.6])
	clusters.append([Vector3(-0.3, Y + 0.02, 24.7), 2, 0.12, 0.5])
	for p in [Vector3(-4.5, Y, 32.0), Vector3(4.5, Y, 32.0), Vector3(-4.5, Y, 26.0), Vector3(4.5, Y, 26.0)]:
		clusters.append([p + Vector3(0.55, 0, 0.55), 3, 0.15, 0.6])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1890
	for c in clusters:
		var p: Vector3 = c[0]
		var n: int = c[1]
		var spread: float = c[2]
		for i in n:
			var off := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * spread
			var h := rng.randf_range(0.12, 0.42)
			var r := rng.randf_range(0.028, 0.045)
			candle_xfs.append(Transform3D(Basis().scaled(Vector3(r / 0.04, h / 0.3, r / 0.04)), p + off))
		halo_xfs.append(Transform3D(Basis().scaled(Vector3.ONE * (0.9 + 0.12 * n)), p + Vector3(0, 0.45, 0)))
		bake.append([p + Vector3(0, 0.4, 0), warm * (0.55 + 0.12 * n) * float(c[3]), 2.6 + 0.35 * n])
	# blood fridges (east), the subway lantern, the window lit from the cathedral (south)
	bake.append([Vector3(8.2, Y + 1.2, 17.3), Color(1.0, 0.05, 0.04) * 2.6, 5.5])
	bake.append([Vector3(7.6, Y + 1.9, 30.2), warm * 1.6, 5.0])
	bake.append([Vector3(0.0, -4.5, 37.2), Color(0.35, 0.42, 0.8) * 1.3, 9.0])
	# the red glow breathing up the tunnel from the crypt, and the well's red light at the door
	bake.append([Vector3(0.0, -2.6, 3.4), Color(1.0, 0.1, 0.05) * 1.2, 3.5])


func _tunnel_floor(z: float) -> float:
	return lerpf(-3.4, LAND_Y, clampf((z - 5.0) / 7.0, 0.0, 1.0))


## Grand stair (z 14 -> 18.5) height at z.
func _grand_y(z: float) -> float:
	var k := clampi(int((z - 14.0) / 0.5), 0, 8)
	return LAND_Y - (k + 1) * (LAND_Y - Y) / 9.0


# ---------------------------------------------------------------- materials
const CRYPT_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.33;
uniform float baked = 1.0;
uniform float wet = 0.3;
uniform float albedo_mul = 0.5;
void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 a = texture(albedo_tex, uv).rgb * tint.rgb;
	ALBEDO = a * albedo_mul;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	ROUGHNESS = mix(texture(rough_tex, uv).r, 0.18, wet);
	SPECULAR = 0.5;
	// the baked candle light (vertex colour) as light the stone gives back
	EMISSION = a * COLOR.rgb * baked;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;
uniform float baked = 1.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float t = TIME * 0.35;
	vec2 p = wp.xz;
	float n1 = vn(p * 1.7 + vec2(t, t * 0.6));
	float n2 = vn(p * 3.9 - vec2(t * 0.8, t * 1.3));
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.5 + (n2 - 0.5) * 0.25, 1.0, (n2 - 0.5) * 0.5 - (n1 - 0.5) * 0.2));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	ALBEDO = vec3(0.004, 0.005, 0.006);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	// the candle pools mirrored: the baked light, broken up by the ripples and stretched toward the eye
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float streak = 0.35 + 0.9 * smoothstep(0.35, 0.8, n1 * 0.6 + n2 * 0.6);
	EMISSION = COLOR.rgb * baked * (0.25 + 0.8 * fres) * streak;
}
"""

const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.25, 1.0);
uniform float strength = 1.0;
varying float flick;
void vertex() {
	float id = float(INSTANCE_ID);
	flick = 0.75 + 0.25 * sin(TIME * (9.0 + mod(id, 5.0)) + id * 1.7) * sin(TIME * 3.1 + id);
	// a small camera-facing flame on top of the candle (instance origin = candle foot)
	vec3 top = (MODEL_MATRIX * vec4(0.0, 0.3, 0.0, 1.0)).xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 w = top + right * VERTEX.x * 0.05 + up * (VERTEX.y + 0.5) * 0.11 * flick + up * 0.01;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}
void fragment() {
	vec2 c = UV - vec2(0.5, 0.62);
	float d = length(c * vec2(2.2, 1.2));
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 1.6);
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.95, 0.8), clamp(1.0 - d * 2.0, 0.0, 1.0)) * strength * 2.4 * flick;
	ALPHA = a;
}
"""

const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.22, 1.0);
uniform float strength = 0.32;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 2.6);
	ALBEDO = tint.rgb;
	ALPHA = a * strength * (0.9 + 0.1 * sin(TIME * 7.0 + float(INSTANCE_ID)));
}
"""


func _lib(name: String) -> Array:
	var out := []
	for k in ["albedo", "normal", "roughness"]:
		var p := "res://assets/textures/library/%s_%s.jpg" % [name, k]
		out.append(load(p) if ResourceLoader.exists(p) else null)
	return out


func _crypt_mat(tex: String, tile: float, tint: Color, wet := 0.3, albedo_mul := 0.5) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = CRYPT_SHADER
	if not mats.has("_crypt_shader"):
		mats["_crypt_shader"] = sh
	var m := ShaderMaterial.new()
	m.shader = mats["_crypt_shader"]
	var t := _lib(tex)
	if t[0] != null:
		m.set_shader_parameter("albedo_tex", t[0])
	if t[1] != null:
		m.set_shader_parameter("normal_tex", t[1])
	if t[2] != null:
		m.set_shader_parameter("rough_tex", t[2])
	m.set_shader_parameter("uv_scale", 1.0 / tile)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("wet", wet)
	m.set_shader_parameter("albedo_mul", albedo_mul)
	return m


func _make_materials() -> void:
	mats["stone"] = _crypt_mat("limestone", 3.0, Color(0.78, 0.74, 0.68), 0.25)
	mats["rib"] = _crypt_mat("limestone", 2.0, Color(0.6, 0.57, 0.52), 0.15)
	mats["brick"] = _crypt_mat("brick", 2.0, Color(0.7, 0.62, 0.56), 0.35)
	mats["floor"] = _crypt_mat("wet_cobblestone", 2.5, Color(0.8, 0.78, 0.74), 0.65)
	mats["names"] = _crypt_mat("limestone", 1.6, Color(0.72, 0.68, 0.6), 0.1)
	var water := ShaderMaterial.new()
	water.shader = Shader.new()
	water.shader.code = WATER_SHADER
	mats["water"] = water
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.05, 0.045, 0.04)
	iron.metallic = 0.7
	iron.roughness = 0.45
	iron.vertex_color_use_as_albedo = false
	mats["iron"] = iron
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.85, 0.78, 0.62)
	wax.emission_enabled = true
	wax.emission = Color(1.0, 0.62, 0.3)
	wax.emission_energy_multiplier = 0.35
	wax.roughness = 0.6
	mats["wax"] = wax
	var fl := ShaderMaterial.new()
	fl.shader = Shader.new()
	fl.shader.code = FLAME_SHADER
	mats["flame"] = fl
	var ha := ShaderMaterial.new()
	ha.shader = Shader.new()
	ha.shader.code = HALO_SHADER
	mats["halo"] = ha
	# the blood fridges' glass: bags hanging in red light
	var fridge := StandardMaterial3D.new()
	fridge.albedo_texture = _fridge_texture()
	fridge.emission_enabled = true
	fridge.emission_texture = fridge.albedo_texture
	fridge.emission = Color(1, 1, 1)
	fridge.emission_energy_multiplier = 2.2
	fridge.roughness = 0.1
	fridge.metallic = 0.3
	mats["fridge"] = fridge
	# the stained lancet, lit from the cathedral above
	var glass := StandardMaterial3D.new()
	glass.albedo_texture = _glass_texture()
	glass.emission_enabled = true
	glass.emission_texture = glass.albedo_texture
	glass.emission = Color(1, 1, 1)
	glass.emission_energy_multiplier = 1.6
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["glass"] = glass
	mats["lamp"] = _glow(Color(1.0, 0.72, 0.38), 5.0)
	mats["distant"] = _glow(Color(1.0, 0.85, 0.6), 2.5)
	mats["void"] = _glow(Color(0, 0, 0), 0.0)
	(mats["void"] as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func _fridge_texture() -> ImageTexture:
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.42, 0.02, 0.02))
	# three shelves of hanging bags, each a dark sack with a bright rim and a tube
	for row in 3:
		var y0 := 10 + row * 40
		img.fill_rect(Rect2i(0, y0 + 31, w, 2), Color(0.85, 0.75, 0.7))
		for col in 4:
			var x0 := 3 + col * 15
			for yy in 22:
				for xx in 11:
					var cx := (xx - 5.0) / 5.5
					var cy := (yy - 11.0) / 11.5
					if cx * cx + cy * cy * 0.6 < 1.0:
						var rim := cx * cx + cy * cy * 0.6 > 0.62
						img.set_pixel(x0 + xx, y0 + 6 + yy, Color(1.0, 0.2, 0.15) if rim else Color(0.32, 0.0, 0.01))
			img.fill_rect(Rect2i(x0 + 5, y0, 1, 7), Color(0.9, 0.85, 0.8))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _glass_texture() -> ImageTexture:
	var w := 32
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var pal := [Color(0.65, 0.08, 0.1), Color(0.12, 0.2, 0.6), Color(0.85, 0.6, 0.18), Color(0.1, 0.4, 0.25), Color(0.5, 0.12, 0.5)]
	for cy in 12:
		for cx in 4:
			var c: Color = pal[rng.randi() % pal.size()] * rng.randf_range(0.7, 1.15)
			img.fill_rect(Rect2i(cx * 8, cy * 8, 8, 8), c)
	# lead lines
	for y in range(0, h, 8):
		img.fill_rect(Rect2i(0, y, w, 1), Color(0.02, 0.02, 0.02))
	for x in range(0, w, 8):
		img.fill_rect(Rect2i(x, 0, 1, h), Color(0.02, 0.02, 0.02))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- geometry
## A mesh builder that bakes the planned lights into vertex colours as it goes. Quads are
## subdivided to about `cell` metres so the candle pools have vertices to land on. UVs are
## planar in metres (picked by the face normal).
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var bake: Array
	var ambient := Color(0.035, 0.032, 0.036)

	func _init(b: Array) -> void:
		bake = b

	func lit(p: Vector3, nrm: Vector3, tint: Color) -> Color:
		var c := ambient
		for L in bake:
			var d: Vector3 = L[0] - p
			var r: float = L[2]
			var dist := d.length()
			if dist >= r:
				continue
			var att := pow(1.0 - dist / r, 2.0)
			var lam := clampf(nrm.dot(d / maxf(dist, 0.001)) * 0.6 + 0.45, 0.0, 1.0)
			c += (L[1] as Color) * att * lam
		return Color(c.r * tint.r, c.g * tint.g, c.b * tint.b)

	static func _uv(p: Vector3, nrm: Vector3) -> Vector2:
		var a := nrm.abs()
		if a.y >= a.x and a.y >= a.z:
			return Vector2(p.x, p.z)
		if a.x >= a.z:
			return Vector2(p.z, -p.y)
		return Vector2(p.x, -p.y)

	func vert(p: Vector3, nrm: Vector3, tint: Color, uvo := Vector2.INF) -> int:
		v.append(p)
		n.append(nrm)
		uv.append(_uv(p, nrm) if uvo == Vector2.INF else uvo)
		col.append(lit(p, nrm, tint))
		return v.size() - 1

	func tri_i(a: int, b: int, c: int, nrm: Vector3) -> void:
		# Godot's front faces are clockwise
		if (v[b] - v[a]).cross(v[c] - v[a]).dot(nrm) > 0.0:
			idx.append(a); idx.append(c); idx.append(b)
		else:
			idx.append(a); idx.append(b); idx.append(c)

	## a b c d around the quad; nrm its facing. Subdivided into cells about `cell` m.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, tint := Color.WHITE, cell := 1.2) -> void:
		var nu := clampi(ceili(a.distance_to(b) / cell), 1, 24)
		var nv := clampi(ceili(a.distance_to(d) / cell), 1, 24)
		var base := v.size()
		for j in nv + 1:
			for i in nu + 1:
				var s := float(i) / nu
				var t := float(j) / nv
				var p := a.lerp(b, s).lerp(d.lerp(c, s), t)
				vert(p, nrm, tint)
		for j in nv:
			for i in nu:
				var k := base + j * (nu + 1) + i
				tri_i(k, k + 1, k + nu + 2, nrm)
				tri_i(k, k + nu + 2, k + nu + 1, nrm)

	## Axis-aligned box (skip: 1 +x, 2 -x, 4 +y, 8 -y, 16 +z, 32 -z).
	func box(c: Vector3, s: Vector3, tint := Color.WHITE, skip := 8, cell := 1.2) -> void:
		var h := s * 0.5
		var x0 := c.x - h.x
		var x1 := c.x + h.x
		var y0 := c.y - h.y
		var y1 := c.y + h.y
		var z0 := c.z - h.z
		var z1 := c.z + h.z
		if skip & 4 == 0:
			quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, tint, cell)
		if skip & 8 == 0:
			quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN, tint, cell)
		if skip & 1 == 0:
			quad(Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3.RIGHT, tint, cell)
		if skip & 2 == 0:
			quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT, tint, cell)
		if skip & 16 == 0:
			quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, tint, cell)
		if skip & 32 == 0:
			quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.FORWARD, tint, cell)

	## A beam between two points (square section w x h), for ribs and rails.
	func beam(p0: Vector3, p1: Vector3, w: float, h: float, tint := Color.WHITE, up := Vector3.UP) -> void:
		var z := (p1 - p0)
		var len := z.length()
		if len < 0.001:
			return
		z /= len
		var x := up.cross(z).normalized()
		if x.length() < 0.5:
			x = Vector3.RIGHT
		var y := z.cross(x).normalized()
		var hx := x * w * 0.5
		var hy := y * h * 0.5
		var corners := [hx + hy, -hx + hy, -hx - hy, hx - hy]
		var norms := [y, -x, -y, x]
		for k in 4:
			var ca: Vector3 = corners[k]
			var cb: Vector3 = corners[(k + 1) % 4]
			quad(p0 + ca, p0 + cb, p1 + cb, p1 + ca, norms[k], tint, 4.0)

	## An octagonal shaft from y0 to y1 at (x, z).
	func shaft(c: Vector3, r: float, h: float, tint := Color.WHITE, sides := 8) -> void:
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var nm := (d0 + d1).normalized()
			quad(c + d0 * r, c + d1 * r, c + d1 * r + Vector3(0, h, 0), c + d0 * r + Vector3(0, h, 0), nm, tint, 1.0)

	func mesh(mat: Material) -> ArrayMesh:
		var m := ArrayMesh.new()
		if idx.is_empty():
			return m
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_COLOR] = col
		a[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		m.surface_set_material(0, mat)
		return m


var _geos := {} # "band|mat" -> Geo


func G(mat: String, band := "t") -> Geo:
	var key := band + "|" + mat
	if not _geos.has(key):
		_geos[key] = Geo.new(bake)
	return _geos[key]


## Which z-band a point belongs to (each band is its own mesh, so a light touches few meshes).
static func band(z: float) -> String:
	if z < 13.5:
		return "t"
	if z < 22.0:
		return "a"
	if z < 30.0:
		return "b"
	return "c"


func _flush_geo(parent: Node3D, prefix: String) -> void:
	for key in _geos.keys():
		if not String(key).begins_with(prefix + "|"):
			continue
		var g: Geo = _geos[key]
		var mat: String = String(key).split("|")[1]
		if g.idx.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Geo_" + String(key).replace("|", "_")
		mi.mesh = g.mesh(mats[mat])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		_geos.erase(key)


var col_faces := PackedVector3Array() # the tunnel's trimesh collider
var col_body: StaticBody3D


func _col_box(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = s
	cs.shape = b
	cs.position = c
	col_body.add_child(cs)


func _col_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	col_faces.append_array([a, b, c, a, c, d])


## A convex block whose foot spreads `spread` m wider than its top: walkable chamfered edges.
func _col_chamfer(r: Rect2, top: float, bottom: float, spread: float) -> void:
	var pts := PackedVector3Array()
	for yy in [[top, 0.0], [bottom, spread]]:
		var g := r.grow(yy[1])
		for p in [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]:
			pts.append(Vector3(p.x, yy[0], p.y))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	col_body.add_child(cs)


# ---------------------------------------------------------------- the tunnel
func _build_tunnel() -> void:
	col_body = StaticBody3D.new()
	col_body.name = "DepthsCol"
	add_child(col_body)
	var W := 1.0 # half width
	var sc := Color(0.86, 0.82, 0.76)
	var st := G("stone", "t")
	var br := G("brick", "t")
	var fl := G("floor", "t")
	# floor: the vestibule (flat), the stair (steps), the landing
	fl.quad(Vector3(-W, -3.4, 2.75), Vector3(W, -3.4, 2.75), Vector3(W, -3.4, 5.0), Vector3(-W, -3.4, 5.0), Vector3.UP, sc)
	var n := 22
	var rise := (-3.4 - LAND_Y) / n
	var tread := 7.0 / n
	for k in n:
		var z0 := 5.0 + k * tread
		var y := -3.4 - (k + 1) * rise
		st.quad(Vector3(-W, y, z0), Vector3(W, y, z0), Vector3(W, y, z0 + tread), Vector3(-W, y, z0 + tread), Vector3.UP, sc * (0.9 + 0.1 * float(k % 2)), 2.0)
		st.quad(Vector3(-W, y, z0), Vector3(W, y, z0), Vector3(W, y + rise, z0), Vector3(-W, y + rise, z0), Vector3.FORWARD, sc * 0.75, 2.0)
	fl.quad(Vector3(-W, LAND_Y, 12.0), Vector3(W, LAND_Y, 12.0), Vector3(W, LAND_Y, 14.2), Vector3(-W, LAND_Y, 14.2), Vector3.UP, sc)
	# walls (brick) and a pointed barrel vault (stone) following the floor
	var segs := 28
	for s in segs:
		var za := 2.75 + (14.2 - 2.75) * s / segs
		var zb := 2.75 + (14.2 - 2.75) * (s + 1) / segs
		var fa := _tunnel_floor(za)
		var fb := _tunnel_floor(zb)
		var ha := fa + 2.0
		var hb := fb + 2.0
		for sx in [-1.0, 1.0]:
			br.quad(Vector3(sx * W, fa, za), Vector3(sx * W, fb, zb), Vector3(sx * W, hb, zb), Vector3(sx * W, ha, za), Vector3(-sx, 0, 0), Color(0.8, 0.75, 0.7), 1.0)
		# vault: 6 facets across, pointed
		var facets := 6
		for q in facets:
			var u0 := -1.0 + 2.0 * q / facets
			var u1 := -1.0 + 2.0 * (q + 1) / facets
			var p0a := Vector3(u0 * W, ha + 0.7 * _pointed(u0), za)
			var p1a := Vector3(u1 * W, ha + 0.7 * _pointed(u1), za)
			var p0b := Vector3(u0 * W, hb + 0.7 * _pointed(u0), zb)
			var p1b := Vector3(u1 * W, hb + 0.7 * _pointed(u1), zb)
			var nm := -(p1a - p0a).cross(p0b - p0a).normalized()
			if nm.y > 0.0:
				nm = -nm
			st.quad(p0a, p1a, p1b, p0b, nm, sc * 0.8, 2.0)
		# ribs every 2 m
		if s % 5 == 0:
			for q in facets:
				var u0 := -1.0 + 2.0 * q / facets
				var u1 := -1.0 + 2.0 * (q + 1) / facets
				G("rib", "t").beam(Vector3(u0 * W * 0.98, ha + 0.7 * _pointed(u0) - 0.06, za), Vector3(u1 * W * 0.98, ha + 0.7 * _pointed(u1) - 0.06, za), 0.18, 0.14, sc)
			for sx in [-1.0, 1.0]:
				G("rib", "t").box(Vector3(sx * (W - 0.08), (fa + ha) * 0.5, za), Vector3(0.18, ha - fa, 0.22), sc, 8, 4.0)
	# colliders: floor ramp, walls, ceiling
	_col_quad(Vector3(-W, -3.4, 2.6), Vector3(W, -3.4, 2.6), Vector3(W, -3.4, 5.0), Vector3(-W, -3.4, 5.0))
	_col_quad(Vector3(-W, -3.4, 5.0), Vector3(W, -3.4, 5.0), Vector3(W, LAND_Y, 12.0), Vector3(-W, LAND_Y, 12.0))
	_col_quad(Vector3(-W, LAND_Y, 12.0), Vector3(W, LAND_Y, 12.0), Vector3(W, LAND_Y, 14.3), Vector3(-W, LAND_Y, 14.3))
	for s in segs:
		var za := 2.6 + (14.2 - 2.6) * s / segs
		var zb := 2.6 + (14.2 - 2.6) * (s + 1) / segs
		var fa := _tunnel_floor(za)
		var fb := _tunnel_floor(zb)
		for sx in [-1.0, 1.0]:
			_col_quad(Vector3(sx * W, fa - 0.5, za), Vector3(sx * W, fb - 0.5, zb), Vector3(sx * W, fb + 2.8, zb), Vector3(sx * W, fa + 2.8, za))
		_col_quad(Vector3(-W, fa + 2.55, za), Vector3(W, fa + 2.55, za), Vector3(W, fb + 2.55, zb), Vector3(-W, fb + 2.55, zb))
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(col_faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	col_body.add_child(cs)
	_flush_geo(tunnel_root, "t")


## Pointed-arch profile: 1 at the crown (t = 0), 0 at the springing (|t| = 1).
static func _pointed(t: float) -> float:
	var rho := 1.35
	var top := sqrt(rho * rho - (rho - 1.0) * (rho - 1.0))
	var a := clampf(absf(t), 0.0, 1.0) + rho - 1.0
	return sqrt(maxf(rho * rho - a * a, 0.0)) / top


# ---------------------------------------------------------------- the crypt
func _build_hall() -> void:
	var sc := Color(0.82, 0.78, 0.72)
	# --- floors: the flooded bed, the water, the dry floors
	var dry: Array = [
		DAIS,
		Rect2(-9.0, 14.0, 2.5, 24.0), # west walk (the names wall)
		Rect2(6.5, 14.0, 2.5, 24.0), # east walk (fridges, the subway)
		Rect2(-2.6, 18.4, 5.2, 1.7), # the stair's foot
	]
	for z0 in [14.0, 20.0, 26.0, 32.0]:
		var b := band(z0 + 1.0)
		G("floor", b).quad(Vector3(-9, BED, z0), Vector3(9, BED, z0), Vector3(9, BED, z0 + 6), Vector3(-9, BED, z0 + 6), Vector3.UP, Color(0.5, 0.5, 0.5), 1.5)
		G("water", b).quad(Vector3(-6.5, WATER, z0), Vector3(6.5, WATER, z0), Vector3(6.5, WATER, z0 + 6), Vector3(-6.5, WATER, z0 + 6), Vector3.UP, Color.WHITE, 0.8)
	for r: Rect2 in dry:
		_slab(r, Y, sc)
	_col_box(Vector3(0, BED - 0.5, 26.0), Vector3(18.2, 1.0, 24.2))
	for r: Rect2 in dry:
		_col_chamfer(r, Y, BED - 0.02, 0.45)
	# stepping stones from the stair's foot to the duel floor
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var zz := 20.85
	for k in 4:
		var c := Vector3(rng.randf_range(-0.35, 0.35), Y + 0.02, zz)
		var s := Vector2(rng.randf_range(1.0, 1.25), rng.randf_range(0.8, 0.95))
		_stone(c, s, rng.randf_range(-0.25, 0.25))
		_col_chamfer(Rect2(c.x - s.x * 0.5, c.z - s.y * 0.5, s.x, s.y), Y + 0.02, BED - 0.02, 0.35)
		zz += 1.2
	# --- the grand stair down from the landing, flanked by angels
	for k in 9:
		var z0 := 14.0 + k * 0.5
		var y := LAND_Y - (k + 1) * (LAND_Y - Y) / 9.0
		var g := G("stone", "a")
		g.quad(Vector3(-2.6, y, z0), Vector3(2.6, y, z0), Vector3(2.6, y, z0 + 0.5), Vector3(-2.6, y, z0 + 0.5), Vector3.UP, sc * (0.9 + 0.1 * float(k % 2)), 1.4)
		g.quad(Vector3(-2.6, y - (LAND_Y - Y) / 9.0, z0), Vector3(2.6, y - (LAND_Y - Y) / 9.0, z0), Vector3(2.6, y, z0), Vector3(-2.6, y, z0), Vector3.FORWARD, sc * 0.7, 1.4)
		for sx in [-1.0, 1.0]:
			g.quad(Vector3(sx * 2.6, BED, z0), Vector3(sx * 2.6, BED, z0 + 0.5), Vector3(sx * 2.6, y, z0 + 0.5), Vector3(sx * 2.6, y, z0), Vector3(sx, 0, 0), sc * 0.65, 1.4)
	var ramp := PackedVector3Array()
	ramp.append_array([Vector3(-2.6, LAND_Y, 14.0), Vector3(2.6, LAND_Y, 14.0), Vector3(2.6, Y, 18.5), Vector3(-2.6, LAND_Y, 14.0), Vector3(2.6, Y, 18.5), Vector3(-2.6, Y, 18.5)])
	var rs := ConcavePolygonShape3D.new()
	rs.backface_collision = true
	rs.set_faces(ramp)
	var rcs := CollisionShape3D.new()
	rcs.shape = rs
	col_body.add_child(rcs)
	# stair side walls (keep Sol off the drop beside the steps up top)
	for sx in [-1.0, 1.0]:
		_col_box(Vector3(sx * 2.75, LAND_Y + 0.2, 15.2), Vector3(0.3, 2.0, 2.4))
	var angel_xfs: Array = []
	for sx in [-1.0, 1.0]:
		var pp := Vector3(sx * 3.45, Y, 15.4)
		_pedestal(pp, 1.7)
		angel_xfs.append(Transform3D(Basis(Vector3.UP, PI + sx * 0.45), pp + Vector3(0, 1.7, 0)))
	for sx in [-1.0, 1.0]:
		var pp := Vector3(sx * 7.6, Y, 36.6)
		_pedestal(pp, 1.3)
		angel_xfs.append(Transform3D(Basis(Vector3.UP, PI - sx * 0.6), pp + Vector3(0, 1.3, 0)))
	# --- piers and vaults
	for x in [-4.5, 4.5]:
		for z in [20.0, 26.0, 32.0]:
			_pier(Vector3(x, BED, z))
			_col_cyl(Vector3(x, BED, z), 0.62, YS - BED + 0.5)
	for iz in 4:
		for ix in 3:
			var cx: float = (XS[ix] + XS[ix + 1]) * 0.5
			var cz: float = (ZS[iz] + ZS[iz + 1]) * 0.5
			_vault(cx, cz, (XS[ix + 1] - XS[ix]) * 0.5, (ZS[iz + 1] - ZS[iz]) * 0.5)
	_col_box(Vector3(0, YC + 0.3, 26.0), Vector3(18.4, 0.6, 24.4)) # the camera stays under the vaults
	# --- walls
	_walls(sc)
	_names_wall()
	_fridges()
	_subway()
	_window()
	# --- angels (one MultiMesh of the generated statue)
	_angels(angel_xfs)
	for b in ["a", "b", "c"]:
		_flush_geo(hall_root, b)


func _slab(r: Rect2, top: float, sc: Color) -> void:
	var cz := r.get_center().y
	var g := G("floor", band(cz))
	g.quad(Vector3(r.position.x, top, r.position.y), Vector3(r.end.x, top, r.position.y), Vector3(r.end.x, top, r.end.y), Vector3(r.position.x, top, r.end.y), Vector3.UP, sc, 1.0)
	# kerb faces down to the water
	var e := G("stone", band(cz))
	var k := sc * 0.6
	e.quad(Vector3(r.position.x, BED, r.position.y), Vector3(r.end.x, BED, r.position.y), Vector3(r.end.x, top, r.position.y), Vector3(r.position.x, top, r.position.y), Vector3.FORWARD, k, 2.0)
	e.quad(Vector3(r.position.x, BED, r.end.y), Vector3(r.end.x, BED, r.end.y), Vector3(r.end.x, top, r.end.y), Vector3(r.position.x, top, r.end.y), Vector3.BACK, k, 2.0)
	e.quad(Vector3(r.position.x, BED, r.position.y), Vector3(r.position.x, BED, r.end.y), Vector3(r.position.x, top, r.end.y), Vector3(r.position.x, top, r.position.y), Vector3.LEFT, k, 2.0)
	e.quad(Vector3(r.end.x, BED, r.position.y), Vector3(r.end.x, BED, r.end.y), Vector3(r.end.x, top, r.end.y), Vector3(r.end.x, top, r.position.y), Vector3.RIGHT, k, 2.0)


## A rough stepping stone: an irregular octagon slab.
func _stone(c: Vector3, s: Vector2, yaw: float) -> void:
	var g := G("stone", band(c.z))
	var pts: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.z * 100.0)
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var p := Vector2(cos(a) * s.x * 0.5, sin(a) * s.y * 0.5) * rng.randf_range(0.88, 1.08)
		p = p.rotated(yaw)
		pts.append(Vector3(c.x + p.x, c.y, c.z + p.y))
	var top := c + Vector3(0, 0.03, 0)
	var tint := Color(0.7, 0.68, 0.64)
	for k in 8:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % 8]
		var i0 := g.vert(top, Vector3.UP, tint)
		var i1 := g.vert(a, Vector3.UP, tint)
		var i2 := g.vert(b, Vector3.UP, tint)
		g.tri_i(i0, i1, i2, Vector3.UP)
		var out := ((a + b) * 0.5 - c).normalized()
		out.y = 0.0
		g.quad(Vector3(a.x, BED, a.z), Vector3(b.x, BED, b.z), b, a, out.normalized(), tint * 0.7, 2.0)


func _pedestal(p: Vector3, h: float) -> void:
	var g := G("stone", band(p.z))
	var sc := Color(0.72, 0.7, 0.64)
	g.box(p + Vector3(0, -0.1, 0), Vector3(1.35, 0.3, 1.35), sc * 0.8)
	g.box(p + Vector3(0, h * 0.5, 0), Vector3(1.0, h - 0.2, 1.0), sc)
	g.box(p + Vector3(0, h - 0.08, 0), Vector3(1.22, 0.16, 1.22), sc * 1.05)
	_col_box(p + Vector3(0, h * 0.5 + 0.6, 0), Vector3(1.1, h + 1.6, 1.1))


## A clustered pier: an octagonal core, four colonnettes, a plinth and a capital.
func _pier(p: Vector3) -> void:
	var g := G("rib", band(p.z))
	var sc := Color(0.8, 0.76, 0.7)
	var h := YS - p.y
	g.box(p + Vector3(0, 0.45, 0), Vector3(1.3, 0.9, 1.3), sc * 0.75)
	g.shaft(p + Vector3(0, 0.9, 0), 0.42, h - 1.2, sc)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		g.shaft(p + Vector3(cos(a) * 0.43, 0.9, sin(a) * 0.43), 0.11, h - 1.2, sc * 0.9, 6)
	g.box(p + Vector3(0, h - 0.15, 0), Vector3(1.25, 0.3, 1.25), sc * 0.85)


func _col_cyl(base: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	cs.position = base + Vector3(0, h * 0.5, 0)
	col_body.add_child(cs)


## A ribbed groin vault over one bay: two pointed barrels crossing (the surface is the higher of
## the two), diagonal ribs along the groins and arch ribs round the edges.
func _vault(cx: float, cz: float, hx: float, hz: float) -> void:
	var b := band(cz)
	var g := G("stone", b)
	var N := 10
	var sc := Color(0.62, 0.6, 0.56)
	var rise := YC - YS
	var base := g.v.size()
	for j in N + 1:
		for i in N + 1:
			var u := -1.0 + 2.0 * i / N
			var w := -1.0 + 2.0 * j / N
			var p := Vector3(cx + u * hx, YS + rise * maxf(_pointed(u), _pointed(w)), cz + w * hz)
			var e := 0.02
			var du := (YS + rise * maxf(_pointed(u + e), _pointed(w))) - (YS + rise * maxf(_pointed(u - e), _pointed(w)))
			var dw := (YS + rise * maxf(_pointed(u), _pointed(w + e))) - (YS + rise * maxf(_pointed(u), _pointed(w - e)))
			var nm := Vector3(du / (2.0 * e * hx), -1.0, dw / (2.0 * e * hz)).normalized()
			if absf(u) > 0.999 or absf(w) > 0.999:
				nm = Vector3(0, -1, 0)
			g.vert(p, nm, sc, Vector2(p.x + p.y * 0.3, p.z + p.y * 0.3))
	for j in N:
		for i in N:
			var k := base + j * (N + 1) + i
			g.tri_i(k, k + 1, k + N + 2, Vector3.DOWN)
			g.tri_i(k, k + N + 2, k + N + 1, Vector3.DOWN)
	# ribs
	var r := G("rib", b)
	var rc := Color(0.78, 0.74, 0.68)
	var M := 12
	for diag in [1.0, -1.0]:
		for s in M:
			var t0 := -1.0 + 2.0 * s / M
			var t1 := -1.0 + 2.0 * (s + 1) / M
			var a := Vector3(cx + t0 * hx, YS + rise * _pointed(t0) - 0.1, cz + t0 * hz * diag)
			var c := Vector3(cx + t1 * hx, YS + rise * _pointed(t1) - 0.1, cz + t1 * hz * diag)
			r.beam(a, c, 0.2, 0.2, rc)
	for e in [[1.0, 0.0], [-1.0, 0.0], [0.0, 1.0], [0.0, -1.0]]:
		for s in M:
			var t0 := -1.0 + 2.0 * s / M
			var t1 := -1.0 + 2.0 * (s + 1) / M
			var a: Vector3
			var c: Vector3
			if e[0] != 0.0:
				a = Vector3(cx + e[0] * hx * 0.985, YS + rise * _pointed(t0) - 0.08, cz + t0 * hz)
				c = Vector3(cx + e[0] * hx * 0.985, YS + rise * _pointed(t1) - 0.08, cz + t1 * hz)
			else:
				a = Vector3(cx + t0 * hx, YS + rise * _pointed(t0) - 0.08, cz + e[1] * hz * 0.985)
				c = Vector3(cx + t1 * hx, YS + rise * _pointed(t1) - 0.08, cz + e[1] * hz * 0.985)
			r.beam(a, c, 0.26, 0.24, rc * 0.92)
	# a boss stone at the crossing
	r.box(Vector3(cx, YC - 0.12, cz), Vector3(0.42, 0.24, 0.42), rc)


## Outer walls, each topped by its bay's pointed arch (the vault's wall rib).
func _walls(sc: Color) -> void:
	var wc := Color(0.72, 0.68, 0.62)
	var rise := YC - YS
	# side walls (x = +-9), arch tops along z per bay
	for sx in [-1.0, 1.0]:
		var x: float = sx * 9.0
		for iz in 4:
			var z0: float = ZS[iz]
			var z1: float = ZS[iz + 1]
			var hz := (z1 - z0) * 0.5
			var cz := (z0 + z1) * 0.5
			var segs := 10
			for s in segs:
				var za := z0 + (z1 - z0) * s / segs
				var zb := z0 + (z1 - z0) * (s + 1) / segs
				var ta := YS + rise * _pointed((za - cz) / hz)
				var tb := YS + rise * _pointed((zb - cz) / hz)
				var opening := sx > 0.0 and zb > 31.0 and za < 35.0
				var y_lo := BED if not opening else -5.6
				var tex := "brick" if (sx > 0.0 or iz == 0) else "stone"
				G(tex, band(cz)).quad(Vector3(x, y_lo, za), Vector3(x, y_lo, zb), Vector3(x, tb, zb), Vector3(x, ta, za), Vector3(-sx, 0, 0), wc, 1.2)
			# a wall shaft between bays
			G("rib", band(z0 + 0.1)).box(Vector3(x - sx * 0.12, (BED + YS) * 0.5, z0), Vector3(0.36, YS - BED, 0.7), sc * 0.8, 8, 3.0)
		_col_box(Vector3(x + sx * 0.3, -5.0, 26.0), Vector3(0.6, 9.0, 24.4))
	# north wall (z = 14) with the tunnel's arch, and the south wall (z = 38)
	for zw in [14.0, 38.0]:
		var nz := 1.0 if zw < 20.0 else -1.0
		for ix in 3:
			var x0: float = XS[ix]
			var x1: float = XS[ix + 1]
			var hx := (x1 - x0) * 0.5
			var cx := (x0 + x1) * 0.5
			var segs := 10
			for s in segs:
				var xa := x0 + (x1 - x0) * s / segs
				var xb := x0 + (x1 - x0) * (s + 1) / segs
				var ta := YS + rise * _pointed((xa - cx) / hx)
				var tb := YS + rise * _pointed((xb - cx) / hx)
				var g := G("stone" if zw > 20.0 else "brick", band(zw + nz * 0.5))
				if zw < 20.0 and xb > -1.0 and xa < 1.0:
					# the tunnel opening: wall only above its vault
					var ya := LAND_Y + 2.0 + 0.7 * _pointed(clampf(xa, -1.0, 1.0)) + 0.05
					var yb := LAND_Y + 2.0 + 0.7 * _pointed(clampf(xb, -1.0, 1.0)) + 0.05
					g.quad(Vector3(xa, ya, zw), Vector3(xb, yb, zw), Vector3(xb, tb, zw), Vector3(xa, ta, zw), Vector3(0, 0, nz), wc, 1.2)
					continue
				if zw > 20.0 and xb > -1.15 and xa < 1.15:
					# round the lancet window
					g.quad(Vector3(xa, BED, zw), Vector3(xb, BED, zw), Vector3(xb, -6.6, zw), Vector3(xa, -6.6, zw), Vector3(0, 0, nz), wc, 1.2)
					var wa := -3.2 + 0.9 * _pointed(clampf(xa / 1.15, -1.0, 1.0))
					var wb := -3.2 + 0.9 * _pointed(clampf(xb / 1.15, -1.0, 1.0))
					g.quad(Vector3(xa, wa, zw), Vector3(xb, wb, zw), Vector3(xb, tb, zw), Vector3(xa, ta, zw), Vector3(0, 0, nz), wc, 1.2)
					continue
				g.quad(Vector3(xa, BED, zw), Vector3(xb, BED, zw), Vector3(xb, tb, zw), Vector3(xa, ta, zw), Vector3(0, 0, nz), wc, 1.2)
		if zw > 20.0:
			_col_box(Vector3(0, -5.0, zw + 0.3), Vector3(18.4, 9.0, 0.6))
		else:
			for sx in [-1.0, 1.0]:
				_col_box(Vector3(sx * 5.05, -5.0, zw - 0.3), Vector3(8.1, 9.0, 0.6))
			_col_box(Vector3(0, -3.0, zw - 0.3), Vector3(2.2, 3.8, 0.6))
	# the tunnel arch's carved frame
	var f := G("rib", "a")
	for s in 10:
		var u0 := -1.0 + 2.0 * s / 10.0
		var u1 := -1.0 + 2.0 * (s + 1) / 10.0
		f.beam(Vector3(u0 * 1.15, LAND_Y + 2.0 + 0.85 * _pointed(u0), 14.05), Vector3(u1 * 1.15, LAND_Y + 2.0 + 0.85 * _pointed(u1), 14.05), 0.3, 0.3, Color(0.75, 0.72, 0.66))
	for sx in [-1.0, 1.0]:
		f.box(Vector3(sx * 1.15, (LAND_Y + LAND_Y + 2.0) * 0.5, 14.05), Vector3(0.3, 2.0, 0.3), Color(0.75, 0.72, 0.66), 8, 4.0)


## The crypt wall of names (west): blind arches over carved panels, a candle ledge below.
const NAMES := [
	"BROTHER AMBROSE TELL  ·  1891", "SISTER MARGUERITE OLIER", "JEAN-LUC FAVROT", "PATRICK DUNNE  ·  THE IRISH CHANNEL",
	"ELOISE BEAUREGARD  ·  1906", "MATTHIAS KROLL", "THE TWINS DESHOTEL", "AUGUSTIN LEBLANC  ·  1927",
	"HONORE CASTILLE", "WINIFRED PEAKE", "BENOIT SAUCIER  ·  1938", "ODILE FONTENOT", "FATHER TOMAS ARCENEAUX",
	"CLEMENT GUIDRY", "ROSALIE DUPLANTIER  ·  1951", "ISAAC MARROW", "THEODORE BAPTISTE", "LOUISA CHENIER  ·  1966",
	"VIRGIL ST. AMANT", "MARIE-CLAIRE BOUDREAUX", "HENRI LACOMBE  ·  1979", "GRACE WREN", "ABEL THIBODEAUX",
	"CONSTANCE VIDRINE", "ELIJAH MERCIER  ·  1988", "RUTH ANSELM", "NOEL ROBICHAUX", "DELPHINE LAVERGNE",
	"SILAS CROWE  ·  FORSWORN",
]


func _names_wall() -> void:
	var x := -8.95
	var g := G("names", "b")
	var r := G("rib", "b")
	var per := 7
	for k in 4:
		var z0 := 15.0 + k * 6.0
		var cz := z0 + 3.0
		if k == 0:
			continue # the first bay stays plain brick behind the stair's angel
		# the panel, a blind pointed arch round it and the ledge
		g.quad(Vector3(x, Y + 1.0, cz - 2.2), Vector3(x, Y + 1.0, cz + 2.2), Vector3(x, Y + 3.6, cz + 2.2), Vector3(x, Y + 3.6, cz - 2.2), Vector3.RIGHT, Color(0.9, 0.86, 0.78), 0.9)
		for s in 8:
			var u0 := -1.0 + 2.0 * s / 8.0
			var u1 := -1.0 + 2.0 * (s + 1) / 8.0
			r.beam(Vector3(x + 0.08, Y + 3.6 + 0.9 * _pointed(u0), cz + u0 * 2.3), Vector3(x + 0.08, Y + 3.6 + 0.9 * _pointed(u1), cz + u1 * 2.3), 0.2, 0.2, Color(0.76, 0.72, 0.66))
		for sz in [-1.0, 1.0]:
			r.box(Vector3(x + 0.08, Y + 1.8, cz + sz * 2.3), Vector3(0.2, 3.6, 0.2), Color(0.76, 0.72, 0.66), 8, 4.0)
		r.box(Vector3(x + 0.3, Y + 0.7, cz), Vector3(0.62, 0.16, 4.8), Color(0.7, 0.66, 0.6), 0, 4.0)
		# the carved names
		var lines: Array = []
		for i in per:
			var ni := ((k - 1) * per + i)
			if ni < NAMES.size():
				lines.append(NAMES[ni])
		if k == 3:
			lines.append(NAMES[NAMES.size() - 1])
		var lab := Label3D.new()
		lab.text = "\n".join(lines)
		lab.font_size = 44
		lab.pixel_size = 0.0042
		lab.line_spacing = 6.0
		lab.modulate = Color(0.62, 0.5, 0.36)
		lab.outline_size = 0
		lab.shaded = false
		lab.double_sided = false
		lab.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		lab.position = Vector3(x + 0.03, Y + 2.3, cz)
		lab.rotation.y = PI * 0.5
		hall_root.add_child(lab)
	_col_box(Vector3(-8.65, Y + 0.7, 26.0), Vector3(0.6, 0.3, 24.0))


## Three blood fridges against the east wall, glass glowing red.
func _fridges() -> void:
	var g := G("iron", "a")
	var fr := G("fridge", "a")
	for k in 3:
		var cz := 15.9 + k * 1.15
		var c := Vector3(8.45, Y + 1.1, cz)
		g.box(c, Vector3(0.9, 2.2, 1.05), Color(0.5, 0.5, 0.5), 0, 4.0)
		var x := c.x - 0.452
		var i0 := fr.vert(Vector3(x, Y + 0.25, cz - 0.45), Vector3.LEFT, Color.WHITE, Vector2(0, 1))
		var i1 := fr.vert(Vector3(x, Y + 0.25, cz + 0.45), Vector3.LEFT, Color.WHITE, Vector2(1, 1))
		var i2 := fr.vert(Vector3(x, Y + 2.05, cz + 0.45), Vector3.LEFT, Color.WHITE, Vector2(1, 0))
		var i3 := fr.vert(Vector3(x, Y + 2.05, cz - 0.45), Vector3.LEFT, Color.WHITE, Vector2(0, 0))
		fr.tri_i(i0, i1, i2, Vector3.LEFT)
		fr.tri_i(i0, i2, i3, Vector3.LEFT)
	_col_box(Vector3(8.45, Y + 1.1, 17.05), Vector3(0.95, 2.2, 3.5))


## The gated 1890s subway tunnel through the east wall: a brick barrel, rails into the dark, an
## iron gate (closed) and a caged lantern on a stand.
func _subway() -> void:
	var z0 := 31.0
	var z1 := 35.0
	var cz := 33.0
	var hw := 2.0
	var x0 := 9.0
	var x1 := 15.0
	var br := G("brick", "c")
	var rail_y := BED - 0.1
	var bc := Color(0.62, 0.55, 0.5)
	br.quad(Vector3(x0, rail_y, z0), Vector3(x1, rail_y, z0), Vector3(x1, rail_y, z1), Vector3(x0, rail_y, z1), Vector3.UP, bc * 0.6, 1.0)
	for sz in [-1.0, 1.0]:
		var z := cz + sz * hw
		br.quad(Vector3(x0, rail_y, z), Vector3(x1, rail_y, z), Vector3(x1, -5.6, z), Vector3(x0, -5.6, z), Vector3(0, 0, -sz), bc, 1.0)
	var facets := 8
	for q in facets:
		var u0 := -1.0 + 2.0 * q / facets
		var u1 := -1.0 + 2.0 * (q + 1) / facets
		var a0 := Vector3(0, -5.6 + 1.6 * sqrt(maxf(1.0 - u0 * u0, 0.0)), cz + u0 * hw)
		var a1 := Vector3(0, -5.6 + 1.6 * sqrt(maxf(1.0 - u1 * u1, 0.0)), cz + u1 * hw)
		var nm := Vector3(0, -1, 0).lerp(Vector3(0, 0, -signf(u0 + u1)), absf(u0 + u1) * 0.5).normalized()
		br.quad(Vector3(x0, a0.y, a0.z), Vector3(x0, a1.y, a1.z), Vector3(x1, a1.y, a1.z), Vector3(x1, a0.y, a0.z), nm, bc * 0.8, 1.0)
	# the wall above the arch opening (the side wall stops at -5.6 there)
	var st := G("brick", "c")
	for q in facets:
		var u0 := -1.0 + 2.0 * q / facets
		var u1 := -1.0 + 2.0 * (q + 1) / facets
		var y0 := -5.6 + 1.6 * sqrt(maxf(1.0 - u0 * u0, 0.0))
		var y1 := -5.6 + 1.6 * sqrt(maxf(1.0 - u1 * u1, 0.0))
		st.quad(Vector3(x0 - 0.01, y0, cz + u0 * hw), Vector3(x0 - 0.01, y1, cz + u1 * hw), Vector3(x0 - 0.01, -5.6 + 1.7, cz + u1 * hw), Vector3(x0 - 0.01, -5.6 + 1.7, cz + u0 * hw), Vector3.LEFT, Color(0.72, 0.68, 0.62), 1.0)
	# the far end: dark, with a distant work lamp
	var vd := G("void", "c")
	vd.quad(Vector3(x1, rail_y, z0), Vector3(x1, rail_y, z1), Vector3(x1, -3.8, z1), Vector3(x1, -3.8, z0), Vector3.LEFT)
	G("distant", "c").box(Vector3(x1 - 0.1, -6.3, cz + 1.4), Vector3(0.05, 0.12, 0.12), Color.WHITE, 0, 4.0)
	# rails and sleepers
	var ir := G("iron", "c")
	for sz in [-0.72, 0.72]:
		ir.beam(Vector3(x0 - 1.8, rail_y + 0.07, cz + sz), Vector3(x1, rail_y + 0.07, cz + sz), 0.07, 0.12, Color.WHITE)
	var sl := G("brick", "c")
	var xx := x0 - 1.6
	while xx < x1:
		sl.box(Vector3(xx, rail_y + 0.0, cz), Vector3(0.22, 0.08, 2.2), Color(0.25, 0.2, 0.16), 8, 4.0)
		xx += 0.8
	# the gate: iron bars and two rails across
	var bars := 13
	for k in bars:
		var z := z0 + 0.15 + (z1 - z0 - 0.3) * k / (bars - 1)
		var top := -5.6 + 1.6 * sqrt(maxf(1.0 - pow((z - cz) / hw, 2.0), 0.0)) - 0.05
		ir.beam(Vector3(x0 + 0.05, BED, z), Vector3(x0 + 0.05, top, z), 0.05, 0.05, Color.WHITE)
	for y in [-8.2, -6.6]:
		ir.beam(Vector3(x0 + 0.05, y, z0 + 0.05), Vector3(x0 + 0.05, y, z1 - 0.05), 0.06, 0.1, Color.WHITE, Vector3.RIGHT)
	_col_box(Vector3(x0 + 0.1, -7.0, cz), Vector3(0.2, 5.0, 4.2))
	# the caged lantern on its stand (concept 08)
	var lp := Vector3(7.6, Y, 30.2)
	for k in 3:
		var a := TAU * k / 3.0
		ir.beam(lp + Vector3(cos(a) * 0.4, 0, sin(a) * 0.4), lp + Vector3(0, 1.4, 0), 0.04, 0.04, Color.WHITE)
	ir.beam(lp + Vector3(0, 1.4, 0), lp + Vector3(0, 1.95, 0), 0.05, 0.05, Color.WHITE)
	G("lamp", "c").box(lp + Vector3(0, 2.08, 0), Vector3(0.2, 0.28, 0.2), Color.WHITE, 0, 4.0)
	ir.box(lp + Vector3(0, 2.26, 0), Vector3(0.28, 0.06, 0.28), Color.WHITE, 0, 4.0)
	_col_box(lp + Vector3(0, 1.0, 0), Vector3(0.6, 2.0, 0.6))


## The stained lancet high in the south wall, glowing as if the cathedral's candles were behind it.
func _window() -> void:
	var g := G("glass", "c")
	var z := 37.98
	var segs := 8
	for s in segs:
		var u0 := -1.0 + 2.0 * s / segs
		var u1 := -1.0 + 2.0 * (s + 1) / segs
		var a := g.vert(Vector3(u0 * 1.15, -6.6, z), Vector3.FORWARD, Color.WHITE, Vector2((u0 + 1.0) * 0.5, 1.0))
		var b := g.vert(Vector3(u1 * 1.15, -6.6, z), Vector3.FORWARD, Color.WHITE, Vector2((u1 + 1.0) * 0.5, 1.0))
		var ya := -3.2 + 0.9 * _pointed(u0)
		var yb := -3.2 + 0.9 * _pointed(u1)
		var c := g.vert(Vector3(u1 * 1.15, yb, z), Vector3.FORWARD, Color.WHITE, Vector2((u1 + 1.0) * 0.5, (-2.3 - yb) / 4.3))
		var d := g.vert(Vector3(u0 * 1.15, ya, z), Vector3.FORWARD, Color.WHITE, Vector2((u0 + 1.0) * 0.5, (-2.3 - ya) / 4.3))
		g.tri_i(a, b, c, Vector3.FORWARD)
		g.tri_i(a, c, d, Vector3.FORWARD)
	var r := G("rib", "c")
	for s in 10:
		var u0 := -1.0 + 2.0 * s / 10.0
		var u1 := -1.0 + 2.0 * (s + 1) / 10.0
		r.beam(Vector3(u0 * 1.3, -3.2 + 1.0 * _pointed(u0), 37.9), Vector3(u1 * 1.3, -3.2 + 1.0 * _pointed(u1), 37.9), 0.22, 0.22, Color(0.75, 0.72, 0.66))
	for sx in [-1.0, 1.0]:
		r.box(Vector3(sx * 1.3, -4.9, 37.9), Vector3(0.22, 3.4, 0.22), Color(0.75, 0.72, 0.66), 8, 4.0)
	r.box(Vector3(0, -6.7, 37.85), Vector3(2.9, 0.2, 0.35), Color(0.75, 0.72, 0.66), 0, 4.0)
	r.beam(Vector3(0, -6.6, 37.93), Vector3(0, -2.4, 37.93), 0.08, 0.08, Color(0.3, 0.3, 0.3))


func _angels(xfs: Array) -> void:
	var path := "res://assets/props/angel.glb"
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var inst := scene.instantiate()
	var found: Array = []
	PropsScript._collect_meshes(inst, Transform3D.IDENTITY, found)
	inst.free()
	if found.is_empty():
		return
	var bb := AABB()
	for k in found.size():
		var b: AABB = found[k][1] * (found[k][0] as Mesh).get_aabb()
		bb = b if k == 0 else bb.merge(b)
	var s := 2.2 / maxf(bb.size.y, 0.0001)
	var c := bb.get_center()
	var norm := Transform3D(Basis().scaled(Vector3(s, s, s)), -Vector3(c.x, bb.position.y, c.z) * s)
	for f in found:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = f[0]
		mm.instance_count = xfs.size()
		for k in xfs.size():
			mm.set_instance_transform(k, (xfs[k] as Transform3D) * norm * (f[1] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Angels"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hall_root.add_child(mmi)


# ---------------------------------------------------------------- candles and lights
func _build_candles() -> void:
	# split by root: the tunnel's candles stay with the tunnel
	var parts := {"t": [[], []], "h": [[], []]}
	for xf: Transform3D in candle_xfs:
		parts["t" if xf.origin.z < 13.9 else "h"][0].append(xf)
	for xf: Transform3D in halo_xfs:
		parts["t" if xf.origin.z < 13.9 else "h"][1].append(xf)
	var body := CylinderMesh.new()
	body.top_radius = 0.04
	body.bottom_radius = 0.043
	body.height = 0.3
	body.radial_segments = 6
	body.rings = 1
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	for key in parts:
		var parent: Node3D = tunnel_root if key == "t" else hall_root
		var cxf: Array = parts[key][0]
		var hxf: Array = parts[key][1]
		var shifted: Array = []
		for xf: Transform3D in cxf:
			shifted.append(Transform3D(xf.basis, xf.origin + xf.basis * Vector3(0, 0.15, 0)))
		_mm(parent, "Candles", body, mats["wax"], shifted)
		_mm(parent, "Flames", q, mats["flame"], cxf, Vector3(0, 0.0, 0))
		_mm(parent, "Halos", q, mats["halo"], hxf)


func _mm(parent: Node3D, nm: String, mesh: Mesh, mat: Material, xfs: Array, _off := Vector3.ZERO) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	var aabb := AABB()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		var o: Vector3 = (xfs[k] as Transform3D).origin
		aabb = AABB(o, Vector3.ZERO) if k == 0 else aabb.expand(o)
	mm.custom_aabb = aabb.grow(1.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


func _build_lights() -> void:
	var warm := Color(1.0, 0.6, 0.3)
	var defs := [
		[tunnel_root, Vector3(0.0, -4.6, 8.6), warm, 1.0, 6.0],
		[hall_root, Vector3(0.0, -7.2, 16.6), warm, 1.6, 7.0],
		[hall_root, Vector3(0.0, -6.6, 28.8), warm, 1.5, 9.5],
		[hall_root, Vector3(-7.6, -7.5, 27.0), warm, 1.2, 8.0],
		[hall_root, Vector3(7.4, -7.4, 17.3), Color(1.0, 0.08, 0.05), 1.8, 6.5],
		[hall_root, Vector3(7.4, -6.9, 30.4), warm, 1.3, 6.5],
		[hall_root, Vector3(0.0, -4.4, 36.4), Color(0.5, 0.58, 1.0), 0.9, 11.0],
	]
	for d in defs:
		var l := OmniLight3D.new()
		l.position = d[1]
		l.light_color = d[2]
		l.light_energy = d[3]
		l.omni_range = d[4]
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.light_specular = 0.6
		(d[0] as Node3D).add_child(l)
		lights.append(l)
		light_base.append(float(d[3]))


func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.27, 0.3)
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.25
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.045, 0.04)
	env.fog_light_energy = 1.0
	env.fog_density = 0.035
	env.fog_sky_affect = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.05


# ================================================================ runtime
func _process(delta: float) -> void:
	_t += delta
	if main == null or main.player == null or not main.player.is_inside_tree():
		return
	var p = main.player
	var cam: Camera3D = p.camera
	if cam == null:
		return
	if poi == null and main.hunt != null:
		_register_poi()
	_flag_drop()
	var cp := cam.global_position
	var pp: Vector3 = p.global_position
	var near_well := Vector2(pp.x, pp.z).length() < 26.0
	tunnel_root.visible = near_well or inside
	hall_root.visible = inside or (cp.y < -2.0 and ZONE.has_point(Vector2(cp.x, cp.z))) or (pp.y < -3.0 and ZONE.has_point(Vector2(pp.x, pp.z)))
	var want := inside
	if not inside and cp.y < ENTER_Y and ZONE.has_point(Vector2(cp.x, cp.z)) and pp.y < ENTER_Y + 1.0:
		want = true
	elif inside and (cp.y > EXIT_Y or not ZONE.has_point(Vector2(cp.x, cp.z))):
		want = false
	if want != inside:
		_set_inside(want)
	# Sol's ground for loot, motes and telegraphs (terrain.gd's UNDERCROFT HOOK)
	var in_hall := HALL.grow(0.5).has_point(Vector2(pp.x, pp.z)) and pp.y < -6.0
	Terrain.under_rect = HALL.grow(1.0) if in_hall else Rect2()
	Terrain.under_y = Y
	if inside:
		for i in lights.size():
			var f := 0.88 + 0.08 * sin(_t * (7.0 + i) + i * 2.1) + 0.04 * sin(_t * 17.0 + i)
			lights[i].light_energy = float(light_base[i]) * f
	_rival_tick(p)


func _set_inside(on: bool) -> void:
	inside = on
	var p = main.player
	if on:
		_hidden.clear()
		for c in main.get_children():
			if c is Node3D and c != self and c != p and c != main.enemies_root and c != main.get("loot") and c.name != "Undercroft" and c.name != "Fx":
				_hidden[c] = (c as Node3D).visible
				(c as Node3D).visible = false
		if main.atmo != null:
			if main.atmo.sun != null:
				_hidden[main.atmo.sun] = main.atmo.sun.visible
				main.atmo.sun.visible = false
			if main.atmo.rain != null:
				_hidden[main.atmo.rain] = main.atmo.rain.visible
				main.atmo.rain.visible = false
		# the crypt's own grade, eased in from the street's
		var street: Environment = main.env
		if street != null:
			env.tonemap_exposure = street.tonemap_exposure
		p.camera.environment = env
		var tw := create_tween()
		tw.tween_property(env, "tonemap_exposure", 1.25 * Settings.brightness, 0.8)
	else:
		for n in _hidden:
			if is_instance_valid(n):
				(n as Node3D).visible = _hidden[n]
		_hidden.clear()
		p.camera.environment = null
		Terrain.under_rect = Rect2()


## Is this point (world) down in the crypt or its tunnel? (for other systems and the tests)
func contains(p: Vector3) -> bool:
	return p.y < -2.0 and ZONE.has_point(Vector2(p.x, p.z))


# ---------------------------------------------------------------- the rival
func _rival_tick(p) -> void:
	if rival_dead:
		return
	var in_hall := HALL.has_point(Vector2(p.global_position.x, p.global_position.z)) and p.global_position.y < -6.0
	if (rival == null or not is_instance_valid(rival)) and (inside or in_hall) and main.enemies_root != null:
		spawn_rival()
	if rival == null or not is_instance_valid(rival):
		return
	if rival.dead:
		return
	# Sol left the crypt: the duel waits for him (full health, back at his post)
	if not inside and not in_hall and rival.state != "wait":
		rival.reset_to(RIVAL_HOME)
	# Sol fell down here: when he rises (a Hunt revive brings him back up top), wake him at the
	# stair's foot and let the rival take his place again
	if p.dead and in_hall:
		_died_inside = true
	elif _died_inside and not p.dead:
		_died_inside = false
		p.global_position = START + Vector3(0, 0.2, 0)
		p.velocity = Vector3.ZERO
		rival.reset_to(RIVAL_HOME)


func spawn_rival() -> CharacterBody3D:
	rival = Rival.new()
	rival.main = main
	rival.depths = self
	rival.position = RIVAL_HOME
	rival.home = RIVAL_HOME
	rival.arena = Rect2(-8.3, 19.2, 16.6, 18.4)
	rival.rematch = int(record.get("rival_kills", 0)) > 0
	main.enemies_root.add_child(rival)
	rival.died.connect(_on_rival_died)
	return rival


func _on_rival_died(r) -> void:
	rival_dead = true
	record["rival_kills"] = int(record.get("rival_kills", 0)) + 1
	save_record()
	if poi != null:
		poi.cleared = true
	# the loot: his blade the first time, a Hallowed-or-better find after that
	var ItemDB = load("res://scripts/items/item_db.gd")
	var pos: Vector3 = r.global_position
	var first := int(record.rival_kills) == 1 or not record.get("blade_taken", false)
	var inst: Dictionary
	if first:
		inst = ItemDB.make("crowes_penance", 3)
		record["blade_taken"] = true
		save_record()
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		inst = ItemDB.random_item(rng, true, false, 0.6)
		inst["r"] = maxi(int(inst.get("r", 0)), 2)
	var entry: Dictionary = main.loot.spawn_item(inst, pos + Vector3(0, 0, -1.0))
	if entry.has("node") and is_instance_valid(entry.node):
		entry.node.global_position.y = Y + 0.1
	main.hud.announce("RIVAL DEFEATED\n" + Rival.NAME_TITLE)


# ---------------------------------------------------------------- the POI and the test flag
func _register_poi() -> void:
	if main.hunt == null or not main.hunt.has_method("register_poi"):
		return
	poi = PoiScript.new()
	poi.depths = self
	poi.position = Vector3(0, 0, 0)
	poi.cleared = rival_dead
	main.hunt.register_poi(poi)


func _flag_drop() -> void:
	if _flag_done:
		return
	if not wanted_flag(main):
		_flag_done = true
		return
	if not main.started:
		return
	if main.hunt != null and String(main.hunt.state) in ["idle", "deploy"]:
		return
	_flag_done = true
	drop_sol_at_bottom()


static func wanted_flag(m) -> bool:
	return "--undercroft" in OS.get_cmdline_user_args() or (m != null and m.has_method("_url_flag") and m._url_flag("undercroft"))


## Put Sol at the foot of the grand stair, facing the duel floor.
func drop_sol_at_bottom() -> void:
	var p = main.player
	p.global_position = START + Vector3(0, 0.15, 0)
	p.velocity = Vector3.ZERO
	p.facing = 0.0
	p.cam_yaw = PI
	p.visual.rotation.y = 0.0
	p.has_safe = false


# ---------------------------------------------------------------- record (survives Hunts)
static func load_record() -> void:
	record = {}
	if FileAccess.file_exists(record_path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(record_path))
		if d is Dictionary:
			record = d


static func save_record() -> void:
	var f := FileAccess.open(record_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(record, "\t"))
