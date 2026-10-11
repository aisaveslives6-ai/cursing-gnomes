extends SceneTree
## Cursing Gnomes — SimVehicles core tests (Jeremy 2026-10-10 direct order:
## road infrastructure + full vehicle system, phase P1).
##
## Unified vehicle records + driving physics: spawn/despawn, accel/brake
## ramps, turn-rate-limited steering, stone/dirt road bonuses, wear scaling,
## off-road penalty, vehicle separation, building blocking, water avoidance,
## road-wear accrual, save/load roundtrip.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_vehicles.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes vehicles tests ===")
	_test_spawn_rejects_unknown_type()
	_test_spawn_defaults()
	_test_drive_to_arrives()
	_test_accel_ramps_no_teleport()
	_test_brake_eases_into_target()
	_test_turn_rate_limited()
	_test_stone_road_bonus()
	_test_dirt_road_bonus()
	_test_worn_road_loses_bonus()
	_test_offroad_penalty()
	_test_vehicle_separation()
	_test_building_blocks()
	_test_bridge_exempt()
	_test_water_avoidance()
	_test_wear_accrual()
	_test_wagon_wears_more_than_cart()
	_test_save_load_roundtrip()
	_test_old_save_empty()
	_test_despawn()
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


## Dry world: no water, WorkerAI roads live on GameState.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var ai := WorkerAI.new(gs)
	gs.worker_ai = ai
	var veh := SimVehicles.new(gs)
	return {"gs": gs, "ai": ai, "veh": veh}


## World with a water stripe at tile columns [x0, x1) (test_ferry pattern).
func _new_water_world(x0: int, x1: int) -> Dictionary:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var terrain := PackedByteArray()
	terrain.resize(128 * 128)
	for i in terrain.size():
		terrain[i] = MapGen.TILE_GRASS
	for ty in 128:
		for tx in range(x0, x1):
			terrain[ty * 128 + tx] = MapGen.TILE_WATER
	gs.map_data = {
		"terrain": terrain, "tile_size": 32.0,
		"world_size": Vector2(4096, 4096),
	}
	return w


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _drive_ticks(veh: SimVehicles, ticks: int, delta: float = 1.0 / 60.0) -> void:
	for _i in ticks:
		veh.tick(delta)


## Paints a straight road of the given type along +x from `start`.
func _paint_line(ai: WorkerAI, start: Vector2, length: float,
		rtype: String) -> void:
	var x := start.x
	while x < start.x + length:
		ai.paint_road(Vector2(x, start.y), "humans", rtype)
		x += 18.0


func _test_spawn_rejects_unknown_type() -> void:
	var w := _new_world()
	var v: Dictionary = (w["veh"] as SimVehicles).spawn_vehicle(
		"hovercar", Vector2(100, 100), "humans")
	_check("unknown type rejected", v.is_empty())
	_check("no vehicle recorded", (w["veh"] as SimVehicles).vehicle_count() == 0)
	_free_world(w)


func _test_spawn_defaults() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var a: Dictionary = veh.spawn_vehicle("wagon", Vector2(100, 100), "humans")
	var b: Dictionary = veh.spawn_vehicle("cart", Vector2(200, 200), "humans", 7)
	_check("ids increment", int(a["id"]) + 1 == int(b["id"]))
	_check("starts parked", String(a["state"]) == "parked")
	_check("starts still", float(a["speed"]) == 0.0)
	_check("no driver", int(a["driver_id"]) == -1)
	_check("owner kept", int(b["owner_id"]) == 7)
	_check("lookup works", int(veh.vehicle_by_id(int(a["id"]))["id"]) == int(a["id"]))
	_check("faction filter", veh.vehicles_of_faction("humans").size() == 2)
	_check("faction filter empty", veh.vehicles_of_faction("gnomes").is_empty())
	_check("assign driver", veh.assign_driver(int(a["id"]), 42)
		and int(veh.vehicle_by_id(int(a["id"]))["driver_id"]) == 42)
	_check("release driver", veh.release_driver(int(a["id"]))
		and int(veh.vehicle_by_id(int(a["id"]))["driver_id"]) == -1)
	_check("drive_to unknown id", not veh.drive_to(9999, Vector2.ZERO))
	_free_world(w)


