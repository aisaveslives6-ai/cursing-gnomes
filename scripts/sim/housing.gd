class_name SimHousing
extends RefCounted
## Cursing Gnomes — housing economy (Milestone 3: workers / hiring / housing).
##
## Ports the HTML build's housing economy (housingTick, housingUnitTick,
## migrateToCountryside, settleCountryside, homesteadTick, closeHomeSale,
## adoptLegacyHousing, townHouseCount, countrysideHouseCount — not its code):
##
##   - 15 houses per town, 15 countryside houses per faction (Jeremy's law).
##     A house counts as countryside when flagged so, or when it sits beyond
##     1.15x territory radius of any same-faction town.
##   - Homeless civilians: first try to move into a faction house with a
##     free bed (household cap 5); buy a for-sale home if they can afford it;
##     when their town is at 15 houses, they move out to the countryside.
##   - Survival-craft homesteads: a homeless civilian who can't buy and
##     can't move keeps a PERSONAL stockpile (never faction resources),
##     gathers thatch+lumber from trees and stone from rocks with their own
##     axe, then raises their own countryside house. Countryside settlers
##     do the same on arrival. No free houses.
##   - Coins: units earn personal wages (haul drop-offs, station work);
##     empty completed houses are listed for sale and bought for coins.
##   - ensureHomes bookkeeping: the departed release their bed claims
##     (dead or moved-out residents are pruned), a dead owner's deed passes
##     to the first surviving resident, and a destroyed home frees its
##     residents with a "My home is gone…" line.
##
## Movement is driven here (not WorkerAI) while a unit is migrating,
## homesteading, or house-hunting; WorkerAI yields to those states.
## Deterministic: no randomness in any decision — spot picks hash the unit
## id, so repeated runs agree.
##
## Pure logic — no rendering, no input, no audio.


## Jeremy's housing law (HTML TOWN_HOUSE_CAP / COUNTRYSIDE_HOUSE_CAP).
const TOWN_HOUSE_CAP := 15
const COUNTRYSIDE_HOUSE_CAP := 15

## Territory radius around a town (HTML TERRITORY_R default).
const TERRITORY_R := 420.0

## Residents per house (HTML HOUSE_CAP default 5).
const HOUSEHOLD_CAP := 5

## Homestead recipe (HTML HOMESTEAD_COST): personal materials per house.
const HOMESTEAD_COST := {"thatch": 8, "lumber": 6, "stone": 4}

## Seconds of chopping/mining per homestead material unit.
const HOMESTEAD_SWING_TIME := 2.6

## Reach for an axe/pick swing.
const HOMESTEAD_REACH := 70.0

## Starting personal coins (HTML: 20 + random*40 — deterministic here).
const START_COINS := 20.0

## Wage: coins per haul drop-off and per second of on-shift station work.
const HAUL_WAGE := 2.0
const STATION_WAGE_PER_SEC := 0.8

## House listing price (HTML adoptLegacyHousing: 100 + size).
const LIST_BASE_PRICE := 100.0

## Map bounds for countryside spot picks.
const MAP_RECT := Rect2(0, 0, 4096, 4096)

## Homestead phases.
const PHASE_GATHER := "gather"
const PHASE_WAITING := "waiting"


var _gs: GameState
var _cursor: int = 0

## --- Perf: per-walk building caches (2026-10-04; walk staggered to 20Hz
## in R25, 2026-10-05) ---
## _housing_unit_tick ran up to 4 full building scans per homeless unit per
## tick (buy-home scan, town house count, countryside count, near-town
## scan), each with per-house town-distance checks — ~3.4ms/tick, the
## second-hottest sim cost. _list_houses() already walks every building
## once per walk, so it also builds:
##   _cc_town:    "faction:town_id" -> town house count (excl. countryside)
##   _cc_country: faction -> countryside house count
##   _cc_forsale: faction -> Array of for-sale house dicts
##   _cc_halls:   Array of [faction, pos] for town-hall proximity checks
## The walk (and the occupancy repair inside it) runs every 3rd tick (20Hz,
## R15/R17/R19/R20 stagger pattern): listings/counts lag at most 2 frames,
## which is invisible at 60fps. Same-walk double sales are still impossible
## (the buy loop skips owner_unit >= 0 / for_sale == false), and the
## 15-house build cap is enforced by the LIVE count in
## _homestead_try_build, never the cache.
## Internal hot paths read the cache when fresh (see _cc_fresh); the public
## count functions keep their live computation as the fallback so external
## callers (sandbox, tests) always get correct answers.
var _tick_n := 0
var _cc_tick := -1
var _cc_town: Dictionary = {}
var _cc_country: Dictionary = {}
var _cc_forsale: Dictionary = {}
var _cc_halls: Array = []


