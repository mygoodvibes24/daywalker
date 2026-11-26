extends CanvasLayer
## The Hunt's HUD layer (on top of hud.gd): compass strip, "DAY 1 — The Curfew falls in
## 2:10", revive charges, the boss health bar, the POI prompt, the blood-fog tint when
## Sol stands outside the Curfew, and a fade for the Final Night crossing.

const S = preload("res://scripts/ui/ui_style.gd")
const Compass = preload("res://scripts/ui/compass.gd")

var director: HuntDirector
var main: Main
var root: Control
var compass: Control
var phase: Label
var revive_label: Label
var tally: Label
var prompt: Label
var tint: ColorRect
var fade: ColorRect
var boss_box: Control
var boss_name: Label
var boss_bar: ProgressBar
var boss_lag: ProgressBar
var map_hint: Label


func _ready() -> void:
	add_to_group("hud_fade") # SETTINGS HOOK: HUD opacity / high contrast (settings.gd)
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	tint = ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.color = Color(0.55, 0.0, 0.02, 0.0)
	root.add_child(tint)

	compass = Compass.new()
	compass.director = director
	compass.main = main
	compass.anchor_left = 0.5
	compass.anchor_right = 0.5
	compass.offset_left = -330
	compass.offset_right = 330
	compass.offset_top = 8
	compass.offset_bottom = 52
	root.add_child(compass)

	phase = S.label("", 20, Color(1.0, 0.86, 0.8), 6)
	phase.add_theme_font_override("font", S.serif())
	phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase.anchor_left = 0.5
	phase.anchor_right = 0.5
	phase.offset_left = -400
	phase.offset_right = 400
	phase.offset_top = 70
	phase.offset_bottom = 100
	phase.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(phase)

	revive_label = S.label("", 18, Color(1.0, 0.5, 0.45), 5)
	revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	revive_label.anchor_left = 1.0
	revive_label.anchor_right = 1.0
	revive_label.offset_left = -360
	revive_label.offset_right = -24
	revive_label.offset_top = 18
	revive_label.offset_bottom = 46
	root.add_child(revive_label)
	tally = S.label("", 15, Color(0.85, 0.8, 0.75), 4)
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tally.anchor_left = 1.0
	tally.anchor_right = 1.0
	tally.offset_left = -360
	tally.offset_right = -24
	tally.offset_top = 46
	tally.offset_bottom = 110
	root.add_child(tally)

	prompt = S.label("", 21, Color(1.0, 0.85, 0.55), 6)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.anchor_left = 0.0
	prompt.anchor_right = 1.0
	prompt.anchor_top = 0.8
	prompt.anchor_bottom = 0.8
	prompt.offset_top = -30
	prompt.offset_bottom = 30
	root.add_child(prompt)

	# the boss bar
	boss_box = VBoxContainer.new()
	boss_box.anchor_left = 0.5
	boss_box.anchor_right = 0.5
	boss_box.anchor_top = 1.0
	boss_box.anchor_bottom = 1.0
	boss_box.offset_left = -380
	boss_box.offset_right = 380
	boss_box.offset_top = -92
	boss_box.offset_bottom = -30
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(boss_box)
	boss_name = S.title("", 26, Color(1.0, 0.82, 0.7))
	boss_box.add_child(boss_name)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(760, 16)
	boss_box.add_child(stack)
	boss_lag = _bar(Color(0.95, 0.75, 0.4, 0.8), Color(0, 0, 0, 0.7))
	stack.add_child(boss_lag)
	boss_bar = _bar(Color(0.72, 0.03, 0.06), Color(0, 0, 0, 0))
	stack.add_child(boss_bar)
	boss_box.visible = false

	map_hint = S.label("[M] map", 13, Color(0.75, 0.7, 0.65), 3)
	map_hint.anchor_left = 0.5
	map_hint.anchor_right = 0.5
	map_hint.offset_left = 268
	map_hint.offset_top = 54
	root.add_child(map_hint)

	fade = ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.color = Color(0.25, 0.0, 0.02, 0.0)
	root.add_child(fade)


func _bar(fg: Color, bg: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.85, 0.65, 0.4, 0.6) if bg.a > 0.0 else Color(0, 0, 0, 0)
	sb.set_border_width_all(1 if bg.a > 0.0 else 0)
	var sf := StyleBoxFlat.new()
	sf.bg_color = fg
	b.add_theme_stylebox_override("background", sb)
	b.add_theme_stylebox_override("fill", sf)
	b.max_value = 1.0
	b.step = 0.0
	return b


## The blood-mist crossing to the Final Night.
func fade_flash() -> void:
	fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(fade, "color:a", 0.0, 1.4)


func _process(delta: float) -> void:
	if director == null:
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	var show: bool = director.state != "idle" and director.state != "over"
	root.visible = show
	if not show:
		return
	# PERF: the text lines are formatted 10 times a second, not every frame
	_text_t -= real_dt
	if _text_t <= 0.0:
		_text_t = 0.1
		_update_texts()
	tint.color.a = lerpf(tint.color.a, director.outside_amount * (0.32 + 0.08 * sin(Time.get_ticks_msec() * 0.008)), minf(8.0 * real_dt, 1.0))
	_boss_bar(real_dt)


var _text_t := 0.0


func _update_texts() -> void:
	phase.text = director.phase_label()
	revive_label.text = ("REVIVES  %d" % director.revives) if director.revives > 0 else "NO REVIVES LEFT"
	var cleared := 0
	var combat := 0
	for poi in director.pois:
		if poi.is_combat():
			combat += 1
			if poi.cleared:
				cleared += 1
	tally.text = "Bosses slain  %d / 3\nSites cleared  %d / %d\nKills  %d" % [director.bosses_killed, cleared, combat, main.kills]
	prompt.text = director.prompt
	map_hint.text = "[Back] map" if main.hud.using_pad else "[M] map"
	map_hint.visible = main.hud.using_pad or not main.hud._touch() # touch has its own MAP button


func _boss_bar(real_dt: float) -> void:
	var b = director.boss if director.boss != null and is_instance_valid(director.boss) and not director.boss.dead else director.engaged_boss
	if b != null and is_instance_valid(b) and not b.dead and (b == director.boss or b.global_position.distance_to(main.player.global_position) < 45.0):
		boss_box.visible = true
		boss_name.text = b.boss_name
		var f: float = clampf(b.hp / maxf(b.max_hp, 1.0), 0.0, 1.0)
		boss_bar.value = f
		boss_lag.value = maxf(f, move_toward(boss_lag.value, f, real_dt * 0.25))
	else:
		boss_box.visible = false
		boss_lag.value = 1.0
