extends Node3D
## Crows: birds perched round the map (headstones, fences, mausoleum roofs, dead trees, lamp
## posts, rooftops) that scatter when Sol comes close or fights nearby. They burst up with
## fast wingbeats, rise and fan out away from him, cawing, then either glide down onto a
## perch far off or fly out of sight and come back later.
##
## One MultiMesh draws the whole flock (one draw call). The crow is a ~100-triangle low-poly
## mesh; its wings beat in the vertex shader (two-bone wings: shoulder and wrist), they fold
## along the back when perched, and the head turns and pecks. INSTANCE_CUSTOM per crow:
## x wing angle, y spread (0 folded .. 1 open), z head yaw, w head pitch.
##
## Placing perches (any builder, before or after the flock exists):
##   const Crows = preload("res://scripts/world/crows.gd")
##   Crows.add_perch(city, Vector3(x, y, z), yaw)   # during the city build (stored on the host)
##   Crows.spawn(city)                               # once; the flock settles on the next frame
##   city.get_node("Crows").add_perch_now(pos)        # at runtime
## A perch is the point the crow's feet stand on.

const SCARE_R := 5.0 # Sol walking this close sends a crow up
const SCARE_R_RUN := 7.0 # sprinting or dashing is noticed further off
const ATTACK_R := 11.0 # a swing or a hit this close scatters every crow around
const CASCADE_R := 7.0 # a crow taking off startles its neighbours
const MAX_CROWS := 72
const RESPAWN := Vector2(35.0, 80.0) # seconds before a crow that flew off turns up again
const META := "crow_perches"

enum { PERCHED, FLYING, GONE }

class Crow:
	var state := PERCHED
	var pos := Vector3.ZERO
	var yaw := 0.0
	var scale := 1.0
	var perch := -1
	var target := -1
	var vel := Vector3.ZERO
	var t := 0.0 # time in the current state
	var life := 0.0 # flight time before vanishing (no target)
	var flap := 0.0 # wingbeat phase
	var flap_rate := 0.0
	var spread := 0.0
	var wing := 0.0
	var head_yaw := 0.0
	var head_goal := 0.0
	var head_pitch := 0.0
	var idle_t := 1.0
	var hop := 0.0 # hop arc time left
	var hop_from := Vector3.ZERO
	var hop_to := Vector3.ZERO
	var delay := -1.0 # startled, taking off after this
	var away := Vector3.ZERO
	var bank := 0.0
	var respawn_t := 0.0

var perches: Array = [] # [{pos, yaw, busy}]
var crows: Array = []
var mm: MultiMesh
var mmi: MultiMeshInstance3D
var main: Node = null
var player: Node3D = null
var rng := RandomNumberGenerator.new()
var _ready_done := false
var _caw_streams: Array = []
var _flap_stream: AudioStreamWAV
var _players: Array[AudioStreamPlayer3D] = []
var _ambient_t := 6.0
var _connected := false
var takeoffs := 0 # crows that have taken off (tests, debug)


## Register a perch on the host (the city) while it is being built.
static func add_perch(host: Node, pos: Vector3, yaw: float = INF) -> void:
	var list: Array = host.get_meta(META, [])
	list.append([pos, yaw])
	host.set_meta(META, list)


## Register a callable (no arguments, returns [[pos, yaw], ...]) that the flock calls once the
## host is fully built, for perches that only exist after the build (lamps, rooftops).
static func add_provider(host: Node, f: Callable) -> void:
	var list: Array = host.get_meta(META + "_providers", [])
	list.append(f)
	host.set_meta(META + "_providers", list)


## Create the flock under host (once). It settles on its perches on the next frame.
static func spawn(host: Node3D) -> Node3D:
	var n: Node3D = host.get_node_or_null("Crows")
	if n != null:
		return n
	n = load("res://scripts/world/crows.gd").new()
	n.name = "Crows"
	host.add_child(n)
	return n


func add_perch_now(pos: Vector3, yaw: float = INF, occupy := false) -> void:
	perches.append({"pos": pos, "yaw": rng.randf() * TAU if yaw == INF else yaw, "busy": false})
	if occupy and _ready_done and crows.size() < MAX_CROWS:
		_new_crow(perches.size() - 1)


func _ready() -> void:
	rng.seed = 9137
	_build_mesh()


