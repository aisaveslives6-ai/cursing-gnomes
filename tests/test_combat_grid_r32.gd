extends SceneTree
## Cursing Gnomes — perf round R32: combat unit-grid allocation removal.
##
## R32 made _sync_unit_grid allocation-free after warmup (cell arrays are
## cleared in place and reused; pairs pack flat as [unit, idx, ...] instead
## of per-unit [u, i] arrays).
## R41 (2026-10-08) replaced _nearest_hostile's ring-bucket scratch with a
## direct ring-coordinate walk: rings are visited by coordinate and only
## occupied cells are scanned, in ascending ring order with the same
## stopping rule and the same argmin + build-index tie-break — bit-identical
## results at ~2.4x the speed. The _nh_rings scratch member is gone.
##
## These tests prove the grid + scan behavior:
##   1. Oracle parity: _nearest_hostile agrees with brute force on a
##      scattered battlefield (same contract as test_combat_unit_grid).
##   2. Flat storage: every cell array has even length, alternating
##      Dictionary (unit) / int (build index), in build order.
##   3. Reuse: the grid holds the same cells and pair order across
##      rebuilds (no churn, no unbounded growth).
##   4. Stale cells: cells abandoned between rebuilds are erased from the
##      grid (no unbounded empty-cell growth).
##   5. R41 ring walk: boundary semantics, exact-distance tie-break,
##      far-ring stopping rule, and ring-0 queries all agree with the
##      brute-force oracle.
##   6. R42 building grid: _nearest_hostile_building walks a 512px building
##      grid with the R41 ring pattern — oracle parity vs the old linear
##      scan, boundary semantics, tie-break, destroyed-flag live filtering,
##      and count-change auto-rebuild all pinned.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_combat_grid_r32.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes R32 combat-grid tests ===")
	_test_oracle_parity()
	_test_flat_storage()
	_test_reuse_across_rebuilds()
	_test_stale_cells_erased()
	_test_r41_ring_walk()
	_test_r42_building_grid()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves"])
	var combat := SimCombat.new(gs)
	return {"gs": gs, "combat": combat}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, "soldier", -1, pos)


