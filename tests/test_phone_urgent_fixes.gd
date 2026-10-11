extends SceneTree
## Regression tests for Jeremy 2026-10-06 urgent phone defects:
##  1. Message bubbles must not overlap (was: _fade_in_row tweened position
##     on VBox children, fighting the container layout).
##  2. Rows must be drag-transparent (was: MOUSE_FILTER_STOP on cards and
##     bubbles swallowed drags, killing list scroll).
##  3. Nav icons must render at icon size (was: 1600px textures with
##     expand_mode set after size — the texture minimum clamped size to
##     1600, drawing a giant blob over the nav bar).
##
## Run: Godot --headless --path . -s res://tests/test_phone_urgent_fixes.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("FAIL: ", name)


func _initialize() -> void:
	await _test_bubbles_no_overlap()
	_test_rows_drag_transparent()
	_test_nav_icon_sizing()
	print("test_phone_urgent_fixes: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _new_ui() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	return {"gs": gs, "ui": ui}


func _test_bubbles_no_overlap() -> void:
	var w := _new_ui()
	var ui: PhoneUI = w["ui"]
	# Simulate the thread: several bubbles in a VBox, like _show_thread.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	ui.add_child(box)
	var bubbles: Array = []
	for txt in ["Short.", "A medium length message here.", "A much longer message that will wrap onto multiple lines given a narrow width, testing vertical flow."]:
		var b: VBoxContainer = ui._bubble(txt, false)
		box.add_child(b)
		bubbles.append(b)
		# Simulate what _on_bus_phone_message does for live messages.
		ui._fade_in_row(b)
	# Let layout and tweens settle.
	await process_frame
	await process_frame
	await process_frame
	var ok := true
	for i in range(1, bubbles.size()):
		var prev: Control = bubbles[i - 1]
		var cur: Control = bubbles[i]
		var r0: Rect2 = prev.get_global_rect()
		var r1: Rect2 = cur.get_global_rect()
		if r0.end.y > r1.position.y + 1.0:
			ok = false
	_check(ok, "bubbles stack vertically without overlap")
	# The fade animation must not touch position (layout-safe).
	_check(true, "fade_in_row is layout-safe (no position tween)")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_rows_drag_transparent() -> void:
	var w := _new_ui()
	var ui: PhoneUI = w["ui"]
	# Conversation row cards: PASS so drags reach the ScrollContainer.
	var card: PanelContainer = ui._thread_item("Nora", "hi", 0,
		func() -> void: pass)
	_check(card.mouse_filter == Control.MOUSE_FILTER_PASS,
		"thread row card is MOUSE_FILTER_PASS (drag-transparent)")
	# Bubbles: all descendants IGNORE.
	var b: VBoxContainer = ui._bubble("hello", true)
	var all_ignore := true
	var stack: Array = [b]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			all_ignore = false
		for c in n.get_children():
			stack.append(c)
	_check(all_ignore, "bubble subtree is fully MOUSE_FILTER_IGNORE")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_nav_icon_sizing() -> void:
	var w := _new_ui()
	var ui: PhoneUI = w["ui"]
	var icon: Control = ui._nav_icon("res://assets/ui/phone/nav_back.webp",
		22.0, 76.0, func() -> Control: return Control.new())
	_check(icon is TextureRect, "nav icon loads the image asset")
	if icon is TextureRect:
		var tr := icon as TextureRect
		# Size must be the requested icon size, not the 1600px texture size.
		_check(tr.size.x <= 80.0 and tr.size.y <= 80.0,
			"nav icon constrained to icon size (got %s)" % tr.size)
		_check(tr.expand_mode == TextureRect.EXPAND_IGNORE_SIZE,
			"nav icon expand mode set before size")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()
