extends CanvasLayer
## The Coat: carried items, equipment (1 blade, 3 charms, 2 quick-use), stats and tooltips.
## Pauses the world while open. Mouse, keyboard and full gamepad (focus) navigation.

signal closed

const S = preload("res://scripts/ui/ui_style.gd")
const ItemDB = preload("res://scripts/items/item_db.gd")
const SLOT := 72
const BIG := 96

var main
var root: Control
var bag_slots: Array[Button] = []
var weapon_slot: Button
var charm_slots: Array[Button] = []
var quick_slots: Array[Button] = []
var weapon_name: Label
var carried_lbl: Label
var header_lbl: Label
var stats_lbl: Label
var tip_icon: TextureRect
var tip_name: Label
var tip_body: Label
var tip_frame: PanelContainer
var hint_lbl: Label
var btn_equip: Button
var btn_use: Button
var btn_drop: Button
var sel_where := "bag"
var sel_idx := 0


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(S.dim_backdrop())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := S.panel(20)
	panel.custom_minimum_size = Vector2(1220, 600)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	# header
	var head := HBoxContainer.new()
	col.add_child(head)
	var t := S.title("THE  COAT", 40)
	head.add_child(t)
	var sub := S.label("   what Sol carries", 15, S.TEXT_DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var drop_icon := TextureRect.new()
	drop_icon.texture = ItemDB.icon("tithe")
	drop_icon.custom_minimum_size = Vector2(34, 34)
	drop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drop_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drop_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(drop_icon)
	header_lbl = S.label("", 20, S.GOLD)
	header_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(header_lbl)
	col.add_child(S.rule())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_center())
	body.add_child(_build_right())
	col.add_child(S.rule())
	col.add_child(_build_footer())


func _section(text: String) -> Label:
	return S.label(text, 13, S.GOLD_DIM, 3)


func _build_left() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(320, 0)
	v.add_theme_constant_override("separation", 8)
	v.add_child(_section("BLADE"))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 12)
	v.add_child(wrow)
	weapon_slot = _slot(BIG, "weapon", 0)
	wrow.add_child(weapon_slot)
	weapon_name = S.label("", 18, S.TEXT)
	weapon_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_name.custom_minimum_size = Vector2(220, 0)
	weapon_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(weapon_name)
	v.add_child(_section("CHARMS"))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	v.add_child(crow)
	for i in 3:
		var b := _slot(SLOT + 6, "charm", i)
		charm_slots.append(b)
		crow.add_child(b)
	v.add_child(_section("QUICK-USE"))
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 10)
	v.add_child(qrow)
	for i in 2:
		var b := _slot(SLOT + 6, "quick", i)
		quick_slots.append(b)
		qrow.add_child(b)
	return v


func _build_center() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	carried_lbl = _section("CARRIED")
	v.add_child(carried_lbl)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for i in main.inventory.BAG_SIZE:
		var b := _slot(SLOT, "bag", i)
		bag_slots.append(b)
		grid.add_child(b)
	v.add_child(S.rule())
	v.add_child(_section("THE BLOOD"))
	stats_lbl = S.label("", 14, S.TEXT, 3)
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_lbl.custom_minimum_size = Vector2(462, 0)
	v.add_child(stats_lbl)
	return v


func _build_right() -> Control:
	tip_frame = PanelContainer.new()
	tip_frame.custom_minimum_size = Vector2(350, 0)
	tip_frame.add_theme_stylebox_override("panel", S.box(Color(0.03, 0.02, 0.025, 0.9), S.GOLD_DIM, 1, 3, 16))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	tip_frame.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	tip_icon = TextureRect.new()
	tip_icon.custom_minimum_size = Vector2(104, 104)
	tip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(tip_icon)
	tip_name = S.title("", 26)
	tip_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_name.custom_minimum_size = Vector2(200, 0)
	tip_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tip_name)
	v.add_child(S.rule())
	tip_body = S.label("", 15, S.TEXT, 3)
	tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_body.custom_minimum_size = Vector2(316, 0)
	v.add_child(tip_body)
	return tip_frame


func _build_footer() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	btn_equip = S.button("Equip", 16)
	btn_use = S.button("Use", 16)
	btn_drop = S.button("Drop", 16)
	var btn_close := S.button("Close", 16)
	var btn_pause := S.button("Pause", 16) # the pause menu (Options, Controls, Quit) for controllers
	for b in [btn_equip, btn_use, btn_drop, btn_close, btn_pause]:
		b.focus_mode = Control.FOCUS_NONE # don't steal focus from the slots
		b.custom_minimum_size = Vector2(110, 38)
		h.add_child(b)
	btn_equip.pressed.connect(_primary)
	btn_use.pressed.connect(_use)
	btn_drop.pressed.connect(_drop)
	btn_close.pressed.connect(close)
	btn_pause.pressed.connect(_pause)
	hint_lbl = S.label("", 14, S.TEXT_DIM, 3)
	hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hint_lbl)
	return h


