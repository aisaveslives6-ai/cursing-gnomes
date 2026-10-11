class_name GameState
extends Node
## Cursing Gnomes — central simulation state (Milestone 1: sim core).
##
## Owns every sim subsystem (bus, resources, population, spawner) and the raw
## record lists. Registered as an autoload (named "Game" to avoid shadowing the
## GameState class) for the real game; tests instantiate it directly via
## GameState.new().
##
## UNIT SCHEMA (Dictionary):
##   id: int, faction: String, job: String, town_id: int (-1 = countryside),
##   position: Vector2, alive: bool, hp: float, max_hp: float
## TOWN SCHEMA (Dictionary):
##   id: int, faction: String, name: String, position: Vector2
## BUILDING SCHEMA (Dictionary):
##   id: int, type: String, faction: String, town_id: int, position: Vector2
##
## WORK SITE SCHEMA (Dictionary):
##   id: int, kind: String ("tree" | "rock" | "gold_vein" | "bush"),
##   position: Vector2, amount: float (remaining harvestable units)
##
## Pure logic — no rendering, no input, no audio in this file.


## NOTE: subsystem vars are intentionally untyped (no `var spawner: Spawner`)
## to avoid a cyclic class-reference between GameState and the sim scripts,
## which breaks GDScript type inference at parse time.


var bus  # EventBus — owned signal bus; sim systems emit through this.
var resources  # SimResources — per-faction resource ledgers.
var population  # SimPopulation — cap queries.
var spawner  # Spawner — unit creation with cap enforcement.
var diplomacy  # SimDiplomacy — pair-wise faction relationships (Milestone 8).
var zoning  # SimZoning — painted land-use zones + bonuses.
## Port-wave subsystems (assigned by World._ready; null in bare tests).
var seasons  # SimSeasons — fantasy calendar + weather sim.
var farming  # SimFarming — farm plots, seeds economy.
var animals  # SimAnimals — farm animals (barn/coop yields, feeding).
var industry  # SimIndustry — oil production, trader, gather orders.
var court_sys  # SimRoyalCourt — also owned by World.
var phone_sys  # SimPhone — also owned by World.
var army  # SimArmy — stances, draft/muster/deploy, warlord, campaigns.
var arty  # SimArtillery — vehicles, crews, grape shot, air defense.
var undead  # SimUndead — soul essence, corpses, necromancy, plague.
var factions  # SimFactions — faction military rosters (C61 uniques).
var border_walls  # BorderWalls — AI border-wall rings per faction.
var starfort_bases  # StarFortBases — AI star-fort military bases (Jeremy 2026-09-26).
var hiring  # GuildHiring — officers, hiring sweep, training queues.
var housing  # SimHousing — house caps, buying, migration, homesteads.
var disasters  # DisasterSim — owned by World (fires, monsters, forecast).
var hydro  # HydroSim — flood/hydrology sim, owned by World.
var ai_director  # SimAIDirector — AI faction brain, owned by World.
var petitions  # SimPetitions — tool/shop petition chain, owned by World.
var food_feedback  # SimFoodFeedback — food-economy reporting (digest/Gazette), owned by World.
var lexicon  # SimLexicon — Living Lexicon vocabulary brain, owned by World.
## Jeremy 2026-10-04: strategic proposal protocol ("AI plays the game,
## player approves") — war/monastery/expansion decisions. Owned by World.
var proposals  # SimProposals — strategic proposals, owned by World.
var handyman  # SimHandyman — wandering handyman tribute event, owned by World.
var founding  # SimFounding — new-game founding beat (Gazette + adviser DM), owned by World.
var rulers_voice  # SimRulersVoice — cabinet order-taking in Messenger, owned by World.
var trade_deals  # SimTradeDeals — faction resource trade deals + ledger, owned by World.
## Jeremy 2026-10-11: war-spare fate votes + negotiable peace treaties,
## owned by World. disaster_aid: disaster aid votes + helper missions.
var war_spare  # SimWarSpare — owned by World.
var disaster_aid  # SimDisasterAid — owned by World.
## Jeremy 2026-10-11: per-race lifespans + natural aging, owned by World.
var lifespans  # SimLifespans — owned by World.
## Jeremy 2026-10-11: plague/disease system + doctrines, owned by World.
## (SimSkills is static — no instance needed.)
var disease  # SimDisease — owned by World.
var garrison  # SimGarrison — peacetime garrison AI, owned by World.
var tap_command  # SimTapCommand — tap-to-command player military orders, owned by World.
var siege  # SimSiege — civilian siege response (hide/repair), owned by World.
var trade_routes  # SimTradeRoutes — inter-faction trade routes, owned by World.
var vehicles  # SimVehicles — unified vehicle records + driving physics, owned by World.
var dealership  # SimDealership — wagon dealership, citizen ownership, assigned parking, owned by World.
var motor_pool  # SimMotorPool — military motor pool: depot lots, fleet funding, baggage-train dispatch, owned by World.
var npc_travel  # SimNPCTravel — citizens ride their own vehicles on long trips (migration, drive-home), owned by World.
var worker_ai  # WorkerAI — painted road network records, owned by World.
var towns_sys  # SimTowns — town founding registry, owned by World.
var family  # SimFamily — romance/marriage/children/belonging/leadership, owned by World.
var backchannel  # SimBackchannel — ruler letters/diplomacy background, owned by World.
## Jeremy 2026-10-04: Seven Monasteries — gods, perks, capture. Owned by
## World; null in bare GameState tests until wired.
var monasteries = null
## Jeremy 2026-10-04: Seven Dark Crystals — rogue gods, devastating
## powers, corruption. Owned by World; null in bare GameState tests.
var crystals = null
## Jeremy 2026-10-06: Command Posts — unified town/monastery/crystal
## capture model (Battlefront directive). Owned by World; null in bare
## GameState tests until wired.
var command_posts = null
## Jeremy 2026-10-04: nuclear warfare — silo arming, nuke strikes,
## detonations, radiation zones. Owned by World; null in bare tests.
var nuclear = null
## Jeremy 2026-10-04: faction leaders — communicable AI characters per
## faction (created in _init so tests get them without a World).
var faction_leaders  # SimFactionLeaders
## Jeremy 2026-10-06: ASSFACE — the phone disaster. Phone-only prank entity
## (created in _init so tests get it without a World).
var assface  # SimAssface
## SimPathfinder — A* movement routing, owned by World. Untyped to avoid a
## core<->sim class cycle. Null until World wires it; movement falls back
## to direct steering when null (headless tests, old saves).
var pathfinder = null
## Worldgen options chosen on the setup screen (modes agent).
var worldgen: Dictionary = {}

