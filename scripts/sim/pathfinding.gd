class_name SimPathfinder
extends RefCounted
## Cursing Gnomes — real A* pathfinding (ported from HTML fix79).
##
## The old movement steered straight at targets (units walked through
## buildings; armies plowed through towns). This ports the HTML's
## astarDGrid + findUnitPathCells + computeProjectedRoute stack:
##
##   - A* over the map tile grid with a binary heap, cross-product
##     tie-breaker, and best-effort fallback (HTML astarDGrid).
##   - HTML-parity movement costs: stone roads 0.18, dirt roads 0.28,
##     bridges 0.9, off-road 1.6, rough (trees) 2.6, swim 7.5,
##     +1 climb 2.2, sheer cliffs (|level diff| > 1) impassable,
##     buildings/walls block.
##   - Routes are projected ONCE per order and cached on the unit
##     (HTML Stage 1); per-frame work is just waypoint steering.
##   - Per-tick route budget with a queue (HTML ROUTE_MS_PER_TICK).
##   - Repath when the goal moves, the nav grid rebuilds, or a waypoint
##     gets built over; stuck detection + nudge-out recovery.
##   - String-pulling smoothing so movement reads as smooth curves,
##     not grid zig-zags.
##
## Performance (iPhone Safari): the nav grid rebuilds at most every 8 s
## (HTML TTL) or when the building count changes; A* caps at 4500
## expansions; only 6 fresh routes compute per tick (rest queue).
## Pure logic — no nodes. Owned by World, exposed via GameState.pathfinder.


## Movement costs — HTML findUnitPathCells parity.
const COST_STONE_ROAD := 0.18
const COST_DIRT_ROAD := 0.28

## Wear-scaled road step cost (Jeremy 2026-10-10 road wear): a fresh road
## costs its engineered base; a fully worn road costs off-road — worn roads
## lose their movement bonus. Pure static so tests pin the formula; the A*
## hot loop calls this (identical math to the old inline form, one static
## call — the R16 call-free loop's single exception, ~ns).
static func road_step_cost(base_cost: float, wear01: float) -> float:
	return base_cost + (COST_OFFROAD - base_cost) * wear01


const COST_BRIDGE := 0.9
const COST_OFFROAD := 1.6
const COST_ROUGH := 2.6
const COST_SWIM := 7.5
const COST_UPHILL := 2.2
## Jeremy 2026-10-10 visible road construction: segments under construction
## are closed — costly enough to route around (worse than rough), never
## hard-blocked (a unit whose goal sits inside still gets there).
const COST_WORKZONE := 5.0
const DIAG_MULT := 1.4142

const MAX_EXPANSIONS := 4500
const HEUR_MULT := 3.2  # HTML: hCost 1.6 * hWeight 2.0 (weighted A*)
const TIE_BREAK := 0.001  # cross-product tie-breaker (HTML Stage 1)

const ROUTE_DIRECT_DIST := 200.0  # below: direct steering (HTML parity)
const WAYPOINT_ADVANCE := 20.0    # HTML: 20px advance threshold
const WAYPOINT_ADVANCE_SQ := WAYPOINT_ADVANCE * WAYPOINT_ADVANCE
const GOAL_MOVED_REPATH := 60.0   # goal drift that forces a repath
const GOAL_MOVED_REPATH_SQ := GOAL_MOVED_REPATH * GOAL_MOVED_REPATH
## Perf R18: route-validity stagger — a full request_route validity check
## runs when (physics_frame + unit_id) % VALIDITY_STAGGER == 0 (see
## move_routed). Jeremy 2026-10-05: "evenly distribute the cycles".
const VALIDITY_STAGGER := 3
## HTML ROUTE_MS_PER_TICK parity: max ms per tick spent projecting routes
## (iPhone-safe). Time-based, not count-based: a cold A* on a blocked map
## costs ~9ms on desktop (more on iPhone), so a count budget of 6 could
## burn 50ms+ in a single frame. The ms budget self-scales to the device.
const ROUTE_MS_PER_TICK := 4.0
const ROAD_SPEED_MULT := 1.3      # roads are engineered: faster travel
const NAV_TTL := 8.0              # nav grid rebuild TTL (HTML parity)
const ARRIVE_DIST := 6.0
const EASE_DIST := 48.0           # arrival easing zone (smooth stops)
const STUCK_TIME := 1.5           # seconds without progress = stuck
const STUCK_MIN_MOVE := 4.0       # px that counts as progress
const STUCK_MAX_REPATHS := 3      # then nudge to a free cell
const ROUTE_CACHE_MAX := 96       # HTML ROUTE_CACHE_MAX parity
const ROUTE_CACHE_REACH := 200.0  # only cache routes that reach the dest
const NOPATH_RETRY_CD := 2.0      # s before retrying a failed projection

const INF := 1e30


var _gs  # GameState (untyped: core <-> sim cycle)
var _roads_host  # WorkerAI — owns the painted road list


## Nav grid cache — dense byte grids (R16: Dictionaries replaced; identical
## membership info, ~3x cheaper per lookup in the A* hot loop).
var _nav_blocked := PackedByteArray()  # int cell -> 1 = blocked
var _nav_road := PackedByteArray()     # int cell -> 0 none | 1 dirt | 2 stone
var _nav_road_wear := PackedByteArray()  # int cell -> 0..255 road wear
var _nav_bridge := PackedByteArray()   # int cell -> 1 = bridge deck
var _nav_rough := PackedByteArray()    # int cell -> 1 = trees (rough)
var _nav_workzone := PackedByteArray()  # int cell -> 1 = closed work zone
var _nav_t := 0
var _nav_built_at := -100.0
var _nav_building_count := -1
var _nav_map_key := ""
var _map_w := 0
var _map_h := 0
var _tile := 32.0
## Hoisted cliff-level arrays for the movement hot path (zero dict gets
## per step). Refreshed in _build_nav alongside the nav grid; read by
## _steer via Cliffs.try_step_fast. Same source as find_route's arrays.
var _pf_levels := PackedByteArray()
var _pf_terr := PackedByteArray()
var _pf_sx := 0
var _pf_sy := 0
var _pf_tile := 32
## R35: water-check inputs hoisted with is_water_at's exact defaults
## (size_tiles (128,128), tile_size 32.0), plus a has-water flag so the
## per-step shoreline checks short-circuit on dry maps. Refreshed in
## _build_nav; read by _steer/move_routed via WaterNav.is_water_at_fast.
var _pf_wterr := PackedByteArray()
var _pf_wsx := 128
var _pf_wsy := 128
var _pf_wtile := 32.0
var _pf_has_water := false
## The map_data Dictionary the hoisted arrays were built from (reference).
## Compared with is_same() — map_data is replaced (never mutated) on
## new game/load, so a reference check is sufficient for freshness.
var _pf_map_ref := {}

