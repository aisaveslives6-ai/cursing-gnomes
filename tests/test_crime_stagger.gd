extends SceneTree
## Cursing Gnomes — R17 crime-global stagger tests (2026-10-05).
##
## Perf R17: SimCrimeLife.tick_global ran three full unit scans every frame
## (0.68ms/f, the #1 sim hotspot post-R15). It now runs every 3rd frame
## (20Hz): guard dispatch, jail release, and trial pacing. These tests pin
## the stagger contract:
##   - dispatch fires on the 3rd tick_global, not the 1st/2nd
##   - dispatch outcome is identical to a direct _dispatch_guards() call
##   - no double-dispatch across consecutive dispatch ticks
##   - jail release still flows through tick_global (3 calls)
##   - live-trial phase timing is preserved via the scaled delta
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_crime_stagger.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes crime-stagger (R17) tests ===")
	_test_stagger_cadence()
	_test_dispatch_parity()
	_test_no_double_dispatch()
	_test_release_through_global()
	_test_trial_timing_preserved()
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


## --- harness (mirrors test_crime_life.gd) -------------------------------------

func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.towns[1] = {"id": 1, "name": "Town0", "faction": "humans",
		"pos": Vector2.ZERO, "owner": "humans"}
	for r: String in ["gold", "food", "wood", "oil"]:
		gs.resources.add_resource("humans", r, 10000.0, true)
	var mind := SimMind.new(gs)
	var court := SimRoyalCourt.new(gs)
	var life: SimCrimeLife = court.crime.life
	gs.add_building({"type": "jail", "faction": "humans", "town_id": 1,
		"position": Vector2(200, 0), "alive": true, "complete": true,
		"progress": 1.0, "hp": 700.0, "max_hp": 700.0})
	gs.add_building({"type": "courthouse", "faction": "humans", "town_id": 1,
		"position": Vector2(-200, 0), "alive": true, "complete": true,
		"progress": 1.0, "hp": 900.0, "max_hp": 900.0})
	return {"gs": gs, "mind": mind, "court": court, "life": life,
		"crime": court.crime}


func _spawn(w: Dictionary, job: String, pos: Vector2 = Vector2(100, 100)) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit("humans", job, 1, pos)
	mind.ensure(u)
	return u


func _make_wanted(w: Dictionary) -> Array:
	var life: SimCrimeLife = w["life"]
	var crime = w["crime"]
	var guard: Dictionary = _spawn(w, "guard", Vector2(30, 0))
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	var rec: Dictionary = crime.ensure_rec(crook)
	(rec["c55"] as Dictionary)["wanted"] = true
	return [guard, crook]


## --- tests --------------------------------------------------------------------

func _test_stagger_cadence() -> void:
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var pair: Array = _make_wanted(w)
	var guard: Dictionary = pair[0]
	var d := 1.0 / 60.0
	life.tick_global(d)
	_check("no dispatch on 1st tick_global",
		String(guard.get("crime_phase", "")) == "")
	life.tick_global(d)
	_check("no dispatch on 2nd tick_global",
		String(guard.get("crime_phase", "")) == "")
	life.tick_global(d)
	_check("dispatch on 3rd tick_global",
		String(guard.get("crime_phase", "")) == "guard_hunt")
	_check("suspect hunted on 3rd tick_global",
		String((pair[1] as Dictionary).get("crime_phase", "")) == "hunted")


func _test_dispatch_parity() -> void:
	# Same world state, direct _dispatch_guards() vs tick_global x3:
	# identical assignment.
	var w1: Dictionary = _new_world()
	var w2: Dictionary = _new_world()
	seed(77)
	var p1: Array = _make_wanted(w1)
	seed(77)
	var p2: Array = _make_wanted(w2)
	(w1["life"] as SimCrimeLife)._dispatch_guards()
	var life2: SimCrimeLife = w2["life"]
	var d := 1.0 / 60.0
	life2.tick_global(d)
	life2.tick_global(d)
	life2.tick_global(d)
	_check("parity: guard phase",
		String((p1[0] as Dictionary).get("crime_phase", "")) \
		== String((p2[0] as Dictionary).get("crime_phase", "")))
	_check("parity: suspect phase",
		String((p1[1] as Dictionary).get("crime_phase", "")) \
		== String((p2[1] as Dictionary).get("crime_phase", "")))
	_check("parity: guard target",
		int((p1[0] as Dictionary).get("crime_target", -1)) \
		== int((p2[0] as Dictionary).get("crime_target", -1)))


func _test_no_double_dispatch() -> void:
	# Two guards, one crook: the second dispatch tick must not reassign
	# the already-handled suspect to the free guard.
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var pair: Array = _make_wanted(w)
	var guard2: Dictionary = _spawn(w, "guard", Vector2(-30, 0))
	var d := 1.0 / 60.0
	for i: int in range(6):
		life.tick_global(d)
	_check("first guard hunting",
		String((pair[0] as Dictionary).get("crime_phase", "")) == "guard_hunt")
	_check("second guard NOT double-dispatched",
		String(guard2.get("crime_phase", "")) == "")


func _test_release_through_global() -> void:
	# A jailed unit whose record is cleared gets released via tick_global
	# (needs 3 calls to reach a dispatch tick).
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var life: SimCrimeLife = w["life"]
	var crime = w["crime"]
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	var rec: Dictionary = crime.ensure_rec(crook)
	life._jail_unit(crook, false)
	_check("jailed", String(crook.get("crime_phase", "")) == "jailed")
	# Simulate time served: clear the jail record.
	rec["jailedUntil"] = -1.0
	var d := 1.0 / 60.0
	life.tick_global(d)
	life.tick_global(d)
	_check("still jailed before dispatch tick",
		String(crook.get("crime_phase", "")) == "jailed")
	life.tick_global(d)
	_check("released on dispatch tick",
		String(crook.get("crime_phase", "")) == "")


func _test_trial_timing_preserved() -> void:
	# Live trial phase clock advances by 3*delta per dispatch tick —
	# identical pacing to per-frame delta.
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var life: SimCrimeLife = w["life"]
	var crime = w["crime"]
	var accused: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	# Trial cast needs townsfolk (judge/jury/...) — mirror test_crime_life.
	for i: int in 15:
		_spawn(w, "worker", Vector2(20 + i * 8, 20))
	var rec: Dictionary = crime.ensure_rec(accused)
	var c55: Dictionary = rec["c55"]
	c55["awaitingTrial"] = true
	c55["trialDay"] = int(crime.state["day"])
	rec["jailedUntil"] = float(crime.state["day"]) + 1.2
	life._jail_unit(accused, false)
	seed(3)
	life._start_due_trials()
	_check("live trial started", bool(c55.get("trial_live", false)))
	var trial: Dictionary = c55["trial"]
	var d := 1.0 / 60.0
	# Two skip frames: clock must not advance.
	life.tick_global(d)
	life.tick_global(d)
	_check("trial clock frozen on skip frames",
		is_equal_approx(float(trial.get("t", -1.0)), 0.0))
	# Dispatch tick: clock advances by 3*delta.
	life.tick_global(d)
	_check("trial clock advances 3*delta on dispatch tick",
		is_equal_approx(float(trial.get("t", 0.0)), 3.0 * d))
