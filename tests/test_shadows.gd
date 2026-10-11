extends SceneTree
## Cursing Gnomes — sun-driven blob shadow tests (Shadows).
##
## The 2026-10-03 graphics pass ports HTML fix79's drawShadowSystem/_sunState
## sun math into Godot (the HTML function is dead upstream — it opens with
## `return;` — so this is a Godot-native enable of the same model): soft blob
## per mover, offset opposite the sun, long at dawn/dusk, zero at night.
## These tests pin the sun math, the HTML-verbatim sizing/offset numbers,
## and the redraw-key behavior. No rendering: only the pure math is tested.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_shadows.gd
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


## Sun math in the GameState day-phase space (0 = midnight, 0.5 = noon).
## Phase day: sun up for hour in [5, 21]; solar noon at hour 13
## (dayT = 0.5), matching the GameState clock. Jeremy 2026-10-04: fixed
## stuck-at-night — old bands assumed 0.25 = noon.
func _test_sun_state() -> void:
	# Solar noon: shadow straight up-screen (-Y), shortest, full alpha.
	var noon: Dictionary = Shadows.sun_state_for(13.0 / 24.0)
	_check("noon sun up", bool(noon["up"]))
	_check("noon shadow points up-screen (dx~0)", absf(float(noon["dx"])) < 0.05)
	_check("noon shadow points up-screen (dy~-1)", absf(float(noon["dy"]) + 1.0) < 0.05)
	_check("noon lenF shortest (0.35)", is_equal_approx(float(noon["lenF"]), 0.35))
	_check("noon alpha full (0.36)", is_equal_approx(float(noon["alpha"]), 0.36))
	# Mid-morning: sun toward the east (+X), shadow falls west (-X).
	var morning: Dictionary = Shadows.sun_state_for(9.0 / 24.0)
	_check("morning sun up", bool(morning["up"]))
	_check("morning shadow points west (dx<0)", float(morning["dx"]) < -0.5)
	# Dusk: sun toward the west (-X), shadow falls east (+X), longer.
	var dusk: Dictionary = Shadows.sun_state_for(19.0 / 24.0)
	_check("dusk sun up", bool(dusk["up"]))
	_check("dusk shadow points east (dx>0)", float(dusk["dx"]) > 0.5)
	_check("dusk lenF longer than noon",
		float(dusk["lenF"]) > float(noon["lenF"]) + 0.5)
	_check("dusk alpha less than noon",
		float(dusk["alpha"]) < float(noon["alpha"]) and float(dusk["alpha"]) > 0.0)
	# Night: no sun, no shadow.
	var night: Dictionary = Shadows.sun_state_for(0.95)
	_check("night sun down", not bool(night["up"]))
	_check("night alpha zero", is_equal_approx(float(night["alpha"]), 0.0))
	var night2: Dictionary = Shadows.sun_state_for(0.0)
	_check("phase 0 night", not bool(night2["up"]))
	# Dawn boundary: elevation 0 -> not up yet (elev > 0.03 rule).
	var dawn: Dictionary = Shadows.sun_state_for(5.0 / 24.0)
	_check("dawn boundary sun not up", not bool(dawn["up"]))
	_check("dawn boundary alpha zero", is_equal_approx(float(dawn["alpha"]), 0.0))


## HTML putD numbers: offset = sun dir * 34px * lenF, clamped to 80px;
## size = fp*1.3 x fp*0.85; alpha = sun.alpha * 0.8.
func _test_putd_numbers() -> void:
	# Offset never exceeds the 80px clamp across the whole day.
	for i in 41:
		var phase := (5.0 + 16.0 * float(i) / 40.0) / 24.0
		var off := Shadows.offset_for(Shadows.sun_state_for(phase))
		_check("offset clamped at phase %.2f" % phase, off.length() <= 80.001)
	# Noon: 34 * 0.35 = 11.9px straight up.
	var noon_off := Shadows.offset_for(Shadows.sun_state_for(13.0 / 24.0))
	_check("noon offset magnitude (11.9px)",
		absf(noon_off.length() - 11.9) < 0.3)
	_check("noon offset points up", noon_off.y < 0.0 and absf(noon_off.x) < 1.0)
	# Alpha scaling.
	_check("noon blob alpha (0.288)",
		is_equal_approx(Shadows.alpha_for(Shadows.sun_state_for(13.0 / 24.0)), 0.36 * 0.8))
	_check("night blob alpha zero",
		is_equal_approx(Shadows.alpha_for(Shadows.sun_state_for(0.95)), 0.0))
	_check("blueprint alpha half",
		is_equal_approx(Shadows.alpha_for(Shadows.sun_state_for(13.0 / 24.0), 0.5), 0.36 * 0.8 * 0.5))


## Soft blob texture: radial falloff, center opaque-ish, corners clear.
func _test_blob_texture() -> void:
	var tex: Texture2D = Shadows.blob_texture()
	_check("blob texture exists", tex != null)
	_check("blob texture 64x64", tex.get_width() == 64 and tex.get_height() == 64)
	var img := tex.get_image()
	var center_a := img.get_pixel(32, 32).a
	var mid_a := img.get_pixel(48, 32).a
	var corner_a := img.get_pixel(0, 0).a
	_check("blob center strongest", center_a > mid_a)
	_check("blob fades toward edge", mid_a < center_a and mid_a > 0.0)
	_check("blob corner clear", corner_a < 0.01)
	_check("blob is white RGB", img.get_pixel(32, 32).r > 0.9)


## Redraw keys: stable when nothing changes, change on big sun moves.
func _test_shadow_keys() -> void:
	var pos := Vector2(100, 200)
	Shadows.set_phase(13.0 / 24.0)
	var k1 := Shadows.shadow_key(pos)
	_check("key stable same phase", Shadows.shadow_key(pos) == k1)
	_check("key moves with position", Shadows.shadow_key(pos + Vector2(50, 0)) != k1)
	Shadows.set_phase(0.0)
	_check("key changes day->night", Shadows.shadow_key(pos) != k1)
	# set_phase feeds current().
	Shadows.set_phase(9.0 / 24.0)
	var cur: Dictionary = Shadows.current()
	_check("current() matches set_phase",
		is_equal_approx(float(cur["alpha"]), float(Shadows.sun_state_for(9.0 / 24.0)["alpha"])))


## Node footprints: units chibi-sized, monsters scaled, buildings by type.
func _test_footprints() -> void:
	var u := UnitNode.new()
	u.job = "worker"
	_check("unit footprint chibi (33.0)",
		is_equal_approx(u._shadow_footprint(), 44.0 * 0.75))
	u.job = "thicc_moose"
	_check("moose footprint bigger",
		u._shadow_footprint() > 44.0 * 0.75)
	u.job = "giant_ass"
	_check("giant ass footprint biggest",
		is_equal_approx(u._shadow_footprint(), 44.0 * 3.0 * 0.75))
	u.queue_free()
	var b := BuildingNode.new()
	b.btype = "hall"
	_check("hall shadow footprint 52", is_equal_approx(b._size_for("hall"), 52.0))
	b.btype = "well"
	_check("well shadow footprint 20", is_equal_approx(b._size_for("well"), 20.0))
	b.btype = "something_new"
	_check("unknown type falls back to 30", is_equal_approx(b._size_for("something_new"), 30.0))
	b.queue_free()


func _initialize() -> void:
	print("=== Cursing Gnomes shadow tests ===")
	_test_sun_state()
	_test_putd_numbers()
	_test_blob_texture()
	_test_shadow_keys()
	_test_footprints()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
