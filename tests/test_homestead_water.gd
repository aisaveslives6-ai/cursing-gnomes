extends SceneTree
## Cursing Gnomes — homestead water-hole regression (Jeremy 2026-10-10 P0).
##
## Jeremy photographed a survival-craft house under construction sitting in
## a lake: _start_homestead stored the unit's raw position with NO water
## check, bypassing SimBuildings.can_place_at entirely (all other
## placement paths are covered by the 2026-10-10 no-buildings-on-water
## rule). These tests prove the hole is closed:
## - _start_homestead nudges a waterlogged spot to the nearest dry land
## - dry spots pass through unchanged
## - _spot_blocked rejects water (so _homestead_try_build re-picks, and
##   _find_wild_spot never returns a water spot)
## - empty map_data keeps the old behavior (no-op guard)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_homestead_water.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes homestead-water tests ===")
	_test_start_homestead_nudges_off_water()
	_test_start_homestead_dry_spot_unchanged()
	_test_spot_blocked_rejects_water()
	_test_find_wild_spot_never_water()
	_test_empty_map_data_keeps_old_behavior()
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


## 128x128 terrain grid, 32px tiles (4096px world). A lake of water tiles
## at tile coords [60..68] x [60..68] -> world [1920..2208]px; lake center
## ~(2064, 2064). Everything else grass.
func _lake_map() -> Dictionary:
	var n := MapGen.MAP_TILES * MapGen.MAP_TILES
	var terrain := PackedByteArray()
	terrain.resize(n)
	for i in n:
		terrain[i] = MapGen.TILE_GRASS
	for ty in range(60, 69):
		for tx in range(60, 69):
			terrain[ty * MapGen.MAP_TILES + tx] = MapGen.TILE_WATER
	return {"terrain": terrain, "tile_size": 32.0,
		"world_w": 4096.0, "world_h": 4096.0}


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"] as Array[String])
	gs.map_data = _lake_map()
	return {"gs": gs, "housing": SimHousing.new(gs)}


func _homeless_unit(uid: int, pos: Vector2) -> Dictionary:
	return {"id": uid, "alive": true, "job": "worker", "faction": "gnomes",
		"position": pos, "home": {}}


func _is_dry(gs: GameState, spot: Vector2) -> bool:
	return not SimBuildings.footprint_in_water(gs.map_data, "house", spot)


func _test_start_homestead_nudges_off_water() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var lake := Vector2(2064, 2064)
	_check("lake spot is really water", not _is_dry(gs, lake))
	var u := _homeless_unit(101, lake)
	housing._start_homestead(u, u["position"])
	var hs: Dictionary = u.get("_homestead", {})
	_check("homestead started", not hs.is_empty())
	var spot: Vector2 = hs.get("spot", Vector2(-1, -1))
	_check("nudged spot is dry", _is_dry(gs, spot))
	_check("nudged spot near the lake (nearest dry land)",
		spot.distance_to(lake) <= 1150.0)
	gs.queue_free()


func _test_start_homestead_dry_spot_unchanged() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var dry := Vector2(1000, 1000)
	_check("dry spot is really dry", _is_dry(gs, dry))
	var u := _homeless_unit(102, dry)
	housing._start_homestead(u, u["position"])
	var spot: Vector2 = (u["_homestead"] as Dictionary).get("spot",
		Vector2(-1, -1))
	_check("dry spot passes through unchanged", spot == dry)
	gs.queue_free()


func _test_spot_blocked_rejects_water() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var u := _homeless_unit(103, Vector2(1000, 1000))
	_check("water spot blocked", housing._spot_blocked(u, Vector2(2064, 2064)))
	_check("dry spot not blocked", not housing._spot_blocked(u, Vector2(1000, 1000)))
	gs.queue_free()


func _test_find_wild_spot_never_water() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var all_ok := true
	for uid in range(201, 209):
		var u := _homeless_unit(uid, Vector2(2064, 2064))
		var spot: Vector2 = housing._find_wild_spot(u)
		if spot.x >= 0.0 and not _is_dry(gs, spot):
			all_ok = false
	_check("wild-spot picks across 8 uids: dry or none", all_ok)
	gs.queue_free()


func _test_empty_map_data_keeps_old_behavior() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"] as Array[String])
	gs.map_data = {}  # test-stub guard: footprint_in_water no-ops
	var housing := SimHousing.new(gs)
	var lake := Vector2(2064, 2064)
	var u := _homeless_unit(104, lake)
	housing._start_homestead(u, u["position"])
	var spot: Vector2 = (u["_homestead"] as Dictionary).get("spot",
		Vector2(-1, -1))
	_check("empty map_data: raw spot stored unchanged", spot == lake)
	gs.queue_free()
