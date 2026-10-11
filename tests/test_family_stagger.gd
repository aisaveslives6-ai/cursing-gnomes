extends SceneTree
## Cursing Gnomes — family movement stagger tests (optimization round R19).
##
## Verifies the 20 Hz movement-sweep stagger in SimFamily.tick: the sweep runs
## on every 3rd physics frame with a 3x-scaled delta, so walker speed, arrival
## timing and child wander probabilities are unchanged.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_family_stagger.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

const DELTA := 1.0 / 60.0

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes family movement-stagger tests ===")
	_test_sweep_cadence()
	_test_delta_parity()
	_test_arrival_clears_flag()
	_test_busy_yields()
	_test_child_sweep_scaled()
	_test_roll_scaling_math()
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


func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var fam := SimFamily.new(gs)
	return [gs, fam]


func _walker(gs: GameState, fam: SimFamily, pos: Vector2, target: Vector2) -> Dictionary:
	var u := gs.add_unit({"faction": "humans", "job": "worker", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 30.0, "gender": "m", "is_worker": true, "work_state": "idle"})
	fam.ensure(u)
	u["family_walking"] = true
	u["family_walk"] = target
	return u


# --- stagger ----------------------------------------------------------------

func _test_sweep_cadence() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _walker(gs, fam, Vector2(0, 0), Vector2(300, 0))
	fam.tick(DELTA)
	_check("stagger: no move on tick 1", Vector2(u["position"]).x == 0.0)
	fam.tick(DELTA)
	_check("stagger: no move on tick 2", Vector2(u["position"]).x == 0.0)
	fam.tick(DELTA)
	_check("stagger: moves on tick 3", Vector2(u["position"]).x > 0.0)
	_check("stagger: still walking (300px away)", bool(u["family_walking"]))


func _test_delta_parity() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _walker(gs, fam, Vector2(0, 0), Vector2(300, 0))
	for i in range(3):
		fam.tick(DELTA)
	# Old behavior: 3 frames x speed*delta = 30 * 3/60 = 1.5px.
	_check("stagger: 3 ticks move exactly 1.5px",
		absf(Vector2(u["position"]).x - 1.5) < 0.0001)


func _test_arrival_clears_flag() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _walker(gs, fam, Vector2(295, 0), Vector2(300, 0))
	for i in range(3):
		fam.tick(DELTA)
	_check("stagger: arrival (< 12px) clears family_walking",
		not bool(u["family_walking"]))


func _test_busy_yields() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _walker(gs, fam, Vector2(0, 0), Vector2(300, 0))
	u["fleeing"] = true
	for i in range(3):
		fam.tick(DELTA)
	_check("stagger: busy unit yields (family_walking cleared)",
		not bool(u["family_walking"]))


func _test_child_sweep_scaled() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _walker(gs, fam, Vector2(0, 0), Vector2(300, 0))
	u["is_child"] = true
	for i in range(3):
		fam.tick(DELTA)
	# Child speed = 30 * 0.7, one sweep of delta*3: 21 * 0.05 = 1.05px.
	_check("stagger: child sweep moves 1.05px",
		absf(Vector2(u["position"]).x - 1.05) < 0.0001)


func _test_roll_scaling_math() -> void:
	var w := _make_world()
	var fam: SimFamily = w[1]
	# _roll(p, 3/60) must compound the per-frame probability 3 times:
	# expected per-sweep rate = 1 - (1-0.004)^3 ~= 0.011952.
	var n := 20000
	var hits := 0
	for i in range(n):
		if fam._roll(0.004, 3.0 * DELTA):
			hits += 1
	var rate := float(hits) / float(n)
	_check("stagger: _roll(0.004, 3/60) rate ~= 0.01195 (3x compound)",
		rate > 0.008 and rate < 0.016)
	# Sanity: the single-frame roll is ~0.004, proving the sweep step scales it.
	var hits1 := 0
	for i in range(n):
		if fam._roll(0.004, DELTA):
			hits1 += 1
	var rate1 := float(hits1) / float(n)
	_check("stagger: _roll(0.004, 1/60) rate ~= 0.004",
		rate1 > 0.002 and rate1 < 0.006)
