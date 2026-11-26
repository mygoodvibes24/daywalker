extends Node
## Player settings (autoload "Settings"): loads and saves user://settings.cfg and applies
## everything live. Values live in static vars so scripts can read them through
## `preload("res://scripts/settings.gd")` even when the autoload isn't running
## (e.g. the headless smoke test), and get the defaults.
##
## PERF / SETTINGS API (for the world builders and everyone else):
##   Settings.tier               the active graphics preset: 0 Very Low, 1 Low, 2 Medium, 3 High, 4 Custom
##   Settings.view_distance      0.4..1.0 multiplier on every visibility range (LOD bias) and the camera far
##   Settings.foliage_density    0..1 share of undergrowth instances drawn
##   Settings.tree_density       0.3..1 share of trees drawn
##   Settings.shadow_quality     0 off, 1 low, 2 high
##   Settings.vfx_amount         0.2..1 particles / debris multiplier (Settings.vfx_count(n))
##   Settings.crowd_density      0.6..1 multiplier on the live enemy cap (Settings.max_enemies(n))
##   Settings.coat_quality       0 static, 1 cheap, 2 full spring coat
##   Settings.light_quality      0 few lamps (short fade, no omni shadows), 1 medium, 2 all
##   Settings.cue(name)          colour-blind-safe colour for "danger" / "safe" / "warn" / "parry" cues
##   Settings.shake_scale()      0..1 camera shake multiplier (camera shake + reduced motion)
##   Settings.flash_scale()      0..1 multiplier for flashes (lightning, hit flash, vignette)
## Signals: `changed` (any value), `graphics_changed` (a graphics value: re-read densities / ranges).
## Applied generically here (no builder edits needed): visibility ranges of every GeometryInstance3D
## (scaled by view_distance), MultiMesh visible_instance_count for foliage / trees (by node name),
## light shadows and light distance fade, the Environment, the viewport scale / AA, Engine.max_fps.

signal changed
signal graphics_changed

const PATH := "user://settings.cfg"
const WINDOW_MODES := ["Windowed", "Fullscreen", "Borderless"]
const PRESETS := ["Very Low", "Low", "Medium", "High", "Custom"]
const QUALITY := ["Low", "Medium", "High"] # legacy: the Environment quality derived from the preset
const BUSES := ["Master", "Music", "SFX", "Voice"]
const SHADOWS := ["Off", "Low", "High"]
const FOG := ["Simple", "Medium", "Full"]
const AA := ["Off", "FXAA", "MSAA 2x", "MSAA 4x"]
const FPS_CAPS := ["30", "60", "Unlimited"]
const COAT := ["Static", "Low", "Full"]
const LIGHTS := ["Few", "Some", "All"]
const COLORBLIND := ["Off", "Deuteranopia", "Protanopia", "Tritanopia"]
const SUB_SIZES := ["Small", "Medium", "Large", "Huge"]

# base look speeds (sensitivity 1.0 = the game's original tuning)
const MOUSE_BASE := 0.0025 # radians per pixel
const PAD_YAW_BASE := 3.0 # radians per second at full stick
const PAD_PITCH_BASE := 2.0

# ---------------------------------------------------------------- display
static var brightness := 1.0 # exposure multiplier, 0.5..1.6
static var window_mode := 0 # index into WINDOW_MODES
static var vsync := true
static var fov := 70.0 # base camera field of view
static var ui_scale := 1.0 # 0.8..1.5 on top of the automatic phone scale
static var hud_opacity := 1.0 # 0.3..1
static var show_fps := false
# ---------------------------------------------------------------- graphics (the preset sets these)
static var tier := 3 # index into PRESETS (4 = Custom)
static var quality := 2 # legacy 0 Low, 1 Medium, 2 High (derived from the tier)
static var resolution_scale := 1.0 # 3D render scale, 0.5..1.0
static var dynamic_res := false
static var shadow_quality := 2
static var shadow_distance := 70.0 # m
static var view_distance := 1.0 # LOD bias: x every visibility range, x the camera far
static var foliage_density := 1.0
static var tree_density := 1.0
static var crowd_density := 1.0
static var fog_quality := 2
static var post_fx := true
static var ssao := true # desktop (Forward+) only: SSAO / SSR / SSIL
static var rain := true
static var aa := 2
static var coat_quality := 2
static var vfx_amount := 1.0
static var light_quality := 2
static var fps_cap := 2 # index into FPS_CAPS
# ---------------------------------------------------------------- preferences
static var mouse_sensitivity := 1.0 # 0.2..3.0
static var pad_sensitivity := 1.0 # 0.2..3.0
static var touch_sensitivity := 1.0 # 0.2..3.0
static var invert_y := false
static var camera_shake := 1.0 # 0..1
static var aim_assist := true # soft-lock onto the nearest enemy when striking
static var hints := true
static var touch_size := 1.0 # 0.7..1.4
static var touch_opacity := 0.85 # 0.2..1
# ---------------------------------------------------------------- audio
static var volume := {"Master": 0.9, "Music": 0.7, "SFX": 0.8, "Voice": 0.9} # linear 0..1
static var subtitles := true # AUDIO: dialogue subtitles
static var mute_unfocused := true
# ---------------------------------------------------------------- accessibility
static var subtitle_size := 1 # index into SUB_SIZES
static var subtitle_bg := true
static var colorblind := 0 # index into COLORBLIND
static var reduce_flashing := false
static var reduce_motion := false
static var toggle_sprint := false
static var high_contrast := false
static var large_text := false
# ---------------------------------------------------------------- state
static var first_run := true # no settings file yet: auto-detect the tier
static var probed := false # the first-run frame-time probe has run
static var dyn_scale := 1.0 # the dynamic resolution scaler's current factor (x resolution_scale)
static var uncapped := false # the benchmark measures raw frame cost: no FPS cap

