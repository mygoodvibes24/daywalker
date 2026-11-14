extends RefCounted
## Builds the visible blade for an equipped weapon item. Kept separate so a real
## sword model can replace it later: return any Node3D whose blade runs from the
## origin (the hilt) along +Z, flat side facing ±X.

const ItemDB = preload("res://scripts/items/item_db.gd")

static var _mats := {}
static var _sword_mats := {}

## Modelled swords (built by tools/build_sol_modular.gd): origin at the grip, blade along +Z,
## flat facing +-X. Blade family -> sword scene.
const SWORD_DIR := "res://assets/characters/sol/"
const FAMILY_SWORD := {
	"saber": "sabre",
	"cleaver": "cleaver", "machete": "cleaver", "kukri": "cleaver",
	"cane": "rapier",
	"longblade": "silver",
}
const DEFAULT_SWORD := "silver"


## Which sword model an item uses. Sol's own Marrow's Silver keeps the silver blade.
static func sword_for(inst: Dictionary) -> String:
	if inst.get("id", "marrow_silver") == "marrow_silver":
		return DEFAULT_SWORD
	var d := ItemDB.get_def(inst.get("id", "marrow_silver"))
	return FAMILY_SWORD.get(d.get("family", ""), DEFAULT_SWORD)


## The sword model for an item, tinted toward its family's steel and its rarity colour
## (Hallowed and Eclipse blades also glow faintly). Null if the scene is missing.
static func build_model(inst: Dictionary) -> Node3D:
	var sword := sword_for(inst)
	var path := SWORD_DIR + "sol_sword_%s.scn" % sword
	if not ResourceLoader.exists(path):
		return null
	var node := (load(path) as PackedScene).instantiate() as Node3D
	var d := ItemDB.get_def(inst.get("id", "marrow_silver"))
	var look: Dictionary = ItemDB.BLADE_LOOK.get(d.get("family", "saber"), ItemDB.BLADE_LOOK.saber)
	var rarity := int(inst.get("r", 0))
	var key := "%s_%s_%d" % [sword, d.get("family", ""), rarity]
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var base := m.mesh.surface_get_material(0) as StandardMaterial3D
		if base == null:
			continue
		if not _sword_mats.has(key):
			var mat := base.duplicate() as StandardMaterial3D
			var tint: Color = Color.WHITE.lerp(look.col, 0.35)
			if rarity > ItemDB.COMMON:
				tint = tint.lerp(ItemDB.RARITY_COLORS[rarity], 0.12 + 0.06 * rarity)
			mat.albedo_color = tint
			if rarity >= ItemDB.RARE:
				mat.emission_enabled = true
				mat.emission = ItemDB.RARITY_COLORS[rarity]
				mat.emission_energy_multiplier = 0.25 if rarity == ItemDB.RARE else 0.5
			_sword_mats[key] = mat
		m.material_override = _sword_mats[key]
	node.name = "WeaponVisual"
	return node


static func _steel(c: Color, rarity: int) -> StandardMaterial3D:
	var key := "%s_%d" % [c.to_html(), rarity]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = 1.0
		m.roughness = 0.15
		if rarity >= ItemDB.RARE:
			m.emission_enabled = true # Hallowed and Eclipse blades glow faintly in their rarity colour
			m.emission = ItemDB.RARITY_COLORS[rarity]
			m.emission_energy_multiplier = 0.6 if rarity == ItemDB.RARE else 1.2
		_mats[key] = m
	return _mats[key]


## `thickness` is the original blade's flat-axis size, so it matches the hand it sits in.
## `modelled`: use the sword models (the modular hero holds them by the grip).
static func build(inst: Dictionary, thickness: float = 0.014, modelled: bool = false) -> Node3D:
	if modelled:
		var m := build_model(inst)
		if m != null:
			return m
	var d := ItemDB.get_def(inst.get("id", "marrow_silver"))
	var look: Dictionary = ItemDB.BLADE_LOOK.get(d.get("family", "saber"), ItemDB.BLADE_LOOK.saber)
	var rarity := int(inst.get("r", 0))
	var root := Node3D.new()
	root.name = "WeaponVisual"
	var mat := _steel(look.col, rarity)
	var L: float = look.len
	var W: float = look.w
	match look.shape:
		"curved", "hooked":
			# three short segments bending back for a curved edge
			var segs := 3
			var bend := 0.07 if look.shape == "curved" else -0.16
			var p := Vector3.ZERO
			var ang := 0.0
			for i in segs:
				var sl := L / segs
				ang += bend
				var dir := Vector3(0, sin(ang), cos(ang))
				var mi := _box(root, Vector3(thickness, W * (1.0 if i < segs - 1 else 0.75), sl * 1.04), mat)
				mi.position = p + dir * sl * 0.5
				mi.rotation.x = -ang
				p += dir * sl
		"cleaver":
			var mi := _box(root, Vector3(thickness * 1.4, W, L), mat)
			mi.position = Vector3(0, W * 0.35, L * 0.5 + 0.04)
		"wide":
			var mi := _box(root, Vector3(thickness * 1.2, W, L), mat)
			mi.position = Vector3(0, W * 0.15, L * 0.5 + 0.03)
		_:
			var mi := _box(root, Vector3(thickness, W, L), mat)
			mi.position = Vector3(0, 0, L * 0.5 + 0.03)
	return root


static func _box(parent: Node3D, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
