extends Node3D
## Turns a regular enemy (enemy.gd) into a named elite without touching its script:
## stat multipliers, a bigger body, a fresnel aura and a name plate. Rides as a child
## of the enemy, so it goes when the enemy does. Re-applies after a wolf transform
## (which resets the enemy's stats and swaps its model).

const HFx = preload("res://scripts/hunt/hunt_fx.gd")

var e # the enemy (enemy.gd public API: kind, max_hp, hp, damage, speed, transformed, model, visual, dead)
var def: Dictionary
var display_name := ""
var label: Label3D
var aura: MeshInstance3D
var _tf := false
var _model: Node3D


static func apply(enemy: Node3D, elite_def: Dictionary, name_: String) -> Node3D:
	var el = load("res://scripts/hunt/elite.gd").new()
	el.e = enemy
	el.def = elite_def
	el.display_name = name_
	el.name = "Elite"
	enemy.add_child(el)
	return el


func _ready() -> void:
	_buff()
	_tf = e.transformed
	var s: float = def.get("scale", 1.2)
	aura = HFx.aura(self, def.get("aura", Color(1, 0.1, 0.2)), 1.3 * s, 2.3 * s, 0.9)
	label = Label3D.new()
	label.text = display_name.to_upper()
	label.font_size = 40
	label.outline_size = 10
	label.modulate = def.get("aura", Color(1, 0.3, 0.3)).lightened(0.35)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.006
	label.position = Vector3(0, 2.6 * s + 0.3, 0)
	add_child(label)


func _buff() -> void:
	e.max_hp *= def.get("hp", 2.5)
	e.hp = e.max_hp
	e.damage *= def.get("dmg", 1.5)
	e.speed *= def.get("speed", 1.0)


func _process(_delta: float) -> void:
	if e == null or e.dead:
		if label != null:
			label.visible = false
		if aura != null:
			aura.visible = false
		return
	if e.transformed != _tf: # a transform (or sunrise) just reset his stats
		_tf = e.transformed
		_buff()
		label.position.y = (3.4 if _tf else 2.6) * def.get("scale", 1.2) + 0.3
		aura.scale.y = (3.0 if _tf else 2.3) * def.get("scale", 1.2)
		aura.position.y = aura.scale.y * 0.5
	var m: Node3D = e.get("model")
	var s: float = def.get("scale", 1.2)
	if m != null and is_instance_valid(m):
		if m != _model or not m.scale.is_equal_approx(Vector3.ONE * s):
			_model = m
			m.scale = Vector3.ONE * s
	elif e.get("visual") != null and _model == null:
		_model = e.visual
		var v: Node3D = e.visual
		v.scale = Vector3.ONE * s
	var hp_frac := clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
	label.text = "%s\n%s" % [display_name.to_upper(), "|".repeat(int(round(hp_frac * 20.0))).rpad(20, ".")]
