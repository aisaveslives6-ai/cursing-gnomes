class_name SimVehicles
extends RefCounted
## Cursing Gnomes — unified vehicle system core (Jeremy 2026-10-10 direct
## order: road infrastructure + full vehicle system, phase P1).
##
## One record per physical vehicle on the map. EVERY vehicle — trade wagons,
## citizen carts/carriages, military vehicles, fire trucks — drives through
## this physics step: real acceleration/braking, turn-rate-limited steering,
## disc collision (vehicles + buildings), and road preference. No abstracted
## vehicle movement remains: P5 migrated the fire-truck path onto these
## records (firefighters mount up at the station lot and ride with physics);
## trade-wagon migration follows the same board/drive/disembark API.
##
## Fantasy-era types only (Jeremy's constraint — never modern cars):
## wagon / cart / carriage / firetruck (horse-drawn fire wagon).
##
## Scope is deliberately tight (Jeremy: "vehicles are a means of travel,
## not a new combat or economy system"): this file owns records + driving
## physics + boarding + save/load. Dealership/ownership/parking (P3), the
## renderer (P2), planned road networks (P4), and NPC mounting/fire-truck
## dispatch (P5, done for fire trucks) build on top of it. Nothing here
## spends coins or auto-builds, so the player faction's adviser/sovereignty
## rules are untouched.
##
## Owned by World (game.vehicles). Wired in world.gd next to SimTradeRoutes,
## ticked per-frame, serialized in save_system.gd.


const STATE_PARKED := "parked"
const STATE_DRIVING := "driving"

## Per-type driving model: top speed (px/s), accel/brake (px/s^2),
## turn_rate (rad/s at standstill, damped at speed), collision radius (px),
## and road-wear accrual multiplier (heavy loads grind roads down —
## wagon 4x matches the trade-wagon WAGON_WEAR_MULT).
const TYPES := {
	"wagon": {"max_speed": 55.0, "accel": 22.0, "brake": 45.0,
		"turn_rate": 1.7, "radius": 14.0, "wear_mult": 4.0},
	"cart": {"max_speed": 48.0, "accel": 34.0, "brake": 60.0,
		"turn_rate": 2.5, "radius": 9.0, "wear_mult": 1.5},
	"carriage": {"max_speed": 70.0, "accel": 28.0, "brake": 55.0,
		"turn_rate": 2.1, "radius": 11.0, "wear_mult": 2.0},
	# Jeremy 2026-10-10 fire-truck dispatch: fantasy-era horse-drawn fire
	# wagon (red tank body, water barrel — never a modern truck). One per
	# fire station; firefighters mount up at the station lot.
	"firetruck": {"max_speed": 62.0, "accel": 26.0, "brake": 55.0,
		"turn_rate": 2.0, "radius": 13.0, "wear_mult": 3.0},
	# Jeremy 2026-10-11 tap-menu aid: horse-drawn relief wagon
	# (canvas-topped, goods-laden — never a modern truck). Rolls when the
	# player sends resource aid from the tap menu; visibly hauls the goods
	# to the recipient's hall, then drives home and stands down. Renders
	# with the covered-wagon art until it gets its own pass.
	"aidwagon": {"max_speed": 52.0, "accel": 24.0, "brake": 50.0,
		"turn_rate": 1.9, "radius": 12.0, "wear_mult": 2.5},
}

## Max riders besides the driver (a fire crew is 2-3; 5 is headroom).
const MAX_CREW := 5

## Road surface model (mirrors the unit side): stone reads 1.3x like
## SimPathfinder.ROAD_SPEED_MULT; dirt is a milder 1.15x; off-road is rough
## (0.85x) so vehicles genuinely prefer roads. Wear scales the engineered
## bonus back toward 1.0 — the same lerp the pathfinder's road_step_cost
## uses for routing, so physics and routing agree on what "worn out" means.
const STONE_ROAD_MULT := 1.3
const DIRT_ROAD_MULT := 1.15
const OFFROAD_MULT := 0.85
const ARRIVE_DIST := 10.0
const EASE_DIST := 60.0   # arrival easing zone (mirrors pathfinder's 48)


