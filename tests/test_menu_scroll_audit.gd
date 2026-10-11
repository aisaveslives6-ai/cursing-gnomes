extends SceneTree
## Cursing Gnomes — menu scroll audit, drag-swallower contract (Jeremy 2026-10-11).
##
## Jeremy's standing complaint: "a lot of menus don't have proper scroll."
## The 2026-10-07 rumors fix (test_rumors_scroll.gd) and the 2026-10-11
## messenger-thread fix (test_thread_scroll.gd) established the contract:
## every Control inside a ScrollContainer is MOUSE_FILTER_IGNORE except
## Button subtrees, which keep STOP so they stay tappable — because a
## default-STOP Label/Container/Panel swallows the touch drag before it
## reaches the ScrollContainer, so scrolling dies depending on where the
## drag starts.
##
## This suite pins the contract on the six remaining scrollables:
##   end_screen.gd, trader_panel.gd, unit_info.gd, world_setup.gd,
##   main_menu.gd (title screen), adventure_hud.gd (quest panel).
## world_setup's two carousel views are intentional STOP controls: they
## run a direction lock (horizontal = spin, vertical bubbles to the
## ScrollContainer — see _on_car_input), so the test allowlists them.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_menu_scroll_audit.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _gs: GameState = null


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	print("=== Cursing Gnomes menu scroll audit tests ===")
	_run.call_deferred()


