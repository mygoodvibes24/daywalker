class_name BossBase
extends CharacterBody3D
## Shared body and brain for Hunt bosses (night bosses and field-boss landmarks).
## The bodies are the auto-rigged enemy models (*_anim.scn, tools/build_enemy_anims.gd) driven
## by real mocap clips: the street enemies' set (idle / run / sprint / attack / hit / death /
## jump) plus a boss-only library of the hero's heavier sword moves, retargeted onto the same
## skeletons (<body>_boss_clips.res: heavy, thrust, judgment, quick, stance, combo; built with
## BOSS_CLIPS=1). Each boss is set apart by scale, a fresnel aura, glowing veins (an overlay
## shader) and a silhouette piece of its own (a cape, a mane, spikes, a fused rider).
## Speaks enemy.gd's public API (kind, transformed, staggered, dead, max_hp, hp, take_hit,
## drain), so the player's blade, the Vows and loot treat it like any other enemy.
##
## Attacks are data: {type, windup, ...}. Every attack telegraphs (a wind-up clip timed so its
## strike frame lands on the hit, and a red ground marker), commits its aim, and can be dashed
## through (perfect dodge) or outrun.
##   swipe  {range, arc, dmg}            slam  {radius, dmg, leap (s), self?}
##   dash   {length, dmg, chain}          bolts {count, spread, dmg, ring?}
##   howl   {summon: [kind...]}           blink {then: attack}

const U = preload("res://scripts/util.gd")
const HFx = preload("res://scripts/hunt/hunt_fx.gd")
const ANIM_PATHS := {
	"vampire": "res://assets/characters/vampire/vampire_anim.scn",
	"werewolf": "res://assets/characters/werewolf/werewolf_anim.scn",
	"civilian": "res://assets/characters/civilian/civilian_anim.scn",
}
const BOSS_CLIPS := {
	"vampire": "res://assets/characters/vampire/vampire_boss_clips.res",
	"werewolf": "res://assets/characters/werewolf/werewolf_boss_clips.res",
}
## The older hand-rigged bodies, only if an *_anim.scn is missing (posed by nothing: a statue).
const MODEL_PATHS := {
	"vampire": "res://assets/characters/vampire/vampire_rig.scn",
	"werewolf": "res://assets/characters/werewolf/werewolf_rig.scn",
	"civilian": "res://assets/characters/civilian/civilian_rig.scn",
}
const GRAVITY := 24.0
## Wind-up clip per attack type: [clip, follow-through seconds after the strike].
const WINDUP_CLIP := {
	"swipe": ["attack", 0.45], "slam": ["boss/heavy", 0.6], "dash": ["boss/thrust", 0.5],
	"bolts": ["boss/judgment", 0.55], "howl": ["boss/stance", 0.4],
}

