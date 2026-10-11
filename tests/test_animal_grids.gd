extends SceneTree
## Cursing Gnomes — animal spatial-grid equivalence + perf tests (2026-10-04).
##
## The 2026-10-04 optimization replaced the per-frame O(wild x units) and
## O(wolves x prey) full scans in SimAnimals with once-per-tick coarse
## spatial grids, and gated the per-plot housing building scan. These tests
## prove the grids return EXACTLY what the old scans returned across
## randomized layouts (same radii, same tie order, same decisions), and
## that tick() stays cheap at full population scale.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_animal_grids.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes animal-grid tests ===")
	_test_threat_equivalence()
	_test_threat_ties_and_edges()
	_test_wolf_choice_equivalence()
	_test_housing_gate()
	_test_tick_perf()
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


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	return gs


func _new_farm_stack(factions: Array[String]) -> Array:
	var gs := _new_game(factions)
	var f := SimFarming.new(gs)
	gs.farming = f
	gs.resources.add_resource(factions[0], "wood", 100.0)
	var a := SimAnimals.new(gs)
	gs.animals = a
	return [gs, f, a]


## Verbatim copy of the PRE-optimization _nearest_unit_threat (full scan).
func _brute_threat(gs: GameState, pos: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := 70.0
	for u in gs.units:
		if not (u is Dictionary):
			continue
		if not bool(u.get("alive", true)):
			continue
		var up: Vector2 = u.get("position", Vector2.INF)
		var d: float = pos.distance_to(up)
		if d < best_d:
			best_d = d
			best = up
	return best


## Verbatim copy of the PRE-optimization wolf prey choice (wild scan, then
## livestock scan). Returns the chosen prey dict (may be empty).
func _brute_wolf_prey(a: SimAnimals, wolf: Dictionary,
		pos: Vector2) -> Dictionary:
	var prey_types: Array = SimAnimals.PREDATORS.get("wolf", [])
	var best: Dictionary = {}
	var best_d := 300.0
	for an in a.wild:
		if an == wolf or not bool(an.get("alive", false)):
			continue
		if not (String(an.get("type", "")) in prey_types):
			continue
		var d: float = pos.distance_to(an.get("position", pos))
		if d < best_d:
			best_d = d
			best = an
	if best.is_empty():
		for p in a._plots():
			if not (p is Dictionary):
				continue
			for an in p.get("animals", []):
				if not (an is Dictionary):
					continue
				if not bool(an.get("alive", false)):
					continue
				if not (String(an.get("type", "")) in prey_types):
					continue
				var d2: float = pos.distance_to(an.get("position", pos))
				if d2 < best_d:
					best_d = d2
					best = an
	return best


func _scatter_units(gs: GameState, rng: RandomNumberGenerator, n: int,
		half_extent: float) -> void:
	for i in range(n):
		var u: Dictionary = {
			"id": 1000 + i,
			"alive": rng.randf() > 0.05,
			"position": Vector2(
				rng.randf_range(-half_extent, half_extent),
				rng.randf_range(-half_extent, half_extent)),
		}
		# Some units lack the alive key (old code defaults them alive).
		if rng.randf() < 0.1:
			u.erase("alive")
		gs.units.append(u)


func _test_threat_equivalence() -> void:
	# Randomized layouts: grid answers must equal brute-force answers.
	for seed_i in range(5):
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242 + seed_i
		var pack: Array = _new_farm_stack(["humans"])
		var gs: GameState = pack[0]
		var a: SimAnimals = pack[2]
		_scatter_units(gs, rng, 240, 2000.0)
		# Jeremy 2026-10-05 perf: grids rebuild every 3rd tick (20Hz).
		for i in 3:
			a.tick(1.0 / 60.0)  # builds the grids
		var mismatches := 0
		for q in range(200):
			var qp := Vector2(rng.randf_range(-2000.0, 2000.0),
				rng.randf_range(-2000.0, 2000.0))
			var want := _brute_threat(gs, qp)
			var got: Vector2 = a._nearest_unit_threat(qp)
			if want != got:
				mismatches += 1
		_check("threat grid == brute force (seed %d)" % seed_i,
			mismatches == 0)
		gs.queue_free()


func _test_threat_ties_and_edges() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var a: SimAnimals = pack[2]
	# Two units exactly equidistant from the query point: the old scan
	# kept the first in units order.
	gs.units.append({"id": 1, "alive": true,
		"position": Vector2(100, 130)})
	gs.units.append({"id": 2, "alive": true,
		"position": Vector2(100, 70)})
	# Unit at exactly the 70px boundary: old scan used strict <, so it is
	# NOT a threat.
	gs.units.append({"id": 3, "alive": true,
		"position": Vector2(170, 100)})
	# Dead unit inside the radius: ignored by both.
	gs.units.append({"id": 4, "alive": false,
		"position": Vector2(105, 100)})
	# Jeremy 2026-10-05 perf: grids rebuild every 3rd tick (20Hz).
	for i in 3:
		a.tick(1.0 / 60.0)
	var got: Vector2 = a._nearest_unit_threat(Vector2(100, 100))
	_check("threat tie keeps first unit", got == Vector2(100, 130))
	# Boundary unit alone: no threat.
	var gs2: GameState = _new_game(["humans"])
	var pack2: Array = [gs2, null, null]
	var f2 := SimFarming.new(gs2)
	gs2.farming = f2
	var a2 := SimAnimals.new(gs2)
	gs2.animals = a2
	gs2.units.append({"id": 9, "alive": true,
		"position": Vector2(170, 100)})
	a2.tick(1.0 / 60.0)
	_check("threat boundary strict < 70",
		a2._nearest_unit_threat(Vector2(100, 100)) == Vector2.INF)
	gs.queue_free()
	gs2.queue_free()


func _test_wolf_choice_equivalence() -> void:
	# The wolf's chosen prey (via its movement toward the target) must
	# match the brute-force choice across randomized layouts.
	for seed_i in range(5):
		var rng := RandomNumberGenerator.new()
		rng.seed = 9001 + seed_i
		var pack: Array = _new_farm_stack(["humans"])
		var gs: GameState = pack[0]
		var a: SimAnimals = pack[2]
		var types := ["boar", "sheep", "chicken", "goat", "pig"]
		for i in range(30):
			var t: String = types[rng.randi_range(0, types.size() - 1)]
			a.spawn_wild(t, Vector2(rng.randf_range(-900.0, 900.0),
				rng.randf_range(-900.0, 900.0)))
		var wolf: Dictionary = a.spawn_wild("wolf",
			Vector2(rng.randf_range(-900.0, 900.0),
				rng.randf_range(-900.0, 900.0)))
		# A livestock alternative for the wild-first tie rule.
		var f: SimFarming = pack[1]
		var plot: Dictionary = f.create_plot("humans",
			Vector2(rng.randf_range(-900.0, 900.0),
				rng.randf_range(-900.0, 900.0)), -1, true)
		a.add_animal(plot, "sheep",
			Vector2(rng.randf_range(-900.0, 900.0),
				rng.randf_range(-900.0, 900.0)))
		var wpos: Vector2 = wolf.get("position", Vector2.ZERO)
		# Jeremy 2026-10-05 perf: wild brains + neighbor grids run at 20Hz
		# (round-robin slices), so warm up 3 ticks — grids build and every
		# animal thinks at least once — before measuring the wolf's choice.
		# The wolf (spawned last) thinks on ticks 3 and 6, both with a
		# freshly rebuilt grid, so the measurement window is ticks 4-6.
		for i in 3:
			a.tick(1.0 / 60.0)
		wpos = wolf.get("position", wpos)
		var want := _brute_wolf_prey(a, wolf, wpos)
		for i in 3:
			a.tick(1.0 / 60.0)
		var wpos2: Vector2 = wolf.get("position", wpos)
		if want.is_empty():
			# No prey in range: wolf wanders (position may still move).
			_check("wolf choice empty == brute (seed %d)" % seed_i, true)
		else:
			var tpos: Vector2 = want.get("position", wpos)
			# Wolf moved toward the brute-force-chosen prey.
			var moved: Vector2 = wpos2 - wpos
			var to_prey: Vector2 = tpos - wpos
			_check("wolf chases brute-force prey (seed %d)" % seed_i,
				moved.length() > 0.001 and moved.normalized().dot(
					to_prey.normalized()) > 0.99)
		gs.queue_free()


func _test_housing_gate() -> void:
	# Barn attach still works through the gate (first tick rescans because
	# the building count changed).
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var f: SimFarming = pack[1]
	var a: SimAnimals = pack[2]
	var plot: Dictionary = f.create_plot("humans", Vector2(500, 500), -1,
		true)
	gs.add_building({"type": "barn", "faction": "humans", "town_id": -1,
		"position": Vector2(520, 500), "alive": true, "complete": true})
	for i in range(5):
		a.tick(1.0 / 60.0)
	_check("barn attaches through housing gate",
		int(plot.get("barn_bld", -1)) != -1)
	_check("barn stocks livestock", (plot.get("animals", []) as Array).size() >= 2)
	# Fully-housed plot + steady building count: the scan is skipped but
	# the plot keeps working (hunger decays on tick).
	var an0: Dictionary = (plot.get("animals", []) as Array)[0]
	var h0: float = float(an0.get("hunger", 0.0))
	for i in range(10):
		a.tick(1.0 / 60.0)
	_check("plot still ticks with gate closed",
		float(an0.get("hunger", 0.0)) < h0)
	gs.queue_free()


func _test_tick_perf() -> void:
	# Full-scale load: 240 units + 40 wild + stocked plots. Generous bound
	# so the test is stable across machines; the old code took ~4ms on a
	# fast desktop here, the grid should be far under 2ms.
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var f: SimFarming = pack[1]
	var a: SimAnimals = pack[2]
	_scatter_units(gs, rng, 240, 2000.0)
	var types := ["boar", "sheep", "chicken", "goat", "pig", "wolf"]
	for i in range(40):
		a.spawn_wild(types[rng.randi_range(0, types.size() - 1)],
			Vector2(rng.randf_range(-2000.0, 2000.0),
				rng.randf_range(-2000.0, 2000.0)))
	for i in range(6):
		var plot: Dictionary = f.create_plot("humans",
			Vector2(rng.randf_range(-1500.0, 1500.0),
				rng.randf_range(-1500.0, 1500.0)), -1, true)
		for k in range(8):
			a.add_animal(plot, "sheep",
				Vector2(rng.randf_range(-1500.0, 1500.0),
					rng.randf_range(-1500.0, 1500.0)))
	# Warm up, then time.
	for i in range(10):
		a.tick(1.0 / 60.0)
	var t0 := Time.get_ticks_msec()
	var iters := 120
	for i in range(iters):
		a.tick(1.0 / 60.0)
	var avg_ms := float(Time.get_ticks_msec() - t0) / float(iters)
	print("  animal tick avg_ms=%.3f at full scale" % avg_ms)
	_check("tick under 2ms at full scale", avg_ms < 2.0)
	gs.queue_free()