var _route_queue: Array = []  # [{unit, target}]
var _budget_frame := -1
## A* milliseconds spent this process frame (HTML _routeMsThisTick parity).
## Reset lazily on the first route request of each process frame.
var _route_ms_this_tick := 0.0
## Shared route cache (HTML _routeCache parity): "a squad marching on one
## point computes once." Key -> {"wps": PackedVector2Array, "grid_t": int}.
## Entries are only valid for the nav grid they were computed against.
var _route_cache := {}
## Tests set this to bypass the per-tick route budget (headless runs never
## advance Engine.get_process_frames, so the budget would never reset).
var unlimited_budget := false


func _init(game_state) -> void:
	_gs = game_state


## WorkerAI owns roads; the pathfinder reads them on nav rebuilds.
func bind_roads(roads_host) -> void:
	_roads_host = roads_host


func mark_dirty() -> void:
	_nav_building_count = -1  # force rebuild on next sync


## Called each tick by World. Rebuilds the nav grid when stale.
func sync() -> void:
	_ensure_nav()


## Current nav grid version (routes stamp this; mismatch = repath).
func nav_version() -> int:
	return _nav_t


func _map_key_for(map_data: Dictionary) -> String:
	var size: Vector2i = map_data.get("size_tiles", Vector2i.ZERO)
	return "%d_%d_%d" % [size.x, size.y, int(map_data.get("tile_size", 32))]


var _cached_map_key := ""
var _cached_key_size := Vector2i(-1, -1)
var _cached_key_tile := -1


func _ensure_nav() -> void:
	var map_data: Dictionary = _gs.map_data
	if map_data.is_empty():
		return
	var now: float = _gs.game_time
	# Jeremy 2026-10-04 perf: cache the map key string — was formatted
	# every physics frame (60Hz string alloc). Key derives from size +
	# tile_size, so compare those cheaply instead of deep-comparing dicts.
	var sz: Vector2i = map_data.get("size_tiles", Vector2i.ZERO)
	var ts: int = int(map_data.get("tile_size", 32))
	var key: String = _cached_map_key
	if sz != _cached_key_size or ts != _cached_key_tile:
		key = _map_key_for(map_data)
		_cached_map_key = key
		_cached_key_size = sz
		_cached_key_tile = ts
	var bcount: int = _gs.buildings.size()
	var rcount: int = _roads_host.roads.size() if _roads_host != null else 0
	var wver: int = int(_roads_host.road_wear_version) \
		if _roads_host != null else 0
	var vver: int = int(_roads_host.road_work_version) \
		if _roads_host != null else 0
	if key == _nav_map_key and bcount == _nav_building_count \
			and rcount == _nav_road_count \
			and wver == _nav_road_wear_ver \
			and vver == _nav_work_ver \
			and now - _nav_built_at < NAV_TTL:
		return
	_build_nav(map_data, key, bcount, rcount, wver, vver, now)


var _nav_road_count := -1
var _nav_road_wear_ver := -1
var _nav_work_ver := -1


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(clampi(int(pos.x / _tile), 0, _map_w - 1),
			clampi(int(pos.y / _tile), 0, _map_h - 1))


func _key(tx: int, ty: int) -> int:
	return ty * _map_w + tx


func _world_of(tx: int, ty: int) -> Vector2:
	return Vector2((float(tx) + 0.5) * _tile, (float(ty) + 0.5) * _tile)


