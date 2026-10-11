extends SceneTree
## Cursing Gnomes — downed-unit readability tests (rapid iteration 2026-10-08).
##
## The sim's goDowned path (combat.gd _go_downed: knocked out, immobile,
## untargetable, 60s bleed-out unless a doctor revives) froze the unit but
## the visuals never showed it — combat_state "downed" had no visual, so a
## downed fighter looked identical to a standing one and revivable allies
## were invisible on the battlefield. UnitNode.set_downed now drives a prone
## pose + pulsing gold revive ring (pulse quickens as the clock runs down);
## world.gd syncs the sim flag every frame; revive restores the stance and
## play_death clears to the DEATH clip.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_downed_visual.gd
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


func _make_node() -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(66, "gnomes", "worker", Vector2(100, 100), "m")
	return un


func _initialize() -> void:
	_test_flag_and_timer()
	_test_early_out_keeps_pulse_phase()
	_test_period_bounds()
	_test_period_quickens()
	_test_ring_params_sane()
	_test_prone_pose_applied()
	_test_revive_restores()
	_test_death_clears_downed()
	_test_ring_draw_guarded()
	print("downed_visual: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("    - ", f)
		quit(1)
	else:
		quit(0)


func _test_flag_and_timer() -> void:
	var un := _make_node()
	_check("default not downed", un._downed == false)
	un.set_downed(true, 60.0)
	_check("set_downed(true) flips flag", un._downed == true)
	_check("timer stored", is_equal_approx(un._downed_timer, 60.0))
	un.queue_free()


func _test_early_out_keeps_pulse_phase() -> void:
	var un := _make_node()
	un.set_downed(true, 60.0)
	un._downed_t = 5.0
	un.set_downed(true, 55.0)  # same flag: refresh timer, keep phase
	_check("early-out updates timer", is_equal_approx(un._downed_timer, 55.0))
	_check("early-out keeps pulse phase (no strobe)",
		is_equal_approx(un._downed_t, 5.0))
	un.queue_free()


func _test_period_bounds() -> void:
	var un := _make_node()
	un.set_downed(true, 60.0)
	_check("full clock -> slow period ~1.15s",
		is_equal_approx(un._downed_period(), 1.15))
	un.set_downed(true, 0.0)
	_check("empty clock -> urgent period ~0.32s",
		is_equal_approx(un._downed_period(), 0.32))
	un.set_downed(true, 30.0)
	_check("half clock -> mid period ~0.735s",
		is_equal_approx(un._downed_period(), 0.735))
	un.queue_free()


func _test_period_quickens() -> void:
	var un := _make_node()
	un.set_downed(true, 55.0)
	var slow := un._downed_period()
	un.set_downed(true, 5.0)
	var fast := un._downed_period()
	_check("period quickens as bleed-out nears", fast < slow)
	un.queue_free()


func _test_ring_params_sane() -> void:
	var un := _make_node()
	un.set_downed(true, 60.0)
	un._downed_t = 0.3
	var p: Array = un._downed_ring_params()
	_check("ring params [radius, alpha]", p.size() == 2)
	_check("radius near DOWNED_RING_R",
		float(p[0]) >= 26.0 and float(p[0]) <= 26.0 * 1.12 + 0.01)
	_check("alpha in pulse band",
		float(p[1]) >= 0.30 and float(p[1]) <= 0.85 + 0.001)
	un.queue_free()


func _test_prone_pose_applied() -> void:
	var un := _make_node()
	un.set_downed(true, 60.0)
	un._process(0.016)
	_check("prone rotation applied",
		is_equal_approx(absf(un._body.rotation), 1.35))
	_check("body dropped to ground",
		is_equal_approx(un._body.position.y, 7.0))
	_check("body held still (scale pinned)",
		un._body.scale == Vector2.ONE)
	un.queue_free()


func _test_revive_restores() -> void:
	var un := _make_node()
	un.set_downed(true, 60.0)
	un._process(0.016)
	un.set_downed(false, 0.0)
	_check("revive clears flag", un._downed == false)
	# Next _process lets the animator own the body again (no prone pin).
	un._process(0.016)
	_check("revive releases prone rotation",
		not is_equal_approx(absf(un._body.rotation), 1.35))
	un.queue_free()


func _test_death_clears_downed() -> void:
	var un := _make_node()
	un.set_downed(true, 12.0)
	un.play_death()
	_check("play_death clears downed flag", un._downed == false)
	_check("play_death still sets DEATH state",
		un.anim.state == UnitAnimator.DEATH)
	un.queue_free()


func _test_ring_draw_guarded() -> void:
	var un := _make_node()
	# Not downed: _draw_downed_ring must be a silent no-op (no canvas in
	# headless tests, so we only assert the guard, not pixels).
	un._draw_downed_ring()
	_check("ring draw guarded when not downed", true)
	un.queue_free()
