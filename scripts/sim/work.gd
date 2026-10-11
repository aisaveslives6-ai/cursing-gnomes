class_name WorkerAI
extends RefCounted
## Cursing Gnomes — civilian/service unit work state machine (Milestone 3).
##
## Every civilian or service unit runs this each tick. It is a simple
## sense→act loop over the unit's record (no nodes, no rendering):
##
##   IDLE -> pick a task for the unit's job
##   TO_RESOURCE -> walk to a work site (tree / rock / gold vein)
##   GATHERING   -> fill the carry load, depleting the site
##   TO_DROPOFF  -> walk to the nearest hall, credit the ledger
##   TO_BUILD    -> walk to a blueprint, BUILDING -> raise progress
##   TO_REPAIR / REPAIRING -> fix damaged buildings
##   DOCTOR      -> walk to the most injured ally in range, heal
##   TO_STATION / WORKING -> station jobs (shopkeepers, desk officers):
##       walk to the workplace building, stand at the work spot, work the
##       shift; desk jobs claim a free cubicle desk at shift start and
##       release it after the shift
##   TO_ROAD / ROADWORK -> roadbuilders walk their road order, painting
##       roads under their feet (stone when the faction is stocked)
##
## Runtime fields on the unit record (all optional, backward compatible):
##   work_state: String, work_site: int (-1 none), work_building: int (-1),
##   carrying: {resource: float}, carry_cap: float, speed: float,
##   station: {job, building_id, spot, act}, _desk: {building_id, desk_id},
##   _road_order: Vector2, craft: {thatch, lumber, stone} (homestead),
##   _homestead / _country_move: owned by SimHousing (this AI yields),
##   coins: float (personal wages)
##
## Design ported from the HTML build's gather/haul/build loop, station
## driver (stationTick57), desk-claim system (c71ClaimDesk/c71ReleaseDesk),
## roadbuilder crew, and factionWorkPriority (not its code).
## Pure logic — no rendering, no input, no audio.


const GATHER_RATE := 2.5      # resource units per second while gathering
const CARRY_CAP := 10.0        # per trip
# Jeremy 2026-10-05: felled trees burst into wood pickups (no trickle).
const TREE_WOOD_YIELD := 60.0  # wood per felled tree (== tree site amount)
const PICKUP_WOOD := 10.0      # wood per pickup (== one full carry)
const PICKUP_RADIUS := 40.0    # walk-over collection radius (px)
const BUILD_RANGE := 48.0      # px — close enough to swing a hammer
const GATHER_RANGE := 36.0     # px — close enough to chop/mine
const HEAL_RATE := 12.0        # doctor hp/sec
const HEAL_RANGE := 60.0
const REPAIR_RATE := 25.0      # hp/sec per builder power

## Work shifts (HTML ensureShiftProfile parity — Jeremy 2026-10-02 audit).
## {job: [start_hour, end_hour]}. Firefighters are 24/7.
const SHIFTS := {
	"firefighter": [0.0, 24.0],
	"doctor": [7.0, 19.0],
	"shopkeeper": [8.0, 18.0],
	"cashier": [8.0, 18.0],
	"barkeep": [8.0, 18.0],
	"innkeeper": [8.0, 18.0],
	"military": [6.0, 18.0],  # soldiers/guards/archers/etc.
	"default": [7.5, 16.5],   # workers, builders, farmers, advisers, officers
}


## Current hour of day (0-24) from game time.
static func hour_of_day(game: GameState) -> float:
	var phase: float = fmod(game.game_time, Config.DAY_LENGTH_SECONDS) / Config.DAY_LENGTH_SECONDS
	return phase * 24.0


## Is this job on shift right now? (HTML workBell57 parity)
static func is_on_shift(job: String, hour: float) -> bool:
	var shift: Array = SHIFTS.get(job, SHIFTS["default"])
	if JobDefs.is_military(job):
		shift = SHIFTS["military"]
	var start: float = shift[0]
	var end: float = shift[1]
	if start <= end:
		return hour >= start and hour < end
	return hour >= start or hour < end  # overnight shift

## Work-site kind -> resource it yields.
const SITE_RESOURCE := {
	"tree": "wood",
	"wood_pile": "wood",
	"rock": "oil",
	"gold_vein": "gold",
	"bush": "food",
}


var _gs: GameState


## Spatial index over _gs.work_sites (perf 2026-10-05: _nearest_site was a
## full O(N) scan — ~600 us at 753 sites — fired on every task pick, and
## _tick_ai_budgeted runs 32 units/tick). Sites are append-only (depleted
## in place, never removed, positions write-once), so the grid syncs
## incrementally by array size; a shrink (new game / save load) triggers a
## full rebuild. Queries use expanding rings with an exact stopping rule,
## so results are IDENTICAL to the old linear scan — including the
## lowest-id tie-break the old first-match array order produced.
const SITE_GRID_CELL := 256.0
var _site_grid := {}  # Vector2i cell -> Array[Dictionary] (site record refs)
var _site_grid_n := 0  # _gs.work_sites.size() already indexed
var _site_grid_ver := -1  # _gs.site_cache_version at last sync
var _site_grid_min := Vector2i.ZERO  # bounding box of non-empty cells
var _site_grid_max := Vector2i.ZERO
var _site_nomatch := {}  # kind-signature -> true; "no site matched" cache.
# Only depletion-safe direction is cached: a miss can only become a hit
# when NEW sites appear, and any grid change clears this cache. Depleting
# a site never turns a miss into a hit, so the cache stays correct.

## Pickup spatial index (R33): _collect_pickups ran every working unit,
## every tick, as a full O(pickups) reverse scan (~8.3 ms/frame at 230
## units / 60 pickups). The grid narrows each unit to the 3x3 cells around
## it; the reverse scan then only visits pickups in those cells, in the
## same order — bit-identical collection, including the quirky
## break-when-this-kind-is-full rule. Validated by _gs.pickup_version
## (bumped on add/remove/save-load); a stale cell can only hold a
## REMOVED pickup, whose id never matches the live-array scan.
const PICKUP_GRID_CELL := 128.0  # >> PICKUP_RADIUS (40): 3x3 always covers
var _pickup_grid := {}  # Vector2i cell -> Array[Dictionary] (pickup refs)
var _pickup_grid_ver := -1  # _gs.pickup_version at last sync

## R34 idle retry backoff: an idle unit whose last full _pick_task scan
## found nothing skips re-scanning for IDLE_RETRY_TICKS of its own AI
## ticks. The world rarely changes between two consecutive slices, and the
## full scan (building loops, unit-wide patient scan, site grid queries)
## was the dominant _pick_task cost — e.g. idle doctors re-scanned every
## unit, every tick, at ~275 us a call. Behavior: a newly-appearing task
## (new blueprint, new patient, fresh site) is picked up at most
## IDLE_RETRY_TICKS slices later — well under a second of game time at
## normal AI budgets. Implementation-only: no quality, density, content,
## or mechanics change.
const IDLE_RETRY_TICKS := 20


func _pickup_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / PICKUP_GRID_CELL)),
		int(floor(pos.y / PICKUP_GRID_CELL)))


func _sync_pickup_grid() -> void:
	var ver: int = _gs.pickup_version
	if ver == _pickup_grid_ver:
		return
	_pickup_grid.clear()
	for p: Dictionary in _gs.pickups:
		var c := _pickup_cell(p.get("position", Vector2.ZERO))
		if _pickup_grid.has(c):
			(_pickup_grid[c] as Array).append(p)
		else:
			_pickup_grid[c] = [p]
	_pickup_grid_ver = ver


func _init(game_state: GameState) -> void:
	_gs = game_state


## Painted road records: [{position: Vector2, type: "dirt"|"stone",
## faction: String, wear: float}]. Near-duplicates merge (12 px) instead of
## stacking. wear runs 0.0 (fresh) -> 1.0 (fully worn out): traffic wears
## roads down (Jeremy 2026-10-10 road-wear order); worn roads lose their
## movement bonus and render shabby until a roadbuilder repairs them.
## The renderer reads these to draw the road network (HOOK).
var roads: Array[Dictionary] = []

## Bumped whenever any road record crosses a wear band (fresh / worn /
## shabby / ruined). SimPathfinder and RoadOverlay watch this to refresh
## wear-scaled routing costs and visuals without rescanning the network.
var road_wear_version := 0

## Bumped whenever road work zones change (link planned / claimed / staged /
## finished, repair started / finished). SimPathfinder and RoadOverlay watch
## this to refresh closure routing and work-zone visuals.
var road_work_version := 0
## Cached work-zone list (recomputed at WORK_ZONE_CACHE_TTL cadence).
var _work_zone_cache: Array = []
var _work_zone_cache_t := -100.0
var _work_zone_sig := ""
var _work_zones_dirty := true


## Work-zone state changed: nav + overlay must refresh.
func _bump_work_version() -> void:
	road_work_version += 1
	_work_zones_dirty = true

## O(1) road lookup grid: Vector2i cell (ROAD_CELL) -> Array[int] of road
## indexes. Rebuilt on load, appended incrementally by paint_road. Powers
## wear accrual in the per-unit movement choke point (move_unit).
var _road_grid: Dictionary = {}

## Road painting cadence / reach for the roadbuilder crew.
const ROAD_PAINT_INTERVAL := 0.35
# Jeremy 2026-10-07 ("AI not rebuilding roads"): merge radius was 24 px while
# every painter steps 18-22 px (HTML ROAD_CELL = 22) — dense paints merged
# into ~44 px effective spacing and the 26 px discs rendered as dashed
# fragments. 12 px sits below every paint step, so discs (26 px diameter)
# always overlap into continuous roads, while same-spot repaints still merge.
const ROAD_MERGE_RADIUS := 12.0
const ROAD_ORDER_ARRIVE := 36.0
# HTML ROAD_CELL verbatim (fix79): zone-road paint spacing + crew gap-fill step.
const ROAD_CELL := 22.0
# HTML paintRoad verbatim: hard cap — prevents lag from dense painting.
const ROAD_MAX := 4500
## Jeremy 2026-10-10 road wear: one full game-day (14400 game-seconds) of
## constant foot traffic wears a segment out completely. Real traffic is
## sparse — a unit crosses a 22 px cell in under a second — so busy routes
## need roadbuilder attention every few days while quiet trails effectively
## never wear. Wagons count 4x (heavy loads).
const WEAR_PER_SEC := 1.0 / 14400.0
const WEAR_BANDS := 4
## Roadbuilder maintenance: worn segments at/above this wear get a repair
## order when within search range; the repair channels REPAIR_TIME seconds.
const REPAIR_WEAR_THRESHOLD := 0.5
const REPAIR_SEARCH_RADIUS := 900.0
const REPAIR_TIME := 3.0

## Planned road network links (Jeremy 2026-10-10 direct order: the AI lays
## deliberate building-to-building road networks instead of only incidental
## crew trails). Records: [{id: int, faction: String, a: Vector2,
## b: Vector2, done: bool, day: int}]. The AI director plans links
## (hall<->farm, hall<->lumber, hall<->shop, town<->town); roadbuilder
## crews claim an undone link, walk its waypoint polyline, and paint it
## with the same crew machinery as trails. Finished links stay as dedup
## history; stale undone links are pruned so the plan can refresh.
var road_links: Array = []
var _road_link_next_id := 1
const ROAD_LINK_WP_SPACING := 160.0  # px between link waypoints
const ROAD_LINK_RANGE := 1600.0      # roadbuilder claims links this near
const ROAD_LINK_DEDUP := 80.0        # endpoints within this = same link
const ROAD_LINKS_MAX := 600          # cap; oldest done links pruned first
const ROAD_LINK_STALE_DAYS := 12     # undone links older than this refresh
## Jeremy 2026-10-10 visible road construction: a planned link is a marked
## work zone first — barriers/cones, staged surveyed -> graded -> paved
## progress — and segments under construction are closed to traffic until
## the segment opens. Fantasy-era materials only (dirt/gravel/cobble).
const ROAD_STAGE_SURVEYED := 0  # planned: stakes up, corridor still open
const ROAD_STAGE_GRADING := 1   # crew on site: dirt laid, corridor closed
const ROAD_STAGE_PAVING := 2    # stone over dirt: moving zone at the paver
const ROAD_STAGE_DONE := 3      # complete: open road, barriers cleared
const WORK_ZONE_HALF_WIDTH := 44.0  # closed corridor half-width (px)
const WORK_ZONE_DISC_R := 56.0      # repair / paving work-zone radius (px)
const WORK_ZONE_CACHE_TTL := 1.0    # seconds between zone recomputes


## Wear band of a road record: 0 fresh .. WEAR_BANDS-1 ruined.
static func wear_band(wear: float) -> int:
	return mini(WEAR_BANDS - 1, int(wear * float(WEAR_BANDS)))


func _road_cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / ROAD_CELL)), int(floor(pos.y / ROAD_CELL)))


func _index_road(idx: int) -> void:
	var r: Dictionary = roads[idx]
	var cell := _road_cell_of(r.get("position", Vector2.ZERO))
	if _road_grid.has(cell):
		(_road_grid[cell] as Array).append(idx)
	else:
		_road_grid[cell] = [idx]


func _rebuild_road_grid() -> void:
	_road_grid.clear()
	for i in roads.size():
		_index_road(i)


## Index of the nearest road record within ROAD_MERGE_RADIUS * 1.5 of pos,
## or -1. Cell lookup + 3x3 neighborhood: O(1), safe in the per-tick
## movement choke point.
func road_index_at(pos: Vector2) -> int:
	var c := _road_cell_of(pos)
	var best := -1
	var best_d := ROAD_MERGE_RADIUS * 1.5
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell := Vector2i(c.x + dx, c.y + dy)
			if not _road_grid.has(cell):
				continue
			for idx in (_road_grid[cell] as Array):
				var i: int = idx
				if i < 0 or i >= roads.size():
					continue
				var d: float = (roads[i].get("position", Vector2.ZERO) \
						as Vector2).distance_to(pos)
				if d <= best_d:
					best_d = d
					best = i
	return best


## Adds wear to the road under pos (traffic). Band crossings bump
## road_wear_version so the pathfinder and overlay refresh.
func wear_road_at(pos: Vector2, amount: float) -> void:
	if amount <= 0.0:
		return
	var idx := road_index_at(pos)
	if idx < 0:
		return
	var r: Dictionary = roads[idx]
	var old_band := wear_band(float(r.get("wear", 0.0)))
	r["wear"] = minf(1.0, float(r.get("wear", 0.0)) + amount)
	if wear_band(float(r["wear"])) != old_band:
		road_wear_version += 1


