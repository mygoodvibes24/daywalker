extends CanvasLayer
## End of a Hunt: what you killed, how far you got, the Sunmarks you earned and the
## charms you carried home. Then back to the Undercroft (the hub) or straight into another.

const S = preload("res://scripts/ui/ui_style.gd")
const MS = preload("res://scripts/menu/menu_style.gd")
const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const Meta = preload("res://scripts/hunt/hunt_meta.gd")

var director: HuntDirector
var root: Control
var title: Label
var sub: Label
var epilogue: Label # STORY: one line on how it ended (hunt_story.gd epilogue())
var stats: Label
var earned: Label
var buttons: Array[Button] = []


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.0, 0.01, 0.82)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := S.panel(30)
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	title = S.title("THE HUNT IS OVER", 48, MS.CRIMSON)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	sub = S.label("", 18, S.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	epilogue = S.label("", 19, MS.BONE)
	epilogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	epilogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	epilogue.custom_minimum_size = Vector2(560, 0)
	epilogue.add_theme_font_override("font", S.serif())
	v.add_child(epilogue)
	var r := S.rule(420)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(r)
	stats = S.label("", 20, S.TEXT)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats)
	earned = S.title("", 30, S.GOLD)
	earned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(earned)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	for e in [["Return to the Undercroft", _hub], ["Hunt Again", _again]]:
		var b := MS.item(e[0], 26)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(e[1])
		v.add_child(b)
		buttons.append(b)
	buttons[0].focus_neighbor_bottom = buttons[1].get_path()
	buttons[1].focus_neighbor_top = buttons[0].get_path()
	visible = false


func is_open() -> bool:
	return visible


func show_results(s: Dictionary) -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if s.won:
		title.text = "DAWN OVER PORT VESPER"
		title.add_theme_color_override("font_color", S.GOLD)
		sub.text = "The Hunt is won. Seraphine's work lies in ashes."
	else:
		title.text = "THE HUNT IS OVER"
		sub.text = "Sol falls on %s." % ("the Final Night" if int(s.day) >= 3 else "Day %d" % int(s.day))
	epilogue.text = '"%s"' % s.get("epilogue", "") if s.get("epilogue", "") != "" else ""
	epilogue.visible = epilogue.text != ""
	var t := int(s.time)
	stats.text = "Bosses slain   %d / 3\nKills   %d\nCommunion rank reached   %d\nTime   %d:%02d" % [s.bosses, s.kills, s.rank, t / 60, t % 60]
	var rites: Array = s.get("rites", [])
	if not rites.is_empty():
		stats.text += "\nBlood Rites   " + "  ·  ".join(rites)
	if int(s.get("micros", 0)) > 0:
		stats.text += "\nFinds between the sites   %d" % int(s.micros)
	var kept: Array = s.get("kept", [])
	if not kept.is_empty():
		stats.text += "\n\nSewn into your armoury:  " + ", ".join(kept)
	earned.text = "+%d %s   (%d banked)" % [s.earned, Cfg.META_NAME, int(Meta.data.get("sunmarks", 0))]
	buttons[0].grab_focus.call_deferred()


func _hub() -> void:
	director.return_to_hub()


func _again() -> void:
	director.hunt_again()
