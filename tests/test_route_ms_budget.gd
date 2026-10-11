extends SceneTree
## Cursing Gnomes — route-compute ms-budget tests.
## Perf 2026-10-04 (4-hour pass): the route projection budget was
## count-based (ROUTES_PER_TICK = 6). A cold A* on a blocked map costs
## ~9ms on desktop (more on iPhone), so one frame could burn 50ms+
## computing 6 routes back-to-back — a systemic frame spike. This ports
## the HTML source of truth's time budget (fix79 index.html:
## ROUTE_MS_PER_TICK = 4, "max ms per tick spent projecting routes
## (iPhone-safe)"): the budget gates A* projection only, shared-cache
## hits stay free, and the queue drains while ms remain.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_route_ms_budget.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes route ms-budget tests ===")
	_test_cache_hit_is_free()
	_test_over_budget_queues()
	_test_ms_accumulates_on_compute()
	_test_drain_respects_budget()
	_test_budget_reset_on_new_frame()
	_test_unlimited_budget()
	_test_queued_unit_eventually_routed()
	_test_routing_core_untouched()
	_test_drain_invariant()
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


## Realistic blocked map: dense town clusters force real A* work.
func _make_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0,
		"size_tiles": Vector2i(128, 128), "tile_size": 32}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	var towns := [Vector2(800, 800), Vector2(3300, 800), Vector2(800, 3300),
		Vector2(3300, 3300), Vector2(2048, 2048)]
	for ti in towns.size():
		for i in 60:
			gs.buildings.append({"type": "house", "faction": "humans",
				"position": towns[ti] + Vector2(rng.randf_range(-400, 400),
				rng.randf_range(-400, 400)), "alive": true, "complete": true})
	var pf := SimPathfinder.new(gs)
	gs.pathfinder = pf
	return {"gs": gs, "pf": pf}


func _make_unit(id: int, pos: Vector2) -> Dictionary:
	return {"id": id, "faction": "humans", "job": "worker", "position": pos,
		"alive": true, "hp": 100.0, "max_hp": 100.0, "speed": 95.0}


func _far_target(i: int) -> Vector2:
	# Distinct far destinations (avoid shared-cache hits between units).
	return Vector2(3200.0 + float(i % 7) * 90.0, 3200.0 + float(i / 7) * 90.0)


## HTML parity: shared-cache hits consume ZERO budget even when the ms
## budget is exhausted.
func _test_cache_hit_is_free() -> void:
	var w := _make_world()
	var pf: SimPathfinder = w["pf"]
	var u := _make_unit(1, Vector2(300, 300))
	var t := _far_target(0)
	var r1: Dictionary = pf.request_route(u, t)
	_check("cache_free: first compute returns a route", not r1.is_empty())
	u.erase("_pf_route")  # force re-request, keep the shared cache warm
	pf._route_ms_this_tick = 999.0  # simulate an exhausted budget
	var r2: Dictionary = pf.request_route(u, t)
	_check("cache_free: exhausted budget still serves cache hit",
		not r2.is_empty())
	_check("cache_free: cache hit consumed no budget",
		pf._route_ms_this_tick == 999.0)
	_check("cache_free: cache hit did not queue", pf._route_queue.is_empty())
	(w["gs"] as GameState).queue_free()


## Over budget, a novel route queues (steer-direct meanwhile) instead of
## burning a 9ms A* in this frame.
func _test_over_budget_queues() -> void:
	var w := _make_world()
	var pf: SimPathfinder = w["pf"]
	var u := _make_unit(2, Vector2(300, 300))
	pf._budget_frame = Engine.get_process_frames()  # pin: no lazy reset
	pf._route_ms_this_tick = 999.0
	var r: Dictionary = pf.request_route(u, _far_target(3))
	_check("over_budget: returns {} (steer direct meanwhile)", r.is_empty())
	_check("over_budget: unit queued", pf._route_queue.size() == 1)
	_check("over_budget: queued unit has no route yet",
		(u.get("_pf_route", {}) as Dictionary).is_empty())
	(w["gs"] as GameState).queue_free()


## Real A* work accrues against the ms budget.
func _test_ms_accumulates_on_compute() -> void:
	var w := _make_world()
	var pf: SimPathfinder = w["pf"]
	var u := _make_unit(4, Vector2(300, 300))
	var r: Dictionary = pf.request_route(u, _far_target(5))
	_check("ms_accrue: route computed", not r.is_empty())
	_check("ms_accrue: budget consumed", pf._route_ms_this_tick > 0.0)
	(w["gs"] as GameState).queue_free()


