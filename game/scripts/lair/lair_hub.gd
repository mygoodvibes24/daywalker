extends Node3D
## LAIR: Sol's walkable basement under the cathedral (res://scenes/lair.tscn), the hub between Hunts.
## Main menu Start, a Hunt's results and ?lair all land here. The room is the menu's lair set
## (menu/lair_set.gd in hub mode + lair/lair_rooms.gd): the vaulted lab with its bench, fridges, map
## board and tunnel, plus the armoury alcove and the wardrobe corner.
##
## Sol is the real player (player.gd) with `peaceful` on: walk, run, crouch, jump, dodge and the
## camera, touch controls included, but no blade (it stays on his back) and no bite. Walk up to a
## station, press E / Y / USE, and the camera frames it while its panel opens (lair_panel.gd):
##   rack (armoury alcove)  the blade he carries        bench   charms and Nia's contacts
##   mirror (wardrobe)      clothes, with their stats    table   tonight's briefing + Begin the Hunt
##   gate (subway tunnel)   Begin the Hunt               Nia     she talks (voiced lines, subtitles)
## Begin the Hunt fades out and loads main.tscn; the Hunt's drop-in follows as before.
##
## This node also stands in for main.gd for everything player.gd / touch_controls.gd / pause_menu.gd
## ask of it (hud, progression, enemies_root, menu_open, open_pause...).

