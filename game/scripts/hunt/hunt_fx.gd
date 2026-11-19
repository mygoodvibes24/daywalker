extends RefCounted
## Cheap shared looks for the Hunt: fresnel auras, ground telegraphs, shockwaves and puffs.
## All unshaded + additive, no lights, shared materials where possible (web-friendly).

const U = preload("res://scripts/util.gd")

const AURA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float strength = 1.0;
uniform float power = 2.2;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	float wave = 0.7 + 0.3 * sin(TIME * 4.0 + UV.y * 24.0 + UV.x * 6.2831);
	ALBEDO = color.rgb * f * strength * wave;
	ALPHA = clamp(f * strength, 0.0, 1.0);
}
"""

static var _aura_shader: Shader
static var _aura_mats := {}
static var _sphere: SphereMesh
static var _disc: CylinderMesh
static var _ring: TorusMesh
static var _box: BoxMesh
static var _flat_mats := {}
## Floor decals made by circle_telegraph / line_telegraph (the smoke test checks that common enemies
## make none: they telegraph with the body instead, see enemy.gd _tell()).
static var decals := 0
static var _glint_mat: StandardMaterial3D
static var _glint_mesh: QuadMesh
static var _blood_mat: StandardMaterial3D
static var _blood_mesh: QuadMesh
static var _soft_mats := {}


static func aura_mat(c: Color, strength := 1.0) -> ShaderMaterial:
	var key := "%s_%.2f" % [c.to_html(), strength]
	if _aura_mats.has(key):
		return _aura_mats[key]
	if _aura_shader == null:
		_aura_shader = Shader.new()
		_aura_shader.code = AURA_SHADER
	var m := ShaderMaterial.new()
	m.shader = _aura_shader
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("strength", strength)
	_aura_mats[key] = m
	return m


## A fresnel shell around a body: `height` metres tall, `width` across.
static func aura(parent: Node3D, c: Color, width: float, height: float, strength := 1.0) -> MeshInstance3D:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_sphere.radial_segments = 16
		_sphere.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere
	mi.material_override = aura_mat(c, strength)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(width, height, width)
	mi.position.y = height * 0.5
	parent.add_child(mi)
	return mi


## Unshaded additive colour (shared per colour).
static func flat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _flat_mats.has(key):
		return _flat_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = c
	_flat_mats[key] = m
	return m


static func disc_mesh() -> CylinderMesh:
	if _disc == null:
		_disc = CylinderMesh.new()
		_disc.top_radius = 1.0
		_disc.bottom_radius = 1.0
		_disc.height = 0.02
		_disc.radial_segments = 32
		_disc.rings = 1
	return _disc


static func ring_mesh() -> TorusMesh:
	if _ring == null:
		_ring = TorusMesh.new()
		_ring.inner_radius = 0.92
		_ring.outer_radius = 1.0
		_ring.rings = 40
		_ring.ring_segments = 4
	return _ring


static func box_mesh() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	return _box


static func _mi(parent: Node, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A ground circle telegraph: outline + a fill that grows over `seconds`. Frees itself after.
## TERRAIN HOOK: ground height (map/terrain.gd; 0 on the city plates).
static func _gy(p: Vector3) -> float:
	return preload("res://scripts/map/terrain.gd").height_at(p.x, p.z)


static func circle_telegraph(parent: Node, pos: Vector3, radius: float, seconds: float, c := Color(1.0, 0.1, 0.05)) -> Node3D:
	decals += 1
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = Vector3(pos.x, _gy(pos) + 0.12, pos.z) # TERRAIN HOOK
	var edge := _mi(root, ring_mesh(), flat(Color(c.r, c.g, c.b, 0.9)))
	edge.scale = Vector3(radius, 1.0, radius)
	var fill := _mi(root, disc_mesh(), flat(Color(c.r * 0.45, c.g * 0.45, c.b * 0.45, 0.28)))
	fill.scale = Vector3(0.05, 1.0, 0.05)
	var tw := root.create_tween()
	tw.tween_property(fill, "scale", Vector3(radius, 1.0, radius), maxf(seconds, 0.05))
	tw.tween_callback(root.queue_free)
	return root


## A line telegraph from `from` along `dir` for `length` m, `width` wide.
static func line_telegraph(parent: Node, from: Vector3, dir: Vector3, length: float, width: float, seconds: float, c := Color(1.0, 0.1, 0.1)) -> Node3D:
	decals += 1
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = Vector3(from.x, _gy(from) + 0.13, from.z) # TERRAIN HOOK
	root.rotation.y = atan2(dir.x, dir.z)
	var bar := _mi(root, box_mesh(), flat(Color(c.r, c.g, c.b, 0.55)))
	bar.scale = Vector3(width, 0.02, 0.1)
	bar.position.z = 0.05
	var tw := root.create_tween()
	tw.tween_property(bar, "scale", Vector3(width, 0.02, length), maxf(seconds * 0.6, 0.05))
	tw.parallel().tween_property(bar, "position:z", length * 0.5, maxf(seconds * 0.6, 0.05))
	tw.tween_interval(seconds * 0.4)
	tw.tween_callback(root.queue_free)
	return root


## An expanding ring on the ground (a slam landing, a howl, a deployment slam).
static func shockwave(parent: Node, pos: Vector3, radius: float, c := Color(1.0, 0.25, 0.1), seconds := 0.45) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = Vector3(pos.x, _gy(pos) + 0.15, pos.z) # TERRAIN HOOK
	var r := _mi(root, ring_mesh(), flat(Color(c.r, c.g, c.b, 0.9)))
	r.scale = Vector3(0.3, 1.0, 0.3)
	var tw := root.create_tween()
	tw.tween_property(r, "scale", Vector3(radius, 3.0, radius), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(root, "position:y", 0.4, seconds)
	tw.tween_callback(root.queue_free)


## A burst of glowing blood droplets / mist (blink, death, deploy dust).
static func puff(parent: Node, pos: Vector3, c := Color(0.8, 0.02, 0.05), count := 10, size := 0.18, spread := 2.5) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var m := flat(Color(c.r, c.g, c.b, 0.8))
	var tw := root.create_tween().set_parallel(true)
	for i in count:
		var s := _mi(root, U.sphere(size), m)
		var a := TAU * i / float(count) + randf() * 0.5
		var to := Vector3(cos(a) * spread, randf_range(0.2, 1.8), sin(a) * spread) * randf_range(0.5, 1.0)
		tw.tween_property(s, "position", to, 0.5).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "scale", Vector3.ZERO, 0.6)
	tw.chain().tween_callback(root.queue_free)


# ---------------------------------------------------------------- body-language tells and impacts
## A soft, dark ground cue (a shadow, not a raid marker): only the big area attacks use it (the
## wolf's pounce landing, a boss slam). Alpha-blended dark disc with a faint dim rim, fading in.
static func soft_ground_cue(parent: Node, pos: Vector3, radius: float, seconds: float, rim := Color(0.55, 0.06, 0.04)) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = Vector3(pos.x, _gy(pos) + 0.06, pos.z) # TERRAIN HOOK
	var key := "shadow"
	if not _soft_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.55))
		g.set_color(1, Color(0, 0, 0, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		m.albedo_texture = gt
		_soft_mats[key] = m
	var q := PlaneMesh.new()
	q.size = Vector2(2.0, 2.0)
	var disc := MeshInstance3D.new()
	disc.mesh = q
	var dm := (_soft_mats[key] as StandardMaterial3D).duplicate() as StandardMaterial3D
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.scale = Vector3(radius, 1.0, radius)
	root.add_child(disc)
	var edge := _mi(root, ring_mesh(), flat(Color(rim.r, rim.g, rim.b, 0.0)))
	var em := (edge.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	edge.material_override = em
	edge.scale = Vector3(radius, 0.4, radius)
	var tw := root.create_tween().set_parallel(true)
	dm.albedo_color = Color(1, 1, 1, 0.0)
	tw.tween_property(dm, "albedo_color:a", 1.0, maxf(seconds * 0.8, 0.05)).set_ease(Tween.EASE_IN)
	tw.tween_property(em, "albedo_color:a", 0.22, maxf(seconds, 0.05)).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(root.queue_free)
	return root


## A brief star glint (an eye or a blade catching the light): an additive billboard that pops up
## and fades out over `seconds`, parented to `parent` (a bone attachment, so it follows the head).
static func glint(parent: Node3D, local_pos: Vector3, c := Color(1.0, 0.25, 0.15), size := 0.22, seconds := 0.22) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	if _glint_mesh == null:
		_glint_mesh = QuadMesh.new()
		_glint_mesh.size = Vector2.ONE
		_glint_mat = StandardMaterial3D.new()
		_glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_glint_mat.no_depth_test = true
		_glint_mat.vertex_color_use_as_albedo = false
		_glint_mat.albedo_texture = _star_texture()
		_glint_mat.render_priority = 3
	var mi := MeshInstance3D.new()
	mi.mesh = _glint_mesh
	var m := _glint_mat.duplicate() as StandardMaterial3D
	m.albedo_color = Color(c.r, c.g, c.b, 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = local_pos
	# undo the parent's scale (a 1.35x boss, a centimetre skeleton) so the glint keeps its size
	var gs := parent.global_transform.basis.get_scale()
	var inv := 1.0 / maxf(gs.x, 0.001)
	mi.scale = Vector3.ONE * size * 0.2 * inv
	mi.rotation.z = randf() * 0.6
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size * inv, seconds * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(mi, "rotation:z", mi.rotation.z + 0.5, seconds)
	tw.tween_property(m, "albedo_color:a", 0.0, seconds * 0.7)
	tw.tween_callback(mi.queue_free)
	return mi


static func _star_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var core := exp(-r * r * 40.0)
			var rays := exp(-absf(u) * 26.0) * maxf(1.0 - absf(v), 0.0) + exp(-absf(v) * 26.0) * maxf(1.0 - absf(u), 0.0)
			var halo := exp(-r * r * 6.0) * 0.25
			var a := clampf(core + rays * 0.8 + halo, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


## A short, directional spurt of dark blood at a blade contact: ~12 droplets thrown along `dir`
## (and up), falling under gravity, shrinking out. CPU particles (web-safe), one shot, self-freeing.
static func blood_spray(parent: Node, pos: Vector3, dir: Vector3, amount := 12, force := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _blood_mesh == null:
		_blood_mesh = QuadMesh.new()
		_blood_mesh.size = Vector2(0.07, 0.07)
		_blood_mat = StandardMaterial3D.new()
		_blood_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blood_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blood_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_blood_mat.vertex_color_use_as_albedo = true
		_blood_mat.albedo_texture = _drop_texture()
		_blood_mesh.material = _blood_mat
	var p := CPUParticles3D.new()
	p.mesh = _blood_mesh
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.92
	p.lifetime = 0.55
	p.local_coords = false
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	p.direction = (d + Vector3.UP * 0.55).normalized()
	p.spread = 24.0
	p.initial_velocity_min = 3.0 * force
	p.initial_velocity_max = 6.5 * force
	p.gravity = Vector3(0, -14.0, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.0, 0.02, 1.0))
	g.set_color(1, Color(0.22, 0.0, 0.01, 0.0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.2, false).timeout.connect(p.queue_free)


static func _drop_texture() -> ImageTexture:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var a := clampf(1.0 - sqrt(u * u + v * v), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, smoothstep(0.0, 0.5, a)))
	return ImageTexture.create_from_image(img)


## The wind-up curve every body tell shares (enemies and bosses): how far through the clip's
## wind-up (0 = `from`, 1 = the strike frame) the body is at fraction `k` of the wind-up time.
## Slow in: a quick rise into the cocked pose, a held, creeping anticipation, then the snap.
## `cock` is where the cocked pose sits on that 0..1 span (just before the strike).
static func tell_curve(k: float, cock := 0.75) -> float:
	k = clampf(k, 0.0, 1.0)
	if k < 0.42:
		var a := k / 0.42
		return cock * 0.9 * (1.0 - (1.0 - a) * (1.0 - a)) # ease out into the pose
	if k < 0.8:
		return cock * (0.9 + 0.1 * (k - 0.42) / 0.38) # held: a creeping coil
	var b := (k - 0.8) / 0.2
	return cock + (1.0 - cock) * b * b # the snap, accelerating into the strike