func _test_drive_to_arrives() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v: Dictionary = veh.spawn_vehicle("cart", Vector2(100, 100), "humans")
	_check("drive_to accepted", veh.drive_to(int(v["id"]), Vector2(400, 100)))
	_check("state driving", String(v["state"]) == "driving")
	_drive_ticks(veh, 60 * 20)  # 20 s is plenty for 300 px
	_check("arrived at target",
		(v["pos"] as Vector2).distance_to(Vector2(400, 100)) < 12.0)
	_check("parked on arrival", String(v["state"]) == "parked")
	_check("still on arrival", float(v["speed"]) == 0.0)
	_free_world(w)


func _test_accel_ramps_no_teleport() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v: Dictionary = veh.spawn_vehicle("wagon", Vector2(100, 100), "humans")
	veh.drive_to(int(v["id"]), Vector2(2000, 100))
	var prev_speed := 0.0
	var ok := true
	var last_pos: Vector2 = v["pos"]
	for _i in 120:  # 2 s of accel
		veh.tick(1.0 / 60.0)
		var s := float(v["speed"])
		if s < prev_speed - 0.001:
			ok = false  # should only accelerate on a clear straight
		prev_speed = s
		var step: float = (v["pos"] as Vector2).distance_to(last_pos)
		if step > 55.0 * 1.3 * (1.0 / 60.0) + 0.5:
			ok = false  # teleport check: never faster than top speed
		last_pos = v["pos"]
	_check("accel ramps monotonically", ok)
	_check("not at top speed after 2 s (accel 22)",
		float(v["speed"]) < 55.0 * 0.85 - 1.0)
	_check("moving", float(v["speed"]) > 5.0)
	_free_world(w)


func _test_brake_eases_into_target() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v: Dictionary = veh.spawn_vehicle("carriage", Vector2(100, 100), "humans")
	veh.drive_to(int(v["id"]), Vector2(700, 100))
	_drive_ticks(veh, 60)
	var mid_speed := float(v["speed"])
	_drive_ticks(veh, 60 * 12)  # 600 px at ~59.5 px/s + accel ramp + easing
	_check("reached and parked", String(v["state"]) == "parked")
	_check("was fast mid-run", mid_speed > 20.0)  # 1 s at accel 28
	# No overshoot oscillation: final position sits at the target.
	_check("no overshoot", (v["pos"] as Vector2).distance_to(Vector2(700, 100)) < 12.0)
	_free_world(w)


func _test_turn_rate_limited() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	# Target directly behind: a full PI turn at cart turn_rate 2.5 rad/s
	# needs >= ~1.26 s; facing must move in bounded steps.
	var v: Dictionary = veh.spawn_vehicle("cart", Vector2(500, 500), "humans")
	v["facing"] = 0.0  # pointing +x
	veh.drive_to(int(v["id"]), Vector2(100, 500))  # goal is -x
	var ok := true
	var prev := 0.0
	for _i in 30:
		veh.tick(1.0 / 60.0)
		var f := float(v["facing"])
		var step: float = absf(wrapf(f - prev, -PI, PI))
		if step > 2.5 * (1.0 / 60.0) + 0.01:
			ok = false
		prev = f
	_check("turn rate bounded per tick", ok)
	_check("turning the long way (not snapping)",
		absf(wrapf(float(v["facing"]), -PI, PI)) < PI - 0.5)
	_free_world(w)


func _test_stone_road_bonus() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var ai: WorkerAI = w["ai"]
	_paint_line(ai, Vector2(100, 100), 900.0, "stone")
	var v: Dictionary = veh.spawn_vehicle("wagon", Vector2(110, 100), "humans")
	_check("stone bonus is 1.3x fresh",
		absf(veh.road_bonus_at(Vector2(110, 100)) - 1.3) < 0.01)
	# Relative race: identical wagon off-road must lose to the stone-road
	# wagon over the same ticks (same accel ramp, different top speed).
	var w2: Dictionary = veh.spawn_vehicle("wagon", Vector2(110, 300), "humans")
	veh.drive_to(int(v["id"]), Vector2(900, 100))
	veh.drive_to(int(w2["id"]), Vector2(900, 300))
	_drive_ticks(veh, 240)
	_check("stone road outruns off-road",
		(v["pos"] as Vector2).x > (w2["pos"] as Vector2).x + 30.0)
	_free_world(w)


