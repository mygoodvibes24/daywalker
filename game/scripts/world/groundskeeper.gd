extends Node3D
## Old Amos, St. Roch's night groundskeeper: a harmless civilian who stands by his fresh grave
## with a lantern and mutters a line when Sol comes near (Dialogue autoload, subtitles).
## Not an enemy: no hurtbox, not in the enemy list, only a capsule so Sol can't walk through him.
## Also runs the warm lights of his shed and dig site, which follow the street lamps (they wake
## at dusk with main's lamp material).

const TALK_R := 5.5
const LINES := "keeper_"

var lights: Array[OmniLight3D] = [] # set by cemetery.gd: [light, full energy] pairs in light_energy
var light_energy: Array[float] = []
var model: Node3D
var anim: AnimationPlayer
var _main: Node = null
var _talk_cd := 0.0
var _yaw0 := 0.0
var spoke := 0 # lines started (tests)


func _ready() -> void:
	_yaw0 = rotation.y
	var ps := load("res://assets/characters/civilian/civilian_anim.scn") as PackedScene
	if ps != null:
		model = ps.instantiate() as Node3D
		add_child(model)
		var sk := model.get_node_or_null("Skeleton") as Skeleton3D
		var body := sk.get_node_or_null("Body") as MeshInstance3D if sk != null else null
		if body != null:
			var h := body.get_aabb().size.y
			if h > 0.1:
				model.scale = Vector3.ONE * (1.74 / h)
			# a darker, older work coat than the city's civilians
			var tint := StandardMaterial3D.new()
			tint.albedo_color = Color(0.0, 0.0, 0.0, 0.25)
			tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			body.material_overlay = tint
			_hat(sk)
		anim = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if anim != null and anim.has_animation("idle"):
			anim.play("idle")
			anim.speed_scale = 0.8
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	body.add_child(cs)
	add_child(body)


## A flat cap on the head bone, so he never reads as one of the Pack's civilians.
func _hat(sk: Skeleton3D) -> void:
	var hb := -1
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).to_lower().contains("head"):
			hb = i
			break
	if hb < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = hb
	sk.add_child(att)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.105
	cyl.bottom_radius = 0.115
	cyl.height = 0.07
	cyl.radial_segments = 10
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.11, 0.09)
	m.roughness = 0.95
	mi.material_override = m
	var s := 1.0 / maxf(model.scale.x, 0.001)
	mi.scale = Vector3.ONE * s
	mi.position = Vector3(0, 0.16, 0.0) * s
	att.add_child(mi)
	var brim := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.015, 0.1)
	brim.mesh = bm
	brim.material_override = m
	brim.scale = mi.scale
	brim.position = Vector3(0, 0.135, 0.1) * s
	att.add_child(brim)


func _main_node() -> Node:
	if _main == null:
		var n: Node = get_parent()
		while n != null and n.get("player") == null:
			n = n.get_parent()
		_main = n
	return _main


func _process(delta: float) -> void:
	var m := _main_node()
	if m == null:
		return
	# lights follow the street lamps (lamp_mat energy: 0.2 by day, up to ~6 at night)
	var lm = m.get("lamp_mat")
	if lm != null:
		var k := clampf((float(lm.emission_energy_multiplier) - 0.2) / 3.0, 0.0, 1.0)
		for i in lights.size():
			lights[i].light_energy = light_energy[i] * k
			lights[i].visible = k > 0.02
	var p = m.get("player")
	if p == null:
		return
	_talk_cd -= delta
	var to: Vector3 = p.global_position - global_position
	to.y = 0.0
	var d := to.length()
	# turn to watch Sol while he is close, back to the grave when he leaves
	var want := atan2(to.x, to.z) if d < 9.0 else _yaw0
	rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * 2.0))
	if d < TALK_R and _talk_cd <= 0.0:
		var dlg := get_node_or_null("/root/Dialogue")
		if dlg != null and dlg.play_group(LINES):
			spoke += 1
		_talk_cd = 14.0
