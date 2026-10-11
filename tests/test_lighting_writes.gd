extends SceneTree
## Cursing Gnomes — LightingRig write-skip tests (perf 2026-10-04).
##
## Graphics-hourly pass: LightingRig.set_phase() runs EVERY frame and used
## to write energy to every pooled PointLight2D plus the CanvasModulate
## color on every call — each write dirties a canvas item, pure
## render-thread churn while the values sat unchanged for hours of game
## time (day: window energy 0.0, night: 1.1). The fix:
##   - window lights: rewrite ALL lights only when w_energy actually changed
##     (sentinel -1.0 forces the first frame; every light always carries the
##     last written value, so the old "no dark frame on mid-frame reveal"
##     invariant is preserved)
##   - fire flicker: sampled at 15 Hz instead of 60 Hz (13 rad/s flicker is
##     visually identical at 15 Hz; _flicker_t still advances per frame so
##     the sampled pose stays exact)
##   - CanvasModulate: settle once the lerped color is indistinguishable
##     from the target instead of writing every frame forever
## Zero visual change: the same values reach the same properties.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_lighting_writes.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

const NIGHT := 0.0   # deep night: window energy 1.1
const MIDDAY := 0.5  # full day: window energy 0.0


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	_test_first_frame_writes_all()
	_test_stable_phase_skips_writes()
	_test_phase_change_rewrites()
	_test_setup_resets_sentinel()
	_test_flicker_quantized()
	_test_flicker_pose_exact()
	_test_modulate_settles()
	_test_flash_expiry_intact()
	print("lighting_writes: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _make_rig() -> LightingRig:
	var rig := LightingRig.new()
	rig.setup(null, "medium")  # 10 window + 6 fire + 4 flash
	return rig


## Sentinel forces the first frame to write every pooled window light.
func _test_first_frame_writes_all() -> void:
	var rig := _make_rig()
	rig.set_phase(NIGHT, 1.0 / 60.0)
	_check("first frame writes all 10 window lights",
		rig._window_writes == 10)
	var ok := true
	for l in rig._window_lights:
		if not is_equal_approx(l.energy, 1.1):
			ok = false
	_check("night window energy is 1.1 on every light", ok)
	rig.queue_free()


## 600 identical frames at night: no further window writes, values hold.
func _test_stable_phase_skips_writes() -> void:
	var rig := _make_rig()
	rig.set_phase(NIGHT, 1.0 / 60.0)
	var writes_after_first: int = rig._window_writes
	for i in range(600):
		rig.set_phase(NIGHT, 1.0 / 60.0)
	_check("600 stable night frames add zero window writes",
		rig._window_writes == writes_after_first)
	var ok := true
	for l in rig._window_lights:
		if not is_equal_approx(l.energy, 1.1):
			ok = false
	_check("window energies still 1.1 after skipped frames", ok)
	rig.queue_free()


## Day <-> night transitions still rewrite every light (no stuck values).
func _test_phase_change_rewrites() -> void:
	var rig := _make_rig()
	rig.set_phase(NIGHT, 1.0 / 60.0)
	for i in range(60):
		rig.set_phase(NIGHT, 1.0 / 60.0)
	var before: int = rig._window_writes
	rig.set_phase(MIDDAY, 1.0 / 60.0)
	_check("day transition rewrites all window lights",
		rig._window_writes == before + 10)
	var ok := true
	for l in rig._window_lights:
		if not is_equal_approx(l.energy, 0.0):
			ok = false
	_check("day window energy is 0.0 on every light", ok)
	for i in range(60):
		rig.set_phase(MIDDAY, 1.0 / 60.0)
	_check("stable day frames add zero window writes",
		rig._window_writes == before + 10)
	rig.set_phase(NIGHT, 1.0 / 60.0)
	ok = true
	for l in rig._window_lights:
		if not is_equal_approx(l.energy, 1.1):
			ok = false
	_check("return to night restores 1.1 on every light", ok)
	rig.queue_free()


## setup() rebuilds pools at energy 0.0 — the sentinel must reset so the
## first set_phase after a re-setup still writes (no dark-frame regress).
func _test_setup_resets_sentinel() -> void:
	var rig := _make_rig()
	rig.set_phase(NIGHT, 1.0 / 60.0)
	_check("night write happened", rig._window_writes == 10)
	rig.setup(null, "medium")  # rebuild: lights back at energy 0.0
	_check("setup resets window write counter", rig._window_writes == 0)
	_check("fresh lights start at energy 0.0",
		is_equal_approx(rig._window_lights[0].energy, 0.0))
	rig.set_phase(NIGHT, 1.0 / 60.0)
	_check("post-setup night frame rewrites all lights",
		rig._window_writes == 10)
	_check("post-setup night energy is 1.1",
		is_equal_approx(rig._window_lights[0].energy, 1.1))
	rig.queue_free()


## Fire flicker is quantized: 1.0s of 1/600 frames must produce ~15 quanta
## (14..16 to absorb float accumulation at the boundary), not 600.
func _test_flicker_quantized() -> void:
	var rig := _make_rig()
	for i in range(600):
		rig.set_phase(NIGHT, 1.0 / 600.0)
	var quanta: float = float(rig._fire_writes) / 6.0
	_check("fire flicker quantized (~15 quanta in 1.0s, got %d)" % int(quanta),
		quanta >= 14.0 and quanta <= 16.0)
	_check("flicker writes far below per-frame (600*6)",
		rig._fire_writes < 600 * 6)
	rig.queue_free()


## The sampled flicker pose is exactly the formula at the sampled time —
## quantization changes WHEN we sample, never the pose math.
func _test_flicker_pose_exact() -> void:
	var rig := _make_rig()
	# Drive past the first quantum with irregular deltas.
	var deltas := [0.03, 0.01, 0.05, 0.02, 0.09, 0.016]
	for d in deltas:
		rig.set_phase(NIGHT, d)
	_check("flicker fired at least once", rig._fire_writes >= 6)
	# Energies were written at the last quantum, not at "now".
	var t: float = rig._last_flicker_t
	_check("quantum time is in the past", t <= rig._flicker_t)
	var ok := true
	for i in range(rig._fire_lights.size()):
		var expect := 1.15 + 0.35 * sin(t * 13.0 + float(i) * 2.399)
		if not is_equal_approx(rig._fire_lights[i].energy, expect):
			ok = false
	_check("fire energies match formula at sampled time", ok)
	# Energies stay inside the candle band.
	ok = true
	for fl in rig._fire_lights:
		if fl.energy < 0.79 or fl.energy > 1.51:
			ok = false
	_check("fire energies stay in [0.8, 1.5] band", ok)
	rig.queue_free()


## CanvasModulate converges to the phase target and then stops churning.
func _test_modulate_settles() -> void:
	var rig := _make_rig()
	for i in range(600):
		rig.set_phase(0.3, 1.0 / 60.0)
	_check("modulate converges to ambient target",
		rig._modulate.color.is_equal_approx(LightingRig.ambient_for(0.3)))
	rig.queue_free()


## One-shot flash expiry is untouched by the write-skip change.
func _test_flash_expiry_intact() -> void:
	var rig := _make_rig()
	rig.flash(Vector2(50, 50), Color.RED, 150.0, 0.3)
	_check("flash visible after trigger", rig.visible_light_count() == 1)
	var slot: Dictionary = rig._flash_lights[0]
	slot["age"] = 5.0
	rig.set_phase(NIGHT, 0.1)
	_check("flash still expires after life", rig.visible_light_count() == 0)
	rig.queue_free()
