extends Node
## PERF: the repeatable benchmark. A fixed Hunt route (fixed seed): the drop-in, a run through
## the open map, a camp fight with ~8 enemies, tonight's boss, the map screen. Per segment it
## records frame time p50 / p95 / p99 / max and spikes, and the per-frame script time of each
## system (player, enemies, bosses, coat sim, director, Curfew ring, HUD, map, audio, ...).
##
## Natively: tests/bench_run.gd (headless --fixed-fps 60 measures pure CPU cost per frame).
## On the web: ?bench (implies ?autohunt); the result is printed as one "BENCH_RESULT {json}" line
## and kept in window.daywalkerBench for Playwright.
##
## How the per-system time is measured without touching anyone's script: every node with a
## script gets its category's process / physics priority, and marker nodes sit at the borders
## between the categories. Godot runs nodes in priority order, so the time between two markers
## is the time that category's callbacks took. Engine nodes (AnimationTree, AnimationPlayer in
## auto mode, ...) keep priority 0 and are measured as "engine" after all the scripts.

signal done(result: Dictionary)

const CATS := ["director", "ring", "poi", "enemy", "boss", "player", "coat", "hud", "map", "audio", "loot", "world", "ui", "other"]
const BASE := -100000
const STEP := 1000

## [name, seconds]
const ROUTE := [["dropin", 5.0], ["roam", 10.0], ["camp", 15.0], ["boss", 15.0], ["map", 4.0]]

var main
var seg := -1
var seg_t := 0.0
var results := {}
var _cur := {}
var _frame_ms := PackedFloat32Array()
var _p_mark := PackedInt64Array()
var _f_mark := PackedInt64Array()
var _markers: Array = []
var _attack_t := 0.0
var _started := false
var _t_start := 0
var _cats_seen := {}


class Marker extends Node:
	var bench
	var idx := 0
	func _process(_d: float) -> void:
		bench._mark_p(idx)
	func _physics_process(_d: float) -> void:
		bench._mark_f(idx)


static func wanted() -> bool:
	if "--bench" in OS.get_cmdline_user_args():
		return true
	if not OS.has_feature("web"):
		return false
	var q := str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
	for part in q.split("&", false):
		if part.split("=")[0] == "bench":
			return true
	return false


func _ready() -> void:
	name = "Bench"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = BASE - 10 # the route driver itself is counted nowhere
	# markers: one before each category (index i at BASE + i * STEP), one before the engine
	# nodes (priority 0) and a last one after everything
	var prios: Array = []
	for i in CATS.size():
		prios.append(BASE + i * STEP)
	prios.append(-1)
	prios.append(1000000)
	_p_mark.resize(prios.size())
	_f_mark.resize(prios.size())
	for i in prios.size():
		var m := Marker.new()
		m.bench = self
		m.idx = i
		m.process_mode = Node.PROCESS_MODE_ALWAYS
		m.process_priority = prios[i]
		m.process_physics_priority = prios[i]
		add_child(m)
		_markers.append(m)
	get_tree().node_added.connect(_on_added)
	for n in get_tree().root.find_children("*", "", true, false):
		_classify(n)
	_t_start = Time.get_ticks_msec()


static func category(n: Node) -> String:
	var sc = n.get_script()
	if sc == null:
		return ""
	var p: String = sc.resource_path
	if p == "" or p.ends_with("bench.gd"):
		return ""
	var f := p.get_file()
	if p.contains("/bosses/"):
		return "boss"
	match f:
		"enemy.gd", "elite.gd": return "enemy"
		"player.gd", "sol_modular_anim.gd", "sword_wrist.gd": return "player"
		"coat_sim.gd": return "coat"
		"hunt_director.gd": return "director"
		"curfew_ring.gd": return "ring"
		"poi.gd", "micro_poi.gd", "poi_spawner.gd": return "poi"
		"hud.gd", "hunt_hud.gd", "compass.gd", "touch_controls.gd": return "hud"
		"map_screen.gd": return "map"
		"audio.gd", "dialogue.gd": return "audio"
		"loot.gd", "fx.gd", "progression.gd", "inventory.gd": return "loot"
		"city.gd", "rain.gd", "atmosphere.gd", "props.gd", "post_fx.gd", "hunt_fx.gd", "deploy.gd": return "world"
	if p.contains("/ui/") or p.contains("/menu/"):
		return "ui"
	return "other"


func _on_added(n: Node) -> void:
	_classify.call_deferred(n) # after the node's own _ready may have set a priority


