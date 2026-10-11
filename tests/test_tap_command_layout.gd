extends SceneTree
## Cursing Gnomes — tap-to-command "Command Military" sheet layout tests
## (Jeremy 2026-10-10 P0: the sheet clipped off the right edge in portrait —
## the title read "Command Milita", body text and "Attack-Move He..." buttons
## were cut off).
##
## Proves the sheet fits phone widths: labels wrap instead of overflowing,
## buttons fill the sheet with a minimum width that fits portrait content,
## the sheet rect stays inside the viewport, and the sheet height follows
## the wrapped content.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tap_command_layout.gd
##
## Exit code 0 = all passed, 1 = any failure.


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


func _initialize() -> void:
	print("=== Cursing Gnomes tap-command layout tests ===")
	_run.call_deferred()


func _run() -> void:
	_test_widget_config()
	_test_panel_inside_viewport()
	await _test_content_fits_width(735.0, "portrait")
	await _test_content_fits_width(1870.0, "landscape")
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


## Longest real strings the sheet ever shows (n=240, enemy-target variant).
func _make_menu() -> Hud:
	var hud := Hud.new()
	hud._ui_scale = 2.5
	hud._build_command_menu()
	hud._cmd_title.text = "Command Military (240)"
	hud._cmd_sub.text = "An enemy is marked \u2014 tap Attack Target and " \
		+ "your entire military engages it."
	return hud


func _test_widget_config() -> void:
	var hud := _make_menu()
	_check("title wraps words",
		hud._cmd_title.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART)
	_check("subtitle wraps words",
		hud._cmd_sub.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART)
	_check("title expands to sheet width",
		hud._cmd_title.size_flags_horizontal & Control.SIZE_EXPAND_FILL != 0)
	_check("subtitle expands to sheet width",
		hud._cmd_sub.size_flags_horizontal & Control.SIZE_EXPAND_FILL != 0)
	for b in [hud._cmd_move_btn, hud._cmd_attack_btn, hud._cmd_cancel_btn]:
		_check("button fills sheet width: " + b.text,
			b.size_flags_horizontal & Control.SIZE_EXPAND_FILL != 0)
	# Buttons must fit the narrowest real content width: iPhone portrait
	# 390 CSS px at 2.5x = 975 canvas units, minus side insets (20+20),
	# sheet side margins (2x30) and stylebox content margins (2x70).
	var content_w := 975.0 - 40.0 - 60.0 - 140.0
	_check("button min width fits phone portrait content (%.0f)" % content_w,
		hud._cmd_move_btn.custom_minimum_size.x <= content_w)
	_check("sheet content scrolls vertically when too tall",
		hud._cmd_vbox.get_parent() is ScrollContainer)
	hud.queue_free()


func _test_panel_inside_viewport() -> void:
	var hud := _make_menu()
	# Headless: null viewport -> (800,600) fallback, fallback insets.
	hud._position_command_menu()
	var vsz := Vector2(800, 600)
	var left := hud._cmd_menu.offset_left
	var right := vsz.x + hud._cmd_menu.offset_right
	var bottom := vsz.y + hud._cmd_menu.offset_bottom
	_check("panel left inside viewport", left >= 0.0)
	_check("panel right inside viewport", right <= vsz.x + 0.5)
	_check("panel bottom inside viewport", bottom <= vsz.y + 0.5)
	_check("panel has positive width", right > left)
	_check("panel has positive height", bottom > vsz.y + hud._cmd_menu.offset_top)
	hud.queue_free()


## Lays the REAL sheet vbox out at a phone content width and asserts no
## child overflows it horizontally and the labels actually wrapped.
## portrait: 735 (975 - insets - margins - stylebox); landscape: 1870.
func _test_content_fits_width(content_w: float, tag: String) -> void:
	var hud := _make_menu()
	var host := Control.new()
	host.size = Vector2(content_w, 4000.0)
	root.add_child(host)
	var vbox: VBoxContainer = hud._cmd_vbox
	vbox.reparent(host)
	vbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	await process_frame
	await process_frame
	for c in vbox.get_children():
		if c is Control:
			_check("%s: child fits width (%.0f): %s" % [tag, content_w, c.get_class()],
				(c as Control).size.x <= content_w + 0.5)
	if tag == "portrait":
		# At phone-portrait width the longest real strings must wrap;
		# in landscape they may fit on fewer lines — only overflow matters.
		_check(tag + ": title wrapped to multiple lines",
			hud._cmd_title.get_line_count() >= 2)
		_check(tag + ": subtitle wrapped to multiple lines",
			hud._cmd_sub.get_line_count() >= 2)
	_check(tag + ": content height reported",
		hud._command_menu_content_h() > 0.0)
	host.queue_free()
	hud.queue_free()
