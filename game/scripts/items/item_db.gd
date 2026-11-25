extends RefCounted
## Every item in the game, as data. An item *instance* is a small Dictionary
## {"id": String, "r": rarity 0..3, "n": stack count} so it saves straight to JSON.
##
## Stat keys (all additive, 0 = no effect) are read by progression.gd:
##   max_hp (flat)  dmg (+x damage)  dmg_taken (-x = less taken)  dash_rate  bite_heal
##   sun_heal  frenzy_time  speed  lifesteal (fraction of damage)  vs_vamp  vs_wolf
##   finisher (3rd combo hit)  tithe_mult  loot_luck  dodge_heal (HP)  kill_heal (HP)  night_dmg
## Flags (any value > 0 turns them on) are handled by progression.gd / loot.gd:
##   sunburst  moonsplit  sun_any  reflect  (plus the Vow flags in progression.gd)

const Arsenal = preload("res://scripts/items/arsenal_data.gd")
const ArsenalMoves = preload("res://scripts/items/arsenal_moves.gd")

enum { COMMON, UNCOMMON, RARE, LEGENDARY }

const RARITY_NAMES := ["Street", "Blooded", "Hallowed", "Eclipse"]
const RARITY_COLORS := [Color(0.86, 0.86, 0.82), Color(0.35, 0.95, 0.4), Color(0.3, 0.6, 1.0), Color(0.82, 0.42, 1.0)]
const RARITY_ACCENT := [Color(0.6, 0.6, 0.6), Color(0.2, 0.7, 0.25), Color(0.2, 0.4, 0.9), Color(1.0, 0.78, 0.3)] # beam core / gold
## How rarity scales an item: blade damage, then everything else.
const DMG_SCALE := [1.0, 1.12, 1.26, 1.45]
const STAT_SCALE := [1.0, 1.35, 1.75, 2.25]
## Extra perk every Eclipse-tier item carries.
const ECLIPSE_PERK := {"kill_heal": 3.0}

const STAT_TEXT := {
	"max_hp": "+%d max blood", "dmg": "+%d%% damage", "dmg_taken": "%d%% damage taken", "dash_rate": "+%d%% dash recharge",
	"bite_heal": "+%d%% bite healing", "sun_heal": "+%d%% sunlight healing", "frenzy_time": "+%d%% frenzy duration",
	"speed": "+%d%% move speed", "lifesteal": "%d%% of blade damage heals you", "vs_vamp": "+%d%% damage to vampires",
	"vs_wolf": "+%d%% damage to werewolves", "finisher": "+%d%% third-strike damage", "tithe_mult": "+%d%% Tithe gained",
	"loot_luck": "+%d%% find better loot", "dodge_heal": "Perfect dodges heal %d", "kill_heal": "Kills heal %d",
	"night_dmg": "+%d%% damage at night",
	# the Arsenal (round 4, items/arsenal.gd)
	"bleed": "+%d%% Bleed build-up", "poise": "+%d%% stagger", "art_cd": "Weapon Art recharges %d%% faster",
	"art_dmg": "+%d%% Weapon Art damage", "bleed_heal": "Hemorrhage heals you %d",
}
const PERCENT_KEYS := ["dmg", "dmg_taken", "dash_rate", "bite_heal", "sun_heal", "frenzy_time", "speed", "lifesteal",
	"vs_vamp", "vs_wolf", "finisher", "tithe_mult", "loot_luck", "night_dmg", "bleed", "poise", "art_cd", "art_dmg"]

## Icon per family (one painted icon each; rarity tints it in the UI).
const FAMILIES := {
	"saber": {"label": "Saber", "icon": "saber"},
	"machete": {"label": "Machete", "icon": "machete"},
	"cane": {"label": "Cane-Sword", "icon": "cane"},
	"cleaver": {"label": "Cleaver", "icon": "cleaver"},
	"longblade": {"label": "Longblade", "icon": "longblade"},
	"kukri": {"label": "Kukri", "icon": "kukri"},
	# the Arsenal (round 4): no painted icons yet, _fallback_icon() draws each silhouette
	"katana": {"label": "Katana", "icon": "katana"},
	"daggers": {"label": "Twin Stakes", "icon": "daggers"},
	"greatsword": {"label": "Greatsword", "icon": "greatsword"},
	"halberd": {"label": "Halberd", "icon": "halberd"},
	"scythe": {"label": "Scythe", "icon": "scythe"},
	"hammer": {"label": "War Hammer", "icon": "hammer"},
	"whip": {"label": "Chain-Whip", "icon": "whip"},
	"grisgris": {"label": "Gris-gris", "icon": "grisgris"},
	"rosary": {"label": "Rosary", "icon": "rosary"},
	"fang": {"label": "Fang", "icon": "fang"},
	"medal": {"label": "Medal", "icon": "medal"},
	"bones": {"label": "Bones", "icon": "bones"},
	"candle": {"label": "Candle", "icon": "candle"},
	"mirror": {"label": "Mirror", "icon": "mirror"},
	"vial": {"label": "Vial", "icon": "vial"},
	"flare": {"label": "Flare", "icon": "flare"},
}

