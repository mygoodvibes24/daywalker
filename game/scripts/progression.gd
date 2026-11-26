class_name Progression
extends Node
## Sol's progression: Tithe (the blood-essence currency), Communion rank (levels),
## Vows (passive perks picked on each rank) and the save file.
## Lives as a child of main; the player reads its numbers through player.stat().

signal tithe_changed(total: int)
signal leveled_up(level: int)
signal vows_changed
signal stats_changed

const ItemDB = preload("res://scripts/items/item_db.gd")
const Rites = preload("res://scripts/hunt/blood_rite.gd")

const MAX_LEVEL := 15
const BASE_HP := 100.0
## What every rank adds on its own.
const PER_LEVEL := {"max_hp": 8.0, "dmg": 0.04, "dash_rate": 0.04, "bite_heal": 0.05}
## Tithe for a kill, by enemy; draining with a bite pays extra.
const KILL_TITHE := {"vampire": 8, "civilian": 12, "werewolf": 25, "moon_wolf": 40}
const DRAIN_BONUS := 1.5

## Overridden by the smoke test so it never touches the player's real save.
static var save_path := "user://save.json"

## Vows: one is offered from three on every new rank. Flags are read by fx.gd / this file.
const VOWS := {
	"crimson_wake": {"name": "Crimson Wake", "desc": "Your Blood Dash leaves a burning trail of blood that scalds anything that crosses it.", "mods": {"blood_trail": 1.0}},
	"sidestep": {"name": "Sidestep Sacrament", "desc": "Perfect dodges heal 12 blood.", "mods": {"dodge_heal": 12.0}},
	"communion_ward": {"name": "Communion Ward", "desc": "For 1.5 s after a bite nothing can touch you.", "mods": {"bite_ward": 1.0}},
	"crescent_rite": {"name": "Crescent Rite", "desc": "The third strike of a combo throws a crescent of blood that cuts through a line of enemies.", "mods": {"crescent": 1.0}},
	"sunward": {"name": "Sunward", "desc": "Sunlight heals you three times as fast.", "mods": {"sun_heal": 2.0}},
	"long_night": {"name": "The Long Night", "desc": "Frenzy lasts 60% longer.", "mods": {"frenzy_time": 0.6}},
	"ashmaker": {"name": "Ashmaker", "desc": "+30% damage to vampires.", "mods": {"vs_vamp": 0.3}},
	"wolfsbane_veins": {"name": "Wolfsbane Veins", "desc": "+30% damage to werewolves, and wolf blood no longer burns you.", "mods": {"vs_wolf": 0.3, "wolf_noburn": 1.0}},
	"hemophage": {"name": "Hemophage", "desc": "5% of all blade damage flows back to you as blood.", "mods": {"lifesteal": 0.05}},
	"collector": {"name": "Collection Plate", "desc": "+30% Tithe, and motes find you from twice as far.", "mods": {"tithe_mult": 0.3, "magnet": 1.0}},
	"thick_blood": {"name": "Thick Blood", "desc": "+25 max blood.", "mods": {"max_hp": 25.0}},
	"quickened": {"name": "Quickened Step", "desc": "Blood Dash recharges 30% faster.", "mods": {"dash_rate": 0.3}},
	"stone_skin": {"name": "Crypt Stone", "desc": "Take 15% less damage.", "mods": {"dmg_taken": -0.15}},
	"scavenger": {"name": "Scavenger's Eye", "desc": "Much better odds of rare loot from kills and caches.", "mods": {"loot_luck": 0.3}},
	"fleet": {"name": "Fleet of Foot", "desc": "+10% move speed.", "mods": {"speed": 0.1}},
	"red_harvest": {"name": "Red Harvest", "desc": "Every kill heals 4 blood.", "mods": {"kill_heal": 4.0}},
	"second_bite": {"name": "Second Bite", "desc": "Bites heal 20% more and refund a Blood Dash.", "mods": {"bite_heal": 0.2, "second_bite": 1.0}},
}

var main
var inventory # inventory.gd
var level := 1
var tithe := 0
var vows: Array = []
var vow_choices: Array = [] # the three offered and not yet picked
## HUNT: Blood Rites taken this run (blood_rite.gd RITES ids), the three on offer, tonight's
## modifier mods (hunt_config.gd NIGHT_MODIFIERS) and run bonuses from micro-POIs (shrines).
var rites: Array = []
var rite_choices: Array = []
var night_mods: Dictionary = {}
var run_mods: Dictionary = {}
var death_drop := {} # {"pos": [x, y, z], "amount": n} — Tithe lost at the last death
var stats := {}
var rng := RandomNumberGenerator.new()
## HUNT HOOK: false during a Hunt, where rank / Tithe / Vows / the Coat are run-scoped.
var persist := true


