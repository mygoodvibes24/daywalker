extends CanvasLayer
## The Hunt map (M / pad Back): Port Vesper drawn from city.gd's layout data — building
## footprints, the plaza — with every POI (cleared ones struck through), the Red Curfew now
## and where it closes next, tonight's arena, the Lost Tithe and Sol's arrow.
## It doesn't pause: the night keeps coming while you read it.

const Icons = preload("res://scripts/ui/poi_icons.gd")
const S = preload("res://scripts/ui/ui_style.gd")
const CityScript = preload("res://scripts/city.gd")
const MapLayout = preload("res://scripts/map/map_layout.gd")
const WORLD := MapLayout.HALF # half-extent shown (MAP HOOK: the large map's bounds)

var director: HuntDirector
var main: Main
var panel: Control
var frame: Control # clips the map drawing to its square
var canvas: Control # the map itself
var deco: Control # frame, title and legend
var font: Font


func _ready() -> void:
	layer = 20
	_bind()
	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(dim)
	deco = Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(_draw_deco)
	panel.add_child(deco)
	frame = Control.new()
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(frame)
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_map)
	frame.add_child(canvas)
	font = canvas.get_theme_default_font()
	panel.visible = false


static func _bind() -> void:
	if InputMap.has_action("hunt_map"):
		return
	InputMap.add_action("hunt_map")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_M
	InputMap.action_add_event("hunt_map", k)
	for jb in [JOY_BUTTON_BACK, JOY_BUTTON_TOUCHPAD]:
		var b := InputEventJoypadButton.new()
		b.button_index = jb
		b.device = -1
		InputMap.action_add_event("hunt_map", b)


func is_open() -> bool:
	return panel.visible


func open() -> void:
	panel.visible = true
	_redraw_t = 0.0
	_world_far(true)


func close() -> void:
	if panel != null:
		panel.visible = false
	_world_far(false)


## Frame budget (Group C): behind the dimmed map only the street around Sol is worth drawing,
## so the camera's far plane closes in while the map is up (the map-open view cost 1,000+ draws).
const MAP_OPEN_FAR := 45.0
var _saved_far := 0.0


func _world_far(on: bool) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	if on and _saved_far <= 0.0:
		_saved_far = cam.far
		cam.far = MAP_OPEN_FAR
	elif not on and _saved_far > 0.0:
		cam.far = _saved_far
		_saved_far = 0.0


func toggle() -> void:
	if panel.visible:
		close()
	else:
		open()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("hunt_map"):
		return
	if main == null or not main.started or main.game_over or main.menu_open() or get_tree().paused:
		return
	if director == null or director.state in ["idle", "over"]:
		return
	get_viewport().set_input_as_handled() # pad Back is the map in a Hunt, not the rain toggle
	toggle()


var _redraw_t := 0.0


## PERF: the map redraws 10 times a second while open (it drew every frame).
func _process(delta: float) -> void:
	if panel.visible:
		_redraw_t -= delta / maxf(Engine.time_scale, 0.01)
		if _redraw_t > 0.0:
			return
		_redraw_t = 0.1
		_layout()
		canvas.queue_redraw()
		deco.queue_redraw()


# ---------------------------------------------------------------- drawing
var _origin := Vector2.ZERO
var _scale := 1.0


func _w2m(p: Vector3) -> Vector2:
	return _origin + Vector2(p.x, p.z) * _scale


var _side := 400.0
var _tl := Vector2.ZERO


func _layout() -> void:
	var vs := panel.size
	_side = maxf(minf(vs.y - 120.0, vs.x - 380.0), 200.0)
	_tl = Vector2(vs.x * 0.5 - 90.0, vs.y * 0.5 + 10.0) - Vector2(_side, _side) * 0.5
	frame.position = _tl
	frame.size = Vector2(_side, _side)


func _draw_deco() -> void:
	var tl := _tl
	var side := _side
	deco.draw_rect(Rect2(tl - Vector2(10, 10), Vector2(side, side) + Vector2(20, 20)), Color(0.05, 0.035, 0.035, 0.96))
	deco.draw_rect(Rect2(tl - Vector2(10, 10), Vector2(side, side) + Vector2(20, 20)), S.GOLD_DIM, false, 1.5)
	_legend(Vector2(tl.x + side + 30.0, tl.y))
	deco.draw_string(font, Vector2(tl.x, tl.y - 22), "PORT VESPER  ·  " + director.phase_label(), HORIZONTAL_ALIGNMENT_LEFT, side + 300, 18, S.GOLD)


