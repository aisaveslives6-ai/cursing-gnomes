class_name SimIndustry
extends RefCounted
## Cursing Gnomes — industrial oil production, the traveling trader, and
## player-directed gather orders (Milestone 6b: world & environment / economy).
##
## 1. OIL PRODUCTION:
##    - Developed industrial lots: HTML's zone tick paid oil = 2.2*lvl*dt/
##      DAY_LENGTH (DAY_LENGTH=3600), plus wood 1.8 and gold 1.4 at the same
##      formula. Godot zones carry no density level, so each completed
##      industrial building (BUILDING_ZONE "I") inside an industrial zone of
##      its faction produced at lvl=1 — verbatim rates.
##    - Jeremy 2026-10-05 (supersedes): oil comes ONLY from oil pumps
##      (0.8/s each in an industrial zone — see SimZoning.tick). The
##      HTML lot-oil rate is RETIRED: it fired on every industrial
##      building, so pumps double-dipped and non-pump buildings leaked
##      oil against the design order. Lots still pay wood/gold verbatim.
##    - Workers at industrial workplaces (RETIRED 2026-10-05): HTML paid
##      +0.15 oil per tick to on-site workers — but the "workplace"
##      WorkerAI hook was never implemented (no code ever sets
##      unit["workplace"]), and implementing it now would add a SECOND
##      oil source, violating Jeremy's 2026-10-05 "oil comes ONLY from
##      oil pumps" order. The dead per-tick O(units) loop is removed
##      rather than hooked up. Pumps in industrial zones are the sole
##      oil source (0.8/s each, SimZoning.tick).
## 2. CAPTAIN FUNKY PANTS — the neutral traveling trader (HTML verbatim):
##    finite caravan stock, slow off-map restock, timed visits near a random
##    hall, 1:1 player barter, deposits, and AI auto-trading. All NPC trade
##    dialogue stays 100% offline/scripted (Jeremy's law).
##    Presentation (launch-readiness 2026-10-06, gate 1): TraderLayer draws
##    the caravan on the map from bus.trader_arrived/trader_left and opens
##    the TraderPanel (scripts/ui/trader_panel.gd, the #funky-trade-panel
##    port) on tap; arrival/departure also publish Gazette stories.
## 3. PLAYER GATHER ORDERS — the tap-tree "Cut tree" flow (HTML
##    orderWorkersGather verbatim): up to 6 nearest free workers of the
##    faction are pointed at a work site. The worker-side response
##    (work_site/work_state fields) is a WorkerAI hook.
##
## Pure logic — no rendering, no input, no audio.


## HTML zone-lot rates per second at lvl 1 (1.8/3600, 1.4/3600, verbatim).
## Jeremy 2026-10-05: oil is pumps-only, so the HTML lot-oil rate
## (2.2/3600) is RETIRED — it used to pay oil on every industrial
## building, contradicting "oil comes ONLY from oil pumps" and letting
## pumps double-dip. Lots still pay wood/gold.
const LOT_WOOD_PER_SEC := 1.8 / 3600.0
const LOT_GOLD_PER_SEC := 1.4 / 3600.0
## RETIRED 2026-10-05: HTML's per-tick 0.15 oil for on-site industrial
## workers was never wired (no WorkerAI "workplace" hook) and would
## contradict the oil-pumps-only order — constants removed with the loop.

## Captain Funky Pants (HTML values, verbatim).
const FUNKY_SPEED := 55.0
const FUNKY_STOCK := {"gold": 400.0, "wood": 500.0, "food": 200.0,
	"seeds": 40.0, "oil": 60.0}
const FUNKY_MAX_STOCK := {"gold": 800.0, "wood": 900.0, "food": 400.0,
	"seeds": 80.0, "oil": 120.0}
