extends SceneTree
## Cursing Gnomes — dealership / ownership / assigned parking tests
## (Jeremy 2026-10-10 direct order: roads/vehicles phase P3).
##
## wagon_dealership building def + zoning; citizen vehicle purchases with
## personal coins (priciest affordable first, treasury credited); assigned
## lot slots; trip blocking (military, war-enemy lots, full lots); parking
## validation on demolition; send_home re-park; save/load; water rule.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_dealership.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes dealership tests ===")
	_test_building_def()
	_test_zoning()
	_test_water_rule()
	_test_lot_slots()
	_test_free_slot()
	_test_purchase_flow()
	_test_tier_selection()
	_test_broke_citizen()
	_test_military_blocked()
	_test_war_enemy_skipped()
	_test_full_lot_skipped()
	_test_send_home()
	_test_parking_validated()
	_test_save_load()
	_test_no_double_ownership()
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
	gs.setup(["humans", "ogres"])
	var ai := WorkerAI.new(gs)
	gs.worker_ai = ai
	var veh := SimVehicles.new(gs)
	gs.vehicles = veh
	var deal := SimDealership.new(gs)
	gs.dealership = deal
	gs.bus.unit_said.connect(func(uid: int, text: String) -> void:
		_said.append([uid, text]))
	return {"gs": gs, "ai": ai, "veh": veh, "deal": deal}


func _free_world(w: Dictionary) -> void:
	_said.clear()
	(w["gs"] as GameState).queue_free()


func _dealer(w: Dictionary, pos: Vector2, faction: String = "humans",
		complete: bool = true) -> Dictionary:
	var gs: GameState = w["gs"]
	var b := {"id": 100 + gs.buildings.size(), "type": "wagon_dealership",
		"faction": faction, "complete": complete, "alive": true,
		"position": pos, "size": 36.0}
	gs.buildings.append(b)
	return b


func _citizen(w: Dictionary, pos: Vector2, coins: float,
		job: String = "farmer", faction: String = "humans") -> Dictionary:
	var gs: GameState = w["gs"]
	var u := {"id": 500 + gs.units.size(), "job": job, "faction": faction,
		"alive": true, "position": pos, "coins": coins, "work_state": "idle",
		"speed": 36.0}
	gs.units.append(u)
	return u


## Drives one shopper's trip to completion (trip state pre-seeded so the
## RNG roll is not in the loop).
func _run_trip(w: Dictionary, u: Dictionary, did: int,
		max_ticks: int = 600) -> void:
	var deal: SimDealership = w["deal"]
	u["_dealer_id"] = did
	u["_buying_vehicle"] = true
	for _i in max_ticks:
		if not u.has("_dealer_id"):
			break
		deal._tick_shopper(u, 1.0 / 60.0)


func _test_building_def() -> void:
	_check("dealership def exists",
		SimBuildings.BUILDINGS.has("wagon_dealership"))
	_check("dealership player-buildable",
		SimBuildings.is_player_buildable("wagon_dealership"))
	_check("dealership in services tab",
		SimBuildings.build_category("wagon_dealership") == "services")
	_check("dealership has sane cost",
		float((SimBuildings.BUILDINGS["wagon_dealership"] as Dictionary)\
			["costs"]["wood"]) > 0.0)


func _test_zoning() -> void:
	_check("dealership wants commercial zone",
		String(SimZoning.BUILDING_ZONE.get("wagon_dealership", "")) == "C")
	_check("dealership district-developed",
		(SimZoning.DISTRICT_PICKS["C"] as Array).has("wagon_dealership"))
	_check("dealership capped at 1 per faction",
		int(SimZoning.DISTRICT_PICK_CAPS.get("wagon_dealership", 0)) == 1)


func _test_water_rule() -> void:
	var w := _new_world()
	var terrain := PackedByteArray()
	terrain.resize(128 * 128)
	for i in terrain.size():
		terrain[i] = MapGen.TILE_WATER
	var md := {"terrain": terrain, "tile_size": 32.0,
		"world_size": Vector2(4096, 4096)}
	var rect := Rect2(0, 0, 4096, 4096)
	_check("dealership rejected on water",
		not SimBuildings.can_place_at([], "wagon_dealership",
			Vector2(2048, 2048), rect, "humans", 0.0, [], md))
	_free_world(w)


