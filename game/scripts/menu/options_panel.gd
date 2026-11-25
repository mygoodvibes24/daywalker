extends PanelContainer
## The Options screen, shared by the main menu and the pause menu: five tabs (Graphics / Display /
## Preferences / Audio / Accessibility), each a scrolling list of rows bound to a key of the Settings
## autoload (settings.gd), which applies the change live and saves it to user://settings.cfg.
## Mouse / touch: tap a tab, drag or wheel the list, tap a choice (right-click steps back).
## Keyboard / controller: up / down moves between rows, left / right changes a value, A / Enter
## cycles a choice, LB / RB (or [ / ], PageUp / PageDown) switch tabs, B / Esc goes back (handled by
## the owner, see `back`).
## Graphics changes that move the preset ask "Keep these settings?" and revert after 12 s unless kept.

signal back

const S = preload("res://scripts/ui/ui_style.gd")
const SettingsScript = preload("res://scripts/settings.gd")
const TABS := ["Graphics", "Display", "Preferences", "Audio", "Accessibility"]
const TAB_SECTION := ["graphics", "video", "controls", "audio", "access"]
const CONFIRM_SECONDS := 12.0

# [key, label, kind, extra...]; kind: "slider" (min, max, step, format, scale), "choice" (names),
# "toggle"; a "?" prefix on the label hides the row where it does nothing (see _row_wanted)
const ROWS := [
	[ # Graphics
		["tier", "Quality preset", "choice", SettingsScript.PRESETS],
		["resolution_scale", "Render scale", "slider", 0.5, 1.0, 0.05, "%d%%", 100.0],
		["dynamic_res", "Dynamic resolution", "toggle"],
		["shadow_quality", "Shadows", "choice", SettingsScript.SHADOWS],
		["shadow_distance", "Shadow distance", "slider", 20.0, 120.0, 5.0, "%d m", 1.0],
		["view_distance", "View distance", "slider", 0.4, 1.0, 0.05, "%d%%", 100.0],
		["foliage_density", "Foliage density", "slider", 0.0, 1.0, 0.05, "%d%%", 100.0],
		["tree_density", "Tree density", "slider", 0.3, 1.0, 0.05, "%d%%", 100.0],
		["crowd_density", "Crowd density (max enemies)", "slider", 0.6, 1.0, 0.05, "%d%%", 100.0],
		["fog_quality", "Fog and light shafts", "choice", SettingsScript.FOG],
		["light_quality", "Street lights", "choice", SettingsScript.LIGHTS],
		["post_fx", "Post effects (glow, grain)", "toggle"],
		["ssao", "SSAO / SSR (desktop)", "toggle"],
		["rain", "Rain", "toggle"],
		["aa", "Anti-aliasing", "choice", SettingsScript.AA],
		["coat_quality", "Coat physics", "choice", SettingsScript.COAT],
		["vfx_amount", "Effects amount", "slider", 0.2, 1.0, 0.05, "%d%%", 100.0],
		["fps_cap", "Frame rate cap", "choice", SettingsScript.FPS_CAPS],
		["show_fps", "FPS counter", "toggle"],
	],
	[ # Display
		["window_mode", "Window mode", "choice", SettingsScript.WINDOW_MODES],
		["brightness", "Brightness", "slider", 0.5, 1.6, 0.05, "%d%%", 100.0],
		["fov", "Field of view", "slider", 55.0, 100.0, 1.0, "%d°", 1.0],
		["vsync", "V-Sync", "toggle"],
		["ui_scale", "UI scale", "slider", 0.8, 1.5, 0.05, "%d%%", 100.0],
		["hud_opacity", "HUD opacity", "slider", 0.3, 1.0, 0.05, "%d%%", 100.0],
	],
	[ # Preferences
		["mouse_sensitivity", "Mouse sensitivity", "slider", 0.2, 3.0, 0.05, "%.2f x", 1.0],
		["pad_sensitivity", "Controller look sensitivity", "slider", 0.2, 3.0, 0.05, "%.2f x", 1.0],
		["touch_sensitivity", "Touch look sensitivity", "slider", 0.2, 3.0, 0.05, "%.2f x", 1.0],
		["invert_y", "Invert Y look", "toggle"],
		["camera_shake", "Camera shake", "slider", 0.0, 1.0, 0.05, "%d%%", 100.0],
		["aim_assist", "Aim assist (soft lock)", "toggle"],
		["subtitles", "Subtitles", "toggle"],
		["hints", "Control hints", "toggle"],
		["touch_size", "Touch controls size", "slider", 0.7, 1.4, 0.05, "%d%%", 100.0],
		["touch_opacity", "Touch controls opacity", "slider", 0.2, 1.0, 0.05, "%d%%", 100.0],
	],
	[ # Audio
		["Master", "Master volume", "slider", 0.0, 1.0, 0.05, "%d%%", 100.0],
		["Music", "Music volume", "slider", 0.0, 1.0, 0.05, "%d%%", 100.0],
		["SFX", "Effects volume", "slider", 0.0, 1.0, 0.05, "%d%%", 100.0],
		["Voice", "Voice volume", "slider", 0.0, 1.0, 0.05, "%d%%", 100.0],
		["mute_unfocused", "Mute when in background", "toggle"],
	],
	[ # Accessibility
		["subtitles", "Subtitles", "toggle"],
		["subtitle_size", "Subtitle size", "choice", SettingsScript.SUB_SIZES],
		["subtitle_bg", "Subtitle background", "toggle"],
		["colorblind", "Colour-blind palette", "choice", SettingsScript.COLORBLIND],
		["reduce_flashing", "Reduce flashing", "toggle"],
		["reduce_motion", "Reduce motion (no shake)", "toggle"],
		["toggle_sprint", "Sprint: toggle instead of hold", "toggle"],
		["high_contrast", "High-contrast HUD", "toggle"],
		["large_text", "Larger UI text", "toggle"],
	],
]

