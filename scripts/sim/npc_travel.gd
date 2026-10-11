class_name SimNPCTravel
extends RefCounted
## Cursing Gnomes — NPC vehicle travel (Jeremy 2026-10-10 direct order,
## roads/vehicles order, phase P5 — the last unbuilt piece).
##
## Citizens ride their OWN vehicles (dealership purchases) on long trips:
## countryside migration and driving a new purchase home. Boarding, travel
## and dismount run on the unified SimVehicles physics — real acceleration /
## steering / collision, road-preferring, work-zone-deflecting,
## wear-accruing. No spending, no auto-anything: riding your own parked
## vehicle is travel, not economy, so the player-faction adviser /
## sovereignty rules are untouched (same standing as the fire-truck
## dispatch, which already rides every faction's crews).
##
## How it works: another system calls request_ride(unit, dest, kind).
## NPC travel owns the trip from there — the unit walks to its parked
## vehicle ("to_vehicle"), boards as driver, the vehicle drives with
## physics ("on_vehicle", riders glued to the wagon like fire crews), and
## on arrival the unit dismounts and the kind-specific arrival runs:
##   "migrate"    -> _country_move is restored; SimHousing settles the
##                   unit next tick (walk fallback if the ride cancels).
##   "drive_home" -> the buyer parks their new vehicle at their town.
## Anything can cancel a ride (vehicle gone, unit re-tasked, stuck wagon):
## the unit is never stranded — it falls back to walking.
##
## Owned by World (game.npc_travel). Ticked per-frame after
## game.vehicles.tick (positions settled) and before the fire-truck
## driver. Serialized in save_system.gd (transient only — ride state
## lives on the unit/vehicle records, which already serialize).


## Personal vehicle types a citizen may ride. Faction equipment
## (firetruck) and military wagons are never commandeered.
const PERSONAL_TYPES := ["cart", "wagon", "carriage"]

const RIDE_MIN_DIST := 500.0    # px: shorter trips just walk
const VEHICLE_SEEK_RANGE := 800.0  # px: vehicle must be this close to bother
const BOARD_RANGE := 40.0       # px: close enough to climb aboard
const STUCK_TIMEOUT := 8.0      # s: wagon unmoved this long -> dismount, walk

## Trip kinds.
const KIND_MIGRATE := "migrate"
const KIND_DRIVE_HOME := "drive_home"


var _gs = null               ## GameState (untyped: avoids load cycle)
var _rides := {}             ## unit_id -> true (active rides; state on records)


func _init(game_state) -> void:
	_gs = game_state


## --- ride requests --------------------------------------------------------


## Asks NPC travel to drive this unit's trip. Returns true when the trip
## is now owned here (the caller must NOT also walk the unit).
func request_ride(u: Dictionary, dest: Vector2, kind: String) -> bool:
	if _gs == null or u.is_empty() or not u.get("alive", false):
		return false
	if u.has("_ride"):
		return false  # one trip at a time
	var uid := int(u.get("id", -1))
	if uid < 0 or _ride_blocked(u):
		return false
	if JobDefs.is_military(String(u.get("job", ""))):
		return false  # soldiers ride motor-pool wagons / fire trucks
	if dest == Vector2.INF:
		return false
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if upos.distance_to(dest) < RIDE_MIN_DIST:
		return false  # short trip — walk it
	var sv := _gs.get("vehicles") as SimVehicles
	if sv == null:
		return false
	var v: Dictionary = sv.vehicle_by_id(int(u.get("vehicle_id", -1)))
	if not _usable_personal_vehicle(v, uid):
		return false
	var vpos: Vector2 = v.get("pos", upos)
	if upos.distance_to(vpos) > VEHICLE_SEEK_RANGE:
		return false  # the wagon's clear across town — walk instead
	u["_ride"] = {
		"vehicle_id": int(v.get("id", -1)),
		"kind": kind,
		"dest": dest,
		"stuck_t": 0.0,
		"last_vpos": vpos,
	}
	u["work_state"] = "to_vehicle"
	_rides[uid] = true
	return true


## Migration hook for SimHousing: ride out to the countryside instead of
## walking the whole way.
func take_migration_ride(u: Dictionary, dest: Vector2) -> bool:
	return request_ride(u, dest, KIND_MIGRATE)


