extends SceneTree
## Cursing Gnomes — vehicle layer tests (Jeremy 2026-10-10 vehicle order,
## phase P2: renderer for SimVehicles records).
##
## VehicleLayer turns SimVehicles records into draw commands: per-type art
## selection (wagon/cart/carriage), parked-vs-driving presentation (bob +
## wheel spin + dust only while driving), faction trim, camera culling, and
## zero per-frame cost when the fleet is empty. VehicleArt holds the shared
## procedural drawing — no white squares, no placeholder art.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_vehicle_layer.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes vehicle layer tests ===")
	_test_empty_fleet_hides()
	_test_spawned_types_render()
	_test_faction_trim()
	_test_parked_no_bob()
	_test_driving_animates()
	_test_dust_puffs()
	_test_no_camera_no_cull()
	_test_camera_guard_no_cull()
	_test_facing_mirror()
	_test_travel_pruned()
	_test_uses_sim_vehicles_directly()
	_test_art_palette_no_white()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var veh := SimVehicles.new(gs)
	return {"gs": gs, "veh": veh}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _layer_for(fleet: Array) -> VehicleLayer:
	var layer := VehicleLayer.new()
	root.add_child(layer)
	layer.set_provider(func() -> Array: return fleet)
	return layer


func _test_empty_fleet_hides() -> void:
	var layer := _layer_for([])
	layer._process(0.1)
	_check("layer hides when fleet empty", not layer.visible)
	_check("no commands when fleet empty", layer._commands.is_empty())
	layer.free()


func _test_spawned_types_render() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	veh.spawn_vehicle("wagon", Vector2(100, 100), "humans")
	veh.spawn_vehicle("cart", Vector2(200, 200), "humans")
	veh.spawn_vehicle("carriage", Vector2(300, 300), "humans")
	var layer := VehicleLayer.new()
	root.add_child(layer)
	layer.set_vehicles(veh)
	layer._process(0.1)
	var types := {}
	for c in layer._commands:
		if String(c["kind"]) == "vehicle":
			types[String(c["type"])] = true
	_check("layer visible with fleet", layer.visible)
	_check("wagon command built", types.has("wagon"))
	_check("cart command built", types.has("cart"))
	_check("carriage command built", types.has("carriage"))
	_check("exactly three vehicle commands",
		layer._commands.filter(
			func(c: Dictionary) -> bool:
				return String(c["kind"]) == "vehicle").size() == 3)
	layer.free()
	_free_world(w)


func _test_faction_trim() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var factions := ["humans", "ogres", "elves", "gnomes", "undead"]
	for i in factions.size():
		veh.spawn_vehicle("cart", Vector2(100 + i * 50, 100),
			factions[i])
	var layer := _layer_for(veh.vehicles)
	layer._process(0.1)
	var ok := true
	for c in layer._commands:
		if String(c["kind"]) != "vehicle":
			continue
		var idx := int((c["at"] as Vector2).x / 50.0) - 2
		var want: Color = Config.FACTIONS[factions[idx]]["color"]
		if (c["trim"] as Color) != want:
			ok = false
	_check("faction trim matches Config.FACTIONS (5 factions)", ok)
	layer.free()
	_free_world(w)


func _test_parked_no_bob() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v := veh.spawn_vehicle("wagon", Vector2(100, 100), "humans")
	# Parked by default.
	var layer := _layer_for(veh.vehicles)
	layer._process(1.0)
	var bob := 999.0
	var spin := 999.0
	for c in layer._commands:
		if String(c["kind"]) == "vehicle":
			bob = float(c["bob"])
			spin = float(c["wheel_spin"])
	_check("parked vehicle has no bob", bob == 0.0)
	_check("parked vehicle wheels still", spin == 0.0)
	layer.free()
	_free_world(w)


func _test_driving_animates() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v := veh.spawn_vehicle("wagon", Vector2(100, 100), "humans")
	v["state"] = SimVehicles.STATE_DRIVING
	v["speed"] = 30.0
	v["facing"] = 0.0
	var layer := _layer_for(veh.vehicles)
	layer._process(1.0)  # 30 px travelled
	var bob := 0.0
	var spin := 0.0
	for c in layer._commands:
		if String(c["kind"]) == "vehicle":
			bob = float(c["bob"])
			spin = float(c["wheel_spin"])
	_check("driving wheel spin accumulates with travel", spin > 0.0)
	_check("driving spin matches travel / wheel radius",
		absf(spin - 30.0 / 4.5) < 0.001)
	_check("driving bob oscillates", bob != 0.0)
	_check("driving bob within amplitude", absf(bob) <= 1.5)
	layer.free()
	_free_world(w)


