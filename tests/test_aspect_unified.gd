extends SceneTree
## Cursing Gnomes — unified aspect/orientation detection tests.
##
## Jeremy 2026-10-08 (community idea, "16:9 aspect ratio and landscape UI
## compatibility"): the main menu and the in-game HUD used DIFFERENT
## orientation buckets (menu: landscape at 1.0x; HUD: landscape at 1.2x)
## and both keyed touch detection off DisplayServer.is_touchscreen_available()
## alone, which misreports on the Godot web export (iPhone Safari) — a phone
## could get the DESKTOP chrome in every orientation.
##
## Fix: Hud.touchscreen_available() (has_feature(FEATURE_TOUCHSCREEN) OR
## is_touchscreen_available()) is the single touch signal, and
## MainMenu._detect_orientation() delegates its bucket to
## Hud.layout_mode_for(). These tests pin the unified contract across
## 16:9 / 19.5:9 / 21:9 / 4:3 / square x touch on/off.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_aspect_unified.gd
##
## Exit code 0 = all passed, 1 = any failure.


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
	print("=== Cursing Gnomes unified aspect/orientation tests ===")
	_run.call_deferred()


func _menu_mode(vp: Vector2, touchscreen: bool) -> MainMenu:
	var m := MainMenu.new()
	m._detect_orientation(vp, touchscreen)
	return m


func _run() -> void:
	_test_touch_helper()
	_test_menu_hud_agreement()
	_test_pinned_buckets()
	_test_menu_side_effects()
	_test_headless_default_preserved()
	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _test_touch_helper() -> void:
	var t: bool = Hud.touchscreen_available()
	_check("touchscreen_available returns bool", t == true or t == false)
	# The unified signal is a superset of the old one: every platform where
	# is_touchscreen_available() was right is still right.
	if DisplayServer.is_touchscreen_available():
		_check("old signal true => unified signal true", t)
	# FEATURE_TOUCHSCREEN is a real DisplayServer feature id (no crash).
	var feat: bool = DisplayServer.has_feature(DisplayServer.FEATURE_TOUCHSCREEN)
	_check("has_feature(FEATURE_TOUCHSCREEN) returns bool", feat == true or feat == false)


func _test_menu_hud_agreement() -> void:
	# 16:9, 21:9, 19.5:9 phone, phone portrait, 4:3, square x touch on/off.
	var viewports: Array[Vector2] = [
		Vector2(1920, 1080), Vector2(1280, 720), Vector2(1366, 768),
		Vector2(2560, 1080), Vector2(3840, 2160),
		Vector2(844, 390), Vector2(390, 844), Vector2(1170, 2532),
		Vector2(1024, 768), Vector2(1600, 1200), Vector2(1280, 960),
		Vector2(1000, 1000), Vector2(800, 800),
	]
	for vp in viewports:
		for touch in [true, false]:
			var m := _menu_mode(vp, touch)
			var hud_mode: String = Hud.layout_mode_for(vp, touch)
			_check("menu==hud %s touch=%s (%s)" % [str(vp), str(touch), hud_mode],
				m._orientation == hud_mode)
			m.free()


func _test_pinned_buckets() -> void:
	# Explicit buckets Jeremy cares about (touch phone + desktop 16:9/4:3).
	_check("16:9 no-touch: desktop", Hud.layout_mode_for(Vector2(1920, 1080), false) == "desktop")
	_check("16:9 touch: landscape", Hud.layout_mode_for(Vector2(1920, 1080), true) == "landscape")
	_check("21:9 touch: landscape", Hud.layout_mode_for(Vector2(2560, 1080), true) == "landscape")
	_check("19.5:9 phone landscape: landscape",
		Hud.layout_mode_for(Vector2(844, 390), true) == "landscape")
	_check("phone portrait: portrait",
		Hud.layout_mode_for(Vector2(390, 844), true) == "portrait")
	_check("4:3 desktop: desktop", Hud.layout_mode_for(Vector2(1024, 768), false) == "desktop")
	_check("4:3 touch: landscape", Hud.layout_mode_for(Vector2(1600, 1200), true) == "landscape")
	# Unification change: near-square used to be "landscape" in the menu
	# (1.0x line) but "portrait" in the HUD. Both now say portrait.
	_check("square touch: portrait", Hud.layout_mode_for(Vector2(1000, 1000), true) == "portrait")
	var m := _menu_mode(Vector2(1000, 1000), true)
	_check("square touch menu: portrait", m._orientation == "portrait")
	m.free()
	# Small window with no touch is NOT desktop (needs >= 1024x600).
	_check("small no-touch: portrait", Hud.layout_mode_for(Vector2(390, 844), false) == "portrait")


func _test_menu_side_effects() -> void:
	# _is_desktop tracks the bucket; _aspect stays orthogonal (16:9 vs 4:3).
	var m := _menu_mode(Vector2(1920, 1080), false)
	_check("1080p no-touch: is_desktop", m._is_desktop)
	_check("1080p no-touch: orientation desktop", m._orientation == "desktop")
	_check("1080p: aspect widescreen", m._aspect == "widescreen")
	m.free()
	m = _menu_mode(Vector2(1024, 768), false)
	_check("4:3 no-touch: is_desktop", m._is_desktop)
	_check("4:3: aspect standard", m._aspect == "standard")
	m.free()
	m = _menu_mode(Vector2(844, 390), true)
	_check("phone landscape: not desktop", not m._is_desktop)
	_check("phone landscape 19.5:9: aspect widescreen", m._aspect == "widescreen")
	m.free()


func _test_headless_default_preserved() -> void:
	# Headless Godot reports a touchscreen as available, so the default
	# parameter hides the desktop branch (pinned in test_aspect_layouts.gd).
	# The unified default must keep that quirk: 844x390 with no explicit
	# touch arg is still "landscape", not "desktop".
	var m := MainMenu.new()
	_check("headless default: 844x390 landscape", m._detect_orientation(Vector2(844, 390)) == "landscape")
	m.free()
