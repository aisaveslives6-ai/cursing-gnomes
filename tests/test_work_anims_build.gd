extends SceneTree
## Cursing Gnomes — HAMMER + HOE work-loop animation tests.
## (Jeremy 2026-10-05 animation pass: builders swing the smith's hammer,
## farmers till with the hoe — dedicated loops instead of the generic
## WORK bob, with strike impact FX on the tool's landing edge.)
##
## Covers:
##   - HAMMER/HOE state consts, loop lengths, strike fractions
##   - loops keep looping (no settle), like MINE/CHOP
##   - tool_swing() returns a sane raise->strike->recover arc per cycle
##   - the strike edge fires exactly once per swing loop
##   - set_work_state maps building/repairing -> HAMMER, tending/plot_chore -> HOE
##   - hammer/hoe tool art loads; equipped tool wins over the fallback
##   - strike impact FX flavor: hammer -> wood chips, hoe -> soil dust
##   - freeze-position: swing cycles play with the node planted
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_work_anims_build.gd


## Tool sprites are normal-map wrapped at runtime (SpriteNormals.apply_to),
## so texture-identity checks must unwrap via diffuse_of first.
const SN := preload("res://scripts/world/sprite_normals.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hammer/hoe work-animation tests ===")
	_test_state_consts()
	_test_loops_not_settle()
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
	_check("build: HAMMER const", UnitAnimator.HAMMER == "hammer")
	_check("build: HOE const", UnitAnimator.HOE == "hoe")
	_check("build: states distinct",
		UnitAnimator.HAMMER != UnitAnimator.HOE
		and UnitAnimator.HAMMER != UnitAnimator.MINE
		and UnitAnimator.HOE != UnitAnimator.CHOP
		and UnitAnimator.HAMMER != UnitAnimator.WORK)
	_check("build: loop lengths sane",
		UnitAnimator.HAMMER_LEN > 0.5 and UnitAnimator.HOE_LEN > 0.5)
	_check("build: strike fractions in (0,1)",
		UnitAnimator.HAMMER_STRIKE_AT > 0.0
		and UnitAnimator.HAMMER_STRIKE_AT < 1.0
		and UnitAnimator.HOE_STRIKE_AT > 0.0
		and UnitAnimator.HOE_STRIKE_AT < 1.0)


## Loops run forever (never settle to idle), like MINE/CHOP.
func _test_loops_not_settle() -> void:
	for st: String in [UnitAnimator.HAMMER, UnitAnimator.HOE]:
		var a := UnitAnimator.for_uid(41)
		a.set_state(st)
		for i: int in range(400):
			a.tick(1.0 / 60.0)
		_check("build: %s keeps looping" % st, a.state == st)
		var expect_len: float = UnitAnimator.HAMMER_LEN \
			if st == UnitAnimator.HAMMER else UnitAnimator.HOE_LEN
		var expect_sf: float = UnitAnimator.HAMMER_STRIKE_AT \
			if st == UnitAnimator.HAMMER else UnitAnimator.HOE_STRIKE_AT
		_check("build: %s loop len helper" % st,
			is_equal_approx(a.work_loop_len(), expect_len))
		_check("build: %s strike frac helper" % st,
			is_equal_approx(a.strike_frac(), expect_sf))


## The tool raises back (negative angle) before the strike, swings
## down in front (positive angle) at the strike, and reach extends on hit.
func _test_tool_swing_arc() -> void:
	for st: String in [UnitAnimator.HAMMER, UnitAnimator.HOE]:
		var a := UnitAnimator.for_uid(42)
		a.set_state(st)
		var loop_len: float = a.work_loop_len()
		var sf: float = a.strike_frac()
		a.state_t = loop_len * (sf - 0.15)
		var early: Vector2 = a.tool_swing()
		a.state_t = loop_len * sf
		var strike: Vector2 = a.tool_swing()
		_check("build: %s raises back before strike" % st, early.x < -1.0)
		_check("build: %s swings down at strike" % st, strike.x > 0.5)
		_check("build: %s extends reach on strike" % st, strike.y > 1.0)
		# Rest pose for non-swing states.
		var w := UnitAnimator.for_uid(43)
		w.set_state(UnitAnimator.WORK)
		_check("build: tool_swing rest off-swing",
			w.tool_swing() == Vector2(0.35, 0.0))


