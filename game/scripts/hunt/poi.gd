class_name Poi
extends Node3D
## One point of interest in a Hunt: its dressing, its pre-placed camp of enemies (idle until
## Sol comes close), its loot and its "cleared" state. Enemies only exist while Sol is within
## ACTIVATE_RANGE; beyond SLEEP_RANGE an un-roused camp goes back to sleep (freed, remembered).
## Idle enemies are held still by parking enemy.gd's public `speed` at 0 until roused.

const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const Dressing = preload("res://scripts/hunt/poi_dressing.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const Elite = preload("res://scripts/hunt/elite.gd")
const HFx = preload("res://scripts/hunt/hunt_fx.gd")

signal cleared_now(poi)

var director: HuntDirector
var main: Main
var type := ""
var def: Dictionary
var display_name := ""
var cleared := false
var roused := false
var pending: Array = [] # specs not on the field: {kind, elite, ename, off, yaw}
var live: Array = [] # [{e, spec}]
var coffins: Array = [] # [{node, opened}]
var night_added := false
var field_boss_def := {}
var field_boss: Node3D
var used := false # chapels / merchants: visited at least once
var rng := RandomNumberGenerator.new()
var marker: Label3D
var elite_names := {}


func setup(director_, type_: String, seed_: int, boss_def := {}) -> void:
	director = director_
	main = director_.main
	type = type_
	def = Cfg.POI_TYPES[type]
	rng.seed = seed_
	field_boss_def = boss_def
	display_name = def.label if boss_def.is_empty() else title_case(boss_def.name)
	if type == "fieldboss":
		display_name = title_case(boss_def.name.split(",")[0])


## "OLD GRISTLE OF THE PINES" -> "Old Gristle of the Pines" (QA2 #16: not capitalize()'s "Of The").
static func title_case(s: String) -> String:
	var out: Array = []
	for w in s.strip_edges().to_lower().split(" ", false):
		if out.size() > 0 and w in ["of", "the", "and", "a", "in"]:
			out.append(w)
		else:
			out.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(out)


func _ready() -> void:
	process_physics_priority = -10 # hold idle enemies before their own physics runs
	var d := Dressing.build(type, self, rng, def.color)
	for c in d.coffins:
		coffins.append({"node": c, "opened": false})
	marker = Dressing.label(self, display_name.to_upper(), def.color.lightened(0.3), 6.5)
	marker.no_depth_test = false
	_refill(main.is_day())


func is_combat() -> bool:
	return type in ["nest", "camp", "market", "fieldboss"]


## Who lives here in this light. Nests swap their sleepers for the waking Court at night.
func _refill(day: bool) -> void:
	pending.clear()
	if cleared:
		return
	for g in def.day if day else (def.day + def.night):
		for i in int(g.n):
			var spec := {"kind": g.kind, "elite": g.get("elite", ""), "yaw": rng.randf() * TAU}
			var a := rng.randf() * TAU
			var r := rng.randf_range(1.2, 4.0) if spec.elite == "" else 0.6
			spec["off"] = Vector3(cos(a) * r, 0.0, sin(a) * r)
			if spec.elite != "":
				var names: Array = Cfg.ELITES[spec.elite].names
				spec["ename"] = names[rng.randi() % names.size()]
			pending.append(spec)
	night_added = not day


func total_alive() -> int:
	var n := pending.size()
	for l in live:
		if is_instance_valid(l.e) and not l.e.dead:
			n += 1
	if field_boss != null and is_instance_valid(field_boss) and not field_boss.dead:
		n += 1
	return n


func distance_to(p: Vector3) -> float:
	return Vector2(global_position.x - p.x, global_position.z - p.z).length()


## Called by the director when the light changes (dusk / dawn).
func on_light_changed(day: bool) -> void:
	if cleared:
		return
	if not day and not night_added:
		# night falls: the nest wakes, the market's night guard arrives
		for g in def.night:
			for i in int(g.n):
				var spec := {"kind": g.kind, "elite": g.get("elite", ""), "yaw": rng.randf() * TAU,
					"off": Vector3(rng.randf_range(-3.5, 3.5), 0, rng.randf_range(-3.5, 3.5))}
				if spec.elite != "":
					var names: Array = Cfg.ELITES[spec.elite].names
					spec["ename"] = names[rng.randi() % names.size()]
				pending.append(spec)
		night_added = true
	elif day and night_added and type == "nest":
		# dawn: whatever still lives goes back to its coffin
		_sleep_all()
		_refill(true)
		roused = false


# ---------------------------------------------------------------- per frame
## Returns how many enemies it spawned (the director keeps the global budget).
func tick(delta: float, ppos: Vector3, budget: int) -> int:
	var spawned := 0
	if cleared:
		return 0
	var dist := distance_to(ppos)
	if type == "fieldboss":
		return _tick_field_boss(dist, budget)
	# activate / sleep
	if dist < Cfg.ACTIVATE_RANGE and not pending.is_empty() and budget > 0:
		while not pending.is_empty() and spawned < budget:
			_spawn(pending.pop_front())
			spawned += 1
	elif dist > Cfg.SLEEP_RANGE and not roused and not live.is_empty():
		_sleep_all()
	# rouse
	if not roused:
		for l in live:
			var e = l.e
			if not is_instance_valid(e) or e.dead:
				roused = true
				break
			if e.global_position.distance_to(ppos) < (director.aggro_range() if director != null else Cfg.AGGRO_RANGE * (main.player.detect_mult() if main.player.has_method("detect_mult") else 1.0)) or e.hp < e.max_hp - 0.01 or e.staggered:
				roused = true
				break
		if roused and director != null:
			director.on_poi_roused(self)
	# hold idle ones in place: their speed is parked at 0 (they stand in their idle clip and
	# keep a wary eye on Sol) and handed back the moment the camp is roused
	for l in live:
		var e = l.e
		if not is_instance_valid(e) or e.dead:
			continue
		if not roused:
			if e.speed > 0.0:
				l["speed"] = e.speed # also picks up a wolf transform's new speed
				e.speed = 0.0
		elif l.has("speed"):
			if e.speed <= 0.0:
				e.speed = l.speed
			l.erase("speed")
	# cleared?
	if not live.is_empty() or pending.is_empty():
		var done := pending.is_empty()
		for l in live:
			if is_instance_valid(l.e) and not l.e.dead:
				done = false
				break
		if done and (roused or live.size() > 0) and is_combat():
			_clear()
	return spawned


func _tick_field_boss(dist: float, budget: int) -> int:
	if field_boss == null and dist < Cfg.ACTIVATE_RANGE and budget > 0:
		var script: GDScript = load("res://scripts/hunt/bosses/field_boss.gd")
		var b = script.new()
		b.main = main
		b.director = director
		b.variant = field_boss_def.id
		b.boss_name = field_boss_def.name
		b.base_hp = field_boss_def.hp
		b.dormant = true
		b.home = global_position
		b.position = global_position + Vector3(0, 0.05, 2.6)
		main.enemies_root.add_child(b)
		field_boss = b
		return 1
	if field_boss != null and not is_instance_valid(field_boss):
		field_boss = null
		_clear()
		return 0
	if field_boss != null and field_boss.dead and not cleared:
		_clear()
	elif field_boss != null and not field_boss.dead and field_boss.dormant and dist > Cfg.SLEEP_RANGE:
		field_boss.queue_free() # asleep again; he'll be back at full strength
		field_boss = null
	return 0


func _spawn(spec: Dictionary) -> void:
	var e: CharacterBody3D = EnemyScript.new()
	e.main = main
	e.kind = spec.kind
	e.position = global_position + spec.off + Vector3(0, 0.05, 0)
	main.enemies_root.add_child(e)
	e.visual.rotation.y = spec.yaw
	if spec.elite != "":
		Elite.apply(e, Cfg.ELITES[spec.elite], spec.ename)
	live.append({"e": e, "spec": spec})


## Free the field members who were never roused and remember them for later.
func _sleep_all() -> void:
	for l in live:
		var e = l.e
		if is_instance_valid(e) and not e.dead:
			if night_added or l.spec.kind == 1 or main.is_day(): # vampires only come back at night
				pending.append(l.spec)
			main.release_attack_token(e)
			e.queue_free()
	live.clear()


## Take members off the field without counting them as killed (the boss arena wall went
## up between them and Sol, or the Final Night moved him). `keep(e) -> bool` spares some.
func recall(keep: Callable = Callable()) -> void:
	for i in range(live.size() - 1, -1, -1):
		var l: Dictionary = live[i]
		var e = l.e
		if not is_instance_valid(e) or e.dead:
			continue
		if keep.is_valid() and keep.call(e):
			continue
		pending.append(l.spec)
		main.release_attack_token(e)
		e.queue_free()
		live.remove_at(i)
	if live.is_empty():
		roused = false
	if field_boss != null and is_instance_valid(field_boss) and not field_boss.dead and not (keep.is_valid() and keep.call(field_boss)):
		field_boss.queue_free()
		field_boss = null


func _clear() -> void:
	if cleared:
		return
	cleared = true
	marker.text = display_name.to_upper() + "\nCLEARED"
	marker.modulate = Color(0.6, 0.6, 0.6)
	cleared_now.emit(self)


# ---------------------------------------------------------------- interaction
## The nearest thing to do here within reach, or {}.
func interaction(ppos: Vector3) -> Dictionary:
	if type == "chapel" and distance_to(ppos) < 3.2:
		return {"text": "KEEP VIGIL  ·  spend Tithe to rise a rank", "act": "vigil"}
	if type == "merchant" and distance_to(ppos) < 3.4:
		return {"text": "TRADE WITH THE NIGHT MERCHANT", "act": "trade"}
	for c in coffins:
		if not c.opened and Vector2(c.node.global_position.x - ppos.x, c.node.global_position.z - ppos.z).length() < 2.3:
			return {"text": "PRY OPEN THE COFFIN", "act": "coffin", "coffin": c}
	return {}


func open_coffin(c: Dictionary) -> void:
	if c.opened:
		return
	c.opened = true
	var lid: Node3D = c.node.get_node("Lid")
	var tw := create_tween()
	tw.tween_property(lid, "rotation:z", -1.9, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	director.coffin_loot(c.node.global_position, main.is_day())
	HFx.puff(self, c.node.global_position + Vector3(0, 0.6, 0), Color(0.4, 0.4, 0.4), 8, 0.12, 1.4)