func _test_lot_slots() -> void:
	var b := {"position": Vector2(500, 500), "size": 36.0}
	var slots: Array = SimDealership.lot_slots(b)
	_check("six lot slots", slots.size() == 6)
	var seen := {}
	var clear := true
	for s in slots:
		var sp: Vector2 = s
		if sp.distance_to(Vector2(500, 500)) <= 18.0:
			clear = false
		seen[Vector2i(sp)] = true
	_check("slots clear of footprint", clear)
	_check("slots distinct", seen.size() == 6)


func _test_free_slot() -> void:
	var w := _new_world()
	var deal: SimDealership = w["deal"]
	var veh: SimVehicles = w["veh"]
	var d := _dealer(w, Vector2(500, 500))
	var did := int(d["id"])
	_check("empty lot: slot 0 free", deal.free_slot(did) == 0)
	var v: Dictionary = veh.spawn_vehicle("cart", Vector2.ZERO, "humans", 1)
	v["parking"] = {"building_id": did, "slot": 0}
	_check("slot 0 taken -> 1 free", deal.free_slot(did) == 1)
	for i in range(1, 6):
		var v2: Dictionary = veh.spawn_vehicle("cart", Vector2.ZERO,
			"humans", 1)
		v2["parking"] = {"building_id": did, "slot": i}
	_check("full lot -> -1", deal.free_slot(did) == -1)
	_free_world(w)


func _test_purchase_flow() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var deal: SimDealership = w["deal"]
	var veh: SimVehicles = w["veh"]
	var d := _dealer(w, Vector2(500, 500))
	var u := _citizen(w, Vector2(500, 530), 100.0)
	var gold0: float = gs.resources.get_amount("humans", "gold")
	_run_trip(w, u, int(d["id"]))
	_check("trip flags cleared", not u.has("_dealer_id") \
		and not u.has("_buying_vehicle"))
	_check("carriage bought (priciest affordable)",
		veh.vehicle_count() == 1 \
		and String((veh.vehicles[0] as Dictionary).get("type", "")) \
			== "carriage")
	var v: Dictionary = veh.vehicles[0]
	_check("coins deducted", float(u.get("coins", -1.0)) == 0.0)
	_check("treasury credited",
		gs.resources.get_amount("humans", "gold") == gold0 + 100.0)
	_check("owner recorded",
		int(v.get("owner_id", -1)) == int(u.get("id", -2)))
	_check("unit owns vehicle",
		int(u.get("vehicle_id", -1)) == int(v.get("id", -2)))
	var pk: Dictionary = v.get("parking", {})
	_check("parking assigned",
		int(pk.get("building_id", -1)) == int(d["id"]) \
		and int(pk.get("slot", -1)) >= 0)
	_check("spawned at its slot",
		(v.get("pos", Vector2.INF) as Vector2).distance_to(
			SimDealership.slot_pos(d, int(pk.get("slot", 0)))) < 1.0)
	_check("purchase line said", _said.size() == 1 \
		and int(_said[0][0]) == int(u.get("id", -1)))
	_free_world(w)


func _test_tier_selection() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var d := _dealer(w, Vector2(500, 500))
	var u := _citizen(w, Vector2(500, 530), 60.0)
	_run_trip(w, u, int(d["id"]))
	_check("60 coins buys wagon",
		String((veh.vehicles[0] as Dictionary).get("type", "")) == "wagon")
	_check("wagon exact change", float(u.get("coins", -1.0)) == 0.0)
	var u2 := _citizen(w, Vector2(500, 530), 35.0)
	_run_trip(w, u2, int(d["id"]))
	_check("35 coins buys cart",
		String((veh.vehicles[1] as Dictionary).get("type", "")) == "cart")
	_free_world(w)


func _test_broke_citizen() -> void:
	var w := _new_world()
	var deal: SimDealership = w["deal"]
	_dealer(w, Vector2(500, 500))
	var u := _citizen(w, Vector2(500, 530), 10.0)
	var started: bool = deal._tick_shopper(u, 1.0 / 60.0)
	_check("broke citizen starts no trip",
		not started and not u.has("_dealer_id"))
	_free_world(w)


func _test_military_blocked() -> void:
	var w := _new_world()
	var deal: SimDealership = w["deal"]
	var veh: SimVehicles = w["veh"]
	var d := _dealer(w, Vector2(500, 500))
	var u := _citizen(w, Vector2(500, 530), 100.0, "soldier")
	_run_trip(w, u, int(d["id"]))
	_check("soldier buys nothing", veh.vehicle_count() == 0)
	_check("soldier trip aborted", not u.has("_dealer_id"))
	_free_world(w)


