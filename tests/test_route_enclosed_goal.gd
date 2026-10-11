extends SceneTree
## Cursing Gnomes — round 9 pathfinding perf tests.
##
## Enclosed-goal early-out + stagnation bailout (2026-10-04): routing to a
## goal cell surrounded by blocked cells (e.g. a hall center inside its own
## footprint) used to burn all MAX_EXPANSIONS (4500, ~120-260 ms) before
## returning a best-effort partial. Now: enclosed goals retarget to the
## nearest walkable cell up front, and any A* that stops converging bails
## after 400 stagnant expansions. Behavior for reachable goals is
## unchanged (same A*, same waypoints).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_route_enclosed_goal.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes enclosed-goal route tests ===")
	_test_enclosed_goal_fast()
	_test_enclosed_goal_waypoints_walkable()
	_test_enclosed_goal_keeps_original_target()
	_test_reachable_goal_unchanged()
	_test_walled_goal_bails_fast()
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


## 16x16 open grass map, all level 1.
func _open_map() -> Dictionary:
	var terrain := PackedByteArray()
	terrain.resize(256)
	var levels := PackedByteArray()
	levels.resize(256)
	for i in 256:
		levels[i] = 1
	return {"terrain": terrain, "levels": levels,
			"size_tiles": Vector2i(16, 16), "tile_size": 32}


func _new_pf(map_data: Dictionary) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = map_data
	var pf := SimPathfinder.new(gs)
	pf.unlimited_budget = true
	gs.pathfinder = pf
	return {"gs": gs, "pf": pf}


func _free_pf(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


## 3x3 building footprint centered on (8,8): the center cell's 8 neighbors
## are all blocked, like a hall center.
func _hall_map() -> Dictionary:
	var md := _open_map()
	return md


func _add_footprint(gs: GameState, cx: int, cy: int) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			gs.buildings.append({"type": "town_hall",
					"position": Vector2((cx + dx) * 32 + 16, (cy + dy) * 32 + 16),
					"alive": true, "complete": true})


func _test_enclosed_goal_fast() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	_add_footprint(gs, 8, 8)
	pf.sync()
	# Hall center at (8*32+16, 8*32+16) = (272, 272).
	var t0 := Time.get_ticks_usec()
	var r := pf.find_route(Vector2(48, 48), Vector2(272, 272))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_check("enclosed: route returned", not r.is_empty())
	_check("enclosed: fast (<50ms, was ~120ms+)", ms < 50.0)
	_free_pf(w)


func _test_enclosed_goal_waypoints_walkable() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	_add_footprint(gs, 8, 8)
	pf.sync()
	var r := pf.find_route(Vector2(48, 48), Vector2(272, 272))
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	# All waypoints except the final (original target) must be on
	# non-blocked cells.
	var blocked: PackedByteArray = pf.get("_nav_blocked")
	var ok := true
	for i in range(wps.size() - 1):
		var c: Vector2i = pf.call("_cell_of", wps[i])
		if blocked[pf.call("_key", c.x, c.y)] == 1:
			ok = false
	_check("enclosed: waypoints avoid blocked cells", ok)
	_check("enclosed: has waypoints", wps.size() >= 2)
	_free_pf(w)


func _test_enclosed_goal_keeps_original_target() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	_add_footprint(gs, 8, 8)
	pf.sync()
	var r := pf.find_route(Vector2(48, 48), Vector2(272, 272))
	# gx/gy stay on the original target so route validity, arrival, and
	# cache keys behave exactly as before.
	_check("enclosed: gx/gy = original target",
			float(r.get("gx", -1.0)) == 272.0 and float(r.get("gy", -1.0)) == 272.0)
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	_check("enclosed: final waypoint = original target",
			wps[wps.size() - 1].distance_to(Vector2(272, 272)) < 1.0)
	_free_pf(w)


func _test_reachable_goal_unchanged() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	_add_footprint(gs, 8, 8)
	pf.sync()
	# Open-ground target far from the footprint: must route normally and
	# actually reach it.
	var r := pf.find_route(Vector2(48, 48), Vector2(400, 400))
	_check("reachable: route found", not r.is_empty())
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	_check("reachable: ends at target",
			wps[wps.size() - 1].distance_to(Vector2(400, 400)) < 1.0)
	_free_pf(w)


func _test_walled_goal_bails_fast() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	# Wall off the entire right half: goal behind an unbroken wall.
	for x in range(10, 16):
		for y in range(16):
			gs.buildings.append({"type": "wall",
					"position": Vector2(x * 32 + 16, y * 32 + 16),
					"alive": true, "complete": true})
	pf.sync()
	var t0 := Time.get_ticks_usec()
	var r := pf.find_route(Vector2(48, 48), Vector2(480, 480))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	# Best-effort partial, but fast — stagnation bailout, not 4500 expansions.
	_check("walled: best-effort returned", not r.is_empty())
	_check("walled: bails fast (<50ms)", ms < 50.0)
	_free_pf(w)