func _test_dirt_road_bonus() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var ai: WorkerAI = w["ai"]
	_paint_line(ai, Vector2(100, 100), 900.0, "dirt")
	_check("dirt bonus is 1.15x fresh",
		absf(veh.road_bonus_at(Vector2(110, 100)) - 1.15) < 0.01)
	_free_world(w)


func _test_worn_road_loses_bonus() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var ai: WorkerAI = w["ai"]
	_paint_line(ai, Vector2(100, 100), 400.0, "stone")
	# Grind one segment to fully worn.
	var idx: int = ai.road_index_at(Vector2(110, 100))
	(ai.roads[idx] as Dictionary)["wear"] = 1.0
	_check("worn stone loses bonus",
		absf(veh.road_bonus_at(Vector2(110, 100)) - 1.0) < 0.01)
	(ai.roads[idx] as Dictionary)["wear"] = 0.5
	_check("half-worn stone keeps half bonus",
		absf(veh.road_bonus_at(Vector2(110, 100)) - 1.15) < 0.01)
	_free_world(w)


func _test_offroad_penalty() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	_check("off-road is 0.85x",
		absf(veh.road_bonus_at(Vector2(3000, 3000)) - 0.85) < 0.001)
	var v: Dictionary = veh.spawn_vehicle("cart", Vector2(100, 100), "humans")
	veh.drive_to(int(v["id"]), Vector2(1900, 100))
	_drive_ticks(veh, 120)  # 2 s at 48*0.85 = 40.8 px/s
	var x: float = (v["pos"] as Vector2).x
	_check("off-road slower than road pace", x < 100.0 + 40.8 * 2.0 + 12.0)
	_check("off-road still moves", x > 100.0 + 20.0)
	_free_world(w)


func _test_vehicle_separation() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var a: Dictionary = veh.spawn_vehicle("cart", Vector2(500, 500), "humans")
	var b: Dictionary = veh.spawn_vehicle("cart", Vector2(505, 500), "humans")
	veh.tick(1.0 / 60.0)  # separation runs even with no drivers
	var d: float = (a["pos"] as Vector2).distance_to(b["pos"] as Vector2)
	_check("overlapping vehicles pushed apart", d >= 18.0 - 0.5)
	_free_world(w)


func _test_building_blocks() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var gs: GameState = w["gs"]
	# A completed town hall (footprint ~ big) sits on the drive line.
	gs.buildings.append({"type": "town_hall", "position": Vector2(400, 100),
		"complete": true, "alive": true, "faction": "humans"})
	var v: Dictionary = veh.spawn_vehicle("cart", Vector2(100, 100), "humans")
	veh.drive_to(int(v["id"]), Vector2(800, 100))
	_drive_ticks(veh, 60 * 15)
	var x: float = (v["pos"] as Vector2).x
	var fr: float = SimBuildings.footprint("town_hall") + 9.0
	_check("stops before the building", x < 400.0 - fr + 30.0)
	_check("does not enter the footprint", x < 400.0 - fr + 1.0)
	_free_world(w)


func _test_bridge_exempt() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var gs: GameState = w["gs"]
	gs.buildings.append({"type": "bridge", "position": Vector2(400, 100),
		"complete": true, "alive": true, "faction": "humans"})
	var v: Dictionary = veh.spawn_vehicle("cart", Vector2(100, 100), "humans")
	veh.drive_to(int(v["id"]), Vector2(800, 100))
	_drive_ticks(veh, 60 * 20)
	_check("crosses bridges",
		(v["pos"] as Vector2).distance_to(Vector2(800, 100)) < 60.0)
	_free_world(w)


func _test_water_avoidance() -> void:
	# Water stripe at tile columns 60..68 -> x 1920..2176. Drive along the
	# stripe's edge; the vehicle must never get wet.
	var w := _new_water_world(60, 68)
	var veh: SimVehicles = w["veh"]
	var gs: GameState = w["gs"]
	var v: Dictionary = veh.spawn_vehicle("wagon", Vector2(1800, 2048), "humans")
	veh.drive_to(int(v["id"]), Vector2(2300, 2048))  # straight at the water
	_drive_ticks(veh, 60 * 25)
	var p: Vector2 = v["pos"]
	_check("never enters water",
		not WaterNav.is_water_at(gs.map_data, p))
	_check("did not cross the stripe", p.x < 1920.0 + 40.0)
	_free_world(w)