func _test_war_enemy_skipped() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var deal: SimDealership = w["deal"]
	_dealer(w, Vector2(500, 500), "ogres")
	gs.diplomacy.declare_war("humans", "ogres")
	var u := _citizen(w, Vector2(500, 530), 100.0, "farmer", "humans")
	_check("no shopping behind enemy lines",
		deal._find_dealership(u.get("position", Vector2.ZERO),
			"humans").is_empty())
	_free_world(w)


func _test_full_lot_skipped() -> void:
	var w := _new_world()
	var deal: SimDealership = w["deal"]
	var veh: SimVehicles = w["veh"]
	var d := _dealer(w, Vector2(500, 500))
	var did := int(d["id"])
	for i in 6:
		var v: Dictionary = veh.spawn_vehicle("cart", Vector2.ZERO,
			"humans", 1)
		v["parking"] = {"building_id": did, "slot": i}
	var u := _citizen(w, Vector2(500, 530), 100.0)
	_check("full lot skipped",
		deal._find_dealership(u.get("position", Vector2.ZERO),
			"humans").is_empty())
	_free_world(w)


func _test_send_home() -> void:
	var w := _new_world()
	var deal: SimDealership = w["deal"]
	var veh: SimVehicles = w["veh"]
	var d := _dealer(w, Vector2(500, 500))
	var v: Dictionary = veh.spawn_vehicle("wagon", Vector2(900, 900),
		"humans", 7)
	v["parking"] = {"building_id": int(d["id"]), "slot": 2}
	_check("send_home accepted", deal.send_home(int(v.get("id", -1))))
	var spot := SimDealership.slot_pos(d, 2)
	for _i in 1200:
		veh.tick(1.0 / 60.0)
		if String(v.get("state", "")) == "parked" \
				and not bool(v.get("has_target", false)):
			break
	_check("vehicle re-parked at its slot",
		(v.get("pos", Vector2.INF) as Vector2).distance_to(spot) < 12.0)
	_free_world(w)


func _test_parking_validated() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var deal: SimDealership = w["deal"]
	var veh: SimVehicles = w["veh"]
	var d := _dealer(w, Vector2(500, 500))
	var v: Dictionary = veh.spawn_vehicle("cart", Vector2(500, 560),
		"humans", 7)
	v["parking"] = {"building_id": int(d["id"]), "slot": 0}
	d["alive"] = false  # dealership demolished
	deal._open_scan_t = 99.0  # force the 0.5 Hz validation scan
	deal.tick(1.0 / 60.0)
	_check("demolition releases the slot",
		(v.get("parking", {}) as Dictionary).is_empty())
	_check("vehicle stays parked in place",
		String(v.get("state", "")) == "parked")
	_free_world(w)


func _test_save_load() -> void:
	var w := _new_world()
	var deal: SimDealership = w["deal"]
	var veh: SimVehicles = w["veh"]
	var d := _dealer(w, Vector2(500, 500))
	var v: Dictionary = veh.spawn_vehicle("carriage", Vector2(500, 560),
		"humans", 7)
	v["parking"] = {"building_id": int(d["id"]), "slot": 3}
	deal._announced["humans"] = true
	var d2 := SimDealership.new(w["gs"])
	d2.from_dict(deal.to_dict())
	_check("announced survives save/load",
		bool(d2._announced.get("humans", false)))
	var veh2 := SimVehicles.new(w["gs"])
	veh2.from_dict(veh.to_dict())
	var pv: Dictionary = veh2.vehicle_by_id(int(v.get("id", -1)))
	_check("parking survives save/load",
		int((pv.get("parking", {}) as Dictionary).get("slot", -1)) == 3)
	_free_world(w)


func _test_no_double_ownership() -> void:
	var w := _new_world()
	var deal: SimDealership = w["deal"]
	var veh: SimVehicles = w["veh"]
	var d := _dealer(w, Vector2(500, 500))
	var u := _citizen(w, Vector2(500, 530), 200.0)
	_run_trip(w, u, int(d["id"]))
	_check("one vehicle per citizen", veh.vehicle_count() == 1)
	# Already owns one: starting another trip is blocked.
	_check("owner blocked from second trip",
		not deal._tick_shopper(u, 1.0 / 60.0))
	_free_world(w)