const FUNKY_RESTOCK_PER_SEC := 0.15
const FUNKY_FIRST_VISIT_MIN := 180.0
const FUNKY_FIRST_VISIT_MAX := 300.0
const FUNKY_VISIT_MIN := 90.0
const FUNKY_VISIT_MAX := 150.0
const FUNKY_NEXT_VISIT_MIN := 480.0
const FUNKY_NEXT_VISIT_MAX := 900.0
const FUNKY_AI_TRADE_RATE := 0.25  # HTML: dt * 0.25 roll
const FUNKY_DEPOSIT_CAP_FRAC := 0.92
const FUNKY_DEPOSIT_MAX := 40.0
const FUNKY_BUY_NEED := 30.0
const FUNKY_BUY_MIN_STOCK := 15.0
const FUNKY_BUY_GIVE := 25.0
const FUNKY_BUY_TAKE := 15.0

## Gather orders (HTML orderWorkersGather, verbatim: 6 workers max).
const EATERY_PAYOUT_INTERVAL := 33.0  # HTML: every ~33 sim-seconds
const EATERY_OPEN_START := 7.0        # HTML: timeOfDay 7..22
const EATERY_OPEN_END := 22.0
const EATERY_PAY_MIN := 3             # HTML: 3 + floor(rand * 4)
const EATERY_PAY_MAX := 6
## Eatery building types that earn income (HTML only had "restaurant";
## the undead's soul_cafe is their faction-unique eatery, so it earns too).
const EATERY_TYPES := ["restaurant", "soul_cafe"]
var _eatery_accum := 0.0
const ORDER_MAX_WORKERS := 6


var _gs: GameState
var _rng := RandomNumberGenerator.new()

## Trader state.
var funky_stock: Dictionary = {}
var funky_on_map: bool = false
var funky_pos := Vector2(-9999, -9999)
var funky_visit_timer: float = 0.0
var funky_visit_left: float = 0.0
var _funky_wander_target := Vector2.ZERO
var _funky_wander_t: float = 0.0
var _funky_facing: float = 1.0


func _init(game_state: GameState) -> void:
	_gs = game_state
	_rng.randomize()


## Resets industry + trader state. Called by GameState.setup() on new game.
func reset() -> void:
	funky_stock = FUNKY_STOCK.duplicate()
	funky_on_map = false
	funky_pos = Vector2(-9999, -9999)
	funky_visit_timer = _rng.randf_range(FUNKY_FIRST_VISIT_MIN,
		FUNKY_FIRST_VISIT_MAX)
	funky_visit_left = 0.0
	_funky_wander_t = 0.0


## ---- oil production -----------------------------------------------------


## Per-tick industrial production. Call once per physics tick from the world.
## (2026-10-05: workplace-oil loop retired — oil is pumps-only per
## Jeremy's design order, so no per-unit workplace scan runs here.)
func tick(delta: float) -> void:
	_tick_lot_production(delta)
	_tick_eatery_income(delta)
	tick_trader(delta)


## Completed industrial buildings inside industrial zones of their faction
## produce wood/gold at HTML's verbatim zone-lot rates.
## Jeremy 2026-10-05: NO oil here — oil comes only from oil pumps
## (SimZoning.tick, 0.8/s in an industrial zone). The retired HTML lot-oil
## rate is documented above; keeping it would double-dip pumps and leak
## oil from every industrial building.
func _tick_lot_production(delta: float) -> void:
	if _gs.zoning == null:
		return
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if bool(b.get("hoa_lien", false)):
			continue  # HOA Karen lien — production seized until she leaves
		var faction: String = String(b.get("faction", ""))
		if String(SimZoning.BUILDING_ZONE.get(String(b.get("type", "")),
				"")) != SimZoning.INDUSTRIAL:
			continue
		if _gs.zoning.zone_at(b.get("position", Vector2.ZERO),
				faction) != SimZoning.INDUSTRIAL:
			continue
		# Bill's cybernetics: assimilated buildings run at -15%.
		var borg_mult := DisasterSim.borg_building_mult(b)
		_gs.resources.add_resource(faction, "wood",
			LOT_WOOD_PER_SEC * delta * borg_mult)
		_gs.resources.add_resource(faction, "gold",
			LOT_GOLD_PER_SEC * delta * borg_mult)


