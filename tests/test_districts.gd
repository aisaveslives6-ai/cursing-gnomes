extends SceneTree
## Cursing Gnomes — district engine headless tests (SimCity-style RCI).
##
## Covers: lot generation, spacing minimums, demand-driven growth,
## development, lot adoption, block road rings, upgrades, desirability,
## save round-trip.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_districts.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


class MockRoads:
	extends RefCounted
	var painted: Array = []  # [{pos, faction, type}]

	func paint_road(pos: Vector2, faction: String, force_type := "") -> void:
		painted.append({"pos": pos, "faction": faction, "type": force_type})


func _initialize() -> void:
	print("=== Cursing Gnomes district tests ===")
	_test_lot_generation()
	_test_lot_spacing()
	_test_demand()
	_test_development()
	_test_adoption()
	_test_block_roads()
	_test_upgrade()
	_test_desirability()
	_test_block_keys()
	_test_save_roundtrip()
	_test_placement_gap_airy()
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
	return {"gs": gs, "buildings": SimBuildings.new(gs)}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _give(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	for res: String in Config.RESOURCES:
		gs.resources.add_resource(faction, res, 1000.0)


func _found(w: Dictionary, faction: String) -> Dictionary:
	var gs: GameState = w["gs"]
	var town: Dictionary = gs.found_town(faction, "T", Vector2(2000, 2000))
	var hall: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		"town_hall", faction, int(town["id"]), Vector2(2000, 2000))
	hall["complete"] = true
	hall["progress"] = 1.0
	return town


func _spawn_pop(w: Dictionary, faction: String, n: int) -> void:
	var gs: GameState = w["gs"]
	for i in n:
		gs.spawner.spawn_unit(faction, "worker", -1,
			Vector2(2000 + i * 4, 2000))


## --- Lot generation --------------------------------------------------------


func _test_lot_generation() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var z: Dictionary = gs.zoning.paint_zone(
		"R", "gnomes", Rect2(0, 0, 432, 432))
	var lots: Array = gs.zoning.ensure_lots(z)
	# 432px / 144px lots -> 3x3 = 9 lots.
	_check("9 lots in 300px zone", lots.size() == 9)
	var all_inside := true
	for lot: Dictionary in lots:
		if not (z["rect"] as Rect2).has_point(lot["pos"]):
			all_inside = false
	_check("lot centers inside zone", all_inside)
	# Cached: second call returns the same array.
	_check("lots cached", gs.zoning.ensure_lots(z) == lots)
	# Absurd zones are skipped (safety cap).
	var big: Dictionary = gs.zoning.paint_zone(
		"C", "gnomes", Rect2(0, 0, 20000, 20000))
	_check("huge zone gets no lots",
		gs.zoning.ensure_lots(big).is_empty())
	_free_world(w)


## --- Spacing ---------------------------------------------------------------


func _test_lot_spacing() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	_give(w, "gnomes")
	_found(w, "gnomes")
	_spawn_pop(w, "gnomes", 30)
	gs.zoning.paint_zone("R", "gnomes", Rect2(0, 0, 600, 600))
	var mock := MockRoads.new()
	# Run until several lots develop (high housing demand: 30 pop, no beds).
	for i in 60:
		gs.zoning.tick_districts(1.0, mock)
	var houses: Array = []
	for b: Dictionary in gs.buildings:
		if bool(b.get("alive", false)) \
				and String(b.get("type", "")) == "house":
			houses.append(b)
	_check("district grew houses", houses.size() >= 2)
	var min_dist := 1e9
	for a in houses:
		for b in houses:
			if a == b:
				continue
			var d: float = (a["position"] as Vector2) \
				.distance_to(b["position"])
			min_dist = minf(min_dist, d)
	_check("houses >= lot spacing apart",
		min_dist >= SimZoning.DISTRICT_LOT - 1.0)
	_free_world(w)


## --- Demand ----------------------------------------------------------------


