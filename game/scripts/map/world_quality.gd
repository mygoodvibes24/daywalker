extends RefCounted
## The world builders' view of the quality settings (Group C <-> the Performance and
## Scalability agent).
##
## COORDINATION: the Performance agent owns settings.gd and is adding quality tiers (Very Low ..
## High) with `Settings.tier`, `Settings.view_distance`, `Settings.foliage_density`,
## `Settings.shadow_quality` and a `changed` signal. Until those land, every getter here falls
## back to a default derived from the existing `Settings.quality` (Low / Medium / High) and the
## render tier, so the world code never depends on the order the branches merge in. Once the
## real fields exist they win automatically (read by name, no code change needed here):
##   tier            int    0 Very Low, 1 Low, 2 Medium, 3 High
##   view_distance   float  metres the world is drawn to (the city chunks, trees, props)
##   foliage_density float  0..1 share of trees, bushes and undergrowth instances drawn
##   prop_density    float  0..1 share of street clutter instances drawn (optional)
##   shadow_quality  int    0 off, 1 low (one short cascade), 2 high
##
## city.gd registers its scalable nodes (visibility ranges, MultiMesh counts, lights) and
## re-applies them live whenever Settings emits `changed` (see city.gd apply_quality()).


const VERY_LOW := 0
const LOW := 1
const MEDIUM := 2
const HIGH := 3

## View distance (m) per tier on the web renderer; the cinematic (Forward+) tier draws further.
const VIEW_WEB := [55.0, 75.0, 90.0, 110.0]
const VIEW_CINEMATIC := [70.0, 100.0, 130.0, 160.0]
const FOLIAGE := [0.3, 0.55, 0.8, 1.0]
const PROPS := [0.35, 0.6, 0.85, 1.0]
const SHADOWS := [0, 1, 1, 2]


static func _read(key: String, fallback):
	# read through a plain Object (the script's static vars, which the autoload shares) so a field
	# that doesn't exist yet is just null rather than a parse error
	var src: Object = load("res://scripts/settings.gd")
	var v = src.get(key) if key in src else null
	return fallback if v == null else v


static func is_web() -> bool:
	return preload("res://scripts/atmosphere.gd").detect_tier() == "web"


## 0 Very Low .. 3 High. Default: the old 3-step quality mapped onto Low / Medium / High, and
## touch devices (phones) start one step lower.
static func tier() -> int:
	var q := int(_read("quality", 2)) # 0 Low, 1 Medium, 2 High
	var t := q + 1
	if OS.has_feature("web") and (OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()):
		t -= 1
	return clampi(int(_read("tier", t)), VERY_LOW, HIGH)


static func view_distance() -> float:
	var table: Array = VIEW_WEB if is_web() else VIEW_CINEMATIC
	return clampf(float(_read("view_distance", table[tier()])), 35.0, 400.0)


static func foliage_density() -> float:
	return clampf(float(_read("foliage_density", FOLIAGE[tier()])), 0.0, 1.0)


static func prop_density() -> float:
	return clampf(float(_read("prop_density", PROPS[tier()])), 0.0, 1.0)


static func shadow_quality() -> int:
	return clampi(int(_read("shadow_quality", SHADOWS[tier()])), 0, 2)


## A visibility range authored for High, scaled to the current view distance.
static func range_scale() -> float:
	var table: Array = VIEW_WEB if is_web() else VIEW_CINEMATIC
	return view_distance() / float(table[HIGH])
