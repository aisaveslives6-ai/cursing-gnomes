extends SceneTree
## Cursing Gnomes — landscape-compact HUD layout tests (launch readiness gate 4).
##
## Jeremy's order: portrait, landscape, PC 16:9 and PC 4:3 each get their own
## UI. The main menu already buckets orientation/aspect (test_aspect_layouts);
## the in-game HUD now does too via Hud.layout_mode_for / bar_h_for /
## bubble_d_for. Phone landscape (844x390) previously lost ~half its vertical
## canvas to the stacked 84px bar + 64px tab strip; landscape mode gets a
## 48px slim bar, 48px bubbles, and the tabs move to a left vertical rail.
## Desktop keeps the standard chrome in every aspect.
##
## Drop into tests/ and run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ui_landscape.gd
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
	print("=== Cursing Gnomes landscape-compact HUD tests ===")
	_run.call_deferred()


func _run() -> void:
	_test_layout_modes()
	_test_chrome_values()
	_test_landscape_saves_space()
	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _mode(vsz: Vector2, touch: bool) -> String:
	return Hud.layout_mode_for(vsz, touch)


func _test_layout_modes() -> void:
	# Desktops: touch off + big viewport -> "desktop" in both aspects.
	_check("1080p desktop", _mode(Vector2(1920, 1080), false) == "desktop")
	_check("4:3 1400x1050 desktop", _mode(Vector2(1400, 1050), false) == "desktop")
	_check("1600x1200 desktop", _mode(Vector2(1600, 1200), false) == "desktop")
	# Phone portrait (iPhone 17 390x844, touch on).
	_check("iphone portrait", _mode(Vector2(390, 844), true) == "portrait")
	# Phone landscape (iPhone 17 844x390, touch on).
	_check("iphone landscape", _mode(Vector2(844, 390), true) == "landscape")
	# Landscape needs a real ratio, not just wider: near-square stays portrait.
	_check("near-square 800x700 portrait", _mode(Vector2(800, 700), true) == "portrait")
	_check("mild wide 900x700 landscape", _mode(Vector2(900, 700), true) == "landscape")
	# Touch always forces the phone path, even on a big screen.
	_check("touch 1920x1080 landscape", _mode(Vector2(1920, 1080), true) == "landscape")
	_check("touch 1024x900 stays portrait", _mode(Vector2(1024, 900), true) == "portrait")
	# Small desktop window falls back to phone-style buckets (touch off).
	_check("tiny desktop window portrait", _mode(Vector2(600, 500), false) == "portrait")


func _test_chrome_values() -> void:
	_check("portrait bar 84", Hud.bar_h_for("portrait") == 84.0)
	_check("desktop bar 84", Hud.bar_h_for("desktop") == 84.0)
	_check("landscape bar 48", Hud.bar_h_for("landscape") == 48.0)
	_check("landscape bar slimmer", Hud.bar_h_for("landscape") < Hud.bar_h_for("portrait"))
	_check("portrait bubble 64", Hud.bubble_d_for("portrait") == 64.0)
	_check("desktop bubble 64", Hud.bubble_d_for("desktop") == 64.0)
	_check("landscape bubble 48", Hud.bubble_d_for("landscape") == 48.0)
	# Unknown mode falls back to the standard chrome, never a slim surprise.
	_check("unknown mode bar falls back", Hud.bar_h_for("bogus") == 84.0)
	_check("unknown mode bubble falls back", Hud.bubble_d_for("bogus") == 64.0)


func _test_landscape_saves_space() -> void:
	# iPhone landscape canvas units: base 1280x720, aspect expand.
	# scale = max(844/1280, 390/720) = 0.6594 -> visible (1280, 591.4).
	var canvas_h := 591.4
	var ui_scale := 2.5
	# Old stack: 84 bar + 64*0.9 strip protrusion (10% overlaps the bar).
	var old_chrome := (84.0 + 64.0 * 0.9) * ui_scale
	# New stack: 48 bar, tabs moved to the left rail (zero bottom chrome).
	var new_chrome := 48.0 * ui_scale
	_check("landscape frees vertical space", new_chrome < old_chrome)
	_check("landscape chrome under 25% of canvas", new_chrome / canvas_h < 0.25)
	# The old stack ate over half the vertical canvas in landscape.
	_check("old chrome ate over half", old_chrome / canvas_h > 0.5)
