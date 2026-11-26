extends PanelContainer
## LAIR: the focused panel a station opens (lair_hub.gd). One panel, rebuilt per station, docked to
## the side of the screen away from what the camera frames:
##   rack    the armoury: Nia's rack of blades (hunt_meta.gd BLADE_RACK): carry one, buy the others
##   bench   the workbench: the three charms worn in, the charm armoury, Nia's contacts (Sunmarks)
##   mirror  the wardrobe: seven slots, the clothes for each (wear / buy / found in a Hunt), the
##           piece's stats and the outfit's totals; Turn spins Sol in the mirror
##   table   the map table: tonight's target and modifier, the record, the loadout, Begin the Hunt
##   gate    the subway gate: Begin the Hunt
## Everything the old menu hub (hunt/hub_panel.gd) offered is here, spread over the stations.

signal closed
signal begin
signal changed(what: String) # "blade", "charms", "outfit"
signal turn # the wardrobe's Turn button

const S = preload("res://scripts/ui/ui_style.gd")
const MS = preload("res://scripts/menu/menu_style.gd")
const Meta = preload("res://scripts/hunt/hunt_meta.gd")
const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const ItemDB = preload("res://scripts/items/item_db.gd")
const W = preload("res://scripts/items/wardrobe_data.gd")

var kind := ""
var hub # lair_hub.gd (the briefing's seed, the outfit preview)
var col: VBoxContainer
var body: VBoxContainer
var detail: Label
var first_focus: Control
var back_button: Button
var begin_button: Button
var slot := "coat" # the wardrobe's open slot
var rows := {} # id -> Button (tests)
var stats_box: VBoxContainer


func _init() -> void:
	var sb := S.box(Color(0.03, 0.02, 0.024, 0.9), S.GOLD_DIM, 1, 3, 20)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 20
	add_theme_stylebox_override("panel", sb)
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_top = 24
	offset_bottom = -24
	custom_minimum_size = Vector2(520, 0)
	visible = false


## Open on a station. `side`: "left" or "right" of the screen.
func open(k: String, side: String) -> void:
	kind = k
	if side == "left":
		anchor_left = 0.0
		anchor_right = 0.0
		offset_left = 24
		offset_right = 544
	else:
		anchor_left = 1.0
		anchor_right = 1.0
		offset_left = -544
		offset_right = -24
	# the gate's panel is a short confirm, centred on its side; the rest run full height
	anchor_top = 0.3 if k == "gate" else 0.0
	anchor_bottom = 0.3 if k == "gate" else 1.0
	offset_top = 0 if k == "gate" else 24
	offset_bottom = 0 if k == "gate" else -24
	visible = true
	rebuild()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func rebuild() -> void:
	var keep_focus := ""
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f != null and f is Button and is_ancestor_of(f):
		keep_focus = String((f as Button).get_meta("key", ""))
	for c in get_children():
		remove_child(c)
		c.queue_free()
	rows.clear()
	first_focus = null
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	match kind:
		"rack": _rack()
		"bench": _bench()
		"mirror": _mirror()
		"table": _table()
		"gate": _gate()
	# Back (and Begin where it belongs) at the foot
	col.add_child(S.rule())
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 24)
	col.add_child(foot)
	begin_button = null
	if kind in ["table", "gate"]:
		begin_button = MS.item("Begin the Hunt", 30)
		begin_button.pressed.connect(func(): begin.emit())
		begin_button.set_meta("key", "@begin")
		foot.add_child(begin_button)
	if kind == "mirror":
		var t := MS.item("Turn", 22)
		t.pressed.connect(func(): turn.emit())
		t.set_meta("key", "@turn")
		foot.add_child(t)
	back_button = MS.item("Back" if kind != "gate" else "Not yet", 22)
	back_button.pressed.connect(close)
	back_button.set_meta("key", "@back")
	foot.add_child(back_button)
	if begin_button != null:
		first_focus = begin_button
	if first_focus == null:
		first_focus = back_button
	var target: Control = first_focus
	if keep_focus != "":
		for b in find_children("*", "Button", true, false):
			if String(b.get_meta("key", "")) == keep_focus:
				target = b
	if is_inside_tree():
		target.grab_focus.call_deferred()


