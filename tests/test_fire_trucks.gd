extends SceneTree
## Cursing Gnomes — fire-truck dispatch tests (Jeremy 2026-10-10 direct
## order: real fire-truck dispatch replaces the rapid-response-speed
## abstraction).
##
## Full loop: every complete fire station owns one parked firetruck at its
## lot (real SimVehicles record, physics-driven); firefighters mount up at
## the lot, ride with driving physics, dismount to fight the fire, ride
## back, and re-park. Legacy speed-boost/fake-visual survives only when no
## truck record exists.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_fire_trucks.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes fire-truck dispatch tests ===")
	_test_firetruck_type_registered()
	_test_station_gets_one_parked_truck()
	_test_ensure_is_idempotent()
	_test_far_fire_walks_to_truck_and_boards()
	_test_truck_drives_crew_and_dismounts_at_fire()
	_test_fire_out_truck_returns_and_reparks()
	_test_near_fire_no_truck_ride()
	_test_no_truck_record_legacy_fallback()
	_test_station_destroyed_truck_despawned_crew_released()
	_test_save_load_keeps_crew()
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


## Dry world: station at (500,500), firefighter + fire station wired.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var ai := WorkerAI.new(gs)
	gs.worker_ai = ai
	var veh := SimVehicles.new(gs)
	gs.vehicles = veh
	var combat := SimCombat.new(gs)
	var dis := DisasterSim.new(gs, combat)
	var station := {"id": 1, "type": "fire_station", "faction": "humans",
		"complete": true, "alive": true, "position": Vector2(500, 500)}
	gs.buildings.append(station)
	var ff := {"id": 10, "job": "firefighter", "faction": "humans",
		"alive": true, "position": Vector2(500, 500)}
	gs.units.append(ff)
	return {"gs": gs, "ai": ai, "veh": veh, "dis": dis,
		"station": station, "ff": ff}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _lot(dis: DisasterSim, st: Dictionary) -> Vector2:
	return dis._station_lot(st)


func _add_fire(dis: DisasterSim, pos: Vector2,
		intensity: float = 100.0) -> Dictionary:
	var f := {"id": 7, "position": pos, "intensity": intensity}
	dis.fires.append(f)
	return f


## One sim tick: firefighter brain + truck driver + vehicle physics.
func _tick_all(w: Dictionary, delta: float = 1.0 / 60.0) -> void:
	(w["dis"] as DisasterSim).tick_firefighter(w["ff"], delta)
	(w["dis"] as DisasterSim).tick_station_trucks(delta)
	(w["veh"] as SimVehicles).tick(delta)


func _test_firetruck_type_registered() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v: Dictionary = veh.spawn_vehicle("firetruck",
		Vector2(100, 100), "humans")
	_check("firetruck spawns", not v.is_empty())
	_check("firetruck has crew list", v.has("crew"))
	var t: Dictionary = SimVehicles.TYPES["firetruck"]
	_check("firetruck top speed sane",
		float(t["max_speed"]) > 50.0 and float(t["max_speed"]) < 80.0)
	_free_world(w)


func _test_station_gets_one_parked_truck() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var veh: SimVehicles = w["veh"]
	dis.tick_station_trucks(1.0 / 60.0)
	var tid := int((w["station"] as Dictionary).get("truck_id", -1))
	_check("station got a truck_id", tid > 0)
	var truck := veh.vehicle_by_id(tid)
	_check("truck record live", not truck.is_empty())
	_check("truck parked at the lot",
		String(truck.get("state", "")) == "parked"
		and (truck.get("pos", Vector2.ZERO) as Vector2).distance_to(
			_lot(dis, w["station"])) < 1.0)
	_check("truck is firetruck type",
		String(truck.get("type", "")) == "firetruck")
	_free_world(w)


func _test_ensure_is_idempotent() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var veh: SimVehicles = w["veh"]
	for _i in 3:
		dis.tick_station_trucks(1.0 / 60.0)
	var n := 0
	for v in veh.vehicles:
		if String(v.get("type", "")) == "firetruck":
			n += 1
	_check("exactly one truck after 3 ticks", n == 1)
	_free_world(w)


func _test_far_fire_walks_to_truck_and_boards() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var veh: SimVehicles = w["veh"]
	dis.tick_station_trucks(1.0 / 60.0)
	_add_fire(dis, Vector2(1500, 500))
	var ff: Dictionary = w["ff"]
	# Firefighter starts at the station, walks to the lot first.
	dis.tick_firefighter(ff, 1.0 / 60.0)
	_check("far fire -> walks to truck",
		String(ff.get("work_state", "")) == "to_truck")
	# Teleport to the lot (walking is covered by _walk_to elsewhere).
	ff["position"] = _lot(dis, w["station"])
	dis.tick_firefighter(ff, 1.0 / 60.0)
	_check("boards at the lot", int(ff.get("truck_id", -1)) > 0)
	var tid := int(ff["truck_id"])
	_check("crew lists the firefighter",
		veh.aboard_ids(tid).has(10))
	_check("no fake truck visual while riding real",
		not bool(ff.get("on_truck", false)))
	_free_world(w)