func _building_by_id(bid: int) -> Dictionary:
	# Jeremy 2026-10-05 perf: shared O(1) id index on GameState.
	return _gs.get_building(bid)


## ---- Eatery income --------------------------------------------------------


## Eatery income (HTML eateryIncomeTick, verbatim economics): every
## ~33 sim-seconds, each completed, living, STAFFED eatery pays its faction
## 3-6 gold — but only 07:00-22:00 (kitchens close at night). "Staffed"
## mirrors the hire roster: a living shopkeeper whose station record points
## at the building (GuildHiring._holder_matches parity).
func _tick_eatery_income(delta: float) -> void:
	_eatery_accum += delta
	if _eatery_accum < EATERY_PAYOUT_INTERVAL:
		return
	_eatery_accum = 0.0
	var hour: float = WorkerAI.hour_of_day(_gs)
	if hour < EATERY_OPEN_START or hour > EATERY_OPEN_END:
		return
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if not String(b.get("type", "")) in EATERY_TYPES:
			continue
		if not _eatery_staffed(b):
			continue
		var payout := float(randi_range(EATERY_PAY_MIN, EATERY_PAY_MAX))
		_gs.resources.add_resource(String(b.get("faction", "")), "gold",
			payout)


## True when a living shopkeeper of the building's faction has this building
## as their station (HTML's `b.shopkeeper && b.shopkeeper.alive`).
func _eatery_staffed(b: Dictionary) -> bool:
	var bid: int = int(b.get("id", -1))
	var faction: String = String(b.get("faction", ""))
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("job", "")) != "shopkeeper":
			continue
		var st: Dictionary = u.get("station", {})
		if int(st.get("building_id", -1)) == bid:
			return true
	return false


## ---- Captain Funky Pants -----------------------------------------------


## Trader per-tick: restock off-map, timed visits, wandering, AI trades.
func tick_trader(delta: float) -> void:
	if not funky_on_map:
		for k in funky_stock.keys():
			var cap: float = float(FUNKY_MAX_STOCK.get(k, 100.0))
			if float(funky_stock[k]) < cap:
				funky_stock[k] = minf(cap,
					float(funky_stock[k]) + FUNKY_RESTOCK_PER_SEC * delta)
		funky_visit_timer -= delta
		if funky_visit_timer <= 0.0:
			_begin_visit()
		return
	funky_visit_left -= delta
	if funky_visit_left <= 0.0:
		_end_visit()
		return
	_funky_wander_t -= delta
	if _funky_wander_t <= 0.0:
		_funky_wander_t = _rng.randf_range(10.0, 22.0)
		_funky_wander_target = funky_pos + Vector2(
			_rng.randf_range(-90.0, 90.0), _rng.randf_range(-90.0, 90.0))
	var to: Vector2 = _funky_wander_target - funky_pos
	if to.length() > 6.0:
		funky_pos += to.normalized() * FUNKY_SPEED * delta
		_funky_facing = 1.0 if to.x >= 0.0 else -1.0
	if _rng.randf() < FUNKY_AI_TRADE_RATE * delta:
		try_ai_trade()


func _begin_visit() -> void:
	var halls: Array[Dictionary] = []
	for b: Dictionary in _gs.buildings:
		if b.get("alive", false) \
				and String(b.get("type", "")) in ["town_hall", "hall"]:
			halls.append(b)
	if halls.is_empty():
		funky_pos = Vector2(2048, 2048)
	else:
		var hall: Dictionary = halls[_rng.randi_range(0, halls.size() - 1)]
		funky_pos = hall.get("position", Vector2(2048, 2048)) \
			+ Vector2(_rng.randf_range(-100.0, 100.0),
				_rng.randf_range(120.0, 200.0))
	funky_on_map = true
	funky_visit_left = _rng.randf_range(FUNKY_VISIT_MIN, FUNKY_VISIT_MAX)
	_funky_wander_t = 0.0
	if _gs.bus.has_signal("trader_arrived"):
		_gs.bus.trader_arrived.emit("Captain Funky Pants", funky_pos)
	# HTML parity (fix79 beginVisit systemMsg): the player must know the
	# caravan is here — the Gazette story lands in the News app. The
	# TraderLayer (scripts/world/trader_layer.gd) draws the caravan on the
	# map and opens the trade panel on tap.
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs,
		"Captain Funky Pants' caravan has arrived — limited stock!",
		"The traveling trader's caravan is visiting the region. Tap the caravan to barter — stock is limited, darlings!",
		"trade")