const PlayerScript = preload("res://scripts/player.gd")
const LairSet = preload("res://scripts/menu/lair_set.gd")
const LairRooms = preload("res://scripts/lair/lair_rooms.gd")
const LairHud = preload("res://scripts/lair/lair_hud.gd")
const LairPanel = preload("res://scripts/lair/lair_panel.gd")
const ProgressionScript = preload("res://scripts/progression.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const MainScript = preload("res://scripts/main.gd")
const Meta = preload("res://scripts/hunt/hunt_meta.gd")
const Cfg = preload("res://scripts/hunt/hunt_config.gd")
const GAME_SCENE := "res://scenes/main.tscn"
const SPAWN := Vector3(1.7, 0.2, 0.7) # in the front bay, looking down the lab toward the fridges
const SPAWN_YAW := PI # facing -Z

## Station framing: camera position, look target, fov, panel side.
const SHOTS := {
	"rack": [Vector3(0.75, 1.8, 0.75), Vector3(3.9, 1.55, 2.45), 50.0, "left"],
	"bench": [Vector3(-0.35, 1.85, -0.85), Vector3(1.55, 0.9, -3.1), 52.0, "right"],
	"mirror": [Vector3(-1.85, 1.3, 0.4), Vector3(0.22, 0.95, 2.64), 40.0, "right"],
	"table": [Vector3(1.25, 1.85, -4.35), Vector3(1.0, 1.45, -6.9), 52.0, "right"],
	"gate": [Vector3(0.1, 1.85, -5.1), Vector3(-2.3, 1.15, -9.6), 54.0, "right"],
}
## What the touch layer shows here (touch_controls.gd): move / look, run, crouch, jump, dash, USE, pause.
var touch_buttons := ["jump", "dash", "sprint", "crouch", "bite", "pause"]
var touch_labels := {"bite": "USE"}

# ---- what player.gd and friends read off "main"
var player: Player
var hud: CanvasLayer
var enemies_root: Node3D
var progression: Progression
var inventory = null
var fx = null
var hunt = null
var started := true
var game_over := false
var lair_pos := Vector3(0, -500, 0) # no bagged-blood drink prompt here
var lair_stock := 0
var pause_menu: CanvasLayer
var ui_block_until := 0

var set_ # lair_set.gd
var rooms # lair_rooms.gd
var panel: PanelContainer
var station := "" # the open station ("" walking)
var near := "" # the station in reach
var cam: Camera3D # the station camera
var hunt_seed := 0
var nia_talks := 0
var leaving := false
var _cam_tw: Tween
var _turn := 0
var _load_threaded := false
var stations_used := {} # tests: station -> times opened
var _pad_a_was := false


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	var m = MainScript.new() # the input map lives in main.gd: borrow its bindings
	m._setup_input()
	m.free()
	hunt_seed = randi() % 1000000
	set_ = LairSet.new()
	set_.name = "LairSet"
	set_.hub_mode = true
	add_child(set_)
	rooms = set_.rooms
	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)
	hud = LairHud.new()
	add_child(hud)
	player = PlayerScript.new()
	player.main = self
	player.peaceful = true
	player.auto_sheathe = true
	player.cam_arm = 3.1
	player.position = SPAWN
	player.facing = SPAWN_YAW
	player.cam_yaw = 0.0 # the camera behind him, looking down -Z
	player.cam_pitch = -0.18
	add_child(player)
	progression = ProgressionScript.new()
	progression.name = "Progression"
	progression.main = self
	progression.persist = false
	add_child(progression)
	_apply_loadout()
	player.hp = player.max_hp
	if player.sheath != null:
		player.sheath.sheathe(true)
	if player.arsenal != null and player.arsenal.get("hud") != null:
		player.arsenal.hud.visible = false # no Weapon Art here
	# a soft warm fill that walks with him, so he reads in the dark bays (no shadows: cheap)
	var fill := OmniLight3D.new()
	fill.name = "SolFill"
	fill.position = Vector3(0.0, 2.3, 0.9)
	fill.light_color = Color(1.0, 0.72, 0.5)
	fill.light_energy = 0.7
	fill.omni_range = 3.2
	fill.omni_attenuation = 1.4
	player.add_child(fill)
	var idle = set_.get_node_or_null("NiaIdle")
	if idle != null:
		idle.face = player
	cam = Camera3D.new()
	cam.name = "StationCam"
	add_child(cam)
	var ui := CanvasLayer.new()
	ui.layer = 12
	add_child(ui)
	panel = LairPanel.new()
	panel.hub = self
	ui.add_child(panel)
	panel.closed.connect(_on_panel_closed)
	panel.begin.connect(begin_hunt)
	panel.changed.connect(_on_changed)
	panel.turn.connect(_turn_sol)
	pause_menu = PauseMenu.new()
	pause_menu.main = self
	add_child(pause_menu)
	Audio.attach_world(self) # AUDIO HOOK: footsteps, the dash
	Audio.set_music("menu")
	hud.set_marks(int(Meta.ensure().sunmarks), Cfg.META_NAME)
	var tw := create_tween()
	tw.tween_property(hud.fade, "color:a", 0.0, 1.2).set_trans(Tween.TRANS_SINE)
	if Meta.return_to_hub:
		Meta.return_to_hub = false
		hud.popup("HOME\nNia has the kettle on")
	print("Daywalker: LAIR_READY")


# ---------------------------------------------------------------- the loadout on Sol
func _apply_loadout() -> void:
	progression.set_outfit(Meta.outfit())
	player.set_weapon_visual(Meta.start_blade())
	player.apply_outfit(Meta.outfit())


func _on_changed(what: String) -> void:
	match what:
		"blade":
			player.set_weapon_visual(Meta.start_blade())
			if rooms != null:
				rooms.refresh_rack()
		"outfit":
			_apply_loadout()
			if rooms != null:
				rooms.refresh_wardrobe()
	hud.set_marks(int(Meta.ensure().sunmarks), Cfg.META_NAME)