var _gs = null               ## GameState (untyped: avoids load cycle)
var _next_id := 1

## Building-collision spatial grid (Jeremy 2026-10-10 perf pass, AAA 60fps):
## the old _blocked_by_building scanned ALL buildings per driving vehicle
## per frame — O(vehicles * buildings), measured 21.4ms/frame at 30 driving
## vehicles x 300 buildings (over a full 16.7ms frame budget). Buildings are
## static, so a cell grid makes the query O(nearby). The grid stores raw
## building dict refs; alive/complete/type/footprint are always read LIVE
## at query time, so completion flips, demolition flags, and direct array
## appends stay correct — only membership is cached, invalidated when
## gs.buildings.size() changes (covers add/erase/wholesale replace).
const BLD_GRID_CELL := 128.0
const BLD_GRID_MARGIN := 48.0  # covers max vehicle radius (14) + regrowth
var _bld_grid: Dictionary = {}  # Vector2i cell -> Array[Dictionary]
var _bld_grid_bcount := -1

## Separation runs only when something moved or the fleet changed
## (Jeremy 2026-10-10 perf pass): the old tick() ran the O(n^2) pairwise
## separation every frame even for a fully parked fleet (~0.7ms at 30).
var _fleet_dirty := true
var separation_passes := 0  # debug counter: how often _separate_vehicles ran

## Live vehicles: [{id:int, type:String, faction:String, owner_id:int,
## driver_id:int (-1 = none), pos:Vector2, facing:float (radians),
## speed:float, state:"parked"|"driving", target:Vector2, has_target:bool}]
var vehicles: Array[Dictionary] = []


func _init(game_state) -> void:
	_gs = game_state


## --- lifecycle ------------------------------------------------------------


## Spawns a vehicle. Unknown type -> {} (no silent mis-spawn).
func spawn_vehicle(vtype: String, pos: Vector2, faction: String,
		owner_id: int = -1) -> Dictionary:
	if not TYPES.has(vtype):
		return {}
	var v := {
		"id": _next_id, "type": vtype, "faction": faction,
		"owner_id": owner_id, "driver_id": -1, "crew": [],
		"pos": pos, "facing": 0.0, "speed": 0.0,
		"state": STATE_PARKED, "target": pos, "has_target": false,
	}
	_next_id += 1
	vehicles.append(v)
	_fleet_dirty = true
	return v


func despawn_vehicle(vehicle_id: int) -> bool:
	for i in vehicles.size():
		if int(vehicles[i].get("id", -1)) == vehicle_id:
			vehicles.remove_at(i)
			_fleet_dirty = true
			return true
	return false


func vehicle_by_id(vehicle_id: int) -> Dictionary:
	for v in vehicles:
		if int(v.get("id", -1)) == vehicle_id:
			return v
	return {}


func vehicles_of_faction(faction: String) -> Array:
	var out: Array = []
	for v in vehicles:
		if String(v.get("faction", "")) == faction:
			out.append(v)
	return out


func vehicle_count() -> int:
	return vehicles.size()


## --- driving --------------------------------------------------------------


func assign_driver(vehicle_id: int, unit_id: int) -> bool:
	var v := vehicle_by_id(vehicle_id)
	if v.is_empty():
		return false
	v["driver_id"] = unit_id
	return true


func release_driver(vehicle_id: int) -> bool:
	return assign_driver(vehicle_id, -1)


## Boards a unit: the first boarder drives, the rest ride as crew
## (cap MAX_CREW). Unknown id / invalid unit -> false.
func board_vehicle(vehicle_id: int, unit_id: int) -> bool:
	var v := vehicle_by_id(vehicle_id)
	if v.is_empty() or unit_id < 0:
		return false
	if int(v.get("driver_id", -1)) == unit_id:
		return true
	var crew: Array = v.get("crew", [])
	if crew.has(unit_id):
		return true
	if int(v.get("driver_id", -1)) < 0:
		v["driver_id"] = unit_id
	elif crew.size() < MAX_CREW:
		crew.append(unit_id)
		v["crew"] = crew
	else:
		return false
	return true


