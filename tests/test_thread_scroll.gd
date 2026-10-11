extends SceneTree
## Cursing Gnomes — messenger thread scroll regression (Jeremy 2026-10-11).
##
## Jeremy's standing complaint: "a lot of menus don't have proper scroll."
## The 2026-10-07 rumors fix (test_rumors_scroll.gd) established the
## contract: every Control inside a scrollable list is MOUSE_FILTER_IGNORE
## except Button subtrees, which keep STOP so they stay tappable — because
## a default-STOP PanelContainer/Label swallows the touch drag before it
## reaches the ScrollContainer.
##
## The thread view's message bubbles already honored it
## (PhoneUI._bubble -> _ignore_mouse), but five thread children did not:
##   - _day_divider (row + pill + label, all default-STOP)
##   - _receipt_label (default-STOP Label under every sent bubble)
##   - _show_typing_indicator (row + bubble + labels, all default-STOP)
##   - _counsel_button_row / _gnomba_button_row / _podcast_button_row
##     (the row background between the inline Accept/Deny-style buttons
##     was default-STOP; drags starting there died instead of scrolling)
## A long thread — day dividers, receipts, typing, and an inline decision
## row — could therefore refuse to scroll depending on where the drag
## started. Fixed with PhoneUI._drag_safe (IGNORE everything except
## Button subtrees), applied to all five.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_thread_scroll.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes thread scroll tests ===")
	_test_thread_extras_drag_safe()
	_test_inline_buttons_stay_tappable()
	_test_bubbles_still_drag_safe()
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


## Fresh game + phone UI.
func _new_ui() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	return {"gs": gs, "phone": phone, "court": court, "ui": ui}


func _free_ui(w: Dictionary) -> void:
	(w["ui"] as PhoneUI).queue_free()
	(w["gs"] as GameState).queue_free()


## Count STOP controls that are NOT inside a Button subtree. Mirrors the
## rumors contract: drags must reach the ScrollContainer from anywhere on
## a display-only item.
func _drag_swallowers(n: Node) -> int:
	var bad := 0
	var stack: Array = [[n, false]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var in_button: bool = item[1]
		if node is Button:
			in_button = true
		if node is Control and not in_button:
			if (node as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
				bad += 1
		for c in node.get_children():
			stack.append([c, in_button])
	return bad


func _buttons_under(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button:
			out.append(node)
		for c in node.get_children():
			stack.append(c)
	return out


## Build a busy thread: bubbles, day dividers, read receipts, the typing
## indicator, and all three inline decision rows. None of it may swallow
## drags outside the buttons.
func _test_thread_extras_drag_safe() -> void:
	var w: Dictionary = _new_ui()
	var ui: PhoneUI = w["ui"]
	var box := VBoxContainer.new()
	root.add_child(box)
	ui._thread_box = box
	for i in 30:
		box.add_child(ui._bubble("Message %d from the war council." % i, i % 2 == 0))
		if i % 5 == 0:
			box.add_child(ui._day_divider("Day %d" % (i / 5 + 1)))
		if i % 2 == 0:
			box.add_child(ui._receipt_label("read"))
	ui._show_typing_indicator()
	box.add_child(ui._counsel_button_row(7))
	box.add_child(ui._gnomba_button_row(7))
	box.add_child(ui._podcast_button_row(7))
	_check("thread: no drag-swallowers outside buttons",
		_drag_swallowers(box) == 0)
	# The typing row specifically (bubble + labels inside the scroll box).
	_check("thread: typing indicator drag-safe",
		ui._typing_row != null and _drag_swallowers(ui._typing_row) == 0)
	_free_ui(w)
	box.queue_free()


## The inline decision rows must keep working: every button stays STOP so
## taps still land, and each row keeps its full button set.
func _test_inline_buttons_stay_tappable() -> void:
	var w: Dictionary = _new_ui()
	var ui: PhoneUI = w["ui"]
	var rows: Array = [
		["counsel", ui._counsel_button_row(7), ["Accept", "Deny"]],
		["gnomba", ui._gnomba_button_row(7), ["Send 500g", "Block & Report"]],
		["podcast", ui._podcast_button_row(7), ["Sponsor 300g", "Unplug"]],
	]
	for r: Array in rows:
		var tag: String = r[0]
		var row: Control = r[1]
		var want: Array = r[2]
		var btns: Array = _buttons_under(row)
		_check("%s: has %d buttons" % [tag, want.size()], btns.size() == want.size())
		var texts: Array = []
		var all_stop := true
		for b: Button in btns:
			texts.append(b.text)
			if b.mouse_filter != Control.MOUSE_FILTER_STOP:
				all_stop = false
		for label: String in want:
			_check("%s: has '%s' button" % [tag, label], texts.has(label))
		_check("%s: buttons keep STOP (tappable)" % tag, all_stop)
		row.queue_free()
	_free_ui(w)


## Guard the pre-existing bubble contract: _bubble's subtree (wrap, row,
## panel, label, avatar, timestamp) must stay fully drag-safe.
func _test_bubbles_still_drag_safe() -> void:
	var w: Dictionary = _new_ui()
	var ui: PhoneUI = w["ui"]
	var sent: VBoxContainer = ui._bubble("Attack at dawn.", true)
	var recv: VBoxContainer = ui._bubble("We stand ready, my liege.", false, null, "Day 3")
	_check("bubbles: sent bubble drag-safe", _drag_swallowers(sent) == 0)
	_check("bubbles: received bubble drag-safe", _drag_swallowers(recv) == 0)
	sent.queue_free()
	recv.queue_free()
	_free_ui(w)
