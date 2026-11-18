extends Node3D
## The main-menu backdrop: Sol's lair in the Undercroft, the flooded crypt under the
## cathedral (docs/concept_art/13_main_menu_lair.jpg). Built in code like the city.
## The left third stays dark and empty for the menu; Sol works at the bench centre-right
## under a brass work lamp, Nia stands at his shoulder with a tablet, the blood fridges
## glow red behind them, and a gated subway tunnel recedes on the left.
##
## Lights: 4 real lights on the web tier (work lamp, fridges, candles x2), a few more with
## shadows and volumetric fog on Forward+. Everything else glows through emission and
## additive sprites.

const U = preload("res://scripts/util.gd")
const Atmo = preload("res://scripts/atmosphere.gd")
const PostFxScript = preload("res://scripts/post_fx.gd")
const BenchPose = preload("res://scripts/menu/sol_bench_pose.gd")
const NiaIdle = preload("res://scripts/menu/nia_idle.gd")
const SOL_SCENES := ["res://assets/characters/sol/sol_modular.scn", "res://assets/characters/sol/sol.scn"]
const NIA_SCENE := "res://assets/characters/nia/nia.scn"
const PROP_DIR := "res://assets/props/lair/"
const SWORD_SCENE := "res://assets/characters/sol/sol_sword_silver.scn"

const SOL_POS := Vector3(1.15, 0.12, -3.62)
const BENCH_POS := Vector3(1.0, 0.12, -3.0) # centre of the bench at floor level
const BENCH_LEN := 3.2
const BENCH_TOP := 0.98
const NIA_POS := Vector3(2.45, 0.12, -4.05)
const TUNNEL_X := -1.9
const VAULT_SPRING := 2.75 # a low, heavy crypt: the ribs spring just above the fridge tops
const BLADE_REST := 0.045 # the wooden rests the blade lies on
const BLADE_Z_LOCAL := -0.34 # blade line, in bench space (Sol stands at -z)

# two framings the camera drifts between: [position, look target, fov]
const SHOT_A := [Vector3(-0.45, 1.68, -0.95), Vector3(0.25, 1.62, -4.6), 56.0]
const SHOT_B := [Vector3(-0.1, 1.6, -1.3), Vector3(0.45, 1.56, -4.7), 52.0]
const DRIFT_TIME := 26.0

var tier := "web"
var cinematic := false
var camera: Camera3D
var env: Environment
var world_env: WorldEnvironment
var base_exposure := 1.0
var t := 0.0
var flicker_lights: Array = [] # [OmniLight3D, base energy, phase]
var sol_skel: Skeleton3D
var nia: Node3D
var post: CanvasLayer

var m_stone: StandardMaterial3D
var m_stone_dark: StandardMaterial3D
var m_vault: StandardMaterial3D # ribs and piers: m_stone with a faint warm bounce glow
var m_brick: StandardMaterial3D
var m_wood: StandardMaterial3D
var m_wood_dark: StandardMaterial3D
var m_iron: StandardMaterial3D
var m_brass: StandardMaterial3D
var m_steel: StandardMaterial3D
var m_water: StandardMaterial3D
var m_floor: StandardMaterial3D
var puddle_tex: NoiseTexture2D
var m_wax: StandardMaterial3D
var m_paper: StandardMaterial3D
var m_red_glow: StandardMaterial3D
var flame_mat: ShaderMaterial
var flame_mesh: QuadMesh
var candle_xf: Array[Transform3D] = []
var halos: Array = [] # [position, size, colour]
var puddle_glows: Array = [] # [floor point, colour]: fake reflections in the puddles (web)


func _ready() -> void:
	tier = Atmo.detect_tier()
	cinematic = tier == "cinematic"
	_materials()
	_environment()
	_room()
	_tunnel()
	_fridges()
	_pegboard()
	_planning_table()
	_workbench()
	_window()
	_chandelier()
	_candle_clusters()
	_flush_candles()
	_bounce()
	_puddles()
	_dust()
	_sol()
	_nia()
	_lights()
	_camera()
	post = PostFxScript.new()
	post.name = "PostFX"
	add_child(post)
	post.configure(cinematic)


# ---------------------------------------------------------------- materials
func _noise_tex(freq: float, seed_: int, normal := false, size := 512) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = 5
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.noise = n
	if normal:
		tex.as_normal_map = true
		tex.bump_strength = 6.0
	return tex


func _surface(col: Color, rough: float, scale: float, seed_: int, ramp: Array) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var g := Gradient.new()
	g.set_color(0, ramp[0])
	g.set_color(1, ramp[1])
	var alb := _noise_tex(0.012, seed_)
	alb.color_ramp = g
	m.albedo_texture = alb
	m.albedo_color = col
	m.roughness = rough
	m.normal_enabled = true
	m.normal_texture = _noise_tex(0.03, seed_ + 7, true)
	m.normal_scale = 0.45
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