func _classify(n) -> void:
	if not is_instance_valid(n):
		return
	var c := category(n)
	if c == "":
		return
	var i := CATS.find(c)
	n.process_priority = BASE + i * STEP + 1
	n.process_physics_priority = BASE + i * STEP + 1
	_cats_seen[c] = int(_cats_seen.get(c, 0)) + 1


var _fb := {} # this frame's buckets: "f:<cat>" physics callbacks, "p:<cat>" process callbacks,
# "phys_engine" (physics server step + navigation + queued calls after the physics callbacks),
# "render" (drawing, sync, idle: from the end of _process to the next frame)
var _last_f_end := 0
var _last_p_end := 0
var _sum := {}
var _worst: Array = [] # [[ms, buckets], ...] the slowest frames of the segment


func _add(k: String, us: int) -> void:
	_fb[k] = int(_fb.get(k, 0)) + us


func _mark_f(i: int) -> void:
	var now := Time.get_ticks_usec()
	_f_mark[i] = now
	if i == 0:
		if _last_f_end > _last_p_end:
			_add("phys_engine", now - _last_f_end) # a second physics step this frame
		elif _last_p_end > 0:
			_add("render", now - _last_p_end)
		return
	_add("f:" + (CATS[i - 1] if i <= CATS.size() else "engine"), now - _f_mark[i - 1])
	if i == _f_mark.size() - 1:
		_last_f_end = now


func _mark_p(i: int) -> void:
	var now := Time.get_ticks_usec()
	_p_mark[i] = now
	if i == 0:
		if _last_f_end > _last_p_end:
			_add("phys_engine", now - _last_f_end)
		elif _last_p_end > 0:
			_add("render", now - _last_p_end)
		return
	_add("p:" + (CATS[i - 1] if i <= CATS.size() else "engine"), now - _p_mark[i - 1])
	if i == _p_mark.size() - 1:
		_end_frame(now)


