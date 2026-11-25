extends Node
## The Arsenal (round 4): what Sol's weapon types add on top of player.gd's sword moves. A child of the
## player (player.gd makes it in _ready); player.gd calls three hooks, everything else hangs off its
## signals:
##
##   attack_pressed()     before player.gd's own attack routing: the riposte, the jump cut / plunge
##   heavy_move()         which held heavy comes out (tap, tap, HOLD gives the chain's finisher)
##   affinity_mult(e)     silver / holy / fire damage against this enemy (in player._vs_mult)
##   on_weapon_changed()  the left-hand twin, the whip chain, the trail's reach
##
## and owns:
##   - the Weapon Art (input "weapon_art": V / mouse thumb button / RB / the ART touch button), its
##     cooldown and blood cost, and the art effects (projectile, nova, ruptures, pull, dash-through)
##   - the special combo routes: L-L-H finisher, the heavy after a dodge (hold through the dash thrust),
##     the sprint heavy (hold through the running slash), the jump cut and the plunge, the riposte after
##     a parry and the blood-chain (Weapon Art right after the third hit: spends blood for a finisher)
##   - multi-hit timing for moves with "hits" (arsenal_moves.gd), shockwaves ("aoe")
##   - Bleed build-up and the Hemorrhage burst, stagger (poise) build-up and breaks, fire burns
##   - the slash trail (one ImmediateMesh ribbon per hand) and pooled blood sprays
##   - a small art HUD (cooldown ring, the route's name)
##
## Cheap by construction for the single-threaded web build: one trail mesh per hand rebuilt only while a
## move plays, a fixed pool of CPU particle emitters, and the VFX amount honours Settings.vfx_amount
## (the Performance agent's setting, if present) and the Low quality tier.

const SolMoves = preload("res://scripts/sol_moves.gd")
const ArsenalMoves = preload("res://scripts/items/arsenal_moves.gd")
const ArsenalData = preload("res://scripts/items/arsenal_data.gd")
const WeaponVisual = preload("res://scripts/items/weapon_visual.gd")
const HFx = preload("res://scripts/hunt/hunt_fx.gd")

const ART_BUFFER := 0.25 # an art pressed this long before Sol can act still comes out
const ROUTE_HOLD := 0.3 # hold attack this long through the dash thrust / running slash for the heavy
const PLUNGE_HOLD := 0.18 # hold attack this long in the air for the plunge
const RIPOSTE_WINDOW := 1.4 # seconds after a parry the riposte is on
const CHAIN_WINDOW := 0.9 # seconds after the third hit the blood-chain is on
const BLEED_MAX := 100.0
const BLEED_MAX_BOSS := 260.0
const POISE_DECAY := 30.0 # stagger points lost per second, 1.5 s after the last hit
const SPRAY_POOL := 8
const TRAIL_LEN := 12 # samples per ribbon

var player # player.gd
var main
var weapon := {} # the equipped blade instance
var wtype := {} # its arsenal_data.gd type row
var tname := "longsword"
var tip_len := 1.0

var art_cd_t := 0.0 # seconds until the Weapon Art is ready
var art_cd_max := 1.0
var art_buffer_t := 0.0
var riposte_t := 0.0
var riposte_target = null
var chain_t := 0.0 # the blood-chain window after the third hit
var route := "" # the special move last performed ("" none)
var route_count := {} # move name -> times performed (the smoke test reads it)
var art_count := 0
var _events: Array = [] # [{t, kind, ...}] timed strikes of the move in play
var _press_t := -1.0 # seconds attack has been held since a press that may become a route heavy
var _press_move := "" # the move that press started (dash / sprint / jump_cut)
var _plunging := false
var _plunge_move := ""
var _plunge_air := 0.0
var _phase_t := 0.0
var _recent := {} # enemy -> msec of its last hit (shockwaves skip what the blade just hit)
var _in_proc := false
var _hang_t := 0.0

# VFX
var _sprays: Array[CPUParticles3D] = []
var _spray_next := 0
var _trails: Array = [] # [{mi, imesh, pts: [[base, tip, age]], socket, left}]
var _waves: Array = [] # [{node, dir, life, hit, dmg}]
var _wave_pool: Array[MeshInstance3D] = []
var _left_visual: Node3D
var _chain: Node3D # the whip's chain (whip_chain.gd), if the whip is equipped
var hud: CanvasLayer
var _hud_ctl: Control
var _title := ""
var _title_t := 0.0

static var _crescent: ArrayMesh
static var _mats := {}


func _ready() -> void:
	main = player.main
	_setup_input()
	if player.has_signal("parried"):
		player.parried.connect(_on_parried)
	player.hit_enemy.connect(_on_hit)
	player.attacked.connect(_on_attacked)
	_build_hud()
	process_physics_priority = 1 # after the player's own physics tick


# ---------------------------------------------------------------- input
## "weapon_art": V, the mouse's thumb button, RB on a pad (the Blood Dash keeps B), the ART touch button.
static func _setup_input() -> void:
	if InputMap.has_action("weapon_art"):
		return
	InputMap.add_action("weapon_art", 0.25)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_V
	InputMap.action_add_event("weapon_art", k)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	InputMap.action_add_event("weapon_art", mb)
	var pb := InputEventJoypadButton.new()
	pb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	pb.device = -1
	InputMap.action_add_event("weapon_art", pb)
	if InputMap.has_action("dash"):
		for ev in InputMap.action_get_events("dash"):
			if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				InputMap.action_erase_event("dash", ev) # RB is the Weapon Art now; the dash is B