func _test_demand() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	# No population: demand bottoms out.
	var d0: float = gs.zoning._district_demand("gnomes", "R")
	# Crowded and homeless: demand spikes.
	_spawn_pop(w, "gnomes", 40)
	gs.zoning._demand_cache.clear()
	var d1: float = gs.zoning._district_demand("gnomes", "R")
	_check("R demand rises with housing pressure", d1 > d0)
	_check("R demand is strong when homeless", d1 >= 2.0)
	# Peacetime military demand is low and flat.
	var m: float = gs.zoning._district_demand("gnomes", "M")
	_check("M demand low in peacetime",
		is_equal_approx(m, 1.2))
	_free_world(w)


## --- Development -----------------------------------------------------------


func _test_development() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	_give(w, "gnomes")
	_found(w, "gnomes")
	_spawn_pop(w, "gnomes", 30)
	gs.zoning.paint_zone("R", "gnomes", Rect2(0, 0, 300, 300))
	var mock := MockRoads.new()
	for i in 40:
		gs.zoning.tick_districts(1.0, mock)
	var houses := 0
	for b: Dictionary in gs.buildings:
		if bool(b.get("alive", false)) \
				and String(b.get("type", "")) == "house":
			houses += 1
	_check("R district develops houses from demand", houses >= 1)
	# The developed lot links its building.
	var linked := false
	var z: Dictionary = gs.zoning.zones_of("R", "gnomes")[0]
	for lot: Dictionary in gs.zoning.ensure_lots(z):
		if int(lot.get("building_id", -1)) >= 0:
			linked = true
	_check("developed lot links building", linked)
	_free_world(w)


## --- Adoption --------------------------------------------------------------


func _test_adoption() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	_spawn_pop(w, "gnomes", 30)
	var z: Dictionary = gs.zoning.paint_zone(
		"R", "gnomes", Rect2(0, 0, 300, 300))
	var lots: Array = gs.zoning.ensure_lots(z)
	var lot: Dictionary = lots[0]
	# Player/AI places a house right on the lot by hand.
	var house: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		"house", "gnomes", int(town["id"]), lot["pos"])
	house["complete"] = true
	var mock := MockRoads.new()
	for i in 40:
		gs.zoning.tick_districts(1.0, mock)
	# Other lots may develop, but nothing new may appear on THIS lot.
	var near := 0
	for b: Dictionary in gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		var bp: Vector2 = b.get("position", Vector2.ZERO)
		if bp.distance_to(lot["pos"]) < SimZoning.DISTRICT_LOT * 0.5:
			near += 1
	_check("no double-build on occupied lot", near == 1)
	_check("lot adopts the hand-placed house",
		int(lot.get("building_id", -1)) == int(house.get("id", -2)))
	_free_world(w)


## --- Block road rings ------------------------------------------------------


func _test_block_roads() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	_give(w, "gnomes")
	_found(w, "gnomes")
	_spawn_pop(w, "gnomes", 30)
	gs.zoning.paint_zone("R", "gnomes", Rect2(0, 0, 300, 300))
	var mock := MockRoads.new()
	for i in 40:
		gs.zoning.tick_districts(1.0, mock)
	_check("road ring painted for developed block", mock.painted.size() > 0)
	var minx := 1e9
	var maxx := -1e9
	var miny := 1e9
	var maxy := -1e9
	for r: Dictionary in mock.painted:
		var p: Vector2 = r["pos"]
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
		miny = minf(miny, p.y)
		maxy = maxf(maxy, p.y)
	# A ring around one 288px block spans ~BLOCK_PX on both axes.
	_check("ring spans block width",
		maxx - minx >= SimZoning.BLOCK_PX - SimZoning.ROAD_RING_STEP)
	_check("ring spans block height",
		maxy - miny >= SimZoning.BLOCK_PX - SimZoning.ROAD_RING_STEP)
	# All roads are dirt streets for the faction.
	var all_dirt := true
	for r: Dictionary in mock.painted:
		if String(r["type"]) != "dirt" \
				or String(r["faction"]) != "gnomes":
			all_dirt = false
	_check("ring roads are dirt, own faction", all_dirt)
	_free_world(w)


