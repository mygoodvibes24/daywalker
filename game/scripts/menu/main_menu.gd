extends Node
## The main menu (res://scenes/main_menu.tscn, the project's main scene): the live lair
## set behind (lair_menu_set.tscn), the title and menu in the dark left third, and the
## Controls / Options screens. Start fades out and loads the game on a thread with a
## "Loading..." indicator (synchronously on the web), then hands over to main.tscn with
## main.gd's `started_once` set, so the game begins at once without its title overlay.

const MS = preload("res://scripts/menu/menu_style.gd")
const S = preload("res://scripts/ui/ui_style.gd")
const OptionsPanel = preload("res://scripts/menu/options_panel.gd")
const ControlsPanel = preload("res://scripts/menu/controls_panel.gd")
const MainScript = preload("res://scripts/main.gd")
const GAME_SCENE := "res://scenes/main.tscn"

var ui: CanvasLayer
var menu_box: Control # the title + buttons column
var buttons: Array[Button] = []
var options: Control
var controls: Control
var fade: ColorRect
var loading: Label
var hint: Label
var using_pad := false
var state := "menu" # menu, options, controls, loading
var load_threaded := false
var last_focus: Control
var load_t := 0.0


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	buttons[0].grab_focus.call_deferred()
	Audio.set_music("menu"); Dialogue.start_menu_banter() # AUDIO HOOK (starts after the first click on the web)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 1.6).set_trans(Tween.TRANS_SINE)


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "MenuUI"
	ui.layer = 10
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# darken the left third further so the text always reads, plus a soft bottom band
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.texture = _gradient([0.0, 0.3, 0.52], [Color(0, 0, 0, 0.78), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0)], false)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(shade)
	var band := TextureRect.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.texture = _gradient([0.0, 0.8, 1.0], [Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55)], true)
	band.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(band)

	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 6)
	menu_box.anchor_left = 0.0
	menu_box.anchor_top = 0.5
	menu_box.anchor_bottom = 0.5
	menu_box.offset_left = 76
	menu_box.offset_top = -230
	menu_box.offset_bottom = 230
	menu_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(menu_box)
	menu_box.add_child(MS.lockup(86))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 46)
	menu_box.add_child(gap)
	var entries := [["Start", _on_start], ["Controls", _show.bind("controls")], ["Options", _show.bind("options")]]
	if not OS.has_feature("web"):
		entries.append(["Quit", func(): get_tree().quit()])
	for e in entries:
		var b := MS.item(e[0], 30)
		b.custom_minimum_size = Vector2(300, 0)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.pressed.connect(e[1])
		b.focus_entered.connect(Audio.play.bind("ui_hover", -9.0, 0.05)); b.pressed.connect(Audio.play.bind("ui_click", -3.0, 0.0)) # AUDIO HOOK
		menu_box.add_child(b)
		buttons.append(b)
	for i in buttons.size(): # wrap around with up / down
		buttons[i].focus_neighbor_top = buttons[posmod(i - 1, buttons.size())].get_path()
		buttons[i].focus_neighbor_bottom = buttons[(i + 1) % buttons.size()].get_path()
		buttons[i].focus_neighbor_left = buttons[i].get_path()
		buttons[i].focus_neighbor_right = buttons[i].get_path()

	hint = S.label(MS.hint(false), 14, MS.BONE_DIM, 3)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 98
	hint.offset_top = -46
	root.add_child(hint)

	for which in ["options", "controls"]:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.visible = false
		root.add_child(center)
		var p: PanelContainer = OptionsPanel.new() if which == "options" else ControlsPanel.new()
		center.add_child(p)
		p.back.connect(_back)
		if which == "options":
			options = center
		else:
			controls = center

	loading = S.label("Loading...", 22, MS.BONE, 4)
	loading.add_theme_font_override("font", S.serif())
	loading.anchor_left = 1.0
	loading.anchor_right = 1.0
	loading.anchor_top = 1.0
	loading.anchor_bottom = 1.0
	loading.offset_left = -240
	loading.offset_top = -70
	loading.visible = false
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	root.add_child(loading) # above the fade


func _gradient(offsets: Array, colors: Array, vertical: bool) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 8 if vertical else 256
	tex.height = 256 if vertical else 8
	tex.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	return tex


# ---------------------------------------------------------------- screens
func _show(which: String) -> void:
	if state != "menu":
		return
	last_focus = get_viewport().gui_get_focus_owner()
	state = which
	menu_box.visible = false
	options.visible = which == "options"
	controls.visible = which == "controls"


func _back() -> void:
	if state != "options" and state != "controls":
		return
	state = "menu"
	options.visible = false
	controls.visible = false
	menu_box.visible = true
	var f: Control = last_focus if is_instance_valid(last_focus) else buttons[0]
	f.grab_focus.call_deferred()


## Screenshot / test helper: open a screen by name.
func debug_show(which: String) -> void:
	if which == "loading":
		_on_start()
	else:
		_show(which)


func _unhandled_input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	if pad != using_pad and (pad or event is InputEventKey or event is InputEventMouseButton):
		using_pad = pad
		hint.text = MS.hint(pad)
	if state == "loading":
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()
	elif get_viewport().gui_get_focus_owner() == null and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_accept")):
		# keyboard / pad wakes focus again after the mouse wandered off
		get_viewport().set_input_as_handled()
		(buttons[0] if state == "menu" else (options if state == "options" else controls).get_child(0).first_focus).grab_focus()


# ---------------------------------------------------------------- start the game
func _on_start() -> void:
	if state == "loading":
		return
	state = "loading"
	Dialogue.stop_menu_banter(); Audio.set_music("", 1.2) # AUDIO HOOK
	for b in buttons:
		b.disabled = true
		b.release_focus()
	MainScript.started_once = true # main.gd starts at once, no title overlay
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_begin_load)


func _begin_load() -> void:
	loading.visible = true
	# browsers may lack threads (no SharedArrayBuffer): load synchronously there
	load_threaded = not OS.has_feature("web") and OS.get_processor_count() > 1
	if load_threaded and ResourceLoader.load_threaded_request(GAME_SCENE, "PackedScene", true) == OK:
		return
	load_threaded = false
	# give the "Loading..." label one frame on screen before blocking
	await get_tree().process_frame
	await get_tree().process_frame
	_enter(load(GAME_SCENE) as PackedScene)


func _process(delta: float) -> void:
	if loading != null and loading.visible:
		load_t += delta
		loading.modulate.a = 0.55 + 0.45 * sin(load_t * 4.0)
		loading.text = "Loading" + ".".repeat(1 + int(load_t * 2.0) % 3)
	if state != "loading" or not load_threaded:
		return
	var st := ResourceLoader.load_threaded_get_status(GAME_SCENE)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		load_threaded = false
		_enter(ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene)
	elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		load_threaded = false
		_enter(load(GAME_SCENE) as PackedScene)


func _enter(scene: PackedScene) -> void:
	if scene == null:
		push_error("main menu: could not load " + GAME_SCENE)
		return
	get_tree().change_scene_to_packed(scene)