# ---------------------------------------------------------------- weapon
func on_weapon_changed(item: Dictionary) -> void:
	weapon = item
	tname = WeaponVisual.type_for(item)
	wtype = ArsenalData.get_type(tname)
	tip_len = WeaponVisual.tip_length(item)
	art_cd_t = minf(art_cd_t, 1.0) # a new blade's art is (nearly) ready
	if _left_visual != null and is_instance_valid(_left_visual):
		_left_visual.queue_free()
	_left_visual = null
	var lsock := _socket(true)
	if lsock != null:
		_left_visual = WeaponVisual.build_left(item)
		if _left_visual != null:
			lsock.add_child(_left_visual)
	_chain = null
	if player.weapon_visual != null and is_instance_valid(player.weapon_visual):
		_chain = player.weapon_visual.get_node_or_null("Chain") as Node3D
	_build_trails()


func _socket(left: bool) -> Node3D:
	if player.visual == null:
		return null
	var s = player.visual.find_child("BladeL" if left else "Blade", true, false)
	return s as Node3D if s is Node3D and not s is MeshInstance3D else null


func art() -> Dictionary:
	return ArsenalMoves.ARTS.get(String(wtype.get("art", "silver_nova")), ArsenalMoves.ARTS.silver_nova)


func _stat(k: String) -> float:
	return player.stat(k)


# ---------------------------------------------------------------- hooks from player.gd
## Called first thing on an attack press. True: the Arsenal took it (riposte, jump cut, plunge).
func attack_pressed() -> bool:
	if player.dead:
		return false
	_press_t = 0.0
	_press_move = ""
	# the riposte: attack right after a parry, on the parried enemy
	if riposte_t > 0.0 and riposte_target != null and is_instance_valid(riposte_target) and not riposte_target.dead:
		var to: Vector3 = riposte_target.global_position - player.global_position
		to.y = 0.0
		if to.length() < 4.5:
			riposte_t = 0.0
			perform(_route("riposte"), riposte_target)
			return true
	# in the air: the jump cut (held on, it becomes the plunge)
	if not player.is_on_floor() and player.dash_t <= 0.0 and not _plunging:
		perform(_route("jump"))
		_press_move = "jump"
		return true
	# out of a dash / in a sprint player.gd plays the thrust / running slash; hold on for the heavy
	if player.dash_t > 0.0 or player.dashed_recently(player.DASH_TIME + player.DASH_ATTACK_WINDOW):
		_press_move = "dash"
	elif player.sprinting:
		_press_move = "sprint"
	return false


## The held heavy (player._combat_tick's hold): the third press of a chain held is the L-L-H finisher.
func heavy_move() -> String:
	if player.combo >= 3 and player.combo_t > 0.0:
		return "@" + _route("llh") # "@": performed here, not by player._special
	return String(wtype.get("heavy", "charged"))


## Silver against the Pack, holy and fire against the Court.
func affinity_mult(e) -> float:
	var aff := String(wtype.get("affinity", ""))
	var kind = e.get("kind")
	var wolf: bool = kind == 1 and (e.get("transformed") == true or e.has_method("parry_open"))
	var k := 1.0 + _stat("affinity") # the Hallowed Edge Rite doubles it
	match aff:
		"silver":
			return 1.0 + 0.35 * k if wolf else 1.0
		"holy":
			return 1.0 + 0.35 * k if kind == 0 else 1.0
		"fire":
			return 1.0 + 0.2 * k if kind == 0 else 1.0
	return 1.0


func _route(k: String) -> String:
	return String(wtype.get("routes", {}).get(k, ""))


# ---------------------------------------------------------------- per frame
func _physics_process(delta: float) -> void:
	if player == null or main == null:
		return
	if player.dead:
		_events.clear()
		return
	art_cd_t = maxf(art_cd_t - delta, 0.0)
	riposte_t = maxf(riposte_t - delta, 0.0)
	chain_t = maxf(chain_t - delta, 0.0)
	_title_t = maxf(_title_t - delta, 0.0)
	if _phase_t > 0.0:
		_phase_t -= delta
		player.collision_mask = 1 # passes through enemies, like the dash
		if _phase_t <= 0.0 and player.dash_t <= 0.0:
			player.collision_mask = 1 | 4
	if _hang_t > 0.0:
		_hang_t -= delta
		player.velocity.y = maxf(player.velocity.y, -1.0) # the jump cut hangs a breath in the air
	# Weapon Art / blood-chain
	if Input.is_action_just_pressed("weapon_art"):
		art_buffer_t = ART_BUFFER
	if art_buffer_t > 0.0:
		art_buffer_t -= delta
		if _can_act():
			art_buffer_t = 0.0
			art_pressed()
	_route_holds(delta)
	_plunge_tick()
	_tick_events(delta)
	_tick_waves(delta)
	_tick_status(delta)


func _chain_name() -> String:
	return String(wtype.get("chain", "light"))


func _can_act() -> bool:
	return player.bite_t <= 0.0 and player.finisher_t <= 0.0 and player.attack_cd <= 0.12 and not _plunging


## The heavy after a dodge / in a sprint: hold attack through the thrust / running slash; and the
## plunge: hold attack through the jump cut.
func _route_holds(delta: float) -> void:
	if _press_t < 0.0:
		return
	if not Input.is_action_pressed("attack"):
		_press_t = -1.0
		return
	_press_t += delta
	match _press_move:
		"dash", "sprint":
			if _press_t >= ROUTE_HOLD and player.move_name in ["dash", "sprint"]:
				_press_t = -1.0
				perform(_route("dodge" if _press_move == "dash" else "sprint"))
		"jump":
			if _press_t >= PLUNGE_HOLD and not player.is_on_floor():
				_press_t = -1.0
				_start_plunge()


