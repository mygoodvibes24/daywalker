extends Node3D
## Lighting, atmosphere and weather for Port Vesper.
##
## Two quality tiers, picked from the renderer that is actually running:
##   "cinematic" (Forward+, desktop): volumetric fog, SSR, SSAO, SSIL, TAA,
##       soft shadows, shadowed street lamps that light the fog, GPU rain.
##   "web" (Compatibility, browser): depth + height fog, glow, fake light
##       cones under the lamps, CPU rain, lighter film grain.
## main.gd owns the clock; it calls update_lighting() every frame.

const U = preload("res://scripts/util.gd")
const Wet = preload("res://scripts/wet_materials.gd")
const RainScript = preload("res://scripts/rain.gd")
const PostFxScript = preload("res://scripts/post_fx.gd")

const SOL_LIGHT_LAYER := 1 << 19 # render layer 20: only Sol receives the rim and fill lights

var tier := "web"
## Exposed setting: scales the fog density (the map sets it so landmarks read at range).
var fog_scale := 1.0
var cinematic := false
var main: Node3D
var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var rain: Node3D
var post: CanvasLayer
var rim: OmniLight3D
var fill: OmniLight3D
var lamp_cones: Array[MeshInstance3D] = []
var cone_mat: ShaderMaterial
var _lamps_done := 0
var _sol_done := false
var _sky_t := 0.0
var _sky_colors: Array[Color] = []
var _lightning_t := 0.0
var _flash := 0.0
var _flash2_t := 0.0


## "cinematic" on Forward+/Mobile (a RenderingDevice exists), "web" on Compatibility.
static func detect_tier() -> String:
	if OS.has_feature("web"):
		return "web"
	var method := str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	if RenderingServer.get_rendering_device() == null or method == "gl_compatibility":
		return "web" # also --rendering-method gl_compatibility and the headless dummy renderer
	return "cinematic"


func _ready() -> void:
	tier = detect_tier()
	cinematic = tier == "cinematic"
	print("Daywalker render tier: ", tier)
	_build_environment()
	_build_sun()
	_setup_viewport()
	rain = RainScript.new()
	rain.name = "Rain"
	add_child(rain)
	rain.setup(cinematic)
	post = PostFxScript.new()
	post.name = "PostFX"
	add_child(post)
	post.configure(cinematic)
	var rain_on: bool = Settings.rain
	if "--norain" in OS.get_cmdline_user_args() or _url_flag("norain"):
		rain_on = false
	set_rain(rain_on)
	if not InputMap.has_action("toggle_rain"):
		InputMap.add_action("toggle_rain")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_T
		InputMap.action_add_event("toggle_rain", k)
		var b := InputEventJoypadButton.new()
		b.button_index = JOY_BUTTON_BACK
		b.device = -1
		InputMap.action_add_event("toggle_rain", b)


func _url_flag(flag: String) -> bool:
	if not OS.has_feature("web"):
		return false
	var q := str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
	for part in q.split("&", false):
		if part.split("=")[0] == flag:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_rain"):
		set_rain(not rain.enabled)
		if main != null and main.hud != null:
			main.hud.popup("RAIN ON" if rain.enabled else "RAIN OFF")


func set_rain(on: bool) -> void:
	rain.set_enabled(on)
	Wet.set_rain(1.0 if on else 0.0)


# ---------------------------------------------------------------- setup
func _build_environment() -> void:
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 6.0
	sky_mat.sun_curve = 0.08
	sky_mat.ground_curve = 0.05
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256 if cinematic else Sky.RADIANCE_SIZE_64
	if cinematic:
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.85
	# glow: neon, lamps and windows bloom softly
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.85 if cinematic else 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3, 5] else 0.0)
	# grade: a little contrast, desaturated, cool shadows / warm highlights
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 0.8
	env.adjustment_color_correction = _grade_lut()
	if cinematic:
		env.ssr_enabled = true
		env.ssr_max_steps = 72
		env.ssr_fade_in = 0.12
		env.ssr_fade_out = 2.5
		env.ssr_depth_tolerance = 0.25
		env.ssao_enabled = true
		env.ssao_radius = 1.4
		env.ssao_intensity = 2.2
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		env.ssil_enabled = true
		env.ssil_radius = 6.0
		env.ssil_intensity = 1.2
		env.volumetric_fog_enabled = true
		env.volumetric_fog_length = 80.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_anisotropy = 0.55
		env.volumetric_fog_gi_inject = 0.0
		env.volumetric_fog_ambient_inject = 0.25
		env.volumetric_fog_sky_affect = 0.3
		env.volumetric_fog_temporal_reprojection_enabled = true
		env.fog_density = 0.004
	else:
		env.fog_density = 0.012
		env.fog_height = 1.2
		env.fog_height_density = 0.06
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


