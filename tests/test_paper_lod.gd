extends SceneTree
## Cursing Gnomes — paper-map LOD tests (Jeremy 2026-10-04).
##
## Jeremy's idea: at far zoom-out, the game switches to paper-map-only
## rendering (HTML inPaperMap parity) — ~1,500 detailed nodes hide, leaving
## just the parchment map. This is the far-zoom 60fps win.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_paper_lod.gd

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


func _test_lod_trigger() -> void:
	var pm := PaperMap.new()
	# Starts transparent (no zoom-out yet) -> not LOD.
	_check("starts not LOD", not pm.is_paper_lod())
	# Simulate fully faded in.
	pm._map_opacity = 1.0
	_check("fully opaque -> LOD", pm.is_paper_lod())
	# Partial fade -> not LOD (seamless transition still showing world).
	pm._map_opacity = 0.5
	_check("half fade -> not LOD", not pm.is_paper_lod())
	# Just under the bar -> not LOD.
	pm._map_opacity = 0.98
	_check("0.98 -> not LOD", not pm.is_paper_lod())
	pm._map_opacity = 0.99
	_check("0.99 -> LOD", pm.is_paper_lod())
	pm.queue_free()


func _test_zoom_threshold_matches_html() -> void:
	# Jeremy 2026-10-04: moved from HTML's 0.16 to 0.35 — "should switch
	# to LOD sooner" when zooming out. Intentional deviation for perf.
	_check("zoom threshold 0.35 (Jeremy 2026-10-04)",
		absf(PaperMap.ZOOM_THRESHOLD - 0.35) < 0.001)


func _initialize() -> void:
	print("=== Paper-map LOD tests ===")
	_test_lod_trigger()
	_test_zoom_threshold_matches_html()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)
