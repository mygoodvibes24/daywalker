extends RefCounted
## Scene dressing for points of interest and deployment points: primitive props with
## shared materials, a few box colliders (built before the navmesh bake, so enemies path
## around them). Lives apart from city.gd on purpose.

const U = preload("res://scripts/util.gd")

static var M := {}


static func mats() -> Dictionary:
	if not M.is_empty():
		return M
	M.wood = U.mat(Color(0.2, 0.1, 0.06), 0.7)
	M.wood_dark = U.mat(Color(0.07, 0.035, 0.03), 0.55)
	M.crate = U.mat(Color(0.42, 0.3, 0.17), 0.85)
	M.velvet = U.mat(Color(0.35, 0.0, 0.04), 0.6)
	M.iron = U.mat(Color(0.12, 0.12, 0.13), 0.45, 0.8)
	M.rust = U.mat(Color(0.3, 0.14, 0.08), 0.8, 0.3)
	M.stone = U.mat(Color(0.58, 0.55, 0.5), 0.9)
	M.trailer = U.mat(Color(0.62, 0.6, 0.54), 0.55, 0.45)
	M.trailer_band = U.mat(Color(0.18, 0.36, 0.36), 0.6, 0.3)
	M.trailer_rib = U.mat(Color(0.5, 0.49, 0.45), 0.45, 0.6)
	M.rust_dark = U.mat(Color(0.18, 0.08, 0.05), 0.85, 0.2)
	M.tarp = U.mat(Color(0.12, 0.2, 0.3), 0.9)
	M.bone = U.mat(Color(0.85, 0.8, 0.68), 0.7)
	M.gold = U.mat(Color(0.85, 0.65, 0.3), 0.3, 1.0)
	M.cloth = U.mat(Color(0.08, 0.06, 0.07), 0.95)
	M.candle = U.glow(Color(1.0, 0.65, 0.3), 3.0)
	M.blood = U.glow(Color(0.75, 0.0, 0.04), 2.0)
	M.fire = U.glow(Color(1.0, 0.45, 0.1), 5.0)
	M.window = U.glow(Color(1.0, 0.75, 0.4), 1.6)
	M.green = U.glow(Color(0.3, 1.0, 0.45), 3.0)
	M.eyes = U.glow(Color(0.5, 1.0, 0.6), 6.0)
	M.holy = U.glow(Color(1.0, 0.9, 0.6), 2.5)
	M.subway = U.glow(Color(0.25, 0.9, 0.5), 2.5)
	M.asphalt = U.mat(Color(0.05, 0.05, 0.05), 0.4)
	return M


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, shadow := false) -> MeshInstance3D:
	var mi := U.part(parent, mesh, mat, pos, rot, scl)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _col(parent: Node3D, size: Vector3, pos: Vector3, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	body.position = pos
	body.rotation.y = yaw
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	body.add_child(c)


static func label(parent: Node3D, text: String, c: Color, y := 4.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 44
	l.outline_size = 10
	l.modulate = c
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, y, 0)
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- props
static func coffin(parent: Node3D, pos: Vector3, yaw: float, open := false) -> Node3D:
	var m := mats()
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	_p(root, U.box(Vector3(0.66, 0.44, 1.9)), m.wood_dark, Vector3(0, 0.22, 0), Vector3.ZERO, Vector3.ONE, true)
	_p(root, U.box(Vector3(0.6, 0.02, 1.8)), m.velvet, Vector3(0, 0.45, 0))
	var lid := Node3D.new()
	lid.name = "Lid"
	root.add_child(lid)
	lid.position = Vector3(0.33, 0.46, 0)
	_p(lid, U.box(Vector3(0.72, 0.08, 1.98)), m.wood, Vector3(-0.33, 0, 0))
	_p(lid, U.box(Vector3(0.08, 0.02, 0.95)), m.gold, Vector3(-0.33, 0.05, 0.2))
	_p(lid, U.box(Vector3(0.44, 0.02, 0.08)), m.gold, Vector3(-0.33, 0.05, 0.42))
	if open:
		lid.rotation.z = -1.9
	_col(root, Vector3(0.7, 0.5, 1.95), Vector3(0, 0.25, 0))
	return root


static func candle_cluster(parent: Node3D, pos: Vector3) -> void:
	var m := mats()
	for i in 3:
		var o := Vector3(cos(i * 2.1) * 0.15, 0, sin(i * 2.1) * 0.15)
		var h := 0.18 + i * 0.08
		_p(parent, U.cyl(0.035, 0.035, h), U.mat(Color(0.9, 0.86, 0.78), 0.8), pos + o + Vector3(0, h * 0.5, 0))
		_p(parent, U.sphere(0.03), m.candle, pos + o + Vector3(0, h + 0.03, 0))


static func crate(parent: Node3D, pos: Vector3, size := 1.0, yaw := 0.0, collide := true) -> void:
	var m := mats()
	_p(parent, U.box(Vector3.ONE * size), m.crate, pos + Vector3(0, size * 0.5, 0), Vector3(0, yaw, 0), Vector3.ONE, true)
	_p(parent, U.box(Vector3(size * 1.03, size * 0.1, size * 1.03)), m.wood_dark, pos + Vector3(0, size * 0.85, 0), Vector3(0, yaw, 0))
	if collide:
		_col(parent, Vector3.ONE * size, pos + Vector3(0, size * 0.5, 0), yaw)


static func barrel(parent: Node3D, pos: Vector3, fire := false) -> void:
	var m := mats()
	_p(parent, U.cyl(0.31, 0.3, 0.95), m.rust, pos + Vector3(0, 0.475, 0), Vector3.ZERO, Vector3.ONE, true)
	for y in [0.15, 0.48, 0.82]: # rolled hoops
		_p(parent, U.cyl(0.325, 0.325, 0.05), m.rust_dark, pos + Vector3(0, y, 0))
	if fire:
		# a burn barrel: punched vent holes glowing, embers, flames, smoke and a warm light
		for i in 6:
			var a := TAU * i / 6.0
			_p(parent, U.sphere(0.045), m.fire, pos + Vector3(cos(a) * 0.3, 0.3, sin(a) * 0.3))
		_p(parent, U.cyl(0.29, 0.29, 0.04), U.glow(Color(1.0, 0.35, 0.05), 3.0), pos + Vector3(0, 0.9, 0))
		var flame := CPUParticles3D.new()
		flame.position = pos + Vector3(0, 0.95, 0)
		flame.amount = 18
		flame.lifetime = 0.7
		flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		flame.emission_sphere_radius = 0.18
		flame.direction = Vector3.UP
		flame.spread = 15.0
		flame.gravity = Vector3(0, 1.6, 0)
		flame.initial_velocity_min = 0.5
		flame.initial_velocity_max = 1.1
		flame.scale_amount_min = 0.6
		flame.scale_amount_max = 1.0
		var fc := Curve.new()
		fc.add_point(Vector2(0, 1.0))
		fc.add_point(Vector2(1, 0.1))
		flame.scale_amount_curve = fc
		var fq := QuadMesh.new()
		fq.size = Vector2(0.38, 0.5)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		fm.vertex_color_use_as_albedo = true
		fm.albedo_texture = _soft_dot()
		fq.material = fm
		flame.mesh = fq
		var fg := Gradient.new()
		fg.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
		fg.set_color(1, Color(0.8, 0.1, 0.0, 0.0))
		flame.color_ramp = fg
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.visibility_range_end = 60.0
		parent.add_child(flame)
		var smoke := CPUParticles3D.new()
		smoke.position = pos + Vector3(0, 1.4, 0)
		smoke.amount = 10
		smoke.lifetime = 4.0
		smoke.preprocess = 4.0
		smoke.direction = Vector3.UP
		smoke.spread = 10.0
		smoke.gravity = Vector3(0.25, 0.35, 0)
		smoke.initial_velocity_min = 0.4
		smoke.initial_velocity_max = 0.8
		smoke.scale_amount_min = 1.0
		smoke.scale_amount_max = 1.6
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.5))
		sc.add_point(Vector2(1, 2.6))
		smoke.scale_amount_curve = sc
		var sq := QuadMesh.new()
		sq.size = Vector2(1.0, 1.0)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.vertex_color_use_as_albedo = true
		sm.albedo_texture = _soft_dot()
		sm.disable_receive_shadows = true
		sq.material = sm
		smoke.mesh = sq
		var sg := Gradient.new()
		sg.set_color(0, Color(0.2, 0.18, 0.17, 0.0))
		sg.add_point(0.2, Color(0.22, 0.2, 0.19, 0.35))
		sg.set_color(sg.get_point_count() - 1, Color(0.25, 0.24, 0.24, 0.0))
		smoke.color_ramp = sg
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smoke.visibility_range_end = 70.0
		parent.add_child(smoke)
		var l := OmniLight3D.new()
		l.position = pos + Vector3(0, 1.3, 0)
		l.light_color = Color(1.0, 0.55, 0.22)
		l.light_energy = 1.8
		l.omni_range = 7.5
		l.shadow_enabled = false
		parent.add_child(l)
	_col(parent, Vector3(0.6, 1.0, 0.6), pos + Vector3(0, 0.5, 0))


