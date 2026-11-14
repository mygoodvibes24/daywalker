extends "res://scripts/hunt/bosses/boss_base.gd"
## A Landmark's guardian: a named horror that waits (dormant) by its monument until Sol
## comes close or strikes it. Blood Knights wear blackened plate the sun can't get through;
## Old Gristle is a grey Pack alpha who never fully turned back. Leashed to its landmark.

var variant := "blood_knight"
var base_hp := 500.0


func _build() -> void:
	is_field_boss = true
	max_hp = base_hp
	arena_center = home
	arena_radius = 22.0
	if variant == "old_gristle":
		kind = 1
		transformed = true
		aura_color = Color(0.75, 0.55, 1.0)
		base_overlay = Color(0.35, 0.35, 0.38, 0.35)
		body_radius = 0.85
		body_height = 3.3
		speed = 7.0
		add_rig("werewolf", 1.4, null, Color(0.7, 0.5, 1.0))
	else:
		kind = 0
		transformed = false
		aura_color = Color(0.85, 0.2, 0.6)
		base_overlay = Color(0.08, 0.08, 0.11, 0.6) # blackened plate
		body_radius = 0.7
		body_height = 2.9
		speed = 5.5
		add_rig("vampire", 1.45, null, Color(1.0, 0.1, 0.4))


func _choose_attack(dist: float) -> Dictionary:
	var r := randf()
	if variant == "old_gristle":
		if dist > 6.0 or r < 0.3:
			return {"type": "slam", "windup": 0.8, "leap": 0.55, "radius": 3.8, "dmg": 22.0, "recover": 0.9, "cd": 1.5}
		return {"type": "swipe", "windup": 0.55, "range": 3.2, "arc": 0.15, "dmg": 16.0, "recover": 0.6, "cd": 1.1}
	if dist > 7.0 or r < 0.25:
		return {"type": "dash", "windup": 0.7, "length": 11.0, "dmg": 18.0, "speed": 24.0, "recover": 0.8, "cd": 1.5}
	if r < 0.55:
		return {"type": "slam", "windup": 0.85, "self": true, "radius": 4.0, "dmg": 24.0, "recover": 0.9, "cd": 1.4}
	return {"type": "swipe", "windup": 0.6, "range": 3.2, "arc": 0.15, "dmg": 18.0, "recover": 0.6, "cd": 1.1}


func _on_half() -> void:
	speed *= 1.25
	windup_mult = 0.85
