extends SceneTree
## Cursing Gnomes — realm drawer + system menu scroll tests (Jeremy 2026-10-11).
##
## Jeremy's standing complaint: "a lot of menus don't have proper scroll."
## The menu-scroll-audit contract (test_menu_scroll_audit.gd): every Control
## inside a ScrollContainer is MOUSE_FILTER_IGNORE except Button subtrees,
## which keep STOP so they stay tappable — because a default-STOP
## Label/Container swallows the touch drag before it reaches the
## ScrollContainer, so scrolling dies depending on where the drag starts.
##
## Gap found 2026-10-11: the realm drawer (_drawer ScrollContainer) was never
## covered by the 2026-10-10 HUD audit — its section headers, REALM title
## row, live pop/peace/weather labels, and resource icon rows were all
## default-STOP, so drags starting on them died instead of scrolling the
## drawer. Same for the 12px gaps in the system-menu button list.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_drawer_scroll.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _gs: GameState = null
var _hud: Hud = null


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	print("=== Cursing Gnomes drawer scroll tests ===")
	_run.call_deferred()


## Count STOP controls that are NOT inside a Button subtree.
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


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	gs.player_faction = "gnomes"
	return gs


func _run() -> void:
	_gs = _new_game()
	_hud = Hud.new()
	root.add_child(_hud)
	_hud.setup(_gs, Selection.new())
	await process_frame
	await process_frame
	# Each test suspends on awaits, so await them in order — otherwise
	# _run would reach quit() before the deferred bodies resume.
	await _test_realm_drawer()
	await _test_drawer_rebuild_keeps_contract()
	await _test_system_menu()
	await _test_res_icon_row()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	_hud.queue_free()
	_gs.queue_free()
	quit(1 if _failed > 0 else 0)


func _drawer_scroll() -> ScrollContainer:
	var drawer := _hud.get("_drawer") as Control
	_check("drawer: realm drawer exists", drawer != null)
	if drawer == null:
		return null
	var scrolls := _scrolls_under(drawer)
	_check("drawer: has a ScrollContainer", not scrolls.is_empty())
	if scrolls.is_empty():
		return null
	return scrolls[0] as ScrollContainer


func _test_realm_drawer() -> void:
	var sc := _drawer_scroll()
	if sc == null:
		return
	var bad := 0
	for ch in sc.get_children():
		bad += _drag_swallowers(ch)
	_check("drawer: no drag-swallowers outside buttons (got %d)" % bad, bad == 0)
	var btns := _buttons_under(sc)
	_check("drawer: drawer buttons present", btns.size() >= 10)
	_check("drawer: buttons stay STOP (tappable)",
		btns.all(func(b: Button) -> bool: return b.mouse_filter == Control.MOUSE_FILTER_STOP))


func _test_drawer_rebuild_keeps_contract() -> void:
	# _rebuild_drawer runs again on every drawer refresh — the contract
	# must survive a rebuild, not just the first construction.
	_hud._rebuild_drawer()
	await process_frame
	var sc := _drawer_scroll()
	if sc == null:
		return
	var bad := 0
	for ch in sc.get_children():
		bad += _drag_swallowers(ch)
	_check("drawer: no drag-swallowers after rebuild (got %d)" % bad, bad == 0)


func _test_system_menu() -> void:
	var menu := _hud.get("_sys_menu") as Control
	_check("sysmenu: system menu exists", menu != null)
	if menu == null:
		return
	var scrolls := _scrolls_under(menu)
	_check("sysmenu: has a ScrollContainer", not scrolls.is_empty())
	if scrolls.is_empty():
		return
	var sc := scrolls[0] as ScrollContainer
	var bad := 0
	for ch in sc.get_children():
		bad += _drag_swallowers(ch)
	_check("sysmenu: no drag-swallowers outside buttons (got %d)" % bad, bad == 0)
	var btns := _buttons_under(sc)
	_check("sysmenu: 10 menu buttons present", btns.size() == 10)
	_check("sysmenu: buttons stay STOP (tappable)",
		btns.all(func(b: Button) -> bool: return b.mouse_filter == Control.MOUSE_FILTER_STOP))


func _test_res_icon_row() -> void:
	# _res_icon_row is shared by the drawer and the side-panel resources
	# content — the unit itself must be drag-transparent.
	var parts: Array = _hud._res_icon_row("wood", 24)
	_check("resrow: returns [row, label]", parts.size() == 2)
	var row := parts[0] as Control
	var l := parts[1] as Control
	_check("resrow: row is IGNORE", row.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("resrow: label is IGNORE", l.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var icon := row.get_child(0) as Control
	_check("resrow: icon is IGNORE", icon.mouse_filter == Control.MOUSE_FILTER_IGNORE)
