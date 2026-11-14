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
	M.trailer = U.mat(Color(0.75, 0.73, 0.66), 0.6, 0.3)
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
	_p(parent, U.cyl(0.32, 0.3, 0.95), m.rust, pos + Vector3(0, 0.475, 0), Vector3.ZERO, Vector3.ONE, true)
	if fire:
		_p(parent, U.cyl(0.0, 0.26, 0.7), m.fire, pos + Vector3(0, 1.25, 0))
		_p(parent, U.cyl(0.0, 0.16, 0.5), U.glow(Color(1.0, 0.85, 0.4), 6.0), pos + Vector3(0.05, 1.2, 0.03))
	_col(parent, Vector3(0.6, 1.0, 0.6), pos + Vector3(0, 0.5, 0))


static func trailer(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var m := mats()
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	_p(root, U.box(Vector3(2.3, 2.3, 6.0)), m.trailer, Vector3(0, 1.45, 0), Vector3.ZERO, Vector3.ONE, true)
	_p(root, U.box(Vector3(2.32, 0.25, 6.02)), m.rust, Vector3(0, 0.45, 0))
	for z in [-1.6, 0.4]:
		_p(root, U.box(Vector3(2.34, 0.6, 1.0)), m.window, Vector3(0, 1.8, z))
	_p(root, U.box(Vector3(2.34, 1.8, 0.8)), m.wood_dark, Vector3(0, 1.25, 2.0))
	for x in [-0.9, 0.9]:
		_p(root, U.cyl(0.32, 0.32, 0.25), m.asphalt, Vector3(x, 0.32, 0.6), Vector3(0, 0, PI / 2))
	_col(root, Vector3(2.3, 2.6, 6.0), Vector3(0, 1.3, 0))


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
			_p(r, U.box(Vector3(2.8, 0.5, 0.06)), U.glow(Color(0.1, 0.5, 0.25), 1.6), Vector3(0, 2.3, -0.9))
			label(r, "VESPER LINE", Color(0.7, 1.0, 0.8), 2.3).billboard = BaseMaterial3D.BILLBOARD_DISABLED
		"manhole":
			_p(root, U.cyl(0.55, 0.55, 0.03), U.mat(Color(0, 0, 0), 1.0), Vector3(0, 0.02, 0))
			var cover := _p(root, U.cyl(0.6, 0.6, 0.06), m.iron, Vector3(0.9, 0.04, 0.4), Vector3(0, 0, 0.0), Vector3.ONE, true)
			cover.name = "Cover"
			out["cover"] = cover
			_p(root, U.cyl(0.9, 0.9, 0.02), U.glow(Color(0.4, 0.3, 0.2), 0.3), Vector3(0, 0.03, 0))
		"rooftop":
			pass # Sol drops from the roofline; the slam leaves a crater decal at runtime
	return out
