extends SceneTree
## Cursing Gnomes — end-screen scroll tests (Jeremy 2026-10-10, POLISH MODE).
##
## Menu scroll audit remnant finding: scripts/ui/end_screen.gd laid out its
## title (88px) + message + two 88px buttons in a bare CenterContainer with
## no scroll. The sandbox case ("SIMULATION COMPLETE" + 2-line message,
## ~425px total) clipped ~25px top/bottom on the smallest landscape phones
## (~375px canvas) — title slightly clipped, MAIN MENU button partially
## clipped but still tappable.
## Jeremy: "a lot of menus don't have proper scroll."
##
## Fix: the content vbox now lives inside a vertical-only ScrollContainer
## capped at 90% of the viewport height. Short content keeps the old
## centered look (inner vbox minimum height = cap height).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_end_screen_scroll.gd
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


func _initialize() -> void:
	print("=== Cursing Gnomes end-screen scroll tests ===")
	_run.call_deferred()


func _find_first(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c: Node in n.get_children():
		var r := _find_first(c, cls)
		if r != null:
			return r
	return null


func _is_descendant_of(ancestor: Node, n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false


func _find_button(es: Node, text: String) -> Button:
	var stack: Array[Node] = [es]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == text:
			return n as Button
		for c: Node in n.get_children():
			stack.push_back(c)
	return null


func _run() -> void:
	await process_frame
	await process_frame

	var es := EndScreen.new()
	root.add_child(es)
	await process_frame
	await process_frame

	var vp: Vector2 = root.get_visible_rect().size
	var want_w: float = minf(vp.x * 0.94, 560.0)
	var want_h: float = vp.y * 0.90

	# 1. Content must live inside a ScrollContainer.
	var scroll := _find_first(es, "ScrollContainer") as ScrollContainer
	_check("scroll container exists", scroll != null)
	if scroll == null:
		print("  passed: ", _passed, " failed: ", _failed)
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
		return

	# 2. Vertical-only touch scroll: horizontal disabled so drags never
	#    pan sideways and taps can't mis-fire mid-scroll.
	_check("horizontal scroll disabled",
		scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)

	# 3. Scroll area capped at 90% viewport height — can never run off-screen.
	_check("scroll height capped at 90vh",
		scroll.custom_minimum_size.y <= vp.y * 0.90 + 1.0)
	_check("scroll height matches 90vh cap",
		absf(scroll.custom_minimum_size.y - want_h) < 1.0)

	# 4. Width preserved from the old layout (94% viewport, max 560).
	_check("scroll width preserved",
		absf(scroll.custom_minimum_size.x - want_w) < 1.0)

	# 5. Title, message and both buttons are inside the scroll (all reachable).
	var again := _find_button(es, "PLAY AGAIN")
	var menu := _find_button(es, "MAIN MENU")
	_check("play again button exists", again != null)
	_check("main menu button exists", menu != null)
	_check("play again inside scroll",
		again != null and _is_descendant_of(scroll, again))
	_check("main menu inside scroll",
		menu != null and _is_descendant_of(scroll, menu))

	# 6. The inner vbox keeps the old centered look for short content:
	#    its minimum height equals the cap height.
	var vbox := _find_first(scroll, "VBoxContainer") as VBoxContainer
	_check("inner vbox exists", vbox != null)
	if vbox != null:
		_check("inner vbox min height equals cap (centered short content)",
			absf(vbox.custom_minimum_size.y - want_h) < 1.0)
		_check("inner vbox centered alignment",
			vbox.alignment == BoxContainer.ALIGNMENT_CENTER)

	# 7. All three end kinds render without error; sandbox (tallest) still
	#    capped — the case that clipped before the fix.
	es.show_end("sandbox", "",
		"Ass dominated the continent. (Sandbox \u2014 you were an observer.)\nSecond line for height.")
	await process_frame
	_check("sandbox end shows", es.visible)
	_check("scroll still capped after sandbox show",
		scroll.custom_minimum_size.y <= vp.y * 0.90 + 1.0)
	es.show_end("victory", "", "Ass stands. Enemy Halls are rubble.")
	_check("victory title set", (es as EndScreen)._title.text == "VICTORY")
	es.show_end("defeat", "", "The Hall of Ass has fallen.")
	_check("defeat title set", (es as EndScreen)._title.text == "DEFEAT")
	es.hide_end()
	_check("hide_end hides", not es.visible)

	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)
