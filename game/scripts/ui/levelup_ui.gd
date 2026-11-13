extends CanvasLayer
## The Vigil: spend Tithe at the Undercroft to rise a Communion rank, then pick one of three Vows.

signal closed

const S = preload("res://scripts/ui/ui_style.gd")

var main
var root: Control
var flash: ColorRect
var rank_view: VBoxContainer
var vow_view: VBoxContainer
var rank_num: Label
var tithe_lbl: Label
var cost_lbl: Label
var cost_bar: ProgressBar
var gains_lbl: Label
var vows_lbl: Label
var offer_btn: Button
var leave_btn: Button
var vow_sub: Label
var cards: HBoxContainer
var hint_lbl: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(S.dim_backdrop())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := S.panel(26)
	panel.custom_minimum_size = Vector2(860, 0)
	center.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	_build_rank_view(stack)
	_build_vow_view(stack)
	hint_lbl = S.label("", 14, S.TEXT_DIM, 3)
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(hint_lbl)
	flash = ColorRect.new()
	flash.color = Color(1.0, 0.85, 0.6, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)


func _build_rank_view(parent: Control) -> void:
	rank_view = VBoxContainer.new()
	rank_view.add_theme_constant_override("separation", 12)
	parent.add_child(rank_view)
	var t := S.title("THE  VIGIL", 46)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_view.add_child(t)
	var sub := S.label("Kneel at the Undercroft. Offer your Tithe. Deepen the blood.", 17, S.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_view.add_child(sub)
	rank_view.add_child(S.rule())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	rank_view.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	row.add_child(left)
	var rl := S.label("COMMUNION RANK", 14, S.GOLD_DIM)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(rl)
	rank_num = S.title("1", 96, Color(0.95, 0.2, 0.22))
	rank_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(rank_num)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	tithe_lbl = S.label("", 20, S.TEXT)
	right.add_child(tithe_lbl)
	cost_lbl = S.label("", 18, S.TEXT_DIM)
	right.add_child(cost_lbl)
	cost_bar = ProgressBar.new()
	cost_bar.show_percentage = false
	cost_bar.custom_minimum_size = Vector2(0, 10)
	cost_bar.add_theme_stylebox_override("background", S.box(Color(0, 0, 0, 0.7), S.GOLD_DIM, 1, 1))
	cost_bar.add_theme_stylebox_override("fill", S.box(S.CRIMSON, Color(1, 0.3, 0.3, 0.6), 0, 1))
	right.add_child(cost_bar)
	var gh := S.label("EACH RANK GRANTS", 13, S.GOLD_DIM)
	right.add_child(gh)
	gains_lbl = S.label("", 16, S.TEXT)
	gains_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(gains_lbl)
	rank_view.add_child(S.rule())
	vows_lbl = S.label("", 15, S.TEXT_DIM)
	vows_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vows_lbl.custom_minimum_size = Vector2(800, 0)
	rank_view.add_child(vows_lbl)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 24)
	rank_view.add_child(btns)
	offer_btn = S.button("Offer Tithe", 22)
	offer_btn.custom_minimum_size = Vector2(260, 52)
	offer_btn.pressed.connect(_on_offer)
	btns.add_child(offer_btn)
	leave_btn = S.button("Rise and leave", 20)
	leave_btn.custom_minimum_size = Vector2(220, 52)
	leave_btn.pressed.connect(close)
	btns.add_child(leave_btn)
	offer_btn.focus_neighbor_right = offer_btn.get_path_to(leave_btn)
	leave_btn.focus_neighbor_left = leave_btn.get_path_to(offer_btn)


func _build_vow_view(parent: Control) -> void:
	vow_view = VBoxContainer.new()
	vow_view.add_theme_constant_override("separation", 14)
	vow_view.visible = false
	parent.add_child(vow_view)
	var t := S.title("CHOOSE  A  VOW", 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vow_view.add_child(t)
	vow_sub = S.label("", 17, S.TEXT_DIM)
	vow_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vow_view.add_child(vow_sub)
	vow_view.add_child(S.rule())
	cards = HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 20)
	vow_view.add_child(cards)


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if main.progression.vow_choices.is_empty():
		_show_rank()
	else:
		_show_vows()


