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
static func circle_telegraph(parent: Node, pos: Vector3, radius: float, seconds: float, c := Color(1.0, 0.1, 0.05)) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = Vector3(pos.x, 0.12, pos.z)
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
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = Vector3(from.x, 0.13, from.z)
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
	root.global_position = Vector3(pos.x, 0.15, pos.z)
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
