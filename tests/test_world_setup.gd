extends SceneTree
## Cursing Gnomes — world setup screen safe-area tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_world_setup.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	# WorldSetupScreen._ready() (which runs _build()) fires on the first
	# frame, not synchronously on add_child in -s script mode.
	await process_frame
	print("=== Cursing Gnomes world setup tests ===")
	_test_safe_insets()
	_test_tips_line()
	_test_lockpop_tap_outside()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## Jeremy 2026-10-06 (launch readiness): the world-gen screen reads its
## safe-area insets from the OS (DisplayServer.get_display_safe_area(),
## same pattern as hud.gd) instead of hardcoded portrait/landscape
## guesses that diverge from the real device.
func _test_safe_insets() -> void:
	var ws := WorldSetupScreen.new()
	root.add_child(ws)
	var insets: Vector4 = ws._safe_insets()
	var vsz: Vector2 = root.get_visible_rect().size
	var is_desktop := not DisplayServer.is_touchscreen_available() \
		and vsz.x >= 1024.0 and vsz.y >= 600.0
	if is_desktop:
		# Headless desktop: zero insets, no safe-area guessing.
		_check("safe insets desktop zero", insets == Vector4.ZERO)
	else:
		_check("safe insets non-negative",
			insets.x >= 0.0 and insets.y >= 0.0 \
			and insets.z >= 0.0 and insets.w >= 0.0)
	ws.queue_free()


## Jeremy 2026-10-08 ("Tips?"): the Forge-Your-World screen carries the
## rotating gameplay tips line (title screen stays SC1-clean). Tips come
## from MainMenu.random_tip(); ASCII-only per the iPhone tofu rule
## (menu glyph-walk trips on anything above U+2500).
func _test_tips_line() -> void:
	var ws := WorldSetupScreen.new()
	root.add_child(ws)
	# _ready() ran _build(): the tips label exists and shows a real tip.
	_check("tips label built", is_instance_valid(ws._tip_label))
	var first: String = ws._tip_label.text
	_check("tip non-empty", not first.is_empty())
	_check("tip has TIP prefix", first.begins_with("TIP:"))
	_check("random_tip helper non-empty",
		not String(MainMenu.random_tip()).is_empty())
	var ascii_ok := true
	for i in range(first.length()):
		if first.unicode_at(i) > 0x2500:
			ascii_ok = false
			break
	_check("tip ascii-only (no tofu glyphs)", ascii_ok)
	# Rotation: many spins always yield valid, non-repeating-adjacent tips.
	var seen := {}
	var prev := ""
	var valid := true
	var adjacent_repeat := false
	for i in range(40):
		ws._rotate_tip()
		var t: String = ws._tip_label.text
		if t.is_empty() or not t.begins_with("TIP:"):
			valid = false
		if t == prev:
			adjacent_repeat = true
		seen[t] = true
		prev = t
	_check("rotation stays valid", valid)
	_check("rotation never repeats back-to-back", not adjacent_repeat)
	_check("rotation shows variety", seen.size() >= 2)
	ws.queue_free()


## Jeremy's tap-outside-to-close rule: the "size needs a desktop" lock popup
## (Forge-Your-World screen) dismisses when the dim outside the card is
## tapped — the dim is no longer dead. The GOT IT button still works.
func _test_lockpop_tap_outside() -> void:
	var ws := WorldSetupScreen.new()
	ws._show_lockpop("huge")
	var pop: PanelContainer = null
	for c in ws.get_children():
		if c is PanelContainer:
			pop = c
	_check("lockpop: popup added", pop != null)
	if pop == null:
		ws.free()
		return
	var dim: ColorRect = null
	for c in pop.get_children():
		if c is ColorRect:
			dim = c
			break
	_check("lockpop: dim present", dim != null)
	if dim == null:
		ws.free()
		return
	_check("lockpop: dim full-rect",
		dim.anchor_right == 1.0 and dim.anchor_bottom == 1.0)
	_check("lockpop: dim stops taps", dim.mouse_filter == Control.MOUSE_FILTER_STOP)
	_check("lockpop: dim wired for tap-outside",
		dim.gui_input.get_connections().size() > 0)
	_check("lockpop: GOT IT button kept", _find_button(pop, "GOT IT") != null)
	_check("lockpop: no literal %s in body text", not _has_literal_percent(pop))
	# A tap on the dim (outside the card) dismisses the popup.
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	dim.gui_input.emit(touch)
	_check("lockpop: tap outside dismisses popup", pop.is_queued_for_deletion())
	ws.free()


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for c in node.get_children():
		var found := _find_button(c, text)
		if found != null:
			return found
	return null


func _has_literal_percent(node: Node) -> bool:
	if node is Label and (node as Label).text.contains("%s"):
		return true
	for c in node.get_children():
		if _has_literal_percent(c):
			return true
	return false
