extends SceneTree
## Cursing Gnomes — housing 20Hz walk-stagger tests (R25, 2026-10-05).
##
## R25 staggered the _list_houses() building walk + occupancy repair to
## every 3rd tick (20Hz). The cache readers accept the last walk's data
## (up to 2 frames old) via _cc_fresh(). These tests prove:
##   - the walk runs on ticks 1, 4, 7... (and not on off-frames),
##   - readers use the walk cache on off-frames (no live-scan fallback),
##   - two buyers racing one listing in the same walk window can't
##     double-buy (owner_unit / for_sale guards),
##   - occupancy repair still frees dead residents' beds across the stagger,
##   - cached counts exactly match the live computation at walk ticks.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_housing_stagger_r25.gd
##
## Exit code 0 = all passed, 1 = any failure.


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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	for res: String in Config.RESOURCES:
		gs.resources.add_resource("gnomes", res, 10000.0, true)
	var housing := SimHousing.new(gs)
	var bs := SimBuildings.new(gs)
	var town: Dictionary = gs.found_town("gnomes", "T", Vector2(500, 500))
	return {"gs": gs, "housing": housing, "buildings": bs,
		"tid": int(town["id"])}


func _house(w: Dictionary, pos: Vector2, complete: bool) -> Dictionary:
	var bs: SimBuildings = w["buildings"]
	var h: Dictionary = bs.place_blueprint("house", "gnomes",
		int(w["tid"]), pos)
	if complete:
		h["complete"] = true
		h["progress"] = 1.0
	return h


func _brute_town_count(w: Dictionary) -> int:
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var n := 0
	for b: Dictionary in gs.buildings:
		if not b.get("alive", false) \
				or String(b.get("faction", "")) != "gnomes":
			continue
		if String(b.get("type", "")) != "house":
			continue
		if housing._is_countryside_house(b):
			continue
		if int(b.get("town_id", -2)) != int(w["tid"]):
			continue
		n += 1
	return n


func _test_walk_cadence() -> void:
	var w := _new_world()
	var housing: SimHousing = w["housing"]
	_house(w, Vector2(600, 500), true)
	housing.tick(1.0 / 60.0)  # tick 1
	_check("walk runs on tick 1", housing._cc_tick == 1)
	housing.tick(1.0 / 60.0)  # tick 2
	_check("no walk on tick 2", housing._cc_tick == 1)
	housing.tick(1.0 / 60.0)  # tick 3
	_check("no walk on tick 3", housing._cc_tick == 1)
	housing.tick(1.0 / 60.0)  # tick 4
	_check("walk runs on tick 4", housing._cc_tick == 4)
	(w["gs"] as GameState).queue_free()


func _test_offframe_cache_read() -> void:
	var w := _new_world()
	var housing: SimHousing = w["housing"]
	_house(w, Vector2(600, 500), true)
	housing.tick(1.0 / 60.0)  # tick 1: walk, cache == 1
	_check("cache fresh on walk tick", housing._cc_fresh())
	_house(w, Vector2(680, 500), true)  # placed after the walk
	housing.tick(1.0 / 60.0)  # tick 2: no walk
	_check("cache still fresh on off-frame", housing._cc_fresh())
	# Stale read proves the cache (not a live scan) served the off-frame.
	_check("off-frame read is the walk snapshot (1, not 2)",
		housing.town_house_count("gnomes", int(w["tid"])) == 1)
	housing.tick(1.0 / 60.0)  # tick 3: no walk
	_check("cache fresh on 2nd off-frame", housing._cc_fresh())
	_check("2nd off-frame still snapshot",
		housing.town_house_count("gnomes", int(w["tid"])) == 1)
	housing.tick(1.0 / 60.0)  # tick 4: walk
	_check("walk picks up the new house",
		housing.town_house_count("gnomes", int(w["tid"])) == 2)
	_check("walk count == live count",
		housing.town_house_count("gnomes", int(w["tid"])) \
			== _brute_town_count(w))
	(w["gs"] as GameState).queue_free()


func _test_no_double_sale_in_walk_window() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var h: Dictionary = _house(w, Vector2(520, 500), true)
	housing.tick(1.0 / 60.0)  # tick 1: walk lists the house
	_check("house listed", bool(h.get("for_sale", false)))
	# Two homeless buyers with coins arrive in the same walk window.
	var u1: Dictionary = {"id": 11, "alive": true, "faction": "gnomes",
		"job": "worker", "town_id": int(w["tid"]),
		"position": Vector2(500, 500), "coins": 500.0,
		"work_state": "idle"}
	var u2: Dictionary = {"id": 12, "alive": true, "faction": "gnomes",
		"job": "worker", "town_id": int(w["tid"]),
		"position": Vector2(500, 500), "coins": 500.0,
		"work_state": "idle"}
	gs.units.append(u1)
	gs.units.append(u2)
	for i in range(6):
		housing.tick(1.0 / 60.0)
	var got1: bool = u1.has("home")
	var got2: bool = u2.has("home")
	_check("exactly one buyer got the house", got1 != got2)
	_check("owner_unit set to the winner",
		int(h.get("owner_unit", -1)) == (11 if got1 else 12))
	_check("house no longer for sale", not bool(h.get("for_sale", false)))
	gs.queue_free()


func _test_repair_across_stagger() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var h: Dictionary = _house(w, Vector2(600, 500), true)
	# Occupy the house with one resident.
	var u: Dictionary = {"id": 21, "alive": true, "faction": "gnomes",
		"job": "worker", "town_id": int(w["tid"]),
		"position": Vector2(600, 500), "work_state": "idle"}
	gs.units.append(u)
	h["residents"] = [21]
	u["home"] = h
	housing.tick(1.0 / 60.0)  # tick 1: walk repairs (nothing to do)
	_check("resident kept while alive",
		(h["residents"] as Array) == [21])
	# Resident dies; the bed must free on a later walk (<=3 ticks out).
	u["alive"] = false
	for i in range(6):
		housing.tick(1.0 / 60.0)
	_check("dead resident pruned", (h["residents"] as Array).is_empty())
	_check("deed cleared", int(h.get("owner_unit", -1)) == -1)
	gs.queue_free()


func _test_never_ticked_live_fallback() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	_house(w, Vector2(600, 500), true)
	_house(w, Vector2(680, 500), true)
	# No tick yet: readers must compute live, not serve an empty cache.
	_check("never-ticked cache not fresh", not housing._cc_fresh())
	_check("never-ticked count live == 2",
		housing.town_house_count("gnomes", int(w["tid"])) == 2)
	gs.queue_free()


func _initialize() -> void:
	print("=== Cursing Gnomes housing-stagger R25 tests ===")
	_test_walk_cadence()
	_test_offframe_cache_read()
	_test_no_double_sale_in_walk_window()
	_test_repair_across_stagger()
	_test_never_ticked_live_fallback()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