## Paints a road tile under the roadbuilder's feet (dirt by default;
## stone when the faction is stocked: gold >= 30 and wood >= 20 —
## HTML crew's "upgrade to stone when stocked"). force_type overrides the
## auto choice (trade routes paint HTML-verbatim dirt roads).
func paint_road(pos: Vector2, faction: String, force_type := "") -> void:
	# HTML paintRoad verbatim: hard cap — prevents lag from dense painting.
	if roads.size() >= ROAD_MAX:
		return
	var rtype := "dirt"
	if force_type == "dirt" or force_type == "stone":
		rtype = force_type
	elif _gs.resources.get_amount(faction, "gold") >= 30.0 \
			and _gs.resources.get_amount(faction, "wood") >= 20.0:
		rtype = "stone"
	for r: Dictionary in roads:
		if String(r.get("faction", "")) == faction \
				and (r.get("position", Vector2.ZERO) as Vector2).distance_to(pos) \
				<= ROAD_MERGE_RADIUS:
			r["type"] = rtype
			# Jeremy 2026-10-10 visible road construction: repainting never
			# maintains — a worn road needs a real repair work zone (the
			# repair order channel), never an instant paint-over.
			return
	roads.append({"position": pos, "type": rtype, "faction": faction,
		"wear": 0.0})
	_index_road(roads.size() - 1)


## Painted road network persistence (HTML saves data.roads and repaints
## them free on load; the Godot port dropped this, so every load wiped the
## network and zoning rings never repainted — the "roads remain broken"
## half of Jeremy's 2026-10-07 "AI not rebuilding roads" report).
## Positions ride through SaveSystem._encode_value as __vec2.
func to_dict() -> Dictionary:
	var rd: Array = []
	for r: Dictionary in roads:
		rd.append(r.duplicate())
	# Jeremy 2026-10-10 planned road networks: link plans persist with the
	# painted roads (SaveSystem._encode_value turns the Vector2 endpoints
	# into __vec2 markers, same as road positions).
	var lk: Array = []
	for l: Dictionary in road_links:
		lk.append(l.duplicate())
	return {"roads": rd, "road_links": lk,
		"road_link_next_id": _road_link_next_id}


func from_dict(data: Dictionary) -> void:
	roads.clear()
	for r in data.get("roads", []):
		var d := (r as Dictionary).duplicate()
		var p = d.get("position", Vector2.ZERO)
		if p is Array:
			var pa: Array = p
			d["position"] = Vector2(float(pa[0]), float(pa[1]))
		elif not (p is Vector2):
			d["position"] = Vector2.ZERO
		if not d.has("wear"):
			d["wear"] = 0.0  # pre-wear saves
		roads.append(d)
	_rebuild_road_grid()
	road_links.clear()
	_road_link_next_id = 1
	for l in data.get("road_links", []):
		var ld := (l as Dictionary).duplicate()
		ld["a"] = _as_vec2(ld.get("a", Vector2.ZERO))
		ld["b"] = _as_vec2(ld.get("b", Vector2.ZERO))
		if not ld.has("done"):
			ld["done"] = false
		if not ld.has("day"):
			ld["day"] = 0
		# Jeremy 2026-10-10 visible road construction: pre-staging saves.
		if not ld.has("stage"):
			ld["stage"] = ROAD_STAGE_DONE if bool(ld.get("done", false)) \
				else ROAD_STAGE_GRADING
		if not ld.has("front"):
			ld["front"] = 1.0 if bool(ld.get("done", false)) else 0.0
		if not ld.has("pass"):
			ld["pass"] = 0
		ld["from"] = _as_vec2(ld.get("from", ld.get("a", Vector2.ZERO)))
		ld["to"] = _as_vec2(ld.get("to", ld.get("b", Vector2.ZERO)))
		var lid := int(ld.get("id", 0))
		if lid <= 0:
			lid = _road_link_next_id
			ld["id"] = lid
		_road_link_next_id = maxi(_road_link_next_id, lid + 1)
		road_links.append(ld)


## Coerces a saved/foreign position value into a Vector2 (__vec2 markers
## arrive already decoded by SaveSystem._decode_value; old saves and test
## fixtures may carry raw Arrays).
static func _as_vec2(p) -> Vector2:
	if p is Vector2:
		return p
	if p is Array and (p as Array).size() >= 2:
		var pa: Array = p
		return Vector2(float(pa[0]), float(pa[1]))
	return Vector2.ZERO


## Reassigns a unit's job and resets its work state (used by UI / training).
## Stale desk claims die with the job (HTML c71: claims never outlive the
## worker/job) — release_desk needs no GameState, so it runs here.
static func assign_job(unit: Dictionary, job: String) -> void:
	release_desk(unit)
	unit["job"] = job
	unit["work_state"] = "idle"
	unit["work_pose"] = null
	# Jeremy 2026-10-10 planned road networks: a reassigned roadbuilder
	# drops its link claim so another crew can pick the link up.
	unit.erase("_road_link")
	unit.erase("_road_link_pts")
	unit.erase("_road_link_total")
	unit.erase("_road_link_prev")
	unit.erase("_road_order")
	# Jeremy 2026-10-10 visible road construction: a reassigned repair
	# crew drops the repair too — the work zone clears with the flag.
	unit.erase("_road_repair_idx")
	unit.erase("_road_repair_t")
	unit.erase("_repair_working")


## Faction resource pressure -> what generalist workers prioritize today
## (HTML factionWorkPriority): "build" when stocked (wood > 80 and
## gold > 60); otherwise the scarcest of wood/gold/food wins.
func _faction_priority(faction: String) -> String:
	var wood: float = _gs.resources.get_amount(faction, "wood")
	var gold: float = _gs.resources.get_amount(faction, "gold")
	var food: float = _gs.resources.get_amount(faction, "food")
	if wood > 80.0 and gold > 60.0:
		return "build"
	var best := "wood"
	var best_s: float = 1.0 / maxf(40.0, wood)
	var gs2: float = 1.0 / maxf(40.0, gold)
	if gs2 > best_s:
		best = "gold"
		best_s = gs2
	var fs: float = 1.0 / maxf(30.0, food)
	if fs > best_s:
		best = "food"
	return best


## Gathers the faction's scarcest resource (generalist "worker" behavior).
func _assign_gather_priority(unit: Dictionary, faction: String) -> bool:
	match _faction_priority(faction):
		"gold":
			return _assign_gather_kinds(unit, ["gold_vein"])
		"food":
			return _assign_gather_kinds(unit, ["bush"])
		_:
			return _assign_lumber(unit)


## Gathers from the nearest site of the given kinds.
func _assign_gather_kinds(unit: Dictionary, kinds: Array[String]) -> bool:
	var site: Dictionary = _nearest_site(unit, kinds)
	if site.is_empty():
		return false
	unit["work_site"] = int(site["id"])
	unit["work_target_pos"] = site["position"]
	unit["work_state"] = "to_resource"
	return true


## ---- Station jobs (MISS 13) ----------------------------------------------
## Station-job NPCs work visibly at a real workplace anchor: walk to the
## building, stand at the work spot, and do the activity. Desk jobs claim
## one free unowned desk at shift start (one desk per worker, released
## off-shift — HTML c71ClaimDesk/c71ReleaseDesk).


## Sends the unit to its station. Resolves the station building from the
## hire record, falling back to the nearest completed workplace of the
## job's building types (HTML resolveJobStation57).
func _assign_station(unit: Dictionary, job: String) -> bool:
	var st: Dictionary = unit.get("station", {})
	var b: Dictionary = _station_building(unit, st, job)
	if b.is_empty():
		return false
	var entry: Dictionary = JobDefs.workplace_for(job)
	var spot: String = String(entry.get("spot", ""))
	var size: float = SimBuildings.footprint(String(b.get("type", "house")))
	var target: Vector2 = (b.get("position", Vector2.ZERO) as Vector2) \
		+ JobDefs.spot_offset(spot, size, job)
	unit["work_building"] = int(b["id"])
	unit["work_target_pos"] = target
	unit["work_state"] = "to_station"
	unit["work_activity"] = String(entry.get("act", "working"))
	# Desk jobs claim a cubicle at shift start (officers work INSIDE at
	# claimed desks — HTML c71OfficerDeskTick).
	if spot == "desk":
		claim_desk(unit, b)
	return true


## Resolves a station building: the hire-recorded building wins when it is
## alive and still a valid workplace; otherwise the nearest completed
## same-faction workplace of the job's building types.
func _station_building(unit: Dictionary, st: Dictionary, job: String) -> Dictionary:
	var entry: Dictionary = JobDefs.workplace_for(job)
	var types: Array = entry.get("types", [])
	var faction: String = String(unit.get("faction", ""))
	var bid: int = int(st.get("building_id", -1))
	if bid >= 0:
		for b: Dictionary in _gs.buildings:
			if int(b.get("id", -1)) == bid and b.get("alive", false) \
					and String(b.get("faction", "")) == faction:
				# The hire record is authoritative — the guild master's
				# office is the guild hall, outside the roster table.
				return b
	# Fallback: nearest completed workplace of the right types.
	var best: Dictionary = {}
	var best_d := INF
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if not String(b.get("type", "")) in types:
			continue
		var d: float = (b.get("position", Vector2.ZERO) as Vector2).distance_to(up)
		if d < best_d:
			best_d = d
			best = b
	return best


## Working tick at the station: hold the spot, earn wages, set the visible
## interaction pose (HTML c59StationPose57: desk -> sit, counter/bar ->
## use, forge/site -> work).
func _do_station_work(unit: Dictionary, delta: float) -> void:
	var st: Dictionary = unit.get("station", {})
	var job: String = String(unit.get("job", "worker"))
	var b: Dictionary = _building_by_id(int(st.get("building_id", -1)))
	if b.is_empty() or not b.get("alive", false):
		# Workplace died — the roster re-hires next sweep; stand down.
		release_desk(unit)
		unit["station"] = {}
		unit["work_state"] = "idle"
		unit["work_pose"] = null
		return
	var spot: String = String(st.get("spot", ""))
	match spot:
		"desk":
			unit["work_pose"] = "sit"
		"counter", "bar":
			unit["work_pose"] = "use"
		"forge", "site":
			unit["work_pose"] = "work"
		_:
			unit["work_pose"] = null
	# Wages for honest work (HTML: staff earn coins at their workplace).
	unit["coins"] = float(unit.get("coins", 0.0)) \
		+ SimHousing.STATION_WAGE_PER_SEC * delta
	# Drift back to the spot if pushed away.
	var target: Vector2 = unit.get("work_target_pos", unit.get("position", Vector2.ZERO))
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	if up.distance_to(target) > 40.0:
		unit["work_state"] = "to_station"


## ---- Desk claims (C71) -----------------------------------------------------
## Desks are claimable resources on the building record: "desks" is an
## Array of {id, claimed_by}. A worker scans their workplace for a free
## desk, claims it at shift start, keeps it all shift, and releases it
## when the shift ends. No two workers share a desk.


## Ensures a building has its desk roster (one desk per desk-job slot —
## advisers get individual cubicles in the government building; the guild
## master gets the guild-hall office).
func ensure_desks(building: Dictionary) -> void:
	if building.has("desks"):
		return
	var btype: String = String(building.get("type", ""))
	var desks: Array = []
	var next_id := 0
	for e: Dictionary in JobDefs.WORKPLACES:
		if not btype in (e["types"] as Array):
			continue
		if String(e.get("spot", "")) != "desk":
			continue
		# Officer posts anchor on the town hall only (unique per town).
		var job: String = String(e["job"])
		if (job == "guild_master" or job == "adviser" or job == "watchcaptain") \
				and not btype in ["town_hall", "hall"]:
			continue
		for i: int in range(JobDefs.slots_for(btype, int(e["slots"]))):
			desks.append({"id": next_id, "claimed_by": -1})
			next_id += 1
	building["desks"] = desks


## Claims a free unowned desk in the workplace for the unit. Returns true
## when the unit now holds a claim (or already did).
func claim_desk(unit: Dictionary, building: Dictionary) -> bool:
	if unit.is_empty() or building.is_empty():
		return false
	var held: Dictionary = unit.get("_desk", {})
	if not held.is_empty() and int(held.get("building_id", -1)) == int(building.get("id", -1)):
		return true
	ensure_desks(building)
	release_desk(unit)
	var uid: int = int(unit.get("id", 0))
	for d: Dictionary in (building["desks"] as Array):
		if int(d.get("claimed_by", -1)) >= 0 and not _desk_holder_gone(d, building):
			continue
		d["claimed_by"] = uid
		unit["_desk"] = {"building_id": int(building["id"]),
			"desk_id": int(d["id"])}
		return true
	return false


## Releases the unit's desk claim (static: stale claims die with the
## worker/job — safe to call from assign_job).
static func release_desk(unit: Dictionary) -> void:
	unit.erase("_desk")


## True when a claimed desk's holder is gone (dead or released) — the
## claim is stale and the desk is free again.
func _desk_holder_gone(d: Dictionary, _building: Dictionary) -> bool:
	var holder_id: int = int(d.get("claimed_by", -1))
	if holder_id < 0:
		return true
	var holder: Dictionary = _gs.get_unit(holder_id)
	if holder.is_empty() or not holder.get("alive", false):
		return true
	var held: Dictionary = holder.get("_desk", {})
	return held.is_empty()


## ---- Roadbuilder crew -------------------------------------------------------
## Roadbuilders walk their road order (resource camp -> town hall -> the
## nearest tree/rock near the hall), painting a continuous path under
## their feet; stone when the faction is stocked (HTML crew behavior).


