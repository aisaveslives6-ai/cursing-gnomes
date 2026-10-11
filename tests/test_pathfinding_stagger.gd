extends SceneTree
## Cursing Gnomes — move_routed validity-stagger tests (2026-10-05 perf R18).
##
## R18 staggers the expensive request_route validity re-check: a full
## check runs when (physics_frame + unit_id) % VALIDITY_STAGGER == 0,
## evenly spread across frames and units. Between checks the stored route
## is reused after a cheap target-change test. Steering, waypoint advance,
## the blocked-cell safety check, stuck detection, and arrival stay
## per-tick. A target change always forces a full check, so chasers
## (moving goals) and re-tasked workers never ride a stale route.
##
## These tests pin the behavior contract:
##   1. stagger_init     — first call checks fully and stores _pf_tgoal.
##   2. stagger_phase    — phase-0 units revalidate; others reuse the route.
##   3. stagger_reuse    — reuse ticks don't recompute the route.
##   4. target_change    — a moved goal forces an immediate full repath.
##   5. arrival          — staggered walking still arrives on open ground.
##   6. midwalk_rebuild  — grid rebuild mid-walk still arrives.
##   7. goal_boundary    — _route_valid honors the 60px goal-moved edge.
##   8. stuck_sentinel   — stuck tracking works via the has() fast path.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes \
##     -s res://tests/test_pathfinding_stagger.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes pathfinding-stagger (R18) tests ===")
	_test_stagger_init()
	_test_stagger_phase()
	_test_stagger_reuse()
	_test_target_change_forces_repath()
	_test_arrival()
	_test_midwalk_rebuild()
	_test_goal_boundary()
	_test_stuck_sentinel()
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


## 16x16 open grass map, all level 1.
func _open_map() -> Dictionary:
	var terrain := PackedByteArray()
	terrain.resize(256)
	var levels := PackedByteArray()
	levels.resize(256)
	for i in 256:
		levels[i] = 1
	return {"terrain": terrain, "levels": levels,
		"size_tiles": Vector2i(16, 16), "tile_size": 32}


func _new_pf(map_data: Dictionary) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = map_data
	var pf := SimPathfinder.new(gs)
	pf.unlimited_budget = true  # headless: frames never advance
	gs.pathfinder = pf
	return {"gs": gs, "pf": pf}


