extends RefCounted
## Dresses Sol's modular body (sol_modular.scn) in a wardrobe outfit (items/wardrobe_data.gd).
## Nothing in the model is rebuilt: the parts keep their meshes, skins and LODs, and the coat keeps
## its spring bones (coat_sim.gd), so every combination animates exactly like the default.
##
##   coat    the Coat mesh gets a tint material: the leather texture becomes fold detail under the
##           item's colour, roughness and metal ("tex": false drops the texture for flat bone-white
##           leather). "hem" scales the skirt's spring chains along their length (0.72 = thigh, 1.12 =
##           to the ankle).
##   shirt / pants / boots   one shader on the Body: assets/characters/sol/sol_body_regions.png
##           (tools/build_sol_regions.gd) says which UV texels are shirt, trousers or boots; cloth
##           texels there are recoloured, keeping the texture's folds (lum / region mean). Skin and the
##           brown leather straps (saturated texels) stay. "vest" paints a waistcoat with the shirt
##           showing in the chest V; "keep" leaves a region as modelled.
##   gloves  the hand meshes get the same tint, within "reach" of the wrist (fingerless: the palm only).
##           Bare hands = the model's own material. Gauntlet cuffs are a ring at the wrist.
##   boots   recolour (above) plus procedural cuffs (a ring at the boot top) and buckle straps.
##   scarf   a procedural wrap (a flattened torus) on the neck bone, an optional tail hanging down the
##           chest that swings a little (SolOutfitSway), or a mail cowl.
##   hat     procedural meshes on the Head bone, as Silas Crowe's hat: wide brim, low crown, flat cap,
##           bowler or hood.
## Every procedural piece is a handful of primitives with shadows off (web budget).

const W = preload("res://scripts/items/wardrobe_data.gd")
const U = preload("res://scripts/util.gd")
const REGIONS := "res://assets/characters/sol/sol_body_regions.png"
## Mean luminance of the cloth texels per body region (measured from the body texture), so the
## recolour keeps the folds without darkening or brightening the item's colour.
const REGION_LUM := [1.0, 0.172, 0.189, 0.11]
const COAT_LUM := 0.13
const HAND_LUM := 0.22
const HEAD_HAT_Y := 1.86 # top of the head in skeleton space at rest (Crowe's hat height)

static var _tint_shader: Shader
static var _body_shader: Shader


## Dress `model` (the instanced sol_modular.scn) in `outfit` {slot: item id}. Safe to call again.
static func apply(model: Node3D, outfit: Dictionary) -> void:
	if model == null:
		return
	var o := W.sanitize(outfit)
	var skel := model.get_node_or_null("Skeleton3D") as Skeleton3D
	if skel == null:
		return
	model.set_meta("outfit", o.duplicate())
	_coat(model, skel, W.get_def(o.coat).get("look", {}))
	_body(model, W.get_def(o.shirt).get("look", {}), W.get_def(o.pants).get("look", {}), W.get_def(o.boots).get("look", {}))
	_gloves(model, skel, W.get_def(o.gloves).get("look", {}))
	_boot_parts(skel, W.get_def(o.boots).get("look", {}))
	_scarf(model, skel, W.get_def(o.scarf).get("look", {}))
	_hat(skel, W.get_def(o.hat).get("look", {}))


## The outfit last applied to `model` ({} if none).
static func current(model: Node) -> Dictionary:
	return model.get_meta("outfit", {}) if model != null else {}


# ---------------------------------------------------------------- shaders
static func tint_shader() -> Shader:
	if _tint_shader == null:
		_tint_shader = Shader.new()
		_tint_shader.code = """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool use_tex = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform float amount = 1.0;
uniform float base_lum = 0.15;
uniform float rough = 0.6;
uniform float metal = 0.0;
uniform float spec = 0.3;
uniform float normal_depth = 1.0;
// gloves: only within `reach` of `wrist` (model space); 99 = everywhere
uniform vec3 wrist = vec3(0.0);
uniform float reach = 99.0;
varying vec3 lpos;
void vertex() { lpos = VERTEX; }
void fragment() {
	vec4 a = texture(albedo_tex, UV);
	float lum = dot(a.rgb, vec3(0.299, 0.587, 0.114));
	float detail = use_tex ? clamp(lum / base_lum, 0.35, 1.9) : 1.0;
	float k = amount * (1.0 - smoothstep(reach - 0.006, reach + 0.006, distance(lpos, wrist)));
	ALBEDO = mix(a.rgb, tint.rgb * detail, k);
	ROUGHNESS = mix(0.62, rough, k);
	METALLIC = metal * k;
	SPECULAR = mix(0.32, spec, k);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
"""
	return _tint_shader


