extends SceneTree
## Cursing Gnomes — work-site spatial grid tests (perf 2026-10-05).
##
## WorkerAI._nearest_site used to be a full O(N) scan over every work site
## (~600 us at 753 sites), fired on every civilian task pick. It now uses
## an append-only spatial grid with expanding-ring queries and an exact
## stopping rule. These tests prove the grid returns IDENTICAL results to
## the old linear scan (nearest match, lowest-id tie-break, kind + amount
## filters, empty result) across randomized layouts, depletion, incremental
## growth, and grid rebuilds.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_work_site_grid.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes work-site grid tests ===")
	_test_matches_brute_force_random()
	_test_tie_break_lowest_id()
	_test_depleted_skipped()
	_test_kind_filter()
	_test_no_match_empty()
	_test_miss_cache_invalidated_by_new_sites()
	_test_incremental_growth()
	_test_rebuild_after_clear()
	_test_rebuild_after_setup()
	_test_empty_grid()
	_test_grid_synced_count()
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


func _new_wai() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var wai: WorkerAI = WorkerAI.new(gs)
	return [gs, wai]


## The OLD linear-scan algorithm, kept here as the reference oracle.
func _brute(gs: GameState, pos: Vector2, kinds: Array[String]) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for s: Dictionary in gs.work_sites:
		if float(s.get("amount", 0.0)) <= 0.0:
			continue
		if not String(s.get("kind", "")) in kinds:
			continue
		var d: float = pos.distance_to(s.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = s
	return best


func _same_site(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() and b.is_empty():
		return true
	if a.is_empty() or b.is_empty():
		return false
	return int(a.get("id", -1)) == int(b.get("id", -2))


func _add(gs: GameState, kind: String, x: float, y: float,
		amount: float = 60.0) -> Dictionary:
	return gs.add_work_site({"kind": kind, "position": Vector2(x, y),
		"amount": amount})


func _test_matches_brute_force_random() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005
	var kinds_pool: Array[String] = ["tree", "rock", "gold_vein", "bush",
		"wood_pile"]
	# 400 scattered sites across a 4096px map.
	for i in 400:
		var k: String = kinds_pool[rng.randi_range(0, 4)]
		var amt := 60.0
		if rng.randf() < 0.25:
			amt = 0.0  # some depleted
		_add(gs, k, rng.randf_range(0.0, 4096.0), rng.randf_range(0.0, 4096.0), amt)
	var queries: Array = [
		["tree", "wood_pile"],
		["rock", "gold_vein"],
		["bush"],
		["tree", "rock", "gold_vein", "bush"],
		["gold_vein"],
	]
	var mismatches := 0
	for qi in 60:
		var pos := Vector2(rng.randf_range(0.0, 4096.0),
			rng.randf_range(0.0, 4096.0))
		var qk: Array = queries[qi % queries.size()]
		var kinds: Array[String] = []
		for k in qk:
			kinds.append(k)
		var unit := {"position": pos}
		var got: Dictionary = wai._nearest_site(unit, kinds)
		var want: Dictionary = _brute(gs, pos, kinds)
		if not _same_site(got, want):
			mismatches += 1
	_check("random: grid matches brute force (60 queries x 5 kind-sets)",
		mismatches == 0)
	gs.queue_free()


func _test_tie_break_lowest_id() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	# Two trees exactly equidistant from the unit; lower id must win
	# (matches the old first-match array order).
	var s1 := _add(gs, "tree", 100.0, 0.0)
	var s2 := _add(gs, "tree", -100.0, 0.0)
	_check("tie setup: s1 id < s2 id", int(s1["id"]) < int(s2["id"]))
	var got: Dictionary = wai._nearest_site({"position": Vector2.ZERO},
		["tree"] as Array[String])
	_check("tie: lowest id wins", int(got.get("id", -1)) == int(s1["id"]))
	gs.queue_free()


func _test_depleted_skipped() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	_add(gs, "tree", 10.0, 0.0, 0.0)  # depleted, closest
	var far := _add(gs, "tree", 500.0, 0.0, 60.0)
	var got: Dictionary = wai._nearest_site({"position": Vector2.ZERO},
		["tree"] as Array[String])
	_check("depleted: skipped for live site",
		int(got.get("id", -1)) == int(far["id"]))
	gs.queue_free()


func _test_kind_filter() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	_add(gs, "rock", 10.0, 0.0)  # wrong kind, closest
	var tree := _add(gs, "tree", 400.0, 0.0)
	var got: Dictionary = wai._nearest_site({"position": Vector2.ZERO},
		["tree"] as Array[String])
	_check("kind filter respected",
		int(got.get("id", -1)) == int(tree["id"]))
	gs.queue_free()


func _test_no_match_empty() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	_add(gs, "rock", 10.0, 0.0)
	var got: Dictionary = wai._nearest_site({"position": Vector2.ZERO},
		["bush"] as Array[String])
	_check("no match: empty dict", got.is_empty())
	gs.queue_free()


func _test_miss_cache_invalidated_by_new_sites() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	_add(gs, "rock", 10.0, 0.0)
	var kinds: Array[String] = ["bush"]
	# First query misses (and populates the miss cache).
	_check("miss cache: first query empty",
		wai._nearest_site({"position": Vector2.ZERO}, kinds).is_empty())
	# Second query also misses — served from cache, still correct.
	_check("miss cache: repeat query empty",
		wai._nearest_site({"position": Vector2(3000, 3000)}, kinds).is_empty())
	# A new matching site invalidates the cache.
	var bush := _add(gs, "bush", 50.0, 0.0)
	var got: Dictionary = wai._nearest_site({"position": Vector2.ZERO}, kinds)
	_check("miss cache: new site found after invalidation",
		int(got.get("id", -1)) == int(bush["id"]))
	gs.queue_free()


func _test_incremental_growth() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 50:
		_add(gs, "tree", rng.randf_range(0, 2000), rng.randf_range(0, 2000))
	# Query between growth spurts; grid must stay exact.
	var mismatches := 0
	for round_i in 5:
		for i in 30:
			_add(gs, "rock", rng.randf_range(0, 2000), rng.randf_range(0, 2000))
		for qi in 10:
			var pos := Vector2(rng.randf_range(0, 2000),
				rng.randf_range(0, 2000))
			var kinds: Array[String] = ["tree", "rock"]
			var got: Dictionary = wai._nearest_site({"position": pos}, kinds)
			if not _same_site(got, _brute(gs, pos, kinds)):
				mismatches += 1
	_check("incremental growth: exact across 5 growth rounds",
		mismatches == 0)
	gs.queue_free()


func _test_rebuild_after_clear() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	_add(gs, "tree", 10.0, 0.0)
	_check("rebuild: pre-clear finds site",
		not wai._nearest_site({"position": Vector2.ZERO},
			["tree"] as Array[String]).is_empty())
	# Simulate the save-load wholesale replacement (the production path):
	# clear + re-append, then rebuild_lookup_indexes() bumps the version.
	gs.work_sites.clear()
	var far := _add(gs, "tree", 3000.0, 3000.0)
	gs.rebuild_lookup_indexes()
	var got: Dictionary = wai._nearest_site({"position": Vector2.ZERO},
		["tree"] as Array[String])
	_check("rebuild: post-load finds only the new site",
		int(got.get("id", -1)) == int(far["id"]))
	gs.queue_free()


func _test_rebuild_after_setup() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	_add(gs, "tree", 10.0, 0.0)
	_check("setup: pre-reset finds site",
		not wai._nearest_site({"position": Vector2.ZERO},
			["tree"] as Array[String]).is_empty())
	# New game on the same state object: setup() clears + bumps version.
	gs.setup(["humans"])
	var far := _add(gs, "bush", 3000.0, 3000.0)
	var got_tree: Dictionary = wai._nearest_site({"position": Vector2.ZERO},
		["tree"] as Array[String])
	var got_bush: Dictionary = wai._nearest_site({"position": Vector2.ZERO},
		["bush"] as Array[String])
	_check("setup: old tree gone after reset", got_tree.is_empty())
	_check("setup: new bush found after reset",
		int(got_bush.get("id", -1)) == int(far["id"]))
	gs.queue_free()


func _test_empty_grid() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	_check("empty grid: empty dict",
		wai._nearest_site({"position": Vector2.ZERO},
			["tree"] as Array[String]).is_empty())
	gs.queue_free()


func _test_grid_synced_count() -> void:
	var gw: Array = _new_wai()
	var gs: GameState = gw[0]
	var wai: WorkerAI = gw[1]
	for i in 37:
		_add(gs, "bush", float(i * 10), 0.0)
	wai._nearest_site({"position": Vector2.ZERO}, ["bush"] as Array[String])
	_check("grid indexes all sites", wai._site_grid_n == 37)
	gs.queue_free()
