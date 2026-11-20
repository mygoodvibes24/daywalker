extends CanvasLayer
## The Night Merchant's cart: spend Tithe on vials, flares and blades during a Hunt.
## Pauses the world while open (Esc / B / the button closes it).

const S = preload("res://scripts/ui/ui_style.gd")
const MS = preload("res://scripts/menu/menu_style.gd")
const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const ItemDB = preload("res://scripts/items/item_db.gd")

var director: HuntDirector
var main: Main
var root: Control
var list: VBoxContainer
var tithe_label: Label
var stock: Array = [] # [{inst, price, sold}]
var stock_day := -1


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := S.dim_backdrop()
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := S.panel(26)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var t := S.title("THE NIGHT MERCHANT", 40, Color(0.5, 1.0, 0.6))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := S.label("\"Old Ma Celestine takes Tithe, cher. Nothing else spends after dark.\"", 15, S.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	tithe_label = S.label("", 20, Color(1.0, 0.5, 0.45))
	tithe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tithe_label)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	v.add_child(list)
	visible = false


func is_open() -> bool:
	return visible


func _roll_stock() -> void:
	stock.clear()
	for e in Cfg.MERCHANT_STOCK:
		var inst: Dictionary
		if e.get("random_blade", false):
			inst = director.random_item(int(e.r), "blade")
			inst = ItemDB.make(inst.id, int(e.r))
		else:
			inst = ItemDB.make(e.id, int(e.r), int(e.get("n", 1)))
		stock.append({"inst": inst, "price": int(e.price), "sold": false})
	stock_day = director.day


func open() -> void:
	if visible:
		return
	if stock_day != director.day:
		_roll_stock()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	main.player.block_attack()
	main._on_menu_closed()


func _refresh() -> void:
	for c in list.get_children():
		c.queue_free()
	tithe_label.text = "TITHE  %d" % main.progression.tithe
	var first: Button = null
	for i in stock.size():
		var s: Dictionary = stock[i]
		var inst: Dictionary = s.inst
		var name_ := ItemDB.display_name(inst) + ("  x%d" % inst.n if int(inst.get("n", 1)) > 1 else "")
		var txt := "%s  (%s)   —   %s" % [name_, ItemDB.RARITY_NAMES[inst.r], "SOLD" if s.sold else "%d Tithe" % s.price]
		var b := S.button(txt, 17)
		b.add_theme_color_override("font_color", ItemDB.RARITY_COLORS[inst.r])
		b.disabled = s.sold or main.progression.tithe < s.price
		b.pressed.connect(_buy.bind(i))
		list.add_child(b)
		if first == null and not b.disabled:
			first = b
	var leave := S.button("Leave the cart  [Esc]", 17)
	leave.pressed.connect(close)
	list.add_child(leave)
	(first if first != null else leave).grab_focus.call_deferred()


func _buy(i: int) -> void:
	var s: Dictionary = stock[i]
	if s.sold or main.progression.tithe < s.price:
		return
	if not main.inventory.add(s.inst):
		main.hud.popup("YOUR COAT IS FULL")
		return
	main.progression.add_tithe(-s.price)
	s.sold = ItemDB.kind_of(s.inst) == "blade" # vials and flares restock
	main.hud.popup("BOUGHT  " + ItemDB.display_name(s.inst).to_upper())
	_refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		close()
