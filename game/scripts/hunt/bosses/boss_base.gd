extends CharacterBody3D
## Shared body and brain for Hunt bosses (night bosses and field-boss landmarks).
## No new art: the existing vampire / werewolf rigs, scaled up, tinted with an overlay,
## wrapped in a fresnel aura and posed procedurally here (independent of enemy.gd).
## Speaks enemy.gd's public API (kind, transformed, staggered, dead, max_hp, hp, take_hit,
## drain), so the player's blade, the Vows and loot treat it like any other enemy.
##
## Attacks are data: {type, windup, ...}. Every attack telegraphs (a wind-up pose and a
## red ground marker), commits its aim, and can be dashed through (perfect dodge) or outrun.
##   swipe  {range, arc, dmg}            slam  {radius, dmg, leap (s), self?}
##   dash   {length, dmg, chain}          bolts {count, spread, dmg, ring?}
##   howl   {summon: [kind...]}           blink {then: attack}

const U = preload("res://scripts/util.gd")
const HFx = preload("res://scripts/hunt/hunt_fx.gd")
const MODEL_PATHS := {
	"vampire": "res://assets/characters/vampire/vampire_rig.scn",
	"werewolf": "res://assets/characters/werewolf/werewolf_rig.scn",
	"civilian": "res://assets/characters/civilian/civilian_rig.scn",
}
const GRAVITY := 24.0

signal died(boss)

var main
var director
# --- enemy.gd-compatible surface
var kind := 1
var transformed := true
var staggered := false
var dead := false
var max_hp := 1000.0
var hp := 1000.0
# --- boss
var boss_name := "BOSS"
var boss_title := ""
var aura_color := Color(1.0, 0.1, 0.1)
var body_radius := 0.9
var body_height := 3.0
var speed := 6.0
var keep_dist := 2.6
var windup_mult := 1.0
var dmg_mult := 1.0
var dormant := false
var home := Vector3.ZERO
var arena_center := Vector3.ZERO
var arena_radius := 0.0
var enraged := false
var is_field_boss := false
var intro_t := 0.0

var visual: Node3D
var rigs: Array = [] # [{model, skel, bone, wolf, torso}]
var overlay: StandardMaterial3D
var base_overlay := Color(0, 0, 0, 0)
var aura: MeshInstance3D
var light: OmniLight3D
var state := "chase"
var state_t := 0.0
var atk := {}
var act := {}
var cooldown := 1.8
var facing := 0.0
var flash_t := 0.0
var invuln_t := 0.0
var anim_t := 0.0
var run_b := 0.0
var raise_b := 0.0
var crouch_b := 0.0
var howl_b := 0.0
var bolts: Array = []
var hit_done := false

static var _scene_cache := {}
static var _bolt_mesh: SphereMesh
static var _bolt_mat: StandardMaterial3D


# ---------------------------------------------------------------- subclass hooks
func _build() -> void:
	pass


func _choose_attack(_dist: float) -> Dictionary:
	return {"type": "swipe", "windup": 0.6, "range": 3.0, "dmg": 15.0, "recover": 0.6, "cd": 1.2}


func _on_half() -> void:
	pass


# ---------------------------------------------------------------- setup
func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = body_radius
	cap.height = maxf(body_height, body_radius * 2.0 + 0.1)
	col.shape = cap
	col.position.y = cap.height * 0.5
	add_child(col)
	visual = Node3D.new()
	add_child(visual)
	overlay = StandardMaterial3D.new()
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.albedo_color = base_overlay
	_build()
	hp = max_hp
	aura = HFx.aura(self, aura_color, body_radius * 3.2, body_height * 1.25, 1.0)
	light = OmniLight3D.new()
	light.light_color = aura_color
	light.light_energy = 1.6
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.position = Vector3(0, body_height * 0.6, 0)
	add_child(light)
	if main != null and main.player != null:
		var to: Vector3 = main.player.global_position - global_position
		facing = atan2(to.x, to.z)
		visual.rotation.y = facing
	if intro_t > 0.0:
		visual.scale = Vector3.ONE * 0.2
		var tw := create_tween()
		tw.tween_property(visual, "scale", Vector3.ONE, 1.1).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		HFx.puff(get_parent(), global_position + Vector3(0, 1.2, 0), aura_color, 18, 0.28, 4.0)
		HFx.shockwave(get_parent(), global_position, 9.0, aura_color, 0.7)


