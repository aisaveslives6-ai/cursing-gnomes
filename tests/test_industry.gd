extends SceneTree
## Cursing Gnomes — industry headless tests (Jeremy 2026-10-05).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_industry.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
##
## Covers Jeremy's 2026-10-05 oil design order: oil comes ONLY from oil
## pumps (0.8/s each inside an industrial zone, via SimZoning.tick). The
## retired HTML lot-oil rate must pay ZERO oil on industrial buildings —
## even pumps (no double-dip) — while lots keep their verbatim wood/gold.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes industry tests ===")
	_test_lot_pays_no_oil()
	_test_lot_keeps_wood_gold()
	_test_lot_outside_zone_pays_nothing()
	_test_pump_oil_in_izone()
	_test_pump_no_oil_outside_izone()
	_test_pump_not_double_dipped()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, ok: bool) -> void:
	if ok:
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
		"industry": SimIndustry.new(gs),
	}
	return sys


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _give(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	for res: String in Config.RESOURCES:
		gs.resources.add_resource(faction, res, 10000.0, true)


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


## Jeremy 2026-10-05: industrial lots pay NO oil (pumps-only design).
func _test_lot_pays_no_oil() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var ind: SimIndustry = w["industry"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	gs.zoning.paint_zone("I", "gnomes", Rect2(400, 400, 200, 200))
	_complete(w, "sawmill", "gnomes", int(town["id"]), Vector2(500, 500))
	gs.resources.add_resource("gnomes", "oil", -99999.0, true)
	_check("oil starts at zero", gs.resources.get_amount("gnomes", "oil") == 0.0)
	for i: int in range(600):
		ind._tick_lot_production(1.0)
	_check("lot oil retired: zero oil after 600s of lot ticks",
		gs.resources.get_amount("gnomes", "oil") == 0.0)
	_free_world(w)


## Wood/gold lot payouts stay HTML-verbatim (1.8/h and 1.4/h).
func _test_lot_keeps_wood_gold() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var ind: SimIndustry = w["industry"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	gs.zoning.paint_zone("I", "gnomes", Rect2(400, 400, 200, 200))
	_complete(w, "sawmill", "gnomes", int(town["id"]), Vector2(500, 500))
	# Zero the ledgers first: the tick path is cap-clamped, so a granted
	# balance above the cap would be pulled DOWN by clampf on the first add.
	gs.resources.add_resource("gnomes", "wood", -99999.0, true)
	gs.resources.add_resource("gnomes", "gold", -99999.0, true)
	var w0: float = gs.resources.get_amount("gnomes", "wood")
	var g0: float = gs.resources.get_amount("gnomes", "gold")
	for i: int in range(600):
		ind._tick_lot_production(1.0)
	_check("lot still pays wood at verbatim rate",
		is_equal_approx(gs.resources.get_amount("gnomes", "wood") - w0, 0.3))
	_check("lot still pays gold at verbatim rate",
		is_equal_approx(gs.resources.get_amount("gnomes", "gold") - g0,
			1.4 / 6.0))
	_free_world(w)


## Industrial buildings outside the faction's I zone pay nothing at all.
func _test_lot_outside_zone_pays_nothing() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var ind: SimIndustry = w["industry"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	var mill: Dictionary = _complete(w, "sawmill", "gnomes",
		int(town["id"]), Vector2(900, 900))
	_check("sawmill is outside the I zone",
		gs.zoning.zone_at(
			mill.get("position", Vector2.ZERO), "gnomes") == "")
	var w0: float = gs.resources.get_amount("gnomes", "wood")
	for i: int in range(60):
		ind._tick_lot_production(1.0)
	_check("lone sawmill gains no wood",
		is_equal_approx(gs.resources.get_amount("gnomes", "wood"), w0))
	_free_world(w)


## The pump path (SimZoning.tick) is the only oil source: 0.8/s in an I zone.
func _test_pump_oil_in_izone() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	gs.zoning.paint_zone("I", "gnomes", Rect2(400, 400, 200, 200))
	_complete(w, "oil_pump", "gnomes", int(town["id"]), Vector2(500, 500))
	gs.resources.add_resource("gnomes", "oil", -99999.0, true)
	var before: float = gs.resources.get_amount("gnomes", "oil")
	gs.zoning.tick(10.0)
	var after: float = gs.resources.get_amount("gnomes", "oil")
	_check("pump in I generates 0.8 oil/s",
		is_equal_approx(after - before, 8.0))
	_free_world(w)


## Pumps outside an industrial zone produce nothing (Jeremy's order).
func _test_pump_no_oil_outside_izone() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	_complete(w, "oil_pump", "gnomes", int(town["id"]), Vector2(900, 900))
	gs.resources.add_resource("gnomes", "oil", -99999.0, true)
	var before: float = gs.resources.get_amount("gnomes", "oil")
	gs.zoning.tick(10.0)
	var after: float = gs.resources.get_amount("gnomes", "oil")
	_check("pump outside I generates no oil",
		is_equal_approx(after - before, 0.0))
	_free_world(w)


## A pump in an I zone gets its 0.8/s from zoning only — the lot tick must
## not pay it extra oil (the old double-dip).
func _test_pump_not_double_dipped() -> void:
	var w := _new_world(["gnomes"])
	var gs: GameState = w["gs"]
	var ind: SimIndustry = w["industry"]
	_give(w, "gnomes")
	var town: Dictionary = _found(w, "gnomes")
	gs.zoning.paint_zone("I", "gnomes", Rect2(400, 400, 200, 200))
	_complete(w, "oil_pump", "gnomes", int(town["id"]), Vector2(500, 500))
	gs.resources.add_resource("gnomes", "oil", -99999.0, true)
	for i: int in range(600):
		ind._tick_lot_production(1.0)
	_check("lot tick pays no oil to pumps either",
		gs.resources.get_amount("gnomes", "oil") == 0.0)
	_free_world(w)
