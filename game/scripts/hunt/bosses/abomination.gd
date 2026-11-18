extends "res://scripts/hunt/bosses/boss_base.gd"
## The Final Night — SERAPHINE'S ABOMINATION. A Pack giant with a Velvet Court body fused
## to its shoulders (the wolf and vampire rigs combined). Phase 1 fights like a wolf: leap
## slams, swipes, a howl that calls one of each. Phase 2 (below half) the vampire half wakes:
## rings of blood bolts, blinks and dash slashes, faster and angrier.

var howl_cd := 8.0
var rider: Dictionary
const RIDER_OFFSET := Vector3(0, -0.42, -0.12) # in the wolf's model metres, from its upper spine
const RIDER_PITCH := 0.25
const RIDER_SCALE := 0.62


func _build() -> void:
	kind = 1
	transformed = true
	aura_color = Color(0.9, 0.0, 0.12)
	base_overlay = Color(0.25, 0.0, 0.05, 0.35)
	body_radius = 1.1
	body_height = 4.2
	speed = 6.5
	keep_dist = 2.6
	vein_color = Color(1.0, 0.0, 0.15)
	vein_amount = 1.1
	vein_scale = 4.5
	vein_width = 0.07
	var wolf := add_rig("werewolf", 1.9, null, Color(1.0, 0.1, 0.1))
	# the fused rider: a Velvet Court torso growing out of the wolf's back (its legs are
	# scaled away in boss_base._process); it plays the same clips as the wolf, a beat apart
	var mount: Node3D = bone_mount(wolf, "Spine")
	var holder := Node3D.new()
	(mount if mount != null else visual).add_child(holder)
	if mount == null:
		holder.position = Vector3(0, 3.4, -0.4)
		holder.scale = Vector3.ONE * 0.8
	else:
		holder.position = RIDER_OFFSET
		holder.rotation = Vector3(RIDER_PITCH, 0, 0)
		holder.scale = Vector3.ONE * RIDER_SCALE
	rider = add_rig("vampire", 1.0, holder, Color(1.0, 0.0, 0.2), true)
	# silhouette: blood-bone spikes bursting from the spine and shoulders, glowing
	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.55, 0.45, 0.4)
	bone_mat.emission_enabled = true
	bone_mat.emission = Color(1.0, 0.05, 0.1)
	bone_mat.emission_energy_multiplier = 1.2
	bone_mat.roughness = 0.5
	add_spikes(bone_mount(wolf, "Spine02"), 4, 0.5, Vector3(0, 0.8, -1.0), 1.6, bone_mat, 0.07)
	add_spikes(bone_mount(wolf, "Spine01"), 5, 0.6, Vector3(0, 0.7, -1.0), 2.0, bone_mat, 0.08)
	add_spikes(bone_mount(wolf, "LeftArm"), 3, 0.45, Vector3(-0.6, 1.0, -0.4), 1.2, bone_mat, 0.06)
	add_spikes(bone_mount(wolf, "RightArm"), 3, 0.45, Vector3(0.6, 1.0, -0.4), 1.2, bone_mat, 0.06)


func _physics_process(delta: float) -> void:
	howl_cd -= delta
	super(delta)


func _choose_attack(dist: float) -> Dictionary:
	var r := randf()
	if not enraged:
		var living: int = director.summons_alive() if director != null else 0
		if howl_cd <= 0.0 and living < 2:
			howl_cd = 18.0
			return {"type": "howl", "windup": 1.0, "summon": [1, 0], "recover": 0.6, "cd": 0.8}
		if dist > 7.0 or r < 0.3:
			return {"type": "slam", "windup": 0.8, "leap": 0.65, "radius": 5.0, "dmg": 32.0, "recover": 0.9, "cd": 1.4}
		return {"type": "swipe", "windup": 0.6, "range": 3.9, "arc": 0.05, "dmg": 24.0, "recover": 0.6, "cd": 1.1}
	# phase 2: the Court half fights too
	if r < 0.22:
		return {"type": "bolts", "windup": 0.7, "count": 14, "ring": true, "dmg": 12.0, "bolt_speed": 12.0, "recover": 0.5, "cd": 0.9}
	if r < 0.4:
		return {"type": "blink", "windup": 0.1, "cd": 1.0, "then": {"type": "slam", "windup": 0.55, "self": true, "radius": 4.6, "dmg": 30.0, "recover": 0.8}}
	if r < 0.62:
		return {"type": "dash", "windup": 0.6, "length": 15.0, "dmg": 22.0, "speed": 30.0, "recover": 0.5, "cd": 1.2,
			"chain": [{"type": "dash", "windup": 0.45, "length": 14.0, "dmg": 20.0, "speed": 30.0, "recover": 0.6}]}
	if dist > 7.0 or r < 0.8:
		return {"type": "slam", "windup": 0.6, "leap": 0.55, "radius": 5.2, "dmg": 32.0, "recover": 0.7, "cd": 1.1}
	return {"type": "swipe", "windup": 0.45, "range": 3.9, "arc": 0.05, "dmg": 24.0, "recover": 0.5, "cd": 0.9,
		"chain": [{"type": "bolts", "windup": 0.4, "count": 5, "spread": 0.9, "dmg": 11.0, "recover": 0.5}]}


func _on_half() -> void:
	# PHASE 2: a roar, a moment of invulnerability, and the rider tears loose
	invuln_t = 1.6
	state = "recover"
	state_t = 1.6
	atk = {"type": "howl", "cd": 0.6}
	howl_b = 1.0
	speed = 8.5
	windup_mult = 0.8
	base_overlay = Color(0.75, 0.0, 0.08, 0.4)
	aura.material_override = HFx.aura_mat(Color(1.0, 0.0, 0.15), 2.2)
	aura.scale *= 1.25
	light.light_energy = 3.0
	if rider.model != null:
		var tw := create_tween()
		tw.tween_property(rider.model, "scale", rider.model.scale * 1.35, 1.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	HFx.shockwave(main, global_position, 12.0, aura_color, 0.8)
	if director != null:
		director.boss_phase_text(self, "THE COURT HALF AWAKENS")
