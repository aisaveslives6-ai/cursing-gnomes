extends SceneTree
## Cursing Gnomes — aspect-layout regression tests (launch readiness gate 7).
##
## Jeremy's order: portrait, landscape, PC 16:9 and PC 4:3 must each be
## auto-detected with their own UI. MainMenu._detect_orientation() sets the
## _orientation bucket (portrait/landscape/desktop) plus the orthogonal
## _aspect bucket ("widescreen" for 16:9+, "standard" for ~4:3); the faction
## carousel height branches on both via MainMenu.carousel_h_for().
##
## Headless note: DisplayServer.is_touchscreen_available() is false here, so
## "desktop" is decided purely by viewport size (>= 1024x600). The ratio
## math and branch values are identical on device.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_aspect_layouts.gd
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


func _new_menu() -> MainMenu:
	return MainMenu.new()


func _initialize() -> void:
	print("=== Cursing Gnomes aspect layout tests ===")
	_run.call_deferred()


func _run() -> void:
	_test_orientation_buckets()
	_test_headless_default()
	_test_aspect_buckets()
	_test_aspect_boundary()
	_test_carousel_heights()
	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _detect(vp: Vector2, touchscreen: bool = false) -> MainMenu:
	var m := _new_menu()
	m._detect_orientation(vp, touchscreen)
	return m


func _test_orientation_buckets() -> void:
	var m := _detect(Vector2(1920, 1080))
	_check("1080p: orientation desktop", m._orientation == "desktop")
	_check("1080p: is_desktop", m._is_desktop)
	_check("1080p: returns orientation", m._detect_orientation(Vector2(1920, 1080), false) == "desktop")
	m.free()

	m = _detect(Vector2(390, 844), true)  # iPhone 17 portrait CSS px, touch on
	_check("iphone portrait: orientation portrait", m._orientation == "portrait")
	_check("iphone portrait: not desktop", not m._is_desktop)
	m.free()

	m = _detect(Vector2(844, 390), true)  # iPhone 17 landscape CSS px, touch on
	_check("iphone landscape: orientation landscape", m._orientation == "landscape")
	_check("iphone landscape: not desktop", not m._is_desktop)
	m.free()

	m = _detect(Vector2(820, 1180), true)  # tablet portrait, touch on
	_check("tablet portrait: orientation portrait", m._orientation == "portrait")
	_check("tablet portrait: not desktop", not m._is_desktop)
	m.free()

	m = _detect(Vector2(1024, 768))  # 4:3 desktop still counts as desktop
	_check("4:3 desktop: orientation desktop", m._orientation == "desktop")
	_check("4:3 desktop: is_desktop", m._is_desktop)
	m.free()

	# Touchscreen forces the phone/tablet path even at desktop sizes
	# (e.g. a touch laptop in tablet mode).
	m = _detect(Vector2(1920, 1080), true)
	_check("touch 1080p: orientation landscape", m._orientation == "landscape")
	_check("touch 1080p: not desktop", not m._is_desktop)
	m.free()


func _test_headless_default() -> void:
	# Headless Godot reports a touchscreen as available, so the default
	# parameter hides the desktop branch here. This pins the quirk so the
	# injected parameter above stays honest.
	var m := _new_menu()
	m._detect_orientation(Vector2(1920, 1080))
	_check("headless default: 1080p is landscape (touch quirk)", m._orientation == "landscape")
	m.free()


func _test_aspect_buckets() -> void:
	var wide := [Vector2(1920, 1080), Vector2(2560, 1080), Vector2(1366, 768),
		Vector2(3840, 2160)]
	for vp in wide:
		var m := _detect(vp)
		_check("widescreen %s: aspect widescreen" % str(vp), m._aspect == "widescreen")
		m.free()

	var std := [Vector2(1024, 768), Vector2(1280, 960), Vector2(1400, 1050),
		Vector2(1600, 1200)]
	for vp in std:
		var m := _detect(vp)
		_check("4:3-ish %s: aspect standard" % str(vp), m._aspect == "standard")
		m.free()


func _test_aspect_boundary() -> void:
	# Ratio >= 1.5 is widescreen; anything below is standard.
	var m := _detect(Vector2(1500, 1000))  # exactly 1.5
	_check("ratio 1.5: widescreen", m._aspect == "widescreen")
	m.free()
	m = _detect(Vector2(1499, 1000))  # 1.499
	_check("ratio 1.499: standard", m._aspect == "standard")
	m.free()
	m = _detect(Vector2(1600, 1000))  # 1.6
	_check("ratio 1.6: widescreen", m._aspect == "widescreen")
	m.free()


func _test_carousel_heights() -> void:
	_check("portrait: 330", MainMenu.carousel_h_for("portrait", "widescreen") == 330.0)
	_check("portrait ignores aspect", MainMenu.carousel_h_for("portrait", "standard") == 330.0)
	_check("landscape: 300", MainMenu.carousel_h_for("landscape", "widescreen") == 300.0)
	_check("landscape ignores aspect", MainMenu.carousel_h_for("landscape", "standard") == 300.0)
	_check("desktop 16:9: 380", MainMenu.carousel_h_for("desktop", "widescreen") == 380.0)
	_check("desktop 4:3: 430", MainMenu.carousel_h_for("desktop", "standard") == 430.0)
	_check("desktop 4:3 taller than 16:9",
		MainMenu.carousel_h_for("desktop", "standard") > MainMenu.carousel_h_for("desktop", "widescreen"))
	# Unknown aspect falls through to the roomier 4:3 branch (pinned behavior).
	_check("desktop unknown aspect: 430", MainMenu.carousel_h_for("desktop", "bogus") == 430.0)
	# Unknown orientation falls back to the portrait base height.
	_check("unknown orientation: 330", MainMenu.carousel_h_for("bogus", "widescreen") == 330.0)
