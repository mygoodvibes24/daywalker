extends Node3D
## The Descent: Sol's entrance into a Hunt. A ~3 s cinematic at one of the deployment
## points on the map edge (never the plaza): climbing out of a Vesper Line station mouth,
## bursting up through a storm-drain manhole, or dropping off a roofline with a landing
## slam while the camera swoops in. Control is handed over at the end.

const HFx = preload("res://scripts/hunt/hunt_fx.gd")
const Dressing = preload("res://scripts/hunt/poi_dressing.gd")

signal finished

var main
var point: Dictionary
var cam: Camera3D
var t := 0.0
var dur := 3.0
var playing := false
var cam_from := Vector3.ZERO
var cam_to := Vector3.ZERO
var dressing := {}
var slammed := false
var tw: Tween


## Build the dressing for every deployment point (they're part of the city in any Hunt).
static func build_points(parent: Node3D) -> Dictionary:
	var out := {}
	for d in preload("res://scripts/hunt/hunt_config.gd").DEPLOY_POINTS:
		var root := Node3D.new()
		root.name = "Deploy_" + d.name.replace(" ", "_").replace(".", "")
		parent.add_child(root)
		root.position = d.pos
		out[d.name] = Dressing.deploy_point(d.type, root, d.face)
	return out


func play(p: Dictionary, dressings: Dictionary) -> void:
	point = p
	dressing = dressings.get(p.name, {})
	var pl = main.player
	var face: Vector3 = p.face
	var yaw := atan2(face.x, face.z)
	pl.set_physics_process(false)
	pl.velocity = Vector3.ZERO
	pl.facing = yaw
	pl.visual.rotation.y = yaw
	pl.cam_yaw = atan2(-face.x, -face.z) # the follow camera ends up behind him, looking in
	pl.cam_pitch = -0.22
	cam = Camera3D.new()
	cam.fov = 62.0
	add_child(cam)
	cam.current = true
	var pos: Vector3 = p.pos
	var side := Vector3(face.z, 0, -face.x)
	tw = create_tween()
	match p.type:
		"subway":
			dur = 3.0
			pl.global_position = pos - face * 3.6 + Vector3(0, -2.6, 0)
			tw.tween_property(pl, "global_position", pos - face * 1.7 + Vector3(0, -0.7, 0), 1.4).set_trans(Tween.TRANS_SINE)
			tw.tween_property(pl, "global_position", pos + face * 1.2 + Vector3(0, 0.15, 0), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			cam_from = pos + face * 5.5 + side * 2.0 + Vector3(0, 0.6, 0)
			cam_to = pos - face * 3.4 + side * 1.2 + Vector3(0, 2.6, 0)
		"manhole":
			dur = 2.6
			pl.global_position = pos + Vector3(0, -2.2, 0)
			tw.tween_property(pl, "global_position", pos + face * 0.6 + Vector3(0, 3.2, 0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(pl, "global_position", pos + face * 1.6 + Vector3(0, 0.15, 0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(_slam.bind(0.25))
			if dressing.has("cover"):
				var cover: Node3D = dressing.cover
				var ct := create_tween()
				ct.tween_property(cover, "position", cover.position + Vector3(0.6, 2.4, 0.2), 0.35).set_ease(Tween.EASE_OUT)
				ct.parallel().tween_property(cover, "rotation", Vector3(2.8, 0.7, 1.2), 0.7)
				ct.tween_property(cover, "position", cover.position + Vector3(1.6, 0.04, 0.9), 0.4).set_ease(Tween.EASE_IN)
			HFx.puff(main, pos + Vector3(0, 0.2, 0), Color(0.5, 0.5, 0.5), 10, 0.25, 1.6)
			cam_from = pos + face * 6.0 + side * 3.0 + Vector3(0, 1.0, 0)
			cam_to = pos - face * 2.4 + side * 1.0 + Vector3(0, 2.8, 0)
		_: # rooftop
			dur = 3.2
			pl.global_position = pos - face * 5.0 + side * 6.0 + Vector3(0, 17.0, 0)
			tw.tween_interval(0.7)
			tw.tween_property(pl, "global_position", pos + Vector3(0, 0.15, 0), 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(_slam.bind(1.0))
			cam_from = pos + face * 16.0 - side * 4.0 + Vector3(0, 24.0, 0)
			cam_to = pos - face * 3.6 + side * 1.4 + Vector3(0, 2.6, 0)
	cam.global_position = cam_from
	playing = true
	t = 0.0
	if main.hud != null:
		main.hud.announce("THE HUNT BEGINS\n" + p.name)


func _slam(power: float) -> void:
	if slammed:
		return
	slammed = true
	var pos: Vector3 = main.player.global_position
	HFx.shockwave(main, pos, 3.0 + 6.0 * power, Color(1.0, 0.2, 0.15), 0.5)
	HFx.puff(main, pos + Vector3(0, 0.3, 0), Color(0.45, 0.42, 0.4), 14, 0.3, 2.0 + 3.0 * power)
	main.player.shake = maxf(main.player.shake, 0.3 + 0.4 * power)
	main.rumble(0.4, 0.8 * power, 0.35)
	if power > 0.5:
		main.set_slowmo(0.35, 0.35)


func _process(delta: float) -> void:
	if not playing:
		return
	t += delta
	var k := clampf(t / dur, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	cam.global_position = cam_from.lerp(cam_to, e)
	var look: Vector3 = main.player.global_position + Vector3(0, 1.3, 0)
	if cam.global_position.distance_to(look) > 0.5:
		cam.look_at(look, Vector3.UP)
	if t >= dur:
		finish()


## Hand control to the player (also used to skip the cinematic).
func finish() -> void:
	if not playing:
		return
	playing = false
	if tw != null and tw.is_valid():
		tw.kill()
	var pl = main.player
	pl.global_position = Vector3(pl.global_position.x, 0.15, pl.global_position.z)
	pl.set_physics_process(true)
	pl.camera.current = true
	pl.block_attack()
	if cam != null:
		cam.queue_free()
	finished.emit()
