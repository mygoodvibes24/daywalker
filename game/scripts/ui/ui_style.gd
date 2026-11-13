extends RefCounted
## Shared gothic styling for the Coat (inventory) and Vigil (rank-up) screens:
## near-black panels, thin gold / crimson borders, serif titles where the system has one.

const GOLD := Color(0.86, 0.68, 0.36)
const GOLD_DIM := Color(0.55, 0.42, 0.22)
const CRIMSON := Color(0.72, 0.06, 0.1)
const INK := Color(0.045, 0.03, 0.035, 0.96)
const INK_LIGHT := Color(0.09, 0.06, 0.065, 0.95)
const TEXT := Color(0.9, 0.86, 0.82)
const TEXT_DIM := Color(0.62, 0.57, 0.54)

static var _serif: Font


## A serif system font (Georgia, Times, DejaVu Serif...) or the default font where there is none (web).
static func serif() -> Font:
	if _serif == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Cormorant Garamond", "Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif", "Noto Serif", "serif"])
		f.font_weight = 600
		_serif = f
	return _serif


static func box(bg: Color, border: Color, width := 1, radius := 2, pad := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func panel(pad := 18) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(INK, GOLD_DIM, 1, 3, pad)
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.shadow_size = 18
	p.add_theme_stylebox_override("panel", s)
	return p


static func label(text: String, size := 16, color := TEXT, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", outline)
	return l


static func title(text: String, size := 40, color := GOLD) -> Label:
	var l := label(text, size, color, 8)
	l.add_theme_font_override("font", serif())
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.0, 0.02, 0.9))
	return l


## A thin ornamental rule: crimson line with gold end caps.
static func rule(width := 0.0) -> Control:
	var c := HBoxContainer.new()
	c.add_theme_constant_override("separation", 0)
	c.custom_minimum_size = Vector2(width, 6)
	var cap_l := ColorRect.new()
	cap_l.color = GOLD
	cap_l.custom_minimum_size = Vector2(6, 2)
	cap_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := ColorRect.new()
	line.color = Color(CRIMSON.r, CRIMSON.g, CRIMSON.b, 0.8)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cap_r := cap_l.duplicate()
	c.add_child(cap_l)
	c.add_child(line)
	c.add_child(cap_r)
	return c


## Text button in the house style (gold border on focus/hover, crimson when pressed).
static func button(text: String, size := 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", serif())
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.37, 0.35))
	b.add_theme_stylebox_override("normal", box(INK_LIGHT, GOLD_DIM, 1, 2, 10))
	b.add_theme_stylebox_override("hover", box(Color(0.14, 0.07, 0.07), GOLD, 1, 2, 10))
	b.add_theme_stylebox_override("focus", box(Color(0.16, 0.06, 0.07), GOLD, 2, 2, 10))
	b.add_theme_stylebox_override("pressed", box(Color(0.35, 0.03, 0.05), GOLD, 2, 2, 10))
	b.add_theme_stylebox_override("disabled", box(Color(0.05, 0.04, 0.04, 0.9), Color(0.25, 0.2, 0.18), 1, 2, 10))
	return b


static func dim_backdrop() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.0, 0.0, 0.0, 0.72)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	return r