# ---------------------------------------------------------------- helpers
func _title(t: String, sub: String) -> void:
	var h := S.title(t, 34, S.GOLD)
	col.add_child(h)
	if sub != "":
		var l := S.label(sub, 15, S.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	col.add_child(S.rule())


func _head(text: String) -> Label:
	var h := S.label(text, 14, S.CRIMSON.lightened(0.3), 3)
	h.add_theme_font_override("font", S.serif())
	h.custom_minimum_size = Vector2(0, 22)
	h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return h


func _marks() -> Label:
	return S.title("%d %s" % [int(Meta.ensure().sunmarks), Cfg.META_NAME], 22, Color(1.0, 0.8, 0.4))


## A scrolling list that fills the middle of the panel.
func _list() -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	col.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	sc.add_child(v)
	return v


func _row(parent: Control, text: String, key: String, color: Color, cb: Callable, disabled := false, info := "") -> Button:
	var b := S.button(text, 15)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_color_override("font_color", color)
	b.disabled = disabled
	b.set_meta("key", key)
	b.pressed.connect(cb)
	if info != "" and detail != null:
		b.focus_entered.connect(func(): detail.text = info)
		b.mouse_entered.connect(func(): detail.text = info)
	parent.add_child(b)
	rows[key] = b
	if first_focus == null and not disabled:
		first_focus = b
	return b


func _detail_label() -> void:
	detail = S.label("", 14, S.TEXT)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(0, 66)


# ---------------------------------------------------------------- the armoury
func _rack() -> void:
	_title("THE ARMOURY", "One blade rides with you into the Hunt, on your back or at your hip. The rest stay on the board. Blades start each Hunt at Street rarity.")
	col.add_child(_marks())
	_detail_label()
	var list := _list()
	var d := Meta.ensure()
	for e in Meta.BLADE_RACK:
		var inst := ItemDB.make(e.id)
		var owned := Meta.owns_blade(e.id)
		var carried: bool = owned and String(d.start_blade) == e.id
		var t := "%s%s   ·   %s" % ["[CARRIED]  " if carried else "", ItemDB.display_name(inst), ItemDB.weapon_line(inst)]
		if not owned:
			t += "   —   %d %s" % [e.price, Cfg.META_NAME]
		_row(list, t, e.id, S.GOLD if carried else (S.TEXT if owned else S.TEXT_DIM), _rack_pick.bind(e.id),
			not owned and int(d.sunmarks) < int(e.price), ItemDB.describe(inst))
	col.add_child(detail)
	detail.text = ItemDB.describe(Meta.start_blade())


func _rack_pick(id: String) -> void:
	if Meta.owns_blade(id):
		Meta.choose_blade(id)
		Meta.save_meta()
	elif not Meta.buy_blade(id):
		return
	Audio.play("ui_click", -3.0, 0.0)
	changed.emit("blade")
	rebuild()


# ---------------------------------------------------------------- the workbench
func _bench() -> void:
	_title("THE WORKBENCH", "Charms you wear into the Hunt stay yours. Charms you carry home join the armoury. Nia's contacts sell more for Sunmarks.")
	col.add_child(_marks())
	_detail_label()
	var list := _list()
	var d := Meta.ensure()
	list.add_child(_head("WORN INTO THE HUNT  (3 charms)"))
	var worn := Meta.loadout_charms()
	for i in worn.size():
		var inst: Dictionary = worn[i]
		list.add_child(S.label(("%d.  " % (i + 1)) + (_charm_text(inst) if not inst.is_empty() else "— empty —"), 15,
			ItemDB.RARITY_COLORS[inst.r] if not inst.is_empty() else S.TEXT_DIM))
	list.add_child(_head("THE ARMOURY  ·  wear / take off"))
	for i in d.armoury.size():
		var inst: Dictionary = d.armoury[i]
		var on: bool = i in d.loadout
		_row(list, ("[WORN]  " if on else "") + _charm_text(inst), "charm_%d" % i, ItemDB.RARITY_COLORS[inst.r], _toggle.bind(i), false, ItemDB.describe(inst))
	list.add_child(_head("NIA'S CONTACTS  ·  buy with " + Cfg.META_NAME))
	var shown := 0
	for e in Cfg.ARMOURY_SHOP:
		if Meta.owns(e.id):
			continue
		shown += 1
		var inst := ItemDB.make(e.id)
		_row(list, "%s   —   %d %s" % [_charm_text(inst), e.price, Cfg.META_NAME], "shop_" + e.id, S.TEXT, _buy.bind(e.id),
			int(d.sunmarks) < int(e.price), ItemDB.describe(inst))
	if shown == 0:
		list.add_child(S.label("Nia has nothing more to offer. For now.", 14, S.TEXT_DIM))
	col.add_child(detail)


func _charm_text(inst: Dictionary) -> String:
	var mods := ItemDB.item_mods(inst)
	var bits: Array = []
	for k in mods:
		bits.append(ItemDB.mod_line(k, mods[k]))
	return "%s (%s)  %s" % [ItemDB.display_name(inst), ItemDB.RARITY_NAMES[inst.r], ", ".join(bits)]


func _toggle(i: int) -> void:
	Meta.toggle_loadout(i)
	Meta.save_meta()
	changed.emit("charms")
	rebuild()


func _buy(id: String) -> void:
	if Meta.buy(id):
		changed.emit("charms")
		rebuild()


# ---------------------------------------------------------------- the wardrobe
func _mirror() -> void:
	_title("THE WARDROBE", "")
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	col.add_child(tabs)
	for s in W.SLOTS:
		var b := S.button(W.SLOT_NAMES[s], 15)
		b.set_meta("key", "@slot_" + s)
		b.toggle_mode = true
		b.button_pressed = s == slot
		if s == slot:
			b.add_theme_color_override("font_color", S.GOLD)
		b.pressed.connect(_slot.bind(s))
		tabs.add_child(b)
		rows["@slot_" + s] = b
	_detail_label()
	var list := _list()
	var worn := Meta.outfit()
	var marks := int(Meta.ensure().sunmarks)
	for id in W.items_for(slot):
		var d := W.get_def(id)
		var owned := Meta.owns_cloth(id)
		var on: bool = worn.get(slot, "") == id
		var t := "%s%s   ·   %s" % ["[WORN]  " if on else "", d.name, W.mods_line(id)]
		var dis := false
		var c: Color = W.RARITY_COLORS[int(d.r)]
		if not owned:
			if d.has("price"):
				t += "   —   %d %s" % [int(d.price), Cfg.META_NAME]
				dis = marks < int(d.price)
			else:
				t += "   —   found in the Hunt"
				dis = true
			c = c.darkened(0.35)
		var info := "%s  (%s)\n%s\n%s" % [d.name, W.RARITY_NAMES[int(d.r)], d.desc, W.mods_line(id)]
		var b := _row(list, t, id, S.GOLD if on else c, _wear.bind(id), dis, info)
		if on:
			first_focus = b
	col.add_child(detail)
	var wd := W.get_def(String(worn.get(slot, "")))
	detail.text = "%s  (%s)\n%s\n%s" % [wd.get("name", ""), W.RARITY_NAMES[int(wd.get("r", 0))], wd.get("desc", ""), W.mods_line(String(worn.get(slot, "")))]
	col.add_child(_head("WHAT THE OUTFIT GIVES  ·  " + str(int(Meta.ensure().sunmarks)) + " " + Cfg.META_NAME))
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 0)
	col.add_child(stats_box)
	fill_stats(stats_box, Meta.outfit_mods(), true)
	var note := S.label("In the Hunt these add to your rank, Rites, charms and blade (capped). The Coat shows the totals.", 12, S.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)


