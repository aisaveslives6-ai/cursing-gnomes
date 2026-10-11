extends SceneTree
## Regression test: the Captain Funky Pants trade panel must scroll when its
## content overflows the viewport.
## Jeremy 2026-10-10 (menu-scroll audit): the deal/deposit list is ~700px
## tall — on landscape phones it overflowed the viewport with no way to
## reach the lower buttons. The content now lives in a ScrollContainer
## capped to the safe-area viewport height; drag scrolls, taps still fire.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_trader_scroll.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed := 0
var _failed := 0
var _failures: Array[String] = []
var _gs: GameState = null


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		push_error("FAIL: " + name)


func _init() -> void:
	_gs = GameState.new()
	root.add_child(_gs)
	_gs.setup(["humans", "ogres", "elves"])
	_run.call_deferred()


func _scroll_of(p: TraderPanel) -> ScrollContainer:
	return p.get("_scroll") as ScrollContainer


func _run() -> void:
	# Let the tree settle so get_viewport() works inside TraderPanel._refit
	# (nodes added during _init are not inside the tree yet).
	await process_frame
	await process_frame
	print("=== Cursing Gnomes trader scroll tests ===")
	_test_scroll_container_present()
	_test_horizontal_scroll_disabled()
	_test_height_capped_to_viewport()
	_test_content_taller_than_cap_scrolls()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	_gs.queue_free()
	quit(1 if _failed > 0 else 0)


func _make_panel() -> TraderPanel:
	var p := TraderPanel.new()
	root.add_child(p)
	p.setup(_gs)
	return p


func _test_scroll_container_present() -> void:
	var p := _make_panel()
	var sc := _scroll_of(p)
	_check(sc != null, "panel builds a ScrollContainer")
	if sc != null:
		_check(sc.get_child_count() == 1 and sc.get_child(0) is VBoxContainer,
			"scroll child is the content VBox")
		var vb = p.get("_vb")
		_check(vb != null and is_instance_valid(vb) and vb.get_parent() == sc,
			"content VBox is parented to the ScrollContainer")
	p.queue_free()


func _test_horizontal_scroll_disabled() -> void:
	var p := _make_panel()
	var sc := _scroll_of(p)
	_check(sc != null and sc.horizontal_scroll_mode \
		== ScrollContainer.SCROLL_MODE_DISABLED,
		"horizontal scroll stays disabled")
	p.queue_free()


func _test_height_capped_to_viewport() -> void:
	var p := _make_panel()
	var sc := _scroll_of(p)
	_check(sc != null, "cap: scroll exists")
	if sc != null:
		# Headless reports a touchscreen, so _safe_insets() uses the
		# landscape fallback (20, 60, 120, 120) on the square viewport.
		var vsz := root.get_visible_rect().size
		var cap := maxf(220.0, vsz.y - 20.0 - 60.0 - 48.0)
		_check(sc.custom_minimum_size.y <= cap + 0.5,
			"scroll height capped to viewport (%.0f <= %.0f)"
			% [sc.custom_minimum_size.y, cap])
		_check(sc.custom_minimum_size.y >= 220.0,
			"scroll keeps a usable minimum height")
	p.queue_free()


func _test_content_taller_than_cap_scrolls() -> void:
	var p := _make_panel()
	var sc := _scroll_of(p)
	var vb = p.get("_vb")
	_check(sc != null and vb != null, "overflow: scroll and content exist")
	if sc != null and vb != null:
		var need: float = (vb as VBoxContainer).get_combined_minimum_size().y
		# The 6 deal + 3 deposit buttons must need more than a landscape
		# phone's ~270px of usable height, i.e. scrolling is genuinely
		# required on small screens.
		_check(need > 270.0,
			"content genuinely overflows small screens (need %.0f)" % need)
		# And the scroll container must be shorter than the content so the
		# ScrollContainer actually has something to scroll.
		_check(sc.custom_minimum_size.y < need,
			"scroll container shorter than content (%.0f < %.0f)"
			% [sc.custom_minimum_size.y, need])
	p.queue_free()
