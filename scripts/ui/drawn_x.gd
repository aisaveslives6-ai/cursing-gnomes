class_name DrawnX
extends Control
## Jeremy 2026-10-04 (polish): drawn dismiss X — replaces the "×" text-glyph
## dismiss button on the main menu's update banner (tofu risk on iPhone;
## the back-button rule means no text X buttons anywhere in the UI).
## Pure draw commands, always renders. Same construction pattern as
## DrawnChevron (drawn_chevron.gd): color/thickness args, mouse-filter
## IGNORE so the parent Button handles clicks.
var color := Color(0.95, 0.95, 0.95)
var thickness := 8.0


func _init(c: Color = Color(0.95, 0.95, 0.95), th: float = 8.0) -> void:
	color = c
	thickness = th
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(44, 44)


func _draw() -> void:
	var s := size
	var pad := s.x * 0.30
	# X: two diagonal lines, corner to corner.
	draw_line(Vector2(pad, pad), Vector2(s.x - pad, s.y - pad),
		color, thickness, true)
	draw_line(Vector2(s.x - pad, pad), Vector2(pad, s.y - pad),
		color, thickness, true)