## Blade look, per family: length (m), width (m), steel colour, shape. weapon_visual.gd reads this.
const BLADE_LOOK := {
	"saber": {"len": 1.0, "w": 0.045, "col": Color(0.85, 0.88, 0.92), "shape": "curved"},
	"machete": {"len": 0.75, "w": 0.075, "col": Color(0.55, 0.52, 0.48), "shape": "wide"},
	"cane": {"len": 1.1, "w": 0.022, "col": Color(0.9, 0.9, 0.95), "shape": "thin"},
	"cleaver": {"len": 0.7, "w": 0.16, "col": Color(0.45, 0.45, 0.47), "shape": "cleaver"},
	"longblade": {"len": 1.35, "w": 0.06, "col": Color(0.95, 0.75, 0.45), "shape": "straight"},
	"kukri": {"len": 0.65, "w": 0.07, "col": Color(0.7, 0.7, 0.72), "shape": "hooked"},
	# the Arsenal families (modelled in weapon_forge.gd; len / w are only for the fallback bodies)
	"katana": {"len": 0.8, "w": 0.034, "col": Color(0.88, 0.9, 0.94), "shape": "curved"},
	"daggers": {"len": 0.34, "w": 0.036, "col": Color(0.92, 0.88, 0.78), "shape": "straight"},
	"greatsword": {"len": 1.45, "w": 0.115, "col": Color(0.72, 0.7, 0.68), "shape": "straight"},
	"halberd": {"len": 1.4, "w": 0.05, "col": Color(0.8, 0.82, 0.86), "shape": "straight"},
	"scythe": {"len": 1.0, "w": 0.04, "col": Color(0.6, 0.6, 0.64), "shape": "straight"},
	"hammer": {"len": 0.7, "w": 0.13, "col": Color(0.75, 0.77, 0.82), "shape": "cleaver"},
	"whip": {"len": 1.5, "w": 0.026, "col": Color(0.7, 0.62, 0.5), "shape": "thin"},
}

