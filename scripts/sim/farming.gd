class_name SimFarming
extends RefCounted
## Cursing Gnomes — farm plots, the seed economy, and seed shops
## (Milestone 6b: world & environment / economy).
##
## Ports the HTML build's Stardew farm chain (not its code):
##   - Farm plots: 4x4 tilled grids (16 tiles). Soil comes pre-tilled.
##   - plant -> grow -> harvest. A tile grows 0->1 in ~1.5 in-game days;
##     watered crops grow 1.6x faster. Rain waters every crop on the map
##     (HTML s8FarmTick). Seasons scale growth via SimSeasons.growth_mult().
##   - Harvest yields 60-100 food + 2-4 seeds per mature tile (HTML exact).
##   - Seeds economy: seedshop buildings hold a FINITE seedStock
##     (starts at 25, cap 200 — HTML SEEDSHOP_START_STOCK/CAP); seeds cost
##     5 gold each (HTML SEED_PRICE). Harvested seeds can be delivered back
##     to restock the shop (HTML s8DeliverSeedsToShop).
##
## Godot simplifications (documented, faithful where it matters):
##   - HTML farmers buy seeds with their OWN coins and carry harvests home
##     on foot; here the faction ledger is the economy (no per-unit coins
##     exist in the Godot port), so seed purchases debit faction gold and
##     harvests credit the faction ledger directly.
##   - Farm animals live in SimAnimals (scripts/sim/animals.gd): barn/coop
##     housing, per-plot herds, daily feeding + food yields, starvation.
##
## Plot record: {id, faction, building_id, position, seed_bin,
##   tiles: [{g: float 0..1, watered: bool, waterT: float}],
##   animals: [{id, type, position, hunger, hp, max_hp, alive}],
##   barn_bld: int (-1), coop_bld: int (-1)}.
## Pure logic — no rendering, no input, no audio.


const TILES_PER_SIDE := 4          # HTML FARM_TILES: 4x4 tilled grid
const TILE_COUNT := 16
const PLOT_COST_WOOD := 25         # HTML FARM_COST_WOOD
const START_SEED_BIN := 4          # HTML: starter seeds in the farm's bin
const SEED_PRICE := 5              # HTML SEED_PRICE: gold per seed
const SEEDSHOP_START_STOCK := 25   # HTML SEEDSHOP_START_STOCK
const SEEDSHOP_CAP := 200          # HTML SEEDSHOP_CAP
const GROW_DAYS := 1.5             # HTML: ~1.5 in-game days seed->mature
const WATERED_MULT := 1.6          # HTML: watered crops grow 1.6x faster
const RAIN_WATER_TIME := 600.0     # HTML: rain sets waterT = 600
const MANUAL_WATER_TIME := 1800.0  # HTML: hand watering sets waterT = 1800
const HARVEST_FOOD_MIN := 60.0     # HTML: 60-100 food per harvest
const HARVEST_FOOD_MAX := 100.0
const HARVEST_SEEDS_MIN := 2.0     # HTML: 2-4 seeds per harvest
const HARVEST_SEEDS_MAX := 4.0
# Jeremy 2026-10-05 launch-readiness (gate 1): auto-plots. Only the single
# free starting plot (world.gd _spawn_demo) ever existed, because nothing
# else called create_plot — every farm/farmhouse beyond the first was a
# decorative building with no working field, for the player AND the AI.
# The HTML had farm_plot as a player-buildable (25 wood); the Godot port
# dropped the placement UI, so plots could never be made. Deliberate
# deviation: every completed farm/farmhouse now grows its own working
# field automatically, free (the building already cost resources).
# Flesh farms keep their corpse-meat economy (undead.gd) and get no plots.
const PLOT_BUILDING_TYPES: Array[String] = ["farm", "farmhouse"]
const PLOT_AUTO_OFFSET := Vector2(-80, 105)  # field sits south-west of the farmhouse
const PLOT_ADOPT_RADIUS := 175.0  # an unlinked plot this close counts as the farm's field
const PLOT_RECONCILE_INTERVAL := 5.0  # sim-seconds between auto-plot passes


