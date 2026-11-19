class_name MicroPoi
extends Node3D
## A micro-POI: a small one-use find on the road between the big sites (hunt_config.gd
## MICRO_POIS), so the walk from camp to camp has something on it. No enemies and no colliders
## (nothing for the navmesh to care about): one [E] interaction, one reward, then it goes dark.
##   cache   - a smuggler's crate: Tithe and usually a find
##   captive - someone tied to a post: cut them loose for two Blood Vials and a little Tithe
##   fridge  - a humming cooler of bagged blood: heal 50 and ease the hunger
##   shrine  - a street shrine: +8 max blood for the rest of the Hunt
## The props are a handful of primitives merged into one draw per material, faded out by
## visibility range, so fourteen of them cost almost nothing on the web build.

const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const Dressing = preload("res://scripts/hunt/poi_dressing.gd")
const ItemDB = preload("res://scripts/items/item_db.gd")
const HFx = preload("res://scripts/hunt/hunt_fx.gd")
const U = preload("res://scripts/util.gd")

const REACH := 2.6 # flat metres for the [E] prompt
const DRAW_RANGE := 90.0 # meshes fade out beyond this
const LABEL_RANGE := 26.0

var director
var main
var type := ""
var def: Dictionary
var used := false
var rng := RandomNumberGenerator.new()
var marker: Label3D
var beacon: MeshInstance3D
var lid: Node3D # cache lid / fridge door / the captive's body


## [{type, pos, yaw, seed}] for one Hunt: on the map's road points, away from the plaza, the
## arenas, the deployment points, the big POIs (`avoid`: positions) and each other.
static func generate(seed_: int, city, avoid: Array) -> Array:
	var rng_ := RandomNumberGenerator.new()
	rng_.seed = seed_ * 31 + 7
	var roads: Array = []
	if city != null and "road_points" in city:
		for r in city.road_points:
			roads.append(r)
	var rect: Rect2 = city.play_rect.grow(-6.0) if city != null and "play_rect" in city else Rect2(-200, -200, 400, 400)
	for k in range(roads.size() - 1, 0, -1):
		var s := rng_.randi_range(0, k)
		var t = roads[k]
		roads[k] = roads[s]
		roads[s] = t
	var wanted: Array = []
	var most := 0
	for t in Cfg.MICRO_POIS:
		most = maxi(most, int(Cfg.MICRO_POIS[t].n))
	for i in most:
		for t in Cfg.MICRO_POIS:
			if i < int(Cfg.MICRO_POIS[t].n):
				wanted.append(t)
	var out: Array = []
	var ri := 0
	for t in wanted:
		while ri < roads.size():
			var p: Vector3 = roads[ri]
			ri += 1
			if _ok(p, rect, avoid, out):
				out.append({"type": t, "pos": p, "yaw": rng_.randf() * TAU, "seed": rng_.randi()})
				break
	return out


static func _ok(p: Vector3, rect: Rect2, avoid: Array, out: Array) -> bool:
	var q := Vector2(p.x, p.z)
	if q.length() < 26.0 or not rect.has_point(q):
		return false
	for ar in Cfg.ARENAS + [Cfg.FINAL_ARENA]:
		if q.distance_to(Vector2(ar.pos.x, ar.pos.z)) < float(ar.radius) + 8.0:
			return false
	for d in Cfg.DEPLOY_POINTS:
		if q.distance_to(Vector2(d.pos.x, d.pos.z)) < 18.0:
			return false
	for a in avoid:
		if q.distance_to(Vector2(a.x, a.z)) < Cfg.MICRO_CLEAR:
			return false
	for o in out:
		if q.distance_to(Vector2(o.pos.x, o.pos.z)) < Cfg.MICRO_SPACING:
			return false
	return true


func setup(director_, type_: String, seed_: int) -> void:
	director = director_
	main = director_.main
	type = type_
	def = Cfg.MICRO_POIS[type]
	rng.seed = seed_