## Per-channel grading curve: lifted blue-black shadows, slightly warm highlights.
func _grade_lut() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.012, 0.03))
	g.set_color(1, Color(1.0, 0.97, 0.9))
	g.add_point(0.25, Color(0.22, 0.245, 0.27))
	g.add_point(0.6, Color(0.61, 0.6, 0.585))
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


func _build_sun() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "SunMoon"
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	if cinematic:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 90.0
		sun.shadow_blur = 1.5
		sun.light_angular_distance = 0.6 # soft penumbrae (PCSS)
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 50.0
	sun.light_volumetric_fog_energy = 1.0
	add_child(sun)


func _setup_viewport() -> void:
	var vp := get_viewport()
	if cinematic:
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.use_taa = true
		vp.use_debanding = true
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		RenderingServer.directional_shadow_atlas_set_size(4096, true)
	else:
		vp.msaa_3d = Viewport.MSAA_2X


## The street lamps exist only after main builds the city; dress them the first time we see them.
func _dress_lamps() -> void:
	var lamps: Array = main.lamps
	for i in range(_lamps_done, lamps.size()):
		var l: OmniLight3D = lamps[i]
		l.light_color = Color(1.0, 0.72, 0.42)
		l.omni_range = 14.0
		l.omni_attenuation = 1.3
		if cinematic:
			l.shadow_enabled = true
			l.shadow_blur = 1.2
			l.light_size = 0.12
			l.shadow_bias = 0.08
			l.light_volumetric_fog_energy = 2.5
		else:
			l.shadow_enabled = false
			lamp_cones.append(_cone_for(l))
	_lamps_done = lamps.size()


## Web tier: an additive cone under each lamp stands in for volumetric light.
func _cone_for(l: OmniLight3D) -> MeshInstance3D:
	if cone_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.42, 1.0);