func _init(game_state: GameState) -> void:
	_gs = game_state
	# ensureHomes repair half: a destroyed home frees its residents. Guarded
	# so test harnesses that build a second SimHousing on one GameState
	# don't double-fire the handler.
	if not _gs.bus.building_destroyed.is_connected(_on_building_destroyed):
		_gs.bus.building_destroyed.connect(_on_building_destroyed)


## One world tick: processes a staggered slice (30) of units — buy-home
## urges, homeless drift, migration walks, homesteads, listings.
## Perf (R25): the _list_houses() building walk + occupancy repair runs at
## 20Hz (every 3rd tick); readers accept the last walk's data via
## _cc_fresh(). The per-unit slice still runs every tick.
func tick(delta: float) -> void:
	_tick_n += 1
	if _tick_n % 3 == 1:
		_list_houses()
	var n: int = _gs.units.size()
	if n == 0:
		return
	var slice: int = mini(30, n)
	for i: int in range(slice):
		var u: Dictionary = _gs.units[(_cursor + i) % n]
		if u.get("alive", false):
			_housing_unit_tick(u, delta)
	_cursor = (_cursor + slice) % n


## Cache freshness: the list walk runs every 3rd tick, so readers accept
## data from the most recent walk (up to 2 frames old). _cc_tick = -1
## (never walked) is never fresh — readers fall back to the live scan.
func _cc_fresh() -> bool:
	return _cc_tick >= 0 and _tick_n - _cc_tick < 3


func _housing_unit_tick(u: Dictionary, delta: float) -> void:
	if JobDefs.is_military(String(u.get("job", ""))):
		return  # military live in barracks (GuildHiring)
	if u.has("_ride"):
		return  # SimNPCTravel owns this unit's long trip right now
	var homeless: bool = _is_homeless(u)
	# Moving out to the countryside: ride when the unit owns a vehicle,
	# otherwise keep walking until arrival.
	var move: Vector2 = u.get("_country_move", Vector2(-1, -1))
	if move.x >= 0.0:
		var nt = _gs.get("npc_travel")
		if nt != null and (nt as SimNPCTravel).take_migration_ride(u, move):
			u.erase("_country_move")  # travel restores it on arrival
			return
		if WorkerAI.move_unit(_gs, u, move, delta):
			u.erase("_country_move")
			_settle_countryside(u)
		return
	# Self-built countryside home finished? Move in.
	var ch: Dictionary = u.get("_country_home", {})
	if not ch.is_empty() and ch.get("alive", false) and ch.get("complete", false):
		u.erase("_country_home")
		_move_into(u, ch)
		return
	if not homeless:
		return
	# Try to buy a listed home.
	if _try_buy_home(u, delta):
		return
	# Town at 15 houses -> move out to the countryside (Jeremy's rule).
	# A unit already out in the wild homesteads instead of migrating twice.
	var town_id: int = int(u.get("town_id", -1))
	var faction: String = String(u.get("faction", ""))
	if town_id >= 0 and town_house_count(faction, town_id) >= TOWN_HOUSE_CAP:
		if not _near_any_town(faction, u.get("position", Vector2.ZERO),
				TERRITORY_R * 1.15):
			_homestead_tick(u, delta)
			return
		_migrate_to_countryside(u)
		return
	# Survival-craft as the last resort (HTML homestead): gather your own
	# materials and raise a countryside house. (Bed-claiming is not an
	# automatic per-tick grab in the HTML — houses are adopted once via
	# adopt_housing(); homeless civilians buy, migrate, or homestead.)
	_homestead_tick(u, delta)


## One-time adoption of empty houses for homeless civilians (HTML
## adoptLegacyHousing). Called once after worldgen / load, NOT every tick.
func adopt_housing() -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if JobDefs.is_military(String(u.get("job", ""))):
			continue
		if not _is_homeless(u):
			continue
		_claim_bed(u)


