extends RefCounted
## Sol's sword on his back (round 3, the owner's playtest: "his sword on his back while he's walking
## and running, and when he fights he pulls the sword").
##
## The modular model's hand socket ("HandR/Blade") gets a SwordCarrier node holding whatever sword is
## equipped (the build's Sword, or weapon_visual.gd's WeaponVisual). The carrier lives either under
## the hand socket (drawn) or under a BackSocket riding the Spine02 bone (sheathed), in a dark leather
## scabbard angled from behind the right shoulder down toward the left hip, outside the coat (the
## coat's spring bones only start at the waist, so the cloth never meets it).
##
##   draw():    REACH s  the right arm swings up over the shoulder to the hilt (sol_draw_ik.gd)
##              PULL s   the blade travels out of the scabbard into the fist while the arm eases back to
##                       the clip; the first swing may already be playing (player.gd buffers it)
##   sheathe(): STOW s   the hand carries the blade back over the shoulder into the scabbard
##              LET_GO s the arm eases back down to the clip, hand empty
## The empty right hand swaps the fist mesh for HandMeshOpen (built by tools/build_sol_modular.gd) and
## the SwordWrist modifier rests (sol_modular_anim.gd `armed`). Nothing runs per frame when idle.

const DrawIK = preload("res://scripts/sol_draw_ik.gd")
const REACH := 0.15
const PULL := 0.14
const STOW := 0.24
const LET_GO := 0.2
const SPINE_BONE := "Spine02"
## The sword on the back, skeleton space at rest: where the grip sits (behind the right shoulder,
## out from the coat's back by BACK_GAP) and where the blade points (down and across toward the
## left hip; +X is Sol's left).
const GRIP_X := -0.16
const GRIP_Y := 1.72
const BACK_GAP := 0.043
const BLADE_DIR := Vector3(0.45, -0.89, 0.0)
static var _back_z := 0.0 # the coat's back surface (measured once from the coat mesh)

var skel: Skeleton3D
var hand_socket: Node3D # HandR/Blade
var back_socket: Node3D
var carrier: Node3D
var scabbard: Node3D
var ik: Node
var fist: Node3D
var open_hand: Node3D
var drawn := true # the sword is in the hand (or on its way there)
var phase := "" # "" | reach | pull | stow | let_go
var t := 0.0
var _from := Transform3D()


func setup(model: Node3D) -> bool:
	skel = model.get_node_or_null("Skeleton3D") as Skeleton3D
	hand_socket = model.find_child("Blade", true, false) as Node3D
	if skel == null or hand_socket == null or hand_socket is MeshInstance3D or skel.find_bone(SPINE_BONE) < 0:
		return false
	var hr := hand_socket.get_parent()
	fist = hr.get_node_or_null("HandMesh") as Node3D
	open_hand = hr.get_node_or_null("HandMeshOpen") as Node3D
	# the carrier takes over the socket's contents (the build's Sword)
	carrier = Node3D.new()
	carrier.name = "SwordCarrier"
	hand_socket.add_child(carrier)
	for c in hand_socket.get_children():
		if c != carrier:
			c.reparent(carrier, false)
	# the back mount
	var att := BoneAttachment3D.new()
	att.name = "BackMount"
	att.bone_name = SPINE_BONE
	skel.add_child(att)
	back_socket = Node3D.new()
	back_socket.name = "BackSocket"
	att.add_child(back_socket)
	if _back_z == 0.0:
		_back_z = _measure_back(model)
	var z := BLADE_DIR.normalized()
	var x := Vector3(0, 0, -1) # the blade's flat lies against the back
	x = (x - z * x.dot(z)).normalized()
	var want := Transform3D(Basis(x, z.cross(x), z), Vector3(GRIP_X, GRIP_Y, _back_z - BACK_GAP))
	back_socket.transform = skel.get_bone_global_rest(skel.find_bone(SPINE_BONE)).affine_inverse() * want
	scabbard = Node3D.new()
	scabbard.name = "Scabbard"
	back_socket.add_child(scabbard)
	# the reach
	ik = DrawIK.new()
	ik.name = "DrawIK"
	skel.add_child(ik)
	var wrist := skel.get_node_or_null("SwordWrist")
	if wrist != null:
		skel.move_child(ik, wrist.get_index()) # reach first, then the wrist (resting while it reaches)
	fit_scabbard()
	return true


## The coat's back at shoulder-blade height (skeleton space z), from the coat's rest mesh.
static func _measure_back(model: Node3D) -> float:
	var coat := model.find_child("Coat", true, false) as MeshInstance3D
	var best := -0.16
	if coat == null or coat.mesh == null:
		return best
	var v: PackedVector3Array = coat.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var found := false
	for p in v:
		if p.y > 1.3 and p.y < 1.56 and absf(p.x) < 0.15:
			if not found or p.z < best:
				best = p.z
				found = true
	return best


