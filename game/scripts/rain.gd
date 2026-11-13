extends Node3D
## Rain that follows the camera: falling streaks plus ground splashes.
## GPU particles on the cinematic tier, CPU particles on the web tier.

const HEIGHT := 14.0 # emitter height above the street
const AREA := 22.0 # half-width of the rain box around the camera

var cinematic := true
var camera: Camera3D
var drops: GeometryInstance3D
var splashes: GeometryInstance3D
var drop_mat: StandardMaterial3D
var splash_mat: StandardMaterial3D
var enabled := true


func setup(is_cinematic: bool) -> void:
	cinematic = is_cinematic
	top_level = true
	drop_mat = _streak_material()
	splash_mat = _splash_material()
	var streak := QuadMesh.new()
	streak.size = Vector2(0.018, 0.7) if cinematic else Vector2(0.025, 0.9)
	streak.material = drop_mat
	var ring := QuadMesh.new()
	ring.size = Vector2(0.22, 0.22)
	ring.orientation = PlaneMesh.FACE_Y
	ring.material = splash_mat
	if cinematic:
		drops = _gpu(streak, 7000, 0.8, true)
		splashes = _gpu(ring, 900, 0.22, false)
	else:
		drops = _cpu(streak, 1400, 0.8, true)
		splashes = _cpu(ring, 160, 0.22, false)
	add_child(drops)
	add_child(splashes)


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	for p in [drops, splashes]:
		p.set("emitting", on)


## Night rain is dim and cool, day rain a pale grey; lamps and neon do the rest.
func set_light(daylight: float) -> void:
	var c := Color(0.6, 0.68, 0.82, 0.24).lerp(Color(0.8, 0.83, 0.88, 0.26), daylight)
	drop_mat.albedo_color = c
	splash_mat.albedo_color = Color(c.r, c.g, c.b, c.a * 1.6)


func _process(_delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
		if camera == null:
			return
	var c := camera.global_position
	# lead the box a little ahead of the camera so a sprint doesn't outrun the rain
	var ahead := -camera.global_transform.basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() * 6.0 if ahead.length() > 0.01 else Vector3.ZERO
	drops.global_position = Vector3(c.x + ahead.x, HEIGHT, c.z + ahead.z)
	splashes.global_position = Vector3(c.x + ahead.x, 0.09, c.z + ahead.z)


func _streak_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.vertex_color_use_as_albedo = false
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 1))
	g.add_point(0.8, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 64
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	m.albedo_texture = t
	return m


func _splash_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_receive_shadows = true
	m.vertex_color_use_as_albedo = true
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.72, Color(1, 1, 1, 0.9))
	g.add_point(0.55, Color(1, 1, 1, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	m.albedo_texture = t
	return m


func _fade_curve() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	return g


func _gpu(mesh: Mesh, amount: int, life: float, falling: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-AREA - 8, -HEIGHT - 8, -AREA - 8), Vector3(AREA * 2 + 16, HEIGHT + 24, AREA * 2 + 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	if falling:
		pm.emission_box_extents = Vector3(AREA, 5.0, AREA)
		pm.direction = Vector3(0.12, -1.0, 0.05)
		pm.spread = 2.0
		pm.initial_velocity_min = 20.0
		pm.initial_velocity_max = 26.0
		pm.gravity = Vector3(0, -9.8, 0)
	else:
		pm.emission_box_extents = Vector3(AREA * 0.7, 0.0, AREA * 0.7)
		pm.gravity = Vector3.ZERO
		pm.initial_velocity_min = 0.0
		pm.initial_velocity_max = 0.0
		pm.scale_min = 0.4
		pm.scale_max = 1.2
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.2))
		sc.add_point(Vector2(1, 1.0))
		var sct := CurveTexture.new()
		sct.curve = sc
		pm.scale_curve = sct
		var ramp := GradientTexture1D.new()
		ramp.gradient = _fade_curve()
		pm.color_ramp = ramp
	p.process_material = pm
	return p


func _cpu(mesh: Mesh, amount: int, life: float, falling: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	if falling:
		p.emission_box_extents = Vector3(AREA * 0.8, 5.0, AREA * 0.8)
		p.direction = Vector3(0.12, -1.0, 0.05)
		p.spread = 2.0
		p.initial_velocity_min = 20.0
		p.initial_velocity_max = 26.0
		p.gravity = Vector3(0, -9.8, 0)
	else:
		p.emission_box_extents = Vector3(AREA * 0.5, 0.0, AREA * 0.5)
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.4
		p.scale_amount_max = 1.2
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.2))
		sc.add_point(Vector2(1, 1.0))
		p.scale_amount_curve = sc
		p.color_ramp = _fade_curve()
	return p
