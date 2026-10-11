extends SceneTree
## Cursing Gnomes — R33 pickup-grid oracle parity tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_pickup_grid_r33.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: the R33 spatial grid in WorkerAI._collect_pickups returns
## BIT-IDENTICAL results to the old full-array reverse scan (verbatim oracle
## below) across clustered/scattered/boundary layouts, capacity-break
## quirks, mid-run add/remove (version invalidation), and far-away units.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	print("=== Cursing Gnomes pickup-grid R33 tests ===")
	_test_parity_basic()
	_test_parity_capacity_break()
	_test_parity_cell_boundary()
	_test_parity_exact_radius()
	_test_version_bump_add_remove()
	_test_new_pickup_collected_after_add()
	_test_removed_pickup_not_collected()
	_test_far_unit_collects_nothing()
	_test_non_collectible_kinds_ignored()
	_test_empty_pickups_no_crash()
	_test_save_load_refill_resyncs()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## Verbatim copy of the pre-R33 _collect_pickups (full reverse scan).
func _old_collect(unit: Dictionary, gs: GameState) -> void:
	if gs.pickups.is_empty():
		return
	if not unit.has("carrying"):
		return
	var cap: float = float(unit.get("carry_cap", 10.0))
	var carrying: Dictionary = unit["carrying"]
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var changed := false
	for i in range(gs.pickups.size() - 1, -1, -1):
		var p: Dictionary = gs.pickups[i]
		var kind: String = String(p.get("kind", ""))
		if kind != "wood" and kind != "food":
			continue
		var pp: Vector2 = p.get("position", Vector2.ZERO)
		if up.distance_to(pp) > 40.0:
			continue
		var have: float = float(carrying.get(kind, 0.0))
		if have >= cap:
			break
		var pamt: float = float(p.get("amount", 0.0))
		var take: float = minf(pamt, cap - have)
		carrying[kind] = have + take
		if pamt - take <= 0.0:
			gs.remove_pickup(int(p.get("id", 0)))
		else:
			p["amount"] = pamt - take
		changed = true
	if changed:
		unit["carrying"] = carrying


func _world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	var wai := WorkerAI.new(gs)
	return [gs, wai]


func _unit(gs: GameState, pos: Vector2, carrying: Dictionary, cap: float) -> Dictionary:
	return gs.add_unit({"faction": "humans", "job": "worker", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 30.0, "work_state": "gathering", "carrying": carrying,
		"carry_cap": cap})


func _pickup(gs: GameState, kind: String, amount: float, pos: Vector2) -> Dictionary:
	return gs.add_pickup({"kind": kind, "amount": amount, "position": pos})


func _snapshot(gs: GameState) -> Array:
	var out := []
	for u: Dictionary in gs.units:
		out.append((u.get("carrying", {}) as Dictionary).duplicate())
	var pk := []
	for p: Dictionary in gs.pickups:
		pk.append([int(p.get("id", 0)), String(p.get("kind", "")), float(p.get("amount", 0.0))])
	pk.sort()
	out.append(pk)
	return out


## Runs the same scripted scenario on twin worlds: new grid path vs oracle.
func _run_twins(setup_fn: Callable, ticks: int) -> Array:
	var results := []
	for use_new in [true, false]:
		var w: Array = _world()
		var gs: GameState = w[0]
		var wai: WorkerAI = w[1]
		setup_fn.call(gs)
		for _t in range(ticks):
			for u: Dictionary in gs.units:
				if use_new:
					wai._collect_pickups(u)
				else:
					_old_collect(u, gs)
		results.append(_snapshot(gs))
		root.remove_child(gs)
		gs.queue_free()
	return results


func _test_parity_basic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3301
	var defs := []
	for i in range(40):
		defs.append(["wood" if i % 3 else "food", rng.randf_range(1.0, 8.0),
			Vector2(rng.randf_range(0, 800), rng.randf_range(0, 800))])
	var upos := []
	for i in range(12):
		upos.append(Vector2(rng.randf_range(0, 800), rng.randf_range(0, 800)))
	var setup := func(gs: GameState) -> void:
		for d in defs:
			_pickup(gs, d[0], d[1], d[2])
		for up in upos:
			_unit(gs, up, {}, 10.0)
	var r: Array = _run_twins(setup, 4)
	_check("parity: basic 40-pickup/12-unit scenario identical", r[0] == r[1])


func _test_parity_capacity_break() -> void:
	# Quirky rule: a full kind BREAKS the whole scan (not just that kind).
	var setup := func(gs: GameState) -> void:
		_pickup(gs, "wood", 5.0, Vector2(100, 100))
		_pickup(gs, "food", 5.0, Vector2(102, 100))
		_pickup(gs, "wood", 5.0, Vector2(104, 100))
		# Unit already full on wood: old code breaks at the first wood in
		# reverse order and never reaches the food.
		_unit(gs, Vector2(100, 100), {"wood": 10.0}, 10.0)
	var r: Array = _run_twins(setup, 1)
	_check("parity: capacity-break quirk identical", r[0] == r[1])
	_check("capacity-break: food NOT collected (old quirk kept)",
		float((r[0][0] as Dictionary).get("food", 0.0)) == 0.0)


func _test_parity_cell_boundary() -> void:
	# Pickups exactly on 128px cell borders; units straddling cells.
	var setup := func(gs: GameState) -> void:
		for x in [128.0, 256.0, 384.0]:
			for y in [128.0, 256.0]:
				_pickup(gs, "wood", 3.0, Vector2(x, y))
		_unit(gs, Vector2(127.9, 128.1), {}, 10.0)
		_unit(gs, Vector2(256.0, 256.0), {}, 10.0)
		_unit(gs, Vector2(300, 300), {}, 10.0)
	var r: Array = _run_twins(setup, 3)
	_check("parity: cell-boundary layout identical", r[0] == r[1])


