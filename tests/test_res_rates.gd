extends SceneTree
## Cursing Gnomes — rolling per-minute net income sampler tests.
##
## Pins HTML source-of-truth parity (build-staging/fix79/index.html,
## "Rolling per-minute net income sampler"): 1s sample interval, 100-sample
## rolling buffer, 45s rate window, 0.25-minute divisor floor, and the
## "+2.5/min" ASCII rate format (no emoji — tofu boxes on iPhone).
## Pure math: no rendering, no sim, no economy changes.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_res_rates.gd
##
## Exit code 0 = all passed, 1 = any failure.


const RES := ["gold", "wood", "food", "seeds", "oil", "soul_essence"]

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


func _amt(gold: float) -> Dictionary:
	var d: Dictionary = {}
	for r: String in RES:
		d[r] = 0.0
	d["gold"] = gold
	return d


## Empty / single-sample samplers report zero rates (no delta yet).
func _test_cold_start() -> void:
	var s := ResRateSampler.new()
	var r: Dictionary = s.rates_per_min(RES)
	_check("empty sampler: gold rate 0", is_equal_approx(float(r["gold"]), 0.0))
	_check("empty sampler: wood rate 0", is_equal_approx(float(r["wood"]), 0.0))
	s.sample(_amt(100.0), 0)
	r = s.rates_per_min(RES)
	_check("one sample: gold rate 0", is_equal_approx(float(r["gold"]), 0.0))


## Two samples 60s apart, +120 gold: window finds the first sample as base
## (60s >= 45s window), mins = 1.0 -> +120.0/min.
func _test_basic_rate() -> void:
	var s := ResRateSampler.new()
	s.sample(_amt(100.0), 0)
	s.sample(_amt(220.0), 60000)
	var r: Dictionary = s.rates_per_min(RES)
	_check("basic +120/min gold", is_equal_approx(float(r["gold"]), 120.0))
	_check("basic wood still 0", is_equal_approx(float(r["wood"]), 0.0))


## 45s window: samples at t=0, t=30s, t=90s with gold 0/30/90.
## Base = oldest sample >= 45s back from latest (t=30s): delta 60 over
## 60s -> +60.0/min. The t=0 sample falls outside the window.
func _test_window_selection() -> void:
	var s := ResRateSampler.new()
	s.sample(_amt(0.0), 0)
	s.sample(_amt(30.0), 30000)
	s.sample(_amt(90.0), 90000)
	var r: Dictionary = s.rates_per_min(RES)
	_check("windowed rate +60/min", is_equal_approx(float(r["gold"]), 60.0))


## 0.25-minute divisor floor: +60 gold in 1s -> 60 / 0.25 = +240/min.
func _test_min_mins_floor() -> void:
	var s := ResRateSampler.new()
	s.sample(_amt(0.0), 0)
	s.sample(_amt(60.0), 1000)
	var r: Dictionary = s.rates_per_min(RES)
	_check("min-mins floor gives +240/min", is_equal_approx(float(r["gold"]), 240.0))


## Losses show as negative rates.
func _test_negative_rate() -> void:
	var s := ResRateSampler.new()
	s.sample(_amt(500.0), 0)
	s.sample(_amt(380.0), 60000)
	var r: Dictionary = s.rates_per_min(RES)
	_check("negative rate -120/min", is_equal_approx(float(r["gold"]), -120.0))


## 1s sample interval: a sample 500ms after the last is dropped.
func _test_interval_gating() -> void:
	var s := ResRateSampler.new()
	_check("first sample accepted", s.sample(_amt(0.0), 0))
	_check("500ms sample dropped", not s.sample(_amt(1.0), 500))
	_check("1000ms sample accepted", s.sample(_amt(2.0), 1000))


## Buffer cap: 120 accepted samples -> exactly 100 kept (oldest dropped).
func _test_buffer_cap() -> void:
	var s := ResRateSampler.new()
	for i: int in range(120):
		s.sample(_amt(float(i)), i * 1000)
	_check("buffer capped at 100", s._buf.size() == 100)
	_check("oldest kept is t=20000", int(s._buf[0]["t"]) == 20000)


## Rate format: ASCII "+"/"-" prefixes, one decimal, "/min" suffix, no glyphs.
func _test_format_rate() -> void:
	_check("positive format", ResRateSampler.format_rate(2.5) == "+2.5/min")
	_check("negative format", ResRateSampler.format_rate(-3.0) == "-3.0/min")
	_check("zero format", ResRateSampler.format_rate(0.0) == "+0.0/min")
	_check("rounded format", ResRateSampler.format_rate(1.234) == "+1.2/min")


func _initialize() -> void:
	print("=== Cursing Gnomes resource-rate sampler tests ===")
	_test_cold_start()
	_test_basic_rate()
	_test_window_selection()
	_test_min_mins_floor()
	_test_negative_rate()
	_test_interval_gating()
	_test_buffer_cap()
	_test_format_rate()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
