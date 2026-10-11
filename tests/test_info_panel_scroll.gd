extends SceneTree
## Cursing Gnomes — selection info panel scroll tests (Jeremy 2026-10-10,
## POLISH MODE).
##
## Menu scroll audit finding: the HUD's top-left selection info panel had a
## capped width but UNBOUNDED height. Monastery / dark-crystal lore runs
## hundreds of words (name + god + lore + blessing/power + perk/power desc
## + corruption + owner + contested/progress), which grew the panel past
## the bottom of the screen with no way to scroll — and could push the
## nuke ARM/DISARM button out of reach on a landscape iPhone.
## Jeremy: "a lot of menus don't have proper scroll."
##
## Fix: the info label lives in a ScrollContainer (_info_scroll) whose
## height is capped to the safe viewport by _cap_info_panel() (called on
## selection text change via _recap_info_panel() and on rotation/refit).
## The nuke ARM/DISARM button stays PINNED below the scroll so it is always
## reachable; short content keeps the old shrink-to-fit height. The label
## and its vbox are display-only (MOUSE_FILTER_IGNORE) so drags reach the
## scroll and scrolling never fires a tap action; the button stays STOP.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_info_panel_scroll.gd
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
	print("=== Cursing Gnomes info panel scroll tests ===")
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

	_test_info_panel_wiring(hud)
	await _test_info_panel_tall_cap(hud)
	await _test_info_panel_short_uncapped(hud)
	await _test_info_panel_button_pinned(hud)

	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


## The info label must live inside a vertical-only ScrollContainer; the
## label (display-only) must not eat drags, and the nuke button must stay
## outside the scroll so it can never be pushed off-screen.
func _test_info_panel_wiring(hud: Hud) -> void:
	var sc: ScrollContainer = hud._info_scroll
	_check("info panel has a ScrollContainer", sc != null)
	if sc == null:
		return
	_check("info scroll horizontal disabled",
		sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	_check("info label lives inside the scroll",
		_is_descendant_of(sc, hud._info_label))
	_check("inner vbox is the scroll's child",
		hud._info_inner_vbox.get_parent() == sc)
	_check("inner vbox is inside the info panel",
		_is_descendant_of(hud._info_panel, sc))
	# The nuke ARM/DISARM button must be PINNED below the scroll (still in
	# the panel, never inside the scroll) so long lore can never push it
	# out of reach.
	_check("nuke button is inside the info panel",
		_is_descendant_of(hud._info_panel, hud._nuke_arm_btn))
	_check("nuke button is NOT inside the scroll (pinned below it)",
		not _is_descendant_of(sc, hud._nuke_arm_btn))
	# Dragging anywhere on the lore must reach the scroll, so tap actions
	# never fire accidentally mid-scroll.
	_check("info label does not block mouse (scroll owns the gesture)",
		hud._info_label.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("inner vbox does not block mouse (scroll owns the gesture)",
		hud._info_inner_vbox.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("nuke button stays tappable",
		hud._nuke_arm_btn.mouse_filter == Control.MOUSE_FILTER_STOP)


## Monastery-scale lore must be capped to the on-screen safe height via the
## automatic deferred recap; the capped panel must fit inside the viewport.
func _test_info_panel_tall_cap(hud: Hud) -> void:
	if hud._info_scroll == null:
		_check("info cap skipped (no scroll)", false)
		return
	# Headless: the panel stays hidden (no live selection), so container
	# layout never assigns the label a real width — without one, autowrap
	# measures at 1px and the "need" is garbage. Pin a production-realistic
	# width directly; hidden subtrees get no container layout, so it sticks.
	hud._info_label.size = Vector2(280, 0)
	# Simulate the tallest real content: crystal-style multi-section lore.
	var lines: Array[String] = []
	for i: int in range(300):
		lines.append("Lore line %d: the rogue god's domain stretches wide." % i)
	hud._info_label.text = "\n".join(lines)
	# The recap is deferred two frames (container minimum sizes refresh on
	# the layout pass); wait for it to land on its own.
	hud._recap_info_panel()
	await process_frame
	await process_frame
	await process_frame
	var need: float = hud._info_inner_vbox.get_combined_minimum_size().y
	var cap: float = hud._info_scroll.custom_minimum_size.y
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	_check("tall info content needs more than a screen", need > vp.y)
	_check("tall info content is capped (cap < content need)", cap < need)
	_check("info cap is positive (panel still visible)", cap > 0.0)
	var panel_min: float = hud._info_panel.get_combined_minimum_size().y
	_check("capped panel fits inside the viewport",
		hud._info_panel.offset_top + panel_min <= vp.y + 2.0)


## Short selection text (a building name + HP) must keep shrink-to-fit.
func _test_info_panel_short_uncapped(hud: Hud) -> void:
	if hud._info_scroll == null:
		_check("info uncapped skipped (no scroll)", false)
		return
	hud._info_label.size = Vector2(280, 0)
	hud._info_label.text = "Hut (Gnomes)  HP 120/120"
	hud._recap_info_panel()
	await process_frame
	await process_frame
	await process_frame
	var need: float = hud._info_inner_vbox.get_combined_minimum_size().y
	var cap: float = hud._info_scroll.custom_minimum_size.y
	_check("short info content exists", need > 0.0)
	_check("short info content keeps shrink-to-fit (uncapped)",
		absf(cap - need) < 2.0)


## With tall lore AND the nuke button shown, the button must remain pinned
## below the scroll (reachable), and the whole panel on-screen.
func _test_info_panel_button_pinned(hud: Hud) -> void:
	if hud._info_scroll == null:
		_check("button pinned skipped (no scroll)", false)
		return
	hud._info_label.size = Vector2(280, 0)
	var lines: Array[String] = []
	for i: int in range(300):
		lines.append("Lore line %d: the rogue god's domain stretches wide." % i)
	hud._info_label.text = "\n".join(lines)
	hud._nuke_arm_btn.text = "ARM NUKE"
	hud._nuke_arm_btn.visible = true
	hud._recap_info_panel()
	await process_frame
	await process_frame
	await process_frame
	var vp: Vector2 = hud.get_viewport().get_visible_rect().size
	_check("button still outside the scroll with tall lore",
		not _is_descendant_of(hud._info_scroll, hud._nuke_arm_btn))
	_check("button still inside the panel with tall lore",
		_is_descendant_of(hud._info_panel, hud._nuke_arm_btn))
	var panel_min: float = hud._info_panel.get_combined_minimum_size().y
	_check("panel with button fits inside the viewport",
		hud._info_panel.offset_top + panel_min <= vp.y + 2.0)
	hud._nuke_arm_btn.visible = false