## Builds the blocked/road/bridge/rough/workzone cell sets.
func _build_nav(map_data: Dictionary, key: String, bcount: int,
		rcount: int, wver: int, vver: int, now: float) -> void:
	var size: Vector2i = map_data.get("size_tiles", Vector2i.ZERO)
	_map_w = maxi(1, size.x)
	_map_h = maxi(1, size.y)
	_tile = float(maxi(1, int(map_data.get("tile_size", 32))))
	# Hoisted cliff arrays for the movement hot path (Cliffs.try_step_fast).
	# Same guards as find_route: mismatched arrays count as absent.
	var _lv: PackedByteArray = map_data.get("levels", PackedByteArray())
	var _tr: PackedByteArray = map_data.get("terrain", PackedByteArray())
	var _cells := _map_w * _map_h
	_pf_levels = _lv if _lv.size() == _cells else PackedByteArray()
	_pf_terr = _tr if _tr.size() == _cells else PackedByteArray()
	_pf_sx = _map_w
	_pf_sy = _map_h
	_pf_tile = maxi(1, int(map_data.get("tile_size", 32)))
	_pf_map_ref = map_data
	# R35: hoist is_water_at's exact inputs (same defaults) + has-water
	# flag. One scan per nav build; the per-step shoreline checks in
	# _steer/move_routed then short-circuit on dry maps and skip
	# is_water_at's 4 dict gets on wet ones. Identical results.
	var _wtr = map_data.get("terrain", null)
	_pf_wterr = _wtr if _wtr is PackedByteArray else PackedByteArray()
	var _wsz: Vector2i = map_data.get("size_tiles", Vector2i(128, 128))
	_pf_wsx = _wsz.x
	_pf_wsy = _wsz.y
	_pf_wtile = float(map_data.get("tile_size", 32.0))
	_pf_has_water = false
	for t in _pf_wterr:
		if MapGen.is_water(int(t)):
			_pf_has_water = true
			break
	_nav_blocked.resize(_cells)
	_nav_blocked.fill(0)
	_nav_road.resize(_cells)
	_nav_road.fill(0)
	_nav_road_wear.resize(_cells)
	_nav_road_wear.fill(0)
	_nav_bridge.resize(_cells)
	_nav_bridge.fill(0)
	_nav_rough.resize(_cells)
	_nav_rough.fill(0)
	_nav_workzone.resize(_cells)
	_nav_workzone.fill(0)
	# Buildings block; bridges are walkable decks.
	for b in _gs.buildings:
		if not bool(b.get("alive", true)):
			continue
		var btype := String(b.get("type", ""))
		var pos: Vector2 = b.get("position", Vector2.ZERO)
		var r := SimBuildings.footprint(btype)
		if btype == "bridge":
			_paint_disc(_nav_bridge, pos, r, 1)
		else:
			_paint_disc(_nav_blocked, pos, r, 1)
	# Painted roads: cheap to travel — unless worn out (Jeremy 2026-10-10
	# road wear: wear rides along in a parallel byte grid so the A* cost
	# can scale a crumbled segment back up toward off-road).
	if _roads_host != null:
		for rd in _roads_host.roads:
			var c := _cell_of(rd.get("position", Vector2.ZERO))
			var kk := _key(c.x, c.y)
			_nav_road[kk] = \
					2 if String(rd.get("type", "dirt")) == "stone" else 1
			_nav_road_wear[kk] = int(float(rd.get("wear", 0.0)) * 255.0)
	# Jeremy 2026-10-10 visible road construction: active work zones are
	# closed — painted into their own byte grid so the A* cost routes
	# foot traffic around them until the segment opens.
	if _roads_host != null:
		for z in _roads_host.road_work_zones():
			var zd: Dictionary = z
			if not bool(zd.get("closed", true)):
				continue  # surveyed plans are marked, not closed
			if String(zd.get("kind", "")) == "disc":
				_paint_disc(_nav_workzone,
					zd.get("pos", Vector2.ZERO),
					float(zd.get("r", 56.0)), 1)
			else:
				_paint_seg(_nav_workzone,
					zd.get("a", Vector2.ZERO), zd.get("b", Vector2.ZERO),
					float(zd.get("r", 44.0)), 1)
	# Trees are rough terrain (costly, not blocked).
	var trees = map_data.get("trees", PackedVector2Array())
	if trees is PackedVector2Array:
		for tp in trees:
			var c := _cell_of(tp)
			_nav_rough[_key(c.x, c.y)] = 1
	_nav_map_key = key
	_nav_building_count = bcount
	_nav_road_count = rcount
	_nav_road_wear_ver = wver
	# Read live: painting the zones above may have bumped the version.
	_nav_work_ver = int(_roads_host.road_work_version) \
		if _roads_host != null else vver
	_nav_built_at = now
	_nav_t += 1


func _paint_disc(cells: PackedByteArray, pos: Vector2, radius: float,
		val: int) -> void:
	var c := _cell_of(pos)
	var cr := int(ceil(radius / _tile))
	for dy in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var tx := c.x + dx
			var ty := c.y + dy
			if tx < 0 or ty < 0 or tx >= _map_w or ty >= _map_h:
				continue
			var wp := _world_of(tx, ty)
			if wp.distance_to(pos) <= radius + _tile * 0.5:
				cells[_key(tx, ty)] = val


## Paints a corridor of discs along a segment (work-zone closures).
func _paint_seg(cells: PackedByteArray, a: Vector2, b: Vector2,
		radius: float, val: int) -> void:
	var d := a.distance_to(b)
	var steps := maxi(1, int(ceil(d / (_tile * 0.5))))
	for i in range(steps + 1):
		_paint_disc(cells, a.lerp(b, float(i) / float(steps)), radius, val)


## Raw A*. Returns {wps: PackedVector2Array, gx, gy, grid_t} or {}.
## True when every neighbor of the goal cell is blocked (and isn't the
## start cell, which the step-cost logic exempts). A* could never step onto
## such
## a goal — e.g. a hall center inside its own footprint.
func _goal_enclosed(gc: Vector2i, start_k: int, goal_k: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
			Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1),
			Vector2i(-1, 1), Vector2i(-1, -1)]:
		var nx: int = gc.x + d.x
		var ny: int = gc.y + d.y
		if nx < 0 or ny < 0 or nx >= _map_w or ny >= _map_h:
			continue
		var nk := _key(nx, ny)
		if nk == start_k or nk == goal_k:
			continue  # exempt cells are steppable
		if _nav_blocked[nk] != 1:
			return false
	return true


## Spiral search outward from an enclosed goal for the nearest walkable
## cell. Bounded at 12 rings (a building footprint is ~2-4); falls back
## to the goal itself so A* does its old best-effort as before.
func _nearest_open_cell(gc: Vector2i, start_k: int, goal_k: int) -> Vector2i:
	for ring in range(1, 13):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var nx: int = gc.x + dx
				var ny: int = gc.y + dy
				if nx < 0 or ny < 0 or nx >= _map_w or ny >= _map_h:
					continue
				var nk := _key(nx, ny)
				if nk == start_k or nk == goal_k:
					return Vector2i(nx, ny)
				if _nav_blocked[nk] != 1:
					return Vector2i(nx, ny)
	return gc


