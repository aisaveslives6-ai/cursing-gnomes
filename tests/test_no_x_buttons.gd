extends SceneTree
## Cursing Gnomes — no-"X" button tests (Jeremy 2026-10-04).
##
## Jeremy's phone UI rule: apps use a BACK button, never an X.
## The phone UI already replaced its X with a drawn back chevron
## (phone_ui.gd ChevronIcon). These tests pin the last two "X" text
## buttons — the REALM drawer (hud.gd) and the unit info header
## (unit_info.gd) — to the shared DrawnChevron (drawn chevron, no
## text glyph, tofu-safe on iPhone).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_no_x_buttons.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## Live (non-comment) lines containing `text = "X"` or `text = "×"`
## (U+00D7) — a text X dismiss button (tofu on iPhone, breaks the rule).
static func _x_button_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line()
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if line.find('text = "X"') >= 0 or line.find('text = "×"') >= 0:
			out.append(line.strip_edges().left(100))
	f.close()
	return out


func _initialize() -> void:
	print("test_no_x_buttons: Jeremy 2026-10-04 back-button rule")
	var base := "res://scripts/ui/"

	# 1. No live "X" text buttons remain in the last two spots.
	var hud_x: Array[String] = _x_button_lines(base + "hud.gd")
	_check("hud.gd has no 'text = \"X\"' on live lines", hud_x.is_empty())
	for l: String in hud_x:
		print("    leftover in hud.gd: ", l)
	var ui_x: Array[String] = _x_button_lines(base + "unit_info.gd")
	_check("unit_info.gd has no 'text = \"X\"' on live lines", ui_x.is_empty())
	for l: String in ui_x:
		print("    leftover in unit_info.gd: ", l)
	# 1b. 2026-10-04 (16:19 pass): the main menu's update banner had a
	# live 'text = "×"' (U+00D7) dismiss button — same rule violation.
	var menu_x: Array[String] = _x_button_lines(base + "main_menu.gd")
	_check("main_menu.gd has no live text X/× buttons", menu_x.is_empty())
	for l: String in menu_x:
		print("    leftover in main_menu.gd: ", l)

	# 2. The shared chevron class exists and is wired in both places.
	var chev_path := "res://scripts/ui/drawn_chevron.gd"
	_check("drawn_chevron.gd exists",
		FileAccess.file_exists(chev_path))
	var chev := DrawnChevron.new()
	_check("DrawnChevron instantiates as a Control", chev is Control)
	_check("DrawnChevron has a positive minimum size",
		chev.custom_minimum_size.x > 0.0)
	_check("DrawnChevron ignores the mouse (button handles clicks)",
		chev.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var tinted := DrawnChevron.new(Color(1.0, 0.55, 0.5), 9.0)
	_check("DrawnChevron accepts color/thickness args",
		tinted.color == Color(1.0, 0.55, 0.5) and tinted.thickness == 9.0)
	chev.queue_free()
	tinted.queue_free()

	# 3. 2026-10-04 (16:19 pass): the drawn dismiss X used by the main
	# menu's update banner (replaces the text "×" glyph).
	var x_path := "res://scripts/ui/drawn_x.gd"
	_check("drawn_x.gd exists", FileAccess.file_exists(x_path))
	var xmark := DrawnX.new()
	_check("DrawnX instantiates as a Control", xmark is Control)
	_check("DrawnX has a positive minimum size",
		xmark.custom_minimum_size.x > 0.0)
	_check("DrawnX ignores the mouse (button handles clicks)",
		xmark.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var xtinted := DrawnX.new(Color(0.6, 0.2, 1.0), 3.0)
	_check("DrawnX accepts color/thickness args",
		xtinted.color == Color(0.6, 0.2, 1.0) and xtinted.thickness == 3.0)
	xmark.queue_free()
	xtinted.queue_free()

	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		quit(1)
	else:
		quit(0)
