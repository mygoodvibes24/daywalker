extends PanelContainer
## The Options screen, shared by the main menu and the pause menu. Data-driven: one row
## per setting in ROWS, each bound to a key of the Settings autoload (settings.gd), which
## applies the change live and saves it to user://settings.cfg.
## Keyboard / controller: up / down moves between rows, left / right changes a value,
## A / Enter cycles a choice, B / Esc goes back (handled by the owner, see `back`).

signal back

const S = preload("res://scripts/ui/ui_style.gd")
const SettingsScript = preload("res://scripts/settings.gd")

# [key, label, kind, extra...]; kind: "slider" (min, max, step, format, scale) or "choice" (names)
const ROWS := [
	["#", "DISPLAY"],
	["brightness", "Brightness", "slider", 0.5, 1.6, 0.05, "%d%%", 100.0],
	["window_mode", "Window mode", "choice", SettingsScript.WINDOW_MODES],
	["resolution_scale", "Resolution scale", "slider", 0.5, 1.0, 0.05, "%d%%", 100.0],
	["vsync", "V-Sync", "choice", ["Off", "On"]],
	["quality", "Quality preset", "choice", SettingsScript.QUALITY],
	["rain", "Rain", "choice", ["Off", "On"]],
	["#", "CONTROLS"],
	["mouse_sensitivity", "Mouse sensitivity", "slider", 0.2, 3.0, 0.05, "%.2f x", 1.0],
	["pad_sensitivity", "Controller look sensitivity", "slider", 0.2, 3.0, 0.05, "%.2f x", 1.0],
	["invert_y", "Invert Y look", "choice", ["Off", "On"]],
	["#", "AUDIO"],
	["Master", "Master volume", "slider", 0.0, 1.0, 0.05, "%d%%", 100.0],
	["Music", "Music volume", "slider", 0.0, 1.0, 0.05, "%d%%", 100.0],
	["SFX", "Effects volume", "slider", 0.0, 1.0, 0.05, "%d%%", 100.0],
]

var first_focus: Control
var back_button: Button
var _refresh: Array[Callable] = []


func _init() -> void:
	var sb := S.box(Color(0.035, 0.022, 0.026, 0.94), S.GOLD_DIM, 1, 3, 22)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 24
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(620, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	add_child(col)
	var t := S.title("OPTIONS", 34, S.TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	col.add_child(S.rule())
	var prev: Control = null
	for row in ROWS:
		if row[0] == "#":
			var h := S.label(row[1], 14, S.CRIMSON.lightened(0.25), 3)
			h.add_theme_font_override("font", S.serif())
			h.custom_minimum_size = Vector2(0, 26)
			h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			col.add_child(h)
			continue
		var c := _row(col, row)
		if prev == null:
			first_focus = c
		prev = c
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	col.add_child(sp)
	back_button = S.button("Back", 18)
	back_button.custom_minimum_size = Vector2(180, 38)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(func(): back.emit())
	col.add_child(back_button)
	visibility_changed.connect(_on_shown)


func _settings() -> Node:
	return get_node_or_null("/root/Settings") if is_inside_tree() else null


func _value(key: String) -> Variant:
	var s := _settings()
	if s != null:
		return s.get_value(key)
	if key in SettingsScript.BUSES:
		return SettingsScript.volume[key]
	return _static_value(key)


func _static_value(key: String) -> Variant:
	match key:
		"brightness": return SettingsScript.brightness
		"window_mode": return SettingsScript.window_mode
		"resolution_scale": return SettingsScript.resolution_scale
		"vsync": return SettingsScript.vsync
		"quality": return SettingsScript.quality
		"rain": return SettingsScript.rain
		"mouse_sensitivity": return SettingsScript.mouse_sensitivity
		"pad_sensitivity": return SettingsScript.pad_sensitivity
		"invert_y": return SettingsScript.invert_y
	return 0


func _set_value(key: String, v: Variant) -> void:
	var s := _settings()
	if s != null:
		s.set_value(key, v)


func _row(col: VBoxContainer, row: Array) -> Control:
	var key: String = row[0]
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 34)
	h.add_theme_constant_override("separation", 14)
	col.add_child(h)
	var l := S.label(row[1], 17, S.TEXT, 3)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	if row[2] == "slider":
		return _slider(h, key, row, l)
	return _choice(h, key, row[3], l)


func _slider(h: HBoxContainer, key: String, row: Array, l: Label) -> Control:
	var sl := HSlider.new()
	sl.min_value = row[3]
	sl.max_value = row[4]
	sl.step = row[5]
	sl.custom_minimum_size = Vector2(210, 30)
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
	v.custom_minimum_size = Vector2(70, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(v)
	var fmt: String = row[6]
	var scale: float = row[7]
	var show := func(x: float) -> void:
		v.text = fmt % (roundi(x * scale) if fmt.contains("%d") else x * scale)
	var refresh := func() -> void:
		sl.set_value_no_signal(float(_value(key)))
		show.call(sl.value)
	refresh.call()
	_refresh.append(refresh)
	sl.value_changed.connect(func(x: float) -> void:
		show.call(x)
		_set_value(key, x))
	_highlight(sl, l)
	return sl


func _choice(h: HBoxContainer, key: String, names: Array, l: Label) -> Control:
	var b := S.button("", 16)
	b.custom_minimum_size = Vector2(294, 30)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var allowed: Array = range(names.size())
	if key == "window_mode":
		allowed = SettingsScript.window_modes_available()
	h.add_child(b)
	var current := func() -> int:
		var v = _value(key)
		return int(v) if not (v is bool) else (1 if v else 0)
	var refresh := func() -> void:
		b.text = "‹    %s    ›" % names[clampi(current.call(), 0, names.size() - 1)]
	var step := func(dir: int) -> void:
		var i := allowed.find(current.call())
		i = posmod(i + dir, allowed.size())
		var nv: int = allowed[i]
		_set_value(key, (nv == 1) if names.size() == 2 and names[0] == "Off" else nv)
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
	return b


## The row's label lights up gold while its control has focus.
func _highlight(c: Control, l: Label) -> void:
	c.focus_entered.connect(func(): l.add_theme_color_override("font_color", S.GOLD))
	c.focus_exited.connect(func(): l.add_theme_color_override("font_color", S.TEXT))
	c.mouse_entered.connect(func(): c.grab_focus())


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
		return
	for r in _refresh:
		r.call()
	if first_focus != null:
		first_focus.grab_focus.call_deferred()