var _gs: GameState
var plots: Array[Dictionary] = []  # farm plot records
var _next_plot_id: int = 1
var _rng := RandomNumberGenerator.new()
var _reconcile_accum: float = 0.0


func _init(game_state: GameState) -> void:
	_gs = game_state
	_rng.randomize()


## Clears every plot. Called by GameState.setup() on new game.
func reset() -> void:
	plots.clear()
	_next_plot_id = 1
	_reconcile_accum = 0.0


## Creates a farm plot for a faction (costs 25 wood unless free=true).
## building_id links it to a completed farm/farmhouse building (-1 = none).
func create_plot(faction: String, pos: Vector2, building_id: int = -1,
		free: bool = false) -> Dictionary:
	if not free:
		if not _gs.resources.spend(faction, {"wood": float(PLOT_COST_WOOD)}):
			return {}
	var tiles: Array = []
	for i in TILE_COUNT:
		tiles.append({"g": 0.0, "watered": false, "waterT": 0.0})
	var plot: Dictionary = {
		"id": _next_plot_id,
		"faction": faction,
		"building_id": building_id,
		"position": pos,
		"seed_bin": START_SEED_BIN,
		"tiles": tiles,
		# Jeremy 2026-10-05: labor market (HTML s8FillFarmPosts port) —
		# each plot keeps a dedicated crew: one owner + up to 3 farmhands.
		# SimHiring fills these from job seekers; assigned farmers prefer
		# their own plot in nearest_work_plot().
		"owner_uid": -1,
		"worker_uids": [],
	}
	_next_plot_id += 1
	plots.append(plot)
	if _gs.bus.has_signal("farm_plot_created"):
		_gs.bus.farm_plot_created.emit(plot)
	return plot


## Auto-plot pass: every completed, living farm/farmhouse gets one working
## field. A building is skipped when it already owns a linked plot, or when
## an unlinked plot of the same faction sits close enough to count as its
## field (covers the free starting plot next to the demo farm). Linked
## plots never block neighboring farms: only the building_id match and
## nearby UNLINKED plots count.
func _reconcile_plots() -> void:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not bool(b.get("complete", false)):
			continue
		if not String(b.get("type", "")) in PLOT_BUILDING_TYPES:
			continue
		var faction: String = String(b.get("faction", ""))
		var bid: int = int(b.get("id", -1))
		var bpos: Vector2 = b.get("position", Vector2.ZERO)
		var has_field := false
		for p: Dictionary in plots:
			if int(p.get("building_id", -1)) == bid and bid >= 0:
				has_field = true
				break
			if int(p.get("building_id", -1)) != -1:
				continue  # another farm's field — never blocks a neighbor
			if String(p.get("faction", "")) != faction:
				continue
			var ppos: Vector2 = p.get("position", Vector2.ZERO)
			if ppos.distance_to(bpos) <= PLOT_ADOPT_RADIUS:
				has_field = true
				break
		if has_field:
			continue
		create_plot(faction, bpos + PLOT_AUTO_OFFSET, bid, true)


func get_plot(plot_id: int) -> Dictionary:
	for p: Dictionary in plots:
		if int(p.get("id", 0)) == plot_id:
			return p
	return {}


## Plants a seed in an empty tile. Consumes 1 seed from the plot's bin.
func plant(plot: Dictionary, tile_idx: int) -> bool:
	if plot.is_empty():
		return false
	var tiles: Array = plot.get("tiles", [])
	if tile_idx < 0 or tile_idx >= tiles.size():
		return false
	var tile: Dictionary = tiles[tile_idx]
	if tile.has("crop") and tile["crop"] != null:
		return false
	if int(plot.get("seed_bin", 0)) <= 0:
		return false
	plot["seed_bin"] = int(plot.get("seed_bin", 0)) - 1
	tile["crop"] = {"g": 0.0, "watered": false, "waterT": 0.0}
	return true


## Waters a planted tile by hand.
func water(plot: Dictionary, tile_idx: int) -> bool:
	var tile: Dictionary = _tile(plot, tile_idx)
	if tile.is_empty() or not tile.has("crop") or tile["crop"] == null:
		return false
	var crop: Dictionary = tile["crop"]
	crop["watered"] = true
	crop["waterT"] = MANUAL_WATER_TIME
	return true