## Every saved value: key -> [config section, type, min, max]. ("b" bool, "i" int, "f" float)
const SPEC := {
	"brightness": ["video", "f", 0.5, 1.6], "window_mode": ["video", "i", 0, 2], "vsync": ["video", "b"],
	"fov": ["video", "f", 55.0, 100.0], "ui_scale": ["video", "f", 0.8, 1.5], "hud_opacity": ["video", "f", 0.3, 1.0],
	"show_fps": ["video", "b"],
	"tier": ["graphics", "i", 0, 4], "quality": ["video", "i", 0, 2], "resolution_scale": ["video", "f", 0.5, 1.0],
	"dynamic_res": ["graphics", "b"], "shadow_quality": ["graphics", "i", 0, 2], "shadow_distance": ["graphics", "f", 20.0, 120.0],
	"view_distance": ["graphics", "f", 0.4, 1.0], "foliage_density": ["graphics", "f", 0.0, 1.0], "tree_density": ["graphics", "f", 0.3, 1.0],
	"crowd_density": ["graphics", "f", 0.6, 1.0], "fog_quality": ["graphics", "i", 0, 2], "post_fx": ["graphics", "b"],
	"ssao": ["graphics", "b"], "rain": ["video", "b"], "aa": ["graphics", "i", 0, 3], "coat_quality": ["graphics", "i", 0, 2],
	"vfx_amount": ["graphics", "f", 0.2, 1.0], "light_quality": ["graphics", "i", 0, 2], "fps_cap": ["graphics", "i", 0, 2],
	"mouse_sensitivity": ["controls", "f", 0.2, 3.0], "pad_sensitivity": ["controls", "f", 0.2, 3.0],
	"touch_sensitivity": ["controls", "f", 0.2, 3.0], "invert_y": ["controls", "b"], "camera_shake": ["controls", "f", 0.0, 1.0],
	"aim_assist": ["controls", "b"], "hints": ["controls", "b"], "touch_size": ["controls", "f", 0.7, 1.4],
	"touch_opacity": ["controls", "f", 0.2, 1.0],
	"subtitles": ["audio", "b"], "mute_unfocused": ["audio", "b"],
	"subtitle_size": ["access", "i", 0, 3], "subtitle_bg": ["access", "b"], "colorblind": ["access", "i", 0, 3],
	"reduce_flashing": ["access", "b"], "reduce_motion": ["access", "b"], "toggle_sprint": ["access", "b"],
	"high_contrast": ["access", "b"], "large_text": ["access", "b"],
	"probed": ["graphics", "b"],
}

