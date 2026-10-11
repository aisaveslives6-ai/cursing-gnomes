extends SceneTree
## Cursing Gnomes — zoning system headless tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_zoning.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes zoning tests ===")
	_test_zone_type_info()
	_test_suggested_zones()
	_test_paint_and_query()
	_test_paint_merge()
	_test_paint_clips_to_map()
	_test_residential_morale()
	_test_industrial_production()
	_test_commercial_gold()
	_test_military_defense()
	_test_dezone()
	_test_zone_changed_signal()
	_test_save_roundtrip()
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


## Fresh game + systems bundle used by every test.
func _new_world(factions: Array[String]) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	var sys := {
		"gs": gs,
		"buildings": SimBuildings.new(gs),
		"ai": WorkerAI.new(gs),
		"combat": SimCombat.new(gs),
	}
	return sys


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _give(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	for res: String in Config.RESOURCES:
		gs.resources.add_resource(faction, res, 1000.0)


func _found(w: Dictionary, faction: String) -> Dictionary:
	var gs: GameState = w["gs"]
	var town: Dictionary = gs.found_town(faction, "T", Vector2(500, 500))
	var hall: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		"town_hall", faction, int(town["id"]), Vector2(500, 500))
	hall["complete"] = true
	hall["progress"] = 1.0
	return town


func _complete(w: Dictionary, btype: String, faction: String, town_id: int,
		pos: Vector2) -> Dictionary:
	var b: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		btype, faction, town_id, pos)
	b["complete"] = true
	b["progress"] = 1.0
	return b


## --- Zone type info --------------------------------------------------------


func _test_zone_type_info() -> void:
	_check("R is a zone type", SimZoning.is_zone_type("R"))
	_check("C is a zone type", SimZoning.is_zone_type("C"))
	_check("I is a zone type", SimZoning.is_zone_type("I"))
	_check("M is a zone type", SimZoning.is_zone_type("M"))
	_check("X is not a zone type", not SimZoning.is_zone_type("X"))
	_check("R name", SimZoning.zone_name("R") == "Residential")
	_check("C name", SimZoning.zone_name("C") == "Commercial")
	_check("I name", SimZoning.zone_name("I") == "Industrial")
	_check("M name", SimZoning.zone_name("M") == "Military")
	_check("R color is green", SimZoning.zone_color("R").g > 0.7)
	_check("C color is blue", SimZoning.zone_color("C").b > 0.9)
	_check("I color is orange", SimZoning.zone_color("I").r > 0.9 \
		and SimZoning.zone_color("I").g > 0.4)
	_check("M color is red", SimZoning.zone_color("M").r > 0.9 \
		and SimZoning.zone_color("M").g < 0.4)


func _test_suggested_zones() -> void:
	_check("house -> R", SimZoning.suggested_zone_for("house") == "R")
	_check("farm -> R", SimZoning.suggested_zone_for("farm") == "R")
	_check("shop -> C", SimZoning.suggested_zone_for("shop") == "C")
	_check("clinic -> C", SimZoning.suggested_zone_for("clinic") == "C")
	_check("sawmill -> I", SimZoning.suggested_zone_for("sawmill") == "I")
	_check("quarry -> I", SimZoning.suggested_zone_for("quarry") == "I")
	_check("mine -> I", SimZoning.suggested_zone_for("mine") == "I")
	_check("barracks -> M", SimZoning.suggested_zone_for("barracks") == "M")
	_check("guard_tower -> M", SimZoning.suggested_zone_for("guard_tower") == "M")
	_check("wall -> M", SimZoning.suggested_zone_for("wall") == "M")
	_check("town_hall -> none", SimZoning.suggested_zone_for("town_hall") == "")
	_check("shop is a building", SimBuildings.is_building("shop"))


## --- Painting --------------------------------------------------------------


func _test_paint_and_query() -> void:
	var w := _new_world(["gnomes", "humans"])
	var gs: GameState = w["gs"]
	var z: Dictionary = gs.zoning.paint_zone(
		"R", "gnomes", Rect2(0, 0, 200, 200))
	_check("paint returns a record", not z.is_empty())
	_check("zone_at inside", gs.zoning.zone_at(Vector2(100, 100), "gnomes") == "R")
	_check("zone_at outside", gs.zoning.zone_at(Vector2(500, 500), "gnomes") == "")
	_check("zones are per-faction",
		gs.zoning.zone_at(Vector2(100, 100), "humans") == "")
	_check("zones_of count", gs.zoning.zones_of("R", "gnomes").size() == 1)
	_check("zone_count", gs.zoning.zone_count("gnomes") == 1)
	_check("bad type rejected",
		gs.zoning.paint_zone("X", "gnomes", Rect2(0, 0, 50, 50)).is_empty())
	_free_world(w)