func _test_wear_accrual() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var ai: WorkerAI = w["ai"]
	_paint_line(ai, Vector2(100, 100), 900.0, "stone")
	var v: Dictionary = veh.spawn_vehicle("cart", Vector2(110, 100), "humans")
	veh.drive_to(int(v["id"]), Vector2(900, 100))
	_drive_ticks(veh, 60 * 3)
	var worn := false
	for r in ai.roads:
		if float((r as Dictionary).get("wear", 0.0)) > 0.0:
			worn = true
			break
	_check("driving wears the road", worn)
	_free_world(w)


func _test_wagon_wears_more_than_cart() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var ai: WorkerAI = w["ai"]
	_paint_line(ai, Vector2(100, 100), 1200.0, "dirt")
	var wagon: Dictionary = veh.spawn_vehicle("wagon", Vector2(110, 100), "humans")
	var cart: Dictionary = veh.spawn_vehicle("cart", Vector2(110, 140), "humans")
	veh.drive_to(int(wagon["id"]), Vector2(1100, 100))
	veh.drive_to(int(cart["id"]), Vector2(1100, 140))
	_drive_ticks(veh, 60 * 3)
	var wagon_wear := 0.0
	var cart_wear := 0.0
	for r in ai.roads:
		var rd: Dictionary = r
		var rp: Vector2 = rd.get("position", Vector2.ZERO)
		if absf(rp.y - 100.0) < 20.0:
			wagon_wear = maxf(wagon_wear, float(rd.get("wear", 0.0)))
		elif absf(rp.y - 140.0) < 20.0:
			cart_wear = maxf(cart_wear, float(rd.get("wear", 0.0)))
	_check("wagon lane worn", wagon_wear > 0.0)
	_check("wagon (4x) wears more than cart (1.5x)", wagon_wear > cart_wear * 1.5)
	_free_world(w)


func _test_save_load_roundtrip() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v: Dictionary = veh.spawn_vehicle("carriage", Vector2(123, 456), "gnomes", 9)
	veh.assign_driver(int(v["id"]), 77)
	veh.drive_to(int(v["id"]), Vector2(900, 900))
	_drive_ticks(veh, 30)
	var d := veh.to_dict()
	var veh2 := SimVehicles.new(w["gs"])
	veh2.from_dict(d)
	_check("count survives", veh2.vehicle_count() == 1)
	var r: Dictionary = veh2.vehicle_by_id(int(v["id"]))
	_check("id survives", int(r["id"]) == int(v["id"]))
	_check("type survives", String(r["type"]) == "carriage")
	_check("pos survives",
		(r["pos"] as Vector2).distance_to(v["pos"] as Vector2) < 0.01)
	_check("target survives",
		(r["target"] as Vector2).distance_to(Vector2(900, 900)) < 0.01)
	_check("owner survives", int(r["owner_id"]) == 9)
	_check("driver survives", int(r["driver_id"]) == 77)
	_check("state survives", String(r["state"]) == "driving")
	_check("next id continues", int(veh2.to_dict()["next_id"]) == int(v["id"]) + 1)
	# Unknown types in old/corrupt data are skipped, not crashed on.
	var bad := {"next_id": 5, "vehicles": [
		{"id": 4, "type": "hovercar", "faction": "humans",
			"pos": [0, 0], "target": [0, 0]}]}
	veh2.from_dict(bad)
	_check("unknown type skipped on load", veh2.vehicle_count() == 0)
	_free_world(w)


func _test_old_save_empty() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	veh.from_dict({})
	_check("pre-vehicles save loads empty", veh.vehicle_count() == 0)
	_free_world(w)


func _test_despawn() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v: Dictionary = veh.spawn_vehicle("cart", Vector2(100, 100), "humans")
	_check("despawn known", veh.despawn_vehicle(int(v["id"])))
	_check("gone after despawn", veh.vehicle_by_id(int(v["id"])).is_empty())
	_check("despawn unknown", not veh.despawn_vehicle(4242))
	_free_world(w)
