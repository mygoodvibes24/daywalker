extends CharacterBody3D
## Silas Crowe, the Pale Daywalker: the rival in the Undercroft Depths (map/undercroft.gd).
## Not a boss (no boss bar, no intro card): an elite duellist with a name plate and a health bar,
## much harder than anything on the street.
##
## Lore (STORY_BIBLE: Seraphine stole Sol's blood from the crime scenes and the hospital in 1979):
## a hunter of the old Vigil that kept St. Jerome's crypt. Someone gave him Sol's blood; now he
## walks in the sun too, and he wants to know which of them it was meant for. His name is the last
## one on the crypt wall of names, carved over with FORSWORN.
##
## Built from Sol himself, by composition: sol_modular.scn (body, head, coat sim) driven by
## sol_modular_anim.gd and Sol's own clips. Material swaps set him apart: a pale bone-white coat,
## no glasses, red glowing eyes, a black wide-brimmed hunter's hat and his own pale longblade
## (Crowe's Penance, the item he drops).
##
## He fights with Sol's moveset, slowed into readable wind-ups:
##   combo (combo1 -> 2 -> 3), quick slash (gap closer), thrust (a long lunge, line telegraph),
##   charged slash (long red-glowing wind-up, ground telegraph, NOT parryable: dodge it),
##   parry (he guards against Sol's swings, deflects and ripostes), backstep (a blood-dash dodge).
## Every swing but the charged slash is parryable in its last PARRY_OPEN s; every attack ends in a
## recovery he can be punished in. Poise: enough damage in a short time staggers him.
## At half blood he roars, quickens and adds the thrust to his combo; once, low on blood, he
## backsteps and feeds (interrupt it).
##
## Speaks enemy.gd's public API (kind, dead, staggered, transformed, max_hp, hp, take_hit, drain)
## and the bosses' parry API (parry_open, parry_reach, on_parried), so player.gd, the Vows and the
## loot treat him like any other enemy.

signal died(r)

const SolModularAnim = preload("res://scripts/sol_modular_anim.gd")
const WeaponVisual = preload("res://scripts/items/weapon_visual.gd")
const ItemDB = preload("res://scripts/items/item_db.gd")
const HFx = preload("res://scripts/hunt/hunt_fx.gd")
const U = preload("res://scripts/util.gd")
const SOL_MODULAR := "res://assets/characters/sol/sol_modular.scn"

const NAME := "Silas Crowe"
const NAME_TITLE := "Silas Crowe, the Pale Daywalker"
const MAX_HP := 420.0
const GRAVITY := 24.0
const WALK := 3.4
const RUN := 7.2
const PARRY_OPEN := 0.42
const POISE := 70.0
const PALE := Color(0.8, 0.77, 0.7)

## Sol's clips as the rival's attacks. Wind-up = (hit - from) / speed.
const ATTACKS := {
	"light1": {"clip": "combo1", "from": 0.1, "hit": 0.55, "to": 0.88, "speed": 0.95, "dmg": 11.0, "reach": 2.8, "lunge": 1.2, "parry": true, "recover": 0.4},
	"light2": {"clip": "combo2", "from": 0.0, "hit": 0.4, "to": 0.68, "speed": 0.95, "dmg": 11.0, "reach": 2.8, "lunge": 1.0, "parry": true, "recover": 0.4},
	"light3": {"clip": "combo3", "from": 0.0, "hit": 0.37, "to": 1.05, "speed": 0.78, "dmg": 19.0, "reach": 3.2, "lunge": 1.4, "parry": true, "recover": 1.0},
	"quick": {"clip": "quick_slash", "from": 0.08, "hit": 0.45, "to": 0.95, "speed": 0.9, "dmg": 14.0, "reach": 3.0, "lunge": 3.2, "parry": true, "recover": 0.75},
	"thrust": {"clip": "thrust", "from": 0.0, "hit": 0.45, "to": 1.0, "speed": 0.6, "dmg": 21.0, "reach": 1.7, "lunge": 7.0, "parry": true, "recover": 0.95, "tele": "line"},
	"charged": {"clip": "charged", "from": 0.0, "hit": 1.2, "to": 1.85, "speed": 0.85, "dmg": 32.0, "reach": 3.7, "lunge": 1.0, "parry": false, "recover": 1.3, "tele": "circle"},
	"riposte": {"clip": "combo3", "from": 0.12, "hit": 0.37, "to": 1.05, "speed": 1.0, "dmg": 16.0, "reach": 3.0, "lunge": 1.0, "parry": true, "recover": 0.8},
}

