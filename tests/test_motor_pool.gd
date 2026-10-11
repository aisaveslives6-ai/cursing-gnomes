extends SceneTree
## Cursing Gnomes — military motor pool tests
## (Jeremy 2026-10-10 direct order: roads/vehicles phase P5).
##
## vehicle_depot building def + zoning + AI build queue; assigned lot
## slots; AI fleet funding from treasury surplus (reserve floor, 1/day,
## per-depot cap); player faction never auto-spends (advisor phones
## instead); baggage-train dispatch on war deployment; stand-down re-park;
## parking validation on demolition; save/load.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_motor_pool.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes motor pool tests ===")
	_test_building_def()
	_test_zoning()
	_test_lot_slots()
	_test_free_slot()
	_test_fleet_funding()
	_test_one_per_day()
	_test_reserve_floor()
	_test_fleet_cap()
	_test_player_no_autospend()
	_test_dispatch()
	_test_stand_down()
	_test_parking_validated()
	_test_save_load()
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
	gs.setup(["humans", "ogres"])  # humans = player faction
	var ai := WorkerAI.new(gs)
	gs.worker_ai = ai
	var veh := SimVehicles.new(gs)
	gs.vehicles = veh
	var mp := SimMotorPool.new(gs)
	gs.motor_pool = mp
	return {"gs": gs, "ai": ai, "veh": veh, "mp": mp}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _depot(w: Dictionary, pos: Vector2, faction: String = "ogres",
		complete: bool = true) -> Dictionary:
	var gs: GameState = w["gs"]
	var b := {"id": 200 + gs.buildings.size(), "type": "vehicle_depot",
		"faction": faction, "complete": complete, "alive": true,
		"position": pos, "size": 36.0}
	gs.buildings.append(b)
	return b


