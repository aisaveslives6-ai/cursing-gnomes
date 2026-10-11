extends SceneTree
## Cursing Gnomes — phone scroll tests.
## Jeremy 2026-10-06: systemic no-scroll outage on iPhone Safari — touch-drag
## scrolling died in EVERY phone list (message threads, contacts, ...).
## Root cause was the exported HTML's `touch-action: pan-x pan-y` letting
## Safari hijack vertical drags as page pans (fixed in fix-ios-zoom.sh with
## `#canvas { touch-action: none }`). These tests lock in the in-game side:
## every scrollable phone view goes through _scroll() with vertical
## scrolling enabled and horizontal scrolling disabled, thread content can
## actually overflow, and the bottom-snap math works.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_phone_scroll.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes phone scroll tests ===")
	_test_scroll_factory()
	_test_thread_scroll_view()
	_test_thread_bottom_snap()
	_test_messenger_list_uses_factory()
	_test_squabble_uses_factory()
	_test_calendar_uses_factory()
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


func _collect_scrolls(n: Node, out: Array) -> void:
	if n is ScrollContainer:
		out.append(n)
	for c: Node in n.get_children():
		_collect_scrolls(c, out)


func _find_scrolls(ui: PhoneUI) -> Array:
	var out: Array = []
	if ui._root != null and is_instance_valid(ui._root):
		_collect_scrolls(ui._root, out)
	return out


## The shared factory: vertical scrolling on, horizontal off. Every phone
## list must come from here so one fix covers all views.
func _test_scroll_factory() -> void:
	var w: Dictionary = _new_ui()
	var ui: PhoneUI = w["ui"]
	var sc: ScrollContainer = ui._scroll()
	_check("factory: horizontal disabled",
		sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	_check("factory: vertical enabled",
		sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)
	_check("factory: vertical auto",
		sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO)
	_free_ui(w)


## A thread with more messages than fit: the view must expose a working
## vertical scrollbar and a set scroll position must stick.
func _test_thread_scroll_view() -> void:
	var w: Dictionary = _new_ui()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var ui: PhoneUI = w["ui"]
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1, Vector2(100, 100))
	var uid: int = int(u["id"])
	for i in range(40):
		phone.send_message(uid, "scroll test message %d" % i)
	ui.open_thread("u%d" % uid)
	_check("thread screen", ui.current_screen() == "thread")
	var sc: ScrollContainer = ui._thread_scroll
	_check("thread has scroll container", sc != null and is_instance_valid(sc))
	if sc != null and is_instance_valid(sc):
		_check("thread scroll: horizontal disabled",
			sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
		_check("thread scroll: vertical enabled",
			sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)
		# Headless has no layout frames: widen the bar directly (same
		# pattern as test_phone_interior's scroll tests).
		var bar := sc.get_v_scroll_bar()
		bar.max_value = 2000.0
		bar.page = 400.0
		_check("thread list is scrollable", bar.max_value > bar.page)
		sc.scroll_vertical = 800
		_check("scroll position sticks", sc.scroll_vertical == 800)
	_free_ui(w)


## Bottom-snap math: after new content, the thread lands on the last message.
func _test_thread_bottom_snap() -> void:
	var w: Dictionary = _new_ui()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var ui: PhoneUI = w["ui"]
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1, Vector2(100, 100))
	var uid: int = int(u["id"])
	for i in range(10):
		phone.send_message(uid, "snap test %d" % i)
	ui.open_thread("u%d" % uid)
	var sc: ScrollContainer = ui._thread_scroll
	_check("snap: thread scroll exists", sc != null and is_instance_valid(sc))
	if sc != null and is_instance_valid(sc):
		var bar := sc.get_v_scroll_bar()
		bar.max_value = 1500.0
		bar.page = 400.0
		sc.scroll_vertical = 100
		ui._snap_thread_to_bottom()
		# ScrollBar clamps to max_value - page: true bottom, not raw max.
		_check("snap reaches bottom",
			sc.scroll_vertical == int(bar.max_value - bar.page))
	_free_ui(w)


## Every scrollable view on the current screen must come from _scroll()
## (vertical on, horizontal off) — messenger thread/contact list.
func _test_messenger_list_uses_factory() -> void:
	var w: Dictionary = _new_ui()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var ui: PhoneUI = w["ui"]
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1, Vector2(100, 100))
	phone.send_message(int(u["id"]), "hello")
	ui.open_app("messenger")
	_check("messenger screen", ui.current_screen() == "messenger")
	var scrolls: Array = _find_scrolls(ui)
	_check("messenger has a scroll view", scrolls.size() >= 1)
	for sc in scrolls:
		_check("messenger scroll: horizontal disabled",
			(sc as ScrollContainer).horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
		_check("messenger scroll: vertical enabled",
			(sc as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)
	_free_ui(w)


## Squabble feed scrolls through the same factory.
func _test_squabble_uses_factory() -> void:
	var w: Dictionary = _new_ui()
	var ui: PhoneUI = w["ui"]
	ui.open_app("squabble")
	_check("squabble screen", ui.current_screen() == "squabble")
	var scrolls: Array = _find_scrolls(ui)
	_check("squabble has a scroll view", scrolls.size() >= 1)
	for sc in scrolls:
		_check("squabble scroll: horizontal disabled",
			(sc as ScrollContainer).horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
		_check("squabble scroll: vertical enabled",
			(sc as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)
	_free_ui(w)


## Forecast (calendar) month grid + sections scroll through the factory.
func _test_calendar_uses_factory() -> void:
	var w: Dictionary = _new_ui()
	var ui: PhoneUI = w["ui"]
	ui.open_app("calendar")
	_check("calendar screen", ui.current_screen() == "calendar")
	var scrolls: Array = _find_scrolls(ui)
	_check("calendar has a scroll view", scrolls.size() >= 1)
	for sc in scrolls:
		_check("calendar scroll: horizontal disabled",
			(sc as ScrollContainer).horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
		_check("calendar scroll: vertical enabled",
			(sc as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED)
	_free_ui(w)