# ---------------------------------------------------------------- stations
func _physics_process(_delta: float) -> void:
	if station != "" or leaving or pause_menu.is_open():
		return
	near = _station_in_reach()
	if near == "":
		hud.set_prompt("")
	else:
		var st: Dictionary = LairRooms.STATIONS[near]
		hud.set_prompt("%s   %s   ·   %s" % [hud.key("[A]", "[E]"), st.label, st.verb])
	player.no_jump = near != "" # pad A uses the station instead of jumping
	var pad_a := false
	for d in Input.get_connected_joypads():
		pad_a = pad_a or Input.is_joy_button_pressed(d, JOY_BUTTON_A)
	var a_now := pad_a and not _pad_a_was
	_pad_a_was = pad_a
	if near != "" and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("bite") or a_now) and Time.get_ticks_msec() >= ui_block_until:
		use_station(near)


func _station_in_reach() -> String:
	var p := player.global_position
	var best := ""
	var best_d := INF
	for id in LairRooms.STATIONS:
		var st: Dictionary = LairRooms.STATIONS[id]
		var at: Vector3 = st.pos
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		if d < float(st.radius) and d < best_d:
			best = id
			best_d = d
	return best


## Use a station by id (also the tests' and screenshots' entry point).
func use_station(id: String) -> void:
	stations_used[id] = int(stations_used.get(id, 0)) + 1
	if id == "nia":
		_talk_to_nia()
		return
	if not SHOTS.has(id):
		return
	station = id
	hud.set_walking(false)
	hud.set_prompt("")
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play("ui_click", -3.0, 0.0)
	var shot: Array = SHOTS[id]
	if id == "mirror":
		# Sol steps onto the rug and faces the glass; the camera looks out of the mirror at him
		_turn = 0
		_place_sol(LairRooms.STATIONS.mirror.pos, _mirror_yaw())
		if rooms != null and rooms.mirror != null:
			rooms.mirror.get_parent().visible = false
	elif id == "rack":
		_place_sol(LairRooms.STATIONS.rack.pos, PI * 0.5 - 0.25) # facing the board, the blade on his back on show
	_frame(shot[0], shot[1], shot[2])
	panel.open(id, shot[3])


func _mirror_yaw() -> float:
	var shot: Array = SHOTS.mirror
	var d: Vector3 = shot[0] - LairRooms.STATIONS.mirror.pos
	return atan2(d.x, d.z)


func _place_sol(at: Vector3, yaw: float) -> void:
	player.global_position = Vector3(at.x, player.global_position.y, at.z)
	player.facing = yaw
	if player.visual != null:
		player.visual.rotation.y = yaw


