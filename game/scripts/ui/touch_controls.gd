extends CanvasLayer
## Touch controls (autoload "Touch"): a floating virtual stick on the left, camera drag on the
## right, and round buttons for attack (hold for the charged slash), Blood Dash, jump,
## bite / take, parry, a sprint toggle, the Coat, the map and pause. Shown only on touch
## devices (or with --touch / ?touch), and only while Sol is in play.
##
## In menus (the title screen, the hub, the Coat, pause, results...) touches stay emulated
## as mouse clicks so every Button works by tapping. In play that emulation is switched off,
## so a finger on a button never also fires the LMB attack, and every touch lands here.

const STICK_RADIUS := 72.0
const LOOK_SPEED := 0.0065 # radians per logical pixel of drag
const GOLD := Color(0.86, 0.68, 0.36)
const INK := Color(0.05, 0.03, 0.035)

var enabled := false
var active := false # Sol is in play: the layer shows and owns the touches
var pad: Control
var font: Font
## each: {id, label, actions, pos (from the bottom-right or top-right corner), r, anchor, toggle}
var buttons: Array = []
var held := {} # finger index -> button id
var stick_finger := -1
var stick_origin := Vector2.ZERO
var stick_vec := Vector2.ZERO
var look_finger := -1
var sprint_on := false
var _main: Node = null


func _ready() -> void:
	layer = 50 # over the HUD (1), the Hunt HUD (5) and the map, under the menus' own layers
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	enabled = DisplayServer.is_touchscreen_available() or "--touch" in args or _url_flag("touch")
	if "--notouch" in args or _url_flag("notouch"):
		enabled = false
	font = preload("res://scripts/ui/ui_style.gd").serif()
	pad = Control.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.draw.connect(_draw_pad)
	add_child(pad)
	pad.visible = false
	_add("attack", "STRIKE", ["attack"], Vector2(-112, -112), 60.0)
	_add("dash", "DASH", ["dash"], Vector2(-246, -74), 42.0)
	_add("jump", "JUMP", ["jump"], Vector2(-84, -258), 42.0)
	_add("parry", "PARRY", ["parry"], Vector2(-226, -196), 38.0)
	_add("bite", "BITE", ["bite", "interact"], Vector2(-352, -64), 36.0)
	_add("sprint", "RUN", ["sprint"], Vector2(-356, -170), 34.0, true)
	_add("pause", "II", ["@pause"], Vector2(-46, 150), 26.0, false, "top")
	_add("map", "MAP", ["hunt_map"], Vector2(-114, 150), 26.0, false, "top")
	_add("coat", "COAT", ["inventory"], Vector2(-182, 150), 26.0, false, "top")


func _add(id: String, label: String, actions: Array, pos: Vector2, r: float, toggle := false, anchor := "bottom") -> void:
	buttons.append({"id": id, "label": label, "actions": actions, "pos": pos, "r": r, "toggle": toggle, "anchor": anchor})


func _url_flag(flag: String) -> bool:
	if not OS.has_feature("web"):
		return false
	var q := str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
	for part in q.split("&", false):
		if part.split("=")[0] == flag:
			return true
	return false


## The running game scene (main.gd), or null in the menu.
func _game() -> Node:
	var s := get_tree().current_scene
	if s != null and s.get("player") != null and s.has_method("menu_open"):
		return s
	return null


func _in_play() -> bool:
	_main = _game()
	if _main == null or not _main.started or _main.game_over or get_tree().paused or _main.menu_open():
		return false
	var h = _main.get("hunt")
	if h != null and h.state in ["idle", "over", "intro"]: # the intro: a tap skips it (QA2 #13)
		return false
	return true


func _process(_delta: float) -> void:
	if not enabled:
		return
	var now := _in_play()
	if now != active:
		active = now
		_release_all()
		# menus get taps as mouse clicks; play gets raw touches only
		Input.emulate_mouse_from_touch = not active
		if active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pad.visible = active
	if active:
		pad.queue_redraw()


func _button_center(b: Dictionary) -> Vector2:
	var sz := pad.size
	var p: Vector2 = b.pos
	if b.anchor == "top":
		return Vector2(sz.x + p.x, p.y)
	return sz + p


func _hit(pos: Vector2) -> Dictionary:
	for b in buttons:
		if pos.distance_to(_button_center(b)) <= b.r * 1.2:
			return b
	return {}


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		get_viewport().set_input_as_handled()
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		get_viewport().set_input_as_handled()
		if d.index == stick_finger:
			_stick_to(d.position)
		elif d.index == look_finger and _main != null:
			var pl = _main.player
			pl.cam_yaw -= d.relative.x * LOOK_SPEED * Settings.mouse_sensitivity
			pl.cam_pitch = clampf(pl.cam_pitch - d.relative.y * LOOK_SPEED * Settings.mouse_sensitivity * Settings.y_sign(), -1.1, 0.35)