func _materials() -> void:
	m_stone = _surface(Color(0.62, 0.58, 0.52), 0.78, 0.35, 3, [Color(0.16, 0.15, 0.14), Color(0.42, 0.39, 0.35)])
	m_stone_dark = _surface(Color(0.45, 0.43, 0.42), 0.82, 0.3, 11, [Color(0.07, 0.07, 0.075), Color(0.26, 0.25, 0.24)])
	m_vault = m_stone.duplicate() as StandardMaterial3D
	m_vault.emission_enabled = true
	m_vault.emission = Color(0.62, 0.4, 0.26)
	m_vault.emission_energy_multiplier = 0.1 if cinematic else 0.3
	m_vault.emission_texture = m_stone.albedo_texture
	m_brick = _surface(Color(0.6, 0.45, 0.36), 0.7, 0.6, 21, [Color(0.12, 0.08, 0.06), Color(0.36, 0.25, 0.18)])
	m_wood = _surface(Color(0.55, 0.36, 0.22), 0.6, 1.4, 31, [Color(0.18, 0.1, 0.05), Color(0.42, 0.27, 0.15)])
	m_wood.normal_scale = 0.15
	(m_wood.albedo_texture as NoiseTexture2D).noise.frequency = 0.004 # long grain, not blotches
	m_wood.uv1_scale = Vector3(0.5, 1.4, 6.0)
	# the tunnel bricks glow faintly warm, so the tunnel reads without a real light (web budget)
	m_brick.emission_enabled = true
	m_brick.emission = Color(0.5, 0.26, 0.12)
	m_brick.emission_energy_multiplier = 0.32
	m_wood_dark = U.mat(Color(0.09, 0.055, 0.035), 0.55)
	m_iron = U.mat(Color(0.05, 0.05, 0.055), 0.45, 0.8)
	m_brass = U.mat(Color(0.62, 0.45, 0.2), 0.32, 1.0)
	m_steel = U.mat(Color(0.86, 0.88, 0.92), 0.12, 1.0)
	m_wax = U.mat(Color(0.55, 0.48, 0.38), 0.5)
	m_wax.emission_enabled = true
	m_wax.emission = Color(1.0, 0.62, 0.3)
	m_wax.emission_energy_multiplier = 0.12
	m_paper = U.mat(Color(0.45, 0.4, 0.31), 0.9)
	m_red_glow = U.glow(Color(0.9, 0.05, 0.06), 3.0)
	# shallow standing water: near-black, mirror-smooth (SSR on Forward+, specular streaks on web)
	m_water = StandardMaterial3D.new()
	m_water.albedo_color = Color(0.012, 0.014, 0.018)
	m_water.roughness = 0.03 if cinematic else 0.08
	m_water.metallic = 0.2
	m_water.metallic_specular = 0.9
	if not cinematic:
		# translucent so the mirrored glow sprites underneath read as reflections
		m_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m_water.albedo_color.a = 0.86
	m_water.normal_enabled = true
	m_water.normal_texture = _noise_tex(0.05, 41, true, 256)
	m_water.normal_scale = 0.12
	m_water.uv1_triplanar = true
	m_water.uv1_world_triplanar = true
	m_water.uv1_scale = Vector3.ONE * 0.4
	# the raised work platform: wet flagstones
	m_floor = _surface(Color(0.5, 0.47, 0.44), 0.4, 0.3, 51, [Color(0.05, 0.045, 0.04), Color(0.2, 0.18, 0.16)])
	m_floor.normal_scale = 0.2
	# standing puddles: the noise thresholded into near-mirror patches on the flagstones
	puddle_tex = _noise_tex(0.02, 57, false, 256)
	var pg := Gradient.new()
	pg.offsets = PackedFloat32Array([0.0, 0.5, 0.58, 1.0])
	pg.colors = PackedColorArray([Color(0.06, 0.06, 0.06), Color(0.06, 0.06, 0.06), Color(0.75, 0.75, 0.75), Color(0.8, 0.8, 0.8)])
	puddle_tex.color_ramp = pg
	m_floor.roughness = 1.0
	m_floor.roughness_texture = puddle_tex
	m_floor.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	# candle flames: additive billboards that flicker on their own, keyed off world position
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.25, 1.0);
uniform float energy = 2.2;
varying float seed;
void vertex() {
	seed = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float s = length(MODEL_MATRIX[0].xyz);
	VERTEX *= s;
	VERTEX.x += sin(TIME * 7.0 + seed * 40.0) * 0.08 * VERTEX.y * s;
}
void fragment() {
	vec2 d = UV - vec2(0.5, 0.62);
	float core = exp(-dot(d * vec2(3.2, 1.6), d * vec2(3.2, 1.6)) * 18.0);
	float halo = exp(-dot(d, d) * 7.0) * 0.18;
	float fl = 0.82 + 0.18 * sin(TIME * (9.0 + seed * 5.0) + seed * 30.0) * sin(TIME * 3.1 + seed * 11.0);
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.9, 0.7), core) * energy * fl;
	ALPHA = clamp(core + halo, 0.0, 1.0);
}
"""
	flame_mat = ShaderMaterial.new()
	flame_mat.shader = sh
	flame_mesh = QuadMesh.new()
	flame_mesh.size = Vector2(0.09, 0.16)
	flame_mesh.center_offset = Vector3(0, 0.06, 0)


# ---------------------------------------------------------------- environment
func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.005, 0.008)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.3, 0.46)
	env.ambient_light_energy = 0.4 if cinematic else 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	base_exposure = 1.3 if cinematic else 1.45
	env.tonemap_exposure = base_exposure
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.4 if cinematic else 0.75
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2 if cinematic else 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4] else 0.0)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.09, 0.07)
	env.fog_density = 0.035
	env.fog_sky_affect = 0.0
	if cinematic:
		env.ssr_enabled = true
		env.ssr_max_steps = 64
		env.ssr_fade_in = 0.1
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.3
		env.ssao_enabled = true
		env.ssao_radius = 1.0
		env.ssao_intensity = 2.0
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.03
		env.volumetric_fog_albedo = Color(0.8, 0.75, 0.7)
		env.volumetric_fog_length = 24.0
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_ambient_inject = 0.08
		env.fog_density = 0.02
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


# ---------------------------------------------------------------- architecture
func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return U.part(parent, U.box(size), m, pos, rot)


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO, segs := 16) -> MeshInstance3D:
	var c := U.cyl(r_top, r_bot, h)
	c.radial_segments = segs
	c.rings = 1
	return U.part(parent, c, m, pos, rot)


## Instance a generated prop (assets/props/lair/<name>.glb) under `parent`, its bounding box
## stretched to `size` (in the model's own axes; 0 on an axis = keep proportion with y) with
## the bottom at the origin, then placed by `xf`. Returns null if the asset is missing.
func _prop(parent: Node3D, name_: String, size: Vector3, xf: Transform3D) -> Node3D:
	var path := PROP_DIR + name_ + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	var bb := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	if first:
		inst.free()
		return null
	var k := size.y / maxf(bb.size.y, 0.0001)
	var sc := Vector3(size.x / bb.size.x if size.x > 0.0 else k, k, size.z / bb.size.z if size.z > 0.0 else k)
	var holder := Node3D.new()
	holder.name = name_
	holder.transform = xf
	parent.add_child(holder)
	inst.scale = sc
	inst.position = -Vector3(bb.get_center().x, bb.position.y, bb.get_center().z) * sc
	holder.add_child(inst)
	return holder


## A two-centred pointed gothic arch rib from segments. `axis` = the direction the arch
## spans along (X or Z), centred at `c` (floor level), springing at `spring`.
## `k` = radius / span: 1.0 is an equilateral arch, ~0.6 a lower, wider vault.
func _arch(c: Vector3, span: float, spring: float, axis: Vector3, w: float, depth: float, m: Material, segs := 7, k := 1.0) -> void:
	var r := span * maxf(k, 0.51)
	var cx := r - span * 0.5 # the right-hand centre, for the left half of the arch
	var a_end := acos(-cx / r)
	var across := Vector3.UP.cross(axis).normalized()
	var pts_l: Array[Vector2] = []
	for i in segs + 1:
		var a := lerpf(PI, a_end, i / float(segs))
		pts_l.append(Vector2(-(cx + r * cos(a)), r * sin(a)))
	for side: float in [-1.0, 1.0]:
		for i in segs:
			var p0 := pts_l[i]
			var p1 := pts_l[i + 1]
			var w0 := c + axis * p0.x * side + Vector3.UP * (spring + p0.y)
			var w1 := c + axis * p1.x * side + Vector3.UP * (spring + p1.y)
			var mid := (w0 + w1) * 0.5
			var seg := w1 - w0
			var mi := MeshInstance3D.new()
			mi.mesh = U.box(Vector3(w, seg.length() + 0.04, depth))
			mi.material_override = m
			var y := seg.normalized()
			var z := across
			var x := y.cross(z).normalized()
			mi.transform = Transform3D(Basis(x, y, x.cross(y)), mid)
			add_child(mi)


func _pillar(p: Vector3, h: float) -> void:
	_cyl(self, 0.3, 0.3, h, p + Vector3(0, h * 0.5, 0), m_vault, Vector3.ZERO, 12)
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		_cyl(self, 0.09, 0.09, h, p + Vector3(cos(a) * 0.3, h * 0.5, sin(a) * 0.3), m_vault, Vector3.ZERO, 8)
	_box(self, Vector3(0.95, 0.35, 0.95), p + Vector3(0, 0.17, 0), m_stone_dark)
	_box(self, Vector3(0.9, 0.22, 0.9), p + Vector3(0, h - 0.05, 0), m_vault)
	_box(self, Vector3(1.05, 0.12, 1.05), p + Vector3(0, h + 0.1, 0), m_vault)


func _room() -> void:
	# floors: black water over the whole crypt, a raised flagstone platform for the lab
	_box(self, Vector3(24, 0.2, 30), Vector3(-2, -0.12, -6), m_water)
	_box(self, Vector3(5.2, 0.24, 6.6), Vector3(1.7, 0.0, -4.9), m_floor)
	_box(self, Vector3(5.3, 0.07, 0.14), Vector3(1.7, 0.1, -1.6), m_stone)
	_box(self, Vector3(0.14, 0.07, 6.6), Vector3(-0.9, 0.1, -4.9), m_stone)
	# stepping stones across the water toward the tunnel
	for i in 5:
		_box(self, Vector3(0.7, 0.16, 0.55), Vector3(-1.3 - i * 0.22, 0.0, -2.2 - i * 1.15), m_stone)
	# walls
	var tw := 3.2 # tunnel mouth width
	var right_x := 4.6
	_box(self, Vector3(0.6, 9, 16), Vector3(right_x, 4.5, -6), m_stone_dark) # right
	_box(self, Vector3(0.6, 9, 24), Vector3(-8.5, 4.5, -6), m_stone_dark) # left (in darkness)
	var r0 := TUNNEL_X + tw * 0.5
	_box(self, Vector3(right_x - r0 + 0.3, 9, 0.8), Vector3((right_x + r0) * 0.5, 4.5, -8.6), m_stone_dark) # back, right of the tunnel
	var l0 := TUNNEL_X - tw * 0.5
	_box(self, Vector3(l0 + 8.5, 9, 0.8), Vector3((l0 - 8.5) * 0.5, 4.5, -8.6), m_stone_dark) # back, left of it
	_box(self, Vector3(tw + 0.2, 4.6, 0.8), Vector3(TUNNEL_X, 6.7, -8.6), m_stone_dark) # over the tunnel
	_box(self, Vector3(24, 0.4, 30), Vector3(-2, 6.4, -6), m_stone_dark) # vault cap
	# piers and ribbed vaults: one pier in the dark left third, one by the tunnel mouth
	var p_front := Vector3(-2.7, 0, -4.4)
	var p_back := Vector3(TUNNEL_X + 2.05, 0, -7.7)
	var p_left := Vector3(-5.4, 0, -4.2)
	for p in [p_front, p_back, p_left, Vector3(-5.4, 0, 0.4), Vector3(-2.7, 0, 0.8)]:
		_pillar(p, VAULT_SPRING - 0.15)
	_arch(Vector3((p_front.x + right_x) * 0.5, 0, p_front.z), right_x - p_front.x, VAULT_SPRING, Vector3.RIGHT, 0.32, 0.45, m_vault, 12, 0.6)
	_arch(Vector3((p_back.x + right_x) * 0.5, 0, p_back.z), right_x - p_back.x, VAULT_SPRING, Vector3.RIGHT, 0.3, 0.42, m_vault, 12, 0.62)
	_arch(Vector3((p_left.x + p_front.x) * 0.5, 0, p_front.z), p_front.x - p_left.x, VAULT_SPRING, Vector3.RIGHT, 0.3, 0.42, m_vault, 9, 0.8)
	_arch(Vector3(p_front.x, 0, (p_front.z + 0.8) * 0.5), 5.0, VAULT_SPRING, Vector3.FORWARD, 0.28, 0.4, m_vault, 9, 0.75)
	_arch(Vector3(p_left.x, 0, (p_left.z + 0.4) * 0.5), 4.6, VAULT_SPRING, Vector3.FORWARD, 0.28, 0.4, m_vault, 9, 0.75)
	# diagonal ribs over the lab bay
	var c := Vector3((p_front.x + right_x) * 0.5, 0, (p_front.z + p_back.z) * 0.5)
	_arch(c, 6.9, VAULT_SPRING, Vector3(right_x - p_front.x, 0, p_back.z - p_front.z).normalized(), 0.18, 0.26, m_vault, 12, 0.56)
	_arch(c, 6.9, VAULT_SPRING, Vector3(right_x - p_front.x, 0, p_front.z - p_back.z).normalized(), 0.18, 0.26, m_vault, 12, 0.56)
	# wall pilasters on the right
	for z in [-4.2, -7.0, -1.4]:
		_box(self, Vector3(0.4, VAULT_SPRING, 0.6), Vector3(right_x - 0.4, VAULT_SPRING * 0.5, z), m_vault)
	# a stone ledge along the right wall and shelves of jars
	_box(self, Vector3(0.5, 0.9, 6.0), Vector3(right_x - 0.45, 0.55, -4.2), m_vault)
	_shelves(Vector3(right_x - 0.4, 0.0, -2.4))


func _shelves(p: Vector3) -> void:
	var glass := U.mat(Color(0.35, 0.25, 0.2), 0.1, 0.0)
	for k in 4:
		var y := 1.2 + k * 0.45
		_box(self, Vector3(0.35, 0.04, 1.4), p + Vector3(0, y, 0), m_wood)
		for j in 6:
			var h := 0.12 + fmod(j * 0.37 + k * 0.21, 0.12)
			var jar := glass if (j + k) % 3 else U.glow(Color(0.5, 0.05, 0.04), 0.6)
			_cyl(self, 0.045, 0.05, h, p + Vector3(-0.05, y + 0.02 + h * 0.5, -0.6 + j * 0.24), jar, Vector3.ZERO, 8)


func _tunnel() -> void:
	# an 1890s subway tunnel behind an iron gate: brick rings receding into the dark
	var mouth := Vector3(TUNNEL_X, 0, -8.6)
	_arch(mouth + Vector3(0, 0, 0.45), 3.2, 2.2, Vector3.RIGHT, 0.4, 0.5, m_stone, 8)
	_box(self, Vector3(0.45, 2.3, 0.6), mouth + Vector3(-1.75, 1.15, 0.45), m_stone)
	_box(self, Vector3(0.45, 2.3, 0.6), mouth + Vector3(1.75, 1.15, 0.45), m_stone)
	for i in 14:
		var z := mouth.z - 0.6 - i * 1.4
		_arch(Vector3(mouth.x, 0, z), 3.0, 1.6, Vector3.RIGHT, 0.32, 0.5, m_brick, 6)
		_box(self, Vector3(0.3, 1.7, 0.5), Vector3(mouth.x - 1.6, 0.85, z), m_brick)
		_box(self, Vector3(0.3, 1.7, 0.5), Vector3(mouth.x + 1.6, 0.85, z), m_brick)
		if i % 3 == 1:
			# caged bulbs along the tunnel wall, each with a soft halo
			var bulb := U.glow(Color(1.0, 0.7, 0.4), 6.0)
			U.part(self, U.sphere(0.05), bulb, Vector3(mouth.x - 1.35, 2.2, z))
			_halo(Vector3(mouth.x - 1.3, 2.2, z), 0.9, Color(1.0, 0.62, 0.3, 0.55))
	# a glow far down the tunnel: the vanishing point of the composition
	_halo(Vector3(mouth.x, 1.1, mouth.z - 17.0), 3.2, Color(1.0, 0.62, 0.32, 0.7))
	_halo(Vector3(mouth.x, 1.0, mouth.z - 12.0), 2.6, Color(0.9, 0.55, 0.3, 0.22))
	_box(self, Vector3(3.1, 0.1, 21), Vector3(mouth.x, -0.02, mouth.z - 10.5), m_brick)
	for x in [-0.5, 0.5]:
		_box(self, Vector3(0.07, 0.08, 22), Vector3(mouth.x + x, 0.06, mouth.z - 10), m_steel)
	for i in 30:
		_box(self, Vector3(1.5, 0.05, 0.16), Vector3(mouth.x, 0.02, mouth.z - 0.3 - i * 0.7), m_wood_dark)
	# the gate: two leaves of bars, the right one swung half open
	for leaf: float in [-1.0, 1.0]:
		var hinge := mouth + Vector3(leaf * 1.5, 0, 0.3)
		var g := Node3D.new()
		g.position = hinge
		g.rotation.y = 0.0 if leaf < 0 else -0.9
		add_child(g)
		for k in 9:
			var x := -leaf * (0.08 + k * 0.17)
			_cyl(g, 0.018, 0.018, 3.1, Vector3(x, 1.55, 0), m_iron, Vector3.ZERO, 6)
			_box(g, Vector3(0.05, 0.12, 0.05), Vector3(x, 3.12, 0), m_iron)
		for y in [0.25, 1.4, 2.6]:
			_box(g, Vector3(1.5, 0.05, 0.04), Vector3(-leaf * 0.75, y, 0), m_iron)


func _fridges() -> void:
	# two tall industrial blood fridges (generated cabinets); their glass doors are faked with
	# a lit red interior, racks of blood bags and a glass sheet set just proud of each door
	var bag := U.glow(Color(0.6, 0.01, 0.025), 0.75)
	var inner := U.glow(Color(0.4, 0.012, 0.02), 0.45)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.5, 0.15, 0.15, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.metallic_specular = 1.0
	var body := U.mat(Color(0.12, 0.12, 0.13), 0.45, 0.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = U.box(Vector3(0.1, 0.2, 0.05))
	var xfs: Array[Transform3D] = []
	var h := 2.1
	var w := 1.1
	var depth := 0.72
	for k in 2:
		var c := Vector3(1.72 + k * 1.16, 0.12, -7.82)
		var shell := _prop(self, "blood_fridge", Vector3(depth, h, w), Transform3D(Basis(Vector3.UP, PI * 0.5), c))
		if shell == null:
			_box(self, Vector3(w, h, depth), c + Vector3(0, h * 0.5, 0), body)
		var fz := c.z + depth * 0.5 + 0.012 # just proud of the door face
		for side: float in [-1.0, 1.0]:
			var pc := c + Vector3(side * 0.255, 0, 0)
			_box(self, Vector3(0.46, 1.62, 0.01), Vector3(pc.x, c.y + 1.12, fz), inner)
			_box(self, Vector3(0.48, 1.66, 0.006), Vector3(pc.x, c.y + 1.12, fz + 0.075), glass)
			for s_ in 5:
				var y := c.y + 0.42 + s_ * 0.33
				_box(self, Vector3(0.44, 0.012, 0.07), Vector3(pc.x, y, fz + 0.035), m_steel)
				for j in 3:
					xfs.append(Transform3D(Basis(Vector3.UP, randf_range(-0.25, 0.25)), Vector3(pc.x - 0.14 + j * 0.14, y + 0.11, fz + 0.035)))
			# door frame and a long steel handle
			_box(self, Vector3(0.025, 1.7, 0.02), Vector3(pc.x - side * 0.235, c.y + 1.12, fz + 0.078), body)
			_box(self, Vector3(0.02, 0.5, 0.025), Vector3(pc.x - side * 0.2, c.y + 1.15, fz + 0.1), m_steel)
		_box(self, Vector3(0.96, 0.025, 0.02), Vector3(c.x, c.y + 1.96, fz + 0.078), body)
		_box(self, Vector3(0.96, 0.025, 0.02), Vector3(c.x, c.y + 0.29, fz + 0.078), body)
		# the glow they throw on the wet floor in front
		_halo(Vector3(c.x, c.y + 1.15, fz + 0.15), 1.5, Color(1.0, 0.06, 0.06, 0.3))
		puddle_glows.append([Vector3(c.x, c.y, fz + 0.6), Color(1.0, 0.05, 0.05)])
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bag
	add_child(mmi)
	# shelf of supplies and candles on top
	_box(self, Vector3(2.5, 0.06, 0.5), Vector3(2.3, 2.3, -7.85), m_wood_dark)
	for i in 7:
		_candle(Vector3(1.2 + i * 0.36, 2.33, -7.75 + fmod(i * 0.31, 0.2)), 0.08 + fmod(i * 0.13, 0.14))
	for i in 4:
		_box(self, Vector3(0.36, 0.26, 0.36), Vector3(1.4 + i * 0.6, 2.47, -7.95), U.mat(Color(0.2, 0.15, 0.1), 0.85))


func _pegboard() -> void:
	# behind Nia: a dark pegboard wall carrying the rack of blades and stakes (generated)
	var board := Node3D.new()
	board.position = Vector3(4.2, 0.12, -5.7)
	board.rotation.y = -1.05
	add_child(board)
	var peg := U.mat(Color(0.26, 0.19, 0.13), 0.85)
	_box(board, Vector3(2.3, 2.6, 0.05), Vector3(0, 1.85, -0.03), peg)
	_box(board, Vector3(2.4, 0.07, 0.12), Vector3(0, 3.16, 0.0), m_wood_dark)
	_box(board, Vector3(2.4, 0.07, 0.12), Vector3(0, 0.56, 0.0), m_wood_dark)
	# the rack's front is the model's -X; turn it to face out of the board
	var rack := _prop(board, "blade_rack", Vector3(0.24, 1.55, 2.1), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 1.3, 0.1)))
	if rack == null:
		for i in 6:
			_box(board, Vector3(0.04, 1.1, 0.01), Vector3(-0.8 + i * 0.3, 2.15, 0.05), m_steel)
	# a row of stakes over the rack and vials on a little shelf under it
	for i in 9:
		var x := -0.8 + i * 0.2
		_cyl(board, 0.004, 0.02, 0.38, Vector3(x, 2.95, 0.05), m_wood, Vector3(PI, 0, 0), 6)
	_box(board, Vector3(1.0, 0.03, 0.14), Vector3(-0.45, 1.12, 0.08), m_wood_dark)
	for i in 6:
		_cyl(board, 0.018, 0.018, 0.1, Vector3(-0.85 + i * 0.15, 1.19, 0.09), U.glow(Color(0.6, 0.04, 0.03), 1.0), Vector3.ZERO, 8)


func _planning_table() -> void:
	# the planning board of photos, a city map and red string, with a desk under it
	var root := Node3D.new()
	root.position = Vector3(0.45, 0.12, -6.9)
	root.rotation.y = 0.12
	add_child(root)
	var cork := U.mat(Color(0.3, 0.2, 0.12), 0.95)
	_box(root, Vector3(1.9, 1.25, 0.06), Vector3(0, 1.75, 0), cork)
	_box(root, Vector3(2.0, 0.06, 0.08), Vector3(0, 2.4, 0), m_wood_dark)
	_box(root, Vector3(2.0, 0.06, 0.08), Vector3(0, 1.1, 0), m_wood_dark)
	var lit_paper := m_paper.duplicate() as StandardMaterial3D
	lit_paper.emission_enabled = true
	lit_paper.emission = Color(0.9, 0.75, 0.55)
	lit_paper.emission_energy_multiplier = 0.03
	_paper(root, Vector2(0.8, 0.6), Vector3(0.05, 1.75, 0.035), _map_material(0)) # the city map
	var pins: Array[Vector3] = [Vector3(0.05, 1.75, 0.05)]
	for i in 8:
		var a := i * TAU / 8.0 + 0.3
		var p := Vector3(cos(a) * 0.7, 1.75 + sin(a) * 0.42, 0.045)
		_paper(root, Vector2(0.2, 0.16), p, _map_material(1 + i), sin(i * 2.3) * 0.08)
		U.part(root, U.sphere(0.012), m_red_glow, p + Vector3(0, 0.06, 0.01))
		pins.append(p)
	var string := U.glow(Color(0.7, 0.02, 0.03), 0.7)
	for i in range(1, pins.size()):
		_string(root, pins[0], pins[i], string)
		if i > 1:
			_string(root, pins[i - 1], pins[i], string)
	# desk with maps, books, candles
	_box(root, Vector3(1.8, 0.07, 0.9), Vector3(0, 0.82, 0.5), m_wood)
	for x in [-0.82, 0.82]:
		for z in [0.12, 0.88]:
			_box(root, Vector3(0.08, 0.8, 0.08), Vector3(x, 0.4, z), m_wood_dark)
	_box(root, Vector3(1.1, 0.005, 0.6), Vector3(0.1, 0.86, 0.5), lit_paper, Vector3(0, 0.08, 0))
	for i in 3:
		_box(root, Vector3(0.28, 0.06, 0.2), Vector3(-0.68, 0.89 + i * 0.06, 0.45), U.mat(Color(0.25 - i * 0.05, 0.08, 0.06), 0.8), Vector3(0, i * 0.2, 0))
	for i in 4:
		_candle(root.to_global(Vector3(0.55 + i * 0.09, 0.86, 0.75 - i * 0.07)), 0.1 + i * 0.04)


var _map_shader: Shader

## A sheet pinned flat to the board (a quad, so the whole texture shows).
func _paper(parent: Node3D, size: Vector2, pos: Vector3, m: Material, tilt := 0.0) -> void:
	var q := QuadMesh.new()
	q.size = size
	var mi := U.part(parent, q, m, pos, Vector3(0, 0, tilt))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Paper for the planning board: kind 0 is the city map (street grid, river, a red ring
## round the target), the rest are sepia photographs of churches and rooftops.
func _map_material(kind: int) -> ShaderMaterial:
	if _map_shader == null:
		_map_shader = Shader.new()
		_map_shader.code = """