## Nearest complete hall/town_hall of the faction (drive-home target).
## Vector2.INF when the faction holds no hall.
func nearest_hall_pos(faction: String, near: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d2 := INF
	for b in _gs.get("buildings"):
		var bd: Dictionary = b
		if String(bd.get("faction", "")) != faction:
			continue
		if not bool(bd.get("alive", false)) \
				or not bool(bd.get("complete", false)):
			continue
		if not String(bd.get("type", "")) in ["hall", "town_hall"]:
			continue
		var d2: float = near.distance_squared_to(
			bd.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = bd.get("position", Vector2.ZERO)
	return best


## Live, parked, unused, personally-owned civilian vehicle.
func _usable_personal_vehicle(v: Dictionary, uid: int) -> bool:
	if v.is_empty():
		return false
	if not String(v.get("type", "")) in PERSONAL_TYPES:
		return false
	if int(v.get("owner_id", -1)) != uid:
		return false
	if String(v.get("state", "parked")) != SimVehicles.STATE_PARKED:
		return false
	if int(v.get("driver_id", -1)) >= 0:
		return false
	if not (v.get("crew", []) as Array).is_empty():
		return false
	return true


## True when the unit must not start (or must abort) a ride. Mirrors the
## dealership's _shop_blocked: explicit orders, war, disaster and flight
## always win over a pleasure drive.
func _ride_blocked(u: Dictionary) -> bool:
	if not (u.get("player_order", {}) as Dictionary).is_empty():
		return true
	if bool(u.get("deployed_for_war", false)):
		return true
	if int(u.get("deploy_target_id", -1)) >= 0:
		return true
	if int(u.get("disaster_hunt_id", -1)) >= 0:
		return true
	if bool(u.get("withdrawing", false)):
		return true
	if bool(u.get("summoned", false)):
		return true
	if bool(u.get("fleeing", false)):
		return true
	return false


## --- per-frame driver -------------------------------------------------------


func tick(delta: float) -> void:
	if _gs == null or delta <= 0.0:
		return
	if _rides.is_empty():
		return
	var sv := _gs.get("vehicles") as SimVehicles
	if sv == null:
		for uid in _rides.keys():
			var lost: Dictionary = _gs.get_unit(int(uid))
			if not lost.is_empty():
				_cancel_ride(lost, true)
		return
	for uid in _rides.keys():
		var u: Dictionary = _gs.get_unit(int(uid))
		if u.is_empty():
			_rides.erase(uid)
			continue
		if not u.get("alive", false):
			_release_dead_rider(u, sv)
			continue
		var ride: Dictionary = u.get("_ride", {})
		if ride.is_empty():
			_rides.erase(uid)
			continue
		if _ride_blocked(u):
			_cancel_ride(u, true)
			continue
		var v: Dictionary = sv.vehicle_by_id(
			int(ride.get("vehicle_id", -1)))
		if v.is_empty() or int(v.get("owner_id", -1)) != int(uid):
			_cancel_ride(u, true)  # wagon sold / despawned — walk it
			continue
		_tick_ride(u, ride, v, sv, delta)


## A dead rider's seat is freed so the wagon isn't bricked forever.
func _release_dead_rider(u: Dictionary, sv: SimVehicles) -> void:
	var ride: Dictionary = u.get("_ride", {})
	var vid := int(ride.get("vehicle_id", -1))
	if vid > 0:
		sv.disembark_vehicle(vid, int(u.get("id", -1)))
	u.erase("_ride")
	_rides.erase(int(u.get("id", -1)))


func _tick_ride(u: Dictionary, ride: Dictionary, v: Dictionary,
		sv: SimVehicles, delta: float) -> void:
	var uid := int(u.get("id", -1))
	var vid := int(v.get("id", -1))
	var dest: Vector2 = ride.get("dest", Vector2.INF)
	var crew: Array = v.get("crew", [])
	var aboard: bool = int(v.get("driver_id", -1)) == uid \
		or crew.has(uid)
	if not aboard:
		_tick_boarding(u, ride, v, sv, delta)
		return
	# Aboard: glue the rider to the wagon (fire-crew pattern — small
	# offset so driver and rider don't z-stack) and watch for arrival.
	var vpos: Vector2 = v.get("pos", Vector2.ZERO)
	u["position"] = vpos + Vector2(0.0, 4.0)
	u["work_state"] = "on_vehicle"
	var last: Vector2 = ride.get("last_vpos", vpos)
	if vpos.distance_to(last) > 2.0:
		ride["stuck_t"] = 0.0
		ride["last_vpos"] = vpos
	else:
		ride["stuck_t"] = float(ride.get("stuck_t", 0.0)) + delta
		if float(ride.get("stuck_t", 0.0)) > STUCK_TIMEOUT:
			# Boxed in (rubble, a crowd, a bad target) — get out, walk.
			_cancel_ride(u, true)
			return
	if String(v.get("state", "parked")) == SimVehicles.STATE_PARKED \
			and not bool(v.get("has_target", false)):
		_arrive(u, ride, v, sv)


## Not aboard yet: walk to the parked wagon, climb in, roll out.
func _tick_boarding(u: Dictionary, ride: Dictionary, v: Dictionary,
		sv: SimVehicles, delta: float) -> void:
	var uid := int(u.get("id", -1))
	var vid := int(v.get("id", -1))
	var dest: Vector2 = ride.get("dest", Vector2.INF)
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var vpos: Vector2 = v.get("pos", upos)
	u["work_state"] = "to_vehicle"
	if upos.distance_to(vpos) > BOARD_RANGE:
		WorkerAI.move_unit(_gs, u, vpos, delta)
		return
	if not _usable_personal_vehicle(v, uid):
		_cancel_ride(u, true)  # taken / moved while walking over
		return
	if sv.board_vehicle(vid, uid):
		u["work_state"] = "on_vehicle"
		sv.drive_to(vid, dest)
		ride["stuck_t"] = 0.0
		ride["last_vpos"] = v.get("pos", vpos)
	else:
		_cancel_ride(u, true)


## Wheels down: dismount and run the kind-specific arrival.
func _arrive(u: Dictionary, ride: Dictionary, v: Dictionary,
		sv: SimVehicles) -> void:
	var uid := int(u.get("id", -1))
	var vid := int(v.get("id", -1))
	sv.disembark_vehicle(vid, uid)
	sv.park(vid)
	var kind := String(ride.get("kind", ""))
	var dest: Vector2 = ride.get("dest",
		v.get("pos", Vector2.ZERO))
	u.erase("_ride")
	_rides.erase(uid)
	u["work_state"] = "idle"
	if kind == KIND_MIGRATE:
		# Hand back to SimHousing: the unit stands on its spot, so the
		# next housing tick walks zero meters and settles the homestead.
		u["_country_move"] = v.get("pos", dest)


## Cancel a ride without stranding the unit: free the seat, and for a
## migration put the walk back so housing carries on on foot.
func _cancel_ride(u: Dictionary, walk_fallback: bool) -> void:
	var uid := int(u.get("id", -1))
	var ride: Dictionary = u.get("_ride", {})
	var vid := int(ride.get("vehicle_id", -1))
	var sv := _gs.get("vehicles") as SimVehicles
	if sv != null and vid > 0:
		sv.disembark_vehicle(vid, uid)
	var kind := String(ride.get("kind", ""))
	var dest: Vector2 = ride.get("dest", Vector2.INF)
	u.erase("_ride")
	_rides.erase(uid)
	u["work_state"] = "idle"
	if walk_fallback and kind == KIND_MIGRATE and dest != Vector2.INF:
		u["_country_move"] = dest


## --- save/load --------------------------------------------------------------


## Ride state lives on the unit/vehicle records (both serialize); this is
## transient only. On load, re-arm ticks for units that still carry a ride.
func to_dict() -> Dictionary:
	return {}


func from_dict(_data: Dictionary) -> void:
	_rides.clear()
	if _gs == null:
		return
	for u in _gs.get("units"):
		var ud: Dictionary = u
		if ud.has("_ride") and bool(ud.get("alive", false)):
			_rides[int(ud.get("id", -1))] = true
