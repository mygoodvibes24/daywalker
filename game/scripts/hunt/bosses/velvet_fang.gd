extends "res://scripts/hunt/bosses/boss_base.gd"
## Night 2 — MARCUS CRANE, THE VELVET FANG. Sol's mirror: a speed vampire duelist.
## Chained dash slashes along telegraphed lines, a blink that lands behind you, and fans
## of blood bolts. Below half he gets faster and his fans wider.


func _build() -> void:
	kind = 0
	transformed = false
	aura_color = Color(1.0, 0.04, 0.12)
	base_overlay = Color(0.35, 0.0, 0.03, 0.18)
	body_radius = 0.6
	body_height = 2.4
	speed = 8.5
	keep_dist = 3.0
	add_rig("vampire", 1.25, null, Color(1.0, 0.05, 0.05))


func _choose_attack(dist: float) -> Dictionary:
	var r := randf()
	var dash := {"type": "dash", "windup": 0.55, "length": 13.0, "dmg": 14.0, "speed": 32.0, "recover": 0.5, "cd": 1.1}
	var chain: Array = []
	for i in (3 if enraged else 2):
		chain.append({"type": "dash", "windup": 0.4, "length": 12.0, "dmg": 13.0, "speed": 32.0, "recover": 0.45})
	dash["chain"] = chain
	var bolts := {"type": "bolts", "windup": 0.55, "count": 7 if enraged else 5, "spread": 1.1, "dmg": 10.0, "recover": 0.45, "cd": 1.0}
	if dist > 9.0:
		return dash if r < 0.55 else bolts
	if r < 0.3:
		return {"type": "blink", "windup": 0.1, "cd": 0.9, "then": {"type": "swipe", "windup": 0.42, "range": 3.0, "arc": 0.2, "dmg": 16.0, "recover": 0.5}}
	if r < 0.55:
		return bolts
	if r < 0.8:
		return dash
	return {"type": "swipe", "windup": 0.45, "range": 2.8, "arc": 0.2, "dmg": 15.0, "recover": 0.4, "cd": 0.8,
		"chain": [{"type": "swipe", "windup": 0.3, "range": 2.8, "arc": 0.2, "dmg": 15.0, "recover": 0.5}]}


func _on_half() -> void:
	speed = 10.5
	windup_mult = 0.78
	base_overlay = Color(0.6, 0.0, 0.05, 0.3)
	aura.material_override = HFx.aura_mat(Color(1.0, 0.0, 0.1), 1.8)
	if director != null:
		director.boss_phase_text(self, "\"You and I were made the same, Marrow.\"")