func _setup() -> void:
	_ready_done = true
	var host := get_parent()
	var all: Array = host.get_meta(META, []).duplicate()
	for f: Callable in host.get_meta(META + "_providers", []):
		all.append_array(f.call())
	for p in all:
		perches.append({"pos": p[0], "yaw": rng.randf() * TAU if p[1] == INF else p[1], "busy": false})
	# about half the perches start taken, the rest are landing spots
	var order := range(perches.size())
	order.shuffle()
	for k in order:
		if crows.size() >= MAX_CROWS * 0.8:
			break
		if rng.randf() < 0.55:
			_new_crow(k)
	_build_audio()


func _new_crow(k: int) -> void:
	var c := Crow.new()
	c.scale = rng.randf_range(0.85, 1.12)
	_settle(c, k)
	c.idle_t = rng.randf_range(0.2, 3.0)
	crows.append(c)


func _settle(c: Crow, k: int) -> void:
	c.state = PERCHED
	c.perch = k
	perches[k].busy = true
	c.pos = perches[k].pos
	c.yaw = perches[k].yaw
	c.t = 0.0
	c.spread = 0.0
	c.wing = 0.0
	c.vel = Vector3.ZERO
	c.delay = -1.0
	c.target = -1


# ---------------------------------------------------------------- mesh
## The crow, facing +z, feet at y = 0, ~0.45 m long. COLOR.r: wing span fraction (0 = body),
## COLOR.g: 1 on the head, UV.x: the albedo shade (feathers near-black, beak and legs grey).
func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# body: a loft of hexagonal rings, tail end to neck
	var rings := [[-0.16, 0.026, 0.024, 0.125], [-0.08, 0.06, 0.058, 0.13], [0.03, 0.062, 0.062, 0.14], [0.1, 0.04, 0.042, 0.17]]
	_loft(st, rings, 0.0, 0.05)
	var head := [[0.09, 0.03, 0.03, 0.2], [0.13, 0.046, 0.046, 0.215], [0.18, 0.03, 0.032, 0.215]]
	_loft(st, head, 1.0, 0.07)
	# beak
	var bk := [Vector3(-0.016, 0.21, 0.175), Vector3(0.016, 0.21, 0.175), Vector3(0, 0.226, 0.175), Vector3(0, 0.196, 0.177)]
	var tip := Vector3(0, 0.205, 0.255)
	for k in 4:
		var a: Vector3 = bk[[0, 2, 1, 3][k]]
		var b: Vector3 = bk[[2, 1, 3, 0][k]]
		_tri(st, a, b, tip, 0.0, 1.0, 0.25)
	# eyes catch a glint: tiny grey quads either side
	for sx in [-1.0, 1.0]:
		_quad(st, Vector3(sx * 0.044, 0.225, 0.14), Vector3(sx * 0.044, 0.235, 0.15), Vector3(sx * 0.044, 0.225, 0.16), Vector3(sx * 0.044, 0.215, 0.15), 0.0, 1.0, 0.6)
	# tail: a fan of two flat wedges
	for sy in [0.0, 0.006]:
		_quad(st, Vector3(-0.02, 0.125 + sy, -0.15), Vector3(0.02, 0.125 + sy, -0.15), Vector3(0.055, 0.1 + sy, -0.32), Vector3(-0.055, 0.1 + sy, -0.32), 0.0, 0.0, 0.08)
	# legs and toes
	for sx in [-1.0, 1.0]:
		var hip := Vector3(sx * 0.025, 0.1, 0.0)
		var foot := Vector3(sx * 0.028, 0.0, 0.02)
		_quad(st, hip + Vector3(-0.006, 0, 0), hip + Vector3(0.006, 0, 0), foot + Vector3(0.006, 0, 0), foot + Vector3(-0.006, 0, 0), 0.0, 0.0, 0.2)
		_quad(st, foot + Vector3(-0.012, 0.002, 0.04), foot + Vector3(0.012, 0.002, 0.04), foot + Vector3(0.006, 0.002, -0.02), foot + Vector3(-0.006, 0.002, -0.02), 0.0, 0.0, 0.2)
	# wings: two segments each (shoulder to wrist, wrist to tip); flat, double-sided
	for sx in [-1.0, 1.0]:
		var y := 0.155
		var pts := [
			[0.03, 0.07, -0.06], [0.2, 0.07, -0.1], [0.42, 0.02, -0.06],
		]
		# leading edge z at each span station, trailing edge z
		var lead := [0.07, 0.07, 0.02]
		var trail := [-0.07, -0.11, -0.06]
		var span := [0.03, 0.2, 0.43]
		for k in 2:
			var x0: float = span[k]
			var x1: float = span[k + 1]
			var f0 := (x0 - 0.03) / 0.4
			var f1 := (x1 - 0.03) / 0.4
			var a := Vector3(sx * x0, y, lead[k])
			var b := Vector3(sx * x1, y, lead[k + 1])
			var d := Vector3(sx * x1, y, trail[k + 1])
			var e := Vector3(sx * x0, y, trail[k])
			st.set_normal(Vector3.UP)
			for v in [[a, f0], [b, f1], [d, f1], [a, f0], [d, f1], [e, f0]]:
				st.set_color(Color(maxf(v[1], 0.001), 0, 0))
				st.set_uv(Vector2(0.06, 0))
				st.add_vertex(v[0])
		# primary feathers: ragged fingers past the wrist
		for f in 4:
			var z0 := 0.0 - f * 0.022
			var a := Vector3(sx * 0.36, y, z0 + 0.012)
			var b := Vector3(sx * (0.47 - f * 0.012), y, z0 - 0.01)
			var d := Vector3(sx * 0.36, y, z0 - 0.012)
			st.set_normal(Vector3.UP)
			for v in [[a, 0.83], [b, 1.0], [d, 0.83]]:
				st.set_color(Color(v[1], 0, 0))
				st.set_uv(Vector2(0.05, 0))
				st.add_vertex(v[0])
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHADER
	mesh.surface_set_material(0, mat)
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = MAX_CROWS
	mm.visible_instance_count = 0
	mmi = MultiMeshInstance3D.new()
	mmi.name = "Flock"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-600, -50, -600), Vector3(1200, 300, 1200))
	add_child(mmi)


