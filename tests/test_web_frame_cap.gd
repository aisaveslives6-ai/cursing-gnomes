extends SceneTree
## Regression tests for Jeremy 2026-10-07 thermal bug ("iPhone runs hot"):
## web frame-rate cap.
##
## Engine.max_fps was never set (0 = uncapped). On ProMotion iPhones Safari
## can drive rAF at 120 Hz, doubling the sustained burn of the sim + render
## loop for zero visible gain in a pixel-art RTS. World._ready now applies
## WebFrameCap (web-gated, idempotent): 60 fps cap on web, desktop untouched.
##
## Run: Godot --headless --path . -s res://tests/test_web_frame_cap.gd

var _passed := 0
var _failed := 0
var _failures: Array = []
var _saved_cap := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("FAIL: ", name)


func _initialize() -> void:
	_saved_cap = Engine.max_fps
	_test_target_is_sixty()
	_test_forced_web_applies_cap()
	_test_idempotent()
	_test_non_web_leaves_untouched()
	_test_should_cap_is_bool()
	Engine.max_fps = _saved_cap
	print("web_frame_cap: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("FAILURES: ", _failures)
	quit(1 if _failed > 0 else 0)


## Jeremy's bar is 60 fps on iPhone 17 — the cap must equal the target,
## never below it.
func _test_target_is_sixty() -> void:
	_check("target is 60", WebFrameCap.TARGET_FPS == 60)


## Forced-web path (what iPhone Safari takes): cap lands at 60.
func _test_forced_web_applies_cap() -> void:
	Engine.max_fps = 0
	var cap := WebFrameCap.new()
	_check("forced web applies", cap.apply(true))
	_check("cap is 60", Engine.max_fps == 60)
	_check("current_cap reads 60", WebFrameCap.current_cap() == 60)


## Re-applying must not change anything (World._ready runs once, but a
## scene reload must not stack or clear the cap).
func _test_idempotent() -> void:
	Engine.max_fps = 0
	var cap := WebFrameCap.new()
	cap.apply(true)
	var first := Engine.max_fps
	cap.apply(true)
	_check("idempotent", Engine.max_fps == first and Engine.max_fps == 60)


## Headless Linux is not web: the unforced path must leave the engine
## untouched (desktop keeps uncapped high-refresh).
func _test_non_web_leaves_untouched() -> void:
	Engine.max_fps = 0
	var cap := WebFrameCap.new()
	var applied := cap.apply(false)
	if OS.has_feature("web"):
		_check("web build applies unforced", applied and Engine.max_fps == 60)
	else:
		_check("non-web unforced is no-op", not applied)
		_check("non-web leaves cap at 0", Engine.max_fps == 0)


func _test_should_cap_is_bool() -> void:
	var v: bool = WebFrameCap.should_cap()
	_check("should_cap returns bool", v == true or v == false)
