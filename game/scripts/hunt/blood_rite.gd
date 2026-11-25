class_name BloodRite
extends RefCounted
## The Blood Rite: after every boss (the night bosses and the Landmark horrors) Sol drinks from
## what he killed and takes one of three run-scoped boons that change how he fights, the way
## Nightreign's relic and level-up picks shape a run. Rites are stronger and stranger than Vows
## (progression.gd): each one rewrites a move. Data here; the stat mods go through progression's
## stat table, the move hooks hang off Sol's signals (progression.connect_player -> on_*).

const HFx = preload("res://scripts/hunt/hunt_fx.gd")

## id -> {name, sigil, desc, mods}. Flags in mods are read by the on_* hooks below (and by the
## director for curfew_resist).
const RITES := {
	"sanguine_riposte": {"name": "Sanguine Riposte", "sigil": "⚔", "tag": "PARRY",
		"desc": "A perfect parry drinks 20 blood from the strike and refunds a Blood Dash.",
		"mods": {"parry_heal": 20.0}},
	"long_shadow": {"name": "Long Shadow", "sigil": "➶", "tag": "DASH",
		"desc": "Your Blood Dash carries 60% farther, untouchable the whole way.",
		"mods": {"dash_len": 0.6}},
	"red_afterimage": {"name": "Red Afterimage", "sigil": "♦", "tag": "DASH",
		"desc": "Where you dash from, a bleeding afterimage bursts a moment later for heavy damage.",
		"mods": {"afterimage": 1.0}},
	"deep_communion": {"name": "Deep Communion", "sigil": "❦", "tag": "BITE",
		"desc": "Bites heal 60% more, and the blood bursts out of the victim, cutting everything near.",
		"mods": {"bite_heal": 0.6, "bite_burst": 1.0}},
	"butchers_frenzy": {"name": "Butcher's Frenzy", "sigil": "☩", "tag": "EXECUTION",
		"desc": "Every execution throws you into a 6-second Frenzy.",
		"mods": {"exec_frenzy": 6.0}},
	"fourth_cut": {"name": "The Fourth Cut", "sigil": "✠", "tag": "COMBO",
		"desc": "Your combo grows a fourth hit: a phantom blade follows the third strike for 150% damage.",
		"mods": {"echo_cut": 1.5}},
	"curfew_born": {"name": "Curfew-Born", "sigil": "◉", "tag": "CURFEW",
		"desc": "The Red Curfew's fog burns you 70% less. Tithe +20%.",
		"mods": {"curfew_resist": 0.7, "tithe_mult": 0.2}},
	"vampiric_edge": {"name": "Vampiric Edge", "sigil": "♰", "tag": "BLADE",
		"desc": "10% of all blade damage flows back to you as blood.",
		"mods": {"lifesteal": 0.1}},
	"bloodhound": {"name": "Bloodhound", "sigil": "☾", "tag": "KILLS",
		"desc": "Every kill refunds half a Blood Dash. +12% move speed.",
		"mods": {"kill_dash": 1.0, "speed": 0.12}},
	"undercroft_heart": {"name": "Heart of the Undercroft", "sigil": "♥", "tag": "BODY",
		"desc": "+40 max blood and +10% damage.",
		"mods": {"max_hp": 40.0, "dmg": 0.1}},
	# ---- the Arsenal (round 4): Rites that feed the weapon types (items/arsenal.gd reads the mods).
	# "types": the weapon types a Rite resonates with; roll() always offers one that suits your blade.
	"open_veins": {"name": "Open Veins", "sigil": "✚", "tag": "BLEED", "types": ["katana", "daggers", "scythe", "cleaver"],
		"desc": "Bleed builds 80% faster, and every Hemorrhage you open heals you 10.",
		"mods": {"bleed": 0.8, "bleed_heal": 10.0}},
	"shatterer": {"name": "The Shatterer", "sigil": "✸", "tag": "STAGGER", "types": ["greatsword", "hammer", "halberd"],
		"desc": "+60% stagger. Breaking an enemy's stance refunds a Blood Dash.",
		"mods": {"poise": 0.6, "break_dash": 1.0}},
	"crimson_arts": {"name": "Crimson Arts", "sigil": "✺", "tag": "WEAPON ART",
		"types": ["longsword", "cleaver", "katana", "daggers", "greatsword", "halberd", "scythe", "hammer", "whip"],
		"desc": "Your Weapon Art recharges 40% faster and strikes 25% harder.",
		"mods": {"art_cd": 0.4, "art_dmg": 0.25}},
	"chain_of_blood": {"name": "Chain of Blood", "sigil": "⛓", "tag": "BLOOD CHAIN",
		"types": ["longsword", "katana", "daggers", "scythe", "whip"],
		"desc": "The Blood Chain finisher costs no blood, and the last hit of every chain lands 30% harder.",
		"mods": {"chain_free": 1.0, "finisher": 0.3}},
	"hallowed_edge": {"name": "Hallowed Edge", "sigil": "☀", "tag": "AFFINITY",
		"types": ["longsword", "daggers", "greatsword", "halberd", "hammer", "whip"],
		"desc": "Your blade's affinity bites twice as deep: silver, holy and fire bonuses doubled.",
		"mods": {"affinity": 1.0}},
}


