extends RefCounted
## Builds the visible blade for an equipped weapon item: return any Node3D whose blade runs
## from the origin along +Z, flat side facing ±X. With `modelled` (the modular hero) it is one
## of the four sword models, origin at the grip, picked by blade family and tinted by rarity;
## otherwise (the fallback bodies) a box blade whose origin is the hilt.

const ItemDB = preload("res://scripts/items/item_db.gd")
const Arsenal = preload("res://scripts/items/arsenal_data.gd")
const Forge = preload("res://scripts/items/weapon_forge.gd") # the Arsenal's procedural weapons

static var _mats := {}
static var _sword_mats := {}

## Modelled swords (built by tools/build_sol_modular.gd): blade along +Z, flat facing +-X, and a
## GripPoint marker where the fist's tunnel centre goes. Blade family -> sword scene.
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


## The weapon type (items/arsenal_data.gd TYPES) an item belongs to, by its blade family.
static func type_for(inst: Dictionary) -> String:
	if inst.is_empty():
		return Arsenal.DEFAULT_TYPE
	var d := ItemDB.get_def(inst.get("id", "marrow_silver"))
	return Arsenal.type_of_family(d.get("family", "saber"))


static func type_data(inst: Dictionary) -> Dictionary:
	return Arsenal.get_type(type_for(inst))


## Which combo chain (scripts/sol_moves.gd COMBOS, items/arsenal_moves.gd COMBOS) an item swings: the
## cleaver family Weapon_Combo_2, the sword family the light Triple_Combo_Attack, and each Arsenal type
## its own chain.
static func combo_for(inst: Dictionary) -> String:
	if inst.is_empty():
		return "light"
	return String(type_data(inst).chain)


## The sheath preset a weapon type rides on (sol_sheath.gd MOUNTS: back, back_great, hip, hip_right).
static func mount_name(inst: Dictionary) -> String:
	return String(type_data(inst).mount)


## True for the families built here from primitives (the Arsenal types) instead of a sword model.
static func is_procedural(inst: Dictionary) -> bool:
	var d := ItemDB.get_def(inst.get("id", "marrow_silver"))
	return Forge.FAMILIES.has(d.get("family", ""))


## The procedural weapon (weapon_forge.gd); `left` builds the left-hand twin of a dual type.
static func build_procedural(inst: Dictionary, left := false) -> Node3D:
	return Forge.build(inst, left)


## A second copy for the left hand (BladeL) when the type fights with a pair, else null.
static func build_left(inst: Dictionary) -> Node3D:
	if not bool(type_data(inst).get("dual", false)):
		return null
	return Forge.build(inst, true) if is_procedural(inst) else null


## How far the striking end reaches from the grip (m): the slash trail's tip.
static func tip_length(inst: Dictionary) -> float:
	var d := ItemDB.get_def(inst.get("id", "marrow_silver"))
	return float(Forge.TIP.get(d.get("family", "saber"), 1.0))


## The sword model for an item, tinted toward its family's steel and its rarity colour
## (Hallowed and Eclipse blades also glow faintly). Null if the scene is missing.
static func build_model(inst: Dictionary) -> Node3D:
	var sword := sword_for(inst)
	var path := SWORD_DIR + "sol_sword_%s.scn" % sword
	if not ResourceLoader.exists(path):
		return null
	var node := (load(path) as PackedScene).instantiate() as Node3D
	# put the sword's GripPoint (where its grip meets the fist's tunnel centre, set per sword by the
	# build tool) on the hand's grip socket: the parent is the socket, so the sword's own transform is
	# the inverse of its grip frame
	var gp := node.get_node_or_null("GripPoint") as Node3D
	if gp != null:
		node.transform = gp.transform.affine_inverse()
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
			var tint: Color = Color.WHITE.lerp(look.col, 0.35)
			if rarity > ItemDB.COMMON:
				tint = tint.lerp(ItemDB.RARITY_COLORS[rarity], 0.1 + 0.04 * rarity)
			var glow := Color(0, 0, 0)
			if rarity >= ItemDB.RARE:
				glow = ItemDB.RARITY_COLORS[rarity] * (0.08 if rarity == ItemDB.RARE else 0.16)
			var hz := _hilt_z(sword, m.mesh, gp.transform.origin.z if gp != null else 0.0)
			_sword_mats[key] = sword_material(base, tint, glow, hz)
		m.material_override = _sword_mats[key]
	node.name = "WeaponVisual"
	return node