static func _model_scene(n: String) -> PackedScene:
	if not _scene_cache.has(n):
		var path: String = MODEL_PATHS[n]
		_scene_cache[n] = (load(path) as PackedScene) if ResourceLoader.exists(path) else null
	return _scene_cache[n]


## Add one character rig to `parent`, scaled, with the boss overlay and glowing eyes.
## Falls back to a primitive silhouette if the model can't load.
func add_rig(n: String, scale_: float, parent: Node3D = null, eye := Color(1, 0.1, 0.05), torso := false) -> Dictionary:
	if parent == null:
		parent = visual
	var ps := _model_scene(n)
	var inst: Node3D = ps.instantiate() as Node3D if ps != null else null
	var sk: Skeleton3D = inst.get_node_or_null("Skeleton") as Skeleton3D if inst != null else null
	var r := {"model": null, "skel": null, "bone": {}, "wolf": n == "werewolf", "torso": torso}
	if sk == null:
		if inst != null:
			inst.free()
		var fb := Node3D.new()
		parent.add_child(fb)
		fb.scale = Vector3.ONE * scale_
		U.part(fb, U.capsule(0.35, 1.9), U.mat(Color(0.1, 0.05, 0.05), 0.7), Vector3(0, 0.95, 0))
		U.part(fb, U.sphere(0.22), U.mat(Color(0.2, 0.1, 0.1), 0.7), Vector3(0, 2.05, 0.05))
		r.model = fb
		rigs.append(r)
		return r
	inst.scale = Vector3.ONE * scale_
	parent.add_child(inst)
	r.model = inst
	r.skel = sk
	for i in sk.get_bone_count():
		r.bone[sk.get_bone_name(i)] = i
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = overlay
	if r.bone.has("head"):
		var att := BoneAttachment3D.new()
		sk.add_child(att)
		att.bone_name = "head"
		var head_rest: Vector3 = inst.get_meta("head_rest", Vector3(0, 1.5, 0))
		var er: float = inst.get_meta("eye_radius", 0.011) * 1.6
		var em := U.glow(eye, 8.0)
		for key in ["eye_l", "eye_r"]:
			var e := U.part(att, U.sphere(er), em, inst.get_meta(key, head_rest) - head_rest)
			e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rigs.append(r)
	return r


# ---------------------------------------------------------------- frame
func _physics_process(delta: float) -> void:
	if dead:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	flash_t = maxf(flash_t - delta, 0.0)
	invuln_t = maxf(invuln_t - delta, 0.0)
	_update_bolts(delta)
	var p = main.player
	var hv := Vector3.ZERO
	if intro_t > 0.0:
		intro_t -= delta
		howl_b = 1.0
	elif dormant:
		if p != null and not p.dead and (p.global_position.distance_to(global_position) < 15.0 or hp < max_hp):
			wake()
	elif p == null or p.dead:
		state = "chase"
	else:
		hv = _brain(delta, p)
	if state != "act" or not act.get("air", false):
		velocity.x = hv.x
		velocity.z = hv.z
		move_and_slide()
	_clamp_arena()
	visual.rotation.y = lerp_angle(visual.rotation.y, facing, 10.0 * delta)
	_animate(delta, Vector2(hv.x, hv.z).length())


func wake() -> void:
	if not dormant:
		return
	dormant = false
	cooldown = 1.0
	howl_b = 1.0
	if director != null:
		director.on_boss_woke(self)


func _clamp_arena() -> void:
	if arena_radius <= 0.0:
		return
	var off := global_position - arena_center
	off.y = 0.0
	var lim := arena_radius - body_radius - 0.5
	if off.length() > lim:
		var p := arena_center + off.normalized() * lim
		global_position = Vector3(p.x, global_position.y, p.z)