## The values each preset sets (Custom keeps whatever is there).
const PRESET_VALUES := [
	{ # Very Low: the weakest phone GPU
		"resolution_scale": 0.55, "dynamic_res": true, "shadow_quality": 0, "shadow_distance": 25.0, "view_distance": 0.55,
		"foliage_density": 0.1, "tree_density": 0.5, "crowd_density": 0.7, "fog_quality": 0, "post_fx": false, "ssao": false,
		"rain": false, "aa": 0, "coat_quality": 0, "vfx_amount": 0.35, "light_quality": 0, "fps_cap": 0, "quality": 0},
	{ # Low: phones
		"resolution_scale": 0.7, "dynamic_res": true, "shadow_quality": 0, "shadow_distance": 35.0, "view_distance": 0.7,
		"foliage_density": 0.35, "tree_density": 0.75, "crowd_density": 0.85, "fog_quality": 0, "post_fx": false, "ssao": false,
		"rain": true, "aa": 0, "coat_quality": 1, "vfx_amount": 0.6, "light_quality": 1, "fps_cap": 1, "quality": 0},
	{ # Medium: laptops, web desktop
		"resolution_scale": 0.85, "dynamic_res": true, "shadow_quality": 1, "shadow_distance": 50.0, "view_distance": 0.9,
		"foliage_density": 0.7, "tree_density": 1.0, "crowd_density": 1.0, "fog_quality": 1, "post_fx": true, "ssao": false,
		"rain": true, "aa": 1, "coat_quality": 2, "vfx_amount": 0.85, "light_quality": 2, "fps_cap": 1, "quality": 1},
	{ # High: native desktop
		"resolution_scale": 1.0, "dynamic_res": false, "shadow_quality": 2, "shadow_distance": 70.0, "view_distance": 1.0,
		"foliage_density": 1.0, "tree_density": 1.0, "crowd_density": 1.0, "fog_quality": 2, "post_fx": true, "ssao": true,
		"rain": true, "aa": 2, "coat_quality": 2, "vfx_amount": 1.0, "light_quality": 2, "fps_cap": 2, "quality": 2},
]
const GRAPHICS_KEYS := ["resolution_scale", "dynamic_res", "shadow_quality", "shadow_distance", "view_distance",
	"foliage_density", "tree_density", "crowd_density", "fog_quality", "post_fx", "ssao", "rain", "aa", "coat_quality",
	"vfx_amount", "light_quality", "fps_cap"]

# foliage / tree MultiMeshes by node-name prefix (map/wilds.gd scatter_mm names)
const FOLIAGE_PREFIX := ["PineBush", "BayouBush", "Grass", "Fern", "Reeds", "Weeds", "Undergrowth"]
const TREE_PREFIX := ["Pines", "PineShadows", "PineCards", "Cypress", "CypressShadows", "CypressCards"]

static var defaults := {}


static func _me() -> GDScript:
	return load("res://scripts/settings.gd")


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


static func tier_name() -> String:
	return PRESETS[clampi(tier, 0, PRESETS.size() - 1)]


static func window_modes_available() -> Array:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return [0, 1] # browsers only do windowed / fullscreen
	return [0, 1, 2]


static func cinematic() -> bool:
	# Forward+ / Mobile have a RenderingDevice; Compatibility (GL) has none (whatever the project
	# setting says: --rendering-method overrides it)
	return RenderingServer.get_rendering_device() != null and not OS.has_feature("web") and DisplayServer.get_name() != "headless"


## Camera shake multiplier (Preferences slider; Reduced motion turns it off).
static func shake_scale() -> float:
	return 0.0 if reduce_motion else camera_shake


## Flash multiplier for lightning, hit flashes and the blood vignette (Reduced flashing).
static func flash_scale() -> float:
	return 0.25 if reduce_flashing else 1.0


static func vfx_count(n: int) -> int:
	return maxi(1, roundi(n * vfx_amount))


static func max_enemies(n: int) -> int:
	return maxi(4, roundi(n * crowd_density))


## Colour cues safe for colour-blind players. The game's red = danger / green = safe pair becomes
## orange / blue for red-green deficiencies and red / teal for tritanopia.
static func cue(name: String) -> Color:
	var pal := {
		"danger": Color(0.95, 0.06, 0.05), "safe": Color(0.2, 0.85, 0.3), "warn": Color(1.0, 0.55, 0.05), "parry": Color(1.0, 0.82, 0.25)}
	match colorblind:
		1, 2:
			pal = {"danger": Color(1.0, 0.45, 0.0), "safe": Color(0.2, 0.55, 1.0), "warn": Color(1.0, 0.85, 0.1), "parry": Color(0.95, 0.95, 0.95)}
		3:
			pal = {"danger": Color(0.95, 0.1, 0.2), "safe": Color(0.1, 0.8, 0.8), "warn": Color(1.0, 0.4, 0.6), "parry": Color(0.95, 0.95, 0.95)}
	return pal.get(name, Color.WHITE)


## Remap a hard-coded telegraph / HUD colour through the colour-blind palette: strong reds read as
## "danger", strong greens as "safe", oranges as "warn". Other colours pass through.
static func cb(c: Color) -> Color:
	if colorblind == 0:
		return c
	var a := c.a
	var out := c
	if c.r > 0.6 and c.g < 0.2 and c.b < 0.3:
		out = cue("danger")
	elif c.g > 0.5 and c.r < 0.4:
		out = cue("safe")
	elif c.r > 0.8 and c.g >= 0.2 and c.g < 0.6 and c.b < 0.2:
		out = cue("warn")
	out.a = a
	return out


static func sub_font_size() -> int:
	return [16, 20, 26, 34][clampi(subtitle_size, 0, 3)]