func _draw_map() -> void:
	var side := _side
	_scale = side / (WORLD * 2.0)
	_origin = Vector2(side, side) * 0.5
	var tl := Vector2.ZERO
	canvas.draw_rect(Rect2(tl, Vector2(side, side)), Color(0.03, 0.05, 0.08)) # the river
	# districts in colour (MAP HOOK: drawn from map_layout.gd), the quay and the waterfront
	var play: Rect2 = MapLayout.PLAY
	for d in MapLayout.DISTRICTS:
		var poly := PackedVector2Array()
		for v: Vector2 in d.poly:
			var q := Vector2(clampf(v.x, MapLayout.QUAY_X, MapLayout.HALF), clampf(v.y, -MapLayout.HALF, MapLayout.RIVER_Z))
			poly.append(_w2m(Vector3(q.x, 0, q.y)))
		var col: Color = d.color
		canvas.draw_colored_polygon(poly, Color(col.r * 0.22 + 0.06, col.g * 0.22 + 0.06, col.b * 0.22 + 0.06))
	canvas.draw_rect(Rect2(_w2m(Vector3(play.position.x, 0, play.position.y)), play.size * _scale), Color(0.6, 0.55, 0.5, 0.25), false, 1.0)
	var pr: Rect2 = CityScript.PLAZA_RECT
	canvas.draw_rect(Rect2(_w2m(Vector3(pr.position.x, 0, pr.position.y)), pr.size * _scale), Color(0.3, 0.27, 0.24))
	var lots: Array = main.city.lots if main.city != null and "lots" in main.city else []
	for r in lots:
		var rr: Rect2 = r
		canvas.draw_rect(Rect2(_w2m(Vector3(rr.position.x, 0, rr.position.y)), rr.size * _scale), Color(0.34, 0.31, 0.3))
	canvas.draw_circle(_w2m(Vector3.ZERO), 3.5 * _scale, Color(0.55, 0.1, 0.1))
	for d in MapLayout.DISTRICTS:
		var lp: Vector2 = _w2m(Vector3(d.label.x, 0, d.label.y))
		canvas.draw_string(font, lp + Vector2(-90, 0), d.name, HORIZONTAL_ALIGNMENT_CENTER, 180, 13, (d.color as Color).lightened(0.25))
	for lm in MapLayout.LANDMARKS:
		_landmark_icon(_w2m(lm.pos), lm.icon)
	# the Curfew: the blood-fog beyond the current wall, the next wall dashed
	var ring = director.ring
	var rc := _w2m(ring.center)
	_shade_outside(rc, ring.radius * _scale, tl, side)
	canvas.draw_arc(rc, ring.radius * _scale, 0, TAU, 128, Color(1.0, 0.1, 0.1, 0.95), 3.0)
	var nr: float = director.next_ring_radius()
	if nr > 0.0:
		_dashed_circle(_w2m(director.arena.pos), nr * _scale, Color(1.0, 0.95, 0.9, 0.85))
	# POIs
	for poi in director.pois:
		Icons.draw(canvas, poi.type, _w2m(poi.global_position), 9.0, poi.def.color, poi.cleared)
	for mp in director.micros: # micro-POIs: small diamonds, grey once taken
		if is_instance_valid(mp):
			var mc := _w2m(mp.global_position)
			var col: Color = Color(0.45, 0.45, 0.45) if mp.used else mp.def.color
			canvas.draw_colored_polygon(PackedVector2Array([mc + Vector2(0, -5), mc + Vector2(4, 0), mc + Vector2(0, 5), mc + Vector2(-4, 0)]), col)
	Icons.draw(canvas, "arena", _w2m(director.arena.pos), 13.0, Color(1.0, 0.12, 0.1))
	canvas.draw_string(font, _w2m(director.arena.pos) + Vector2(-100, 30), director.arena.name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 200, 13, Color(1, 0.6, 0.55))
	# deployment point
	var dp: Dictionary = director.deploy_point
	if not dp.is_empty():
		var c := _w2m(dp.pos)
		canvas.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color(0.4, 1.0, 0.6), false, 2.0)
	# Lost Tithe
	var dd: Dictionary = main.progression.death_drop
	if not dd.is_empty():
		var c := _w2m(Vector3(dd.pos[0], 0, dd.pos[2]))
		canvas.draw_circle(c, 6.0, Color(1, 0.1, 0.1))
		canvas.draw_circle(c, 3.0, Color(1, 0.8, 0.4))
	# Sol
	var p = main.player
	var pc := _w2m(p.global_position)
	var f := Vector2(sin(p.facing), cos(p.facing))
	var rt := Vector2(f.y, -f.x)
	canvas.draw_colored_polygon(PackedVector2Array([pc + f * 11.0, pc - f * 7.0 + rt * 7.0, pc - f * 3.0, pc - f * 7.0 - rt * 7.0]), Color(1, 1, 1))
	canvas.draw_polyline(PackedVector2Array([pc + f * 11.0, pc - f * 7.0 + rt * 7.0, pc - f * 3.0, pc - f * 7.0 - rt * 7.0, pc + f * 11.0]), Color(0, 0, 0), 1.5)