func _free_pf(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _make_unit(uid: int, pos: Vector2) -> Dictionary:
	return {"id": uid, "position": pos, "alive": true, "speed": 55.0}


## Unit id whose stagger phase is `want` at the current physics frame.
func _id_for_phase(want: int) -> int:
	var frame := Engine.get_physics_frames()
	return (want - (frame % 3) + 6) % 3


## 1. First move_routed call performs the full check and stores the goal.
func _test_stagger_init() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var unit := _make_unit(_id_for_phase(1), Vector2(48, 48))
	var target := Vector2(400, 400)
	pf.move_routed(unit, target, 200.0, 0.05)
	_check("init: route computed",
		not (unit.get("_pf_route", {}) as Dictionary).is_empty())
	_check("init: tgoal stored",
		(unit.get("_pf_tgoal", Vector2.ZERO) as Vector2) == target)
	_free_pf(w)


## 2. Phase-0 units revalidate; other phases reuse the stored route.
## Observable: erase the stored route mid-walk — a revalidating unit
## recomputes it on the next call, a reusing unit steers on without one.
func _test_stagger_phase() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var target := Vector2(400, 400)
	var u0 := _make_unit(_id_for_phase(0), Vector2(48, 48))
	var u1 := _make_unit(_id_for_phase(1), Vector2(48, 48))
	pf.move_routed(u0, target, 200.0, 0.05)
	pf.move_routed(u1, target, 200.0, 0.05)
	_check("phase: both routed", not (u0.get("_pf_route", {}) as Dictionary).is_empty()
		and not (u1.get("_pf_route", {}) as Dictionary).is_empty())
	u0.erase("_pf_route")
	u1.erase("_pf_route")
	pf.move_routed(u0, target, 200.0, 0.05)
	pf.move_routed(u1, target, 200.0, 0.05)
	_check("phase: phase-0 unit revalidates (route recomputed)",
		not (u0.get("_pf_route", {}) as Dictionary).is_empty())
	_check("phase: phase-1 unit reuses (no recompute)",
		(u1.get("_pf_route", {}) as Dictionary).is_empty())
	_free_pf(w)


## 3. Reuse ticks keep following the stored route (no recompute churn).
func _test_stagger_reuse() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var unit := _make_unit(_id_for_phase(1), Vector2(48, 48))
	var target := Vector2(400, 400)
	pf.move_routed(unit, target, 200.0, 0.05)
	var r1: Dictionary = unit.get("_pf_route", {})
	var p0: Vector2 = unit["position"]
	pf.move_routed(unit, target, 200.0, 0.05)
	pf.move_routed(unit, target, 200.0, 0.05)
	_check("reuse: same route dict across reuse ticks",
		(unit.get("_pf_route", {}) as Dictionary) == r1)
	_check("reuse: unit still advances",
		(unit["position"] as Vector2).distance_to(p0) > 1.0)
	_free_pf(w)


## 4. A moved goal forces an immediate full repath (chaser safety),
## even on a reuse-phase unit.
func _test_target_change_forces_repath() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var unit := _make_unit(_id_for_phase(1), Vector2(48, 48))
	var t1 := Vector2(400, 400)
	var t2 := Vector2(100, 400)  # > 60px from t1: goal-moved repath
	pf.move_routed(unit, t1, 200.0, 0.05)
	pf.move_routed(unit, t1, 200.0, 0.05)  # reuse tick
	pf.move_routed(unit, t2, 200.0, 0.05)  # goal moved: forced check
	_check("target: tgoal updated",
		(unit.get("_pf_tgoal", Vector2.ZERO) as Vector2) == t2)
	var r: Dictionary = unit.get("_pf_route", {})
	var gx := float(r.get("gx", 0.0))
	var gy := float(r.get("gy", 0.0))
	_check("target: route goal tracks new target",
		Vector2(gx - t2.x, gy - t2.y).length() <= SimPathfinder.GOAL_MOVED_REPATH)
	# The unit must make progress on the new target.
	var d0: float = (unit["position"] as Vector2).distance_to(t2)
	for i in 60:
		pf.move_routed(unit, t2, 200.0, 0.05)
	var d1: float = (unit["position"] as Vector2).distance_to(t2)
	_check("target: unit closes on new target", d1 < d0)
	_free_pf(w)


## 5. Staggered walking still arrives on open ground (both phases).
func _test_arrival() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var target := Vector2(400, 400)
	for uid in [_id_for_phase(0), _id_for_phase(1), _id_for_phase(2)]:
		var unit := _make_unit(uid, Vector2(48, 48))
		var arrived := false
		for i in 300:
			if pf.move_routed(unit, target, 200.0, 0.05):
				arrived = true
				break
		_check("arrival: phase unit arrives", arrived)
		_check("arrival: ends near target",
			(unit["position"] as Vector2).distance_to(target) < 12.0)
	_free_pf(w)


## 6. A nav-grid rebuild mid-walk still arrives under the stagger.
func _test_midwalk_rebuild() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var unit := _make_unit(_id_for_phase(1), Vector2(48, 48))
	var target := Vector2(400, 400)
	var arrived := false
	for i in 300:
		if i == 20:
			pf.mark_dirty()
			pf.sync()  # rebuild mid-walk
		if pf.move_routed(unit, target, 200.0, 0.05):
			arrived = true
			break
	_check("rebuild: arrives despite mid-walk rebuild", arrived)
	_check("rebuild: ends near target",
		(unit["position"] as Vector2).distance_to(target) < 12.0)
	_free_pf(w)


## 7. _route_valid honors the 60px goal-moved edge (squared rewrite parity).
func _test_goal_boundary() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var unit := _make_unit(_id_for_phase(0), Vector2(48, 48))
	var target := Vector2(400, 400)
	var r: Dictionary = pf.request_route(unit, target)
	_check("boundary: route exists", not r.is_empty())
	# Exactly at the edge: still valid.
	var edge := target + Vector2(SimPathfinder.GOAL_MOVED_REPATH, 0.0)
	_check("boundary: 60px drift still valid", pf._route_valid(unit, edge))
	# Just beyond: invalid.
	var over := target + Vector2(SimPathfinder.GOAL_MOVED_REPATH + 1.0, 0.0)
	_check("boundary: 61px drift invalid", not pf._route_valid(unit, over))
	_free_pf(w)


## 8. Stuck tracking works via the has() fast path (no sentinel alloc).
func _test_stuck_sentinel() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var unit := _make_unit(_id_for_phase(0), Vector2(48, 48))
	var pos := Vector2(48, 48)
	# First call: no _pf_last_pos key — initializes without the old default.
	pf._tick_stuck(unit, pos, 0.05, true)
	_check("stuck: last_pos initialized", unit.has("_pf_last_pos"))
	_check("stuck: stuck_t zeroed", float(unit.get("_pf_stuck_t", -1.0)) == 0.0)
	# No progress for 2s: stuck fires, repath counter up.
	for i in 50:
		pf._tick_stuck(unit, pos, 0.05, true)
	_check("stuck: repaths counted", int(unit.get("_pf_repaths", 0)) >= 1)
	# Progress resets the timer.
	pf._tick_stuck(unit, pos + Vector2(50, 0), 0.05, true)
	_check("stuck: progress resets timer",
		float(unit.get("_pf_stuck_t", 99.0)) == 0.0)
	_free_pf(w)