func _ready() -> void:
	var m := Dressing.mats()
	var c: Color = def.color
	match type:
		"cache":
			Dressing.crate(self, Vector3(0.9, 0, -0.5), 0.7, 0.4, false)
			_p(U.box(Vector3(1.1, 0.6, 0.75)), m.wood_dark, Vector3(0, 0.3, 0))
			_p(U.box(Vector3(1.14, 0.06, 0.08)), m.iron, Vector3(0, 0.45, 0.36))
			lid = Node3D.new()
			lid.name = "Lid"
			lid.position = Vector3(0, 0.6, -0.375)
			add_child(lid)
			U.part(lid, U.box(Vector3(1.12, 0.1, 0.77)), m.wood, Vector3(0, 0.05, 0.375))
			U.part(lid, U.box(Vector3(0.12, 0.12, 0.08)), m.gold, Vector3(0, 0.0, 0.77))
		"captive":
			_p(U.cyl(0.08, 0.1, 2.2), m.wood, Vector3(0, 1.1, -0.25))
			lid = Node3D.new()
			lid.name = "Lid"
			add_child(lid)
			var cloth := U.mat(Color(0.32, 0.28, 0.24), 0.95)
			var skin := U.mat(Color(0.45, 0.32, 0.25), 0.6)
			U.part(lid, U.capsule(0.2, 0.75), cloth, Vector3(0, 0.55, 0), Vector3(0.25, 0, 0)) # kneeling torso
			U.part(lid, U.sphere(0.13), skin, Vector3(0, 1.05, 0.08))
			U.part(lid, U.box(Vector3(0.38, 0.16, 0.55)), cloth, Vector3(0, 0.12, 0.12)) # folded legs
			U.part(lid, U.box(Vector3(0.3, 0.06, 0.06)), U.mat(Color(0.9, 0.88, 0.85)), Vector3(0, 1.08, 0.18)) # gag
			for y in [0.45, 0.7]:
				_p(U.cyl(0.24, 0.24, 0.04), U.mat(Color(0.4, 0.3, 0.15), 0.95), Vector3(0, y, -0.15))
			Dressing.candle_cluster(self, Vector3(0.7, 0, 0.5))
		"fridge":
			var white := U.mat(Color(0.75, 0.74, 0.7), 0.4, 0.3)
			_p(U.box(Vector3(0.85, 1.7, 0.7)), white, Vector3(0, 0.85, 0))
			_p(U.box(Vector3(0.75, 1.5, 0.02)), m.blood, Vector3(0, 0.9, 0.34)) # the red glow inside
			for i in 3:
				_p(U.box(Vector3(0.18, 0.26, 0.06)), U.mat(Color(0.5, 0.0, 0.03), 0.3), Vector3(-0.22 + i * 0.22, 1.2, 0.3))
			lid = Node3D.new()
			lid.name = "Lid"
			lid.position = Vector3(0.43, 0.0, 0.37)
			add_child(lid)
			U.part(lid, U.box(Vector3(0.84, 1.66, 0.06)), white, Vector3(-0.42, 0.86, 0))
			U.part(lid, U.box(Vector3(0.04, 0.5, 0.05)), m.iron, Vector3(-0.78, 1.0, 0.05))
			U.part(lid, U.box(Vector3(0.6, 0.22, 0.01)), U.mat(Color(0.75, 0.1, 0.1)), Vector3(-0.42, 1.45, 0.035)) # a red-cross sticker
			_p(U.box(Vector3(0.12, 0.05, 0.6)), U.mat(Color(0.1, 0.1, 0.1)), Vector3(0.0, 0.03, -0.55)) # the cord
		"shrine":
			_p(U.box(Vector3(0.9, 0.8, 0.6)), m.stone, Vector3(0, 0.4, 0))
			_p(U.box(Vector3(1.0, 0.08, 0.7)), m.stone, Vector3(0, 0.84, 0))
			_p(U.capsule(0.13, 0.62), U.mat(Color(0.85, 0.83, 0.8), 0.7), Vector3(0, 1.2, -0.1))
			_p(U.sphere(0.1), U.mat(Color(0.85, 0.83, 0.8), 0.7), Vector3(0, 1.58, -0.1))
			_p(U.cyl(0.16, 0.16, 0.02), m.gold, Vector3(0, 1.7, -0.14), Vector3(PI / 2, 0, 0)) # the halo
			Dressing.candle_cluster(self, Vector3(-0.28, 0.88, 0.12))
			Dressing.candle_cluster(self, Vector3(0.3, 0.88, 0.14))
			for i in 4:
				_p(U.sphere(0.06), U.mat(Color(0.75, 0.1, 0.25), 0.8), Vector3(-0.35 + i * 0.23, 0.05, 0.45))
	Dressing.merge_parts(self, [lid] if lid != null else [])
	# a small glowing shard over it so it reads at night and from down the street
	beacon = _p(U.sphere(0.12), U.glow(c, 4.0), Vector3(0, 2.3, 0))
	beacon.scale = Vector3(1.0, 1.8, 1.0)
	for mi in find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		g.visibility_range_end = DRAW_RANGE
		g.visibility_range_end_margin = 8.0
	marker = Dressing.label(self, String(def.label).to_upper(), c.lightened(0.35), 2.85)
	marker.font_size = 30
	marker.no_depth_test = false
	marker.visibility_range_end = LABEL_RANGE


