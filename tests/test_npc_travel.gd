extends SceneTree
## Cursing Gnomes — NPC vehicle-travel tests (Jeremy 2026-10-10 direct
## order, roads/vehicles P5: the last unbuilt piece — citizens ride their
## OWN vehicles on long trips).
##
## Full loop: a unit that owns a personal vehicle (dealership purchase)
## and faces a long trip walks to its parked wagon ("to_vehicle"), boards
## as driver, rides with real SimVehicles physics ("on_vehicle", rider
## glued to the wagon), dismounts on arrival — migration hands back to
## SimHousing via _country_move, drive-home just parks. Anything can
## cancel a ride (wagon gone, unit re-tasked, boxed-in wagon): the unit is
## never stranded — it falls back to walking.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_npc_travel.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes NPC vehicle-travel tests ===")
	_test_short_trip_walks()
	_test_no_vehicle_no_ride()
	_test_military_never_rides()
	_test_firetruck_never_commandeered()
	_test_vehicle_in_use_declined()
	_test_full_migration_ride()
	_test_drive_home_ride()
	_test_second_ride_while_riding_declined()
	_test_vehicle_destroyed_midride_fallback()
	_test_blocked_midride_cancels()
	_test_dead_rider_releases_seat()
	_test_stuck_wagon_dismounts_and_walks()
	_test_nearest_hall_pos()
	_test_save_load_resumes_ride()
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


## Dry world: WorkerAI + SimVehicles + SimNPCTravel wired.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var ai := WorkerAI.new(gs)
	gs.worker_ai = ai
	var veh := SimVehicles.new(gs)
	gs.vehicles = veh
	var nt := SimNPCTravel.new(gs)
	gs.npc_travel = nt
	return {"gs": gs, "ai": ai, "veh": veh, "nt": nt}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


## A civilian unit that owns a personal vehicle parked beside them.
func _owner(w: Dictionary, uid: int, pos: Vector2,
		vtype: String = "cart") -> Dictionary:
	var gs: GameState = w["gs"]
	var veh: SimVehicles = w["veh"]
	var u := {"id": uid, "job": "worker", "faction": "humans",
		"alive": true, "position": pos, "coins": 200.0,
		"work_state": "idle"}
	gs.units.append(u)
	var v: Dictionary = veh.spawn_vehicle(vtype, pos + Vector2(30, 0),
		"humans", uid)
	u["vehicle_id"] = int(v["id"])
	return u


## One travel tick: vehicle physics first (positions settled), then travel.
func _tick(w: Dictionary, delta: float = 1.0 / 60.0) -> void:
	(w["veh"] as SimVehicles).tick(delta)
	(w["nt"] as SimNPCTravel).tick(delta)


## Run until the predicate holds or the cap hits. Returns ticks used.
func _until(w: Dictionary, pred: Callable, cap: int = 2400) -> int:
	var n := 0
	while n < cap and not bool(pred.call()):
		_tick(w)
		n += 1
	return n


func _test_short_trip_walks() -> void:
	var w := _new_world()
	var nt: SimNPCTravel = w["nt"]
	var u := _owner(w, 10, Vector2(500, 500))
	_check("short trip declines the ride",
		not nt.request_ride(u, Vector2(700, 500), "migrate"))
	_check("no ride flag on decline", not u.has("_ride"))
	_free_world(w)


func _test_no_vehicle_no_ride() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var nt: SimNPCTravel = w["nt"]
	var u := {"id": 11, "job": "worker", "faction": "humans",
		"alive": true, "position": Vector2(500, 500),
		"work_state": "idle"}
	gs.units.append(u)
	_check("vehicle-less unit can't ride",
		not nt.request_ride(u, Vector2(1500, 500), "migrate"))
	_free_world(w)


func _test_military_never_rides() -> void:
	var w := _new_world()
	var nt: SimNPCTravel = w["nt"]
	var u := _owner(w, 12, Vector2(500, 500))
	u["job"] = "soldier"
	_check("soldiers don't take civilian rides",
		not nt.request_ride(u, Vector2(1500, 500), "migrate"))
	_free_world(w)


func _test_firetruck_never_commandeered() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var veh: SimVehicles = w["veh"]
	var nt: SimNPCTravel = w["nt"]
	var u := {"id": 13, "job": "worker", "faction": "humans",
		"alive": true, "position": Vector2(500, 500),
		"work_state": "idle"}
	gs.units.append(u)
	var ft: Dictionary = veh.spawn_vehicle("firetruck",
		Vector2(530, 500), "humans", 13)
	u["vehicle_id"] = int(ft["id"])
	_check("fire trucks are never commandeered",
		not nt.request_ride(u, Vector2(1500, 500), "migrate"))
	_free_world(w)