var main
var depths
var home := Vector3.ZERO
var arena := Rect2()
var rematch := false
# enemy.gd API
var kind := 0 # Court blood in him now: silver-vs-vampire bonuses count
var transformed := false
var staggered := false
var dead := false
var max_hp := MAX_HP
var hp := MAX_HP
var body_radius := 0.45
var body_height := 1.9
var tithe_value := 220 # progression.kill_value: an elite's worth (a vampire is 8)

var state := "wait" # wait, taunt, stalk, windup, strike, follow, recover, reel, guard, backstep, roar, feed
var state_t := 0.0
var facing := PI
var atk := {}
var atk_name := ""
var chain: Array = []
var windup := 0.5
var hit_done := false
var cooldown := 0.8
var poise := 0.0
var poise_t := 0.0
var phase2 := false
var fed := false
var orbit := 1.0
var guard_cd := 0.0
var dodge_cd := 0.0
var invuln_t := 0.0
var flash_t := 0.0
var lunge_left := 0.0
var lunge_speed := 0.0
var engaged := false

var visual: Node3D
var model: Node3D
var anim: SolModularAnim
var label: Label3D
var bar: MeshInstance3D
var bar_mat: ShaderMaterial
var eye_mat: StandardMaterial3D
var overlay: StandardMaterial3D
var blade_glow: OmniLight3D
var aura: MeshInstance3D
var _player_connected := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	floor_snap_length = 0.4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.85
	col.shape = cap
	col.position.y = 0.925
	add_child(col)
	visual = Node3D.new()
	add_child(visual)
	_build_model()
	_build_plate()
	aura = HFx.aura(self, Color(0.9, 0.12, 0.1), 1.3, 2.3, 0.35)
	blade_glow = OmniLight3D.new()
	blade_glow.light_color = Color(1.0, 0.15, 0.08)
	blade_glow.light_energy = 0.0
	blade_glow.omni_range = 4.0
	blade_glow.shadow_enabled = false
	blade_glow.position = Vector3(0, 1.3, 0.5)
	visual.add_child(blade_glow)
	visual.rotation.y = facing
	hp = max_hp


