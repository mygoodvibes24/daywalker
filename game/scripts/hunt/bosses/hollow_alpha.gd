extends "res://scripts/hunt/bosses/boss_base.gd"
## THE HOLLOW ALPHA, Mother Wren's firstborn. A giant of the Hollow Pack: leap slams across
## the arena, raking swipes, a howl that brings two wolves, and a frenzy below half health.
## Look: the werewolf body at 1.35x (3.2 m) on the round-3 werewolf mocap (feral run, heavy
## overhead swipe, pounce, heavy fall, and the roar for its howl), amber veins, a mane of quills.

var howl_cd := 6.0
const MODEL_SCALE := 1.35 # the round-3 manifest: 2.4 m * 1.35 = 3.24 m


func _build() -> void:
	kind = 1
	transformed = true
	aura_color = Color(1.0, 0.5, 0.08)
	base_overlay = Color(0.12, 0.06, 0.02, 0.25)
	vein_color = Color(1.0, 0.55, 0.08)
	vein_amount = 0.7
	vein_scale = 5.0
	body_radius = 0.85
	body_height = 3.3
	speed = 7.0
	keep_dist = 2.4
	var r := add_rig("werewolf", MODEL_SCALE, null, Color(1.0, 0.7, 0.1))
	# silhouette: a mane of black quills round the neck and down the spine
	var fur := U.mat(Color(0.05, 0.04, 0.035), 0.95)
	add_spikes(bone_mount(r, "neck"), 7, 0.42, Vector3(0, 0.55, -1.0), 2.6, fur, 0.07)
	add_spikes(bone_mount(r, "Spine01"), 5, 0.36, Vector3(0, 0.8, -1.0), 1.4, fur, 0.07)
	add_spikes(bone_mount(r, "Spine02"), 4, 0.28, Vector3(0, 0.9, -1.0), 1.0, fur, 0.06)


func _physics_process(delta: float) -> void:
	howl_cd -= delta
	super(delta)


func _choose_attack(dist: float) -> Dictionary:
	var living: int = director.summons_alive() if director != null else 0
	if howl_cd <= 0.0 and living < 2:
		howl_cd = 16.0 if not enraged else 11.0
		return {"type": "howl", "windup": 1.0, "summon": [1, 1], "recover": 0.6, "cd": 0.8}
	if dist > 7.0 or randf() < 0.25:
		return {"type": "slam", "windup": 0.75, "leap": 0.6, "radius": 4.6, "dmg": 30.0, "recover": 0.9, "cd": 1.4}
	var swipe := {"type": "swipe", "windup": 0.55, "range": 3.6, "arc": 0.1, "dmg": 20.0, "recover": 0.55, "cd": 1.0}
	if enraged:
		swipe["chain"] = [{"type": "swipe", "windup": 0.35, "range": 3.6, "arc": 0.1, "dmg": 18.0, "recover": 0.5}]
	return swipe


func _on_half() -> void:
	# FRENZY: faster, quicker wind-ups, and he calls the pack at once
	speed = 9.5
	windup_mult = 0.72
	howl_cd = 0.0
	base_overlay = Color(0.5, 0.02, 0.0, 0.3)
	aura.material_override = HFx.aura_mat(Color(1.0, 0.2, 0.05), 1.6)
	if director != null:
		director.boss_phase_text(self, "THE ALPHA FRENZIES")