# ---------------------------------------------------------------- sword look (round 2)
## The generated sword textures paint the guard and pommel near-white, and under Sol's rim light the
## guard read as a glowing white disc while the blade itself vanished edge-on. The sword material
## keeps the textured steel for the blade (with a thin fresnel edge so it reads from the follow
## camera) and turns everything below the top of the guard (guard, grip, pommel) to dark, blackened
## iron: no white, no glow on the hilt.
const SWORD_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform int metal_ch = 2;
uniform int rough_ch = 1;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 glow : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float hilt_z = 0.05;
uniform vec4 hilt_col : source_color = vec4(0.075, 0.068, 0.062, 1.0);
uniform vec4 edge_col : source_color = vec4(0.55, 0.62, 0.75, 1.0);
uniform float edge_strength = 0.35;
varying float vz;
void vertex() {
	vz = VERTEX.z;
}
void fragment() {
	vec4 a = texture(albedo_tex, UV);
	vec4 orm = texture(orm_tex, UV);
	float hilt = 1.0 - smoothstep(hilt_z - 0.006, hilt_z + 0.006, vz);
	float lum = dot(a.rgb, vec3(0.299, 0.587, 0.114));
	vec3 steel = a.rgb * tint.rgb;
	vec3 iron = hilt_col.rgb * (0.6 + 0.8 * lum);
	ALBEDO = mix(steel, iron, hilt);
	METALLIC = mix(orm[metal_ch], 0.55, hilt);
	ROUGHNESS = mix(max(orm[rough_ch], 0.16), 0.58, hilt);
	SPECULAR = mix(0.5, 0.3, hilt);
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = (glow.rgb + edge_col.rgb * fres * edge_strength) * (1.0 - hilt);
}
"""
static var _sword_shader: Shader
static var _hilt_cache := {}


static func sword_material(base: StandardMaterial3D, tint: Color, glow: Color, hilt_z: float) -> ShaderMaterial:
	if _sword_shader == null:
		_sword_shader = Shader.new()
		_sword_shader.code = SWORD_SHADER
	var m := ShaderMaterial.new()
	m.shader = _sword_shader
	m.set_shader_parameter("albedo_tex", base.albedo_texture)
	var orm: Texture2D = base.metallic_texture if base.metallic_texture != null else base.roughness_texture
	if orm != null:
		m.set_shader_parameter("orm_tex", orm)
		m.set_shader_parameter("metal_ch", mini(int(base.metallic_texture_channel), 3))
		m.set_shader_parameter("rough_ch", mini(int(base.roughness_texture_channel), 3))
	if base.normal_enabled and base.normal_texture != null:
		m.set_shader_parameter("normal_tex", base.normal_texture)
		m.set_shader_parameter("has_normal", true)
	m.set_shader_parameter("tint", base.albedo_color * tint)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("hilt_z", hilt_z)
	return m


## Where the hilt ends along the sword's +Z (mesh space): the top face of the guard, found the way
## the build tool finds the guard (the widest cross-section in the lower part, then up while the
## section stays wide). Falls back to a little above the grip point.
static func _hilt_z(sword: String, mesh: Mesh, grip_z: float) -> float:
	if _hilt_cache.has(sword):
		return _hilt_cache[sword]
	var hz := grip_z + 0.08
	var arr := mesh.surface_get_arrays(0) if mesh != null and mesh.get_surface_count() > 0 else []
	if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] is PackedVector3Array and (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 50:
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var aabb := mesh.get_aabb()
		var zmin := aabb.position.z
		var zlen := maxf(aabb.size.z, 0.01)
		var bins := 80
		var wid := PackedFloat32Array()
		wid.resize(bins)
		for p in v:
			var b := clampi(int((p.z - zmin) / zlen * bins), 0, bins - 1)
			wid[b] = maxf(wid[b], Vector2(p.x, p.y).length())
		var gb := 0
		for b in int(bins * 0.45):
			if wid[b] > wid[gb]:
				gb = b
		var top := gb
		while top + 1 < bins and top < gb + 6 and wid[top + 1] > wid[gb] * 0.6:
			top += 1
		var found := zmin + (top + 1.0) / bins * zlen
		if found > grip_z and found < grip_z + 0.25:
			hz = found
	_hilt_cache[sword] = hz
	return hz


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
	if is_procedural(inst):
		return build_procedural(inst)
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
