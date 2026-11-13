extends RefCounted
## Street props for Port Vesper: parked sedans, dumpsters, cast-iron lamps,
## hydrants, news boxes and trash piles, scattered around the city blocks.
##
## Self-contained: it reads the building colliders that already exist under
## `parent` (any StaticBody3D with a box/cylinder shape) and places props in the
## free space around them. Each GLB is loaded once and drawn with one
## MultiMeshInstance3D per prop mesh (materials kept), so the whole set costs a
## handful of draw calls instead of hundreds of scene instances.

const DIR := "res://assets/props/"
const GRID := 20.0
const HALF_BLOCK := 6.5 # sidewalk squares are 13 x 13 m
const WALK_Y := 0.06 # sidewalk slab height
const WORLD := 80.0
const CELL := 160.0 / 3.0 # 3 x 3 culling cells over the +-80 m city

## size: real-world target for `measure` ("long" = longest horizontal side, "height").
const SPECS := {
	"sedan": {"size": 5.2, "measure": "long", "shadow": true},
	"dumpster": {"size": 1.8, "measure": "long", "shadow": true},
	"street_lamp": {"size": 4.5, "measure": "height", "shadow": true},
	"hydrant": {"size": 0.8, "measure": "height", "shadow": false},
	"news_box": {"size": 1.1, "measure": "height", "shadow": false},
	"trash_pile": {"size": 1.0, "measure": "long", "shadow": false},
}

## Keep colliders out of these XZ rects (the smoke test walks Sol onto the
## sidewalk at x 20..29, z 22) and keep the cathedral plaza clear.
const NO_COLLIDER_ZONES := [Rect2(12.0, 17.0, 22.0, 10.0)]
const PLAZA := Rect2(-20.0, -20.0, 40.0, 40.0)