func find_route(from: Vector2, to: Vector2,
		avoid_water: bool = false) -> Dictionary:
	_ensure_nav()
	var map_data: Dictionary = _gs.map_data
	if map_data.is_empty() or _map_w <= 0:
		return {}
	var sc := _cell_of(from)
	var gc := _cell_of(to)
	var start_k := _key(sc.x, sc.y)
	var goal_k := _key(gc.x, gc.y)
	if start_k == goal_k:
		return {"wps": PackedVector2Array([to]), "gx": to.x, "gy": to.y,
				"grid_t": _nav_t}
	# Jeremy 2026-10-04 perf (round 9): enclosed-goal early-out. When the
	# goal cell is completely surrounded by blocked cells (e.g. a building
	# center like a hall), A* can never step onto it — the search would
	# burn all MAX_EXPANSIONS (~120-260 ms) and return a best-effort
	# partial anyway. Retarget to the nearest walkable cell up front; the
	# route computes in ~ms and is identical in practice. The final meters
	# are still closed by direct steering (HTML fallback), and the
	# returned gx/gy stay on the original target, so arrival, route
	# validity, and cache behavior are unchanged.
	if _goal_enclosed(gc, start_k, goal_k):
		gc = _nearest_open_cell(gc, start_k, goal_k)
		goal_k = _key(gc.x, gc.y)
	var terrain: PackedByteArray = _pf_terr
	var levels: PackedByteArray = _pf_levels
	# Guard: a terrain/levels array whose length doesn't match the grid
	# would crash on indexed access below (stale or malformed map data).
	# _build_nav already nulled mismatched arrays, so these count as
	# absent (off-road default) — same as before.
	var map_cells := _map_w * _map_h
	var terr_ok := terrain.size() == map_cells
	var lvl_ok := levels.size() == map_cells
	# HTML Stage 1 tie-breaker: penalize deviation from the start->goal line.
	var dx1 := float(sc.x - gc.x)
	var dy1 := float(sc.y - gc.y)
	var gx := float(gc.x)
	var gy := float(gc.y)
	# Binary heap of [f, key].
	var heap: Array = []
	# R16: dense per-search arrays replace the g_score/came_from/closed
	# Dictionaries (2.4-3.5x cheaper per op in the hot loop; values are
	# bit-identical — floats stay doubles in a plain Array).
	var cells_n := _map_w * _map_h
	var g_score := []
	g_score.resize(cells_n)
	g_score.fill(INF)
	g_score[start_k] = 0.0
	var came_from := PackedInt32Array()
	came_from.resize(cells_n)
	came_from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(cells_n)  # zero-filled: nothing visited yet
	var best_k := start_k
	var best_h := INF
	var expansions := 0
	var last_improve := 0
	# Inlined _heur for the start cell.
	var _sfx := float(sc.x)
	var _sfy := float(sc.y)
	_heap_push(heap, (absf(_sfx - gx) + absf(_sfy - gy)) * HEUR_MULT \
			+ absf((_sfx - gx) * dy1 - (_sfy - gy) * dx1) * TIE_BREAK, start_k)
	var DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
			Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1),
			Vector2i(-1, 1), Vector2i(-1, -1)]
	# R16: call-free hot loop. _key/_step_cost/_heur are inlined below with
	# IDENTICAL math (same operations, same order — HTML cost parity
	# preserved); the nav Dictionaries are dense byte grids now. Locals
	# hoist member/array access out of the per-expansion path.
	# (2026-10-10 road wear: road_step_cost() is the one static call here —
	# pure, identical math, pinned by tests/test_road_wear.gd.)
	var mw := _map_w
	var mh := _map_h
	var blk := _nav_blocked
	var rod := _nav_road
	var wea := _nav_road_wear
	var brg := _nav_bridge
	var rgh := _nav_rough
	var wkz := _nav_workzone
	var terr := terrain
	var lvls := levels
	var gs := g_score
	var cf := came_from
	var cl := closed
	while not heap.is_empty() and expansions < MAX_EXPANSIONS:
		var top: Array = _heap_pop(heap)
		var ck: int = top[1]
		if cl[ck] == 1:
			continue
		cl[ck] = 1
		expansions += 1
		var cx := ck % mw
		var cy := ck / mw
		# Inlined _heur.
		var fcx := float(cx)
		var fcy := float(cy)
		var ch := (absf(fcx - gx) + absf(fcy - gy)) * HEUR_MULT \
				+ absf((fcx - gx) * dy1 - (fcy - gy) * dx1) * TIE_BREAK
		if ch < best_h:
			best_h = ch
			best_k = ck
			last_improve = expansions
		if ck == goal_k:
			best_k = ck
			break
		# Jeremy 2026-10-04 perf (round 9): stagnation bailout. If A*
		# hasn't gotten closer to the goal in 400 expansions (after an
		# initial 400-expansion grace), the goal is effectively
		# unreachable — bail and return the best-effort partial instead
		# of burning all MAX_EXPANSIONS (~120-260 ms). Reachable goals
		# converge steadily with the weighted heuristic; 400 stagnant
		# expansions means we're flooding a disconnected region.
		if expansions > 400 and expansions - last_improve > 400:
			break
		var g: float = gs[ck]
		var cbase := cy * mw
		for d in DIRS:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= mw or ny >= mh:
				continue
			var nk := ny * mw + nx
			if cl[nk] == 1:
				continue
			var diagonal: bool = d.x != 0 and d.y != 0
			if diagonal:
				# No corner-cutting through blocked cells.
				if blk[cbase + cx + d.x] == 1 \
						or blk[(cy + d.y) * mw + cx] == 1:
					continue
			# Inlined _step_cost: identical HTML-parity cost math, only
			# the lookups changed (byte grids instead of Dictionaries).
			var step: float
			if nk != start_k and nk != goal_k and blk[nk] == 1:
				continue
			# Jeremy 2026-10-05: land avoiders treat water as impassable
			# (start/goal cells stay enterable so a unit can path OUT of
			# water and still arrive at a waterside goal).
			if avoid_water and terr_ok and nk != start_k and nk != goal_k:
				var tiw: int = terr[nk]
				if tiw == MapGen.TILE_WATER or tiw == MapGen.TILE_RIVER \
						or tiw == MapGen.TILE_WATERFALL:
					continue
			var rd := rod[nk]
			if wkz[nk] == 1:
				# Jeremy 2026-10-10 visible road construction: segments
				# under construction are closed — costly enough to route
				# around, never hard-blocked (a goal inside still reaches).
				step = COST_WORKZONE * (DIAG_MULT if diagonal else 1.0)
			elif rd != 0:
				# Jeremy 2026-10-10 road wear: a worn road loses its
				# engineered cheapness — cost scales back toward off-road
				# so routes stop preferring crumbled segments.
				var base := COST_STONE_ROAD if rd == 2 else COST_DIRT_ROAD
				step = road_step_cost(base, float(wea[nk]) / 255.0) \
						* (DIAG_MULT if diagonal else 1.0)
			elif brg[nk] == 1:
				step = COST_BRIDGE * (DIAG_MULT if diagonal else 1.0)
			else:
				var ti: int = terr[nk] if terr_ok else 0
				if ti == MapGen.TILE_WATER or ti == MapGen.TILE_RIVER \
						or ti == MapGen.TILE_WATERFALL:
					step = COST_SWIM * (DIAG_MULT if diagonal else 1.0)
				else:
					var cost := COST_OFFROAD
					if lvl_ok:
						var dl: int = int(lvls[nk]) - int(lvls[cbase + cx])
						if dl > 1 or dl < -1:
							continue
						if dl == 1:
							cost += COST_UPHILL
					if rgh[nk] == 1:
						cost = COST_ROUGH + (cost - COST_OFFROAD \
								if cost > COST_OFFROAD else 0.0)
					if diagonal:
						cost *= DIAG_MULT
					step = cost
			var ng := g + step
			if ng < gs[nk]:
				gs[nk] = ng
				cf[nk] = ck
				# Inlined _heur for the pushed f value.
				var fnx := float(nx)
				var fny := float(ny)
				_heap_push(heap, ng + (absf(fnx - gx) + absf(fny - gy)) \
						* HEUR_MULT + absf((fnx - gx) * dy1 \
						- (fny - gy) * dx1) * TIE_BREAK, nk)
	# Reconstruct (best-effort: closest cell if goal unreachable).
	var cells: Array[Vector2i] = []
	var cur := best_k
	var guard := 8000
	while guard > 0:
		guard -= 1
		cells.append(Vector2i(cur % mw, cur / mw))
		if cur == start_k:
			break
		var prev := cf[cur]
		if prev < 0:
			break
		cur = prev
	cells.reverse()
	if cells.size() < 2:
		return {}
	var wps := _smooth_cells(cells, start_k, goal_k, to, avoid_water)
	return {"wps": wps, "gx": to.x, "gy": to.y, "grid_t": _nav_t}