func _frame(pos: Vector3, look: Vector3, fov: float) -> void:
	var from := player.camera.global_transform
	cam.fov = player.camera.fov
	cam.global_transform = from
	cam.current = true
	var to := Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	if _cam_tw != null:
		_cam_tw.kill()
	_cam_tw = create_tween().set_parallel(true)
	_cam_tw.tween_property(cam, "global_transform", to, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tw.tween_property(cam, "fov", fov, 0.55)


## Wardrobe: turn Sol a quarter in the mirror (front, side, back, side).
func _turn_sol() -> void:
	_turn = (_turn + 1) % 4
	var yaw := _mirror_yaw() + _turn * PI * 0.5
	var tw := create_tween()
	tw.tween_method(func(y): _place_sol(player.global_position, y), player.facing, yaw if yaw > player.facing else yaw + TAU, 0.35)


## The wardrobe tabs aim the mirror view at the slot (a hat, the boots...). Kept whole-body: Sol is
## small enough in frame that every slot reads.
func frame_slot(_slot: String) -> void:
	pass


func _on_panel_closed() -> void:
	var was := station
	station = ""
	if rooms != null and rooms.mirror != null:
		rooms.mirror.get_parent().visible = true
	if was == "mirror" or was == "rack":
		player.facing = player.visual.rotation.y
	player.cam_yaw = player.facing + PI # the camera comes back behind him
	if _cam_tw != null:
		_cam_tw.kill()
	var target := player.camera.global_transform
	_cam_tw = create_tween().set_parallel(true)
	_cam_tw.tween_property(cam, "global_transform", target, 0.4).set_trans(Tween.TRANS_SINE)
	_cam_tw.tween_property(cam, "fov", player.camera.fov, 0.4)
	_cam_tw.chain().tween_callback(func():
		if station == "":
			player.camera.current = true)
	player.set_physics_process(true)
	player.block_attack()
	hud.set_walking(true)
	ui_block_until = Time.get_ticks_msec() + 250
	if not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _talk_to_nia() -> void:
	# a voiced exchange from the menu banter, or (every other time) a hint about tonight's target
	nia_talks += 1
	if nia_talks % 2 == 0:
		var boss: Dictionary = HuntDirector.bosses_for(hunt_seed)[0]
		var hint := "lair_hint_" + String(boss.id)
		if Dialogue.has_line(hint):
			Dialogue.play(hint)
			return
	var n := 1 + (nia_talks / 2) % 8
	Dialogue.play("menu_lair_%02da" % n)
	Dialogue.play("menu_lair_%02db" % n)


# ---------------------------------------------------------------- begin the Hunt
func begin_hunt() -> void:
	if leaving:
		return
	leaving = true
	Meta.save_meta()
	HuntDirector.requested = true
	HuntDirector.next_seed = hunt_seed
	MainScript.started_once = true
	Audio.set_music("", 1.0)
	Audio.play("ui_click", -3.0, 0.0)
	hud.set_prompt("")
	var tw := create_tween()
	tw.tween_property(hud.fade, "color:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_load_game)


func _load_game() -> void:
	panel.visible = false
	_load_threaded = not OS.has_feature("web") and OS.get_processor_count() > 1
	if _load_threaded and ResourceLoader.load_threaded_request(GAME_SCENE, "PackedScene", true) == OK:
		return
	_load_threaded = false
	await get_tree().process_frame
	get_tree().change_scene_to_packed(load(GAME_SCENE) as PackedScene)


func _process(_delta: float) -> void:
	if player != null and player.arsenal != null and player.arsenal.get("hud") != null:
		player.arsenal.hud.visible = false # no Weapon Art indicator in the lair
	if not _load_threaded:
		return
	var st := ResourceLoader.load_threaded_get_status(GAME_SCENE)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		_load_threaded = false
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene)
	elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_load_threaded = false
		get_tree().change_scene_to_packed(load(GAME_SCENE) as PackedScene)


func _unhandled_input(event: InputEvent) -> void:
	if station != "" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		panel.close()
	elif station == "" and not leaving and event.is_action_pressed("ui_cancel") and not pause_menu.is_open():
		get_viewport().set_input_as_handled()
		open_pause()


# ---------------------------------------------------------------- main.gd's interface for the player
func menu_open() -> bool:
	return station != "" or leaving or Time.get_ticks_msec() < ui_block_until


func open_pause() -> void:
	if station == "" and not leaving:
		pause_menu.open()


func _on_menu_closed() -> void:
	ui_block_until = Time.get_ticks_msec() + 250


func is_day() -> bool:
	return false


func daylight() -> float:
	return 0.0


func is_full_moon() -> bool:
	return false


func rumble(weak: float, strong: float, seconds: float) -> void:
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, weak, strong, seconds)


func set_slowmo(_scale: float, _real_seconds: float) -> void:
	pass


func clear_slowmo() -> void:
	Engine.time_scale = 1.0


func perfect_dodge() -> void:
	pass


func on_player_died() -> void:
	player.dead = false
	player.hp = player.max_hp


func drink_from_lair() -> void:
	pass


func request_attack_token(_e) -> bool:
	return false


func release_attack_token(_e) -> void:
	pass


func spot_clear(_p: Vector3) -> bool:
	return true


func safe_ground(_near: Vector3) -> Vector3:
	return SPAWN


func ground_y(_x: float, _z: float) -> float:
	return 0.0


func below_world(p: Vector3) -> bool:
	return p.y < -4.0


func _url_flag(_name: String) -> bool:
	return false