shader_type spatial;
uniform int kind = 0;
uniform float seed = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 paper = vec3(0.62, 0.52, 0.36) * (0.85 + 0.15 * h(floor(uv * 40.0)));
	vec3 col;
	if (kind == 0) {
		vec2 r = mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94)) * (uv - 0.5);
		vec2 g = abs(fract(r * 9.0) - 0.5);
		float street = smoothstep(0.06, 0.02, min(g.x, g.y));
		vec2 g2 = abs(fract(r * 2.25) - 0.5);
		float avenue = smoothstep(0.03, 0.01, min(g2.x, g2.y));
		float river = smoothstep(0.035, 0.015, abs(uv.y - 0.62 - 0.08 * sin(uv.x * 7.0)));
		float ring = smoothstep(0.012, 0.0, abs(length((uv - vec2(0.55, 0.42)) * vec2(1.3, 1.0)) - 0.12));
		col = paper;
		col = mix(col, vec3(0.3, 0.24, 0.17), street * 0.55);
		col = mix(col, vec3(0.2, 0.15, 0.1), avenue * 0.8);
		col = mix(col, vec3(0.25, 0.3, 0.32), river * 0.7);
		col = mix(col, vec3(0.75, 0.06, 0.05), ring);
	} else {
		float border = step(0.08, uv.x) * step(uv.x, 0.92) * step(0.08, uv.y) * step(uv.y, 0.92);
		float sky = smoothstep(0.75, 0.3, uv.y);
		float bx = floor(uv.x * 6.0);
		float roof = 0.35 + 0.35 * h(vec2(bx, 1.0));
		float spire = step(abs(uv.x - 0.3 - 0.4 * h(vec2(3.0, 7.0))), 0.03 * (uv.y - 0.15) * 4.0);
		float bld = step(roof, uv.y) + spire * step(0.12, uv.y);
		vec3 photo = mix(vec3(0.55, 0.47, 0.36) * (0.6 + 0.4 * sky), vec3(0.12, 0.1, 0.08), clamp(bld, 0.0, 1.0));
		col = mix(vec3(0.75, 0.7, 0.6), photo, border);
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
	EMISSION = col * 0.04;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _map_shader
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("seed", float(kind) * 1.7)
	return m


func _string(parent: Node3D, a: Vector3, b: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = U.box(Vector3(0.006, 0.006, a.distance_to(b)))
	mi.material_override = m
	parent.add_child(mi)
	mi.position = (a + b) * 0.5 + Vector3(0, 0, 0.004)
	mi.look_at(parent.to_global(b + Vector3(0, 0, 0.004)), Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)


func _workbench() -> void:
	var b := Node3D.new()
	b.name = "Workbench"
	b.position = BENCH_POS
	add_child(b)
	var top := BENCH_TOP
	# two heavy old oak bench units end to end (generated), mirrored and turned so each unit's
	# clutter (rags, oil cans, the vice) lands at an outer end, clear of Sol's hands. A planked
	# top is laid over both: one continuous scarred surface, no seam.
	var unit_len := BENCH_LEN * 0.5
	var top_frac := 0.549 / 0.677 # tabletop height / overall height of the generated bench
	var sz := Vector3(unit_len, top / top_frac, 0.95)
	var u1 := _prop(b, "workbench", sz, Transform3D(Basis(Vector3.UP, PI) * Basis().scaled(Vector3(-1, 1, 1)), Vector3(-unit_len * 0.5, 0, 0)))
	var u2 := _prop(b, "workbench", sz, Transform3D(Basis().scaled(Vector3(-1, 1, 1)), Vector3(unit_len * 0.5, 0, 0)))
	if u1 == null or u2 == null:
		_box(b, Vector3(BENCH_LEN, 0.09, 0.95), Vector3(0, top - 0.045, 0), m_wood)
		for x in [-BENCH_LEN * 0.5 + 0.1, BENCH_LEN * 0.5 - 0.1]:
			for z in [-0.4, 0.4]:
				_box(b, Vector3(0.12, top - 0.09, 0.12), Vector3(x, (top - 0.09) * 0.5, z), m_wood_dark)
	var planks := m_wood.duplicate() as StandardMaterial3D
	planks.albedo_color = Color(0.42, 0.27, 0.17)
	planks.roughness = 0.5
	_box(b, Vector3(BENCH_LEN + 0.06, 0.03, 1.0), Vector3(0, top - 0.01, 0), planks)
	for i in 4:
		_box(b, Vector3(BENCH_LEN + 0.061, 0.031, 0.008), Vector3(0, top - 0.01, -0.375 + i * 0.25), m_wood_dark)
	var top_y := top + 0.005
	# the blade Sol is honing: a long silver sabre laid across two wooden rests in front of
	# him, hilt to his left (screen right), edge toward the camera
	var bx := SOL_POS.x - BENCH_POS.x
	var bz := BLADE_Z_LOCAL
	for x in [0.28, -0.32]:
		_box(b, Vector3(0.09, BLADE_REST, 0.14), Vector3(bx + x, top_y + BLADE_REST * 0.5, bz), m_wood_dark)
	var blade := Node3D.new()
	blade.name = "HoningBlade"
	blade.position = Vector3(bx + 0.46, top_y + BLADE_REST + 0.004, bz)
	blade.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	b.add_child(blade)
	var sword_ok := false
	if ResourceLoader.exists(SWORD_SCENE):
		var sw := load(SWORD_SCENE) as PackedScene
		if sw != null:
			var inst := sw.instantiate() as Node3D
			inst.scale = Vector3.ONE * 1.18
			# no reflection probe in the crypt, so true metal reads black: a bright dielectric
			# steel with a tight highlight catches the lamp instead
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var src = (mi as MeshInstance3D).get_active_material(0)
				if src is StandardMaterial3D:
					var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					m.metallic = 0.1
					m.roughness = 0.22
					m.metallic_specular = 1.0
					m.albedo_color = Color(1.05, 1.0, 0.95)
					(mi as MeshInstance3D).material_override = m
			blade.add_child(inst)
			sword_ok = true
	if not sword_ok:
		_box(blade, Vector3(0.06, 0.008, 1.1), Vector3(0, 0, 0.6), m_steel)
		_box(blade, Vector3(0.2, 0.03, 0.03), Vector3(0, 0.01, 0.04), m_brass)
		_cyl(blade, 0.018, 0.018, 0.2, Vector3(0, 0.01, -0.08), m_wood_dark, Vector3(PI / 2.0, 0, 0), 8)
	# a bright specular sliver along the edge, so the blade reads under the lamp on every tier
	var edge := U.glow(Color(0.85, 0.82, 0.75), 0.9)
	_box(b, Vector3(0.9, 0.004, 0.006), Vector3(bx - 0.18, top_y + BLADE_REST + 0.012, bz + 0.028), edge)
	# the crossbow (generated), on the front-left corner as in the concept
	var xb := _prop(b, "crossbow", Vector3(0.8, 0.0, 0.0), Transform3D(Basis(Vector3.UP, 0.25), Vector3(-0.58, top_y, 0.2)))
	if xb == null:
		_box(b, Vector3(0.62, 0.045, 0.05), Vector3(-0.58, top_y + 0.03, 0.2), m_wood, Vector3(0, 0.35 + PI * 0.5, 0))
	# stakes, bundled, red-tipped
	for i in 5:
		var sx := 0.12 + i * 0.05
		_cyl(b, 0.004, 0.02, 0.36, Vector3(sx, top_y + 0.02, 0.25), m_wood, Vector3(PI / 2.0, 0.06 * i - 0.12, 0), 6)
		_cyl(b, 0.021, 0.021, 0.035, Vector3(sx + (0.06 * i - 0.12) * 0.15, top_y + 0.02, 0.4), U.mat(Color(0.45, 0.05, 0.04), 0.6), Vector3(PI / 2.0, 0.06 * i - 0.12, 0), 6)
	# knives
	for i in 2:
		var k := Node3D.new()
		k.position = Vector3(0.5 + i * 0.15, top_y + 0.005, 0.24)
		k.rotation.y = 0.3 + i * 0.1
		b.add_child(k)
		_box(k, Vector3(0.032, 0.006, 0.22), Vector3(0, 0, -0.08), m_steel)
		_box(k, Vector3(0.034, 0.022, 0.12), Vector3(0, 0.006, 0.09), m_wood_dark)
	# glass vials of red serum by the lamp: clear glass, the serum glowing faintly inside, corks
	var vial_glass := StandardMaterial3D.new()
	vial_glass.albedo_color = Color(0.8, 0.75, 0.7, 0.22)
	vial_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vial_glass.roughness = 0.05
	vial_glass.metallic_specular = 1.0
	var serum := U.glow(Color(0.55, 0.02, 0.03), 0.7)
	var cork := U.mat(Color(0.35, 0.24, 0.15), 0.9)
	for i in 5:
		var vh := 0.1 + fmod(i * 0.37, 0.05)
		var vp := Vector3(-0.68 + i * 0.045, top_y, -0.06 + (i % 2) * 0.05)
		_cyl(b, 0.016, 0.016, vh * 0.7, vp + Vector3(0, vh * 0.35, 0), serum, Vector3.ZERO, 8)
		_cyl(b, 0.019, 0.019, vh, vp + Vector3(0, vh * 0.5, 0), vial_glass, Vector3.ZERO, 10)
		_cyl(b, 0.012, 0.012, 0.022, vp + Vector3(0, vh + 0.008, 0), cork, Vector3.ZERO, 6)
	# the brass work lamp, on the camera-left end of the bench
	_cyl(b, 0.09, 0.11, 0.04, Vector3(-0.95, top_y + 0.02, -0.2), m_brass)
	_cyl(b, 0.012, 0.012, 0.6, Vector3(-0.92, top_y + 0.32, -0.2), m_brass, Vector3(0, 0, -0.12), 8)
	_cyl(b, 0.01, 0.01, 0.42, Vector3(-0.72, top_y + 0.66, -0.2), m_brass, Vector3(0, 0, -1.05), 8)
	var lit_brass := m_brass.duplicate() as StandardMaterial3D
	lit_brass.emission_enabled = true
	lit_brass.emission = Color(1.0, 0.7, 0.35)
	lit_brass.emission_energy_multiplier = 0.25
	var shade := _cyl(b, 0.035, 0.14, 0.16, Vector3(-0.5, top_y + 0.66, -0.2), lit_brass, Vector3(0, 0, 0.75), 16)
	_halo(BENCH_POS + Vector3(-0.46, top_y + 0.58, -0.2), 0.55, Color(1.0, 0.75, 0.45, 0.6))
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	U.part(b, U.sphere(0.04), U.glow(Color(1.0, 0.8, 0.5), 8.0), Vector3(-0.46, top_y + 0.6, -0.2))
	for i in 3:
		_candle(b.to_global(Vector3(1.35 + i * 0.07, top_y, -0.3 + i * 0.05)), 0.12 + i * 0.05)


func _window() -> void:
	# three lancets of stained glass high on the back wall, above the fridges, lit faintly
	# red by the city above (the cathedral's undercroft windows sit at street level)
	var glass := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float energy = 1.0;
void fragment() {
	// pointed head: two arcs meeting at the top centre
	vec2 p = vec2((UV.x - 0.5) * 2.0, (1.0 - UV.y) * 2.6);
	float head = p.y - 1.6;
	if (head > 0.0) {
		float r = 1.9;
		if (length(vec2(abs(p.x) + (r - 1.0), head)) > r) discard;
	}
	vec2 cell = UV * vec2(3.0, 9.0);
	vec2 g = fract(cell);
	float lead = step(0.1, g.x) * step(0.1, g.y) * step(g.x, 0.9) * step(g.y, 0.9);
	float k = fract(sin(dot(floor(cell), vec2(12.9, 78.2))) * 43758.5);
	vec3 col = mix(vec3(0.85, 0.04, 0.06), vec3(0.45, 0.02, 0.05), step(0.5, k));
	col = mix(col, vec3(0.8, 0.35, 0.1), step(0.9, k));
	col = mix(col, vec3(0.12, 0.12, 0.45), step(0.95, k));
	float fall = 0.55 + 0.45 * (1.0 - UV.y);
	ALBEDO = col * lead * energy * fall;
}
"""
	glass.shader = sh
	glass.set_shader_parameter("energy", 0.75 if cinematic else 0.95)
	var wz := -8.19
	for x in [1.55, 2.3, 3.05]:
		var q := QuadMesh.new()
		q.size = Vector2(0.46, 1.5)
		var mi := U.part(self, q, glass, Vector3(x, 3.55, wz))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# deep splayed reveal and a pointed hood moulding
		_box(self, Vector3(0.1, 1.2, 0.3), Vector3(x - 0.29, 3.4, wz + 0.12), m_vault)
		_box(self, Vector3(0.1, 1.2, 0.3), Vector3(x + 0.29, 3.4, wz + 0.12), m_vault)
		_box(self, Vector3(0.7, 0.1, 0.34), Vector3(x, 2.77, wz + 0.14), m_vault)
		_arch(Vector3(x, 0, wz + 0.12), 0.68, 3.95, Vector3.RIGHT, 0.09, 0.3, m_vault, 5, 0.85)
		_halo(Vector3(x, 3.5, wz + 0.25), 1.1, Color(1.0, 0.08, 0.1, 0.35))
	# a red wash spilling down the wall and over the vault from the windows
	_halo(Vector3(2.3, 3.7, wz + 0.5), 3.2, Color(0.9, 0.05, 0.06, 0.12))


func _chandelier() -> void:
	# a two-tier cast-iron candle chandelier hanging on chains over the planning table
	var c := Vector3(0.35, 3.05, -5.6)
	for tier_ in 2:
		var r := 0.6 - tier_ * 0.28
		var y := c.y + tier_ * 0.32
		var ring := TorusMesh.new()
		ring.inner_radius = r - 0.035
		ring.outer_radius = r + 0.02
		ring.rings = 24
		ring.ring_segments = 6
		U.part(self, ring, m_iron, Vector3(c.x, y, c.z))
		var n := 14 if tier_ == 0 else 7
		for k in n:
			var a := (k + 0.5 * tier_) * TAU / n
			var p := Vector3(c.x + cos(a) * r, y + 0.02, c.z + sin(a) * r)
			_cyl(self, 0.035, 0.025, 0.03, p, m_iron, Vector3.ZERO, 6) # drip pan
			_candle(p + Vector3(0, 0.03, 0), 0.1 + fmod(k * 0.17 + tier_ * 0.3, 0.12))
	# spokes, a central boss and the chains up into the vault
	for k in 6:
		var a := k * TAU / 6.0
		var p0 := Vector3(c.x, c.y + 0.42, c.z)
		var p1 := Vector3(c.x + cos(a) * 0.6, c.y, c.z + sin(a) * 0.6)
		_rod(p0, p1, 0.012, m_iron)
	_cyl(self, 0.05, 0.08, 0.3, c + Vector3(0, 0.38, 0), m_iron, Vector3.ZERO, 8)
	_cyl(self, 0.008, 0.008, 3.6, c + Vector3(0, 2.3, 0), m_iron, Vector3.ZERO, 4)
	_halo(c + Vector3(0, 0.15, 0), 2.2, Color(1.0, 0.6, 0.3, 0.22))


## A thin rod between two points.
func _rod(a: Vector3, b: Vector3, r: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var cy := U.cyl(r, r, a.distance_to(b))
	cy.radial_segments = 5
	cy.rings = 1
	mi.mesh = cy
	mi.material_override = m
	add_child(mi)
	var d := (b - a).normalized()
	mi.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, d)), (a + b) * 0.5)


func _candle_clusters() -> void:
	var clusters := [
		[Vector3(TUNNEL_X + 2.05, VAULT_SPRING + 0.1, -7.7), 5, 0.3], # on the pier capitals
		[Vector3(-2.7, VAULT_SPRING + 0.1, -4.4), 3, 0.25],
		[Vector3(-0.2, 0.24, -6.3), 6, 0.3], # pier base by the planning table
		[Vector3(TUNNEL_X - 1.95, 1.04, -8.0), 6, 0.3], # tunnel mouth ledge, left
		[Vector3(TUNNEL_X + 1.95, 1.04, -8.0), 5, 0.3], # tunnel mouth ledge, right
		[Vector3(4.15, 1.0, -4.6), 8, 0.5], # right ledge, behind Nia
		[Vector3(4.15, 1.0, -2.6), 5, 0.4],
		[Vector3(3.6, 0.24, -1.9), 5, 0.3], # platform corner
	]
	for c in clusters:
		var p: Vector3 = c[0]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(p.x * 100 + p.z * 10)
		for i in int(c[1]):
			var off := Vector3(rng.randf_range(-1, 1) * c[2], 0, rng.randf_range(-1, 1) * c[2] * 0.6)
			_candle(p + off, rng.randf_range(0.08, 0.3))
	# tunnel-mouth ledges
	_box(self, Vector3(0.6, 1.0, 0.5), Vector3(TUNNEL_X - 1.95, 0.5, -8.0), m_stone)
	_box(self, Vector3(0.6, 1.0, 0.5), Vector3(TUNNEL_X + 1.95, 0.5, -8.0), m_stone)


## Queue a candle (body + flame) at a base point; flushed into two MultiMeshes.
func _candle(base: Vector3, h: float) -> void:
	var r := 0.022 + h * 0.06
	candle_xf.append(Transform3D(Basis().scaled(Vector3(r, h, r)), base + Vector3(0, h * 0.5, 0)))


func _flush_candles() -> void:
	var body := CylinderMesh.new()
	body.top_radius = 1.0
	body.bottom_radius = 1.0
	body.height = 1.0
	body.radial_segments = 8
	body.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = body
	mm.instance_count = candle_xf.size()
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.mesh = flame_mesh
	fm.instance_count = candle_xf.size()
	for i in candle_xf.size():
		var x: Transform3D = candle_xf[i]
		mm.set_instance_transform(i, x)
		var top := x.origin + Vector3(0, x.basis.get_scale().y * 0.5 + 0.005, 0)
		var s := 0.8 + fmod(i * 0.37, 0.5)
		fm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), top))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m_wax
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var fi := MultiMeshInstance3D.new()
	fi.multimesh = fm
	fi.material_override = flame_mat
	fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fi)
	# every candle also gets a small halo, so the clusters bloom even without real lights
	for x in candle_xf:
		var top := x.origin + Vector3(0, x.basis.get_scale().y * 0.5 + 0.06, 0)
		_halo(top, 0.32, Color(1.0, 0.6, 0.28, 0.28))
	_flush_halos()


## Queue a soft additive glow sprite (billboard); colour alpha = intensity.
func _halo(pos: Vector3, size: float, col: Color) -> void:
	halos.append([pos, size, col])


func _halo_material(priority: int) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
varying vec4 tint;
void vertex() {
	tint = COLOR;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.x *= sx;
	VERTEX.y *= sy;
}
void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float g = exp(-dot(d, d) * 4.0);
	ALBEDO = tint.rgb * tint.a * g * 2.0;
	ALPHA = g;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = priority
	return m


func _flush_halos(reflect := true) -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var sets := [[halos, 0, false]]
	if not cinematic and reflect:
		# web tier: no SSR, so mirror every light below the translucent water as a streak
		var refl: Array = []
		for h in halos:
			var p: Vector3 = h[0]
			if p.y > 0.05:
				refl.append([Vector3(p.x, -p.y - 0.04, p.z), h[1], Color(h[2].r, h[2].g, h[2].b, h[2].a * 0.55)])
		sets.append([refl, -1, true])
	for st in sets:
		var list: Array = st[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = q
		mm.instance_count = list.size()
		for i in list.size():
			var h: Array = list[i]
			var sz: float = h[1]
			var scl := Vector3(sz * 0.45, sz * 2.4, 1.0) if st[2] else Vector3(sz, sz, 1.0)
			mm.set_instance_transform(i, Transform3D(Basis().scaled(scl), h[0]))
			mm.set_instance_color(i, h[2])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _halo_material(st[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-30, -30, -40), Vector3(60, 60, 60))
		add_child(mi)
	halos = []


## Web tier fill: big, faint additive glows on the vault and walls near each light source,
## standing in for bounce light so the ribs and piers read with only four real lights.
func _bounce() -> void:
	var k := 0.6 if cinematic else 1.0
	_halo(Vector3(0.35, 4.0, -5.8), 4.2, Color(1.0, 0.58, 0.3, 0.1 * k)) # over the chandelier
	_halo(Vector3(TUNNEL_X + 2.05, 3.4, -7.5), 2.6, Color(1.0, 0.6, 0.32, 0.1 * k)) # pier by the tunnel
	_halo(Vector3(4.1, 3.4, -5.0), 2.8, Color(1.0, 0.55, 0.3, 0.09 * k)) # over the blade rack
	_halo(Vector3(-2.7, 3.4, -4.4), 1.8, Color(1.0, 0.6, 0.32, 0.05 * k)) # the dark left pier, barely
	_flush_halos(false)


## Web tier: there is no SSR, so each strong light gets a soft streak laid flat on the wet
## flagstones, masked by the same puddle noise as the floor's roughness.
func _puddles() -> void:
	if cinematic or puddle_glows.is_empty():
		return
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D wet : filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.3;
varying vec3 wpos;
varying vec4 tint;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = COLOR;
}
void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float g = exp(-d.x * d.x * 5.0 - d.y * d.y * 1.6);
	float mask = 1.0 - smoothstep(0.2, 0.5, texture(wet, wpos.xz * uv_scale).r);
	float rip = 0.75 + 0.25 * sin(wpos.z * 40.0 + sin(wpos.x * 13.0) * 2.0 + TIME * 0.7);
	ALBEDO = tint.rgb * tint.a * g * mask * rip;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("wet", puddle_tex)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	mm.mesh = pm
	mm.instance_count = puddle_glows.size()
	for i in puddle_glows.size():
		var pg: Array = puddle_glows[i]
		var p: Vector3 = pg[0]
		# stretched toward the camera, as a reflection on a flat wet floor would be
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.9, 1.0, 2.6)), Vector3(p.x, 0.125, p.z + 0.9)))
		var c: Color = pg[1]
		mm.set_instance_color(i, Color(c.r, c.g, c.b, 0.9))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _dust() -> void:
	# dust motes drifting through the lamp light
	var p := CPUParticles3D.new()
	p.amount = 90 if cinematic else 50
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.4, 1.4, 1.8)
	p.position = Vector3(0.9, 1.6, -3.3)
	p.direction = Vector3(0.3, 1, 0)
	p.spread = 180.0
	p.gravity = Vector3(0, -0.004, 0)
	p.initial_velocity_min = 0.01
	p.initial_velocity_max = 0.05
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.012)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.85, 0.65, 0.5)
	m.albedo_texture = _soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.mesh = q
	add_child(p)


# ---------------------------------------------------------------- characters
func _sol() -> void:
	var scene: PackedScene = null
	for path in SOL_SCENES:
		if ResourceLoader.exists(path):
			scene = load(path) as PackedScene
			if scene != null:
				break
	if scene == null:
		return
	var model := scene.instantiate() as Node3D
	model.name = "Sol"
	model.position = SOL_POS
	model.rotation.y = 0.0 # faces +Z, toward the bench and the camera
	add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sol_skel = model.find_children("*", "Skeleton3D", true, false).front() if not model.find_children("*", "Skeleton3D", true, false).is_empty() else null
	if sol_skel == null:
		return
	var pose = BenchPose.new()
	pose.name = "BenchPose"
	var bench_local := BENCH_POS - SOL_POS
	pose.blade_y = BENCH_TOP + bench_local.y + 0.005 + BLADE_REST + 0.012
	pose.blade_z = bench_local.z + BLADE_Z_LOCAL
	pose.left_x = 0.22
	pose.stroke_from = -0.06
	pose.stroke_to = -0.44
	add_child(pose)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	pose.setup(sol_skel, players.front() if not players.is_empty() else null)
	# the whetstone under his right fist
	if pose.stone != null:
		U.part(pose.stone, U.box(Vector3(0.17, 0.035, 0.055)), U.mat(Color(0.36, 0.33, 0.3), 0.85), Vector3.ZERO)
	if pose.modular:
		# the modular hero has separate fist meshes (no metallic hands to fix); the blade he is
		# honing lies on the bench, so his own sword stays out of the fist
		var blade := model.find_child("Blade", true, false) as Node3D
		if blade != null:
			blade.visible = false
		return
	_fix_hands(model)


## The generated mesh's hands carry metallic values in its ORM map, so under the work lamp
## they flare white. On the menu set Sol's material is swapped for a shader copy of it that
## turns the metal off and keeps the skin tone within a small radius of each hand bone.
var hand_mat: ShaderMaterial
var hand_bones := PackedInt32Array()

func _fix_hands(model: Node3D) -> void:
	var mi: MeshInstance3D = null
	for m in model.find_children("*", "MeshInstance3D", true, false):
		mi = m
		break
	if mi == null or not (mi.get_active_material(0) is StandardMaterial3D):
		return
	var src := mi.get_active_material(0) as StandardMaterial3D
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform vec4 rough_ch = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 metal_ch = vec4(0.0, 0.0, 1.0, 0.0);
uniform float normal_depth = 1.0;
uniform vec3 hand_a = vec3(0.0, -100.0, 0.0);
uniform vec3 hand_b = vec3(0.0, -100.0, 0.0);
uniform float radius = 0.16;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec4 a = texture(albedo_tex, UV);
	vec4 o = texture(orm_tex, UV);
	float d = min(distance(wpos, hand_a), distance(wpos, hand_b));
	float k = 1.0 - smoothstep(radius * 0.6, radius, d);
	vec3 skin = vec3(0.3, 0.17, 0.11) * (0.6 + 0.8 * dot(a.rgb, vec3(0.33)));
	ALBEDO = mix(a.rgb, skin, k * 0.85);
	ROUGHNESS = mix(dot(o, rough_ch), 0.62, k);
	METALLIC = mix(dot(o, metal_ch), 0.0, k);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
"""
	hand_mat = ShaderMaterial.new()
	hand_mat.shader = sh
	hand_mat.set_shader_parameter("albedo_tex", src.albedo_texture)
	hand_mat.set_shader_parameter("normal_tex", src.normal_texture)
	hand_mat.set_shader_parameter("orm_tex", src.roughness_texture)
	var ch := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.33, 0.33, 0.33, 0)]
	hand_mat.set_shader_parameter("rough_ch", ch[src.roughness_texture_channel])
	hand_mat.set_shader_parameter("metal_ch", ch[src.metallic_texture_channel])
	hand_mat.set_shader_parameter("normal_depth", src.normal_scale)
	mi.material_override = hand_mat
	hand_bones = PackedInt32Array([sol_skel.find_bone("Hand.L"), sol_skel.find_bone("Hand.R")])
	_update_hands()


