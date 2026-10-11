extends SceneTree
## Cursing Gnomes — title-screen tips line tests.
##
## Jeremy 2026-10-08 ("Tips?"): the SC1 clean title dropped the rotating
## tips and he asked for them back. Contract: exactly ONE thin overlay
## line at the very bottom of the title screen — floats above the
## background, reserves NO layout space (the 2026-10-07 "Title screen is
## busted" lesson: reserving space clipped the third button on iPhone),
## never eats taps, single line, safe-area aware, rotates every few
## seconds. The full MENU_TIPS rotation still serves loading screens.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_title_tips.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed := 0
var _failed := 0
var _menu: MainMenu = null


func _check(cond: bool, test_name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + test_name)


func _collect_tip_labels(n: Node, out: Array) -> void:
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is Label and (x as Label).text.begins_with("TIP:"):
			out.append(x)
		for c in x.get_children():
			stack.push_back(c)


func _tip_label() -> Label:
	var out: Array = []
	_collect_tip_labels(_menu, out)
	if out.size() == 1:
		return out[0] as Label
	return null


func _init() -> void:
	_menu = MainMenu.new()
	root.add_child(_menu)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_check(_menu._screen == "title", "boots to title screen")
	_test_single_overlay_line()
	_test_safe_area_offsets()
	_test_rotation()
	_test_freed_on_navigation()
	_test_tip_content_rules()
	print("test_title_tips: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_single_overlay_line() -> void:
	var out: Array = []
	_collect_tip_labels(_menu, out)
	_check(out.size() == 1, "exactly one TIP: label on the title")
	var tl := _tip_label()
	_check(tl != null, "tip label resolvable")
	if tl == null:
		return
	_check(tl.get_parent() == _menu._root, "tip is a _root overlay, not in layout")
	_check(tl.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"tip never eats taps (MOUSE_FILTER_IGNORE)")
	_check(tl.autowrap_mode == TextServer.AUTOWRAP_OFF,
		"tip does not wrap (single thin line)")
	_check(tl.clip_text, "tip clips instead of overflowing")
	_check(tl.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
		"long tips trim with ellipsis")
	_check(tl.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"tip centered")
	_check(MainMenu.MENU_TIPS.has(tl.text), "tip text is a real MENU_TIPS entry")


func _test_safe_area_offsets() -> void:
	var tl := _tip_label()
	_check(tl != null, "tip label present for offset checks")
	if tl == null:
		return
	var insets: Vector4 = _menu._safe_insets()
	# Bottom edge sits above the home indicator (bottom inset + margin),
	# horizontal edges inside the left/right insets.
	_check(tl.offset_bottom < -insets.y,
		"tip bottom edge clears the home-indicator inset")
	_check(tl.offset_top < tl.offset_bottom,
		"tip has positive height")
	_check(tl.offset_bottom - tl.offset_top < _menu._px(60.0),
		"tip band is thin (under 60 canvas units)")
	_check(tl.offset_left >= insets.z,
		"tip left edge respects left safe inset")
	_check(tl.offset_right <= -insets.w,
		"tip right edge respects right safe inset")


func _test_rotation() -> void:
	var tl := _tip_label()
	_check(tl != null, "tip label present for rotation checks")
	if tl == null or MainMenu.MENU_TIPS.size() < 2:
		return
	var first: String = tl.text
	# Below the rotate threshold: no change.
	_menu._process(MainMenu.TITLE_TIP_ROTATE_SECS - 0.5)
	_check(tl.text == first, "tip does not rotate before the interval")
	# Past the threshold: advances exactly one tip.
	_menu._process(0.6)
	_check(tl.text != first, "tip rotates after the interval")
	_check(MainMenu.MENU_TIPS.has(tl.text), "rotated tip is a real entry")
	# Full cycle returns to the start (no repeats, no skips).
	var seen: Array = [first, tl.text]
	for i in range(MainMenu.MENU_TIPS.size() - 1):
		_menu._process(MainMenu.TITLE_TIP_ROTATE_SECS + 0.1)
		seen.append(tl.text)
	_check(tl.text == first, "full rotation cycles back to the first tip")
	_check(seen.size() == MainMenu.MENU_TIPS.size() + 1,
		"rotation visited every tip exactly once per cycle")


func _test_freed_on_navigation() -> void:
	var tl := _tip_label()
	_check(tl != null, "tip label present for navigation check")
	if tl == null:
		return
	_menu._clear_screen()
	_check(tl.is_queued_for_deletion(),
		"tip overlay freed with the screen on navigation")


func _test_tip_content_rules() -> void:
	# Menu glyph-walk smoke test trips on anything above U+2500
	# (iPhone tofu) — tips must stay ASCII-safe.
	var all_ascii := true
	for t: String in MainMenu.MENU_TIPS:
		for i in range(t.length()):
			if t.unicode_at(i) >= 0x2500:
				all_ascii = false
	_check(all_ascii, "all MENU_TIPS ASCII-safe (no iPhone tofu)")
	_check(not MainMenu.MENU_TIPS.is_empty(), "MENU_TIPS non-empty")
	_check(MainMenu.random_tip().begins_with("TIP:"),
		"random_tip() still serves loading screens")