func _touch_down(idx: int, pos: Vector2) -> void:
	var b := _hit(pos)
	if not b.is_empty():
		if b.toggle:
			sprint_on = not sprint_on
			_send(b.actions, sprint_on)
		else:
			held[idx] = b.id
			_send(b.actions, true)
		return
	if pos.x < pad.size.x * 0.42 and stick_finger < 0:
		stick_finger = idx
		stick_origin = pos
		_stick_to(pos)
	elif look_finger < 0:
		look_finger = idx


func _touch_up(idx: int) -> void:
	if held.has(idx):
		var id: String = held[idx]
		held.erase(idx)
		for b in buttons:
			if b.id == id:
				_send(b.actions, false)
	if idx == stick_finger:
		stick_finger = -1
		stick_vec = Vector2.ZERO
		_apply_stick()
		if sprint_on: # letting go of the stick ends the run
			sprint_on = false
			_send(["sprint"], false)
	if idx == look_finger:
		look_finger = -1


func _stick_to(pos: Vector2) -> void:
	var v := (pos - stick_origin) / STICK_RADIUS
	if v.length() > 1.0:
		stick_origin = pos - v.normalized() * STICK_RADIUS # the stick base follows the thumb
		v = v.normalized()
	stick_vec = v
	_apply_stick()


func _apply_stick() -> void:
	var v := stick_vec if stick_vec.length() > 0.12 else Vector2.ZERO
	_axis("move_right", maxf(v.x, 0.0))
	_axis("move_left", maxf(-v.x, 0.0))
	_axis("move_back", maxf(v.y, 0.0))
	_axis("move_forward", maxf(-v.y, 0.0))


func _axis(action: String, s: float) -> void:
	if not InputMap.has_action(action):
		return
	if s > 0.0:
		Input.action_press(action, s)
	else:
		Input.action_release(action)


## Buttons go through real InputEventActions, so _input / _unhandled_input handlers (the map,
## the Coat, pause, skipping the Descent) see them exactly like a key press.
func _send(actions: Array, pressed: bool) -> void:
	for a in actions:
		if a == "@pause": # the pause menu opens on the Esc key itself, so call it directly
			if pressed and _main != null:
				_main.open_pause()
			continue
		if not InputMap.has_action(a):
			continue
		var ev := InputEventAction.new()
		ev.action = a
		ev.pressed = pressed
		ev.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(ev)


func _release_all() -> void:
	for idx in held.keys():
		_touch_up(idx)
	held.clear()
	stick_finger = -1
	look_finger = -1
	stick_vec = Vector2.ZERO
	if InputMap.has_action("move_left"):
		_apply_stick()
	if sprint_on:
		sprint_on = false
		_send(["sprint"], false)


# ---------------------------------------------------------------- drawing
func _draw_pad() -> void:
	var sz := pad.size
	# the stick: resting ghost bottom-left, or under the thumb
	var base := stick_origin if stick_finger >= 0 else Vector2(150, sz.y - 150)
	var a := 0.5 if stick_finger >= 0 else 0.22
	pad.draw_circle(base, STICK_RADIUS, Color(INK.r, INK.g, INK.b, a * 0.8))
	pad.draw_arc(base, STICK_RADIUS, 0.0, TAU, 48, Color(GOLD.r, GOLD.g, GOLD.b, a), 2.0, true)
	pad.draw_circle(base + stick_vec * STICK_RADIUS, 30.0, Color(0.75, 0.08, 0.1, a + 0.2))
	var pressed_ids := held.values()
	for b in buttons:
		var c := _button_center(b)
		var on: bool = b.id in pressed_ids or (b.toggle and sprint_on)
		var r: float = b.r
		pad.draw_circle(c, r, Color(0.55, 0.04, 0.07, 0.75) if on else Color(INK.r, INK.g, INK.b, 0.5))
		pad.draw_arc(c, r, 0.0, TAU, 40, Color(GOLD.r, GOLD.g, GOLD.b, 0.95 if on else 0.6), 2.0, true)
		var fs := int(clampf(r * 0.42, 12.0, 22.0))
		var w := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		pad.draw_string_outline(font, c + Vector2(-w * 0.5, fs * 0.35), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
		pad.draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.9, 0.82))