func _update_hands() -> void:
	if hand_mat == null or hand_bones.has(-1):
		return
	var names := ["hand_a", "hand_b"]
	for i in 2:
		var g := sol_skel.global_transform * sol_skel.get_bone_global_pose(hand_bones[i])
		hand_mat.set_shader_parameter(names[i], g * Vector3(0.08 if i == 0 else -0.08, 0, 0))


func _nia() -> void:
	if not ResourceLoader.exists(NIA_SCENE):
		return
	var scene := load(NIA_SCENE) as PackedScene
	if scene == null:
		return
	nia = scene.instantiate() as Node3D
	nia.position = NIA_POS
	nia.rotation.y = -0.45 # turned toward Sol and the camera
	add_child(nia)
	for mi in nia.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var idle = NiaIdle.new()
	idle.name = "NiaIdle"
	add_child(idle)
	idle.setup(nia)


# ---------------------------------------------------------------- lights
func _omni(pos: Vector3, col: Color, energy: float, rng: float, shadow := false, flicker := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadow and cinematic
	l.light_volumetric_fog_energy = 0.6
	add_child(l)
	if flicker:
		flicker_lights.append([l, energy, randf() * 10.0])
	return l


func _lights() -> void:
	# 1. the work lamp: warm key on Sol's hands and face
	var lamp := SpotLight3D.new()
	lamp.position = BENCH_POS + Vector3(-0.45, BENCH_TOP + 0.58, -0.2)
	lamp.look_at_from_position(lamp.position, SOL_POS + Vector3(-0.15, 1.12, 0.42), Vector3.UP)
	lamp.light_color = Color(1.0, 0.74, 0.45)
	lamp.light_energy = 2.6 if cinematic else 2.4
	lamp.spot_range = 5.0
	lamp.spot_angle = 60.0
	lamp.spot_attenuation = 0.9
	lamp.shadow_enabled = true
	lamp.shadow_blur = 1.5
	lamp.light_volumetric_fog_energy = 1.6
	add_child(lamp)
	# 2. the blood fridges: red spill across the back of the lab
	_omni(Vector3(2.27, 1.2, -7.0), Color(1.0, 0.08, 0.08), 2.4, 3.6)
	# 3. candles on the planning table / chandelier: warm fill, flickering
	_omni(Vector3(0.3, 2.75, -5.4), Color(1.0, 0.6, 0.3), 3.4, 8.5, false, true)
	# 4. the candle ledge behind Nia: rims Sol and Nia, lights the pegboard
	_omni(Vector3(3.6, 1.7, -3.5), Color(1.0, 0.64, 0.36), 2.4, 4.5, false, true)
	if cinematic:
		_omni(Vector3(TUNNEL_X, 1.6, -9.5), Color(1.0, 0.65, 0.35), 1.5, 6.0, true, true) # tunnel mouth candles
		_omni(NIA_POS + Vector3(-0.15, 1.35, 0.45), Color(0.6, 0.75, 1.0), 0.35, 1.0) # tablet on Nia's face
		_omni(Vector3(-1.2, 0.8, -5.2), Color(1.0, 0.6, 0.3), 1.0, 3.0, false, true) # pier-base candles
		lamp.shadow_enabled = true
	else:
		_fake_cone(lamp)
	_beam_motes(lamp)


## Web tier: a faint additive cone under the work lamp stands in for volumetric light.
func _fake_cone(lamp: SpotLight3D) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
varying float h;
void vertex() { h = VERTEX.y; }
void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	// slow drifting haze in the beam
	float haze = 0.75 + 0.25 * sin(h * 23.0 - TIME * 0.6) * sin(UV.x * 31.4 + TIME * 0.3);
	ALBEDO = vec3(1.0, 0.72, 0.42);
	ALPHA = edge * smoothstep(-0.45, 0.4, h) * 0.13 * haze;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var c := CylinderMesh.new()
	c.top_radius = 0.06
	c.bottom_radius = 0.55
	c.height = 0.9
	c.cap_top = false
	c.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var dir := -lamp.global_transform.basis.z
	mi.global_position = lamp.global_position + dir * 0.45
	mi.global_transform.basis = Basis(Quaternion(Vector3.DOWN, dir.normalized())) # cone axis along the beam


var _dot_tex: GradientTexture2D

## A small radial falloff, so dust motes read as soft specks rather than square pixels.
func _soft_dot() -> GradientTexture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_dot_tex = GradientTexture2D.new()
		_dot_tex.gradient = g
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(1.0, 0.5)
		_dot_tex.width = 32
		_dot_tex.height = 32
	return _dot_tex


## Bright dust motes hanging in the lamp beam (both tiers).
func _beam_motes(lamp: SpotLight3D) -> void:
	var p := CPUParticles3D.new()
	p.amount = 46
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.32
	var dir := -lamp.global_transform.basis.z
	p.position = lamp.position + dir * 0.5
	p.direction = Vector3(0.2, 1, 0.1)
	p.spread = 180.0
	p.gravity = Vector3(0, -0.003, 0)
	p.initial_velocity_min = 0.005
	p.initial_velocity_max = 0.025
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.012)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.85, 0.6, 0.9)
	m.albedo_texture = _soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.mesh = q
	add_child(p)


