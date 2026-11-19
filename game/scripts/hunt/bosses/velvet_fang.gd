extends "res://scripts/hunt/bosses/boss_base.gd"
## MARCUS CRANE, THE VELVET FANG. Sol's mirror: a speed vampire duelist.
## Chained dash slashes along telegraphed lines, a blink that lands behind you, and fans
## of blood bolts. Below half he gets faster and his fans wider.
## Look: his own body (asset round 3: a 1.88 m scan-style mesh in a black velvet frock coat with
## crimson lining, rigged, with his own slash combo, lunge and death mocap), at 1.2x for boss
## presence. With his own model the glowing vein overlay and the fresnel aura shell are left off
## (critic round 2: they hid the new model); the stand-in keeps them. The coat material is forced matte in tools/build_r3_anims.gd.
## If his model is missing, the older stand-in returns: the vampire body with a velvet cape.

const MODEL_SCALE := 1.2 # 1.88 m * 1.2 = 2.26 m, the stand-in's height
var own_model := false


func _build() -> void:
	kind = 0
	transformed = false
	aura_color = Color(1.0, 0.04, 0.12)
	base_overlay = Color(0.35, 0.0, 0.03, 0.18)
	vein_color = Color(1.0, 0.02, 0.2)
	vein_amount = 0.55
	vein_scale = 8.0
	body_radius = 0.6
	body_height = 2.4
	speed = 8.5
	keep_dist = 3.0
	own_model = ResourceLoader.exists(ANIM_PATHS.marcus)
	if own_model:
		add_rig("marcus", MODEL_SCALE, null, Color(1.0, 0.05, 0.05))
		vein_amount = 0.0 # no lava veins over the velvet
		base_overlay = Color(0, 0, 0, 0)
	else:
		_add_cape(add_rig("vampire", 1.22, null, Color(1.0, 0.05, 0.05)))


func _ready() -> void:
	super()
	if own_model:
		aura.visible = false # no shield bubble round him


## Marcus's own sounds: claw swipes instead of the blade, a coat-flutter whoosh on his dashes.
func _sfx(name: String, pos: Vector3, db := 0.0) -> void:
	if name == "boss_swipe":
		name = "lunge_whoosh" if state == "act" else "claw_swipe"
	super(name, pos, db)


## The cape hangs from the shoulders; it flares back when he runs and snaps up on a dash
## (boss_base._sway).
func _add_cape(r: Dictionary) -> void:
	var mount := bone_mount(r, "Spine")
	if mount == null:
		return
	var pivot := Node3D.new()
	mount.add_child(pivot)
	pivot.position = Vector3(0, 0.12, -0.13)
	var outer := StandardMaterial3D.new()
	outer.albedo_color = Color(0.07, 0.015, 0.03)
	outer.roughness = 0.75
	outer.cull_mode = BaseMaterial3D.CULL_DISABLED
	outer.rim_enabled = true
	outer.rim = 0.4
	outer.rim_tint = 0.8
	var cape := MeshInstance3D.new()
	cape.mesh = cape_mesh(0.42, 0.66, 1.25, 10, 6)
	cape.material_override = outer
	pivot.add_child(cape)
	# a lining edge in the boss colour, glowing faintly at the hem
	var hem := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(1.3, 0.035, 0.02)
	hem.mesh = hm
	hem.material_override = U.glow(Color(0.9, 0.0, 0.1), 2.5)
	pivot.add_child(hem)
	hem.position = Vector3(0, -1.24, -0.2)
	# the high collar, standing up behind the head
	var collar := MeshInstance3D.new()
	collar.mesh = cape_mesh(0.2, 0.26, 0.26, 6, 2)
	collar.material_override = outer
	mount.add_child(collar)
	collar.position = Vector3(0, 0.33, -0.1)
	collar.rotation = Vector3(PI + 0.35, 0, 0)
	silhouette.append({"node": pivot, "kind": "cape"})


## A curved strip hanging down -Y from its top edge: `top`/`bottom` half-widths, bowed back.
static func cape_mesh(top: float, bottom: float, length: float, cols: int, rows: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for j in rows + 1:
		var v := float(j) / rows
		var hw := lerpf(top, bottom, v)
		var row := []
		for i in cols + 1:
			var u := float(i) / cols * 2.0 - 1.0
			var z := -0.16 * (1.0 - u * u) - 0.1 * v + 0.04 * sin(u * 9.0) * v # wraps the back, folds
			row.append(Vector3(u * hw, -v * length, z))
		pts.append(row)
	for j in rows:
		for i in cols:
			var quad := [[pts[j][i], 0.0, 0.0], [pts[j][i + 1], 1.0, 0.0], [pts[j + 1][i + 1], 1.0, 1.0], [pts[j][i], 0.0, 0.0], [pts[j + 1][i + 1], 1.0, 1.0], [pts[j + 1][i], 0.0, 1.0]]
			for q in quad:
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(q[0])
	st.generate_normals()
	return st.commit()


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
	if not own_model:
		base_overlay = Color(0.6, 0.0, 0.05, 0.3)
	aura.material_override = HFx.aura_mat(Color(1.0, 0.0, 0.1), 1.8)
	if director != null:
		director.boss_phase_text(self, "\"You and I were made the same, Marrow.\"")
