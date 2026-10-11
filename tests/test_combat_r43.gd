extends SceneTree
## Cursing Gnomes — Perf R43 hostile-presence early-out tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_combat_r43.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: the _faction_alive tally (counts, dead/downed exclusion, refresh),
## the peacetime early-out returning {}, and brute-force oracle equivalence of
## _nearest_hostile on randomized war/peace scenes (true nearest, tie-breaks,
## monster hostiles). Deterministic (seeded RNG). No timing gates — the 28.5x
## scan speedup was proven by stub A/B (perf_r43_stub_tmp, 8/8 green).

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


class MockDiplomacy:
	var relation_version := 1
	var hostile_pairs := {}
	func combat_enabled(a: String, b: String) -> bool:
		var k1 := a + "|" + b
		var k2 := b + "|" + a
		return bool(hostile_pairs.get(k1, hostile_pairs.get(k2, false)))


func _initialize() -> void:
	print("=== Cursing Gnomes R43 hostile-presence early-out tests ===")
	_test_tally_counts()
	_test_tally_excludes_dead_and_downed()
	_test_tally_refreshes()
	_test_peace_early_out()
	_test_monster_hostile_in_peace()
	_test_oracle_equivalence()
	_test_tie_break()
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


func _make_combat() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	var combat := SimCombat.new(gs)
	var dip := MockDiplomacy.new()
	combat.diplomacy = dip
	return [gs, combat, dip]


func _free_game(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


func _add_unit(gs: GameState, faction: String, pos: Vector2,
		alive: bool = true, downed: bool = false) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": "soldier", "town_id": 1,
		"position": pos, "alive": alive, "downed": downed,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0})


func _sync(parts: Array) -> void:
	# Force the grid (+tally) rebuild the way the documented test contract
	# requires after structural changes.
	(parts[1] as SimCombat)._invalidate_unit_grid()
	(parts[1] as SimCombat)._nearest_hostile(
		Vector2(2000, 2000), "humans", 600.0)


## Brute-force oracle: the true nearest hostile by the scan's exact rules.
func _oracle(gs: GameState, combat: SimCombat, upos: Vector2,
		faction: String, max_dist: float) -> int:
	var best := -1
	var best_d2 := max_dist * max_dist
	var best_idx := -1
	var idx := 0
	for u in (gs as GameState).units:
		var ud: Dictionary = u
		if bool(ud.get("alive", false)) and not bool(ud.get("downed", false)) \
				and combat.can_fight(faction, String(ud.get("faction", ""))):
			var d2: float = upos.distance_squared_to(
				ud.get("position", Vector2.ZERO))
			if d2 < best_d2 or (best_idx >= 0 and d2 == best_d2 \
					and idx < best_idx):
				best_d2 = d2
				best_idx = idx
				best = int(ud.get("id", -999))
		idx += 1
	return best


func _scan_id(parts: Array, upos: Vector2, faction: String,
		max_dist: float) -> int:
	var res: Dictionary = (parts[1] as SimCombat)._nearest_hostile(
		upos, faction, max_dist)
	return int(res.get("id", -1)) if not res.is_empty() else -1


func _test_tally_counts() -> void:
	var parts := _make_combat()
	var gs: GameState = parts[0]
	_add_unit(gs, "humans", Vector2(500, 500))
	_add_unit(gs, "humans", Vector2(520, 500))
	_add_unit(gs, "ogres", Vector2(900, 900))
	_add_unit(gs, "ogres", Vector2(920, 900))
	_add_unit(gs, "ogres", Vector2(940, 900))
	_sync(parts)
	var tally: Dictionary = (parts[1] as SimCombat)._faction_alive
	_check("tally: humans == 2", int(tally.get("humans", -1)) == 2)
	_check("tally: ogres == 3", int(tally.get("ogres", -1)) == 3)
	_check("tally: gnomes absent (0)", int(tally.get("gnomes", 0)) == 0)
	_free_game(parts)


func _test_tally_excludes_dead_and_downed() -> void:
	var parts := _make_combat()
	var gs: GameState = parts[0]
	_add_unit(gs, "humans", Vector2(500, 500), true, false)
	_add_unit(gs, "humans", Vector2(520, 500), false, false)  # dead
	_add_unit(gs, "humans", Vector2(540, 500), true, true)  # downed
	_sync(parts)
	var tally: Dictionary = (parts[1] as SimCombat)._faction_alive
	_check("tally: dead and downed excluded (humans == 1)",
		int(tally.get("humans", -1)) == 1)
	_free_game(parts)


