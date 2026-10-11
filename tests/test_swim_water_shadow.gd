extends SceneTree
## Cursing Gnomes — swimmer water-shadow tests (launch readiness gate 3).
##
## Deferred finding from the 2026-10-06 floating audit: swimming units and
## animals drew the sun-cast ground blob on water. At dawn/dusk that blob is
## offset up to 80px from the body (HTML putD sun math, verbatim in
## Shadows.offset_for) — a floating dark ellipse on open water. Swimmers now
## get a PINNED water shadow instead: same soft blob, no sun offset, slightly
## tighter and softer (Shadows.draw_water_shadow + water_shadow_rect/size).
## The dispatch contract lives in UnitNode.shadow_style /
## AnimalNode.shadow_style so it is testable without a canvas; the swim bit
## folds into Shadows.shadow_key so entering/exiting water swaps the shadow
## the same frame.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_swim_water_shadow.gd
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
	_test_water_shadow_rect_pinned()
	_test_water_shadow_size()
	_test_shadow_key_swim_bit()
	_test_unit_shadow_style()
	_test_animal_shadow_style()
	_test_water_shadow_alpha_gate()
	print("swim_water_shadow: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("    - ", f)
		quit(1)
	else:
		quit(0)


## The water shadow is pinned: centered on the waterline point under every
## sun state (dawn/noon/dusk), while the ground blob's sun offset moves.
func _test_water_shadow_rect_pinned() -> void:
	var size := Vector2(30.0, 19.5)
	var at := Vector2(123.0, 456.0)
	var rects: Array[Rect2] = []
	for hour in [6.0, 13.0, 19.5]:
		Shadows.set_phase(hour / 24.0)
		var r := Shadows.water_shadow_rect(size, at)
		rects.append(r)
		_check("water rect centered at dawn/noon/dusk (hour %d)" % int(hour),
			r.get_center().is_equal_approx(at))
	# Identical under all three sun states — sun-blind.
	_check("water rect dawn==noon", rects[0].is_equal_approx(rects[1]))
	_check("water rect noon==dusk", rects[1].is_equal_approx(rects[2]))
	# Default origin honored too.
	_check("water rect default at origin",
		Shadows.water_shadow_rect(size).get_center().is_equal_approx(Vector2.ZERO))
	# Contrast: the ground blob's sun offset is large at dawn/dusk — the
	# water shadow deliberately ignores it.
	Shadows.set_phase(6.0 / 24.0)
	var dawn_off := Shadows.offset_for(Shadows.current())
	_check("dawn sun offset is large (>30px)", dawn_off.length() > 30.0)
	_check("water rect ignores the dawn offset",
		Shadows.water_shadow_rect(size, at).get_center().is_equal_approx(at))


## HTML putD footprint shaping (fp*1.3 x fp*0.85), tightened on the water.
func _test_water_shadow_size() -> void:
	var s := Shadows.water_shadow_size(40.0)
	var ground := Vector2(40.0 * 1.3, 40.0 * 0.85)
	_check("water size = ground size * tighten",
		s.is_equal_approx(ground * Shadows.WATER_SHADOW_TIGHTEN))
	_check("tighten < 1 (water shadow smaller)", Shadows.WATER_SHADOW_TIGHTEN < 1.0)
	_check("tighten > 0", Shadows.WATER_SHADOW_TIGHTEN > 0.0)
	_check("zero footprint -> zero size",
		Shadows.water_shadow_size(0.0).is_equal_approx(Vector2.ZERO))


## The swim bit joins the redraw key: same position, different mode.
func _test_shadow_key_swim_bit() -> void:
	Shadows.set_phase(13.0 / 24.0)
	var pos := Vector2(200.0, 300.0)
	var land := Shadows.shadow_key(pos, false)
	var swim := Shadows.shadow_key(pos, true)
	_check("swim bit changes key", land != swim)
	_check("key stable, same mode", Shadows.shadow_key(pos, true) == swim)
	_check("key stable, land mode", Shadows.shadow_key(pos, false) == land)
	_check("default arg == land mode", Shadows.shadow_key(pos) == land)
	_check("key still moves with position",
		Shadows.shadow_key(pos + Vector2(50.0, 0.0), true) != swim)


## Unit dispatch contract.
func _test_unit_shadow_style() -> void:
	var fp := 33.0  # chibi unit footprint (monster_scale * 0.75)
	var swim: Array = UnitNode.shadow_style(true, fp)
	_check("unit swim kind is water", String(swim[0]) == "water")
	_check("unit swim size pinned/tight",
		swim[1].is_equal_approx(Shadows.water_shadow_size(fp)))
	_check("unit swim alpha softer", is_equal_approx(float(swim[2]), 0.55))
	var land: Array = UnitNode.shadow_style(false, fp)
	_check("unit land kind is ground", String(land[0]) == "ground")
	_check("unit land size is HTML putD shaping",
		land[1].is_equal_approx(Vector2(fp * 1.3, fp * 0.85)))
	_check("unit land alpha full", is_equal_approx(float(land[2]), 1.0))
	# Boat footprint path uses the same contract (boats never swim, but the
	# contract must hold for any footprint).
	var boat: Array = UnitNode.shadow_style(false, 60.0)
	_check("unit contract holds for boat footprint",
		String(boat[0]) == "ground")


## Animal dispatch contract (same precedent as units).
func _test_animal_shadow_style() -> void:
	var fp := AnimalNode.ANIMAL_SHADOW_FOOTPRINT
	var swim: Array = AnimalNode.shadow_style(true, fp)
	_check("animal swim kind is water", String(swim[0]) == "water")
	_check("animal swim size pinned/tight",
		swim[1].is_equal_approx(Shadows.water_shadow_size(fp)))
	_check("animal swim alpha softer", is_equal_approx(float(swim[2]), 0.55))
	var land: Array = AnimalNode.shadow_style(false, fp)
	_check("animal land kind is ground", String(land[0]) == "ground")
	_check("animal land size is HTML putD shaping",
		land[1].is_equal_approx(Vector2(fp * 1.3, fp * 0.85)))


## Water shadows obey the same sun alpha gate as ground blobs: zero at
## night, positive at noon (draw_water_shadow early-outs below 0.004).
func _test_water_shadow_alpha_gate() -> void:
	Shadows.set_phase(13.0 / 24.0)
	var noon_a := Shadows.alpha_for(Shadows.current(), 0.55)
	_check("noon water alpha positive", noon_a > 0.004)
	Shadows.set_phase(0.0)
	var night_a := Shadows.alpha_for(Shadows.current(), 0.55)
	_check("night water alpha zero", night_a <= 0.004)
	# Restore a sane phase for any later suites sharing the static.
	Shadows.set_phase(13.0 / 24.0)