func _heap_push(heap: Array, f: float, k: int) -> void:
	heap.append([f, k])
	var c := heap.size() - 1
	while c > 0:
		var p := (c - 1) >> 1
		if float(heap[p][0]) <= float(heap[c][0]):
			break
		var t: Array = heap[p]
		heap[p] = heap[c]
		heap[c] = t
		c = p


func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var p := 0
		while true:
			var l := p * 2 + 1
			var r := l + 1
			var m := p
			if l < heap.size() and float(heap[l][0]) < float(heap[m][0]):
				m = l
			if r < heap.size() and float(heap[r][0]) < float(heap[m][0]):
				m = r
			if m == p:
				break
			var t: Array = heap[p]
			heap[p] = heap[m]
			heap[m] = t
			p = m
	return top


## String-pulling: greedy line-of-sight shortcutting (HTML smoothRouteCells).
func _smooth_cells(cells: Array[Vector2i], start_k: int, goal_k: int,
		final_to: Vector2, avoid_water: bool = false) -> PackedVector2Array:
	var n := cells.size()
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		pts[i] = _world_of(cells[i].x, cells[i].y)
	var out := PackedVector2Array([pts[0]])
	var i := 0
	while i < n - 1:
		var j := mini(n - 1, i + 48)
		while j > i + 1 \
				and not _seg_clear(pts[i], pts[j], start_k, goal_k,
					avoid_water):
			j -= 1
		out.append(pts[j] if j < n - 1 else final_to)
		i = j
	# Always end exactly on the target.
	if out.is_empty() or out[out.size() - 1].distance_to(final_to) > 1.0:
		out.append(final_to)
	return out


## Line-of-sight between two world points (blocked cells only — plus
## water cells when the route must avoid water).
func _seg_clear(a: Vector2, b: Vector2, start_k: int, goal_k: int,
		avoid_water: bool = false) -> bool:
	var d := a.distance_to(b)
	var steps := maxi(1, int(d / 16.0))
	for s in range(1, steps):
		var t := float(s) / float(steps)
		var p := a.lerp(b, t)
		var c := _cell_of(p)
		var k := _key(c.x, c.y)
		if k == start_k or k == goal_k:
			continue
		if _nav_blocked[k] == 1:
			return false
		if avoid_water and _pf_terr.size() == _map_w * _map_h:
			var ti: int = _pf_terr[k]
			if ti == MapGen.TILE_WATER or ti == MapGen.TILE_RIVER \
					or ti == MapGen.TILE_WATERFALL:
				return false
	return true


## Is the unit's cached route still valid for this target?
func _route_valid(unit: Dictionary, target: Vector2) -> bool:
	var r: Dictionary = unit.get("_pf_route", {})
	if r.is_empty():
		return false
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	if wps.is_empty():
		return false
	if int(r.get("grid_t", -1)) != _nav_t:
		return false
	var gx := float(r.get("gx", 0.0))
	var gy := float(r.get("gy", 0.0))
	# Perf R18: squared comparison — no Vector2 alloc, no sqrt.
	var gdx := gx - target.x
	var gdy := gy - target.y
	if gdx * gdx + gdy * gdy > GOAL_MOVED_REPATH_SQ:
		return false
	if int(r.get("idx", 0)) >= wps.size():
		return false
	return true


## Per-frame budget reset (HTML pumpRouteQueue parity): lazily fires on the
## first route request of each process frame, then drains the queue.
func _frame_reset_if_needed() -> void:
	if unlimited_budget:
		return
	var f := Engine.get_process_frames()
	if f != _budget_frame:
		_budget_frame = f
		_route_ms_this_tick = 0.0
		_drain_queue()


## Drain queued route requests while the ms budget remains (HTML
## pumpRouteQueue parity: at most ROUTE_MS_PER_TICK of A* per tick).
func _drain_queue() -> void:
	while not _route_queue.is_empty() \
			and (unlimited_budget or _route_ms_this_tick < ROUTE_MS_PER_TICK):
		var q: Dictionary = _route_queue.pop_front()
		var u: Dictionary = q["unit"]
		var t: Vector2 = q["target"]
		if u.is_empty() or not bool(u.get("alive", true)):
			continue
		if _route_valid(u, t):
			continue
		var r := _compute_route(u, t, true)
		if not r.is_empty():
			r["idx"] = 0
			u["_pf_route"] = r


