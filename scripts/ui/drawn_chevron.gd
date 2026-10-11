class_name DrawnChevron
extends Control
## Jeremy 2026-10-04 (polish): drawn back chevron — replaces "X" text and
## "←" text-glyph buttons (both are tofu risks / rule violations on iPhone).
## Pure draw commands, always renders. Shared by hud.gd (REALM drawer) and
## unit_info.gd (unit panel header); matches the geometry of the phone's
## ChevronIcon inner class (phone_ui.gd) so all back affordances look alike.
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
	# Left-pointing chevron: two lines forming "<"
	draw_line(Vector2(s.x - pad, pad), Vector2(pad, s.y * 0.5),
		color, thickness, true)
	draw_line(Vector2(pad, s.y * 0.5), Vector2(s.x - pad, s.y - pad),
		color, thickness, true)
