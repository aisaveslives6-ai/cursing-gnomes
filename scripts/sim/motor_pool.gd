class_name SimMotorPool
extends RefCounted
## Cursing Gnomes — military motor pool (Jeremy 2026-10-10 direct order,
## roads/vehicles order, phase P5).
##
## Each complete vehicle_depot at the star fort parks, maintains and
## dispatches military wagons:
## - ASSIGNED PARKING: 6-slot lot per depot (two rows of three, deterministic
##   layout — the same assigned-parking pattern as the dealership lot).
##   "parking" rides on the vehicle record; destroyed depots release slots.
## - FLEET: AI factions fund wagons from treasury SURPLUS above the reserve
##   floor (armament-program pattern: a faction's own brain equipping its own
##   troops is command, not direct control). Cap 3 wagons per depot, one
##   purchase per faction per day. Player faction: the War Advisor phones a
##   suggestion instead — never auto-spends (sovereignty, same rule as the
##   AI armament program).
## - MAINTENANCE: the depot keeps the fleet at strength (destroyed wagons
##   are replaced up to cap) and idle wagons re-park in their slots.
## - DISPATCH: when the faction's army deploys for war, the fleet drives out
##   as a baggage train trailing the marching army — real acceleration /
##   steering / collision physics, road-preferring. On stand-down the wagons
##   drive home and re-park.
##
## Owned by World (game.motor_pool). Ticked per-frame after
## game.dealership.tick; serialized in save_system.gd.


## Treasury cost of one military wagon, paid from faction surplus.
const WAGON_WOOD := 40.0
const WAGON_GOLD := 30.0
## The motor pool only spends ABOVE this floor — construction and the war
## effort always eat first (armament program uses 250g/60w; wagons wait
## until the blades are bought).
const MP_GOLD_RESERVE := 300.0
const MP_WOOD_RESERVE := 80.0
const LOT_SLOTS := 6          # assigned parking slots per depot lot
const FLEET_CAP_PER_DEPOT := 3  # wagons per depot (the lot holds spares)
const RETARGET_DIST := 50.0   # px: army moved this far -> wagons re-aim
const TRAIL_GAP := 44.0       # px: spacing of the baggage column
const TICK_SLICE := 2.0       # seconds between depot scans


var _gs = null               ## GameState (untyped: avoids load cycle)
var _scan_t := 0.0
var _announced := {}         ## faction -> true (motor-pool opening told)
var _advise_day := {}        ## faction -> day of last advisor phone nudge
var _buy_day := {}           ## faction -> day of last fleet purchase


func _init(game_state) -> void:
	_gs = game_state


## --- per-frame ------------------------------------------------------------


func tick(delta: float) -> void:
	if _gs == null or delta <= 0.0:
		return
	_scan_t += delta
	if _scan_t < TICK_SLICE:
		return
	_scan_t = 0.0
	_announce_openings()
	_validate_parking()
	for faction in _factions_with_depots():
		_fund_fleet(faction)
		_dispatch(faction)


## Factions that own at least one complete vehicle_depot.
func _factions_with_depots() -> Array:
	var out := []
	for b: Dictionary in _gs.get("buildings"):
		if String(b.get("type", "")) != "vehicle_depot":
			continue
		if not bool(b.get("alive", false)) \
				or not bool(b.get("complete", false)):
			continue
		var f := String(b.get("faction", ""))
		if not out.has(f):
			out.append(f)
	return out


## First completed depot per faction gets a Gazette story (routed through
## court.publish_story so it lands in the Chronicle too).
func _announce_openings() -> void:
	var court = _gs.get("court_sys")
	if court == null:
		return
	for f in _factions_with_depots():
		if bool(_announced.get(f, false)):
			continue
		_announced[f] = true
		var fname := String((Config.FACTIONS.get(f, {}) as Dictionary)\
			.get("name", f))
		court.publish_story("MOTOR POOL OPENS",
			"A motor pool opens at the %s war camp — war wagons parked, " \
			% fname + "fueled and ready to roll with the baggage train.",
			"military")


