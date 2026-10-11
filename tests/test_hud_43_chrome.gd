extends SceneTree
## Cursing Gnomes — 4:3 desktop slim-chrome tests (Jeremy 2026-10-08).
##
## Audit Gate 2's leftover: the in-game HUD had no 16:9 vs 4:3 distinction —
## a squarish PC window (1024x768, 1600x1200) got the full portrait chrome
## (84px bar + 64px tab strip), eating a fifth of the viewport height.
## The HUD now buckets aspect like the main menu (widescreen >= 1.5 ratio,
## else standard) and desktop 4:3 ("standard") takes the slim landscape
## chrome: 48px bar, 48px bubbles, tabs on the left rail.
##
## layout_mode_for is unchanged (1024x768 no-touch is still "desktop") —
## the aspect is orthogonal. Desktop 16:9 keeps the standard chrome, so
## no existing behavior regresses; defaults keep bar_h_for("desktop")=84.
##
## Drop into tests/ and run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hud_43_chrome.gd
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
	print("=== Cursing Gnomes 4:3 desktop slim-chrome tests ===")
	_run.call_deferred()


func _run() -> void:
	_test_slim_chrome_for()
	_test_chrome_values()
	_test_defaults_unchanged()
	_test_instance_helper()
	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _test_slim_chrome_for() -> void:
	# Phone landscape: slim in any aspect.
	_check("landscape widescreen slim",
		Hud.slim_chrome_for("landscape", "widescreen"))
	_check("landscape standard slim",
		Hud.slim_chrome_for("landscape", "standard"))
	# Desktop 4:3 ("standard"): slim — the new behavior.
	_check("desktop standard slim",
		Hud.slim_chrome_for("desktop", "standard"))
	# Desktop 16:9+ ("widescreen"): standard chrome, unchanged.
	_check("desktop widescreen not slim",
		not Hud.slim_chrome_for("desktop", "widescreen"))
	# Portrait: never slim.
	_check("portrait widescreen not slim",
		not Hud.slim_chrome_for("portrait", "widescreen"))
	_check("portrait standard not slim",
		not Hud.slim_chrome_for("portrait", "standard"))


func _test_chrome_values() -> void:
	# 4:3 desktop gets landscape's compact values.
	_check("4:3 desktop bar 48",
		Hud.bar_h_for("desktop", "standard") == 48.0)
	_check("4:3 desktop bubble 48",
		Hud.bubble_d_for("desktop", "standard") == 48.0)
	# Space actually saved vs the old portrait chrome.
	_check("4:3 desktop bar slimmer than old chrome",
		Hud.bar_h_for("desktop", "standard") < Hud.bar_h_for("desktop", "widescreen"))
	_check("4:3 desktop bubble smaller than old chrome",
		Hud.bubble_d_for("desktop", "standard") < Hud.bubble_d_for("desktop", "widescreen"))
	# Landscape values unchanged.
	_check("landscape bar 48",
		Hud.bar_h_for("landscape", "widescreen") == 48.0)
	_check("landscape bubble 48",
		Hud.bubble_d_for("landscape", "widescreen") == 48.0)


func _test_defaults_unchanged() -> void:
	# Backward-compatible defaults: one-arg calls behave exactly as before,
	# so every pinned test (test_ui_landscape, test_aspect_unified) holds.
	_check("desktop default bar 84", Hud.bar_h_for("desktop") == 84.0)
	_check("portrait default bar 84", Hud.bar_h_for("portrait") == 84.0)
	_check("landscape default bar 48", Hud.bar_h_for("landscape") == 48.0)
	_check("desktop default bubble 64", Hud.bubble_d_for("desktop") == 64.0)
	_check("portrait default bubble 64", Hud.bubble_d_for("portrait") == 64.0)
	_check("landscape default bubble 48", Hud.bubble_d_for("landscape") == 48.0)
	_check("bogus default bar 84", Hud.bar_h_for("bogus") == 84.0)
	_check("bogus default bubble 64", Hud.bubble_d_for("bogus") == 64.0)
	# layout_mode_for is untouched: mode is still "desktop" on 4:3 no-touch —
	# aspect is orthogonal, the chrome is what changes.
	_check("4:3 1024x768 no-touch still desktop",
		Hud.layout_mode_for(Vector2(1024, 768), false) == "desktop")
	_check("4:3 1600x1200 no-touch still desktop",
		Hud.layout_mode_for(Vector2(1600, 1200), false) == "desktop")
	_check("16:9 1920x1080 no-touch still desktop",
		Hud.layout_mode_for(Vector2(1920, 1080), false) == "desktop")


func _test_instance_helper() -> void:
	# The instance shortcut follows the current mode+aspect (headless-safe:
	# no viewport needed, it only reads the two fields).
	var hud := Hud.new()
	hud._layout_mode = "desktop"
	hud._aspect = "standard"
	_check("instance 4:3 desktop slim", hud._slim_chrome())
	_check("instance 4:3 desktop bar 48", hud._bubble_d() == 48.0)
	hud._aspect = "widescreen"
	_check("instance 16:9 desktop not slim", not hud._slim_chrome())
	_check("instance 16:9 desktop bubble 64", hud._bubble_d() == 64.0)
	hud._layout_mode = "portrait"
	hud._aspect = "widescreen"
	_check("instance portrait not slim", not hud._slim_chrome())
	hud.free()
