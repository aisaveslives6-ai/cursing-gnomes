extends SceneTree
## Cursing Gnomes — A* pathfinding tests.
##
## Ports of the HTML's movement routing (from fix79/index.html):
##   astarDGrid        — A* with binary heap, tie-breaker, best-effort
##   findUnitPathCells — road/bridge/water/cliff/building costs
##   computeProjectedRoute — project once, cache on unit
##   smoothRouteCells  — string-pulling smoothing
##   CANDIDATE30       — stuck nudge-out recovery
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_pathfinding.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes pathfinding tests ===")
	_test_astar_open_ground()
	_test_astar_around_building()
	_test_astar_cliff_blocked()
	_test_astar_unreachable_fallback()
	_test_road_preferred()
	_test_route_cached()
	_test_direct_under_threshold()
	_test_move_routed_arrives()
	_test_stuck_recovery()
	_test_road_speed_bonus()
	_test_smoothing()
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
	pf.unlimited_budget = true  # headless: frames never advance
	gs.pathfinder = pf
	return {"gs": gs, "pf": pf}


func _free_pf(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _test_astar_open_ground() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var r := pf.find_route(Vector2(48, 48), Vector2(400, 400))
	_check("open ground: route found", not r.is_empty())
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	_check("open ground: has waypoints", wps.size() >= 2)
	_check("open ground: ends at target",
			wps[wps.size() - 1].distance_to(Vector2(400, 400)) < 1.0)
	_free_pf(w)


func _test_astar_around_building() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	# A wall of buildings blocking the straight line at x=256.
	for i in 5:
		gs.buildings.append({"type": "house", "position": Vector2(256, 96 + i * 64),
				"alive": true, "complete": true})
	pf.sync()
	var r := pf.find_route(Vector2(96, 256), Vector2(416, 256))
	_check("building wall: route found", not r.is_empty())
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	var clear := true
	for wp in wps:
		# No waypoint deep inside the building column (x 224..288, y 120..340).
		# Detour corners near the wall's ends are fine.
		if absf(wp.x - 256.0) < 40.0 and wp.y > 120.0 and wp.y < 340.0:
			clear = false
	_check("building wall: route goes around", clear)
	_free_pf(w)


func _test_astar_cliff_blocked() -> void:
	var map := _open_map()
	var levels: PackedByteArray = map["levels"]
	# Sheer cliff: column 8 at level 5, everything else level 1.
	for y in 16:
		levels[y * 16 + 8] = 5
	var w := _new_pf(map)
	var pf: SimPathfinder = w["pf"]
	var r := pf.find_route(Vector2(96, 256), Vector2(416, 256))
	_check("cliff: route found (detour)", not r.is_empty())
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	var clear := true
	for wp in wps:
		var c := Vector2i(clampi(int(wp.x / 32.0), 0, 15),
				clampi(int(wp.y / 32.0), 0, 15))
		if c.x == 8:
			clear = false
	_check("cliff: route avoids sheer face", clear)
	_free_pf(w)


func _test_astar_unreachable_fallback() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	# Surround the goal cell's whole row with buildings except start side.
	for x in 16:
		for y in 16:
			if x > 10:
				gs.buildings.append({"type": "wall",
						"position": Vector2(x * 32 + 16, y * 32 + 16),
						"alive": true, "complete": true})
	pf.sync()
	var r := pf.find_route(Vector2(48, 48), Vector2(480, 480))
	# Best-effort: returns a partial path, never empty/hang.
	_check("unreachable: best-effort path returned", not r.is_empty())
	_free_pf(w)


func _test_road_preferred() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	# L-shaped dirt road: (96,256) -> (256,256) -> (256,416).
	var roads: Array = []
	var p := Vector2(96, 256)
	while p.x <= 256.0:
		roads.append({"position": p, "type": "dirt", "faction": "humans"})
		p.x += 24.0
	p = Vector2(256, 280)
	while p.y <= 416.0:
		roads.append({"position": p, "type": "dirt", "faction": "humans"})
		p.y += 24.0
	var host := WorkerAI.new(gs)
	for rd in roads:
		host.roads.append(rd)
	pf.bind_roads(host)
	pf.mark_dirty()
	pf.sync()
	var r := pf.find_route(Vector2(96, 256), Vector2(256, 416))
	_check("road: route found", not r.is_empty())
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	# Route should hug the road corridor (x~256 for the vertical leg).
	var on_road := 0
	for wp in wps:
		if absf(wp.x - 256.0) < 48.0 or absf(wp.y - 256.0) < 48.0:
			on_road += 1
	_check("road: route follows road corridor",
			float(on_road) / float(maxi(1, wps.size())) > 0.5)
	_check("road: is_on_road detects road cell",
			pf.is_on_road(Vector2(256, 300)))
	_free_pf(w)


func _test_route_cached() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var unit := {"id": 1, "position": Vector2(48, 48), "alive": true,
			"speed": 55.0}
	var target := Vector2(400, 400)
	var r1: Dictionary = pf.request_route(unit, target)
	_check("cache: first request computes", not r1.is_empty())
	var r2: Dictionary = pf.request_route(unit, target)
	_check("cache: second request hits cache",
			r2.get("wps") == r1.get("wps"))
	# Goal moved far: repath.
	var r3: Dictionary = pf.request_route(unit, Vector2(100, 400))
	_check("cache: moved goal repaths",
			Vector2(r3.get("gx", 0.0), r3.get("gy", 0.0)) \
					.distance_to(Vector2(100, 400)) < 1.0)
	_free_pf(w)


func _test_direct_under_threshold() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	gs.pathfinder = pf
	var unit := {"id": 2, "position": Vector2(100, 100), "alive": true,
			"speed": 55.0}
	# 100 px < 200 px threshold: direct, no route cached.
	var arrived := pf.move_routed(unit, Vector2(150, 100), 55.0, 1.0)
	_check("direct: moves toward target",
			(unit["position"] as Vector2).x > 100.0)
	_check("direct: no route cached", not unit.has("_pf_route"))
	_free_pf(w)


func _test_move_routed_arrives() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	gs.pathfinder = pf
	var unit := {"id": 3, "position": Vector2(48, 48), "alive": true,
			"speed": 200.0}
	var target := Vector2(400, 400)
	var arrived := false
	for i in 200:
		if pf.move_routed(unit, target, 200.0, 0.05):
			arrived = true
			break
	_check("routed: unit arrives", arrived)
	_check("routed: ends near target",
			(unit["position"] as Vector2).distance_to(target) < 12.0)
	_free_pf(w)


func _test_stuck_recovery() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	gs.pathfinder = pf
	# Cage the unit in buildings; target outside. It must not hang —
	# stuck recovery nudges it out or it keeps trying sanely.
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			gs.buildings.append({"type": "wall",
					"position": Vector2(256, 256) + Vector2(dx * 40, dy * 40),
					"alive": true, "complete": true})
	pf.sync()
	var unit := {"id": 4, "position": Vector2(256, 256), "alive": true,
			"speed": 55.0}
	var ok := true
	for i in 400:
		pf.move_routed(unit, Vector2(480, 480), 55.0, 0.05)
		var p: Vector2 = unit["position"]
		if not is_finite(p.x) or not is_finite(p.y):
			ok = false
			break
	_check("stuck: no NaN/hang after 400 ticks", ok)
	_free_pf(w)


func _test_road_speed_bonus() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var gs: GameState = w["gs"]
	var host := WorkerAI.new(gs)
	host.roads.append({"position": Vector2(100, 100), "type": "stone",
			"faction": "humans"})
	pf.bind_roads(host)
	pf.mark_dirty()
	pf.sync()
	_check("road bonus: stone cell detected", pf.is_on_road(Vector2(100, 100)))
	_check("road bonus: grass not road", not pf.is_on_road(Vector2(400, 400)))
	# Speed multiplier constant sanity.
	_check("road bonus: multiplier > 1", SimPathfinder.ROAD_SPEED_MULT > 1.0)
	_free_pf(w)


func _test_smoothing() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var r := pf.find_route(Vector2(48, 48), Vector2(400, 400))
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	# Open ground diagonal: smoothing should collapse to very few waypoints.
	_check("smoothing: open diagonal is ~2 waypoints", wps.size() <= 3)
	_free_pf(w)
