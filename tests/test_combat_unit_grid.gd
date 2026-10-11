extends SceneTree
## Cursing Gnomes — combat unit spatial grid tests.
##
## _nearest_hostile was converted from a full O(units) scan to a per-frame
## spatial grid with expanding-ring queries. These tests verify the grid
## returns results IDENTICAL to the old brute-force scan (oracle), plus
## filter semantics, tie-breaking, range edges, and the rebuild contract.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_combat_unit_grid.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes combat unit-grid tests ===")
	_test_oracle_parity()
	_test_filters()
	_test_tie_break()
	_test_range_edges()
	_test_rebuild_contract()
	_test_empty()
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


## Brute-force copy of the pre-grid _nearest_hostile (the oracle).
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


## Randomized oracle parity: grid vs brute force must agree exactly on
## hundreds of queries over a scattered battlefield (multiple cells,
## negative coords, mixed factions, dead/downed units present).
func _test_oracle_parity() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	seed(20261005)
	var factions := ["humans", "ogres", "elves"]
	for i in range(120):
		var f: String = factions[i % 3]
		var pos := Vector2(randf_range(-1500.0, 1500.0),
			randf_range(-1500.0, 1500.0))
		var u := _spawn(w, f, pos)
		if i % 11 == 0:
			u["alive"] = false  # corpses linger in the array
		elif i % 13 == 0:
			u["downed"] = true
	combat._invalidate_unit_grid()
	var mismatches := 0
	for q in range(300):
		var upos := Vector2(randf_range(-1500.0, 1500.0),
			randf_range(-1500.0, 1500.0))
		var f: String = factions[q % 3]
		var max_dist: float = randf_range(50.0, 900.0)
		var got: Dictionary = combat._nearest_hostile(upos, f, max_dist)
		var want: Dictionary = _brute(w, upos, f, max_dist)
		if not _same_unit(got, want):
			mismatches += 1
	_check("oracle parity: 300 random queries identical", mismatches == 0)
	_free_world(w)


## Filter semantics: dead skipped, downed skipped, same-faction skipped.
func _test_filters() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var seeker := Vector2(0, 0)
	var dead := _spawn(w, "ogres", Vector2(10, 0))
	dead["alive"] = false
	var downed := _spawn(w, "ogres", Vector2(20, 0))
	downed["downed"] = true
	var friend := _spawn(w, "humans", Vector2(30, 0))
	var foe := _spawn(w, "ogres", Vector2(100, 0))
	combat._invalidate_unit_grid()
	var got: Dictionary = combat._nearest_hostile(seeker, "humans", 1000.0)
	_check("filters: nearest living hostile picked",
		_same_unit(got, foe) and not _same_unit(got, dead)
		and not _same_unit(got, downed) and not _same_unit(got, friend))
	# Only dead/downed/friendly around -> empty.
	foe["alive"] = false
	combat._invalidate_unit_grid()
	got = combat._nearest_hostile(seeker, "humans", 1000.0)
	_check("filters: nothing valid -> empty", got.is_empty())
	_free_world(w)


## Tie-break: two hostiles at exactly the same spot -> first in
## units-array order wins, matching the old scan.
func _test_tie_break() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var first := _spawn(w, "ogres", Vector2(200, 0))
	var second := _spawn(w, "ogres", Vector2(200, 0))
	combat._invalidate_unit_grid()
	var got: Dictionary = combat._nearest_hostile(Vector2.ZERO,
		"humans", 1000.0)
	_check("tie-break: first in array order wins",
		_same_unit(got, first) and not _same_unit(got, second))
	_free_world(w)


## Range edges: strict < max_dist (a hostile exactly at max_dist is out),
## just inside is in; max_dist 0 finds nothing.
func _test_range_edges() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var edge := _spawn(w, "ogres", Vector2(500, 0))
	combat._invalidate_unit_grid()
	var got: Dictionary = combat._nearest_hostile(Vector2.ZERO,
		"humans", 500.0)
	_check("range: hostile exactly at max_dist excluded", got.is_empty())
	got = combat._nearest_hostile(Vector2.ZERO, "humans", 500.01)
	_check("range: hostile just inside max_dist found",
		_same_unit(got, edge))
	got = combat._nearest_hostile(Vector2.ZERO, "humans", 0.0)
	_check("range: max_dist 0 finds nothing", got.is_empty())
	_free_world(w)


## Rebuild contract: the grid is per-physics-frame; moving a unit mid-frame
## needs an explicit invalidate (headless tests don't advance the clock).
func _test_rebuild_contract() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var foe := _spawn(w, "ogres", Vector2(100, 0))
	combat._invalidate_unit_grid()
	var got: Dictionary = combat._nearest_hostile(Vector2.ZERO,
		"humans", 1000.0)
	_check("rebuild: finds hostile before move", _same_unit(got, foe))
	# Teleport far away and rebuild: the grid now files the foe in a far
	# cell -> correctly out of range.
	foe["position"] = Vector2(5000, 5000)
	combat._invalidate_unit_grid()
	got = combat._nearest_hostile(Vector2.ZERO, "humans", 1000.0)
	_check("rebuild: far-away unit out of range", got.is_empty())
	# The real staleness direction: a unit that moves INTO range stays in
	# its old far-away cell, so the ring walk never visits it.
	foe["position"] = Vector2(100, 0)
	got = combat._nearest_hostile(Vector2.ZERO, "humans", 1000.0)
	_check("rebuild: moved-in unit missed without invalidate (documented)",
		got.is_empty())
	# Invalidate -> rebuild picks up the move -> foe found again.
	combat._invalidate_unit_grid()
	got = combat._nearest_hostile(Vector2.ZERO, "humans", 1000.0)
	_check("rebuild: invalidate refreshes", _same_unit(got, foe))
	# Second query without changes reuses the grid (same frame stamp).
	var frame_before: int = combat._unit_grid_frame
	combat._nearest_hostile(Vector2.ZERO, "humans", 1000.0)
	_check("rebuild: no rebuild when frame unchanged",
		combat._unit_grid_frame == frame_before)
	_free_world(w)


## No units at all -> empty, no crash.
func _test_empty() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	combat._invalidate_unit_grid()
	var got: Dictionary = combat._nearest_hostile(Vector2.ZERO,
		"humans", 1000.0)
	_check("empty: no units -> empty", got.is_empty())
	_free_world(w)