## Harvests a mature tile (g >= 1): 60-100 food + 2-4 seeds to the
## faction ledger (HTML yields, verbatim ranges).
func harvest(plot: Dictionary, tile_idx: int) -> Dictionary:
	var out := {"food": 0.0, "seeds": 0.0}
	if bool(plot.get("hoa_lien", false)):
		return out  # HOA Karen lien — harvest seized until she leaves
	var tile: Dictionary = _tile(plot, tile_idx)
	if tile.is_empty() or not tile.has("crop") or tile["crop"] == null:
		return out
	var crop: Dictionary = tile["crop"]
	if float(crop.get("g", 0.0)) < 1.0:
		return out
	tile["crop"] = null
	out["food"] = _rng.randf_range(HARVEST_FOOD_MIN, HARVEST_FOOD_MAX)
	out["seeds"] = _rng.randf_range(HARVEST_SEEDS_MIN, HARVEST_SEEDS_MAX)
	var faction: String = String(plot.get("faction", ""))
	# Bill's cybernetics: a harvest from an assimilated farm building
	# runs at -15% (empty/missing building = 1.0x via borg_building_mult).
	var borg_mult := DisasterSim.borg_building_mult(
		_gs.get_building(int(plot.get("building_id", -1))))
	out["food"] *= borg_mult
	out["seeds"] *= borg_mult
	_gs.resources.add_resource(faction, "food", out["food"])
	_bank_harvest_seeds(faction, float(out["seeds"]))
	if _gs.bus.has_signal("farm_harvested"):
		_gs.bus.farm_harvested.emit(int(plot.get("id", 0)),
			float(out["food"]), float(out["seeds"]))
	return out


## Banks harvested seeds: ledger first, then overflow into the faction's
## seed shops (HTML s8DeliverSeedsToShop — the restock path had zero
## callers, so shop stock sat at 25 forever). Overflow with no shop, or a
## full shop, is lost — exactly the old clamp behavior.
func _bank_harvest_seeds(faction: String, seeds: float) -> void:
	if seeds <= 0.0 or faction == "":
		return
	var room: float = maxf(0.0, _gs.resources.get_cap(faction, "seeds") \
		- _gs.resources.get_amount(faction, "seeds"))
	var to_ledger: float = minf(seeds, room)
	if to_ledger > 0.0:
		_gs.resources.add_resource(faction, "seeds", to_ledger)
	var overflow: int = int(seeds - to_ledger)
	if overflow <= 0:
		return
	var shop: Dictionary = _shop_with_room(faction)
	if shop.is_empty():
		return
	_ensure_seed_stock(shop)
	var space: int = maxi(0, SEEDSHOP_CAP - int(shop.get("seedStock", 0)))
	var n: int = mini(overflow, space)
	if n > 0:
		shop["seedStock"] = int(shop.get("seedStock", 0)) + n


## First completed seedshop of a faction with room below SEEDSHOP_CAP.
## (The buy path's nearest_seed_shop wants stock > 0 — wrong filter here.)
func _shop_with_room(faction: String) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("type", "")) != "seedshop":
			continue
		if String(b.get("faction", "")) != faction:
			continue
		_ensure_seed_stock(b)
		if int(b.get("seedStock", 0)) < SEEDSHOP_CAP:
			return b
	return {}


## Moves seeds from the faction ledger into a plot's seed bin.
func fill_seed_bin(plot: Dictionary, amount: int) -> int:
	if plot.is_empty() or amount <= 0:
		return 0
	var faction: String = String(plot.get("faction", ""))
	if not _gs.resources.spend(faction, {"seeds": float(amount)}):
		amount = int(_gs.resources.get_amount(faction, "seeds"))
		if amount <= 0:
			return 0
		_gs.resources.spend(faction, {"seeds": float(amount)})
	plot["seed_bin"] = int(plot.get("seed_bin", 0)) + amount
	return amount


