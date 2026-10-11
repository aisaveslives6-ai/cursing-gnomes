class_name DrawnMenuIcon
extends Control
## Jeremy 2026-10-05 (polish): drawn menu-card icons — replaces the hidden
## emoji icon boxes on the main menu (the 2026-10-02 workaround hid them
## because Godot's default font renders emoji as tofu boxes in the web
## export). Pure vector draw commands — no font glyphs, no textures — so
## they always render on iPhone. Same pattern as DrawnX/DrawnChevron:
## mouse-filter IGNORE so the parent Button handles clicks.
##
## kind is one of KINDS; unknown kinds draw a fallback ring + dot so a
## typo never ships as an invisible icon (tests pin this).

const KINDS: Array[String] = [
	"play", "swords", "floppy", "eye", "dagger", "gear", "scroll", "speech",
]

var kind := "play"
var color := Color(1.0, 0.953, 0.839) # C_CREAM_BRIGHT
var thickness := 3.0


func _init(k: String = "play", c: Color = Color(1.0, 0.953, 0.839),
		th: float = 3.0) -> void:
	kind = k
	color = c
	thickness = th
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(44, 44)


func _draw() -> void:
	var s := size
	var cx := s.x * 0.5
	var cy := s.y * 0.5
	var r := minf(s.x, s.y) * 0.34
	match kind:
		"play":
			_draw_play(s)
		"swords":
			_draw_swords(s)
		"floppy":
			_draw_floppy(s)
		"eye":
			_draw_eye(s, cx, cy, r)
		"dagger":
			_draw_dagger(s)
		"gear":
			_draw_gear(s, cx, cy, r)
		"scroll":
			_draw_scroll(s)
		"speech":
			_draw_speech(s)
		_:
			# Fallback ring + dot: visible proof the kind was wrong.
			draw_arc(Vector2(cx, cy), r, 0.0, TAU, 24, color, thickness, true)
			draw_circle(Vector2(cx, cy), thickness * 0.9, color)


func _draw_play(s: Vector2) -> void:
	# Filled right-pointing triangle.
	var pts := PackedVector2Array([
		Vector2(s.x * 0.34, s.y * 0.28),
		Vector2(s.x * 0.34, s.y * 0.72),
		Vector2(s.x * 0.72, s.y * 0.50),
	])
	draw_colored_polygon(pts, color)


func _draw_swords(s: Vector2) -> void:
	# Two crossed blades with guards and pommels.
	var a1 := Vector2(s.x * 0.28, s.y * 0.24)
	var b1 := Vector2(s.x * 0.66, s.y * 0.70)
	var a2 := Vector2(s.x * 0.72, s.y * 0.24)
	var b2 := Vector2(s.x * 0.34, s.y * 0.70)
	draw_line(a1, b1, color, thickness, true)
	draw_line(a2, b2, color, thickness, true)
	# Guards: short perpendicular bars near each pommel end.
	for e in [b1, b2]:
		var tang := (b1 - a1).normalized() if e == b1 else (b2 - a2).normalized()
		var perp := Vector2(-tang.y, tang.x)
		var g := s.x * 0.07
		draw_line(e - perp * g, e + perp * g, color, thickness, true)
	# Pommels.
	draw_circle(b1 + (b1 - a1).normalized() * s.x * 0.05, thickness * 0.85, color)
	draw_circle(b2 + (b2 - a2).normalized() * s.x * 0.05, thickness * 0.85, color)


func _draw_floppy(s: Vector2) -> void:
	# Classic disk: square body, top label slot, side write-notch.
	var pad := s.x * 0.24
	var body := Rect2(pad, s.y * 0.22, s.x - pad * 2.0, s.y * 0.56)
	draw_rect(body, color, false, thickness)
	var label_w := body.size.x * 0.52
	var label := Rect2(
		body.position.x + (body.size.x - label_w) * 0.5,
		body.position.y, label_w, body.size.y * 0.34)
	draw_rect(label, color, false, thickness)
	var notch := Rect2(
		body.position.x + body.size.x * 0.72,
		body.position.y, body.size.x * 0.20, body.size.y * 0.34)
	draw_rect(notch, color, false, thickness * 0.7)


func _draw_eye(s: Vector2, cx: float, cy: float, r: float) -> void:
	# Almond outline + round pupil.
	var pts := PackedVector2Array()
	for i in range(33):
		var a := TAU * float(i) / 32.0
		pts.append(Vector2(cx + cos(a) * r * 1.35, cy + sin(a) * r * 0.85))
	draw_polyline(pts, color, thickness, true)
	draw_circle(Vector2(cx, cy), r * 0.45, color)


func _draw_dagger(s: Vector2) -> void:
	# Vertical blade, guard bar, grip, pommel.
	var cx := s.x * 0.5
	var blade := PackedVector2Array([
		Vector2(cx, s.y * 0.20),
		Vector2(cx - s.x * 0.075, s.y * 0.52),
		Vector2(cx + s.x * 0.075, s.y * 0.52),
	])
	draw_colored_polygon(blade, color)
	draw_line(Vector2(cx - s.x * 0.16, s.y * 0.55),
		Vector2(cx + s.x * 0.16, s.y * 0.55), color, thickness, true)
	draw_line(Vector2(cx, s.y * 0.57), Vector2(cx, s.y * 0.74),
		color, thickness, true)
	draw_circle(Vector2(cx, s.y * 0.77), thickness * 0.9, color)


func _draw_gear(s: Vector2, cx: float, cy: float, r: float) -> void:
	# Ring + 8 teeth + hub.
	draw_arc(Vector2(cx, cy), r * 0.72, 0.0, TAU, 32, color, thickness, true)
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(Vector2(cx, cy) + dir * r * 0.72,
			Vector2(cx, cy) + dir * r * 1.02, color, thickness, true)
	draw_arc(Vector2(cx, cy), r * 0.30, 0.0, TAU, 20, color, thickness, true)


func _draw_scroll(s: Vector2) -> void:
	# Parchment rect with rolled ends.
	var pad := s.x * 0.22
	var body := Rect2(pad, s.y * 0.28, s.x - pad * 2.0, s.y * 0.44)
	draw_rect(body, color, false, thickness)
	var roll := thickness * 1.1
	draw_circle(Vector2(body.position.x, s.y * 0.5), roll, color)
	draw_circle(Vector2(body.position.x + body.size.x, s.y * 0.5), roll, color)


func _draw_speech(s: Vector2) -> void:
	# Rounded bubble + tail.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_border_width_all(int(thickness))
	box.border_color = color
	box.set_corner_radius_all(int(s.x * 0.12))
	var body := Rect2(s.x * 0.20, s.y * 0.24, s.x * 0.60, s.y * 0.42)
	draw_style_box(box, body)
	var tail := PackedVector2Array([
		Vector2(s.x * 0.34, body.position.y + body.size.y - 1.0),
		Vector2(s.x * 0.30, s.y * 0.80),
		Vector2(s.x * 0.50, body.position.y + body.size.y - 1.0),
	])
	draw_colored_polygon(tail, color)
