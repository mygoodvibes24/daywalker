extends PanelContainer
## The Controls screen, shared by the main menu and the pause menu. Built from
## controls_data.gd (which mirrors main.gd `_setup_input()`): every section is a small
## table with a keyboard / mouse column and a controller column; sections flow into two
## side-by-side blocks so the whole list reads at 1280x720 without scrolling.

signal back

const S = preload("res://scripts/ui/ui_style.gd")
const Data = preload("res://scripts/menu/controls_data.gd")
const BONE := Color(0.9, 0.86, 0.78)

var first_focus: Control
var back_button: Button


func _init() -> void:
	var sb := S.box(Color(0.035, 0.022, 0.026, 0.94), S.GOLD_DIM, 1, 3, 22)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 24
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var t := S.title("CONTROLS", 34, S.TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	col.add_child(S.rule())
	# split the rows into sections, then into two blocks of about equal height
	var sections: Array = []
	for r in Data.ROWS:
		if (r[0] as String).begins_with("#"):
			sections.append([r])
		elif not sections.is_empty():
			sections[-1].append(r)
	var total := 0
	for s in sections:
		total += s.size()
	var blocks := HBoxContainer.new()
	blocks.add_theme_constant_override("separation", 34)
	col.add_child(blocks)
	var grid: GridContainer = null
	var used := 0
	for s in sections:
		if grid == null or (used + s.size() * 0.5 > total * 0.5 and blocks.get_child_count() < 2):
			grid = _grid()
			blocks.add_child(grid)
		for r in s:
			_add_row(grid, r)
		used += s.size()
	var notes := S.label(Data.NOTES, 14, S.TEXT_DIM, 3)
	notes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(S.rule())
	col.add_child(notes)
	back_button = S.button("Back", 18)
	back_button.custom_minimum_size = Vector2(180, 38)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(func(): back.emit())
	col.add_child(back_button)
	first_focus = back_button
	visibility_changed.connect(func():
		if is_visible_in_tree():
			back_button.grab_focus.call_deferred())


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 3)
	for h in ["", "KEYBOARD / MOUSE", "CONTROLLER"]:
		var l := S.label(h, 13, S.GOLD_DIM, 2)
		g.add_child(l)
	return g


func _add_row(g: GridContainer, r: Array) -> void:
	var a: String = r[0]
	if a.begins_with("#"):
		var h := S.label(a.trim_prefix("#").strip_edges().to_upper(), 15, S.CRIMSON.lightened(0.3), 3)
		h.add_theme_font_override("font", S.serif())
		h.custom_minimum_size = Vector2(0, 26)
		h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		g.add_child(h)
		g.add_child(Control.new())
		g.add_child(Control.new())
		return
	var name := S.label(a, 15, S.TEXT, 3)
	name.custom_minimum_size = Vector2(200, 0)
	g.add_child(name)
	var kb := S.label(r[1], 15, BONE, 3)
	kb.custom_minimum_size = Vector2(130, 0)
	g.add_child(kb)
	var pad := S.label(r[2], 15, BONE, 3)
	pad.custom_minimum_size = Vector2(150, 0)
	g.add_child(pad)
