extends Node
## Player settings (autoload "Settings"): loads and saves user://settings.cfg and applies
## everything live. Values live in static vars so scripts can read them through
## `preload("res://scripts/settings.gd")` even when the autoload isn't running
## (e.g. the headless smoke test), and get the defaults.

signal changed

const PATH := "user://settings.cfg"
const WINDOW_MODES := ["Windowed", "Fullscreen", "Borderless"]
const QUALITY := ["Low", "Medium", "High"]
const BUSES := ["Master", "Music", "SFX", "Voice"]

# base look speeds (sensitivity 1.0 = the game's original tuning)
const MOUSE_BASE := 0.0025 # radians per pixel
const PAD_YAW_BASE := 3.0 # radians per second at full stick
const PAD_PITCH_BASE := 2.0

static var brightness := 1.0 # exposure multiplier, 0.5..1.6
static var window_mode := 0 # index into WINDOW_MODES
static var resolution_scale := 1.0 # 3D render scale, 0.5..1.0
static var vsync := true
static var quality := 2 # 0 Low, 1 Medium, 2 High
static var rain := true
static var mouse_sensitivity := 1.0 # 0.2..3.0
static var pad_sensitivity := 1.0 # 0.2..3.0
static var invert_y := false
static var volume := {"Master": 0.9, "Music": 0.7, "SFX": 0.8, "Voice": 0.9} # linear 0..1
static var subtitles := true # AUDIO: dialogue subtitles

const KEYS := ["brightness", "window_mode", "resolution_scale", "vsync", "quality", "rain",
	"mouse_sensitivity", "pad_sensitivity", "invert_y"]


# ---------------------------------------------------------------- readers for gameplay code
static func mouse_look() -> float:
	return MOUSE_BASE * mouse_sensitivity


static func pad_yaw() -> float:
	return PAD_YAW_BASE * pad_sensitivity


static func pad_pitch() -> float:
	return PAD_PITCH_BASE * pad_sensitivity


## -1 when the vertical look axis is inverted.
static func y_sign() -> float:
	return -1.0 if invert_y else 1.0


static func quality_name() -> String:
	return QUALITY[clampi(quality, 0, QUALITY.size() - 1)]


static func window_modes_available() -> Array:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return [0, 1] # browsers only do windowed / fullscreen
	return [0, 1, 2]


# ---------------------------------------------------------------- lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	load_settings()
	apply_all()
	# re-apply the brightness/quality/rain to every scene we change to
	get_tree().node_added.connect(_on_node_added)
	get_tree().root.size_changed.connect(apply_ui_scale)
	apply_ui_scale()


## Phones: the 1280x720 layout squeezed onto a ~400 CSS-pixel-tall screen leaves 6-8 px text.
## Enlarge the whole UI on small touch screens so the logical canvas is about 1.3 logical px
## per CSS px tall (never below 960x540 logical, so every panel still fits). Desktop: 1.0.
func apply_ui_scale() -> void:
	var win := get_tree().root
	if DisplayServer.get_name() == "headless":
		return
	var px := Vector2(win.size)
	if px.x <= 0.0 or px.y <= 0.0:
		return
	var f := 1.0
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		var dpr := maxf(DisplayServer.screen_get_scale(), 1.0)
		var css_h := px.y / dpr
		var want_h := clampf(css_h * 1.3, 540.0, 720.0) # logical canvas height we aim for
		var base := minf(px.x / 1280.0, px.y / 720.0)
		f = 720.0 / want_h
		f = minf(f, minf(px.x / (960.0 * base), px.y / (540.0 * base))) # keep >= 960x540 logical
		f = maxf(f, 1.0)
	if not is_equal_approx(win.content_scale_factor, f):
		win.content_scale_factor = f


func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment:
		_apply_env.call_deferred(n)


static func ensure_buses() -> void:
	for b in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


static func load_settings(path: String = PATH) -> bool:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return false
	brightness = clampf(float(cf.get_value("video", "brightness", brightness)), 0.5, 1.6)
	window_mode = clampi(int(cf.get_value("video", "window_mode", window_mode)), 0, WINDOW_MODES.size() - 1)
	resolution_scale = clampf(float(cf.get_value("video", "resolution_scale", resolution_scale)), 0.5, 1.0)
	vsync = bool(cf.get_value("video", "vsync", vsync))
	quality = clampi(int(cf.get_value("video", "quality", quality)), 0, QUALITY.size() - 1)
	rain = bool(cf.get_value("video", "rain", rain))
	mouse_sensitivity = clampf(float(cf.get_value("controls", "mouse_sensitivity", mouse_sensitivity)), 0.2, 3.0)
	pad_sensitivity = clampf(float(cf.get_value("controls", "pad_sensitivity", pad_sensitivity)), 0.2, 3.0)
	invert_y = bool(cf.get_value("controls", "invert_y", invert_y))
	for b in BUSES:
		volume[b] = clampf(float(cf.get_value("audio", b, volume[b])), 0.0, 1.0)
	subtitles = bool(cf.get_value("audio", "subtitles", subtitles))
	return true