static func sprint_held(pressed_now: bool) -> bool:
	if not toggle_sprint:
		return pressed_now
	if Input.is_action_just_pressed("sprint"):
		_sprint_latch = not _sprint_latch
	return _sprint_latch
static var _sprint_latch := false


# ---------------------------------------------------------------- tiers
## The starting tier for a first run: phones (web + touch) Low, web desktop Medium, native High.
static func detect_tier() -> int:
	if OS.has_feature("mobile"):
		return 1
	if OS.has_feature("web"):
		var touch := DisplayServer.is_touchscreen_available()
		if OS.has_feature("web_android") or OS.has_feature("web_ios"):
			touch = true
		return 1 if touch else 2
	return 3


## Set every graphics value from a preset (0..3). 4 (Custom) keeps the values.
static func set_tier_values(t: int) -> void:
	tier = clampi(t, 0, PRESETS.size() - 1)
	if tier >= PRESET_VALUES.size():
		return
	var me := _me()
	var vals: Dictionary = PRESET_VALUES[tier]
	for k in vals:
		me.set(k, vals[k])


## True if the current graphics values match the preset exactly.
static func matches_tier(t: int) -> bool:
	if t < 0 or t >= PRESET_VALUES.size():
		return false
	var me := _me()
	var vals: Dictionary = PRESET_VALUES[t]
	for k in vals:
		if k == "quality":
			continue
		var a = me.get(k)
		var b = vals[k]
		if (a is float or b is float):
			if not is_equal_approx(float(a), float(b)):
				return false
		elif a != b:
			return false
	return true


func apply_tier_name(n: String, save := true) -> void:
	var i := ["verylow", "low", "medium", "high"].find(n.to_lower().replace(" ", "").replace("_", ""))
	if i >= 0:
		set_tier_values(i)
		dyn_scale = 1.0
		if not is_inside_tree():
			return # applied when the autoload enters the tree (_ready)
		apply_all()
		apply_graphics()
		if save:
			save_settings()
		changed.emit()
		graphics_changed.emit()


# ---------------------------------------------------------------- lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if defaults.is_empty():
		defaults = snapshot()
	ensure_buses()
	if not load_settings():
		first_run = true
		set_tier_values(detect_tier())
	var url_tier := _url_value("tier")
	if url_tier != "":
		apply_tier_name(url_tier, false)
	_apply_engine_limits()
	apply_all()
	# re-apply the brightness/quality/rain to every scene we change to
	get_tree().node_added.connect(_on_node_added)
	get_tree().root.size_changed.connect(apply_ui_scale)
	get_tree().root.focus_exited.connect(_on_focus.bind(false))
	get_tree().root.focus_entered.connect(_on_focus.bind(true))
	apply_ui_scale()
	_build_fps_label()


static func _url_value(name: String) -> String:
	if not OS.has_feature("web"):
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--" + name + "="):
				return a.substr(name.length() + 3)
		return ""
	var q := str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
	for part in q.split("&", false):
		var kv := part.split("=")
		if kv[0] == name and kv.size() > 1:
			return kv[1]
	return ""


## The web is single-threaded: logic, physics and drawing share one thread, so a slow frame makes
## the physics catch up with several steps next frame, which makes the frame slower still. Cap the
## catch-up at 3 steps there (the game slows down a touch on a very slow frame instead of stuttering).
func _apply_engine_limits() -> void:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		Engine.max_physics_steps_per_frame = 3
	else:
		Engine.max_physics_steps_per_frame = 6


## Phones: the 1280x720 layout squeezed onto a ~400 CSS-pixel-tall screen leaves 6-8 px text.
## Enlarge the whole UI on small touch screens so the logical canvas is about 1.3 logical px
## per CSS px tall (never below 960x540 logical, so every panel still fits). Desktop: 1.0.
## Then the player's UI scale (and Larger text) on top, kept so the canvas stays >= 800x450.
func apply_ui_scale() -> void:
	var win := get_tree().root
	if DisplayServer.get_name() == "headless":
		return
	var px := Vector2(win.size)
	if px.x <= 0.0 or px.y <= 0.0:
		return
	var f := 1.0
	var base := minf(px.x / 1280.0, px.y / 720.0)
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		var dpr := maxf(DisplayServer.screen_get_scale(), 1.0)
		var css_h := px.y / dpr
		var want_h := clampf(css_h * 1.3, 540.0, 720.0) # logical canvas height we aim for
		f = 720.0 / want_h
		f = minf(f, minf(px.x / (960.0 * base), px.y / (540.0 * base))) # keep >= 960x540 logical
		f = maxf(f, 1.0)
	f *= ui_scale * (1.15 if large_text else 1.0)
	f = minf(f, minf(px.x / (800.0 * base), px.y / (450.0 * base)))
	f = maxf(f, 0.6)
	if not is_equal_approx(win.content_scale_factor, f):
		win.content_scale_factor = f


