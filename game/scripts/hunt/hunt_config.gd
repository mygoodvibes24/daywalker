extends RefCounted
## The Hunt, as data: phase timings, deployment points, boss arenas, the point-of-interest
## pool, elites and bosses. hunt_director.gd, poi_spawner.gd and poi.gd read this; tune here.

# ---------------------------------------------------------------- timings (seconds)
## One "day" = explore -> the Curfew closes (stage 1) -> hold -> closes again (stage 2) -> night boss.
## Two days and a Final Night: ~4.9 min per day + three boss fights = roughly 14-17 minutes.
const TIMINGS := {
	"normal": {"explore": 170.0, "shrink1": 35.0, "hold": 55.0, "shrink2": 35.0, "victory": 9.0, "final_dusk": 20.0, "boss_hp": 1.0},
	"short": {"explore": 20.0, "shrink1": 6.0, "hold": 8.0, "shrink2": 6.0, "victory": 4.0, "final_dusk": 5.0, "boss_hp": 0.35},
}
## time_of_day at the start / end of each phase (0.75 is dusk: night falls as the Curfew first closes).
const CLOCK := {"explore": [0.30, 0.72], "shrink1": [0.72, 0.78], "hold": [0.78, 0.84], "shrink2": [0.84, 0.88], "boss": [0.92, 0.92]}
const REVIVES_PER_DAY := 1
const MAX_ACTIVE_ENEMIES := 14
const ACTIVATE_RANGE := 60.0 # POI enemies exist only within this distance of Sol
const SLEEP_RANGE := 80.0 # ...and go back to sleep (if never roused) beyond this
const AGGRO_RANGE := 17.0
const ROAM_EVERY := 18.0 # a light trickle of roaming spawns
const ROAM_CAP := 5

# ---------------------------------------------------------------- the Red Curfew
const CURFEW_NAME := "the Red Curfew"
const RING_STAGE1 := 55.0 # radius after the first close
const RING_DAMAGE := 5.0 # HP/s the moment you're outside...
const RING_RAMP := 4.0 # ...plus this per second you stay out
const RING_DAMAGE_MAX := 32.0

# ---------------------------------------------------------------- deployment ("the Descent")
## Around the map edge on street centrelines, never the plaza. type: subway | manhole | rooftop.
const DEPLOY_POINTS := [
	{"name": "Dockside Station", "type": "subway", "pos": Vector3(-60, 0, -72), "face": Vector3(0, 0, 1)},
	{"name": "Velvet Mile Station", "type": "subway", "pos": Vector3(72, 0, 40), "face": Vector3(-1, 0, 0)},
	{"name": "Storm Drain 9", "type": "manhole", "pos": Vector3(-72, 0, 20), "face": Vector3(1, 0, 0)},
	{"name": "Midtown Storm Drain", "type": "manhole", "pos": Vector3(20, 0, 74), "face": Vector3(0, 0, -1)},
	{"name": "St. Roch Rooftops", "type": "rooftop", "pos": Vector3(40, 0, -72), "face": Vector3(0, 0, 1)},
	{"name": "Cannery Rooftops", "type": "rooftop", "pos": Vector3(-40, 0, 72), "face": Vector3(0, 0, -1)},
]

# ---------------------------------------------------------------- boss arenas
## Night 1 and Night 2 draw from ARENAS; the Final Night is always fought at FINAL_ARENA.
const ARENAS := [
	{"id": "cathedral", "name": "the Cathedral Steps", "pos": Vector3(0, 0, -20), "radius": 15.0},
	{"id": "pier", "name": "Pier Nine Crossing", "pos": Vector3(-60, 0, 40), "radius": 15.0},
	{"id": "velvet", "name": "Velvet Mile Crossing", "pos": Vector3(60, 0, -20), "radius": 15.0},
	{"id": "midtown", "name": "the Foundry Crossing", "pos": Vector3(40, 0, 60), "radius": 15.0},
]
const FINAL_ARENA := {"id": "plaza", "name": "the Undercroft Plaza", "pos": Vector3(0, 0, 6), "radius": 16.0}

# ---------------------------------------------------------------- bosses
const BOSSES := [
	{"script": "res://scripts/hunt/bosses/hollow_alpha.gd", "name": "THE HOLLOW ALPHA", "title": "Night 1  ·  Mother Wren's Firstborn", "hp": 1400.0, "tithe": 260, "full_moon": true},
	{"script": "res://scripts/hunt/bosses/velvet_fang.gd", "name": "MARCUS CRANE, THE VELVET FANG", "title": "Night 2  ·  Blood Dealer of the Velvet Mile", "hp": 1500.0, "tithe": 340, "full_moon": false},
	{"script": "res://scripts/hunt/bosses/abomination.gd", "name": "SERAPHINE'S ABOMINATION", "title": "The Final Night  ·  Stitched from Court and Pack", "hp": 2400.0, "tithe": 500, "full_moon": true},
]