func _is_homeless(u: Dictionary) -> bool:
	var home: Dictionary = u.get("home", {})
	return home.is_empty() or not home.get("alive", false)


## Move into a house: resident list, ownership, home link.
func _move_into(u: Dictionary, house: Dictionary) -> void:
	_ensure_residents(house)
	u.erase("_buying_home")
	u.erase("_homestead")  # a buyer/settler stops survival-crafting
	var uid: int = int(u.get("id", 0))
	if not uid in (house["residents"] as Array):
		(house["residents"] as Array).append(uid)
	if int(house.get("owner_unit", -1)) < 0:
		house["owner_unit"] = uid
	house["for_sale"] = false
	u["home"] = house


func _ensure_residents(house: Dictionary) -> void:
	if not house.has("residents"):
		house["residents"] = []


## Claim a free bed in a completed faction house (town or countryside).
func _claim_bed(u: Dictionary) -> bool:
	var faction: String = String(u.get("faction", ""))
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) != "house":
			continue
		_ensure_residents(b)
		if (b["residents"] as Array).size() >= HOUSEHOLD_CAP:
			continue
		_move_into(u, b)
		return true
	return false


## Buy the cheapest listed faction house the unit can afford. Walks to it
## first when far; closes the sale on arrival.
func _try_buy_home(u: Dictionary, delta: float) -> bool:
	var faction: String = String(u.get("faction", ""))
	var cheapest: Dictionary = {}
	var cheapest_price := INF
	# Perf: for-sale list from the per-walk cache (was a full building
	# scan per homeless unit per tick). Houses sold earlier this tick are
	# still skipped via owner_unit, exactly as before.
	for b in _forsale_list(faction):
		if not (b is Dictionary):
			continue
		if not bool(b.get("alive", false)) \
				or not bool(b.get("complete", false)):
			continue
		if not bool(b.get("for_sale", false)):
			continue
		if int(b.get("owner_unit", -1)) >= 0:
			continue
		var price: float = float(b.get("price", INF))
		if price < cheapest_price:
			cheapest_price = price
			cheapest = b
	if cheapest.is_empty():
		# Nothing listed — drop the flag. A stale _buying_home freezes
		# WorkerAI (it yields on the flag), stranding the unit forever.
		u.erase("_buying_home")
		return false
	_ensure_coins(u)
	if float(u.get("coins", 0.0)) < cheapest_price:
		# Can't afford it yet — same stale-flag hazard; keep earning.
		u.erase("_buying_home")
		return false
	var up: Vector2 = u.get("position", Vector2.ZERO)
	var hp: Vector2 = cheapest.get("position", Vector2.ZERO)
	if up.distance_to(hp) > 80.0:
		u["_buying_home"] = true
		WorkerAI.move_unit(_gs, u, hp, delta)
		return true
	# Close the sale: coins to the faction treasury, deed transfers.
	u.erase("_buying_home")
	u["coins"] = float(u.get("coins", 0.0)) - cheapest_price
	_gs.resources.add_resource(faction, "gold", cheapest_price, true)
	_move_into(u, cheapest)
	cheapest["owner_unit"] = int(u.get("id", 0))
	return true