func _loft(st: SurfaceTool, rings: Array, head: float, shade: float) -> void:
	var n := 6
	for r in rings.size() - 1:
		var a: Array = rings[r]
		var b: Array = rings[r + 1]
		for k in n:
			var t0 := TAU * k / n
			var t1 := TAU * (k + 1) / n
			var p00 := Vector3(cos(t0) * a[1], a[3] + sin(t0) * a[2], a[0])
			var p01 := Vector3(cos(t1) * a[1], a[3] + sin(t1) * a[2], a[0])
			var p10 := Vector3(cos(t0) * b[1], b[3] + sin(t0) * b[2], b[0])
			var p11 := Vector3(cos(t1) * b[1], b[3] + sin(t1) * b[2], b[0])
			_quad(st, p00, p10, p11, p01, 0.0, head, shade)
	# caps
	for r in [0, rings.size() - 1]:
		var a: Array = rings[r]
		var ctr := Vector3(0, a[3], a[0] + (-0.01 if r == 0 else 0.01))
		for k in n:
			var t0 := TAU * k / n
			var t1 := TAU * (k + 1) / n
			_tri(st, Vector3(cos(t0) * a[1], a[3] + sin(t0) * a[2], a[0]), Vector3(cos(t1) * a[1], a[3] + sin(t1) * a[2], a[0]), ctr, 0.0, head, shade)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, d: Vector3, wing: float, head: float, shade: float) -> void:
	var nrm := (b - a).cross(d - a).normalized()
	var ctr := Vector3(0, 0.15, 0.0)
	if nrm.dot((a + b + d) / 3.0 - ctr) < 0.0:
		var t := b
		b = d
		d = t
		nrm = -nrm
	st.set_normal(nrm)
	st.set_color(Color(wing, head, 0))
	st.set_uv(Vector2(shade, 0))
	# Godot's front faces are clockwise seen from outside
	st.add_vertex(a)
	st.add_vertex(d)
	st.add_vertex(b)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, d: Vector3, e: Vector3, wing: float, head: float, shade: float) -> void:
	_tri(st, a, b, d, wing, head, shade)
	_tri(st, a, d, e, wing, head, shade)


const SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying float shade;
vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}
void vertex() {
	vec4 cu = INSTANCE_CUSTOM;
	shade = UV.x;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	if (COLOR.r > 0.0) {
		float sx = sign(v.x);
		float ax = abs(v.x);
		float a = cu.x;
		// open wing: shoulder at x 0.03, wrist at x 0.2 (the hand bends further)
		vec2 sh = vec2(0.03, 0.155);
		vec2 q;
		if (ax <= 0.2) {
			q = sh + rot(vec2(ax - 0.03, v.y - 0.155), a);
		} else {
			vec2 wr = sh + rot(vec2(0.17, 0.0), a);
			q = wr + rot(vec2(ax - 0.2, v.y - 0.155), a * 1.55);
		}
		vec3 open = vec3(sx * q.x, q.y, v.z);
		vec2 nn = rot(vec2(0.0, 1.0), ax <= 0.2 ? a : a * 1.55);
		vec3 open_n = vec3(sx * nn.x, nn.y, 0.0);
		// folded: the wing lies along the back, the tip reaching past the tail
		float f = COLOR.r;
		vec3 fold = vec3(sx * (0.052 - f * 0.02), 0.165 + f * 0.012 - (v.z + 0.06) * 0.08, 0.05 - f * 0.34 + v.z * 0.35);
		v = mix(fold, open, cu.y);
		n = normalize(mix(vec3(sx * 0.7, 0.7, 0.0), open_n, cu.y));
	} else if (COLOR.g > 0.5) {
		vec3 pv = vec3(0.0, 0.19, 0.1);
		vec3 d = v - pv;
		d.yz = rot(d.yz, -cu.w);
		d.xz = rot(d.xz, cu.z);
		v = pv + d;
		n.yz = rot(n.yz, -cu.w);
		n.xz = rot(n.xz, cu.z);
	}
	VERTEX = v;
	NORMAL = n;
}
void fragment() {
	vec3 c = vec3(shade) * vec3(0.9, 0.95, 1.05);
	ALBEDO = c;
	ROUGHNESS = shade > 0.15 ? 0.6 : 0.42;
	SPECULAR = 0.55;
	// the blue-black sheen of crow feathers at grazing angles
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.02, 0.03, 0.06) * fr;
}
"""


# ---------------------------------------------------------------- audio (synthesised)
func _build_audio() -> void:
	for k in 3:
		_caw_streams.append(_caw(k))
	_flap_stream = _flaps()
	for k in 5:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 7.0
		p.max_distance = 70.0
		p.attenuation_filter_cutoff_hz = 9000.0
		add_child(p)
		_players.append(p)


static func _wav(data: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = bytes
	return s


## A hoarse crow caw: a buzzy sawtooth gliding down, rasped by noise and a fast tremolo,
## pushed through a crude nasal formant. Variant k: one, two or three caws.
func _caw(k: int) -> AudioStreamWAV:
	var rate := 22050
	var r := RandomNumberGenerator.new()
	r.seed = 501 + k
	var n_caws := [1, 2, 3][k]
	var one := 0.3
	var gap := 0.14
	var total := int((n_caws * (one + gap) + 0.1) * rate)
	var out := PackedFloat32Array()
	out.resize(total)
	var lp := 0.0
	var bp_a := 0.0
	var bp_b := 0.0
	for c in n_caws:
		var f0 := r.randf_range(560.0, 680.0)
		var start := int(c * (one + gap) * rate)
		var len := int(one * r.randf_range(0.85, 1.1) * rate)
		var ph := 0.0
		for i in len:
			var t := float(i) / rate
			var u := float(i) / len
			var f := f0 * (1.08 - 0.32 * u) * (1.0 + 0.03 * sin(t * TAU * 31.0))
			ph = fmod(ph + f / rate, 1.0)
			var saw := ph * 2.0 - 1.0
			var x := saw * 0.7 + r.randf_range(-1.0, 1.0) * 0.35
			x *= 0.65 + 0.35 * sin(t * TAU * 72.0)
			# formant around 1.4 kHz: difference of two low-passes
			bp_a += (x - bp_a) * 0.42
			bp_b += (bp_a - bp_b) * 0.12
			lp = bp_a - bp_b * 0.85
			var env := minf(1.0, u / 0.06) * pow(1.0 - u, 0.6)
			out[start + i] += lp * env * 0.9
	return _wav(out, rate)


## A burst of wingbeats: soft noise whumps, fast then easing off.
func _flaps() -> AudioStreamWAV:
	var rate := 22050
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var total := int(1.1 * rate)
	var out := PackedFloat32Array()
	out.resize(total)
	var lp := 0.0
	var lp2 := 0.0
	var t_beat := 0.0
	var beat := 0
	while t_beat < 1.0:
		var start := int(t_beat * rate)
		var len := int(0.075 * rate)
		var amp := 0.95 * pow(1.0 - t_beat, 0.7)
		for i in len:
			if start + i >= total:
				break
			var u := float(i) / len
			var x := r.randf_range(-1.0, 1.0)
			lp += (x - lp) * 0.22
			lp2 += (lp - lp2) * 0.3
			var env := sin(u * PI) * amp
			out[start + i] += lp2 * env * 2.2
		beat += 1
		t_beat += 0.085 + beat * 0.006
	return _wav(out, rate)


func _sound(stream: AudioStream, pos: Vector3, db: float) -> void:
	if stream == null or _players.is_empty():
		return
	var audio := get_node_or_null("/root/Audio")
	if audio != null and not audio.unlocked:
		return
	var best: AudioStreamPlayer3D = _players[0]
	for p in _players:
		if not p.playing:
			best = p
			break
	best.global_position = pos
	best.stream = stream
	best.volume_db = db
	best.pitch_scale = rng.randf_range(0.9, 1.12)
	best.play()


# ---------------------------------------------------------------- behaviour
func _find_player() -> void:
	if main == null:
		var n: Node = get_parent()
		while n != null and n.get("player") == null:
			n = n.get_parent()
		main = n
	if main != null:
		player = main.get("player")
		if player != null and not _connected and player.has_signal("attacked"):
			player.attacked.connect(_on_player_attacked)
			if player.has_signal("hit_enemy"):
				player.hit_enemy.connect(func(_e, _d): scare_at(player.global_position, ATTACK_R))
			_connected = true


func _on_player_attacked(_combo: int, _fwd: Vector3) -> void:
	if player != null:
		scare_at(player.global_position, ATTACK_R)


## Startle every perched crow within r of pos (a fight, an explosion, a door slam).
func scare_at(pos: Vector3, r: float) -> void:
	for c: Crow in crows:
		if c.state == PERCHED and c.delay < 0.0 and c.pos.distance_to(pos) < r:
			c.delay = rng.randf_range(0.0, 0.35)
			c.away = c.pos - pos


func _process(delta: float) -> void:
	if not _ready_done:
		_setup()
	if player == null or not is_instance_valid(player):
		player = null
		_find_player()
	var dt := minf(delta, 0.05)
	var pp := Vector3(0, -1000, 0)
	var run := false
	if player != null:
		pp = player.global_position
		var v = player.get("velocity")
		run = v is Vector3 and Vector2(v.x, v.z).length() > 6.5
	var scare := SCARE_R_RUN if run else SCARE_R
	for c: Crow in crows:
		match c.state:
			PERCHED:
				_perched(c, dt, pp, scare)
			FLYING:
				_flying(c, dt, pp)
			GONE:
				c.respawn_t -= dt
				if c.respawn_t <= 0.0:
					_respawn(c, pp)
	_ambient(dt, pp)
	_upload()


func _perched(c: Crow, dt: float, pp: Vector3, scare: float) -> void:
	c.t += dt
	var d := c.pos.distance_to(pp)
	if c.delay < 0.0 and d < scare and c.t > 0.6:
		c.delay = rng.randf_range(0.0, 0.12)
		c.away = c.pos - pp
	if c.delay >= 0.0:
		c.delay -= dt
		c.head_goal = 0.0
		if c.delay < 0.0:
			_take_off(c, pp)
		return
	# idle: look about, peck, shuffle round, hop to face somewhere else, ruffle the wings
	c.idle_t -= dt
	if c.idle_t <= 0.0:
		var roll := rng.randf()
		if roll < 0.45:
			c.head_goal = rng.randf_range(-1.1, 1.1)
			c.idle_t = rng.randf_range(0.5, 2.2)
		elif roll < 0.62:
			c.head_pitch = 0.9 # a peck
			c.idle_t = rng.randf_range(0.4, 1.0)
		elif roll < 0.8:
			c.hop = 0.28
			c.hop_from = c.pos
			var base: Vector3 = perches[c.perch].pos
			c.hop_to = base + Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
			c.yaw += rng.randf_range(-1.6, 1.6)
			c.idle_t = rng.randf_range(0.8, 2.5)
		elif roll < 0.9:
			c.spread = 0.35 # a ruffle
			c.idle_t = rng.randf_range(1.0, 3.0)
		else:
			# keep an eye on Sol when he is about
			if d < 25.0:
				var to := pp - c.pos
				c.yaw = atan2(to.x, to.z) + rng.randf_range(-0.6, 0.6)
			c.idle_t = rng.randf_range(1.0, 3.0)
	c.head_yaw = lerpf(c.head_yaw, c.head_goal, minf(1.0, dt * 12.0))
	c.head_pitch = maxf(0.0, c.head_pitch - dt * 3.5)
	c.spread = maxf(0.0, c.spread - dt * 1.2)
	c.wing = sin(c.t * 30.0) * 0.25 * c.spread
	if c.hop > 0.0:
		c.hop -= dt
		var u := 1.0 - maxf(c.hop, 0.0) / 0.28
		c.pos = c.hop_from.lerp(c.hop_to, u) + Vector3(0, sin(u * PI) * 0.09, 0)
		c.spread = maxf(c.spread, 0.25 * sin(u * PI))


func _take_off(c: Crow, pp: Vector3) -> void:
	takeoffs += 1
	if c.perch >= 0:
		perches[c.perch].busy = false
	c.perch = -1
	c.state = FLYING
	c.t = 0.0
	var away := Vector3(c.away.x, 0, c.away.z)
	if away.length() < 0.1:
		away = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
	away = away.normalized().rotated(Vector3.UP, rng.randf_range(-0.9, 0.9))
	c.away = away
	c.vel = away * rng.randf_range(2.0, 3.5) + Vector3(0, rng.randf_range(3.5, 5.0), 0)
	c.flap_rate = rng.randf_range(9.0, 11.0)
	c.life = rng.randf_range(6.0, 9.0)
	c.target = -1
	if rng.randf() < 0.6:
		c.target = _pick_perch(c.pos, pp, c.away)
		if c.target >= 0:
			perches[c.target].busy = true
	if rng.randf() < 0.55:
		_sound(_caw_streams[rng.randi() % _caw_streams.size()], c.pos, -4.0)
	if rng.randf() < 0.7:
		_sound(_flap_stream, c.pos, -6.0)
	# the flock goes up together, a beat apart
	for o: Crow in crows:
		if o != c and o.state == PERCHED and o.delay < 0.0 and o.pos.distance_to(c.pos) < CASCADE_R:
			o.delay = rng.randf_range(0.08, 0.45)
			o.away = o.pos - pp


## A free perch well away from Sol, preferably ahead of the crow's flight.
func _pick_perch(from: Vector3, pp: Vector3, dir: Vector3) -> int:
	var best := -1
	var best_s := -INF
	for k in perches.size():
		var p: Dictionary = perches[k]
		if p.busy:
			continue
		var d: float = from.distance_to(p.pos)
		if d < 22.0 or d > 90.0 or pp.distance_to(p.pos) < 28.0:
			continue
		var s: float = (p.pos - from).normalized().dot(dir) * 2.0 + rng.randf() - d * 0.01
		if s > best_s:
			best_s = s
			best = k
	return best


func _flying(c: Crow, dt: float, pp: Vector3) -> void:
	c.t += dt
	var want: Vector3
	var landing := false
	if c.t < 1.1:
		# the burst: climb hard, away from Sol
		want = c.away * 5.0 + Vector3(0, 4.5, 0)
	elif c.target >= 0:
		var tp: Vector3 = perches[c.target].pos
		var to := tp - c.pos
		var flat := Vector2(to.x, to.z).length()
		if flat > 9.0:
			var cruise := maxf(tp.y, 0.0) + 7.0
			want = Vector3(to.x, 0, to.z).normalized() * 7.5 + Vector3(0, clampf(cruise - c.pos.y, -2.0, 2.5), 0)
		else:
			landing = true
			want = to.normalized() * clampf(to.length() * 1.3, 1.2, 6.0)
			if to.length() < 0.25:
				_settle(c, c.target)
				c.yaw = atan2(c.vel.x, c.vel.z)
				perches[c.perch].yaw = c.yaw
				return
	else:
		want = c.away * 7.0 + Vector3(0, 2.0, 0)
		if c.t > c.life:
			_vanish(c)
			return
	var steer := 3.5 if landing else 2.2
	c.vel = c.vel.lerp(want, minf(1.0, dt * steer))
	c.pos += c.vel * dt
	if c.pos.y < 0.3 and not landing:
		c.pos.y = 0.3
		c.vel.y = absf(c.vel.y)
	# wingbeats: hard in the climb, gliding stretches in cruise, braking flaps when landing
	var climb := c.vel.y
	var glide := c.t > 1.6 and not landing and climb < 0.6 and sin(c.t * 0.9 + c.scale * 9.0) > 0.35
	var rate := c.flap_rate if c.t < 1.6 or landing else 7.0
	if glide:
		c.wing = lerpf(c.wing, 0.12, minf(1.0, dt * 6.0))
	else:
		c.flap += dt * rate * TAU
		c.wing = sin(c.flap) * (0.95 if c.t < 1.6 or landing else 0.75) + 0.12
	c.spread = minf(1.0, c.spread + dt * 8.0)
	var hv := Vector2(c.vel.x, c.vel.z)
	if hv.length() > 0.3:
		var ny := atan2(c.vel.x, c.vel.z)
		var dy := wrapf(ny - c.yaw, -PI, PI)
		c.yaw += dy * minf(1.0, dt * 5.0)
		c.bank = lerpf(c.bank, clampf(-dy * 2.0, -0.7, 0.7), minf(1.0, dt * 4.0))
	c.head_yaw = lerpf(c.head_yaw, 0.0, minf(1.0, dt * 8.0))
	c.head_pitch = 0.0


func _vanish(c: Crow) -> void:
	c.state = GONE
	c.respawn_t = rng.randf_range(RESPAWN.x, RESPAWN.y)


func _respawn(c: Crow, pp: Vector3) -> void:
	var tries := 12
	while tries > 0:
		tries -= 1
		var k := rng.randi() % maxi(perches.size(), 1)
		if perches.is_empty():
			return
		if not perches[k].busy and perches[k].pos.distance_to(pp) > 35.0:
			_settle(c, k)
			return
	c.respawn_t = 10.0


func _ambient(dt: float, pp: Vector3) -> void:
	_ambient_t -= dt
	if _ambient_t > 0.0:
		return
	_ambient_t = rng.randf_range(7.0, 18.0)
	var best: Crow = null
	var bd := 40.0
	for c: Crow in crows:
		if c.state == PERCHED:
			var d := c.pos.distance_to(pp)
			if d < bd and d > 6.0:
				bd = d
				best = c
	if best != null:
		best.head_pitch = -0.5
		best.spread = 0.3
		_sound(_caw_streams[rng.randi() % _caw_streams.size()], best.pos, -9.0)


func _upload() -> void:
	var n := 0
	for c: Crow in crows:
		if c.state == GONE:
			continue
		var b := Basis(Vector3.UP, c.yaw)
		if c.state == FLYING:
			var pitch := clampf(-c.vel.y * 0.08, -0.6, 0.5)
			b = b * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, c.bank)
		b = b.scaled(Vector3.ONE * c.scale)
		mm.set_instance_transform(n, Transform3D(b, c.pos))
		mm.set_instance_custom_data(n, Color(c.wing, c.spread, c.head_yaw, c.head_pitch))
		n += 1
	mm.visible_instance_count = n


# ---------------------------------------------------------------- queries (tests, captures)
func perched_count() -> int:
	var n := 0
	for c: Crow in crows:
		if c.state == PERCHED:
			n += 1
	return n


## The perched crow nearest p: {pos, index} or {}.
func nearest_perched(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for k in crows.size():
		var c: Crow = crows[k]
		if c.state == PERCHED and c.delay < 0.0:
			var d := c.pos.distance_to(p)
			if d < bd:
				bd = d
				best = {"pos": c.pos, "index": k}
	return best


func crow_state(k: int) -> Dictionary:
	var c: Crow = crows[k]
	return {"state": ["perched", "flying", "gone"][c.state], "pos": c.pos}
