extends SceneTree
## Cursing Gnomes — building night-glow tests (NightGlow).
##
## The 2026-10-03 graphics pass gives buildings warm lit windows and a soft
## lamplight halo at night (Godot-native atmosphere; fix79's night is only a
## screen tint). Glow intensity runs on the GameState day-phase clock:
## phase 0 = midnight, 0.5 = noon (hour = phase * 24). Night when
## hour < 5 or hour > 21: deep night 1.0, dawn ramps 1->0 (hour 5->6.5),
## day 0, dusk ramps 0->1 (hour 19->21). Flicker is deterministic per
## building id. These tests pin the phase bands, ramp math, flicker bounds,
## and the redraw-key behavior. No rendering: only the pure math is tested.
## Jeremy 2026-10-04: fixed stuck-at-night — old bands assumed 0.25 = noon.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_night_glow.gd
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


## Phase bands follow the GameState clock: 0 = midnight, 0.5 = noon.
func _test_phase_bands() -> void:
	# Deep night: full glow.
	_check("deep night glow 1.0 (phase 0)", is_equal_approx(NightGlow.glow_for(0.0), 1.0))
	_check("deep night glow 1.0 (phase 0.1)", is_equal_approx(NightGlow.glow_for(0.1), 1.0))
	_check("night glow 1.0 (phase 0.9)", is_equal_approx(NightGlow.glow_for(0.9), 1.0))
	_check("night glow 1.0 (phase 0.99)", is_equal_approx(NightGlow.glow_for(0.99), 1.0))
	# Day: no glow. Midday (phase 0.5) must be full day, not night.
	_check("midday glow 0 (phase 0.5)", is_equal_approx(NightGlow.glow_for(0.5), 0.0))
	_check("day glow 0 (phase 0.3)", is_equal_approx(NightGlow.glow_for(0.3), 0.0))
	_check("day glow 0 (phase 0.7)", is_equal_approx(NightGlow.glow_for(0.7), 0.0))
	# Dawn ramps 1 -> 0 across hour 5..6.5 (phase 0.2083..0.2708).
	_check("dawn start 1.0 (hour 5)", is_equal_approx(NightGlow.glow_for(5.0 / 24.0), 1.0))
	_check("dawn midpoint ~0.5 (hour 5.75)",
		is_equal_approx(NightGlow.glow_for(5.75 / 24.0), 0.5))
	_check("dawn end 0 (hour 6.5)", is_equal_approx(NightGlow.glow_for(6.5 / 24.0), 0.0))
	# Dusk ramps 0 -> 1 across hour 19..21 (phase 0.7917..0.875).
	_check("dusk start 0 (hour 19)", is_equal_approx(NightGlow.glow_for(19.0 / 24.0), 0.0))
	_check("dusk midpoint ~0.5 (hour 20)",
		is_equal_approx(NightGlow.glow_for(20.0 / 24.0), 0.5))
	_check("dusk end 1.0 (hour 21)", is_equal_approx(NightGlow.glow_for(21.0 / 24.0), 1.0))
	# Monotonic ramps (no pop at band edges).
	var dawn_ok := true
	var prev := NightGlow.glow_for(5.0 / 24.0)
	for i in range(1, 61):
		var g := NightGlow.glow_for((5.0 + 1.5 * float(i) / 60.0) / 24.0)
		if g > prev + 0.0001:
			dawn_ok = false
		prev = g
	_check("dawn ramp monotonic decreasing", dawn_ok)
	var dusk_ok := true
	prev = NightGlow.glow_for(19.0 / 24.0)
	for i in range(1, 61):
		var g2 := NightGlow.glow_for((19.0 + 2.0 * float(i) / 60.0) / 24.0)
		if g2 < prev - 0.0001:
			dusk_ok = false
		prev = g2
	_check("dusk ramp monotonic increasing", dusk_ok)
	# Range sanity everywhere.
	var ranged := true
	var i := 0
	while i <= 100:
		var g3 := NightGlow.glow_for(float(i) / 100.0)
		if g3 < 0.0 or g3 > 1.0:
			ranged = false
		i += 1
	_check("glow stays in [0,1] across the day", ranged)


## Flicker: candle feel, deterministic, per-id variation.
func _test_flicker() -> void:
	for id in [0, 1, 42, 999999]:
		var f := NightGlow.flicker_for(0.75, id)
		_check("flicker in [0.8,1.0] id=%d" % id, f >= 0.8 and f <= 1.0)
	# Deterministic: same args, same value.
	_check("flicker deterministic",
		is_equal_approx(NightGlow.flicker_for(0.75, 42), NightGlow.flicker_for(0.75, 42)))
	# Per-id variation: not every building flickers in lockstep.
	var seen := {}
	for id2 in range(50):
		seen[int(NightGlow.flicker_for(0.73, id2) * 10000.0)] = true
	_check("flicker varies across ids", seen.size() > 10)
	# It moves with the phase (gentle candle waver, not frozen).
	var f1 := NightGlow.flicker_for(0.700, 7)
	var f2 := NightGlow.flicker_for(0.712, 7)
	_check("flicker changes with phase", not is_equal_approx(f1, f2))


## Phase cache + redraw key behavior.
func _test_key_and_cache() -> void:
	NightGlow.set_phase(0.5)
	_check("midday phase cache is 0", is_equal_approx(NightGlow.current(), 0.0))
	NightGlow.set_phase(0.0)
	_check("midnight phase cache is 1.0", is_equal_approx(NightGlow.current(), 1.0))
	# Stable key at a fixed phase: same args -> same key.
	var k1 := NightGlow.glow_key(123)
	var k2 := NightGlow.glow_key(123)
	_check("glow key stable", k1 == k2)
	# Different ids hash differently (flicker is per-id).
	_check("glow key differs by id", NightGlow.glow_key(123) != NightGlow.glow_key(124))
	# Crossing the day/night boundary changes the key (redraw actually
	# happens when the tint goes dark).
	NightGlow.set_phase(0.5)  # midday
	var kd := NightGlow.glow_key(123)
	NightGlow.set_phase(0.0)  # midnight
	var kn := NightGlow.glow_key(123)
	_check("glow key changes day->night", kd != kn)
	# Window color is warm, full bright (alpha baked by caller).
	var wc := NightGlow.window_color()
	_check("window color warm", wc.r > 0.9 and wc.g > 0.7 and wc.b > 0.4)


func _init() -> void:
	_test_phase_bands()
	_test_flicker()
	_test_key_and_cache()
	print("night_glow: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("FAILED: ", f)
		quit(1)
	quit(0)
