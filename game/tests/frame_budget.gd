extends RefCounted
## A renderer-free estimate of what the web tier (Compatibility) draws from a camera pose, so
## the headless smoke test can guard the frame budget (the dummy renderer reports no stats).
##
## It walks the scene, frustum-culls each visible GeometryInstance3D's AABB, applies its
## visibility range, and counts one draw per surface, plus one more per shadow-casting surface
## inside the sun's shadow distance (the shadow pass). Compatibility shades the omni lights in
## the same pass (up to 8 per object), so lights cost no extra draws here. Triangles are counted
## at LOD 0, so they are an upper bound for imported meshes (which drop LODs with distance).
## Calibrated against RenderingServer's counters on the native Compatibility renderer at the
## probe spots (see docs/qa or the Group C report): it tracks them within about 15-20%.

const ASPECT := 16.0 / 9.0
const NEAR := 0.05

static var _tri_cache := {}


static func mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var id := mesh.get_instance_id()
	if _tri_cache.has(id):
		return _tri_cache[id]
	var t := 0
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for s in am.get_surface_count():
			var n: int = am.surface_get_array_index_len(s)
			if n <= 0:
				n = am.surface_get_array_len(s)
			t += n / 3
	elif mesh is PrimitiveMesh:
		var arr: Array = (mesh as PrimitiveMesh).get_mesh_arrays()
		var idx = arr[Mesh.ARRAY_INDEX]
		t = (idx.size() if idx != null and idx.size() > 0 else arr[Mesh.ARRAY_VERTEX].size()) / 3
	_tri_cache[id] = t
	return t


## Surfaces of a mesh (PrimitiveMeshes are one surface; the dummy renderer can't count them).
static func mesh_surfaces(mesh: Mesh) -> int:
	if mesh is PrimitiveMesh:
		return 1
	return mesh.get_surface_count() if mesh != null else 0


## The six planes (outward normals) of a perspective camera at `xf` (fov vertical, degrees).
static func frustum(xf: Transform3D, fov: float, far: float) -> Array:
	var tv := tan(deg_to_rad(fov) * 0.5)
	var th := tv * ASPECT
	var local := [
		Plane(Vector3(0, 0, 1), -NEAR),
		Plane(Vector3(0, 0, -1), far),
		Plane(Vector3(1, 0, th).normalized(), 0.0),
		Plane(Vector3(-1, 0, th).normalized(), 0.0),
		Plane(Vector3(0, 1, tv).normalized(), 0.0),
		Plane(Vector3(0, -1, tv).normalized(), 0.0),
	]
	var out := []
	for pl: Plane in local:
		out.append(xf * pl)
	return out


static func _in_frustum(planes: Array, aabb: AABB) -> bool:
	var c := aabb.get_center()
	var e := aabb.size * 0.5
	for pl: Plane in planes:
		var r := absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z
		if pl.distance_to(c) > r:
			return false
	return true


static func _range_ok(gi: GeometryInstance3D, d: float) -> bool:
	if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end:
		return false
	if gi.visibility_range_begin > 0.0 and d < gi.visibility_range_begin:
		return false
	return true


## {draws, tris, objects, top: [[name, draws, tris]...]} for a camera at `xf`.
static func estimate(root: Node, xf: Transform3D, fov := 70.0, far := 4000.0, shadow_dist := 40.0, breakdown := false) -> Dictionary:
	var planes: Array = frustum(xf, fov, far)
	var cam := xf.origin
	var geos: Array = [] # [aabb, surfaces, tris, casts, key]
	var lights: Array = [] # [pos, range]
	var stack: Array = [root]
	var draws := 0
	var tris := 0
	var objects := 0
	var shadow_on := false
	while not stack.is_empty():
		var n: Node = stack.pop_back() as Node
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n is CanvasItem or n is CanvasLayer:
			continue
		for ch in n.get_children():
			stack.append(ch)
		if n is DirectionalLight3D:
			shadow_on = shadow_on or (n as DirectionalLight3D).shadow_enabled
			continue
		if n is OmniLight3D or n is SpotLight3D:
			var l := n as Light3D
			var rr: float = (l as OmniLight3D).omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range
			if l.light_energy <= 0.0:
				continue
			if l.distance_fade_enabled and cam.distance_to(l.global_position) > l.distance_fade_begin + l.distance_fade_length:
				continue
			var la := AABB(l.global_position - Vector3.ONE * rr, Vector3.ONE * rr * 2.0)
			if _in_frustum(planes, la):
				lights.append([l.global_position, rr])
			continue
		if not (n is GeometryInstance3D):
			continue
		var gi := n as GeometryInstance3D
		var surf := 0
		var t := 0
		if gi is MeshInstance3D:
			var m: Mesh = (gi as MeshInstance3D).mesh
			if m == null:
				continue
			surf = mesh_surfaces(m)
			t = mesh_tris(m)
		elif gi is MultiMeshInstance3D:
			var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var cnt := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			if cnt <= 0:
				continue
			surf = mesh_surfaces(mm.mesh)
			t = mesh_tris(mm.mesh) * cnt
		elif gi is GPUParticles3D or gi is CPUParticles3D:
			surf = 1
			t = int(gi.get("amount")) * 2
		else:
			surf = 1 # Label3D, Sprite3D, decals...
			t = 2
		var aabb: AABB = gi.global_transform * gi.get_aabb()
		var d := cam.distance_to(aabb.get_center())
		if not _range_ok(gi, d):
			continue
		var casts := gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var only_shadow := gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var key := ""
		if breakdown:
			key = _stem(gi)
		geos.append([aabb, surf, t, casts, only_shadow, key, d])
	var stats := {}
	for g in geos:
		var aabb: AABB = g[0]
		var surf: int = g[1]
		var t: int = g[2]
		var dd := 0
		var tt := 0
		if not g[4] and _in_frustum(planes, aabb):
			dd += surf
			tt += t
			objects += 1
		if shadow_on and g[3]:
			# the orthogonal shadow pass covers a box round the camera out to shadow_dist
			var r := aabb.size.length() * 0.5
			if float(g[6]) - r < shadow_dist:
				dd += surf
				tt += t
		draws += dd
		tris += tt
		if breakdown and dd > 0:
			var k: String = g[5]
			if not stats.has(k):
				stats[k] = [0, 0, 0]
			stats[k][0] += 1
			stats[k][1] += dd
			stats[k][2] += tt
	var out := {"draws": draws + 6, "tris": tris, "objects": objects, "lights": lights.size()} # + sky and post passes
	if breakdown:
		var keys := stats.keys()
		keys.sort_custom(func(a, b): return stats[a][1] > stats[b][1])
		var top := []
		for k in keys.slice(0, 25):
			top.append([k, stats[k][0], stats[k][1], stats[k][2]])
		out["top"] = top
	return out


static func _stem(n: Node) -> String:
	var s := String(n.name)
	var p := n.get_parent()
	if s.begins_with("@") or s in ["Mesh", "MeshInstance3D", "M", "Body"]:
		s = (String(p.name) if p else "?") + "/" + s.left(12)
	s = s.rstrip("0123456789_-")
	if s.begins_with("Chunk_"):
		var parts := s.split("_")
		return "Chunk_" + parts[1].left(1) + "_" + parts[parts.size() - 1]
	if s.begins_with("TerrainChunk"):
		return "TerrainChunk"
	var i := s.find("_")
	if i > 0:
		s = s.substr(0, i)
	return s.rstrip("0123456789")