func _do_roadwork(unit: Dictionary, delta: float) -> void:
	var faction: String = String(unit.get("faction", ""))
	# Jeremy 2026-10-10 planned road networks: a stale link claim (the
	# link finished by another crew, or the plan was dropped) releases
	# back to the pool instead of walking a dead waypoint.
	if unit.has("_road_link"):
		var _li := _link_index(int(unit.get("_road_link", 0)))
		if _li < 0 \
				or bool((road_links[_li] as Dictionary).get("done", false)):
			_clear_link(unit)
	var order: Vector2 = unit.get("_road_order", Vector2(-1, -1))
	if order.x < 0.0:
		order = _pick_road_order(unit)
		if order.x < 0.0:
			unit["work_state"] = "idle"
			return
		unit["_road_order"] = order
	# Always paint under feet — continuous path (HTML crew, 0.35 s cadence).
	# Jeremy 2026-10-10 visible road construction: a crew walking a planned
	# link does NOT paint underfoot — the link paints explicitly waypoint by
	# waypoint behind the work front, so nothing goes down ahead of it.
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var paint_t: float = float(unit.get("_road_paint_t", 0.0)) + delta
	if paint_t >= ROAD_PAINT_INTERVAL and not unit.has("_road_link"):
		unit["_road_paint_t"] = 0.0
		paint_road(up, faction)
		# HTML crew verbatim (fix79): fill gaps toward the order for a
		# continuous painted strip. The Godot port dropped this — its
		# merge-radius-only painting left dashed crew trails.
		var to_order: Vector2 = order - up
		var od := to_order.length()
		if od > 8.0:
			var steps := mini(3, int(od / ROAD_CELL))
			for s in range(1, steps + 1):
				var t := float(s) / float(steps + 1)
				paint_road(up + to_order * t, faction, "dirt")
	else:
		unit["_road_paint_t"] = paint_t
	if up.distance_to(order) < ROAD_ORDER_ARRIVE:
		# Jeremy 2026-10-10 road wear: repair orders channel at the worn
		# segment instead of going idle — wear resets when the work's done.
		# Jeremy 2026-10-10 visible road construction: the repair is a
		# visible work zone (barriers/cones around the crew) for the whole
		# channel — never an instant paint-over.
		if unit.has("_road_repair_idx"):
			var ridx: int = int(unit.get("_road_repair_idx", -1))
			if ridx < 0 or ridx >= roads.size():
				unit.erase("_road_repair_idx")
				unit.erase("_repair_working")
			else:
				if not bool(unit.get("_repair_working", false)):
					unit["_repair_working"] = true
					_bump_work_version()
				var rt: float = float(unit.get("_road_repair_t", 0.0)) \
					+ delta
				if rt >= REPAIR_TIME:
					roads[ridx]["wear"] = 0.0
					road_wear_version += 1
					unit.erase("_road_repair_idx")
					unit.erase("_road_repair_t")
					unit.erase("_road_order")
					unit.erase("_repair_working")
					unit["work_state"] = "idle"
					unit["work_pose"] = null
					_bump_work_version()
					return
				unit["_road_repair_t"] = rt
				unit["work_state"] = "to_road"
				unit["work_pose"] = "work"
				return
		# Jeremy 2026-10-10 planned road networks: a reached waypoint
		# advances along the link polyline (or finishes the link).
		if _advance_link(unit):
			return
		unit.erase("_road_order")
		unit["work_state"] = "idle"
		return
	unit["work_target_pos"] = order
	if _walk_to(unit, order, delta):
		# Repair orders stay live so the arrival branch above can channel
		# the fix; link orders advance along their polyline; only plain
		# paint orders complete on walk arrival.
		if unit.has("_road_link"):
			_advance_link(unit)
		elif not unit.has("_road_repair_idx"):
			unit.erase("_road_order")
			unit["work_state"] = "idle"


## Most-worn road record of the faction within repair range, or -1.
## Worst wear wins; nearer wins ties — the crew fixes what's crumbling
## closest to them first.
func _nearest_worn_road(up: Vector2, faction: String) -> int:
	var best := -1
	var best_score := -1.0
	for i in roads.size():
		var r: Dictionary = roads[i]
		if String(r.get("faction", "")) != faction:
			continue
		var w: float = float(r.get("wear", 0.0))
		if w < REPAIR_WEAR_THRESHOLD:
			continue
		var d: float = (r.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(up)
		if d > REPAIR_SEARCH_RADIUS:
			continue
		var score := w * 100000.0 - d
		if score > best_score:
			best_score = score
			best = i
	return best


## Records a planned network link for the faction's roadbuilder crews.
## Dedupes on endpoint proximity (either direction); returns the link id,
## or 0 when the link already exists or the record is full.
func plan_road_link(faction: String, a: Vector2, b: Vector2) -> int:
	if a.distance_to(b) < 1.0:
		return 0
	for l: Dictionary in road_links:
		if String(l.get("faction", "")) != faction:
			continue
		var la := _as_vec2(l.get("a", Vector2.ZERO))
		var lb := _as_vec2(l.get("b", Vector2.ZERO))
		if (la.distance_to(a) < ROAD_LINK_DEDUP \
				and lb.distance_to(b) < ROAD_LINK_DEDUP) \
			or (la.distance_to(b) < ROAD_LINK_DEDUP \
				and lb.distance_to(a) < ROAD_LINK_DEDUP):
			return 0
	_prune_link_records()
	var lid := _road_link_next_id
	_road_link_next_id += 1
	road_links.append({"id": lid, "faction": faction, "a": a, "b": b,
		"done": false, "day": int(_gs.day_number),
		"stage": ROAD_STAGE_SURVEYED, "front": 0.0, "pass": 0,
		"from": a, "to": b})
	_bump_work_version()
	return lid


## Drops oldest done links when the record is over cap (index-free: links
## are referenced by id, never by position, so removal is safe).
func _prune_link_records() -> void:
	if road_links.size() < ROAD_LINKS_MAX:
		return
	var over: int = road_links.size() - ROAD_LINKS_MAX + 1
	var kept: Array = []
	var dropped := 0
	for l: Dictionary in road_links:
		if dropped < over and bool(l.get("done", false)):
			dropped += 1
			continue
		kept.append(l)
	road_links = kept


## Undone (planned but not yet walked) links for the faction.
func undone_link_count(faction: String) -> int:
	var n := 0
	for l: Dictionary in road_links:
		if String(l.get("faction", "")) == faction \
				and not bool(l.get("done", false)):
			n += 1
	return n


## Forgets stale undone links so the director can re-plan a fresh network
## when the crew never got to the old plan (e.g. no roadbuilders around).
func prune_stale_links(faction: String) -> void:
	var day := int(_gs.day_number)
	var kept: Array = []
	for l: Dictionary in road_links:
		if String(l.get("faction", "")) == faction \
				and not bool(l.get("done", false)) \
				and day - int(l.get("day", day)) > ROAD_LINK_STALE_DAYS:
			continue
		kept.append(l)
	if kept.size() != road_links.size():
		_bump_work_version()
	road_links = kept


## Array index of the link with this id, or -1.
func _link_index(link_id: int) -> int:
	for i in road_links.size():
		if int((road_links[i] as Dictionary).get("id", 0)) == link_id:
			return i
	return -1


## Evenly-spaced waypoints from a to b (inclusive), at most
## ROAD_LINK_WP_SPACING apart — the crew walks and paints these in order.
static func link_waypoints(a: Vector2, b: Vector2) -> Array:
	var pts: Array = []
	var d := a.distance_to(b)
	if d < 1.0:
		return pts
	var n := maxi(1, int(ceil(d / ROAD_LINK_WP_SPACING)))
	for i in range(n + 1):
		pts.append(a.lerp(b, float(i) / float(n)))
	return pts


## Nearest undone link for the faction within claim range of the unit,
## or -1. Links already being walked by another live roadbuilder are
## skipped so two crews don't pave the same stretch twice.
func _nearest_link(up: Vector2, faction: String) -> int:
	var best := -1
	var best_d := ROAD_LINK_RANGE
	for l: Dictionary in road_links:
		if String(l.get("faction", "")) != faction \
				or bool(l.get("done", false)):
			continue
		var lid := int(l.get("id", 0))
		if _link_claimed_by_other(lid, faction):
			continue
		var d: float = minf(
			_as_vec2(l.get("a", Vector2.ZERO)).distance_to(up),
			_as_vec2(l.get("b", Vector2.ZERO)).distance_to(up))
		if d < best_d:
			best_d = d
			best = lid
	return best


## True when some other living roadbuilder is already walking this link.
func _link_claimed_by_other(link_id: int, faction: String) -> bool:
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("job", "")) != "roadbuilder":
			continue
		if int(u.get("_road_link", 0)) == link_id:
			return true
	return false


## Releases a unit's link claim without marking the link done (stale
## claim, reassignment, dropped plan).
func _clear_link(unit: Dictionary) -> void:
	unit.erase("_road_link")
	unit.erase("_road_link_pts")
	unit.erase("_road_link_total")
	unit.erase("_road_link_prev")
	unit.erase("_road_order")


## Marks the unit's link walked: records done and idles the unit.
func _finish_link(unit: Dictionary) -> void:
	var li := _link_index(int(unit.get("_road_link", 0)))
	if li >= 0:
		(road_links[li] as Dictionary)["done"] = true
		(road_links[li] as Dictionary)["stage"] = ROAD_STAGE_DONE
		(road_links[li] as Dictionary)["front"] = 1.0
	_bump_work_version()
	_clear_link(unit)
	unit["work_state"] = "idle"
	unit["work_pose"] = null


## Advances a roadbuilder along their claimed link polyline. The waypoint
## just reached is built: the grade pass (pass 0) lays dirt behind the work
## front; when the front reaches the far end, a stocked faction starts the
## paving pass (pass 1) back along the line, laying stone over the dirt.
## Returns true when the unit held a link (waypoint advanced, pass changed,
## or the link finished and the unit idled); false when no link is held.
func _advance_link(unit: Dictionary) -> bool:
	if not unit.has("_road_link"):
		return false
	var link_id := int(unit.get("_road_link", 0))
	var li := _link_index(link_id)
	var pts: Array = unit.get("_road_link_pts", [])
	var faction := String(unit.get("faction", ""))
	if li < 0:
		_clear_link(unit)
		return false
	var link: Dictionary = road_links[li]
	if bool(link.get("done", false)):
		_clear_link(unit)
		return false
	var total := maxi(1, int(unit.get("_road_link_total", maxi(1, pts.size()))))
	var pass_idx := int(link.get("pass", 0))
	# Build the segment the unit just walked: previous waypoint -> reached.
	if not pts.is_empty():
		var reached: Vector2 = pts[0]
		pts.pop_front()
		if unit.has("_road_link_prev"):
			var prev := _as_vec2(unit.get("_road_link_prev", reached))
			_paint_link_segment(prev, reached, faction,
				"stone" if pass_idx == 1 else "dirt")
		unit["_road_link_prev"] = reached
	link["front"] = clampf(1.0 - float(pts.size()) / float(total), 0.0, 1.0)
	_bump_work_version()
	if pts.is_empty():
		if pass_idx == 0 and _faction_can_pave(faction):
			# Paving pass: walk the finished dirt line back (to -> from),
			# laying stone over the dirt.
			link["pass"] = 1
			link["stage"] = ROAD_STAGE_PAVING
			var lf := _as_vec2(link.get("from",
				link.get("a", Vector2.ZERO)))
			var lt := _as_vec2(link.get("to", link.get("b", Vector2.ZERO)))
			var rpts := link_waypoints(lf, lt)
			rpts.reverse()  # to -> from; the unit stands at the `to` end
			if not rpts.is_empty():
				rpts.pop_front()  # already standing on the `to` end
			if rpts.is_empty():
				_finish_link(unit)
				return true
			unit["_road_link_pts"] = rpts
			unit["_road_link_total"] = rpts.size()
			unit["_road_link_prev"] = lt
			unit["_road_order"] = rpts[0]
			unit["work_target_pos"] = rpts[0]
			return true
		_finish_link(unit)
		return true
	unit["_road_link_pts"] = pts
	unit["_road_order"] = pts[0]
	unit["work_target_pos"] = pts[0]
	return true


## Lays one road type along a waypoint segment (~20 px dabs so the merge
## radius fuses them into a continuous strip).
func _paint_link_segment(a: Vector2, b: Vector2, faction: String,
		rtype: String) -> void:
	var d := a.distance_to(b)
	var steps := maxi(1, int(ceil(d / 20.0)))
	for i in range(steps + 1):
		paint_road(a.lerp(b, float(i) / float(steps)), faction, rtype)


## Stone paving needs stock on hand (same bar as paint_road's auto-stone).
func _faction_can_pave(faction: String) -> bool:
	return _gs.resources.get_amount(faction, "gold") >= 30.0 \
		and _gs.resources.get_amount(faction, "wood") >= 20.0


## ---- Visible road construction: work zones --------------------------------
## Jeremy 2026-10-10: a planned road is a marked work zone first; segments
## under construction are closed — foot traffic, wagons and vehicles route
## around them until the segment opens. Zones derive from live link/crew
## state (no extra records to linger): grading links close their ungraded
## corridor, paving links close a moving disc at the paver, repairs close a
## disc while the crew channels. Surveyed (unclaimed) plans are stakes only.

## Live position of the roadbuilder holding this link, or the fallback when
## the holder is gone (reassigned mid-pass).
func _link_holder_pos(link_id: int, faction: String,
		fallback: Vector2) -> Vector2:
	for u in _gs.units:
		var ud: Dictionary = u
		if not bool(ud.get("alive", false)):
			continue
		if String(ud.get("faction", "")) != faction:
			continue
		if String(ud.get("job", "")) != "roadbuilder":
			continue
		if int(ud.get("_road_link", 0)) == link_id:
			return _as_vec2(ud.get("position", fallback))
	return fallback