static func body_shader() -> Shader:
	if _body_shader == null:
		_body_shader = Shader.new()
		_body_shader.code = """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D region_tex : hint_default_black, filter_nearest;
uniform vec4 rough_ch = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 metal_ch = vec4(0.0, 0.0, 1.0, 0.0);
uniform float normal_depth = 1.0;
uniform vec4 albedo_mul : source_color = vec4(1.0);
// per region (1 shirt, 2 trousers, 3 boots): colour, amount (0 = as modelled), mean lum, roughness (<0 keep)
uniform vec4 col1 : source_color = vec4(1.0);
uniform vec4 col2 : source_color = vec4(1.0);
uniform vec4 col3 : source_color = vec4(1.0);
uniform vec3 amt = vec3(0.0);
uniform vec3 lum_base = vec3(0.172, 0.189, 0.11);
uniform vec3 rough = vec3(-1.0);
// the waistcoat: the chest V shows this colour instead (vee_amt 1)
uniform vec4 vee_col : source_color = vec4(1.0);
uniform float vee_amt = 0.0;
void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo_mul;
	vec4 o = texture(orm_tex, UV);
	vec2 rg = texture(region_tex, UV).rg;
	int reg = int(rg.r * 3.0 + 0.5);
	float lum = dot(a.rgb, vec3(0.299, 0.587, 0.114));
	float chroma = max(a.r, max(a.g, a.b)) - min(a.r, min(a.g, a.b));
	float cloth = 1.0 - smoothstep(0.05, 0.11, chroma); // skin and leather straps stay
	vec3 col = a.rgb;
	float r = dot(o, rough_ch);
	float m = dot(o, metal_ch);
	if (reg >= 1) {
		vec4 c = reg == 1 ? col1 : (reg == 2 ? col2 : col3);
		float k = reg == 1 ? amt.x : (reg == 2 ? amt.y : amt.z);
		float lb = reg == 1 ? lum_base.x : (reg == 2 ? lum_base.y : lum_base.z);
		float rr = reg == 1 ? rough.x : (reg == 2 ? rough.y : rough.z);
		if (reg == 1 && rg.g > 0.5 && vee_amt > 0.5) {
			c = vee_col;
		}
		k *= cloth;
		col = mix(col, c.rgb * clamp(lum / lb, 0.3, 2.0), k);
		if (rr >= 0.0) {
			r = mix(r, rr, k);
		}
		m = mix(m, 0.0, k);
	}
	ALBEDO = col;
	ROUGHNESS = r;
	METALLIC = m;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
"""
	return _body_shader