static func scatter(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var props := {}
	for name in SPECS:
		var p := _load_prop(name)
		if not p.is_empty():
			props[name] = p
	if props.is_empty():
		return
	var root := Node3D.new()
	root.name = "Props"
	parent.add_child(root)

	var obstacles := _collect_obstacles(parent) # Array[Rect2] (XZ) of buildings etc.
	var taken: Array[Rect2] = [] # footprints of props placed so far
	var placed := {} # name -> Array[Transform3D]
	for name in props:
		placed[name] = []
	var colliders: Array = [] # [Vector3 size, Transform3D]

	var blocks: Array[Vector2] = []
	for i in range(-4, 4):
		for j in range(-4, 4):
			var c := Vector2(i * GRID + GRID * 0.5, j * GRID + GRID * 0.5)
			if absf(c.x) < GRID and absf(c.y) < GRID:
				continue # cathedral plaza
			blocks.append(c)

	for c in blocks:
		var block_obs := _obstacles_in_block(obstacles, c)
		# --- parked sedans: only on the +x / +z kerb of each block, so a street
		# segment never has cars on both sides (>= 4.9 m of open road remains).
		if props.has("sedan"):
			for side in [Vector2(1, 0), Vector2(0, 1)]:
				if rng.randf() > 0.35:
					continue
				_try_car(props.sedan, c, side, rng, obstacles, taken, placed.sedan, colliders)
		# --- one street lamp per block on the sidewalk edge (a row along each +x kerb)
		if props.has("street_lamp"):
			var pos := _edge_point(c, Vector2(1, 0), rng.randf_range(-2.5, 2.5), 0.45)
			if not _try_place(props.street_lamp, pos, 0.0, obstacles, taken, placed.street_lamp, 0.15):
				_try_place(props.street_lamp, _edge_point(c, Vector2(0, -1), rng.randf_range(-2.5, 2.5), 0.45), 0.0, obstacles, taken, placed.street_lamp, 0.15)
		# --- hydrant and news box on two random corners
		var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
		_shuffle(corners, rng)
		if props.has("hydrant") and rng.randf() < 0.45:
			var k: Vector2 = corners[0]
			var pos := Vector3(c.x + k.x * (HALF_BLOCK - 1.6), WALK_Y, c.y + k.y * (HALF_BLOCK - 0.5))
			_try_place(props.hydrant, pos, rng.randf() * TAU, obstacles, taken, placed.hydrant, 0.1)
		if props.has("news_box") and rng.randf() < 0.4:
			var k: Vector2 = corners[1]
			var pos := Vector3(c.x + k.x * (HALF_BLOCK - 0.55), WALK_Y, c.y + k.y * (HALF_BLOCK - 1.8))
			# face the street it stands beside (x side)
			var yaw := PI * 0.5 if k.x > 0.0 else -PI * 0.5
			_try_place(props.news_box, pos, yaw, obstacles, taken, placed.news_box, 0.1)
		# --- dumpsters and trash against building walls / in the gaps between them
		if props.has("dumpster") and rng.randf() < 0.55:
			_try_against_wall(props.dumpster, c, block_obs, rng, obstacles, taken, placed.dumpster, colliders, true)
		if props.has("trash_pile"):
			for n in rng.randi_range(0, 2):
				_try_against_wall(props.trash_pile, c, block_obs, rng, obstacles, taken, placed.trash_pile, colliders, false)

	var lamp_meshes: Array[Mesh] = []
	for name in props:
		var used := _build_multimesh(root, name, props[name], placed[name])
		if name == "street_lamp":
			lamp_meshes = used
	_build_colliders(root, colliders)
	if props.has("street_lamp"):
		_add_lamp_lights(root, parent, props.street_lamp, placed.street_lamp, lamp_meshes)


# ---------------------------------------------------------------- loading
## Returns {meshes: [[Mesh, Transform3D]], size: Vector3} with the transforms
## normalised to real-world size, centred on x/z and with the base at y = 0.
static func _load_prop(name: String) -> Dictionary:
	var path: String = DIR + name + ".glb"
	if not ResourceLoader.exists(path):
		return {}
	var scene := load(path) as PackedScene
	if scene == null:
		return {}
	var inst := scene.instantiate()
	var found: Array = []
	_collect_meshes(inst, Transform3D.IDENTITY, found)
	inst.free()
	if found.is_empty():
		return {}
	var box := AABB()
	for k in found.size():
		var b: AABB = found[k][1] * (found[k][0] as Mesh).get_aabb()
		box = b if k == 0 else box.merge(b)
	var spec: Dictionary = SPECS[name]
	var measure := box.size.y if spec.measure == "height" else maxf(box.size.x, box.size.z)
	var s: float = spec.size / maxf(measure, 0.0001)
	var basis := Basis.IDENTITY
	# the sedan and dumpster read their length along z, so a yaw of 0 points along z
	if spec.measure == "long" and box.size.x > box.size.z:
		basis = Basis(Vector3.UP, PI * 0.5)
	var centre := box.get_center()
	var norm := Transform3D(basis.scaled(Vector3(s, s, s)), Vector3.ZERO)
	norm.origin = -(norm.basis * Vector3(centre.x, box.position.y, centre.z))
	var meshes: Array = []
	for f in found:
		meshes.append([f[0], norm * f[1]])
	var size := (basis * box.size).abs() * s
	return {"meshes": meshes, "size": size}


static func _collect_meshes(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		# bake per-instance surface overrides into a copy of the mesh
		var overridden := false
		for si in mesh.get_surface_count():
			if mi.get_surface_override_material(si) != null:
				overridden = true
		if overridden:
			mesh = mesh.duplicate()
			for si in mesh.get_surface_count():
				var m := mi.get_surface_override_material(si)
				if m != null:
					mesh.surface_set_material(si, m)
		out.append([mesh, t])
	for c in n.get_children():
		_collect_meshes(c, t, out)


# ---------------------------------------------------------------- obstacles
static func _collect_obstacles(parent: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var stack: Array[Node] = [parent]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is CollisionShape3D) or not (n.get_parent() is StaticBody3D):
			continue
		var cs := n as CollisionShape3D
		var local := AABB()
		if cs.shape is BoxShape3D:
			var sz: Vector3 = (cs.shape as BoxShape3D).size
			local = AABB(-sz * 0.5, sz)
		elif cs.shape is CylinderShape3D:
			var cy := cs.shape as CylinderShape3D
			local = AABB(Vector3(-cy.radius, -cy.height * 0.5, -cy.radius), Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0))
		else:
			continue
		var g: AABB = cs.global_transform * local
		if g.end.y <= 0.05: # the ground slab
			continue
		if g.size.x > 100.0 or g.size.z > 100.0: # ground / boundary walls
			continue
		out.append(Rect2(g.position.x, g.position.z, g.size.x, g.size.z))
	return out


static func _obstacles_in_block(obstacles: Array[Rect2], c: Vector2) -> Array[Rect2]:
	var block := Rect2(c - Vector2(HALF_BLOCK, HALF_BLOCK), Vector2(HALF_BLOCK, HALF_BLOCK) * 2.0)
	var out: Array[Rect2] = []
	for r in obstacles:
		if block.has_point(r.get_center()):
			out.append(r)
	return out


static func _footprint(prop: Dictionary, pos: Vector3, yaw: float, grow: float) -> Rect2:
	var sz: Vector3 = prop.size
	var b := Basis(Vector3.UP, yaw)
	var ext: Vector3 = (b * Vector3(sz.x, 0, sz.z)).abs() * 0.5 + Vector3(grow, 0, grow)
	# abs() of a rotated vector underestimates the extent off-axis; cover both corners
	var ext2: Vector3 = (b * Vector3(sz.x, 0, -sz.z)).abs() * 0.5 + Vector3(grow, 0, grow)
	var ex := maxf(ext.x, ext2.x)
	var ez := maxf(ext.z, ext2.z)
	return Rect2(pos.x - ex, pos.z - ez, ex * 2.0, ez * 2.0)


static func _is_free(rect: Rect2, obstacles: Array[Rect2], taken: Array[Rect2]) -> bool:
	if absf(rect.get_center().x) > WORLD or absf(rect.get_center().y) > WORLD:
		return false
	for r in obstacles:
		if r.intersects(rect):
			return false
	for r in taken:
		if r.intersects(rect):
			return false
	return true


static func _collider_allowed(rect: Rect2) -> bool:
	for z in NO_COLLIDER_ZONES:
		if (z as Rect2).intersects(rect):
			return false
	return not PLAZA.intersects(rect)


# ---------------------------------------------------------------- placement
static func _edge_point(c: Vector2, side: Vector2, along: float, inset: float) -> Vector3:
	var d := HALF_BLOCK - inset
	if side.x != 0.0:
		return Vector3(c.x + side.x * d, WALK_Y, c.y + along)
	return Vector3(c.x + along, WALK_Y, c.y + side.y * d)


static func _try_place(prop: Dictionary, pos: Vector3, yaw: float, obstacles: Array[Rect2], taken: Array[Rect2], out: Array, grow: float) -> bool:
	var rect := _footprint(prop, pos, yaw, grow)
	if not _is_free(rect, obstacles, taken):
		return false
	taken.append(rect)
	out.append(Transform3D(Basis(Vector3.UP, yaw), pos))
	return true


static func _try_car(prop: Dictionary, c: Vector2, side: Vector2, rng: RandomNumberGenerator, obstacles: Array[Rect2], taken: Array[Rect2], out: Array, colliders: Array) -> void:
	var sz: Vector3 = prop.size # length along z
	var off := HALF_BLOCK + sz.x * 0.5 + 0.12 # just off the kerb, in the street
	var along := rng.randf_range(-(HALF_BLOCK - sz.z * 0.5 - 0.3), HALF_BLOCK - sz.z * 0.5 - 0.3)
	var pos: Vector3
	var yaw: float
	if side.x != 0.0: # kerb runs along z
		pos = Vector3(c.x + off, 0.0, c.y + along)
		yaw = 0.0 if rng.randf() < 0.5 else PI
	else: # kerb runs along x
		pos = Vector3(c.x + along, 0.0, c.y + off)
		yaw = PI * 0.5 if rng.randf() < 0.5 else -PI * 0.5
	yaw += rng.randf_range(-0.03, 0.03) # nobody parks perfectly straight
	var rect := _footprint(prop, pos, yaw, 0.1)
	if not _collider_allowed(rect) or not _is_free(rect, obstacles, taken):
		return
	taken.append(rect)
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	out.append(xf)
	colliders.append([Vector3(sz.x * 0.92, sz.y * 0.85, sz.z * 0.95), xf])


## Put a prop flat against a random face of a building in this block, inside the sidewalk.
static func _try_against_wall(prop: Dictionary, c: Vector2, block_obs: Array[Rect2], rng: RandomNumberGenerator, obstacles: Array[Rect2], taken: Array[Rect2], out: Array, colliders: Array, solid: bool) -> void:
	if block_obs.is_empty():
		return
	var sz: Vector3 = prop.size
	var block := Rect2(c - Vector2(HALF_BLOCK - 0.2, HALF_BLOCK - 0.2), Vector2(HALF_BLOCK - 0.2, HALF_BLOCK - 0.2) * 2.0)
	for attempt in 8:
		var b: Rect2 = block_obs[rng.randi() % block_obs.size()]
		var face := rng.randi() % 4
		var pos := Vector3.ZERO
		var yaw := 0.0
		var depth := sz.x * 0.5 + 0.06 # long side along the wall, back to it
		match face:
			0: # +x face
				pos = Vector3(b.end.x + depth, WALK_Y, rng.randf_range(b.position.y + sz.z * 0.5, b.end.y - sz.z * 0.5))
				yaw = 0.0
			1: # -x face
				pos = Vector3(b.position.x - depth, WALK_Y, rng.randf_range(b.position.y + sz.z * 0.5, b.end.y - sz.z * 0.5))
				yaw = PI
			2: # +z face
				pos = Vector3(rng.randf_range(b.position.x + sz.z * 0.5, b.end.x - sz.z * 0.5), WALK_Y, b.end.y + depth)
				yaw = PI * 0.5
			_: # -z face
				pos = Vector3(rng.randf_range(b.position.x + sz.z * 0.5, b.end.x - sz.z * 0.5), WALK_Y, b.position.y - depth)
				yaw = -PI * 0.5
		if not solid:
			yaw += rng.randf_range(-0.6, 0.6)
		var rect := _footprint(prop, pos, yaw, 0.03)
		if not block.encloses(rect):
			continue
		if solid and not _collider_allowed(rect):
			continue
		if not _is_free(rect, obstacles, taken):
			continue
		taken.append(rect)
		var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
		out.append(xf)
		if solid:
			colliders.append([Vector3(sz.x * 0.95, sz.y, sz.z * 0.95), xf])
		return


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


# ---------------------------------------------------------------- building
## Instances are bucketed into a coarse grid of cells (one MultiMeshInstance3D
## per prop mesh per cell) so off-screen cells are frustum-culled and distant
## cells drop to the importer's lower LODs instead of drawing every triangle.
static func _build_multimesh(root: Node3D, name: String, prop: Dictionary, xforms: Array) -> Array[Mesh]:
	var used: Array[Mesh] = []
	if xforms.is_empty():
		return used
	var spec: Dictionary = SPECS[name]
	var buckets := {}
	for xf in xforms:
		var o: Vector3 = (xf as Transform3D).origin
		var key := Vector2i(clampi(int(floor((o.x + WORLD) / CELL)), 0, 2), clampi(int(floor((o.z + WORLD) / CELL)), 0, 2))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(xf)
	for entry in prop.meshes:
		var mesh: Mesh = entry[0]
		var local: Transform3D = entry[1]
		if name == "street_lamp":
			mesh = _glowing_lamp_mesh(mesh)
		used.append(mesh)
		for key in buckets:
			var list: Array = buckets[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = list.size()
			for k in list.size():
				mm.set_instance_transform(k, (list[k] as Transform3D) * local)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d" % [name.to_pascal_case(), key.x, key.y]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if spec.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if not spec.shadow: # small props vanish into the fog long before the far cells
				mmi.visibility_range_end = 75.0
				mmi.visibility_range_end_margin = 5.0
			root.add_child(mmi)
	return used


## The lamp's lantern glass is the brightest part of its texture, so use the
## albedo texture as an emission mask: dark iron stays dark, the glass glows.
static func _glowing_lamp_mesh(src: Mesh) -> Mesh:
	var mesh: Mesh = src.duplicate()
	for si in mesh.get_surface_count():
		var m := mesh.surface_get_material(si) as BaseMaterial3D
		if m == null:
			continue
		m = m.duplicate()
		m.emission_enabled = true
		m.emission = Color(1.0, 0.72, 0.4)
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = 0.0
		mesh.surface_set_material(si, m)
	return mesh


static func _build_colliders(root: Node3D, colliders: Array) -> void:
	if colliders.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "PropColliders"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	for c in colliders:
		var size: Vector3 = c[0]
		var xf: Transform3D = c[1]
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(xf.basis, xf.origin + Vector3(0, size.y * 0.5, 0))
		body.add_child(cs)


## A real light on the few lamps nearest the plaza; the rest only glow.
static func _add_lamp_lights(root: Node3D, parent: Node3D, prop: Dictionary, xforms: Array, meshes: Array[Mesh]) -> void:
	var sorted := xforms.duplicate()
	sorted.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.origin.length() < b.origin.length())
	var lights: Array[OmniLight3D] = []
	var head_y: float = (prop.size as Vector3).y - 0.5
	for k in mini(3, sorted.size()):
		var l := OmniLight3D.new()
		l.position = (sorted[k] as Transform3D).origin + Vector3(0, head_y, 0)
		l.omni_range = 11.0
		l.light_color = Color(1.0, 0.72, 0.42)
		l.shadow_enabled = false
		root.add_child(l)
		lights.append(l)
	var mats: Array[BaseMaterial3D] = []
	for mesh in meshes:
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si) as BaseMaterial3D
			if m != null:
				mats.append(m)
	var driver := LampDriver.new()
	driver.world = parent
	driver.lights = lights
	driver.mats = mats
	root.add_child(driver)


## Follows the day/night cycle of the world node (if it has `daylight()`).
class LampDriver extends Node:
	var world: Node
	var lights: Array[OmniLight3D] = []
	var mats: Array[BaseMaterial3D] = []
	var last := -1.0

	func _ready() -> void:
		_apply()

	func _process(_delta: float) -> void:
		_apply()

	func _apply() -> void:
		var night := 1.0
		if world != null and world.has_method("daylight"):
			night = 1.0 - clampf(float(world.call("daylight")) * 2.0, 0.0, 1.0)
		if absf(night - last) < 0.01:
			return
		last = night
		for m in mats:
			m.emission_energy_multiplier = night * 3.0
		for l in lights:
			l.light_energy = night * 1.8
			l.visible = night > 0.02
