extends PanelContainer
## The Undercroft, before a Hunt (the hub; shown over the main menu's lair scene).
## Your record from past Hunts, the charms you'll wear in (persistent), the armoury of
## charms you own and the ones you can buy with Sunmarks, and "Begin the Hunt".

signal begin
signal back

const S = preload("res://scripts/ui/ui_style.gd")
const MS = preload("res://scripts/menu/menu_style.gd")
const Meta = preload("res://scripts/hunt/hunt_meta.gd")
const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const ItemDB = preload("res://scripts/items/item_db.gd")

var first_focus: Control
var record: Label
var loadout_box: VBoxContainer
var armoury_box: VBoxContainer
var shop_box: VBoxContainer
var marks: Label
var begin_button: Button


func _init() -> void:
	var sb := S.box(Color(0.035, 0.022, 0.026, 0.94), S.GOLD_DIM, 1, 3, 22)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 24
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(880, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var t := S.title("THE UNDERCROFT", 38, S.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var sub := S.label("Nia has the coat brushed and the blades oiled. Choose what you wear into the Hunt.", 15, S.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(S.rule())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	col.add_child(row)
	# left: record + loadout
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	left.add_child(_head("THE BLOODLINE"))
	record = S.label("", 15, S.TEXT)
	left.add_child(record)
	marks = S.title("", 24, Color(1.0, 0.8, 0.4))
	left.add_child(marks)
	left.add_child(_head("WORN INTO THE HUNT  (3 charms)"))
	loadout_box = VBoxContainer.new()
	left.add_child(loadout_box)
	var note := S.label("Rank, Tithe, Vows, blades and vials start\nfresh every Hunt. Charms and %s stay.\nCharms you carry home join the armoury." % Cfg.META_NAME, 13, S.TEXT_DIM)
	left.add_child(note)
	# right: armoury + shop
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(460, 0)
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	right.add_child(_head("THE ARMOURY  ·  click to wear / take off"))
	armoury_box = VBoxContainer.new()
	right.add_child(armoury_box)
	right.add_child(_head("NIA'S CONTACTS  ·  buy with " + Cfg.META_NAME))
	shop_box = VBoxContainer.new()
	right.add_child(shop_box)
	col.add_child(S.rule())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	col.add_child(buttons)
	begin_button = MS.item("Begin the Hunt", 32)
	begin_button.pressed.connect(func(): begin.emit())
	buttons.add_child(begin_button)
	var b2 := MS.item("Back", 24)
	b2.pressed.connect(func(): back.emit())
	buttons.add_child(b2)
	first_focus = begin_button
	visibility_changed.connect(func():
		if is_visible_in_tree():
			refresh())


func _head(text: String) -> Label:
	var h := S.label(text, 14, S.CRIMSON.lightened(0.3), 3)
	h.add_theme_font_override("font", S.serif())
	h.custom_minimum_size = Vector2(0, 24)
	h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return h


func refresh() -> void:
	var d := Meta.ensure()
	record.text = "Hunts  %d     Won  %d\nMost bosses in one Hunt  %d / 3\nBest rank  %d     Kills  %d" % [d.hunts, d.wins, d.best_bosses, d.best_rank, d.total_kills]
	var last: Dictionary = d.get("last", {})
	if not last.is_empty():
		record.text += "\nLast Hunt: %d boss%s, %d kills, +%d %s" % [int(last.get("bosses", 0)), "" if int(last.get("bosses", 0)) == 1 else "es", int(last.get("kills", 0)), int(last.get("earned", 0)), Cfg.META_NAME]
	marks.text = "%d %s" % [d.sunmarks, Cfg.META_NAME]
	for box in [loadout_box, armoury_box, shop_box]:
		for c in box.get_children():
			c.queue_free()
	var worn := Meta.loadout_charms()
	for i in worn.size():
		var inst: Dictionary = worn[i]
		var l := S.label(("%d.  " % (i + 1)) + (_describe(inst) if not inst.is_empty() else "— empty —"), 15, ItemDB.RARITY_COLORS[inst.r] if not inst.is_empty() else S.TEXT_DIM)
		loadout_box.add_child(l)
	for i in d.armoury.size():
		var inst: Dictionary = d.armoury[i]
		var on: bool = i in d.loadout
		var b := S.button(("[WORN]  " if on else "") + _describe(inst), 15)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", ItemDB.RARITY_COLORS[inst.r])
		b.tooltip_text = ItemDB.describe(inst)
		b.pressed.connect(_toggle.bind(i))
		armoury_box.add_child(b)
	var shown := 0
	for e in Cfg.ARMOURY_SHOP:
		if Meta.owns(e.id) or shown >= 5:
			continue
		shown += 1
		var inst := ItemDB.make(e.id)
		var b := S.button("%s   —   %d %s" % [_describe(inst), e.price, Cfg.META_NAME], 15)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = d.sunmarks < e.price
		b.pressed.connect(_buy.bind(e.id))
		shop_box.add_child(b)
	if shown == 0:
		shop_box.add_child(S.label("Nia has nothing more to offer. For now.", 14, S.TEXT_DIM))


func _describe(inst: Dictionary) -> String:
	var mods := ItemDB.item_mods(inst)
	var bits: Array = []
	for k in mods:
		bits.append(ItemDB.mod_line(k, mods[k]))
	return "%s (%s)  %s" % [ItemDB.display_name(inst), ItemDB.RARITY_NAMES[inst.r], ", ".join(bits)]


func _toggle(i: int) -> void:
	Meta.toggle_loadout(i)
	Meta.save_meta()
	refresh()


func _buy(id: String) -> void:
	if Meta.buy(id):
		refresh()


## Short screens (phones, where the UI is scaled up): shrink the whole panel to fit instead
## of letting "Begin the Hunt" fall off the bottom (R2-A, U2).
func _process(_delta: float) -> void:
	if not is_visible_in_tree() or size.y <= 0.0:
		return
	var vs := get_viewport_rect().size
	var k := minf(1.0, minf(vs.y * 0.97 / size.y, vs.x * 0.97 / size.x))
	pivot_offset = size * 0.5
	if not is_equal_approx(scale.x, k):
		scale = Vector2(k, k)
