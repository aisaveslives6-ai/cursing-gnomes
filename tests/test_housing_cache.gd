extends SceneTree
## Cursing Gnomes — housing per-walk cache tests (2026-10-04, R25 2026-10-05).
##
## The 2026-10-04 optimization made _list_houses() build per-walk caches
## (town/countryside house counts, for-sale lists, hall positions) so the
## per-homeless-unit full building scans became cache lookups. R25 (2026-10-05)
## staggered the _list_houses() walk itself to 20Hz (every 3rd tick): the
## cache is a walk-start snapshot, refreshed every 3rd tick. These tests
## prove the cached answers EXACTLY match the live computation across
## mixed layouts (town houses, flagged countryside houses, distance-based
## countryside houses, under-construction houses, dead houses), that the
## cache invalidates correctly, and that buy-home still works through it.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_housing_cache.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes housing-cache tests ===")
	_test_count_cache_equivalence()
	_test_cache_invalidation()
	_test_buy_home_through_cache()
	_test_forsale_listing()
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


func _new_world(factions: Array[String]) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	for faction: String in factions:
		for res: String in Config.RESOURCES:
			gs.resources.add_resource(faction, res, 10000.0, true)
	return {
		"gs": gs,
		"buildings": SimBuildings.new(gs),
		"housing": SimHousing.new(gs),
	}


func _brute_town_count(gs: GameState, housing: SimHousing, faction: String,
		town_id: int) -> int:
	var n := 0
	for b: Dictionary in gs.buildings:
		if not b.get("alive", false) \
				or String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) != "house":
			continue
		if housing._is_countryside_house(b):
			continue
		if int(b.get("town_id", -2)) != town_id:
			continue
		n += 1
	return n


func _brute_country_count(gs: GameState, housing: SimHousing,
		faction: String) -> int:
	var n := 0
	for b: Dictionary in gs.buildings:
		if not b.get("alive", false) \
				or String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) != "house":
			continue
		if housing._is_countryside_house(b):
			n += 1
	return n


func _house(w: Dictionary, faction: String, town_id: int, pos: Vector2,
		complete: bool, countryside: bool) -> Dictionary:
	var bs: SimBuildings = w["buildings"]
	var h: Dictionary = bs.place_blueprint("house", faction, town_id, pos)
	if complete:
		h["complete"] = true
		h["progress"] = 1.0
	if countryside:
		h["countryside"] = true
	return h


func _test_count_cache_equivalence() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var town: Dictionary = gs.found_town("gnomes", "T", Vector2(500, 500))
	var hall: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		"town_hall", "gnomes", int(town["id"]), Vector2(500, 500))
	hall["complete"] = true
	var tid: int = int(town["id"])
	# Mixed layout: town houses (complete + under construction), a dead
	# house, a flagged countryside house, and a distance-based countryside
	# house (far from any town).
	_house(w, "gnomes", tid, Vector2(600, 500), true, false)
	_house(w, "gnomes", tid, Vector2(680, 500), true, false)
	var uc: Dictionary = _house(w, "gnomes", tid, Vector2(760, 500),
		false, false)
	var dead: Dictionary = _house(w, "gnomes", tid, Vector2(840, 500),
		true, false)
	dead["alive"] = false
	_house(w, "gnomes", -1, Vector2(2000, 2000), true, true)
	_house(w, "gnomes", tid, Vector2(3000, 3000), true, false)
	# A rival faction's house must not leak into gnomes' counts.
	_house(w, "ogres", tid, Vector2(620, 520), true, false)
	housing.tick(1.0 / 60.0)  # builds the cache
	_check("cached town count == live",
		housing.town_house_count("gnomes", tid) \
			== _brute_town_count(gs, housing, "gnomes", tid))
	_check("cached country count == live",
		housing.countryside_house_count("gnomes") \
			== _brute_country_count(gs, housing, "gnomes"))
	_check("town count excludes under-construction? (live parity)",
		housing.town_house_count("gnomes", tid) \
			== _brute_town_count(gs, housing, "gnomes", tid))
	# Spot-check the actual numbers: 2 complete town houses + 1 under
	# construction (live counts built-or-not) = 3 town; 2 countryside.
	_check("town count == 3", housing.town_house_count("gnomes", tid) == 3)
	_check("country count == 2",
		housing.countryside_house_count("gnomes") == 2)
	gs.queue_free()


func _test_cache_invalidation() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var town: Dictionary = gs.found_town("gnomes", "T", Vector2(500, 500))
	var tid: int = int(town["id"])
	_house(w, "gnomes", tid, Vector2(600, 500), true, false)
	housing.tick(1.0 / 60.0)
	_check("warm cache == 1", housing.town_house_count("gnomes", tid) == 1)
	# Snapshot semantics (R25): the cache is a walk-start snapshot refreshed
	# every 3rd tick (20Hz), so a house placed after a walk isn't visible
	# until the next walk. (The build path that enforces caps uses the live
	# count — see _homestead_try_build.)
	_house(w, "gnomes", tid, Vector2(680, 500), true, false)
	_check("pre-walk snapshot still == 1",
		housing.town_house_count("gnomes", tid) == 1)
	for i in range(3):
		housing.tick(1.0 / 60.0)
	_check("walk refreshes cache == 2",
		housing.town_house_count("gnomes", tid) == 2)
	# A housing system that never ticked computes live.
	var h2: SimHousing = SimHousing.new(gs)
	_check("never-ticked housing computes live == 2",
		h2.town_house_count("gnomes", tid) == 2)
	gs.queue_free()


func _test_buy_home_through_cache() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var town: Dictionary = gs.found_town("gnomes", "T", Vector2(500, 500))
	var tid: int = int(town["id"])
	# Empty house near the unit; unit has coins and no home.
	var h: Dictionary = _house(w, "gnomes", tid, Vector2(520, 500),
		true, false)
	# Listing happens on tick, before any buyer exists.
	housing.tick(1.0 / 60.0)
	_check("house listed for sale", bool(h.get("for_sale", false)))
	# Now the homeless buyer arrives with coins.
	var u: Dictionary = {
		"id": 7, "alive": true, "faction": "gnomes", "job": "worker",
		"town_id": tid, "position": Vector2(500, 500), "coins": 500.0,
		"work_state": "idle",
	}
	gs.units.append(u)
	for i in range(10):
		housing.tick(1.0 / 60.0)
	_check("homeless unit bought the house", u.has("home"))
	_check("sale closed (owner set)", int(h.get("owner_unit", -1)) == 7)
	gs.queue_free()


func _test_forsale_listing() -> void:
	# Listing still marks empty completed houses (HTML adoptLegacyHousing).
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var town: Dictionary = gs.found_town("gnomes", "T", Vector2(500, 500))
	var tid: int = int(town["id"])
	var h1: Dictionary = _house(w, "gnomes", tid, Vector2(600, 500),
		true, false)
	var h2: Dictionary = _house(w, "gnomes", tid, Vector2(700, 500),
		false, false)
	housing.tick(1.0 / 60.0)
	_check("empty complete house listed", bool(h1.get("for_sale", false)))
	_check("empty complete house priced", float(h1.get("price", 0.0)) > 0.0)
	_check("under-construction house not listed",
		not bool(h2.get("for_sale", false)))
	gs.queue_free()
