extends Node3D
## The chain-whip's links (weapon_forge.gd builds them as Link0..LinkN children): a cheap verlet chain.
## At rest it hangs and sways off the handle; while `extend` is up (arsenal.gd raises it during a move)
## it is pulled out straight along the handle, so the lash reads as a whip cracking out to its reach.
## One small loop over 14 links per frame, no physics bodies.

const LINKS := 14
const SEG := 0.105
const START := 0.11 # the first link's distance from the grip along +Z
const GRAVITY := 9.0

var extend := 0.0 # 0 hanging .. 1 pulled out straight
var _p: PackedVector3Array
var _prev: PackedVector3Array
var _links: Array[Node3D] = []
var _ready_sim := false


func _ready() -> void:
	for i in LINKS:
		var n := get_node_or_null("Link%d" % i) as Node3D
		if n != null:
			_links.append(n)
	set_process(true)


func _reset() -> void:
	_p = PackedVector3Array()
	_prev = PackedVector3Array()
	var base := global_transform
	for i in _links.size():
		var q := base * Vector3(0, 0, START + i * SEG)
		_p.append(q)
		_prev.append(q)
	_ready_sim = true


func _process(delta: float) -> void:
	if _links.is_empty() or not is_inside_tree() or not is_visible_in_tree():
		return
	if not _ready_sim:
		_reset()
	var dt := clampf(delta, 0.001, 0.05)
	var base := global_transform
	var dir := base.basis.z.normalized()
	var anchor := base.origin + dir * START
	var pull := clampf(extend, 0.0, 1.0)
	# verlet step: inertia + gravity, then pull toward the straight line (more while extended)
	for i in _p.size():
		var cur := _p[i]
		var vel := (cur - _prev[i]) * 0.9
		_prev[i] = cur
		var nxt := cur + vel + Vector3.DOWN * GRAVITY * (1.0 - pull) * dt * dt
		var straight := anchor + dir * (i * SEG)
		nxt = nxt.lerp(straight, (0.05 + 0.6 * pull) * (1.0 - float(i) / (_p.size() * 1.6)))
		_p[i] = nxt
	# keep the links SEG apart, the first one at the handle
	for it in 2:
		_p[0] = anchor
		for i in range(1, _p.size()):
			var d := _p[i] - _p[i - 1]
			var l := d.length()
			if l > 0.0001:
				_p[i] = _p[i - 1] + d * (SEG / l)
	# pose the link meshes along the chain (each mesh runs along its own +Z, centred)
	for i in _links.size():
		var a := _p[i]
		var b := _p[i + 1] if i + 1 < _p.size() else a + (a - _p[i - 1])
		var fwd := (b - a)
		if fwd.length() < 0.0001:
			fwd = dir
		fwd = fwd.normalized()
		var up := base.basis.y if absf(fwd.dot(base.basis.y)) < 0.95 else base.basis.x
		var bas := Basis.looking_at(-fwd, up)
		_links[i].global_transform = Transform3D(bas, (a + b) * 0.5)
	if extend > 0.0:
		extend = move_toward(extend, 0.0, dt * 1.2)


## The world position of the chain's tip (the barb), for the slash trail.
func tip() -> Vector3:
	if _p.is_empty():
		return global_transform * Vector3(0, 0, START + LINKS * SEG)
	return _p[_p.size() - 1]
