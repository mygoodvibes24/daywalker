class_name RiteUI
extends CanvasLayer
## The Blood Rite: pick one of three run-scoped boons after a boss falls (blood_rite.gd).
## Mouse (click a card), keyboard (arrows + Enter, or 1 / 2 / 3), gamepad (d-pad + A) and touch
## (tap a card). The world is paused while it is up; a choice must be made to close it. The cards
## ignore input for a moment after opening, so a mashed attack can't pick one blind.

signal chosen(id: String)

const S = preload("res://scripts/ui/ui_style.gd")
const Rites = preload("res://scripts/hunt/blood_rite.gd")
const ARM_DELAY := 0.7 # seconds before the cards take input

var main: Main
var root: Control
var flash: ColorRect
var title_lbl: Label
var sub_lbl: Label
var cards: HBoxContainer
var hint_lbl: Label
var taken_lbl: Label
var buttons: Array[Button] = []
var offer: Array = []
var armed_at := 0


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := S.dim_backdrop()
	dim.color = Color(0.08, 0.0, 0.01, 0.8)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := S.panel(24)
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	title_lbl = S.title("THE  BLOOD  RITE", 46, Color(0.95, 0.2, 0.22))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_lbl)
	sub_lbl = S.label("", 18, S.TEXT_DIM)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.custom_minimum_size = Vector2(840, 0)
	v.add_child(sub_lbl)
	v.add_child(S.rule())
	cards = HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 20)
	v.add_child(cards)
	taken_lbl = S.label("", 15, S.TEXT_DIM)
	taken_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	taken_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	taken_lbl.custom_minimum_size = Vector2(840, 0)
	v.add_child(taken_lbl)
	hint_lbl = S.label("", 15, S.TEXT_DIM, 3)
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint_lbl)
	flash = ColorRect.new()
	flash.color = Color(0.9, 0.05, 0.08, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)


func is_open() -> bool:
	return visible


## Show the three offered Rites. `from` names what died ("The Hollow Alpha").
func open(choices: Array, from := "") -> void:
	if choices.is_empty():
		return
	offer = choices.duplicate()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sub_lbl.text = ("%s is ash. " % from if from != "" else "") + "Drink what it was, and choose what its blood makes of you."
	var taken: Array = []
	if main != null and main.progression != null:
		for id in main.progression.rites:
			taken.append(Rites.name_of(id))
	taken_lbl.text = "" if taken.is_empty() else "RITES ALREADY IN YOUR BLOOD   " + "  ·  ".join(taken)
	taken_lbl.visible = not taken.is_empty()
	for c in cards.get_children():
		cards.remove_child(c)
		c.queue_free()
	buttons.clear()
	for i in offer.size():
		var b := _card(i, offer[i], Rites.RITES[offer[i]])
		cards.add_child(b)
		buttons.append(b)
	for i in buttons.size():
		buttons[i].focus_neighbor_left = buttons[i].get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		buttons[i].focus_neighbor_right = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])
	buttons[0].grab_focus.call_deferred()
	armed_at = Time.get_ticks_msec() + int(ARM_DELAY * 1000.0)
	_update_hint()
	flash.color.a = 0.6
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.8).set_ease(Tween.EASE_OUT)
	Audio.play("level_up", -4.0) # AUDIO HOOK


func _card(i: int, id: String, r: Dictionary) -> Button:
	var b := S.button("", 18)
	b.custom_minimum_size = Vector2(270, 300)
	b.add_theme_stylebox_override("normal", S.box(Color(0.1, 0.03, 0.04, 0.96), Color(0.5, 0.08, 0.1), 1, 3, 14))
	b.add_theme_stylebox_override("focus", S.box(Color(0.24, 0.03, 0.05), S.GOLD, 2, 3, 14))
	b.add_theme_stylebox_override("hover", S.box(Color(0.18, 0.04, 0.05), S.GOLD, 1, 3, 14))
	b.add_theme_stylebox_override("pressed", S.box(Color(0.4, 0.02, 0.05), S.GOLD, 2, 3, 14))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_right = -18
	box.offset_top = 16
	box.offset_bottom = -14
	box.add_theme_constant_override("separation", 8)
	b.add_child(box)
	var key := S.label("%d" % (i + 1), 14, S.GOLD_DIM)
	key.name = "Key"
	box.add_child(key)
	var sigil := S.title(String(r.get("sigil", "✠")), 40, Color(0.95, 0.15, 0.18))
	sigil.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sigil)
	var tag := S.label(String(r.get("tag", "")), 13, S.GOLD_DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)
	var n := S.title(String(r.name), 26)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(n)
	box.add_child(S.rule())
	var d := S.label(String(r.desc), 17, S.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(d)
	for c in box.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(_pick.bind(id))
	return b


func armed() -> bool:
	return Time.get_ticks_msec() >= armed_at


func _update_hint() -> void:
	var pad: bool = main != null and main.hud != null and main.hud.using_pad
	var touch: bool = DisplayServer.is_touchscreen_available() and not pad
	if pad:
		hint_lbl.text = "[D-pad] choose   [A] take the Rite"
	elif touch:
		hint_lbl.text = "Tap a Rite to take it"
	else:
		hint_lbl.text = "[Click] or [1] [2] [3]   ·   [←] [→] and [Enter]"
	hint_lbl.text += "   ·   one Rite must be taken"


## Take one of the offered Rites (also the test entry point).
func pick(id: String) -> bool:
	if not visible or not id in offer:
		return false
	var prog = main.progression
	if not prog.choose_rite(id):
		return false
	visible = false
	get_tree().paused = false
	if not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	main.ui_block_until = Time.get_ticks_msec() + 300
	if main.player != null:
		main.player.block_attack()
	main.hud.announce("BLOOD RITE\n" + Rites.name_of(id).to_upper())
	main.rumble(0.4, 0.7, 0.4)
	if main.fx != null and main.player != null:
		main.fx.level_burst(main.player.global_position)
	chosen.emit(id)
	return true


func _pick(id: String) -> void:
	if armed():
		pick(id)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_3:
			get_viewport().set_input_as_handled()
			var i := k - KEY_1
			if i < offer.size() and armed():
				pick(offer[i])
			return
	# nothing else gets through while the rite is up (Esc, the Coat, the map...)
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_accept") and not armed():
		get_viewport().set_input_as_handled()