## Empty completed houses go up for sale (HTML adoptLegacyHousing).
## Also builds the per-walk building caches (see _cc_* members): one walk
## replaces the 4-per-homeless-unit full scans below.
func _list_houses() -> void:
	_cc_town.clear()
	_cc_country.clear()
	_cc_forsale.clear()
	_cc_halls.clear()
	# Town positions for the countryside test, snapshotted once per tick
	# (was recomputed per house per homeless unit inside the counters).
	var town_pos: Array = []
	for t: Dictionary in _gs.towns.values():
		town_pos.append([String(t.get("faction", "")),
			t.get("position", Vector2.ZERO)])
	# ensureHomes parity: alive-unit index for occupancy repair, built
	# lazily — only when at least one house actually has residents.
	var unit_index: Dictionary = {}
	var index_built := false
	for b: Dictionary in _gs.buildings:
		var alive: bool = b.get("alive", false)
		var btype: String = String(b.get("type", ""))
		var faction: String = String(b.get("faction", ""))
		if btype == "town_hall" or btype == "hall":
			# _near_any_town parity: alive halls only, complete not required.
			if alive:
				_cc_halls.append([faction, b.get("position", Vector2.ZERO)])
			continue
		if btype != "house" or not alive:
			continue
		# House counts (live parity: alive houses, built or under
		# construction — the public counters don't require complete).
		if _is_countryside_house_fast(b, town_pos):
			_cc_country[faction] = int(_cc_country.get(faction, 0)) + 1
		else:
			var ckey := faction + ":" + str(int(b.get("town_id", -2)))
			_cc_town[ckey] = int(_cc_town.get(ckey, 0)) + 1
		# Sale listings keep the original gate: completed houses only.
		if not b.get("complete", false):
			continue
		_ensure_residents(b)
		if not (b["residents"] as Array).is_empty():
			if not index_built:
				for u: Dictionary in _gs.units:
					if u.get("alive", false):
						unit_index[int(u.get("id", 0))] = u
				index_built = true
			_repair_occupancy(b, unit_index)
		if not (b["residents"] as Array).is_empty():
			continue
		if bool(b.get("for_sale", false)):
			_cc_forsale_get(faction).append(b)
			continue
		b["for_sale"] = true
		b["price"] = LIST_BASE_PRICE + SimBuildings.footprint("house")
		b["owner_unit"] = -1
		_cc_forsale_get(faction).append(b)
	_cc_tick = _tick_n


## HTML ensureHomes parity: release the departed's bed claims and repair
## ownership. A resident only keeps their bed while alive AND still homed
## here (by building id). Without this, dead residents hold beds forever —
## blocking births (HOUSEHOLD_CAP) and keeping the house off the for-sale
## market permanently. A dead or moved-out owner's deed passes to the first
## surviving resident (owned homes are never listed); a house emptied this
## way falls through to the listing logic below.
func _repair_occupancy(house: Dictionary, unit_index: Dictionary) -> void:
	var bid: int = int(house.get("id", -1))
	var kept: Array = []
	for rid in (house["residents"] as Array):
		var u: Dictionary = unit_index.get(int(rid), {})
		if u.is_empty():
			continue
		var uh: Dictionary = u.get("home", {})
		if uh.is_empty() or int(uh.get("id", -2)) != bid:
			continue
		kept.append(int(rid))
	if kept.size() != (house["residents"] as Array).size():
		house["residents"] = kept
	var owner: int = int(house.get("owner_unit", -1))
	if not owner in kept:
		if kept.is_empty():
			house["owner_unit"] = -1
		else:
			house["owner_unit"] = int(kept[0])
			house["for_sale"] = false  # owned homes are never listed


## HTML ensureHomes repair half: a destroyed building frees whoever called
## it home. Their link is cleared (the homeless flow picks them back up to
## buy again) and house residents get the "My home is gone…" line.
func _on_building_destroyed(b: Dictionary) -> void:
	var bid: int = int(b.get("id", -1))
	var is_house: bool = String(b.get("type", "")) == "house"
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var home: Dictionary = u.get("home", {})
		if home.is_empty() or int(home.get("id", -2)) != bid:
			continue
		u["home"] = {}
		if is_house:
			_gs.bus.unit_said.emit(int(u.get("id", 0)), "My home is gone…")


## Same decision as _is_countryside_house(), but against a town-position
## snapshot instead of re-walking _gs.towns per house.
func _is_countryside_house_fast(b: Dictionary, town_pos: Array) -> bool:
	if bool(b.get("countryside", false)):
		return true
	var faction: String = String(b.get("faction", ""))
	var bp: Vector2 = b.get("position", Vector2.ZERO)
	for t in town_pos:
		if String(t[0]) != faction:
			continue
		if bp.distance_to(t[1] as Vector2) <= TERRITORY_R * 1.15:
			return false
	return true


func _cc_forsale_get(faction: String) -> Array:
	var arr: Array = _cc_forsale.get(faction, [])
	_cc_forsale[faction] = arr
	return arr


## For-sale houses of a faction: per-walk cache when fresh, single live
## scan otherwise (tests / external callers outside tick()).
func _forsale_list(faction: String) -> Array:
	if _cc_fresh():
		return _cc_forsale.get(faction, [])
	var out: Array = []
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("type", "")) != "house":
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if bool(b.get("for_sale", false)) \
				and int(b.get("owner_unit", -1)) < 0:
			out.append(b)
	return out