func _test_tally_refreshes() -> void:
	var parts := _make_combat()
	var gs: GameState = parts[0]
	var u := _add_unit(gs, "ogres", Vector2(900, 900))
	_sync(parts)
	_check("tally: ogres == 1 before death",
		int((parts[1] as SimCombat)._faction_alive.get("ogres", -1)) == 1)
	u["alive"] = false
	_sync(parts)  # invalidate + rebuild, per the test contract
	_check("tally: ogres == 0 after death+invalidate",
		int((parts[1] as SimCombat)._faction_alive.get("ogres", 0)) == 0)
	_add_unit(gs, "gnomes", Vector2(300, 300))
	_sync(parts)
	_check("tally: gnomes == 1 after spawn",
		int((parts[1] as SimCombat)._faction_alive.get("gnomes", -1)) == 1)
	_free_game(parts)


func _test_peace_early_out() -> void:
	var parts := _make_combat()
	var gs: GameState = parts[0]
	# MockDiplomacy defaults to no hostile pairs: total peace.
	_add_unit(gs, "humans", Vector2(500, 500))
	_add_unit(gs, "ogres", Vector2(900, 900))
	_add_unit(gs, "gnomes", Vector2(1300, 1300))
	for q in [Vector2(500, 500), Vector2(2000, 2000), Vector2(100, 3000)]:
		_check("peace: early-out returns {} (no hostiles)",
			_scan_id(parts, q, "humans", 600.0) == -1)
	_free_game(parts)


func _test_monster_hostile_in_peace() -> void:
	var parts := _make_combat()
	var gs: GameState = parts[0]
	_add_unit(gs, "humans", Vector2(500, 500))
	var m := _add_unit(gs, "monster", Vector2(600, 500))
	_sync(parts)
	# Monsters are hostile outside diplomacy: the tally counts them and the
	# early-out must NOT fire.
	_check("tally: monster counted",
		int((parts[1] as SimCombat)._faction_alive.get("monster", -1)) == 1)
	_check("peace: monster still found as hostile",
		_scan_id(parts, Vector2(500, 500), "humans", 600.0) == int(m.get("id", -2)))
	_free_game(parts)


func _test_oracle_equivalence() -> void:
	var parts := _make_combat()
	var gs: GameState = parts[0]
	var dip: MockDiplomacy = parts[2]
	dip.hostile_pairs = {"humans|ogres": true}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	var factions := ["humans", "gnomes", "ogres"]
	var n := 0
	for trial in range(10):
		# Fresh scene each trial.
		for u in gs.units:
			(u as Dictionary)["alive"] = false
		for i in range(30):
			var f: String = factions[rng.randi() % 3]
			var p := Vector2(rng.randf() * 3000.0 + 200.0,
				rng.randf() * 3000.0 + 200.0)
			var r := rng.randf()
			_add_unit(gs, f, p, r >= 0.1, r < 0.1 and r >= 0.05)
		if trial % 3 == 0:
			_add_unit(gs, "monster",
				Vector2(rng.randf() * 3000.0 + 200.0, 1500.0))
		(parts[1] as SimCombat)._invalidate_unit_grid()
		for q in range(6):
			var f: String = factions[rng.randi() % 3]
			var p := Vector2(rng.randf() * 3200.0 + 100.0,
				rng.randf() * 3200.0 + 100.0)
			var d := 250.0 + rng.randf() * 600.0
			var got := _scan_id(parts, p, f, d)
			var want := _oracle(gs, parts[1], p, f, d)
			n += 1
			if got != want:
				_check("oracle equiv trial %d q %d: got %d want %d"
					% [trial, q, got, want], false)
				_free_game(parts)
				return
	_check("oracle: _nearest_hostile bit-identical on %d queries" % n, true)
	_free_game(parts)


func _test_tie_break() -> void:
	var parts := _make_combat()
	var gs: GameState = parts[0]
	var dip: MockDiplomacy = parts[2]
	dip.hostile_pairs = {"humans|ogres": true}
	_add_unit(gs, "humans", Vector2(500, 500))
	var a := _add_unit(gs, "ogres", Vector2(600, 500))
	var b := _add_unit(gs, "ogres", Vector2(400, 500))
	# a and b are equidistant (100px) from the querier; the lower
	# units-array index must win, matching the old first-match order.
	var want_id := int(a.get("id", -2)) if gs.units.find(a) < gs.units.find(b) \
		else int(b.get("id", -2))
	_check("tie-break: lowest units-array index wins",
		_scan_id(parts, Vector2(500, 500), "humans", 600.0) == want_id)
	_free_game(parts)
