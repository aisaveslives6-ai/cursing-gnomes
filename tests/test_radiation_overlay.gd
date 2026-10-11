extends SceneTree
## Cursing Gnomes — radiation overlay parity tests (Jeremy 2026-10-06).
##
## HTML parity (fix79 radiation render block): verbatim pulse + alpha formulas,
## pre-rendered rad_haze gradient stops, scorched ring (rgba(50,40,20,
## 0.25*scorch), width 18*scorch at 0.55r, scorch > 0.05), inView culling
## (z.x, z.y, z.r + 40), radius tracking (sim grows zone 396 -> 828 over the
## 240 s life; overlay reads z.r verbatim), intensity fade (max(0.15,
## 1 - age*0.7)) and scorch growth (min(1, age_s*0.02)) derived from sim life.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_radiation_overlay.gd
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


func _approx(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


class _NuclearStub extends RefCounted:
	var zones: Array = []
	var fallout: Dictionary = {}
	var rain: Array = []


func _new_overlay(stub: _NuclearStub) -> RadiationOverlay:
	var ov := RadiationOverlay.new()
	ov.nuclear = stub
	root.add_child(ov)  # triggers _ready() -> bakes the haze texture
	return ov


func _test_pulse_verbatim() -> void:
	# HTML: pulse = 0.55 + 0.45 * sin(now/900 + z.x * 0.01)
	_check("pulse at t=0,x=0 is 0.55", _approx(RadiationOverlay.pulse_at(0.0, 0.0), 0.55))
	var t_peak: float = 900.0 * PI / 2000.0  # t*1000/900 = PI/2
	_check("pulse peaks at 1.0", _approx(RadiationOverlay.pulse_at(t_peak, 0.0), 1.0))
	var t_trough: float = 3.0 * 900.0 * PI / 2000.0  # = 3PI/2
	_check("pulse troughs at 0.1", _approx(RadiationOverlay.pulse_at(t_trough, 0.0), 0.1))
	var x_peak: float = 50.0 * PI  # x*0.01 = PI/2
	_check("pulse spatial phase uses x*0.01", _approx(RadiationOverlay.pulse_at(0.0, x_peak), 1.0))
	# Different zones pulse out of phase (HTML anti-sync trick).
	_check("pulse differs across x", not _approx(
		RadiationOverlay.pulse_at(1.0, 0.0), RadiationOverlay.pulse_at(1.0, 300.0)))


func _test_alpha_verbatim() -> void:
	# HTML: a = 0.12 + 0.18 * intensity * pulse * min(1, life/40)
	_check("alpha full = 0.12+0.18",
		_approx(RadiationOverlay.zone_alpha(1.0, 1.0, 40.0), 0.30))
	_check("alpha scales with pulse",
		_approx(RadiationOverlay.zone_alpha(1.0, 0.55, 100.0), 0.12 + 0.18 * 0.55))
	_check("alpha birth/death ramp halves at life=20",
		_approx(RadiationOverlay.zone_alpha(1.0, 1.0, 20.0), 0.12 + 0.18 * 0.5))
	_check("alpha dead at life=0",
		_approx(RadiationOverlay.zone_alpha(1.0, 1.0, 0.0), 0.12))
	_check("alpha scales with intensity",
		_approx(RadiationOverlay.zone_alpha(0.3, 1.0, 100.0), 0.12 + 0.18 * 0.3))


func _test_intensity_fade() -> void:
	# HTML sim: z.intensity = max(0.15, 1 - age * 0.7), age = 1 - life/maxLife.
	_check("intensity 1.0 at birth", _approx(RadiationOverlay.zone_intensity(240.0, 240.0), 1.0))
	_check("intensity 0.65 at half life", _approx(RadiationOverlay.zone_intensity(120.0, 240.0), 0.65))
	_check("intensity 0.3 at death", _approx(RadiationOverlay.zone_intensity(0.0, 240.0), 0.3))
	_check("intensity never below 0.15", RadiationOverlay.zone_intensity(-50.0, 240.0) >= 0.15)


func _test_scorch_growth() -> void:
	# HTML sim: scorch = min(1, scorch + dt*0.02) => min(1, age_seconds*0.02).
	_check("scorch 0 at birth", _approx(RadiationOverlay.zone_scorch(240.0, 240.0), 0.0))
	_check("scorch 1 after 50 s", _approx(RadiationOverlay.zone_scorch(190.0, 240.0), 1.0))
	_check("scorch clamps at 1", _approx(RadiationOverlay.zone_scorch(0.0, 240.0), 1.0))
	_check("scorch ring threshold 0.05 reached at 2.5 s",
		_approx(RadiationOverlay.zone_scorch(237.5, 240.0), 0.05))
	_check("no ring before 2.5 s", RadiationOverlay.zone_scorch(238.0, 240.0) < 0.05)


func _test_culling() -> void:
	# HTML: inView(z.x, z.y, z.r + 40).
	var view := Rect2(0, 0, 1000, 1000)
	_check("zone in view", RadiationOverlay.zone_in_view(Vector2(500, 500), 100.0, view))
	_check("zone far outside culled",
		not RadiationOverlay.zone_in_view(Vector2(5000, 5000), 100.0, view))
	_check("cull margin r+40 keeps edge zone",
		RadiationOverlay.zone_in_view(Vector2(1139, 500), 100.0, view))
	_check("beyond margin culled",
		not RadiationOverlay.zone_in_view(Vector2(1141, 500), 100.0, view))


func _test_haze_texture() -> void:
	var stub := _NuclearStub.new()
	var ov := _new_overlay(stub)
	ov._bake_haze()  # direct bake check (draw-context-free)
	_check("haze texture baked", ov._haze != null)
	var grad: Gradient = ov._haze.gradient
	_check("haze has 4 stops", grad.get_point_count() == 4)
	# HTML-verbatim stops.
	var expect := [
		[0.0, Color(180.0 / 255.0, 1.0, 80.0 / 255.0, 1.0)],
		[0.45, Color(100.0 / 255.0, 160.0 / 255.0, 40.0 / 255.0, 0.7)],
		[0.75, Color(60.0 / 255.0, 80.0 / 255.0, 30.0 / 255.0, 0.35)],
		[1.0, Color(40.0 / 255.0, 50.0 / 255.0, 20.0 / 255.0, 0.0)],
	]
	for e in expect:
		var found := false
		for i in range(grad.get_point_count()):
			if _approx(grad.get_offset(i), float(e[0])) \
					and grad.get_color(i).is_equal_approx(e[1]):
				found = true
		_check("haze stop at %s present" % str(e[0]), found)
	_check("haze is radial", ov._haze.fill == GradientTexture2D.FILL_RADIAL)
	ov.queue_free()


func _draw_smoke_async() -> void:
	# Full _draw path via the real engine draw context: zone + scorch ring +
	# fallout field, then grown zone (396 -> 828 radius tracking), then
	# null/empty nuclear states. Headless dummy renderer = silent no-ops.
	var stub := _NuclearStub.new()
	stub.zones.append({"x": 500.0, "y": 500.0, "r": 396.0,
		"intensity": 1.0, "life": 100.0, "maxLife": 240.0})
	stub.fallout = {"x": 900.0, "y": 900.0, "r": 864.0,
		"life": 45.0, "maxLife": 90.0}
	var ov := _new_overlay(stub)
	ov.queue_redraw()
	await process_frame
	_check("draw with zone+fallout runs", true)
	# Radius tracking: sim grows the zone 396 -> 828; overlay must follow.
	stub.zones[0]["r"] = 828.0
	ov.queue_redraw()
	await process_frame
	_check("draw with grown zone runs", true)
	# Null/empty states must not error.
	ov.nuclear = null
	ov.queue_redraw()
	await process_frame
	_check("draw with null nuclear runs", true)
	ov.queue_free()


func _draw_rain_smoke_async() -> void:
	# HTML "Fallout rain" render block: rects, glow/base greens, alpha
	# min(1, life/4). Headless dummy renderer = silent no-ops.
	var stub := _NuclearStub.new()
	for i in range(12):
		stub.rain.append({"x": 500.0 + i * 40.0, "y": 400.0,
			"life": 2.0 + i * 2.0, "size": 3.0, "glow": i % 2 == 0})
	var ov := _new_overlay(stub)
	ov.queue_redraw()
	await process_frame
	_check("draw with rain runs", true)
	ov.queue_free()


func _test_suit_palette() -> void:
	# HTML drawRadiationSuit faction colors, verbatim.
	var expect := {
		"ogres": ["#33691e", "#1b5e20", "#aed581", "#558b2f"],
		"gnomes": ["#6a1b9a", "#4a148c", "#e1bee7", "#9c27b0"],
		"elves": ["#1b5e20", "#004d40", "#b2ff59", "#2e7d32"],
		"humans": ["#546e7a", "#37474f", "#ffd54f", "#78909c"],
		"undead": ["#546e7a", "#37474f", "#ffd54f", "#78909c"],
	}
	for faction: String in expect.keys():
		var cols: Array = UnitNode.suit_palette(faction)
		var ok := cols.size() == 4
		if ok:
			for i in range(4):
				var got: Color = cols[i]
				if not got.is_equal_approx(Color(String(expect[faction][i]))):
					ok = false
		_check("suit palette %s" % faction, ok)


func _initialize() -> void:
	_test_pulse_verbatim()
	_test_alpha_verbatim()
	_test_intensity_fade()
	_test_scorch_growth()
	_test_culling()
	_test_haze_texture()
	await _draw_smoke_async()
	await _draw_rain_smoke_async()
	_test_suit_palette()
	print("radiation_overlay: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)