func _to_player(p) -> Vector3:
	var to: Vector3 = p.global_position - global_position
	to.y = 0.0
	return to


func _brain(delta: float, p) -> Vector3:
	var to := _to_player(p)
	var dist := to.length()
	match state:
		"chase":
			if dist > 0.01:
				facing = atan2(to.x, to.z)
			cooldown -= delta
			if cooldown <= 0.0:
				_start_attack(_choose_attack(dist), p)
				return Vector3.ZERO
			if dist > keep_dist + body_radius:
				return to / dist * speed
			var tangent := Vector3(-to.z, 0.0, to.x) / maxf(dist, 0.01)
			return tangent * speed * 0.25
		"windup":
			if not atk.get("lock", false) and dist > 0.01 and state_t > 0.18:
				facing = atan2(to.x, to.z)
			state_t -= delta
			if state_t <= 0.0:
				_execute(p)
		"act":
			return _act(delta, p)
		"recover":
			state_t -= delta
			if state_t <= 0.0:
				state = "chase"
				cooldown = atk.get("cd", 1.0) * (0.65 if enraged else 1.0)
		"vanish":
			state_t -= delta
			if state_t <= 0.0:
				_reappear(p)
	return Vector3.ZERO


# ---------------------------------------------------------------- attacks
func _start_attack(a: Dictionary, p) -> void:
	atk = a.duplicate(true)
	var to := _to_player(p)
	var dir := to.normalized() if to.length() > 0.01 else Vector3(sin(facing), 0, cos(facing))
	state = "windup"
	state_t = float(a.get("windup", 0.6)) * windup_mult
	match a.type:
		"swipe":
			HFx.circle_telegraph(get_parent(), global_position + dir * a.range * 0.45, a.range * 0.75, state_t, Color(1.0, 0.2, 0.05))
		"slam":
			var tgt: Vector3 = global_position if a.get("self", false) else p.global_position
			atk["target"] = tgt
			atk["lock"] = true
			facing = atan2(dir.x, dir.z)
			HFx.circle_telegraph(get_parent(), tgt, a.radius, state_t + a.get("leap", 0.0), Color(1.0, 0.1, 0.05))
		"dash":
			atk["dir"] = dir
			atk["lock"] = true
			facing = atan2(dir.x, dir.z)
			HFx.line_telegraph(get_parent(), global_position, dir, a.length, 2.6, state_t, Color(1.0, 0.05, 0.15))
		"bolts":
			HFx.puff(get_parent(), global_position + Vector3(0, body_height * 0.7, 0), aura_color, 6, 0.12, 1.2)
		"howl":
			HFx.circle_telegraph(get_parent(), global_position, 6.0, state_t, Color(1.0, 0.6, 0.1))
		"blink":
			HFx.puff(get_parent(), global_position + Vector3(0, 1.2, 0), aura_color, 14, 0.22, 2.5)
			visual.visible = false
			collision_layer = 0
			invuln_t = 1.0
			state = "vanish"
			state_t = 0.45


func _execute(p) -> void:
	var to := _to_player(p)
	var dist := to.length()
	match atk.type:
		"swipe":
			var fwd := Vector3(sin(facing), 0, cos(facing))
			var reach: float = atk.range + body_radius * 0.5
			if dist < reach and (dist < 1.0 or fwd.dot(to / dist) > atk.get("arc", 0.2)):
				_hurt(p, atk.dmg)
			else:
				_maybe_perfect(p, dist, reach + 3.0)
			p.shake = maxf(p.shake, 0.12)
			_recover()
		"slam":
			if atk.get("leap", 0.0) > 0.0:
				state = "act"
				act = {"kind": "leap", "from": global_position, "to": atk.target, "t": 0.0, "dur": atk.leap, "air": true}
			else:
				_impact(p)
				_recover()
		"dash":
			state = "act"
			act = {"kind": "dash", "left": atk.length, "dir": atk.dir, "speed": atk.get("speed", 30.0)}
			hit_done = false
		"bolts":
			_fire_bolts(p)
			_recover()
		"howl":
			HFx.shockwave(get_parent(), global_position, 10.0, aura_color, 0.6)
			p.shake = maxf(p.shake, 0.4)
			main.rumble(0.3, 0.5, 0.4)
			if director != null:
				for k in atk.get("summon", []):
					director.summon(k, global_position)
			_recover()
		_:
			_recover()


