extends Node
## Gives Nia's unrigged statue-pose mesh some life: slow breathing (a tiny vertical
## scale), a gentle weight shift, and now and then a small head-tilt read through the
## whole body, as if she is scrolling and thinking. Deliberately subtle.

var body: Node3D
var base_pos := Vector3.ZERO
var base_rot := Vector3.ZERO
var t := 0.0
var tilt := 0.0
var tilt_target := 0.0
var next_tilt := 4.0


func setup(n: Node3D) -> void:
	body = n
	base_pos = n.position
	base_rot = n.rotation
	t = randf() * 10.0


func _process(delta: float) -> void:
	if body == null:
		return
	t += delta
	next_tilt -= delta
	if next_tilt <= 0.0:
		next_tilt = randf_range(5.0, 9.0)
		tilt_target = 0.0 if absf(tilt_target) > 0.001 else randf_range(-1.0, 1.0) * 0.02
	tilt = lerpf(tilt, tilt_target, clampf(delta * 1.2, 0.0, 1.0))
	var breath := sin(t * TAU / 4.2) # one breath every ~4 s
	var sway := sin(t * 0.37) * 0.6 + sin(t * 0.21 + 1.3) * 0.4
	body.scale = Vector3(1.0 + breath * 0.002, 1.0 + breath * 0.004, 1.0 + breath * 0.003)
	body.position = base_pos + Vector3(sway * 0.008, 0.0, 0.0)
	body.rotation = base_rot + Vector3(tilt * 0.4, sway * 0.012, sway * 0.006 + tilt)
