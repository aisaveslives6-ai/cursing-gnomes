extends SceneTree
## Cursing Gnomes — routing-layer optimization tests (2026-10-04 perf round 6).
##
## HTML source of truth: fix79/index.html _astarPathHop / computeProjectedRoute /
## routeRemainderClear / _routeCache. The Godot port was missing three of the
## HTML's mechanisms, causing (a) a full repath storm for every walking unit
## on every nav-grid rebuild, (b) one A* per squad member marching on the same
## destination, and (c) a full A* every AI tick for units whose projection
## fails (e.g. standing deep inside a building footprint).
##
## These tests pin the restored behavior:
##   1. rebuild_restamp   — route survives a nav rebuild when the remainder is
##                          still clear (re-stamped, no fresh A*).
##   2. rebuild_blocked   — a newly blocked remainder forces a real repath.
##   3. shared_cache      — two units, one destination: one cache entry.
##   4. nopath_cooldown   — failed projection sets a retry cooldown; the unit
##                          steers direct meanwhile and retries after expiry.
##   5. midwalk_rebuild   — a unit mid-walk still arrives after a rebuild.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_route_cache.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes route-cache tests ===")
	_test_rebuild_restamp()
	_test_rebuild_blocked_repaths()
	_test_shared_cache()
	_test_nopath_cooldown()
	_test_midwalk_rebuild()
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


func _make_unit(uid: int, pos: Vector2) -> Dictionary:
	return {"id": uid, "position": pos, "alive": true, "speed": 55.0}


## 1. A nav-grid rebuild must NOT force a fresh A* when the route's
## remainder is still clear: the route is re-stamped to the new grid.
func _test_rebuild_restamp() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var unit := _make_unit(1, Vector2(48, 48))
	var target := Vector2(400, 400)
	var r1: Dictionary = pf.request_route(unit, target)
	_check("restamp: route computed", not r1.is_empty())
	var wps1: PackedVector2Array = r1["wps"]
	var old_t: int = pf.nav_version()
	# Force a nav rebuild (TTL expiry / building-count change path).
	pf.mark_dirty()
	pf.sync()
	_check("restamp: grid version bumped", pf.nav_version() == old_t + 1)
	var r2: Dictionary = pf.request_route(unit, target)
	_check("restamp: route kept", not r2.is_empty())
	_check("restamp: same waypoints (no repath)",
			(r2["wps"] as PackedVector2Array) == wps1)
	_check("restamp: re-stamped to new grid",
			int(r2["grid_t"]) == pf.nav_version())
	# No fresh projection ran: the shared cache still holds the STALE entry
	# (a recompute would have erased it and stored a fresh one).
	var stale := 0
	for ck in pf._route_cache:
		if int((pf._route_cache[ck] as Dictionary).get("grid_t", -1)) != pf.nav_version():
			stale += 1
	_check("restamp: no fresh projection (cache entry still stale)", stale == 1)
	_free_pf(w)


## 2. When the rebuild puts a wall across the remaining route, the unit
## must repath around it (not keep walking into the wall).
func _test_rebuild_blocked_repaths() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	var unit := _make_unit(2, Vector2(48, 48))
	var target := Vector2(400, 400)
	var r1: Dictionary = pf.request_route(unit, target)
	_check("blocked: route computed", not r1.is_empty())
	# Drop a wall across the middle of the first leg, then rebuild the nav grid.
	var wps1: PackedVector2Array = r1["wps"]
	_check("blocked: multi-waypoint route", wps1.size() >= 2)
	var mid: Vector2 = (wps1[0] as Vector2).lerp(wps1[1] as Vector2, 0.5)
	gs.buildings.append({"type": "wall", "position": mid,
			"alive": true, "complete": true})
	pf.mark_dirty()
	pf.sync()
	var r2: Dictionary = pf.request_route(unit, target)
	_check("blocked: repath produced a route", not r2.is_empty())
	_check("blocked: new grid stamp", int(r2["grid_t"]) == pf.nav_version())
	# The new route must not walk through the wall cell.
	var wc: Vector2i = pf._cell_of(mid)
	var wk: int = pf._key(wc.x, wc.y)
	_check("blocked: wall cell is blocked", pf._nav_blocked[wk] == 1)
	var clear := true
	for p in (r2["wps"] as PackedVector2Array):
		var c: Vector2i = pf._cell_of(p)
		if pf._key(c.x, c.y) == wk:
			clear = false
	_check("blocked: new route avoids the wall", clear)
	_free_pf(w)


## 3. Two units marching on the same destination share one cached route.
func _test_shared_cache() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var target := Vector2(400, 400)
	var u1 := _make_unit(11, Vector2(48, 48))
	var u2 := _make_unit(12, Vector2(64, 40))  # same 192px start region
	var r1: Dictionary = pf.request_route(u1, target)
	_check("shared: first unit routed", not r1.is_empty())
	_check("shared: cache populated", pf._route_cache.size() == 1)
	var r2: Dictionary = pf.request_route(u2, target)
	_check("shared: second unit routed", not r2.is_empty())
	_check("shared: still one cache entry", pf._route_cache.size() == 1)
	_check("shared: second unit got the cached waypoints",
			(r2["wps"] as PackedVector2Array) == (r1["wps"] as PackedVector2Array))
	_check("shared: stamped for the second unit's own goal",
			Vector2(float(r2.get("gx", 0.0)), float(r2.get("gy", 0.0))) \
					.distance_to(target) < 1.0)
	_free_pf(w)


## 4. A unit whose projection fails (caged inside walls) gets a retry
## cooldown instead of burning an A* every call; it retries after expiry.
func _test_nopath_cooldown() -> void:
	var w := _new_pf(_open_map())
	var gs: GameState = w["gs"]
	var pf: SimPathfinder = w["pf"]
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			gs.buildings.append({"type": "wall",
					"position": Vector2(256, 256) + Vector2(dx * 40, dy * 40),
					"alive": true, "complete": true})
	pf.sync()
	var unit := _make_unit(21, Vector2(256, 256))
	var target := Vector2(480, 480)
	var r1: Dictionary = pf.request_route(unit, target)
	_check("nopath: no route (caged)", r1.is_empty())
	_check("nopath: cooldown recorded",
			float(unit.get("_pf_nopath_cd", 0.0)) > float(gs.game_time))
	var r2: Dictionary = pf.request_route(unit, target)
	_check("nopath: cooldown short-circuits retry", r2.is_empty())
	# After expiry, from open ground, the projection succeeds again.
	unit["position"] = Vector2(48, 48)
	unit["_pf_nopath_cd"] = 0.0
	var r3: Dictionary = pf.request_route(unit, Vector2(400, 400))
	_check("nopath: retry after expiry routes", not r3.is_empty())
	_free_pf(w)


## 5. A unit mid-walk still reaches its target when the nav grid rebuilds
## underneath it (the re-stamped route keeps guiding it).
func _test_midwalk_rebuild() -> void:
	var w := _new_pf(_open_map())
	var pf: SimPathfinder = w["pf"]
	var unit := _make_unit(31, Vector2(48, 48))
	var target := Vector2(400, 400)
	var arrived := false
	for i in 200:
		if i == 20:
			pf.mark_dirty()
			pf.sync()  # rebuild mid-walk
		if pf.move_routed(unit, target, 200.0, 0.05):
			arrived = true
			break
	_check("midwalk: unit arrives despite rebuild", arrived)
	_check("midwalk: ends near target",
			(unit["position"] as Vector2).distance_to(target) < 12.0)
	_free_pf(w)
