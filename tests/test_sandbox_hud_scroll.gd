extends SceneTree
## Cursing Gnomes — sandbox director HUD scroll tests
## (Jeremy 2026-10-10, POLISH MODE menu-scroll audit).
##
## Audit finding (horizontal): the sandbox director panel's five wide
## button rows (DIRECTOR title+chips, faction focus, actions, weather/time,
## disasters) hold 700–1200px of content in plain HBoxContainers — far
## wider than a portrait phone, so the right side (disasters, weather
## buttons, pause/MENU) clipped off-screen with no way to reach it.
## Jeremy: "a lot of menus don't have proper scroll."
##
## Fix: each wide row lives in a horizontal-only ScrollContainer
## (Hud._sb_hscroll): taps still fire the buttons, horizontal drags
## scroll the row. The narrow tools row ("TOOLS" + 2 buttons, ~380px)
## stays unwrapped by its own row scroll.
##
## Audit finding (vertical, remnants pass): the 7 stacked rows + log had
## no vertical cap — on small landscape phones the panel ran off the
## bottom with unreachable content.
##
## Fix: the whole row stack lives in a vertical-only ScrollContainer
## (Hud._sb_vscroll) capped by _cap_sb_panel() to
## viewport.y − top safe inset − breathing room; _recap_sb_panel() re-applies
## the cap on content changes, and _on_viewport_resized() re-runs all panel
## recaps so rotation can't leave a stale cap.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_sandbox_hud_scroll.gd
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
	print("=== Cursing Gnomes sandbox HUD scroll tests ===")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.player_faction = "gnomes"
	gs.set_meta("army", SimArmy.new(gs))
	var sb := SimSandbox.new(gs)

	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	hud.enter_sandbox_mode(sb)
	await process_frame
	await process_frame

	_check("sandbox panel exists", hud._sb_panel != null)
	if hud._sb_panel != null:
		_test_wide_rows_wrapped(hud)
		_test_buttons_reachable(hud)
		_test_faction_rebuild(hud, sb)
		_test_narrow_row_not_wrapped(hud)
		# The vertical recap fires 2 frames after _build_sandbox_hud;
		# give it its frames before asserting the cap.
		await process_frame
		await process_frame
		_test_vertical_cap(hud)
		_test_resize_recap(hud)

	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


