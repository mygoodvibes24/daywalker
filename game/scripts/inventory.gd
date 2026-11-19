class_name Inventory
extends Node
## What Sol carries ("the Coat"): a bag of item instances plus equipment —
## 1 blade, 3 charms and 2 quick-use slots. Items are item_db.gd instances.

signal changed # anything in the bag or the slots moved
signal equipment_changed # the stat-affecting slots changed (blade / charms)
signal item_used(inst: Dictionary)

const ItemDB = preload("res://scripts/items/item_db.gd")
const BAG_SIZE := 24
const STARTER := "marrow_silver"

var main
var bag: Array = [] # item instances, packed (no holes)
var weapon: Dictionary = {}
var charms: Array = [{}, {}, {}]
var quick: Array = [{}, {}]


func _init() -> void:
	reset()


func reset() -> void:
	bag = []
	weapon = ItemDB.make(STARTER)
	charms = [{}, {}, {}]
	quick = [ItemDB.make("blood_vial", 0, 2), {}]


func equipped_items() -> Array:
	var out: Array = []
	if not weapon.is_empty():
		out.append(weapon)
	for c in charms:
		if not c.is_empty():
			out.append(c)
	return out


func is_full() -> bool:
	return bag.size() >= BAG_SIZE


## Put an item in the coat: stacks onto a matching quick slot or bag stack first.
func add(inst: Dictionary) -> bool:
	inst = inst.duplicate()
	if ItemDB.is_stackable(inst):
		var cap: int = ItemDB.get_def(inst.id).stack
		for i in quick.size():
			var q: Dictionary = quick[i]
			if not q.is_empty() and q.id == inst.id and q.r == inst.r and q.n < cap:
				var moved := mini(cap - q.n, inst.n)
				q.n += moved
				inst.n -= moved
				if inst.n <= 0:
					changed.emit()
					return true
		for s in bag:
			if s.id == inst.id and s.r == inst.r and s.n < cap:
				var moved := mini(cap - s.n, inst.n)
				s.n += moved
				inst.n -= moved
				if inst.n <= 0:
					changed.emit()
					return true
	if is_full():
		return false
	bag.append(inst)
	changed.emit()
	return true


## Equip / assign the bag item at index i. Blades swap with the current blade,
## charms go to the first free slot (else replace the last), consumables to a quick slot.
func equip_from_bag(i: int, slot: int = -1) -> bool:
	if i < 0 or i >= bag.size():
		return false
	var inst: Dictionary = bag[i]
	match ItemDB.kind_of(inst):
		"blade":
			bag.remove_at(i)
			if not weapon.is_empty():
				bag.insert(i, weapon)
			weapon = inst
			_after_equip(true)
		"charm":
			if slot < 0:
				slot = charms.find({})
				if slot < 0:
					slot = charms.size() - 1
			bag.remove_at(i)
			if not charms[slot].is_empty():
				bag.insert(i, charms[slot])
			charms[slot] = inst
			_after_equip(true)
		"vial", "flare":
			if slot < 0:
				slot = -1
				for k in quick.size():
					if not quick[k].is_empty() and quick[k].id == inst.id and quick[k].r == inst.r:
						slot = k
				if slot < 0:
					slot = quick.find({})
				if slot < 0:
					slot = 0
			bag.remove_at(i)
			var q: Dictionary = quick[slot]
			if not q.is_empty() and q.id == inst.id and q.r == inst.r:
				q.n += inst.n
			else:
				if not q.is_empty():
					bag.insert(i, q)
				quick[slot] = inst
			_after_equip(false)
		_:
			return false
	return true


## Move an equipped item back into the bag. slot_kind: "weapon" | "charm" | "quick".
func unequip(slot_kind: String, idx: int = 0) -> bool:
	if is_full():
		return false
	match slot_kind:
		"weapon":
			return false # Sol always keeps a blade in hand: equip another one to swap
		"charm":
			if charms[idx].is_empty():
				return false
			bag.append(charms[idx])
			charms[idx] = {}
			_after_equip(true)
		"quick":
			if quick[idx].is_empty():
				return false
			bag.append(quick[idx])
			quick[idx] = {}
			_after_equip(false)
	return true


