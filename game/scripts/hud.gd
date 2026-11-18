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
var help_t := 30.0 # the basic controls show for the first 30 s of play, then only context tips
var tip_t := 0.0
var tips_seen := {}
var lock_label: Label # desktop web: "Click to take the hunt" while the pointer isn't locked
var started := false
var using_pad := false
var debug_label: Label # ?debug / --debug: camera, player and draw-call overlay (R2-A, W1)
const KEYS_HELP := "WASD move   SHIFT sprint   SPACE jump (x2)   LMB combo (hold: charged)   RMB / Q dash   C parry\nM map   TAB the Coat   1 / 2 quick-use   ESC pause"
const PAD_HELP := "L-stick move   LT sprint   A jump (x2)   X / RT combo (hold: charged)   B / RB dash   L3 parry\nBACK map   START the Coat   LB / R3 quick-use"
const ROAM_KEYS := "\nF drink at the Undercroft   T rain" # free roam (debug) only
const ROAM_PAD := "\nLB drink at the Undercroft"
## one-shot tips, shown the first time the action becomes possible: [keyboard, pad]
const TIPS := {
	"bite": ["E  bite the staggered enemy (red orb): blood, and Tithe", "Y  bite the staggered enemy (red orb): blood, and Tithe"],
	"rank": ["A rank awaits: rest at a chapel to rise", "A rank awaits: rest at a chapel to rise"],
}


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

	help_label = _label("", 15, Color(0.8, 0.8, 0.8))
	root.add_child(help_label)
	_pin(help_label, 0.0, 1.0, Rect2(24, -84, 900, 74))
	help_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_refresh_help()

	lock_label = _centered(22, Color(1, 0.85, 0.75))
	lock_label.text = "CLICK TO TAKE THE HUNT"
	lock_label.anchor_top = 0.5
	lock_label.anchor_bottom = 0.5
	lock_label.visible = false

	if "--debug" in OS.get_cmdline_user_args() or (main != null and main._url_flag("debug")):
		debug_label = _label("", 13, Color(0.6, 1.0, 0.6))
		_pin(debug_label, 0.0, 0.0, Rect2(24, 230, 700, 140))
		root.add_child(debug_label)

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
	var click := _centered(24, Color(1, 0.4, 0.4))
	click_label = click
	click.text = "TAP TO HUNT" if _touch() else "CLICK TO HUNT  (or press A on a controller)"
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
		_refresh_help()
		click_label.text = "PRESS A TO HUNT" if pad else ("TAP TO HUNT" if _touch() else "CLICK TO HUNT  (or press A on a controller)")
		if started:
			help_t = maxf(help_t, 8.0) # a controller just picked up: show its buttons briefly
			tip_t = 0.0
	if not started and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventScreenTouch) and event.is_pressed():
		get_viewport().set_input_as_handled()
		Audio.unlock() # AUDIO HOOK: the first click unlocks web audio
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
	if debug_label != null:
		_update_debug()
	if started:
		_update_hints(real_dt)
	lock_label.visible = OS.has_feature("web") and started and not _touch() and not using_pad \
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused and not main.game_over and not main.menu_open()


func _update_debug() -> void:
	var cam := get_viewport().get_camera_3d()
	var p = main.player
	var t := "fps %d   draws %d   prims %dk   objs %d\n" % [Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)]
	if cam != null:
		t += "cam %s  %s  far %.0f\n" % [cam.get_path(), str(cam.global_position.snapped(Vector3.ONE * 0.1)), cam.far]
	else:
		t += "cam: none\n"
	t += "sol %s  vel %s" % [str(p.global_position.snapped(Vector3.ONE * 0.1)), str(p.velocity.snapped(Vector3.ONE * 0.1))]
	debug_label.text = t



## The touch layer (touch_controls.gd) is up: its buttons are labelled, so no key hints.
func _touch() -> bool:
	var t := get_node_or_null("/root/Touch")
	return t != null and t.enabled


func _refresh_help() -> void:
	var roam: bool = main != null and main.get("hunt") == null
	if using_pad:
		help_label.text = PAD_HELP + (ROAM_PAD if roam else "")
	else:
		help_label.text = KEYS_HELP + (ROAM_KEYS if roam else "")


## Context hints: the basic controls for the first 30 s of play (and for 8 s when the device
## changes), then one tip the first time something becomes possible (a bite, a rank), else nothing.
func _update_hints(dt: float) -> void:
	if _touch() and not using_pad:
		help_label.visible = false
		return
	help_label.visible = true
	if help_t > 0.0:
		help_t -= dt
		if help_t <= 0.0:
			help_label.text = ""
		help_label.modulate.a = clampf(help_t / 2.0, 0.0, 1.0)
		return
	if tip_t > 0.0:
		tip_t -= dt
		help_label.modulate.a = clampf(tip_t, 0.0, 1.0)
		return
	var p = main.player
	if p.get("bite_ready") and not tips_seen.has("bite"):
		_tip("bite")
	elif main.progression != null and main.get("hunt") != null and main.progression.can_level() and not tips_seen.has("rank"):
		_tip("rank")


func _tip(id: String) -> void:
	tips_seen[id] = true
	help_label.text = TIPS[id][1 if using_pad else 0]
	tip_t = 6.0