## Stat rows: label and value, green for a gain, red for a trade-off. Static: the Coat uses it too.
static func fill_stats(box: Container, mods: Dictionary, show_zero := false) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	box.add_child(grid)
	for row in W.STAT_ROWS:
		var k: String = row[0]
		var v := float(mods.get(k, 0.0))
		if absf(v) < 0.0001 and not show_zero:
			continue
		if absf(v) < 0.0001 and k in ["vs_vamp", "vs_wolf"]:
			continue
		grid.add_child(S.label(String(row[1]), 14, S.TEXT_DIM, 3))
		var txt := "—"
		if absf(v) >= 0.0001:
			txt = ("%+d%%" % int(round(v * 100.0))) if row[2] else ("%+d" % int(round(v)))
		var c := S.TEXT_DIM
		if absf(v) >= 0.0001:
			c = Color(0.45, 0.95, 0.5) if W.is_good(k, v) else Color(1.0, 0.42, 0.38)
		grid.add_child(S.label(txt, 14, c, 3))


func _slot(s: String) -> void:
	slot = s
	if hub != null and hub.has_method("frame_slot"):
		hub.frame_slot(s)
	rebuild()


func _wear(id: String) -> void:
	if Meta.owns_cloth(id):
		Meta.wear(id)
		Meta.save_meta()
	elif not Meta.buy_cloth(id):
		return
	Audio.play("ui_click", -3.0, 0.0)
	changed.emit("outfit")
	rebuild()


