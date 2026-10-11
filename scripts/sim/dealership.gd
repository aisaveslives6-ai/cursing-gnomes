class_name SimDealership
extends RefCounted
## Cursing Gnomes — vehicle dealership, ownership & assigned parking
## (Jeremy 2026-10-10 direct order, roads/vehicles phase P3).
##
## The wagon_dealership is a commercial building (district-developed like
## the other shops). Citizens spend their OWN coins — never the faction
## treasury — on fantasy-era personal vehicles (cart / wagon / carriage),
## the same personal-purse pattern as SimHousing house sales and
## SimCombat's fighter weapon shopping. That keeps the player faction's
## adviser/sovereignty rules untouched: no crown gold moves, no forced
## builds, no auto-spend.
##
## Every sold vehicle gets an ASSIGNED parking slot on the dealership lot
## (6 slots, two rows of three). The slot rides on the vehicle record
## ("parking" = {building_id, slot}) so save/load is wholesale and a
## destroyed dealership simply releases its slots — the vehicles stay
## parked where they are. send_home() drives a vehicle back to its slot;
## arrival auto-parks through the SimVehicles physics step (P5's travel
## code calls this at trip end).
##
## Shopping trips: an idle, order-free civilian rolls (HTML-weapon-shop
## cadence) for a trip to the nearest complete dealership within
## SEEK_RANGE — any faction's lot serves anyone except a faction we're at
## war with (same commerce rule as the weaponsmith). WorkerAI yields on
## the _buying_vehicle flag (work.gd, like _buying_home) so the trip
## isn't yanked mid-walk; the flag is always cleared on abort/buy.
##
## Owned by World (game.dealership). Ticked per-frame after
## game.vehicles.tick; serialized in save_system.gd.


## Sale prices in personal coins. Units start with 20-60 and earn wages
## (SimHousing), so a cart is an early purchase, a carriage a savings goal.
const VEHICLE_PRICES := {"cart": 35.0, "wagon": 60.0, "carriage": 100.0}
## Sale order: priciest affordable first (aspirational shopping).
const SALE_ORDER := ["carriage", "wagon", "cart"]
const SEEK_RANGE := 500.0   # px: how far a citizen looks for a dealership
const BUY_RANGE := 50.0     # px: close enough to pay the dealer
const ROLL_PER_TICK := 0.004  # same cadence as the weaponsmith roll
const LOT_SLOTS := 6        # assigned parking slots per dealership lot
const TICK_SLICE := 20      # units processed per frame (cursor round-robin)

const TRIP_FLAG := "_buying_vehicle"
const DEALER_KEY := "_dealer_id"

const PURCHASE_LINES := {
	"gnomes": "Bought a wagon. About fucking time.",
	"ogres": "Big cart! Ogre rides!",
	"elves": "A carriage, at last.",
	"humans": "New wheels, finally.",
	"undead": "The dead ride in style.",
}


var _gs = null               ## GameState (untyped: avoids load cycle)
var _cursor := 0
var _announced := {}         ## faction -> true (grand-opening story told)
var _open_scan_t := 0.0      ## throttle: dealership scan runs at 0.5 Hz


func _init(game_state) -> void:
	_gs = game_state


## --- per-frame ------------------------------------------------------------


func tick(delta: float) -> void:
	if _gs == null or delta <= 0.0:
		return
	_open_scan_t += delta
	if _open_scan_t >= 2.0:
		_open_scan_t = 0.0
		_announce_openings()
		_validate_parking()
	var units: Array = _gs.get("units")
	var n := units.size()
	if n <= 0:
		return
	var todo := mini(TICK_SLICE, n)
	for i in todo:
		var u: Dictionary = units[(_cursor + i) % n]
		_tick_shopper(u, delta)
	_cursor = (_cursor + todo) % n


## First completed dealership per faction gets a Gazette grand opening
## (routed through court.publish_story so it lands in the Chronicle too).
func _announce_openings() -> void:
	var court = _gs.get("court_sys")
	if court == null:
		return
	for b: Dictionary in _gs.get("buildings"):
		if String(b.get("type", "")) != "wagon_dealership":
			continue
		if not bool(b.get("alive", false)) \
				or not bool(b.get("complete", false)):
			continue
		var faction := String(b.get("faction", ""))
		if bool(_announced.get(faction, false)):
			continue
		_announced[faction] = true
		var fname := String((Config.FACTIONS.get(faction, {}) as Dictionary)\
			.get("name", faction))
		court.publish_story("GRAND OPENING",
			"A wagon dealership opens among the %s — carts, wagons and " \
			% fname + "carriages for sale to any citizen with the coin.",
			"economy")


