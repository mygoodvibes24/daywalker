extends Node
## Voiced lines with subtitles (autoload "Dialogue"). Lines live in res://data/dialogue.json
## (see docs/DIALOGUE.md). One voice channel: lines never overlap, so no speaker ever talks
## over themself. A busy channel queues comms and boss lines, drops stale barks, and a
## higher-priority line (a boss intro) cuts in over a lower one (a bark).
##
##   Dialogue.play("curfew_warning")      # by id; returns false if it could not play/queue
##   Dialogue.play_group("bark_bite_")    # a random line whose id starts with the prefix
##   Dialogue.start_menu_banter()         # Nia and Sol chat while the main menu idles
##
## Subtitles: a bottom-centre label on its own CanvasLayer (menu and game), the speaker's
## name in their colour. Off when Settings.subtitles is false.

signal line_started(id: String)
signal line_finished(id: String)

const DATA := "res://data/dialogue.json"
const BARK_MAX_WAIT := 1.5 # a queued bark older than this is dropped, it would be stale
const QUEUE_MAX_WAIT := 20.0
const BANTER_IDLE := 9.0 # seconds without input before the menu banter starts
const BANTER_GAP := Vector2(22.0, 36.0) # seconds between two menu exchanges

var lines := {} # id -> Dictionary
var speakers := {}
var current := {} # the line playing now ({} when free)
var queue: Array = [] # [{line, at}]
var _player: AudioStreamPlayer
var _ends_at := 0 # msec when the current line is over (audio and subtitle)
var _last := {} # id -> msec last played (cooldowns)
var _layer: CanvasLayer
var _panel: PanelContainer
var _label: RichTextLabel
var _sub_fade := 0.0
var _banter := false
var _banter_next := 0 # msec
var _banter_idx := 0
var _last_input := 0 # msec


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load("res://scripts/settings.gd").ensure_buses()
	_load()
	_player = AudioStreamPlayer.new()
	_player.bus = "Voice"
	add_child(_player)
	_build_subtitles()


func _load() -> void:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		push_error("Dialogue: cannot open " + DATA)
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		push_error("Dialogue: bad JSON in " + DATA)
		return
	speakers = d.get("speakers", {})
	for l in d.get("lines", []):
		lines[l.id] = l


func _build_subtitles() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 60
	add_child(_layer)
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(anchor)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -132
	anchor.add_child(_panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 20)
	_label.add_theme_font_size_override("bold_font_size", 20)
	_label.add_theme_color_override("default_color", Color(0.95, 0.92, 0.88))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	_panel.add_child(_label)
	_panel.visible = false


# ---------------------------------------------------------------- API
func has_line(id: String) -> bool:
	return lines.has(id)


## Play a line by id. Returns true if it started or was queued.
func play(id: String) -> bool:
	if not lines.has(id):
		push_warning("Dialogue: no line '%s'" % id)
		return false
	var l: Dictionary = lines[id]
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, -1000000)) < int(float(l.get("cooldown", 0)) * 1000.0):
		return false
	if not _audio().unlocked:
		return false # browsers: nothing before the first gesture
	var pr := int(l.get("priority", 1))
	if current.is_empty():
		_start(l)
		return true
	if pr > int(current.get("priority", 0)):
		_stop_current() # a boss intro beats a bark
		_start(l)
		return true
	if pr <= 1 and l.get("category", "") == current.get("category", ""):
		return false # one bark at a time; the moment has passed
	for q in queue:
		if q.line.id == id:
			return true
	queue.append({"line": l, "at": now})
	queue.sort_custom(func(a, b): return int(a.line.priority) > int(b.line.priority))
	_last[id] = now # the cooldown starts now, so a queued bark can't be re-queued
	return true


## Play a random line whose id starts with `prefix` (variants: bark_bite_1, bark_bite_2).
func play_group(prefix: String) -> bool:
	var ids := []
	var now := Time.get_ticks_msec()
	for id in lines:
		if id.begins_with(prefix) and now - int(_last.get(id, -1000000)) >= int(float(lines[id].get("cooldown", 0)) * 1000.0):
			ids.append(id)
	if ids.is_empty():
		return false
	var ok := play(ids.pick_random())
	if ok:
		for id in ids: # variants share the cooldown
			_last[id] = now
	return ok