## kind: blade | charm | vial | flare.  unique = only ever drops at Eclipse rarity, with its own effect.
const ITEMS := {
	# ------------------------------------------------------------ blades
	"marrow_silver": {"name": "Marrow's Silver", "kind": "blade", "family": "saber", "dmg": 14.0, "spd": 1.0, "reach": 0.0,
		"mods": {"vs_wolf": 0.15}, "desc": "The blade Sol has carried since he was seventeen. Silver bites the Pack."},
	"dock_machete": {"name": "Dockhand's Machete", "kind": "blade", "family": "machete", "dmg": 17.0, "spd": 0.9, "reach": -0.2,
		"mods": {"tithe_mult": 0.15}, "desc": "Cuts rope, crates and throats. Smugglers pay well for what it opens."},
	"widow_cane": {"name": "Widow's Cane-Sword", "kind": "blade", "family": "cane", "dmg": 11.0, "spd": 1.35, "reach": 0.3,
		"mods": {"lifesteal": 0.03}, "desc": "A mourning cane from the Old Quarter. The blade inside never stops grieving."},
	"bayou_butcher": {"name": "Bayou Butcher", "kind": "blade", "family": "cleaver", "dmg": 22.0, "spd": 0.75, "reach": -0.3,
		"mods": {"finisher": 0.35}, "desc": "Slow, ugly, final. The third swing lands like a slammed door."},
	"sunsteel_long": {"name": "Sun-Steel Longblade", "kind": "blade", "family": "longblade", "dmg": 19.0, "spd": 0.85, "reach": 0.6,
		"mods": {"vs_vamp": 0.35}, "desc": "Quenched at noon in holy water. The Court's skin smokes where it touches."},
	"pine_kukri": {"name": "Hollow Pines Kukri", "kind": "blade", "family": "kukri", "dmg": 13.0, "spd": 1.25, "reach": -0.2,
		"mods": {"vs_wolf": 0.25}, "desc": "A logger's knife, edged with melted-down wedding silver."},
	"velvet_rapier": {"name": "Velvet Mile Rapier", "kind": "blade", "family": "cane", "dmg": 12.0, "spd": 1.3, "reach": 0.5,
		"mods": {"vs_vamp": 0.2}, "desc": "Taken from a Courtier who duelled for sport. He lost the last one."},
	"smuggler_saber": {"name": "Smuggler's Saber", "kind": "blade", "family": "saber", "dmg": 15.0, "spd": 1.05, "reach": 0.1,
		"mods": {"loot_luck": 0.15}, "desc": "Its owner always found the good crates first. Then he found Sol."},
	"foundry_cleaver": {"name": "Foundry Cleaver", "kind": "blade", "family": "cleaver", "dmg": 24.0, "spd": 0.7, "reach": -0.2,
		"mods": {"dmg_taken": -0.08}, "desc": "Thick enough to hide behind."},
	"bloodletter": {"name": "Bloodletter", "kind": "blade", "family": "kukri", "dmg": 14.0, "spd": 1.15, "reach": 0.0,
		"mods": {"lifesteal": 0.06}, "desc": "Grooved so the blood runs back up the blade. Toward you."},
	"belltower_great": {"name": "Bell-Tower Greatsword", "kind": "blade", "family": "greatsword", "dmg": 23.0, "spd": 0.75, "reach": 0.8,
		"mods": {"finisher": 0.25}, "desc": "Pulled from the cathedral's bell loft. It still rings when it hits."},
	"nightshift_saber": {"name": "Night-Shift Saber", "kind": "blade", "family": "saber", "dmg": 16.0, "spd": 1.1, "reach": 0.0,
		"mods": {"bite_heal": 0.2}, "desc": "Wrapped in hospital tape. Somebody kept it by the ER doors."},
	"dawnbreaker": {"name": "Dawnbreaker", "kind": "blade", "family": "longblade", "dmg": 24.0, "spd": 0.9, "reach": 0.7, "unique": true,
		"mods": {"vs_vamp": 0.5, "sunburst": 1.0}, "effect": "Every third strike bursts into noon light, burning vampires within 5 m.",
		"desc": "Forged during an eclipse from a church bell and a sunrise."},
	"graces_scalpel": {"name": "Grace's Scalpel", "kind": "blade", "family": "cane", "dmg": 15.0, "spd": 1.4, "reach": 0.2, "unique": true,
		"mods": {"lifesteal": 0.1, "bite_heal": 0.4}, "effect": "Your mother's steady hand: bites heal 40% more.",
		"desc": "A trauma nurse's scalpel, grown long. It remembers the night you were born."},
	"moonsplitter": {"name": "Moonsplitter", "kind": "blade", "family": "cleaver", "dmg": 28.0, "spd": 0.75, "reach": 0.0, "unique": true,
		"mods": {"vs_wolf": 0.6, "moonsplit": 1.0}, "effect": "Killing a werewolf refunds a Blood Dash.",
		"desc": "A silver headsman's blade. The Pack tells its children about it."},
	# ------------------------------------------------------------ the Arsenal (round 4): weapon types
	# (arsenal_data.gd says how each family fights; its Weapon Art comes with the type)
	"hunter_silver": {"name": "Hunter's Silver Longsword", "kind": "blade", "family": "longblade", "dmg": 17.0, "spd": 0.95, "reach": 0.4,
		"mods": {"vs_wolf": 0.2}, "desc": "Church silver over a steel core, the way Sol's father would have wanted it. If he'd stayed."},
	"ronin_katana": {"name": "Ronin's Crescent", "kind": "blade", "family": "katana", "dmg": 13.0, "spd": 1.3, "reach": 0.2,
		"mods": {"bleed": 0.15}, "desc": "Came off a cargo ship from Osaka with no papers and no owner. It found one."},
	"lantern_katana": {"name": "Lantern-Street Katana", "kind": "blade", "family": "katana", "dmg": 15.0, "spd": 1.25, "reach": 0.2,
		"mods": {"night_dmg": 0.12}, "desc": "Its tsuba is a melted streetlamp. It cuts best where the lights are out."},
	"crimson_tide": {"name": "Crimson Tide", "kind": "blade", "family": "katana", "dmg": 17.0, "spd": 1.35, "reach": 0.3, "unique": true,
		"mods": {"bleed": 0.5, "bleed_heal": 12.0}, "effect": "Every Hemorrhage you open heals you 12.",
		"desc": "Folded a thousand times in the river's mud. It drinks, then it shares."},
	"hawthorn_stakes": {"name": "Hawthorn Stakes", "kind": "blade", "family": "daggers", "dmg": 8.0, "spd": 1.5, "reach": -0.3,
		"mods": {"vs_vamp": 0.2}, "desc": "Sharpened hawthorn, capped in silver. The oldest answer to the Court, twice over."},
	"gutter_twins": {"name": "Gutter Twins", "kind": "blade", "family": "daggers", "dmg": 9.0, "spd": 1.45, "reach": -0.3,
		"mods": {"lifesteal": 0.04}, "desc": "Two knives that never left a Docks alley. Neither did their last owner."},
	"mothers_needles": {"name": "Grace's Needles", "kind": "blade", "family": "daggers", "dmg": 10.0, "spd": 1.6, "reach": -0.2, "unique": true,
		"mods": {"art_cd": 0.35, "vs_vamp": 0.3}, "effect": "Your Weapon Art recharges 35% faster.",
		"desc": "Surgical steel from Port Vesper General, the night of 1979. Sharpened every year since."},
	"cathedral_slab": {"name": "Cathedral Slab", "kind": "blade", "family": "greatsword", "dmg": 27.0, "spd": 0.7, "reach": 0.9,
		"mods": {"poise": 0.2}, "desc": "Cut from the altar rail of St. Jerome's. It weighs what a sin weighs."},
	"noonfall": {"name": "Noonfall", "kind": "blade", "family": "greatsword", "dmg": 30.0, "spd": 0.72, "reach": 1.0, "unique": true,
		"mods": {"vs_vamp": 0.45, "art_dmg": 0.4}, "effect": "Weapon Arts strike 40% harder.",
		"desc": "A greatsword that holds the sun at its height. The Court calls it the long afternoon."},
	"levee_halberd": {"name": "Levee Guard Halberd", "kind": "blade", "family": "halberd", "dmg": 18.0, "spd": 0.9, "reach": 1.2,
		"mods": {"vs_wolf": 0.15}, "desc": "Issued to the men who held the levee the night the Pack came through. Most of them."},
	"riverboat_pike": {"name": "Riverboat Pike", "kind": "blade", "family": "halberd", "dmg": 17.0, "spd": 0.95, "reach": 1.4,
		"mods": {"dmg_taken": -0.05}, "desc": "Kept a paddle-steamer's deck clear for a hundred years. Kept it red."},
	"jerome_lance": {"name": "St. Jerome's Lance", "kind": "blade", "family": "halberd", "dmg": 21.0, "spd": 0.95, "reach": 1.5, "unique": true,
		"mods": {"vs_wolf": 0.4, "poise": 0.4}, "effect": "Every thrust carries 40% more stagger.",
		"desc": "The saint's own, the sacristan swears. The silver on its head was a reliquary."},
	"canefield_scythe": {"name": "Cane-Field Scythe", "kind": "blade", "family": "scythe", "dmg": 16.0, "spd": 0.95, "reach": 0.9,
		"mods": {"bleed": 0.15}, "desc": "Harvested sugar for a plantation. The cane remembers. So does the blade."},
	"gravedigger_scythe": {"name": "Gravedigger's Scythe", "kind": "blade", "family": "scythe", "dmg": 17.0, "spd": 0.9, "reach": 0.9,
		"mods": {"kill_heal": 3.0}, "desc": "For the weeds on the Cemetery's paths. For whatever crawls out, too."},
	"last_harvest": {"name": "The Last Harvest", "kind": "blade", "family": "scythe", "dmg": 20.0, "spd": 1.0, "reach": 1.0, "unique": true,
		"mods": {"bleed": 0.6, "lifesteal": 0.06}, "effect": "Reaps blood: Bleed builds 60% faster and feeds you.",
		"desc": "Mama Odette won't touch it. She says it was made for one particular neck."},
	"foundry_maul": {"name": "Foundry Maul", "kind": "blade", "family": "hammer", "dmg": 25.0, "spd": 0.68, "reach": -0.2,
		"mods": {"poise": 0.15}, "desc": "A rivet hammer from the dead foundry. It still flattens things."},
	"railspike_hammer": {"name": "Railspike Hammer", "kind": "blade", "family": "hammer", "dmg": 24.0, "spd": 0.72, "reach": -0.2,
		"mods": {"vs_wolf": 0.2}, "desc": "Drives silver spikes through rail ties, and through anything else that runs on four legs."},
	"wolfsbane_maul": {"name": "Wolfsbane Maul", "kind": "blade", "family": "hammer", "dmg": 29.0, "spd": 0.7, "reach": 0.0, "unique": true,
		"mods": {"vs_wolf": 0.6, "poise": 0.5}, "effect": "Breaks the Pack: wolves stagger in half the hits.",
		"desc": "Silver head, ash haft, a sprig of wolfsbane under the wrap. Wren Hollow has a bounty on it."},
	"censer_chain": {"name": "Censer Chain", "kind": "blade", "family": "whip", "dmg": 12.0, "spd": 1.1, "reach": 0.0,
		"mods": {"vs_vamp": 0.2}, "desc": "The thurible's chain from the cathedral, its links filed to edges. Still smells of incense."},
	"mooring_chain": {"name": "Mooring Chain", "kind": "blade", "family": "whip", "dmg": 13.0, "spd": 1.05, "reach": 0.2,
		"mods": {"tithe_mult": 0.12}, "desc": "Held a smuggler's boat to the pier. Holds Thralls still now."},
	"penitent_chain": {"name": "Chain of the Penitent", "kind": "blade", "family": "whip", "dmg": 15.0, "spd": 1.15, "reach": 0.3, "unique": true,
		"mods": {"vs_vamp": 0.4, "art_cd": 0.25}, "effect": "Burns the Court; Chain Lash recharges 25% faster.",
		"desc": "A flagellant's chain, set alight at the end of every prayer. It never quite goes out."},
	# ------------------------------------------------------------ charms (gris-gris)
	"red_flannel": {"name": "Red Flannel Bag", "kind": "charm", "family": "grisgris", "mods": {"max_hp": 12.0},
		"desc": "Nine herbs, a lock of hair and a promise, tied in red."},
	"john_root": {"name": "High John Root", "kind": "charm", "family": "grisgris", "mods": {"dmg": 0.06},
		"desc": "The conqueror root. Carry it and hit harder."},
	"grave_salt": {"name": "Graveyard Salt", "kind": "charm", "family": "grisgris", "mods": {"dmg_taken": -0.06},
		"desc": "Salt from a fresh grave. The dead lend you their stubbornness."},
	"iron_rosary": {"name": "Iron Rosary", "kind": "charm", "family": "rosary", "mods": {"vs_vamp": 0.15},
		"desc": "Cold iron beads. The Court can't stand the clicking."},
	"thorn_rosary": {"name": "Thorn Rosary", "kind": "charm", "family": "rosary", "mods": {"bite_heal": 0.2},
		"desc": "Every bead draws a little blood. You learn to like it."},
	"pack_fang": {"name": "Pack Fang", "kind": "charm", "family": "fang", "mods": {"vs_wolf": 0.15},
		"desc": "A trophy from a wolf that thought you were easy."},
	"alpha_tooth": {"name": "Alpha's Tooth", "kind": "charm", "family": "fang", "mods": {"speed": 0.06},
		"desc": "Still warm. Your legs remember running on four."},
	"jerome_medal": {"name": "St. Jerome's Medal", "kind": "charm", "family": "medal", "mods": {"sun_heal": 0.6},
		"desc": "From the cathedral above your lair. The sun likes whoever wears it."},
	"noon_medal": {"name": "Noon Medal", "kind": "charm", "family": "medal", "mods": {"dash_rate": 0.12},
		"desc": "Stamped with a sun at its height. Your step quickens."},
	"knucklebones": {"name": "Knucklebones", "kind": "charm", "family": "bones", "mods": {"loot_luck": 0.15},
		"desc": "Mama Odette's casting bones. They always point at something shiny."},
	"gamblers_dice": {"name": "Gambler's Dice", "kind": "charm", "family": "bones", "mods": {"tithe_mult": 0.15},
		"desc": "Carved from a vampire's knuckle. Loaded, naturally."},
	"vigil_candle": {"name": "Vigil Candle", "kind": "charm", "family": "candle", "mods": {"frenzy_time": 0.25},
		"desc": "Burns red. While it burns, the beast stays out longer."},
	"black_candle": {"name": "Black Candle", "kind": "charm", "family": "candle", "mods": {"lifesteal": 0.02},
		"desc": "Lit for enemies. Their blood feeds the wick, and you."},
	"mirror_shard": {"name": "Mirror Shard", "kind": "charm", "family": "mirror", "mods": {"dodge_heal": 4.0},
		"desc": "Vampires can't see themselves in it. They can't see you leave, either."},
	"odette_bag": {"name": "Odette's Last Bag", "kind": "charm", "family": "grisgris", "unique": true,
		"mods": {"max_hp": 30.0, "sun_any": 1.0}, "effect": "Sunlight heals you even in combat and even when you're hungry.",
		"desc": "The root-woman tied it for your mother. She meant it for you."},
	"eclipse_coin": {"name": "Eclipse Coin", "kind": "charm", "family": "medal", "unique": true,
		"mods": {"night_dmg": 0.15, "tithe_mult": 0.25}, "effect": "A black sun on both faces. Pays for the dark.",
		"desc": "Minted for a day that hasn't come yet."},
	"counts_mirror": {"name": "The Count's Hand-Mirror", "kind": "charm", "family": "mirror", "unique": true,
		"mods": {"dmg_taken": -0.12, "reflect": 20.0}, "effect": "Anything that strikes you takes 20 damage back.",
		"desc": "Empty glass. Lucien kept it to remind himself what he gave up."},
	# ------------------------------------------------------------ consumables
	"blood_vial": {"name": "Blood Vial", "kind": "vial", "family": "vial", "heal": 35.0, "hunger": 0.0, "stack": 9,
		"desc": "Bagged blood, decanted. Quick to drink, quiet on the hunger."},
	"vintage_vial": {"name": "Vintage Vial", "kind": "vial", "family": "vial", "heal": 60.0, "hunger": -15.0, "stack": 9,
		"desc": "A Courtier's private stock. Smooth, heavy, and it settles the beast."},
	"dawn_flare": {"name": "Dawn Flare", "kind": "flare", "family": "flare", "radius": 6.0, "power": 60.0, "stack": 9,
		"desc": "A road flare packed with UV salts. Crack it and the street becomes noon for a breath."},
}


