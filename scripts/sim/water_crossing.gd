class_name SimWaterCrossing
extends RefCounted
## Cursing Gnomes — AI water-crossing (HTML waterxAITick parity).
##
## Ports the HTML's per-race water-crossing AI (build-staging/fix79/index.html,
## `waterxAITick` + the WATERX module). When an AI faction is at war and the
## straight line from its hall to the nearest hostile hall crosses water,
## the AI engineers a bridge over the strait. Verbatim HTML numbers:
##   - span < 160px: no real crossing — walk or swim it, skip
##   - span <= 900px: bridge it — extend the water run 70px past each shore,
##     one segment per 30px, quiet per-segment placement
##     (canPlaceBridge + spend, no player-facing spam on failure)
##   - > 2 segments placed: bridge project starts
##     ("<Race> engineers are bridging the strait."); otherwise the project
##     fails and the race cools down 180s
##   - an in-progress project clears when a completed bridge of that race
##     stands within 240px of the run midpoint, or goes stale after 300s
##   - span > 900px: ferry the assault — a free boat (alive, same race,
##     boat job, no ferry state) boards nearby troops and sails for the
##     nearest water to the enemy hall (SimFerry, scripts/sim/ferry.gd;
##     HTML waterxOrderFerry + the waterxAITick ferry branch)
##
## Tick cadence: HTML runs waterxAITick round-robin, one race per aiThink
## third (~1.1s per race). Here: a 1.0s accumulator, one AI faction per tick.
## The player's faction never bridges (playerRace is skipped in HTML).
##
## Placement reuses the player bridge tooling: BridgeDrag.plan_path /
## can_place_bridge (HTML canPlaceBridge parity: 70px map margin, water
## within 80px, no stacking within 26px, no building overlap) and
## SimBuildings.place_blueprint for the spend + incomplete-blueprint
## records, so AI bridges stage and get built by workers exactly like
## player bridges (waterxBridgeDone parity: complete + race + 240px).
##
## Pure logic — no rendering, no input, no audio. World owns one instance
## (see WIRING), ticked in _physics_process. Project state is transient:
## HTML's _waterxProj is also unsaved — a reload just restarts cooldowns.
##
## WIRING (world.gd — owned by the world agent):
##   var waterx: SimWaterCrossing          # null until configure()
##   configure(): waterx = SimWaterCrossing.new(game, buildings_sys)
##   _physics_process(): if waterx != null: waterx.tick(delta)


## Span rules (HTML WATERX verbatim, px).
const SPAN_MIN := 160.0        # shorter: no real crossing, skip
const SPAN_BRIDGE_MAX := 900.0 # longer: ferry instead of bridge (queued)
const SPAN_SAMPLE_PX := 40.0   # waterxSpan samples the line every 40px
const EXTEND_PX := 70.0        # bridge run extends 70px past each shore
const MIN_PLACED := 2          # waterxAIStartBridge: >2 segments = project
const FAIL_COOLDOWN := 180.0   # failed project: cool down (game seconds)
const STALE_AFTER := 300.0     # in-progress project goes stale (game seconds)
const DONE_RADIUS := 240.0     # waterxBridgeDone: completed bridge near midpoint
const TICK_INTERVAL := 1.0     # one AI faction per second (HTML ~1.1s/race)

## Hall types the crossing AI treats as a faction's town center (HTML checks
## 'hall'; Godot also aliases 'town_hall'/'townhall' — see CAP_EXEMPT).
const HALL_TYPES := ["hall", "town_hall", "townhall"]

## Near-water radius for bridge placement (HTML nearWaterAt(x, y, 80)).
const PLACE_WATER_RADIUS := 80.0


var _gs: GameState
var _bs  # SimBuildings — place_blueprint for AI bridge segments
var _ferry  # SimFerry — ferry-assault branch (null when unwired)
var _drag := BridgeDrag.new()  # commit() carries the run_id sequence
var _projs := {}  # faction -> {x1,y1,x2,y2,started} | {failed:true,started}
var _order: Array = []  # round-robin AI faction order
var _cursor := 0
var _acc := 0.0


func _init(game_state: GameState, buildings_sys, ferry = null) -> void:
	_gs = game_state
	_bs = buildings_sys
	_ferry = ferry


## One AI faction per TICK_INTERVAL (HTML: round-robin, one race per tick).
func tick(delta: float) -> void:
	_acc += delta
	if _acc < TICK_INTERVAL:
		return
	_acc = 0.0
	if _order.is_empty():
		_build_order()
	if _order.is_empty():
		return
	_cursor = _cursor % _order.size()
	var f: String = String(_order[_cursor])
	_cursor += 1
	tick_faction(f)