# ---------------------------------------------------------------- camera
func _camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.near = 0.1
	camera.far = 80.0
	add_child(camera)
	if cinematic:
		var attr := CameraAttributesPractical.new()
		attr.dof_blur_far_enabled = true
		attr.dof_blur_far_distance = 9.0
		attr.dof_blur_far_transition = 8.0
		attr.dof_blur_amount = 0.025
		camera.attributes = attr
	_place_camera(0.0)


func _place_camera(time: float) -> void:
	# ease back and forth between the two framings, with a slow handheld wobble
	var k := 0.5 - 0.5 * cos(time * TAU / DRIFT_TIME)
	k = k * k * (3.0 - 2.0 * k)
	var pos: Vector3 = (SHOT_A[0] as Vector3).lerp(SHOT_B[0], k)
	var tgt: Vector3 = (SHOT_A[1] as Vector3).lerp(SHOT_B[1], k)
	var fov: float = lerpf(SHOT_A[2], SHOT_B[2], k)
	var wob := Vector3(sin(time * 0.71) * 0.012 + sin(time * 1.93) * 0.004,
		sin(time * 0.53 + 1.0) * 0.009 + sin(time * 2.3) * 0.003, 0.0)
	# narrower than 16:9 (4:3 tablets, split screens): hold the 16:9 horizontal view instead of
	# the vertical one, so Sol at the bench and Nia by the fridges stay in frame (R2-A, U2)
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	if aspect < 16.0 / 9.0 - 0.01:
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) * 0.5) * 16.0 / 9.0))
	else:
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = fov
	camera.look_at_from_position(pos + wob, tgt + wob * 0.4 + Vector3(sin(time * 0.37) * 0.02, 0, 0), Vector3.UP)


func _process(delta: float) -> void:
	t += delta
	_place_camera(t)
	for f in flicker_lights:
		var l: OmniLight3D = f[0]
		var ph: float = f[2]
		l.light_energy = f[1] * (0.86 + 0.08 * sin(t * 9.0 + ph) + 0.06 * sin(t * 23.0 + ph * 3.0))
	_update_hands()
	env.tonemap_exposure = base_exposure * Settings.brightness