static func get_def(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func make(id: String, rarity: int = COMMON, count: int = 1) -> Dictionary:
	var d := get_def(id)
	if d.get("unique", false):
		rarity = LEGENDARY
	return {"id": id, "r": clampi(rarity, 0, 3), "n": count}


static func is_stackable(inst: Dictionary) -> bool:
	return get_def(inst.id).get("stack", 1) > 1


static func is_consumable(inst: Dictionary) -> bool:
	var k: String = get_def(inst.id).get("kind", "")
	return k == "vial" or k == "flare"


static func kind_of(inst: Dictionary) -> String:
	return get_def(inst.get("id", "")).get("kind", "")


static func display_name(inst: Dictionary) -> String:
	return get_def(inst.id).get("name", inst.id)


static func color(inst: Dictionary) -> Color:
	return RARITY_COLORS[int(inst.get("r", 0))]


## Blade numbers after rarity: {dmg, spd, reach}, plus the Arsenal's {type, stagger, affinity, art}
## (items/arsenal_data.gd: the weapon type the blade's family belongs to).
static func weapon_stats(inst: Dictionary) -> Dictionary:
	var d := get_def(inst.get("id", "marrow_silver"))
	if d.is_empty() or d.kind != "blade":
		d = ITEMS["marrow_silver"]
	var r := int(inst.get("r", 0))
	var tname := Arsenal.type_of_family(d.get("family", "saber"))
	var t := Arsenal.get_type(tname)
	return {"dmg": d.dmg * DMG_SCALE[r], "spd": d.spd, "reach": d.reach, "type": tname, "stagger": float(t.stagger),
		"affinity": String(t.affinity), "art": String(t.art)}


## "Katana  ·  Bleed  ·  Art: Blood Wave" for a blade (the Coat, the hub, tooltips).
static func weapon_line(inst: Dictionary) -> String:
	var w := weapon_stats(inst)
	var t := Arsenal.get_type(w.type)
	var art: Dictionary = ArsenalMoves.ARTS.get(w.art, {})
	return "%s  ·  %s  ·  Art: %s" % [t.label, String(w.affinity).capitalize(), art.get("name", "—")]


## Stat contributions of an equipped item after rarity.
static func item_mods(inst: Dictionary) -> Dictionary:
	var d := get_def(inst.get("id", ""))
	var out := {}
	if d.is_empty():
		return out
	var r := int(inst.get("r", 0))
	var flags := ["sunburst", "moonsplit", "sun_any"]
	for k in d.get("mods", {}):
		var v: float = d.mods[k]
		out[k] = v if (k in flags or d.get("unique", false)) else v * STAT_SCALE[r]
	if r == LEGENDARY:
		for k in ECLIPSE_PERK:
			out[k] = out.get(k, 0.0) + ECLIPSE_PERK[k]
	return out


static func heal_amount(inst: Dictionary) -> float:
	return get_def(inst.id).get("heal", 0.0) * (1.0 + 0.25 * int(inst.get("r", 0)))


static func flare_power(inst: Dictionary) -> float:
	return get_def(inst.id).get("power", 0.0) * (1.0 + 0.3 * int(inst.get("r", 0)))


static func mod_line(k: String, v: float) -> String:
	if not STAT_TEXT.has(k):
		return ""
	var n := v * 100.0 if k in PERCENT_KEYS else v
	return STAT_TEXT[k] % roundi(n)


## Tooltip body: family, stats, effect, flavour.
static func describe(inst: Dictionary) -> String:
	var d := get_def(inst.id)
	var r := int(inst.get("r", 0))
	var lines: Array[String] = []
	var fam: String = FAMILIES.get(d.get("family", ""), {}).get("label", "")
	var kinds := {"blade": "Blade", "charm": "Charm", "vial": "Quick-use heal", "flare": "Quick-use throwable"}
	lines.append("%s %s  ·  %s" % [RARITY_NAMES[r], kinds[d.kind], fam])
	lines.append("")
	match d.kind:
		"blade":
			var w := weapon_stats(inst)
			lines.append("Damage  %d    Speed  %.2f    Reach  %+.1f m    Stagger  %.1f" % [roundi(w.dmg), w.spd, w.reach, w.stagger])
			var t := Arsenal.get_type(w.type)
			lines.append("%s  ·  %s" % [t.label, Arsenal.AFFINITY_TEXT.get(w.affinity, "")])
			var art: Dictionary = ArsenalMoves.ARTS.get(w.art, {})
			if not art.is_empty():
				var cost := ("  ·  %d blood" % roundi(art.blood)) if float(art.blood) > 0.0 else ""
				lines.append("Weapon Art: %s  (%ds%s)  %s" % [art.name, roundi(art.cd), cost, art.desc])
		"vial":
			lines.append("Restores %d blood" % roundi(heal_amount(inst)) + ("  ·  eases hunger" if d.get("hunger", 0.0) < 0.0 else ""))
		"flare":
			lines.append("Burns vampires for %d within %d m  ·  scorches wolves" % [roundi(flare_power(inst)), roundi(d.radius)])
	for k in item_mods(inst):
		var t := mod_line(k, item_mods(inst)[k])
		if t != "" and not (r == LEGENDARY and ECLIPSE_PERK.has(k) and not d.mods.has(k)):
			lines.append(t)
	if d.has("effect"):
		lines.append("")
		lines.append("✦ " + d.effect)
	if r == LEGENDARY and not d.get("unique", false):
		lines.append("✦ Eclipse-touched: kills heal %d" % roundi(ECLIPSE_PERK.kill_heal))
	lines.append("")
	lines.append(d.get("desc", ""))
	return "\n".join(lines)


# ---------------------------------------------------------------- drops
## Rarity weights [common, uncommon, rare, legendary] for the time of day.
static func rarity_weights(night: bool, full_moon: bool, luck: float) -> Array:
	var w: Array = [70.0, 22.0, 7.0, 1.0]
	if full_moon:
		w = [44.0, 32.0, 18.0, 6.0]
	elif night:
		w = [60.0, 27.0, 11.0, 2.0]
	# luck shifts weight from common to the higher tiers
	var shift: float = w[0] * clampf(luck, 0.0, 0.8)
	w[0] -= shift
	w[1] += shift * 0.45
	w[2] += shift * 0.38
	w[3] += shift * 0.17
	return w


static func roll_rarity(rng: RandomNumberGenerator, night: bool, full_moon: bool, luck: float = 0.0) -> int:
	var w := rarity_weights(night, full_moon, luck)
	var total := 0.0
	for x in w:
		total += x
	var pick := rng.randf() * total
	for i in 4:
		pick -= w[i]
		if pick <= 0.0:
			return i
	return 0


## A random item instance. Uniques only appear on an Eclipse roll.
static func random_item(rng: RandomNumberGenerator, night: bool, full_moon: bool, luck: float = 0.0) -> Dictionary:
	var r := roll_rarity(rng, night, full_moon, luck)
	var roll := rng.randf()
	var kind := "blade" if roll < 0.28 else ("charm" if roll < 0.62 else "consumable")
	var pool: Array = []
	for id in ITEMS:
		var d: Dictionary = ITEMS[id]
		if id == "marrow_silver":
			continue
		var k: String = d.kind
		if (kind == "consumable" and (k == "vial" or k == "flare")) or k == kind:
			if d.get("unique", false) and r != LEGENDARY:
				continue
			pool.append(id)
	var id: String = pool[rng.randi() % pool.size()]
	var count := 1
	if ITEMS[id].get("stack", 1) > 1:
		count = 1 + (1 if rng.randf() < 0.3 else 0)
	return make(id, r, count)


# ---------------------------------------------------------------- icons
static var _icon_cache := {}

## The family icon (painted PNG if present, else a drawn fallback).
static func icon(inst_or_family) -> Texture2D:
	var fam: String = inst_or_family if inst_or_family is String else get_def(inst_or_family.id).get("family", "vial")
	if _icon_cache.has(fam):
		return _icon_cache[fam]
	var key: String = FAMILIES.get(fam, {"icon": fam}).icon
	var path := "res://assets/ui/icons/%s.png" % key
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	if tex == null:
		tex = _fallback_icon(fam)
	_icon_cache[fam] = tex
	return tex


static func _fallback_icon(fam: String) -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.03, 0.04))
	var c := Color(0.8, 0.8, 0.85)
	match fam:
		"vial":
			c = Color(0.75, 0.05, 0.08)
		"flare":
			c = Color(0.75, 0.5, 1.0)
		"grisgris", "candle":
			c = Color(0.7, 0.15, 0.12)
		"medal", "rosary":
			c = Color(0.9, 0.75, 0.35)
	if Arsenal.FAMILY_TYPE.has(fam) and fam in ["katana", "daggers", "greatsword", "halberd", "scythe", "hammer", "whip"]:
		_arsenal_icon(img, fam)
	elif BLADE_LOOK.has(fam):
		for i in 44:
			img.fill_rect(Rect2i(10 + i, 52 - i, 4, 4), c)
	else:
		for y in 64:
			for x in 64:
				if Vector2(x - 32, y - 32).length() < 16.0:
					img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func _stroke(img: Image, a: Vector2, b: Vector2, w: int, c: Color) -> void:
	var n := int(maxf(a.distance_to(b), 1.0))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		img.fill_rect(Rect2i(int(p.x) - w / 2, int(p.y) - w / 2, w, w), c)