func _build_order() -> void:
	_order.clear()
	_cursor = 0
	var active: Array = []
	if _gs != null and _gs.get("active_factions") != null:
		active = _gs.active_factions
	if active.is_empty():
		for f: String in Config.FACTIONS.keys():
			active.append(f)
	var player: String = String(_gs.player_faction) if _gs != null else ""
	for f: String in active:
		if f != player:
			_order.append(f)


## The per-race waterxAITick (bridge path). Public for tests.
func tick_faction(f: String) -> void:
	if _gs == null or f == "" or f == String(_gs.player_faction):
		return  # HTML: skip null race and playerRace
	var now: float = float(_gs.game_time)
	var proj: Dictionary = _projs.get(f, {})
	if not proj.is_empty():
		if bool(proj.get("failed", false)):
			if now - float(proj.get("started", 0.0)) < FAIL_COOLDOWN:
				return  # broke/blocked: cool down
			_projs.erase(f)
		elif not bridge_done(f):
			if now - float(proj.get("started", 0.0)) > STALE_AFTER:
				_projs.erase(f)  # stale: workers never finished it
			return
		else:
			_projs.erase(f)  # bridge finished
	var hall: Dictionary = _hall_of(f)
	if hall.is_empty():
		return
	var foe_hall: Dictionary = _nearest_hostile_hall(
		f, hall.get("position", Vector2.ZERO))
	if foe_hall.is_empty():
		return
	var span: Dictionary = water_span(hall.get("position", Vector2.ZERO),
		foe_hall.get("position", Vector2.ZERO))
	if span.is_empty():
		return
	if float(span.get("len", 0.0)) < SPAN_MIN:
		return  # no real crossing — walk or swim it
	if float(span.get("len", 0.0)) <= SPAN_BRIDGE_MAX:
		start_bridge(f, span)
		return
	# Span > 900px: ferry the assault (HTML waterxAITick ferry branch).
	if _ferry != null:
		_ferry_assault(f, foe_hall)


## The waterxAITick ferry branch for long crossings: a free boat (alive,
## same faction, boat job, no ferry state) sails troops at the nearest
## water to the enemy hall. Public for tests.
func _ferry_assault(f: String, foe_hall: Dictionary) -> bool:
	var boat := {}
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != f:
			continue
		if not _ferry.is_boat(u):
			continue
		if String(u.get("ferry_state", "")) != "":
			continue
		boat = u
		break
	if boat.is_empty():
		return false
	var eh: Vector2 = foe_hall.get("position", Vector2.ZERO)
	var dest = _ferry.nearest_water(eh)
	if dest == null:
		return false
	if _ferry.order_ferry(boat, dest, true):
		# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
		SimGazette.publish_or_emit(_gs, "Ferry assault",
			"%s launches a ferry assault" % _race_name(f), "war")
		return true
	return false


## Longest water run along the straight line a->b (HTML waterxSpan verbatim:
## sample every 40px, keep the longest wet run). Returns
## {x1,y1,x2,y2,len} or {} when the line never touches water.
func water_span(a: Vector2, b: Vector2) -> Dictionary:
	var d: Vector2 = b - a
	var dist: float = d.length()
	if dist < 1.0:
		return {}
	var n: int = maxi(1, int(dist / SPAN_SAMPLE_PX))
	var bs := -1
	var be := -1
	var cs := -1
	for i: int in range(n + 1):
		var wet: bool = _in_water(a + d * (float(i) / float(n)))
		if wet and cs < 0:
			cs = i
		if not wet and cs >= 0:
			if (i - 1) - cs > be - bs:
				bs = cs
				be = i - 1
			cs = -1
	if cs >= 0 and n - cs > be - bs:
		bs = cs
		be = n
	if bs < 0:
		return {}
	var p1: Vector2 = a + d * (float(bs) / float(n))
	var p2: Vector2 = a + d * (float(be) / float(n))
	return {"x1": p1.x, "y1": p1.y, "x2": p2.x, "y2": p2.y,
		"len": float(be - bs) * SPAN_SAMPLE_PX}


## True when a completed bridge of faction f stands near the active
## project's run midpoint (HTML waterxBridgeDone verbatim).
func bridge_done(f: String) -> bool:
	var proj: Dictionary = _projs.get(f, {})
	if proj.is_empty() or bool(proj.get("failed", false)):
		return false
	var mx: float = (float(proj.get("x1", 0.0)) + float(proj.get("x2", 0.0))) * 0.5
	var my: float = (float(proj.get("y1", 0.0)) + float(proj.get("y2", 0.0))) * 0.5
	var mid := Vector2(mx, my)
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("type", "")) != "bridge":
			continue
		if not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != f:
			continue
		if (b.get("position", Vector2.ZERO) as Vector2).distance_to(mid) \
				< DONE_RADIUS:
			return true
	return false