## ---- Countryside migration -------------------------------------------------
## Jeremy's rule: a homeless civilian whose town already has 15 houses moves
## out — picks a spot outside every town's territory and walks there.


func _migrate_to_countryside(u: Dictionary) -> void:
	var faction: String = String(u.get("faction", ""))
	var hall: Dictionary = _nearest_hall(u)
	var hp: Vector2 = u.get("position", Vector2.ZERO)
	if not hall.is_empty():
		hp = hall.get("position", hp)
	var uid: int = int(u.get("id", 0))
	for i: int in range(24):
		var a: float = _hash01(uid * 31 + i) * TAU
		var d: float = 520.0 + _hash01(uid * 57 + i * 3) * 380.0
		var x: float = clampf(hp.x + cos(a) * d, 90.0, MAP_RECT.size.x - 90.0)
		var y: float = clampf(hp.y + sin(a) * d, 90.0, MAP_RECT.size.y - 90.0)
		var spot := Vector2(x, y)
		if _near_any_town(faction, spot, TERRITORY_R * 1.25):
			continue
		u["_country_move"] = spot
		return


func _settle_countryside(u: Dictionary) -> void:
	var faction: String = String(u.get("faction", ""))
	if countryside_house_count(faction) >= COUNTRYSIDE_HOUSE_CAP:
		return  # countryside full too — roughing it
	# Live off the land: released from faction labor, gathers their own.
	u["job"] = "worker"
	WorkerAI.assign_job(u, "worker")
	_start_homestead(u, u.get("position", Vector2.ZERO))


func _near_any_town(faction: String, spot: Vector2, radius: float) -> bool:
	# Perf: hall positions cached per walk in _list_houses (was a full
	# building scan per call; _migrate_to_countryside calls this up to
	# 24x per unit).
	if _cc_fresh():
		for h in _cc_halls:
			if String(h[0]) != faction:
				continue
			if (h[1] as Vector2).distance_to(spot) < radius:
				return true
		return false
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if not String(b.get("type", "")) in ["town_hall", "hall"]:
			continue
		if (b.get("position", Vector2.ZERO) as Vector2).distance_to(spot) < radius:
			return true
	return false


func _nearest_hall(u: Dictionary) -> Dictionary:
	var faction: String = String(u.get("faction", ""))
	var best: Dictionary = {}
	var best_d := INF
	var up: Vector2 = u.get("position", Vector2.ZERO)
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if not String(b.get("type", "")) in ["town_hall", "hall"]:
			continue
		var d: float = (b.get("position", Vector2.ZERO) as Vector2).distance_to(up)
		if d < best_d:
			best_d = d
			best = b
	return best


## ---- Survival-craft homesteads ---------------------------------------------
## A homeless civilian who can't buy a town home gathers their OWN building
## materials (personal stockpile u["craft"], never faction resources) and
## raises their own house. Trees yield lumber + thatch (leafy byproduct);
## rocks yield stone.


## Who may survival-craft: homeless civilians only. Shop staff tend their
## stores; roadbuilders keep the roads — don't yank them.
func _homestead_eligible(u: Dictionary) -> bool:
	if not u.get("alive", false):
		return false
	if JobDefs.is_military(String(u.get("job", ""))):
		return false
	var job: String = String(u.get("job", ""))
	if job in ["shopkeeper", "cashier", "roadbuilder"]:
		return false
	return true


func _start_homestead(u: Dictionary, spot: Vector2) -> void:
	if not _homestead_eligible(u):
		return
	if not _is_homeless(u):
		return
	if not u.has("craft"):
		u["craft"] = {"thatch": 0, "lumber": 0, "stone": 0}
	# Jeremy 2026-10-10 P0 (homestead-in-lake photo): the house must never
	# start on water — validate the spot and nudge to nearest dry land.
	spot = _dry_homestead_spot(spot)
	u["_homestead"] = {"phase": PHASE_GATHER,
		"need": HOMESTEAD_COST.duplicate(),
		"target": -1, "tgt_kind": "", "swing_t": 0.0, "spot": spot}


