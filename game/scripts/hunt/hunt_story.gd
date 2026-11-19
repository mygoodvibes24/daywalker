extends CanvasLayer
## The Hunt's story framing (critic R1, S1): why Sol is out there and who he's hunting.
##  - the INTRO, before the first Hunt only: a title card, then Nia's briefing from the
##    Undercroft over a slow night flyover of Port Vesper (voiced, subtitled by Dialogue, with
##    a case-file caption per beat). Skippable with attack / jump / interact / Esc / a tap.
##  - a NIGHT CARD at the start of each day (and at the Final Night's dusk): tonight's boss,
##    and why. Non-blocking; fades by itself.
##  - the results EPILOGUE line (epilogue(), read by ui/results_screen.gd).
## hunt_director.gd owns when these happen; this file only draws and sequences them.

const S = preload("res://scripts/ui/ui_style.gd")
const MS = preload("res://scripts/menu/menu_style.gd")
const SEEN_PATH := "user://story.cfg"

## [voice line id (data/dialogue.json), caption title, caption body]
const BRIEFING := [
	["intro_brief_1", "THE ACCORD IS BROKEN", "Two hundred years of peace. Then Wren Hollow's husband turns up bitten,\nand a duke of the Velvet Court turns up torn apart by claws."],
	["intro_brief_2", "BOTH SIDES BLAME YOU", "Your scent was at both scenes. The Court and the Pack agree on one thing."],
	["curfew_broadcast", "THE RED CURFEW", "Count Lucien seals the city at dusk. Each night the blood-fog closes,\nand whatever is inside it hunts."],
	["intro_brief_3", "THREE NIGHTS", "Survive the Curfew. Cut down whoever they send.\nFind out who is framing you."],
]

## Tests and screenshots: force the intro (or never show it).
static var force_intro := false
static var never_intro := false

var director
var main
var playing := false
var _done: Callable
var _root: Control
var _dim: ColorRect
var _title_box: Control
var _caption: VBoxContainer
var _cap_title: Label
var _cap_body: Label
var _comms: PanelContainer
var _bars: Array[ColorRect] = []
var _step := -1
var _step_t := 0.0
var _step_len := 0.0
var _t := 0.0
var _cam: Camera3D
var _saved_tod := 0.3
var _card: PanelContainer
var _card_tw: Tween


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


# ---------------------------------------------------------------- the intro
## True the first time (per save), unless a test / CI / headless run.
static func intro_wanted(short: bool) -> bool:
	if force_intro:
		return true
	if never_intro or short or DisplayServer.get_name() == "headless" or "--nointro" in OS.get_cmdline_user_args():
		return false
	var mm = load("res://scripts/menu/main_menu.gd")
	if mm != null and mm.has_method("_autohunt_wanted") and mm._autohunt_wanted():
		return false # the CI web render check wants gameplay on screen
	var cf := ConfigFile.new()
	return cf.load(SEEN_PATH) != OK or not cf.get_value("story", "intro_seen", false)


static func mark_seen() -> void:
	var cf := ConfigFile.new()
	cf.load(SEEN_PATH)
	cf.set_value("story", "intro_seen", true)
	cf.save(SEEN_PATH)


func play_intro(done: Callable) -> void:
	_done = done
	playing = true
	_t = 0.0
	_step = -1
	_build_intro()
	_hud_visible(false)
	# a night flyover of the city while Nia talks
	_saved_tod = main.time_of_day
	main.time_of_day = 0.96
	_cam = Camera3D.new()
	_cam.fov = 55.0
	director.add_child(_cam)
	_cam.current = true
	_fly(0.0)
	Dialogue.stop_all() # "Comms are up" waits for the Descent