func _end_visit() -> void:
	funky_on_map = false
	funky_pos = Vector2(-9999, -9999)
	funky_visit_left = 0.0
	funky_visit_timer = _rng.randf_range(FUNKY_NEXT_VISIT_MIN,
		FUNKY_NEXT_VISIT_MAX)
	if _gs.bus.has_signal("trader_left"):
		_gs.bus.trader_left.emit("Captain Funky Pants")
	# HTML parity (fix79 endVisit systemMsg): the trade panel auto-closes
	# via the TraderLayer's trader_left listener.
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs,
		"Captain Funky Pants packs up the caravan",
		"The traveling trader has moved on. It will be back — Funky always comes back.",
		"trade")


## 1:1 barter with the caravan (HTML funkyTrade, verbatim rules):
## caravan must be visiting, the faction must have the goods, the caravan
## must have stock, and there must be warehouse room for the take.
func trade(faction: String, give: String, take: String, give_amt: float,
		take_amt: float) -> bool:
	if not funky_on_map:
		return false
	if not (give in Config.RESOURCES) or not (take in Config.RESOURCES):
		return false
	if _gs.resources.get_amount(faction, give) < give_amt:
		return false
	if float(funky_stock.get(take, 0.0)) < take_amt:
		return false
	var room: float = _gs.resources.get_cap(faction, take) \
		- _gs.resources.get_amount(faction, take)
	if room < take_amt:
		return false
	_gs.resources.spend(faction, {give: give_amt})
	funky_stock[give] = float(funky_stock.get(give, 0.0)) + give_amt
	funky_stock[take] = float(funky_stock.get(take, 0.0)) - take_amt
	_gs.resources.add_resource(faction, take, take_amt)
	if _gs.bus.has_signal("trade_done"):
		_gs.bus.trade_done.emit(faction, give, take, give_amt, take_amt)
	return true


## Deposit goods with the caravan (HTML funkyDeposit): capped at max stock.
func deposit(faction: String, res: String, amt: float) -> bool:
	if not funky_on_map:
		return false
	if not (res in Config.RESOURCES):
		return false
	if _gs.resources.get_amount(faction, res) < amt:
		return false
	_gs.resources.spend(faction, {res: amt})
	var cap: float = float(FUNKY_MAX_STOCK.get(res, 999.0))
	funky_stock[res] = minf(cap, float(funky_stock.get(res, 0.0)) + amt)
	return true


