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
		"loadout": [0, -1, -1], # armoury indices worn into the next Hunt
		"blades": ["marrow_silver"], # the Arsenal: blade ids on Nia's rack (one per weapon type to buy)
		"start_blade": "marrow_silver"} # the blade Sol carries into the next Hunt


## The Arsenal (round 4): one blade of every weapon type on Nia's rack, bought once with Sunmarks;
## the one chosen in the Undercroft is the blade Sol starts the Hunt with (Street rarity).
const BLADE_RACK := [
	{"id": "marrow_silver", "price": 0}, {"id": "hunter_silver", "price": 30}, {"id": "dock_machete", "price": 30},
	{"id": "ronin_katana", "price": 50}, {"id": "hawthorn_stakes", "price": 50}, {"id": "levee_halberd", "price": 60},
	{"id": "canefield_scythe", "price": 60}, {"id": "cathedral_slab", "price": 70}, {"id": "foundry_maul", "price": 70},
	{"id": "censer_chain", "price": 60},
]


static func owns_blade(id: String) -> bool:
	ensure()
	return id in data.blades


static func buy_blade(id: String) -> bool:
	ensure()
	if owns_blade(id):
		return false
	for e in BLADE_RACK:
		if e.id == id and data.sunmarks >= e.price:
			data.sunmarks -= e.price
			data.blades.append(id)
			data.start_blade = id
			save_meta()
			return true
	return false


static func choose_blade(id: String) -> bool:
	ensure()
	if not owns_blade(id):
		return false
	data.start_blade = id
	return true


## The blade instance Sol carries into the Hunt.
static func start_blade() -> Dictionary:
	ensure()
	var id := String(data.get("start_blade", "marrow_silver"))
	if not owns_blade(id) or ItemDB.kind_of({"id": id}) != "blade":
		id = "marrow_silver"
	return ItemDB.make(id)


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
	var blades: Array = ["marrow_silver"]
	if data.blades is Array:
		for b in data.blades:
			if b is String and ItemDB.get_def(b).get("kind", "") == "blade" and not b in blades:
				blades.append(b)
	data.blades = blades
	data.start_blade = String(data.start_blade) if String(data.start_blade) in blades else "marrow_silver"


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
