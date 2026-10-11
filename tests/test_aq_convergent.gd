extends SceneTree
## Cursing Gnomes — convergent adaptive-quality tests.
## Perf 2026-10-04 (graphics-hourly): AQ ping-ponged medium<->low forever on
## marginal devices — degrade when the frame-time EMA blew 22 ms, upgrade
## after 60 s of smooth frames, degrade again. Every step re-sweeps the tree
## budget and rebuilds grass, which on-device reads as fast -> crawl ->
## oscillate (and matches Jeremy's ~5 s cliff: the first degrade fires ~5 s
## after boot once the sim warms the EMA past the threshold).
## The fix: an upgrade followed by a degrade inside AQ_RATCHET_WINDOW proves
## the higher tier unsustainable, so the upgrade ceiling ratchets down and AQ
## converges on the highest sustainable tier instead of oscillating. No tier,
## knob, or feature is removed; manual tier selection still bypasses AQ.
##
## These tests drive world._tick_adaptive_quality with synthetic frame deltas
## on the real booted world scene and assert the governor's decisions. The
## world's own _process/_physics_process are frozen during the synthetic
## phases so real frame deltas can't contaminate the EMA.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_aq_convergent.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _world: World = null
var _frames := 0
var _ran := false


func _initialize() -> void:
	print("=== Cursing Gnomes convergent-AQ tests ===")
	var packed: PackedScene = load("res://scenes/world/world.tscn") as PackedScene
	if packed == null:
		print("  FAIL: could not load world.tscn")
		quit(1)
		return
	_world = packed.instantiate() as World
	root.add_child(_world)
	if _world.has_method("configure"):
		_world.call("configure", "gnomes", "AQTest")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30 or _ran:
		return false  # let the world settle, then run once
	_ran = true
	_world.set_process(false)
	_world.set_physics_process(false)
	_run_all()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
	return false


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## White-box setup: force the AQ state machine into a known configuration.
func _aq_setup(tier: String, boot_tier: String) -> void:
	_world._graphics_mode = "auto"
	_world._boot_tier = boot_tier
	_world._active_tier = tier
	_world._reset_aq_convergence()


func _feed(delta: float, frames: int) -> void:
	for i in range(frames):
		_world._tick_adaptive_quality(delta)


func _run_all() -> void:
	_test_degrade_under_load()
	_test_upgrade_after_sustained_smooth()
	_test_failed_upgrade_ratchets()
	_test_converged_no_pingpong()
	_test_transient_degrade_no_ratchet()
	_test_recovery_after_transient()
	_test_reset()
	_test_low_boot_inert()


## Heavy frames -> EMA blows 22 ms -> step down medium -> low.
func _test_degrade_under_load() -> void:
	_aq_setup("medium", "medium")
	_feed(0.030, 240)
	_check("degrade_under_load: tier steps down to low",
		_world._active_tier == "low")
	_check("degrade_under_load: ceiling untouched by fresh degrade",
		_world._aq_ceil_idx == 2)


## 60 s of smooth frames -> step back up low -> medium (first upgrade is
## always allowed: no failure recorded yet).
func _test_upgrade_after_sustained_smooth() -> void:
	_aq_setup("medium", "medium")
	_feed(0.030, 240)  # -> low
	_check("upgrade_setup: degraded to low", _world._active_tier == "low")
	_feed(0.010, 3700)  # ~37 s synthetic; EMA settles < 14 ms, 3600 smooth frames
	_check("upgrade_after_smooth: tier steps back up to medium",
		_world._active_tier == "medium")
	_check("upgrade_after_smooth: upgrade timestamp recorded",
		_world._aq_upgraded_at >= 0.0)


## Upgrade then immediate re-degrade -> ceiling ratchets below the failed tier.
func _test_failed_upgrade_ratchets() -> void:
	_aq_setup("medium", "medium")
	_feed(0.030, 240)   # -> low
	_feed(0.010, 3700)  # -> medium (upgrade at ~36 s)
	_check("ratchet_setup: upgraded to medium", _world._active_tier == "medium")
	_feed(0.030, 300)   # 9 s later: degrade again, inside the 120 s window
	_check("failed_upgrade_ratchets: tier falls back to low",
		_world._active_tier == "low")
	_check("failed_upgrade_ratchets: ceiling pinned below medium",
		_world._aq_ceil_idx == 3)


## After the ratchet, smooth frames must NOT re-upgrade: no ping-pong.
func _test_converged_no_pingpong() -> void:
	_aq_setup("medium", "medium")
	_feed(0.030, 240)
	_feed(0.010, 3700)
	_feed(0.030, 300)  # ratchet fires; ceiling = 3
	_check("converge_setup: ceiling is 3", _world._aq_ceil_idx == 3)
	_feed(0.010, 4000)  # 40 s of smooth frames: upgrade must stay a no-op
	_check("converged_no_pingpong: tier stays low",
		_world._active_tier == "low")
	_check("converged_no_pingpong: ceiling stays 3",
		_world._aq_ceil_idx == 3)


## A degrade long after an upgrade (transient spike, e.g. a disaster) must
## NOT ratchet: the window distinguishes "tier unsustainable" from noise.
func _test_transient_degrade_no_ratchet() -> void:
	_aq_setup("medium", "medium")
	_world._aq_upgraded_at = 0.0  # upgrade happened at t=0...
	_world._aq_time = 200.0       # ...200 s ago, outside the window
	_feed(0.030, 240)
	_check("transient_degrade: tier steps down to low",
		_world._active_tier == "low")
	_check("transient_degrade_no_ratchet: ceiling stays at boot tier",
		_world._aq_ceil_idx == 2)


## After a transient degrade, sustained smooth frames may still upgrade:
## the governor recovers when conditions genuinely improve.
func _test_recovery_after_transient() -> void:
	_aq_setup("medium", "medium")
	_world._aq_upgraded_at = 0.0
	_world._aq_time = 200.0
	_feed(0.030, 240)  # -> low, no ratchet
	_check("recovery_setup: degraded to low", _world._active_tier == "low")
	_feed(0.010, 4000)
	_check("recovery_after_transient: upgrades back to medium",
		_world._active_tier == "medium")
	_check("recovery_after_transient: ceiling still 2",
		_world._aq_ceil_idx == 2)


## Settings/world reload resets convergence state to the boot tier.
func _test_reset() -> void:
	_world._boot_tier = "medium"
	_world._aq_ceil_idx = 3
	_world._aq_upgraded_at = 50.0
	_world._reset_aq_convergence()
	_check("reset: ceiling returns to boot tier", _world._aq_ceil_idx == 2)
	_check("reset: upgrade memory cleared", _world._aq_upgraded_at < 0.0)
	_check("reset: clock cleared", _world._aq_time == 0.0)
	_check("reset: ema/smooth cleared",
		_world._aq_ema == 0.0 and _world._aq_smooth == 0)
	_world._boot_tier = "low"
	_world._reset_aq_convergence()
	_check("reset: low boot tier gives ceiling 3", _world._aq_ceil_idx == 3)


## Boot tier low: AQ is inert (can't step down or up); nothing crashes.
func _test_low_boot_inert() -> void:
	_aq_setup("low", "low")
	_feed(0.030, 240)
	_check("low_boot: heavy frames keep low", _world._active_tier == "low")
	_feed(0.010, 4000)
	_check("low_boot: smooth frames keep low", _world._active_tier == "low")
	_check("low_boot: ceiling stays 3", _world._aq_ceil_idx == 3)
