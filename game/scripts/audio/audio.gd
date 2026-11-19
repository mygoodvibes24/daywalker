extends Node
## Sound (autoload "Audio"): one-shot SFX from a small player pool with random pitch,
## 3D positional SFX for world events, the rain bed with distant thunder, footsteps, and
## music that crossfades by context: "menu", "explore", "combat", "boss" ("" = silence).
##
## In the game, main.gd calls `Audio.attach_world(self)`; from then on the music follows
## the fight on its own (enemies near and alive -> combat, none for a few seconds ->
## explore, `set_boss(true)` -> boss). Browsers block audio until the first user input, so
## nothing plays before `unlock()` (any key / click / button press calls it on the web).

const DIR := "res://assets/audio/"
const SFX := {
	"sword_swing": ["sfx/sword_swing_1", "sfx/sword_swing_2"],
	"sword_hit": ["sfx/sword_hit_1", "sfx/sword_hit_2"],
	"bite": ["sfx/bite"],
	"blood_dash": ["sfx/blood_dash"],
	"perfect_dodge": ["sfx/perfect_dodge"],
	"level_up": ["sfx/level_up"],
	"loot_pickup": ["sfx/loot_pickup"],
	"loot_rare_hum": ["sfx/loot_rare_hum"],
	"tithe_collect": ["sfx/tithe_collect"],
	"wolf_transform": ["sfx/wolf_transform"],
	"wolf_growl": ["sfx/wolf_growl"],
	"wolf_howl": ["sfx/wolf_howl"],
	"vamp_hiss": ["sfx/vamp_hiss", "sfx/vampire_hiss"],
	"vamp_burn": ["sfx/vamp_burn"],
	"death": ["sfx/death"],
	"rain_loop": ["sfx/rain_loop"],
	"thunder": ["sfx/thunder"],
	"step": ["sfx/step_wet_1", "sfx/step_wet_2"],
	"ui_hover": ["sfx/ui_hover"],
	"ui_click": ["sfx/ui_click"],
	# bosses (hunt/bosses/boss_base.gd)
	"boss_slam": ["sfx/boss_slam"],
	"boss_slam_impact": ["sfx/boss_slam_impact"], # the Abomination's slam and throw
	"boss_swipe": ["sfx/boss_swipe"],
	"blood_bolt": ["sfx/blood_bolt"],
	"boss_blink": ["sfx/boss_blink"],
	# the Red Curfew wall (a 3D loop, hunt/curfew_ring.gd)
	"curfew_drone": ["sfx/curfew_drone"],
	# the Descent (played from hunt_director.gd)
	"manhole_clank": ["sfx/manhole_clank"],
	"land_thud": ["sfx/land_thud"],
	# a successful parry (player.parried, connected in attach_world)
	"parry_clang": ["sfx/parry_clang"],
	# creatures (asset round 3), timed to the creature clips from enemy_bark / on_enemy_died
	"wolf_roar": ["sfx/werewolf_roar"],
	"claw_swipe": ["sfx/claw_swipe"],
	"pounce_whoosh": ["sfx/pounce_whoosh"],
	"lunge_whoosh": ["sfx/vampire_lunge_whoosh"],
	"body_fall": ["sfx/body_fall"],
}
const MUSIC := {
	"menu": "music/menu_lair",
	"explore": "music/explore",
	"combat": "music/combat",
	"boss": "music/combat",
	# boss themes (asset round 3): "boss_<boss id>" plays in that fight, else "boss"
	"boss_marcus": "music/boss_marcus",
	"boss_abomination": "music/boss_abomination",
}
const MUSIC_DB := {"menu": -4.0, "explore": -6.0, "combat": -5.0, "boss": -2.0, "boss_marcus": -4.0, "boss_abomination": -3.0}
## Creature SFX timing (seconds into the move), from the clip manifest and enemy.gd's SPECIALS.
const POUNCE_DELAY := 0.5 # the leap's wind-up: the spring
const LUNGE_DELAY := 0.55 # the lunge's wind-up: the dash
const WOLF_FALL_DELAY := 1.3 # werewolf_anim_death_heavy lands at 1.6 s, played at 1.25x
const CIVILIAN_FALL_DELAY := 1.0
const POOL_2D := 12
const POOL_3D := 10
const COMBAT_RADIUS := 16.0
const COMBAT_HOLD := 5.0 # seconds of calm before the music drops back to explore