## --- Upgrades --------------------------------------------------------------


func _test_upgrade() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	_spawn_pop(w, "gnomes", 40)
	var z: Dictionary = gs.zoning.paint_zone(
		"R", "gnomes", Rect2(0, 0, 300, 300))
	var lots: Array = gs.zoning.ensure_lots(z)
	var lot: Dictionary = lots[0]
	var house: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		"house", "gnomes", int(town["id"]), lot["pos"])
	house["complete"] = true
	house["progress"] = 1.0
	lot["building_id"] = int(house.get("id", -1))
	lot["dens"] = 1
	var mock := MockRoads.new()
	# 40 homeless workers -> R demand maxes -> upgrade should fire.
	for i in 10:
		gs.zoning.tick_districts(1.0, mock)
	_check("house upgraded to hotel at high demand",
		int(lot.get("dens", 0)) == 2)
	var nb: Dictionary = gs.get_building(int(lot.get("building_id", -1)))
	_check("upgrade produced a hotel",
		String(nb.get("type", "")) == "hotel")
	_check("old house demolished", not bool(house.get("alive", false)))
	_free_world(w)


## --- Desirability ----------------------------------------------------------


func _test_desirability() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var zr: Dictionary = gs.zoning.paint_zone(
		"R", "gnomes", Rect2(0, 0, 300, 300))
	gs.zoning.paint_zone("I", "gnomes", Rect2(400, 400, 200, 200))
	var near := -1.0
	var far := -1.0
	for lot: Dictionary in gs.zoning.ensure_lots(zr):
		var p: Vector2 = lot["pos"]
		if p.x > 200.0 and p.y > 200.0:
			near = float(lot["desir"])
		if p.x < 100.0 and p.y < 100.0:
			far = float(lot["desir"])
	_check("desirability sampled both lots", near > 0.0 and far > 0.0)
	_check("industry smell lowers R desirability", near < far)
	_free_world(w)


## --- Block keys ------------------------------------------------------------


func _test_block_keys() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var a: Vector2i = gs.zoning._block_key(Vector2(100, 100))
	var b: Vector2i = gs.zoning._block_key(Vector2(200, 200))
	var c: Vector2i = gs.zoning._block_key(Vector2(300, 300))
	_check("same block shares key", a == b)
	_check("other block differs", a != c)
	_free_world(w)


## --- Save round-trip -------------------------------------------------------


func _test_save_roundtrip() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var z: Dictionary = gs.zoning.paint_zone(
		"R", "gnomes", Rect2(10, 20, 300, 400))
	var lots: Array = gs.zoning.ensure_lots(z)
	(lots[0] as Dictionary)["grow"] = 0.33
	(lots[0] as Dictionary)["dens"] = 1
	var data: Dictionary = SaveSystem.snapshot(gs)
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	_check("restore ok", SaveSystem.restore(gs2, data))
	var z2: Dictionary = gs2.zoning.zones_of("R", "gnomes")[0]
	var lots2: Array = gs2.zoning.ensure_lots(z2)
	_check("lot count survives save", lots2.size() == lots.size())
	_check("lot grow survives save",
		is_equal_approx(float(lots2[0]["grow"]), 0.33))
	_check("lot dens survives save", int(lots2[0]["dens"]) == 1)
	gs2.free()
	_free_world(w)


## --- Airy spacing rule -----------------------------------------------------


func _test_placement_gap_airy() -> void:
	# Jeremy 2026-10-06: districts space buildings out more per block.
	_check("AI placement gap is airy",
		SimBuildings.PLACEMENT_GAP >= 90.0)
	_check("district lots are roomy",
		SimZoning.DISTRICT_LOT >= 128.0)