func _test_vehicle_in_use_declined() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var nt: SimNPCTravel = w["nt"]
	var u := _owner(w, 14, Vector2(500, 500))
	var v: Dictionary = veh.vehicle_by_id(int(u["vehicle_id"]))
	v["driver_id"] = 99  # somebody else took it
	_check("in-use vehicle declines",
		not nt.request_ride(u, Vector2(1500, 500), "migrate"))
	_free_world(w)


func _test_full_migration_ride() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var nt: SimNPCTravel = w["nt"]
	var u := _owner(w, 15, Vector2(500, 500), "wagon")
	var dest := Vector2(1300, 500)
	_check("long trip takes the ride",
		nt.request_ride(u, dest, SimNPCTravel.KIND_MIGRATE))
	_check("walks to the wagon first",
		String(u.get("work_state", "")) == "to_vehicle")
	# Board: walk the 30px (teleport-free — the walk is the point).
	var boarded := _until(w, func() -> bool:
		return String(u.get("work_state", "")) == "on_vehicle")
	_check("boards as driver", boarded < 2400)
	var vid := int(u["vehicle_id"])
	_check("owner drives", int(
		(veh.vehicle_by_id(vid) as Dictionary).get("driver_id", -1)) == 15)
	var start: Vector2 = (veh.vehicle_by_id(vid) as Dictionary).get(
		"pos", Vector2.ZERO)
	# Ride: the wagon must physically carry the unit toward the dest.
	var arrived := _until(w, func() -> bool:
		return not u.has("_ride"))
	_check("ride completes", arrived < 2400)
	var now: Vector2 = (veh.vehicle_by_id(vid) as Dictionary).get(
		"pos", start)
	_check("wagon physically moved", now.distance_to(start) > 200.0)
	_check("wagon nearer the dest than it started",
		now.distance_to(dest) < start.distance_to(dest))
	_check("rider dismounted", int(
		(veh.vehicle_by_id(vid) as Dictionary).get("driver_id", -1)) < 0)
	_check("migration hands back to housing",
		(u.get("_country_move", Vector2(-1, -1)) as Vector2).x >= 0.0)
	_check("unit idle after arrival",
		String(u.get("work_state", "")) == "idle")
	_free_world(w)


func _test_drive_home_ride() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var veh: SimVehicles = w["veh"]
	var nt: SimNPCTravel = w["nt"]
	# Town hall 700px east; the hook offsets clear of the footprint.
	gs.buildings.append({"id": 5, "type": "town_hall", "faction": "humans",
		"complete": true, "alive": true, "position": Vector2(1200, 500)})
	var u := _owner(w, 16, Vector2(500, 500), "cart")
	var hall := nt.nearest_hall_pos("humans", Vector2(500, 500))
	_check("hall found", hall == Vector2(1200, 500))
	var clear := SimBuildings.footprint("town_hall") + 40.0
	_check("drive home accepted",
		nt.request_ride(u, hall + Vector2(clear, 0.0),
			SimNPCTravel.KIND_DRIVE_HOME))
	var done := _until(w, func() -> bool: return not u.has("_ride"))
	_check("drive home completes", done < 2400)
	var vid := int(u["vehicle_id"])
	var vpos: Vector2 = (veh.vehicle_by_id(vid) as Dictionary).get(
		"pos", Vector2.ZERO)
	_check("wagon parked near the hall",
		vpos.distance_to(hall) < 200.0)
	_check("no housing handoff for drive_home",
		not u.has("_country_move"))
	_free_world(w)


func _test_second_ride_while_riding_declined() -> void:
	var w := _new_world()
	var nt: SimNPCTravel = w["nt"]
	var u := _owner(w, 17, Vector2(500, 500))
	_check("first ride ok",
		nt.request_ride(u, Vector2(1500, 500), "migrate"))
	_check("second ride declined while riding",
		not nt.request_ride(u, Vector2(500, 1500), "migrate"))
	_free_world(w)


func _test_vehicle_destroyed_midride_fallback() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var nt: SimNPCTravel = w["nt"]
	var u := _owner(w, 18, Vector2(500, 500))
	nt.request_ride(u, Vector2(1500, 500), "migrate")
	_tick(w)  # to_vehicle
	_check("ride active", u.has("_ride"))
	veh.despawn_vehicle(int(u["vehicle_id"]))
	_tick(w)
	_check("ride cancelled, not stranded", not u.has("_ride"))
	_check("migration walk restored",
		(u.get("_country_move", Vector2(-1, -1)) as Vector2) \
			== Vector2(1500, 500))
	_free_world(w)