## True when a homestead house footprint would sit on water (HTML's
## footprintInWater guard): center + 4 cardinals at the house footprint
## radius probed against the baked terrain grid. No-ops on empty map_data
## (test stubs keep the old behavior).
func _homestead_on_water(spot: Vector2) -> bool:
	return SimBuildings.footprint_in_water(_gs.map_data, "house", spot)


## Nudge a waterlogged homestead spot to the nearest dry land: spiral out
## in 8 compass directions at growing rings until the house footprint is
## fully dry. Bounded (~1100px, rare path, cheap); falls back to the raw
## spot if the whole neighborhood is water (old behavior, never worse).
## Deterministic: fixed compass order, no randomness.
func _dry_homestead_spot(spot: Vector2) -> Vector2:
	if not _homestead_on_water(spot):
		return spot
	for ring in range(1, 17):
		var d := 64.0 * float(ring)
		for k in range(8):
			var a := TAU * float(k) / 8.0
			var cand := spot + Vector2(cos(a), sin(a)) * d
			cand.x = clampf(cand.x, 90.0, MAP_RECT.size.x - 90.0)
			cand.y = clampf(cand.y, 90.0, MAP_RECT.size.y - 90.0)
			if not _homestead_on_water(cand):
				return cand
	return spot


func _homestead_tick(u: Dictionary, delta: float) -> void:
	var hs: Dictionary = u.get("_homestead", {})
	if hs.is_empty():
		# Gate: only start when the town or countryside caps force it.
		var faction: String = String(u.get("faction", ""))
		var town_id: int = int(u.get("town_id", -1))
		var town_full: bool = town_id >= 0 \
			and town_house_count(faction, town_id) >= TOWN_HOUSE_CAP
		var country_full: bool = countryside_house_count(faction) \
			>= COUNTRYSIDE_HOUSE_CAP
		if town_full or country_full:
			_start_homestead(u, u.get("position", Vector2.ZERO))
		return
	if not _is_homeless(u) or not _homestead_eligible(u):
		u.erase("_homestead")
		return
	var phase: String = String(hs.get("phase", PHASE_GATHER))
	if phase == PHASE_WAITING:
		_homestead_try_build(u, hs)
		return
	if phase != PHASE_GATHER:
		u.erase("_homestead")
		return
	if not u.has("craft"):
		u["craft"] = {"thatch": 0, "lumber": 0, "stone": 0}
	var craft: Dictionary = u["craft"]
	var need: Dictionary = hs.get("need", HOMESTEAD_COST)
	if int(craft.get("thatch", 0)) >= int(need.get("thatch", 8)) \
			and int(craft.get("lumber", 0)) >= int(need.get("lumber", 6)) \
			and int(craft.get("stone", 0)) >= int(need.get("stone", 4)):
		_homestead_try_build(u, hs)
		return
	# Trees first (lumber + thatch byproduct), then stone from rocks.
	var kind: String = "tree" if int(craft.get("thatch", 0)) < int(need.get("thatch", 8)) \
		or int(craft.get("lumber", 0)) < int(need.get("lumber", 6)) else "rock"
	var site_id: int = int(hs.get("target", -1))
	var site: Dictionary = _gs.get_work_site(site_id) if site_id >= 0 else {}
	if site.is_empty() or float(site.get("amount", 0.0)) <= 0.0 \
			or String(hs.get("tgt_kind", "")) != kind:
		site = _nearest_node(u, kind)
		if site.is_empty():
			return  # nothing in reach — drift, retry next tick
		hs["target"] = int(site["id"])
		hs["tgt_kind"] = kind
	hs["gather_target"] = int(site["id"])  # pin: WorkerAI leaves us alone
	var up: Vector2 = u.get("position", Vector2.ZERO)
	var sp: Vector2 = site.get("position", Vector2.ZERO)
	if up.distance_to(sp) > HOMESTEAD_REACH:
		WorkerAI.move_unit(_gs, u, sp, delta)
		hs["swing_t"] = 0.0
		return
	hs["swing_t"] = float(hs.get("swing_t", 0.0)) + delta
	if float(hs.get("swing_t", 0.0)) >= HOMESTEAD_SWING_TIME:
		hs["swing_t"] = 0.0
		_homestead_swing(u, hs, site, kind)