var active_factions: Array[String] = []
var player_faction: String = ""  # faction the local player controls (HUD, placement)
var towns: Dictionary = {}            # town_id -> town Dictionary
var units: Array[Dictionary] = []     # unit records (alive + dead until purged)
var buildings: Array[Dictionary] = [] # building records
var work_sites: Array[Dictionary] = [] # harvestable sites: trees/rocks/gold/bushes
## Ground pickups (Jeremy 2026-10-05): felled trees burst into wood pickups
## instead of trickling wood straight into inventories. {id, kind ("wood"),
## amount, position}. Choppers collect them by walking over them.
var pickups: Array[Dictionary] = []
var zones: Array[Dictionary] = []      # zone records (see SimZoning schema)
## Jeremy 2026-10-05 perf: O(1) id -> live-record indexes. The Dictionaries
## stored here are the SAME live references as the arrays above (GDScript
## Dictionaries are reference types), so mutation behavior is identical —
## only the lookup is O(1) instead of a linear scan. Per-frame callers
## (WorkerAI._do_gather x240, _building_by_id in 7 sim modules) were paying
## O(units x records) every frame (~24ms/frame at the 240-unit cap).
var building_by_id: Dictionary = {}   # building id -> live building record
var work_site_by_id: Dictionary = {}  # work-site id -> live site record
## Zone lookup cache: SimZoning keeps per-faction rect lists here, validated
## by zone_cache_version. Bumped on every zones mutation (add_zone, dezone,
## paint-merge, setup, save load) so the cache can never go stale.
var zone_cache_version: int = 0
var zone_cache: Dictionary = {}        # {"_v": int, faction -> Array[{rect, type}]}
## Work-site spatial index version: WorkerAI keeps a grid over work_sites,
## validated by site_cache_version. Bumped on every wholesale replacement
## of the array (setup, save load) so the grid can never go stale.
## Plain appends (add_work_site) do NOT bump — the grid syncs those
## incrementally by array size.
var site_cache_version: int = 0
## Ground-pickup spatial index version: WorkerAI keeps a grid over pickups,
## validated by pickup_version. Bumped on every mutation (add_pickup,
## remove_pickup, save load) so the grid can never go stale. (R33: the
## walk-over magnet was a per-unit-per-tick O(pickups) scan.)
var pickup_version: int = 0
## MapGen output for the live world (terrain, levels, starts...). Set by
## World after generation; read by cliff-aware sim systems. NOT part of
## the save snapshot (regenerated from seed on load).
var map_data: Dictionary = {}

var game_time: float = 0.0
var day_number: int = 1
var is_night: bool = false

## Player preferences pushed from the main menu's settings store
## (user://settings.json): ai_aggression, graphics, etc.
## The sim reads these directly (e.g. SimArmy AI aggression). Not part of
## the save snapshot — re-pushed from the menu on new game / continue.
var settings: Dictionary = {}

