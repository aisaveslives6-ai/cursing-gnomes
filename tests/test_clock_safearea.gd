extends SceneTree
## Cursing Gnomes — bottom-bar clock safe-area tests (Jeremy 2026-10-04).
##
## The old top-right clock panel was removed: the clock now lives inside a
## bottom menu bar (tabs ride on top of the bar), and the FPS debug label
## sits in the top-right safe area. The bar must clear the iPhone home
## indicator via DisplayServer.get_display_safe_area().
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_clock_safearea.gd

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


## True if `node` is `ancestor` or a descendant of it.
func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var n: Node = node
	while n != null:
		if n == ancestor:
			return true
		n = n.get_parent()
	return false


func _test_bottom_bar_safe_area() -> void:
	var hud := Hud.new()
	# Headless: not in the tree, so get_viewport() is null and _safe_insets()
	# returns the conservative fallback Vector4(180, 100, 20, 20)
	# (top, bottom, left, right).
	hud._ui_scale = 2.5
	hud._build_bottom_bar()
	var insets: Vector4 = hud._safe_insets()
	_check("headless fallback insets", absf(insets.y - 100.0) < 0.01)

	# Bottom bar exists and holds the clock labels.
	_check("bottom bar built", hud._bottom_bar != null)
	_check("clock box built", hud._clock_box != null)
	_check("clock time label built", hud._clock_time_label != null)
	_check("clock date label built", hud._clock_date_label != null)
	if hud._clock_box != null and hud._bottom_bar != null:
		_check("clock box inside bottom bar",
			_is_descendant_of(hud._clock_box, hud._bottom_bar))

	# Tab strip: 5 circular bubbles (phone, resources, government,
	# diplomacy, menu). Jeremy 2026-10-04: Menu tab added; Government is
	# government-only. Jeremy 2026-10-07: Diplomacy tab added.
	_check("tab strip built", hud._side_tab_bar != null)
	_check("5 tabs built", hud._side_tabs.size() == 5)
	for tab_id in ["phone", "resources", "government", "diplomacy", "menu"]:
		_check("tab present: " + tab_id, hud._side_tabs.has(tab_id))
	if hud._side_tab_bar != null and hud._bottom_bar != null:
		# Strip added after the bar: draws on top of it.
		_check("tab strip above bar in draw order",
			hud._side_tab_bar.get_index() > hud._bottom_bar.get_index())
		# Strip itself never eats taps; the bubble buttons do.
		_check("tab strip mouse_filter IGNORE",
			hud._side_tab_bar.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	# FPS debug label exists, top-right anchored, ignores mouse.
	_check("fps label built", hud._fps_label != null)
	if hud._fps_label != null:
		_check("fps label top-right anchored",
			hud._fps_label.anchor_left == 1.0 and hud._fps_label.anchor_top == 0.0)
		_check("fps label mouse_filter IGNORE",
			hud._fps_label.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	# Dropdown panel: bottom-center anchored, grows upward.
	_check("side panel built", hud._side_panel != null)
	if hud._side_panel != null:
		_check("side panel bottom-center anchored",
			hud._side_panel.anchor_top == 1.0 and hud._side_panel.anchor_bottom == 1.0)
		_check("side panel grows upward",
			hud._side_panel.grow_vertical == Control.GROW_DIRECTION_BEGIN)

	hud.queue_free()


func _initialize() -> void:
	print("=== Bottom-bar safe-area tests ===")
	_test_bottom_bar_safe_area()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)