## Seed-shop bootstrap (2026-10-05 launch-readiness, gate 1): the buy path
## (buy_seeds, 5 gold each) had zero callers, so a seed-dry faction could
## never restock even with a built seedshop and full coffers. When the
## ledger cannot cover `need`, buy the shortfall from the faction's own
## shops instead of leaving farm bins empty forever. Returns seeds bought
## (0 when there is no shop, no stock, or no gold).
## Runs in the worker labor loop for every faction (same as fill_seed_bin):
## it is sim automation rescuing stalling farms, not director spending.
func ensure_seed_supply(faction: String, need: int) -> int:
	if need <= 0 or faction == "":
		return 0
	var have: float = _gs.resources.get_amount(faction, "seeds")
	var shortfall: int = maxi(0, need - int(have))
	if shortfall <= 0:
		return 0
	return buy_seeds(faction, shortfall)


## Buys seeds from a completed seedshop of the faction: 5 gold each
## (HTML SEED_PRICE), limited by the shop's finite stock. Seeds land in
## the faction ledger (HTML farmers bought with personal coins and
## carried them — no per-unit coins exist in the Godot port).
func buy_seeds(faction: String, amount: int) -> int:
	var shop: Dictionary = nearest_seed_shop(faction,
		Vector2(2048, 2048))
	if shop.is_empty():
		return 0
	return buy_seeds_from(shop, faction, amount)


## Same, from a specific shop building record.
func buy_seeds_from(shop: Dictionary, faction: String,
		amount: int) -> int:
	if shop.is_empty() or not shop.get("alive", false) \
			or not shop.get("complete", false):
		return 0
	_ensure_seed_stock(shop)
	var stock: int = int(shop.get("seedStock", 0))
	var afford: int = int(_gs.resources.get_amount(faction, "gold")) \
		/ SEED_PRICE
	var n: int = mini(amount, mini(stock, afford))
	if n <= 0:
		return 0
	var cost: float = float(n * SEED_PRICE)
	if not _gs.resources.spend(faction, {"gold": cost}):
		return 0
	shop["seedStock"] = stock - n
	_gs.resources.add_resource(faction, "seeds", float(n))
	if _gs.bus.has_signal("seeds_bought"):
		_gs.bus.seeds_bought.emit(faction, n)
	return n


## Delivers harvested seeds back to a seed shop, restocking its finite
## inventory up to SEEDSHOP_CAP (HTML s8DeliverSeedsToShop).
func deliver_seeds_to_shop(shop: Dictionary, faction: String,
		amount: int) -> int:
	if shop.is_empty() or not shop.get("alive", false):
		return 0
	_ensure_seed_stock(shop)
	var stock: int = int(shop.get("seedStock", 0))
	var room: int = maxi(0, SEEDSHOP_CAP - stock)
	var have: int = int(_gs.resources.get_amount(faction, "seeds"))
	var n: int = mini(amount, mini(room, have))
	if n <= 0:
		return 0
	if not _gs.resources.spend(faction, {"seeds": float(n)}):
		return 0
	shop["seedStock"] = stock + n
	return n


## Nearest completed seedshop of a faction with stock (HTML s8FindSeedShop).
func nearest_seed_shop(faction: String, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("type", "")) != "seedshop":
			continue
		if String(b.get("faction", "")) != faction:
			continue
		_ensure_seed_stock(b)
		if int(b.get("seedStock", 0)) <= 0:
			continue
		var d: float = pos.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	return best


func _ensure_seed_stock(shop: Dictionary) -> void:
	if not shop.has("seedStock"):
		shop["seedStock"] = SEEDSHOP_START_STOCK


func _tile(plot: Dictionary, tile_idx: int) -> Dictionary:
	if plot.is_empty():
		return {}
	var tiles: Array = plot.get("tiles", [])
	if tile_idx < 0 or tile_idx >= tiles.size():
		return {}
	return tiles[tile_idx]