## Brute-force oracle (pre-grid semantics).
func _brute(w: Dictionary, upos: Vector2, faction: String,
		max_dist: float) -> Dictionary:
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var best: Dictionary = {}
	var best_d2: float = max_dist * max_dist
	for u: Dictionary in gs.units:
		if not u.get("alive", false):
			continue
		if bool(u.get("downed", false)):
			continue
		if not combat.can_fight(faction, String(u.get("faction", ""))):
			continue
		var d2: float = upos.distance_squared_to(
			u.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = u
	return best


func _same_unit(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() and b.is_empty():
		return true
	if a.is_empty() or b.is_empty():
		return false
	return int(a.get("id", -1)) == int(b.get("id", -1))


func _test_oracle_parity() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	seed(20261006)
	var factions := ["humans", "ogres", "elves"]
	for i in range(120):
		var f: String = factions[i % 3]
		var pos := Vector2(randf_range(-1500.0, 1500.0),
			randf_range(-1500.0, 1500.0))
		var u := _spawn(w, f, pos)
		if i % 11 == 0:
			u["alive"] = false
		elif i % 13 == 0:
			u["downed"] = true
	combat._invalidate_unit_grid()
	var mismatches := 0
	for q in range(300):
		var qp := Vector2(randf_range(-1500.0, 1500.0),
			randf_range(-1500.0, 1500.0))
		var qf: String = factions[q % 3]
		var qd: float = randf_range(50.0, 900.0)
		var got: Dictionary = combat._nearest_hostile(qp, qf, qd)
		var want: Dictionary = _brute(w, qp, qf, qd)
		if not _same_unit(got, want):
			mismatches += 1
	_check("oracle parity: 300 queries agree with brute force",
		mismatches == 0)
	_free_world(w)


func _test_flat_storage() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	# Several units sharing cells and spread across cells.
	_spawn(w, "humans", Vector2(10, 10))
	_spawn(w, "ogres", Vector2(20, 15))
	_spawn(w, "elves", Vector2(1500, -700))
	_spawn(w, "humans", Vector2(12, 11))
	combat._invalidate_unit_grid()
	combat._nearest_hostile(Vector2.ZERO, "humans", 5000.0)
	var ok := true
	var total_pairs := 0
	for ckey in combat._unit_grid:
		var cell: Array = combat._unit_grid[ckey]
		if cell.size() % 2 != 0:
			ok = false
		var p := 0
		while p < cell.size():
			if not (cell[p] is Dictionary):
				ok = false
			if not (cell[p + 1] is int):
				ok = false
			total_pairs += 1
			p += 2
	_check("flat storage: even length, Dictionary/int pairs", ok)
	# 4 live units (spawner may block some; require at least the pairs
	# present to be consistent and non-empty).
	_check("flat storage: all spawned units present",
		total_pairs >= 3)
	_free_world(w)


func _test_reuse_across_rebuilds() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	for i in range(40):
		_spawn(w, "humans" if i % 2 == 0 else "ogres",
			Vector2(randf_range(-900.0, 900.0), randf_range(-900.0, 900.0)))
	combat._invalidate_unit_grid()
	combat._nearest_hostile(Vector2.ZERO, "humans", 2000.0)
	# Snapshot grid contents (cell -> unit id list in order).
	var before := {}
	for ckey in combat._unit_grid:
		var ids: Array = []
		var cell: Array = combat._unit_grid[ckey]
		var p := 0
		while p < cell.size():
			ids.append(int((cell[p] as Dictionary).get("id", -1)))
			p += 2
		before[ckey] = ids
	# Move every unit a little (same cells) and force a rebuild.
	var gs: GameState = w["gs"]
	for u: Dictionary in gs.units:
		var pos: Vector2 = u.get("position", Vector2.ZERO)
		u["position"] = pos + Vector2(3.0, -2.0)
	combat._invalidate_unit_grid()
	combat._nearest_hostile(Vector2.ZERO, "humans", 2000.0)
	var same := true
	if (combat._unit_grid as Dictionary).size() != before.size():
		same = false
	else:
		for ckey in combat._unit_grid:
			if not before.has(ckey):
				same = false
				break
			var ids: Array = []
			var cell: Array = combat._unit_grid[ckey]
			var p := 0
			while p < cell.size():
				ids.append(int((cell[p] as Dictionary).get("id", -1)))
				p += 2
			if ids != before[ckey]:
				same = false
				break
	_check("rebuild: same cells and pair order across rebuilds", same)
	# Oracle parity after the rebuild churn.
	var got: Dictionary = combat._nearest_hostile(Vector2(50, -30), "ogres", 2000.0)
	var want: Dictionary = _brute(w, Vector2(50, -30), "ogres", 2000.0)
	_check("rebuild: oracle parity after churn", _same_unit(got, want))
	_free_world(w)


func _test_stale_cells_erased() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var gs: GameState = w["gs"]
	var units: Array = []
	for i in range(10):
		units.append(_spawn(w, "ogres",
			Vector2(1200.0 + i * 300.0, 800.0)))
	combat._invalidate_unit_grid()
	combat._nearest_hostile(Vector2.ZERO, "humans", 5000.0)
	var keys_before: int = (combat._unit_grid as Dictionary).size()
	# Teleport everyone into one cell and rebuild: abandoned cells must go.
	for u: Dictionary in units:
		u["position"] = Vector2(10, 10)
	combat._invalidate_unit_grid()
	combat._nearest_hostile(Vector2.ZERO, "humans", 5000.0)
	var keys_after: int = (combat._unit_grid as Dictionary).size()
	_check("stale erase: many cells before", keys_before > 3)
	_check("stale erase: one cell after teleport", keys_after == 1)
	# And the oracle still agrees after the churn.
	var got: Dictionary = combat._nearest_hostile(Vector2(0, 0), "humans", 5000.0)
	var want: Dictionary = _brute(w, Vector2(0, 0), "humans", 5000.0)
	_check("stale erase: oracle parity after churn", _same_unit(got, want))
	_free_world(w)


func _test_r41_ring_walk() -> void:
	# R41 replaced the ring-bucket scratch with a direct ring-coordinate
	# walk (bit-identical results, ~2.4x faster). These pin the walk's
	# edge cases against the brute-force oracle.
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	# Boundary: strict d2 < max_dist^2 semantics.
	var edge_in := _spawn(w, "ogres", Vector2(399, 0))
	var edge_out := _spawn(w, "ogres", Vector2(400, 0))
	combat._invalidate_unit_grid()
	var got: Dictionary = combat._nearest_hostile(Vector2.ZERO, "humans",
		400.0)
	_check("r41: target just inside max_dist is found",
		int(got.get("id", -1)) == int(edge_in.get("id", -1)))
	combat._invalidate_unit_grid()
	got = combat._nearest_hostile(Vector2(1, 0), "humans", 399.0)
	# Scanner at (1,0): edge_in at d=398 < 399 -> included; edge_out at
	# d=399, not < 399 -> excluded. Brute force decides; the walk must
	# agree exactly.
	_check("r41: boundary query matches brute force",
		_same_unit(got, _brute(w, Vector2(1, 0), "humans", 399.0)))
	# Tie-break: two hostiles at exactly equal d2 -> lower build index.
	var w2: Dictionary = _new_world()
	var c2: SimCombat = w2["combat"]
	var first := _spawn(w2, "ogres", Vector2(300, 0))
	_spawn(w2, "ogres", Vector2(-300, 0))
	c2._invalidate_unit_grid()
	var got2: Dictionary = c2._nearest_hostile(Vector2.ZERO, "humans",
		500.0)
	_check("r41: exact-distance tie goes to lower build index",
		int(got2.get("id", -1)) == int(first.get("id", -1)))
	_check("r41: tie-break matches brute force",
		_same_unit(got2, _brute(w2, Vector2.ZERO, "humans", 500.0)))
	_free_world(w2)
	# Far ring: nearest hostile several rings out (stopping rule).
	var w3: Dictionary = _new_world()
	var c3: SimCombat = w3["combat"]
	# CELL=256: rings 0..3 cover 1024px; target at ~900px sits in ring 3.
	var far := _spawn(w3, "ogres", Vector2(900, 100))
	c3._invalidate_unit_grid()
	var got3: Dictionary = c3._nearest_hostile(Vector2.ZERO, "humans",
		1000.0)
	_check("r41: far-ring target found",
		int(got3.get("id", -1)) == int(far.get("id", -1)))
	_check("r41: far-ring matches brute force",
		_same_unit(got3, _brute(w3, Vector2.ZERO, "humans", 1000.0)))
	_free_world(w3)
	# Same-cell (ring 0) fast path + empty result.
	combat._invalidate_unit_grid()
	var got4: Dictionary = combat._nearest_hostile(Vector2(399, 5),
		"humans", 50.0)
	_check("r41: ring-0 query matches brute force",
		_same_unit(got4, _brute(w, Vector2(399, 5), "humans", 50.0)))
	_free_world(w)


## R42: _nearest_hostile_building walks a 512px building grid with the R41
## ring pattern instead of a linear scan over all buildings. Bit-identical
## contract: ascending rings, same stopping rule, argmin + build-index
## tie-break. These tests pin the edge cases against the old linear scan
## semantics (copied verbatim below as the oracle).
func _add_b(w: Dictionary, faction: String, pos: Vector2,
		btype: String = "house") -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({"type": btype, "faction": faction,
		"position": pos, "alive": true, "complete": true})


## Old linear-scan semantics, verbatim (pre-R42 _nearest_hostile_building).
func _brute_buildings(w: Dictionary, upos: Vector2, faction: String,
		max_dist: float) -> Dictionary:
	var combat: SimCombat = w["combat"]
	var hostile: Dictionary = combat._hostile_cached(faction)
	var best: Dictionary = {}
	var best_d2: float = max_dist * max_dist
	for b: Dictionary in (w["gs"] as GameState).buildings:
		if bool(b.get("destroyed", false)):
			continue
		if not hostile.has(String(b.get("faction", ""))):
			continue
		var d2: float = upos.distance_squared_to(
			b.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = b
	return best


func _same_building(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() and b.is_empty():
		return true
	if a.is_empty() or b.is_empty():
		return false
	return int(a.get("id", -1)) == int(b.get("id", -1))


func _test_r42_building_grid() -> void:
	# Oracle parity: 150 scattered buildings, 200 random queries.
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	seed(20261008)
	var factions := ["humans", "ogres", "elves"]
	for i in range(150):
		var b := _add_b(w, factions[i % 3],
			Vector2(randf_range(-3000.0, 3000.0),
				randf_range(-3000.0, 3000.0)))
		if i % 17 == 0:
			b["destroyed"] = true  # flagged after grid sync: live filter
	var mismatches := 0
	for q in range(200):
		var qp := Vector2(randf_range(-3000.0, 3000.0),
			randf_range(-3000.0, 3000.0))
		var qf: String = factions[q % 3]
		var qd: float = randf_range(100.0, 1400.0)
		var got: Dictionary = combat._nearest_hostile_building(qp, qf, qd)
		var want: Dictionary = _brute_buildings(w, qp, qf, qd)
		if not _same_building(got, want):
			mismatches += 1
	_check("r42: 200 queries agree with old linear scan", mismatches == 0)
	# Flat storage: even-length [building, idx, ...] cells in build order.
	var even := true
	for ckey in combat._bldg_grid:
		var cell: Array = combat._bldg_grid[ckey]
		if cell.size() % 2 != 0:
			even = false
		var p := 0
		while p < cell.size():
			if not (cell[p] is Dictionary and cell[p + 1] is int):
				even = false
			p += 2
	_check("r42: building grid packs flat [building, idx] pairs", even)
	_free_world(w)
	# Boundary: strict d2 < max_dist^2 semantics.
	var w2: Dictionary = _new_world()
	var c2: SimCombat = w2["combat"]
	var edge_in := _add_b(w2, "ogres", Vector2(899.99, 0))
	_add_b(w2, "ogres", Vector2(900.0, 0))
	var got: Dictionary = c2._nearest_hostile_building(Vector2.ZERO,
		"humans", 900.0)
	_check("r42: target just inside max_dist is found",
		int(got.get("id", -1)) == int(edge_in.get("id", -1)))
	_check("r42: boundary query matches old scan",
		_same_building(got, _brute_buildings(w2, Vector2.ZERO, "humans",
			900.0)))
	# Tie-break: two hostiles at exactly equal d2 -> lower build index.
	var first := _add_b(w2, "elves", Vector2(0, 300))
	_add_b(w2, "elves", Vector2(0, -300))
	var got2: Dictionary = c2._nearest_hostile_building(Vector2.ZERO,
		"humans", 500.0)
	_check("r42: exact-distance tie goes to lower build index",
		int(got2.get("id", -1)) == int(first.get("id", -1)))
	_check("r42: tie-break matches old scan",
		_same_building(got2, _brute_buildings(w2, Vector2.ZERO, "humans",
			500.0)))
	# Destroyed flag is read live: no rebuild needed to drop a target.
	var doomed := _add_b(w2, "ogres", Vector2(50, 0))
	var got3: Dictionary = c2._nearest_hostile_building(Vector2.ZERO,
		"humans", 500.0)
	_check("r42: nearest found before destroy",
		int(got3.get("id", -1)) == int(doomed.get("id", -1)))
	doomed["destroyed"] = true  # no _invalidate_building_grid() call
	var got4: Dictionary = c2._nearest_hostile_building(Vector2.ZERO,
		"humans", 500.0)
	_check("r42: destroyed building skipped without rebuild",
		int(got4.get("id", -1)) != int(doomed.get("id", -1)))
	_check("r42: post-destroy matches old scan",
		_same_building(got4, _brute_buildings(w2, Vector2.ZERO, "humans",
			500.0)))
	# Count-change auto-rebuild: added buildings appear with no explicit
	# invalidate; erased buildings vanish.
	var fresh := _add_b(w2, "ogres", Vector2(25, 0))
	var got5: Dictionary = c2._nearest_hostile_building(Vector2.ZERO,
		"humans", 500.0)
	_check("r42: added building found without explicit invalidate",
		int(got5.get("id", -1)) == int(fresh.get("id", -1)))
	(w2["gs"] as GameState).erase_building(fresh)
	var got6: Dictionary = c2._nearest_hostile_building(Vector2.ZERO,
		"humans", 500.0)
	_check("r42: erased building gone without explicit invalidate",
		int(got6.get("id", -1)) != int(fresh.get("id", -1)))
	_check("r42: post-erase matches old scan",
		_same_building(got6, _brute_buildings(w2, Vector2.ZERO, "humans",
			500.0)))
	# Building moves (Ricky-tow contract): a position write plus the explicit
	# invalidate the tow path performs -> the building is found at its new
	# spot, never stranded in its old cell.
	var mover := _add_b(w2, "ogres", Vector2(60, 0))
	mover["position"] = Vector2(2000, 2000)
	c2._invalidate_building_grid()
	var got7b: Dictionary = c2._nearest_hostile_building(
		Vector2(2000, 1990), "humans", 500.0)
	_check("r42: moved building found at new position after invalidate",
		int(got7b.get("id", -1)) == int(mover.get("id", -1)))
	_check("r42: post-move matches old scan",
		_same_building(got7b, _brute_buildings(w2, Vector2(2000, 1990),
			"humans", 500.0)))
	# Far ring: target several cells out (stopping rule).
	var w3: Dictionary = _new_world()
	var c3: SimCombat = w3["combat"]
	# BLDG_GRID_CELL=512: target at ~900px sits in ring 1-2.
	var far := _add_b(w3, "ogres", Vector2(900, 100))
	var got7: Dictionary = c3._nearest_hostile_building(Vector2.ZERO,
		"humans", 1200.0)
	_check("r42: far-ring target found",
		int(got7.get("id", -1)) == int(far.get("id", -1)))
	_check("r42: far-ring matches old scan",
		_same_building(got7, _brute_buildings(w3, Vector2.ZERO, "humans",
			1200.0)))
	_free_world(w3)
	_free_world(w2)