func _ready() -> void:
	rng.randomize()


## Tithe needed to go from `lv` to `lv + 1`: cheap at first, then rising steadily.
static func cost_for(lv: int) -> int:
	return int(round(25.0 + 15.0 * pow(float(lv - 1), 1.45)))


func next_cost() -> int:
	return cost_for(level)


func can_level() -> bool:
	return level < MAX_LEVEL and tithe >= next_cost() and vow_choices.is_empty()


func stat(key: String) -> float:
	return stats.get(key, 0.0)


func has_flag(key: String) -> bool:
	return stats.get(key, 0.0) > 0.0


## Rebuild the stat table from rank, Vows and equipment, then push it to the player.
func recompute() -> void:
	var s := {}
	for k in PER_LEVEL:
		s[k] = PER_LEVEL[k] * (level - 1)
	for id in vows:
		_add_mods(s, VOWS.get(id, {}).get("mods", {}))
	for id in rites:
		_add_mods(s, Rites.RITES.get(id, {}).get("mods", {}))
	_add_mods(s, night_mods)
	_add_mods(s, run_mods)
	if inventory != null:
		for inst in inventory.equipped_items():
			_add_mods(s, ItemDB.item_mods(inst))
	stats = s
	_apply_to_player()
	stats_changed.emit()


func _add_mods(s: Dictionary, mods: Dictionary) -> void:
	for k in mods:
		s[k] = s.get(k, 0.0) + mods[k]


func _apply_to_player() -> void:
	var p = main.player if main != null else null
	if p == null:
		return
	var new_max := BASE_HP + stat("max_hp")
	var gained: float = new_max - p.max_hp
	p.max_hp = new_max
	p.hp = clampf(p.hp + maxf(gained, 0.0), 0.0, new_max) if not p.dead else p.hp


func weapon_stats() -> Dictionary:
	return ItemDB.weapon_stats(inventory.weapon if inventory != null else {})


# ---------------------------------------------------------------- tithe
## Tithe a kill is worth (before collection). Vows/charms multiply it.
func kill_value(e: Node, drained: bool) -> int:
	var key := "vampire"
	if e.kind == 1:
		key = ("moon_wolf" if e.max_hp >= 150.0 else "werewolf") if e.transformed else "civilian"
	var v := float(KILL_TITHE[key])
	if e.get("tithe_value") != null: # an elite (the Undercroft's rival daywalker) names its own worth
		v = float(e.get("tithe_value"))
	if drained:
		v *= DRAIN_BONUS
	return int(round(v * (1.0 + stat("tithe_mult"))))


func add_tithe(n: int) -> void:
	if n == 0:
		return
	tithe = maxi(tithe + n, 0)
	tithe_changed.emit(tithe)


# ---------------------------------------------------------------- levels
func level_up() -> bool:
	if not can_level():
		return false
	tithe -= next_cost()
	level += 1
	recompute()
	var p = main.player
	if p != null:
		p.hp = p.max_hp # a new rank fills you up
	vow_choices = roll_vows(3)
	tithe_changed.emit(tithe)
	leveled_up.emit(level)
	Audio.play("level_up"); Dialogue.play_group("bark_levelup_") # AUDIO HOOK
	save()
	return true


func roll_vows(n: int) -> Array:
	var pool: Array = []
	for id in VOWS:
		if not id in vows:
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, mini(n, pool.size()))


func choose_vow(id: String) -> void:
	if not VOWS.has(id) or id in vows:
		return
	vows.append(id)
	vow_choices.clear()
	recompute()
	vows_changed.emit()
	save()


func level_gain_text() -> String:
	return "+%d max blood   +%d%% damage   +%d%% dash recharge   +%d%% bite healing" % [
		PER_LEVEL.max_hp, PER_LEVEL.dmg * 100.0, PER_LEVEL.dash_rate * 100.0, PER_LEVEL.bite_heal * 100.0]


# ---------------------------------------------------------------- combat hooks (player signals)
func connect_player(p) -> void:
	p.hit_enemy.connect(_on_hit)
	p.bit_enemy.connect(_on_bite)
	p.hurt.connect(_on_hurt)
	# Blood Rite effects that hang off Sol's own signals (blood_rite.gd)
	p.parried.connect(func(e): Rites.on_parried(self, e))
	p.dashed.connect(func(dir): Rites.on_dashed(self, dir))
	p.attacked.connect(func(c, fwd): Rites.on_attacked(self, c, fwd))
	p.special_move.connect(func(n): Rites.on_special(self, n))


func _on_hit(_e, dmg: float) -> void:
	if stat("lifesteal") > 0.0:
		main.player.heal(dmg * stat("lifesteal"))