func _p(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := U.part(self, mesh, mat, pos, rot)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func distance_to(p: Vector3) -> float:
	return Vector2(global_position.x - p.x, global_position.z - p.z).length()


## The [E] prompt here, or {} (used or out of reach). Same shape as poi.gd's.
func interaction(ppos: Vector3) -> Dictionary:
	if used or distance_to(ppos) > REACH or not visible:
		return {}
	return {"text": String(def.act), "act": "micro"}


## Take what's here. Returns true if it paid out.
func use() -> bool:
	if used:
		return false
	used = true
	var p = main.player
	var prog = main.progression
	var pos := global_position
	match type:
		"cache":
			main.loot.spawn_motes(pos + Vector3(0, 1.0, 0), int(round(rng.randi_range(25, 45) * (1.0 + prog.stat("tithe_mult")))))
			if rng.randf() < 0.65:
				main.loot.spawn_item(director.random_item(ItemDB.UNCOMMON), pos + Vector3(0.9, 0, 0.9))
			main.hud.popup("SMUGGLER'S CACHE")
			_swing(-1.7, "rotation:x")
			Audio.play_at("manhole_clank", pos, -6.0) # AUDIO HOOK
		"captive":
			main.loot.spawn_item(ItemDB.make("blood_vial", ItemDB.COMMON, 2), pos + Vector3(0.6, 0, 0.9))
			main.loot.spawn_motes(pos + Vector3(0, 1.0, 0), int(round(20 * (1.0 + prog.stat("tithe_mult")))))
			main.hud.popup("FREED  ·  \"Take these. Don't let them find me again.\"")
			if lid != null:
				var tw := create_tween()
				tw.tween_property(lid, "position:y", 0.35, 0.25)
				tw.tween_property(lid, "position", lid.position + Vector3(0, 0.35, 6.0), 0.9)
				tw.tween_callback(lid.hide)
		"fridge":
			p.heal(50.0)
			p.hunger = maxf(p.hunger - 40.0, 0.0)
			main.hud.popup("BAGGED BLOOD  +50  ·  the hunger eases")
			_swing(1.6, "rotation:y")
			Audio.play_at("bite", pos, -6.0) # AUDIO HOOK
		"shrine":
			prog.add_run_mod("max_hp", Cfg.SHRINE_HP)
			p.heal(Cfg.SHRINE_HP)
			main.hud.popup("THE SHRINE ANSWERS  ·  +%d MAX BLOOD" % int(Cfg.SHRINE_HP))
			HFx.shockwave(main, pos, 2.5, Color(0.85, 0.8, 1.0), 0.5)
			Audio.play("level_up", -10.0) # AUDIO HOOK
	HFx.puff(main, pos + Vector3(0, 1.2, 0), def.color, 8, 0.12, 1.4)
	if beacon != null:
		beacon.visible = false
	marker.text = String(def.label).to_upper() + "\nTAKEN"
	marker.modulate = Color(0.55, 0.55, 0.55)
	return true


func _swing(to: float, prop: String) -> void:
	if lid == null:
		return
	var tw := create_tween()
	tw.tween_property(lid, prop, to, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
