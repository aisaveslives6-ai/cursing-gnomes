extends SceneTree
## Cursing Gnomes — water navigation tests (Jeremy 2026-10-05,
## Oblivion/Skyrim-style): land animals/NPCs steer around water, fleeing
## creatures may swim, vehicles never enter water.
##
## Covers WaterNav (O(1) water check, dry-step shoreline slides, vehicle
## deflection, avoid rules), SimAnimals integration (wild boar avoids
## water / flees into water / swimming flag), WorkerAI._move_direct
## (NPC avoids / fleeing swims / swimming flag), and SimPathfinder
## find_route with avoid_water (no waypoint on water).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_water_nav.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes water-nav tests ===")
	_test_is_water_at()
	_test_dry_step()
	_test_animal_rules()
	_test_unit_rules()
	_test_vehicle_deflect()
	_test_wild_boar_avoids_water()
	_test_fleeing_boar_may_swim()
	_test_npc_avoids_water()
	_test_fleeing_npc_swims()
	_test_pathfinder_avoids_water()
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


## 128x128 fake map: grass everywhere except a water column at tiles
## x in [20, 30) spanning all rows (world x in [640, 960)).
func _fake_map() -> Dictionary:
	var terrain := PackedByteArray()
	terrain.resize(128 * 128)
	terrain.fill(0)  # TILE_GRASS = 0
	for ty in range(128):
		for tx in range(20, 30):
			terrain[ty * 128 + tx] = MapGen.TILE_WATER
	return {
		"terrain": terrain,
		"tile_size": 32.0,
		"size_tiles": Vector2i(128, 128),
	}


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	gs.map_data = _fake_map()
	return gs


func _test_is_water_at() -> void:
	var m := _fake_map()
	_check("water tile detected", WaterNav.is_water_at(m, Vector2(700, 500)))
	_check("river tile detected",
		WaterNav.is_water_at(m, Vector2(700, 100)))
	_check("grass not water", not WaterNav.is_water_at(m, Vector2(600, 500)))
	_check("grass east not water",
		not WaterNav.is_water_at(m, Vector2(1000, 500)))
	_check("out of bounds not water",
		not WaterNav.is_water_at(m, Vector2(-50, 500)))
	_check("empty map not water",
		not WaterNav.is_water_at({}, Vector2(700, 500)))


func _test_dry_step() -> void:
	var m := _fake_map()
	# Land step stays land.
	var p1 := WaterNav.dry_step(m, Vector2(600, 500), Vector2(10, 0))
	_check("dry step passes through", p1 == Vector2(610, 500))
	# Head-on into water: x blocked, y has no component -> holds.
	var p2 := WaterNav.dry_step(m, Vector2(630, 500), Vector2(20, 0))
	_check("head-on water holds", p2 == Vector2(630, 500))
	_check("head-on never enters water",
		not WaterNav.is_water_at(m, p2))
	# Diagonal into water slides along the shore (y-only).
	var p3 := WaterNav.dry_step(m, Vector2(630, 500), Vector2(20, 12))
	_check("diagonal slides along shore", p3 == Vector2(630, 512))
	_check("slide landing dry", not WaterNav.is_water_at(m, p3))
	# Already in water: keep moving (no trap).
	var p4 := WaterNav.dry_step(m, Vector2(700, 500), Vector2(10, 0))
	_check("wet mover keeps moving", p4 == Vector2(710, 500))


func _test_animal_rules() -> void:
	var calm := {"running": false}
	var st := {"water_liking": false}
	_check("calm land animal avoids",
		WaterNav.animal_avoids_water(calm, st))
	_check("fleeing animal may swim",
		not WaterNav.animal_avoids_water({"running": true}, st))
	_check("water-liking animal may swim",
		not WaterNav.animal_avoids_water(calm, {"water_liking": true}))
	# Registry: all current types are land animals.
	for t in SimAnimals.ANIMAL_TYPES.keys():
		_check("type %s not water-liking" % t,
			not bool(SimAnimals.ANIMAL_TYPES[t].get("water_liking", false)))


func _test_unit_rules() -> void:
	_check("worker avoids water",
		WaterNav.unit_avoids_water({"job": "worker"}))
	_check("fleeing worker may swim",
		not WaterNav.unit_avoids_water(
			{"job": "worker", "fleeing": true}))
	_check("fishing boat does not avoid",
		not WaterNav.unit_avoids_water({"job": "fishing_boat"}))
	_check("war ship does not avoid",
		not WaterNav.unit_avoids_water({"job": "war_ship"}))