func _test_dust_puffs() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v := veh.spawn_vehicle("cart", Vector2(100, 100), "humans")
	v["state"] = SimVehicles.STATE_DRIVING
	v["speed"] = 30.0
	var layer := _layer_for(veh.vehicles)
	layer._process(0.3)  # past PUFF_SPAWN (0.28)
	var puffs := 0
	for c in layer._commands:
		if String(c["kind"]) == "puff":
			puffs += 1
	_check("moving vehicle kicks up dust", puffs >= 1)
	# Parked vehicles kick up nothing.
	v["state"] = SimVehicles.STATE_PARKED
	v["speed"] = 0.0
	layer._process(1.0)
	puffs = 0
	for c in layer._commands:
		if String(c["kind"]) == "puff":
			puffs += 1
	_check("parked vehicle kicks up no dust", puffs == 0)
	layer.free()
	_free_world(w)


## No camera -> nothing is culled (same rule as TradeWagonLayer).
func _test_no_camera_no_cull() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	veh.spawn_vehicle("wagon", Vector2(500, 500), "humans")
	veh.spawn_vehicle("wagon", Vector2(50000, 50000), "humans")
	var layer := _layer_for(veh.vehicles)
	layer._process(0.1)
	var n := 0
	for c in layer._commands:
		if String(c["kind"]) == "vehicle":
			n += 1
	_check("no camera means no culling", n == 2)
	layer.free()
	_free_world(w)


## Camera set but layer not in-tree (headless tests) -> the guard returns
## an empty rect instead of erroring, so nothing is culled. In the live
## game the layer is in-tree and the grown-rect cull applies (same math as
## the proven TradeWagonLayer).
func _test_camera_guard_no_cull() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	veh.spawn_vehicle("wagon", Vector2(50000, 50000), "humans")
	var layer := _layer_for(veh.vehicles)
	var cam := Camera2D.new()
	layer.set_camera(cam)  # valid zoom, but no tree -> guard path
	layer._process(0.1)
	var n := 0
	for c in layer._commands:
		if String(c["kind"]) == "vehicle":
			n += 1
	_check("off-tree camera guard skips culling", n == 1)
	cam.free()
	layer.free()
	_free_world(w)


func _test_facing_mirror() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var east := veh.spawn_vehicle("wagon", Vector2(100, 100), "humans")
	east["facing"] = 0.0
	var west := veh.spawn_vehicle("wagon", Vector2(200, 100), "humans")
	west["facing"] = PI
	var layer := _layer_for(veh.vehicles)
	layer._process(0.1)
	var fx_east := 0.0
	var fx_west := 0.0
	for c in layer._commands:
		if String(c["kind"]) != "vehicle":
			continue
		if (c["at"] as Vector2).x < 150.0:
			fx_east = float(c["fx"])
		else:
			fx_west = float(c["fx"])
	_check("eastbound vehicle not mirrored", fx_east == 1.0)
	_check("westbound vehicle mirrored", fx_west == -1.0)
	layer.free()
	_free_world(w)


func _test_travel_pruned() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v := veh.spawn_vehicle("wagon", Vector2(100, 100), "humans")
	v["state"] = SimVehicles.STATE_DRIVING
	v["speed"] = 30.0
	var layer := _layer_for(veh.vehicles)
	layer._process(0.5)
	_check("travel accumulates while driving",
		not layer._travel.is_empty())
	veh.despawn_vehicle(int(v["id"]))
	layer._process(0.5)
	_check("travel pruned when vehicle despawns",
		layer._travel.is_empty())
	layer.free()
	_free_world(w)


func _test_uses_sim_vehicles_directly() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	veh.spawn_vehicle("carriage", Vector2(100, 100), "elves")
	var layer := VehicleLayer.new()
	root.add_child(layer)
	layer.set_vehicles(veh)  # no provider — reads veh.vehicles
	layer._process(0.1)
	var n := 0
	for c in layer._commands:
		if String(c["kind"]) == "vehicle":
			n += 1
	_check("layer reads SimVehicles.vehicles directly", n == 1)
	layer.free()
	_free_world(w)


func _test_art_palette_no_white() -> void:
	var whites := 0
	for col in [VehicleArt.BODY_BROWN, VehicleArt.CANVAS_TAN,
			VehicleArt.DARK_OUTLINE, VehicleArt.WHEEL_DARK,
			VehicleArt.WOOD_LIGHT, VehicleArt.WOOD_DARK,
			VehicleArt.HAY, VehicleArt.CABIN_RED,
			VehicleArt.ROOF_DARK, VehicleArt.GLASS,
			VehicleArt.LANTERN]:
		if (col as Color) == Color(1, 1, 1):
			whites += 1
	_check("no pure-white palette colors (no white squares)", whites == 0)
	_check("wheel radii defined for all sim types",
		VehicleArt.WHEEL_RADIUS.has("wagon")
		and VehicleArt.WHEEL_RADIUS.has("cart")
		and VehicleArt.WHEEL_RADIUS.has("carriage"))
