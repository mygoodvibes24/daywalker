extends RefCounted
## Lays out a Hunt's points of interest from the pool with a seeded RNG, on street
## crossings taken from city.gd's layout data (blocks / lots, read-only).

const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const CityScript = preload("res://scripts/city.gd")
const MIN_SPACING := 22.0


## Every street crossing free for a POI: the corners of city.gd's `blocks` (read-only
## layout data), outside PLAZA_RECT, clear of every building footprint in `lots`, and away
## from the cathedral front, the boss arenas and the deployment points.
static func candidate_spots(city) -> Array:
	var g: float = CityScript.GRID
	var seen := {}
	var out: Array = []
	var blocks: Array = city.blocks if city != null and "blocks" in city else []
	var lots: Array = city.lots if city != null and "lots" in city else []
	var plaza: Rect2 = CityScript.PLAZA_RECT.grow(4.0)
	var edge: float = CityScript.BLOCKS * g - 1.0
	for b in blocks:
		var c: Vector2 = b.centre
		for sx in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				var q := Vector2(c.x + sx * g, c.y + sz * g)
				var key := "%d_%d" % [roundi(q.x), roundi(q.y)]
				if seen.has(key):
					continue
				seen[key] = true
				if absf(q.x) >= edge or absf(q.y) >= edge or plaza.has_point(q):
					continue
				if absf(q.x) <= g and q.y <= -g and q.y >= -2.0 * g:
					continue # the cathedral front
				var bad := false
				for r in lots:
					if (r as Rect2).grow(2.5).has_point(q):
						bad = true
						break
				for a in Cfg.ARENAS + [Cfg.FINAL_ARENA]:
					if q.distance_to(Vector2(a.pos.x, a.pos.z)) < 14.0:
						bad = true
				for d in Cfg.DEPLOY_POINTS:
					if q.distance_to(Vector2(d.pos.x, d.pos.z)) < 18.0:
						bad = true
				if not bad:
					out.append(Vector3(q.x, 0.0, q.y))
	out.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.z < b.z)) # stable before the seeded shuffle
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
	for type in wanted:
		for idx in spots.size():
			var p: Vector3 = spots[idx]
			var ok := true
			for o in out:
				# two camps of enemies need a block between them; a chapel or cart can sit next door
				var calm: bool = type in ["chapel", "merchant"] or o.type in ["chapel", "merchant"]
				if o.pos.distance_to(p) < (MIN_SPACING if not calm else 19.0):
					ok = false
					break
			if ok:
				var e := {"type": type, "pos": p, "seed": rng.randi()}
				if type == "fieldboss":
					e["boss"] = bosses.pop_front() if not bosses.is_empty() else Cfg.FIELD_BOSSES[0]
				out.append(e)
				spots.remove_at(idx)
				break
	return out