## Starts a bridge project over span (HTML waterxAIStartBridge verbatim):
## extend 70px past each shore, one segment per 30px via the shared bridge
## tooling (quiet per-segment placement). >2 placed -> project + the
## engineers announcement; otherwise failed -> 180s cooldown.
func start_bridge(f: String, span: Dictionary) -> bool:
	var now: float = float(_gs.game_time)
	var a := Vector2(float(span.get("x1", 0.0)), float(span.get("y1", 0.0)))
	var b := Vector2(float(span.get("x2", 0.0)), float(span.get("y2", 0.0)))
	var d: Vector2 = b - a
	var dist: float = d.length()
	if dist < 1.0:
		_projs[f] = {"failed": true, "started": now}
		return false
	var u: Vector2 = d / dist
	var s: Vector2 = a - u * EXTEND_PX
	var e: Vector2 = b + u * EXTEND_PX
	var hall: Dictionary = _hall_of(f)
	var town_id: int = int(hall.get("town_id", 0))
	var plan: Dictionary = BridgeDrag.plan_path(s, e, _gs.buildings,
		_map_rect(), Callable(self, "_near_water_80"))
	var res: Dictionary = _drag.commit(_bs, plan, f, town_id)
	var placed: Array = res.get("placed", [])
	if placed.size() > MIN_PLACED:
		_projs[f] = {"x1": s.x, "y1": s.y, "x2": e.x, "y2": e.y,
			"started": now}
		_announce("%s engineers are bridging the strait." % _race_name(f))
		return true
	_projs[f] = {"failed": true, "started": now}  # broke or blocked: cool down
	return false


## Faction's living town center, or {} (HTML: race's alive 'hall').
func _hall_of(f: String) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not HALL_TYPES.has(String(b.get("type", ""))):
			continue
		if String(b.get("faction", "")) != f:
			continue
		return b
	return {}


## Nearest living hostile hall to from_pos, or {} (HTML: nearest foe hall
## among activeRaces61().filter(isHostile)).
func _nearest_hostile_hall(f: String, from_pos: Vector2) -> Dictionary:
	if _gs.diplomacy == null:
		return {}
	var best := {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not HALL_TYPES.has(String(b.get("type", ""))):
			continue
		var of: String = String(b.get("faction", ""))
		if of == f:
			continue
		if String(_gs.diplomacy.relation_state(f, of)) != "war":
			continue
		var d: float = (b.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(from_pos)
		if d < best_d:
			best_d = d
			best = b
	return best


## Point-in-water probe for span sampling (HTML inWaterAt).
func _in_water(pos: Vector2) -> bool:
	return _water_within(pos, 0.0)


## Water-within-80px probe for bridge placement (HTML nearWaterAt(x, y, 80)
## inside canPlaceBridge).
func _near_water_80(pos: Vector2) -> bool:
	return _water_within(pos, PLACE_WATER_RADIUS)


func _water_within(pos: Vector2, radius_px: float) -> bool:
	var md: Dictionary = _gs.map_data
	if md.is_empty():
		return false
	var terrain: PackedByteArray = md.get("terrain", PackedByteArray())
	if terrain.is_empty():
		return false
	var tpx: float = maxf(1.0, float(md.get("tile_size", 32.0)))
	var rt: int = int(ceil(radius_px / tpx))
	var ctx: int = int(pos.x / tpx)
	var cty: int = int(pos.y / tpx)
	for dy: int in range(-rt, rt + 1):
		for dx: int in range(-rt, rt + 1):
			var tx: int = ctx + dx
			var ty: int = cty + dy
			if tx < 0 or ty < 0 or tx >= MapGen.MAP_TILES \
					or ty >= MapGen.MAP_TILES:
				continue
			if not MapGen.is_water(terrain[ty * MapGen.MAP_TILES + tx]):
				continue
			if radius_px <= 0.0:
				return dx == 0 and dy == 0
			# Tile-center distance must fall inside the radius.
			var cp := Vector2((float(tx) + 0.5) * tpx,
				(float(ty) + 0.5) * tpx)
			if cp.distance_to(pos) <= radius_px:
				return true
	return false


func _map_rect() -> Rect2:
	var ws := Vector2(4096.0, 4096.0)
	var md: Dictionary = _gs.map_data
	if not md.is_empty() and md.has("world_size"):
		ws = md["world_size"]
	return Rect2(Vector2.ZERO, ws)


func _race_name(f: String) -> String:
	var d: Dictionary = Config.FACTIONS.get(f, {})
	return String(d.get("name", f.capitalize()))


## HTML systemMsg parity: one quiet line on project start (failures stay
## silent, per the WATERX "quiet AI bridge segment" rule).
func _announce(body: String) -> void:
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs, "Engineers bridging the strait",
		body, "war")


## Test/debug hook: the active project record for a faction, or {}.
func project_of(f: String) -> Dictionary:
	return (_projs.get(f, {}) as Dictionary).duplicate()