var unlocked := not OS.has_feature("web")
var context := "" # the music context playing (or waiting for the unlock)
var boss_active := false
var boss_id := "" # the boss fight playing (its theme, if it has one)
var world: Node = null # main.gd while a game is running
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _music: Array[AudioStreamPlayer] = []
var _music_cur := 0
var _music_tween: Tween
var _rain: AudioStreamPlayer
var _thunder_t := 25.0
var _calm_t := 99.0
var _poll_t := 0.0
var _step_t := 0.0
var _last_play := {} # name -> msec, to stop machine-gun repeats


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var settings = load("res://scripts/settings.gd")
	settings.ensure_buses()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 7.0
		p.max_distance = 70.0
		p.attenuation_filter_cutoff_hz = 9000.0
		add_child(p)
		_pool3d.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	_rain = AudioStreamPlayer.new()
	_rain.bus = "SFX"
	_rain.volume_db = -17.0
	add_child(_rain)


## The first user gesture: start whatever was waiting (browsers require this).
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	var want := context
	context = ""
	set_music(want)


func _input(event: InputEvent) -> void:
	if not unlocked and event.is_pressed() and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventScreenTouch):
		unlock()


# ---------------------------------------------------------------- streams
func stream(path: String) -> AudioStream:
	if not _streams.has(path):
		var s = load(DIR + path + ".ogg")
		_streams[path] = s
	return _streams[path]


func _pick(name: String) -> AudioStream:
	var list: Array = SFX.get(name, [])
	if list.is_empty():
		return null
	return stream(list.pick_random())


func _free_player(pool: Array):
	for p in pool:
		if not p.playing:
			return p
	return pool[0] # all busy: steal the oldest slot


func _rate_ok(name: String, min_ms: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(name, -100000)) < min_ms:
		return false
	_last_play[name] = now
	return true


# ---------------------------------------------------------------- one-shots
## Play a non-positional sound by name (see SFX), with a little random pitch.
func play(name: String, volume_db := 0.0, pitch_var := 0.07) -> AudioStreamPlayer:
	if not unlocked or not _rate_ok(name, 40):
		return null
	var s := _pick(name)
	if s == null:
		return null
	var p: AudioStreamPlayer = _free_player(_pool)
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
	return p


## Play a sound at a world position (enemy hits, howls, transforms).
func play_at(name: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.08) -> AudioStreamPlayer3D:
	if not unlocked or not _rate_ok(name + "@3d", 30):
		return null
	var s := _pick(name)
	if s == null:
		return null
	var p: AudioStreamPlayer3D = _free_player(_pool3d)
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.global_position = pos
	p.play()
	return p


# ---------------------------------------------------------------- music
## Crossfade to a context ("menu", "explore", "combat", "boss", or "" for silence).
func set_music(ctx: String, fade := 2.0) -> void:
	if ctx == context:
		return
	context = ctx
	if not unlocked:
		return # unlock() starts it
	var old := _music[_music_cur]
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	if old.playing:
		_music_tween.tween_property(old, "volume_db", -60.0, fade)
		_music_tween.chain().tween_callback(old.stop)
	if ctx == "" or not MUSIC.has(ctx):
		return
	var s = stream(MUSIC[ctx])
	if s is AudioStreamOggVorbis:
		s.loop = true
	_music_cur = 1 - _music_cur
	var nxt := _music[_music_cur]
	nxt.stream = s
	nxt.volume_db = -50.0
	# boss and combat share a track: keep the place when switching between them
	nxt.play()
	_music_tween.tween_property(nxt, "volume_db", MUSIC_DB[ctx], fade * 0.8)