uniform float strength = 0.0;
varying float h;
void vertex() { h = VERTEX.y; }
void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float fall = smoothstep(-2.2, 2.0, h);
	ALBEDO = tint.rgb;
	ALPHA = strength * edge * fall * 0.16;
}
"""
		cone_mat = ShaderMaterial.new()
		cone_mat.shader = sh
	var c := CylinderMesh.new()
	c.top_radius = 0.25
	c.bottom_radius = 2.6
	c.height = 4.2
	c.cap_top = false
	c.cap_bottom = false
	c.radial_segments = 20
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = cone_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.get_parent().add_child(mi)
	mi.global_position = l.global_position + Vector3(0, -2.1, 0)
	return mi


## Rim + fill lights that only touch Sol, so the black coat reads against the night.
func _dress_sol() -> void:
	var p = main.player
	if p == null or p.pivot == null or p.camera == null:
		return
	for mi in p.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers |= SOL_LIGHT_LAYER
	rim = OmniLight3D.new()
	rim.name = "SolRim"
	rim.light_cull_mask = SOL_LIGHT_LAYER
	rim.omni_range = 5.0
	rim.light_specular = 1.0
	rim.position = Vector3(-1.5, 0.6, -1.3) # ahead of Sol, off to the side: catches the coat edge
	p.pivot.add_child(rim)
	fill = OmniLight3D.new()
	fill.name = "SolFill"
	fill.light_cull_mask = SOL_LIGHT_LAYER
	fill.omni_range = 9.0
	fill.light_specular = 0.3
	fill.position = Vector3(0.4, 0.8, 0.0)
	p.camera.add_child(fill)
	_sol_done = true


# ---------------------------------------------------------------- per frame
## d = daylight 0..1, night = 0..1 (1 = full night), full_moon from the clock.
func update_lighting(d: float, night: float, full_moon: bool) -> void:
	if main != null:
		if main.lamps.size() != _lamps_done:
			_dress_lamps()
		if not _sol_done and main.player != null and main.player.is_inside_tree():
			_dress_sol()
	# sky: navy night (violet under a full moon), ember dusk, overcast rain-grey noon
	var night_top := Color(0.012, 0.018, 0.045) if not full_moon else Color(0.03, 0.03, 0.065)
	var night_hor := Color(0.05, 0.06, 0.1) if not full_moon else Color(0.1, 0.085, 0.13)
	var top := night_top.lerp(Color(0.18, 0.16, 0.24), clampf(d * 3.0, 0.0, 1.0)).lerp(Color(0.34, 0.39, 0.46), clampf((d - 0.3) / 0.7, 0.0, 1.0))
	var hor := night_hor.lerp(Color(0.62, 0.32, 0.22), clampf(d * 3.0, 0.0, 1.0)).lerp(Color(0.55, 0.58, 0.62), clampf((d - 0.3) / 0.7, 0.0, 1.0))
	_set_sky(top, hor)
	# fog: thick, moon-blue at night; thinner rain haze by day
	var fog_col := hor.lerp(Color(0.16, 0.2, 0.3), night * 0.6)
	if full_moon:
		fog_col = fog_col.lerp(Color(0.24, 0.2, 0.3), night * 0.5)
	env.fog_light_color = fog_col
	env.fog_light_energy = 1.0
	if cinematic:
		env.fog_density = lerpf(0.0035, 0.006, night) * fog_scale
		env.volumetric_fog_density = lerpf(0.012, 0.032, night) * fog_scale
		env.volumetric_fog_albedo = Color(0.75, 0.8, 0.9).lerp(Color(0.62, 0.7, 0.95), night)
		var glow := Color(0.02, 0.025, 0.05) if not full_moon else Color(0.04, 0.03, 0.06)
		env.volumetric_fog_emission = glow * night
		env.volumetric_fog_emission_energy = 1.0
	else:
		env.fog_density = lerpf(0.009, 0.016, night) * fog_scale
	# ambient: cool and present at night so the city never goes pitch black
	env.ambient_light_color = Color(0.3, 0.38, 0.6).lerp(Color(0.68, 0.7, 0.76), d)
	env.ambient_light_energy = lerpf(0.55 if cinematic else 0.6, 0.65, d)
	env.ambient_light_sky_contribution = 0.0
	env.tonemap_exposure = (lerpf(1.25, 1.0, d) if cinematic else lerpf(1.3, 1.0, d)) * Settings.brightness
	env.glow_intensity = lerpf(1.0, 0.45, d) * (1.0 if cinematic else 0.8)
	env.adjustment_saturation = lerpf(0.78, 0.85, d)
	# key light: low warm sun by day, cold moon by night
	if d > 0.0:
		sun.light_color = Color(1.0, 0.55, 0.35).lerp(Color(1.0, 0.95, 0.88), clampf(d * 1.5, 0.0, 1.0))
		sun.light_energy = 0.25 + d * 0.8
		sun.light_volumetric_fog_energy = 0.6
		sky_mat.sun_angle_max = 6.0
	else:
		sun.light_color = Color(0.6, 0.7, 1.0) if not full_moon else Color(0.85, 0.82, 0.95)
		sun.light_energy = (0.7 if full_moon else 0.5)
		sun.light_volumetric_fog_energy = 1.4
		sky_mat.sun_angle_max = 9.0 if full_moon else 5.0
	_update_lightning(night)
	sun.light_energy += _flash * 2.5
	# practical lights: warm against the cool night
	var practical := night
	main.window_mat.emission_energy_multiplier = practical * 1.8
	main.lamp_mat.emission_energy_multiplier = 0.2 + practical * 6.0
	for l in main.lamps:
		l.light_energy = practical * (2.6 if cinematic else 2.4)
		l.visible = practical > 0.02
	for c in lamp_cones:
		c.visible = practical > 0.02
	if cone_mat != null:
		cone_mat.set_shader_parameter("strength", practical)
	if rim != null:
		rim.light_energy = lerpf(5.0, 0.8, d)
		rim.light_color = Color(0.62, 0.74, 1.0).lerp(Color(1.0, 0.9, 0.8), d)
		fill.light_energy = lerpf(1.6, 0.3, d)
		fill.light_color = Color(0.9, 0.85, 0.8)
	rain.set_light(d)


## Distant lightning in a night storm: a brief double flash on the moonlight.
func _update_lightning(night: float) -> void:
	var dt := get_process_delta_time()
	_flash = maxf(_flash - dt * 6.0, 0.0)
	if _flash2_t > 0.0:
		_flash2_t -= dt
		if _flash2_t <= 0.0:
			_flash = 0.7
	if not rain.enabled or night < 0.8:
		return
	_lightning_t -= dt
	if _lightning_t <= 0.0:
		_lightning_t = randf_range(14.0, 34.0)
		_flash = 1.0
		_flash2_t = 0.18


## Sky colour changes trigger a radiance update, so only push noticeable changes.
func _set_sky(top: Color, hor: Color) -> void:
	_sky_t -= get_process_delta_time()
	var ground := hor.darkened(0.6)
	var cols: Array[Color] = [top, hor, ground]
	if not _sky_colors.is_empty() and _sky_t > 0.0:
		return
	if not _sky_colors.is_empty():
		var diff := 0.0
		for i in 3:
			var a: Color = _sky_colors[i]
			diff = maxf(diff, absf(a.r - cols[i].r) + absf(a.g - cols[i].g) + absf(a.b - cols[i].b))
		if diff < 0.01:
			return
	_sky_t = 0.25 if cinematic else 1.0
	_sky_colors = cols
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = ground
	sky_mat.sky_energy_multiplier = 1.0