func _test_truck_drives_crew_and_dismounts_at_fire() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var veh: SimVehicles = w["veh"]
	dis.tick_station_trucks(1.0 / 60.0)
	_add_fire(dis, Vector2(1500, 500))
	var ff: Dictionary = w["ff"]
	ff["position"] = _lot(dis, w["station"])
	dis.tick_firefighter(ff, 1.0 / 60.0)
	var tid := int(ff.get("truck_id", -1))
	_check("boarded for the drive", tid > 0)
	var start: Vector2 = (veh.vehicle_by_id(tid) as Dictionary).get(
		"pos", Vector2.ZERO)
	# Ride: the truck must physically move toward the fire.
	for _i in 1500:
		_tick_all(w)
		if int(ff.get("truck_id", -1)) < 0:
			break
	var truck := veh.vehicle_by_id(tid)
	var now: Vector2 = truck.get("pos", start)
	_check("truck physically moved", now.distance_to(start) > 200.0)
	_check("truck nearer the fire than it started",
		now.distance_to(Vector2(1500, 500)) < start.distance_to(
			Vector2(1500, 500)))
	_check("crew dismounted at the fire",
		int(ff.get("truck_id", -1)) < 0
		and String(ff.get("work_state", "")) == "to_fire")
	_check("dismount is near the fire",
		(ff.get("position", Vector2.ZERO) as Vector2).distance_to(
			Vector2(1500, 500)) < 120.0)
	_free_world(w)


func _test_fire_out_truck_returns_and_reparks() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var veh: SimVehicles = w["veh"]
	dis.tick_station_trucks(1.0 / 60.0)
	var f := _add_fire(dis, Vector2(1500, 500))
	var ff: Dictionary = w["ff"]
	ff["position"] = _lot(dis, w["station"])
	dis.tick_firefighter(ff, 1.0 / 60.0)
	var tid := int(ff.get("truck_id", -1))
	# Drive out, dismount.
	for _i in 1500:
		_tick_all(w)
		if int(ff.get("truck_id", -1)) < 0:
			break
	_check("dismounted at fire", int(ff.get("truck_id", -1)) < 0)
	# Fire goes out (other crew / burnout): full return loop.
	dis.extinguish(f)
	var lot := _lot(dis, w["station"])
	for _i in 1600:
		_tick_all(w)
		var t := veh.vehicle_by_id(tid)
		if t.is_empty():
			break
		if String(t.get("state", "")) == "parked" \
				and (t.get("pos", Vector2.ZERO) as Vector2) \
					.distance_to(lot) < 35.0 \
				and int(ff.get("truck_id", -1)) < 0 \
				and String(ff.get("work_state", "")) == "idle":
			break
	var truck := veh.vehicle_by_id(tid)
	_check("truck re-parked at the lot",
		not truck.is_empty()
		and String(truck.get("state", "")) == "parked"
		and (truck.get("pos", Vector2.ZERO) as Vector2).distance_to(
			lot) < 35.0)
	_check("firefighter idle at home",
		int(ff.get("truck_id", -1)) < 0
		and String(ff.get("work_state", "")) == "idle")
	_free_world(w)


func _test_near_fire_no_truck_ride() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	dis.tick_station_trucks(1.0 / 60.0)
	_add_fire(dis, Vector2(700, 500))  # 200px — inside TRUCK_MIN_DIST
	var ff: Dictionary = w["ff"]
	dis.tick_firefighter(ff, 1.0 / 60.0)
	_check("near fire walks on foot",
		String(ff.get("work_state", "")) == "to_fire")
	_check("near fire never boards", int(ff.get("truck_id", -1)) < 0)
	_free_world(w)


func _test_no_truck_record_legacy_fallback() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	# No vehicles system at all: the old speed-boost path must survive.
	(w["gs"] as GameState).vehicles = null
	_add_fire(dis, Vector2(1500, 500))
	var ff: Dictionary = w["ff"]
	dis.tick_firefighter(ff, 1.0 / 60.0)
	_check("no truck -> legacy fake visual",
		bool(ff.get("on_truck", false)))
	_check("no truck -> still heads to fire",
		String(ff.get("work_state", "")) == "to_fire")
	_free_world(w)


func _test_station_destroyed_truck_despawned_crew_released() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var dis: DisasterSim = w["dis"]
	var veh: SimVehicles = w["veh"]
	dis.tick_station_trucks(1.0 / 60.0)
	var tid := int((w["station"] as Dictionary).get("truck_id", -1))
	var ff: Dictionary = w["ff"]
	ff["position"] = _lot(dis, w["station"])
	veh.board_vehicle(tid, 10)
	ff["truck_id"] = tid
	# Station destroyed: building record removed.
	gs.buildings.clear()
	dis.tick_station_trucks(1.0 / 60.0)
	_check("orphan truck despawned", veh.vehicle_by_id(tid).is_empty())
	_check("crew released", int(ff.get("truck_id", -1)) < 0)
	_free_world(w)


func _test_save_load_keeps_crew() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v: Dictionary = veh.spawn_vehicle("firetruck",
		Vector2(100, 100), "humans")
	veh.board_vehicle(int(v["id"]), 10)
	veh.board_vehicle(int(v["id"]), 11)
	var data := veh.to_dict()
	var veh2 := SimVehicles.new(w["gs"])
	veh2.from_dict(data)
	_check("crew survives save/load",
		veh2.aboard_ids(int(v["id"])) == [10, 11])
	_free_world(w)