func set_boss(on: bool, id := "") -> void:
	boss_active = on
	boss_id = id if on else ""
	_update_context()


## The music context for the boss fight playing: its own theme if it has one.
func boss_context() -> String:
	return "boss_" + boss_id if MUSIC.has("boss_" + boss_id) else "boss"


# ---------------------------------------------------------------- the world
## main.gd hands itself over; music, rain, footsteps and the dash whoosh follow it.
func attach_world(w: Node) -> void:
	world = w
	boss_active = false
	boss_id = ""
	_calm_t = 99.0
	var p = w.get("player")
	if p != null and p.has_signal("dashed") and not p.dashed.is_connected(_on_dashed):
		p.dashed.connect(_on_dashed)
	if p != null and p.has_signal("parried") and not p.parried.is_connected(_on_parried):
		p.parried.connect(_on_parried)
	if not w.tree_exiting.is_connected(_on_world_exit):
		w.tree_exiting.connect(_on_world_exit.bind(w), CONNECT_ONE_SHOT)
	set_music("explore")


func _on_world_exit(w: Node) -> void:
	if world == w:
		world = null
		boss_active = false
		boss_id = ""


func _on_dashed(_dir: Vector3) -> void:
	play("blood_dash", -3.0, 0.1)


## A parry: a bright steel clang on top of the hit, so the window teaches itself.
func _on_parried(_e) -> void:
	play("parry_clang", 1.0, 0.05)


## A looping 3D player (the Curfew wall's drone): not from the pool, owned by `parent`.
func loop_3d(name: String, parent: Node3D, volume_db := 0.0) -> AudioStreamPlayer3D:
	var list: Array = SFX.get(name, [])
	if list.is_empty():
		return null
	var s = stream(list[0])
	if s is AudioStreamOggVorbis:
		s.loop = true
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.stream = s
	p.volume_db = volume_db
	p.unit_size = 10.0
	p.max_distance = 60.0
	p.attenuation_filter_cutoff_hz = 6000.0
	parent.add_child(p)
	return p


func _world_ok() -> bool:
	return world != null and is_instance_valid(world) and world.is_inside_tree()


func _update_context() -> void:
	if not _world_ok():
		return
	if boss_active:
		set_music(boss_context(), 1.2)
	elif _calm_t < COMBAT_HOLD:
		set_music("combat", 1.2)
	else:
		set_music("explore", 3.0)


## Called when Sol falls: a death sting and the music sinks.
func on_player_died() -> void:
	play("death", -2.0, 0.02)
	set_music("explore", 4.0)


## An enemy changed into a wolf.
func on_wolf_transform(pos: Vector3) -> void:
	play_at("wolf_transform", pos, 2.0)
	if randf() < 0.6:
		var cry := "wolf_roar" if randf() < 0.6 else "wolf_howl"
		get_tree().create_timer(1.3, true, false, true).timeout.connect(func(): play_at(cry, pos, 0.0))


## Enemy died: vampires in the sun burn, the rest fall; Sol sometimes says something.
func on_enemy_died(e: Node3D) -> void:
	var burning: bool = e.get("burning") == true
	play_at("vamp_burn" if burning else "death", e.global_position, -4.0 if not burning else 0.0)
	if not burning and e.get("kind") == 1: # wolves and people hit the ground (the heavy fall clip)
		_later(WOLF_FALL_DELAY if e.get("transformed") == true else CIVILIAN_FALL_DELAY, e.global_position, "body_fall", -2.0)
	if randf() < 0.22:
		get_node("/root/Dialogue").play_group("bark_kill_")


## Loot hit the street: Eclipse-tier (rarity 3) drops hum in their beam.
func on_loot_dropped(rarity: int, pos: Vector3) -> void:
	if rarity >= 3:
		play_at("loot_rare_hum", pos, -1.0, 0.0)


