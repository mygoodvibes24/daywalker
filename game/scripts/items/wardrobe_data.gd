extends RefCounted
## Sol's wardrobe (the lair's mirror station): seven clothing slots, the clothes for each, what they
## do (percent stat bonuses, usually with a small trade-off) and how they look on the modular body
## (scripts/sol_outfit.gd reads "look").
##
## Ownership and the worn outfit persist between Hunts (hunt_meta.gd "clothes" / "outfit"). Some
## clothes are owned from the start, some are bought at the mirror with Sunmarks ("price"), and some
## only turn up in a Hunt as rare loot ("drop": loot.gd rolls them from caches and bosses).
##
## Stat keys (all additive fractions unless noted; progression.gd sums them with rank, Vows, Rites,
## charms and the blade, then clamps the totals with STAT_CAPS):
##   max_hp_pct  max blood x (1 + v)          speed       move speed
##   dmg         all damage ("power")         vs_vamp / vs_wolf   damage against the Court / the Pack
##   stamina     max stamina (flat, base 100)  stamina_regen   stamina recovery
##   dmg_taken   damage taken (-0.05 = 5% less: "defence")
##   notice      how far idle enemies notice Sol (-0.1 = 10% closer: "stealth")

const SLOTS := ["hat", "scarf", "coat", "shirt", "gloves", "pants", "boots"]
const SLOT_NAMES := {"hat": "Hat", "scarf": "Scarf", "coat": "Coat", "shirt": "Shirt", "gloves": "Gloves", "pants": "Trousers", "boots": "Boots"}
const RARITY_NAMES := ["Street", "Blooded", "Hallowed", "Eclipse"]
const RARITY_COLORS := [Color(0.86, 0.86, 0.82), Color(0.35, 0.95, 0.4), Color(0.3, 0.6, 1.0), Color(0.82, 0.42, 1.0)]

## What Sol wears on a fresh save (all of it owned). Its pieces carry no stats, so the baseline
## numbers (100 blood, base speed) are what the default outfit gives.
const DEFAULT_OUTFIT := {"hat": "no_hat", "scarf": "no_scarf", "coat": "marrow_coat", "shirt": "black_henley",
	"gloves": "bare_hands", "pants": "work_trousers", "boots": "combat_boots"}

## How the stats read in the panels: [label, format, percent?]. Order = display order.
const STAT_ROWS := [
	["max_hp_pct", "Blood (health)", true], ["speed", "Speed", true], ["dmg", "Power", true],
	["stamina", "Stamina", false], ["stamina_regen", "Stamina regen", true], ["dmg_taken", "Damage taken", true],
	["notice", "Notice range", true], ["vs_vamp", "vs vampires", true], ["vs_wolf", "vs werewolves", true],
]
## Lower is better for these (shown green when negative).
const LOWER_BETTER := ["dmg_taken", "notice"]
## What the whole outfit may add per stat (so seven slots can't stack one stat silly).
const OUTFIT_CAP := {"max_hp_pct": 0.3, "speed": 0.2, "dmg": 0.2, "stamina": 30.0, "stamina_regen": 0.25,
	"dmg_taken": 0.2, "notice": 0.35, "vs_vamp": 0.2, "vs_wolf": 0.2}
## Final caps on the summed totals from every source (rank, Vows, Rites, charms, blade, outfit, the
## night): [min, max]. progression.gd applies them after summing. dmg_taken also floors at -0.8 in
## player.take_damage.
const STAT_CAPS := {"max_hp_pct": [-0.3, 0.6], "speed": [-0.3, 0.45], "dmg": [-0.3, 2.5],
	"stamina_regen": [-0.5, 1.5], "dmg_taken": [-0.6, 1.0], "notice": [-0.6, 0.6]}