## Disembarks a unit; the first crew member takes the reins when the
## driver leaves. Unknown id -> false.
func disembark_vehicle(vehicle_id: int, unit_id: int) -> bool:
	var v := vehicle_by_id(vehicle_id)
	if v.is_empty():
		return false
	var crew: Array = v.get("crew", [])
	if int(v.get("driver_id", -1)) == unit_id:
		v["driver_id"] = -1
		if not crew.is_empty():
			v["driver_id"] = int(crew[0])
			crew.remove_at(0)
			v["crew"] = crew
	elif crew.has(unit_id):
		crew.erase(unit_id)
		v["crew"] = crew
	return true


## Every unit aboard: driver first, then crew. Unknown id -> [].
func aboard_ids(vehicle_id: int) -> Array:
	var v := vehicle_by_id(vehicle_id)
	if v.is_empty():
		return []
	var out: Array = []
	var d := int(v.get("driver_id", -1))
	if d >= 0:
		out.append(d)
	for c in v.get("crew", []):
		out.append(int(c))
	return out


## Set of every unit id currently aboard any vehicle (driver or crew).
## Pure — lets the world renderer hide boarded unit sprites in one pass
## (graphics-hourly 2026-10-11: no more full-size sprites glued to trucks).
func aboard_set() -> Dictionary:
	var out := {}
	for v in vehicles:
		for uid in aboard_ids(int(v.get("id", 0))):
			out[int(uid)] = true
	return out


## Sends the vehicle driving to a point. Unknown id -> false.
func drive_to(vehicle_id: int, target: Vector2) -> bool:
	var v := vehicle_by_id(vehicle_id)
	if v.is_empty():
		return false
	v["target"] = target
	v["has_target"] = true
	v["state"] = STATE_DRIVING
	_fleet_dirty = true
	return true


## Parks the vehicle in place: speed bleeds to zero over this tick's step.
func park(vehicle_id: int) -> bool:
	var v := vehicle_by_id(vehicle_id)
	if v.is_empty():
		return false
	v["has_target"] = false
	v["state"] = STATE_PARKED
	v["speed"] = 0.0
	_fleet_dirty = true
	return true


## Effective speed multiplier at a position from the road network:
## stone 1.3x / dirt 1.15x fresh, scaling to 1.0x as wear -> 1.0, and
## 0.85x off-road. Public so the P2 renderer and later phases can reuse it.
func road_bonus_at(pos: Vector2) -> float:
	var wai = _gs.get("worker_ai") if _gs != null else null
	if wai == null:
		return 1.0
	var idx: int = (wai as WorkerAI).road_index_at(pos)
	if idx < 0:
		return OFFROAD_MULT
	var r: Dictionary = (wai as WorkerAI).roads[idx]
	var wear := clampf(float(r.get("wear", 0.0)), 0.0, 1.0)
	var fresh := 1.0 - wear
	if String(r.get("type", "dirt")) == "stone":
		return 1.0 + (STONE_ROAD_MULT - 1.0) * fresh
	return 1.0 + (DIRT_ROAD_MULT - 1.0) * fresh


## Per-frame physics for every driving vehicle.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	var moved_any := false
	for v in vehicles:
		if String(v.get("state", STATE_PARKED)) == STATE_DRIVING \
				and bool(v.get("has_target", false)):
			var before: Vector2 = v.get("pos", Vector2.ZERO)
			_step_vehicle(v, delta)
			if v.get("pos", Vector2.ZERO) != before:
				moved_any = true
	# Jeremy 2026-10-10 perf pass: a parked fleet needs no O(n^2)
	# separation pass — run it only when something moved or the fleet
	# changed (spawn/despawn/drive/park/load).
	if moved_any or _fleet_dirty:
		_separate_vehicles()
	_fleet_dirty = false