## Loot picked up; an Eclipse item gets a word from Sol.
func on_loot_picked(rarity: int) -> void:
	play("loot_pickup", -2.0 if rarity < 2 else 1.0)
	if rarity >= 3:
		get_node("/root/Dialogue").play("bark_eclipse")


## An enemy winds up a strike: hisses, growls, and now and then a taunt.
func enemy_bark(e: Node3D) -> void:
	var wolf: bool = e.get("kind") == 1
	var sp: String = str(e.get("special")) if e.get("special") != null else ""
	if sp.begins_with("leap"):
		_later_on(POUNCE_DELAY, e, "pounce_whoosh", 0.0)
	elif sp.begins_with("lunge"):
		play_at("vamp_hiss", e.global_position, -3.0)
		_later_on(LUNGE_DELAY, e, "lunge_whoosh", 0.0)
		return
	elif e.get("windup_t") != null and float(e.get("windup_t")) > 0.0:
		_later_on(float(e.get("windup_t")), e, "claw_swipe", -1.0 if wolf else -4.0) # the strike frame
	if wolf:
		if e.get("transformed") == true and randf() < 0.35:
			play_at("wolf_growl", e.global_position, -2.0)
		return
	if randf() < 0.3:
		play_at("vamp_hiss", e.global_position, -4.0)
	if randf() < 0.1 and context != "boss": # no street taunts over a boss fight's adds (QA2 #17)
		get_node("/root/Dialogue").play_group("court_taunt_" if randf() < 0.4 else "vamp_taunt_")


## A positional one-shot `delay` seconds from now, following a node if it is still around.
func _later_on(delay: float, n: Node3D, name: String, db: float) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func():
		if is_instance_valid(n) and n.is_inside_tree():
			play_at(name, n.global_position, db))


func _later(delay: float, pos: Vector3, name: String, db: float) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func(): play_at(name, pos, db))


## A boss went down: the heavy bodies hit the ground on their fall clip's impact frame.
func on_boss_died(id: String, pos: Vector3) -> void:
	var t := {"marcus": 2.9 / 0.9, "abomination": 1.6, "alpha": 2.0, "knight": 1.6}
	if t.has(id):
		_later(float(t[id]), pos, "body_fall", 4.0)


func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	_ambience(real_dt)
	if not _world_ok():
		return
	_poll_t -= real_dt
	if _poll_t <= 0.0:
		_poll_t = 0.4
		var engaged := false
		var p = world.get("player")
		var root = world.get("enemies_root")
		if p != null and root != null and not world.get("game_over") and world.get("started"):
			for e in root.get_children():
				if e is Node3D and e.get("dead") == false and e.global_position.distance_to(p.global_position) < COMBAT_RADIUS:
					engaged = true
					break
		_calm_t = 0.0 if engaged else _calm_t + 0.4
		_update_context()
	_footsteps(real_dt)


func _footsteps(dt: float) -> void:
	var p = world.get("player")
	if p == null or p.dead or world.get_tree().paused or not p.is_on_floor():
		_step_t = 0.0
		return
	var v: Vector3 = p.velocity
	var spd := Vector2(v.x, v.z).length()
	if spd < 1.5:
		_step_t = 0.0
		return
	_step_t -= dt
	if _step_t <= 0.0:
		_step_t = clampf(2.6 / spd, 0.2, 0.55)
		play("step", -13.0 if spd < 9.0 else -10.0, 0.12)


func _ambience(dt: float) -> void:
	var settings = load("res://scripts/settings.gd")
	var want_rain: bool = unlocked and settings.rain and context != ""
	if want_rain and not _rain.playing:
		var s = stream(SFX.rain_loop[0])
		if s is AudioStreamOggVorbis:
			s.loop = true
		_rain.stream = s
		_rain.play()
	elif not want_rain and _rain.playing:
		_rain.stop()
	if want_rain:
		_thunder_t -= dt
		if _thunder_t <= 0.0:
			_thunder_t = randf_range(28.0, 70.0)
			play("thunder", randf_range(-12.0, -6.0), 0.1)
