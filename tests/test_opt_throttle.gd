extends SceneTree
## Cursing Gnomes — performance regression tests for 2026-10-04 optimization.
##
## Jeremy: "Optimize everything." These tests lock in the throttling:
##   - Waterfall _FallsNode: 20Hz redraw (not 60Hz)
##   - Foam layer: 20Hz update (not 60Hz)
##   - Flood overlay: 20Hz redraw (not 60Hz)
##   - Radiation overlay: 20Hz redraw (not 60Hz)
##   - Off-screen props: _process disabled (not just work-skipped)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_opt_throttle.gd

const RiverRenderer = preload("res://scripts/world/river_renderer.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Throttle regression tests ===")
	_test_falls_throttle()
	_test_foam_throttle()
	_test_flood_throttle()
	_test_radiation_throttle()
	_test_prop_process_disable()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## Waterfall must not redraw every _process call.
func _test_falls_throttle() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://scripts/world/river_renderer.gd")
	# The _FallsNode._process must use an accumulator, not bare queue_redraw.
	_check("falls: uses _redraw_acc throttle",
		src.contains("_redraw_acc += delta"))
	_check("falls: 20Hz threshold (0.05)",
		src.contains("_redraw_acc >= 0.05"))
	# Must cull off-screen waterfalls.
	_check("falls: off-screen cull check",
		src.contains("in_view") and src.contains("get_camera_2d"))


## Foam layer must throttle to 20Hz.
func _test_foam_throttle() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://scripts/world/river_renderer.gd")
	_check("foam: uses _foam_acc throttle",
		src.contains("_foam_acc += delta"))
	_check("foam: 20Hz threshold",
		src.contains("_foam_acc < 0.05"))


## Flood overlay must throttle to 20Hz.
func _test_flood_throttle() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://scripts/world/flood_overlay.gd")
	_check("flood: uses _redraw_acc throttle",
		src.contains("_redraw_acc += delta"))


## Radiation overlay must throttle to 20Hz.
func _test_radiation_throttle() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://scripts/world/radiation_overlay.gd")
	_check("radiation: uses _redraw_acc throttle",
		src.contains("_redraw_acc += delta"))


# Note: prop _process disabling is tested via world.gd source check.
# The _cull_offscreen_props must call set_process.
func _test_prop_process_disable() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://scripts/world/world.gd")
	_check("props: set_process on cull",
		src.contains("p2d.set_process(in_view)"))