## One physics step: steer -> accelerate -> collide -> move -> wear.
func _step_vehicle(v: Dictionary, delta: float) -> void:
	var t: Dictionary = TYPES.get(String(v.get("type", "wagon")),
		TYPES["wagon"])
	var pos: Vector2 = v.get("pos", Vector2.ZERO)
	var target: Vector2 = v.get("target", pos)
	var to: Vector2 = target - pos
	var dist := to.length()
	if dist <= ARRIVE_DIST:
		v["pos"] = target
		v["speed"] = 0.0
		v["has_target"] = false
		v["state"] = STATE_PARKED
		return

	var max_speed := float(t.get("max_speed", 50.0))
	var speed := float(v.get("speed", 0.0))

	# Jeremy 2026-10-10 visible road construction: vehicles route around
	# marked work zones (never through the barriers).
	if dist > EASE_DIST and _gs != null:
		var wai = _gs.get("worker_ai")
		if wai != null:
			to = wai.deflect_around_workzones(pos, to / dist, {}) * dist

	# Steering: turn toward the goal, turn-rate limited, damped at speed
	# (a wagon at full tilt can't pirouette).
	var facing := float(v.get("facing", 0.0))
	var desired := to.angle()
	var diff := wrapf(desired - facing, -PI, PI)
	var damp := clampf(1.0 - 0.5 * speed / maxf(max_speed, 1.0), 0.5, 1.0)
	var max_turn := float(t.get("turn_rate", 2.0)) * damp * delta
	v["facing"] = facing + clampf(diff, -max_turn, max_turn)

	# Longitudinal: ease into the target, accelerate/brake toward the
	# road-bonus-scaled top speed.
	var bonus := road_bonus_at(pos)
	var want := max_speed * bonus
	if dist < EASE_DIST:
		want *= 0.35 + 0.65 * dist / EASE_DIST
	if speed < want:
		speed = minf(want, speed + float(t.get("accel", 25.0)) * delta)
	else:
		speed = maxf(want, speed - float(t.get("brake", 50.0)) * delta)
	v["speed"] = speed
	if speed < 0.5:
		return

	# Move: heading step, never into water (dry_step_vehicle probes the
	# direct heading plus deflections; boxed in -> hold position).
	var heading := Vector2(cos(float(v["facing"])), sin(float(v["facing"])))
	var md: Dictionary = _gs.map_data if _gs != null else {}
	var new_pos: Vector2 = WaterNav.dry_step_vehicle(
		md, pos, heading, speed * delta)
	if new_pos == pos:
		v["speed"] = 0.0
		return

	# Buildings are solid (bridges exempt — vehicles cross them).
	if _blocked_by_building(new_pos, float(t.get("radius", 10.0))):
		v["speed"] = 0.0
		return

	var moved: bool = new_pos != pos
	v["pos"] = new_pos

	# Traffic wears roads: heavy loads grind faster (wagon 4x mirrors the
	# trade-wagon WEAR_MULT; move_unit's per-unit hook is the on-foot twin).
	if moved:
		var wai = _gs.get("worker_ai") if _gs != null else null
		if wai != null:
			(wai as WorkerAI).wear_road_at(new_pos,
				WorkerAI.WEAR_PER_SEC * float(t.get("wear_mult", 1.0)) * delta)


## True when a building footprint (not a bridge) overlaps the disc at pos.
## Grid-accelerated (Jeremy 2026-10-10 perf pass): single-cell lookup,
## O(nearby) instead of O(all buildings). Liveness/type/footprint are read
## live from the dict refs, so the result is identical to the old linear
## scan under every mutation pattern (pinned by tests/test_vehicle_grids.gd).
func _blocked_by_building(pos: Vector2, radius: float) -> bool:
	if _gs == null:
		return false
	var bs: Array = _gs.get("buildings")
	if bs.is_empty():
		return false
	if bs.size() != _bld_grid_bcount:
		_rebuild_building_grid(bs)
	var key := Vector2i(int(floor(pos.x / BLD_GRID_CELL)),
		int(floor(pos.y / BLD_GRID_CELL)))
	if not _bld_grid.has(key):
		return false
	for b in (_bld_grid[key] as Array):
		var bd: Dictionary = b
		if not bool(bd.get("alive", false)) \
				or not bool(bd.get("complete", false)):
			continue
		if String(bd.get("type", "")) == "bridge":
			continue
		var fr: float = SimBuildings.footprint(String(bd.get("type", ""))) \
			+ radius
		if pos.distance_squared_to(
				bd.get("position", Vector2.ZERO)) < fr * fr:
			return true
	return false