## Vehicles parked at a destroyed / incomplete dealership lose their slot
## assignment (they stay parked in place; the lot is gone).
func _validate_parking() -> void:
	var veh = _gs.get("vehicles")
	if veh == null:
		return
	for v: Dictionary in (veh as SimVehicles).vehicles:
		var pk: Dictionary = v.get("parking", {})
		if pk.is_empty():
			continue
		var b: Dictionary = _gs.get_building(int(pk.get("building_id", -1)))
		if b.is_empty() or not bool(b.get("alive", false)) \
				or not bool(b.get("complete", false)):
			v.erase("parking")


## --- shopping trips -------------------------------------------------------


## Returns true when this tick was consumed by the dealership trip.
func _tick_shopper(u: Dictionary, delta: float) -> bool:
	if not u.get("alive", false):
		return false
	var did := int(u.get(DEALER_KEY, -1))
	if did >= 0:
		return _continue_trip(u, did, delta)
	if _shop_blocked(u):
		return false
	if float(u.get("coins", 0.0)) < float(VEHICLE_PRICES["cart"]):
		return false  # can't afford even a cart yet — keep earning
	# Same normalized roll as the weaponsmith trip.
	if randf() >= 1.0 - pow(1.0 - ROLL_PER_TICK, 60.0 * delta):
		return false
	var faction := String(u.get("faction", ""))
	var dealer := _find_dealership(
		u.get("position", Vector2.ZERO), faction)
	if dealer.is_empty():
		return false
	u[DEALER_KEY] = int(dealer.get("id", -1))
	u[TRIP_FLAG] = true  # WorkerAI yields while the citizen shops
	return true  # the walk itself starts on the next tick


## Trip in progress: blocked / re-tasked units abort; the walk continues.
func _continue_trip(u: Dictionary, did: int, delta: float) -> bool:
	if _shop_blocked(u):
		_abort_trip(u)
		return false
	var dealer: Dictionary = _gs.get_building(did)
	if dealer.is_empty() or not bool(dealer.get("alive", false)) \
			or not bool(dealer.get("complete", false)) \
			or String(dealer.get("type", "")) != "wagon_dealership":
		_abort_trip(u)
		return false
	var dpos: Vector2 = dealer.get("position", Vector2.ZERO)
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if upos.distance_to(dpos) > BUY_RANGE:
		WorkerAI.move_unit(_gs, u, dpos, delta)
		return true
	_close_sale(u, dealer)
	return true


func _abort_trip(u: Dictionary) -> void:
	u.erase(DEALER_KEY)
	u.erase(TRIP_FLAG)


## True when the unit may not start (or must abort) a dealership trip.
func _shop_blocked(u: Dictionary) -> bool:
	if JobDefs.is_military(String(u.get("job", ""))):
		return true  # soldiers don't go car shopping
	if not (u.get("player_order", {}) as Dictionary).is_empty():
		return true  # explicit player orders win
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
	if int(u.get("vehicle_id", -1)) >= 0:
		return true  # already owns a vehicle
	if int(u.get("truck_id", -1)) >= 0:
		return true  # riding a fire truck
	if _aboard_vehicle(int(u.get("id", -1))):
		return true
	# On a trip the WorkerAI yield holds work_state steady; starting a
	# trip needs a genuinely idle civilian.
	if not u.has(TRIP_FLAG) \
			and String(u.get("work_state", "idle")) != "idle":
		return true
	return false


## True when the unit is currently driving or riding a vehicle.
func _aboard_vehicle(uid: int) -> bool:
	var veh = _gs.get("vehicles")
	if veh == null or uid < 0:
		return false
	for v: Dictionary in (veh as SimVehicles).vehicles:
		if int(v.get("driver_id", -1)) == uid:
			return true
		if (v.get("crew", []) as Array).has(uid):
			return true
	return false