## Get (or compute, budget permitting) the unit's route to target.
## Returns the route dict, or {} when over budget / no path.
func request_route(unit: Dictionary, target: Vector2) -> Dictionary:
	if _route_valid(unit, target):
		return unit["_pf_route"]
	var r: Dictionary = unit.get("_pf_route", {})
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	# HTML _astarPathHop parity: a moved goal always re-projects; otherwise
	# the cached route survives — even across a nav-grid rebuild — when its
	# remainder is still clear, re-stamped to the new grid version.
	var gdx := float(r.get("gx", 0.0)) - target.x
	var gdy := float(r.get("gy", 0.0)) - target.y
	var goal_ok := not r.is_empty() and not wps.is_empty() \
		and int(r.get("idx", 0)) < wps.size() \
		and gdx * gdx + gdy * gdy <= GOAL_MOVED_REPATH * GOAL_MOVED_REPATH
	if goal_ok and _remainder_clear(unit, r):
		r["grid_t"] = _nav_t  # re-stamp: still valid on the new grid
		unit["_pf_route"] = r
		return r
	unit["_pf_route"] = {}
	# Failed-projection cooldown (HTML _repathCd philosophy): a unit whose
	# last projection found no path steers direct for a bit instead of
	# burning a full A* every AI tick. Movement fallback is identical.
	if float(unit.get("_pf_nopath_cd", 0.0)) > float(_gs.game_time):
		return {}
	_frame_reset_if_needed()
	var fresh := _compute_route(unit, target, false)
	if fresh.is_empty():
		return {}
	fresh["idx"] = 0
	unit["_pf_route"] = fresh
	return fresh


## Shared-destination route cache (HTML _routeCache parity): a squad
## marching on one point computes once. Keyed by quantized start cell
## (192px regions) + exact dest cell + boat flag; entries are only valid
## for the nav grid they were computed against (stale entries are dropped).
func _route_cache_key(from: Vector2, to: Vector2, is_boat: bool,
		avoid_water: bool = false) -> int:
	var a := _cell_of(from)
	var b := _cell_of(to)
	var q := (a.x / 6) * 1024 + (a.y / 6)
	var d := b.y * _map_w + b.x
	return ((q * 1048576 + d) * 2 + (1 if is_boat else 0)) * 2 \
		+ (1 if avoid_water else 0)


## Fresh projection with shared-cache lookup. Records the failure cooldown
## on the unit when no path exists.
## HTML computeProjectedRoute parity: the ms budget gates A* projection
## only — shared-cache hits above are free. from_queue=true (queue drain)
## skips the gate; a caller over budget queues the request and steers
## direct meanwhile ({} return).
func _compute_route(unit: Dictionary, target: Vector2,
		from_queue: bool = false) -> Dictionary:
	_ensure_nav()  # key derivation needs valid _map_w/_tile
	var from: Vector2 = unit.get("position", Vector2.ZERO)
	# HTML isBoat flag: boat jobs route on water, land units don't.
	var is_boat := SimBuildings.BOAT_JOBS.has(String(unit.get("job", "")))
	# Jeremy 2026-10-05: land NPCs route around water (fleeing units may
	# swim through — their panic target is what matters).
	var avoid_water := WaterNav.unit_avoids_water(unit)
	var ck := _route_cache_key(from, target, is_boat, avoid_water)
	var hit: Dictionary = _route_cache.get(ck, {})
	if not hit.is_empty():
		if int(hit.get("grid_t", -1)) == _nav_t:
			var hwps: PackedVector2Array = hit.get("wps", PackedVector2Array())
			if not hwps.is_empty():
				return {"wps": hwps.duplicate(), "gx": target.x,
						"gy": target.y, "grid_t": _nav_t}
		else:
			_route_cache.erase(ck)  # stale grid — drop, recompute (HTML)
	if not from_queue and not unlimited_budget \
			and _route_ms_this_tick >= ROUTE_MS_PER_TICK:
		# Over budget: queue for a later tick; the caller steers direct
		# meanwhile (HTML computeProjectedRoute parity).
		_queue_request(unit, target)
		return {}
	var t0 := Time.get_ticks_usec()
	var fresh := find_route(from, target, avoid_water)
	if not unlimited_budget:
		_route_ms_this_tick += float(Time.get_ticks_usec() - t0) / 1000.0
	if fresh.is_empty():
		unit["_pf_nopath_cd"] = float(_gs.game_time) + NOPATH_RETRY_CD
		return {}
	var fwps: PackedVector2Array = fresh.get("wps", PackedVector2Array())
	# HTML parity: only cache routes that actually reach the destination —
	# a truncated (expansion-capped) route is a valid partial path, but
	# caching it would hand other units a route that stops short.
	if not fwps.is_empty():
		var lw: Vector2 = fwps[fwps.size() - 1]
		var rdx := lw.x - target.x
		var rdy := lw.y - target.y
		if rdx * rdx + rdy * rdy < ROUTE_CACHE_REACH * ROUTE_CACHE_REACH:
			# Duplicate: the cache owns its copy. The returned `fresh`
			# dict (and the unit route built from it) must never alias
			# this array — an in-place append/resize by any caller would
			# otherwise corrupt the shared entry for every other unit.
			_route_cache[ck] = {"wps": fwps.duplicate(), "grid_t": _nav_t}
			if _route_cache.size() > ROUTE_CACHE_MAX:
				_route_cache.erase(_route_cache.keys()[0])
	return fresh


func _queue_request(unit: Dictionary, target: Vector2) -> void:
	var uid := int(unit.get("id", 0))
	for q in _route_queue:
		if int((q["unit"] as Dictionary).get("id", 0)) == uid:
			q["target"] = target
			return
	_route_queue.append({"unit": unit, "target": target})