func _on_focus(focused: bool) -> void:
	var i := AudioServer.get_bus_index("Master")
	if i < 0:
		return
	if not focused and mute_unfocused:
		AudioServer.set_bus_mute(i, true)
	else:
		AudioServer.set_bus_mute(i, float(volume["Master"]) <= 0.001)


## The running game / menu scene: current_scene, or (tests, the bench) the scene root that holds
## the last WorldEnvironment that came in.
var _world_root: Node


func world() -> Node:
	var cs := get_tree().current_scene
	if cs != null:
		return cs
	if is_instance_valid(_world_root) and _world_root.is_inside_tree():
		return _world_root
	var root := get_tree().root
	for i in range(root.get_child_count() - 1, -1, -1):
		var c := root.get_child(i)
		if not ProjectSettings.has_setting("autoload/" + c.name) and c.name != "Bench":
			return c
	return null


func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment:
		var r: Node = n
		while r.get_parent() != null and r.get_parent() != get_tree().root:
			r = r.get_parent()
		_world_root = r
		_apply_env.call_deferred(n)
		apply_graphics.call_deferred()
	elif n is GeometryInstance3D:
		if _scene_ready:
			_geo_new.append(n)
	elif n is Light3D:
		if _scene_ready:
			_apply_light.call_deferred(n)
	elif n is Camera3D:
		_apply_camera.call_deferred(n)
	elif n is CanvasLayer:
		_maybe_hud.call_deferred(n)


## The buses normally come from res://default_bus_layout.tres (project setting
## audio/buses/default_bus_layout). This is only a fallback if that layout is missing.
## Never call add_bus() here: in Godot 4.3 web builds (Sample playback) add_bus()
## tells the browser side to insert at position -1, which lands the new bus *before* the
## last one, so the Web Audio bus indices stop matching the engine's. The sends set next
## then wire Master into a child bus and back, and Web Audio silences that cycle: every
## sound plays at zero gain (the "no sound at all on the web" bug). set_bus_layout() rebuilds
## the browser buses in order, so build a whole layout and apply that instead.
static func ensure_buses() -> void:
	var missing := []
	for b in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(b) < 0:
			missing.append(b)
	if missing.is_empty():
		return
	var layout := AudioServer.generate_bus_layout()
	var n := AudioServer.bus_count
	for b in missing:
		layout.set("bus/%d/name" % n, StringName(b))
		layout.set("bus/%d/send" % n, &"Master")
		layout.set("bus/%d/volume_db" % n, 0.0)
		n += 1
	AudioServer.set_bus_layout(layout)


static func snapshot() -> Dictionary:
	var me := _me()
	var d := {}
	for k in SPEC:
		d[k] = me.get(k)
	d["volume"] = volume.duplicate()
	return d


static func restore(d: Dictionary) -> void:
	var me := _me()
	for k in d:
		if k == "volume":
			volume = (d[k] as Dictionary).duplicate()
		elif SPEC.has(k):
			me.set(k, d[k])


static func load_settings(path: String = PATH) -> bool:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return false
	var me := _me()
	var had_tier := cf.has_section_key("graphics", "tier")
	for k in SPEC:
		var sp: Array = SPEC[k]
		var cur = me.get(k)
		var v = cf.get_value(sp[0], k, cur)
		match sp[1]:
			"b": me.set(k, bool(v))
			"i": me.set(k, clampi(int(v), int(sp[2]), int(sp[3])))
			"f": me.set(k, clampf(float(v), float(sp[2]), float(sp[3])))
	if not had_tier:
		# an older settings file (Low / Medium / High quality only): map it onto the presets
		tier = [1, 2, 3][clampi(quality, 0, 2)]
		var keep_rs := resolution_scale
		var keep_rain := rain
		set_tier_values(tier)
		resolution_scale = keep_rs
		rain = keep_rain
		if not matches_tier(tier):
			tier = 4
	for b in BUSES:
		volume[b] = clampf(float(cf.get_value("audio", b, volume[b])), 0.0, 1.0)
	first_run = false
	return true


static func save_settings(path: String = PATH) -> bool:
	var cf := ConfigFile.new()
	var me := _me()
	for k in SPEC:
		cf.set_value(SPEC[k][0], k, me.get(k))
	for b in BUSES:
		cf.set_value("audio", b, volume[b])
	return cf.save(path) == OK


