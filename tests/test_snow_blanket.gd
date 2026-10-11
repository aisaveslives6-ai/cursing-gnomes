extends SceneTree
## Cursing Gnomes — seasonal snow blanket tests.
##
## Jeremy 2026-10-04: the dynamic weather/seasons must be visible in the sim
## graphics. The HTML never whitened the ground in winter; the Godot port
## lays a soft snow blanket over the world while SimSeasons reports Winter
## (SnowBlanket, wired in main.gd next to WeatherFX). These tests pin the
## pure season/fade math, the quantized redraw behavior, and a live-frame
## smoke test (no rendering assertions — headless-safe).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_snow_blanket.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


const SnowScript := preload("res://scripts/world/snow_blanket.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _frame := 0
var _snow: Node2D = null


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	print("=== Cursing Gnomes snow blanket tests ===")
	_test_amount_math()
	_test_ramps_monotonic()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		# Live node: winter override should raise the blanket.
		_snow = SnowScript.new()
		root.add_child(_snow)
		_snow.set_season_override("Winter", 1, 15)
	elif _frame == 2:
		_check("winter: node visible", _snow.visible)
		_check("winter: amount full",
			is_equal_approx(_snow.current_amount(), 1.0))
		_check("winter: z_index -95 (terrain -100, foam -90)",
			_snow.z_index == -95)
		# A real draw pass must not error (headless still runs _draw).
		_snow.queue_redraw()
		_snow.set_season_override("Summer", 7, 15)
	elif _frame == 3:
		_check("summer: node hidden", not _snow.visible)
		_check("summer: amount zero",
			is_equal_approx(_snow.current_amount(), 0.0))
		_snow.queue_free()
		_snow = null
		print("snow_blanket: %d passed, %d failed" % [_passed, _failed])
		if _failed > 0:
			for f in _failures:
				print("  FAILED: ", f)
			quit(1)
		else:
			quit(0)
	return false


func _test_amount_math() -> void:
	var A := SnowScript.blanket_amount_for
	_check("no blanket in summer", is_equal_approx(A.call("Summer", 7, 15), 0.0))
	_check("no blanket in spring", is_equal_approx(A.call("Spring", 4, 10), 0.0))
	_check("no blanket in autumn", is_equal_approx(A.call("Autumn", 10, 20), 0.0))
	_check("full blanket mid-winter", is_equal_approx(A.call("Winter", 1, 15), 1.0))
	_check("winter fade-in day 1", is_equal_approx(A.call("Winter", 12, 1), 0.2))
	_check("winter fade-in complete day 5",
		is_equal_approx(A.call("Winter", 12, 5), 1.0))
	_check("winter fade-in holds late month",
		is_equal_approx(A.call("Winter", 12, 28), 1.0))
	_check("winter fade-out day 30", is_equal_approx(A.call("Winter", 2, 30), 0.2))
	_check("winter fade-out starts day 26",
		is_equal_approx(A.call("Winter", 2, 26), 1.0))
	_check("winter holds before fade-out",
		is_equal_approx(A.call("Winter", 2, 20), 1.0))
	_check("unknown season = no blanket", is_equal_approx(A.call("", 1, 1), 0.0))


func _test_ramps_monotonic() -> void:
	var A := SnowScript.blanket_amount_for
	var prev := -1.0
	for d in range(1, 6):
		var a: float = A.call("Winter", 12, d)
		_check("fade-in monotonic day %d" % d, a >= prev)
		prev = a
	prev = 2.0
	for d in range(26, 31):
		var a2: float = A.call("Winter", 2, d)
		_check("fade-out monotonic day %d" % d, a2 <= prev)
		prev = a2