func _build_intro() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 1.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	# letterbox bars
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_bottom = 64 if top else 0
		bar.offset_top = 0 if top else -64
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(bar)
	# the title card
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 18)
	center.add_child(tv)
	tv.add_child(MS.lockup(92))
	var place := S.label("PORT VESPER, LOUISIANA  ·  THE NIGHT THE ACCORD BROKE", 18, MS.BONE_DIM)
	tv.add_child(place)
	_title_box = center
	_title_box.modulate.a = 0.0
	# case-file captions, left
	_caption = VBoxContainer.new()
	_caption.add_theme_constant_override("separation", 8)
	_caption.anchor_left = 0.07
	_caption.anchor_top = 0.2
	_caption.anchor_right = 0.7
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_caption)
	var tag := S.label("CASE FILE  ·  THE UNDERCROFT", 14, S.GOLD_DIM)
	_caption.add_child(tag)
	_cap_title = S.title("", 46, MS.CRIMSON)
	_caption.add_child(_cap_title)
	var rule := ColorRect.new()
	rule.color = Color(MS.CRIMSON.r, MS.CRIMSON.g, MS.CRIMSON.b, 0.8)
	rule.custom_minimum_size = Vector2(220, 1)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_caption.add_child(rule)
	_cap_body = S.label("", 21, MS.BONE)
	_caption.add_child(_cap_body)
	_caption.modulate.a = 0.0
	# Nia's comms tag with a voice meter, bottom left
	_comms = S.panel(12)
	_comms.anchor_left = 0.0
	_comms.anchor_top = 1.0
	_comms.anchor_bottom = 1.0
	_comms.offset_left = 40
	_comms.offset_top = -170
	_comms.offset_bottom = -90
	_root.add_child(_comms)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 14)
	_comms.add_child(ch)
	var meter := HBoxContainer.new()
	meter.add_theme_constant_override("separation", 3)
	for i in 9:
		var b := ColorRect.new()
		b.color = S.GOLD
		b.custom_minimum_size = Vector2(4, 4)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meter.add_child(b)
		_bars.append(b)
	ch.add_child(meter)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 0)
	ch.add_child(who)
	who.add_child(S.title("DR. NIA OKAFOR", 20, Color(0.44, 0.83, 0.78)))
	who.add_child(S.label("Undercroft comms  ·  secure line", 14, S.TEXT_DIM))
	_comms.modulate.a = 0.0
	var skip := S.label("Attack / Jump / Esc  —  skip", 14, S.TEXT_DIM)
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.anchor_top = 1.0
	skip.anchor_bottom = 1.0
	skip.offset_left = -300
	skip.offset_top = -52
	skip.offset_right = -30
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(skip)


func _process(delta: float) -> void:
	if _card != null and is_instance_valid(_card):
		_card.visible = not _card_hidden() # never through the map or a menu (QA2 #12)
	if not playing:
		return
	var dt := delta / maxf(Engine.time_scale, 0.01)
	_t += dt
	_fly(_t)
	# title: fade in, hold, fade out; the city fades up behind it
	if _step < 0:
		_title_box.modulate.a = clampf(_t / 0.8, 0.0, 1.0) * clampf((3.6 - _t) / 0.6, 0.0, 1.0)
		_dim.color.a = lerpf(1.0, 0.82, clampf(_t / 3.6, 0.0, 1.0))
		if _t >= 3.6:
			_next_step()
		return
	_dim.color.a = move_toward(_dim.color.a, 0.42, dt * 0.5)
	_comms.modulate.a = move_toward(_comms.modulate.a, 1.0, dt * 2.0)
	_step_t += dt
	_caption.modulate.a = clampf(_step_t / 0.5, 0.0, 1.0) * clampf((_step_len - _step_t) / 0.4, 0.15, 1.0)
	var speaking: bool = Dialogue.is_speaking() and Dialogue.current.get("speaker", "") == "nia"
	for i in _bars.size():
		var h := 4.0
		if speaking:
			h = 4.0 + 18.0 * absf(sin(_t * (9.0 + i * 1.7) + i)) * (0.5 + 0.5 * sin(_t * 3.1 + i * 0.6))
		_bars[i].custom_minimum_size.y = lerpf(_bars[i].custom_minimum_size.y, h, minf(dt * 18.0, 1.0))
	if _step_t >= _step_len:
		_next_step()


func _next_step() -> void:
	_step += 1
	_step_t = 0.0
	if _step >= BRIEFING.size():
		finish_intro()
		return
	var b: Array = BRIEFING[_step]
	_cap_title.text = b[1]
	_cap_body.text = b[2]
	var dur := 4.0
	if Dialogue.has_line(b[0]):
		dur = float(Dialogue.lines[b[0]].get("duration", 4.0))
		Dialogue.stop_all()
		Dialogue.play(b[0])
	_step_len = dur + 0.7


