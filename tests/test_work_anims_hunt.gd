extends SceneTree
## Cursing Gnomes — HUNT work-loop animation tests.
## (Jeremy 2026-10-06 animation pass: hunters stalk/strike/recover with the
## spear on the sim's HUNT_CD cadence — a dedicated loop instead of walking
## in place at the prey. The sim already set work_pose "attack"; the world
## layer used to drop it and map "hunting" to WALK.)
##
## Covers:
##   - HUNT state consts, loop length (= sim HUNT_CD), strike fraction
##   - the loop keeps looping (no settle), like MINE/CHOP/HAMMER/HOE/FISH
##   - tool_swing() returns a coil -> strike -> recover arc per cycle
##   - the strike edge fires exactly once per swing loop
##   - set_work_state maps hunting -> HUNT, to_prey -> WALK; equipped tool
##     wins, no tool -> pivot hidden (never a white box)
##   - strike impact FX flavor: the kill blow -> blood flecks
##   - freeze-position: the stalk/strike cycle plays with the node planted
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_work_anims_hunt.gd


## Tool sprites are normal-map wrapped at runtime (SpriteNormals.apply_to),
## so texture-identity checks must unwrap via diffuse_of first.
const SN := preload("res://scripts/world/sprite_normals.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hunt work-animation tests ===")
	_test_state_consts()
	_test_loop_not_settle()
	_test_tool_swing_arc()
	_test_strike_edge_once_per_loop()
	_test_work_state_mapping()
	_test_strike_flavor()
	_test_freeze_position_swing()
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
	_check("hunt: HUNT const", UnitAnimator.HUNT == "hunt")
	_check("hunt: state distinct",
		UnitAnimator.HUNT != UnitAnimator.WORK
		and UnitAnimator.HUNT != UnitAnimator.WALK
		and UnitAnimator.HUNT != UnitAnimator.FISH
		and UnitAnimator.HUNT != UnitAnimator.ATTACK)
	_check("hunt: loop length sane", UnitAnimator.HUNT_LEN > 0.5)
	_check("hunt: loop matches sim strike cadence (HUNT_CD 1.0s)",
		is_equal_approx(UnitAnimator.HUNT_LEN, 1.0))
	_check("hunt: strike fraction in (0,1)",
		UnitAnimator.HUNT_STRIKE_AT > 0.0
		and UnitAnimator.HUNT_STRIKE_AT < 1.0)


## The loop runs forever (never settles to idle), like the other work loops.
func _test_loop_not_settle() -> void:
	var a := UnitAnimator.for_uid(61)
	a.set_state(UnitAnimator.HUNT)
	for i: int in range(400):
		a.tick(1.0 / 60.0)
	_check("hunt: keeps looping", a.state == UnitAnimator.HUNT)
	_check("hunt: loop len helper",
		is_equal_approx(a.work_loop_len(), UnitAnimator.HUNT_LEN))
	_check("hunt: strike frac helper",
		is_equal_approx(a.strike_frac(), UnitAnimator.HUNT_STRIKE_AT))


## The weapon coils back low during the stalk, whips forward at the strike,
## and eases home on recovery.
func _test_tool_swing_arc() -> void:
	var a := UnitAnimator.for_uid(62)
	a.set_state(UnitAnimator.HUNT)
	var loop_len: float = a.work_loop_len()
	var sf: float = a.strike_frac()
	a.state_t = loop_len * 0.20  # mid-stalk: coiling
	var stalk: Vector2 = a.tool_swing()
	_check("hunt: weapon coils back while stalking", stalk.x < -0.6)
	a.state_t = loop_len * (sf - 0.02)  # the blow landing
	var strike: Vector2 = a.tool_swing()
	_check("hunt: weapon whips forward at the strike", strike.x > 0.0)
	_check("hunt: weapon reaches the prey", strike.y > 6.0)
	a.state_t = loop_len * 0.97  # recovered
	var rest: Vector2 = a.tool_swing()
	_check("hunt: weapon recovers near rest angle", absf(rest.x + 0.5) < 0.3)
	_check("hunt: weapon reeled back in", rest.y < 1.0)


## Simulate the UnitNode strike-edge logic: exactly one firing per loop.
func _test_strike_edge_once_per_loop() -> void:
	var a := UnitAnimator.for_uid(63)
	a.set_state(UnitAnimator.HUNT)
	var loop_len: float = a.work_loop_len()
	var sf: float = a.strike_frac()
	var prev := 0.0
	var fires := 0
	var dt: float = 1.0 / 60.0
	var frames: int = int(loop_len * 2.5 * 60.0)
	for i: int in range(frames):
		a.tick(dt)
		var cyc: float = fmod(a.state_t, loop_len) / loop_len
		if prev < sf and cyc >= sf:
			fires += 1
		prev = cyc
	_check("hunt: fires twice in 2.5 loops", fires == 2)


## set_work_state maps sim work_state -> the new animator states.
func _test_work_state_mapping() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(64, "gnomes", "hunter", Vector2(100, 100), "m")
	un.set_work_state("hunting", "")
	_check("hunt: hunting -> HUNT", un.anim.state == UnitAnimator.HUNT)
	un._update_tool(1.0 / 60.0)
	_check("hunt: no tool -> pivot hidden (never a white box)",
		un._tool_pivot.visible == false)
	un.set_work_state("hunting", "", "axe")
	_check("hunt: equipped tool wins over the empty fallback",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("axe"))
	un.set_work_state("to_prey", "")
	_check("hunt: to_prey still walks", un.anim.state == UnitAnimator.WALK)
	un.free()


## Strike FX flavor: the kill blow throws blood flecks (not wood/stone/dust).
func _test_strike_flavor() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(65, "gnomes", "hunter", Vector2(100, 100), "m")
	un.set_work_state("hunting", "")
	var loop_len: float = un.anim.work_loop_len()
	var sf: float = un.anim.strike_frac()
	var prev := 0.0
	var dt: float = 1.0 / 60.0
	var fired := false
	while not fired and un.anim.state_t < loop_len * 1.5:
		un.anim.tick(dt)
		un._update_tool(dt)
		var cyc: float = fmod(un.anim.state_t, loop_len) / loop_len
		if prev < sf and cyc >= sf:
			fired = true
		prev = cyc
	_check("hunt: strike edge reached", fired)
	_check("hunt: blood flavor seeded", un._spark_flavor == 4)
	_check("hunt: not the stone flag", un._spark_stone == false)
	un.free()


## Freeze-position: the stalk/strike cycle plays with the node planted —
## body moves vertically only, never shifts horizontally.
func _test_freeze_position_swing() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(66, "gnomes", "hunter", Vector2(500, 500), "m")
	un.set_work_state("hunting", "")
	var body: Node2D = un.get_node("Body")
	var lifts: Array[float] = []
	for i: int in range(120):
		un.anim.tick(1.0 / 60.0)
		un.anim.apply_to(body)
		lifts.append(body.position.y)
	_check("freeze hunt: node position fixed", un.position == Vector2(500, 500))
	_check("freeze hunt: body never shifts horizontally", body.position.x == 0.0)
	_check("freeze hunt: stalk/strike cycle actually plays",
		lifts.max() - lifts.min() > 1.0)
	un.free()