func _test_paint_merge() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	gs.zoning.paint_zone("R", "gnomes", Rect2(0, 0, 200, 200))
	gs.zoning.paint_zone("R", "gnomes", Rect2(150, 150, 200, 200))
	_check("overlapping paints merge",
		gs.zoning.zones_of("R", "gnomes").size() == 1)
	var merged: Rect2 = gs.zoning.zones_of("R", "gnomes")[0]["rect"]
	_check("merged rect covers both",
		merged.has_point(Vector2(10, 10)) \
		and merged.has_point(Vector2(340, 340)))
	# Different types do NOT merge.
	gs.zoning.paint_zone("C", "gnomes", Rect2(0, 0, 200, 200))
	_check("different types stay separate", gs.zoning.zone_count("gnomes") == 2)
	_free_world(w)


func _test_paint_clips_to_map() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	gs.zoning.map_bounds = Rect2(0, 0, 1000, 1000)
	var z: Dictionary = gs.zoning.paint_zone(
		"I", "gnomes", Rect2(-500, -500, 2000, 2000))
	var r: Rect2 = z["rect"]
	_check("paint clips to map bounds",
		r.position == Vector2.ZERO and r.size == Vector2(1000, 1000))
	_free_world(w)


## --- Residential morale ----------------------------------------------------


func _test_residential_morale() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	gs.zoning.paint_zone("R", "gnomes", Rect2(400, 400, 200, 200))
	var house: Dictionary = _complete(w, "house", "gnomes",
		int(town["id"]), Vector2(500, 500))
	var far_house: Dictionary = _complete(w, "house", "gnomes",
		int(town["id"]), Vector2(900, 900))
	gs.zoning.refresh_all()
	_check("house in R gets morale boost",
		is_equal_approx(float(house.get("zone_morale", 0.0)),
			SimZoning.MORALE_RES_HOME))
	_check("house outside R gets none",
		is_equal_approx(float(far_house.get("zone_morale", 0.0)), 0.0))
	# Industrial smell: house near an industrial zone loses morale.
	gs.zoning.paint_zone("I", "gnomes", Rect2(850, 850, 100, 100))
	gs.zoning.refresh_all()
	_check("house near I loses morale",
		float(far_house.get("zone_morale", 0.0)) < 0.0)
	_free_world(w)


## --- Industrial production -------------------------------------------------


## Runs a farmer for 40 sim-seconds and returns the food hauled to the hall.
func _farm_food(w: Dictionary, faction: String, zoned: bool) -> float:
	var gs: GameState = w["gs"]
	var buildings: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = gs.found_town(faction, "T", Vector2(500, 500))
	var farm: Dictionary = buildings.place_blueprint(
		"farm", faction, int(town["id"]), Vector2(500, 500))
	farm["complete"] = true
	farm["progress"] = 1.0
	var hall: Dictionary = buildings.place_blueprint(
		"town_hall", faction, int(town["id"]), Vector2(500, 500))
	hall["complete"] = true
	hall["progress"] = 1.0
	if zoned:
		gs.zoning.paint_zone("I", faction, Rect2(400, 400, 200, 200))
	var u: Dictionary = gs.spawner.spawn_unit(
		faction, "farmer", int(town["id"]), Vector2(500, 500))
	# Drain to zero: storage caps would clamp production gains otherwise
	# (same as the jobs farm test).
	gs.resources.add_resource(faction, "food", -99999.0)
	# 40 sim-seconds at 0.1 s ticks: fine enough that the 25% gather boost
	# changes how many hauls fit in the window (1 s ticks quantize it away).
	for i: int in range(400):
		ai.tick_unit(u, buildings, 0.1)
	return gs.resources.get_amount(faction, "food")


func _test_industrial_production() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	gs.zoning.paint_zone("I", "gnomes", Rect2(400, 400, 200, 200))
	_check("production mult inside I",
		is_equal_approx(gs.zoning.production_mult_at(
			Vector2(500, 500), "gnomes"), SimZoning.PRODUCTION_MULT))
	_check("production mult outside I",
		is_equal_approx(gs.zoning.production_mult_at(
			Vector2(900, 900), "gnomes"), 1.0))
	_check("production mult is foreign-zone free",
		is_equal_approx(gs.zoning.production_mult_at(
			Vector2(500, 500), "humans"), 1.0))
	_free_world(w)

	# End-to-end: a farmer working a farm inside an industrial zone hauls
	# more food over the same time than one outside.
	var w2 := _new_world(["gnomes"])
	_give(w2, "gnomes")
	var zoned_food: float = _farm_food(w2, "gnomes", true)
	_free_world(w2)
	var w3 := _new_world(["gnomes"])
	_give(w3, "gnomes")
	var plain_food: float = _farm_food(w3, "gnomes", false)
	_free_world(w3)
	_check("industrial zone boosts real harvest",
		zoned_food > plain_food + 1.0)


## --- Commercial gold -------------------------------------------------------