# ---------------------------------------------------------------- points of interest
## n = how many per Hunt. Enemy specs: {kind 0 vampire | 1 Pack civilian, n, elite?}.
## "day" / "night" groups: who is there in that light (a nest's vampires only rise at night).
const POI_TYPES := {
	"nest": {"label": "Velvet Nest", "n": 3, "color": Color(0.95, 0.12, 0.22),
		"day": [{"kind": 1, "n": 2}], "night": [{"kind": 0, "n": 3}, {"kind": 0, "n": 1, "elite": "courtier"}],
		"coffins": 2, "tithe": 60, "reward": 1,
		"blurb": "Sleeping by day: raid the coffins. Awake at night."},
	"camp": {"label": "Hollow Camp", "n": 3, "color": Color(1.0, 0.55, 0.12),
		"day": [{"kind": 1, "n": 3}, {"kind": 1, "n": 1, "elite": "pack_leader"}], "night": [],
		"tithe": 55, "reward": 1, "blurb": "Pack squatters. They turn when the sun goes down."},
	"market": {"label": "Blood Market", "n": 2, "color": Color(1.0, 0.82, 0.3),
		"day": [{"kind": 1, "n": 3}, {"kind": 1, "n": 1, "elite": "fence"}], "night": [{"kind": 0, "n": 1}],
		"tithe": 70, "reward": 2, "blurb": "A smugglers' crate fort. A guaranteed Hallowed find."},
	"fieldboss": {"label": "Landmark", "n": 2, "color": Color(0.8, 0.4, 1.0),
		"day": [], "night": [], "tithe": 150, "reward": 3, "blurb": "A named horror guards an Eclipse relic-blade."},
	"chapel": {"label": "Wayside Chapel", "n": 3, "color": Color(1.0, 0.92, 0.7),
		"day": [], "night": [], "tithe": 0, "reward": -1, "blurb": "Keep Vigil here: spend Tithe to rise a rank."},
	"merchant": {"label": "Night Merchant", "n": 2, "color": Color(0.45, 1.0, 0.6),
		"day": [], "night": [], "tithe": 0, "reward": -1, "blurb": "Spend Tithe on vials and blades."},
}
## Field bosses: one of these per Landmark (no repeats while there are spares).
const FIELD_BOSSES := [
	{"id": "blood_knight", "name": "SIR AURELIEN, BLOOD KNIGHT", "hp": 520.0, "tithe": 0},
	{"id": "old_gristle", "name": "OLD GRISTLE OF THE PINES", "hp": 480.0, "tithe": 0},
	{"id": "blood_knight", "name": "DAME CORVINA, BLOOD KNIGHT", "hp": 560.0, "tithe": 0},
]
const ELITES := {
	"courtier": {"names": ["Courtier Delacroix", "Courtier Valmont", "Lady Esme of the Court", "Courtier Saint-Clair"],
		"hp": 3.0, "dmg": 1.6, "speed": 1.1, "scale": 1.2, "aura": Color(1.0, 0.08, 0.3)},
	"pack_leader": {"names": ["Big Remy Hollow", "Tante Odile", "Jean-Baptiste the Turned", "Cousin Thibodeaux"],
		"hp": 2.6, "dmg": 1.5, "speed": 1.05, "scale": 1.25, "aura": Color(1.0, 0.6, 0.1)},
	"fence": {"names": ["Gator Boudreaux", "Sweet Marie the Fence", "One-Ear Fontenot"],
		"hp": 2.4, "dmg": 1.4, "speed": 1.0, "scale": 1.15, "aura": Color(1.0, 0.85, 0.25)},
}

# ---------------------------------------------------------------- the merchant
const MERCHANT_STOCK := [
	{"id": "blood_vial", "r": 0, "n": 2, "price": 30},
	{"id": "vintage_vial", "r": 0, "n": 1, "price": 55},
	{"id": "dawn_flare", "r": 1, "n": 1, "price": 45},
	{"random_blade": true, "r": 1, "price": 80},
	{"random_blade": true, "r": 2, "price": 150},
]

# ---------------------------------------------------------------- the meta currency
const META_NAME := "Sunmarks"
## Charms you can buy in the Undercroft with Sunmarks (Street rarity; finds can be better).
const ARMOURY_SHOP := [
	{"id": "red_flannel", "price": 0}, {"id": "john_root", "price": 0},
	{"id": "grave_salt", "price": 40}, {"id": "iron_rosary", "price": 40}, {"id": "pack_fang", "price": 40},
	{"id": "noon_medal", "price": 60}, {"id": "thorn_rosary", "price": 60}, {"id": "knucklebones", "price": 70},
	{"id": "gamblers_dice", "price": 70}, {"id": "mirror_shard", "price": 90}, {"id": "vigil_candle", "price": 90},
	{"id": "black_candle", "price": 120},
]


static func timings(short: bool) -> Dictionary:
	return TIMINGS.short if short else TIMINGS.normal


static func day_length(short: bool) -> float:
	var t := timings(short)
	return t.explore + t.shrink1 + t.hold + t.shrink2