func _recover() -> void:
	var chain: Array = atk.get("chain", [])
	if not chain.is_empty() and not dead and main.player != null and not main.player.dead:
		var nxt: Dictionary = chain[0].duplicate(true)
		nxt["chain"] = chain.slice(1)
		nxt["cd"] = atk.get("cd", 1.0)
		_start_attack(nxt, main.player)
		return
	state = "recover"
	state_t = float(atk.get("recover", 0.6)) * (0.7 if enraged else 1.0)


func _act(delta: float, p) -> Vector3:
	match act.kind:
		"leap":
			act.t += delta
			var k := clampf(act.t / act.dur, 0.0, 1.0)
			var pos: Vector3 = act.from.lerp(act.to, k)
			pos.y = act.from.y + sin(k * PI) * 5.0
			global_position = pos
			crouch_b = 0.0
			if k >= 1.0:
				global_position.y = act.to.y + 0.05
				_impact(p)
				_recover()
			return Vector3.ZERO
		"dash":
			var step: float = act.speed * delta
			act.left -= step
			if not hit_done and p.global_position.distance_to(global_position) < 1.6 + body_radius * 0.5:
				hit_done = true
				_hurt(p, atk.dmg)
			if act.left <= 0.0:
				if not hit_done:
					_maybe_perfect(p, _to_player(p).length(), 4.0)
				_recover()
				return Vector3.ZERO
			return act.dir * act.speed
	return Vector3.ZERO


func _impact(p) -> void:
	var c: Vector3 = global_position
	HFx.shockwave(get_parent(), c, atk.radius * 1.15, aura_color, 0.4)
	HFx.puff(get_parent(), c + Vector3(0, 0.3, 0), Color(0.35, 0.3, 0.28), 12, 0.25, atk.radius)
	var d := Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length()
	if d < atk.radius and p.global_position.y < c.y + 2.0:
		_hurt(p, atk.dmg)
	else:
		_maybe_perfect(p, d, atk.radius + 3.0)
	p.shake = maxf(p.shake, 0.45 if d < 14.0 else 0.15)
	main.rumble(0.4, 0.7, 0.3)


func _hurt(p, dmg: float) -> void:
	p.take_damage(dmg * dmg_mult, self) # a dash in progress turns this into a perfect dodge


func _maybe_perfect(p, dist: float, window: float) -> void:
	if dist < window and p.dashed_recently():
		main.perfect_dodge()


func _reappear(p) -> void:
	var behind: Vector3 = p.global_position - p._forward() * 3.2
	behind.y = global_position.y
	global_position = behind
	_clamp_arena()
	visual.visible = true
	collision_layer = 4
	var to := _to_player(p)
	facing = atan2(to.x, to.z)
	visual.rotation.y = facing
	HFx.puff(get_parent(), global_position + Vector3(0, 1.2, 0), aura_color, 14, 0.22, 2.5)
	var then: Dictionary = atk.get("then", {"type": "swipe", "windup": 0.45, "range": 3.0, "dmg": 16.0, "recover": 0.5, "cd": 0.8})
	_start_attack(then, p)