static var _dot: ImageTexture
static func _soft_dot() -> ImageTexture:
	if _dot == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		_dot = ImageTexture.create_from_image(img)
	return _dot


## A single-wide trailer home, built from parts: rounded ends, ribbed aluminium siding in two
## tones, a rust stain skirt, framed windows (lit), a door with a block step, a hitch tongue,
## cinder-block piers. ~6.2 x 2.4 m.
static func trailer(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var m := mats()
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var L := 6.2
	var W := 2.3
	var y0 := 0.55 # floor height on its piers
	var H := 2.2
	# the shell, with rounded ends (half cylinders along x)
	_p(root, U.box(Vector3(W, H, L - W)), m.trailer, Vector3(0, y0 + H * 0.5, 0), Vector3.ZERO, Vector3.ONE, true)
	for s in [-1.0, 1.0]:
		var cap := U.cyl(W * 0.5, W * 0.5, H)
		_p(root, cap, m.trailer, Vector3(0, y0 + H * 0.5, s * (L - W) * 0.5), Vector3.ZERO, Vector3.ONE, true)
	# the teal band and ribbed siding (horizontal ribs)
	_p(root, U.box(Vector3(W + 0.03, 0.55, L - W)), m.trailer_band, Vector3(0, y0 + 0.95, 0))
	for k in 6:
		_p(root, U.box(Vector3(W + 0.05, 0.03, L - W)), m.trailer_rib, Vector3(0, y0 + 0.25 + k * 0.35, 0))
	# the roof: a slightly domed cap
	_p(root, U.box(Vector3(W - 0.1, 0.12, L - 0.3)), m.trailer_rib, Vector3(0, y0 + H + 0.04, 0))
	# rust skirt and cinder-block piers
	_p(root, U.box(Vector3(W - 0.1, 0.35, L - 0.4)), m.rust_dark, Vector3(0, y0 - 0.17, 0))
	for z in [-2.2, 0.0, 2.2]:
		for x in [-0.8, 0.8]:
			_p(root, U.box(Vector3(0.4, 0.38, 0.2)), m.stone, Vector3(x, 0.19, z))
	# windows (lit, framed) along the door side (+x) and one in the end
	for z in [-1.8, 0.6]:
		_p(root, U.box(Vector3(0.06, 0.62, 1.0)), m.rust_dark, Vector3(W * 0.5 + 0.02, y0 + 1.45, z))
		_p(root, U.box(Vector3(0.07, 0.5, 0.86)), m.window, Vector3(W * 0.5 + 0.03, y0 + 1.45, z))
	_p(root, U.box(Vector3(0.7, 0.45, 0.07)), m.window, Vector3(0, y0 + 1.5, L * 0.5 - 0.02))
	# the door, a block step, a porch lamp
	_p(root, U.box(Vector3(0.06, 1.85, 0.8)), m.wood_dark, Vector3(W * 0.5 + 0.03, y0 + 0.95, 2.0))
	_p(root, U.box(Vector3(0.7, 0.4, 0.9)), m.stone, Vector3(W * 0.5 + 0.38, 0.2, 2.0))
	_p(root, U.sphere(0.09), m.window, Vector3(W * 0.5 + 0.1, y0 + 2.0, 1.4))
	# the hitch tongue at the far end
	_p(root, U.box(Vector3(0.08, 0.08, 1.4)), m.iron, Vector3(-0.3, y0 - 0.05, -L * 0.5 - 0.4), Vector3(0, 0.22, 0))
	_p(root, U.box(Vector3(0.08, 0.08, 1.4)), m.iron, Vector3(0.3, y0 - 0.05, -L * 0.5 - 0.4), Vector3(0, -0.22, 0))
	for x in [-0.9, 0.9]:
		_p(root, U.cyl(0.32, 0.32, 0.22), m.asphalt, Vector3(x * 1.25, 0.32, 0.4), Vector3(0, 0, PI / 2))
	_col(root, Vector3(W, H + y0, L), Vector3(0, (H + y0) * 0.5, 0))


# ---------------------------------------------------------------- POI sets
static func build(type: String, root: Node3D, rng: RandomNumberGenerator, c: Color) -> Dictionary:
	var out := {"coffins": []}
	var m := mats()
	match type:
		"nest":
			# a velvet-draped court of coffins on the corner, candles and bones
			for i in 3:
				var a := -0.6 + i * 0.6 + rng.randf_range(-0.1, 0.1)
				var p := Vector3(cos(a) * 4.6, 0.0, sin(a) * 4.6)
				var cf := coffin(root, p.rotated(Vector3.UP, PI * 0.25), a + PI * 0.75)
				out.coffins.append(cf)
			for i in 5:
				candle_cluster(root, Vector3(cos(i * 1.25) * 2.4, 0.0, sin(i * 1.25) * 2.4))
			for s in [-1.0, 1.0]:
				_p(root, U.box(Vector3(0.1, 3.4, 2.4)), m.velvet, Vector3(s * 5.4, 1.7, 5.0), Vector3(0, s * 0.6, 0))
				_p(root, U.cyl(0.06, 0.06, 3.6), m.iron, Vector3(s * 5.4, 1.8, 3.6))
			for i in 6:
				_p(root, U.capsule(0.05, 0.4), m.bone, Vector3(rng.randf_range(-1.5, 1.5), 0.05, rng.randf_range(-1.5, 1.5)), Vector3(PI / 2, rng.randf() * TAU, 0))
			_p(root, U.cyl(1.6, 1.6, 0.02), U.glow(Color(0.35, 0.0, 0.03), 0.8), Vector3(0, 0.12, 0))
		"camp":
			trailer(root, Vector3(4.6, 0, -1.5), 0.15)
			trailer(root, Vector3(-1.5, 0, 4.8), PI * 0.5 - 0.1)
			barrel(root, Vector3(0.0, 0, 0.0), true)
			for i in 4:
				barrel(root, Vector3(-4.2 + i * 0.7, 0, -4.4 + (i % 2) * 0.5))
			for i in 3: # lawn chairs round the fire
				var a := i * 2.1 + 0.4
				_p(root, U.box(Vector3(0.55, 0.06, 0.55)), m.tarp, Vector3(cos(a) * 1.6, 0.45, sin(a) * 1.6), Vector3(0, -a, 0))
				_p(root, U.box(Vector3(0.55, 0.6, 0.06)), m.tarp, Vector3(cos(a) * 1.9, 0.75, sin(a) * 1.9), Vector3(0.2, -a + PI / 2, 0))
			_p(root, U.cyl(2.2, 2.2, 0.02), U.glow(Color(0.4, 0.15, 0.02), 0.6), Vector3(0, 0.12, 0))
		"market":
			# a crate fort: a broken ring of stacked crates round a blood stall
			for i in 10:
				if i == 2 or i == 7:
					continue # two gaps to walk through
				var a := TAU * i / 10.0
				var p := Vector3(cos(a) * 5.0, 0, sin(a) * 5.0)
				crate(root, p, 1.1, a)
				if i % 2 == 0:
					crate(root, p + Vector3(0, 1.1, 0), 0.9, a + 0.3, false)
			_p(root, U.box(Vector3(2.4, 0.9, 1.0)), m.wood, Vector3(0, 0.45, -1.0), Vector3.ZERO, Vector3.ONE, true)
			_col(root, Vector3(2.4, 0.9, 1.0), Vector3(0, 0.45, -1.0))
			_p(root, U.box(Vector3(3.2, 0.05, 2.4)), m.tarp, Vector3(0, 2.4, -1.0), Vector3(0.12, 0, 0))
			for x in [-1.4, 1.4]:
				_p(root, U.cyl(0.05, 0.05, 2.4), m.iron, Vector3(x, 1.2, -0.0))
			for i in 5:
				_p(root, U.capsule(0.08, 0.28), m.blood, Vector3(-1.0 + i * 0.5, 1.9, -1.0))
		"fieldboss":
			# a ruined monument: a broken plinth, iron spikes and a torn banner
			_p(root, U.box(Vector3(2.4, 1.2, 2.4)), m.stone, Vector3(0, 0.6, 0), Vector3.ZERO, Vector3.ONE, true)
			_p(root, U.box(Vector3(1.2, 1.6, 1.0)), m.stone, Vector3(0.2, 1.9, 0.1), Vector3(0, 0.4, 0.15), Vector3.ONE, true)
			_col(root, Vector3(2.4, 1.2, 2.4), Vector3(0, 0.6, 0))
			for i in 8:
				var a := TAU * i / 8.0
				_p(root, U.cyl(0.05, 0.08, 2.2), m.iron, Vector3(cos(a) * 6.4, 1.1, sin(a) * 6.4))
				_p(root, U.cyl(0.0, 0.09, 0.3), m.iron, Vector3(cos(a) * 6.4, 2.35, sin(a) * 6.4))
			_p(root, U.box(Vector3(1.2, 2.2, 0.04)), U.mat(c.darkened(0.5), 0.8), Vector3(-1.5, 3.0, 0), Vector3(0, 0, 0.08))
			_p(root, U.cyl(0.05, 0.05, 4.4), m.iron, Vector3(-2.15, 2.2, 0))
			_p(root, U.cyl(6.4, 6.4, 0.02), U.glow(c.darkened(0.6), 0.6), Vector3(0, 0.12, 0))
		"chapel":
			# a wayside altar: stone, an iron cross, a bowl of light and candles
			_p(root, U.box(Vector3(1.8, 1.0, 0.9)), m.stone, Vector3(0, 0.5, 0), Vector3.ZERO, Vector3.ONE, true)
			_col(root, Vector3(1.8, 1.0, 0.9), Vector3(0, 0.5, 0))
			_p(root, U.box(Vector3(0.14, 2.4, 0.14)), m.iron, Vector3(0, 2.2, -0.2))
			_p(root, U.box(Vector3(1.1, 0.14, 0.14)), m.iron, Vector3(0, 2.8, -0.2))
			_p(root, U.cyl(0.35, 0.22, 0.2), m.gold, Vector3(0, 1.1, 0.15))
			_p(root, U.sphere(0.22), m.holy, Vector3(0, 1.3, 0.15))
			for x in [-0.7, 0.7]:
				candle_cluster(root, Vector3(x, 1.0, 0.2))
			_p(root, U.cyl(2.0, 2.0, 0.02), U.glow(Color(0.45, 0.38, 0.2), 0.7), Vector3(0, 0.12, 0))
		"merchant":
			# a cart with a green lantern and a hooded seller
			_p(root, U.box(Vector3(2.0, 0.8, 1.2)), m.wood, Vector3(0, 0.9, -0.8), Vector3.ZERO, Vector3.ONE, true)
			_col(root, Vector3(2.0, 1.3, 1.2), Vector3(0, 0.65, -0.8))
			for x in [-0.8, 0.8]:
				_p(root, U.cyl(0.45, 0.45, 0.1), m.wood_dark, Vector3(x * 1.3, 0.45, -0.8), Vector3(0, 0, PI / 2))
			_p(root, U.cyl(0.04, 0.04, 2.6), m.iron, Vector3(0.9, 1.6, -0.3))
			_p(root, U.sphere(0.16), m.green, Vector3(0.9, 2.8, -0.3))
			for i in 4:
				_p(root, U.capsule(0.05, 0.18), m.blood, Vector3(-0.6 + i * 0.3, 1.4, -0.6))
			# the seller
			_p(root, U.capsule(0.32, 1.5), m.cloth, Vector3(-1.4, 0.75, 0.2), Vector3.ZERO, Vector3.ONE, true)
			_p(root, U.cyl(0.0, 0.3, 0.55), m.cloth, Vector3(-1.4, 1.75, 0.2))
			for x in [-0.06, 0.06]:
				_p(root, U.sphere(0.025), m.eyes, Vector3(-1.4 + x, 1.55, 0.44))
	return out


# ---------------------------------------------------------------- deployment points
static func deploy_point(type: String, root: Node3D, face: Vector3) -> Dictionary:
	var m := mats()
	var out := {}
	var yaw := atan2(face.x, face.z)
	match type:
		"subway":
			# a station mouth: a dark pit with railings, two green globe lamps and a sign
			var r := Node3D.new()
			root.add_child(r)
			r.rotation.y = yaw
			_p(r, U.box(Vector3(2.6, 0.04, 3.4)), U.mat(Color(0.0, 0.0, 0.0), 1.0), Vector3(0, 0.03, -2.6))
			for s in [-1.0, 1.0]:
				_p(r, U.box(Vector3(0.08, 1.0, 3.4)), m.iron, Vector3(s * 1.35, 0.5, -2.6))
				_p(r, U.cyl(0.05, 0.05, 2.6), m.iron, Vector3(s * 1.35, 1.3, -0.9))
				_p(r, U.sphere(0.22), m.subway, Vector3(s * 1.35, 2.7, -0.9))
				_col(r, Vector3(0.1, 1.0, 3.4), Vector3(s * 1.35, 0.5, -2.6))
			_col(r, Vector3(2.6, 1.0, 0.1), Vector3(0, 0.5, -4.3))
			# an enamel sign board (it was a solid glowing slab: the bright green rectangle at the
			# station spawns); only the lettering and a thin lit edge glow now
			_p(r, U.box(Vector3(2.8, 0.5, 0.06)), U.mat(Color(0.02, 0.07, 0.045), 0.5, 0.2), Vector3(0, 2.3, -0.9))
			_p(r, U.box(Vector3(2.8, 0.03, 0.07)), U.glow(Color(0.1, 0.5, 0.25), 0.8), Vector3(0, 2.04, -0.9))
			var sign_lbl := label(r, "VESPER LINE", Color(0.6, 0.95, 0.75), 2.3)
			sign_lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			sign_lbl.position.z = -0.86
		"manhole":
			_p(root, U.cyl(0.55, 0.55, 0.03), U.mat(Color(0, 0, 0), 1.0), Vector3(0, 0.02, 0))
			var cover := _p(root, U.cyl(0.6, 0.6, 0.06), m.iron, Vector3(0.9, 0.04, 0.4), Vector3(0, 0, 0.0), Vector3.ONE, true)
			cover.name = "Cover"
			out["cover"] = cover
			_p(root, U.cyl(0.9, 0.9, 0.02), U.glow(Color(0.4, 0.3, 0.2), 0.3), Vector3(0, 0.03, 0))
		"rooftop":
			pass # Sol drops from the roofline; the slam leaves a crater decal at runtime
		"ladder":
			# an iron ladder up the quay wall out of the river, and a lamp on the bollard
			var r := Node3D.new()
			root.add_child(r)
			r.rotation.y = yaw
			for s in [-0.28, 0.28]:
				_p(r, U.box(Vector3(0.06, 2.9, 0.06)), m.rust, Vector3(s, -0.45, -3.05))
				_p(r, U.box(Vector3(0.06, 0.06, 0.7)), m.rust, Vector3(s, 0.95, -2.75), Vector3(0.6, 0, 0))
			for k in 8:
				_p(r, U.box(Vector3(0.56, 0.04, 0.04)), m.rust, Vector3(0, -1.7 + k * 0.32, -3.05))
			_p(r, U.cyl(0.05, 0.05, 2.4), m.iron, Vector3(1.4, 1.2, -2.4))
			_p(r, U.sphere(0.2), m.window, Vector3(1.4, 2.5, -2.4))
		"trail":
			# a trail marker: a leaning signpost and a lantern hung on a stake
			var r := Node3D.new()
			root.add_child(r)
			r.rotation.y = yaw
			_p(r, U.box(Vector3(0.14, 2.2, 0.14)), m.wood, Vector3(1.8, 1.1, 0.5), Vector3(0, 0, 0.06))
			_p(r, U.box(Vector3(1.3, 0.35, 0.06)), m.wood, Vector3(2.2, 1.8, 0.5), Vector3(0, 0, -0.1))
			label(r, "HOLLOW PINES", Color(0.9, 0.85, 0.7), 2.4).billboard = BaseMaterial3D.BILLBOARD_DISABLED
			_p(r, U.box(Vector3(0.08, 1.6, 0.08)), m.wood, Vector3(-1.6, 0.8, 0.0))
			_p(r, U.box(Vector3(0.2, 0.3, 0.2)), m.window, Vector3(-1.6, 1.45, 0.25))
		"boat":
			# a flat-bottomed skiff that brings Sol in across the swamp, and a mooring post
			var boat := Node3D.new()
			boat.name = "Boat"
			root.add_child(boat)
			boat.rotation.y = yaw
			boat.position = -face * 1.8 + Vector3(0, 0.05, 0)
			_p(boat, U.box(Vector3(1.3, 0.35, 4.2)), m.wood_dark, Vector3(0, 0.18, 0), Vector3.ZERO, Vector3.ONE, true)
			for s in [-0.62, 0.62]:
				_p(boat, U.box(Vector3(0.06, 0.45, 4.2)), m.wood, Vector3(s, 0.32, 0))
			_p(boat, U.cyl(0.03, 0.03, 0.5), m.iron, Vector3(0, 0.6, 1.8))
			_p(boat, U.sphere(0.13), m.window, Vector3(0, 0.92, 1.8))
			out["boat"] = boat
			_p(root, U.cyl(0.12, 0.14, 1.6), m.wood, face.cross(Vector3.UP) * 1.4 + Vector3(0, 0.8, 0))
	return out