## Nearest usable dealership: alive, complete, within seek range, with a
## free lot slot. Any faction's lot serves anyone (HTML commerce rule)
## except a faction we're at war with — no shopping behind enemy lines.
func _find_dealership(upos: Vector2, faction: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d := SEEK_RANGE
	var dip = _gs.get("diplomacy")
	for b: Dictionary in _gs.get("buildings"):
		if String(b.get("type", "")) != "wagon_dealership":
			continue
		if not bool(b.get("alive", false)) \
				or not bool(b.get("complete", false)):
			continue
		if dip != null and bool(dip.combat_enabled(faction,
				String(b.get("faction", "")))):
			continue
		if free_slot(int(b.get("id", -1))) < 0:
			continue
		var d: float = upos.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	return best


## At the counter: pay personal coins (priciest affordable first), the
## gold goes to the dealer's faction treasury, and the vehicle spawns
## parked in its assigned lot slot.
func _close_sale(u: Dictionary, dealer: Dictionary) -> void:
	_abort_trip(u)  # trip over either way; flags cleared first
	var did := int(dealer.get("id", -1))
	var slot := free_slot(did)
	if slot < 0:
		return  # lot filled while walking over — no sale
	var coins := float(u.get("coins", 0.0))
	var vtype := ""
	for t in SALE_ORDER:
		if coins >= float(VEHICLE_PRICES[t]):
			vtype = t
			break
	if vtype.is_empty():
		return  # spent it on the way over — back to earning
	var price := float(VEHICLE_PRICES[vtype])
	var veh = _gs.get("vehicles")
	if veh == null:
		return
	var spot := slot_pos(dealer, slot)
	var v: Dictionary = (veh as SimVehicles).spawn_vehicle(
		vtype, spot, String(dealer.get("faction", "")), int(u.get("id", -1)))
	if v.is_empty():
		return
	v["parking"] = {"building_id": did, "slot": slot}
	u["vehicle_id"] = int(v.get("id", -1))
	u["coins"] = coins - price
	# Jeremy 2026-10-11 (hearsay flesh-out): the sale is tavern news —
	# the mill hears who bought what (see SimHearsay._on_vehicle_bought).
	_gs.bus.vehicle_bought.emit(int(u.get("id", -1)), vtype, price)
	_gs.resources.add_resource(String(dealer.get("faction", "")), "gold",
		price, true)
	var faction := String(u.get("faction", ""))
	_gs.bus.unit_said.emit(int(u.get("id", -1)),
		String(PURCHASE_LINES.get(faction, "Bought a vehicle!")))
	# Drive it home: the buyer rides their new vehicle back to town
	# (SimNPCTravel owns the trip; short hops just walk). Pulls up
	# outside the hall's footprint — wagons can't park inside a building.
	var nt = _gs.get("npc_travel")
	if nt != null:
		var hall: Vector2 = (nt as SimNPCTravel).nearest_hall_pos(
			faction, u.get("position", Vector2.ZERO))
		if hall != Vector2.INF:
			var clear := SimBuildings.footprint("town_hall") + 40.0
			(nt as SimNPCTravel).request_ride(u, hall + Vector2(clear, 0.0),
				SimNPCTravel.KIND_DRIVE_HOME)


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


## First free lot slot on the dealership's lot, or -1 when full.
func free_slot(building_id: int) -> int:
	var veh = _gs.get("vehicles")
	if veh == null:
		return -1
	var taken := {}
	for v: Dictionary in (veh as SimVehicles).vehicles:
		var pk: Dictionary = v.get("parking", {})
		if int(pk.get("building_id", -1)) == building_id:
			taken[int(pk.get("slot", -1))] = true
	for i in LOT_SLOTS:
		if not taken.has(i):
			return i
	return -1


## Sends a vehicle back to its assigned lot slot (P5 travel calls this at
## trip end). Arrival auto-parks via the SimVehicles physics step.
func send_home(vehicle_id: int) -> bool:
	var veh = _gs.get("vehicles")
	if veh == null:
		return false
	var v: Dictionary = (veh as SimVehicles).vehicle_by_id(vehicle_id)
	if v.is_empty():
		return false
	var pk: Dictionary = v.get("parking", {})
	if pk.is_empty():
		return false
	var b: Dictionary = _gs.get_building(int(pk.get("building_id", -1)))
	if b.is_empty():
		return false
	return (veh as SimVehicles).drive_to(vehicle_id,
		slot_pos(b, int(pk.get("slot", 0))))


## --- save/load ------------------------------------------------------------


func to_dict() -> Dictionary:
	return {"announced": _announced.keys()}


func from_dict(data: Dictionary) -> void:
	_announced.clear()
	for f in data.get("announced", []):
		_announced[String(f)] = true
