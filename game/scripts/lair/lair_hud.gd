extends CanvasLayer
## LAIR: the walkable lair's light HUD (lair_hub.gd): the place name and Sunmarks top left, the
## station prompt at the bottom ("[E]  WARDROBE  ·  change clothes"), popups, a controls hint and
## the fade to black when the Hunt begins. Answers the few calls player.gd makes on main.hud.

const S = preload("res://scripts/ui/ui_style.gd")
const MS = preload("res://scripts/menu/menu_style.gd")

var using_pad := false
var started := true
var title: Label
var marks: Label
var prompt_box: PanelContainer
var prompt: Label
var pop: Label
var hint: Label
var fade: ColorRect
var _pop_t := 0.0


func _ready() -> void:
	layer = 1
	add_to_group("hud_fade")
	var tl := VBoxContainer.new()
	tl.position = Vector2(40, 26)
	tl.add_theme_constant_override("separation", 0)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tl)
	title = S.title("THE UNDERCROFT", 30, S.GOLD)
	tl.add_child(title)
	marks = S.label("", 17, Color(1.0, 0.8, 0.4))
	tl.add_child(marks)
	prompt_box = PanelContainer.new()
	var sb := S.box(Color(0.03, 0.02, 0.022, 0.78), S.GOLD_DIM, 1, 3, 10)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	prompt_box.add_theme_stylebox_override("panel", sb)
	prompt_box.anchor_left = 0.5
	prompt_box.anchor_right = 0.5
	prompt_box.anchor_top = 1.0
	prompt_box.anchor_bottom = 1.0
	prompt_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_box.offset_bottom = -150
	prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_box.visible = false
	add_child(prompt_box)
	prompt = S.label("", 22, S.TEXT)
	prompt.add_theme_font_override("font", S.serif_bold())
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_box.add_child(prompt)
	pop = S.label("", 24, S.TEXT, 6)
	pop.add_theme_font_override("font", S.serif_bold())
	pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pop.anchor_top = 0.2
	pop.anchor_bottom = 0.2
	pop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop.modulate.a = 0.0
	add_child(pop)
	hint = S.label("", 14, MS.BONE_DIM, 3)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 40
	hint.offset_top = -40
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	_update_hint()


func set_marks(n: int, name_: String) -> void:
	marks.text = "%d %s" % [n, name_]


func set_prompt(t: String) -> void:
	prompt.text = t
	prompt_box.visible = t != ""


func popup(t: String) -> void:
	pop.text = t
	_pop_t = 2.6


func announce(t: String) -> void:
	popup(t)


func on_damage() -> void:
	pass


## Hide the walking HUD while a station panel is open (the panel takes over).
func set_walking(on: bool) -> void:
	title.get_parent().visible = on
	hint.visible = on
	if not on:
		prompt_box.visible = false


func key(pad_key: String, kb_key: String) -> String:
	var t := get_node_or_null("/root/Touch")
	if not using_pad and t != null and t.enabled:
		return "[USE]"
	return pad_key if using_pad else kb_key


func _update_hint() -> void:
	var t := get_node_or_null("/root/Touch")
	if not using_pad and t != null and t.enabled:
		hint.text = "Walk to a station and tap USE"
	elif using_pad:
		hint.text = "L stick  move     LT  run     D-pad down  crouch     Y  use     Start  menu"
	else:
		hint.text = "WASD  move     Shift  run     X  crouch     E  use     Esc  menu"


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	if pad != using_pad and (pad or event is InputEventKey or event is InputEventMouseButton):
		using_pad = pad
		_update_hint()


func _process(delta: float) -> void:
	if _pop_t > 0.0:
		_pop_t -= delta
		pop.modulate.a = clampf(_pop_t / 0.4, 0.0, 1.0)