## Rebuild the scabbard around the carried sword (a weapon swap changes its length and width).
func fit_scabbard() -> void:
	if scabbard == null:
		return
	for c in scabbard.get_children():
		c.queue_free()
	var blade_len := 0.0
	var guard_z := 0.05
	var guard_w := 0.0
	var lo := Vector3(INF, INF, 0)
	var hi := Vector3(-INF, -INF, 0)
	var inv := carrier.global_transform.affine_inverse() if carrier.is_inside_tree() else Transform3D()
	for mi in carrier.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var rel: Transform3D = inv * m.global_transform if carrier.is_inside_tree() else _rel(m)
		var v: PackedVector3Array = m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for p in v:
			blade_len = maxf(blade_len, (rel * p).z)
		for p in v:
			var q := rel * p
			if q.z > blade_len * 0.35 and q.z < blade_len * 0.75:
				lo = Vector3(minf(lo.x, q.x), minf(lo.y, q.y), 0)
				hi = Vector3(maxf(hi.x, q.x), maxf(hi.y, q.y), 0)
			elif q.z > -0.02 and q.z < blade_len * 0.25 and absf(q.y) > guard_w:
				guard_w = absf(q.y)
				guard_z = q.z
	if blade_len <= 0.1 or lo.x == INF:
		blade_len = 1.0
		lo = Vector3(-0.01, -0.025, 0)
		hi = Vector3(0.01, 0.025, 0)
	var mid := (lo + hi) * 0.5 # the blade's cross-section centre (not always on the grip axis)
	var size := hi - lo
	var mouth := guard_z + 0.015
	var body_len := maxf(blade_len - mouth + 0.02, 0.3)
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.045, 0.035, 0.032)
	leather.roughness = 0.5
	leather.metallic_specular = 0.35
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.11, 0.1)
	iron.metallic = 0.8
	iron.roughness = 0.4
	var box := BoxMesh.new()
	box.size = Vector3(size.x + 0.012, size.y + 0.014, body_len)
	_part(box, leather, Vector3(mid.x, mid.y, mouth + body_len * 0.5))
	var throat := BoxMesh.new()
	throat.size = Vector3(size.x + 0.02, size.y + 0.024, 0.05)
	_part(throat, iron, Vector3(mid.x, mid.y, mouth + 0.025))
	var chape := BoxMesh.new()
	chape.size = Vector3(size.x + 0.018, size.y + 0.02, 0.06)
	_part(chape, iron, Vector3(mid.x, mid.y, mouth + body_len - 0.03))


func _rel(n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur != carrier:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _part(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	scabbard.add_child(mi)


func is_drawn() -> bool:
	return drawn and phase != "reach"


## Busy moving the sword (no swing may start until the grab).
func busy() -> bool:
	return phase == "reach" or phase == "stow"


## Pull the sword. Returns the seconds until it is in the hand (0 = already there).
func draw(instant := false) -> float:
	if drawn and phase != "stow" and phase != "let_go":
		return maxf(REACH - t, 0.0) if phase == "reach" else 0.0
	if instant:
		_to_hand()
		return 0.0
	drawn = true
	if phase == "stow":
		# changed his mind mid-stow: the blade is still in hand, carry it straight back
		phase = "pull"
		t = PULL * 0.5
		return 0.0
	phase = "reach"
	t = 0.0
	return REACH


func sheathe(instant := false) -> void:
	if not drawn and phase != "reach":
		return
	if instant:
		_to_back()
		return
	drawn = false
	if phase == "reach":
		phase = "let_go"
		t = 0.0
		return
	_from = carrier.global_transform
	carrier.top_level = true
	carrier.global_transform = _from
	phase = "stow"
	t = 0.0


func _hand_target() -> Transform3D:
	return back_socket.global_transform * hand_socket.transform.affine_inverse()


func tick(delta: float) -> void:
	if phase == "":
		return
	t += delta
	match phase:
		"reach":
			var k := clampf(t / REACH, 0.0, 1.0)
			ik.weight = k * k * (3.0 - 2.0 * k)
			ik.orient = 0.6
			ik.target = _hand_target()
			if t >= REACH:
				_grab()
		"pull":
			var k := clampf(t / PULL, 0.0, 1.0)
			ik.weight = 1.0 - k * k * (3.0 - 2.0 * k)
			ik.target = _hand_target()
			var s := k * k * (3.0 - 2.0 * k)
			carrier.global_transform = back_socket.global_transform.interpolate_with(hand_socket.global_transform, s)
			if t >= PULL:
				_to_hand()
		"stow":
			var k := clampf(t / STOW, 0.0, 1.0)
			ik.weight = k * k * (3.0 - 2.0 * k)
			ik.orient = 0.6
			ik.target = _hand_target()
			var s := k * k * (3.0 - 2.0 * k)
			# the blade rides the hand most of the way, then slides home into the scabbard
			var follow := hand_socket.global_transform
			carrier.global_transform = follow.interpolate_with(back_socket.global_transform, s * s)
			if t >= STOW:
				_to_back()
				phase = "let_go"
				t = 0.0
				ik.weight = 1.0
		"let_go":
			var k := clampf(t / LET_GO, 0.0, 1.0)
			ik.weight = minf(ik.weight, 1.0 - k * k * (3.0 - 2.0 * k))
			ik.target = _hand_target()
			if t >= LET_GO:
				phase = ""
				ik.weight = 0.0


## The hand closes on the hilt: the carrier leaves the scabbard (free in world space for the pull).
func _grab() -> void:
	phase = "pull"
	t = 0.0
	var xf := carrier.global_transform
	carrier.top_level = true
	carrier.global_transform = xf
	_hands(true)


func _to_hand() -> void:
	drawn = true
	phase = ""
	t = 0.0
	if ik != null:
		ik.weight = 0.0
	carrier.top_level = false
	if carrier.get_parent() != hand_socket:
		carrier.reparent(hand_socket, false)
	carrier.transform = Transform3D()
	_hands(true)


func _to_back() -> void:
	drawn = false
	phase = ""
	t = 0.0
	if ik != null:
		ik.weight = 0.0
	carrier.top_level = false
	if carrier.get_parent() != back_socket:
		carrier.reparent(back_socket, false)
	carrier.transform = Transform3D()
	_hands(false)


func _hands(holding: bool) -> void:
	if open_hand == null or fist == null:
		return
	fist.visible = holding
	open_hand.visible = not holding


## True when the sword is home in the scabbard (smoke test).
func on_back() -> bool:
	return carrier.get_parent() == back_socket and phase == ""


func in_hand() -> bool:
	return carrier.get_parent() == hand_socket and phase == ""
