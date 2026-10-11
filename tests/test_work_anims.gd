extends SceneTree
## Cursing Gnomes — work animation tests (Jeremy 2026-10-04).
##
## Covers the MINE (pickaxe) and CHOP (axe) UnitAnimator states:
##   - the states exist, are distinct from WORK, and loop (never settle
##     like one-shots)
##   - tool_swing() returns a sane raise->strike->recover arc per cycle
##   - the strike edge fires exactly once per swing loop
##   - UnitNode.set_work_state maps gathering+site-kind to the right state
##     and shows/hides the tool overlay
##   - strike impact FX seeds the spark pool and decays
##   - freeze-position: the swing plays with the node planted
##   - existing states are untouched (death still terminal, one-shots
##     still settle)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_work_anims.gd


## Tool sprites are normal-map wrapped at runtime (SpriteNormals.apply_to),
## so texture-identity checks must unwrap via diffuse_of first.
const SN := preload("res://scripts/world/sprite_normals.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes work animation tests ===")
	_test_state_consts()
	_test_loops_not_settle()
	_test_tool_swing_arc()
	_test_strike_edge_once_per_loop()
	_test_work_state_mapping()
	_test_tool_overlay_visibility()
	_test_strike_fx()
	_test_freeze_position_swing()
	_test_existing_states_untouched()
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
	_check("work: MINE const", UnitAnimator.MINE == "mine")
	_check("work: CHOP const", UnitAnimator.CHOP == "chop")
	_check("work: distinct from WORK",
		UnitAnimator.MINE != UnitAnimator.WORK
		and UnitAnimator.CHOP != UnitAnimator.WORK
		and UnitAnimator.MINE != UnitAnimator.CHOP)
	_check("work: loop lengths sane",
		UnitAnimator.MINE_LEN > 0.5 and UnitAnimator.CHOP_LEN > 0.5)
	_check("work: strike fractions in (0,1)",
		UnitAnimator.MINE_STRIKE_AT > 0.0
		and UnitAnimator.MINE_STRIKE_AT < 1.0
		and UnitAnimator.CHOP_STRIKE_AT > 0.0
		and UnitAnimator.CHOP_STRIKE_AT < 1.0)


## MINE/CHOP loop forever while the unit works; they must NOT settle back
## to idle like ATTACK/HURT do.
func _test_loops_not_settle() -> void:
	for st: String in [UnitAnimator.MINE, UnitAnimator.CHOP]:
		var a := UnitAnimator.for_uid(11)
		a.set_state(st)
		_check("work: %s set" % st, a.state == st)
		for i: int in range(240):  # 4 s at 60 Hz — several swing loops
			a.tick(1.0 / 60.0)
		_check("work: %s loops (no settle)" % st, a.state == st)
		# Loop helpers agree with the constants.
		var expect_len: float = UnitAnimator.MINE_LEN \
			if st == UnitAnimator.MINE else UnitAnimator.CHOP_LEN
		var expect_sf: float = UnitAnimator.MINE_STRIKE_AT \
			if st == UnitAnimator.MINE else UnitAnimator.CHOP_STRIKE_AT
		_check("work: %s loop len helper" % st,
			is_equal_approx(a.work_loop_len(), expect_len))
		_check("work: %s strike frac helper" % st,
			is_equal_approx(a.strike_frac(), expect_sf))
	var idle := UnitAnimator.for_uid(12)
	_check("work: helpers 0/-1 off-swing",
		idle.work_loop_len() == 0.0 and idle.strike_frac() == -1.0)


## The tool arc: raised back (negative angle) early in the loop, swung
## down in front (positive angle) at the strike, and reach extends on hit.
func _test_tool_swing_arc() -> void:
	for st: String in [UnitAnimator.MINE, UnitAnimator.CHOP]:
		var a := UnitAnimator.for_uid(13)
		a.set_state(st)
		var loop_len: float = a.work_loop_len()
		var sf: float = a.strike_frac()
		# Sample near the end of the raise (tool fully back) and exactly
		# at the strike fraction (tool landed, reach extended).
		a.state_t = loop_len * (sf - 0.13)
		var early: Vector2 = a.tool_swing()
		a.state_t = loop_len * sf
		var strike: Vector2 = a.tool_swing()
		_check("work: %s raises back before strike" % st, early.x < -1.0)
		_check("work: %s swings down at strike" % st, strike.x > 0.5)
		_check("work: %s extends reach on strike" % st, strike.y > 1.0)
		# Rest pose for non-swing states.
		var w := UnitAnimator.for_uid(14)
		w.set_state(UnitAnimator.WORK)
		_check("work: tool_swing rest off-swing",
			w.tool_swing() == Vector2(0.35, 0.0))


## Simulate the UnitNode strike-edge logic: exactly one firing per loop.
func _test_strike_edge_once_per_loop() -> void:
	for st: String in [UnitAnimator.MINE, UnitAnimator.CHOP]:
		var a := UnitAnimator.for_uid(15)
		a.set_state(st)
		var loop_len: float = a.work_loop_len()
		var sf: float = a.strike_frac()
		var prev := 0.0
		var fires := 0
		var dt: float = 1.0 / 60.0
		# Fixed frame count (float accumulation makes a time-bound loop
		# run a 136th frame and catch a third edge — boundary flake).
		var frames: int = int(loop_len * 2.5 * 60.0)
		for i: int in range(frames):
			a.tick(dt)
			var cyc: float = fmod(a.state_t, loop_len) / loop_len
			if prev < sf and cyc >= sf:
				fires += 1
			prev = cyc
		_check("work: %s fires twice in 2.5 loops" % st, fires == 2)