func _test_parity_exact_radius() -> void:
	# Pickup exactly at 40.0 px (in radius: not > 40) and just outside.
	var setup := func(gs: GameState) -> void:
		_pickup(gs, "wood", 4.0, Vector2(140, 100))   # exactly 40 away
		_pickup(gs, "wood", 4.0, Vector2(140.1, 100)) # 40.1 away
		_unit(gs, Vector2(100, 100), {}, 10.0)
	var r: Array = _run_twins(setup, 1)
	_check("parity: exact-radius edge identical", r[0] == r[1])
	_check("exact-radius: 40.0 collected, 40.1 not",
		(r[0][1] as Array).size() == 1
		and float((r[0][0] as Dictionary).get("wood", 0.0)) == 4.0)


func _test_version_bump_add_remove() -> void:
	var w: Array = _world()
	var gs: GameState = w[0]
	_check("version starts at 0", gs.pickup_version == 0)
	var p: Dictionary = _pickup(gs, "wood", 2.0, Vector2(50, 50))
	_check("version bumps on add", gs.pickup_version == 1)
	gs.remove_pickup(int(p.get("id", 0)))
	_check("version bumps on remove", gs.pickup_version == 2)
	root.remove_child(gs)
	gs.queue_free()


func _test_new_pickup_collected_after_add() -> void:
	# Grid must re-sync when a pickup appears mid-run (fisher catch).
	var w: Array = _world()
	var gs: GameState = w[0]
	var wai: WorkerAI = w[1]
	var u: Dictionary = _unit(gs, Vector2(100, 100), {}, 10.0)
	wai._collect_pickups(u)  # syncs grid on empty world
	_pickup(gs, "food", 6.0, Vector2(105, 100))
	wai._collect_pickups(u)
	_check("new pickup collected after version bump",
		float((u.get("carrying", {}) as Dictionary).get("food", 0.0)) == 6.0)
	root.remove_child(gs)
	gs.queue_free()


func _test_removed_pickup_not_collected() -> void:
	var w: Array = _world()
	var gs: GameState = w[0]
	var wai: WorkerAI = w[1]
	var u: Dictionary = _unit(gs, Vector2(100, 100), {"wood": 10.0}, 10.0)
	var p: Dictionary = _pickup(gs, "wood", 5.0, Vector2(102, 100))
	wai._collect_pickups(u)  # syncs grid; wood full -> break, nothing collected
	gs.remove_pickup(int(p.get("id", 0)))  # external removal; grid ref now stale
	u["carrying"] = {}
	wai._collect_pickups(u)  # stale grid id must not match the live array
	_check("removed pickup not collected",
		(u.get("carrying", {}) as Dictionary).is_empty())
	root.remove_child(gs)
	gs.queue_free()


func _test_far_unit_collects_nothing() -> void:
	var w: Array = _world()
	var gs: GameState = w[0]
	var wai: WorkerAI = w[1]
	_pickup(gs, "wood", 5.0, Vector2(100, 100))
	var u: Dictionary = _unit(gs, Vector2(3000, 3000), {}, 10.0)
	wai._collect_pickups(u)  # early-out: no pickups in 3x3 cells
	_check("far unit collects nothing",
		(u.get("carrying", {}) as Dictionary).is_empty())
	_check("far pickup untouched", gs.pickups.size() == 1)
	root.remove_child(gs)
	gs.queue_free()


func _test_non_collectible_kinds_ignored() -> void:
	var setup := func(gs: GameState) -> void:
		_pickup(gs, "stone", 5.0, Vector2(101, 100))
		_pickup(gs, "gold", 5.0, Vector2(102, 100))
		_pickup(gs, "wood", 2.0, Vector2(103, 100))
		_unit(gs, Vector2(100, 100), {}, 10.0)
	var r: Array = _run_twins(setup, 1)
	_check("parity: non-collectible kinds identical", r[0] == r[1])
	_check("only wood collected",
		(r[0][1] as Array).size() == 2
		and float((r[0][0] as Dictionary).get("wood", 0.0)) == 2.0)


func _test_empty_pickups_no_crash() -> void:
	var w: Array = _world()
	var gs: GameState = w[0]
	var wai: WorkerAI = w[1]
	var u: Dictionary = _unit(gs, Vector2(100, 100), {}, 10.0)
	wai._collect_pickups(u)  # empty array early-out
	_check("empty pickups: no crash, nothing carried",
		(u.get("carrying", {}) as Dictionary).is_empty())
	root.remove_child(gs)
	gs.queue_free()


func _test_save_load_refill_resyncs() -> void:
	# Mirrors save_system.gd's load path: clear + re-append, then bump.
	var w: Array = _world()
	var gs: GameState = w[0]
	var wai: WorkerAI = w[1]
	var u: Dictionary = _unit(gs, Vector2(100, 100), {}, 10.0)
	_pickup(gs, "wood", 3.0, Vector2(102, 100))
	wai._collect_pickups(u)  # syncs grid, collects the wood
	_check("pre-load: wood collected",
		float((u.get("carrying", {}) as Dictionary).get("wood", 0.0)) == 3.0)
	u["carrying"] = {}
	var saved: Array = gs.pickups.duplicate()
	gs.pickups.clear()
	for p in saved:
		gs.pickups.append(p)
	gs.pickup_version += 1  # save_system.gd load path
	_pickup(gs, "food", 4.0, Vector2(104, 100))
	wai._collect_pickups(u)
	_check("post-load refill: grid rebuilt, food collected",
		float((u.get("carrying", {}) as Dictionary).get("food", 0.0)) == 4.0)
	root.remove_child(gs)
	gs.queue_free()