## Simulate the UnitNode strike-edge logic: exactly one firing per loop.
func _test_strike_edge_once_per_loop() -> void:
	for st: String in [UnitAnimator.HAMMER, UnitAnimator.HOE]:
		var a := UnitAnimator.for_uid(44)
		a.set_state(st)
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
		_check("build: %s fires twice in 2.5 loops" % st, fires == 2)


## set_work_state maps sim work_state -> the new animator states.
func _test_work_state_mapping() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(45, "gnomes", "builder", Vector2(100, 100), "m")
	un.set_work_state("building", "")
	_check("build: building -> HAMMER", un.anim.state == UnitAnimator.HAMMER)
	_check("build: hammer art loaded",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("hammer"))
	un.set_work_state("repairing", "")
	_check("build: repairing -> HAMMER", un.anim.state == UnitAnimator.HAMMER)
	un.set_work_state("building", "", "axe")
	_check("build: equipped tool wins over hammer fallback",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("axe"))
	un.set_work_state("healing", "")
	_check("build: healing stays WORK", un.anim.state == UnitAnimator.WORK)
	un.free()

	var fu := UnitNode.new()
	root.add_child(fu)
	fu.setup(46, "gnomes", "farmer", Vector2(200, 200), "f")
	fu.set_work_state("tending", "")
	_check("build: tending -> HOE", fu.anim.state == UnitAnimator.HOE)
	_check("build: hoe art loaded",
		SN.diffuse_of(fu._tool_sprite.texture) == Art.tool_texture("hoe"))
	fu.set_work_state("plot_chore", "")
	_check("build: plot_chore -> HOE", fu.anim.state == UnitAnimator.HOE)
	fu.set_work_state("tending", "", "fishingrod")
	_check("build: equipped tool wins over hoe fallback",
		SN.diffuse_of(fu._tool_sprite.texture) == Art.tool_texture("fishingrod"))
	fu.free()


## Strike FX flavor: hammer -> wood chips, hoe -> soil dust,
## pickaxe stays stone sparks.
func _test_strike_flavor() -> void:
	for data: Array in [
			["building", "", "builder", 0, false],
			["tending", "", "farmer", 2, false],
			["gathering", "rock", "miner", 1, true]]:
		var un := UnitNode.new()
		root.add_child(un)
		un.setup(47, "gnomes", String(data[2]), Vector2(100, 100), "m")
		un.set_work_state(String(data[0]), String(data[1]))
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
		_check("build: %s strike edge reached" % data[0], fired)
		_check("build: %s flavor seeded" % data[0],
			un._spark_flavor == int(data[3]))
		_check("build: %s stone flag" % data[0],
			un._spark_stone == bool(data[4]))
		un.free()


## Freeze-position for swings: the cycle plays with the node planted —
## body bounces vertically only, never shifts horizontally.
func _test_freeze_position_swing() -> void:
	for data: Array in [
			[UnitAnimator.HAMMER, "building", "builder"],
			[UnitAnimator.HOE, "tending", "farmer"]]:
		var un := UnitNode.new()
		root.add_child(un)
		un.setup(48, "gnomes", String(data[2]), Vector2(500, 500), "m")
		un.set_work_state(String(data[1]), "")
		var body: Node2D = un.get_node("Body")
		var lifts: Array[float] = []
		for i: int in range(120):
			un.anim.tick(1.0 / 60.0)
			un.anim.apply_to(body)
			lifts.append(body.position.y)
		_check("freeze %s: node position fixed" % String(data[0]),
			un.position == Vector2(500, 500))
		_check("freeze %s: body never shifts horizontally" % String(data[0]),
			body.position.x == 0.0)
		_check("freeze %s: swing cycle actually plays" % String(data[0]),
			lifts.max() - lifts.min() > 1.0)
		un.free()