## The player's ruler name. NEVER trimmed, eaten, hardcoded-over, or baked —
## it is stored verbatim and substituted verbatim into dialogue (Jeremy's law).
## Default is Jeremy's chosen name.
var ruler_name: String = ""  # Jeremy 2026-10-02: blank by default.

var _next_unit_id: int = 1
var _next_town_id: int = 1
var _next_building_id: int = 1
var _next_site_id: int = 1
var _next_zone_id: int = 1
var _next_pickup_id: int = 1


func _init() -> void:
	bus = EventBus.new()
	# Owned child so bus is freed with the GameState (no leaks in tests).
	add_child(bus)
	resources = SimResources.new(self)
	population = SimPopulation.new(self)
	spawner = Spawner.new(self)
	diplomacy = SimDiplomacy.new(self)
	zoning = SimZoning.new(self)
	faction_leaders = SimFactionLeaders.new(self)
	assface = SimAssface.new(self)


## Resets all state for a new game with the given active faction ids.
func setup(faction_ids: Array[String]) -> void:
	active_factions = faction_ids.duplicate()
	player_faction = faction_ids[0] if not faction_ids.is_empty() else ""
	towns.clear()
	units.clear()
	buildings.clear()
	work_sites.clear()
	site_cache_version += 1  # wholesale array replacement: invalidate grids
	pickups.clear()
	zones.clear()
	building_by_id.clear()
	work_site_by_id.clear()
	bump_zone_version()
	resources.reset()
	# Jeremy 2026-10-04: new games start at midday (12:00), not midnight.
	# hour_of_day() = phase * 24, so half a day = 12:00.
	game_time = Config.DAY_LENGTH_SECONDS * 0.5
	day_number = 1
	is_night = false
	_next_unit_id = 1
	_next_town_id = 1
	_next_building_id = 1
	_next_site_id = 1
	_next_zone_id = 1
	_next_pickup_id = 1
	for f: String in active_factions:
		resources.ensure_faction(f)
	diplomacy.reset(active_factions)
	faction_leaders.ensure(active_factions)
	bus.game_started.emit(active_factions)


## Adds a harvestable work site (tree, rock, gold vein, bush). Returns record.
func add_work_site(record: Dictionary) -> Dictionary:
	var site: Dictionary = record.duplicate()
	site["id"] = _next_site_id
	_next_site_id += 1
	work_sites.append(site)
	work_site_by_id[site["id"]] = site
	return site


## Fetches a work site by id, or {} if not found. O(1) via the id index;
## the linear fallback self-heals the index for records appended directly
## (save load rebuilds it explicitly via rebuild_lookup_indexes).
func get_work_site(site_id: int) -> Dictionary:
	if work_site_by_id.has(site_id):
		return work_site_by_id[site_id]
	for s: Dictionary in work_sites:
		if int(s.get("id", 0)) == site_id:
			work_site_by_id[site_id] = s
			return s
	return {}


## Adds a ground pickup (felled-tree wood). Returns the record.
func add_pickup(record: Dictionary) -> Dictionary:
	var p: Dictionary = record.duplicate()
	p["id"] = _next_pickup_id
	_next_pickup_id += 1
	pickups.append(p)
	pickup_version += 1
	return p


## Removes a pickup by id (collected or expired). No-op if missing.
func remove_pickup(pickup_id: int) -> void:
	for i in range(pickups.size()):
		if int(pickups[i].get("id", 0)) == pickup_id:
			pickups.remove_at(i)
			pickup_version += 1
			return


## Removes amount from a site, clamping at zero. Returns what was actually
## taken (may be less than asked when the site runs dry).
func deplete_site(site_id: int, amount: float) -> float:
	var s: Dictionary = get_work_site(site_id)
	if s.is_empty():
		return 0.0
	var have: float = float(s.get("amount", 0.0))
	var taken: float = minf(maxf(0.0, amount), have)
	s["amount"] = have - taken
	return taken


## Founds a town for a faction. Returns the town record.
func found_town(faction: String, town_name: String, position: Vector2) -> Dictionary:
	var town: Dictionary = {
		"id": _next_town_id,
		"faction": faction,
		"name": town_name,
		"position": position,
	}
	_next_town_id += 1
	towns[town["id"]] = town
	bus.town_founded.emit(town)
	return town


## Adds a unit record, assigning it a unique id. Prefer Spawner.spawn_unit()
## (it enforces caps); this is the low-level record writer.
func add_unit(record: Dictionary) -> Dictionary:
	var unit: Dictionary = record.duplicate()
	unit["id"] = _next_unit_id
	_next_unit_id += 1
	units.append(unit)
	return unit


