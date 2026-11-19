extends RefCounted
## Title-screen styling shared by the main menu and the pause menu: the crimson / bone
## title lockup and the text-only menu buttons (a crimson bar and glow on focus).

const S = preload("res://scripts/ui/ui_style.gd")
const CRIMSON := Color(0.78, 0.06, 0.09)
const CRIMSON_HI := Color(0.95, 0.16, 0.16)
const BONE := Color(0.91, 0.87, 0.79)
const BONE_DIM := Color(0.62, 0.58, 0.52)


## "DAYWALKER" over "BLOOD AND MOON", left aligned, with a thin crimson rule between.
static func lockup(title_size := 86) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var t := Label.new()
	t.text = "DAYWALKER"
	t.add_theme_font_override("font", S.serif_bold())
	t.add_theme_font_size_override("font_size", title_size)
	t.add_theme_color_override("font_color", CRIMSON)
	t.add_theme_color_override("font_outline_color", Color(0.12, 0.0, 0.01, 0.95))
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_shadow_color", Color(0.6, 0.0, 0.03, 0.35))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 0)
	t.add_theme_constant_override("shadow_outline_size", 26)
	v.add_child(t)
	var rule := HBoxContainer.new()
	rule.add_theme_constant_override("separation", 10)
	var l1 := ColorRect.new()
	l1.color = Color(CRIMSON.r, CRIMSON.g, CRIMSON.b, 0.85)
	l1.custom_minimum_size = Vector2(64, 1)
	l1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.add_child(l1)
	var sub := Label.new()
	sub.text = "B L O O D    A N D    M O O N"
	sub.add_theme_font_override("font", S.serif())
	sub.add_theme_font_size_override("font_size", maxi(14, title_size / 4))
	sub.add_theme_color_override("font_color", BONE)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub.add_theme_constant_override("outline_size", 4)
	rule.add_child(sub)
	var l2 := l1.duplicate()
	rule.add_child(l2)
	v.add_child(rule)
	return v


## A text-only menu entry: bone white, crimson with a left bar when focused or hovered.
static func item(text: String, size := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", S.serif())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", CRIMSON_HI)
	b.add_theme_color_override("font_focus_color", CRIMSON_HI)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", BONE_DIM)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	b.add_theme_constant_override("outline_size", 5)
	var idle := StyleBoxEmpty.new()
	idle.content_margin_left = 22
	idle.content_margin_right = 22
	idle.content_margin_top = 4
	idle.content_margin_bottom = 4
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(0.4, 0.02, 0.04, 0.28)
	lit.border_color = CRIMSON
	lit.border_width_left = 3
	lit.content_margin_left = 22
	lit.content_margin_right = 22
	lit.content_margin_top = 4
	lit.content_margin_bottom = 4
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, idle)
	for st in ["hover", "focus", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, lit)
	b.mouse_entered.connect(func():
		if not b.disabled:
			b.grab_focus())
	return b


## A small footer hint ("[A] Select   [B] Back") that follows the last-used device.
static func hint(pad: bool) -> String:
	return "A  select      B  back" if pad else "Enter / click  select      Esc  back"