# ---------------------------------------------------------------- blood projectiles
func _fire_bolts(p) -> void:
	if _bolt_mesh == null:
		_bolt_mesh = SphereMesh.new()
		_bolt_mesh.radius = 0.22
		_bolt_mesh.height = 0.44
		_bolt_mesh.radial_segments = 8
		_bolt_mesh.rings = 4
		_bolt_mat = HFx.flat(Color(1.0, 0.08, 0.1, 1.0))
	var n: int = atk.get("count", 5)
	var origin := global_position + Vector3(0, body_height * 0.6, 0)
	var to := _to_player(p)
	var base := atan2(to.x, to.z)
	for i in n:
		var a: float
		if atk.get("ring", false):
			a = base + TAU * i / float(n)
		else:
			var spread: float = atk.get("spread", 0.8)
			a = base + (spread * (float(i) / maxf(n - 1, 1) - 0.5) if n > 1 else 0.0)
		var dir := Vector3(sin(a), 0, cos(a))
		var mi := MeshInstance3D.new()
		mi.mesh = _bolt_mesh
		mi.material_override = _bolt_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(mi)
		mi.global_position = origin
		bolts.append({"node": mi, "vel": dir * atk.get("bolt_speed", 15.0), "t": 0.0, "dmg": atk.dmg})


func _update_bolts(delta: float) -> void:
	if bolts.is_empty():
		return
	var p = main.player
	for i in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[i]
		b.t += delta
		var node: MeshInstance3D = b.node
		node.global_position += b.vel * delta
		node.global_position.y = lerpf(node.global_position.y, 1.1, 3.0 * delta)
		var hit := false
		if p != null and not p.dead and node.global_position.distance_to(p.global_position + Vector3(0, 1.0, 0)) < 0.85:
			_hurt(p, b.dmg)
			hit = true
		if hit or b.t > 3.0:
			node.queue_free()
			bolts.remove_at(i)


func _clear_bolts() -> void:
	for b in bolts:
		if is_instance_valid(b.node):
			b.node.queue_free()
	bolts.clear()


# ---------------------------------------------------------------- damage
func take_hit(amount: float, _dir: Vector3) -> void:
	if dead or invuln_t > 0.0 or not visual.visible:
		return
	if dormant:
		wake()
	hp -= amount
	flash_t = 0.12
	if not enraged and hp <= max_hp * 0.5 and hp > 0.0:
		enraged = true
		_on_half()
	if hp <= 0.0:
		hp = 0.0
		_die(false)


## Bosses can't be bitten (they never stagger); here for API parity.
func drain() -> int:
	_die(true)
	return 1 if kind == 0 else 2


func _die(drained: bool) -> void:
	if dead:
		return
	dead = true
	collision_layer = 0
	collision_mask = 1
	_clear_bolts()
	main.release_attack_token(self)
	main.on_enemy_killed(self, drained)
	died.emit(self)
	HFx.puff(get_parent(), global_position + Vector3(0, 1.5, 0), aura_color, 22, 0.3, 4.5)
	HFx.shockwave(get_parent(), global_position, 10.0, aura_color, 0.8)
	var tw := create_tween()
	tw.tween_property(overlay, "albedo_color", Color(0.05, 0.0, 0.0, 0.95), 0.6)
	tw.parallel().tween_property(visual, "rotation:x", -1.3 if kind == 1 else 0.0, 0.9).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(aura, "scale", aura.scale * 2.0, 0.9)
	tw.tween_property(visual, "scale", Vector3(1.3, 0.02, 1.3), 1.2)
	tw.parallel().tween_property(light, "light_energy", 0.0, 1.2)
	tw.parallel().tween_property(aura, "scale", Vector3.ZERO, 1.2)
	tw.tween_callback(queue_free)


# ---------------------------------------------------------------- pose
func _animate(delta: float, spd: float) -> void:
	anim_t += delta * (3.0 + spd * 0.9)
	run_b = lerpf(run_b, clampf(spd / 5.0, 0.0, 1.0), minf(8.0 * delta, 1.0))
	var winding := state == "windup"
	var t: String = atk.get("type", "")
	raise_b = lerpf(raise_b, 1.0 if winding and t in ["swipe", "bolts", "dash"] else 0.0, minf(12.0 * delta, 1.0))
	crouch_b = lerpf(crouch_b, 1.0 if winding and t == "slam" else 0.0, minf(10.0 * delta, 1.0))
	howl_b = lerpf(howl_b, 1.0 if (winding and t == "howl") or intro_t > 0.0 else 0.0, minf(6.0 * delta, 1.0))
	if state == "act" and act.get("kind", "") == "dash":
		raise_b = 0.6
	var c := base_overlay
	if enraged:
		c = c.lerp(Color(0.9, 0.0, 0.05, 0.35), 0.5 + 0.2 * sin(anim_t * 2.0))
	if flash_t > 0.0:
		c = c.lerp(Color(1, 1, 1, 0.85), flash_t / 0.12)
	overlay.albedo_color = c
	var lean := 0.35 * crouch_b - 0.25 * howl_b + 0.12 * run_b
	visual.rotation.x = lerpf(visual.rotation.x, lean, 8.0 * delta)
	for r in rigs:
		if r.skel != null:
			_pose_rig(r)