static func save_settings(path: String = PATH) -> bool:
	var cf := ConfigFile.new()
	cf.set_value("video", "brightness", brightness)
	cf.set_value("video", "window_mode", window_mode)
	cf.set_value("video", "resolution_scale", resolution_scale)
	cf.set_value("video", "vsync", vsync)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "rain", rain)
	cf.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("controls", "pad_sensitivity", pad_sensitivity)
	cf.set_value("controls", "invert_y", invert_y)
	for b in BUSES:
		cf.set_value("audio", b, volume[b])
	cf.set_value("audio", "subtitles", subtitles)
	return cf.save(path) == OK


## Set one value by name (used by the options panel), apply it and save.
func set_value(key: String, value) -> void:
	if key in BUSES:
		volume[key] = float(value)
	else:
		match key:
			"brightness": brightness = float(value)
			"window_mode": window_mode = int(value)
			"resolution_scale": resolution_scale = float(value)
			"vsync": vsync = bool(value)
			"quality": quality = int(value)
			"rain": rain = bool(value)
			"mouse_sensitivity": mouse_sensitivity = float(value)
			"pad_sensitivity": pad_sensitivity = float(value)
			"invert_y": invert_y = bool(value)
			"subtitles": subtitles = bool(value)
	apply_all()
	if key == "rain":
		_apply_rain()
	save_settings()
	changed.emit()


func get_value(key: String):
	if key in BUSES:
		return volume[key]
	match key:
		"brightness": return brightness
		"window_mode": return window_mode
		"resolution_scale": return resolution_scale
		"vsync": return vsync
		"quality": return quality
		"rain": return rain
		"mouse_sensitivity": return mouse_sensitivity
		"pad_sensitivity": return pad_sensitivity
		"invert_y": return invert_y
		"subtitles": return subtitles
	return null


# ---------------------------------------------------------------- apply
func apply_all() -> void:
	_apply_audio()
	_apply_display()
	for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_apply_env(we)


func _apply_audio() -> void:
	ensure_buses()
	for b in BUSES:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			var v: float = volume[b]
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(i, v <= 0.001)


func _apply_display() -> void:
	var vp := get_viewport()
	vp.scaling_3d_scale = resolution_scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	if DisplayServer.get_name() == "headless":
		return
	if not OS.has_feature("web"): # browsers own the frame pacing; the call only logs an error there
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var want := window_mode if window_mode in window_modes_available() else 0
	var mode := DisplayServer.WINDOW_MODE_WINDOWED
	match want:
		1: mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if not OS.has_feature("web") else DisplayServer.WINDOW_MODE_FULLSCREEN
		2: mode = DisplayServer.WINDOW_MODE_FULLSCREEN # borderless fullscreen window
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


## Quality preset: Low switches off the expensive screen-space passes; Medium keeps SSR off
## and fog lighter; High is whatever the scene set up. The brightness hook lives in the
## scene's own exposure code (atmosphere.gd / lair_set.gd multiply Settings.brightness in).
func _apply_env(we: WorldEnvironment) -> void:
	if not is_instance_valid(we) or we.environment == null:
		return
	var env := we.environment
	if not env.has_meta("q_base"):
		env.set_meta("q_base", [env.ssr_enabled, env.ssao_enabled, env.ssil_enabled, env.volumetric_fog_enabled, env.glow_enabled])
	var base: Array = env.get_meta("q_base")
	env.ssr_enabled = base[0] and quality >= 2
	env.ssao_enabled = base[1] and quality >= 1
	env.ssil_enabled = base[2] and quality >= 2
	env.volumetric_fog_enabled = base[3] and quality >= 1
	env.glow_enabled = base[4]


func _apply_rain() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var atmo := scene.get_node_or_null("Atmosphere")
	if atmo != null and atmo.has_method("set_rain") and atmo.rain != null and atmo.rain.enabled != rain:
		atmo.set_rain(rain)