func _test_commercial_gold() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	gs.zoning.paint_zone("C", "gnomes", Rect2(400, 400, 200, 200))
	var shop: Dictionary = _complete(w, "shop", "gnomes",
		int(town["id"]), Vector2(500, 500))
	var lone_shop: Dictionary = _complete(w, "shop", "gnomes",
		int(town["id"]), Vector2(900, 900))
	var before: float = gs.resources.get_amount("gnomes", "gold")
	gs.zoning.tick(10.0)
	var after: float = gs.resources.get_amount("gnomes", "gold")
	_check("shop in C generates gold",
		is_equal_approx(after - before, SimZoning.SHOP_GOLD_PER_SEC * 10.0))
	_check("shop outside C generates nothing",
		gs.zoning.zone_at(
			lone_shop.get("position", Vector2.ZERO), "gnomes") == "")
	_free_world(w)


## --- Military defense ------------------------------------------------------


func _test_military_defense() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	gs.zoning.paint_zone("M", "gnomes", Rect2(400, 400, 200, 200))
	_check("defense mult inside M",
		is_equal_approx(gs.zoning.defense_mult_at(
			Vector2(500, 500), "gnomes"), SimZoning.DEFENSE_MULT))
	_check("defense mult outside M",
		is_equal_approx(gs.zoning.defense_mult_at(
			Vector2(900, 900), "gnomes"), 1.0))
	# Walls finished inside a military zone are tougher.
	var wall: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		"wall", "gnomes", int(town["id"]), Vector2(500, 500))
	var done: bool = (w["buildings"] as SimBuildings).tick_construction(
		wall, 1.0, 15.0)
	_check("wall completes", done)
	_check("military wall is tougher",
		is_equal_approx(float(wall.get("max_hp", 0.0)),
			900.0 * SimZoning.WALL_HP_BONUS))
	# Garrisoned troops recover.
	var u: Dictionary = gs.spawner.spawn_unit(
		"gnomes", "soldier", int(town["id"]), Vector2(500, 500))
	u["hp"] = 50.0
	u["max_hp"] = 100.0
	combat.tick_unit(u, 1.0)
	_check("garrison regen in M",
		is_equal_approx(float(u.get("hp", 0.0)),
			50.0 + SimZoning.GARRISON_REGEN))
	_free_world(w)


## --- Dezone ----------------------------------------------------------------


func _test_dezone() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	gs.zoning.paint_zone("R", "gnomes", Rect2(0, 0, 400, 400))
	var house: Dictionary = _complete(w, "house", "gnomes",
		int(town["id"]), Vector2(300, 100))
	gs.zoning.refresh_all()
	_check("morale before dezone",
		float(house.get("zone_morale", 0.0)) > 0.0)
	# Dezone the right half: the house's zone is clipped away.
	var touched: int = gs.zoning.dezone("gnomes", Rect2(200, 0, 200, 400))
	_check("dezone touches zones", touched > 0)
	_check("dezoned area is clear",
		gs.zoning.zone_at(Vector2(300, 100), "gnomes") == "")
	_check("kept area still zoned",
		gs.zoning.zone_at(Vector2(100, 100), "gnomes") == "R")
	gs.zoning.refresh_all()
	_check("morale gone after dezone",
		is_equal_approx(float(house.get("zone_morale", 0.0)), 0.0))
	# Dezone everything.
	gs.zoning.dezone("gnomes", Rect2(0, 0, 400, 400))
	_check("all zones removed", gs.zoning.zone_count("gnomes") == 0)
	_check("dezone of empty area is a no-op",
		gs.zoning.dezone("gnomes", Rect2(0, 0, 400, 400)) == 0)
	_free_world(w)


func _test_zone_changed_signal() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var fired: Array = [0]
	gs.bus.zone_changed.connect(func() -> void: fired[0] += 1)
	gs.zoning.paint_zone("R", "gnomes", Rect2(0, 0, 100, 100))
	_check("paint emits zone_changed", fired[0] == 1)
	gs.zoning.dezone("gnomes", Rect2(0, 0, 100, 100))
	_check("dezone emits zone_changed", fired[0] == 2)
	gs.zoning.dezone("gnomes", Rect2(500, 500, 100, 100))
	_check("empty dezone stays silent", fired[0] == 2)
	_free_world(w)


## --- Save round-trip -------------------------------------------------------


func _test_save_roundtrip() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	gs.zoning.paint_zone("R", "gnomes", Rect2(10, 20, 300, 400))
	gs.zoning.paint_zone("M", "gnomes", Rect2(500, 500, 100, 100))
	var data: Dictionary = SaveSystem.snapshot(gs)
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	_check("restore ok", SaveSystem.restore(gs2, data))
	_check("zone survives save",
		gs2.zoning.zone_at(Vector2(100, 100), "gnomes") == "R")
	_check("zone rect survives save",
		gs2.zoning.zones_of("R", "gnomes")[0]["rect"] == Rect2(10, 20, 300, 400))
	_check("military zone survives save",
		gs2.zoning.zone_at(Vector2(550, 550), "gnomes") == "M")
	gs2.free()
	_free_world(w)