## set_work_state maps sim work_state + site kind -> animator state.
func _test_work_state_mapping() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(21, "gnomes", "woodcutter", Vector2(100, 100), "m")
	un.set_work_state("gathering", "tree")
	_check("map: tree -> CHOP", un.anim.state == UnitAnimator.CHOP)
	un.set_work_state("gathering", "rock")
	_check("map: rock -> MINE", un.anim.state == UnitAnimator.MINE)
	un.set_work_state("gathering", "gold_vein")
	_check("map: gold_vein -> MINE", un.anim.state == UnitAnimator.MINE)
	un.set_work_state("gathering", "bush")
	_check("map: bush -> WORK", un.anim.state == UnitAnimator.WORK)
	un.set_work_state("gathering", "")
	_check("map: unknown kind -> WORK", un.anim.state == UnitAnimator.WORK)
	un.set_work_state("building", "")
	_check("map: building -> HAMMER", un.anim.state == UnitAnimator.HAMMER)
	un.set_work_state("idle", "")
	_check("map: idle -> IDLE", un.anim.state == UnitAnimator.IDLE)
	un.set_work_state("to_resource", "")
	_check("map: to_resource -> WALK", un.anim.state == UnitAnimator.WALK)
	un.free()


## The tool overlay shows for MINE/CHOP and hides for everything else.
func _test_tool_overlay_visibility() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(22, "gnomes", "miner", Vector2(100, 100), "m")
	_check("tool: hidden initially", not un._tool_pivot.visible)
	un.set_work_state("gathering", "rock")
	_check("tool: pickaxe visible while mining", un._tool_pivot.visible)
	_check("tool: pickaxe art loaded",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("pickaxe"))
	un.set_work_state("gathering", "tree")
	_check("tool: axe visible while chopping", un._tool_pivot.visible)
	_check("tool: axe art loaded",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("axe"))
	un.set_work_state("to_dropoff", "")
	_check("tool: hidden while hauling", not un._tool_pivot.visible)
	un.set_work_state("gathering", "tree")
	# The swing actually moves the pivot (raise vs strike differ).
	un.anim.state_t = UnitAnimator.CHOP_LEN \
		* (UnitAnimator.CHOP_STRIKE_AT - 0.13)
	un._update_tool(1.0 / 60.0)
	var r1: float = un._tool_pivot.rotation
	un.anim.state_t = UnitAnimator.CHOP_LEN * UnitAnimator.CHOP_STRIKE_AT
	un._update_tool(0.0)
	var r2: float = un._tool_pivot.rotation
	_check("tool: pivot swings", absf(r2 - r1) > 0.5)
	un.free()


## Strike FX: the spark pool seeds on the strike edge and decays.
func _test_strike_fx() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(23, "gnomes", "miner", Vector2(100, 100), "m")
	un.set_work_state("gathering", "rock")
	_check("fx: no sparks before strike", un._spark_life <= 0.0)
	var loop_len: float = UnitAnimator.MINE_LEN
	var sf: float = UnitAnimator.MINE_STRIKE_AT
	# Drive past the strike edge the way _process does.
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
	_check("fx: strike edge reached", fired)
	_check("fx: sparks seeded", un._spark_life > 0.0)
	_check("fx: stone sparks flagged", un._spark_stone)
	var moved := false
	var p0: Vector2 = un._spark_pos[0]
	un._update_tool(0.1)
	if un._spark_pos[0] != p0:
		moved = true
	_check("fx: sparks advance", moved)
	un._update_tool(1.0)
	_check("fx: sparks decay", un._spark_life <= 0.0)
	un.free()


## Freeze-position for swings: the cycle plays with the node planted —
## body bounces vertically only, never shifts horizontally.
func _test_freeze_position_swing() -> void:
	for st: String in [UnitAnimator.MINE, UnitAnimator.CHOP]:
		var un := UnitNode.new()
		root.add_child(un)
		un.setup(24, "gnomes", "woodcutter", Vector2(500, 500), "m")
		un.set_work_state("gathering",
			"tree" if st == UnitAnimator.CHOP else "rock")
		var body: Node2D = un.get_node("Body")
		var lifts: Array[float] = []
		for i: int in range(120):
			un.anim.tick(1.0 / 60.0)
			un.anim.apply_to(body)
			lifts.append(body.position.y)
		_check("freeze %s: node position fixed" % st,
			un.position == Vector2(500, 500))
		_check("freeze %s: body never shifts horizontally" % st,
			body.position.x == 0.0)
		_check("freeze %s: swing cycle actually plays" % st,
			lifts.max() - lifts.min() > 1.0)
		un.free()


## New states must not disturb the old ones.
func _test_existing_states_untouched() -> void:
	var a := UnitAnimator.for_uid(25)
	a.set_state(UnitAnimator.ATTACK)
	for i: int in range(40):
		a.tick(1.0 / 60.0)
	_check("regression: attack still settles", a.state == UnitAnimator.IDLE)
	a.set_state(UnitAnimator.DEATH)
	a.set_state(UnitAnimator.MINE)
	_check("regression: death still terminal", a.state == UnitAnimator.DEATH)
	a.set_state(UnitAnimator.CHOP)
	_check("regression: death uninterruptible by chop",
		a.state == UnitAnimator.DEATH)
	# WORK still loops (never settles).
	var w := UnitAnimator.for_uid(26)
	w.set_state(UnitAnimator.WORK)
	for i: int in range(240):
		w.tick(1.0 / 60.0)
	_check("regression: work still loops", w.state == UnitAnimator.WORK)
