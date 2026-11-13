extends CanvasLayer
## Full-screen film look over the 3D view and under the HUD:
## film grain, vignette, slight chromatic aberration and a gentle split-tone.

const SHADER := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float grain = 0.045;
uniform float vignette = 0.38;
uniform float aberration = 0.0025;
uniform float tone = 0.5; // split-tone strength: cool shadows, warm highlights
uniform vec3 shadow_tint : source_color = vec3(0.86, 0.95, 1.08);
uniform vec3 highlight_tint : source_color = vec3(1.06, 1.0, 0.92);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r2 = dot(d, d);
	vec2 off = d * aberration * r2 * 4.0;
	vec3 c = vec3(
		texture(screen_tex, uv + off).r,
		texture(screen_tex, uv).g,
		texture(screen_tex, uv - off).b);
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 tint = mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.6, lum));
	c = mix(c, c * tint, tone);
	// vignette: elliptical, soft
	float v = smoothstep(0.95, 0.25, length(d * vec2(1.0, 1.25)));
	c *= mix(1.0 - vignette, 1.0, v);
	// grain at 24 fps, strongest in the mid-tones, quiet in the blacks
	float t = floor(TIME * 24.0);
	float n = hash(FRAGCOORD.xy + vec2(t * 17.0, t * 31.0)) + hash(FRAGCOORD.xy * 1.37 + t) - 1.0;
	float w = smoothstep(0.0, 0.12, lum) * (1.0 - smoothstep(0.5, 1.0, lum) * 0.6);
	c += n * grain * w;
	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
"""

var rect: ColorRect
var mat: ShaderMaterial


func _init() -> void:
	layer = 0 # the HUD is on layer 1, so this sits between the 3D view and the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect = ColorRect.new()
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)


## Cinematic tier gets the full look; the web tier a lighter one (and cheaper aberration).
func configure(cinematic: bool) -> void:
	mat.set_shader_parameter("grain", 0.05 if cinematic else 0.035)
	mat.set_shader_parameter("vignette", 0.4 if cinematic else 0.32)
	mat.set_shader_parameter("aberration", 0.003 if cinematic else 0.0015)
	mat.set_shader_parameter("tone", 0.5 if cinematic else 0.4)
