extends SceneTree
## Cursing Gnomes — R26 crime-dispatch guard-index tests (2026-10-05).
##
## Perf R26: SimCrimeLife._dispatch_guards ran _nearest_free_guard (a full
## O(units) scan) once per wanted suspect — O(wanted x units), probe-verified
## at ~187us per wanted suspect at 222 units (5 wanted = 1.28ms/dispatch).
## It now builds a free-guard index in one pass; each suspect scans only
## that list. These tests pin the behavior contract:
##   - nearest free guard is assigned (old _nearest_free_guard semantics)
##   - distance ties break first-in-units-order (strict <)
##   - one guard serves one suspect per dispatch (no double-assignment)
##   - already-pursued suspects are skipped (handled set)
##   - busy guards (any crime_phase) are not in the free pool
##   - foreign-faction guards are never assigned to player suspects
##   - non-wanted / jailed / trial-phase suspects are skipped
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_crime_dispatch_index.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes crime-dispatch-index (R26) tests ===")
	_test_nearest_guard_assigned()
	_test_tie_break_units_order()
	_test_no_double_assignment()
	_test_handled_suspect_skipped()
	_test_busy_guard_excluded()
	_test_foreign_guard_excluded()
	_test_non_wanted_skipped()
	_test_jailed_suspect_skipped()
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


## --- harness (mirrors test_crime_stagger.gd) -----------------------------------

func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	gs.towns[1] = {"id": 1, "name": "Town0", "faction": "humans",
		"pos": Vector2.ZERO, "owner": "humans"}
	for r: String in ["gold", "food", "wood", "oil"]:
		gs.resources.add_resource("humans", r, 10000.0, true)
		gs.resources.add_resource("ogres", r, 10000.0, true)
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


func _spawn(w: Dictionary, job: String, pos: Vector2,
		faction: String = "humans") -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, job, 1, pos)
	mind.ensure(u)
	return u


func _want(w: Dictionary, u: Dictionary) -> void:
	var rec: Dictionary = (w["crime"] as SimCrime).ensure_rec(u)
	(rec.get("c55", {}) as Dictionary)["wanted"] = true


## --- tests ---------------------------------------------------------------------

func _test_nearest_guard_assigned() -> void:
	# Two free guards; the nearer one must take the hunt (old
	# _nearest_free_guard semantics: argmin of distance_squared).
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var far: Dictionary = _spawn(w, "guard", Vector2(500, 0))
	var near: Dictionary = _spawn(w, "guard", Vector2(40, 0))
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_want(w, crook)
	life._dispatch_guards()
	_check("nearest guard hunts",
		String(near.get("crime_phase", "")) == "guard_hunt")
	_check("nearest guard targets the crook",
		int(near.get("crime_target", -1)) == int(crook.get("id", 0)))
	_check("far guard stays free",
		String(far.get("crime_phase", "")) == "")
	_check("crook is hunted",
		String(crook.get("crime_phase", "")) == "hunted")


func _test_tie_break_units_order() -> void:
	# Equidistant guards: strict < keeps the first-in-units-order winner,
	# exactly like the old full scan.
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var first: Dictionary = _spawn(w, "guard", Vector2(100, 0))
	var second: Dictionary = _spawn(w, "guard", Vector2(-100, 0))
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_want(w, crook)
	life._dispatch_guards()
	_check("tie: first-spawned guard hunts",
		String(first.get("crime_phase", "")) == "guard_hunt")
	_check("tie: second guard stays free",
		String(second.get("crime_phase", "")) == "")


func _test_no_double_assignment() -> void:
	# One guard, two wanted crooks: the guard takes the first in units
	# order; the second crook waits (guard left the free pool this
	# dispatch — the old scan skipped it via crime_phase != "").
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var guard: Dictionary = _spawn(w, "guard", Vector2(30, 0))
	var crook1: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	var crook2: Dictionary = _spawn(w, "worker", Vector2(10, 0))
	_want(w, crook1)
	_want(w, crook2)
	life._dispatch_guards()
	_check("guard hunts first crook",
		int(guard.get("crime_target", -1)) == int(crook1.get("id", 0)))
	_check("second crook not hunted this dispatch",
		String(crook2.get("crime_phase", "")) == "")


func _test_handled_suspect_skipped() -> void:
	# A suspect already pursued by a busy guard is in the handled set and
	# must not be reassigned to the free guard.
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var busy: Dictionary = _spawn(w, "guard", Vector2(400, 0))
	var free: Dictionary = _spawn(w, "guard", Vector2(35, 0))
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_want(w, crook)
	busy["crime_phase"] = "guard_hunt"
	busy["crime_target"] = int(crook.get("id", 0))
	life._dispatch_guards()
	_check("handled suspect not reassigned",
		String(free.get("crime_phase", "")) == "")
	_check("crook phase untouched by dispatch",
		String(crook.get("crime_phase", "")) == "")


func _test_busy_guard_excluded() -> void:
	# A guard mid-escort (crime_phase set) is not in the free pool; the
	# other guard takes the hunt.
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var busy: Dictionary = _spawn(w, "guard", Vector2(20, 0))
	var free: Dictionary = _spawn(w, "guard", Vector2(60, 0))
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_want(w, crook)
	busy["crime_phase"] = "guard_escort"
	busy["crime_target"] = 999
	life._dispatch_guards()
	_check("busy guard not assigned",
		String(busy.get("crime_phase", "")) == "guard_escort")
	_check("free guard hunts instead",
		String(free.get("crime_phase", "")) == "guard_hunt")


func _test_foreign_guard_excluded() -> void:
	# An ogre guard is never dispatched against a human suspect (the old
	# scan filtered by the suspect's faction).
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var ogre_guard: Dictionary = _spawn(w, "guard", Vector2(25, 0), "ogres")
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_want(w, crook)
	life._dispatch_guards()
	_check("foreign guard not assigned",
		String(ogre_guard.get("crime_phase", "")) == "")
	_check("crook unhunted with no human guard",
		String(crook.get("crime_phase", "")) == "")


func _test_non_wanted_skipped() -> void:
	# A civilian with a crime record but wanted=false gets no hunter.
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var guard: Dictionary = _spawn(w, "guard", Vector2(30, 0))
	var civ: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	var rec: Dictionary = (w["crime"] as SimCrime).ensure_rec(civ)
	(rec.get("c55", {}) as Dictionary)["wanted"] = false
	life._dispatch_guards()
	_check("non-wanted civilian ignored",
		String(guard.get("crime_phase", "")) == "")
	_check("civilian phase untouched",
		String(civ.get("crime_phase", "")) == "")


func _test_jailed_suspect_skipped() -> void:
	# A wanted but jailed suspect is not dispatched against.
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var crime: SimCrime = w["crime"]
	var guard: Dictionary = _spawn(w, "guard", Vector2(30, 0))
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_want(w, crook)
	crook["crime_phase"] = "jailed"
	# is_jailed(uid): rec.jailedUntil > state.day.
	var rec: Dictionary = crime.ensure_rec(crook)
	rec["jailedUntil"] = float((crime.state as Dictionary).get("day", 0)) + 5.0
	life._dispatch_guards()
	_check("jailed suspect not dispatched",
		String(guard.get("crime_phase", "")) == "")