static func _tint_material(src: StandardMaterial3D, col: Color, rough: float, metal: float, base_lum: float, use_tex := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = tint_shader()
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("normal_tex", src.normal_texture)
	m.set_shader_parameter("normal_depth", src.normal_scale if src.normal_enabled else 0.0)
	m.set_shader_parameter("use_tex", use_tex)
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("spec", 0.3 + metal * 0.4)
	m.set_shader_parameter("base_lum", base_lum)
	return m


# ---------------------------------------------------------------- coat
static func _coat(model: Node3D, skel: Skeleton3D, look: Dictionary) -> void:
	var coat := model.find_child("Coat", true, false) as MeshInstance3D
	if coat == null or coat.mesh == null:
		return
	var base := coat.mesh.surface_get_material(0) as StandardMaterial3D
	if base == null:
		return
	if look.is_empty() or (look.get("tex", true) and look.get("col", Color(0.35, 0.35, 0.336)) == Color(0.35, 0.35, 0.336)):
		# Sol's own coat: the matte black leather player.gd gives it
		var m := base.duplicate() as StandardMaterial3D
		m.metallic = 0.0
		m.metallic_texture = null
		m.metallic_specular = 0.3
		m.roughness = float(look.get("rough", 0.62))
		m.roughness_texture = null
		m.albedo_color = Color(0.35, 0.35, 0.336)
		coat.material_override = m
	else:
		coat.material_override = _tint_material(base, look.get("col", Color(0.1, 0.1, 0.1)), float(look.get("rough", 0.6)),
			float(look.get("metal", 0.0)), COAT_LUM, bool(look.get("tex", true)))
	# the hem: the skirt chains scaled along their length (their rest basis points them down)
	var hem := float(look.get("hem", 1.0))
	for c in 12:
		var b := skel.find_bone("Coat%d_1" % c)
		if b < 0:
			break
		skel.set_bone_pose_scale(b, Vector3(1.0, hem, 1.0))


# ---------------------------------------------------------------- shirt / trousers / boots
static func _body(model: Node3D, shirt: Dictionary, pants: Dictionary, boots: Dictionary) -> void:
	var body := model.find_child("Body", true, false) as MeshInstance3D
	if body == null or body.mesh == null:
		return
	var src := body.mesh.surface_get_material(0) as StandardMaterial3D
	if src == null or not ResourceLoader.exists(REGIONS):
		return
	var all_keep: bool = shirt.get("keep", false) and pants.get("keep", false) and boots.get("keep", false)
	if all_keep:
		body.material_override = null # as modelled: the stock material (cheapest)
		return
	var m := body.material_override as ShaderMaterial
	if m == null or m.shader != body_shader():
		m = ShaderMaterial.new()
		m.shader = body_shader()
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("normal_tex", src.normal_texture)
		m.set_shader_parameter("orm_tex", src.roughness_texture)
		m.set_shader_parameter("region_tex", load(REGIONS))
		var ch := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.33, 0.33, 0.33, 0)]
		m.set_shader_parameter("rough_ch", ch[src.roughness_texture_channel])
		m.set_shader_parameter("metal_ch", ch[src.metallic_texture_channel] if src.metallic_texture != null else Vector4.ZERO)
		m.set_shader_parameter("normal_depth", src.normal_scale if src.normal_enabled else 0.0)
		m.set_shader_parameter("albedo_mul", src.albedo_color)
		m.set_shader_parameter("lum_base", Vector3(REGION_LUM[1], REGION_LUM[2], REGION_LUM[3]))
		body.material_override = m
	var looks := [shirt, pants, boots]
	var amt := Vector3.ZERO
	var rough := Vector3(-1, -1, -1)
	for i in 3:
		var lk: Dictionary = looks[i]
		var k := 0.0 if lk.get("keep", false) or lk.is_empty() else 1.0
		amt[i] = k
		m.set_shader_parameter("col%d" % (i + 1), lk.get("col", Color(1, 1, 1)))
		if lk.get("sheen", false):
			rough[i] = 0.32
		elif lk.get("suede", false):
			rough[i] = 0.95
	m.set_shader_parameter("amt", amt)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("vee_amt", 1.0 if shirt.get("vest", false) else 0.0)
	m.set_shader_parameter("vee_col", shirt.get("shirt_col", Color(0.6, 0.58, 0.52)))


# ---------------------------------------------------------------- gloves
static func _gloves(model: Node3D, skel: Skeleton3D, look: Dictionary) -> void:
	var kind := String(look.get("kind", "bare"))
	for side in ["HandR", "HandL"]:
		var att := model.find_child(side, true, false)
		if att == null:
			continue
		var wrist := skel.get_bone_global_rest(skel.find_bone("RightHand" if side == "HandR" else "LeftHand")).origin
		for n in ["HandMesh", "HandMeshOpen"]:
			var mi := att.get_node_or_null(n) as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if kind == "bare":
				mi.material_override = null
				continue
			var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if src == null:
				continue
			var gm := _tint_material(src, look.get("col", Color(0.05, 0.05, 0.05)), 0.34 if look.get("sheen", false) else 0.6, 0.0, HAND_LUM)
			gm.set_shader_parameter("wrist", wrist)
			gm.set_shader_parameter("reach", 0.075 if kind == "fingerless" else 99.0)
			mi.material_override = gm
	var holder := _holder(skel, "OutfitCuffR", "RightForeArm")
	var holder_l := _holder(skel, "OutfitCuffL", "LeftForeArm")
	if look.get("cuff", false):
		var leather := U.mat(Color(look.get("col", Color(0.2, 0.1, 0.05))).darkened(0.2), 0.55)
		var steel := U.mat(Color(0.5, 0.5, 0.52), 0.35, 0.8)
		for pair in [[holder, "Right"], [holder_l, "Left"]]:
			var h: Node3D = pair[0]
			var fore := skel.get_bone_global_rest(skel.find_bone(pair[1] + "ForeArm")).origin
			var hand := skel.get_bone_global_rest(skel.find_bone(pair[1] + "Hand")).origin
			var at := hand.lerp(fore, 0.16)
			var up := (hand - fore).normalized()
			var inv := skel.get_bone_global_rest(skel.find_bone(pair[1] + "ForeArm")).affine_inverse()
			var b := Basis(Quaternion(Vector3.UP, up))
			_part(h, U.cyl(0.05, 0.043, 0.07), leather, inv * Transform3D(b, at))
			_part(h, U.cyl(0.052, 0.052, 0.012), steel, inv * Transform3D(b, at + up * 0.02))


