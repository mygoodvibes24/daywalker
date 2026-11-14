extends CanvasLayer
## On-screen HUD: blood, hunger, dash charges, clock, prompts and announcements.

var main
var root: Control
var hp_bar: ProgressBar
var hunger_bar: ProgressBar
var hunger_fill: StyleBoxFlat
var dash_label: Label
var form_label: Label
var clock_label: Label
var info_label: Label
var prompt_label: Label
var announce_label: Label
var popup_label: Label
var help_label: Label
var tithe_label: Label # PROGRESSION HOOK: rank + Tithe
var vignette: ColorRect
var frenzy_tint: ColorRect
var start_overlay: Control
var over_panel: Control
var over_label: Label
var click_label: Label
var announce_t := 0.0
var popup_t := 0.0
var damage_t := 0.0
var help_t := 20.0
var started := false
var using_pad := false
const KEYS_HELP := "WASD move   SHIFT sprint   SPACE jump (x2)\nRMB / Q  Blood Dash   LMB / J  blade combo\nE  bite a staggered enemy (red orb) / take loot   F  drink at the Undercroft\nTAB / I  the Coat (inventory)   1 / 2  quick-use   T  rain   ESC  pause"
const PAD_HELP := "L-stick move   R-stick camera   LT / L3 sprint   A jump (x2)\nB / RB  Blood Dash   X / RT  blade combo\nY  bite a staggered enemy (red orb) / take loot   LB  drink at the Undercroft\nSTART  the Coat (restart after death)   LB / R3  quick-use   BACK  rain (pause from the Coat)"


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	vignette = _rect(Color(0.7, 0.0, 0.0, 0.0))
	frenzy_tint = _rect(Color(0.5, 0.0, 0.05, 0.0))

	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	box.add_child(_label("BLOOD", 14, Color(0.9, 0.85, 0.85)))
	hp_bar = _bar(Color(0.75, 0.05, 0.08))
	box.add_child(hp_bar)
	box.add_child(_label("HUNGER", 14, Color(0.9, 0.85, 0.85)))
	hunger_bar = _bar(Color(0.45, 0.1, 0.55))
	hunger_fill = hunger_bar.get_theme_stylebox("fill") as StyleBoxFlat
	box.add_child(hunger_bar)
	form_label = _label("", 16, Color(1, 0.85, 0.5))
	box.add_child(form_label)
	dash_label = _label("", 18, Color(0.85, 0.9, 1.0))
	box.add_child(dash_label)
	tithe_label = _label("", 18, Color(1.0, 0.45, 0.4))
	box.add_child(tithe_label)

	clock_label = _label("", 30, Color.WHITE)
	_pin(clock_label, 1.0, 0.0, Rect2(-344, 16, 320, 40))
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(clock_label)
	info_label = _label("", 16, Color(0.85, 0.85, 0.85))
	_pin(info_label, 1.0, 0.0, Rect2(-344, 58, 320, 80))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(info_label)

	prompt_label = _centered(22, Color(1, 0.35, 0.35))
	prompt_label.anchor_top = 0.72
	prompt_label.anchor_bottom = 0.72
	announce_label = _centered(40, Color(1, 0.9, 0.85))
	announce_label.anchor_top = 0.16
	announce_label.anchor_bottom = 0.16
	popup_label = _centered(24, Color(1, 0.8, 0.8))
	popup_label.anchor_top = 0.6
	popup_label.anchor_bottom = 0.6

	help_label = _label(KEYS_HELP, 15, Color(0.8, 0.8, 0.8))
	root.add_child(help_label)
	_pin(help_label, 0.0, 1.0, Rect2(24, -110, 760, 100))

	start_overlay = _build_start()
	over_panel = ColorRect.new()
	(over_panel as ColorRect).color = Color(0, 0, 0, 0.7)
	over_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over_panel.visible = false
	root.add_child(over_panel)
	over_label = _centered(36, Color(1, 0.3, 0.3))
	over_label.reparent(over_panel)
	over_label.anchor_top = 0.4
	over_label.anchor_bottom = 0.4


func _build_start() -> Control:
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.82)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var title := _centered(64, Color(0.85, 0.05, 0.1))
	title.text = "DAYWALKER"
	title.reparent(panel)
	title.anchor_top = 0.3
	title.anchor_bottom = 0.3
	var sub := _centered(26, Color(0.9, 0.9, 0.9))
	sub.text = "BLOOD AND MOON"
	sub.reparent(panel)
	sub.anchor_top = 0.41
	sub.anchor_bottom = 0.41
	var story := _centered(17, Color(0.75, 0.75, 0.75))
	story.text = "Port Vesper. Someone is framing you for murders on both sides.\nThe Velvet Court hunts by night. The Hollow Pack turns under the moon.\nSurvive. Feed. Don't lose yourself."
	story.reparent(panel)
	story.anchor_top = 0.55
	story.anchor_bottom = 0.55
	if DisplayServer.is_touchscreen_available() and OS.has_feature("web"):
		var note := _centered(20, Color(1, 0.85, 0.4))
		note.text = "Best on a desktop browser with keyboard + mouse or a controller.\nTouch controls are not supported yet."
		note.reparent(panel)
		note.anchor_top = 0.88
		note.anchor_bottom = 0.88
	var click := _centered(24, Color(1, 0.4, 0.4))
	click_label = click
	click.text = "CLICK TO HUNT  (or press A on a controller)"
	click.reparent(panel)
	click.anchor_top = 0.75
	click.anchor_bottom = 0.75
	return panel