## The Weapon Art button: the blood-chain right after the third hit, else the weapon's art.
func art_pressed() -> bool:
	if player.dead or not _can_act():
		return false
	var chain_cost := 0.0 if _stat("chain_free") > 0.0 else ArsenalMoves.BLOOD_CHAIN_COST # the Chain of Blood Rite
	if chain_t > 0.0 and player.hp > chain_cost + 1.0:
		chain_t = 0.0
		player.hp -= chain_cost
		perform(_route("chain"))
		return true
	var a := art()
	if art_cd_t > 0.0:
		return false
	if float(a.blood) > 0.0 and player.hp <= float(a.blood) + 1.0:
		_show_title("NOT ENOUGH BLOOD")
		return false
	player.hp -= float(a.blood)
	art_cd_max = float(a.cd) * maxf(1.0 - _stat("art_cd"), 0.4)
	art_cd_t = art_cd_max
	art_count += 1
	perform(String(a.move), null, String(a.fx))
	_show_title(String(a.name).to_upper())
	return true


func _on_parried(e) -> void:
	riposte_t = RIPOSTE_WINDOW
	riposte_target = e


func _on_attacked(combo: int, _fwd: Vector3) -> void:
	# extra hits and shockwaves of player.gd's own moves (the chains' multi-hit steps, the heavies)
	var name: String = player.move_name
	if combo >= 3 and SolMoves.chain(_chain_name()).has(name):
		chain_t = CHAIN_WINDOW # the third hit of the chain: the blood-chain is on
	if _performing or not ArsenalMoves.MOVES.has(name):
		return
	var m := SolMoves.move(name)
	_schedule(m, _rate(), "", null, true)


# ---------------------------------------------------------------- performing a move
var _performing := false


## The playback rate for the Arsenal's moves: the blade's speed, kept within reason.
func _rate() -> float:
	var w: Dictionary = player.weapon_stats()
	return clampf(float(w.spd), 0.8, 1.3)


## Play move `name` (arsenal_moves.gd / sol_moves.gd row) as a special: clip, lunge, i-frames, leap,
## and its timed strikes. `fx` names an art effect (ARTS fx).
func perform(name: String, target = null, fx := "") -> void:
	if name == "" or not SolMoves.has_move(name):
		return
	var m := SolMoves.move(name)
	var p = player
	# the light strike still in flight lands now (the held press of an L-L-H is dropped, like the charge)
	if p.pending.has("combo") and p.hold_t >= 0.0 and Input.is_action_pressed("attack"):
		p.pending = {}
	p._flush_pending()
	_events.clear()
	p.move_name = name
	p.combo = 0
	p.combo_t = 0.0
	p.hold_t = -1.0
	p.attack_buffer_t = 0.0
	if target == null:
		target = p._nearest_enemy(6.0, -1)
	if target != null and is_instance_valid(target):
		var tt: Vector3 = target.global_position - p.global_position
		if Vector2(tt.x, tt.z).length() > 0.05:
			p.facing = atan2(tt.x, tt.z)
			p.visual.rotation.y = p.facing
	var rate := _rate()
	var hits := _hit_times(m, rate)
	var last: float = hits[hits.size() - 1][0] if not hits.is_empty() else 0.3
	p.attack_cd = maxf(float(m.cd) / rate, last + 0.08)
	p.swing_t = maxf(float(m.lock), last * 0.6)
	var to_hit := last
	if p.mod_anim != null:
		to_hit = p.mod_anim.play_move(m, rate)
	var lunge := float(m.lunge)
	if target != null and is_instance_valid(target) and name == _route("riposte"):
		var d: Vector3 = target.global_position - p.global_position
		lunge = maxf(Vector2(d.x, d.z).length() - 1.1, 0.0) # close in for the crit
	p._lunge(lunge, maxf((last if m.has("hits") else to_hit) * 0.85, 0.1))
	if m.has("invuln"):
		p.invuln_t = maxf(p.invuln_t, float(m.invuln))
	if m.get("phase", false):
		_phase_t = last + 0.1
	if m.has("leap") and p.is_on_floor():
		p.velocity.y = float(m.leap)
	if m.has("hang"):
		_hang_t = float(m.hang)
		p.velocity.y = maxf(p.velocity.y, 2.0)
	_spend_stamina(m)
	route = name
	route_count[name] = int(route_count.get(name, 0)) + 1
	var title := String(m.get("title", ""))
	if title != "":
		_show_title(title)
	_performing = true
	var finisher := name in [_route("llh"), _route("chain"), _route("riposte")]
	p.attacked.emit(3 if finisher else 1, p._forward())
	_performing = false
	p.special_move.emit(name)
	_schedule(m, rate, fx, target, false)
	Audio.play("sword_swing", 1.5 if finisher or fx != "" else -1.0, 0.12) # AUDIO HOOK
	if fx in ["slam", "flurry", "rush"]:
		Audio.play("lunge_whoosh", -2.0, 0.1) # AUDIO HOOK
	if _chain != null:
		_chain.set("extend", 1.0)