## Wagons parked at a destroyed / incomplete depot lose their slot
## assignment (they stay parked in place; the lot is gone).
func _validate_parking() -> void:
	var veh = _gs.get("vehicles")
	if veh == null:
		return
	for v: Dictionary in (veh as SimVehicles).vehicles:
		if not bool(v.get("military", false)):
			continue
		var pk: Dictionary = v.get("parking", {})
		if pk.is_empty():
			continue
		var b: Dictionary = _gs.get_building(int(pk.get("building_id", -1)))
		if b.is_empty() or not bool(b.get("alive", false)) \
				or not bool(b.get("complete", false)):
			v.erase("parking")


## --- fleet funding --------------------------------------------------------


## Military wagons belonging to a faction's motor pool.
func _fleet(faction: String) -> Array:
	var veh = _gs.get("vehicles")
	var out := []
	if veh == null:
		return out
	for v: Dictionary in (veh as SimVehicles).vehicles:
		if bool(v.get("military", false)) \
				and String(v.get("faction", "")) == faction:
			out.append(v)
	return out


## Keeps each depot's fleet at strength, funded from treasury surplus.
## Player faction: the War Advisor phones a suggestion (throttled 1/day);
## advisers never spend the player's gold (sovereignty).
func _fund_fleet(faction: String) -> void:
	var depots := []
	for b: Dictionary in _gs.get("buildings"):
		if String(b.get("type", "")) != "vehicle_depot":
			continue
		if not bool(b.get("alive", false)) \
				or not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) == faction:
			depots.append(b)
	if depots.is_empty():
		return
	if _fleet(faction).size() >= depots.size() * FLEET_CAP_PER_DEPOT:
		return  # fleet at strength — nothing to maintain
	if faction == String(_gs.get("player_faction")):
		_advise_motorize(faction)
		return
	var day := int(_gs.get("day_number"))
	if int(_buy_day.get(faction, -99)) == day:
		return  # one wagon per faction per day — pace the spend
	var gold: float = _gs.resources.get_amount(faction, "gold")
	var wood: float = _gs.resources.get_amount(faction, "wood")
	if gold < MP_GOLD_RESERVE + WAGON_GOLD \
			or wood < MP_WOOD_RESERVE + WAGON_WOOD:
		return  # construction and the war effort eat first
	var depot := _depot_with_slot(depots)
	if depot.is_empty():
		return
	var slot := free_slot(int(depot.get("id", -1)))
	var veh = _gs.get("vehicles")
	if veh == null:
		return
	var v: Dictionary = (veh as SimVehicles).spawn_vehicle(
		"wagon", slot_pos(depot, slot), faction, -1)
	if v.is_empty():
		return
	v["military"] = true
	v["mp_mission"] = "parked"
	v["parking"] = {"building_id": int(depot.get("id", -1)), "slot": slot}
	_gs.resources.add_resource(faction, "wood", -WAGON_WOOD, true)
	_gs.resources.add_resource(faction, "gold", -WAGON_GOLD, true)
	_buy_day[faction] = day


## First depot of the faction with a free lot slot.
func _depot_with_slot(depots: Array) -> Dictionary:
	for d in depots:
		if free_slot(int((d as Dictionary).get("id", -1))) >= 0:
			return d
	return {}


## War Advisor phones the player about an empty motor pool (1/day).
func _advise_motorize(faction: String) -> void:
	var day := int(_gs.get("day_number"))
	if int(_advise_day.get(faction, -99)) == day:
		return
	_advise_day[faction] = day
	var fl = _gs.get("faction_leaders")
	if fl != null and fl.has_method("message_player"):
		fl.message_player(faction,
			"My liege, the motor pool stands empty. Fund war wagons and " \
			+ "our armies will march with a proper baggage train.")


## --- dispatch: the baggage train ------------------------------------------


