extends RefCounted
## The Arsenal (round 4): Sol's weapon types as data. Every blade item (item_db.gd) belongs to a family,
## and every family to one of these types. A type says how the weapon fights:
##
##   label      shown in the Coat, the hub and tooltips
##   chain      the light combo (sol_moves.gd COMBOS; arsenal_moves.gd adds the new ones)
##   heavy      the held-attack charged move
##   routes     the special combo moves (arsenal.gd): llh (tap, tap, hold), dodge (hold through the
##              thrust out of a Blood Dash), sprint (hold through the running slash), jump (attack in
##              the air), plunge (hold attack in the air), riposte (attack after a parry), chain (the
##              Weapon Art button right after the third hit: the blood-chain finisher)
##   art        the Weapon Art (arsenal_moves.gd ARTS)
##   stagger    poise damage per point of damage (1.0 = the longsword)
##   stamina    multiplier on every move's stamina_cost (Group B's stamina reads it)
##   affinity   silver (the Pack), holy (the Court), fire (the Court, burns), bleed (builds to a burst)
##   bleed      bleed build-up per point of damage (0 = none)
##   trail      slash-trail colour
##   mount      where the blade rides when sheathed: a sol_sheath.gd MOUNTS preset (its FAMILY_MOUNT
##              maps every family of the type to the same preset)
##   dual       true: a second copy rides in the left hand (BladeL)

const AFFINITY_TEXT := {
	"silver": "Silver  (+35% vs the Pack, breaks wolves)",
	"holy": "Holy  (+35% vs the Court)",
	"fire": "Fire  (+20% vs the Court, sets them burning)",
	"bleed": "Bleed  (builds to a Hemorrhage burst)",
}
const AFFINITY_COLOR := {
	"silver": Color(0.75, 0.85, 1.0), "holy": Color(1.0, 0.82, 0.4), "fire": Color(1.0, 0.45, 0.12), "bleed": Color(0.9, 0.04, 0.08),
}

const TYPES := {
	"longsword": {"label": "Silver Longsword", "chain": "light", "heavy": "charged", "art": "silver_nova",
		"stagger": 1.0, "stamina": 1.0, "affinity": "silver", "bleed": 0.0, "trail": Color(0.75, 0.85, 1.0),
		"routes": {"llh": "ls_llh", "dodge": "ls_dodge", "sprint": "ls_sprint", "jump": "jump_cut", "plunge": "plunge",
			"riposte": "riposte", "chain": "blood_chain"},
		"mount": "back"},
	"cleaver": {"label": "Cleaver", "chain": "heavy", "heavy": "charged", "art": "butcher_cleave",
		"stagger": 1.6, "stamina": 1.2, "affinity": "bleed", "bleed": 0.6, "trail": Color(0.85, 0.2, 0.15),
		"routes": {"llh": "cl_llh", "dodge": "ls_dodge", "sprint": "hv_sprint", "jump": "jump_cut", "plunge": "plunge",
			"riposte": "riposte", "chain": "blood_chain"},
		"mount": "back"},
	"katana": {"label": "Katana", "chain": "katana", "heavy": "kt_charged", "art": "blood_wave",
		"stagger": 0.8, "stamina": 0.85, "affinity": "bleed", "bleed": 1.6, "trail": Color(1.0, 0.15, 0.2),
		"routes": {"llh": "kt_llh", "dodge": "kt_dodge", "sprint": "ls_sprint", "jump": "jump_cut", "plunge": "plunge",
			"riposte": "riposte", "chain": "blood_chain"},
		"mount": "hip"},
	"daggers": {"label": "Twin Stakes", "chain": "daggers", "heavy": "dg_charged", "art": "crimson_flurry",
		"stagger": 0.5, "stamina": 0.6, "affinity": "holy", "bleed": 0.9, "trail": Color(1.0, 0.8, 0.45), "dual": true,
		"routes": {"llh": "dg_llh", "dodge": "dg_dodge", "sprint": "dg_sprint", "jump": "jump_cut", "plunge": "plunge",
			"riposte": "riposte", "chain": "blood_chain"},
		"mount": "hip_right"},
	"greatsword": {"label": "Greatsword", "chain": "great", "heavy": "gs_charged", "art": "rising_launcher",
		"stagger": 2.2, "stamina": 1.5, "affinity": "fire", "bleed": 0.0, "trail": Color(1.0, 0.5, 0.15),
		"routes": {"llh": "gs_llh", "dodge": "gs_dodge", "sprint": "hv_sprint", "jump": "jump_cut", "plunge": "plunge",
			"riposte": "riposte", "chain": "blood_chain"},
		"mount": "back_great"},
	"halberd": {"label": "Halberd", "chain": "halberd", "heavy": "hb_charged", "art": "impaling_rush",
		"stagger": 1.3, "stamina": 1.2, "affinity": "silver", "bleed": 0.0, "trail": Color(0.8, 0.9, 1.0),
		"routes": {"llh": "hb_llh", "dodge": "hb_dodge", "sprint": "hb_sprint", "jump": "jump_cut", "plunge": "plunge",
			"riposte": "riposte", "chain": "blood_chain"},
		"mount": "back_great"},
	"scythe": {"label": "Scythe", "chain": "scythe", "heavy": "sc_charged", "art": "whirlwind",
		"stagger": 1.1, "stamina": 1.15, "affinity": "bleed", "bleed": 1.3, "trail": Color(0.7, 0.05, 0.25),
		"routes": {"llh": "sc_llh", "dodge": "sc_dodge", "sprint": "hb_sprint", "jump": "jump_cut", "plunge": "plunge",
			"riposte": "riposte", "chain": "blood_chain"},
		"mount": "back_great"},
	"hammer": {"label": "War Hammer", "chain": "hammer", "heavy": "hm_charged", "art": "leaping_slam",
		"stagger": 2.6, "stamina": 1.45, "affinity": "silver", "bleed": 0.0, "trail": Color(0.85, 0.9, 1.0),
		"wolf_break": true,
		"routes": {"llh": "hm_llh", "dodge": "gs_dodge", "sprint": "hm_sprint", "jump": "jump_cut", "plunge": "plunge_heavy",
			"riposte": "riposte", "chain": "blood_chain"},
		"mount": "back"},
	"whip": {"label": "Chain-Whip", "chain": "whip", "heavy": "wh_charged", "art": "chain_lash",
		"stagger": 0.7, "stamina": 0.9, "affinity": "fire", "bleed": 0.4, "trail": Color(1.0, 0.55, 0.2),
		"routes": {"llh": "wh_llh", "dodge": "wh_dodge", "sprint": "wh_sprint", "jump": "jump_cut", "plunge": "plunge",
			"riposte": "riposte", "chain": "blood_chain"},
		"mount": "hip_right"},
}

## Blade family (item_db.gd) -> weapon type.
const FAMILY_TYPE := {
	"saber": "longsword", "cane": "longsword", "longblade": "longsword",
	"cleaver": "cleaver", "machete": "cleaver", "kukri": "cleaver",
	"katana": "katana", "daggers": "daggers", "greatsword": "greatsword", "halberd": "halberd",
	"scythe": "scythe", "hammer": "hammer", "whip": "whip",
}

const DEFAULT_TYPE := "longsword"


static func type_of_family(family: String) -> String:
	return FAMILY_TYPE.get(family, DEFAULT_TYPE)


static func get_type(t: String) -> Dictionary:
	return TYPES.get(t, TYPES[DEFAULT_TYPE])