## Fetches a unit record by id, or {} if not found.
func get_unit(unit_id: int) -> Dictionary:
	for u: Dictionary in units:
		if int(u.get("id", 0)) == unit_id:
			return u
	return {}


## Marks a unit dead and emits unit_died. Dead units still occupy their record
## until purge_dead() runs (they do NOT count toward population caps).
func kill_unit(unit_id: int) -> bool:
	var u: Dictionary = get_unit(unit_id)
	if u.is_empty() or not u.get("alive", false):
		return false
	u["alive"] = false
	bus.unit_died.emit(unit_id, String(u.get("faction", "")))
	return true


## Removes dead unit records from the list. Returns the number purged.
func purge_dead() -> int:
	var before: int = units.size()
	var kept: Array[Dictionary] = []
	for u: Dictionary in units:
		if u.get("alive", false):
			kept.append(u)
	units = kept
	return before - units.size()


## Adds a building record, assigning it a unique id. Emits building_placed.
func add_building(record: Dictionary) -> Dictionary:
	var b: Dictionary = record.duplicate()
	b["id"] = _next_building_id
	_next_building_id += 1
	buildings.append(b)
	building_by_id[b["id"]] = b
	bus.building_placed.emit(b)
	return b


## Fetches a building by id, or {} if not found. O(1) via the id index;
## the linear fallback self-heals the index for records appended directly.
func get_building(building_id: int) -> Dictionary:
	if building_by_id.has(building_id):
		return building_by_id[building_id]
	for b: Dictionary in buildings:
		if int(b.get("id", 0)) == building_id:
			building_by_id[building_id] = b
			return b
	return {}


## Erases a building record from the array AND the id index (use instead of
## buildings.erase — the index would otherwise return a dead record).
func erase_building(b: Dictionary) -> void:
	buildings.erase(b)
	building_by_id.erase(int(b.get("id", -1)))


## Rebuilds the id indexes from the arrays. Called after save-load, which
## appends records directly instead of going through add_*.
func rebuild_lookup_indexes() -> void:
	building_by_id.clear()
	for b: Dictionary in buildings:
		building_by_id[int(b.get("id", 0))] = b
	work_site_by_id.clear()
	for s: Dictionary in work_sites:
		work_site_by_id[int(s.get("id", 0))] = s
	# The arrays were wholesale-replaced: any positional index over them
	# (e.g. WorkerAI's site grid) must rebuild too.
	site_cache_version += 1


## Bumps the zone-cache version, invalidating SimZoning's per-faction rect
## cache. Call after ANY direct mutation of the zones array.
func bump_zone_version() -> void:
	zone_cache_version += 1
	zone_cache.clear()


## Hands out the next zone id (used by SimZoning for dezone fragments).
func next_zone_id() -> int:
	var zid: int = _next_zone_id
	_next_zone_id += 1
	return zid


## Adds a zone record, assigning it a unique id. Prefer
## SimZoning.paint_zone() (it merges + clips); this is the low-level writer.
func add_zone(record: Dictionary) -> Dictionary:
	var z: Dictionary = record.duplicate()
	z["id"] = next_zone_id()
	zones.append(z)
	bump_zone_version()
	return z


## Fetches a zone record by id, or {} if not found.
func get_zone(zone_id: int) -> Dictionary:
	for z: Dictionary in zones:
		if int(z.get("id", 0)) == zone_id:
			return z
	return {}


## All unit records (alive and dead) belonging to a faction.
func get_faction_units(faction: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u: Dictionary in units:
		if String(u.get("faction", "")) == faction:
			out.append(u)
	return out


## All unit records (alive and dead) assigned to a town.
func get_town_units(town_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u: Dictionary in units:
		if int(u.get("town_id", -1)) == town_id:
			out.append(u)
	return out


## Sets the ruler name VERBATIM. No strip(), no trim, no case changes —
## Jeremy's naming law: the name pipeline must never eat the name.
func set_ruler_name(new_name: String) -> void:
	ruler_name = new_name


## Advances the simulation clock and the day/night cycle.
## Phase 0 = midnight (hour_of_day = phase * 24). Night follows the HTML
## definition (hour < 5 or hour > 21), matching SimSeasons.is_night_hour().
## Jeremy 2026-10-04: new games start at midday (phase 0.5).
func tick(delta: float) -> void:
	var prev_day: int = day_number
	game_time += delta
	day_number = int(game_time / Config.DAY_LENGTH_SECONDS) + 1
	var phase: float = fmod(game_time, Config.DAY_LENGTH_SECONDS) / Config.DAY_LENGTH_SECONDS
	var hour: float = phase * 24.0
	is_night = hour < 5.0 or hour > 21.0
	if day_number != prev_day:
		bus.day_changed.emit(day_number, is_night)