func is_speaking() -> bool:
	return not current.is_empty()


func stop_all() -> void:
	queue.clear()
	_stop_current()


## Low blood: Sol grunts first, Nia nags if it stays low.
func on_player_hurt(frac: float) -> void:
	if frac < 0.3:
		if not play_group("bark_lowhp_") and frac < 0.2:
			play("nia_low_blood")


# ---------------------------------------------------------------- menu banter
func start_menu_banter() -> void:
	_banter = true
	_last_input = Time.get_ticks_msec()
	_banter_next = _last_input + int(BANTER_IDLE * 1000.0)


func stop_menu_banter() -> void:
	_banter = false
	if current.get("category", "") == "menu":
		stop_all()


func _menu_pairs() -> Array:
	var ids := []
	for id in lines:
		if id.begins_with("menu_lair_") and id.ends_with("a"):
			ids.append(id)
	ids.sort()
	return ids


func _input(event: InputEvent) -> void:
	if not _banter:
		return
	if event is InputEventMouseMotion and event.relative.length() < 4.0:
		return
	if event is InputEventJoypadMotion and absf(event.axis_value) < 0.5:
		return
	_last_input = Time.get_ticks_msec()
	if event.is_pressed() and current.get("category", "") == "menu":
		stop_all() # never talk over the player clicking
		_banter_next = _last_input + int(BANTER_IDLE * 1000.0)


func _banter_tick(now: int) -> void:
	if not current.is_empty() or not queue.is_empty() or now < _banter_next:
		return
	if now - _last_input < int(BANTER_IDLE * 1000.0):
		return
	var pairs := _menu_pairs()
	if pairs.is_empty():
		return
	var a: String = pairs[_banter_idx % pairs.size()]
	_banter_idx += 1
	if play(a):
		var b := a.left(a.length() - 1) + "b"
		if lines.has(b):
			queue.append({"line": lines[b], "at": _ends_at})
	_banter_next = now + int(randf_range(BANTER_GAP.x, BANTER_GAP.y) * 1000.0)


# ---------------------------------------------------------------- playback
func _audio() -> Node:
	return get_node("/root/Audio")


func _start(l: Dictionary) -> void:
	current = l
	var now := Time.get_ticks_msec()
	_last[l.id] = now
	var s = load(l.audio) if ResourceLoader.exists(l.audio) else null
	var secs := float(l.get("duration", 2.0))
	if s != null:
		_player.stream = s
		_player.play()
		secs = maxf(secs, s.get_length())
	_ends_at = now + int(secs * 1000.0)
	_show_subtitle(l)
	line_started.emit(l.id)


func _stop_current() -> void:
	if current.is_empty():
		return
	var id: String = current.id
	_player.stop()
	current = {}
	_hide_subtitle()
	line_finished.emit(id)


func _show_subtitle(l: Dictionary) -> void:
	var sp: Dictionary = speakers.get(l.speaker, {"name": str(l.speaker).to_upper(), "color": "#ffffff"})
	_label.text = "[b][color=%s]%s[/color][/b]   %s" % [sp.color, sp.name, l.text]
	_panel.visible = subtitles_on()
	_panel.modulate.a = 1.0


func _hide_subtitle() -> void:
	_panel.visible = false


func subtitles_on() -> bool:
	return bool(load("res://scripts/settings.gd").subtitles)


func subtitle_text() -> String:
	return _label.get_parsed_text() if _panel.visible else ""


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if not current.is_empty() and now >= _ends_at and not _player.playing:
		var id: String = current.id
		current = {}
		_hide_subtitle()
		line_finished.emit(id)
	if current.is_empty() and not queue.is_empty():
		while not queue.is_empty():
			var q: Dictionary = queue.pop_front()
			var wait := (now - int(q.at)) / 1000.0
			var limit := BARK_MAX_WAIT if int(q.line.priority) <= 1 else QUEUE_MAX_WAIT
			if q.line.category == "menu":
				limit = 3.0
			if wait <= limit:
				_start(q.line)
				break
	if _banter:
		_banter_tick(now)