## The strike times of a move in game seconds from now: [[t, damage mult], ...].
func _hit_times(m: Dictionary, rate: float) -> Array:
	var spd := float(m.speed) * rate
	var from := float(m.from)
	var out: Array = []
	if m.has("hits"):
		for h in m.hits:
			out.append([maxf(float(h[0]) - from, 0.0) / spd, float(h[1])])
	else:
		out.append([maxf(float(m.hit) - from, 0.0) / spd, float(m.dmg)])
	return out


## Queue a move's strikes. `extra_only`: player.gd lands the first one itself (its own moves).
func _schedule(m: Dictionary, rate: float, fx: String, target, extra_only: bool) -> void:
	var hits := _hit_times(m, rate)
	for i in hits.size():
		if extra_only and i == 0:
			continue
		_events.append({"t": hits[i][0], "kind": "strike", "mult": hits[i][1], "m": m, "fx": fx if i == 0 else "",
			"target": target, "first": i == 0, "art": fx != ""})
	if extra_only and m.has("aoe") and not hits.is_empty():
		_events.append({"t": hits[0][0] + 0.01, "kind": "aoe", "m": m, "mult": float(m.dmg) * 0.5})


func _tick_events(delta: float) -> void:
	for i in range(_events.size() - 1, -1, -1):
		var ev: Dictionary = _events[i]
		ev.t -= delta
		if ev.t > 0.0:
			continue
		_events.remove_at(i)
		match ev.kind:
			"strike":
				_strike_event(ev)
			"aoe":
				_shockwave(ev.m, float(ev.mult), float(ev.m.aoe))
			"rupture":
				_rupture(ev.pos, float(ev.dmg))


func _strike_event(ev: Dictionary) -> void:
	var m: Dictionary = ev.m
	var mult: float = ev.mult
	match String(ev.fx):
		"wave":
			_fire_wave(mult)
			return
		"lash":
			_lash(m, mult)
			return
		"cleave":
			var fwd: Vector3 = player._forward()
			for k in 3:
				_events.append({"t": 0.09 * k, "kind": "rupture", "pos": player.global_position + fwd * (2.0 + 2.0 * k), "dmg": mult})
			player.shake = maxf(player.shake, float(m.shake))
			Audio.play_at("boss_slam_impact", player.global_position + fwd * 2.0, -3.0) # AUDIO HOOK
			return
	var target = ev.target
	var n := strike(m, mult, target, bool(ev.art))
	if m.has("aoe") and ev.first:
		n += _shockwave(m, mult * 0.6, float(m.aoe))
	match String(ev.fx):
		"nova":
			_nova_fx(player.global_position + Vector3(0, 1.0, 0), float(m.reach))
		"slam":
			HFx.shockwave(main, player.global_position, float(m.aoe) * 1.1, Color(0.85, 0.9, 1.0), 0.5)
			Audio.play_at("boss_slam_impact", player.global_position, 0.0) # AUDIO HOOK
	if n > 0 and m.has("crit") and target != null:
		_show_title("RIPOSTE")


## One strike of a move: everything in the cone (reach, arc) around Sol. Returns how many it hit.
## Staggered enemies are left for the bite / execution, except a move's own target (the riposte).
func strike(m: Dictionary, mult: float, target = null, is_art := false) -> int:
	var p = player
	var w: Dictionary = p.weapon_stats()
	var fwd: Vector3 = p._forward()
	var reach := float(m.reach) + float(w.reach)
	var arc := float(m.get("arc", 0.3))
	var dmg: float = float(w.dmg) * mult * p.damage_mult() * ((1.0 + _stat("art_dmg")) if is_art else 1.0)
	if m.has("crit"):
		dmg *= float(m.crit)
	var n := 0
	for e in main.enemies_root.get_children():
		if e.dead or (e.staggered and e != target):
			continue
		var to: Vector3 = e.global_position - p.global_position
		to.y = 0.0
		var d := to.length()
		var r: float = reach + (float(e.get("body_radius")) if e.get("body_radius") != null else 0.0)
		if d < r and (d < 0.9 or fwd.dot(to / d) > arc):
			_deal(e, dmg, to.normalized() if d > 0.01 else fwd, m)
			n += 1
	if n > 0:
		p.shake = maxf(p.shake, float(m.shake))
		main.rumble(0.4, 0.5, 0.1)
		main.set_slowmo(0.06, float(m.stop))
	return n


## Damage one enemy from an Arsenal strike (through take_hit and the hit_enemy signal, like the blade).
func _deal(e, dmg: float, dir: Vector3, m: Dictionary = {}) -> void:
	var hd: float = dmg * player._vs_mult(e)
	e.take_hit(hd, dir)
	_recent[e] = Time.get_ticks_msec()
	if m.has("bleed"):
		_add_bleed(e, float(m.bleed))
	if m.has("launch") and not e.dead and e.get("velocity") != null and not e.has_method("parry_open"):
		e.velocity.y = float(m.launch)
		e.knockback = dir * 4.0
	player.hit_enemy.emit(e, hd)
	Audio.play_at("sword_hit", e.global_position, 2.0 if m.has("crit") else 0.0) # AUDIO HOOK