## kind of each item = its slot. look keys per slot are documented in sol_outfit.gd.
const ITEMS := {
	# ------------------------------------------------------------------ hats
	"no_hat": {"slot": "hat", "name": "Bare-headed", "r": 0, "start": true, "mods": {},
		"desc": "Locs tied back. Nothing between him and the rain.", "look": {"kind": "none"}},
	"flat_cap": {"slot": "hat", "name": "Docker's Flat Cap", "r": 0, "price": 25, "mods": {"speed": 0.03, "notice": -0.04},
		"desc": "Wool, oil-stained, bought off a longshoreman for a bottle. Nobody looks twice at a docker.",
		"look": {"kind": "cap", "col": Color(0.17, 0.15, 0.13)}},
	"wide_brim": {"slot": "hat", "name": "Wide-brim Hunter's Hat", "r": 1, "price": 60, "mods": {"notice": -0.1, "max_hp_pct": 0.02},
		"desc": "The old Vigil's hat. The brim keeps the rain off and the eyes from finding yours.",
		"look": {"kind": "wide", "col": Color(0.05, 0.045, 0.045), "band": Color(0.35, 0.03, 0.03)}},
	"preacher_hat": {"slot": "hat", "name": "Preacher's Low Crown", "r": 1, "price": 50, "mods": {"vs_vamp": 0.06},
		"desc": "Taken from a street preacher's coat-rack. The Court can smell the sermons in the felt.",
		"look": {"kind": "low", "col": Color(0.09, 0.08, 0.1), "band": Color(0.55, 0.45, 0.25)}},
	"crow_hood": {"slot": "hat", "name": "Crow-feather Hood", "r": 2, "drop": true, "mods": {"notice": -0.15, "max_hp_pct": -0.03},
		"desc": "A cowl stitched with black feathers by someone in the bayou. Crows don't caw at you any more.",
		"look": {"kind": "hood", "col": Color(0.035, 0.035, 0.045)}},
	"undertaker_bowler": {"slot": "hat", "name": "Undertaker's Bowler", "r": 2, "drop": true, "mods": {"dmg_taken": -0.04, "speed": -0.02},
		"desc": "Hard as a coffin lid. Its owner measured the dead for a living; it measured him back.",
		"look": {"kind": "bowler", "col": Color(0.04, 0.035, 0.035), "band": Color(0.12, 0.1, 0.1)}},
	# ------------------------------------------------------------------ scarves
	"no_scarf": {"slot": "scarf", "name": "Open Collar", "r": 0, "start": true, "mods": {},
		"desc": "Nothing at the throat. Bold, for a man who hunts things that bite.", "look": {"kind": "none"}},
	"graces_knit": {"slot": "scarf", "name": "Grace's Knitted Scarf", "r": 1, "start": true, "mods": {"max_hp_pct": 0.05},
		"desc": "Charcoal wool his mother knitted for a son she never met. The foster file kept it for him.",
		"look": {"kind": "wrap", "col": Color(0.2, 0.19, 0.19), "tail": true}},
	"wolfhide_scarf": {"slot": "scarf", "name": "Wolfhide Scarf", "r": 1, "price": 30, "mods": {"stamina_regen": 0.05},
		"desc": "Grey pelt from a Pack runner who didn't make the turn. Warm enough to keep you breathing.",
		"look": {"kind": "wrap", "col": Color(0.36, 0.34, 0.31), "tail": false, "fur": true}},
	"crimson_silk": {"slot": "scarf", "name": "Crimson Silk Scarf", "r": 1, "price": 45, "mods": {"dmg": 0.04, "notice": 0.05},
		"desc": "Velvet Mile silk the colour of what you're hunting. It gets you noticed. It gets you angry.",
		"look": {"kind": "wrap", "col": Color(0.42, 0.02, 0.04), "tail": true, "sheen": true}},
	"rosary_wrap": {"slot": "scarf", "name": "Rosary-bead Wrap", "r": 2, "drop": true, "mods": {"vs_vamp": 0.05, "stamina_regen": 0.03},
		"desc": "A black cotton wrap with a chapel rosary sewn through it. The beads click when you run.",
		"look": {"kind": "wrap", "col": Color(0.06, 0.06, 0.07), "tail": true, "beads": true}},
	"mail_cowl": {"slot": "scarf", "name": "Mail Neck-guard", "r": 2, "drop": true, "mods": {"dmg_taken": -0.06, "speed": -0.02},
		"desc": "Riveted steel rings under a leather band. Fangs skid off it. So do claws, mostly.",
		"look": {"kind": "cowl", "col": Color(0.42, 0.43, 0.46), "metal": true}},
	# ------------------------------------------------------------------ coats
	"marrow_coat": {"slot": "coat", "name": "Marrow's Trenchcoat", "r": 0, "start": true, "mods": {},
		"desc": "Black leather to mid-shin, rain-worn at every seam. The coat the city knows him by.",
		"look": {"col": Color(0.35, 0.35, 0.336), "rough": 0.62, "tex": true, "hem": 1.0}},
	"hunter_duster": {"slot": "coat", "name": "Hunter's Duster", "r": 1, "price": 60, "mods": {"max_hp_pct": 0.1, "speed": -0.03},
		"desc": "Oiled canvas, heavy as a tarp, long enough to sweep the gutters. Takes a hit and keeps walking.",
		"look": {"col": Color(0.42, 0.29, 0.17), "rough": 0.82, "tex": true, "hem": 1.12}},
	"iron_lined": {"slot": "coat", "name": "Iron-lined Coat", "r": 2, "price": 90, "mods": {"max_hp_pct": 0.12, "speed": -0.05, "dmg_taken": -0.03},
		"desc": "Gunmetal leather over sewn-in iron plates. A coat like a locked door.",
		"look": {"col": Color(0.2, 0.21, 0.23), "rough": 0.42, "metal": 0.35, "tex": true, "hem": 1.0}},
	"courier_coat": {"slot": "coat", "name": "Courier's Short Coat", "r": 1, "price": 50, "mods": {"speed": 0.06, "max_hp_pct": -0.03},
		"desc": "Cut short at the thigh for bike couriers. Nothing to catch on a fence, nothing to stop a claw.",
		"look": {"col": Color(0.13, 0.15, 0.13), "rough": 0.7, "tex": true, "hem": 0.72}},
	"oxblood_frock": {"slot": "coat", "name": "Oxblood Frock Coat", "r": 2, "drop": true, "mods": {"dmg": 0.06, "vs_vamp": 0.04},
		"desc": "A Courtier's frock coat in deep red leather. Wearing their colours to their funerals.",
		"look": {"col": Color(0.3, 0.035, 0.04), "rough": 0.5, "tex": true, "hem": 1.05}},
	"vigil_greatcoat": {"slot": "coat", "name": "Vigil Greatcoat", "r": 3, "drop": true, "mods": {"dmg_taken": -0.08, "max_hp_pct": 0.06, "notice": 0.08},
		"desc": "Bone-white leather of the old Vigil, like Silas Crowe's. Every eye in the street finds it.",
		"look": {"col": Color(0.78, 0.75, 0.68), "rough": 0.55, "tex": false, "hem": 1.1}},
	# ------------------------------------------------------------------ shirts
	"black_henley": {"slot": "shirt", "name": "Black Henley", "r": 0, "start": true, "mods": {},
		"desc": "Cotton, three buttons, washed grey at the collar. He owns six of them.",
		"look": {"col": Color(1.0, 1.0, 1.0), "keep": true}},
	"thermal": {"slot": "shirt", "name": "Night-shift Thermal", "r": 0, "price": 25, "mods": {"stamina": 10.0, "max_hp_pct": 0.02},
		"desc": "Waffle-knit, hospital issue. Grace wore the same kind under her scrubs.",
		"look": {"col": Color(0.55, 0.5, 0.44)}},
	"waistcoat": {"slot": "shirt", "name": "Waistcoat and Shirt", "r": 1, "price": 35, "mods": {"dmg": 0.03, "stamina_regen": 0.03},
		"desc": "A pinstripe waistcoat over a bone shirt. Dress for the job you want: executioner.",
		"look": {"col": Color(0.12, 0.1, 0.11), "vest": true, "shirt_col": Color(0.62, 0.58, 0.5)}},
	"silver_mesh": {"slot": "shirt", "name": "Silver-thread Undershirt", "r": 1, "price": 45, "mods": {"vs_wolf": 0.06},
		"desc": "Fine silver wire knitted into black cotton. A wolf that bites through it remembers.",
		"look": {"col": Color(0.42, 0.44, 0.48), "sheen": true}},
	"stab_vest": {"slot": "shirt", "name": "Stab Vest", "r": 2, "drop": true, "mods": {"dmg_taken": -0.08, "speed": -0.04},
		"desc": "Police surplus, the badge torn off. Heavy, hot and worth it.",
		"look": {"col": Color(0.1, 0.11, 0.1), "vest": true, "shirt_col": Color(0.15, 0.15, 0.15), "plates": true}},
	# ------------------------------------------------------------------ gloves
	"bare_hands": {"slot": "gloves", "name": "Bare Hands", "r": 0, "start": true, "mods": {},
		"desc": "Scarred knuckles. He likes to feel the grip.", "look": {"kind": "bare"}},
	"driving_gloves": {"slot": "gloves", "name": "Fingerless Driving Gloves", "r": 0, "price": 20, "mods": {"dmg": 0.03, "stamina_regen": 0.02},
		"desc": "Cut-off leather. A better grip on the hilt, fingers free for the trigger.",
		"look": {"kind": "fingerless", "col": Color(0.07, 0.05, 0.04)}},
	"silver_gloves": {"slot": "gloves", "name": "Silver-thread Gloves", "r": 1, "price": 40, "mods": {"vs_vamp": 0.06},
		"desc": "Black kid leather stitched with silver. Every punch is a little bit holy.",
		"look": {"kind": "leather", "col": Color(0.05, 0.05, 0.06), "sheen": true}},
	"butcher_gauntlets": {"slot": "gloves", "name": "Butcher's Gauntlets", "r": 2, "drop": true, "mods": {"dmg": 0.08, "speed": -0.02},
		"desc": "Bayou butcher's chain-cuffed gloves. They were made for cleavers. They work for heads.",
		"look": {"kind": "leather", "col": Color(0.24, 0.13, 0.07), "cuff": true}},
	"graces_gloves": {"slot": "gloves", "name": "Surgical Black Nitrile", "r": 1, "price": 30, "mods": {"stamina_regen": 0.04, "notice": -0.03},
		"desc": "A box from Nia's lab. No prints, no blood under the nails, no noise.",
		"look": {"kind": "leather", "col": Color(0.02, 0.02, 0.025), "sheen": true, "thin": true}},
	# ------------------------------------------------------------------ trousers
	"work_trousers": {"slot": "pants", "name": "Black Work Trousers", "r": 0, "start": true, "mods": {},
		"desc": "Heavy cotton twill with a gusset. Made for kneeling in gutters.", "look": {"col": Color(1.0, 1.0, 1.0), "keep": true}},
	"waxed_canvas": {"slot": "pants", "name": "Waxed Canvas Trousers", "r": 0, "price": 30, "mods": {"max_hp_pct": 0.04, "dmg_taken": -0.02},
		"desc": "Olive waxed canvas. Rain runs off; so does the occasional claw.",
		"look": {"col": Color(0.3, 0.29, 0.2)}},
	"runner_slacks": {"slot": "pants", "name": "Runner's Slacks", "r": 1, "price": 40, "mods": {"speed": 0.05, "dmg_taken": 0.03},
		"desc": "Light charcoal wool with a stretch weave. Nothing slows the legs. Nothing stops a bite.",
		"look": {"col": Color(0.32, 0.32, 0.34)}},
	"riding_leathers": {"slot": "pants", "name": "Riding Leathers", "r": 1, "price": 55, "mods": {"dmg_taken": -0.05, "speed": -0.02},
		"desc": "Black motorcycle leathers, scuffed at both knees from the last time.",
		"look": {"col": Color(0.12, 0.1, 0.1), "sheen": true}},
	# ------------------------------------------------------------------ boots
	"combat_boots": {"slot": "boots", "name": "Marrow's Combat Boots", "r": 0, "start": true, "mods": {},
		"desc": "Resoled twice. They know every stair in the Undercroft.", "look": {"col": Color(1.0, 1.0, 1.0), "keep": true}},
	"courier_boots": {"slot": "boots", "name": "Courier Boots", "r": 1, "price": 50, "mods": {"speed": 0.08},
		"desc": "Light, laced to the shin, soled in bike-tyre rubber. Faster than the rumours.",
		"look": {"col": Color(0.2, 0.12, 0.07), "cuff": true}},
	"hobnail_boots": {"slot": "boots", "name": "Hobnailed Boots", "r": 0, "price": 35, "mods": {"dmg": 0.04, "notice": 0.05},
		"desc": "Iron nails in the sole, iron in the kick. You'll hear them coming. So will they.",
		"look": {"col": Color(0.1, 0.08, 0.07), "buckles": 2}},
	"creepers": {"slot": "boots", "name": "Soft-soled Creepers", "r": 1, "price": 45, "mods": {"notice": -0.12, "dmg_taken": 0.02},
		"desc": "Suede and crepe rubber. The Court's own butlers wear them for a reason.",
		"look": {"col": Color(0.16, 0.14, 0.13), "suede": true}},
	"steel_toes": {"slot": "boots", "name": "Foundry Steel-toes", "r": 2, "drop": true, "mods": {"dmg_taken": -0.05, "speed": -0.03},
		"desc": "Steel caps, steel shanks, a foundry's burn-marks on the leather.",
		"look": {"col": Color(0.08, 0.075, 0.07), "buckles": 3, "cuff": true}},
	"gator_boots": {"slot": "boots", "name": "Gator-skin Boots", "r": 3, "drop": true, "mods": {"max_hp_pct": 0.06, "stamina_regen": 0.05},
		"desc": "The root-woman's gift, from something big that lived under her porch. Lucky, she says.",
		"look": {"col": Color(0.22, 0.24, 0.15), "buckles": 1, "suede": true}},
}