## One axe/pick swing: personal materials in, node durability down.
func _homestead_swing(u: Dictionary, hs: Dictionary, site: Dictionary,
		kind: String) -> void:
	var craft: Dictionary = u["craft"]
	if kind == "tree":
		craft["lumber"] = int(craft.get("lumber", 0)) + 1
		craft["thatch"] = int(craft.get("thatch", 0)) + 1  # leafy byproduct
	else:
		craft["stone"] = int(craft.get("stone", 0)) + 1
	_gs.deplete_site(int(site["id"]), 1.0)
	if float(_gs.get_work_site(int(site["id"])).get("amount", 0.0)) <= 0.0:
		hs["target"] = -1  # node died — retarget next tick


## Materials done -> raise the house. Respects the 15/faction countryside
## cap (materials are kept when the cap forces a wait).
func _homestead_try_build(u: Dictionary, hs: Dictionary) -> void:
	var faction: String = String(u.get("faction", ""))
	# Jeremy 2026-10-04 perf note: the cap check here deliberately uses
	# the LIVE count, not the tick cache — the house is placed below, so a
	# second builder later in the same tick must see it (old behavior).
	if _countryside_house_count_live(faction) >= COUNTRYSIDE_HOUSE_CAP:
		hs["phase"] = PHASE_WAITING
		return
	var spot: Vector2 = hs.get("spot", Vector2(-1, -1))
	if spot.x < 0.0 or _spot_blocked(u, spot):
		spot = _find_wild_spot(u)
		if spot.x < 0.0:
			hs["phase"] = PHASE_WAITING
			return
		hs["spot"] = spot
	# Jeremy 2026-10-10 P0 (iPhone catch — a homestead house photographed
	# under construction in a lake): homestead placement never went
	# through SimBuildings.can_place_at, so the no-water rule didn't
	# apply. Validate the footprint and nudge to the nearest dry land.
	spot = _dry_spot_near(u, spot)
	if spot.x < 0.0:
		hs["phase"] = PHASE_WAITING  # no dry land in reach — keep gathering, retry later
		return
	hs["spot"] = spot
	var b: Dictionary = _gs.add_building({
		"type": "house",
		"faction": faction,
		"town_id": -1,
		"position": spot,
		"alive": true,
		"complete": false,
		"progress": 0.05,
		"hp": SimBuildings.footprint("house"),
		"max_hp": SimBuildings.footprint("house"),
	})
	b["countryside"] = true  # counts toward the rural cap, not the town cap
	b["for_sale"] = false
	b["owner_unit"] = int(u.get("id", 0))
	b["residents"] = []
	u["_country_home"] = b  # the housing tick moves them in on completion
	u.erase("_homestead")


func _spot_blocked(u: Dictionary, spot: Vector2) -> bool:
	var faction: String = String(u.get("faction", ""))
	# Jeremy 2026-10-10 (homestead-in-lake P0): a water spot is blocked, so
	# _homestead_try_build re-picks via _find_wild_spot (which filters
	# through this same check) and no homestead house ever lands in a lake.
	if _homestead_on_water(spot):
		return true
	if _near_any_town(faction, spot, TERRITORY_R * 1.2):
		return true
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		var bp: Vector2 = b.get("position", Vector2.ZERO)
		if bp.distance_to(spot) < 60.0:
			return true
	return false


## Jeremy 2026-10-10 P0: the no-water rule (SimBuildings.can_place_at /
## footprint_in_water) never applied to homestead spots. Returns the
## spot unchanged when the house footprint is dry; otherwise nudges
## outward in expanding rings to the nearest dry, unblocked spot, or
## Vector2(-1, -1) when none is in reach. No-ops (identity) when
## map_data is empty — the old pre-guard behavior is preserved for
## callers without terrain.
func _dry_spot_near(u: Dictionary, spot: Vector2) -> Vector2:
	var md: Dictionary = _gs.map_data
	if not SimBuildings.footprint_in_water(md, "house", spot):
		return spot
	var step: float = SimBuildings.footprint("house") * 2.0
	for ring in range(1, 9):
		var d: float = step * float(ring)
		for k in range(12):
			var a: float = TAU * float(k) / 12.0
			var cand := Vector2(
				clampf(spot.x + cos(a) * d, 90.0, MAP_RECT.size.x - 90.0),
				clampf(spot.y + sin(a) * d, 90.0, MAP_RECT.size.y - 90.0))
			if _spot_blocked(u, cand):
				continue
			if SimBuildings.footprint_in_water(md, "house", cand):
				continue
			return cand
	return Vector2(-1, -1)