## A ground shockwave of `radius` around the strike point: everything the blade itself did not just hit.
func _shockwave(m: Dictionary, mult: float, radius: float) -> int:
	var p = player
	var w: Dictionary = p.weapon_stats()
	var at: Vector3 = p.global_position + p._forward() * 1.0
	var now := Time.get_ticks_msec()
	var n := 0
	for e in main.enemies_root.get_children():
		if e.dead or e.staggered or now - int(_recent.get(e, -9999)) < 150:
			continue
		var to: Vector3 = e.global_position - at
		to.y = 0.0
		if to.length() < radius + (float(e.get("body_radius")) if e.get("body_radius") != null else 0.0):
			_deal(e, float(w.dmg) * mult * p.damage_mult(), to.normalized() if to.length() > 0.01 else p._forward(), m)
			n += 1
	HFx.shockwave(main, at, radius, ArsenalData.AFFINITY_COLOR.get(String(wtype.get("affinity", "")), Color(1, 0.3, 0.1)), 0.4)
	_spray(at + Vector3(0, 0.3, 0), Vector3.UP, Color(0.35, 0.3, 0.28), 10) # grit off the street
	p.shake = maxf(p.shake, float(m.get("shake", 0.3)))
	return n


func _spend_stamina(m: Dictionary) -> void:
	var c := float(m.get("stamina_cost", 0.0)) * float(wtype.get("stamina", 1.0))
	if c > 0.0 and player.has_method("spend_stamina"):
		player.spend_stamina(c) # Group B's stamina, when it lands


# ---------------------------------------------------------------- the plunge
func _start_plunge() -> void:
	_plunging = true
	_plunge_move = _route("plunge")
	var m := SolMoves.move(_plunge_move)
	_events.clear()
	player.velocity.y = -24.0
	player.move_name = _plunge_move
	player.swing_t = 0.6
	player.attack_cd = 0.6
	player.invuln_t = maxf(player.invuln_t, 0.3)
	_show_title(String(m.get("title", "PLUNGE")))
	route = _plunge_move
	route_count[_plunge_move] = int(route_count.get(_plunge_move, 0)) + 1
	if player.mod_anim != null:
		player.mod_anim.play_move(m, 1.4) # the overhead wind-up while he dives
	Audio.play("pounce_whoosh", -2.0, 0.1) # AUDIO HOOK


func _plunge_tick() -> void:
	if not _plunging:
		return
	player.velocity.y = minf(player.velocity.y, -20.0)
	player.attack_cd = maxf(player.attack_cd, 0.2)
	_plunge_air += get_physics_process_delta_time()
	if player.is_on_floor() or _plunge_air > 2.0:
		_plunge_air = 0.0
		_plunging = false
		var m := SolMoves.move(_plunge_move)
		if player.mod_anim != null:
			var land := m.duplicate()
			land.from = float(m.hit) - 0.05
			player.mod_anim.play_move(land, 1.0)
		player.swing_t = 0.4
		player.attack_cd = 0.35
		strike(m, float(m.dmg))
		_shockwave(m, float(m.dmg) * 0.7, float(m.aoe))
		HFx.shockwave(main, player.global_position, float(m.aoe) * 1.15, Color(0.95, 0.85, 0.7), 0.45)
		Audio.play_at("boss_slam_impact", player.global_position, -1.0) # AUDIO HOOK
		Audio.play("land_thud", 0.0, 0.05)
		main.set_slowmo(0.06, float(m.stop))
		main.rumble(0.6, 0.9, 0.2)
		player.special_move.emit(_plunge_move)


# ---------------------------------------------------------------- art effects
## Blood Wave: a crescent of blood that flies 16 m, cutting (and bleeding) all it passes.
func _fire_wave(mult: float) -> void:
	var p = player
	var fwd: Vector3 = p._forward()
	var mi := _wave_node()
	mi.visible = true
	mi.global_position = p.global_position + Vector3(0, 1.1, 0) + fwd * 0.8
	mi.basis = Basis(Vector3.UP, atan2(fwd.x, fwd.z)) * Basis(Vector3.FORWARD, deg_to_rad(-20.0))
	mi.scale = Vector3.ONE * 1.2
	var w: Dictionary = p.weapon_stats()
	_waves.append({"node": mi, "dir": fwd, "life": 0.68, "hit": {}, "dmg": float(w.dmg) * mult * p.damage_mult() * (1.0 + _stat("art_dmg"))})
	Audio.play("blood_bolt", -1.0, 0.1) # AUDIO HOOK


func _wave_node() -> MeshInstance3D:
	for n in _wave_pool:
		if not n.visible:
			return n
	if _crescent == null:
		_crescent = _make_crescent()
	var mi := MeshInstance3D.new()
	mi.mesh = _crescent
	mi.material_override = _add_mat(Color(1.0, 0.06, 0.1, 0.9))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	_wave_pool.append(mi)
	return mi


func _tick_waves(delta: float) -> void:
	for i in range(_waves.size() - 1, -1, -1):
		var wv: Dictionary = _waves[i]
		wv.life -= delta
		var node: MeshInstance3D = wv.node
		node.global_position += wv.dir * 24.0 * delta
		node.scale = Vector3.ONE * (1.2 + (0.68 - wv.life) * 1.2)
		for e in main.enemies_root.get_children():
			if e.dead or e.staggered or wv.hit.has(e):
				continue
			var to: Vector3 = e.global_position - node.global_position
			to.y = 0.0
			if to.length() < 1.8 + (float(e.get("body_radius")) if e.get("body_radius") != null else 0.0):
				wv.hit[e] = true
				_deal(e, wv.dmg, wv.dir, {"bleed": 70.0})
		if wv.life <= 0.0:
			node.visible = false
			_waves.remove_at(i)


