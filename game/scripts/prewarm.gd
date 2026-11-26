extends Node
## PERF: kill first-use hitches before play starts (main.gd calls Prewarm.run at the end of _ready,
## inside the loading frame).
##  1. Resources: every enemy / boss body (130-470 ms each to load on first use: the first camp, the
##     first wolf at dusk and the boss entrance used to freeze for that long), the boss clip
##     libraries and scripts, the SFX streams and the voice lines. References are kept for the run.
##  2. GPU (not headless): WebGL / GLES compile a shader the first time something draws with it, which
##     is the classic stutter when a new material, an enemy or an effect first comes on screen. For
##     a few frames behind an opaque "Preparing" card, one of each body, each unique material in the
##     scene (plain, MultiMesh and skinned variants, with shadows) and each combat effect are drawn
##     right in front of the camera, then freed.

const EnemyScript = preload("res://scripts/enemy.gd")
const BossBase = preload("res://scripts/hunt/bosses/boss_base.gd")
const HFx = preload("res://scripts/hunt/hunt_fx.gd")
const FRAMES := 4

static var _keep: Array = [] # resources held for the run
static var last_report := {}

var main
var _frames := 0
var _holder: Node3D
var _card: CanvasLayer


static func run(main_) -> Node:
	var t0 := Time.get_ticks_msec()
	var n := warm_resources(main_)
	last_report = {"resources": n, "resource_ms": Time.get_ticks_msec() - t0}
	if DisplayServer.get_name() == "headless":
		return null
	var w = load("res://scripts/prewarm.gd").new()
	w.main = main_
	main_.add_child(w)
	return w


static func warm_resources(main_) -> int:
	var n := 0
	for k in EnemyScript.ANIM_PATHS:
		if EnemyScript._model_scene(k) != null:
			n += 1
	for k in BossBase.ANIM_PATHS:
		var ps = BossBase._model_scene(k)
		if ps != null:
			n += 1
	for k in BossBase.BOSS_CLIPS:
		if BossBase._boss_lib(k) != null:
			n += 1
	var h = main_.get("hunt")
	if h != null:
		for d in h.get("night_bosses") if h.get("night_bosses") != null else []:
			if d is Dictionary and d.has("script") and ResourceLoader.exists(d.script):
				_keep.append(load(d.script))
				n += 1
	for p in ["res://scripts/hunt/bosses/field_boss.gd", "res://scripts/hunt/elite.gd"]:
		if ResourceLoader.exists(p):
			_keep.append(load(p))
	var tree: SceneTree = main_.get_tree()
	var audio = tree.root.get_node_or_null("Audio") if tree != null else null
	if audio != null and audio.has_method("stream") and audio.get("SFX") is Dictionary:
		for name in audio.SFX:
			for path in audio.SFX[name]:
				if audio.stream(path) != null:
					n += 1
	var dlg = tree.root.get_node_or_null("Dialogue") if tree != null else null
	if dlg != null and dlg.get("lines") is Dictionary:
		for id in dlg.lines:
			var a = dlg.lines[id].get("audio", "")
			if a is String and a != "" and ResourceLoader.exists(a):
				_keep.append(load(a))
				n += 1
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_card = CanvasLayer.new()
	_card.layer = 126
	add_child(_card)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.012, 0.015, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(bg)
	var l := Label.new()
	l.text = "Preparing the night..."
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.86, 0.68, 0.36))
	bg.add_child(l)
	_build()


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d()