## HTML routeRemainderClear parity: is the rest of the route still walkable?
## Checks each remaining waypoint cell AND the legs between them (sampled
## every 14px, skipping the first 24px of the first leg so a unit being
## pushed out of a wall doesn't instantly thrash).
func _remainder_clear(unit: Dictionary, r: Dictionary) -> bool:
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	var idx := int(r.get("idx", 0))
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	var px := pos.x
	var py := pos.y
	for k in range(idx, wps.size()):
		var w: Vector2 = wps[k]
		var c := _cell_of(w)
		if _nav_blocked[_key(c.x, c.y)] == 1:
			return false
		var dx := w.x - px
		var dy := w.y - py
		var d := sqrt(dx * dx + dy * dy)
		var n := maxi(1, int(ceil(d / 14.0)))
		for s in range(1, n + 1):
			var t := float(s) / float(n)
			if t * d < 24.0 and k == idx:
				continue
			var sc := _cell_of(Vector2(px + dx * t, py + dy * t))
			if _nav_blocked[_key(sc.x, sc.y)] == 1:
				return false
		px = w.x
		py = w.y
	return true


## The cached route for visualization (Selection overlay). {} when none.
func get_route(unit: Dictionary) -> Dictionary:
	var r: Dictionary = unit.get("_pf_route", {})
	if r.is_empty():
		return {}
	var wps: PackedVector2Array = r.get("wps", PackedVector2Array())
	if wps.is_empty() or int(r.get("idx", 0)) >= wps.size():
		return {}
	return r


## Is this world position on a road cell? (speed bonus + visuals)
func is_on_road(pos: Vector2) -> bool:
	if _nav_map_key == "":
		return false
	return _nav_road[_key(_cell_of(pos).x, _cell_of(pos).y)] != 0


## High-level movement: route for long hauls, steer direct when close.
## Returns true on arrival. Handles repath, stuck recovery, easing.
func move_routed(unit: Dictionary, target: Vector2, speed: float,
		delta: float) -> bool:
	# Freshness for the hoisted cliff arrays used by _steer: map_data is
	# replaced (never mutated) on new game/load, so a reference check is
	# enough — far cheaper than _ensure_nav()'s early-out (~1.2us).
	if not is_same(_pf_map_ref, _gs.map_data):
		_ensure_nav()
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	var dist := pos.distance_to(target)
	if dist <= ARRIVE_DIST:
		unit.erase("_pf_route")
		unit["_pf_stuck_t"] = 0.0
		# R35: hoisted water check (see _steer).
		unit["swimming"] = _pf_has_water and WaterNav.is_water_at_fast(
			_pf_wterr, _pf_wsx, _pf_wsy, _pf_wtile, pos)
		return true
	if dist < ROUTE_DIRECT_DIST:
		unit.erase("_pf_route")
		_tick_stuck(unit, pos, delta, false)
		_steer(unit, target, _eased_speed(speed, dist), delta)
		return false
	# Perf R18: route-validity stagger. A full request_route validity
	# check runs when (physics_frame + unit_id) % VALIDITY_STAGGER == 0 —
	# evenly spread across frames and units (Jeremy 2026-10-05: "evenly
	# distribute the cycles"). Between checks the stored route is reused
	# after a cheap target-change test. Steering, waypoint advance, the
	# blocked-cell safety check, stuck detection, and arrival stay
	# per-tick, so movement is identical — only re-validation of an
	# already-good route is deferred. A target change always forces a
	# full check, so chasers (moving goals) and re-tasked workers never
	# ride a stale route.
	var r: Dictionary
	var goal_same := unit.has("_pf_tgoal") \
		and (unit["_pf_tgoal"] as Vector2) == target
	var phase := (Engine.get_physics_frames() \
		+ absi(int(unit.get("id", 0)))) % VALIDITY_STAGGER
	if phase == 0 or not goal_same:
		r = request_route(unit, target)
		unit["_pf_tgoal"] = target
	else:
		r = unit.get("_pf_route", {})
	# Waypoint-repath loop (bounded): a waypoint built over mid-route
	# invalidates and re-projects. Was unbounded self-recursion — a nav
	# grid that keeps yielding a route whose next waypoint is blocked
	# would overflow the call stack.
	for _attempt in 3:
		if r.is_empty():
			# Over budget or no path: steer direct meanwhile (HTML fallback).
			_tick_stuck(unit, pos, delta, true)
			_steer(unit, target, _eased_speed(speed, dist), delta)
			return false
		var wps: PackedVector2Array = r["wps"]
		var idx := int(r["idx"])
		# Advance past reached waypoints (squared: no sqrt per waypoint).
		while idx < wps.size() \
				and pos.distance_squared_to(wps[idx]) < WAYPOINT_ADVANCE_SQ:
			idx += 1
		if idx >= wps.size():
			unit.erase("_pf_route")
			_tick_stuck(unit, pos, delta, false)
			_steer(unit, target, _eased_speed(speed, dist), delta)
			return pos.distance_to(target) <= ARRIVE_DIST
		r["idx"] = idx
		# NOTE: request_route already stored the route on the unit in
		# every path — no redundant re-store here (was 1 dict set per
		# routed unit per tick).
		var wp: Vector2 = wps[idx]
		# Waypoint built over mid-route: invalidate and re-project.
		var wc := _cell_of(wp)
		var wk := _key(wc.x, wc.y)
		var sk := _key(_cell_of(pos).x, _cell_of(pos).y)
		if _nav_blocked.has(wk) and wk != sk:
			unit.erase("_pf_route")
			r = request_route(unit, target)
			unit["_pf_tgoal"] = target
			continue
		_tick_stuck(unit, pos, delta, true)
		_steer(unit, wp, _road_speed(unit, pos, speed), delta)
		return false
	# Repath attempts exhausted: steer direct this tick (HTML fallback).
	_tick_stuck(unit, pos, delta, true)
	_steer(unit, target, _eased_speed(speed, dist), delta)
	return false


## Arrival easing: smooth deceleration into the target (no snapping).
func _eased_speed(speed: float, dist: float) -> float:
	if dist >= EASE_DIST:
		return speed
	var t := clampf(dist / EASE_DIST, 0.0, 1.0)
	return speed * (0.35 + 0.65 * t)