## Silver Nova: a ring of silver light.
func _nova_fx(at: Vector3, radius: float) -> void:
	HFx.shockwave(main, at - Vector3(0, 1.0, 0), radius, Color(0.75, 0.85, 1.0), 0.5)
	HFx.shockwave(main, at - Vector3(0, 1.0, 0), radius * 0.6, Color(1.0, 1.0, 1.0), 0.35)
	_spray(at, Vector3.UP, Color(0.8, 0.9, 1.0), 24)
	Audio.play("parry_clang", 0.0, 0.1) # AUDIO HOOK


## Chain Lash: lash the nearest enemy in the cone up to 10 m and drag it to Sol's feet.
func _lash(m: Dictionary, mult: float) -> void:
	var p = player
	var fwd: Vector3 = p._forward()
	var best = null
	var best_d := float(m.reach)
	for e in main.enemies_root.get_children():
		if e.dead:
			continue
		var to: Vector3 = e.global_position - p.global_position
		to.y = 0.0
		var d := to.length()
		if d < best_d and (d < 1.0 or fwd.dot(to / d) > float(m.arc)):
			best = e
			best_d = d
	if _chain != null:
		_chain.set("extend", 1.0)
	if best == null:
		return
	var w: Dictionary = p.weapon_stats()
	var back: Vector3 = p.global_position - best.global_position
	back.y = 0.0
	_deal(best, float(w.dmg) * mult * p.damage_mult() * (1.0 + _stat("art_dmg")), -back.normalized(), m)
	if not best.dead and not best.has_method("parry_open") and best.get("knockback") != null:
		best.knockback = back.normalized() * sqrt(2.0 * 25.0 * maxf(best_d - 1.4, 0.0))
	_add_poise(best, 999.0) # dragged in off its feet
	_burn(best, 2.5)
	_spray(best.global_position + Vector3(0, 1.1, 0), back.normalized(), Color(1.0, 0.5, 0.15), 14)
	p.shake = maxf(p.shake, float(m.shake))
	main.set_slowmo(0.08, float(m.stop))


## Butcher's Cleave: one rupture of the street.
func _rupture(at: Vector3, mult: float) -> void:
	var p = player
	var w: Dictionary = p.weapon_stats()
	var n := 0
	for e in main.enemies_root.get_children():
		if e.dead or e.staggered:
			continue
		var to: Vector3 = e.global_position - at
		to.y = 0.0
		if to.length() < 1.7 + (float(e.get("body_radius")) if e.get("body_radius") != null else 0.0):
			_deal(e, float(w.dmg) * mult * p.damage_mult() * (1.0 + _stat("art_dmg")), (e.global_position - p.global_position).normalized(), {"bleed": 40.0})
			n += 1
	HFx.shockwave(main, at, 1.8, Color(0.9, 0.05, 0.08), 0.35)
	_spray(at + Vector3(0, 0.2, 0), Vector3.UP, Color(0.6, 0.02, 0.04), 18)
	if n > 0:
		main.set_slowmo(0.08, 0.05)


# ---------------------------------------------------------------- status: bleed, stagger, burn
func _on_hit(e, dmg: float) -> void:
	if _in_proc or e == null or not is_instance_valid(e):
		return
	_recent[e] = Time.get_ticks_msec()
	var dir: Vector3 = (e.global_position - player.global_position)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else player._forward()
	_spray(e.global_position + Vector3(0, 1.15, 0), dir + Vector3(0, 0.4, 0), Color(0.55, 0.0, 0.03), 12)
	if e.dead:
		return
	var m: Dictionary = SolMoves.move(player.move_name) if SolMoves.has_move(player.move_name) else {}
	var b := float(wtype.get("bleed", 0.0)) * (1.0 + _stat("bleed"))
	if b > 0.0:
		_add_bleed(e, dmg * b)
	var poise: float = dmg * float(wtype.get("stagger", 1.0)) * float(m.get("poise", 1.0)) * (1.0 + _stat("poise"))
	if wtype.get("wolf_break", false) and e.get("kind") == 1:
		poise *= 1.6 # the war hammer breaks the Pack
	_add_poise(e, poise)
	if String(wtype.get("affinity", "")) == "fire" and e.get("kind") == 0:
		_burn(e, 2.0)


func _add_bleed(e, amount: float) -> void:
	if e.dead:
		return
	var boss: bool = e.has_method("parry_open")
	var cap := BLEED_MAX_BOSS if boss else BLEED_MAX
	var v: float = float(e.get_meta("bleed", 0.0)) + amount
	e.set_meta("bleed_t", Time.get_ticks_msec())
	if v >= cap:
		e.set_meta("bleed", 0.0)
		_hemorrhage(e)
	else:
		e.set_meta("bleed", v)


## The Bleed burst: a share of max blood at once, and a great spray.
func _hemorrhage(e) -> void:
	var boss: bool = e.has_method("parry_open")
	var mhp: float = float(e.get("max_hp")) if e.get("max_hp") != null else 100.0
	var dmg: float = (mhp * 0.05 + 20.0) if boss else maxf(18.0, mhp * 0.15)
	_in_proc = true
	if not (e.staggered and not boss):
		e.take_hit(dmg, Vector3.UP)
	_in_proc = false
	var at: Vector3 = e.global_position + Vector3(0, 1.2, 0)
	_spray(at, Vector3.UP, Color(0.8, 0.0, 0.05), 30)
	_spray(at, Vector3(1, 0.3, 0), Color(0.5, 0.0, 0.02), 16)
	HFx.shockwave(main, e.global_position, 1.6, Color(0.9, 0.02, 0.06), 0.3)
	Audio.play_at("blood_bolt", e.global_position, 1.0) # AUDIO HOOK
	if _stat("bleed_heal") > 0.0:
		player.heal(_stat("bleed_heal"))
	_show_title("HEMORRHAGE")


