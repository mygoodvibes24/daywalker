extends CanvasLayer
## The pause menu: Esc in play (or "Pause" / pad Back inside the Coat) pauses the world,
## frees the mouse and offers Resume / Options / Controls / Quit to Menu. The Options and
## Controls screens are the same ones the main menu uses. Esc / pad B steps back, then resumes.

const MS = preload("res://scripts/menu/menu_style.gd")
const S = preload("res://scripts/ui/ui_style.gd")
const OptionsPanel = preload("res://scripts/menu/options_panel.gd")
const ControlsPanel = preload("res://scripts/menu/controls_panel.gd")
const MENU_SCENE := "res://scenes/main_menu.tscn"

var main
var root: Control
var list: Control
var buttons: Array[Button] = []
var options: Control
var controls: Control
var hint: Label
var screen := "" # "", list, options, controls


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := S.dim_backdrop()
	dim.color = Color(0.0, 0.0, 0.0, 0.66)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	center.add_child(list)
	var t := S.title("PAUSED", 54, MS.CRIMSON)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(t)
	var r := S.rule(300)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	list.add_child(r)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	list.add_child(gap)
	for e in [["Resume", close], ["Options", _show.bind("options")], ["Controls", _show.bind("controls")], ["Quit to Menu", _quit_to_menu]]:
		var b := MS.item(e[0], 28)
		b.custom_minimum_size = Vector2(320, 0)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(e[1])
		list.add_child(b)
		buttons.append(b)
	for i in buttons.size():
		buttons[i].focus_neighbor_top = buttons[posmod(i - 1, buttons.size())].get_path()
		buttons[i].focus_neighbor_bottom = buttons[(i + 1) % buttons.size()].get_path()
	hint = S.label("Esc / B  resume", 14, MS.BONE_DIM, 3)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(hint)
	for which in ["options", "controls"]:
		var c := CenterContainer.new()
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.visible = false
		root.add_child(c)
		var p: PanelContainer = OptionsPanel.new() if which == "options" else ControlsPanel.new()
		c.add_child(p)
		p.back.connect(_back)
		if which == "options":
			options = c
		else:
			controls = c
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show("list")


func close() -> void:
	if not visible:
		return
	visible = false
	screen = ""
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if main != null:
		main.player.block_attack()
		main._on_menu_closed()


func _show(which: String) -> void:
	screen = which
	list.visible = which == "list"
	options.visible = which == "options"
	controls.visible = which == "controls"
	if which == "list":
		buttons[0].grab_focus.call_deferred()


func _back() -> void:
	var from := screen
	_show("list")
	var i := 1 if from == "options" else 2
	buttons[i].grab_focus.call_deferred()


func _quit_to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# keep the Coat / Vigil / rain bindings from firing underneath
	if event.is_action_pressed("inventory") or event.is_action_pressed("toggle_rain"):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if screen == "list":
			close()
		else:
			_back()
	elif get_viewport().gui_get_focus_owner() == null and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up")):
		get_viewport().set_input_as_handled()
		if screen == "list":
			buttons[0].grab_focus()
		else:
			(options if screen == "options" else controls).get_child(0).first_focus.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# Esc opens it (pad B is Blood Dash, so the controller reaches it through the Coat)
	if visible or main == null or not main.started or main.game_over or main.menu_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		open()