func _test_blocked_midride_cancels() -> void:
	var w := _new_world()
	var nt: SimNPCTravel = w["nt"]
	var u := _owner(w, 19, Vector2(500, 500))
	nt.request_ride(u, Vector2(1500, 500), "migrate")
	u["player_order"] = {"kind": "move"}  # the player grabs them
	_tick(w)
	_check("re-tasked unit drops the ride", not u.has("_ride"))
	_check("falls back to walking",
		(u.get("_country_move", Vector2(-1, -1)) as Vector2) \
			== Vector2(1500, 500))
	_free_world(w)


func _test_dead_rider_releases_seat() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var nt: SimNPCTravel = w["nt"]
	var u := _owner(w, 20, Vector2(500, 500))
	nt.request_ride(u, Vector2(1500, 500), "migrate")
	_until(w, func() -> bool:
		return String(u.get("work_state", "")) == "on_vehicle")
	var vid := int(u["vehicle_id"])
	u["alive"] = false
	_tick(w)
	_check("dead rider disembarked", int(
		(veh.vehicle_by_id(vid) as Dictionary).get("driver_id", -1)) < 0)
	_check("dead ride cleared", not u.has("_ride"))
	_free_world(w)


func _test_stuck_wagon_dismounts_and_walks() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var veh: SimVehicles = w["veh"]
	var nt: SimNPCTravel = w["nt"]
	var u := _owner(w, 21, Vector2(500, 500), "cart")
	# A house sits exactly on the destination: the wagon can never
	# arrive (footprint 30 + cart radius 9 > ARRIVE_DIST 10).
	var dest := Vector2(1300, 500)
	gs.buildings.append({"id": 6, "type": "house", "faction": "humans",
		"complete": true, "alive": true, "position": dest})
	nt.request_ride(u, dest, "migrate")
	_until(w, func() -> bool:
		return String(u.get("work_state", "")) == "on_vehicle")
	# Drive out (~470px) + the 8s stuck timeout before it gives up.
	var done := _until(w, func() -> bool: return not u.has("_ride"))
	_check("boxed-in wagon gives up the ride", done < 2400)
	var vid := int(u["vehicle_id"])
	_check("rider dismounted", int(
		(veh.vehicle_by_id(vid) as Dictionary).get("driver_id", -1)) < 0)
	_check("walks the rest",
		(u.get("_country_move", Vector2(-1, -1)) as Vector2) == dest)
	_free_world(w)


func _test_nearest_hall_pos() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var nt: SimNPCTravel = w["nt"]
	_check("no hall -> INF",
		nt.nearest_hall_pos("humans", Vector2.ZERO) == Vector2.INF)
	gs.buildings.append({"id": 7, "type": "town_hall", "faction": "humans",
		"complete": true, "alive": true, "position": Vector2(900, 100)})
	gs.buildings.append({"id": 8, "type": "hall", "faction": "humans",
		"complete": true, "alive": true, "position": Vector2(100, 900)})
	_check("nearest hall wins",
		nt.nearest_hall_pos("humans", Vector2(800, 0)) \
			== Vector2(900, 100))
	_free_world(w)


func _test_save_load_resumes_ride() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var veh: SimVehicles = w["veh"]
	var nt: SimNPCTravel = w["nt"]
	var u := _owner(w, 22, Vector2(500, 500), "wagon")
	nt.request_ride(u, Vector2(1500, 500), "migrate")
	_until(w, func() -> bool:
		return String(u.get("work_state", "")) == "on_vehicle")
	# Save the fleet, load it into a fresh SimVehicles, swap it in.
	var data := veh.to_dict()
	var veh2 := SimVehicles.new(gs)
	veh2.from_dict(data)
	gs.vehicles = veh2
	w["veh"] = veh2
	# A fresh SimNPCTravel re-arms from the unit records on load.
	var nt2 := SimNPCTravel.new(gs)
	nt2.from_dict({})
	gs.npc_travel = nt2
	w["nt"] = nt2
	var vid := int(u["vehicle_id"])
	_check("crew survives the fleet reload",
		veh2.aboard_ids(vid).has(22))
	_tick(w)
	_check("reloaded travel still glues the rider",
		String(u.get("work_state", "")) == "on_vehicle")
	var vpos: Vector2 = veh2.vehicle_by_id(vid).get("pos", Vector2.ZERO)
	_check("rider tracks the wagon",
		(u.get("position", Vector2.ZERO) as Vector2).distance_to(vpos) \
			< 12.0)
	_free_world(w)