func _add_poise(e, amount: float) -> void:
	if e.dead or e.staggered:
		return
	var boss: bool = e.has_method("parry_open")
	var mhp: float = float(e.get("max_hp")) if e.get("max_hp") != null else 100.0
	var cap: float = mhp * 0.18 if boss else maxf(45.0, mhp * 0.8)
	var v: float = float(e.get_meta("poise", 0.0)) + amount
	e.set_meta("poise_t", Time.get_ticks_msec())
	if v >= cap:
		e.set_meta("poise", 0.0)
		player._stagger_enemy(e, 2.2 if not boss else 1.5)
		if _stat("break_dash") > 0.0: # the Shatterer Rite
			player.dash_charges = minf(player.dash_charges + 1.0, player.MAX_DASH)
		HFx.shockwave(main, e.global_position, 1.2, Color(1.0, 0.85, 0.4), 0.3)
		Audio.play_at("parry_clang", e.global_position, -2.0, 0.1) # AUDIO HOOK
		_show_title("STAGGER")
	else:
		e.set_meta("poise", v)


func _burn(e, seconds: float) -> void:
	e.set_meta("burn_until", Time.get_ticks_msec() + int(seconds * 1000.0))


var _status_t := 0.0


func _tick_status(delta: float) -> void:
	_status_t -= delta
	if _status_t > 0.0:
		return
	_status_t = 0.5
	var now := Time.get_ticks_msec()
	var w: Dictionary = player.weapon_stats()
	for e in main.enemies_root.get_children():
		if e.dead:
			continue
		# poise and bleed ebb away when the blade stops landing
		if e.has_meta("poise") and now - int(e.get_meta("poise_t", 0)) > 1500:
			e.set_meta("poise", maxf(float(e.get_meta("poise")) - POISE_DECAY * 0.5, 0.0))
		if e.has_meta("bleed") and now - int(e.get_meta("bleed_t", 0)) > 3000:
			e.set_meta("bleed", maxf(float(e.get_meta("bleed")) - 4.0, 0.0))
		if e.has_meta("burn_until") and now < int(e.get_meta("burn_until")) and not e.staggered:
			_in_proc = true
			e.take_hit(float(w.dmg) * 0.2, Vector3.UP)
			_in_proc = false
			_spray(e.global_position + Vector3(0, 1.3, 0), Vector3.UP, Color(1.0, 0.45, 0.1), 5)
	for k in _recent.keys():
		if not is_instance_valid(k) or now - int(_recent[k]) > 2000:
			_recent.erase(k)


# ---------------------------------------------------------------- VFX: blood sprays (pooled)
func vfx_amount() -> float:
	var st := get_node_or_null("/root/Settings")
	var a := 1.0
	if st != null:
		var v = st.get("vfx_amount")
		if v == null and st.get_script() != null:
			v = (st.get_script() as Script).get("vfx_amount") # a static var on the script
		if v != null:
			a = float(v)
		var q = st.get_script().get("quality") if st.get_script() != null else null
		if q != null and int(q) == 0:
			a *= 0.5
	return clampf(a, 0.0, 2.0)


func _spray(at: Vector3, dir: Vector3, c: Color, amount: int) -> void:
	var k := vfx_amount()
	if k <= 0.01 or not is_inside_tree():
		return
	if _sprays.is_empty():
		_build_sprays()
	var ps := _sprays[_spray_next]
	_spray_next = (_spray_next + 1) % _sprays.size()
	ps.global_position = at
	ps.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	ps.color = c
	ps.amount = maxi(int(amount * k), 2)
	ps.restart()
	ps.emitting = true


func _build_sprays() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	for i in SPRAY_POOL:
		var ps := CPUParticles3D.new()
		ps.one_shot = true
		ps.emitting = false
		ps.amount = 16
		ps.lifetime = 0.55
		ps.explosiveness = 0.95
		ps.mesh = q
		ps.spread = 38.0
		ps.initial_velocity_min = 2.5
		ps.initial_velocity_max = 6.0
		ps.gravity = Vector3(0, -14.0, 0)
		ps.scale_amount_min = 0.6
		ps.scale_amount_max = 1.6
		ps.local_coords = false
		ps.top_level = true
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(0.4, 0.4, 0.4, 0))
		ps.color_ramp = g
		add_child(ps)
		_sprays.append(ps)


# ---------------------------------------------------------------- VFX: slash trails
func _build_trails() -> void:
	for t in _trails:
		if is_instance_valid(t.mi):
			t.mi.queue_free()
	_trails.clear()
	for left in [false, true]:
		var sock := _socket(left)
		if sock == null or (left and _left_visual == null):
			continue
		var im := ImmediateMesh.new()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _trail_mat()
		mi.extra_cull_margin = 16.0
		add_child(mi)
		mi.global_transform = Transform3D.IDENTITY
		_trails.append({"mi": mi, "im": im, "pts": [], "socket": sock, "left": left})


