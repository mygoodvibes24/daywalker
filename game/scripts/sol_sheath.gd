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
const ItemDB = preload("res://scripts/items/item_db.gd")
const STOW := 0.24
const LET_GO := 0.2
const SPINE_BONE := "Spine02"
## WEAPON MOUNTS (the per-weapon field the Arsenal sets). Where a sheathed weapon rides, in Sol's
## skeleton space at rest (+X is his left, +Y up, +Z forward). The carried weapon's own frame is the
## hand's grip frame: blade along +Z from the grip, flat facing +-X.
##   bone      the bone it rides (Spine02 for the back, Hips for a belt)
##   grip      where the grip sits; with "surface": "back" its z is BACK_GAP out from the coat's back
##   dir       where the blade points (normalised for you)
##   flat      the direction the blade's flat faces (made perpendicular to dir)
##   pole      the elbow direction of the reach (sol_draw_ik.gd), from the shoulder
##   reach / pull   seconds: the hand to the grip, then the weapon out into the fist (~0.3 s total)
##   scabbard  false: no sheath drawn (an axe or a hammer hangs bare)
## An item picks one with `"mount": "<preset>"` in its item_db.gd def, or tunes one with a Dictionary
## (`{"preset": "back", "grip": Vector3(...)}`: missing keys come from the preset). Without one, the
## family default (FAMILY_MOUNT), else "back".
const MOUNTS := {
	# over the right shoulder, the blade down across the back toward the left hip
	"back": {"bone": "Spine02", "grip": Vector3(-0.16, 1.72, 0.0), "surface": "back", "dir": Vector3(0.45, -0.89, 0.0),
		"flat": Vector3(0, 0, -1), "pole": Vector3(-0.55, 0.75, -0.25), "reach": 0.15, "pull": 0.14, "scabbard": true},
	# a long or great blade: steeper, the grip higher behind the shoulder so the tip clears the calves
	"back_great": {"bone": "Spine02", "grip": Vector3(-0.13, 1.8, 0.0), "surface": "back", "dir": Vector3(0.28, -0.96, 0.0),
		"flat": Vector3(0, 0, -1), "pole": Vector3(-0.5, 0.85, -0.25), "reach": 0.17, "pull": 0.17, "scabbard": true},
	# a short blade on the left hip, worn for the cross-draw: grip forward, blade back and down
	"hip": {"bone": "Hips", "grip": Vector3(0.25, 1.0, 0.12), "dir": Vector3(0.08, -0.4, -0.91),
		"flat": Vector3(1, 0, 0), "pole": Vector3(-0.6, -0.1, 0.45), "reach": 0.13, "pull": 0.12, "scabbard": true},
	# a knife or a dagger at the right hip, blade down (a quick back-hand draw)
	"hip_right": {"bone": "Hips", "grip": Vector3(-0.25, 1.02, -0.02), "dir": Vector3(-0.08, -0.97, -0.22),
		"flat": Vector3(1, 0, 0), "pole": Vector3(-0.7, -0.2, -0.2), "reach": 0.1, "pull": 0.1, "scabbard": true},
}
const FAMILY_MOUNT := {"kukri": "hip", "longblade": "back_great"}
const BACK_GAP := 0.043
static var _back_z := 0.0 # the coat's back surface (measured once from the coat mesh)

var skel: Skeleton3D
var hand_socket: Node3D # HandR/Blade
var back_socket: Node3D
var carrier: Node3D
var scabbard: Node3D
var ik: Node
var fist: Node3D
var open_hand: Node3D
var mount_att: BoneAttachment3D
var mount: Dictionary = MOUNTS.back
var mount_name := "back"
var reach_t := 0.15 # the current mount's reach / pull times
var pull_t := 0.14
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
	# the mount (back or belt; set_mount moves it per weapon)
	mount_att = BoneAttachment3D.new()
	mount_att.name = "BackMount"
	mount_att.bone_name = SPINE_BONE
	skel.add_child(mount_att)
	back_socket = Node3D.new()
	back_socket.name = "BackSocket"
	mount_att.add_child(back_socket)
	if _back_z == 0.0:
		_back_z = _measure_back(model)
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
	set_mount(MOUNTS.back, "back")
	fit_scabbard()
	return true