# ---------------------------------------------------------------- boot parts
static func _boot_parts(skel: Skeleton3D, look: Dictionary) -> void:
	for side in ["Left", "Right"]:
		var h := _holder(skel, "OutfitBoot" + side, side + "Leg")
		var cuff: bool = look.get("cuff", false)
		var buckles := int(look.get("buckles", 0))
		if not cuff and buckles == 0:
			continue
		var knee := skel.get_bone_global_rest(skel.find_bone(side + "Leg")).origin
		var ankle := skel.get_bone_global_rest(skel.find_bone(side + "Foot")).origin
		var inv := skel.get_bone_global_rest(skel.find_bone(side + "Leg")).affine_inverse()
		var up := (knee - ankle).normalized()
		var b := Basis(Quaternion(Vector3.UP, up))
		var leather := U.mat(Color(look.get("col", Color(0.1, 0.08, 0.07))) * 0.8, 0.6)
		var steel := U.mat(Color(0.55, 0.52, 0.45), 0.3, 0.9)
		var sx := 1.0 if side == "Left" else -1.0
		if cuff:
			# a folded cuff around the boot top
			_part(h, U.cyl(0.066, 0.06, 0.05), leather, inv * Transform3D(b, ankle + up * 0.15 + Vector3(0, 0, 0.012)))
		for i in buckles:
			var y := 0.03 + i * 0.045
			var p := ankle + up * y + Vector3(0, 0, 0.012)
			var strap := U.cyl(0.063, 0.059, 0.016)
			_part(h, strap, leather, inv * Transform3D(b, p))
			_part(h, U.box(Vector3(0.012, 0.022, 0.026)), steel, inv * Transform3D(b, p + Vector3(sx * 0.062, 0, 0.0)))