static func _trail_mat() -> StandardMaterial3D:
	if not _mats.has("trail"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
		_mats["trail"] = m
	return _mats["trail"]


static func _add_mat(c: Color) -> StandardMaterial3D:
	var key := "add_" + c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = c
		_mats[key] = m
	return _mats[key]


static func _make_crescent() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	for i in n:
		var a0 := lerpf(-1.2, 1.2, float(i) / n)
		var a1 := lerpf(-1.2, 1.2, float(i + 1) / n)
		var w0 := 0.38 * sin(PI * float(i) / n) + 0.02
		var w1 := 0.38 * sin(PI * float(i + 1) / n) + 0.02
		var o0 := Vector3(sin(a0), 0, cos(a0)) * 1.4
		var o1 := Vector3(sin(a1), 0, cos(a1)) * 1.4
		var i0 := Vector3(sin(a0), 0, cos(a0)) * (1.4 - w0)
		var i1 := Vector3(sin(a1), 0, cos(a1)) * (1.4 - w1)
		for v in [i0, o0, o1, i0, o1, i1]:
			st.add_vertex(v)
	return st.commit()


func _process(delta: float) -> void:
	if player == null or _trails.is_empty():
		_update_hud()
		return
	var active: bool = player.mod_anim != null and player.mod_anim.move_playing() and not player.dead
	var k := vfx_amount()
	var col: Color = wtype.get("trail", Color(0.8, 0.85, 1.0))
	if player.frenzy_t > 0.0:
		col = Color(1.0, 0.05, 0.1)
	for t in _trails:
		var pts: Array = t.pts
		for s in pts:
			s[2] += delta
		while not pts.is_empty() and pts[0][2] > 0.16:
			pts.pop_front()
		if active and k > 0.01 and is_instance_valid(t.socket):
			var xf: Transform3D = (t.socket as Node3D).global_transform
			var tip: Vector3 = xf * Vector3(0, 0, tip_len)
			if _chain != null and not t.left and _chain.has_method("tip"):
				tip = _chain.tip()
			var base: Vector3 = xf * Vector3(0, 0, tip_len * (0.35 if tip_len < 1.2 else 0.55))
			pts.append([base, tip, 0.0])
			while pts.size() > TRAIL_LEN:
				pts.pop_front()
		var im: ImmediateMesh = t.im
		im.clear_surfaces()
		if pts.size() >= 2:
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for s in pts:
				var a := clampf(1.0 - s[2] / 0.16, 0.0, 1.0) * 0.75 * minf(k, 1.0)
				im.surface_set_color(Color(col.r, col.g, col.b, a * 0.25))
				im.surface_add_vertex(s[0])
				im.surface_set_color(Color(col.r, col.g, col.b, a))
				im.surface_add_vertex(s[1])
			im.surface_end()
	_update_hud()


# ---------------------------------------------------------------- HUD: the art's cooldown ring
func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 2
	add_child(hud)
	_hud_ctl = Control.new()
	_hud_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_ctl.draw.connect(_draw_hud)
	hud.add_child(_hud_ctl)


func _show_title(t: String) -> void:
	_title = t
	_title_t = 1.1


func _update_hud() -> void:
	if _hud_ctl == null:
		return
	var show: bool = main != null and main.get("started") != false and not player.dead
	hud.visible = show
	if show:
		_hud_ctl.queue_redraw()


func _draw_hud() -> void:
	var c := _hud_ctl
	var sz := c.size
	var tc := c.get_node_or_null("/root/Touch")
	var touch: bool = tc != null and tc.get("active") == true
	# bottom right, clear of the HUD; on touch the ART button itself sits there, so the ring moves left
	var centre := Vector2(sz.x - 70.0, sz.y - 70.0)
	if touch:
		centre = Vector2(sz.x * 0.5 + 150.0, sz.y - 54.0)
	var r := 26.0
	var a := art()
	var ready := art_cd_t <= 0.0
	c.draw_circle(centre, r + 3.0, Color(0.03, 0.02, 0.025, 0.75))
	var col: Color = ArsenalData.AFFINITY_COLOR.get(String(wtype.get("affinity", "")), Color(0.9, 0.8, 0.6))
	if ready:
		c.draw_circle(centre, r - 4.0, Color(col.r, col.g, col.b, 0.35))
		c.draw_arc(centre, r, 0.0, TAU, 32, col, 2.5, true)
	else:
		var f := 1.0 - art_cd_t / maxf(art_cd_max, 0.01)
		c.draw_arc(centre, r, -PI / 2.0, -PI / 2.0 + TAU * f, 32, Color(col.r, col.g, col.b, 0.8), 2.5, true)
	if chain_t > 0.0:
		c.draw_arc(centre, r + 6.0, 0.0, TAU, 32, Color(1.0, 0.05, 0.1, 0.9), 2.0, true)
	var font := ThemeDB.fallback_font
	var key: String = "RB" if (main != null and main.hud != null and main.hud.using_pad) else "V"
	if touch:
		key = "ART"
	c.draw_string(font, centre + Vector2(-r, 6.0), key, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 15, Color(1, 1, 1, 0.9 if ready else 0.5))
	c.draw_string(font, centre + Vector2(-110.0, r + 18.0), String(a.name).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 220.0, 12, Color(col.r, col.g, col.b, 0.85))
	if chain_t > 0.0:
		c.draw_string(font, centre + Vector2(-110.0, -r - 12.0), "BLOOD CHAIN", HORIZONTAL_ALIGNMENT_CENTER, 220.0, 12, Color(1.0, 0.2, 0.2, 0.95))
	if _title_t > 0.0:
		var alpha := clampf(_title_t / 0.3, 0.0, 1.0)
		c.draw_string(font, Vector2(0, sz.y * 0.68), _title, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 26, Color(1.0, 0.85, 0.6, alpha))
