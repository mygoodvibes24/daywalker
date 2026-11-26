extends RefCounted
## Rain-soaked surface materials: wet asphalt with puddles and wet paving.
## One spatial shader that works in Forward+ (where SSR reflects the city in
## the puddles) and in Compatibility (where lamps leave long specular streaks).
## Texturing is in world space, so any mesh can use it without UVs.

const SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D puddle_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_alb : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_mix : hint_range(0.0, 1.0) = 0.0; // 1 = the photographic library texture
uniform float detail_scale = 0.25; // repeats per metre
uniform vec3 base_color : source_color = vec3(0.075, 0.075, 0.08);
uniform float dry_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float damp_roughness : hint_range(0.0, 1.0) = 0.5;
uniform float puddle_roughness : hint_range(0.0, 1.0) = 0.06;
uniform float wetness : hint_range(0.0, 1.0) = 1.0;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.5;
uniform float puddle_scale = 0.035;
uniform float grain_scale = 0.45;
uniform float normal_strength = 0.35;
uniform float rain = 1.0; // drives the ripples in puddles

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	// V1 (critic R2): no per-pixel glitter. Fine normal detail fades out once a texel gets
	// smaller than a pixel (from the screen-space footprint), and the wet roughness never drops
	// below 0.3 outside the puddles, so lamp highlights stay smooth streaks instead of sparkles.
	float foot = length(fwidth(p));
	float fine = 1.0 - smoothstep(0.02, 0.09, foot);
	float n = texture(puddle_noise, p * puddle_scale).r;
	float n2 = texture(puddle_noise, p * puddle_scale * 4.3 + vec2(0.37, 0.71)).r;
	float shape = n * 0.78 + n2 * 0.22;
	float cut = mix(0.78, 0.46, puddle_amount);
	float puddle = smoothstep(cut, cut + 0.07, shape) * wetness;
	// photographic cracked asphalt / concrete, rotated against itself to hide the repeat
	vec2 dp = p * detail_scale;
	vec2 dq = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * detail_scale * 0.37 + 0.41;
	vec3 da = mix(texture(detail_alb, dp).rgb, texture(detail_alb, dq).rgb, smoothstep(0.35, 0.65, n2));
	vec3 dn = mix(texture(detail_nrm, dp).rgb, texture(detail_nrm, dq).rgb, smoothstep(0.35, 0.65, n2));
	float dl = dot(da, vec3(0.3, 0.59, 0.11));
	// darker where the ground is soaked, darkest in standing water
	vec3 col = base_color * (0.82 + 0.36 * n2);
	col = mix(col, base_color * (0.45 + 1.4 * da), detail_mix);
	col *= mix(1.0, 0.7, wetness);
	col *= mix(1.0, 0.55, puddle);
	ALBEDO = col;
	float damp = max(damp_roughness * (0.8 + 0.4 * n2) + (0.5 - dl) * 0.25 * detail_mix, 0.3);
	ROUGHNESS = mix(dry_roughness, mix(damp, puddle_roughness, puddle), wetness);
	METALLIC = 0.0;
	SPECULAR = mix(0.45, 0.6, puddle);
	// asphalt grain (library normal or the noise grain), flattened under standing water, plus
	// rain ripples in the puddles
	vec3 grain = mix(texture(grain_normal, p * grain_scale).rgb, dn, detail_mix);
	vec3 r1 = texture(grain_normal, p * 1.9 + vec2(TIME * 0.11, -TIME * 0.07)).rgb;
	vec3 r2 = texture(grain_normal, p * 2.3 + vec2(-TIME * 0.09, TIME * 0.13)).rgb;
	vec3 ripple = normalize((r1 + r2) - 1.0) * 0.5 + 0.5;
	NORMAL_MAP = mix(grain, ripple, puddle * rain * 0.6 * fine);
	NORMAL_MAP_DEPTH = normal_strength * mix(1.0, 0.25 + 0.35 * rain, puddle) * mix(0.35, 1.0, fine);
}
"""

static var _shader: Shader
static var _puddle_tex: NoiseTexture2D
static var _grain_tex: NoiseTexture2D
static var _asphalt: ShaderMaterial
static var _paving: ShaderMaterial


static func _textures() -> void:
	if _shader != null:
		return
	_shader = Shader.new()
	_shader.code = SHADER
	var pn := FastNoiseLite.new()
	pn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pn.frequency = 0.012
	pn.fractal_octaves = 4
	pn.seed = 7
	_puddle_tex = NoiseTexture2D.new()
	_puddle_tex.width = 256
	_puddle_tex.height = 256
	_puddle_tex.seamless = true
	_puddle_tex.normalize = true
	_puddle_tex.noise = pn
	var gn := FastNoiseLite.new()
	gn.noise_type = FastNoiseLite.TYPE_CELLULAR
	gn.frequency = 0.09
	gn.fractal_octaves = 2
	gn.seed = 3
	_grain_tex = NoiseTexture2D.new()
	_grain_tex.width = 256
	_grain_tex.height = 256
	_grain_tex.seamless = true
	_grain_tex.as_normal_map = true
	_grain_tex.bump_strength = 6.0
	_grain_tex.noise = gn


static func _make(base: Color, puddles: float, normal_strength: float) -> ShaderMaterial:
	_textures()
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("puddle_noise", _puddle_tex)
	m.set_shader_parameter("grain_normal", _grain_tex)
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("puddle_amount", puddles)
	m.set_shader_parameter("normal_strength", normal_strength)
	return m


const LIB := "res://assets/textures/library/%s_%s.jpg"


## The photographic library texture under a wet surface (falls back to the noise grain).
static func _detail(m: ShaderMaterial, lib: String, scale: float) -> void:
	if not ResourceLoader.exists(LIB % [lib, "albedo"]):
		return
	m.set_shader_parameter("detail_alb", load(LIB % [lib, "albedo"]))
	m.set_shader_parameter("detail_nrm", load(LIB % [lib, "normal"]))
	m.set_shader_parameter("detail_mix", 1.0)
	m.set_shader_parameter("detail_scale", scale)


## Wet asphalt with puddles (roads, plaza). Shared: every caller gets the same material.
static func asphalt() -> ShaderMaterial:
	if _asphalt == null:
		_asphalt = _make(Color(0.085, 0.085, 0.09), 0.55, 0.35)
		_detail(_asphalt, "cracked_asphalt", 0.22)
	return _asphalt


## Wet quay and tank-farm concrete (critic V1: the ground there read as molten plastic):
## lighter, a few big puddles, the weathered concrete texture at a tight repeat.
static func concrete(base: Color) -> ShaderMaterial:
	var m := _make(base, 0.3, 0.3)
	m.set_shader_parameter("dry_roughness", 0.9)
	m.set_shader_parameter("damp_roughness", 0.6)
	m.set_shader_parameter("puddle_scale", 0.06)
	_detail(m, "weathered_concrete", 0.3)
	return m


## Wet paving stones (sidewalks): lighter, fewer puddles. Shared like asphalt().
static func paving() -> ShaderMaterial:
	if _paving == null:
		_paving = _make(Color(0.26, 0.25, 0.24), 0.25, 0.3)
		_paving.set_shader_parameter("dry_roughness", 0.9)
		_paving.set_shader_parameter("damp_roughness", 0.5)
		_paving.set_shader_parameter("grain_scale", 0.8)
	return _paving


## Rain ripples in the puddles (0 = dry spell, 1 = downpour).
static func set_rain(amount: float) -> void:
	for m in [_asphalt, _paving]:
		if m != null:
			m.set_shader_parameter("rain", amount)
