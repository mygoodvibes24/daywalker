extends Node3D
## The Red Curfew: a wall of blood fog with crimson lightning that closes on the night's
## boss arena. One open cylinder with a scrolling, fresnel, additive shader (cheap on web)
## plus a few pooled lightning ribbons near Sol. Radius tweens in stages.

const HEIGHT := 70.0

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(0.95, 0.05, 0.08, 1.0);
uniform float radius = 100.0;
uniform float flash = 0.0;
uniform float intensity = 1.35;
varying float h;
void vertex() {
	h = VERTEX.y;
}
void fragment() {
	float tiles = max(2.0, floor(radius * 6.2831 / 26.0));
	vec2 uv = vec2(UV.x * tiles, h / 26.0);
	float n1 = texture(noise_tex, uv + vec2(TIME * 0.025, -TIME * 0.16)).r;
	float n2 = texture(noise_tex, uv * vec2(0.5, 0.35) + vec2(-TIME * 0.018, -TIME * 0.06)).r;
	float n = n1 * 0.65 + n2 * 0.55;
	float hf = clamp((h + 35.0) / 70.0, 0.0, 1.0);
	float base = pow(1.0 - hf, 1.6);
	float fres = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	// vertical blood streaks running up the wall
	float streak = pow(texture(noise_tex, vec2(UV.x * tiles * 3.0, TIME * 0.05)).r, 3.0) * 1.6;
	float veil = (0.42 + smoothstep(0.3, 0.9, n) * 1.1 + streak * (1.0 - hf)) * (0.55 + fres * 0.9);
	float a = base * veil * intensity + flash * base * 0.8;
	float foot = smoothstep(0.08, 0.0, hf) * 1.4;
	vec3 c = color.rgb * (0.6 + n * 0.8) + vec3(1.0, 0.35, 0.3) * flash * 0.5;
	// fade out right in front of the camera so standing in the wall doesn't white out the screen
	float near = smoothstep(1.5, 12.0, -VERTEX.z);
	float k = clamp(a + foot, 0.0, 0.85) * near;
	ALBEDO = c * k;
	ALPHA = k;
}
"""

var radius := 120.0
var target_radius := 120.0
var center := Vector3.ZERO
var wall: MeshInstance3D
var mat: ShaderMaterial
var bolts: Array[MeshInstance3D] = []
var base_ring: MeshInstance3D # a burning line where the wall meets the street
var bolt_mat: StandardMaterial3D
var bolt_t := 0.5
var flash := 0.0
var tween: Tween
var main: Main
var drone: AudioStreamPlayer3D # AUDIO: the wall hums where it is nearest Sol
var crackle_t := 2.0


func _ready() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = HEIGHT
	cyl.radial_segments = 96
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.generate_mipmaps = true
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("noise_tex", tex)
	wall = MeshInstance3D.new()
	wall.mesh = cyl
	wall.material_override = mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.position.y = HEIGHT * 0.5 - 1.0
	wall.extra_cull_margin = 200.0
	add_child(wall)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.997
	tor.outer_radius = 1.003
	tor.rings = 128
	tor.ring_segments = 4
	base_ring = MeshInstance3D.new()
	base_ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(1.0, 0.12, 0.1)
	base_ring.material_override = rm
	base_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base_ring.position.y = 0.15
	base_ring.extra_cull_margin = 200.0
	add_child(base_ring)
	bolt_mat = StandardMaterial3D.new()
	bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bolt_mat.albedo_color = Color(1.0, 0.25, 0.3)
	for i in 3:
		var b := MeshInstance3D.new()
		b.mesh = _bolt_mesh(i)
		b.material_override = bolt_mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visible = false
		add_child(b)
		bolts.append(b)
	drone = Audio.loop_3d("curfew_drone", self, -2.0) # AUDIO HOOK
	_apply()


## A jagged vertical ribbon, ~40 m tall.
func _bolt_mesh(seed_: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = 77 + seed_
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := 0.0
	var y := 42.0
	var w := 0.35
	while y > 0.0:
		var ny := y - r.randf_range(3.0, 6.0)
		var nx := x + r.randf_range(-2.2, 2.2)
		var a := Vector3(x - w, y, 0)
		var b := Vector3(x + w, y, 0)
		var c := Vector3(nx + w, ny, 0)
		var d := Vector3(nx - w, ny, 0)
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
		x = nx
		y = ny
	return st.commit()


func set_center(c: Vector3) -> void:
	center = Vector3(c.x, 0.0, c.z)
	_apply()


func set_radius(r: float) -> void:
	if tween != null:
		tween.kill()
	radius = r
	target_radius = r
	_apply()


## Shrink (or grow) to `r` over `seconds`.
func shrink_to(r: float, seconds: float) -> void:
	if tween != null:
		tween.kill()
	target_radius = r
	tween = create_tween()
	tween.tween_method(_set_r, radius, r, maxf(seconds, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_r(v: float) -> void:
	radius = v
	_apply()


func _apply() -> void:
	global_position = center
	if wall != null:
		# V5 (critic R2): once the wall closes round a boss arena it surrounds the camera on every
		# side, and at full strength it washed the whole fight crimson. Small rings are lower and
		# thinner, so the arena keeps its night colours and the wall reads as a wall.
		var k := smoothstep(18.0, 70.0, radius)
		wall.scale = Vector3(radius, lerpf(0.42, 1.0, k), radius)
		wall.position.y = HEIGHT * 0.5 * lerpf(0.42, 1.0, k) - 1.0
		base_ring.scale = Vector3(radius, 40.0, radius)
		mat.set_shader_parameter("radius", radius)
		mat.set_shader_parameter("intensity", lerpf(0.5, 1.35, k))


## How far outside the wall a point is (<= 0 inside).
func outside_by(p: Vector3) -> float:
	return Vector2(p.x - center.x, p.z - center.z).length() - radius


func _process(delta: float) -> void:
	if not visible:
		return
	flash = maxf(flash - delta * 5.0, 0.0)
	bolt_t -= delta
	for b in bolts:
		if b.visible:
			b.set_meta("t", float(b.get_meta("t", 0.0)) - delta)
			if float(b.get_meta("t")) <= 0.0:
				b.visible = false
	if bolt_t <= 0.0:
		bolt_t = randf_range(0.35, 1.4)
		_strike()
	mat.set_shader_parameter("flash", flash * Settings.flash_scale()) # SETTINGS HOOK: reduced flashing
	_drone(delta)


## Keep the drone on the wall at the point nearest Sol; silent when he's far from it.
func _drone(delta: float) -> void:
	if drone == null or main == null or main.player == null:
		return
	var p: Vector3 = main.player.global_position
	var to := Vector3(p.x - center.x, 0.0, p.z - center.z)
	var dir := to.normalized() if to.length() > 0.1 else Vector3.RIGHT
	var near := absf(outside_by(p))
	drone.global_position = center + dir * radius + Vector3(0, minf(p.y + 1.5, 8.0), 0)
	var want: bool = Audio.unlocked and near < 70.0
	if want and not drone.playing:
		drone.play()
	elif not want and drone.playing:
		drone.stop()
	crackle_t -= delta


## Crimson lightning somewhere on the wall in Sol's half of the sky.
func _strike() -> void:
	var p: Vector3 = main.player.global_position if main != null and main.player != null else center + Vector3(radius, 0, 0)
	var to := p - center
	var base_a := atan2(to.z, to.x) if to.length() > 0.1 else randf() * TAU
	var a := base_a + randf_range(-0.9, 0.9) * clampf(40.0 / maxf(radius, 1.0), 0.15, 1.0)
	for b in bolts:
		if not b.visible:
			b.visible = true
			b.set_meta("t", randf_range(0.08, 0.16))
			b.position = Vector3(cos(a) * radius, 0.0, sin(a) * radius)
			b.rotation.y = -a + PI * 0.5
			b.scale = Vector3(randf_range(0.7, 1.3), randf_range(0.6, 1.0), 1.0)
			flash = 1.0
			if crackle_t <= 0.0 and main != null and main.player != null and absf(outside_by(main.player.global_position)) < 45.0:
				crackle_t = randf_range(4.0, 9.0)
				Audio.play_at("thunder", global_position + b.position + Vector3(0, 6, 0), -9.0, 0.25) # AUDIO HOOK: the lightning cracks
			return