## n Rites not in `taken`, in a random order. With `weapon_type` (arsenal_data.gd), one Rite that
## resonates with it (its "types") is always among the offer, if any is left.
static func roll(taken: Array, n: int, rng: RandomNumberGenerator, weapon_type := "") -> Array:
	var pool: Array = []
	for id in RITES:
		if not id in taken:
			pool.append(id)
	for k in range(pool.size() - 1, 0, -1):
		var s := rng.randi_range(0, k)
		var t = pool[k]
		pool[k] = pool[s]
		pool[s] = t
	var out: Array = pool.slice(0, mini(n, pool.size()))
	if weapon_type != "" and not out.any(func(id): return weapon_type in RITES[id].get("types", [])):
		for id in pool:
			if weapon_type in RITES[id].get("types", []) and not id in out:
				out[out.size() - 1] = id
				break
	return out


## True if Rite `id` resonates with weapon type `t`.
static func resonates(id: String, t: String) -> bool:
	return t in RITES.get(id, {}).get("types", [])


static func name_of(id: String) -> String:
	return String(RITES.get(id, {}).get("name", id))


# ---------------------------------------------------------------- move hooks (prog = progression.gd)
static func on_parried(prog, _e) -> void:
	var p = prog.main.player
	if p == null or p.dead or prog.stat("parry_heal") <= 0.0:
		return
	p.heal(prog.stat("parry_heal"))
	p.dash_charges = minf(p.dash_charges + 1.0, p.MAX_DASH)
	if prog.main.hud != null:
		prog.main.hud.popup("SANGUINE RIPOSTE  +%d" % int(prog.stat("parry_heal")))


static func on_dashed(prog, _dir: Vector3) -> void:
	var p = prog.main.player
	if p == null:
		return
	if prog.stat("dash_len") > 0.0:
		p.dash_t *= 1.0 + prog.stat("dash_len") # player.gd set dash_t just before it emitted `dashed`
		p.invuln_t = maxf(p.invuln_t, p.dash_t + 0.12)
	if prog.has_flag("afterimage"):
		var at: Vector3 = p.global_position
		var main = prog.main
		HFx.puff(main, at + Vector3(0, 1.0, 0), Color(0.7, 0.02, 0.05), 6, 0.15, 1.2)
		main.get_tree().create_timer(0.45, false).timeout.connect(func():
			if not is_instance_valid(main) or main.fx == null or main.player == null:
				return
			var dmg: float = 30.0 * main.player.damage_mult()
			main.fx.damage_area(at, 3.2, dmg)
			HFx.shockwave(main, at, 3.2, Color(1.0, 0.05, 0.1), 0.35))


static func on_attacked(prog, combo: int, fwd: Vector3) -> void:
	if combo != 3 or prog.stat("echo_cut") <= 0.0:
		return
	var main = prog.main
	var mult: float = prog.stat("echo_cut")
	main.get_tree().create_timer(0.3, false).timeout.connect(func():
		if is_instance_valid(main):
			echo_cut(main, fwd, mult))


## The Fourth Cut: a phantom blade strikes a cone in front of Sol.
static func echo_cut(main, fwd: Vector3, mult: float) -> int:
	var p = main.player
	if p == null or p.dead:
		return 0
	var w: Dictionary = p.weapon_stats()
	var dmg: float = float(w.dmg) * mult * p.damage_mult()
	var reach: float = 3.6 + float(w.reach)
	var n := 0
	for e in main.enemies_root.get_children():
		if e.dead or e.staggered:
			continue
		var to: Vector3 = e.global_position - p.global_position
		to.y = 0.0
		var d := to.length()
		if d < reach and (d < 0.9 or fwd.dot(to / d) > 0.2):
			var hd: float = dmg * (p._vs_mult(e) if p.has_method("_vs_mult") else 1.0)
			e.take_hit(hd, to.normalized() if d > 0.01 else fwd)
			p.hit_enemy.emit(e, hd)
			n += 1
	HFx.shockwave(main, p.global_position + fwd * 1.6, 2.0, Color(1.0, 0.1, 0.15), 0.25)
	if n > 0:
		Audio.play_at("sword_hit", p.global_position + fwd * 1.5, 2.0) # AUDIO HOOK
	return n


static func on_special(prog, name: String) -> void:
	if name != "finisher" or prog.stat("exec_frenzy") <= 0.0:
		return
	var p = prog.main.player
	if p == null or p.dead:
		return
	var t: float = prog.stat("exec_frenzy") * (1.0 + prog.stat("frenzy_time"))
	if p.frenzy_t <= 0.0 and prog.main.hud != null:
		prog.main.hud.popup("BUTCHER'S FRENZY")
	p.frenzy_t = maxf(p.frenzy_t, t)


static func on_bite(prog, e) -> void:
	if not prog.has_flag("bite_burst"):
		return
	var main = prog.main
	if main.fx == null or e == null or not is_instance_valid(e):
		return
	var at: Vector3 = e.global_position
	main.fx.damage_area(at, 4.5, 30.0 * main.player.damage_mult())
	HFx.shockwave(main, at, 4.5, Color(0.9, 0.0, 0.08), 0.4)