## Active work zones. Recomputed when dirty or at WORK_ZONE_CACHE_TTL
## cadence; the version bumps on any real change so the pathfinder nav and
## the overlay refresh. Each zone: {kind: "seg", a, b, r, stage, link,
## front} or {kind: "disc", pos, r, stage, link}.
func road_work_zones() -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	if not _work_zones_dirty \
			and now - _work_zone_cache_t < WORK_ZONE_CACHE_TTL:
		return _work_zone_cache
	_work_zones_dirty = false
	_work_zone_cache_t = now
	var zones: Array = []
	for l in road_links:
		var ld: Dictionary = l
		if bool(ld.get("done", false)):
			continue
		var stage := int(ld.get("stage", ROAD_STAGE_SURVEYED))
		if stage == ROAD_STAGE_DONE:
			continue
		var lid := int(ld.get("id", 0))
		var faction := String(ld.get("faction", ""))
		var va := _as_vec2(ld.get("a", Vector2.ZERO))
		var vb := _as_vec2(ld.get("b", Vector2.ZERO))
		if stage == ROAD_STAGE_SURVEYED:
			# Fresh plan: survey stakes mark the line, corridor stays open
			# until a crew breaks ground.
			zones.append({"kind": "seg", "a": va, "b": vb,
				"r": WORK_ZONE_HALF_WIDTH, "stage": stage, "link": lid,
				"front": va, "closed": false})
			continue
		if not _link_claimed_by_other(lid, faction):
			continue  # crew lost (reassigned): stakes again on re-claim
		if stage == ROAD_STAGE_GRADING:
			var a := _as_vec2(ld.get("from", va))
			var b := _as_vec2(ld.get("to", vb))
			var fp := a.lerp(b,
				clampf(float(ld.get("front", 0.0)), 0.0, 1.0))
			zones.append({"kind": "seg", "a": fp, "b": b,
				"r": WORK_ZONE_HALF_WIDTH, "stage": stage, "link": lid,
				"front": fp, "closed": true})
		elif stage == ROAD_STAGE_PAVING:
			var fa := _as_vec2(ld.get("from", va))
			var fb := _as_vec2(ld.get("to", vb))
			var hp := _link_holder_pos(lid, faction, fa.lerp(fb, 0.5))
			zones.append({"kind": "disc", "pos": hp, "r": WORK_ZONE_DISC_R,
				"stage": stage, "link": lid, "closed": true})
	for u in _gs.units:
		var ud: Dictionary = u
		if not bool(ud.get("alive", false)):
			continue
		if String(ud.get("job", "")) != "roadbuilder":
			continue
		if not bool(ud.get("_repair_working", false)):
			continue
		var ridx := int(ud.get("_road_repair_idx", -1))
		if ridx < 0 or ridx >= roads.size():
			continue
		var rp: Vector2 = (roads[ridx] as Dictionary).get(
			"position", Vector2.ZERO)
		zones.append({"kind": "disc", "pos": rp, "r": WORK_ZONE_DISC_R,
			"stage": -1, "link": 0, "closed": true})
	var sig := ""
	for z in zones:
		var zd: Dictionary = z
		var pa: Vector2 = zd.get("a", zd.get("pos", Vector2.ZERO))
		var pb: Vector2 = zd.get("b", pa)
		sig += "%s%d:%d,%d:%d,%d|" % [String(zd.get("kind", "")),
			int(zd.get("stage", 0)), int(pa.x / 16.0), int(pa.y / 16.0),
			int(pb.x / 16.0), int(pb.y / 16.0)]
	if sig != _work_zone_sig:
		_work_zone_sig = sig
		road_work_version += 1
	_work_zone_cache = zones
	return zones


## Steering deflection away from active work zones (foot traffic, wagons,
## vehicles). The crew working a zone is exempt — everyone else slides
## around it. Pure w.r.t. the sim (no state mutated).
func deflect_around_workzones(pos: Vector2, dir: Vector2,
		unit: Dictionary) -> Vector2:
	if dir.length_squared() < 0.0001:
		return dir
	if String(unit.get("job", "")) == "roadbuilder" \
			and (unit.has("_road_link") \
				or bool(unit.get("_repair_working", false))):
		return dir
	var zones := road_work_zones()
	if zones.is_empty():
		return dir
	var push := Vector2.ZERO
	for z in zones:
		var zd: Dictionary = z
		if not bool(zd.get("closed", true)):
			continue  # surveyed plans are marked, not closed
		var center := Vector2.ZERO
		var radius := 0.0
		if String(zd.get("kind", "")) == "disc":
			center = zd.get("pos", Vector2.ZERO)
			radius = float(zd.get("r", WORK_ZONE_DISC_R)) + 24.0
		else:
			center = Geometry2D.get_closest_point_to_segment(pos,
				zd.get("a", Vector2.ZERO), zd.get("b", Vector2.ZERO))
			radius = float(zd.get("r", WORK_ZONE_HALF_WIDTH)) + 24.0
		var off := pos - center
		var dist := off.length()
		if dist < radius and dist > 0.01:
			push += off / dist * (1.0 - dist / radius)
	if push.length_squared() < 0.0001:
		return dir
	return (dir + push * 2.0).normalized() * dir.length()