## One item slot: icon, stack count and a rarity stripe.
func _slot(size: int, where: String, idx: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("where", where)
	b.set_meta("idx", idx)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 5
	icon.offset_top = 5
	icon.offset_right = -5
	icon.offset_bottom = -7
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	var stripe := ColorRect.new()
	stripe.name = "Stripe"
	stripe.anchor_left = 0.0
	stripe.anchor_right = 1.0
	stripe.anchor_top = 1.0
	stripe.anchor_bottom = 1.0
	stripe.offset_left = 3
	stripe.offset_right = -3
	stripe.offset_top = -5
	stripe.offset_bottom = -2
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(stripe)
	var count := S.label("", 15, Color.WHITE, 4)
	count.name = "Count"
	count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -34
	count.offset_top = -26
	count.offset_right = -6
	count.offset_bottom = -6
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(count)
	var tag := S.label("", 11, S.TEXT_DIM, 3)
	tag.name = "Tag"
	tag.set_anchors_preset(Control.PRESET_FULL_RECT)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tag)
	b.focus_entered.connect(_on_focus.bind(where, idx))
	b.mouse_entered.connect(b.grab_focus)
	b.pressed.connect(_on_slot_pressed.bind(where, idx))
	return b


# ---------------------------------------------------------------- data
func _inst(where: String, idx: int) -> Dictionary:
	var inv = main.inventory
	match where:
		"bag":
			return inv.bag[idx] if idx < inv.bag.size() else {}
		"weapon":
			return inv.weapon
		"charm":
			return inv.charms[idx]
		"quick":
			return inv.quick[idx]
	return {}


func refresh() -> void:
	var inv = main.inventory
	var prog = main.progression
	for i in bag_slots.size():
		_paint(bag_slots[i], _inst("bag", i), "")
	_paint(weapon_slot, inv.weapon, "BLADE")
	for i in 3:
		_paint(charm_slots[i], inv.charms[i], "CHARM")
	var qkeys := ["LB", "R3"] if main.hud.using_pad else ["1", "2"]
	for i in 2:
		_paint(quick_slots[i], inv.quick[i], "QUICK " + qkeys[i])
	weapon_name.text = ItemDB.display_name(inv.weapon) if not inv.weapon.is_empty() else ""
	weapon_name.add_theme_color_override("font_color", ItemDB.color(inv.weapon) if not inv.weapon.is_empty() else S.TEXT)
	carried_lbl.text = "CARRIED   %d / %d" % [inv.bag.size(), inv.BAG_SIZE]
	header_lbl.text = "RANK %d     TITHE %d" % [prog.level, prog.tithe]
	stats_lbl.text = _stats_text()
	_update_tooltip()
	_update_hint()


func _paint(b: Button, inst: Dictionary, empty_tag: String) -> void:
	var icon: TextureRect = b.get_node("Icon")
	var stripe: ColorRect = b.get_node("Stripe")
	var count: Label = b.get_node("Count")
	var tag: Label = b.get_node("Tag")
	var has := not inst.is_empty()
	var rc: Color = ItemDB.color(inst) if has else S.GOLD_DIM
	icon.texture = ItemDB.icon(inst) if has else null
	icon.modulate = Color.WHITE.lerp(rc, 0.18) if has else Color.WHITE
	stripe.color = rc if has else Color(0, 0, 0, 0)
	count.text = str(inst.n) if has and int(inst.get("n", 1)) > 1 else ""
	tag.text = "" if has else empty_tag
	var bg := Color(0.06, 0.04, 0.045, 0.95) if has else Color(0.035, 0.025, 0.03, 0.9)
	var edge := Color(rc.r, rc.g, rc.b, 0.75) if has else Color(S.GOLD_DIM.r, S.GOLD_DIM.g, S.GOLD_DIM.b, 0.35)
	b.add_theme_stylebox_override("normal", S.box(bg, edge, 1, 2))
	b.add_theme_stylebox_override("hover", S.box(bg.lightened(0.06), S.GOLD, 1, 2))
	b.add_theme_stylebox_override("pressed", S.box(Color(0.3, 0.03, 0.05), S.GOLD, 2, 2))
	b.add_theme_stylebox_override("focus", S.box(Color(0, 0, 0, 0), S.GOLD, 2, 2))


func _stats_text() -> String:
	var p = main.player
	var prog = main.progression
	var w: Dictionary = prog.weapon_stats()
	var lines: Array[String] = []
	lines.append("Rank %d    Blood %d / %d" % [prog.level, roundi(p.hp), roundi(p.max_hp)])
	lines.append("Strike %d  (finisher %d)   Speed %.2f   Reach %+.1f m" % [
		roundi(w.dmg * p.damage_mult()), roundi(w.dmg * 2.0 * (1.0 + prog.stat("finisher")) * p.damage_mult()), w.spd, w.reach])
	var extra: Array[String] = []
	for k in ["dash_rate", "bite_heal", "dmg_taken", "vs_vamp", "vs_wolf", "lifesteal", "speed", "tithe_mult", "loot_luck", "sun_heal", "frenzy_time"]:
		var v: float = prog.stat(k)
		if absf(v) > 0.001:
			extra.append(ItemDB.mod_line(k, v))
	if not extra.is_empty():
		lines.append("  ·  ".join(extra))
	var names: Array = []
	for id in prog.vows:
		names.append(prog.VOWS[id].name)
	lines.append("")
	lines.append("Vows:  " + ("none yet — keep vigil at the Undercroft" if names.is_empty() else ", ".join(names)))
	return "\n".join(lines)


