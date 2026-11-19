extends "res://scripts/hunt/bosses/field_boss.gd"
## A night boss from the pool: CASSIUS VANE, LUCIEN'S BLOOD KNIGHT. The Count's own champion,
## sent to drag Sol in. A field Blood Knight promoted: heavier plate, a longer reach, a
## crossing dash, a ground-splitting slam, and below half a ring of blood bolts.


func _build() -> void:
	is_field_boss = false
	kind = 0
	transformed = false
	aura_color = Color(0.95, 0.15, 0.55)
	base_overlay = Color(0.06, 0.05, 0.08, 0.62)
	vein_color = Color(1.0, 0.1, 0.5)
	vein_amount = 0.6
	vein_scale = 7.0
	body_radius = 0.75
	body_height = 3.1
	speed = 6.0
	keep_dist = 2.8
	var r := add_rig("vampire", 1.55, null, Color(1.0, 0.1, 0.45))
	add_plate_spikes(r)
	var plate := U.mat(Color(0.05, 0.05, 0.07), 0.35, 0.8)
	add_spikes(bone_mount(r, "Head"), 3, 0.22, Vector3(0, 1.0, -0.3), 1.2, plate, 0.035) # a crowned helm


func _choose_attack(dist: float) -> Dictionary:
	var r := randf()
	if enraged and r < 0.2:
		return {"type": "bolts", "windup": 0.7, "count": 10, "ring": true, "dmg": 12.0, "bolt_speed": 12.0, "recover": 0.6, "cd": 1.0}
	if dist > 7.0 or r < 0.3:
		return {"type": "dash", "windup": 0.65, "length": 14.0, "dmg": 20.0, "speed": 26.0, "recover": 0.7, "cd": 1.3,
			"chain": [{"type": "dash", "windup": 0.5, "length": 12.0, "dmg": 18.0, "speed": 26.0, "recover": 0.7}] if enraged else []}
	if r < 0.6:
		return {"type": "slam", "windup": 0.8, "self": true, "radius": 4.6, "dmg": 28.0, "recover": 0.9, "cd": 1.3}
	return {"type": "swipe", "windup": 0.55, "range": 3.6, "arc": 0.1, "dmg": 20.0, "recover": 0.55, "cd": 1.0,
		"chain": [{"type": "swipe", "windup": 0.4, "range": 3.6, "arc": 0.1, "dmg": 18.0, "recover": 0.6}]}


func _on_half() -> void:
	speed = 7.5
	windup_mult = 0.8
	base_overlay = Color(0.4, 0.0, 0.12, 0.5)
	aura.material_override = HFx.aura_mat(Color(1.0, 0.1, 0.5), 1.8)
	if director != null:
		director.boss_phase_text(self, "\"The Count wants you breathing. He never said whole.\"")
