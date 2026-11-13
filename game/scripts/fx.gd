extends Node3D
## Combat effects for Vows, legendary blades and throwables: the Crimson Wake
## dash trail, Crescent Rite wave, Dawnbreaker sunburst, Dawn Flare and the
## rank-up burst. All unshaded additive meshes with shared materials (no lights).

const TRAIL_LIFE := 2.4
const TRAIL_TICK := 0.35
const TRAIL_DMG := 7.0
const TRAIL_MAX := 28

var main
var trail_until := 0.0
var trail_next := 0.0
var trails: Array = [] # [{node, life, tick}]
var waves: Array = [] # [{node, dir, life, hit: {}}]
var clock := 0.0

static var _mats := {}
static var _disc: Mesh
static var _crescent: Mesh
static var _sphere: Mesh
static var _ring: Mesh


static func add_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
		m.albedo_color = c
		_mats[key] = m
	return _mats[key]


func _ready() -> void:
	if _disc == null:
		var d := CylinderMesh.new()
		d.top_radius = 0.55
		d.bottom_radius = 0.55
		d.height = 0.02
		d.radial_segments = 12
		d.rings = 1
		_disc = d
		_crescent = _make_crescent()
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 16
		s.rings = 8
		_sphere = s
		var t := TorusMesh.new()
		t.inner_radius = 0.9
		t.outer_radius = 1.0
		t.rings = 32
		t.ring_segments = 6
		_ring = t


static func _make_crescent() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	for i in n:
		var a0 := lerpf(-1.1, 1.1, float(i) / n)
		var a1 := lerpf(-1.1, 1.1, float(i + 1) / n)
		var w0 := 0.32 * sin(PI * float(i) / n) + 0.02
		var w1 := 0.32 * sin(PI * float(i + 1) / n) + 0.02
		var o0 := Vector3(sin(a0), 0, cos(a0)) * 1.3
		var o1 := Vector3(sin(a1), 0, cos(a1)) * 1.3
		var i0 := Vector3(sin(a0), 0, cos(a0)) * (1.3 - w0)
		var i1 := Vector3(sin(a1), 0, cos(a1)) * (1.3 - w1)
		for v in [i0, o0, o1, i0, o1, i1]:
			st.add_vertex(v)
	return st.commit()


func connect_player(p) -> void:
	p.dashed.connect(_on_dash)
	p.attacked.connect(_on_attack)


func _prog():
	return main.progression


func _on_dash(_dir: Vector3) -> void:
	if _prog().has_flag("blood_trail"):
		trail_until = clock + 0.28


func _on_attack(combo: int, fwd: Vector3) -> void:
	if combo != 3:
		return
	var p = main.player
	if _prog().has_flag("crescent"):
		crescent(p.global_position + Vector3(0, 1.0, 0) + fwd * 0.6, fwd, 18.0 * p.damage_mult())
	if _prog().has_flag("sunburst"):
		sunburst(p.global_position + Vector3(0, 1.0, 0), 5.0, 35.0 * p.damage_mult())


## Hurt enemies in a radius. kinds: -1 any, 0 vampires, 1 Pack. Staggered ones are left for the bite.
func damage_area(center: Vector3, radius: float, amount: float, kinds: int = -1, wolf_scale := 1.0) -> int:
	var n := 0
	for e in main.enemies_root.get_children():
		if e.dead or e.staggered:
			continue
		if kinds >= 0 and e.kind != kinds:
			continue
		var to: Vector3 = e.global_position - center
		to.y = 0.0
		if to.length() > radius:
			continue
		var dmg := amount
		if e.kind == 1:
			if wolf_scale <= 0.0:
				continue
			dmg *= wolf_scale
		e.take_hit(dmg, to.normalized() if to.length() > 0.01 else Vector3.FORWARD)
		n += 1
	return n