## The flyover: a slow arc high over the Old Quarter, the cathedral in frame.
func _fly(t: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var a := 0.6 + t * 0.035
	var r := 120.0 - t * 1.2
	var pos := Vector3(cos(a) * r, 46.0 - t * 0.6, sin(a) * r)
	_cam.global_position = pos
	_cam.look_at(Vector3(0, 6, 0), Vector3.UP)


## _input, not _unhandled_input (QA2 #3): the intro owns every press while it plays, so Esc skips
## it instead of opening the pause menu, and Tab / M can't open the Coat or the map underneath.
func _input(event: InputEvent) -> void:
	if not playing:
		return
	var press: bool = (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton 			or event is InputEventScreenTouch or event is InputEventAction) and event.is_pressed() and not event.is_echo()
	if not press:
		return
	get_viewport().set_input_as_handled()
	if _t < 0.6:
		return
	if event.is_action_pressed("attack") or event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept") 			or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE) or event is InputEventScreenTouch:
		finish_intro()


func finish_intro() -> void:
	if not playing:
		return
	playing = false
	mark_seen()
	Dialogue.stop_all()
	main.time_of_day = _saved_tod
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	var tw := create_tween()
	for n in _root.get_children():
		if n != _card:
			tw.parallel().tween_property(n, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		for n in _root.get_children():
			if n != _card:
				n.queue_free())
	_hud_visible(true)
	if _done.is_valid():
		_done.call()


func _hud_visible(on: bool) -> void:
	if main != null and main.hud != null:
		main.hud.visible = on
	if director != null and director.hud != null:
		director.hud.visible = on


# ---------------------------------------------------------------- the night card
## "NIGHT 1 · THE HOLLOW ALPHA" and why, for a few seconds: top centre under the compass and the
## phase line (QA2 #12: clear of the phone stick bottom-left and the touch buttons top-right). It
## waits for a HUD announcement ("DAY 1") to clear first, and hides while the map is open.
func night_card(heading: String, def: Dictionary) -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = S.panel(14)
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.0
	_card.offset_left = -250
	_card.offset_right = 250
	_card.offset_top = 104 # under the compass (8-52) and the phase line (70)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.custom_minimum_size = Vector2(500, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_card.add_child(v)
	v.add_child(S.label(heading, 15, S.GOLD))
	v.add_child(S.title(def.get("name", ""), 28, MS.CRIMSON_HI))
	v.add_child(S.label(def.get("title", ""), 16, S.TEXT_DIM))
	var r := ColorRect.new()
	r.color = Color(MS.CRIMSON.r, MS.CRIMSON.g, MS.CRIMSON.b, 0.7)
	r.custom_minimum_size = Vector2(160, 1)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(r)
	var why := S.label(def.get("why", ""), 16, MS.BONE)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.custom_minimum_size = Vector2(470, 0)
	v.add_child(why)
	_card.modulate.a = 0.0
	if _card_tw != null and _card_tw.is_valid():
		_card_tw.kill()
	_card_tw = create_tween()
	var wait := 0.0
	if main != null and main.hud != null and main.hud.get("announce_t") != null:
		wait = float(main.hud.announce_t) # the centre announcement goes first
	if wait > 0.0:
		_card_tw.tween_interval(wait + 0.2)
	_card_tw.tween_property(_card, "modulate:a", 1.0, 0.6)
	_card_tw.tween_interval(7.5)
	_card_tw.tween_property(_card, "modulate:a", 0.0, 1.2)


func _card_hidden() -> bool:
	if director != null and director.get("map_screen") != null and director.map_screen.is_open():
		return true
	return main != null and (main.menu_open() or (main.pause_menu != null and main.pause_menu.visible))


func card_text() -> String:
	if _card == null or not is_instance_valid(_card):
		return ""
	var out := []
	for l in _card.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return " | ".join(out)


# ---------------------------------------------------------------- the epilogue
## One line for the results screen, from how the Hunt went.
static func epilogue(s: Dictionary) -> String:
	if s.get("won", false):
		return "Three nights, three hunters, and the stitched thing at the Undercroft. Whoever framed Sol has run out of monsters to send. Not out of reasons."
	var fell: String = s.get("fell_to_epitaph", "")
	if fell != "":
		return fell
	match int(s.get("bosses", 0)):
		0:
			return "The Curfew closed on an empty street. Somewhere, someone is still wearing Sol's scent."
		1:
			return "One hunter down. The ones who sent it are already sending another."
		_:
			return "So close to the Final Night. Nia keeps the kettle warm, and the case file open."