var first_focus: Control
var back_button: Button
var reset_button: Button
var tab_buttons: Array[Button] = []
var pages: Array[Control] = []
var page_first: Array[Control] = []
var scroll: ScrollContainer
var tab := 0
var confirm_bar: Control
var confirm_label: Label
var keep_button: Button
var _confirm_t := -1.0
var _confirm_snap := {}
var _refresh: Array[Callable] = []
var _settings_node: Node
var _row_controls := {} # key -> Control (the first row of that key), for tests


func _init() -> void:
	var sb := S.box(Color(0.035, 0.022, 0.026, 0.95), S.GOLD_DIM, 1, 3, 18)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 24
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(980, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)
	var t := S.title("OPTIONS", 30, S.TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(t)
	# tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(tabs)
	for i in TABS.size():
		var b := S.button(TABS[i], 17)
		b.custom_minimum_size = Vector2(150, 34)
		b.toggle_mode = true
		b.pressed.connect(show_tab.bind(i))
		tabs.add_child(b)
		tab_buttons.append(b)
	outer.add_child(S.rule())
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var stack := MarginContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("margin_right", 14)
	scroll.add_child(stack)
	for i in TABS.size():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.visible = i == 0
		stack.add_child(col)
		pages.append(col)
		var first: Control = null
		for row in ROWS[i]:
			if not _row_wanted(row[0]):
				continue
			var c := _row(col, row)
			if first == null:
				first = c
			if not _row_controls.has(row[0]):
				_row_controls[row[0]] = c
		page_first.append(first)
	# the "keep these graphics settings?" bar
	confirm_bar = HBoxContainer.new()
	confirm_bar.add_theme_constant_override("separation", 12)
	confirm_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_bar.visible = false
	outer.add_child(confirm_bar)
	confirm_label = S.label("", 16, S.GOLD, 3)
	confirm_bar.add_child(confirm_label)
	keep_button = S.button("Keep", 16)
	keep_button.custom_minimum_size = Vector2(110, 32)
	keep_button.pressed.connect(confirm_keep)
	confirm_bar.add_child(keep_button)
	var rv := S.button("Revert", 16)
	rv.custom_minimum_size = Vector2(110, 32)
	rv.pressed.connect(confirm_revert)
	confirm_bar.add_child(rv)
	# footer: reset this tab, back
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 18)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(foot)
	reset_button = S.button("Reset to defaults", 16)
	reset_button.custom_minimum_size = Vector2(210, 36)
	reset_button.pressed.connect(reset_tab)
	foot.add_child(reset_button)
	back_button = S.button("Back", 18)
	back_button.custom_minimum_size = Vector2(180, 36)
	back_button.pressed.connect(func(): back.emit())
	foot.add_child(back_button)
	var hint := S.label("LB / RB  or  [ / ]   switch tab", 13, S.TEXT_DIM, 3)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(hint)
	_wire_focus()
	visibility_changed.connect(_on_shown)
	show_tab(0, false)


## Rows that do nothing on this platform stay out: V-Sync in a browser, SSAO / SSR on the
## Compatibility renderer, touch rows without a touch screen... (kept in the headless tests).
func _row_wanted(key: String) -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	match key:
		"vsync":
			return not OS.has_feature("web")
		"ssao":
			return SettingsScript.cinematic()
		"touch_size", "touch_opacity", "touch_sensitivity":
			return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web")
	return true


func _wire_focus() -> void:
	# tabs <-> first row; last row -> footer
	for b in tab_buttons:
		b.focus_neighbor_bottom = NodePath("")