# ---------------------------------------------------------------- look
func _build_model() -> void:
	var ps := load(SOL_MODULAR) as PackedScene if ResourceLoader.exists(SOL_MODULAR) else null
	if ps == null:
		U.part(visual, U.capsule(0.35, 1.85), U.mat(PALE), Vector3(0, 0.92, 0))
		return
	model = ps.instantiate() as Node3D
	visual.add_child(model)
	anim = SolModularAnim.new()
	if not anim.setup(model):
		anim = null
	var sk := model.get_node_or_null("Skeleton3D") as Skeleton3D
	overlay = StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.albedo_color = Color(1, 1, 1, 0)
	overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.material_overlay = overlay
	# the pale coat: bone-white leather (the dark leather texture can't be brightened, so a flat
	# pale albedo over the coat's own normal map)
	var coat := model.find_child("Coat", true, false) as MeshInstance3D
	if coat != null and coat.mesh != null:
		var base := coat.mesh.surface_get_material(0) as StandardMaterial3D
		var m := base.duplicate() as StandardMaterial3D if base != null else StandardMaterial3D.new()
		m.albedo_texture = null
		m.albedo_color = PALE
		m.metallic = 0.0
		m.metallic_texture = null
		m.roughness = 0.55
		m.roughness_texture = null
		coat.material_override = m
	# the clothes under it a cold charcoal, the skin ashen
	var body := model.find_child("Body", true, false) as MeshInstance3D
	if body != null and body.mesh != null and body.mesh.surface_get_material(0) is StandardMaterial3D:
		var m := (body.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = Color(0.55, 0.55, 0.6)
		body.material_override = m
	var head := model.find_child("HeadMesh", true, false) as MeshInstance3D
	if head != null and head.mesh != null and head.mesh.surface_get_material(0) is StandardMaterial3D:
		var m := (head.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = Color(0.8, 0.78, 0.82)
		m.emission_enabled = true
		m.emission = Color(0.16, 0.15, 0.17)
		m.emission_energy_multiplier = 1.0
		head.material_override = m
	# no glasses: the eyes are the point
	var glasses := model.find_child("Glasses", true, false) as Node3D
	if glasses != null:
		glasses.visible = false
	if sk != null:
		var hb := sk.find_bone("Head")
		if hb >= 0:
			var att := BoneAttachment3D.new()
			att.bone_name = "Head"
			sk.add_child(att)
			var inv := sk.get_bone_global_rest(hb).affine_inverse()
			eye_mat = U.glow(Color(1.0, 0.08, 0.04), 9.0)
			for e in [Vector3(-0.032, 1.741, 0.112), Vector3(0.032, 1.741, 0.114)]:
				var s := U.part(att, U.sphere(0.011), eye_mat, inv * e)
				s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# a black wide-brimmed hunter's hat with a red band
			var hat := Node3D.new()
			att.add_child(hat)
			hat.transform = Transform3D(inv.basis, inv * Vector3(0.0, 1.86, -0.05))
			hat.rotation_degrees.x += -6.0
			var felt := U.mat(Color(0.04, 0.035, 0.035), 0.75)
			var brim := U.cyl(0.29, 0.3, 0.018)
			(brim as CylinderMesh).radial_segments = 20
			U.part(hat, brim, felt, Vector3.ZERO)
			var crown := U.cyl(0.115, 0.13, 0.15)
			(crown as CylinderMesh).radial_segments = 14
			U.part(hat, crown, felt, Vector3(0, 0.08, 0))
			var band := U.cyl(0.132, 0.132, 0.03)
			(band as CylinderMesh).radial_segments = 14
			U.part(hat, band, U.mat(Color(0.35, 0.02, 0.02), 0.6), Vector3(0, 0.03, 0))
			for c in hat.get_children():
				(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# his own blade
	var grip := model.find_child("Blade", true, false)
	if grip != null and not grip is MeshInstance3D:
		for c in grip.get_children():
			(c as Node3D).visible = false
		grip.add_child(WeaponVisual.build(ItemDB.make("crowes_penance", 3), 0.014, true))


func _build_plate() -> void:
	label = Label3D.new()
	label.text = NAME_TITLE.to_upper()
	label.font_size = 30
	label.outline_size = 9
	label.modulate = Color(1.0, 0.82, 0.74)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.004
	label.position = Vector3(0, 2.62, 0)
	label.visible = false
	add_child(label)
	var sh := Shader.new()
	sh.code = preload("res://scripts/enemy.gd").BAR_SHADER
	bar_mat = ShaderMaterial.new()
	bar_mat.shader = sh
	bar_mat.render_priority = 2
	bar_mat.set_shader_parameter("fill_col", Color(0.85, 0.08, 0.06))
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 0.1)
	bar = MeshInstance3D.new()
	bar.name = "HealthBar"
	bar.mesh = q
	bar.material_override = bar_mat
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position = Vector3(0, 2.42, 0)
	bar.visible = false
	add_child(bar)


# ---------------------------------------------------------------- frame
func _physics_process(delta: float) -> void:
	var p = main.player if main != null else null
	if not _player_connected and p != null:
		_player_connected = true
		p.attacked.connect(_on_player_attacked)
	if dead:
		if anim != null:
			anim.update(delta, {"speed": 0.0, "on_floor": true})
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	invuln_t = maxf(invuln_t - delta, 0.0)
	flash_t = maxf(flash_t - delta, 0.0)
	guard_cd = maxf(guard_cd - delta, 0.0)
	dodge_cd = maxf(dodge_cd - delta, 0.0)
	poise_t += delta
	if poise_t > 1.6:
		poise = maxf(poise - 30.0 * delta, 0.0)
	var hv := Vector3.ZERO
	if p != null and not p.dead:
		hv = _brain(delta, p)
	elif state != "wait":
		state = "stalk" if engaged else "wait"
	velocity.x = hv.x
	velocity.z = hv.z
	move_and_slide()
	_clamp()
	visual.rotation.y = lerp_angle(visual.rotation.y, facing, 12.0 * delta)
	if anim != null:
		anim.in_combat = state != "wait"
		anim.update(delta, {"speed": Vector2(hv.x, hv.z).length(), "on_floor": is_on_floor()})
	_look(delta, p)


func _clamp() -> void:
	if arena.has_area():
		var x := clampf(global_position.x, arena.position.x, arena.end.x)
		var z := clampf(global_position.z, arena.position.y, arena.end.y)
		global_position = Vector3(x, global_position.y, z)


func _to(p) -> Vector3:
	var to: Vector3 = p.global_position - global_position
	to.y = 0.0
	return to


func _face(to: Vector3) -> void:
	if to.length() > 0.01:
		facing = atan2(to.x, to.z)


func _fwd() -> Vector3:
	return Vector3(sin(facing), 0, cos(facing))


func _brain(delta: float, p) -> Vector3:
	var to := _to(p)
	var dist := to.length()
	state_t -= delta
	match state:
		"wait":
			# he stands his post facing the stair, and turns when Sol comes down onto the water
			var sees: bool = dist < 15.0 and absf(p.global_position.y - global_position.y) < 2.5
			if sees:
				_face(to)
				_taunt()
			return Vector3.ZERO
		"taunt":
			_face(to)
			if state_t <= 0.0 or dist < 3.5:
				state = "stalk"
				cooldown = 0.6
			return Vector3.ZERO
		"stalk":
			_face(to)
			cooldown -= delta
			if cooldown <= 0.0:
				_choose(dist)
				return Vector3.ZERO
			# circle at duelling range, closing in
			var want := 3.6
			var radial := 0.0
			if dist > want + 0.6:
				radial = 1.0
			elif dist < want - 1.0:
				radial = -0.6
			var tangent := Vector3(-to.z, 0, to.x) / maxf(dist, 0.01) * orbit
			var dir := (to / maxf(dist, 0.01)) * radial + tangent * 0.7
			var spd := RUN if dist > 8.0 else WALK
			if randf() < delta * 0.25:
				orbit = -orbit
			return dir.normalized() * spd * (1.1 if phase2 else 1.0)
		"windup":
			if state_t > 0.18:
				_face(to)
			if state_t <= 0.0:
				_strike_begin()
			return Vector3.ZERO
		"strike":
			# the lunge carries him in; the blade lands once, as he arrives
			var v := Vector3.ZERO
			if lunge_left > 0.0:
				var step := lunge_speed * delta
				if dist < 1.15 and atk_name != "thrust":
					lunge_left = 0.0
				else:
					lunge_left -= step
					v = _fwd() * lunge_speed
			if not hit_done:
				var reach: float = atk.reach
				var fwd := _fwd()
				if dist < reach and (dist < 0.8 or fwd.dot(to / maxf(dist, 0.01)) > 0.25):
					hit_done = true
					_hurt(p)
					if state != "strike":
						return Vector3.ZERO # parried
				elif lunge_left <= 0.0 and state_t <= 0.0:
					hit_done = true
					if dist < reach + 3.0 and p.dashed_recently():
						main.perfect_dodge()
			if state_t <= 0.0 and lunge_left <= 0.0:
				state = "follow"
				state_t = maxf(float(atk.to) - float(atk.hit), 0.1) / float(atk.speed) * 0.6
			return v
		"follow":
			if state_t <= 0.0:
				if not chain.is_empty() and dist < 6.0:
					_start(chain.pop_front())
				else:
					chain.clear()
					state = "recover"
					state_t = float(atk.recover) * (0.85 if phase2 else 1.0)
			return Vector3.ZERO
		"recover", "reel":
			if state_t <= 0.0:
				state = "stalk"
				cooldown = randf_range(0.35, 0.9) * (0.75 if phase2 else 1.0)
			return Vector3.ZERO
		"guard":
			_face(to)
			if state_t <= 0.0:
				state = "stalk"
				cooldown = 0.3
			return Vector3.ZERO
		"backstep":
			if state_t <= 0.0:
				if not fed and phase2 and hp < max_hp * 0.33:
					_feed()
				elif dist < 7.0 and randf() < 0.6:
					_start("quick") # punish the whiff
				else:
					state = "stalk"
					cooldown = 0.4
				return Vector3.ZERO
			return -_fwd() * 10.0
		"roar":
			if state_t <= 0.0:
				state = "stalk"
				cooldown = 0.2
			return Vector3.ZERO
		"feed":
			hp = minf(hp + 40.0 * delta, max_hp)
			if state_t <= 0.0:
				state = "stalk"
				cooldown = 0.3
			return Vector3.ZERO
	return Vector3.ZERO


func _taunt() -> void:
	state = "taunt"
	state_t = 1.6
	engaged = true
	label.visible = true
	bar.visible = true
	if anim != null:
		anim.play_move({"clip": "stance", "from": 0.0, "to": 1.4, "hit": 0.0, "speed": 1.0}, 1.0)
	_say("rival_taunt_rematch" if rematch else "rival_taunt")
	main.hud.popup(NAME_TITLE.to_upper())


func _say(id: String) -> void:
	var d = get_node_or_null("/root/Dialogue")
	if d != null and d.has_line(id):
		d.play(id)


func _choose(dist: float) -> void:
	var r := randf()
	if dist > 6.5:
		_start("thrust" if r < 0.45 else "quick")
	elif dist > 3.6:
		if r < 0.35:
			_start("thrust")
		elif r < 0.7:
			_start("quick")
		else:
			cooldown = 0.25 # keep closing
	else:
		if r < 0.22:
			_start("charged")
		else:
			chain = ["light2", "light3"] if r < 0.75 else ["light2"]
			if phase2 and r < 0.6:
				chain.append("thrust")
			_start("light1")


func _start(name: String) -> void:
	atk_name = name
	atk = ATTACKS[name]
	var k := 0.86 if phase2 else 1.0
	windup = (float(atk.hit) - float(atk.from)) / float(atk.speed) * k
	state = "windup"
	state_t = windup
	hit_done = false
	if anim != null:
		var m: Dictionary = atk.duplicate()
		m["speed"] = float(atk.speed) / k
		anim.play_move(m, 1.0)
	var p = main.player
	var dir := _to(p).normalized() if p != null else _fwd()
	match atk.get("tele", ""):
		"line":
			HFx.line_telegraph(main, global_position, dir, float(atk.lunge) + 1.5, 1.6, windup, Color(1.0, 0.08, 0.1))
		"circle":
			HFx.circle_telegraph(main, global_position + dir * 2.0, 2.4, windup, Color(1.0, 0.12, 0.05))
	# the tell: a red glint along the blade and in the eyes
	var tw := create_tween()
	var peak := 2.6 if name == "charged" else 1.2
	tw.tween_property(blade_glow, "light_energy", peak, windup * 0.7)
	tw.tween_property(blade_glow, "light_energy", 0.0, 0.25)
	if name == "charged":
		_sfx("boss_blink", global_position, -2.0)


func _strike_begin() -> void:
	state = "strike"
	state_t = 0.12
	lunge_left = float(atk.lunge)
	lunge_speed = lunge_left / (0.32 if atk_name == "thrust" else 0.22)
	_sfx("boss_swipe" if atk_name in ["charged", "thrust", "light3"] else "sword_swing", global_position + _fwd(), 0.0)


func _hurt(p) -> void:
	p.take_damage(float(atk.dmg) * (1.12 if phase2 else 1.0), self) # a dash or a parry turns it aside
	if state == "strike":
		p.shake = maxf(p.shake, 0.15 if atk_name != "charged" else 0.4)
		if atk_name == "charged":
			HFx.shockwave(main, global_position + _fwd() * 2.0, 3.5, Color(1.0, 0.15, 0.08), 0.35)


func _on_player_attacked(_combo: int, _fwd_dir: Vector3) -> void:
	if dead or state != "stalk" or main.player == null:
		return
	var to := _to(main.player)
	if to.length() > 4.4:
		return
	var r := randf()
	if dodge_cd <= 0.0 and r < 0.3:
		_backstep()
	elif guard_cd <= 0.0 and r < (0.62 if phase2 else 0.5):
		_guard()


func _backstep() -> void:
	state = "backstep"
	state_t = 0.3
	invuln_t = 0.32
	dodge_cd = 2.6
	HFx.puff(main, global_position + Vector3(0, 1.0, 0), Color(0.6, 0.02, 0.04), 8, 0.14, 1.2)
	_sfx("perfect_dodge", global_position, -8.0)
	if anim != null:
		anim.play_move({"clip": "hit", "from": 0.05, "to": 0.45, "hit": 0.0, "speed": 1.6}, 1.0)


func _guard() -> void:
	state = "guard"
	state_t = 0.5
	guard_cd = 2.2
	if anim != null:
		anim.play_move({"clip": "parry", "from": 0.05, "to": 0.75, "hit": 0.3, "speed": 1.4}, 1.0)


func _feed() -> void:
	fed = true
	state = "feed"
	state_t = 1.5
	HFx.puff(main, global_position + Vector3(0, 1.4, 0), Color(0.8, 0.02, 0.04), 14, 0.12, 0.8)
	main.hud.popup("HE FEEDS  —  STOP HIM")
	if anim != null:
		anim.play_move({"clip": "stance", "from": 0.0, "to": 1.5, "hit": 0.0, "speed": 0.8}, 1.0)


# ---------------------------------------------------------------- damage and parry (player.gd)
func take_hit(amount: float, _dir: Vector3) -> void:
	if dead or invuln_t > 0.0:
		return
	var p = main.player
	if state == "guard" and p != null and _fwd().dot(_to(p).normalized()) > 0.2:
		_deflect(p)
		return
	if not engaged:
		_taunt()
	hp -= amount
	flash_t = 0.12
	poise += amount
	poise_t = 0.0
	if hp <= 0.0:
		hp = 0.0
		_die()
		return
	if not phase2 and hp <= max_hp * 0.5:
		_phase2()
		return
	if state == "feed":
		_reel(0.8)
	elif poise >= POISE:
		poise = 0.0
		_reel(1.0)
	elif state in ["stalk", "recover", "taunt"] and anim != null:
		anim.hit()


func _deflect(p) -> void:
	HFx.puff(main, global_position + Vector3(0, 1.3, 0) + _fwd() * 0.6, Color(1.0, 0.75, 0.35), 10, 0.06, 1.4)
	_sfx("sword_hit", global_position, 4.0)
	p.shake = maxf(p.shake, 0.3)
	p.attack_cd = maxf(p.attack_cd, 0.65) # his guard knocks Sol's blade wide
	p.pending = {}
	main.hud.popup("DEFLECTED")
	main.set_slowmo(0.3, 0.2)
	_start("riposte")


func _reel(t: float) -> void:
	state = "reel"
	state_t = t
	chain.clear()
	lunge_left = 0.0
	if anim != null:
		anim.stop_moves()
		anim.hit()


func _phase2() -> void:
	phase2 = true
	state = "roar"
	state_t = 1.1
	chain.clear()
	invuln_t = 0.6
	aura.scale *= 1.25
	eye_mat.emission_energy_multiplier = 16.0
	HFx.shockwave(main, global_position, 6.0, Color(1.0, 0.1, 0.08), 0.5)
	_sfx("vamp_hiss", global_position, 2.0)
	var p = main.player
	if p != null and _to(p).length() < 4.0:
		p.shake = maxf(p.shake, 0.35)
	if anim != null:
		anim.play_move({"clip": "stance", "from": 0.0, "to": 1.1, "hit": 0.0, "speed": 1.2}, 1.0)
	_say("rival_half")


func parry_open() -> bool:
	if dead or atk.is_empty() or not atk.get("parry", false):
		return false
	if state == "windup":
		return state_t <= PARRY_OPEN
	return state == "strike" and atk_name == "thrust" and not hit_done


func parry_reach() -> float:
	if state == "strike":
		return 2.6
	return float(atk.get("reach", 2.8)) + 1.4


## A parry (or the charged slash's heavy hit) breaks his attack: he reels, open to punishment.
func on_parried(_t: float = 0.0) -> void:
	if dead:
		return
	atk = {}
	hit_done = true
	_reel(1.5 if _t >= 2.0 else 0.9)
	flash_t = 0.12
	main.release_attack_token(self)


## He never staggers (no bite); here for API parity.
func drain() -> int:
	take_hit(40.0, Vector3.ZERO)
	return 1


func _die() -> void:
	if dead:
		return
	dead = true
	state = "dead"
	collision_layer = 0
	collision_mask = 1
	velocity = Vector3.ZERO
	label.visible = false
	bar.visible = false
	blade_glow.light_energy = 0.0
	if anim != null:
		anim.die()
	main.release_attack_token(self)
	main.on_enemy_killed(self, false)
	HFx.puff(main, global_position + Vector3(0, 1.2, 0), Color(0.8, 0.03, 0.05), 18, 0.2, 2.5)
	_sfx("vamp_burn", global_position, 0.0)
	var tw := create_tween()
	tw.tween_property(aura, "scale", Vector3.ZERO, 1.2)
	tw.parallel().tween_property(eye_mat, "emission_energy_multiplier", 0.0, 2.0)
	died.emit(self)
	_say("rival_death")


## Back to his post at full blood (Sol left the crypt, or fell and rose again).
func reset_to(p: Vector3) -> void:
	if dead:
		return
	global_position = p
	velocity = Vector3.ZERO
	hp = max_hp
	state = "wait"
	engaged = false
	phase2 = false
	fed = false
	chain.clear()
	atk = {}
	poise = 0.0
	facing = PI
	label.visible = false
	bar.visible = false
	if anim != null:
		anim.stop_moves()


func _look(_delta: float, p) -> void:
	var c := Color(1, 1, 1, 0)
	if flash_t > 0.0:
		c = Color(1, 0.9, 0.85, 0.6 * flash_t / 0.12)
	if overlay != null:
		overlay.albedo_color = c
	if bar.visible:
		bar_mat.set_shader_parameter("frac", clampf(hp / max_hp, 0.0, 1.0))
		var near: bool = p != null and get_viewport().get_camera_3d() != null and get_viewport().get_camera_3d().global_position.distance_squared_to(global_position + Vector3(0, 1.5, 0)) < 4.0
		label.visible = not near
		bar.visible = true


func _sfx(n: String, pos: Vector3, db := 0.0) -> void:
	var a := get_node_or_null("/root/Audio")
	if a != null:
		a.play_at(n, pos, db)