## AI factions auto-trade while the caravan visits (HTML tryAiFunkyTrade,
## verbatim): deposit excess wood/gold/food, buy what they lack.
func try_ai_trade() -> void:
	if not funky_on_map:
		return
	for faction: String in _gs.active_factions:
		if faction == _gs.player_faction and _rng.randf() < 0.7:
			continue
		for key in ["wood", "gold", "food"]:
			var have: float = _gs.resources.get_amount(faction, key)
			var cap: float = _gs.resources.get_cap(faction, key)
			if have > cap * FUNKY_DEPOSIT_CAP_FRAC \
					and float(funky_stock.get(key, 0.0)) \
					< float(FUNKY_MAX_STOCK.get(key, 100.0)):
				var amt: float = minf(FUNKY_DEPOSIT_MAX,
					floorf(have - cap * 0.7))
				if amt > 5.0:
					_gs.resources.spend(faction, {key: amt})
					funky_stock[key] = \
						float(funky_stock.get(key, 0.0)) + amt
		for take in ["food", "wood", "gold", "oil", "seeds"]:
			if _gs.resources.get_amount(faction, take) > FUNKY_BUY_NEED:
				continue
			if float(funky_stock.get(take, 0.0)) < FUNKY_BUY_MIN_STOCK:
				continue
			var room: float = _gs.resources.get_cap(faction, take) \
				- _gs.resources.get_amount(faction, take)
			if room < FUNKY_BUY_TAKE:
				continue
			var give := "gold"
			if _gs.resources.get_amount(faction, "wood") \
					> _gs.resources.get_amount(faction, "gold"):
				give = "wood"
			if _gs.resources.get_amount(faction, give) < FUNKY_BUY_GIVE:
				continue
			_gs.resources.spend(faction, {give: FUNKY_BUY_GIVE})
			funky_stock[give] = float(funky_stock.get(give, 0.0)) \
				+ FUNKY_BUY_GIVE
			funky_stock[take] = float(funky_stock.get(take, 0.0)) \
				- FUNKY_BUY_TAKE
			_gs.resources.add_resource(faction, take, FUNKY_BUY_TAKE)
			break


## ---- player gather orders -----------------------------------------------


## "Cut tree" order (HTML orderWorkersGather, verbatim): sends up to
## ORDER_MAX_WORKERS (6) nearest free workers of the faction to a work
## site. Sets the WorkerAI fields work_site / work_target_pos / work_state
## ("to_resource") — the response side is a WorkerAI hook.
## Returns the number of workers assigned.
func order_gather(site_id: int, faction: String = "",
		max_workers: int = ORDER_MAX_WORKERS) -> int:
	var site: Dictionary = _gs.get_work_site(site_id)
	if site.is_empty() or float(site.get("amount", 0.0)) <= 0.0:
		return 0
	if faction == "":
		faction = _gs.player_faction
	var spos: Vector2 = site.get("position", Vector2.ZERO)
	var cands: Array[Dictionary] = []
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if not (String(u.get("job", "")) == "worker" \
				or String(u.get("job", "")) in ["woodcutter", "miner"]):
			continue
		if int(u.get("work_building", -1)) >= 0:
			continue  # busy building — HTML skips buildTarget workers
		cands.append(u)
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.get("position", Vector2.ZERO) as Vector2) \
			.distance_squared_to(spos) < (b.get("position", Vector2.ZERO)
				as Vector2).distance_squared_to(spos))
	var n := 0
	for u: Dictionary in cands:
		if n >= max_workers:
			break
		u["work_site"] = site_id
		u["work_state"] = "to_resource"
		u["work_target_pos"] = spos + Vector2(
			_rng.randf_range(-18.0, 18.0), _rng.randf_range(-18.0, 18.0))
		u["work_building"] = -1
		u.erase("player_order")
		n += 1
	if n > 0 and _gs.bus.has_signal("gather_ordered"):
		_gs.bus.gather_ordered.emit(faction, site_id, n)
	return n


## ---- save ----------------------------------------------------------------


## Milestone 7: export trader + nothing else mutable (oil production is
## stateless) for save files.
func to_dict() -> Dictionary:
	return {
		"funky_stock": funky_stock.duplicate(),
		"funky_on_map": funky_on_map,
		"funky_pos": funky_pos,
		"funky_visit_timer": funky_visit_timer,
		"funky_visit_left": funky_visit_left,
	}


## Milestone 7: restore trader state from a save file.
func from_dict(data: Dictionary) -> void:
	funky_stock = FUNKY_STOCK.duplicate()
	for k in data.get("funky_stock", {}).keys():
		funky_stock[str(k)] = float(data["funky_stock"][k])
	funky_on_map = bool(data.get("funky_on_map", false))
	funky_pos = data.get("funky_pos", Vector2(-9999, -9999))
	funky_visit_timer = float(data.get("funky_visit_timer",
		FUNKY_FIRST_VISIT_MIN))
	funky_visit_left = float(data.get("funky_visit_left", 0.0))
