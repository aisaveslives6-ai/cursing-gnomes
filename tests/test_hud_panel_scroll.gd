extends SceneTree
## Cursing Gnomes — HUD panel scroll tests (Jeremy 2026-10-10, POLISH MODE).
##
## Menu scroll audit finding: the HUD's side dropdown panel (Resources /
## Government tabs) and the build-menu grid had NO ScrollContainer. Long
## content — Resources tab with the expanded ArmyTab, or the Military tab's
## 17 buildings — grew past the screen edge with no way to reach it.
## Jeremy: "a lot of menus don't have proper scroll."
##
## Fix: _side_vbox and _build_grid each live inside a ScrollContainer whose
## height is capped to the safe viewport by _cap_side_panel() /
## _cap_build_panel() (called on tab open, content toggle, and rotation).
## Short content keeps the old shrink-to-fit height.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hud_panel_scroll.gd
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
	print("=== Cursing Gnomes HUD panel scroll tests ===")
	_run.call_deferred()


func _is_descendant_of(ancestor: Node, n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false


func _run() -> void:
	await process_frame
	await process_frame
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	gs.player_faction = "gnomes"

	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	await process_frame
	await process_frame

	_test_side_panel_wiring(hud)
	_test_build_grid_wiring(hud)
	_test_build_tab_row_scroll(hud)
	await _test_side_panel_cap(hud)
	await _test_build_grid_cap(hud)

	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


## The side panel's content VBox must live inside a ScrollContainer with
## horizontal scrolling disabled (vertical-only touch scroll).
func _test_side_panel_wiring(hud: Hud) -> void:
	var sc: ScrollContainer = hud._side_scroll
	_check("side panel has a ScrollContainer", sc != null)
	if sc == null:
		return
	_check("side scroll horizontal disabled",
		sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	_check("side vbox is the scroll's child",
		hud._side_vbox.get_parent() == sc)
	_check("side scroll lives under the side panel",
		_is_descendant_of(hud._side_panel, sc))
	# Dragging anywhere on the panel must reach the scroll, so tap actions
	# never fire accidentally mid-scroll: the vbox itself must not eat
	# the drag before the ScrollContainer sees it.
	_check("side vbox does not block mouse (scroll owns the gesture)",
		hud._side_vbox.mouse_filter != Control.MOUSE_FILTER_STOP)


## The build grid must live inside a ScrollContainer with horizontal
## scrolling disabled.
func _test_build_grid_wiring(hud: Hud) -> void:
	var sc: ScrollContainer = hud._build_scroll
	_check("build grid has a ScrollContainer", sc != null)
	if sc == null:
		return
	_check("build scroll horizontal disabled",
		sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	_check("build grid is the scroll's child",
		hud._build_grid.get_parent() == sc)


## Tall side-panel content gets capped to the on-screen safe height via the
## automatic deferred recap; short content keeps shrink-to-fit (uncapped).
func _test_side_panel_cap(hud: Hud) -> void:
	if hud._side_scroll == null:
		_check("side cap skipped (no scroll)", false)
		return
	hud._on_side_tab("resources")
	# Simulate the tallest real content: expanded ArmyTab + zone host.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 4000)
	hud._side_vbox.add_child(spacer)
	# The recap is deferred two frames (container minimum sizes refresh on
	# the layout pass); wait for it to land on its own.
	await process_frame
	await process_frame
	await process_frame
	var cap: float = hud._side_scroll.custom_minimum_size.y
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	_check("tall side content is capped (cap < content need)",
		cap < 4000.0)
	_check("side cap is positive (panel still visible)", cap > 0.0)
	_check("side cap fits above the bottom chrome", cap < vp.y)
	spacer.queue_free()
	# Short content: Government tab must NOT be capped (shrink-to-fit).
	hud._on_side_tab("government")
	await process_frame
	await process_frame
	await process_frame
	var need: float = hud._side_vbox.get_combined_minimum_size().y
	var cap2: float = hud._side_scroll.custom_minimum_size.y
	_check("short side content keeps shrink-to-fit (uncapped)",
		absf(cap2 - need) < 2.0)


## Build tab row (5 tabs x 100px = 516px) is wider than a portrait phone —
## the Military tab used to clip with no way to tap it. The row must sit
## in a horizontal-only ScrollContainer; the tab buttons stay STOP.
func _test_build_tab_row_scroll(hud: Hud) -> void:
	var row: HBoxContainer = hud._build_tab_row
	_check("build tab row exists", row != null)
	if row == null:
		return
	var sc := row.get_parent()
	_check("build tab row wrapped in a scroll", sc is ScrollContainer)
	if not (sc is ScrollContainer):
		return
	_check("tab row scroll is horizontal-only",
		(sc as ScrollContainer).horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
		and (sc as ScrollContainer).vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	var tabs := 0
	for c in row.get_children():
		if c is Button:
			tabs += 1
			_check("tab button stays tap-able (STOP)",
				(c as Button).mouse_filter == Control.MOUSE_FILTER_STOP)
	_check("all 5 build tabs present", tabs == 5)
	var need: float = row.get_combined_minimum_size().x
	_check("tab row wider than portrait phone (%.0f > 390)" % need,
		need > 390.0)


## Military tab (17 buildings) must engage scrolling via the automatic
## deferred recap; a short tab (roads) must not be capped.
func _test_build_grid_cap(hud: Hud) -> void:
	if hud._build_scroll == null:
		_check("build cap skipped (no scroll)", false)
		return
	hud._on_build_tab("military")
	await process_frame
	await process_frame
	await process_frame
	var need: float = hud._build_grid.get_combined_minimum_size().y
	var cap: float = hud._build_scroll.custom_minimum_size.y
	_check("military grid content is tall", need > 0.0)
	_check("military grid engages scroll (cap < need)", cap < need)
	_check("military cap is positive", cap > 0.0)
	# Short tab: roads list must keep its natural height.
	hud._on_build_tab("roads")
	await process_frame
	await process_frame
	await process_frame
	var need2: float = hud._build_grid.get_combined_minimum_size().y
	var cap2: float = hud._build_scroll.custom_minimum_size.y
	_check("roads grid content exists", need2 > 0.0)
	_check("short build list keeps shrink-to-fit (uncapped)",
		absf(cap2 - need2) < 2.0)