func _on_focus(where: String, idx: int) -> void:
	sel_where = where
	sel_idx = idx
	_update_tooltip()
	_update_hint()


func _update_tooltip() -> void:
	var inst := _inst(sel_where, sel_idx)
	if inst.is_empty():
		tip_icon.texture = null
		tip_name.text = {"bag": "Empty pocket", "weapon": "Blade", "charm": "Charm slot", "quick": "Quick-use slot"}[sel_where]
		tip_name.add_theme_color_override("font_color", S.TEXT_DIM)
		tip_body.text = {"bag": "Loot from kills, coffins and crates lands here.",
			"weapon": "Sol always keeps a blade in hand. Equip another from your coat to swap.",
			"charm": "Equip a gris-gris charm from your coat. Three can be worn at once.",
			"quick": "Assign a vial or flare from your coat. Use it in the field with 1 / 2 (LB / R3 on a controller)."}[sel_where]
		tip_frame.add_theme_stylebox_override("panel", S.box(Color(0.03, 0.02, 0.025, 0.9), S.GOLD_DIM, 1, 3, 16))
		return
	var rc := ItemDB.color(inst)
	tip_icon.texture = ItemDB.icon(inst)
	tip_icon.modulate = Color.WHITE.lerp(rc, 0.18)
	tip_name.text = ItemDB.display_name(inst) + ("  x%d" % inst.n if int(inst.get("n", 1)) > 1 else "")
	tip_name.add_theme_color_override("font_color", rc)
	tip_body.text = ItemDB.describe(inst)
	tip_frame.add_theme_stylebox_override("panel", S.box(Color(0.03, 0.02, 0.025, 0.92), Color(rc.r, rc.g, rc.b, 0.8), 1, 3, 16))


func _update_hint() -> void:
	var inst := _inst(sel_where, sel_idx)
	var pad: bool = main.hud.using_pad
	var primary := "Equip"
	if sel_where == "charm" or sel_where == "quick":
		primary = "Unequip"
	elif not inst.is_empty() and ItemDB.is_consumable(inst):
		primary = "Assign"
	btn_equip.text = primary
	btn_equip.disabled = inst.is_empty() or sel_where == "weapon"
	btn_use.disabled = inst.is_empty() or not ItemDB.is_consumable(inst)
	btn_drop.disabled = inst.is_empty() or sel_where == "weapon"
	if pad:
		hint_lbl.text = "[A] %s   [Y] Use   [X] Drop   [B] Close   [Back] Pause" % primary
	else:
		hint_lbl.text = "[Click / Enter] %s   [U] Use   [X / Del] Drop   [Tab / I / Esc] Close" % primary


# ---------------------------------------------------------------- actions
func _on_slot_pressed(where: String, idx: int) -> void:
	sel_where = where
	sel_idx = idx
	_primary()


func _primary() -> void:
	var inv = main.inventory
	var inst := _inst(sel_where, sel_idx)
	if inst.is_empty():
		return
	match sel_where:
		"bag":
			inv.equip_from_bag(sel_idx)
		"weapon":
			main.hud.popup("Equip another blade from your coat to swap")
		"charm", "quick":
			if not inv.unequip(sel_where, sel_idx):
				main.hud.popup("YOUR COAT IS FULL")
	refresh()


func _use() -> void:
	var inv = main.inventory
	if sel_where == "bag":
		inv.use_bag(sel_idx)
	elif sel_where == "quick":
		inv.use_quick(sel_idx)
	refresh()


func _drop() -> void:
	var inv = main.inventory
	var inst := {}
	if sel_where == "bag":
		inst = inv.take_from_bag(sel_idx)
	elif sel_where == "charm" or sel_where == "quick":
		inst = inv.take_from_slot(sel_where, sel_idx)
	if not inst.is_empty():
		main.loot.drop_from_player(inst)
		main.hud.popup("DROPPED  " + ItemDB.display_name(inst).to_upper())
	refresh()


# ---------------------------------------------------------------- open / close
func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sel_where = "bag"
	sel_idx = 0
	refresh()
	bag_slots[0].grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	main.player.block_attack()
	main.progression.save()
	closed.emit()


## Leave the Coat for the pause menu.
func _pause() -> void:
	close()
	main.open_pause()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var handled := true
	if event.is_action_pressed("inventory") or event.is_action_pressed("ui_cancel"):
		close()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_U:
				_use()
			KEY_X, KEY_DELETE:
				_drop()
			_:
				handled = false
	elif event is InputEventJoypadButton and event.pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_Y:
				_use()
			JOY_BUTTON_X:
				_drop()
			JOY_BUTTON_BACK:
				_pause()
			_:
				handled = false
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