func _settings() -> Node:
	if _settings_node == null and is_inside_tree():
		_settings_node = get_node_or_null("/root/Settings")
	return _settings_node


func _value(key: String) -> Variant:
	var s := _settings()
	if s != null:
		return s.get_value(key)
	if key in SettingsScript.BUSES:
		return SettingsScript.volume[key]
	return SettingsScript._me().get(key)


func _set_value(key: String, v: Variant) -> void:
	var s := _settings()
	var graphics: bool = key == "tier" # a preset change asks to keep or revert
	if graphics and _confirm_t < 0.0:
		_confirm_snap = SettingsScript.snapshot()
	if s != null:
		s.set_value(key, v)
	else:
		SettingsScript._me().set(key, v)
	if graphics:
		_start_confirm()
	refresh_all()


func refresh_all() -> void:
	for r in _refresh:
		r.call()


# ---------------------------------------------------------------- tabs
func show_tab(i: int, focus := true) -> void:
	tab = clampi(i, 0, TABS.size() - 1)
	for k in pages.size():
		pages[k].visible = k == tab
		tab_buttons[k].button_pressed = k == tab
	first_focus = page_first[tab]
	scroll.scroll_vertical = 0
	if focus and first_focus != null and is_visible_in_tree():
		first_focus.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var dir := 0
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			dir = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			dir = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_BRACKETLEFT, KEY_PAGEUP: dir = -1
			KEY_BRACKETRIGHT, KEY_PAGEDOWN: dir = 1
	if dir != 0:
		show_tab(posmod(tab + dir, TABS.size()))
		get_viewport().set_input_as_handled()


func reset_tab() -> void:
	var s := _settings()
	if tab == 0 and _confirm_t < 0.0:
		_confirm_snap = SettingsScript.snapshot()
	if s != null:
		s.reset_defaults(TAB_SECTION[tab])
	if tab == 0:
		_start_confirm()
	refresh_all()


# ---------------------------------------------------------------- keep / revert graphics
func _start_confirm() -> void:
	if _confirm_snap.is_empty():
		return
	_confirm_t = CONFIRM_SECONDS
	confirm_bar.visible = true
	_update_confirm_label()


func _update_confirm_label() -> void:
	confirm_label.text = "Keep these graphics settings?  Reverting in %d s" % ceili(maxf(_confirm_t, 0.0))


func confirm_keep() -> void:
	_confirm_t = -1.0
	_confirm_snap = {}
	confirm_bar.visible = false


func confirm_revert() -> void:
	if not _confirm_snap.is_empty():
		var snap := {}
		for k in SettingsScript.GRAPHICS_KEYS + ["tier", "quality"]:
			snap[k] = _confirm_snap[k]
		SettingsScript.restore(snap)
		var s := _settings()
		if s != null:
			SettingsScript.dyn_scale = 1.0
			s.apply_all()
			s.apply_graphics()
			s.save_settings()
			s.changed.emit()
			s.graphics_changed.emit()
	confirm_keep()
	refresh_all()


# ---------------------------------------------------------------- rows
func _row(col: VBoxContainer, row: Array) -> Control:
	var key: String = row[0]
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 34)
	h.add_theme_constant_override("separation", 14)
	col.add_child(h)
	var l := S.label(row[1], 17, S.TEXT, 3)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	h.add_child(l)
	match row[2]:
		"slider":
			return _slider(h, key, row, l)
		"toggle":
			return _choice(h, key, ["Off", "On"], l)
	return _choice(h, key, row[3], l)