## Picks a road destination: the nearest completed town hall/hall of the
## faction (HTML: resource camp first — Godot has no camp type), else the
## nearest tree or rock work site within 500 px of the unit.
func _pick_road_order(unit: Dictionary) -> Vector2:
	var faction: String = String(unit.get("faction", ""))
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	# Jeremy 2026-10-10 road wear: maintenance first — a worn segment in
	# range outranks painting new road.
	var repair_idx := _nearest_worn_road(up, faction)
	if repair_idx >= 0:
		unit["_road_repair_idx"] = repair_idx
		unit["_road_repair_t"] = 0.0
		return roads[repair_idx].get("position", Vector2.ZERO)
	unit.erase("_road_repair_idx")
	unit.erase("_road_repair_t")
	# Jeremy 2026-10-10 planned road networks: a director-planned link for
	# this faction outranks incidental trail painting. The crew walks the
	# waypoint polyline and paints it; the link completes when the last
	# waypoint is reached.
	var link_id := _nearest_link(up, faction)
	if link_id > 0:
		var li := _link_index(link_id)
		if li >= 0:
			var la := _as_vec2(
				(road_links[li] as Dictionary).get("a", Vector2.ZERO))
			var lb := _as_vec2(
				(road_links[li] as Dictionary).get("b", Vector2.ZERO))
			var pts := link_waypoints(la, lb)
			if not pts.is_empty():
				# Walk the nearer endpoint first — no backtracking.
				if up.distance_to(pts[pts.size() - 1]) \
						< up.distance_to(pts[0]):
					pts.reverse()
				# Jeremy 2026-10-10 visible road construction: claiming the
				# link breaks ground — surveyed -> grading, work zone live.
				var claim_d: Dictionary = road_links[li]
				claim_d["stage"] = ROAD_STAGE_GRADING
				claim_d["pass"] = 0
				claim_d["front"] = 0.0
				claim_d["from"] = pts[0]
				claim_d["to"] = pts[pts.size() - 1]
				unit["_road_link"] = link_id
				unit["_road_link_pts"] = pts
				unit["_road_link_total"] = pts.size()
				_bump_work_version()
				return pts[0]
		_clear_link(unit)
	var best: Dictionary = {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if not String(b.get("type", "")) in ["town_hall", "hall"]:
			continue
		var d: float = (b.get("position", Vector2.ZERO) as Vector2).distance_to(up)
		if d < best_d and d > 1.0:
			best_d = d
			best = b
	if not best.is_empty():
		return best["position"]
	var site: Dictionary = _nearest_site(unit, ["tree", "gold_vein"])
	if site.is_empty():
		return Vector2(-1, -1)
	var sp: Vector2 = site["position"]
	if up.distance_to(sp) > 500.0:
		return Vector2(-1, -1)
	return sp
	unit["work_site"] = -1
	unit["work_building"] = -1
	unit["carrying"] = {}
	unit["station"] = {}
	unit["work_pose"] = null
	unit.erase("_road_order")


## One tick of work for a single unit record. buildings is the SimBuildings
## instance (needed for construction progress).
func tick_unit(unit: Dictionary, buildings: SimBuildings, delta: float) -> void:
	# Per-unit AI slice clock for the _pick_task idle backoff (R34).
	unit["_ai_ticks"] = int(unit.get("_ai_ticks", 0)) + 1
	if not unit.get("alive", false):
		return
	# SimHousing owns migration, homesteading, and house-hunting walks.
	# SimNPCTravel owns a unit's long trip while it rides its own vehicle.
	if unit.has("_homestead") or unit.has("_buying_home") \
			or unit.has("_buying_vehicle") or unit.has("_ride"):
		return
	# Jeremy 2026-10-11 (disaster aid): guest helpers are driven by
	# SimDisasterAid — the worker AI must not reassign them.
	if unit.has("aid_mission"):
		return
	var _cm: Vector2 = unit.get("_country_move", Vector2(-1, -1))
	if _cm.x >= 0.0:
		return
	var job: String = String(unit.get("job", "worker"))
	_ensure_fields(unit)
	if JobDefs.is_military(job):
		return  # Milestone 4 owns military behavior.
	if job == "firefighter":
		unit["work_state"] = "idle"
		return  # SimDisasters.tick_firefighter drives them; hold position
	# Massive-dev 2026-10-08: Milo the Doomscroller's aura — a doomscrolling
	# citizen stares at their phone instead of working. The flag is set and
	# cleared by SimDisasters._doomscroll_aura (2s cadence) and on the
	# disaster's departure/slain; holding here keeps the disruption stuck
	# to the aura instead of fighting the task picker every tick.
	if bool(unit.get("doomscrolling", false)):
		unit["work_state"] = "idle"
		unit["work_pose"] = null
		return
	# Dedicated-porting 2026-10-08: Chad the MLM Bro's pitch — a hustling
	# citizen is too busy building their downline to work. The flag is set
	# and cleared by SimDisasters._mlm_aura (3s cadence) and on the
	# disaster's departure/slain; holding here keeps the disruption stuck
	# to the aura instead of fighting the task picker every tick.
	if bool(unit.get("hustling", false)):
		unit["work_state"] = "idle"
		unit["work_pose"] = null
		return
	# Wake rapid-iteration 2026-10-08: Dave the DMV Clerk's queue — a
	# citizen waiting in line is too busy holding their ticket to work.
	# The flag is set and cleared by SimDisasters._dmv_aura (4s cadence),
	# dispersed at lunch, and cleared on the disaster's departure/slain;
	# holding here keeps the disruption stuck to the aura instead of
	# fighting the task picker every tick.
	if bool(unit.get("waiting_in_line", false)):
		unit["work_state"] = "idle"
		unit["work_pose"] = null
		return
	# Massive-dev 2026-10-08: Kyle the CrossFit Gnome's WOD — a workout
	# citizen is too busy doing burpees to work. The flag is set and cleared
	# by SimDisasters._crossfit_aura (2.5s cadence) and on the disaster's
	# departure/slain; holding here keeps the disruption stuck to the aura
	# instead of fighting the task picker every tick.
	if bool(unit.get("workouting", false)):
		unit["work_state"] = "idle"
		unit["work_pose"] = null
		return
	# Dedicated-porting 2026-10-08: Vicky the Influencer's clout — a
	# gawking citizen is too busy posing for the stream to work. The flag
	# is set and cleared by SimDisasters._influencer_aura (2.5s cadence)
	# and on the disaster's departure/slain; holding here keeps the
	# disruption stuck to the aura instead of fighting the task picker.
	if bool(unit.get("gawking", false)):
		unit["work_state"] = "idle"
		unit["work_pose"] = null
		return
	# Massive-dev 2026-10-08: DJ Weddington's drop — a dancing citizen
	# is too busy feeling the beat to work. The flag is set and cleared
	# by SimDisasters._dj_aura (2.5s cadence) and on the disaster's
	# departure/slain; holding here keeps the disruption stuck to the aura
	# instead of fighting the task picker.
	if bool(unit.get("dancing", false)):
		unit["work_state"] = "idle"
		unit["work_pose"] = null
		return
	# Rapid-iteration 2026-10-08: Milo the Podcast Bro's engagement — a
	# podcast guest is too busy being content to work. The flag is set and
	# cleared by SimDisasters._podcast_aura (2.5s cadence) and on the
	# disaster's departure/slain; holding here keeps the disruption stuck
	# to the aura instead of fighting the task picker.
	if bool(unit.get("podcasting", false)):
		unit["work_state"] = "idle"
		unit["work_pose"] = null
		return
	if job == "unemployed":
		_tick_unemployed(unit, delta)
		return  # GuildHiring owns the seek-work walk; urges still ran in mind
	var hour: float = hour_of_day(_gs)
	# Jeremy 2026-10-05: ground pickups (felled-tree wood) are collected by
	# walking over them — runs for every working unit, every tick. Cheap:
	# early-outs when no pickups exist.
	_collect_pickups(unit)
	# Station/desk jobs work their shift at their workplace; off-shift they
	# release their desk and stand down (shops staffed during business
	# hours per shift). Only units with a hire-recorded station are gated
	# here — unassigned specialists (e.g. doctors) keep job behavior.
	var st: Dictionary = unit.get("station", {})
	if not st.is_empty() and JobDefs.is_station_job(job):
		if not is_on_shift(job, hour):
			release_desk(unit)
			unit["work_state"] = "idle"
			unit["work_pose"] = null
			return
	match String(unit["work_state"]):
		"idle":
			_pick_task(unit, buildings, hour)
		"to_resource":
			if _walk_to(unit, unit["work_target_pos"], delta):
				unit["work_state"] = "gathering"
		"to_plot":
			if _walk_to(unit, unit["work_target_pos"], delta):
				unit["work_state"] = "plot_chore"
		"plot_chore":
			_do_plot_chore(unit, delta)
		"gathering":
			_do_gather(unit, delta)
		"to_lake":
			if _walk_to(unit, unit["work_target_pos"], delta):
				unit["work_state"] = "fishing"
				unit["work_pose"] = "work"
				unit["_fish_timer"] = 0.0
		"to_dropoff":
			if _walk_to(unit, unit["work_target_pos"], delta):
				_do_dropoff(unit)
		"to_build":
			if _walk_to(unit, unit["work_target_pos"], delta):
				unit["work_state"] = "building"
		"building":
			_do_build(unit, buildings, delta)
		# Jeremy 2026-10-04: tool supply flow — walking to a shop to buy
		# the job's tool (set up by SimPetitions.try_supply_tool).
		"to_shop":
			if _walk_to(unit, unit["work_target_pos"], delta):
				_do_shop_buy(unit)
		"to_repair":
			if _walk_to(unit, unit["work_target_pos"], delta):
				unit["work_state"] = "repairing"
		"repairing":
			_do_repair(unit, delta)
		"to_patient":
			if _walk_to(unit, unit["work_target_pos"], delta):
				unit["work_state"] = "healing"
		"healing":
			_do_heal(unit, delta)
		"to_station":
			if _walk_to(unit, unit["work_target_pos"], delta):
				unit["work_state"] = "working"
		"working":
			_do_station_work(unit, delta)
		"to_road":
			_do_roadwork(unit, delta)
		"to_prey":
			if _walk_to(unit, unit["work_target_pos"], delta):
				unit["work_state"] = "hunting"
		"hunting":
			_do_hunt(unit, delta)
		"fishing":
			_do_fish(unit, delta)
		"to_tend":
			if _walk_to(unit, unit["work_target_pos"], delta):
				unit["work_state"] = "tending"
		"tending":
			_do_tend(unit, delta)
		_:
			# Unknown / stale state (including "off_shift" when the shift
			# bell rings again): drop the downtime plan and re-pick work.
			unit["work_state"] = "idle"
			unit.erase("_downtime")


## Fills in runtime defaults the first time a unit works.
func _ensure_fields(unit: Dictionary) -> void:
	# Fast path: fields are only ever added, never removed (except
	# work_site, which siege/ai_director reassignments erase — re-add it).
	if unit.has("_wf_init"):
		if not unit.has("work_site"):
			unit["work_site"] = -1
		return
	if not unit.has("work_state"):
		unit["work_state"] = "idle"
	if not unit.has("work_site"):
		unit["work_site"] = -1
	if not unit.has("work_building"):
		unit["work_building"] = -1
	if not unit.has("carrying"):
		unit["carrying"] = {}
	if not unit.has("carry_cap"):
		unit["carry_cap"] = CARRY_CAP
	if not unit.has("speed"):
		# Jeremy 2026-10-04: units moved too fast — slower, deliberate pace.
		unit["speed"] = 45.0 if String(unit.get("job", "")) == "ranger" else 30.0
	if not unit.has("work_target_pos"):
		unit["work_target_pos"] = unit.get("position", Vector2.ZERO)
	# Personal wages (HTML: units start with 20-40 coins) — deterministic
	# from the unit id; spent on houses, earned at drop-offs and stations.
	if not unit.has("coins"):
		unit["coins"] = 20.0 + float(int(unit.get("id", 0)) % 40)
	unit["_wf_init"] = true


## Routed movement. Returns true on arrival (within 6 px).
## Long hauls (>200 px) project an A* route around buildings, water,
## and cliffs (SimPathfinder — HTML astarDGrid parity); short hops steer
## direct. Cliffs: steps route through Cliffs.try_step — sheer faces
## (|level diff| > 1) block, and the unit slides along the edge instead
## of walking off (HTML's cgCliffBlocked / CLIFFDETECT).
## Static so SimHousing can drive migration/homestead walks with the same
## movement rules (WorkerAI yields to those states).
static func move_unit(gs: GameState, unit: Dictionary, target: Vector2,
		delta: float) -> bool:
	var pf = gs.get("pathfinder")
	# Jeremy 2026-10-04: food perk speed modifier (Bastard Rush etc.).
	var spd: float = float(unit.get("speed", 36.0)) \
		* SimFoodPerks.get_modifier(unit, "speed", gs.game_time) \
		* float(unit.get("age_move_mult", 1.0))  # Jeremy 2026-10-11: elders amble
	# Jeremy 2026-10-05: swimming is slower than walking.
	if bool(unit.get("swimming", false)):
		spd *= 0.55
	var before: Vector2 = unit.get("position", Vector2.ZERO)
	var arrived: bool
	if pf != null:
		arrived = (pf as SimPathfinder).move_routed(unit, target, spd, delta)
	else:
		arrived = _move_direct(gs, unit, target, delta)
	# Jeremy 2026-10-10 road wear: traffic degrades roads underfoot —
	# only when the unit actually moved (not idling, not swimming).
	var after: Vector2 = unit.get("position", Vector2.ZERO)
	if after != before and not bool(unit.get("swimming", false)):
		var wai = gs.get("worker_ai")
		if wai != null:
			(wai as WorkerAI).wear_road_at(after, WEAR_PER_SEC * delta)
	return arrived


## Straight-line steering fallback (no pathfinder: headless/tests).
## Jeremy 2026-10-05: Oblivion/Skyrim water rules — land NPCs steer
## around water (fleeing units may swim; naval jobs belong on water).
static func _move_direct(gs: GameState, unit: Dictionary, target: Vector2,
		delta: float) -> bool:
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	var to: Vector2 = target - pos
	var dist: float = to.length()
	var step: float = float(unit.get("speed", 30.0)) \
		* SimFoodPerks.get_modifier(unit, "speed", gs.game_time) \
		* float(unit.get("age_move_mult", 1.0)) * delta  # Jeremy 2026-10-11: elders amble
	if bool(unit.get("swimming", false)):
		step *= 0.55  # swimming is slower
	var avoid := WaterNav.unit_avoids_water(unit)
	if dist <= maxf(6.0, step):
		var np: Vector2 = Cliffs.try_step(gs.map_data, pos, to)
		if avoid:
			np = WaterNav.dry_step(gs.map_data, pos, np - pos)
		unit["position"] = np
		unit["moving"] = true
		unit["swimming"] = WaterNav.is_water_at(gs.map_data, np)
		return np.distance_squared_to(target) < 36.0
	var dir: Vector2 = to / dist
	# Jeremy 2026-10-10 visible road construction: foot traffic routes
	# around marked work zones (the crew working a zone is exempt).
	var wai = gs.get("worker_ai")
	if wai != null and dist > 80.0:
		dir = wai.deflect_around_workzones(pos, dir, unit)
	var np2: Vector2 = Cliffs.try_step(gs.map_data, pos, dir * step)
	if avoid:
		np2 = WaterNav.dry_step(gs.map_data, pos, np2 - pos)
	unit["position"] = np2
	unit["moving"] = true
	unit["swimming"] = WaterNav.is_water_at(gs.map_data, np2)
	return false


func _walk_to(unit: Dictionary, target: Vector2, delta: float) -> bool:
	return move_unit(_gs, unit, target, delta)


## Unemployed job-seek behavior (Jeremy 2026-10-04): the unit walks to
## the guild hall (GuildHiring sets unit["_seek_pos"] on its sweep) and
## waits there for assignment. Urges and daily life still run via the
## mind tick — this only drives the seek walk.
func _tick_unemployed(unit: Dictionary, delta: float) -> void:
	var seek: Vector2 = unit.get("_seek_pos", Vector2(-1, -1))
	if seek.x < 0.0:
		# No hall in range, or already waiting at one — idle in place.
		unit["work_state"] = "idle"
		unit["work_pose"] = null
		return
	unit["work_state"] = "to_seek"
	if _walk_to(unit, seek, delta):
		unit.erase("_seek_pos")
		unit["work_state"] = "idle"


## ---- Off-shift downtime (Jeremy 2026-10-04: NPCs "live their lives") ------
## The world calls tick_off_shift instead of tick_unit while the job is off
## shift (HTML offShiftUrge57 port — the Godot build used to freeze units
## in place with work_state "off_shift"). The plan is picked ONCE per
## off-shift (cheap); only the walk runs per tick:
##   rest:      energy < 32 — walk home (or the hall), catch a breather
##   socialize: social < 55 or mood < 55 — walk to the nearest inn /
##              restaurant, recover social with company
##   friend:    social < 55 and no inn in reach — walk to a nearby ally
##   home:      otherwise — drift home and relax (slow mood recovery)
## Recovery is a gentle nudge, not the sleep cycle — the mind's
## critical-urge overrides still own real sleep and meals.
const DOWNTIME_SOCIAL_TYPES := ["inn", "restaurant", "greasy_spoon",
	"salad_bar"]
const DOWNTIME_REST_ENERGY := 32.0
const DOWNTIME_SOCIAL_LOW := 55.0
const DOWNTIME_ARRIVE := 48.0
const DOWNTIME_INN_RANGE := 1500.0
const DOWNTIME_PAL_RANGE := 800.0


## One off-shift tick for a unit record. Called by the world (instead of
## tick_unit) while the unit's job is off shift.
func tick_off_shift(unit: Dictionary, delta: float) -> void:
	if not unit.get("alive", false):
		return
	# SimHousing drives migration / homestead / house-hunting walks.
	# SimNPCTravel owns a unit's long trip while it rides its own vehicle.
	if unit.has("_homestead") or unit.has("_buying_home") \
			or unit.has("_buying_vehicle") or unit.has("_ride"):
		return
	var _cm: Vector2 = unit.get("_country_move", Vector2(-1, -1))
	if _cm.x >= 0.0:
		return
	# Job seekers keep seeking (HTML offShiftUrge57: seekers are exempt).
	if unit.has("_seek_pos"):
		_tick_unemployed(unit, delta)
		return
	_ensure_fields(unit)
	var plan: Dictionary = unit.get("_downtime", {})
	if String(plan.get("plan", "")) == "celebrate" \
			and _festival_joy_town() != String(plan.get("town", "")):
		# The music stopped mid-off-shift — drop the stale plan so the
		# next tick re-picks (rest/socialize/home, not a dead party).
		unit.erase("_downtime")
		plan = {}
	if plan.is_empty() or String(plan.get("plan", "")) == "":
		plan = _downtime_pick(unit)
		unit["_downtime"] = plan
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var target: Vector2 = plan.get("target", up)
	if up.distance_to(target) > DOWNTIME_ARRIVE:
		_walk_to(unit, target, delta)
		up = unit.get("position", Vector2.ZERO)
	if up.distance_to(target) <= DOWNTIME_ARRIVE * 2.0:
		_downtime_recover(unit, String(plan.get("plan", "home")), delta)
		# Jeremy 2026-10-06: mark arrived resters — the world sync plays
		# IDLE (breathing) instead of walking in place at home.
		# Jeremy 2026-10-08: arrived celebrants dance at the plaza.
		if String(plan.get("plan", "")) == "celebrate":
			unit["work_pose"] = "dance"
		else:
			unit["work_pose"] = "rest"
	else:
		unit["work_pose"] = null


## Picks one downtime plan for this off-shift (HTML offShiftUrge57 order:
## rest beats drink beats chat beats idle).
func _downtime_pick(unit: Dictionary) -> Dictionary:
	var ur: Dictionary = _downtime_urges(unit)
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var faction: String = String(unit.get("faction", ""))
	var energy: float = float(ur.get("energy", 60.0))
	var social: float = float(ur.get("social", 60.0))
	var mood: float = float(ur.get("mood", 60.0))
	if energy < DOWNTIME_REST_ENERGY:
		return {"plan": "rest", "target": _rest_spot(unit)}
	# Jeremy 2026-10-08: festival joy — off-shift citizens join the party
	# at the plaza instead of the tavern (the ruler paid for pies AND
	# music). Rest still wins (tired people sleep); nobody is yanked off
	# duty, so the economy and the guard roster are untouched.
	var joy: String = _festival_joy_town()
	if joy != "":
		var plaza: Vector2 = _festival_plaza(unit, joy)
		if plaza.x >= 0.0:
			return {"plan": "celebrate", "town": joy, "target": plaza}
	if mood < DOWNTIME_SOCIAL_LOW or social < DOWNTIME_SOCIAL_LOW:
		var inn: Dictionary = _nearest_social_building(unit, faction)
		if not inn.is_empty():
			return {"plan": "socialize",
				"target": inn.get("position", up)}
	if social < DOWNTIME_SOCIAL_LOW:
		var pal: Dictionary = _nearest_ally(unit, faction)
		if not pal.is_empty():
			return {"plan": "friend", "target": pal.get("position", up)}
	return {"plan": "home", "target": _rest_spot(unit)}


## Lazy urge dict for downtime reads/writes (mirrors SimUrges defaults;
## the mind owns the authoritative dict when it runs).
func _downtime_urges(unit: Dictionary) -> Dictionary:
	var ur: Dictionary = unit.get("urges", {})
	if ur.is_empty():
		for urge: String in SimUrges.URGES:
			ur[urge] = 60.0
		unit["urges"] = ur
	return ur


## Rest spot: the unit's own home when it has one, else the nearest hall,
## else wherever they stand (HTML restSpot57: home, then hall).
func _rest_spot(unit: Dictionary) -> Vector2:
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var home: Dictionary = unit.get("home", {})
	if not home.is_empty() and home.get("alive", false):
		return home.get("position", up)
	var hall: Dictionary = _nearest_hall(unit)
	if not hall.is_empty():
		return hall.get("position", up)
	return up


## Jeremy 2026-10-08: the town currently inside the festival joy window,
## or "" when no festival is being celebrated (SimPolicies owns the rule).
func _festival_joy_town() -> String:
	if _gs.get("court_sys") == null:
		return ""
	var pol = _gs.court_sys.get("policies")
	if pol == null:
		return ""
	return String(pol.festival_joy_town())


## Festival plaza for a unit: a personal dance spot around the celebrating
## town's center (same faction, within party range). Vector2(-1, -1) when
## there's no party this unit can join. The golden-angle spread keeps the
## crowd from stacking on one pixel; the radius stays inside the bunting
## ring (FestivalFx POLE_R = 190).
func _festival_plaza(unit: Dictionary, joy_town: String) -> Vector2:
	var bad := Vector2(-1, -1)
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var faction: String = String(unit.get("faction", ""))
	var best: Dictionary = {}
	var best_d := DOWNTIME_INN_RANGE
	for tid in _gs.towns.keys():
		var t: Dictionary = _gs.towns[tid]
		if String(t.get("name", "")) != joy_town:
			continue
		if String(t.get("faction", "")) != faction:
			continue
		var d: float = up.distance_to(t.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = t
	if best.is_empty():
		return bad
	var tp: Vector2 = best.get("position", Vector2.ZERO)
	var uid: int = int(unit.get("id", 0))
	var ang: float = float(uid) * 2.39996
	var rad: float = 40.0 + float(abs(uid * 37) % 90)
	return tp + Vector2(cos(ang), sin(ang)) * rad


## Nearest completed inn/restaurant of the faction (HTML drinkSpot57:
## tavern/inn/restaurant — Godot has no tavern type).
func _nearest_social_building(unit: Dictionary, faction: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if not String(b.get("type", "")) in DOWNTIME_SOCIAL_TYPES:
			continue
		var d: float = (b.get("position", Vector2.ZERO) as Vector2).distance_to(up)
		if d < best_d and d <= DOWNTIME_INN_RANGE:
			best_d = d
			best = b
	return best


## Nearest living ally (HTML s10FindFriend): company for the evening.
func _nearest_ally(unit: Dictionary, faction: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var uid: int = int(unit.get("id", 0))
	for other: Dictionary in _gs.units:
		if not other.get("alive", false):
			continue
		if int(other.get("id", 0)) == uid:
			continue
		if String(other.get("faction", "")) != faction:
			continue
		var d: float = (other.get("position", Vector2.ZERO) as Vector2).distance_to(up)
		if d < best_d and d <= DOWNTIME_PAL_RANGE:
			best_d = d
			best = other
	return best


## True when a living ally is close enough for company (HTML social rate
## doubles with company nearby — mirrors SimUrges._satisfy_social).
func _has_company(unit: Dictionary) -> bool:
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var faction: String = String(unit.get("faction", ""))
	var uid: int = int(unit.get("id", 0))
	for other: Dictionary in _gs.units:
		if not other.get("alive", false):
			continue
		if int(other.get("id", 0)) == uid:
			continue
		if String(other.get("faction", "")) != faction:
			continue
		if up.distance_to(other.get("position", Vector2.ZERO)) <= 200.0:
			return true
	return false


## Gentle urge recovery at the downtime destination.
func _downtime_recover(unit: Dictionary, plan: String, delta: float) -> void:
	var ur: Dictionary = _downtime_urges(unit)
	match plan:
		"rest":
			ur["energy"] = clampf(float(ur.get("energy", 60.0))
				+ 4.0 * delta, 0.0, 100.0)
		"socialize":
			var rate := 2.0
			if _has_company(unit):
				rate = 8.0
			ur["social"] = clampf(float(ur.get("social", 60.0))
				+ rate * delta, 0.0, 100.0)
		"friend":
			# The pal may have wandered off — only chatting counts.
			var rate := 2.0
			if _has_company(unit):
				rate = 6.0
			ur["social"] = clampf(float(ur.get("social", 60.0))
				+ rate * delta, 0.0, 100.0)
		"celebrate":
			# Jeremy 2026-10-08: a festival party is the best social venue
			# in the game — mood and social both rise, faster with company.
			var prate := 3.0
			if _has_company(unit):
				prate = 8.0
			ur["social"] = clampf(float(ur.get("social", 60.0))
				+ prate * delta, 0.0, 100.0)
			ur["mood"] = clampf(float(ur.get("mood", 60.0))
				+ 3.0 * delta, 0.0, 100.0)
		_:
			ur["mood"] = clampf(float(ur.get("mood", 60.0))
				+ 2.0 * delta, 0.0, 100.0)


## Chooses the next task for an idle unit based on its job.
## hour is 0-24 (only used where documented).
func _pick_task(unit: Dictionary, buildings: SimBuildings, hour: float) -> void:
	# R34 idle retry backoff: a full task scan that found nothing is not
	# re-run for IDLE_RETRY_TICKS of this unit's own AI slices. The world
	# rarely changes between two consecutive slices; without this, idle
	# units (doctors with no patients, builders with no blueprints, ...)
	# paid the full scan cost every slice.
	if int(unit.get("_ai_ticks", 0)) < int(unit.get("_pick_retry_at", 0)):
		return
	_pick_task_inner(unit, buildings, hour)
	if String(unit.get("work_state", "")) == "idle":
		unit["_pick_retry_at"] = int(unit.get("_ai_ticks", 0)) + IDLE_RETRY_TICKS
	else:
		unit.erase("_pick_retry_at")


func _pick_task_inner(unit: Dictionary, buildings: SimBuildings, hour: float) -> void:
	var job: String = String(unit.get("job", "worker"))
	var faction: String = String(unit.get("faction", ""))
	# Jeremy 2026-10-05: siege-owned civilians (SimSiege) keep their
	# hiding / brave-repair assignments — never re-task them mid-attack.
	if bool(unit.get("_siege_hide", false)) \
			or bool(unit.get("_siege_repair", false)):
		return
	# Station jobs (shop staff, desk officers): walk to the workplace and
	# work the shift there. On-shift is guaranteed by tick_unit. Only units
	# with a hire-recorded station post are routed here.
	var st: Dictionary = unit.get("station", {})
	if not st.is_empty() and JobDefs.is_station_job(job):
		if _assign_station(unit, job):
			return
		unit["work_state"] = "idle"
		return
	# If already carrying something (e.g. site depleted mid-trip), haul it.
	if not (unit.get("carrying", {}) as Dictionary).is_empty():
		_assign_dropoff(unit)
		return
	match job:
		"builder":
			if _assign_build(unit, buildings):
				return
			if _assign_repair(unit):
				return
		"doctor":
			if _assign_patient(unit):
				return
		"firefighter":
			return  # SimDisasters.tick_firefighter drives them; hold position
		"farmer":
			if _assign_farm(unit):
				return
		"fisher":
			# Fishing (fix79 fisher port): work the lake, not the farm.
			if _assign_fish(unit):
				return
			# No stocked lake in reach — fall back to farm work (old behavior).
			if _assign_farm(unit):
				return
		"hunter":
			if _assign_hunt(unit):
				return
		"roadbuilder":
			unit["work_state"] = "to_road"
			return
		"worker":
			# Generalist: faction resource pressure decides (HTML
			# factionWorkPriority) — gather the scarcest resource, or help
			# build when the faction is stocked (wood>80, gold>60).
			if _faction_priority(faction) == "build":
				if _assign_build(unit, buildings):
					return
			if _assign_gather_priority(unit, faction):
				return
			if _assign_build(unit, buildings):
				return
		_:
			if _assign_gather(unit, job):
				return
			# Generalist fallback: help build when nothing to gather.
			if _assign_build(unit, buildings):
				return
	unit["work_state"] = "idle"


## Nearest work site of the right kind with remaining amount.
func _assign_gather(unit: Dictionary, job: String) -> bool:
	var want: String = JobDefs.gather_resource(job)
	var kinds: Array[String] = []
	match want:
		"wood":
			return _assign_lumber(unit)
		"oil":
			# Jeremy 2026-10-05: oil rocks are gone — oil comes from pumps.
			# Miners work gold veins.
			kinds = ["gold_vein"]
		"gold":
			kinds = ["gold_vein"]
		"food":
			kinds = ["bush"]
		_:
			kinds = ["tree", "rock", "gold_vein", "bush"]
	var site: Dictionary = _nearest_site(unit, kinds)
	if site.is_empty():
		return false
	unit["work_site"] = int(site["id"])
	unit["work_target_pos"] = site["position"]
	unit["work_state"] = "to_resource"
	return true


## Jeremy 2026-10-05: lumber camps (Rise of Nations style). When the
## faction has a completed lumber camp, woodcutters work trees inside the
## camp's coverage radius (nearest such tree to the worker); otherwise they
## fall back to the nearest tree anywhere. The hauled wood goes to the
## camp via the normal dropoff path (see _nearest_camp).
func _assign_lumber(unit: Dictionary) -> bool:
	var faction: String = String(unit.get("faction", ""))
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)) or not bool(b.get("complete", false)):
			continue
		if String(b.get("type", "")) != "lumber_camp":
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var bp: Vector2 = b.get("position", Vector2.ZERO)
		var site: Dictionary = _nearest_site_at(
			bp, ["tree"], SimBuildings.LUMBER_CAMP_RADIUS)
		if site.is_empty():
			continue
		var d: float = up.distance_to(site.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = site
	var site: Dictionary = best
	if site.is_empty():
		site = _nearest_site(unit, ["tree"])
	if site.is_empty():
		return false
	unit["work_site"] = int(site["id"])
	unit["work_target_pos"] = site["position"]
	unit["work_state"] = "to_resource"
	return true


## Farmers carry seeds to empty plot bins. When the faction ledger is dry,
## bootstrap from the faction's own seedshops (5 gold each, HTML price)
## before giving up — the shop buy path was dead, so seed-dry factions
## stalled their farms forever despite built shops and full coffers.
func _top_up_seed_bins(unit: Dictionary, faction: String) -> void:
	if _gs.get("farming") == null or _gs.get("resources") == null:
		return
	var best: Dictionary = {}
	var best_d := INF
	for p: Dictionary in _gs.farming.plots:
		if String(p.get("faction", "")) != faction:
			continue
		if int(p.get("seed_bin", 0)) > 0:
			continue
		var d: float = (unit.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(p.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = p
	if best.is_empty():
		return
	if _gs.resources.get_amount(faction, "seeds") < 1.0:
		_gs.farming.ensure_seed_supply(faction, 4)
		if _gs.resources.get_amount(faction, "seeds") < 1.0:
			return
	_gs.farming.fill_seed_bin(best, 4)


## Farm plot chore execution: walk to the chore tile, apply plant/water/
## harvest, then look for the next chore.
func _do_plot_chore(unit: Dictionary, delta: float) -> void:
	if _gs.get("farming") == null:
		unit["work_state"] = "idle"
		return
	var plot: Dictionary = _gs.farming.get_plot(int(unit.get("work_plot_id", -1)))
	if plot.is_empty():
		unit["work_state"] = "idle"
		return
	var chore: Dictionary = _gs.farming.plot_chore(plot)
	if chore.is_empty():
		unit["work_state"] = "idle"
		return
	var tiles: Array = plot.get("tiles", [])
	var tile: Dictionary = tiles[int(chore.get("tile", 0))]
	var tpos: Vector2 = tile.get("pos", plot.get("position", Vector2.ZERO))
	if _walk_to(unit, tpos, delta):
		var action: String = String(chore.get("action", ""))
		match action:
			"plant":
				_gs.farming.plant(plot, int(chore.get("tile", 0)))
			"water":
				_gs.farming.water(plot, int(chore.get("tile", 0)))
			"harvest":
				_gs.farming.harvest(plot, int(chore.get("tile", 0)))
		unit["work_state"] = "idle"  # re-pick: next chore or other work


## Farmers work farm plots first (plant/water/harvest chores), then fall
## back to the nearest completed food building (infinite food source).
func _assign_farm(unit: Dictionary) -> bool:
	var faction: String = String(unit.get("faction", ""))
	# Prefer real farm plots with pending chores (farming port).
	# Jeremy 2026-10-05: labor market — a farmer hired onto a plot works
	# their own land first (SimFarming.nearest_work_plot prefer_id).
	if _gs.get("farming") != null:
		var plot: Dictionary = _gs.farming.nearest_work_plot(faction,
			unit.get("position", Vector2.ZERO),
			int(unit.get("_farm_plot_id", -1)))
		if not plot.is_empty():
			unit["work_plot_id"] = int(plot.get("id", -1))
			unit["work_target_pos"] = plot.get("position", Vector2.ZERO)
			unit["work_state"] = "to_plot"
			return true
		# No chores anywhere: top up an empty seed bin if the ledger has seeds.
		_top_up_seed_bins(unit, faction)
	var best: Dictionary = {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if not String(b.get("type", "")) in SimBuildings.FOOD_BUILDINGS:
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var d: float = (unit.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	if best.is_empty():
		# No farm building? Tend livestock at the nearest barn/coop.
		if _assign_tend(unit, faction):
			return true
		return _assign_gather(unit, "worker")  # no farm? forage like a worker
	unit["work_site"] = -1
	unit["work_target_pos"] = best["position"]
	unit["work_state"] = "to_resource"
	unit["_farm_building"] = int(best["id"])
	return true


## Fisher: nearest stocked lake (fix79 fisher port — HTML: the fisher's
## gatherType is 'fish', gatherTarget is the lake). The fisher casts from
## the shore, not the middle of the water. Returns false when no lake
## holds fish (caller falls back to farm work).
const FISH_TICK := 1.1      # HTML 'fish' gather cadence, seconds per cast
const FISH_CATCH := 8.0     # HTML: take = min(8, lake.fish)
const FISH_RANGE := 4000.0  # fish the nearest lake, not one across the map
## Jeremy 2026-10-07: the Stinky Gizmundo — a rare, legendary, eye-wateringly
## smelly fish that lucky fishers occasionally hook instead of a normal haul.
## Counts as a big meal when hauled home.
const GIZMUNDO_CHANCE := 0.02
const GIZMUNDO_FOOD := 12.0
## Game day of the last Gizmundo Gazette story (transient throttle — a lucky
## streak never spams the newspaper; worst case after a load is one extra).
var _gizmundo_story_day := -1

func _assign_fish(unit: Dictionary) -> bool:
	var hydro = _gs.get("hydro")
	if hydro == null:
		return false
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d := INF
	for b in hydro.bodies():
		if not (b is Dictionary):
			continue
		if String(b.get("kind", "")) != "lake":
			continue
		if float(b.get("fish", 0.0)) <= 0.0:
			continue
		var d: float = up.distance_to(b.get("pos", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	if best.is_empty() or best_d > FISH_RANGE:
		return false
	unit["_lake"] = best  # live dict ref into the hydro body list
	# Stop at the shore: the fisher casts from the bank (HTML moved to
	# lake.x/lake.y, but wading to the middle is neither sane nor needed).
	var lp: Vector2 = best.get("pos", up)
	var shore: Vector2 = up - lp
	if shore.length() > 0.01:
		lp = lp + shore.normalized() * float(best.get("radius", 55.0)) * 0.8
	unit["work_target_pos"] = lp
	unit["work_state"] = "to_lake"
	unit["_fish_timer"] = 0.0
	return true


## Fisher work tick (fix79 'fish' gatherType port): timed casts pull up to
## 8 fish per cycle from the lake stock; the catch lands at the fisher's
## feet as a food pickup (the walk-over magnet collects it on the next
## tick). No rod = 25% catch + the tool supply flow (toolTake54 parity via
## _tool_mult, which may re-route the fisher to a shop).
func _do_fish(unit: Dictionary, delta: float) -> void:
	var body: Dictionary = unit.get("_lake", {})
	if body.is_empty() or float(body.get("fish", 0.0)) <= 0.0:
		# Lake fished out (HTML: "No more fish.") — re-pick work.
		unit["work_state"] = "idle"
		unit["work_pose"] = null
		return
	var cap: float = float(unit.get("carry_cap", CARRY_CAP))
	var carrying: Dictionary = unit.get("carrying", {})
	if float(carrying.get("food", 0.0)) >= cap:
		unit["work_pose"] = null
		_assign_dropoff(unit)
		return
	unit["_fish_timer"] = float(unit.get("_fish_timer", 0.0)) + delta
	if unit["_fish_timer"] < FISH_TICK:
		return
	unit["_fish_timer"] = 0.0
	var take: float = maxf(1.0, minf(FISH_CATCH, float(body.get("fish", 0.0)))
		* _tool_mult(unit, "fisher"))
	body["fish"] = float(body.get("fish", 0.0)) - take
	# HTML verbatim: the catch lands at the fisher's feet as a pickup.
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	if _roll_gizmundo(randf()):
		# Jeremy 2026-10-07: the lucky cast hooks a Stinky Gizmundo — the
		# legendary smelly fish replaces the normal haul for this cast.
		_hook_gizmundo(unit, up)
	else:
		_gs.add_pickup({
			"kind": "food",
			"amount": take,
			"position": up + Vector2(0, -10),
		})
	if String(unit.get("work_state", "")) == "fishing" \
			and float(body.get("fish", 0.0)) <= 0.0:
		# Fished out — but never clobber a tool-supply shop trip the
		# _tool_mult above may have started.
		unit["work_state"] = "idle"
		unit["work_pose"] = null


## Test seam for the Gizmundo roll: a pure function of the drawn value so
## suites stay deterministic (no RNG flake around a 2% chance).
func _roll_gizmundo(r: float) -> bool:
	return r < GIZMUNDO_CHANCE


## A fisher hooks the legendary Stinky Gizmundo: a special ground pickup
## (worth a big meal) plus a throttled Gazette story (one per day max —
## a lucky streak never spams the newspaper).
func _hook_gizmundo(unit: Dictionary, up: Vector2) -> void:
	_gs.add_pickup({
		"kind": "gizmundo",
		"amount": GIZMUNDO_FOOD,
		"position": up + Vector2(0, -10),
	})
	var today: int = _gs.day_number
	if _gizmundo_story_day == today:
		return
	_gizmundo_story_day = today
	var fname := String(unit.get("name", "A lucky fisher"))
	var headline := "STINKY GIZMUNDO!"
	var body := "%s hauled a Stinky Gizmundo from the deep, a legendary, eye-wateringly smelly fish. The taverns will sing of this catch, from a safe distance." % fname
	if _gs.get("court_sys") != null:
		# Chronicle archive + bus (a direct gazette_story.emit only
		# reaches the toast path, per the news-desk standing rule).
		_gs.court_sys.publish_story(headline, body, "news")
	else:
		_gs.bus.gazette_story.emit({
			"day": today, "headline": headline, "body": body, "kind": "news",
		})


## Hunter: find the nearest wild animal and go kill it for meat
## (HTML: gatherTarget = animal, 8 dmg per hit, meat pickups on kill).
func _assign_hunt(unit: Dictionary) -> bool:
	if _gs.get("animals") == null:
		return false
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	var prey: Dictionary = _gs.animals.nearest_wild(pos, 1200.0)
	if prey.is_empty():
		return false
	unit["hunt_prey_id"] = int(prey.get("id", -1))
	unit["work_target_pos"] = prey.get("position", pos)
	unit["work_state"] = "to_prey"
	return true


## Hunter attack tick: chase the prey, strike in range (HTML: 8 dmg per
## gatherTimer cycle). On kill, meat goes straight into carrying.
const HUNT_DMG := 8.0
const HUNT_RANGE := 30.0
const HUNT_CD := 1.0

func _do_hunt(unit: Dictionary, delta: float) -> void:
	if _gs.get("animals") == null:
		unit["work_state"] = "idle"
		return
	var prey_id: int = int(unit.get("hunt_prey_id", -1))
	var prey: Dictionary = {}
	for an in _gs.animals.wild:
		if int(an.get("id", -2)) == prey_id:
			prey = an
			break
	if prey.is_empty() or not bool(prey.get("alive", false)):
		# Prey gone — find another, or haul meat home.
		unit.erase("hunt_prey_id")
		if not (unit.get("carrying", {}) as Dictionary).is_empty():
			_assign_dropoff(unit)
		elif not _assign_hunt(unit):
			unit["work_state"] = "idle"
		return
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var pp: Vector2 = prey.get("position", up)
	if up.distance_to(pp) > HUNT_RANGE:
		# Prey moved — chase it.
		unit["work_target_pos"] = pp
		unit["work_state"] = "to_prey"
		return
	unit["work_pose"] = "attack"
	var cd: float = float(unit.get("_hunt_cd", 0.0)) - delta
	if cd <= 0.0:
		cd = HUNT_CD
		var meat: float = _gs.animals.damage_wild(prey, HUNT_DMG)
		if meat > 0.0:
			var carrying: Dictionary = unit.get("carrying", {})
			carrying["food"] = float(carrying.get("food", 0.0)) + meat
			unit["carrying"] = carrying
			unit.erase("hunt_prey_id")
			unit["work_pose"] = null
			_assign_dropoff(unit)
			return
	unit["_hunt_cd"] = cd


## Farmer tends livestock: walks to the nearest barn/coop with animals and
## feeds them (hunger topped up, +25% yield bonus flag for the day).
func _assign_tend(unit: Dictionary, faction: String) -> bool:
	if _gs.get("animals") == null:
		return false
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if not String(b.get("type", "")) in ["barn", "coop"]:
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var d: float = up.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	if best.is_empty():
		return false
	unit["work_building"] = int(best.get("id", -1))
	unit["work_target_pos"] = best.get("position", Vector2.ZERO)
	unit["work_state"] = "to_tend"
	return true


## Tending tick: feed nearby livestock, mark them tended for a yield bonus.
func _do_tend(unit: Dictionary, delta: float) -> void:
	if _gs.get("animals") == null:
		unit["work_state"] = "idle"
		return
	unit["work_pose"] = "work"
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var tended := 0
	if _gs.get("farming") != null:
		for p in _gs.farming.plots:
			if not (p is Dictionary):
				continue
			if String(p.get("faction", "")) != String(unit.get("faction", "")):
				continue
			for an in p.get("animals", []):
				if not (an is Dictionary):
					continue
				if not bool(an.get("alive", false)):
					continue
				var ap: Vector2 = an.get("position", up)
				if up.distance_to(ap) < 200.0:
					an["hunger"] = 100.0
					an["tended"] = true
					tended += 1
	unit["_tend_t"] = float(unit.get("_tend_t", 0.0)) + delta
	# Tend for a while, then move on.
	if float(unit.get("_tend_t", 0.0)) > 20.0 or tended == 0:
		unit.erase("_tend_t")
		unit["work_pose"] = null
		unit["work_state"] = "idle"


func _assign_dropoff(unit: Dictionary) -> void:
	# Jeremy 2026-10-04: resource camps first (HTML parity), town hall fallback.
	var camp: Dictionary = _nearest_camp(unit)
	if not camp.is_empty():
		unit["work_target_pos"] = camp["position"]
		unit["work_state"] = "to_dropoff"
		return
	var hall: Dictionary = _nearest_hall(unit)
	if hall.is_empty():
		_do_dropoff(unit)  # nowhere to haul — credit directly, don't strand
		return
	unit["work_target_pos"] = hall["position"]
	unit["work_state"] = "to_dropoff"


## Nearest completed resource camp of the unit's faction, or {}.
## Jeremy 2026-10-05: lumber camps are wood dropoffs too — wood carriers
## prefer the nearest lumber camp, then resource camps; other carriers use
## whichever camp is nearest (both credit faction inventory on dropoff).
func _nearest_camp(unit: Dictionary) -> Dictionary:
	var faction: String = String(unit.get("faction", ""))
	var carries_wood: bool = float(
		(unit.get("carrying", {}) as Dictionary).get("wood", 0.0)) > 0.0
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var best_lumber: Dictionary = {}
	var best_lumber_d := INF
	var best_camp: Dictionary = {}
	var best_camp_d := INF
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var bt: String = String(b.get("type", ""))
		if bt != "resource_camp" and bt != "lumber_camp":
			continue
		var d: float = up.distance_to(b.get("position", Vector2.ZERO))
		if bt == "lumber_camp":
			if d < best_lumber_d:
				best_lumber_d = d
				best_lumber = b
		elif d < best_camp_d:
			best_camp_d = d
			best_camp = b
	if carries_wood and not best_lumber.is_empty():
		return best_lumber
	if not best_camp.is_empty():
		return best_camp
	return best_lumber


func _assign_build(unit: Dictionary, _buildings: SimBuildings) -> bool:
	var faction: String = String(unit.get("faction", ""))
	var best: Dictionary = {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var d: float = (unit.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	if best.is_empty():
		return false
	unit["work_building"] = int(best["id"])
	unit["work_target_pos"] = best["position"]
	unit["work_state"] = "to_build"
	return true


func _assign_repair(unit: Dictionary) -> bool:
	var faction: String = String(unit.get("faction", ""))
	var best: Dictionary = {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if float(b.get("hp", 1.0)) >= float(b.get("max_hp", 1.0)):
			continue
		var d: float = (unit.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	if best.is_empty():
		return false
	unit["work_building"] = int(best["id"])
	unit["work_target_pos"] = best["position"]
	unit["work_state"] = "to_repair"
	return true


## Doctors seek the most injured ally of their faction.
func _assign_patient(unit: Dictionary) -> bool:
	var faction: String = String(unit.get("faction", ""))
	var best: Dictionary = {}
	var worst := 1.0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if int(u.get("id", 0)) == int(unit.get("id", 0)):
			continue
		var frac: float = float(u.get("hp", 100.0)) / maxf(1.0, float(u.get("max_hp", 100.0)))
		if frac < worst:
			worst = frac
			best = u
	if best.is_empty() or worst >= 0.999:
		return false
	unit["work_building"] = int(best["id"])  # reuse field: target unit id
	unit["work_target_pos"] = best["position"]
	unit["work_state"] = "to_patient"
	return true


func _site_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / SITE_GRID_CELL)),
		int(floor(pos.y / SITE_GRID_CELL)))


## Incrementally indexes new work sites into the grid. O(new sites);
## O(1) when nothing changed. A version bump (setup / save load replaced
## the array wholesale) or a shrink triggers a full rebuild — the grid can
## never hold orphaned records.
func _sync_site_grid() -> void:
	var sites: Array = _gs.work_sites
	var n: int = sites.size()
	var ver: int = _gs.site_cache_version
	if n == _site_grid_n and ver == _site_grid_ver:
		return
	# Any grid change can turn a cached "no match" into a hit.
	_site_nomatch.clear()
	if ver != _site_grid_ver or n < _site_grid_n:
		_site_grid.clear()
		_site_grid_n = 0
		_site_grid_min = Vector2i.ZERO
		_site_grid_max = Vector2i.ZERO
		_site_grid_ver = ver
	for i in range(_site_grid_n, n):
		var s: Dictionary = sites[i]
		var c := _site_cell(s.get("position", Vector2.ZERO))
		if _site_grid.has(c):
			(_site_grid[c] as Array).append(s)
		else:
			_site_grid[c] = [s]
			if _site_grid.size() == 1:
				_site_grid_min = c
				_site_grid_max = c
			else:
				_site_grid_min = Vector2i(
					mini(_site_grid_min.x, c.x), mini(_site_grid_min.y, c.y))
				_site_grid_max = Vector2i(
					maxi(_site_grid_max.x, c.x), maxi(_site_grid_max.y, c.y))
	_site_grid_n = n
	_site_grid_ver = ver


## Nearest work site of the right kind with remaining amount.
## Grid-accelerated: expanding rings from the unit's cell. After scanning
## ring r, ring r+1's closest possible point is r*CELL away, so when
## best_d <= r*CELL nothing farther can win — the TRUE nearest, identical
## to the old full scan. Ties break by lowest site id, matching the old
## first-match array order (ids are assigned in append order).
func _nearest_site(unit: Dictionary, kinds: Array[String]) -> Dictionary:
	_sync_site_grid()
	if _site_grid.is_empty():
		return {}
	# Miss cache: depletion can never turn a miss into a hit, and any
	# grid change clears this cache — so a cached miss stays correct.
	var sig := "|".join(kinds)
	if _site_nomatch.has(sig):
		return {}
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	var cc := _site_cell(pos)
	var best: Dictionary = {}
	var best_d := INF
	var best_id := 0
	# Farthest ring that can hold a site (covers the grid bounding box).
	var max_ring: int = maxi(
		maxi(absi(cc.x - _site_grid_min.x), absi(cc.x - _site_grid_max.x)),
		maxi(absi(cc.y - _site_grid_min.y), absi(cc.y - _site_grid_max.y)))
	var ring := 0
	while ring <= max_ring:
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var cell_sites: Array = _site_grid.get(
					cc + Vector2i(dx, dy), [])
				for s in cell_sites:
					var sd: Dictionary = s
					if float(sd.get("amount", 0.0)) <= 0.0:
						continue
					if not String(sd.get("kind", "")) in kinds:
						continue
					var d: float = pos.distance_to(
						sd.get("position", Vector2.ZERO))
					var sid := int(sd.get("id", 0))
					if d < best_d or (d == best_d and sid < best_id):
						best_d = d
						best = sd
						best_id = sid
		if best_d <= float(ring) * SITE_GRID_CELL:
			break
		ring += 1
	if best.is_empty():
		_site_nomatch[sig] = true
	return best


## Jeremy 2026-10-05: grid query centered on an arbitrary position with a
## hard max distance — lumber camps search for trees inside their coverage
## radius. Mirrors _nearest_site (same ring walk, kind + amount filters,
## lowest-id tie-break); the ring walk stops once rings exceed max_dist.
func _nearest_site_at(pos: Vector2, kinds: Array[String],
		max_dist: float) -> Dictionary:
	_sync_site_grid()
	if _site_grid.is_empty():
		return {}
	var cc := _site_cell(pos)
	var sig := "at|%d,%d|%d|%s" % [cc.x, cc.y, int(max_dist), "|".join(kinds)]
	if _site_nomatch.has(sig):
		return {}
	var best: Dictionary = {}
	var best_d := INF
	var best_id := 0
	var max_ring: int = int(ceil(max_dist / SITE_GRID_CELL)) + 1
	var ring := 0
	while ring <= max_ring:
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var cell_sites: Array = _site_grid.get(
					cc + Vector2i(dx, dy), [])
				for s in cell_sites:
					var sd: Dictionary = s
					if float(sd.get("amount", 0.0)) <= 0.0:
						continue
					if not String(sd.get("kind", "")) in kinds:
						continue
					var d: float = pos.distance_to(
						sd.get("position", Vector2.ZERO))
					if d > max_dist:
						continue
					var sid := int(sd.get("id", 0))
					if d < best_d or (d == best_d and sid < best_id):
						best_d = d
						best = sd
						best_id = sid
		if best_d <= float(ring) * SITE_GRID_CELL:
			break
		ring += 1
	if best.is_empty():
		_site_nomatch[sig] = true
	return best


func _nearest_hall(unit: Dictionary) -> Dictionary:
	var faction: String = String(unit.get("faction", ""))
	var best: Dictionary = {}
	var best_d := INF
	var pos: Vector2 = unit.get("position", Vector2.ZERO)
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		var bt: String = String(b.get("type", ""))
		if bt != "town_hall" and bt != "hall":
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var d: float = pos.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	return best


## Gathering tick: fill the carry load from the site (or farm building).
## Jeremy 2026-10-04: tool factor for a job. Units working without their
## job's tool (miner->pickaxe, woodcutter->axe, fisher->fishing rod,
## farmer->hoe, builder->hammer) produce at 25% (fix79 toolTake54 port)
## and are routed into the SimPetitions supply flow: walk to the nearest
## shop to buy one, or petition the adviser for a shop when none exists.
## No-op when the petition system isn't wired (bare tests).
func _tool_mult(unit: Dictionary, job: String) -> float:
	var need: String = SimPetitions.tool_for_job(job)
	if need == "":
		return 1.0
	if SimPetitions.unit_has_tool(unit, need):
		return 1.0
	var pet = _gs.get("petitions")
	if pet != null:
		pet.try_supply_tool(unit)
	return SimPetitions.NO_TOOL_YIELD_MULT


func _do_gather(unit: Dictionary, delta: float) -> void:
	var job: String = String(unit.get("job", "worker"))
	# Jeremy 2026-10-11: workers level their trade by working — 1 XP per
	# 5s of active gathering; skilled hands gather more.
	var _wskill := SimSkills.skill_for_job(job)
	if _wskill != "":
		SimSkills.grant_tick(_gs, unit, _wskill, delta)
	var res: String = JobDefs.gather_resource(job)
	if res == "":
		res = "wood"
	# The site kind decides the actual resource (a miner on a gold vein
	# hauls gold, not stone).
	# Jeremy 2026-10-04 perf: fetch the site ONCE. The old code ran the
	# linear get_work_site scan up to 4x per gatherer per tick (two header
	# lookups, one pre-deplete check, one inside deplete_site). The
	# Dictionary is the live record, so mutating it below is exactly what
	# deplete_site did.
	var site_id: int = int(unit.get("work_site", -1))
	var site: Dictionary = _gs.get_work_site(site_id) if site_id >= 0 else {}
	if not site.is_empty():
		res = String(SITE_RESOURCE.get(String(site.get("kind", "tree")), res))
	# Zoning: gathering at a site/farm inside an industrial zone of the
	# unit's faction is 25% faster.
	var faction: String = String(unit.get("faction", ""))
	var work_pos: Vector2 = unit.get("position", Vector2.ZERO)
	if site_id >= 0:
		if not site.is_empty():
			work_pos = site.get("position", work_pos)
	elif unit.has("_farm_building"):
		var _fb: Dictionary = _building_by_id(int(unit.get("_farm_building", -1)))
		if not _fb.is_empty():
			work_pos = _fb.get("position", work_pos)
	var prod_mult := 1.0
	if _gs.zoning != null:
		prod_mult = _gs.zoning.production_mult_at(work_pos, faction)
	# Policies: strikes slow all work (HTML govWorkMult parity).
	if _gs.get("court_sys") != null and _gs.court_sys.get("policies") != null:
		prod_mult *= _gs.court_sys.policies.work_mult()
	# Jeremy 2026-10-04: food perk work modifier (Greasy Grind etc.).
	prod_mult *= SimFoodPerks.get_modifier(unit, "work", _gs.game_time)
	# Jeremy 2026-10-07: Baron von Foam's party — drunk (or hungover)
	# workers are slow workers. Floor at 40% so blackout drunks still
	# trickle home eventually (no stuck haulers).
	prod_mult *= DisasterSim.drunk_work_mult(unit)
	var cap: float = float(unit.get("carry_cap", CARRY_CAP))
	var carrying: Dictionary = unit["carrying"]
	var have: float = float(carrying.get(res, 0.0))
	if have >= cap:
		_assign_dropoff(unit)
		return
	# Jeremy 2026-10-04: tools — working without the job's tool yields 25%
	# (fix79 toolTake54 port) and kicks off the buy/petition supply flow.
	# The penalty shapes the RATE, before clamping to the remaining
	# headroom: applied after the clamp, the take would shrink with the
	# headroom and the load would never fill (Zeno) — the unit would gather
	# forever and never haul back. HTML toolTake54 always yields >= 1.
	var take: float = minf(GATHER_RATE * prod_mult * _tool_mult(unit, job) * delta,
		cap - have)
	if _wskill != "":
		take *= SimSkills.yield_mult(unit, _wskill)
	# Farm buildings are infinite sources. Farmhouses (upgraded farms)
	# gather 50% faster.
	if job == "farmer" or site_id < 0:
		if job == "farmer" and unit.has("_farm_building"):
			var fb: Dictionary = _building_by_id(int(unit.get("_farm_building", -1)))
			var rate: float = GATHER_RATE * prod_mult
			if String(fb.get("type", "")) == "farmhouse":
				rate *= SimBuildings.FARMHOUSE_BONUS
			# Tool penalty shapes the rate (see above) — never the clamped
			# take, or the load would never fill.
			take = minf(rate * _tool_mult(unit, job) * delta, cap - have)
			if _wskill != "":
				take *= SimSkills.yield_mult(unit, _wskill)
			carrying[res] = have + take
			unit["carrying"] = carrying
			return
		# No site and not a farmer: nothing to gather.
		unit["work_state"] = "idle"
		return
	var site_amount: float = float(site.get("amount", 0.0))
	if site.is_empty() or site_amount <= 0.0:
		# Site gone — haul what we have, or go idle.
		if have > 0.0:
			_assign_dropoff(unit)
		else:
			unit["work_state"] = "idle"
		return
	# Jeremy 2026-10-05: trees don't trickle wood into inventories. Chopping
	# damages the tree (it shakes — see MapProp.set_chopping); when chopped
	# through, the tree falls and bursts into wood pickups that the chopper
	# collects by walking over them, then hauls to camp like any other load.
	if String(site.get("kind", "tree")) == "tree":
		var dmg: float = GATHER_RATE * prod_mult * _tool_mult(unit, job) * delta
		site["amount"] = maxf(0.0, site_amount - dmg)
		if float(site["amount"]) <= 0.0:
			_fell_tree(site, unit)
		return
	# Inline deplete_site on the already-fetched record (identical math:
	# take >= 0 by construction, so maxf(0, take) == take).
	var got: float = minf(take, site_amount)
	site["amount"] = site_amount - got
	carrying[res] = have + got
	unit["carrying"] = carrying


## Jeremy 2026-10-05: a chopped-through tree falls and bursts into wood
## pickups scattered around the stump. The full yield bursts out — nothing
## was trickled during chopping, so nothing is double-counted.
func _fell_tree(site: Dictionary, unit: Dictionary) -> void:
	site["felled"] = true
	var pos: Vector2 = site.get("position", Vector2.ZERO)
	# Burst the tree's full yield (stored at seed; falls back to the
	# standard yield for old saves / test sites). Nothing was trickled
	# during chopping, so nothing is double-counted.
	var total: float = float(site.get("yield", TREE_WOOD_YIELD))
	var n := maxi(1, int(round(total / PICKUP_WOOD)))
	for i in range(n):
		var ang := randf() * TAU
		var dist := randf_range(15.0, 35.0)
		_gs.add_pickup({
			"kind": "wood",
			"amount": total / float(n),
			"position": pos + Vector2(cos(ang), sin(ang)) * dist,
		})
	# The chopper stands at the stump — the pickup magnet grabs the burst
	# on the next tick and the normal depleted-site path hauls it to camp.
	unit["work_state"] = "gathering"


## Jeremy 2026-10-05: ground pickups (felled-tree wood) are collected by
## walking over them — whoever is closest (usually the chopper) gets them.
func _collect_pickups(unit: Dictionary) -> void:
	if _gs.pickups.is_empty():
		return
	if not unit.has("carrying"):
		return
	# R33: narrow the reverse scan to pickups in the 3x3 cells around the
	# unit. The scan below keeps its original order and rules, so results
	# are bit-identical to the old full-array version.
	_sync_pickup_grid()
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	var uc := _pickup_cell(up)
	var near := {}
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell: Array = _pickup_grid.get(uc + Vector2i(dx, dy), [])
			for p: Dictionary in cell:
				near[int(p.get("id", -1))] = true
	if near.is_empty():
		return
	var cap: float = float(unit.get("carry_cap", CARRY_CAP))
	var carrying: Dictionary = unit["carrying"]
	var changed := false
	for i in range(_gs.pickups.size() - 1, -1, -1):
		var p: Dictionary = _gs.pickups[i]
		if not near.has(int(p.get("id", -1))):
			continue
		# Jeremy 2026-10-05: felled-tree wood bursts are walk-over pickups;
		# Jeremy 2026-10-06: fisher catches land as food pickups at their
		# feet — the same magnet collects them (only pickup kinds the
		# system produces are collected).
		# Jeremy 2026-10-07: the legendary Stinky Gizmundo is collected too —
		# it eats like a big fish (credited to food on pickup).
		var kind: String = String(p.get("kind", ""))
		if kind != "wood" and kind != "food" and kind != "gizmundo":
			continue
		var pp: Vector2 = p.get("position", Vector2.ZERO)
		if up.distance_to(pp) > PICKUP_RADIUS:
			continue
		var ckey := kind
		if ckey == "gizmundo":
			ckey = "food"
		var have: float = float(carrying.get(ckey, 0.0))
		if have >= cap:
			break
		var pamt: float = float(p.get("amount", 0.0))
		var take: float = minf(pamt, cap - have)
		carrying[ckey] = have + take
		if pamt - take <= 0.0:
			_gs.remove_pickup(int(p.get("id", 0)))
		else:
			p["amount"] = pamt - take
		changed = true
	if changed:
		unit["carrying"] = carrying


## Drop-off tick: credit the ledger, clear the load, pay a haul wage.
func _do_dropoff(unit: Dictionary) -> void:
	var faction: String = String(unit.get("faction", ""))
	var carrying: Dictionary = unit.get("carrying", {})
	for res: String in carrying.keys():
		var amt: float = float(carrying[res])
		if amt > 0.0 and res in Config.RESOURCES:
			_gs.resources.add_resource(faction, res, amt)
	unit["carrying"] = {}
	unit["work_state"] = "idle"
	unit["coins"] = float(unit.get("coins", 0.0)) + SimHousing.HAUL_WAGE


## Build tick: contribute builder power to the blueprint's progress.
func _do_build(unit: Dictionary, buildings: SimBuildings, delta: float) -> void:
	var b: Dictionary = _building_by_id(int(unit.get("work_building", -1)))
	if b.is_empty() or not b.get("alive", false):
		unit["work_state"] = "idle"
		return
	if b.get("complete", false):
		unit["work_state"] = "idle"
		return
	# Stay in hammer range; walk back if drifted.
	var bp: Vector2 = b.get("position", Vector2.ZERO)
	var up: Vector2 = unit.get("position", Vector2.ZERO)
	if up.distance_to(bp) > BUILD_RANGE * 1.5:
		unit["work_target_pos"] = bp
		unit["work_state"] = "to_build"
		return
	if buildings.tick_construction(b, SimSkills.build_mult(unit), delta):
		unit["work_state"] = "idle"  # done — find new work
	# Jeremy 2026-10-11: builders level the building skill while they work.
	SimSkills.grant_tick(_gs, unit, "building", delta)


## Jeremy 2026-10-04: tool purchase arrival — buy the wanted tool at the
## shop with faction gold, equip it, and go back to idle so the unit picks
## up work with the tool in hand. If the shop is gone or the treasury is
## empty, just go idle; the supply flow re-triggers (cooldown-gated).
func _do_shop_buy(unit: Dictionary) -> void:
	unit["work_state"] = "idle"
	var tool_id: String = String(unit.get("_tool_wanted", ""))
	var shop_id := int(unit.get("_shop_target", -1))
	unit.erase("_tool_wanted")
	unit.erase("_shop_target")
	if tool_id == "":
		return
	var pet = _gs.get("petitions")
	if pet == null:
		return
	var shop: Dictionary = _building_by_id(shop_id)
	if shop.is_empty() or not shop.get("alive", false):
		return
	pet.buy_tool(unit, tool_id)


func _do_repair(unit: Dictionary, delta: float) -> void:
	var b: Dictionary = _building_by_id(int(unit.get("work_building", -1)))
	if b.is_empty() or not b.get("alive", false) or not b.get("complete", false):
		unit["work_state"] = "idle"
		return
	var hp: float = float(b.get("hp", 1.0))
	var max_hp: float = float(b.get("max_hp", 1.0))
	if hp >= max_hp:
		unit["work_state"] = "idle"
		return
	var rate: float = REPAIR_RATE
	# A completed repair shop of the same faction nearby speeds repairs.
	var bp: Vector2 = b.get("position", Vector2.ZERO)
	var faction: String = String(b.get("faction", ""))
	for s: Dictionary in _gs.buildings:
		if not s.get("alive", false) or not s.get("complete", false):
			continue
		if String(s.get("type", "")) != "repair_shop":
			continue
		if String(s.get("faction", "")) != faction:
			continue
		var sp: Vector2 = s.get("position", Vector2.ZERO)
		if sp.distance_to(bp) <= SimBuildings.REPAIR_SHOP_RANGE:
			rate *= SimBuildings.REPAIR_SHOP_BONUS
			break
	b["hp"] = minf(max_hp, hp + rate * delta)


func _do_heal(unit: Dictionary, delta: float) -> void:
	var target: Dictionary = _gs.get_unit(int(unit.get("work_building", -1)))
	if target.is_empty() or not target.get("alive", false):
		unit["work_state"] = "idle"
		return
	var hp: float = float(target.get("hp", 100.0))
	var max_hp: float = float(target.get("max_hp", 100.0))
	if hp >= max_hp:
		unit["work_state"] = "idle"
		return
	target["hp"] = minf(max_hp, hp + HEAL_RATE * SimSkills.heal_mult(unit) * delta)
	# Jeremy 2026-10-11: doctors level medicine by healing.
	SimSkills.grant_tick(_gs, unit, "medicine", delta)


func _building_by_id(bid: int) -> Dictionary:
	# Jeremy 2026-10-05 perf: shared O(1) id index on GameState.
	return _gs.get_building(bid)
