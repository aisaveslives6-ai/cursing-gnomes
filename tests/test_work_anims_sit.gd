extends SceneTree
## Cursing Gnomes — SIT work-loop animation tests.
## (Jeremy 2026-10-06 animation pass: the sim's work_pose channel was wired
## through the world sync — desk workers ("working" + pose "sit") play a
## seated desk-work loop instead of standing at their desks, and arrived
## off-shift resters ("off_shift" + pose "rest") idle-breathe at home
## instead of walking in place. The world layer used to drop work_pose.)
##
## Covers:
##   - SIT state consts, SIT_LEN, distinct from WORK/WALK/IDLE
##   - the loop keeps looping (no settle), seated read (body lowered,
##     leaning toward the desk), seamless wrap
##   - set_work_state maps working+sit -> SIT (tool hidden), working+use ->
##     WORK, off_shift+rest -> IDLE, off_shift -> WALK, travel states ignore
##     a stale sit pose
##   - SIT has no strike edge (no phantom impact FX)
##   - freeze-position: the desk-work cycle plays with the node planted
##   - SIT rides the weight-scaled loop clock
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_work_anims_sit.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes sit work-animation tests ===")
	_test_state_consts()
	_test_loop_not_settle()
	_test_seated_read()
	_test_wrap_continuity()
	_test_work_state_mapping()
	_test_no_strike_edge()
	_test_freeze_position()
	_test_loop_clock()
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


func _test_state_consts() -> void:
	_check("sit: SIT const", UnitAnimator.SIT == "sit")
	_check("sit: state distinct",
		UnitAnimator.SIT != UnitAnimator.WORK
		and UnitAnimator.SIT != UnitAnimator.WALK
		and UnitAnimator.SIT != UnitAnimator.IDLE)
	_check("sit: SIT_LEN 1.6 s", is_equal_approx(UnitAnimator.SIT_LEN, 1.6))


func _test_loop_not_settle() -> void:
	# A moving hold, never frozen: lift and rock vary across the loop.
	var a := UnitAnimator.new()
	a.state = UnitAnimator.SIT
	a.phase = 1.71
	var lifts: Array[float] = []
	var rocks: Array[float] = []
	for i in 12:
		a.state_t = float(i) / 12.0 * UnitAnimator.SIT_LEN
		var p: Dictionary = a.pose()
		lifts.append(float(p["lift"]))
		rocks.append(float(p["rock"]))
	_check("sit: lift varies (typing bursts, never frozen)",
		lifts.max() - lifts.min() > 0.3)
	_check("sit: rock varies (lean rhythm)",
		rocks.max() - rocks.min() > 0.05)


func _test_seated_read() -> void:
	# Seated = body lowered onto the chair and leaning toward the desk.
	var a := UnitAnimator.new()
	a.state = UnitAnimator.SIT
	a.phase = 1.71
	var crouch_sum := 0.0
	var rock_sum := 0.0
	var n := 16
	for i in n:
		a.state_t = float(i) / float(n) * UnitAnimator.SIT_LEN
		var p: Dictionary = a.pose()
		crouch_sum += float(p["crouch"])
		rock_sum += float(p["rock"])
	_check("sit: body stays lowered (crouch mean > 4)",
		crouch_sum / float(n) > 4.0)
	_check("sit: leans toward the desk (rock mean > 0.05)",
		rock_sum / float(n) > 0.05)


func _test_wrap_continuity() -> void:
	# The loop must wrap without a pop: adjacent samples across the wrap
	# boundary stay close.
	var a := UnitAnimator.new()
	a.state = UnitAnimator.SIT
	a.phase = 1.71
	a.state_t = 0.02
	var p0: Dictionary = a.pose()
	a.state_t = UnitAnimator.SIT_LEN - 0.02
	var p1: Dictionary = a.pose()
	_check("sit: wrap lift continuous",
		absf(float(p1["lift"]) - float(p0["lift"])) < 1.0)
	_check("sit: wrap rock continuous",
		absf(float(p1["rock"]) - float(p0["rock"])) < 0.08)
	_check("sit: wrap crouch continuous",
		absf(float(p1["crouch"]) - float(p0["crouch"])) < 1.0)


func _test_work_state_mapping() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(66, "gnomes", "clerk", Vector2(100, 100), "m")
	un.set_work_state("working", "", "", "sit")
	_check("sit: working+sit -> SIT", un.anim.state == UnitAnimator.SIT)
	un._update_tool(1.0 / 60.0)
	_check("sit: seated -> tool hidden (never a white box)",
		un._tool_pivot.visible == false)
	un.set_work_state("working", "", "axe", "use")
	_check("sit: working+use -> WORK (counter/bar rhythm)",
		un.anim.state == UnitAnimator.WORK)
	un.set_work_state("working", "", "hammer")
	_check("sit: working (no pose) -> WORK (forge/site unchanged)",
		un.anim.state == UnitAnimator.WORK)
	un.set_work_state("extinguishing", "", "", "sit")
	_check("sit: extinguishing ignores sit pose -> WORK",
		un.anim.state == UnitAnimator.WORK)
	un.set_work_state("off_shift", "", "", "rest")
	_check("sit: off_shift+rest -> IDLE (breathes at home)",
		un.anim.state == UnitAnimator.IDLE)
	un.set_work_state("off_shift", "", "")
	_check("sit: off_shift walking -> WALK", un.anim.state == UnitAnimator.WALK)
	un.set_work_state("to_station", "", "", "sit")
	_check("sit: stale sit pose on a travel state -> WALK",
		un.anim.state == UnitAnimator.WALK)
	un.free()


func _test_no_strike_edge() -> void:
	# SIT is a hold loop, not a swing: no impact FX may fire.
	var a := UnitAnimator.new()
	a.state = UnitAnimator.SIT
	_check("sit: work_loop_len 0 (no swing)", a.work_loop_len() == 0.0)
	_check("sit: strike_frac -1 (no strike edge)", a.strike_frac() == -1.0)


func _test_freeze_position() -> void:
	# The desk-work cycle plays with the node planted — body moves
	# vertically only, never shifts horizontally.
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(67, "gnomes", "clerk", Vector2(100, 100), "m")
	un.set_work_state("working", "", "", "sit")
	var body := Node2D.new()
	root.add_child(body)
	var ok := true
	for i in 16:
		un.anim.state_t = float(i) / 16.0 * UnitAnimator.SIT_LEN
		un.anim.apply_to(body)
		if body.position.x != 0.0:
			ok = false
	_check("sit: freeze-position (no horizontal body shift)", ok)
	body.free()
	un.free()


func _test_loop_clock() -> void:
	# SIT is a loop state: it rides the weight-scaled clock (heavy bodies
	# sit-work slower), like the other work loops.
	var a := UnitAnimator.new()
	a.state = UnitAnimator.SIT
	a.weight = 2.0
	a.tick(1.0)
	_check("sit: weight-scaled loop clock", is_equal_approx(a.state_t, 0.5))