## The mount an item's weapon rides on when sheathed (see MOUNTS).
static func mount_for(item: Dictionary) -> Dictionary:
	var m = _mount_field(item)
	if m is Dictionary:
		var base: Dictionary = MOUNTS.get(m.get("preset", "back"), MOUNTS.back).duplicate()
		base.merge(m, true)
		return base
	return MOUNTS.get(m, MOUNTS.back)


## The preset name an item mounts on ("back", "hip", ...; a tuned Dictionary reports its preset).
static func mount_name_for(item: Dictionary) -> String:
	var m = _mount_field(item)
	if m is Dictionary:
		m = m.get("preset", "back")
	return str(m) if MOUNTS.has(m) else "back"


static func _mount_field(item: Dictionary):
	if item.is_empty():
		return "back"
	if item.has("mount"):
		return item.mount # an instance may carry its own (a test, a one-off)
	var d: Dictionary = ItemDB.get_def(item.get("id", "marrow_silver"))
	return d.get("mount", FAMILY_MOUNT.get(d.get("family", ""), "back"))


## Move the sheath to mount `m` (a MOUNTS entry, or an item's tuned one). A sheathed weapon follows.
func set_mount(m: Dictionary, mname := "") -> void:
	mount = m
	mount_name = mname
	var bone: String = m.get("bone", SPINE_BONE)
	if skel.find_bone(bone) < 0:
		bone = SPINE_BONE
	mount_att.bone_name = bone
	var z: Vector3 = Vector3(m.get("dir", Vector3(0, -1, 0))).normalized()
	var x: Vector3 = m.get("flat", Vector3(0, 0, -1))
	x = x - z * x.dot(z)
	if x.length() < 0.01:
		x = Vector3(1, 0, 0) - z * z.x
	x = x.normalized()
	var g: Vector3 = m.get("grip", Vector3(-0.16, 1.72, 0.0))
	if m.get("surface", "") == "back":
		g.z = _back_z - BACK_GAP
	var want := Transform3D(Basis(x, z.cross(x), z), g)
	back_socket.transform = skel.get_bone_global_rest(skel.find_bone(bone)).affine_inverse() * want
	reach_t = float(m.get("reach", 0.15))
	pull_t = float(m.get("pull", 0.14))
	if ik != null:
		ik.pole = m.get("pole", Vector3(-0.55, 0.75, -0.25))
	scabbard.visible = bool(m.get("scabbard", true))


## A new weapon is in the carrier: move to its mount and refit the scabbard around it.
func use_item(item: Dictionary) -> void:
	set_mount(mount_for(item), mount_name_for(item))
	fit_scabbard()


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
		return maxf(reach_t - t, 0.0) if phase == "reach" else 0.0
	if instant:
		_to_hand()
		return 0.0
	drawn = true
	if phase == "stow":
		# changed his mind mid-stow: the blade is still in hand, carry it straight back
		phase = "pull"
		t = pull_t * 0.5
		return 0.0
	phase = "reach"
	t = 0.0
	return reach_t


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
			var k := clampf(t / reach_t, 0.0, 1.0)
			ik.weight = k * k * (3.0 - 2.0 * k)
			ik.orient = 0.6
			ik.target = _hand_target()
			if t >= reach_t:
				_grab()
		"pull":
			var k := clampf(t / pull_t, 0.0, 1.0)
			ik.weight = 1.0 - k * k * (3.0 - 2.0 * k)
			ik.target = _hand_target()
			var s := k * k * (3.0 - 2.0 * k)
			carrier.global_transform = back_socket.global_transform.interpolate_with(hand_socket.global_transform, s)
			if t >= pull_t:
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