func _pin(c: Control, ax: float, ay: float, r: Rect2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _centered(size: int, color: Color) -> Label:
	var l := _label("", size, color)
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.offset_top = -60
	l.offset_bottom = 60
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(l)
	return l


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(320, 16)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.border_color = Color(1, 1, 1, 0.25)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


func announce(text: String) -> void:
	announce_label.text = text
	announce_t = 4.0


func popup(text: String) -> void:
	popup_label.text = text
	popup_t = 1.8


func on_damage() -> void:
	damage_t = 0.4


func show_game_over() -> void:
	over_panel.visible = true
	over_label.text = "YOU FELL IN PORT VESPER\nKills: %d     Nights survived: %d\n\n[R] / START  Rise again" % [main.kills, main.night_count]


func _unhandled_input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	if pad != using_pad and (pad or event is InputEventKey or event is InputEventMouseButton):
		using_pad = pad
		help_label.text = PAD_HELP if pad else KEYS_HELP
		click_label.text = "PRESS A TO HUNT" if pad else "CLICK TO HUNT  (or press A on a controller)"
		if started:
			help_t = maxf(help_t, 6.0)
	if not started and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed():
		get_viewport().set_input_as_handled()
		main.start_game()


func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	var p = main.player
	start_overlay.visible = not started
	hp_bar.max_value = p.max_hp # PROGRESSION HOOK: ranks raise max blood
	hp_bar.value = p.hp
	hunger_bar.value = p.hunger
	hunger_fill.bg_color = Color(0.45, 0.1, 0.55).lerp(Color(1.0, 0.05, 0.1), p.hunger / 100.0)
	var form := "DAYWALKER  (sunlight heals you)" if main.daylight() > 0.3 else "DAYWALKER"
	if p.frenzy_t > 0.0:
		form = "FRENZY  %.0fs" % p.frenzy_t
	elif p.hunger >= 60.0:
		form = "NIGHTBORN  (+25% damage)"
	elif p.hunger >= 30.0:
		form = "HUNGRY"
	var buffs := ""
	if p.speed_boost_t > 0.0:
		buffs += "  SPEED"
	if p.rage_t > 0.0:
		buffs += "  RAGE"
	form_label.text = form + buffs
	dash_label.text = "DASH  %d / %d" % [int(p.dash_charges), int(p.MAX_DASH)]
	var phase := "DAY" if main.is_day() else ("FULL MOON" if main.is_full_moon() else "NIGHT")
	clock_label.text = "%s  %s" % [phase, main.clock_text()]
	info_label.text = "Kills  %d\nNights survived  %d\nBlood bank  %d / %d" % [main.kills, main.night_count, main.lair_stock, main.LAIR_MAX]
	prompt_label.text = p.prompt_text
	if main.progression != null: # PROGRESSION HOOK
		var lp: String = main.loot.prompt_text
		prompt_label.text = lp if prompt_label.text == "" else (prompt_label.text + ("\n" + lp if lp != "" else ""))
		tithe_label.text = "RANK %d     TITHE %d" % [main.progression.level, main.progression.tithe]
		if main.progression.can_level():
			tithe_label.text += "   ·  a rank awaits at " + ("a chapel" if main.get("hunt") != null else "the Undercroft")

	announce_t = maxf(announce_t - real_dt, 0.0)
	announce_label.modulate.a = clampf(announce_t, 0.0, 1.0)
	popup_t = maxf(popup_t - real_dt, 0.0)
	popup_label.modulate.a = clampf(popup_t * 2.0, 0.0, 1.0)
	damage_t = maxf(damage_t - real_dt, 0.0)
	var low := clampf(1.0 - p.hp / 35.0, 0.0, 1.0) * 0.18
	vignette.color.a = maxf(damage_t * 0.8, low)
	frenzy_tint.color.a = lerpf(frenzy_tint.color.a, 0.22 if p.frenzy_t > 0.0 else 0.0, 6.0 * real_dt)
	if started:
		help_t -= real_dt
		help_label.modulate.a = clampf(help_t / 2.0, 0.0, 1.0)