func _rich(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	gs.resources.add_resource(faction, "gold", 1000.0, true)
	gs.resources.add_resource(faction, "wood", 500.0, true)


func _soldier(w: Dictionary, pos: Vector2, faction: String = "ogres",
		deployed: bool = false) -> Dictionary:
	var gs: GameState = w["gs"]
	var u := {"id": 700 + gs.units.size(), "job": "soldier",
		"faction": faction, "alive": true, "position": pos,
		"deployed_for_war": deployed}
	gs.units.append(u)
	return u


func _test_building_def() -> void:
	_check("depot def exists", SimBuildings.BUILDINGS.has("vehicle_depot"))
	_check("depot player-buildable",
		SimBuildings.is_player_buildable("vehicle_depot"))
	_check("depot in military tab",
		SimBuildings.build_category("vehicle_depot") == "military")
	_check("depot has sane cost",
		float((SimBuildings.BUILDINGS["vehicle_depot"] as Dictionary)\
			["costs"]["wood"]) > 0.0)


func _test_zoning() -> void:
	_check("depot wants military zone",
		String(SimZoning.BUILDING_ZONE.get("vehicle_depot", "")) == "M")


func _test_lot_slots() -> void:
	var b := {"position": Vector2(100, 100), "size": 36.0}
	var slots: Array = SimMotorPool.lot_slots(b)
	_check("depot lot has 6 slots", slots.size() == 6)
	var south := true
	for s in slots:
		if (s as Vector2).y <= 100.0:
			south = false
	_check("depot lot sits south of the footprint", south)
	var again: Array = SimMotorPool.lot_slots(b)
	_check("depot lot layout deterministic", str(slots) == str(again))
	_check("slot_pos(0) matches", SimMotorPool.slot_pos(b, 0) == slots[0])


func _test_free_slot() -> void:
	var w := _new_world()
	var mp: SimMotorPool = w["mp"]
	var d := _depot(w, Vector2(300, 300))
	_check("fresh depot lot slot 0 free", mp.free_slot(int(d["id"])) == 0)
	var veh: SimVehicles = w["veh"]
	var v := veh.spawn_vehicle("wagon", Vector2.ZERO, "ogres", -1)
	v["military"] = true
	v["parking"] = {"building_id": int(d["id"]), "slot": 0}
	_check("taken slot skipped", mp.free_slot(int(d["id"])) == 1)
	_free_world(w)


func _test_fleet_funding() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var mp: SimMotorPool = w["mp"]
	_depot(w, Vector2(300, 300), "ogres")
	_rich(w, "ogres")
	var gold0: float = gs.resources.get_amount("ogres", "gold")
	var wood0: float = gs.resources.get_amount("ogres", "wood")
	mp.tick(2.5)
	var fleet: Array = mp._fleet("ogres")
	_check("AI faction funds a wagon", fleet.size() == 1)
	var v: Dictionary = fleet[0]
	_check("fleet wagon parked in a lot slot",
		int((v.get("parking", {}) as Dictionary).get("slot", -1)) == 0)
	_check("fleet wagon mission parked",
		String(v.get("mp_mission", "")) == "parked")
	_check("treasury debited gold",
		gs.resources.get_amount("ogres", "gold") < gold0)
	_check("treasury debited wood",
		gs.resources.get_amount("ogres", "wood") < wood0)
	_free_world(w)


func _test_one_per_day() -> void:
	var w := _new_world()
	var mp: SimMotorPool = w["mp"]
	_depot(w, Vector2(300, 300), "ogres")
	_rich(w, "ogres")
	mp.tick(2.5)
	mp.tick(2.5)
	_check("one wagon per faction per day",
		mp._fleet("ogres").size() == 1)
	_free_world(w)


func _test_reserve_floor() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var mp: SimMotorPool = w["mp"]
	_depot(w, Vector2(300, 300), "ogres")
	gs.resources.add_resource("ogres", "gold", 100.0, true)  # below reserve
	gs.resources.add_resource("ogres", "wood", 500.0, true)
	mp.tick(2.5)
	_check("no fleet below the reserve floor",
		mp._fleet("ogres").is_empty())
	_free_world(w)


func _test_fleet_cap() -> void:
	var w := _new_world()
	var mp: SimMotorPool = w["mp"]
	_depot(w, Vector2(300, 300), "ogres")
	_rich(w, "ogres")
	for day in 5:
		mp._buy_day["ogres"] = day - 1  # yesterday: buy allowed again
		mp.tick(2.5)
	_check("fleet capped at 3 per depot",
		mp._fleet("ogres").size() == 3)
	_free_world(w)


func _test_player_no_autospend() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var mp: SimMotorPool = w["mp"]
	_depot(w, Vector2(300, 300), "humans")  # player faction
	_rich(w, "humans")
	var gold0: float = gs.resources.get_amount("humans", "gold")
	mp.tick(2.5)
	_check("player treasury never auto-spent",
		mp._fleet("humans").is_empty())
	_check("player gold untouched",
		gs.resources.get_amount("humans", "gold") == gold0)
	_check("advisor phone nudge throttled 1/day",
		int(mp._advise_day.get("humans", -99)) == int(gs.get("day_number")))
	_free_world(w)


func _test_dispatch() -> void:
	var w := _new_world()
	var mp: SimMotorPool = w["mp"]
	var veh: SimVehicles = w["veh"]
	_depot(w, Vector2(300, 300), "ogres")
	_rich(w, "ogres")
	mp.tick(2.5)  # fund one wagon
	_soldier(w, Vector2(900, 900), "ogres", true)
	_soldier(w, Vector2(940, 900), "ogres", true)
	mp.tick(2.5)  # dispatch scan
	var fleet: Array = mp._fleet("ogres")
	_check("fleet exists for dispatch", fleet.size() == 1)
	var v: Dictionary = fleet[0]
	_check("wagon dispatched as baggage train",
		String(v.get("mp_mission", "")) == "deployed")
	_check("wagon has a drive target near the army",
		bool(v.get("has_target", false)))
	var t: Vector2 = v.get("target", Vector2.ZERO)
	_check("baggage target trails the army centroid",
		t.distance_to(Vector2(920, 900)) < 200.0)
	_free_world(w)


func _test_stand_down() -> void:
	var w := _new_world()
	var mp: SimMotorPool = w["mp"]
	var veh: SimVehicles = w["veh"]
	var d := _depot(w, Vector2(300, 300), "ogres")
	_rich(w, "ogres")
	mp.tick(2.5)
	_soldier(w, Vector2(900, 900), "ogres", true)
	mp.tick(2.5)  # deployed
	var v: Dictionary = mp._fleet("ogres")[0]
	_check("wagon out with the army",
		String(v.get("mp_mission", "")) == "deployed")
	# Army stands down: no deployed units left.
	for u in (w["gs"] as GameState).units:
		(u as Dictionary)["deployed_for_war"] = false
	mp.tick(2.5)
	_check("wagon ordered home on stand-down",
		String(v.get("mp_mission", "")) == "returning")
	# Simulate arrival: physics parks it at the slot.
	veh.park(int(v.get("id", -1)))
	mp.tick(2.5)
	_check("wagon re-parked after arrival",
		String(v.get("mp_mission", "")) == "parked")
	_free_world(w)


func _test_parking_validated() -> void:
	var w := _new_world()
	var mp: SimMotorPool = w["mp"]
	var d := _depot(w, Vector2(300, 300), "ogres")
	_rich(w, "ogres")
	mp.tick(2.5)
	var v: Dictionary = mp._fleet("ogres")[0]
	d["alive"] = false  # depot destroyed
	mp.tick(2.5)
	_check("destroyed depot releases parking",
		(v.get("parking", {}) as Dictionary).is_empty())
	_free_world(w)


func _test_save_load() -> void:
	var w := _new_world()
	var mp: SimMotorPool = w["mp"]
	mp._announced["ogres"] = true
	mp._advise_day["humans"] = 12
	mp._buy_day["ogres"] = 7
	var data := mp.to_dict()
	var mp2 := SimMotorPool.new(w["gs"])
	mp2.from_dict(data)
	_check("announced survives save/load",
		bool(mp2._announced.get("ogres", false)))
	_check("advise day survives save/load",
		int(mp2._advise_day.get("humans", -99)) == 12)
	_check("buy day survives save/load",
		int(mp2._buy_day.get("ogres", -99)) == 7)
	_free_world(w)
