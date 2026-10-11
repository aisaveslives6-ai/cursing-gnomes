extends SceneTree
## Cursing Gnomes — draft-horse tests (Jeremy 2026-10-11 deep animation
## pass: no more ghost wagons).
##
## Every vehicle — SimVehicles records (wagon/cart/carriage/firetruck) and
## SimTradeRoutes wagons — gets a hitched draft horse: a faithful GDScript
## port of the HTML's drawDetailedHorse, re-harnessed (collar + traces, no
## saddle), with a travel-driven walk gait. Hitched while driving or while
## a driver is aboard; unhitched (no horse) when parked driverless.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_vehicle_horses.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes draft-horse tests ===")
	_test_coat_palettes()
	_test_qpoly_math()
	_test_vehicle_horse_hitched_driving()
	_test_vehicle_horse_parked_no_driver()
	_test_vehicle_horse_parked_with_driver()
	_test_vehicle_horse_phase_freezes()
	_test_vehicle_horse_coat_deterministic()
	_test_trade_wagon_horse()
	_test_trade_wagon_phase_tracks_movement()
	_test_wagon_draw_list_has_id()
	_test_draw_horse_executes()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(n: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(n)


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	return {"gs": gs, "veh": SimVehicles.new(gs)}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _vehicle_layer_for(fleet: Array) -> VehicleLayer:
	var layer := VehicleLayer.new()
	root.add_child(layer)
	layer.set_provider(func() -> Array: return fleet)
	return layer


func _horse_cmd(layer: VehicleLayer) -> Dictionary:
	for c in layer._commands:
		if String(c.get("kind", "")) == "vehicle":
			return c
	return {}


## --- art data ---------------------------------------------------------------


func _test_coat_palettes() -> void:
	_check("four draft coats", VehicleArt.HORSE_COATS.size() == 4)
	var seen := {}
	for pal in VehicleArt.HORSE_COATS:
		for key in ["coat", "lt", "dk", "mane"]:
			var col: Color = (pal as Dictionary)[key]
			_check("coat %s is a color" % key, col is Color)
			_check("coat %s not white placeholder" % key,
				col != Color.WHITE)
			_check("coat %s opaque" % key, col.a == 1.0)
		seen[str((pal as Dictionary)["coat"])] = true
	_check("coats are distinct", seen.size() == 4)


func _test_qpoly_math() -> void:
	var p0 := Vector2(0, 0)
	var c := Vector2(10, -10)
	var p1 := Vector2(20, 0)
	var pts := VehicleArt._qpoly(p0, c, p1, 8)
	_check("qpoly point count", pts.size() == 9)
	_check("qpoly starts at p0", pts[0] == p0)
	_check("qpoly ends at p1", pts[8] == p1)
	# Midpoint of a quadratic at t=0.5: 0.25*p0 + 0.5*c + 0.25*p1.
	var mid: Vector2 = pts[4]
	_check("qpoly midpoint on curve",
		mid.distance_to(Vector2(10, -5)) < 0.001)
	var chained := VehicleArt._q2poly(p0, c, p1, Vector2(30, 10),
		Vector2(40, 0), 6)
	_check("q2poly chains without duplicating the joint",
		chained.size() == 13)
	_check("q2poly starts at p0", chained[0] == p0)
	_check("q2poly ends at p2", chained[12] == Vector2(40, 0))


## --- SimVehicles layer ------------------------------------------------------


func _test_vehicle_horse_hitched_driving() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v := veh.spawn_vehicle("wagon", Vector2(100, 100), "humans")
	v["state"] = SimVehicles.STATE_DRIVING
	v["speed"] = 30.0
	v["facing"] = 0.0
	var layer := _vehicle_layer_for(veh.vehicles)
	layer._process(1.0)  # 30 px travelled
	var cmd := _horse_cmd(layer)
	_check("driving wagon has a hitched horse",
		bool(cmd.get("horse", false)))
	_check("horse phase advances with travel",
		float(cmd.get("horse_phase", 0.0)) > 0.0)
	_check("horse phase matches travel * HORSE_GAIT",
		absf(float(cmd.get("horse_phase", 0.0)) \
			- 30.0 * VehicleArt.HORSE_GAIT) < 0.001)
	var coat := int(cmd.get("horse_coat", -1))
	_check("horse coat in palette range",
		coat >= 0 and coat < VehicleArt.HORSE_COATS.size())
	layer.free()
	_free_world(w)


func _test_vehicle_horse_parked_no_driver() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	veh.spawn_vehicle("cart", Vector2(200, 200), "humans")
	var layer := _vehicle_layer_for(veh.vehicles)
	layer._process(0.5)
	var cmd := _horse_cmd(layer)
	_check("parked driverless cart has no horse",
		not bool(cmd.get("horse", true)))
	layer.free()
	_free_world(w)


func _test_vehicle_horse_parked_with_driver() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v := veh.spawn_vehicle("firetruck", Vector2(300, 300), "humans")
	v["driver_id"] = 7
	var layer := _vehicle_layer_for(veh.vehicles)
	layer._process(0.5)
	var cmd := _horse_cmd(layer)
	_check("parked truck with driver keeps its horse",
		bool(cmd.get("horse", false)))
	_check("standing horse phase frozen at zero",
		float(cmd.get("horse_phase", -1.0)) == 0.0)
	# A second frame must not advance the gait either.
	layer._process(0.5)
	var cmd2 := _horse_cmd(layer)
	_check("standing horse phase never advances",
		float(cmd2.get("horse_phase", -1.0)) == 0.0)
	layer.free()
	_free_world(w)


func _test_vehicle_horse_phase_freezes() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v := veh.spawn_vehicle("carriage", Vector2(100, 100), "humans")
	v["state"] = SimVehicles.STATE_DRIVING
	v["speed"] = 40.0
	v["facing"] = 0.0
	var layer := _vehicle_layer_for(veh.vehicles)
	layer._process(1.0)
	var rolling := float(_horse_cmd(layer).get("horse_phase", 0.0))
	_check("rolling carriage gait active", rolling > 0.0)
	v["state"] = SimVehicles.STATE_PARKED
	v["speed"] = 0.0
	layer._process(1.0)
	var stood := float(_horse_cmd(layer).get("horse_phase", -1.0))
	_check("gait freezes the moment it parks", stood == rolling)
	layer.free()
	_free_world(w)


func _test_vehicle_horse_coat_deterministic() -> void:
	var w := _new_world()
	var veh: SimVehicles = w["veh"]
	var v := veh.spawn_vehicle("wagon", Vector2(100, 100), "humans")
	v["state"] = SimVehicles.STATE_DRIVING
	v["speed"] = 20.0
	var layer := _vehicle_layer_for(veh.vehicles)
	layer._process(0.5)
	var c1 := int(_horse_cmd(layer).get("horse_coat", -1))
	layer._process(0.5)
	var c2 := int(_horse_cmd(layer).get("horse_coat", -1))
	_check("coat stable across frames", c1 == c2)
	_check("coat matches id hash rule",
		c1 == abs(int(v.get("id", 0))) % VehicleArt.HORSE_COATS.size())
	layer.free()
	_free_world(w)


## --- trade-wagon layer ------------------------------------------------------


func _trade_layer_for(wagons: Array) -> TradeWagonLayer:
	var layer := TradeWagonLayer.new()
	root.add_child(layer)
	layer.set_provider(func() -> Array: return wagons)
	return layer


func _wagon_cmd(layer: TradeWagonLayer) -> Dictionary:
	for c in layer._commands:
		if String(c.get("kind", "")) == "wagon":
			return c
	return {}


func _test_trade_wagon_horse() -> void:
	var wagons := [{
		"pos": Vector2(50, 50), "id": "tw1", "from_race": "humans",
		"facing": 1.0, "bob": 0.0,
	}]
	var layer := _trade_layer_for(wagons)
	layer._process(0.1)
	var cmd := _wagon_cmd(layer)
	_check("trade wagon always hitched", bool(cmd.get("horse", false)))
	var coat := int(cmd.get("horse_coat", -1))
	_check("trade wagon coat in range",
		coat >= 0 and coat < VehicleArt.HORSE_COATS.size())
	layer.free()


func _test_trade_wagon_phase_tracks_movement() -> void:
	var wagons := [{
		"pos": Vector2(50, 50), "id": "tw9", "from_race": "elves",
		"facing": 1.0, "bob": 3.0,
	}]
	var layer := _trade_layer_for(wagons)
	layer._process(0.1)
	var still := float(_wagon_cmd(layer).get("horse_phase", -1.0))
	# First frame seeds last-pos; the gait must not jump on spawn.
	layer._process(0.1)
	var held := float(_wagon_cmd(layer).get("horse_phase", -1.0))
	_check("holding wagon (war hold) keeps a still horse", held == still)
	(wagons[0] as Dictionary)["pos"] = Vector2(80, 50)  # 30 px roll
	layer._process(0.1)
	var rolled := float(_wagon_cmd(layer).get("horse_phase", 0.0))
	_check("rolling wagon advances the gait", rolled > held)
	_check("gait matches distance * HORSE_GAIT",
		absf(rolled - held - 30.0 * VehicleArt.HORSE_GAIT) < 0.01)
	layer.free()


func _test_wagon_draw_list_has_id() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var routes := SimTradeRoutes.new(gs)
	routes.wagons.append({
		"pos": Vector2(10, 10), "id": "tw42", "from_race": "humans",
		"facing": 1.0, "bob": 0.0,
	})
	var list: Array = routes.wagon_draw_list()
	_check("draw list carries the wagon id",
		String((list[0] as Dictionary).get("id", "")) == "tw42")
	gs.queue_free()


## --- draw-path smoke --------------------------------------------------------


class HorseDrawProbe extends Node2D:
	var drew := false

	func _draw() -> void:
		for coat in range(VehicleArt.HORSE_COATS.size()):
			for fx in [1.0, -1.0]:
				for phase in [0.0, 1.3, 4.2]:
					VehicleArt.draw_horse(self, Vector2(100, 100),
						fx, phase, coat)
		drew = true


func _test_draw_horse_executes() -> void:
	var probe := HorseDrawProbe.new()
	root.add_child(probe)
	probe.queue_redraw()
	await process_frame
	await process_frame
	_check("draw_horse renders all coats x mirrors x phases", probe.drew)
	probe.free()