func _slider(h: HBoxContainer, key: String, row: Array, l: Label) -> Control:
	var sl := HSlider.new()
	sl.min_value = row[3]
	sl.max_value = row[4]
	sl.step = row[5]
	sl.custom_minimum_size = Vector2(240, 30)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_ALL
	var track := S.box(Color(0.12, 0.08, 0.08), Color(0.3, 0.22, 0.16), 1, 2)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	sl.add_theme_stylebox_override("slider", track)
	var fill := S.box(Color(0.55, 0.04, 0.07), Color(0.75, 0.1, 0.12), 1, 2)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.add_theme_icon_override("grabber", _knob(S.TEXT_DIM))
	sl.add_theme_icon_override("grabber_highlight", _knob(S.GOLD))
	sl.add_theme_stylebox_override("focus", S.box(Color(0, 0, 0, 0), S.GOLD, 1, 3, 2))
	h.add_child(sl)
	var v := S.label("", 16, S.GOLD, 3)
	v.custom_minimum_size = Vector2(76, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(v)
	var fmt: String = row[6]
	var scale: float = row[7]
	var show := func(x: float) -> void:
		v.text = fmt % (roundi(x * scale) if fmt.contains("%d") else x * scale)
	var refresh := func() -> void:
		var val = _value(key)
		sl.set_value_no_signal(float(val) if val != null else sl.min_value)
		show.call(sl.value)
	refresh.call()
	_refresh.append(refresh)
	# apply on release / keys (a drag would re-apply graphics every pixel): the label follows live
	sl.value_changed.connect(func(x: float) -> void:
		show.call(x)
		if not sl.has_meta("dragging"):
			_set_value(key, x))
	sl.drag_started.connect(func(): sl.set_meta("dragging", true))
	sl.drag_ended.connect(func(changed: bool) -> void:
		sl.remove_meta("dragging")
		if changed:
			_set_value(key, sl.value))
	_highlight(sl, l)
	return sl


func _choice(h: HBoxContainer, key: String, names: Array, l: Label) -> Control:
	var b := S.button("", 16)
	b.custom_minimum_size = Vector2(320, 30)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var allowed: Array = range(names.size())
	if key == "window_mode":
		allowed = SettingsScript.window_modes_available()
	elif key == "aa" and not SettingsScript.cinematic() and DisplayServer.get_name() != "headless" and OS.has_feature("web"):
		allowed = [0, 1, 2] # MSAA 4x is too heavy for the browser
	h.add_child(b)
	var current := func() -> int:
		var v = _value(key)
		if v == null:
			return 0
		return int(v) if not (v is bool) else (1 if v else 0)
	var refresh := func() -> void:
		b.text = "‹    %s    ›" % names[clampi(current.call(), 0, names.size() - 1)]
	var step := func(dir: int) -> void:
		var i := allowed.find(current.call())
		i = posmod(i + dir, allowed.size())
		var nv: int = allowed[i]
		var is_bool: bool = names.size() == 2 and names[0] == "Off"
		_set_value(key, (nv == 1) if is_bool else nv)
		refresh.call()
	refresh.call()
	_refresh.append(refresh)
	b.pressed.connect(func(): step.call(1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left", true):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed("ui_right", true):
			step.call(1)
			b.accept_event()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			step.call(-1)
			b.accept_event())
	_highlight(b, l)
	b.set_meta("step", step)
	return b


## Test hook: step a choice row (by key) forward or back, as a press / left-right would.
func step_choice(key: String, dir := 1) -> bool:
	var c: Control = _row_controls.get(key)
	if c == null or not c.has_meta("step"):
		return false
	(c.get_meta("step") as Callable).call(dir)
	return true


func row_control(key: String) -> Control:
	return _row_controls.get(key)


## The row's label lights up gold while its control has focus.
func _highlight(c: Control, l: Label) -> void:
	c.focus_entered.connect(func(): l.add_theme_color_override("font_color", S.GOLD))
	c.focus_exited.connect(func(): l.add_theme_color_override("font_color", S.TEXT))
	c.mouse_entered.connect(func():
		if not DisplayServer.is_touchscreen_available():
			c.grab_focus())


func _knob(col: Color) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length()
			var a := clampf(7.5 - d, 0.0, 1.0)
			var c := col if d < 5.5 else Color(0.1, 0.02, 0.03)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


func _on_shown() -> void:
	if not is_visible_in_tree():
		if _confirm_t >= 0.0:
			confirm_keep() # leaving the screen keeps what you chose
		return
	refresh_all()
	var s := _settings()
	if s != null and not s.changed.is_connected(refresh_all):
		s.changed.connect(refresh_all)
	if first_focus != null:
		first_focus.grab_focus.call_deferred()


var _last_vs := Vector2.ZERO


## Size the panel to the screen: up to 980 px wide, the list scrolls to fill ~92 % of the height,
## so the footer (Back) is always on screen at 720p and on a phone in landscape.
func fit_scale(vs: Vector2) -> float:
	var sz := size if size.y > 0.0 else get_combined_minimum_size()
	return minf(1.0, minf(vs.y * 0.96 / maxf(sz.y, 1.0), vs.x * 0.96 / maxf(sz.x, 1.0)))


func _layout(vs: Vector2) -> void:
	custom_minimum_size.x = minf(980.0, vs.x - 24.0)
	var chrome := get_combined_minimum_size().y - scroll.custom_minimum_size.y
	scroll.custom_minimum_size.y = clampf(vs.y * 0.94 - chrome, 160.0, 560.0)
	size = Vector2.ZERO # shrink to the new minimum


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _confirm_t >= 0.0:
		_confirm_t -= delta / maxf(Engine.time_scale, 0.01)
		if _confirm_t <= 0.0:
			confirm_revert()
		else:
			_update_confirm_label()
	var vs := get_viewport_rect().size
	if vs != _last_vs:
		_last_vs = vs
		_layout(vs)
	if size.y <= 0.0:
		return
	var k := fit_scale(vs)
	pivot_offset = size * 0.5
	if not is_equal_approx(scale.x, k):
		scale = Vector2(k, k)