func close() -> void:
	if not visible or not main.progression.vow_choices.is_empty():
		return # a Vow must be chosen first
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	main.player.block_attack()
	closed.emit()


func _show_rank() -> void:
	vow_view.visible = false
	rank_view.visible = true
	var prog = main.progression
	rank_num.text = str(prog.level)
	tithe_lbl.text = "Tithe carried   %d" % prog.tithe
	if prog.level >= prog.MAX_LEVEL:
		cost_lbl.text = "You have risen as far as the blood allows."
		cost_bar.max_value = 1
		cost_bar.value = 1
	else:
		cost_lbl.text = "Offering for rank %d   %d" % [prog.level + 1, prog.next_cost()]
		cost_bar.max_value = prog.next_cost()
		cost_bar.value = mini(prog.tithe, prog.next_cost())
	gains_lbl.text = prog.level_gain_text() + "\n+ one Vow, chosen from three"
	var names: Array = []
	for id in prog.vows:
		names.append(prog.VOWS[id].name)
	vows_lbl.text = "VOWS KEPT   " + ("none yet" if names.is_empty() else "  ·  ".join(names))
	offer_btn.disabled = not prog.can_level()
	offer_btn.focus_mode = Control.FOCUS_NONE if offer_btn.disabled else Control.FOCUS_ALL
	(offer_btn if not offer_btn.disabled else leave_btn).grab_focus()
	_update_hint()


func _show_vows() -> void:
	rank_view.visible = false
	vow_view.visible = true
	var prog = main.progression
	vow_sub.text = "Rank %d. The blood remembers what you promise it." % prog.level
	for c in cards.get_children():
		cards.remove_child(c)
		c.queue_free()
	var btns: Array[Button] = []
	for id in prog.vow_choices:
		var b := _vow_card(id, prog.VOWS[id])
		cards.add_child(b)
		btns.append(b)
	for i in btns.size():
		btns[i].focus_neighbor_left = btns[i].get_path_to(btns[(i - 1 + btns.size()) % btns.size()])
		btns[i].focus_neighbor_right = btns[i].get_path_to(btns[(i + 1) % btns.size()])
	if not btns.is_empty():
		btns[0].grab_focus()
	_update_hint()


func _vow_card(id: String, v: Dictionary) -> Button:
	var b := S.button("", 18)
	b.custom_minimum_size = Vector2(250, 290)
	b.add_theme_stylebox_override("normal", S.box(S.INK_LIGHT, S.GOLD_DIM, 1, 3, 14))
	b.add_theme_stylebox_override("focus", S.box(Color(0.2, 0.04, 0.06), S.GOLD, 2, 3, 14))
	b.add_theme_stylebox_override("hover", S.box(Color(0.15, 0.05, 0.06), S.GOLD, 1, 3, 14))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_right = -18
	box.offset_top = 22
	box.offset_bottom = -18
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var sigil := S.title("✠", 40, S.CRIMSON)
	sigil.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sigil)
	var n := S.title(v.name, 26)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(n)
	box.add_child(S.rule())
	var d := S.label(v.desc, 17, S.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(d)
	for c in box.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(_on_vow.bind(id))
	return b


func _update_hint() -> void:
	var pad: bool = main.hud.using_pad
	if vow_view.visible:
		hint_lbl.text = ("[A] choose" if pad else "[Click / Enter] choose") + "   ·   a Vow must be taken"
	else:
		hint_lbl.text = "[A] select   [B] leave" if pad else "[Click / Enter] select   [Esc / E] leave"


func _on_offer() -> void:
	var prog = main.progression
	if not prog.level_up():
		return
	main.hud.announce("RANK %d\nThe blood deepens" % prog.level)
	main.hud.popup(prog.level_gain_text())
	main.rumble(0.4, 0.7, 0.4)
	if main.fx != null:
		main.fx.level_burst(main.player.global_position)
	flash.color.a = 0.85
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.9).set_ease(Tween.EASE_OUT)
	_show_vows()


func _on_vow(id: String) -> void:
	var prog = main.progression
	prog.choose_vow(id)
	main.hud.popup("VOW TAKEN  ·  " + prog.VOWS[id].name.to_upper())
	_show_rank()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact") or event.is_action_pressed("inventory"):
		if vow_view.visible:
			get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
		close()