## Set one value by name (used by the options panel), apply it and save.
func set_value(key: String, value) -> void:
	if key in BUSES:
		volume[key] = float(value)
	elif key == "tier":
		var t := int(value)
		if t < PRESET_VALUES.size():
			set_tier_values(t)
			dyn_scale = 1.0
		else:
			tier = PRESETS.size() - 1
	elif SPEC.has(key):
		var sp: Array = SPEC[key]
		match sp[1]:
			"b": _me().set(key, bool(value))
			"i": _me().set(key, clampi(int(value), int(sp[2]), int(sp[3])))
			"f": _me().set(key, clampf(float(value), float(sp[2]), float(sp[3])))
		if key in GRAPHICS_KEYS:
			# a hand-picked graphics value makes it Custom (unless it lands on a preset again)
			tier = PRESETS.size() - 1
			for t in PRESET_VALUES.size():
				if matches_tier(t):
					tier = t
			if key == "resolution_scale":
				dyn_scale = 1.0
	else:
		return
	apply_all()
	if key == "tier" or key in GRAPHICS_KEYS:
		apply_graphics()
		graphics_changed.emit()
	if key in ["ui_scale", "large_text"]:
		apply_ui_scale()
	save_settings()
	changed.emit()


func get_value(key: String):
	if key in BUSES:
		return volume[key]
	if SPEC.has(key):
		return _me().get(key)
	return null


## Back to the defaults (all of them, or one section: "graphics", "video", "controls", "audio", "access").
func reset_defaults(section := "") -> void:
	var me := _me()
	for k in SPEC:
		if section == "" or SPEC[k][0] == section or (section == "graphics" and k in GRAPHICS_KEYS):
			me.set(k, defaults[k])
	if section == "" or section == "audio":
		volume = (defaults["volume"] as Dictionary).duplicate()
	if section == "" or section == "graphics":
		set_tier_values(detect_tier())
		dyn_scale = 1.0
	apply_all()
	apply_graphics()
	apply_ui_scale()
	save_settings()
	changed.emit()
	graphics_changed.emit()


# ---------------------------------------------------------------- apply
func apply_all() -> void:
	_apply_audio()
	_apply_display()
	for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_apply_env(we)
	if _fps_label != null:
		_fps_label.visible = show_fps
	_apply_hud()


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
	vp.scaling_3d_scale = clampf(resolution_scale * dyn_scale, 0.4, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	Engine.max_fps = 0 if uncapped else [30, 60, 0][clampi(fps_cap, 0, 2)]
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


## The Environment: screen-space passes (desktop) by SSAO, volumetric fog by Fog quality, glow by
## Post FX. The brightness hook lives in the scene's own exposure code (atmosphere.gd / lair_set.gd
## multiply Settings.brightness in).
func _apply_env(we: WorldEnvironment) -> void:
	if not is_instance_valid(we) or we.environment == null:
		return
	var env := we.environment
	if not env.has_meta("q_base"):
		env.set_meta("q_base", [env.ssr_enabled, env.ssao_enabled, env.ssil_enabled, env.volumetric_fog_enabled, env.glow_enabled, env.fog_height_density])
	var base: Array = env.get_meta("q_base")
	env.ssr_enabled = base[0] and ssao and fog_quality >= 1
	env.ssao_enabled = base[1] and ssao
	env.ssil_enabled = base[2] and ssao and tier >= 3
	env.volumetric_fog_enabled = base[3] and fog_quality >= 2
	env.glow_enabled = base[4] and post_fx


var _scene_ready := false
var _geo_new: Array = []


## Graphics values that live in the scene: lights and shadows, visibility ranges (LOD bias),
## foliage / tree density, post FX layers, AA, the camera far. Cheap enough to call on every change.
func apply_graphics() -> void:
	var scene := world()
	_apply_viewport_aa()
	_apply_shadow_atlas()
	if scene == null:
		return
	_scene_ready = true
	for n in scene.find_children("*", "Light3D", true, false):
		_apply_light(n)
	for n in scene.find_children("*", "GeometryInstance3D", true, false):
		_apply_geo(n)
	for n in scene.find_children("*", "Camera3D", true, false):
		_apply_camera(n)
	var atmo := scene.get_node_or_null("Atmosphere")
	if atmo != null:
		var post = atmo.get("post")
		if post is CanvasLayer:
			post.visible = post_fx
		if atmo.get("rain") != null and atmo.rain != null and atmo.rain.enabled != rain and atmo.has_method("set_rain"):
			atmo.set_rain(rain)
		var cones = atmo.get("lamp_cones")
		if cones is Array:
			for c in cones:
				if is_instance_valid(c):
					c.set_meta("q_off", fog_quality == 0)
					if fog_quality == 0:
						c.visible = false


func _process(_delta: float) -> void:
	if not _geo_new.is_empty():
		for n in _geo_new:
			if is_instance_valid(n):
				_apply_geo(n)
		_geo_new.clear()
	_tick_dynamic_res()
	if _fps_label != null and show_fps:
		_fps_t -= _delta
		if _fps_t <= 0.0:
			_fps_t = 0.5
			_fps_label.text = "%d FPS  %.1f ms  x%.2f" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), get_viewport().scaling_3d_scale]