# ---------------------------------------------------------------- the map table / the gate
func _table() -> void:
	_title("TONIGHT", "Three nights. The Red Curfew closes the city around you. Find who's framing you.")
	var seed_ := int(hub.hunt_seed) if hub != null else 0
	var boss: Dictionary = HuntDirector.bosses_for(seed_)[0]
	var mod: Dictionary = Cfg.NIGHT_MODIFIERS.get(String(HuntDirector.modifiers_for(seed_)[0]), {})
	var list := _list()
	list.add_child(_head("NIGHT ONE  ·  THE TARGET"))
	list.add_child(S.title(String(boss.name), 22, S.TEXT))
	list.add_child(S.label(String(boss.get("title", "")), 15, S.GOLD))
	var why := S.label(String(boss.get("why", "")), 14, S.TEXT_DIM)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(why)
	if not mod.is_empty():
		list.add_child(_head("THE NIGHT"))
		list.add_child(S.title(String(mod.name), 20, mod.get("color", S.TEXT)))
		var md := S.label(String(mod.get("desc", "")), 14, S.TEXT_DIM)
		md.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(md)
	list.add_child(_head("YOUR LOADOUT"))
	var blade := Meta.start_blade()
	list.add_child(S.label("Blade:  %s   ·   %s" % [ItemDB.display_name(blade), ItemDB.weapon_line(blade)], 14, S.TEXT))
	var charms: Array = []
	for c in Meta.loadout_charms():
		if not c.is_empty():
			charms.append(ItemDB.display_name(c))
	list.add_child(S.label("Charms:  " + (", ".join(charms) if not charms.is_empty() else "none"), 14, S.TEXT))
	var bits: Array = []
	var o := Meta.outfit()
	for s in ["hat", "scarf", "coat", "boots"]:
		var d := W.get_def(o[s])
		if not d.get("mods", {}).is_empty() or s == "coat":
			bits.append(String(d.name))
	list.add_child(S.label("Wearing:  " + ", ".join(bits), 14, S.TEXT))
	var sb := VBoxContainer.new()
	list.add_child(sb)
	fill_stats(sb, Meta.outfit_mods())
	list.add_child(_head("THE BLOODLINE"))
	var d := Meta.ensure()
	var rec := "Hunts  %d     Won  %d     Most bosses in one Hunt  %d / 3\nBest rank  %d     Kills  %d     %d %s" % [d.hunts, d.wins, d.best_bosses, d.best_rank, d.total_kills, d.sunmarks, Cfg.META_NAME]
	var last: Dictionary = d.get("last", {})
	if not last.is_empty():
		rec += "\nLast Hunt: %d boss%s, %d kills, +%d %s" % [int(last.get("bosses", 0)), "" if int(last.get("bosses", 0)) == 1 else "es", int(last.get("kills", 0)), int(last.get("earned", 0)), Cfg.META_NAME]
	list.add_child(S.label(rec, 14, S.TEXT))


func _gate() -> void:
	_title("THE OLD LINE", "The 1890s subway runs under the whole city. Nia's drop points are up every service ladder. Once you're through this gate, the Hunt is on.")
	var blade := Meta.start_blade()
	col.add_child(S.label("You carry  %s." % ItemDB.display_name(blade), 16, S.TEXT))


## Short screens (phones): shrink to fit, like the old hub panel.
func _process(_delta: float) -> void:
	if not visible or size.y <= 0.0:
		return
	var vs := get_viewport_rect().size
	var need := get_combined_minimum_size().y
	var k := clampf(vs.y / maxf(need + 48.0, 1.0), 0.62, 1.0) if need + 48.0 > vs.y else 1.0
	k = minf(k, vs.x * 0.6 / 544.0) if vs.x < 1100.0 else k
	k = clampf(k, 0.55, 1.0)
	if not is_equal_approx(scale.x, k):
		scale = Vector2(k, k)
		pivot_offset = Vector2(size.x if anchor_left > 0.5 else 0.0, 0.0)