## A silhouette per Arsenal family (steel, dark haft, a little colour), drawn into the 64 px icon.
static func _arsenal_icon(img: Image, fam: String) -> void:
	var steel := Color(0.86, 0.88, 0.92)
	var wood := Color(0.45, 0.28, 0.15)
	var red := Color(0.7, 0.08, 0.1)
	var gold := Color(0.85, 0.65, 0.3)
	match fam:
		"katana":
			_stroke(img, Vector2(10, 54), Vector2(20, 44), 5, red)
			_stroke(img, Vector2(17, 40), Vector2(24, 47), 3, gold)
			for i in 30:
				var u := i / 29.0
				var p := Vector2(22 + u * 32, 42 - u * 32 + sin(u * PI) * 4)
				img.fill_rect(Rect2i(int(p.x) - 2, int(p.y) - 2, 4, 4), steel)
		"daggers":
			for off in [Vector2(0, 0), Vector2(18, 4)]:
				_stroke(img, Vector2(12, 52) + off, Vector2(18, 44) + off, 5, wood)
				_stroke(img, Vector2(14, 42) + off, Vector2(20, 48) + off, 3, steel)
				_stroke(img, Vector2(18, 44) + off, Vector2(34, 22) + off, 4, steel)
		"greatsword":
			_stroke(img, Vector2(8, 56), Vector2(16, 48), 5, wood)
			_stroke(img, Vector2(10, 40), Vector2(24, 54), 5, gold)
			_stroke(img, Vector2(17, 47), Vector2(56, 8), 9, steel)
		"halberd":
			_stroke(img, Vector2(8, 58), Vector2(52, 14), 3, wood)
			_stroke(img, Vector2(50, 16), Vector2(60, 4), 3, steel)
			for i in 10:
				_stroke(img, Vector2(44 - i, 18 - i), Vector2(54 - i, 28 - i), 2, steel)
		"scythe":
			_stroke(img, Vector2(14, 60), Vector2(30, 6), 3, wood)
			for i in 26:
				var u := i / 25.0
				var p := Vector2(30 + u * 28, 8 - sin(u * PI) * -6 + u * 18)
				img.fill_rect(Rect2i(int(p.x) - 2, int(p.y) - 2, 5, int(6 - u * 4)), steel)
		"hammer":
			_stroke(img, Vector2(14, 58), Vector2(40, 20), 4, wood)
			for i in 14:
				_stroke(img, Vector2(28 + i, 10 + i * 0.6), Vector2(48 + i * 0.3, 28 + i * 0.4), 3, steel)
			_stroke(img, Vector2(46, 14), Vector2(56, 8), 3, steel)
		"whip":
			_stroke(img, Vector2(8, 56), Vector2(18, 46), 5, red)
			var prev := Vector2(18, 46)
			for i in 14:
				var u := (i + 1) / 14.0
				var p := Vector2(18 + u * 38, 46 - u * 30 + sin(u * 7.0) * 6)
				_stroke(img, prev, p, 3, steel if i % 2 == 0 else gold)
				prev = p