func _apply_viewport_aa() -> void:
	var vp := get_viewport()
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	var msaa := Viewport.MSAA_DISABLED
	if aa == 2:
		msaa = Viewport.MSAA_2X
	elif aa == 3:
		msaa = Viewport.MSAA_4X
	if cinematic() and aa >= 2:
		msaa = Viewport.MSAA_DISABLED # Forward+ uses TAA at these levels (atmosphere.gd)
		vp.use_taa = true
	elif cinematic():
		vp.use_taa = false
	vp.msaa_3d = msaa


func _apply_shadow_atlas() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var sz := 1024 if shadow_quality <= 1 else (4096 if cinematic() else 2048)
	RenderingServer.directional_shadow_atlas_set_size(sz, true)
	get_viewport().positional_shadow_atlas_size = 0 if shadow_quality < 2 else (4096 if cinematic() else 2048)


func _apply_light(l) -> void:
	if not is_instance_valid(l) or not (l is Light3D):
		return
	if not l.has_meta("q_base"):
		l.set_meta("q_base", [l.shadow_enabled, l.distance_fade_enabled, l.distance_fade_begin, l.distance_fade_length])
	var b: Array = l.get_meta("q_base")
	if l is DirectionalLight3D:
		var d := l as DirectionalLight3D
		d.shadow_enabled = b[0] and shadow_quality > 0
		if not d.has_meta("q_dist"):
			d.set_meta("q_dist", [d.directional_shadow_max_distance, d.directional_shadow_mode])
		var qd: Array = d.get_meta("q_dist")
		d.directional_shadow_max_distance = shadow_distance
		d.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if shadow_quality == 1 else qd[1]
		return
	# omni / spot: shadows only on High; fewer lights fade out sooner
	l.shadow_enabled = b[0] and shadow_quality >= 2
	if light_quality >= 2:
		l.distance_fade_enabled = b[1]
		l.distance_fade_begin = b[2]
		l.distance_fade_length = b[3]
	else:
		var begin := 22.0 if light_quality == 0 else 45.0
		l.distance_fade_enabled = true
		l.distance_fade_begin = minf(begin, float(b[2])) if b[1] else begin
		l.distance_fade_length = 8.0
		l.distance_fade_shadow = minf(l.distance_fade_shadow, begin)


## LOD bias: every visibility range (begin and end, so LOD pairs stay matched) x view_distance;
## foliage / tree MultiMeshes draw only their density share of instances.
func _apply_geo(g) -> void:
	if not is_instance_valid(g) or not (g is GeometryInstance3D):
		return
	if not g.has_meta("q_vr"):
		if g.visibility_range_end <= 0.0 and g.visibility_range_begin <= 0.0:
			g.set_meta("q_vr", Vector4.ZERO) # no range set by the builder: leave it alone
		else:
			g.set_meta("q_vr", Vector4(g.visibility_range_begin, g.visibility_range_end, g.visibility_range_begin_margin, g.visibility_range_end_margin))
	var vr: Vector4 = g.get_meta("q_vr")
	if vr != Vector4.ZERO:
		# never closer than 40 m (or the builder's own range): camps and landmarks stay in sight;
		# begin scales by the same factor so LOD pairs (near mesh / far impostor) stay matched
		var f := view_distance
		if vr.y > 0.0:
			f = maxf(view_distance, minf(1.0, 40.0 / vr.y))
		g.visibility_range_begin = vr.x * f
		g.visibility_range_end = vr.y * f
	if g is MultiMeshInstance3D and g.multimesh != null:
		var nm := String(g.name)
		var dens := -1.0
		for p in FOLIAGE_PREFIX:
			if nm.begins_with(p):
				dens = foliage_density
		if dens < 0.0:
			for p in TREE_PREFIX:
				if nm.begins_with(p):
					dens = tree_density
		if dens >= 0.0:
			var mm: MultiMesh = g.multimesh
			mm.visible_instance_count = -1 if dens >= 0.999 else int(mm.instance_count * dens)


func _apply_camera(c) -> void:
	if not is_instance_valid(c) or not (c is Camera3D):
		return
	if not c.has_meta("q_far"):
		c.set_meta("q_far", c.far)
	c.far = maxf(float(c.get_meta("q_far")) * lerpf(0.5, 1.0, inverse_lerp(0.4, 1.0, view_distance)), 60.0)