## Overlay on every boss body: the flash / enrage / death tint, plus glowing veins that crawl
## over the skin (unshaded, so they read as light at night), pulsing.
const OVERLAY_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.0);
uniform vec4 vein_color : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float vein_amount = 0.0;
uniform float vein_scale = 6.0;
uniform float vein_width = 0.05;
varying vec3 lp;
float h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 p = lp * vein_scale;
	float n = (vnoise(p) + 0.5 * vnoise(p * 2.13 + 7.31)) / 1.5;
	float ridge = abs(n - 0.5);
	float v = (1.0 - smoothstep(vein_width * 0.35, vein_width, ridge)) * vein_amount;
	v *= 0.65 + 0.35 * sin(TIME * 3.0 + lp.y * 5.0);
	float a = clamp(tint.a + v, 0.0, 1.0);
	ALBEDO = mix(tint.rgb, vein_color.rgb * 1.5, clamp(v / max(a, 0.001), 0.0, 1.0));
	ALPHA = a;
}
"""

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
var boss_id := ""
var aura_color := Color(1.0, 0.1, 0.1)
var vein_color := Color(1.0, 0.1, 0.1)
var vein_amount := 0.8
var vein_scale := 6.0
var vein_width := 0.05
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
var rigs: Array = [] # [{model, skel, bone, wolf, torso, anim, strikes}]
var overlay: ShaderMaterial
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
var howl_b := 0.0
var crouch_b := 0.0
var anim_lock_t := 0.0 # a one-shot clip is playing; locomotion waits
var loco := "" # the locomotion clip playing
var bolts: Array = []
var hit_done := false
var silhouette: Array = [] # [{node, kind}] silhouette pieces that sway with the body

static var _scene_cache := {}
static var _lib_cache := {}
static var _overlay_shader: Shader
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
	visual = Node3D.new()
	add_child(visual)
	if _overlay_shader == null:
		_overlay_shader = Shader.new()
		_overlay_shader.code = OVERLAY_SHADER
	overlay = ShaderMaterial.new()
	overlay.shader = _overlay_shader
	_build()
	overlay.set_shader_parameter("vein_color", vein_color)
	overlay.set_shader_parameter("vein_amount", vein_amount)
	overlay.set_shader_parameter("vein_scale", vein_scale)
	overlay.set_shader_parameter("vein_width", vein_width)
	_set_tint(base_overlay)
	cap.radius = body_radius
	cap.height = maxf(body_height, body_radius * 2.0 + 0.1)
	col.shape = cap
	col.position.y = cap.height * 0.5
	add_child(col)
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
		HFx.puff(main, global_position + Vector3(0, 1.2, 0), aura_color, 18, 0.28, 4.0)
		HFx.shockwave(main, global_position, 9.0, aura_color, 0.7)
		_play_all("boss/stance", 0.0, 0.7)
		anim_lock_t = intro_t
		_sfx("boss_slam", global_position, -4.0) # AUDIO HOOK: the entrance lands
	else:
		_play_all("idle", 0.0)


static func _model_scene(n: String) -> PackedScene:
	if not _scene_cache.has(n):
		var ps: PackedScene = null
		for path in [ANIM_PATHS.get(n, ""), MODEL_PATHS.get(n, "")]:
			if path != "" and ResourceLoader.exists(path):
				ps = load(path) as PackedScene
				if ps != null:
					break
		_scene_cache[n] = ps
	return _scene_cache[n]


static func _boss_lib(n: String) -> AnimationLibrary:
	if not _lib_cache.has(n):
		var path: String = BOSS_CLIPS.get(n, "")
		_lib_cache[n] = load(path) as AnimationLibrary if path != "" and ResourceLoader.exists(path) else null
	return _lib_cache[n]


## Add one character body to `parent`, scaled, with the boss overlay, glowing eyes and its
## clips. Falls back to a primitive silhouette if the model can't load.
func add_rig(n: String, scale_: float, parent: Node3D = null, eye := Color(1, 0.1, 0.05), torso := false) -> Dictionary:
	if parent == null:
		parent = visual
	var ps := _model_scene(n)
	var inst: Node3D = ps.instantiate() as Node3D if ps != null else null
	var sk: Skeleton3D = inst.get_node_or_null("Skeleton") as Skeleton3D if inst != null else null
	var r := {"model": null, "skel": null, "bone": {}, "wolf": n == "werewolf", "torso": torso, "anim": null, "strikes": {}, "name": n}
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
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null:
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		ap.playback_default_blend_time = 0.15
		var lib := _boss_lib(n)
		if lib != null and not ap.has_animation_library("boss"):
			ap.add_animation_library("boss", lib)
			var st: Dictionary = lib.get_meta("strike_times", {})
			for k in st:
				r.strikes["boss/" + k] = st[k]
		r.strikes["attack"] = inst.get_meta("strike_time", 0.9)
		r.anim = ap
	var head_bone: String = inst.get_meta("head_bone", "head")
	if r.bone.has(head_bone):
		var att := BoneAttachment3D.new()
		sk.add_child(att)
		att.bone_name = head_bone
		var head_rest: Vector3 = inst.get_meta("head_rest", Vector3(0, 1.5, 0))
		var er: float = inst.get_meta("eye_radius", 0.011) * 1.6
		var em := U.glow(eye, 8.0)
		for key in ["eye_l", "eye_r"]:
			var off: Vector3 = inst.get_meta(key + "_local") if inst.has_meta(key + "_local") else inst.get_meta(key, head_rest) - head_rest
			var e := U.part(att, U.sphere(er), em, off)
			e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rigs.append(r)
	return r


## A node riding one of a rig's bones, its axes turned to the MODEL's (x right, y up, z forward),
## so silhouette pieces can be placed in plain model-space metres. Null if the bone is missing.
func bone_mount(r: Dictionary, bone_name: String) -> Node3D:
	if r.skel == null or not r.bone.has(bone_name):
		return null
	var sk: Skeleton3D = r.skel
	var att := BoneAttachment3D.new()
	att.bone_name = bone_name
	sk.add_child(att)
	var holder := Node3D.new()
	att.add_child(holder)
	holder.basis = sk.get_bone_global_rest(r.bone[bone_name]).basis.orthonormalized().inverse()
	return holder


## Glowing horn-like spikes on a bone mount, fanned along `dir` (model space).
func add_spikes(mount: Node3D, count: int, length: float, dir: Vector3, spread: float, mat: Material, radius := 0.05) -> void:
	if mount == null:
		return
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = length
	cone.radial_segments = 6
	cone.rings = 1
	for i in count:
		var k := (float(i) / maxf(count - 1, 1)) - 0.5 if count > 1 else 0.0
		var d := dir.normalized().rotated(Vector3.UP, k * spread).rotated(Vector3.RIGHT, 0.25 * sin(i * 2.3))
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mount.add_child(mi)
		mi.position = Vector3(k * spread * 0.18, 0, 0) + d * length * 0.5
		mi.basis = Basis(Quaternion(Vector3.UP, d))


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


func _process(delta: float) -> void:
	for r in rigs:
		var ap: AnimationPlayer = r.anim
		if ap != null and is_instance_valid(ap):
			ap.advance(delta)
			if r.torso: # a fused rider: no legs below the wolf's back
				for b in ["LeftUpLeg", "RightUpLeg"]:
					if r.bone.has(b):
						r.skel.set_bone_pose_scale(r.bone[b], Vector3.ONE * 0.01)


func wake() -> void:
	if not dormant:
		return
	dormant = false
	cooldown = 1.0
	howl_b = 1.0
	_play_all("boss/stance", 0.1, 1.0)
	anim_lock_t = 0.8
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
			HFx.circle_telegraph(main, global_position + dir * a.range * 0.45, a.range * 0.75, state_t, Color(1.0, 0.2, 0.05))
		"slam":
			var tgt: Vector3 = global_position if a.get("self", false) else p.global_position
			atk["target"] = tgt
			atk["lock"] = true
			facing = atan2(dir.x, dir.z)
			HFx.circle_telegraph(main, tgt, a.radius, state_t + a.get("leap", 0.0), Color(1.0, 0.1, 0.05))
		"dash":
			atk["dir"] = dir
			atk["lock"] = true
			facing = atan2(dir.x, dir.z)
			HFx.line_telegraph(main, global_position, dir, a.length, 2.6, state_t, Color(1.0, 0.05, 0.15))
		"bolts":
			HFx.puff(main, global_position + Vector3(0, body_height * 0.7, 0), aura_color, 6, 0.12, 1.2)
		"howl":
			HFx.circle_telegraph(main, global_position, 6.0, state_t, Color(1.0, 0.6, 0.1))
		"blink":
			HFx.puff(main, global_position + Vector3(0, 1.2, 0), aura_color, 14, 0.22, 2.5)
			_sfx("boss_blink", global_position) # AUDIO HOOK
			visual.visible = false
			collision_layer = 0
			invuln_t = 1.0
			state = "vanish"
			state_t = 0.45
			return
	_anim_windup(a.type, state_t + (float(a.get("leap", 0.0)) if a.type == "slam" else 0.0))


func _execute(p) -> void:
	var to := _to_player(p)
	var dist := to.length()
	match atk.type:
		"swipe":
			var fwd := Vector3(sin(facing), 0, cos(facing))
			var reach: float = atk.range + body_radius * 0.5
			_sfx("boss_swipe", global_position + fwd * 1.5, 0.0) # AUDIO HOOK
			if dist < reach and (dist < 1.0 or fwd.dot(to / dist) > atk.get("arc", 0.2)):
				_hurt(p, atk.dmg)
				if atk.get("type", "") == "parried":
					return # turned aside: on_parried() set the reel, no chain follows
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
			_sfx("boss_swipe", global_position, 2.0) # AUDIO HOOK
		"bolts":
			_fire_bolts(p)
			_sfx("blood_bolt", global_position + Vector3(0, body_height * 0.6, 0), 1.0) # AUDIO HOOK
			_recover()
		"howl":
			HFx.shockwave(main, global_position, 10.0, aura_color, 0.6)
			_sfx("wolf_howl" if kind == 1 else "vamp_hiss", global_position, 3.0) # AUDIO HOOK
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
				if state != "act":
					return Vector3.ZERO # parried: on_parried() already broke the dash
			if act.left <= 0.0:
				if not hit_done:
					_maybe_perfect(p, _to_player(p).length(), 4.0)
				_recover()
				return Vector3.ZERO
			return act.dir * act.speed
	return Vector3.ZERO


func _impact(p) -> void:
	var c: Vector3 = global_position
	HFx.shockwave(main, c, atk.radius * 1.15, aura_color, 0.4)
	HFx.puff(main, c + Vector3(0, 0.3, 0), Color(0.35, 0.3, 0.28), 12, 0.25, atk.radius)
	_sfx("boss_slam", c, 2.0) # AUDIO HOOK
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


# ---------------------------------------------------------------- parry (player.gd asks these)
## Bosses never stagger, but a melee strike can be turned aside: the last PARRY_OPEN seconds of a
## swipe or dash wind-up, and the dash itself. Slams, bolts and howls can't be parried (dodge them).
const PARRY_OPEN := 0.4
const PARRY_PUNISH := 1.3 # seconds the boss reels after a parry (shorter when enraged)


func parry_open() -> bool:
	if dead or dormant or visual == null or not visual.visible:
		return false
	var t: String = atk.get("type", "")
	if state == "windup":
		return (t == "swipe" or t == "dash") and state_t <= PARRY_OPEN
	return state == "act" and act.get("kind", "") == "dash"


## Flat distance from the player at which a parry catches this boss's open attack.
func parry_reach() -> float:
	if state == "act":
		return 2.4 + body_radius
	return float(atk.get("range", 3.0)) + body_radius * 0.5 + 1.4


## The parry landed: the attack is broken (no chain follows) and the boss reels, open to punishment.
func on_parried(_t: float = 0.0) -> void:
	if dead:
		return
	atk = {"type": "parried", "recover": PARRY_PUNISH * (0.7 if enraged else 1.0), "cd": 0.9}
	act = {}
	hit_done = true
	state = "recover"
	state_t = float(atk.recover)
	velocity = Vector3.ZERO
	flash_t = 0.12
	if not _play_all("hit", 0.08, 0.9, 0.0):
		_play_all("boss/stance", 0.1, 1.2)
	anim_lock_t = state_t
	main.release_attack_token(self)


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
	HFx.puff(main, global_position + Vector3(0, 1.2, 0), aura_color, 14, 0.22, 2.5)
	_sfx("boss_blink", global_position, 2.0) # AUDIO HOOK
	var then: Dictionary = atk.get("then", {"type": "swipe", "windup": 0.45, "range": 3.0, "dmg": 16.0, "recover": 0.5, "cd": 0.8})
	_start_attack(then, p)


func _sfx(name: String, pos: Vector3, db := 0.0) -> void:
	var a := get_node_or_null("/root/Audio")
	if a != null:
		a.play_at(name, pos, db)


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
		main.add_child(mi)
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
		vein_amount = minf(vein_amount * 1.6 + 0.3, 2.0)
		overlay.set_shader_parameter("vein_amount", vein_amount)
		_play_all("boss/stance", 0.1, 1.2)
		anim_lock_t = maxf(anim_lock_t, 0.9)
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
	HFx.puff(main, global_position + Vector3(0, 1.5, 0), aura_color, 22, 0.3, 4.5)
	HFx.shockwave(main, global_position, 10.0, aura_color, 0.8)
	_sfx("boss_slam", global_position, 0.0) # AUDIO HOOK
	_sfx("vamp_burn" if kind == 0 else "wolf_howl", global_position, 2.0)
	var clipped := _play_all("death", 0.1, 0.9)
	var tw := create_tween()
	tw.tween_method(_set_tint, base_overlay, Color(0.05, 0.0, 0.0, 0.9), 1.2)
	if clipped:
		tw.parallel().tween_property(aura, "scale", aura.scale * 2.0, 0.9)
		tw.tween_interval(0.6)
	else:
		tw.parallel().tween_property(visual, "rotation:x", -1.3 if kind == 1 else 0.0, 0.9).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(aura, "scale", aura.scale * 2.0, 0.9)
	tw.tween_property(visual, "scale", Vector3(1.2, 0.02, 1.2), 1.0).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(light, "light_energy", 0.0, 1.0)
	tw.parallel().tween_property(aura, "scale", Vector3.ZERO, 1.0)
	tw.tween_callback(queue_free)


# ---------------------------------------------------------------- look and clips
func _set_tint(c: Color) -> void:
	overlay.set_shader_parameter("tint", c)


## Play a clip on every body (a fused rider mirrors the wolf). False if none has clips.
func _play_all(clip: String, blend := -1.0, spd := 1.0, from := -1.0) -> bool:
	var any := false
	for r in rigs:
		var ap: AnimationPlayer = r.anim
		if ap == null or not ap.has_animation(clip):
			continue
		ap.play(clip, blend)
		ap.speed_scale = spd
		if from >= 0.0:
			ap.seek(from, true)
		any = true
	if any:
		loco = ""
	return any


## Start an attack's wind-up clip so its strike frame lands as the attack resolves.
func _anim_windup(type: String, total: float) -> void:
	var w: Array = WINDUP_CLIP.get(type, [])
	if w.is_empty():
		return
	var clip: String = w[0]
	if type == "swipe" and enraged:
		clip = "boss/quick"
	if type == "howl" and kind == 1:
		clip = "hit" # wolves throw their head back and writhe
	for r in rigs:
		var ap: AnimationPlayer = r.anim
		if ap == null:
			continue
		var c := clip if ap.has_animation(clip) else "attack"
		if not ap.has_animation(c):
			continue
		var strike: float = r.strikes.get(c, 0.6) if c != "hit" else 0.5
		var lead := minf(strike, 1.1) # skip a long idle lead-in
		ap.play(c, 0.08)
		ap.speed_scale = clampf(lead / maxf(total, 0.05), 0.25, 3.0)
		ap.seek(maxf(strike - lead, 0.0), true)
	loco = ""
	anim_lock_t = total + float(w[1])


## Per frame: one-shots run out, then locomotion by speed; procedural lean and tint on top.
func _animate(delta: float, spd: float) -> void:
	anim_t += delta * (3.0 + spd * 0.9)
	run_b = lerpf(run_b, clampf(spd / 5.0, 0.0, 1.0), minf(8.0 * delta, 1.0))
	var winding := state == "windup"
	var t: String = atk.get("type", "")
	crouch_b = lerpf(crouch_b, 1.0 if winding and t == "slam" else 0.0, minf(10.0 * delta, 1.0))
	howl_b = lerpf(howl_b, 1.0 if (winding and t == "howl") or intro_t > 0.0 else 0.0, minf(6.0 * delta, 1.0))
	var c := base_overlay
	if enraged:
		c = c.lerp(Color(0.9, 0.0, 0.05, 0.35), 0.5 + 0.2 * sin(anim_t * 2.0))
	if flash_t > 0.0:
		c = c.lerp(Color(1, 1, 1, 0.85), flash_t / 0.12)
	_set_tint(c)
	var lean := 0.12 * crouch_b - 0.22 * howl_b
	visual.rotation.x = lerpf(visual.rotation.x, lean, 8.0 * delta)
	anim_lock_t = maxf(anim_lock_t - delta, 0.0)
	var in_air: bool = state == "act" and act.get("kind", "") == "leap"
	var dashing: bool = state == "act" and act.get("kind", "") == "dash"
	if in_air and loco != "jump" and anim_lock_t <= 0.0:
		_play_all("jump", 0.1, 1.4, 0.2)
		loco = "jump"
	elif dashing and loco != "sprint" and anim_lock_t <= 0.0:
		_play_all("sprint", 0.05, 1.6)
		loco = "sprint"
	elif anim_lock_t <= 0.0 and not in_air and not dashing and state != "windup":
		var want := "idle"
		if spd > 0.6:
			want = "sprint" if spd > 7.5 else "run"
		if want != loco:
			_play_all(want, 0.2)
			loco = want
		var s := 1.0
		if want == "run":
			s = clampf(spd / (4.2 * visual.scale.x * _body_scale()), 0.6, 1.6)
		elif want == "sprint":
			s = clampf(spd / (8.0 * _body_scale()), 0.8, 1.5)
		for r in rigs:
			if r.anim != null and r.anim.current_animation == want:
				r.anim.speed_scale = s
	_sway(delta)


func _body_scale() -> float:
	for r in rigs:
		if r.model != null and not r.torso:
			return maxf(r.model.scale.x, 0.5)
	return 1.0


## Capes and manes lag behind the body: they flare back with speed and lift on a leap.
func _sway(delta: float) -> void:
	for s in silhouette:
		var n: Node3D = s.node
		if not is_instance_valid(n):
			continue
		var target := 0.12 + 0.75 * run_b + 0.25 * sin(anim_t * 1.7) * 0.2
		if state == "act":
			target = 1.1
		if s.get("kind", "") == "cape":
			n.rotation.x = lerpf(n.rotation.x, target, minf(5.0 * delta, 1.0))
			n.rotation.z = 0.05 * sin(anim_t * 0.9)