## Small glyphs for the landmarks you steer by.
func _landmark_icon(c: Vector2, icon: String) -> void:
	var col := Color(1.0, 0.92, 0.75)
	match icon:
		"spire":
			for dx in [-4.0, 4.0]:
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(dx - 3, 6), c + Vector2(dx, -10), c + Vector2(dx + 3, 6)]), col)
		"crane":
			canvas.draw_line(c + Vector2(-6, 8), c + Vector2(-6, -8), col, 2.0)
			canvas.draw_line(c + Vector2(6, 8), c + Vector2(6, -8), col, 2.0)
			canvas.draw_line(c + Vector2(-9, -8), c + Vector2(9, -8), col, 2.5)
			canvas.draw_circle(c + Vector2(0, -11), 2.0, Color(1, 0.2, 0.15))
		"tower":
			canvas.draw_rect(Rect2(c + Vector2(-5, -10), Vector2(10, 7)), col)
			canvas.draw_line(c + Vector2(-4, -3), c + Vector2(-6, 8), col, 1.5)
			canvas.draw_line(c + Vector2(4, -3), c + Vector2(6, 8), col, 1.5)
		"ruin":
			for k in 4:
				canvas.draw_line(c + Vector2(-6 + k * 4, 7), c + Vector2(-6 + k * 4, -5 + (k % 2) * 3), col, 2.0)
			canvas.draw_line(c + Vector2(-8, -6), c + Vector2(4, -6), col, 2.0)
		"dome":
			canvas.draw_arc(c + Vector2(0, 2), 7.0, PI, TAU, 12, col, 2.5)
			canvas.draw_line(c + Vector2(-8, 3), c + Vector2(8, 3), col, 2.0)
			canvas.draw_line(c + Vector2(0, -5), c + Vector2(0, -10), col, 2.0)


func _shade_outside(c: Vector2, r: float, tl: Vector2, side: float) -> void:
	# cheap: a thick translucent ring band just outside the wall
	var band := side * 1.5
	canvas.draw_arc(c, r + band * 0.5, 0, TAU, 128, Color(0.6, 0.0, 0.02, 0.3), band)


func _dashed_circle(c: Vector2, r: float, col: Color, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = canvas
	var n := 64
	for i in n:
		if i % 2 == 0:
			ci.draw_arc(c, r, TAU * i / n, TAU * (i + 1) / n, 4, col, 2.0)


func _legend(at: Vector2) -> void:
	var y := at.y
	deco.draw_string(font, Vector2(at.x, y + 14), "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, S.GOLD)
	y += 34
	var Cfg = load("res://scripts/hunt/hunt_config.gd")
	for t in Cfg.POI_TYPES:
		var d: Dictionary = Cfg.POI_TYPES[t]
		Icons.draw(deco, t, Vector2(at.x + 10, y), 9.0, d.color)
		deco.draw_string(font, Vector2(at.x + 28, y + 5), d.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, S.TEXT)
		y += 28
	var mc := Vector2(at.x + 10, y)
	deco.draw_colored_polygon(PackedVector2Array([mc + Vector2(0, -6), mc + Vector2(5, 0), mc + Vector2(0, 6), mc + Vector2(-5, 0)]), Color(1.0, 0.78, 0.35))
	deco.draw_string(font, Vector2(at.x + 28, y + 5), "Cache, captive, fridge, shrine", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, S.TEXT)
	y += 28
	Icons.draw(deco, "arena", Vector2(at.x + 10, y), 10.0, Color(1, 0.12, 0.1))
	deco.draw_string(font, Vector2(at.x + 28, y + 5), "Tonight's arena", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, S.TEXT)
	y += 28
	deco.draw_arc(Vector2(at.x + 10, y), 8, 0, TAU, 24, Color(1, 0.1, 0.1), 2.5)
	deco.draw_string(font, Vector2(at.x + 28, y + 5), "The Red Curfew", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, S.TEXT)
	y += 28
	_dashed_circle(Vector2(at.x + 10, y), 8, Color(1, 0.95, 0.9), deco)
	deco.draw_string(font, Vector2(at.x + 28, y + 5), "Where it closes next", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, S.TEXT)
	y += 40
	deco.draw_string(font, Vector2(at.x, y), "[M] / [Back] close", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, S.TEXT_DIM)