func _on_bite(_e, blood: int) -> void:
	var p = main.player
	if has_flag("bite_ward"):
		p.invuln_t = maxf(p.invuln_t, 1.5)
	if has_flag("second_bite"):
		p.dash_charges = minf(p.dash_charges + 1.0, p.MAX_DASH)
	if blood == 2 and has_flag("wolf_noburn"):
		p.burn_t = 0.0
	Rites.on_bite(self, _e)


func _on_hurt(_amount: float, src) -> void:
	if stat("reflect") > 0.0 and src != null and is_instance_valid(src) and src.has_method("take_hit") and not src.dead and not src.staggered:
		var dir: Vector3 = src.global_position - main.player.global_position
		dir.y = 0.0
		src.take_hit(stat("reflect"), dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD)


func on_perfect_dodge() -> void:
	if stat("dodge_heal") > 0.0:
		main.player.heal(stat("dodge_heal"))


func on_kill(e: Node) -> void:
	var p = main.player
	if p == null or p.dead:
		return
	if stat("kill_heal") > 0.0:
		p.heal(stat("kill_heal"))
	if has_flag("moonsplit") and e.kind == 1 and e.transformed:
		p.dash_charges = minf(p.dash_charges + 1.0, p.MAX_DASH)
	if has_flag("kill_dash"):
		p.dash_charges = minf(p.dash_charges + 0.5, p.MAX_DASH)


func _process(delta: float) -> void:
	# Odette's Last Bag: the sun heals even when the normal Daywalker rule wouldn't
	if has_flag("sun_any") and main != null and main.player != null and not main.player.dead:
		var p = main.player
		if main.daylight() > 0.3 and not (p.hunger < 30.0 and p.since_hurt > 4.0):
			p.heal(p.SUN_HEAL * (1.0 + stat("sun_heal")) * delta)


# ---------------------------------------------------------------- Blood Rites (run-scoped)
## Offer three Rites not yet taken (fewer if the pool runs dry). Returns the offer.
func offer_rites(n := 3) -> Array:
	rite_choices = Rites.roll(rites, n, rng)
	return rite_choices


func choose_rite(id: String) -> bool:
	if not Rites.RITES.has(id) or id in rites or not id in rite_choices:
		return false
	rites.append(id)
	rite_choices.clear()
	recompute()
	var p = main.player if main != null else null
	if p != null and not p.dead:
		p.hp = p.max_hp # the rite fills you
	vows_changed.emit()
	return true


## Tonight's modifier (hunt_director.gd); {} clears it.
func set_night_mods(mods: Dictionary) -> void:
	night_mods = mods.duplicate()
	recompute()


func add_run_mod(key: String, v: float) -> void:
	run_mods[key] = float(run_mods.get(key, 0.0)) + v
	recompute()


# ---------------------------------------------------------------- death
## Half the carried Tithe stays where Sol fell. An older unrecovered drop is gone for good.
func on_death(pos: Vector3) -> void:
	var lost := tithe / 2
	tithe -= lost
	death_drop = {"pos": [pos.x, pos.y, pos.z], "amount": lost} if lost > 0 else {}
	save()


func recover_death_drop() -> int:
	var n: int = death_drop.get("amount", 0)
	death_drop = {}
	add_tithe(n)
	save()
	return n


# ---------------------------------------------------------------- save / load
func to_dict() -> Dictionary:
	return {"version": 1, "level": level, "tithe": tithe, "vows": vows.duplicate(), "vow_choices": vow_choices.duplicate(),
		"death_drop": death_drop.duplicate(true), "inventory": inventory.to_dict() if inventory != null else {}}


func from_dict(d: Dictionary) -> void:
	level = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
	tithe = maxi(int(d.get("tithe", 0)), 0)
	vows = []
	for v in d.get("vows", []):
		if VOWS.has(str(v)) and not str(v) in vows:
			vows.append(str(v))
	vow_choices = []
	for v in d.get("vow_choices", []):
		if VOWS.has(str(v)):
			vow_choices.append(str(v))
	death_drop = d.get("death_drop", {})
	if inventory != null:
		inventory.from_dict(d.get("inventory", {}))
	recompute()
	tithe_changed.emit(tithe)


func save() -> bool:
	if not persist:
		return true # HUNT HOOK: nothing run-scoped is written
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return true


func load_save() -> bool:
	if not FileAccess.file_exists(save_path):
		recompute()
		return false
	var txt := FileAccess.get_file_as_string(save_path)
	var d = JSON.parse_string(txt)
	if not d is Dictionary:
		recompute()
		return false
	from_dict(d)
	return true


func reset() -> void:
	level = 1
	tithe = 0
	vows = []
	vow_choices = []
	rites = []
	rite_choices = []
	night_mods = {}
	run_mods = {}
	death_drop = {}
	if inventory != null:
		inventory.reset()
	recompute()
	tithe_changed.emit(tithe)
