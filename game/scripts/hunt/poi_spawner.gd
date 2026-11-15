extends RefCounted
## Lays out a Hunt's points of interest from the pool with a seeded RNG, on the open spots
## the map exposes (city.gd's `poi_anchors`: street crossings, clearings, islands, yards...),
## each type in its thematic districts (hunt_config.gd POI_TYPES[type].districts).

const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const MIN_SPACING := 30.0 # two camps of enemies get a good sprint between them
const CALM_SPACING := 20.0 # a chapel or a cart can sit closer


## Every anchor free for a POI: away from the plaza, the boss arenas and the deployment
## points. [{pos, district, tag}]
static func candidate_spots(city) -> Array:
	var anchors: Array = city.poi_anchors if city != null and "poi_anchors" in city else []
	var out: Array = []
	for a in anchors:
		var p: Vector3 = a.pos
		var q := Vector2(p.x, p.z)
		if q.length() < 24.0:
			continue # the plaza
		var bad := false
		for ar in Cfg.ARENAS + [Cfg.FINAL_ARENA]:
			if q.distance_to(Vector2(ar.pos.x, ar.pos.z)) < float(ar.radius) + 6.0:
				bad = true
		for d in Cfg.DEPLOY_POINTS:
			if q.distance_to(Vector2(d.pos.x, d.pos.z)) < 18.0:
				bad = true
		if not bad:
			out.append(a)
	out.sort_custom(func(a, b): return a.pos.x < b.pos.x or (a.pos.x == b.pos.x and a.pos.z < b.pos.z)) # stable before the seeded shuffle
	return out


## [{type, pos, seed, boss?}] for one Hunt.
static func generate(seed_: int, city) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var spots := candidate_spots(city)
	# deterministic shuffle
	for k in range(spots.size() - 1, 0, -1):
		var s := rng.randi_range(0, k)
		var t = spots[k]
		spots[k] = spots[s]
		spots[s] = t
	# round-robin over the pool so every kind of site gets placed before any gets its extras
	var wanted: Array = []
	var most := 0
	for type in Cfg.POI_TYPES:
		most = maxi(most, int(Cfg.POI_TYPES[type].n))
	for i in most:
		for type in Cfg.POI_TYPES:
			if i < int(Cfg.POI_TYPES[type].n):
				wanted.append(type)
	var bosses: Array = Cfg.FIELD_BOSSES.duplicate()
	for k in range(bosses.size() - 1, 0, -1):
		var s := rng.randi_range(0, k)
		var t = bosses[k]
		bosses[k] = bosses[s]
		bosses[s] = t
	var out: Array = []
	var per_district := {}
	for type in wanted:
		var def: Dictionary = Cfg.POI_TYPES[type]
		var dists: Array = def.get("districts", [])
		var tags: Array = def.get("tags", [])
		# pass 0: the type's own districts (and tags), spreading over districts; pass 1: anywhere
		var placed := false
		for pass_ in 2:
			var best := -1
			var best_load := 1 << 30
			for idx in spots.size():
				var a: Dictionary = spots[idx]
				if pass_ == 0:
					if not dists.is_empty() and not a.district in dists:
						continue
					if not tags.is_empty() and not a.tag in tags:
						continue
				if not _spaced(out, type, a.pos):
					continue
				# prefer the district that has the fewest of this type so far (first in shuffle order wins ties)
				var load: int = per_district.get(type + "|" + a.district, 0)
				if load < best_load:
					best_load = load
					best = idx
					if load == 0:
						break
			if best >= 0:
				var a: Dictionary = spots[best]
				var e := {"type": type, "pos": a.pos, "seed": rng.randi(), "district": a.district}
				if type == "fieldboss":
					e["boss"] = bosses.pop_front() if not bosses.is_empty() else Cfg.FIELD_BOSSES[0]
				out.append(e)
				var key: String = type + "|" + a.district
				per_district[key] = int(per_district.get(key, 0)) + 1
				spots.remove_at(best)
				placed = true
				break
		if not placed:
			continue
	return out


static func _spaced(out: Array, type: String, p: Vector3) -> bool:
	for o in out:
		var calm: bool = type in ["chapel", "merchant"] or o.type in ["chapel", "merchant"]
		if o.pos.distance_to(p) < (MIN_SPACING if not calm else CALM_SPACING):
			return false
	return true