## Queue drain stops once the ms budget is exhausted — one cold route per
## frame max on slow machines, never a 6-route 50ms pileup.
func _test_drain_respects_budget() -> void:
	var w := _make_world()
	var pf: SimPathfinder = w["pf"]
	var units: Array = []
	for i in 3:
		var u := _make_unit(10 + i, Vector2(300.0 + float(i) * 400.0, 300.0))
		units.append(u)
		pf._queue_request(u, _far_target(20 + i))
	_check("drain: 3 queued", pf._route_queue.size() == 3)
	pf._route_ms_this_tick = 999.0
	pf._drain_queue()
	_check("drain: exhausted budget drains nothing", pf._route_queue.size() == 3)
	pf._route_ms_this_tick = 0.0
	pf._drain_queue()
	# First compute blows past the 4ms budget, so the drain stops after it.
	_check("drain: stopped at budget (1 of 3 computed)",
		pf._route_queue.size() == 2)
	_check("drain: drained unit got its route",
		not (units[0].get("_pf_route", {}) as Dictionary).is_empty())
	_check("drain: budget recorded", pf._route_ms_this_tick >= 4.0)
	(w["gs"] as GameState).queue_free()


## A new process frame resets the ms budget and re-drains.
func _test_budget_reset_on_new_frame() -> void:
	var w := _make_world()
	var pf: SimPathfinder = w["pf"]
	pf._route_ms_this_tick = 999.0
	pf._budget_frame = -999  # force the "new frame" path
	pf._frame_reset_if_needed()
	_check("reset: ms cleared on new frame", pf._route_ms_this_tick == 0.0)
	(w["gs"] as GameState).queue_free()


## unlimited_budget (tests): no gate, no accounting, full drain.
func _test_unlimited_budget() -> void:
	var w := _make_world()
	var pf: SimPathfinder = w["pf"]
	pf.unlimited_budget = true
	for i in 3:
		pf._queue_request(_make_unit(30 + i, Vector2(300.0 + float(i) * 400.0, 300.0)),
			_far_target(40 + i))
	pf._route_ms_this_tick = 999.0
	pf._drain_queue()
	_check("unlimited: queue fully drained", pf._route_queue.is_empty())
	_check("unlimited: no ms accounting", pf._route_ms_this_tick == 999.0)
	var u := _make_unit(99, Vector2(300, 300))
	var r: Dictionary = pf.request_route(u, _far_target(60))
	_check("unlimited: immediate compute ignores budget", not r.is_empty())
	(w["gs"] as GameState).queue_free()


## End-to-end: a queued unit gets its route on a later drain.
func _test_queued_unit_eventually_routed() -> void:
	var w := _make_world()
	var pf: SimPathfinder = w["pf"]
	var u := _make_unit(50, Vector2(300, 300))
	pf._budget_frame = Engine.get_process_frames()  # pin: no lazy reset
	pf._route_ms_this_tick = 999.0
	_check("queued_e2e: queued, not routed",
		pf.request_route(u, _far_target(70)).is_empty())
	pf._route_ms_this_tick = 0.0
	pf._frame_reset_if_needed()  # no frame change: no reset, no drain
	_check("queued_e2e: still queued before drain", pf._route_queue.size() == 1)
	pf._drain_queue()
	var r: Dictionary = u.get("_pf_route", {})
	_check("queued_e2e: unit routed after drain", not r.is_empty())
	_check("queued_e2e: route has waypoints",
		(r.get("wps", PackedVector2Array()) as PackedVector2Array).size() >= 2)
	(w["gs"] as GameState).queue_free()


## The routing CORE is untouched: request_route returns exactly what a
## direct (ungated) compute produces for the same inputs.
func _test_routing_core_untouched() -> void:
	var w := _make_world()
	var pf: SimPathfinder = w["pf"]
	pf.unlimited_budget = true
	var t := _far_target(80)
	var u1 := _make_unit(60, Vector2(300, 300))
	var u2 := _make_unit(61, Vector2(300, 300))
	var via_request: Dictionary = pf.request_route(u1, t)
	u2.erase("_pf_route")
	var via_direct: Dictionary = pf._compute_route(u2, t, true)
	var w1: PackedVector2Array = via_request.get("wps", PackedVector2Array())
	var w2: PackedVector2Array = via_direct.get("wps", PackedVector2Array())
	_check("core: same waypoint count", w1.size() == w2.size() and w1.size() >= 2)
	var same := w1.size() == w2.size()
	if same:
		for i in w1.size():
			if w1[i].distance_to(w2[i]) > 0.001:
				same = false
				break
	_check("core: identical waypoints", same)
	_check("core: identical goal stamp",
		float(via_request.get("gx", -1.0)) == float(via_direct.get("gx", -2.0))
		and float(via_request.get("gy", -1.0)) == float(via_direct.get("gy", -2.0)))
	(w["gs"] as GameState).queue_free()


## Machine-independent invariant: after a drain, either the queue is
## empty or the ms budget is exhausted — never a mid-frame pileup.
func _test_drain_invariant() -> void:
	var w := _make_world()
	var pf: SimPathfinder = w["pf"]
	for i in 6:
		pf._queue_request(_make_unit(70 + i, Vector2(250.0 + float(i) * 350.0, 250.0)),
			_far_target(90 + i))
	pf._route_ms_this_tick = 0.0
	pf._drain_queue()
	var ok: bool = pf._route_queue.is_empty() \
		or pf._route_ms_this_tick >= SimPathfinder.ROUTE_MS_PER_TICK
	_check("drain_invariant: queue empty or budget exhausted", ok)
	(w["gs"] as GameState).queue_free()
