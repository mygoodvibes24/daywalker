extends RefCounted
## What survives between Hunts: Sunmarks (the meta currency), the charm armoury and the
## loadout you equip in the Undercroft, plus your record. Everything else (rank, Tithe, Vows,
## carried blades and vials) is run-scoped and starts over each Hunt.
## Saved to user://hunt_meta.json (the smoke test points `path` elsewhere).

const ItemDB = preload("res://scripts/items/item_db.gd")
const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const LOADOUT_SLOTS := 3

static var path := "user://hunt_meta.json"
## Set by the results screen so the main menu opens straight on the Undercroft hub.
static var return_to_hub := false

static var data := {}
static var _loaded := false


static func defaults() -> Dictionary:
	return {"version": 1, "sunmarks": 0, "hunts": 0, "wins": 0, "best_bosses": 0, "best_rank": 1, "total_kills": 0,
		"bosses_slain": 0, "last": {},
		"armoury": [ItemDB.make("red_flannel"), ItemDB.make("john_root")], # charm instances owned for good
		"loadout": [0, -1, -1]} # armoury indices worn into the next Hunt


static func ensure() -> Dictionary:
	if not _loaded:
		load_meta()
	return data


static func load_meta() -> void:
	_loaded = true
	data = defaults()
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return
	for k in data:
		if d.has(k):
			data[k] = d[k]
	# JSON numbers come back as floats: rebuild clean charm instances
	var arm: Array = []
	for inst in data.armoury:
		if inst is Dictionary and inst.has("id") and ItemDB.get_def(str(inst.id)).get("kind", "") == "charm":
			arm.append(ItemDB.make(str(inst.id), int(inst.get("r", 0))))
	data.armoury = arm
	var lo: Array = []
	for i in LOADOUT_SLOTS:
		var v := int(data.loadout[i]) if i < data.loadout.size() else -1
		lo.append(v if v >= 0 and v < arm.size() and not v in lo else -1)
	data.loadout = lo
	for k in ["sunmarks", "hunts", "wins", "best_bosses", "best_rank", "total_kills", "bosses_slain"]:
		data[k] = int(data[k])


static func save_meta() -> bool:
	ensure()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


static func reset_meta() -> void:
	data = defaults()
	_loaded = true


## The charm instances worn into the Hunt, one per loadout slot ({} for empty).
static func loadout_charms() -> Array:
	ensure()
	var out: Array = []
	for i in LOADOUT_SLOTS:
		var idx: int = data.loadout[i]
		out.append(data.armoury[idx].duplicate() if idx >= 0 and idx < data.armoury.size() else {})
	return out


## Toggle an armoury charm into the first free slot (or out, if it is already worn).
static func toggle_loadout(armoury_idx: int) -> void:
	ensure()
	var lo: Array = data.loadout
	var at := lo.find(armoury_idx)
	if at >= 0:
		lo[at] = -1
		return
	var free := lo.find(-1)
	lo[free if free >= 0 else LOADOUT_SLOTS - 1] = armoury_idx


static func owns(id: String) -> bool:
	ensure()
	for inst in data.armoury:
		if inst.id == id:
			return true
	return false


## Add a charm to the armoury; a better copy of one you own replaces it.
static func add_charm(inst: Dictionary) -> bool:
	ensure()
	if inst.is_empty() or ItemDB.kind_of(inst) != "charm":
		return false
	for i in data.armoury.size():
		var a: Dictionary = data.armoury[i]
		if a.id == inst.id:
			if int(inst.r) > int(a.r):
				data.armoury[i] = ItemDB.make(inst.id, int(inst.r))
				return true
			return false
	data.armoury.append(ItemDB.make(inst.id, int(inst.r)))
	return true


static func buy(id: String) -> bool:
	ensure()
	if owns(id):
		return false
	for e in Cfg.ARMOURY_SHOP:
		if e.id == id and data.sunmarks >= e.price:
			data.sunmarks -= e.price
			add_charm(ItemDB.make(id))
			save_meta()
			return true
	return false


## Sunmarks a Hunt pays out.
static func earnings(bosses: int, kills: int, rank: int, won: bool) -> int:
	return 10 + kills / 2 + bosses * 40 + (rank - 1) * 5 + (60 if won else 0)


## Book a finished Hunt: pay out, keep the record and sew carried charms into the armoury.
static func record_hunt(summary: Dictionary, carried_charms: Array) -> int:
	ensure()
	var earned := earnings(summary.bosses, summary.kills, summary.rank, summary.won)
	data.sunmarks += earned
	data.hunts += 1
	if summary.won:
		data.wins += 1
	data.best_bosses = maxi(data.best_bosses, summary.bosses)
	data.best_rank = maxi(data.best_rank, summary.rank)
	data.total_kills += summary.kills
	data.bosses_slain += summary.bosses
	var kept: Array = []
	for c in carried_charms:
		if add_charm(c):
			kept.append(ItemDB.display_name(c))
	var last: Dictionary = summary.duplicate()
	last["earned"] = earned
	last["kept"] = kept
	data.last = last
	save_meta()
	return earned