## When the faction's army deploys for war, idle fleet wagons drive out and
## trail the marching army as a baggage train; on stand-down they drive
## home and re-park. All movement is the real SimVehicles physics step.
func _dispatch(faction: String) -> void:
	var fleet := _fleet(faction)
	if fleet.is_empty():
		return
	var army := _deployed_army(faction)
	if army.is_empty():
		for w in fleet:
			_stand_down(w as Dictionary)
		return
	var cx := 0.0
	var cy := 0.0
	for u in army:
		var p: Vector2 = (u as Dictionary).get("position", Vector2.ZERO)
		cx += p.x
		cy += p.y
	var centroid := Vector2(cx / army.size(), cy / army.size())
	var i := 0
	for w in fleet:
		var v: Dictionary = w
		var mission := String(v.get("mp_mission", "parked"))
		var target := centroid + Vector2(TRAIL_GAP * float(i + 1),
			TRAIL_GAP * 0.5 * float(i + 1))
		var cur: Vector2 = v.get("target", v.get("pos", Vector2.ZERO))
		if mission != "deployed" or cur.distance_to(target) > RETARGET_DIST:
			var veh = _gs.get("vehicles")
			if veh != null:
				(veh as SimVehicles).drive_to(int(v.get("id", -1)), target)
				v["mp_mission"] = "deployed"
		i += 1


## Alive units of the faction currently deployed for war.
func _deployed_army(faction: String) -> Array:
	var out := []
	for u: Dictionary in _gs.get("units"):
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if bool(u.get("deployed_for_war", false)):
			out.append(u)
	return out


## No army in the field: wagons drive home; arrival re-parks them.
func _stand_down(v: Dictionary) -> void:
	var mission := String(v.get("mp_mission", "parked"))
	if mission == "parked":
		return
	if mission == "deployed":
		_send_home(v)
		v["mp_mission"] = "returning"
		return
	if mission == "returning" \
			and String(v.get("state", "parked")) == "parked" \
			and not bool(v.get("has_target", false)):
		v["mp_mission"] = "parked"


## Drives a wagon back to its assigned lot slot.
func _send_home(v: Dictionary) -> void:
	var pk: Dictionary = v.get("parking", {})
	if pk.is_empty():
		return
	var b: Dictionary = _gs.get_building(int(pk.get("building_id", -1)))
	if b.is_empty():
		return
	var veh = _gs.get("vehicles")
	if veh == null:
		return
	(veh as SimVehicles).drive_to(int(v.get("id", -1)),
		slot_pos(b, int(pk.get("slot", 0))))


## --- assigned parking -----------------------------------------------------


## Deterministic lot layout: two rows of three slots on the building's
## south side, clear of the footprint. Pure function of the record.
static func lot_slots(building: Dictionary) -> Array:
	var out: Array = []
	var bp: Vector2 = building.get("position", Vector2.ZERO)
	var s := float(building.get("size", 36.0))
	for i in LOT_SLOTS:
		var col := i % 3
		var row := i / 3
		out.append(bp + Vector2((float(col) - 1.0) * s * 0.85,
			s * 0.75 + float(row) * s * 0.85))
	return out


static func slot_pos(building: Dictionary, slot: int) -> Vector2:
	var slots := lot_slots(building)
	if slot < 0 or slot >= slots.size():
		return building.get("position", Vector2.ZERO)
	return slots[slot]


## First free lot slot on the depot's lot, or -1 when full.
func free_slot(building_id: int) -> int:
	var veh = _gs.get("vehicles")
	if veh == null:
		return -1
	var taken := {}
	for v: Dictionary in (veh as SimVehicles).vehicles:
		if not bool(v.get("military", false)):
			continue
		var pk: Dictionary = v.get("parking", {})
		if int(pk.get("building_id", -1)) == building_id:
			taken[int(pk.get("slot", -1))] = true
	for i in LOT_SLOTS:
		if not taken.has(i):
			return i
	return -1


## --- save/load ------------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"announced": _announced.keys(),
		"advise_day": _advise_day,
		"buy_day": _buy_day,
	}


func from_dict(data: Dictionary) -> void:
	_announced.clear()
	for f in data.get("announced", []):
		_announced[String(f)] = true
	_advise_day.clear()
	for f in (data.get("advise_day", {}) as Dictionary).keys():
		_advise_day[String(f)] = int((data["advise_day"] as Dictionary)[f])
	_buy_day.clear()
	for f in (data.get("buy_day", {}) as Dictionary).keys():
		_buy_day[String(f)] = int((data["buy_day"] as Dictionary)[f])