## Per-tick: grow crops, decay watering, rain waters everything
## (HTML s8FarmTick, verbatim rates).
func tick(delta: float) -> void:
	_reconcile_accum += delta
	if _reconcile_accum >= PLOT_RECONCILE_INTERVAL:
		_reconcile_accum = 0.0
		_reconcile_plots()
	var raining := false
	var growth_season := 1.0
	var seas = _gs.get("seasons")
	if seas != null:
		raining = String(seas.weather) in ["rain", "storm"]
		if seas.has_method("growth_mult"):
			growth_season = float(seas.growth_mult())
	var rate: float = delta / (GROW_DAYS * Config.DAY_LENGTH_SECONDS) \
		* growth_season
	for plot: Dictionary in plots:
		# Flood mud: halved growth while the muck dries (HydroSim stamps
		# mud_until when waters recede — Jeremy 2026-10-04).
		var mud_mult := 0.5 \
			if float(plot.get("mud_until", 0.0)) > _gs.game_time else 1.0
		var tiles: Array = plot.get("tiles", [])
		for tile in tiles:
			if not (tile is Dictionary):
				continue
			var t: Dictionary = tile
			if not t.has("crop") or t["crop"] == null:
				continue
			var crop: Dictionary = t["crop"]
			if raining:
				crop["watered"] = true
				crop["waterT"] = RAIN_WATER_TIME
			elif bool(crop.get("watered", false)):
				crop["waterT"] = float(crop.get("waterT", 0.0)) - delta
				if float(crop.get("waterT", 0.0)) <= 0.0:
					crop["watered"] = false
			if float(crop.get("g", 0.0)) < 1.0:
				var mult: float = WATERED_MULT \
					if bool(crop.get("watered", false)) else 1.0
				crop["g"] = minf(1.0,
					float(crop.get("g", 0.0)) + rate * mult * mud_mult)


## Picks the next chore for a farmer working a plot (HTML s8DoFarmChore
## priority: harvest mature -> plant empty -> water dry).
## Returns {action, tile} with action in harvest|plant|water, or {}.
func plot_chore(plot: Dictionary) -> Dictionary:
	if plot.is_empty():
		return {}
	var tiles: Array = plot.get("tiles", [])
	var mature := -1
	var empty := -1
	var dry := -1
	for i in tiles.size():
		var t: Dictionary = tiles[i]
		if not (t is Dictionary):
			continue
		if not t.has("crop") or t["crop"] == null:
			if empty < 0:
				empty = i
			continue
		var crop: Dictionary = t["crop"]
		if float(crop.get("g", 0.0)) >= 1.0:
			if mature < 0:
				mature = i
		elif not bool(crop.get("watered", false)):
			if dry < 0:
				dry = i
	if mature >= 0:
		return {"action": "harvest", "tile": mature}
	if empty >= 0 and int(plot.get("seed_bin", 0)) > 0:
		return {"action": "plant", "tile": empty}
	if dry >= 0:
		return {"action": "water", "tile": dry}
	return {}


## Nearest plot of a faction that has pending work.
## prefer_id: a plot id the caller is assigned to (HTML s8FillFarmPosts
## staffing) — checked first so dedicated farm crews work their own land.
func nearest_work_plot(faction: String, pos: Vector2,
		prefer_id: int = -1) -> Dictionary:
	if prefer_id > 0:
		var pref := get_plot(prefer_id)
		if not pref.is_empty() and String(pref.get("faction", "")) == faction \
				and not plot_chore(pref).is_empty():
			return pref
	var best: Dictionary = {}
	var best_d := INF
	for p: Dictionary in plots:
		if String(p.get("faction", "")) != faction:
			continue
		if plot_chore(p).is_empty():
			continue
		var d: float = pos.distance_to(p.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = p
	return best


## Milestone 7: export plots for save files.
func to_dict() -> Dictionary:
	var out: Array = []
	for p: Dictionary in plots:
		out.append(p.duplicate(true))
	return {"plots": out, "next_plot_id": _next_plot_id}


## Milestone 7: restore plots from a save file.
func from_dict(data: Dictionary) -> void:
	plots.clear()
	for p in data.get("plots", []):
		if p is Dictionary:
			var pd: Dictionary = (p as Dictionary).duplicate(true)
			# Backfill for saves written before the labor-market staffing
			# fields existed (2026-10-05).
			if not pd.has("owner_uid"):
				pd["owner_uid"] = -1
			if not pd.has("worker_uids"):
				pd["worker_uids"] = []
			plots.append(pd)
	_next_plot_id = int(data.get("next_plot_id", 1))