## Collect every ScrollContainer under the sandbox panel.
func _scrolls_under(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is ScrollContainer:
			out.append(cur as ScrollContainer)
		for c in cur.get_children():
			stack.append(c)
	return out


func _find_button(n: Node, text: String) -> Button:
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Button and (cur as Button).text == text:
			return cur as Button
		for c in cur.get_children():
			stack.append(c)
	return null


func _enclosing_scroll(c: Control) -> ScrollContainer:
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			return n as ScrollContainer
		n = n.get_parent()
	return null


## Five wide rows sit in horizontal-only scrolls; the row stack itself
## sits in one vertical-only outer scroll. Six scrolls total.
func _test_wide_rows_wrapped(hud: Hud) -> void:
	var scrolls: Array = _scrolls_under(hud._sb_panel)
	_check("six scrolls under panel (5 row + 1 vertical outer)",
		scrolls.size() == 6)
	var h_count := 0
	var v_count := 0
	for sc in scrolls:
		if sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO \
				and sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			h_count += 1
			var child: Node = sc.get_child(0)
			_check("row scroll child is the row HBox",
				child is HBoxContainer)
		elif sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED \
				and sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO:
			v_count += 1
		else:
			_check("scroll has a sane axis mode: " + str(sc.get_path()), false)
	_check("five horizontal-only row scrolls", h_count == 5)
	_check("one vertical-only outer scroll", v_count == 1)


## The doom row is genuinely wider than a portrait phone (~1230px min)
## — proving the scroll is needed — and its buttons still tap (STOP).
func _test_buttons_reachable(hud: Hud) -> void:
	var volcano := _find_button(hud._sb_panel, "Volcano")
	_check("disaster button exists under panel", volcano != null)
	if volcano == null:
		return
	var sc := _enclosing_scroll(volcano)
	_check("disaster button sits inside a horizontal scroll", sc != null)
	if sc != null:
		_check("disaster button's nearest scroll is horizontal-only",
			sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
			and sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
		var need: float = (sc.get_child(0) as Control).get_combined_minimum_size().x
		_check("doom row content wider than phone portrait (%.0f > 1000)" % need,
			need > 1000.0)
	_check("disaster button still tap-able (STOP)",
		volcano.mouse_filter == Control.MOUSE_FILTER_STOP)
	var pause_b := _find_button(hud._sb_panel, "II")
	_check("pause button present and wrapped", pause_b != null
		and _enclosing_scroll(pause_b) != null)


## The faction row is rebuilt by clearing its children on refresh —
## that must still work with the scroll as its parent.
func _test_faction_rebuild(hud: Hud, sb: SimSandbox) -> void:
	var row: HBoxContainer = hud._sb_faction_row
	_check("faction row keeps its member ref", row != null)
	if row == null:
		return
	_check("faction row parent is now a scroll",
		row.get_parent() is ScrollContainer)
	hud._refresh_sandbox(true)
	# queue_free() is deferred — the old buttons clear at end of frame.
	await process_frame
	await process_frame
	_check("faction buttons rebuilt under scroll (2 factions)",
		row.get_child_count() == 2)
	for c in row.get_children():
		_check("rebuilt faction button still tap-able (STOP)",
			(c as Button).mouse_filter == Control.MOUSE_FILTER_STOP)


## The narrow tools row (~380px: TOOLS + Expand + Clear fires) must NOT
## get its own horizontal row scroll — no pointless scroll chrome on a
## row that fits. It does sit inside the vertical outer scroll, which is
## the correct enclosing scroll for it.
func _test_narrow_row_not_wrapped(hud: Hud) -> void:
	var expand := _find_button(hud._sb_panel, "Expand")
	_check("tools button exists", expand != null)
	if expand == null:
		return
	var sc := _enclosing_scroll(expand)
	_check("tools row's nearest scroll is the vertical outer scroll",
		sc == hud._sb_vscroll)
	_check("no horizontal scroll wraps the tools row",
		sc == null
		or sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)


## The vertical outer scroll: member refs, axis modes, and the height cap
## (min of content need and the viewport-derived max).
func _test_vertical_cap(hud: Hud) -> void:
	_check("sb vscroll member exists", hud._sb_vscroll != null)
	_check("sb vbox member exists", hud._sb_vbox != null)
	if hud._sb_vscroll == null or hud._sb_vbox == null:
		return
	_check("vscroll is vertical-only",
		hud._sb_vscroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		and hud._sb_vscroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO)
	_check("vbox is the vscroll's child",
		(hud._sb_vbox as Node).get_parent() == hud._sb_vscroll)
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	var insets: Vector4 = hud._safe_insets()
	var max_h: float = maxf(vp.y - insets.x - hud._s(8.0) - hud._s(96.0),
		hud._s(200.0))
	var need: float = (hud._sb_vbox as Control).get_combined_minimum_size().y
	var expected: float = minf(need, max_h)
	var cap: float = hud._sb_vscroll.custom_minimum_size.y
	_check("cap applied (%.0f > 0)" % cap, cap > 0.0)
	_check("cap never taller than the viewport (%.0f <= %.0f)" % [cap, vp.y],
		cap <= vp.y)
	_check("cap == min(need %.0f, max_h %.0f)" % [need, max_h],
		is_equal_approx(cap, expected))


## Rotation/resize must re-run the deferred recaps without crashing, and
## the caps must settle back on the same formula afterwards.
func _test_resize_recap(hud: Hud) -> void:
	hud._on_viewport_resized()
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	_check("panel still valid after resize recap",
		is_instance_valid(hud._sb_panel))
	if hud._sb_vscroll == null or hud._sb_vbox == null:
		_check("vscroll/vbox survive resize", false)
		return
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	var insets: Vector4 = hud._safe_insets()
	var max_h: float = maxf(vp.y - insets.x - hud._s(8.0) - hud._s(96.0),
		hud._s(200.0))
	var need: float = (hud._sb_vbox as Control).get_combined_minimum_size().y
	var expected: float = minf(need, max_h)
	_check("cap re-applied after resize",
		is_equal_approx(hud._sb_vscroll.custom_minimum_size.y, expected))