func _spawn(mesh: Mesh, c: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = add_mat(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	mi.global_position = pos
	return mi


## Expanding sphere + ground ring that fades out (shared by bursts).
func _burst(pos: Vector3, radius: float, c: Color, time := 0.5) -> void:
	var s := _spawn(_sphere, c, pos)
	s.material_override = add_mat(Color(c.r, c.g, c.b, 0.35)).duplicate()
	s.scale = Vector3.ONE * 0.3
	var r := _spawn(_ring, c, Vector3(pos.x, main.player.global_position.y + 0.08, pos.z))
	r.material_override = add_mat(c).duplicate()
	r.scale = Vector3(0.3, 1.0, 0.3)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE * radius, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(s.material_override, "albedo_color:a", 0.0, time)
	tw.tween_property(r, "scale", Vector3(radius, 1.0, radius), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(r.material_override, "albedo_color:a", 0.0, time * 1.2)
	tw.chain().tween_callback(s.queue_free)
	tw.tween_callback(r.queue_free)


func crescent(pos: Vector3, dir: Vector3, dmg: float) -> void:
	var mi := _spawn(_crescent, Color(1.0, 0.08, 0.12, 0.85), pos)
	mi.basis = Basis(Vector3.UP, atan2(dir.x, dir.z))
	waves.append({"node": mi, "dir": dir, "life": 0.55, "hit": {}, "dmg": dmg})


func sunburst(pos: Vector3, radius: float, dmg: float) -> void:
	_burst(pos, radius, Color(1.0, 0.75, 0.3, 0.8), 0.45)
	damage_area(pos, radius, dmg, 0)


func dawn_flare(pos: Vector3, radius: float, power: float) -> void:
	_burst(pos + Vector3(0, 0.6, 0), radius, Color(0.75, 0.55, 1.0, 0.9), 0.6)
	var hit := damage_area(pos, radius, power, -1, 0.4)
	if main.hud != null:
		main.hud.popup("DAWN FLARE" + ("  ·  %d burned" % hit if hit > 0 else ""))
	main.player.shake = maxf(main.player.shake, 0.2)


func level_burst(pos: Vector3) -> void:
	_burst(pos + Vector3(0, 1.0, 0), 4.0, Color(1.0, 0.7, 0.25, 0.9), 0.8)
	_burst(pos + Vector3(0, 1.0, 0), 2.5, Color(1.0, 0.1, 0.12, 0.9), 0.6)


func _physics_process(delta: float) -> void:
	clock += delta
	var p = main.player
	# Crimson Wake: drop blood pools along the dash
	if clock < trail_until and clock >= trail_next and p != null:
		trail_next = clock + 0.04
		if trails.size() >= TRAIL_MAX:
			trails.pop_front().node.queue_free()
		var mi := _spawn(_disc, Color(0.9, 0.02, 0.05, 0.7), p.global_position + Vector3(0, 0.12, 0))
		mi.material_override = add_mat(Color(0.9, 0.02, 0.05, 0.7)).duplicate()
		trails.append({"node": mi, "life": TRAIL_LIFE, "tick": 0.0})
	for i in range(trails.size() - 1, -1, -1):
		var t: Dictionary = trails[i]
		t.life -= delta
		t.tick -= delta
		if t.tick <= 0.0:
			t.tick = TRAIL_TICK
			damage_area(t.node.global_position, 0.9, TRAIL_DMG)
		(t.node.material_override as StandardMaterial3D).albedo_color.a = clampf(t.life / TRAIL_LIFE, 0.0, 1.0) * 0.7
		if t.life <= 0.0:
			t.node.queue_free()
			trails.remove_at(i)
	for i in range(waves.size() - 1, -1, -1):
		var w: Dictionary = waves[i]
		w.life -= delta
		w.node.global_position += w.dir * 22.0 * delta
		for e in main.enemies_root.get_children():
			if e.dead or e.staggered or w.hit.has(e):
				continue
			var to: Vector3 = e.global_position - w.node.global_position
			to.y = 0.0
			if to.length() < 1.6:
				w.hit[e] = true
				e.take_hit(w.dmg, w.dir)
		if w.life <= 0.0:
			w.node.queue_free()
			waves.remove_at(i)