## Quick-use in the field: 1 / 2 on the keyboard, LB / R3 on a controller.
func _process(_delta: float) -> void:
	if main == null or not main.started or main.game_over or main.menu_open():
		return
	for i in quick.size():
		if not Input.is_action_just_pressed("quick_%d" % (i + 1)):
			continue
		# LB doubles as "drink bagged blood" at the Undercroft; the lair wins there
		if Input.is_action_just_pressed("drink") and main.player.global_position.distance_to(main.lair_pos) < 3.5:
			continue
		if quick[i].is_empty():
			main.hud.popup("QUICK SLOT %d IS EMPTY  ·  assign one in the Coat" % (i + 1))
		else:
			use_quick(i)


func _after_equip(stats: bool) -> void:
	changed.emit()
	if stats:
		equipment_changed.emit()


## Use a quick slot (key 1 / 2). Returns true if something was used.
func use_quick(idx: int) -> bool:
	if idx < 0 or idx >= quick.size() or quick[idx].is_empty():
		return false
	var inst: Dictionary = quick[idx]
	if not _consume(inst):
		return false
	if inst.n <= 0:
		quick[idx] = {}
	changed.emit()
	return true


func use_bag(i: int) -> bool:
	if i < 0 or i >= bag.size() or not ItemDB.is_consumable(bag[i]):
		return false
	var inst: Dictionary = bag[i]
	if not _consume(inst):
		return false
	if inst.n <= 0:
		bag.remove_at(i)
	changed.emit()
	return true


func _consume(inst: Dictionary) -> bool:
	var p = main.player if main != null else null
	if p == null or p.dead:
		return false
	var d := ItemDB.get_def(inst.id)
	match d.kind:
		"vial":
			if p.hp >= p.max_hp and d.get("hunger", 0.0) >= 0.0:
				if main.hud != null:
					main.hud.popup("ALREADY AT FULL BLOOD")
				return false
			p.heal(ItemDB.heal_amount(inst))
			p.hunger = clampf(p.hunger + d.get("hunger", 0.0), 0.0, 100.0)
			if main.hud != null:
				main.hud.popup("%s  +%d" % [d.name.to_upper(), roundi(ItemDB.heal_amount(inst))])
		"flare":
			if main.fx != null:
				main.fx.dawn_flare(p.global_position + p._forward() * 2.5, d.radius, ItemDB.flare_power(inst))
		_:
			return false
	inst.n -= 1
	item_used.emit(inst)
	return true


## Remove the bag item at i and return it (the caller drops it in the world).
func take_from_bag(i: int) -> Dictionary:
	if i < 0 or i >= bag.size():
		return {}
	var inst: Dictionary = bag[i]
	bag.remove_at(i)
	changed.emit()
	return inst


func take_from_slot(slot_kind: String, idx: int) -> Dictionary:
	var inst := {}
	match slot_kind:
		"weapon":
			return {} # the blade can be swapped, not thrown away
		"charm":
			inst = charms[idx]
			charms[idx] = {}
			_after_equip(true)
		"quick":
			inst = quick[idx]
			quick[idx] = {}
			_after_equip(false)
	return inst


# ---------------------------------------------------------------- save
func to_dict() -> Dictionary:
	return {"bag": bag.duplicate(true), "weapon": weapon.duplicate(), "charms": charms.duplicate(true), "quick": quick.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	bag = []
	for inst in d.get("bag", []):
		var v := _valid(inst)
		if not v.is_empty() and bag.size() < BAG_SIZE:
			bag.append(v)
	var w := _valid(d.get("weapon", {}))
	weapon = w if not w.is_empty() and ItemDB.kind_of(w) == "blade" else ItemDB.make(STARTER)
	var cs: Array = d.get("charms", [])
	for i in charms.size():
		var c := _valid(cs[i] if i < cs.size() else {})
		charms[i] = c if not c.is_empty() and ItemDB.kind_of(c) == "charm" else {}
	var qs: Array = d.get("quick", [])
	for i in quick.size():
		var q := _valid(qs[i] if i < qs.size() else {})
		quick[i] = q if not q.is_empty() and ItemDB.is_consumable(q) else {}
	changed.emit()
	equipment_changed.emit()


## JSON numbers come back as floats; rebuild a clean instance or {} if unknown.
func _valid(inst) -> Dictionary:
	if not inst is Dictionary or not inst.has("id") or ItemDB.get_def(str(inst.id)).is_empty():
		return {}
	return ItemDB.make(str(inst.id), int(inst.get("r", 0)), maxi(int(inst.get("n", 1)), 1))