# ---------------------------------------------------------------- scarf
static func _scarf(model: Node3D, skel: Skeleton3D, look: Dictionary) -> void:
	var h := _holder(skel, "OutfitScarf", "neck")
	var sway := model.get_node_or_null("OutfitSway")
	if sway != null:
		sway.free()
	var kind := String(look.get("kind", "none"))
	if kind == "none":
		return
	var col: Color = look.get("col", Color(0.2, 0.2, 0.2))
	var mat: BaseMaterial3D
	if look.get("metal", false):
		mat = U.mat(col, 0.35, 0.85)
	else:
		mat = U.mat(col, 0.42 if look.get("sheen", false) else (0.98 if look.get("fur", false) else 0.88))
	var inv := skel.get_bone_global_rest(skel.find_bone("neck")).affine_inverse()
	var neck := skel.get_bone_global_rest(skel.find_bone("neck")).origin
	var c := neck + Vector3(0.0, 0.012, 0.012)
	if kind == "cowl":
		# a riveted mail guard under a leather band
		_part(h, U.cyl(0.085, 0.11, 0.1), mat, inv * Transform3D(Basis(), c + Vector3(0, -0.01, 0)))
		_part(h, U.cyl(0.088, 0.088, 0.022), U.mat(Color(0.06, 0.045, 0.035), 0.6), inv * Transform3D(Basis(), c + Vector3(0, 0.04, 0)))
		return
	# the wrap: two flattened rings, a little bulky, sitting inside the coat's collar
	var t1 := TorusMesh.new()
	t1.inner_radius = 0.058
	t1.outer_radius = 0.098
	t1.rings = 14
	t1.ring_segments = 8
	_part(h, t1, mat, inv * Transform3D(Basis().scaled(Vector3(1.05, 0.62, 1.08)).rotated(Vector3.RIGHT, 0.12), c + Vector3(0, -0.012, 0.0)))
	_part(h, t1, mat, inv * Transform3D(Basis().scaled(Vector3(1.0, 0.55, 1.03)).rotated(Vector3.RIGHT, -0.08), c + Vector3(0, 0.03, -0.004)))
	if look.get("beads", false):
		var bead := U.mat(Color(0.75, 0.68, 0.5), 0.3, 0.8)
		for i in 9:
			var a := lerpf(-1.2, 1.2, i / 8.0)
			_part(h, U.sphere(0.008), bead, inv * Transform3D(Basis(), c + Vector3(sin(a) * 0.1, -0.03 - cos(a) * 0.012, cos(a) * 0.098)))
	if look.get("tail", false):
		# two tails hanging down the chest from the knot, swung a little by SolOutfitSway
		var pivot := Node3D.new()
		pivot.name = "ScarfTail"
		h.add_child(pivot)
		pivot.transform = inv * Transform3D(Basis(), c + Vector3(-0.045, -0.03, 0.085))
		_part(pivot, U.box(Vector3(0.07, 0.3, 0.018)), mat, Transform3D(Basis(Vector3.FORWARD, 0.06), Vector3(0, -0.15, 0.0)))
		_part(pivot, U.box(Vector3(0.062, 0.24, 0.016)), mat, Transform3D(Basis(Vector3.FORWARD, -0.1), Vector3(0.05, -0.13, -0.006)))
		var s := SolOutfitSway.new()
		s.name = "OutfitSway"
		s.target = pivot
		s.skel = skel
		model.add_child(s)


# ---------------------------------------------------------------- hat
static func _hat(skel: Skeleton3D, look: Dictionary) -> void:
	var h := _holder(skel, "OutfitHat", "Head")
	var kind := String(look.get("kind", "none"))
	if kind == "none":
		return
	var inv := skel.get_bone_global_rest(skel.find_bone("Head")).affine_inverse()
	var col: Color = look.get("col", Color(0.05, 0.05, 0.05))
	var felt := U.mat(col, 0.82)
	var band := U.mat(look.get("band", col.darkened(0.3)), 0.6)
	var hat := Node3D.new()
	hat.name = "Hat"
	h.add_child(hat)
	match kind:
		"wide":
			hat.transform = Transform3D(inv.basis, inv * Vector3(0.0, HEAD_HAT_Y, -0.04)).rotated_local(Vector3.RIGHT, deg_to_rad(-7.0))
			_part(hat, _cyl(0.29, 0.3, 0.018, 22), felt, Transform3D(Basis(), Vector3.ZERO))
			_part(hat, _cyl(0.112, 0.128, 0.15, 14), felt, Transform3D(Basis(), Vector3(0, 0.08, 0)))
			_part(hat, _cyl(0.131, 0.131, 0.03, 14), band, Transform3D(Basis(), Vector3(0, 0.03, 0)))
		"low":
			hat.transform = Transform3D(inv.basis, inv * Vector3(0.0, HEAD_HAT_Y - 0.005, -0.035)).rotated_local(Vector3.RIGHT, deg_to_rad(-5.0))
			_part(hat, _cyl(0.22, 0.225, 0.016, 20), felt, Transform3D(Basis(), Vector3.ZERO))
			_part(hat, _cyl(0.118, 0.126, 0.1, 14), felt, Transform3D(Basis(), Vector3(0, 0.055, 0)))
			_part(hat, _cyl(0.128, 0.128, 0.022, 14), band, Transform3D(Basis(), Vector3(0, 0.02, 0)))
		"bowler":
			hat.transform = Transform3D(inv.basis, inv * Vector3(0.0, HEAD_HAT_Y - 0.01, -0.035)).rotated_local(Vector3.RIGHT, deg_to_rad(-4.0))
			_part(hat, _cyl(0.165, 0.17, 0.014, 20), felt, Transform3D(Basis().scaled(Vector3(1, 1, 1.12)), Vector3.ZERO))
			var dome := SphereMesh.new()
			dome.radius = 0.125
			dome.height = 0.25
			dome.is_hemisphere = true
			dome.radial_segments = 16
			dome.rings = 6
			_part(hat, dome, felt, Transform3D(Basis().scaled(Vector3(1, 0.9, 1.1)), Vector3(0, 0.005, 0)))
			_part(hat, _cyl(0.127, 0.127, 0.022, 16), band, Transform3D(Basis().scaled(Vector3(1, 1, 1.1)), Vector3(0, 0.014, 0)))
		"cap":
			hat.transform = Transform3D(inv.basis, inv * Vector3(0.0, HEAD_HAT_Y - 0.045, -0.02)).rotated_local(Vector3.RIGHT, deg_to_rad(-9.0))
			var crown := SphereMesh.new()
			crown.radius = 0.128
			crown.height = 0.256
			crown.is_hemisphere = true
			crown.radial_segments = 16
			crown.rings = 6
			_part(hat, crown, felt, Transform3D(Basis().scaled(Vector3(1.05, 0.48, 1.18)), Vector3(0, 0.0, 0.01)))
			_part(hat, _cyl(0.126, 0.13, 0.03, 16), felt, Transform3D(Basis().scaled(Vector3(1.04, 1, 1.12)), Vector3(0, 0.0, 0.0)))
			# the bill
			_part(hat, _cyl(0.11, 0.11, 0.012, 16), felt, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.55)).rotated(Vector3.RIGHT, 0.12), Vector3(0, -0.012, 0.12)))
		"hood":
			# a deep cowl: a shell over the skull falling to the shoulders behind
			hat.transform = Transform3D(inv.basis, inv * Vector3(0.0, 1.74, -0.035))
			var shell := SphereMesh.new()
			shell.radius = 0.15
			shell.height = 0.3
			shell.radial_segments = 18
			shell.rings = 10
			var mat := felt.duplicate() as StandardMaterial3D
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_part(hat, shell, mat, Transform3D(Basis().scaled(Vector3(1.0, 1.08, 1.06)), Vector3(0, 0.03, -0.035)))
			_part(hat, _cyl(0.14, 0.2, 0.2, 16), mat, Transform3D(Basis(), Vector3(0, -0.12, -0.075)))
			# the open face: a dark rim
			var rim := TorusMesh.new()
			rim.inner_radius = 0.115
			rim.outer_radius = 0.135
			rim.rings = 18
			rim.ring_segments = 6
			_part(hat, rim, felt, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.0, 1.25)), Vector3(0, 0.02, 0.085)))
	for c in hat.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- helpers