static func get_def(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func slot_of(id: String) -> String:
	return String(ITEMS.get(id, {}).get("slot", ""))


## Every item id for one slot, in data order.
static func items_for(slot: String) -> Array:
	var out: Array = []
	for id in ITEMS:
		if ITEMS[id].slot == slot:
			out.append(id)
	return out


static func start_items() -> Array:
	var out: Array = []
	for id in ITEMS:
		if ITEMS[id].get("start", false):
			out.append(id)
	return out


static func drop_items() -> Array:
	var out: Array = []
	for id in ITEMS:
		if ITEMS[id].get("drop", false):
			out.append(id)
	return out


## A valid outfit: every slot filled with a known item of that slot (missing ones from the default).
static func sanitize(outfit) -> Dictionary:
	var o := {}
	for s in SLOTS:
		var id := String(outfit.get(s, "")) if outfit is Dictionary else ""
		o[s] = id if slot_of(id) == s else String(DEFAULT_OUTFIT[s])
	return o


## The outfit's summed mods, each stat clamped to OUTFIT_CAP.
static func outfit_mods(outfit: Dictionary) -> Dictionary:
	var s := {}
	for slot in SLOTS:
		var mods: Dictionary = ITEMS.get(String(outfit.get(slot, "")), {}).get("mods", {})
		for k in mods:
			s[k] = float(s.get(k, 0.0)) + float(mods[k])
	for k in s.keys():
		if OUTFIT_CAP.has(k):
			s[k] = clampf(s[k], -float(OUTFIT_CAP[k]), float(OUTFIT_CAP[k]))
	return s


## Clamp summed totals (all sources) to STAT_CAPS, in place.
static func clamp_totals(s: Dictionary) -> void:
	for k in STAT_CAPS:
		if s.has(k):
			s[k] = clampf(float(s[k]), float(STAT_CAPS[k][0]), float(STAT_CAPS[k][1]))


## "+10% blood", "-3% speed", "+5 stamina": one stat as the panels show it.
static func stat_text(k: String, v: float) -> String:
	for row in STAT_ROWS:
		if row[0] == k:
			if row[2]:
				return "%s%d%% %s" % ["+" if v >= 0.0 else "-", int(round(absf(v) * 100.0)), String(row[1]).to_lower()]
			return "%s%d %s" % ["+" if v >= 0.0 else "-", int(round(absf(v))), String(row[1]).to_lower()]
	return "%s %+.2f" % [k, v]


## Is this value good for the player (green) or a trade-off (red)?
static func is_good(k: String, v: float) -> bool:
	return v < 0.0 if k in LOWER_BETTER else v > 0.0


## One line of an item's stats ("+10% blood (health), -3% speed").
static func mods_line(id: String) -> String:
	var mods: Dictionary = get_def(id).get("mods", {})
	if mods.is_empty():
		return "no bonuses"
	var bits: Array = []
	for row in STAT_ROWS:
		if mods.has(row[0]):
			bits.append(stat_text(row[0], float(mods[row[0]])))
	return ", ".join(bits)