## Roads are engineered: units travel faster on them.
## (Perf R18: the old unit["_pf_on_road"] write was dead — nothing read it.)
func _road_speed(_unit: Dictionary, pos: Vector2, speed: float) -> float:
	if is_on_road(pos):
		return speed * ROAD_SPEED_MULT
	return speed


## Direct steering with cliff slide (the old move_unit core).
## Work-zone deflection for short direct steers (Jeremy 2026-10-10 visible
## road construction): long routes avoid closures via the A* workzone cost;
## this slides short hops around them. Skipped near the goal so arrivals
## still land, and free when no zones are live.
func _workzone_dir(pos: Vector2, dir: Vector2, dist: float,
		unit: Dictionary) -> Vector2:
	if _roads_host == null or dist <= 80.0:
		return dir
	return _roads_host.deflect_around_workzones(pos, dir, unit)


func _steer(unit: Dictionary, target: Vector2, speed: float,
		delta: float) -> void:
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	var to: Vector2 = target - pos
	var dist := to.length()
	if dist < 0.001:
		return
	var step: float = minf(speed * delta, dist)
	# Hot path: hoisted cliff arrays (zero dict gets) — identical result
	# to Cliffs.try_step(_gs.map_data, ...); _ensure_nav ran in
	# move_routed so the arrays are fresh.
	var stepped: Vector2 = Cliffs.try_step_fast(_pf_levels, _pf_sx, _pf_sy,
			_pf_tile, pos, _workzone_dir(pos, to / dist, dist, unit) * step)
	# Jeremy 2026-10-05: shoreline safety net — smoothed waypoints can cut
	# a corner into water; slide along the shore instead.
	# R35: _pf_has_water gates the shoreline safety net (one bool read —
	# dry maps skip unit_avoids_water + the water lookup entirely);
	# is_water_at_fast is the zero-dict-get form of is_water_at.
	# Identical results: no water on the map => is_water_at was false
	# everywhere anyway.
	if _pf_has_water and WaterNav.unit_avoids_water(unit) \
			and WaterNav.is_water_at_fast(_pf_wterr, _pf_wsx, _pf_wsy,
				_pf_wtile, stepped):
		stepped = WaterNav.dry_step(_gs.map_data, pos, stepped - pos)
	unit["position"] = stepped
	unit["moving"] = true
	unit["swimming"] = _pf_has_water and WaterNav.is_water_at_fast(
		_pf_wterr, _pf_wsx, _pf_wsy, _pf_wtile, stepped)


## Stuck detection: no progress for STUCK_TIME -> repath; repeated
## failures -> nudge to the nearest free cell (HTML CANDIDATE30 parity).
func _tick_stuck(unit: Dictionary, pos: Vector2, delta: float,
		en_route: bool) -> void:
	if not en_route:
		unit["_pf_stuck_t"] = 0.0
		unit["_pf_repaths"] = 0
		return
	var last := Vector2(-99999.0, -99999.0)
	if unit.has("_pf_last_pos"):
		last = unit["_pf_last_pos"]
	if last.x < -99998.0:
		unit["_pf_last_pos"] = pos
		unit["_pf_stuck_t"] = 0.0
		return
	if pos.distance_to(last) < STUCK_MIN_MOVE:
		unit["_pf_stuck_t"] = float(unit.get("_pf_stuck_t", 0.0)) + delta
	else:
		unit["_pf_stuck_t"] = 0.0
		unit["_pf_repaths"] = 0
	unit["_pf_last_pos"] = pos
	if float(unit.get("_pf_stuck_t", 0.0)) < STUCK_TIME:
		return
	unit["_pf_stuck_t"] = 0.0
	var reps := int(unit.get("_pf_repaths", 0)) + 1
	unit["_pf_repaths"] = reps
	unit.erase("_pf_route")  # force a fresh projection next call
	if reps > STUCK_MAX_REPATHS:
		unit["_pf_repaths"] = 0
		var free := nearest_free_cell(pos, 6)
		if free != Vector2(-1, -1):
			unit["position"] = free
			unit["_pf_last_pos"] = free


## Spiral search for the nearest unblocked cell center.
func nearest_free_cell(pos: Vector2, max_rings: int) -> Vector2:
	_ensure_nav()
	if _map_w <= 0:
		return Vector2(-1, -1)
	var c := _cell_of(pos)
	for ring in range(max_rings + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var tx := c.x + dx
				var ty := c.y + dy
				if tx < 0 or ty < 0 or tx >= _map_w or ty >= _map_h:
					continue
				if _nav_blocked[_key(tx, ty)] != 1:
					return _world_of(tx, ty)
	return Vector2(-1, -1)


## Static helper for combat.gd / adventure.gd walk_to integration.
## Routes long hauls through the pathfinder; short hops steer direct.
static func walk_to(gs, unit: Dictionary, target: Vector2,
		speed: float, delta: float) -> bool:
	var pf = gs.get("pathfinder")
	var before: Vector2 = unit.get("position", Vector2.ZERO)
	var arrived: bool
	if pf == null:
		arrived = _direct_walk(gs, unit, target, speed, delta)
	else:
		arrived = (pf as SimPathfinder).move_routed(unit, target, speed, delta)
	# Jeremy 2026-10-10 road wear: traffic degrades roads underfoot —
	# armies and adventurers grind roads down just like workers do.
	var after: Vector2 = unit.get("position", Vector2.ZERO)
	if after != before and not bool(unit.get("swimming", false)):
		var wai = gs.get("worker_ai")
		if wai != null:
			(wai as WorkerAI).wear_road_at(after,
				WorkerAI.WEAR_PER_SEC * delta)
	return arrived


static func _direct_walk(gs, unit: Dictionary, target: Vector2,
		speed: float, delta: float) -> bool:
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	var to: Vector2 = target - pos
	var dist := to.length()
	if dist < ARRIVE_DIST:
		return true
	var step: float = minf(speed * delta, dist)
	unit["position"] = Cliffs.try_step(gs.map_data, pos, to / dist * step)
	unit["moving"] = true
	return false
