extends Control
## The compass strip at the top of the screen: N/E/S/W, POI markers by bearing, the boss
## arena, the Lost Tithe beam, and an arrow back to safety when Sol is outside the Curfew.

const Icons = preload("res://scripts/ui/poi_icons.gd")
const SPAN := deg_to_rad(100.0) # half the field shown on the strip

var director: HuntDirector
var main: Main
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()


var _last_key := Vector4.INF
var _redraw_t := 0.0


## PERF: redraw only when the view turned or Sol moved (or 4 times a second for the markers),
## not every frame.
func _process(delta: float) -> void:
	_redraw_t -= delta
	if main == null or main.player == null:
		return
	var p = main.player
	var k := Vector4(p.cam_yaw, p.global_position.x, p.global_position.z, size.x)
	if _redraw_t <= 0.0 or absf(k.x - _last_key.x) > 0.002 or Vector2(k.y - _last_key.y, k.z - _last_key.z).length() > 0.4 or k.w != _last_key.w:
		_last_key = k
		_redraw_t = 0.25
		queue_redraw()


static func heading(v: Vector3) -> float:
	return atan2(-v.x, -v.z) # 0 = north (-Z), matching player.cam_yaw


func _x_for(rel: float) -> float:
	return size.x * 0.5 - rel / SPAN * size.x * 0.5


func _draw() -> void:
	if director == null or main == null or main.player == null:
		return
	var p = main.player
	var yaw: float = p.cam_yaw
	var w := size.x
	var h := size.y
	# backing strip, fading at the ends
	draw_rect(Rect2(0, 6, w, h - 12), Color(0, 0, 0, 0.45))
	draw_line(Vector2(0, h - 6), Vector2(w, h - 6), Color(0.85, 0.7, 0.5, 0.5), 1.0)
	draw_line(Vector2(w * 0.5, 2), Vector2(w * 0.5, 10), Color(1, 0.9, 0.8), 2.0)
	# ticks and cardinals
	for i in 24:
		var a := TAU * i / 24.0
		var rel := wrapf(a - yaw, -PI, PI)
		if absf(rel) > SPAN:
			continue
		var x := _x_for(rel)
		var letter := ""
		match i:
			0: letter = "N"
			6: letter = "W"
			12: letter = "S"
			18: letter = "E"
		if letter != "":
			draw_string(font, Vector2(x - 6, h * 0.5 + 7), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.92, 0.85) if letter != "N" else Color(1, 0.35, 0.3))
		else:
			draw_line(Vector2(x, h - 14), Vector2(x, h - 7), Color(0.85, 0.8, 0.75, 0.6), 1.0)
	var pp: Vector3 = p.global_position
	var best_rel := 99.0
	var best_label := ""
	var best_x := 0.0
	# points of interest
	for poi in director.pois:
		var to: Vector3 = poi.global_position - pp
		var d := Vector2(to.x, to.z).length()
		if d > 170.0 or d < 2.0:
			continue
		var rel := wrapf(heading(to) - yaw, -PI, PI)
		if absf(rel) > SPAN:
			continue
		var x := _x_for(rel)
		var s := 8.0 if d > 60.0 else 10.0
		Icons.draw(self, poi.type, Vector2(x, h * 0.5), s, poi.def.color, poi.cleared)
		if absf(rel) < best_rel:
			best_rel = absf(rel)
			best_label = "%s  %dm" % [poi.display_name, int(d)]
			best_x = x
	# tonight's arena
	if director.arena != null and not director.arena.is_empty():
		var to: Vector3 = director.arena.pos - pp
		var d := Vector2(to.x, to.z).length()
		var rel := wrapf(heading(to) - yaw, -PI, PI)
		var x := _x_for(clampf(rel, -SPAN, SPAN))
		Icons.draw(self, "arena", Vector2(x, h * 0.5), 11.0, Color(1.0, 0.1, 0.1))
		if absf(rel) < best_rel or director.state in ["shrink2", "boss"]:
			best_rel = absf(rel)
			best_label = "%s  %dm" % [director.arena.name.capitalize(), int(d)]
			best_x = x
	# the Lost Tithe
	var dd: Dictionary = main.progression.death_drop
	if not dd.is_empty():
		var to := Vector3(dd.pos[0], 0, dd.pos[2]) - pp
		var rel := wrapf(heading(to) - yaw, -PI, PI)
		if absf(rel) <= SPAN:
			var x := _x_for(rel)
			draw_rect(Rect2(x - 3, 8, 6, h - 16), Color(1.0, 0.15, 0.1, 0.9))
	if best_label != "" and best_rel < 0.35:
		draw_string(font, Vector2(best_x - 120, h + 16), best_label, HORIZONTAL_ALIGNMENT_CENTER, 240, 14, Color(1, 0.9, 0.85))
	# outside the Curfew: point back in
	if director.outside_amount > 0.05 and director.ring != null:
		var to: Vector3 = director.ring.center - pp
		var rel := wrapf(heading(to) - yaw, -PI, PI)
		var x := _x_for(clampf(rel, -SPAN, SPAN))
		var c := Color(1, 0.2, 0.15, director.outside_amount)
		draw_colored_polygon(PackedVector2Array([Vector2(x, h + 2), Vector2(x - 9, h + 14), Vector2(x + 9, h + 14)]), c)