## Find a build spot in the wilds: outside every same-faction town's
## territory (deterministic spot picks).
func _find_wild_spot(u: Dictionary) -> Vector2:
	var faction: String = String(u.get("faction", ""))
	var up: Vector2 = u.get("position", Vector2.ZERO)
	var uid: int = int(u.get("id", 0))
	for i: int in range(24):
		var a: float = _hash01(uid * 13 + i * 7) * TAU
		var d: float = 60.0 + _hash01(uid * 29 + i) * 200.0
		var spot := Vector2(
			clampf(up.x + cos(a) * d, 90.0, MAP_RECT.size.x - 90.0),
			clampf(up.y + sin(a) * d, 90.0, MAP_RECT.size.y - 90.0))
		if _spot_blocked(u, spot):
			continue
		# Jeremy 2026-10-10 P0: wild spots must be dry too (no-water rule).
		# No-ops when map_data is empty (old test stubs keep old behavior).
		if SimBuildings.footprint_in_water(_gs.map_data, "house", spot):
			continue
		return spot
	return Vector2(-1, -1)


func _nearest_node(u: Dictionary, kind: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var up: Vector2 = u.get("position", Vector2.ZERO)
	for s: Dictionary in _gs.work_sites:
		if float(s.get("amount", 0.0)) <= 0.0:
			continue
		if String(s.get("kind", "")) != kind:
			continue
		var d: float = (s.get("position", Vector2.ZERO) as Vector2).distance_to(up)
		if d < best_d:
			best_d = d
			best = s
	return best


## ---- House counts --------------------------------------------------------

## Houses (built or under construction) belonging to a town — countryside
## houses don't count against the town's 15.
func town_house_count(faction: String, town_id: int) -> int:
	# Perf: per-walk cache when fresh (built in _list_houses); live scan
	# otherwise for external callers.
	if _cc_fresh():
		return int(_cc_town.get(faction + ":" + str(town_id), 0))
	return _town_house_count_live(faction, town_id)


## Live town-house computation (no cache). Used by the fallback above and
## by _homestead_try_build, where the build decision must see houses
## placed earlier in the same tick (the cache is a tick-start snapshot).
func _town_house_count_live(faction: String, town_id: int) -> int:
	var n := 0
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) != "house":
			continue
		if _is_countryside_house(b):
			continue
		if int(b.get("town_id", -2)) != town_id:
			continue
		n += 1
	return n


## Countryside houses (built or under construction) for a faction.
func countryside_house_count(faction: String) -> int:
	# Perf: per-walk cache when fresh (built in _list_houses); live scan
	# otherwise for external callers.
	if _cc_fresh():
		return int(_cc_country.get(faction, 0))
	return _countryside_house_count_live(faction)


## Live countryside computation (no cache). See _town_house_count_live.
func _countryside_house_count_live(faction: String) -> int:
	var n := 0
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) != "house":
			continue
		if _is_countryside_house(b):
			n += 1
	return n


## A house counts as countryside when flagged so, or when it sits beyond
## 1.15x territory radius of any same-faction town (covers pre-rule saves).
func _is_countryside_house(b: Dictionary) -> bool:
	if bool(b.get("countryside", false)):
		return true
	var faction: String = String(b.get("faction", ""))
	var bp: Vector2 = b.get("position", Vector2.ZERO)
	for t: Dictionary in _gs.towns.values():
		if String(t.get("faction", "")) != faction:
			continue
		var tp: Vector2 = t.get("position", Vector2.ZERO)
		if bp.distance_to(tp) <= TERRITORY_R * 1.15:
			return false
	return true


## ---- Coins -----------------------------------------------------------------

## Personal wages (HTML: units start with 20-40 coins; workers earn at
## workplaces). Deterministic start from the unit id.
func _ensure_coins(u: Dictionary) -> void:
	if u.has("coins"):
		return
	u["coins"] = START_COINS + float(int(u.get("id", 0)) % 40)


## Deterministic 0..1 hash for spot picks (no randomness in decisions).
static func _hash01(n: int) -> float:
	var x: int = (n * 1103515245 + 12345) & 0x7fffffff
	return float(x % 10000) / 10000.0
