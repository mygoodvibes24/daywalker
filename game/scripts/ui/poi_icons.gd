extends RefCounted
## Vector icons for points of interest, drawn straight onto a CanvasItem (compass + map).

static func draw(ci: CanvasItem, type: String, c: Vector2, s: float, col: Color, cleared := false) -> void:
	var fill := col if not cleared else Color(0.45, 0.45, 0.45, 0.8)
	var ink := Color(0, 0, 0, 0.85)
	ci.draw_circle(c, s * 1.05, ink)
	match type:
		"nest": # a bat-wing chevron over a fang
			var pts := PackedVector2Array([c + Vector2(-s, -s * 0.2), c + Vector2(-s * 0.45, -s * 0.55), c + Vector2(0, -s * 0.15),
				c + Vector2(s * 0.45, -s * 0.55), c + Vector2(s, -s * 0.2), c + Vector2(s * 0.35, s * 0.15), c + Vector2(0, s * 0.8), c + Vector2(-s * 0.35, s * 0.15)])
			ci.draw_colored_polygon(pts, fill)
		"camp": # a flame
			var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.55, -s * 0.1), c + Vector2(s * 0.6, s * 0.45),
				c + Vector2(0, s * 0.85), c + Vector2(-s * 0.6, s * 0.45), c + Vector2(-s * 0.4, -s * 0.2), c + Vector2(-s * 0.1, s * 0.05)])
			ci.draw_colored_polygon(pts, fill)
		"market": # a crate
			ci.draw_rect(Rect2(c - Vector2(s, s) * 0.7, Vector2(s, s) * 1.4), fill)
			ci.draw_line(c + Vector2(-s * 0.7, -s * 0.7), c + Vector2(s * 0.7, s * 0.7), ink, maxf(s * 0.18, 1.0))
			ci.draw_line(c + Vector2(s * 0.7, -s * 0.7), c + Vector2(-s * 0.7, s * 0.7), ink, maxf(s * 0.18, 1.0))
		"fieldboss": # a horned skull
			ci.draw_circle(c + Vector2(0, -s * 0.1), s * 0.6, fill)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.35, s * 0.25), Vector2(s * 0.7, s * 0.45)), fill)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.5, -s * 0.4), c + Vector2(-s, -s), c + Vector2(-s * 0.25, -s * 0.6)]), fill)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.5, -s * 0.4), c + Vector2(s, -s), c + Vector2(s * 0.25, -s * 0.6)]), fill)
			ci.draw_circle(c + Vector2(-s * 0.22, -s * 0.1), s * 0.15, ink)
			ci.draw_circle(c + Vector2(s * 0.22, -s * 0.1), s * 0.15, ink)
		"chapel": # a cross
			ci.draw_rect(Rect2(c + Vector2(-s * 0.16, -s * 0.9), Vector2(s * 0.32, s * 1.8)), fill)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.45), Vector2(s * 1.2, s * 0.3)), fill)
		"merchant": # a coin
			ci.draw_circle(c, s * 0.75, fill)
			ci.draw_circle(c, s * 0.45, ink)
			ci.draw_circle(c, s * 0.25, fill)
		"arena": # a crimson crown of spikes
			var pts := PackedVector2Array()
			for i in 10:
				var a := TAU * i / 10.0 - PI / 2.0
				var r := s if i % 2 == 0 else s * 0.5
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			ci.draw_colored_polygon(pts, fill)
		_:
			ci.draw_circle(c, s * 0.6, fill)
	if cleared:
		ci.draw_line(c + Vector2(-s, -s) * 0.8, c + Vector2(s, s) * 0.8, Color(0.9, 0.9, 0.9), maxf(s * 0.2, 1.5))