## HUD opacity, high contrast and the subtitle style. hud.gd / hunt_hud.gd put their layers in the
## "hud_fade" group; their direct Control children take the opacity.
func _apply_hud() -> void:
	if not is_inside_tree():
		return
	for layer in get_tree().get_nodes_in_group("hud_fade"):
		for c in layer.get_children():
			if c is Control:
				(c as Control).modulate.a = hud_opacity
		_apply_contrast(layer)
	var dl := get_node_or_null("/root/Dialogue")
	if dl != null and dl.has_method("apply_subtitle_style"):
		dl.apply_subtitle_style()
	elif dl != null:
		var lab = dl.get("_label")
		if lab is RichTextLabel:
			lab.add_theme_font_size_override("normal_font_size", sub_font_size())
			lab.add_theme_font_size_override("bold_font_size", sub_font_size())
			lab.add_theme_constant_override("outline_size", 6 if (high_contrast or not subtitle_bg) else 0)
			lab.add_theme_color_override("font_outline_color", Color.BLACK)
		var panel = dl.get("_panel")
		if panel is Control:
			panel.self_modulate.a = 1.0 if subtitle_bg else 0.0


## High contrast: a heavy black outline on every HUD label (kept on the label as a meta so it
## can be put back).
func _apply_contrast(layer: Node) -> void:
	for l in layer.find_children("*", "Label", true, false):
		var lab := l as Label
		if not lab.has_meta("hc_base"):
			lab.set_meta("hc_base", lab.get_theme_constant("outline_size"))
		var base := int(lab.get_meta("hc_base"))
		if high_contrast:
			lab.add_theme_constant_override("outline_size", maxi(base, 8))
			lab.add_theme_color_override("font_outline_color", Color.BLACK)
		else:
			lab.add_theme_constant_override("outline_size", base)


func _maybe_hud(n) -> void:
	if is_instance_valid(n) and n.is_in_group("hud_fade"):
		for c in n.get_children():
			if c is Control:
				(c as Control).modulate.a = hud_opacity
		if high_contrast:
			_apply_contrast(n)


func refresh_lights(lights: Array) -> void:
	for l in lights:
		if is_instance_valid(l):
			l.remove_meta("q_base")
			_apply_light(l)


# ---------------------------------------------------------------- dynamic resolution
var _dr_avg := 0.0
var _dr_hi_t := 0.0
var _dr_lo_t := 0.0
var _dr_hold := 0.0


## Lowers the 3D render scale (down to 50 % of the chosen scale, never below 0.4) when the frame
## time stays over the target, and gives it back slowly once frames are on time again.
func _tick_dynamic_res() -> void:
	var w := world()
	if not dynamic_res or get_tree().paused or w == null or not w.has_method("is_day"):
		if not dynamic_res and dyn_scale != 1.0:
			dyn_scale = 1.0
			_apply_display()
		return
	var dt := get_process_delta_time() / maxf(Engine.time_scale, 0.01) * 1000.0
	if dt > 250.0:
		return # a load hitch, not a trend
	feed_frame_time(dt, get_process_delta_time())


## One frame's time (ms) into the scaler. Public so the smoke test can drive it.
func feed_frame_time(ms: float, dt: float) -> void:
	var target := 1000.0 / float([30, 60, 60][clampi(fps_cap, 0, 2)])
	_dr_avg = ms if _dr_avg <= 0.0 else lerpf(_dr_avg, ms, 0.08)
	_dr_hold = maxf(_dr_hold - dt, 0.0)
	if _dr_avg > target * 1.2:
		_dr_hi_t += dt
		_dr_lo_t = 0.0
	elif _dr_avg < target * 1.05:
		_dr_lo_t += dt
		_dr_hi_t = 0.0
	else:
		_dr_hi_t = 0.0
		_dr_lo_t = 0.0
	if _dr_hi_t > 0.75 and dyn_scale > 0.5 + 0.001 and resolution_scale * dyn_scale > 0.41:
		dyn_scale = maxf(dyn_scale - 0.1, 0.5)
		_dr_hi_t = 0.0
		_dr_hold = 6.0
		_apply_display()
	elif _dr_lo_t > 4.0 and _dr_hold <= 0.0 and dyn_scale < 1.0:
		dyn_scale = minf(dyn_scale + 0.05, 1.0)
		_dr_lo_t = 0.0
		_apply_display()


# ---------------------------------------------------------------- FPS counter
var _fps_label: Label
var _fps_t := 0.0


func _build_fps_label() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 120
	cl.name = "FpsLayer"
	add_child(cl)
	_fps_label = Label.new()
	_fps_label.position = Vector2(8, 4)
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = show_fps
	cl.add_child(_fps_label)