func _end_frame(now: int) -> void:
	if seg >= 0 and _last_p_end > 0:
		var ms := (now - _last_p_end) / 1000.0
		_frame_ms.append(ms)
		for k in _fb:
			_sum[k] = int(_sum.get(k, 0)) + _fb[k]
		if _worst.size() < 5 or ms > _worst[-1][0]:
			var fb := _fb.duplicate()
			fb["mon_nav"] = int(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1e6)
			fb["mon_phys"] = int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1e6)
			fb["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) * 1000
			_worst.append([ms, fb])
			_worst.sort_custom(func(a, b): return a[0] > b[0])
			if _worst.size() > 5:
				_worst.resize(5)
		_cur.draws = float(_cur.get("draws", 0.0)) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_cur.prims = float(_cur.get("prims", 0.0)) + Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_fb = {}
	_last_p_end = now


func _process(delta: float) -> void:
	if main == null or not main.started:
		return
	if not _started:
		_started = true
		print("BENCH: start (hunt ready after %d ms)" % (Time.get_ticks_msec() - _t_start))
		_next_segment()
		return
	seg_t += delta
	_drive(delta)
	if seg_t >= float(ROUTE[seg][1]):
		_close_segment()
		_next_segment()


func _next_segment() -> void:
	seg += 1
	seg_t = 0.0
	_attack_t = 0.0
	_frame_ms = PackedFloat32Array()
	_cur = {}
	_sum = {}
	_worst = []
	if seg >= ROUTE.size():
		_finish()
		return
	_setup(ROUTE[seg][0])


func _release_all() -> void:
	for a in ["move_forward", "sprint", "attack"]:
		Input.action_release(a)


func _setup(s: String) -> void:
	var h = main.hunt
	var p = main.player
	_release_all()
	match s:
		"roam":
			if h != null and h.deploy != null and h.deploy.playing:
				h.deploy.finish()
			Input.action_press("move_forward")
			Input.action_press("sprint")
		"camp":
			if h != null:
				h.debug_view_camp()
			# walk into the camp and make it a crowd of ~8
			_top_up(8)
		"boss":
			_clear()
			if h != null:
				h.debug_skip_to("boss")
		"map":
			_clear()
			if h != null and h.map_screen != null:
				h.map_screen.open()


func _drive(delta: float) -> void:
	var p = main.player
	if p == null:
		return
	p.max_hp = 1e9
	p.hp = 1e9
	var s: String = ROUTE[seg][0]
	match s:
		"roam":
			p.cam_yaw += delta * 0.25 # sweep the view across the city
		"camp", "boss":
			_attack_t -= delta
			if _attack_t <= 0.0:
				_attack_t = 0.35
				if Input.is_action_pressed("attack"):
					Input.action_release("attack")
				else:
					Input.action_press("attack")
			var e = _nearest(p.global_position)
			if e != null:
				var to: Vector3 = e.global_position - p.global_position
				p.cam_yaw = atan2(-to.x, -to.z)
				if s == "camp" and Vector2(to.x, to.z).length() > 2.5:
					Input.action_press("move_forward")
				else:
					Input.action_release("move_forward")
			if s == "camp" and fmod(seg_t, 3.0) < delta:
				_top_up(8)


func _nearest(at: Vector3):
	var best = null
	var bd := INF
	if main.hunt != null and main.hunt.boss != null and is_instance_valid(main.hunt.boss) and not main.hunt.boss.dead:
		return main.hunt.boss
	for e in main.enemies_root.get_children():
		if e.get("dead") == false:
			var d: float = e.global_position.distance_squared_to(at)
			if d < bd:
				bd = d
				best = e
	return best


## Keep `n` living enemies round Sol (6-10 m out), half vampires, half the Pack.
func _top_up(n: int) -> void:
	var p = main.player
	var have := 0
	for e in main.enemies_root.get_children():
		if e.get("dead") == false and e.global_position.distance_to(p.global_position) < 30.0:
			have += 1
	var EnemyScript = load("res://scripts/enemy.gd")
	for i in range(have, n):
		var a := TAU * float(i) / float(n)
		var pos: Vector3 = p.global_position + Vector3(cos(a), 0, sin(a)) * 7.0
		pos = main.safe_ground(pos) + Vector3(0, 0.3, 0)
		var e = EnemyScript.new()
		e.main = main
		e.kind = i % 2
		e.position = pos
		main.enemies_root.add_child(e)


func _clear() -> void:
	for e in main.enemies_root.get_children():
		if e.get("dead") == false and not e.has_method("boss_phase"):
			e.queue_free()


func _close_segment() -> void:
	var s: String = ROUTE[seg][0]
	var n := _frame_ms.size()
	var r := {"frames": n}
	if n > 0:
		var sorted := _frame_ms.duplicate()
		sorted.sort()
		var tot := 0.0
		for v in sorted:
			tot += v
		var med: float = sorted[n / 2]
		var spikes := 0
		var spikes33 := 0
		for v in _frame_ms:
			if v > maxf(med * 2.0, med + 8.0):
				spikes += 1
			if v > 33.4:
				spikes33 += 1
		r.mean = snappedf(tot / n, 0.01)
		r.p50 = snappedf(med, 0.01)
		r.p95 = snappedf(sorted[mini(int(n * 0.95), n - 1)], 0.01)
		r.p99 = snappedf(sorted[mini(int(n * 0.99), n - 1)], 0.01)
		r.max = snappedf(sorted[n - 1], 0.01)
		r.spikes = spikes
		r.over33 = spikes33
		for k in ["draws", "prims"]:
			r[k] = snappedf(float(_cur.get(k, 0.0)) / n, 0.1)
		r.ms = _ms_dict(_sum, n)
		var w := []
		for f in _worst:
			w.append({"ms": snappedf(f[0], 0.01), "top": _ms_dict(f[1], 1, 0.3)})
		r.worst = w
	r.enemies = main.living_enemies()
	results[s] = r
	print("BENCH: %-7s frames %4d  p50 %6.2f  p95 %6.2f  p99 %6.2f  max %6.2f ms  spikes %d  enemies %d" % [s, n, r.get("p50", 0.0), r.get("p95", 0.0), r.get("p99", 0.0), r.get("max", 0.0), r.get("spikes", 0), r.enemies])


## Bucket sums (usec) -> average ms per frame, largest first, dropping the ones under `floor` ms.
static func _ms_dict(d: Dictionary, n: int, floor := 0.005) -> Dictionary:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return d[a] > d[b])
	var out := {}
	for k in keys:
		var v := snappedf(float(d[k]) / 1000.0 / maxf(n, 1), 0.001)
		if v >= floor:
			out[k] = v
	return out


func _finish() -> void:
	_release_all()
	var out := {"segments": results, "tier": _tier_name(), "web": OS.has_feature("web"), "renderer": str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")),
		"seconds": (Time.get_ticks_msec() - _t_start) / 1000.0}
	var js := JSON.stringify(out)
	print("BENCH_RESULT " + js)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.daywalkerBench = " + js + ";", true)
	done.emit(out)
	set_process(false)


func _tier_name() -> String:
	var st = get_node_or_null("/root/Settings")
	if st != null and st.has_method("tier_name"):
		return st.tier_name()
	return "?"