static func _cyl(top: float, bot: float, h: float, segs: int) -> CylinderMesh:
	var c := U.cyl(top, bot, h)
	c.radial_segments = segs
	c.rings = 1
	return c


## A BoneAttachment3D under the skeleton for outfit pieces (made once, emptied on every apply).
## Children are placed in skeleton rest space times the bone's inverse rest.
static func _holder(skel: Skeleton3D, name: String, bone: String) -> Node3D:
	var att := skel.get_node_or_null(name) as BoneAttachment3D
	if att == null:
		att = BoneAttachment3D.new()
		att.name = name
		att.bone_name = bone
		skel.add_child(att)
	for c in att.get_children():
		att.remove_child(c)
		c.queue_free()
	return att


static func _part(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## The scarf's tails swing a little with the chest's motion (a damped spring on one angle; no
## per-frame allocation, parked when Sol is still).
class SolOutfitSway extends Node:
	var target: Node3D
	var skel: Skeleton3D
	var last := Vector3.ZERO
	var ang := Vector2.ZERO
	var vel := Vector2.ZERO
	var base := Transform3D()
	var started := false

	func _physics_process(delta: float) -> void:
		if target == null or not is_instance_valid(target) or delta <= 0.0:
			return
		if not started:
			base = target.transform
			last = target.global_position
			started = true
			return
		var p := target.global_position
		var v := (p - last) / delta
		last = p
		var local := target.get_parent().global_transform.basis.inverse() * v
		# accelerate opposite the motion, spring back, damp
		var acc := Vector2(local.z, -local.x) * 1.6 - ang * 60.0 - vel * 7.0
		vel += acc * delta
		ang += vel * delta
		ang = ang.clamp(Vector2(-0.6, -0.4), Vector2(0.5, 0.4))
		target.transform = base * Transform3D(Basis.from_euler(Vector3(ang.x, 0.0, ang.y)), Vector3.ZERO)