func _test_vehicle_deflect() -> void:
	var m := _fake_map()
	# Straight at the water column: deflects around or holds — never wet.
	var np := WaterNav.dry_step_vehicle(
		m, Vector2(600, 500), Vector2(1, 0), 60.0)
	_check("vehicle never lands in water",
		not WaterNav.is_water_at(m, np))
	# Open ground: drives straight.
	var np2 := WaterNav.dry_step_vehicle(
		m, Vector2(100, 500), Vector2(1, 0), 60.0)
	_check("vehicle drives straight on land", np2 == Vector2(160, 500))


func _test_wild_boar_avoids_water() -> void:
	var gs := _new_game(["humans"])
	var a := SimAnimals.new(gs)
	gs.animals = a
	var boar: Dictionary = a.spawn_wild("boar", Vector2(600, 500))
	# Diagonal heading into the water column: should slide along the
	# shore, never enter.
	boar["move_target"] = Vector2(760, 580)
	var entered := false
	for i in range(60):
		a._tick_wild_one(boar, 0.1)
		if WaterNav.is_water_at(gs.map_data,
				boar.get("position", Vector2.ZERO)):
			entered = true
	_check("calm boar never enters water", not entered)
	_check("boar not swimming", not bool(boar.get("swimming", false)))


func _test_fleeing_boar_may_swim() -> void:
	var gs := _new_game(["humans"])
	var a := SimAnimals.new(gs)
	gs.animals = a
	var boar: Dictionary = a.spawn_wild("boar", Vector2(600, 500))
	# A wolf right next to the boar triggers the real flee path
	# (running=true), which is allowed into water.
	var wolf: Dictionary = a.spawn_wild("wolf", Vector2(560, 500))
	a._rebuild_wolf_grid()
	a._tick_wild_one(boar, 0.1)
	_check("boar flees the wolf", bool(boar.get("running", false)))
	# Drive it at the water: fleeing may enter.
	boar["move_target"] = Vector2(760, 500)
	var entered := false
	for i in range(120):
		a._rebuild_wolf_grid()
		a._tick_wild_one(boar, 0.1)
		a._tick_wild_one(wolf, 0.1)
		if WaterNav.is_water_at(gs.map_data,
				boar.get("position", Vector2.ZERO)):
			entered = true
			break
	_check("fleeing boar may enter water", entered)
	_check("swimming flag set in water",
		bool(boar.get("swimming", false)) or entered)


func _test_npc_avoids_water() -> void:
	var gs := _new_game(["humans"])
	var unit := {"id": 1, "position": Vector2(600, 500), "speed": 60.0,
		"job": "worker"}
	# Walk diagonally at the water column for 3 simulated seconds.
	for i in range(60):
		WorkerAI._move_direct(gs, unit, Vector2(760, 580), 0.05)
		if WaterNav.is_water_at(gs.map_data,
				unit.get("position", Vector2.ZERO)):
			_check("calm NPC never enters water", false)
			return
	_check("calm NPC never enters water", true)
	_check("calm NPC not swimming", not bool(unit.get("swimming", false)))


func _test_fleeing_npc_swims() -> void:
	var gs := _new_game(["humans"])
	var unit := {"id": 2, "position": Vector2(600, 500), "speed": 60.0,
		"job": "worker", "fleeing": true}
	var entered := false
	for i in range(60):
		WorkerAI._move_direct(gs, unit, Vector2(760, 500), 0.05)
		if WaterNav.is_water_at(gs.map_data,
				unit.get("position", Vector2.ZERO)):
			entered = true
			break
	_check("fleeing NPC may enter water", entered)
	_check("fleeing NPC swimming flag", bool(unit.get("swimming", false)))


func _test_pathfinder_avoids_water() -> void:
	var gs := _new_game(["humans"])
	var pf := SimPathfinder.new(gs)
	# Lake-only map (no column): disc of water between start and goal.
	var m := _fake_map()
	var terrain: PackedByteArray = m["terrain"]
	terrain.fill(0)
	for ty in range(14, 20):
		for tx in range(14, 20):
			if Vector2(tx - 16.5, ty - 16.5).length() <= 3.0:
				terrain[ty * 128 + tx] = MapGen.TILE_WATER
	gs.map_data = m
	var from := Vector2(10 * 32, 17 * 32)   # west of the lake
	var to := Vector2(23 * 32, 17 * 32)     # east of the lake
	var r: Dictionary = pf.find_route(from, to, true)
	_check("route found around lake", not r.is_empty())
	if not r.is_empty():
		var wps: PackedVector2Array = r["wps"]
		var wet := false
		for wp in wps:
			if WaterNav.is_water_at(m, wp):
				wet = true
		_check("no waypoint on water", not wet)