## Rebuilds the building-collision grid. Every building is inserted into
## all cells its (footprint + margin) disc touches, so a query only ever
## needs its own cell. ALL buildings are indexed (even dead/incomplete) —
## the query filters liveness live, which keeps completion flips and
## demolition flags correct without a size change.
func _rebuild_building_grid(bs: Array) -> void:
	_bld_grid.clear()
	for b in bs:
		var bd: Dictionary = b
		var bp: Vector2 = bd.get("position", Vector2.ZERO)
		var r := SimBuildings.footprint(String(bd.get("type", ""))) \
			+ BLD_GRID_MARGIN
		var x0 := int(floor((bp.x - r) / BLD_GRID_CELL))
		var x1 := int(floor((bp.x + r) / BLD_GRID_CELL))
		var y0 := int(floor((bp.y - r) / BLD_GRID_CELL))
		var y1 := int(floor((bp.y + r) / BLD_GRID_CELL))
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				var key := Vector2i(cx, cy)
				if not _bld_grid.has(key):
					_bld_grid[key] = []
				(_bld_grid[key] as Array).append(bd)
	_bld_grid_bcount = bs.size()


## Pairwise disc separation so vehicles don't ghost through each other.
## O(n^2) over the vehicle list — n stays small (nothing mass-spawns
## vehicles yet; P3/P5 revisit if fleets grow).
func _separate_vehicles() -> void:
	separation_passes += 1
	var n := vehicles.size()
	if n < 2:
		return
	for i in n:
		var a: Dictionary = vehicles[i]
		var ra := float((TYPES.get(String(a.get("type", "wagon")),
			TYPES["wagon"]) as Dictionary).get("radius", 10.0))
		var pa: Vector2 = a.get("pos", Vector2.ZERO)
		for j in range(i + 1, n):
			var b: Dictionary = vehicles[j]
			var rb := float((TYPES.get(String(b.get("type", "wagon")),
				TYPES["wagon"]) as Dictionary).get("radius", 10.0))
			var pb: Vector2 = b.get("pos", Vector2.ZERO)
			var d := pa.distance_to(pb)
			var min_d := ra + rb
			if d < min_d:
				var push := (min_d - d) * 0.5
				# Jeremy 2026-10-10 perf pass: exact overlaps (d == 0)
				# previously never separated (division guard) and stayed
				# z-stacked forever — push along an arbitrary axis instead.
				var axis := Vector2.RIGHT
				if d > 0.001:
					axis = (pb - pa) / d
				a["pos"] = pa - axis * push
				b["pos"] = pb + axis * push
				pa = a["pos"]


## --- save/load ------------------------------------------------------------


func to_dict() -> Dictionary:
	var vd: Array = []
	for v in vehicles:
		var d := v.duplicate()
		var p: Vector2 = v.get("pos", Vector2.ZERO)
		var tg: Vector2 = v.get("target", Vector2.ZERO)
		d["pos"] = [p.x, p.y]
		d["target"] = [tg.x, tg.y]
		vd.append(d)
	return {"next_id": _next_id, "vehicles": vd}


func from_dict(data: Dictionary) -> void:
	vehicles.clear()
	_fleet_dirty = true
	_next_id = int(data.get("next_id", 1))
	for w in data.get("vehicles", []):
		var d := (w as Dictionary).duplicate()
		var p: Array = d.get("pos", [0, 0])
		var tg: Array = d.get("target", [0, 0])
		d["pos"] = Vector2(float(p[0]), float(p[1]))
		d["target"] = Vector2(float(tg[0]), float(tg[1]))
		# Pre-vehicles saves simply have no "vehicles" key -> empty fleet.
		if TYPES.has(String(d.get("type", ""))):
			# Pre-crew saves (before fire-truck dispatch): no "crew" key.
			if not d.has("crew"):
				d["crew"] = []
			vehicles.append(d)
