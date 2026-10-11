extends SceneTree
## Cursing Gnomes — R26 livestock stagger tests.
##
## R26 moved the per-plot livestock body (hunger, leash, movement, purge)
## from every tick to round-robin 20Hz: plots are dealt into 3 slots by
## array index, one slot per physics tick with delta x3. Every term is
## linear in delta, so the simulation totals are unchanged. _building()
## also went O(1) via the GameState id index.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_animals_stagger_r26.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes R26 livestock-stagger tests ===")
	_test_cadence_exactly_once_per_three()
	_test_slot_distribution()
	_test_small_n_no_speedup()
	_test_hunger_parity_over_window()
	_test_building_lookup_parity()
	_test_purge_across_stagger()
	_test_anchor_uses_building()
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
	var a := SimAnimals.new(gs)
	gs.animals = a
	return [gs, f, a]


func _make_plot(f, faction: String, pos: Vector2) -> Dictionary:
	return f.create_plot(faction, pos, -1, true)


## One plot, 3 ticks of 1.0: the plot is processed exactly once with
## scaled delta 3.0, so hunger drops by exactly 1.1 * 3.0 — not 3x that
## (which would mean every-tick processing leaked through).
func _test_cadence_exactly_once_per_three() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var a = pack[2]
	var plot: Dictionary = _make_plot(pack[1], "humans", Vector2(100, 100))
	var goat: Dictionary = a.add_animal(plot, "goat", Vector2(100, 100))
	var hunger0: float = float(goat["hunger"])
	a.tick(1.0)
	a.tick(1.0)
	a.tick(1.0)
	_check("one plot processed exactly once per 3 ticks",
		is_equal_approx(float(goat["hunger"]), hunger0 - 3.3))
	a.tick(1.0)
	a.tick(1.0)
	a.tick(1.0)
	_check("second window identical",
		is_equal_approx(float(goat["hunger"]), hunger0 - 6.6))


## Six plots: each physics tick processes exactly 2 (one slot), and after
## 3 ticks every plot has been processed exactly once.
func _test_slot_distribution() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var a = pack[2]
	var plots: Array = []
	var hunger0: Array = []
	for i in 6:
		var plot: Dictionary = _make_plot(pack[1], "humans",
			Vector2(100 + i * 50, 100))
		var an0: Dictionary = a.add_animal(plot, "sheep",
			Vector2(100 + i * 50, 100))
		plots.append(plot)
		hunger0.append(float(an0["hunger"]))
	var decayed := 0
	for i in 6:
		var an: Dictionary = (plots[i]["animals"] as Array)[0]
		if float(an["hunger"]) < float(hunger0[i]) - 0.001:
			decayed += 1
	_check("nothing decayed before any tick", decayed == 0)
	a.tick(1.0)
	decayed = 0
	for i in 6:
		var an: Dictionary = (plots[i]["animals"] as Array)[0]
		if float(an["hunger"]) < float(hunger0[i]) - 0.001:
			decayed += 1
	_check("exactly one slot (2 of 6 plots) per tick", decayed == 2)
	a.tick(1.0)
	a.tick(1.0)
	var all_once := true
	for i in 6:
		var an: Dictionary = (plots[i]["animals"] as Array)[0]
		if not is_equal_approx(float(an["hunger"]),
				float(hunger0[i]) - 3.3):
			all_once = false
	_check("all 6 plots processed exactly once after 3 ticks", all_once)


## Fresh system: ticks 1-2 must not touch the animal at all (slot miss),
## tick 3 processes it once. A small-n speedup bug would decay on tick 1.
func _test_small_n_no_speedup() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var a = pack[2]
	var plot: Dictionary = _make_plot(pack[1], "humans", Vector2(100, 100))
	var cow: Dictionary = a.add_animal(plot, "cow", Vector2(100, 100))
	var hunger0: float = float(cow["hunger"])
	a.tick(1.0)
	_check("tick 1: slot miss, hunger untouched",
		is_equal_approx(float(cow["hunger"]), hunger0))
	a.tick(1.0)
	_check("tick 2: slot miss, hunger untouched",
		is_equal_approx(float(cow["hunger"]), hunger0))
	a.tick(1.0)
	_check("tick 3: processed once with scaled delta",
		is_equal_approx(float(cow["hunger"]), hunger0 - 3.3))


## Over a full 3-tick window the totals match the old 60Hz behavior:
## 3 ticks of 2.0s == 6.0s at 1.1/s == 6.6 hunger.
func _test_hunger_parity_over_window() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var a = pack[2]
	var plot: Dictionary = _make_plot(pack[1], "humans", Vector2(100, 100))
	var pig: Dictionary = a.add_animal(plot, "pig", Vector2(100, 100))
	var hunger0: float = float(pig["hunger"])
	a.tick(2.0)
	a.tick(2.0)
	a.tick(2.0)
	_check("hunger parity over 3-tick window",
		is_equal_approx(float(pig["hunger"]), hunger0 - 6.6))


## _building() parity: O(1) index returns the same live record the old
## linear scan found; missing ids and NO_BUILDING return {}.
func _test_building_lookup_parity() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var a = pack[2]
	var b := {"id": 42, "alive": true, "complete": true,
		"type": "barn", "faction": "humans",
		"position": Vector2(500, 500)}
	gs.buildings.append(b)
	var got: Dictionary = a._building(42)
	_check("index finds appended building", got == b)
	_check("same live ref", is_same(got, b))
	_check("missing id -> {}", a._building(999).is_empty())
	_check("NO_BUILDING -> {}", a._building(-1).is_empty())


## A dead animal is purged from the herd on its plot's next slot tick.
func _test_purge_across_stagger() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var a = pack[2]
	var plot: Dictionary = _make_plot(pack[1], "humans", Vector2(100, 100))
	var an: Dictionary = a.add_animal(plot, "chicken", Vector2(100, 100))
	an["alive"] = false
	_check("dead still listed before slot tick",
		(plot["animals"] as Array).size() == 1)
	a.tick(1.0)
	a.tick(1.0)
	a.tick(1.0)
	_check("dead purged after its slot tick",
		(plot["animals"] as Array).is_empty())


## _anchor resolves the attached barn's position (via the O(1) lookup):
## a strayed animal's leash target lands near the BARN, not the plot.
func _test_anchor_uses_building() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var a = pack[2]
	var plot: Dictionary = _make_plot(pack[1], "humans", Vector2(100, 100))
	var barn := {"id": 7, "alive": true, "complete": true,
		"type": "barn", "faction": "humans",
		"position": Vector2(500, 500)}
	gs.buildings.append(barn)
	plot["barn_bld"] = 7
	var an: Dictionary = a.add_animal(plot, "sheep", Vector2(100, 100))
	an["position"] = Vector2(1000, 1000)
	a.tick(1.0)
	a.tick(1.0)
	a.tick(1.0)
	_check("leash target set", an.has("move_target"))
	if an.has("move_target"):
		var tgt: Vector2 = an["move_target"]
		_check("leash target anchored at barn",
			tgt.distance_to(Vector2(500, 500)) < 120.0)