func _build() -> void:
	var t0 := Time.get_ticks_msec()
	_holder = Node3D.new()
	_holder.name = "PrewarmHolder"
	main.add_child(_holder)
	var items: Array[Node3D] = []
	# bodies (skinned meshes, their materials, the per-enemy overlay and eye glow)
	var overlay := StandardMaterial3D.new()
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.albedo_color = Color(1, 1, 1, 0.3)
	var shaded := overlay.duplicate() as StandardMaterial3D
	shaded.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var scenes: Array = []
	for k in EnemyScript.ANIM_PATHS:
		scenes.append(EnemyScript._model_scene(k))
	for k in BossBase.ANIM_PATHS:
		scenes.append(BossBase._model_scene(k))
	var i := 0
	for ps in scenes:
		if ps == null:
			continue
		for variant in 2: # plain, and with the hit-flash / ash overlay pass
			var inst := (ps as PackedScene).instantiate() as Node3D
			if inst == null:
				continue
			_holder.add_child(inst)
			if variant == 1:
				for mi in inst.find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).material_overlay = overlay if i % 2 == 0 else shaded
			items.append(inst)
			i += 1
	# every unique material in the world, plain + MultiMesh, with shadows
	var mats := {}
	for g in main.find_children("*", "GeometryInstance3D", true, false):
		if g is MeshInstance3D:
			var mi := g as MeshInstance3D
			if mi.material_override != null:
				mats[mi.material_override] = g is MeshInstance3D
			if mi.mesh != null:
				for s in mi.mesh.get_surface_count():
					var m := mi.get_active_material(s)
					if m != null:
						mats[m] = true
		elif g is MultiMeshInstance3D:
			var mmi := g as MultiMeshInstance3D
			if mmi.multimesh != null and mmi.multimesh.mesh != null:
				for s in mmi.multimesh.mesh.get_surface_count():
					var m := mmi.multimesh.mesh.surface_get_material(s)
					if mmi.material_override != null:
						m = mmi.material_override
					if m != null and not mats.has(m):
						mats[m] = false # false: draw it through a MultiMesh too
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D())
	mm.set_instance_color(0, Color.WHITE)
	var mat_count := 0
	for m in mats:
		var a := MeshInstance3D.new()
		a.mesh = quad
		a.material_override = m
		_holder.add_child(a)
		items.append(a)
		var b := MultiMeshInstance3D.new()
		b.multimesh = mm
		b.material_override = m
		_holder.add_child(b)
		items.append(b)
		mat_count += 1
	# combat effects: telegraphs, shockwave, blood puff, the health bar
	var fx := Node3D.new()
	_holder.add_child(fx)
	HFx.line_telegraph(fx, Vector3.ZERO, Vector3.FORWARD, 1.0, 0.5, 1.0)
	HFx.circle_telegraph(fx, Vector3.ZERO, 0.5, 1.0)
	HFx.shockwave(fx, Vector3.ZERO, 0.5)
	HFx.puff(fx, Vector3.ZERO, Color(0.55, 0.0, 0.03), 2)
	HFx.aura(fx, Color(1, 0.1, 0.1), 0.5, 1.0)
	var e = EnemyScript.new()
	e.set("main", null)
	e._build_bar()
	if e.hp_bar != null:
		var bar: MeshInstance3D = e.hp_bar
		e.remove_child(bar)
		_holder.add_child(bar)
		items.append(bar)
	e.free()
	items.append(fx)
	# lay them out on a small grid right in front of the camera (all inside the frustum); the
	# holder follows the camera every frame (_process)
	var n := items.size()
	var cols := ceili(sqrt(float(n)))
	for k in n:
		var it := items[k]
		var gx := (k % cols) / float(maxi(cols - 1, 1)) - 0.5
		var gy := (k / cols) / float(maxi(cols - 1, 1)) - 0.5
		var sc := 1.0 if it is GeometryInstance3D else 0.2 # bodies and effect roots are big
		it.transform = Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3(gx * 1.6, gy * 0.9, -2.2))
	_follow()
	last_report["gpu_items"] = n
	last_report["materials"] = mat_count
	last_report["build_ms"] = Time.get_ticks_msec() - t0


func _follow() -> void:
	var cam := _camera()
	if cam != null and _holder != null and is_instance_valid(_holder):
		_holder.global_transform = cam.global_transform


func _process(_d: float) -> void:
	_frames += 1
	_follow()
	if _frames >= FRAMES:
		if _holder != null:
			_holder.queue_free()
		_card.queue_free()
		print("prewarm: %s" % str(last_report))
		queue_free()