## Count STOP controls that are NOT inside a Button subtree, skipping the
## given allowlisted subtree roots (intentional interactive controls).
func _drag_swallowers(n: Node, skip: Array = []) -> int:
	var bad := 0
	var stack: Array = [[n, false]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		if skip.has(node):
			continue
		var in_button: bool = item[1]
		if node is Button:
			in_button = true
		if node is Control and not in_button:
			if (node as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
				bad += 1
		for c in node.get_children():
			stack.append([c, in_button])
	return bad


func _buttons_under(n: Node, skip: Array = []) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if skip.has(node):
			continue
		if node is Button:
			out.append(node)
		for c in node.get_children():
			stack.append(c)
	return out


func _scrolls_under(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is ScrollContainer:
			out.append(node)
		for c in node.get_children():
			stack.append(c)
	return out


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	return gs


func _run() -> void:
	_gs = _new_game()
	await process_frame
	await process_frame
	# Each test suspends on awaits, so await them in order — otherwise
	# _run would reach quit() before the deferred bodies resume.
	await _test_end_screen()
	await _test_trader_panel()
	await _test_unit_info()
	await _test_world_setup()
	await _test_main_menu_title()
	await _test_adventure_quest_panel()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	_gs.queue_free()
	quit(1 if _failed > 0 else 0)


func _test_end_screen() -> void:
	var es := EndScreen.new()
	root.add_child(es)
	await process_frame
	await process_frame
	var scrolls := _scrolls_under(es)
	_check("end_screen: has a ScrollContainer", not scrolls.is_empty())
	var bad := 0
	var btns: Array = []
	for sc in scrolls:
		for ch in (sc as ScrollContainer).get_children():
			bad += _drag_swallowers(ch)
			btns.append_array(_buttons_under(ch))
	_check("end_screen: no drag-swallowers outside buttons (got %d)" % bad, bad == 0)
	_check("end_screen: keeps its 2 buttons", btns.size() == 2)
	_check("end_screen: buttons stay STOP (tappable)",
		btns.all(func(b: Button) -> bool: return b.mouse_filter == Control.MOUSE_FILTER_STOP))
	es.queue_free()


func _test_trader_panel() -> void:
	var p := TraderPanel.new()
	root.add_child(p)
	p.setup(_gs)
	await process_frame
	var sc := p.get("_scroll") as ScrollContainer
	_check("trader: has a ScrollContainer", sc != null)
	if sc == null:
		p.queue_free()
		return
	var bad := 0
	var btns: Array = []
	for ch in sc.get_children():
		bad += _drag_swallowers(ch)
		btns.append_array(_buttons_under(ch))
	_check("trader: no drag-swallowers outside buttons (got %d)" % bad, bad == 0)
	_check("trader: deal/deposit/back buttons present", btns.size() >= 3)
	_check("trader: buttons stay STOP (tappable)",
		btns.all(func(b: Button) -> bool: return b.mouse_filter == Control.MOUSE_FILTER_STOP))
	p.queue_free()


func _make_unit(uid: int) -> Dictionary:
	return {
		"id": uid, "alive": true, "job": "worker", "faction": "gnomes",
		"gender": "f", "name": "Testy", "hp": 80.0, "max_hp": 100.0,
		"town_id": -1, "mind": {"name": "Testy", "critical_urge": ""},
		"mind_state": "",
		"urges": {"hunger": 60.0, "energy": 50.0, "hygiene": 50.0,
			"social": 50.0, "mood": 50.0, "bladder": 50.0},
	}


func _test_unit_info() -> void:
	var p := UnitInfoPanel.new()
	root.add_child(p)
	p._build()
	p.show_unit(_make_unit(7))
	await process_frame
	var scrolls := _scrolls_under(p)
	_check("unit_info: has a ScrollContainer", not scrolls.is_empty())
	var bad := 0
	for sc in scrolls:
		for ch in (sc as ScrollContainer).get_children():
			bad += _drag_swallowers(ch)
	_check("unit_info: no drag-swallowers in scroll content (got %d)" % bad, bad == 0)
	p.queue_free()


func _test_world_setup() -> void:
	var ws := WorldSetupScreen.new()
	root.add_child(ws)
	await process_frame
	await process_frame
	var scrolls := _scrolls_under(ws)
	_check("world_setup: has a ScrollContainer", not scrolls.is_empty())
	# The carousel views are intentional STOP controls (direction-locked
	# drag input; vertical drags bubble to the ScrollContainer).
	var skip: Array = []
	for key in ["_type_car", "_size_car"]:
		var car: Dictionary = ws.get(key)
		if not car.is_empty() and car.has("view"):
			skip.append(car["view"])
	var bad := 0
	var btns: Array = []
	for sc in scrolls:
		for ch in (sc as ScrollContainer).get_children():
			bad += _drag_swallowers(ch, skip)
			btns.append_array(_buttons_under(ch, skip))
	_check("world_setup: no drag-swallowers outside buttons/carousels (got %d)" % bad, bad == 0)
	_check("world_setup: option cards + action buttons present", btns.size() >= 4)
	_check("world_setup: buttons stay STOP (tappable)",
		btns.all(func(b: Button) -> bool: return b.mouse_filter == Control.MOUSE_FILTER_STOP))
	ws.queue_free()


func _test_main_menu_title() -> void:
	var menu := MainMenu.new()
	root.add_child(menu)
	await process_frame
	await process_frame
	await process_frame
	_check("main_menu: boots to title screen", menu.get("_screen") == "title")
	var vbox := menu.get("_refit_vbox") as Control
	_check("main_menu: title content column exists", vbox != null)
	if vbox == null:
		menu.queue_free()
		return
	var bad := _drag_swallowers(vbox)
	_check("main_menu: title screen has no drag-swallowers outside buttons (got %d)" % bad, bad == 0)
	var btns := _buttons_under(vbox)
	_check("main_menu: title buttons present", btns.size() >= 3)
	_check("main_menu: buttons stay STOP (tappable)",
		btns.all(func(b: Button) -> bool: return b.mouse_filter == Control.MOUSE_FILTER_STOP))
	menu.queue_free()


func _test_adventure_quest_panel() -> void:
	var adv := SimAdventure.new(_gs)
	var ok: bool = adv.start("gnomes", "TestHero", "soldier", Vector2(4096, 4096))
	_check("adventure: hero starts", ok)
	var hud := AdventureHUD.new()
	root.add_child(hud)
	hud.setup(adv, _gs)
	var panel := hud.get("_panel") as Control
	_check("adventure: quest panel exists", panel != null)
	if panel == null:
		hud.queue_free()
		return
	panel.visible = true
	# _process throttles rebuilds on a 0.25s accumulator — rebuild directly
	# for a deterministic headless fill.
	hud._rebuild_panel()
	await process_frame
	var box := hud.get("_panel_box") as Control
	_check("adventure: quest panel content exists", box != null)
	if box == null:
		hud.queue_free()
		return
	var bad := _drag_swallowers(box)
	_check("adventure: quest panel has no drag-swallowers outside buttons (got %d)" % bad, bad == 0)
	var btns := _buttons_under(box)
	_check("adventure: Equip/Buy buttons present", btns.size() >= 1)
	_check("adventure: buttons stay STOP (tappable)",
		btns.all(func(b: Button) -> bool: return b.mouse_filter == Control.MOUSE_FILTER_STOP))
	hud.queue_free()
