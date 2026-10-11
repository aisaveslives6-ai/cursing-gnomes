extends SceneTree
## Cursing Gnomes — no buildings on water (Jeremy 2026-10-10).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_water_placement.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: SimBuildings.footprint_in_water + the can_place_at water guard —
## houses/barns blocked on water and at the water's edge, bridges exempt,
## fishing docks allowed at the shore but not ON water, dry-land placement
## unaffected, empty map_data (pre-guard callers) keeps old behavior.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes water-placement tests ===")
	_test_center_on_water_blocked()
	_test_footprint_edge_on_water_blocked()
	_test_dry_land_allowed()
	_test_bridge_on_water_allowed()
	_test_dock_at_shore_allowed()
	_test_dock_on_water_blocked()
	_test_empty_map_data_keeps_old_behavior()
	_test_water_guard_ignores_overlap_paths()
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
## at tile coords [60..68] x [60..68]; everything else grass.
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


func _rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(4096, 4096))


func _lake_center() -> Vector2:
	# Tile (64, 64) center.
	return Vector2(64 * 32 + 16, 64 * 32 + 16)


func _test_center_on_water_blocked() -> void:
	var md := _lake_map()
	_check("house: center on water blocked",
		SimBuildings.footprint_in_water(md, "house", _lake_center()))
	_check("house: can_place_at refuses water center",
		not SimBuildings.can_place_at([], "house", _lake_center(),
			_rect(), "gnomes", 0.0, [], md))
	_check("barn: center on water blocked",
		SimBuildings.footprint_in_water(md, "barn", _lake_center()))
	_check("wall: center on water blocked",
		SimBuildings.footprint_in_water(md, "wall", _lake_center()))


func _test_footprint_edge_on_water_blocked() -> void:
	var md := _lake_map()
	var r: float = SimBuildings.footprint("house")
	# Lake spans tiles 60..68 -> world x [1920, 2208). Put the house center
	# r - 16px left of the lake's left bank so the east cardinal sits in water.
	var edge := Vector2(1920.0 - r + 16.0, _lake_center().y)
	_check("house: dry center, footprint edge in water blocked",
		SimBuildings.footprint_in_water(md, "house", edge))
	_check("house: can_place_at refuses edge-in-water",
		not SimBuildings.can_place_at([], "house", edge,
			_rect(), "gnomes", 0.0, [], md))


func _test_dry_land_allowed() -> void:
	var md := _lake_map()
	var dry := Vector2(500, 500)
	_check("house: dry land not water-blocked",
		not SimBuildings.footprint_in_water(md, "house", dry))
	_check("house: can_place_at allows dry land",
		SimBuildings.can_place_at([], "house", dry,
			_rect(), "gnomes", 0.0, [], md))


func _test_bridge_on_water_allowed() -> void:
	var md := _lake_map()
	_check("bridge: exempt from the water guard",
		not SimBuildings.footprint_in_water(md, "bridge", _lake_center()))
	_check("bridge: can_place_at allows water",
		SimBuildings.can_place_at([], "bridge", _lake_center(),
			_rect(), "gnomes", 0.0, [], md))


func _test_dock_at_shore_allowed() -> void:
	var md := _lake_map()
	# Shore spot: dry grass just west of the lake, water within dock range.
	var shore := Vector2(1800, _lake_center().y)
	_check("fishing_dock: shore placement not water-blocked",
		not SimBuildings.footprint_in_water(md, "fishing_dock", shore))
	_check("fishing_dock: can_place_at allows shore",
		SimBuildings.can_place_at([], "fishing_dock", shore,
			_rect(), "gnomes", 0.0, [], md))


func _test_dock_on_water_blocked() -> void:
	var md := _lake_map()
	_check("fishing_dock: on water blocked",
		SimBuildings.footprint_in_water(md, "fishing_dock", _lake_center()))
	_check("fishing_dock: can_place_at refuses water",
		not SimBuildings.can_place_at([], "fishing_dock", _lake_center(),
			_rect(), "gnomes", 0.0, [], md))


func _test_empty_map_data_keeps_old_behavior() -> void:
	# Callers without terrain data (or tests) must not crash and must keep
	# the pre-guard behavior.
	_check("empty map_data: guard reports false",
		not SimBuildings.footprint_in_water({}, "house", Vector2(64, 64)))
	_check("empty map_data: can_place_at still allows",
		SimBuildings.can_place_at([], "house", Vector2(500, 500),
			_rect(), "gnomes", 0.0, [], {}))


func _test_water_guard_ignores_overlap_paths() -> void:
	# The water check must not mask the other rules: overlap still rejects,
	# and a dry valid spot still passes through the full pipeline.
	var md := _lake_map()
	var dry := Vector2(500, 500)
	var buildings: Array = [{
		"alive": true, "type": "house", "complete": true,
		"faction": "gnomes", "position": dry,
	}]
	_check("overlap: still rejected on dry land",
		not SimBuildings.can_place_at(buildings, "house", dry,
			_rect(), "gnomes", 0.0, [], md))
	_check("no overlap: allowed on dry land",
		SimBuildings.can_place_at(buildings, "house", dry + Vector2(400, 0),
			_rect(), "gnomes", 0.0, [], md))
