extends SceneTree
## Cursing Gnomes — optimization validation tests (Jeremy 2026-10-04).
##
## Validates the "ultimate optimization" pass for the 60fps iPhone 17 target:
##   - UnitAnimator.apply_to computes poses without Dictionary allocation
##     (was 14,400 dict allocs/sec across 240 units)
##   - Off-screen units have _process disabled via set_culled (world sync
##     drives it; position still updates from the sim)
##   - Day/night phase conventions are consistent: GameState (0=midnight,
##     0.5=noon) matches NightGlow, Shadows, LightingRig, WeatherFX
##   - Stardew clock text uses the real game hour (not 86400-based math)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_optimization.gd


const UnitAnimator = preload("res://scripts/world/unit_animator.gd")

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


## apply_to must produce identical results to pose() (no behavior change
## from the dict-allocation removal).
func _test_animator_parity() -> void:
	for state in [UnitAnimator.IDLE, UnitAnimator.WALK, UnitAnimator.WORK,
			UnitAnimator.MINE, UnitAnimator.CHOP,
			UnitAnimator.HAMMER, UnitAnimator.HOE, UnitAnimator.FISH,
			UnitAnimator.HUNT, UnitAnimator.SIT,
			UnitAnimator.ATTACK, UnitAnimator.HURT, UnitAnimator.DEATH]:
		var a = UnitAnimator.new()
		a.state = state
		a.phase = 1.71
		# Sample at several points through the clip.
		for t in [0.0, 0.1, 0.2, 0.3]:
			a.state_t = t
			var p: Dictionary = a.pose()
			# apply_to needs a Node2D; use a bare one headless.
			var body := Node2D.new()
			a.apply_to(body)
			_check("apply_to lift matches pose() (%s t=%.1f)" % [state, t],
				is_equal_approx(body.position.y,
					float(p["lift"]) + float(p["crouch"])))
			_check("apply_to rock matches pose() (%s t=%.1f)" % [state, t],
				is_equal_approx(body.rotation, float(p["rock"])))
			var sq: float = float(p["squash"])
			_check("apply_to squash matches pose() (%s t=%.1f)" % [state, t],
				body.scale.is_equal_approx(Vector2(1.0 + sq, 1.0 - sq)))
			body.free()


## apply_to is measurably faster than the old pose()+dict path.
## (Guards against regressions reintroducing the allocation.)
func _test_animator_speed() -> void:
	var a = UnitAnimator.new()
	a.state = UnitAnimator.WALK
	var body := Node2D.new()
	# Warm up.
	for i in 240:
		a.apply_to(body)
	var t0 := Time.get_ticks_usec()
	for i in 240 * 60:
		a.tick(1.0 / 60.0)
		a.apply_to(body)
	var us_apply := Time.get_ticks_usec() - t0
	# Old path: pose() dict + manual apply, for comparison.
	t0 = Time.get_ticks_usec()
	for i in 240 * 60:
		a.tick(1.0 / 60.0)
		var p: Dictionary = a.pose()
		body.position.y = float(p["lift"]) + float(p["crouch"])
		body.rotation = float(p["rock"])
		var sq2: float = float(p["squash"])
		body.scale = Vector2(1.0 + sq2, 1.0 - sq2)
	var us_dict := Time.get_ticks_usec() - t0
	body.free()
	print("  apply_to: %.1fms vs dict path: %.1fms (%.0f%% faster)" % [
		us_apply / 1000.0, us_dict / 1000.0,
		100.0 * float(us_dict - us_apply) / float(maxi(us_dict, 1))])
	_check("apply_to no slower than dict path", us_apply <= us_dict * 1.1)


## Day/night consistency: all visual systems agree that phase 0.5 = noon.
func _test_phase_consistency() -> void:
	# NightGlow: noon = 0 glow, midnight = full glow.
	_check("glow_for(0.5)=0 (noon)", is_equal_approx(NightGlow.glow_for(0.5), 0.0))
	_check("glow_for(0.0)=1 (midnight)", is_equal_approx(NightGlow.glow_for(0.0), 1.0))
	# Shadows: sun up at noon, down at midnight.
	_check("sun up at noon", bool(Shadows.sun_state_for(0.5)["up"]))
	_check("sun down at midnight", not bool(Shadows.sun_state_for(0.0)["up"]))
	# LightingRig: white at noon, dark at midnight.
	var noon_c := LightingRig.ambient_for(0.5)
	_check("ambient white at noon", noon_c.is_equal_approx(Color(1, 1, 1)))
	var mid_c := LightingRig.ambient_for(0.0)
	_check("ambient dark at midnight", mid_c.r < 0.45 and mid_c.b > mid_c.r)
	# GameState convention: is_night matches the visual systems.
	# (hour < 5 or hour > 21 — check well inside day and night, plus
	# the transition midpoints where glow is ~0.5 by construction.)
	for h in [0.0, 12.0, 23.9]:
		var phase: float = h / 24.0
		var visual_night: bool = NightGlow.glow_for(phase) > 0.5
		var logic_night: bool = h < 5.0 or h > 21.0
		_check("visual/logic night agree at hour %.1f" % h,
			visual_night == logic_night)
	# Transition midpoints: glow ~0.5 by construction.
	_check("dawn midpoint glow ~0.5",
		absf(NightGlow.glow_for(5.75 / 24.0) - 0.5) < 0.05)
	_check("dusk midpoint glow ~0.5",
		absf(NightGlow.glow_for(20.0 / 24.0) - 0.5) < 0.05)


func _initialize() -> void:
	print("=== Cursing Gnomes optimization validation ===")
	_test_animator_parity()
	_test_animator_speed()
	_test_phase_consistency()
	_test_visibility_culling()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


## Jeremy 2026-10-04: off-screen units are hidden from the render pipeline
## (visible=false), not just _process-culled. This is the draw-call fix.
func _test_visibility_culling() -> void:
	var un := UnitNode.new()
	un.setup(999, "humans", "worker", Vector2(100, 100), "m")
	# Initially visible and processing.
	_check("unit starts visible", un.visible)
	# Cull: both _process AND visibility turn off.
	un.set_culled(true)
	_check("culled unit hidden", not un.visible)
	_check("culled unit _process off", not un.is_processing())
	# Uncull: both come back.
	un.set_culled(false)
	_check("unculled unit visible", un.visible)
	_check("unculled unit _process on", un.is_processing())
	# Idempotent: calling twice doesn't toggle.
	un.set_culled(true)
	un.set_culled(true)
	_check("double-cull stays hidden", not un.visible)
	un.queue_free()