func _rot(r: Dictionary, b: String, q: Quaternion) -> void:
	if r.bone.has(b):
		r.skel.set_bone_pose_rotation(r.bone[b], q)


func _pose_rig(r: Dictionary) -> void:
	var wolf: bool = r.wolf
	var s := sin(anim_t)
	var co := cos(anim_t)
	var rb := run_b
	var up := raise_b
	var cr := crouch_b
	var hw := howl_b
	if r.torso: # a fused upper body: writhing, arms reaching
		var w := sin(anim_t * 0.7)
		_rot(r, "upper_l", Quaternion(Vector3.RIGHT, -1.2 - 0.6 * up + w * 0.3) * Quaternion(Vector3.BACK, -0.6))
		_rot(r, "upper_r", Quaternion(Vector3.RIGHT, -1.2 - 0.6 * up - w * 0.3) * Quaternion(Vector3.BACK, 0.6))
		_rot(r, "fore_l", Quaternion(Vector3.UP, -0.9 - w * 0.2))
		_rot(r, "fore_r", Quaternion(Vector3.UP, 0.9 + w * 0.2))
		_rot(r, "head", Quaternion(Vector3.RIGHT, -0.4 - 0.4 * hw + w * 0.15))
		_rot(r, "spine", Quaternion(Vector3.BACK, w * 0.15))
		return
	var stride := 0.8 if wolf else 0.65
	_rot(r, "thigh_l", Quaternion(Vector3.RIGHT, (-s * stride - 0.12) * rb - 0.7 * cr))
	_rot(r, "thigh_r", Quaternion(Vector3.RIGHT, (s * stride - 0.12) * rb - 0.7 * cr))
	_rot(r, "shin_l", Quaternion(Vector3.RIGHT, (0.2 + 0.9 * maxf(co, 0.0)) * rb + 1.1 * cr))
	_rot(r, "shin_r", Quaternion(Vector3.RIGHT, (0.2 + 0.9 * maxf(-co, 0.0)) * rb + 1.1 * cr))
	var idle := sin(anim_t * 0.35) * (1.0 - rb)
	var down := (1.05 if wolf else 1.25) - 0.5 * up - 0.9 * hw + 0.3 * cr + idle * 0.03
	var swing := s * 0.6 * rb
	var raise := -1.6 * up - 0.4 * hw + 0.5 * cr
	_rot(r, "upper_l", Quaternion(Vector3.RIGHT, swing + raise) * Quaternion(Vector3.BACK, -down))
	_rot(r, "upper_r", Quaternion(Vector3.RIGHT, -swing + raise) * Quaternion(Vector3.BACK, down))
	var bend := (0.55 if wolf else 0.2) + 0.9 * rb + 0.6 * up
	_rot(r, "fore_l", Quaternion(Vector3.UP, -bend))
	_rot(r, "fore_r", Quaternion(Vector3.UP, bend))
	_rot(r, "spine", Quaternion(Vector3.RIGHT, 0.1 * rb - 0.15 * up + 0.3 * cr - 0.25 * hw) * Quaternion(Vector3.BACK, idle * 0.04))
	_rot(r, "chest", Quaternion(Vector3.UP, s * 0.14 * rb) * Quaternion(Vector3.RIGHT, -0.2 * hw))
	_rot(r, "head", Quaternion(Vector3.RIGHT, -0.1 * rb - (0.2 if wolf else 0.0) - 0.7 * hw) * Quaternion(Vector3.UP, idle * 0.1))
