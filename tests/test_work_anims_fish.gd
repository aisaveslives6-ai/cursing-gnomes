extends SceneTree
## Cursing Gnomes — FISH work-loop animation tests.
## (Jeremy 2026-10-06 animation pass: fishers cast/wait/yank with the rod —
## a dedicated loop on the sim's catch cadence instead of walking in place
## at the lake; firefighters and station workers keep the WORK rhythm.)
##
## Covers:
##   - FISH state consts, loop length (= sim FISH_TICK), strike fraction
##   - the loop keeps looping (no settle), like MINE/CHOP/HAMMER/HOE
##   - tool_swing() returns a cast -> wait -> yank -> recover arc per cycle
##   - the strike edge fires exactly once per swing loop
##   - set_work_state maps fishing -> FISH, extinguishing/working -> WORK
##   - fishingrod art loads; equipped tool wins over the fallback
##   - strike impact FX flavor: fishing yank -> splash
##   - freeze-position: the cast/yank cycle plays with the node planted
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_work_anims_fish.gd


## Tool sprites are normal-map wrapped at runtime (SpriteNormals.apply_to),
## so texture-identity checks must unwrap via diffuse_of first.
const SN := preload("res://scripts/world/sprite_normals.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes fish work-animation tests ===")
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
	_check("fish: FISH const", UnitAnimator.FISH == "fish")
	_check("fish: state distinct",
		UnitAnimator.FISH != UnitAnimator.WORK
		and UnitAnimator.FISH != UnitAnimator.WALK
		and UnitAnimator.FISH != UnitAnimator.HOE)
	_check("fish: loop length sane", UnitAnimator.FISH_LEN > 0.5)
	_check("fish: loop matches sim catch cadence (FISH_TICK 1.1s)",
		is_equal_approx(UnitAnimator.FISH_LEN, 1.1))
	_check("fish: strike fraction in (0,1)",
		UnitAnimator.FISH_STRIKE_AT > 0.0
		and UnitAnimator.FISH_STRIKE_AT < 1.0)


## The loop runs forever (never settles to idle), like MINE/CHOP/HAMMER/HOE.
func _test_loop_not_settle() -> void:
	var a := UnitAnimator.for_uid(51)
	a.set_state(UnitAnimator.FISH)
	for i: int in range(400):
		a.tick(1.0 / 60.0)
	_check("fish: keeps looping", a.state == UnitAnimator.FISH)
	_check("fish: loop len helper",
		is_equal_approx(a.work_loop_len(), UnitAnimator.FISH_LEN))
	_check("fish: strike frac helper",
		is_equal_approx(a.strike_frac(), UnitAnimator.FISH_STRIKE_AT))


## The rod casts forward (reach grows), holds with a tremble, then yanks
## back over the shoulder at the strike and recovers to rest.
func _test_tool_swing_arc() -> void:
	var a := UnitAnimator.for_uid(52)
	a.set_state(UnitAnimator.FISH)
	var loop_len: float = a.work_loop_len()
	var sf: float = a.strike_frac()
	a.state_t = loop_len * 0.14  # mid-cast
	var cast: Vector2 = a.tool_swing()
	_check("fish: cast swings forward", cast.x > 0.35)
	_check("fish: cast extends the line", cast.y > 2.0)
	a.state_t = loop_len * 0.55  # waiting, line out
	var wait: Vector2 = a.tool_swing()
	_check("fish: rod held forward while waiting", wait.x > 0.8)
	_check("fish: line fully out while waiting", wait.y > 10.0)
	a.state_t = loop_len * (sf + 0.10)  # yank snapping back
	var yank: Vector2 = a.tool_swing()
	_check("fish: yank snaps the rod back", yank.x < 0.5)
	a.state_t = loop_len * 0.97  # recovered
	var rest: Vector2 = a.tool_swing()
	_check("fish: rod recovers near rest angle", absf(rest.x - 0.35) < 0.3)
	_check("fish: line reeled back in", rest.y < 3.0)


## Simulate the UnitNode strike-edge logic: exactly one firing per loop.
func _test_strike_edge_once_per_loop() -> void:
	var a := UnitAnimator.for_uid(53)
	a.set_state(UnitAnimator.FISH)
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
	_check("fish: fires twice in 2.5 loops", fires == 2)


## set_work_state maps sim work_state -> the new animator states.
func _test_work_state_mapping() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(54, "gnomes", "fisher", Vector2(100, 100), "m")
	un.set_work_state("fishing", "")
	_check("fish: fishing -> FISH", un.anim.state == UnitAnimator.FISH)
	_check("fish: fishingrod art loaded",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("fishingrod"))
	un.set_work_state("fishing", "", "axe")
	_check("fish: equipped tool wins over rod fallback",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("axe"))
	un.set_work_state("extinguishing", "")
	_check("fish: extinguishing -> WORK", un.anim.state == UnitAnimator.WORK)
	un.set_work_state("working", "")
	_check("fish: working -> WORK", un.anim.state == UnitAnimator.WORK)
	un.set_work_state("to_lake", "")
	_check("fish: to_lake still walks", un.anim.state == UnitAnimator.WALK)
	un.free()


## Strike FX flavor: the fishing yank pops a splash (not wood/stone/dust).
func _test_strike_flavor() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(55, "gnomes", "fisher", Vector2(100, 100), "m")
	un.set_work_state("fishing", "")
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
	_check("fish: strike edge reached", fired)
	_check("fish: splash flavor seeded", un._spark_flavor == 3)
	_check("fish: not the stone flag", un._spark_stone == false)
	un.free()


## Freeze-position: the cast/yank cycle plays with the node planted —
## body moves vertically only, never shifts horizontally.
func _test_freeze_position_swing() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(56, "gnomes", "fisher", Vector2(500, 500), "m")
	un.set_work_state("fishing", "")
	var body: Node2D = un.get_node("Body")
	var lifts: Array[float] = []
	for i: int in range(120):
		un.anim.tick(1.0 / 60.0)
		un.anim.apply_to(body)
		lifts.append(body.position.y)
	_check("freeze fish: node position fixed", un.position == Vector2(500, 500))
	_check("freeze fish: body never shifts horizontally", body.position.x == 0.0)
	_check("freeze fish: cast/yank cycle actually plays",
		lifts.max() - lifts.min() > 1.0)
	un.free()
