class_name SimTowns
extends RefCounted

## Town-founding system: turns completed town halls into real towns.
##
## HTML parity (fix79): the original runs a periodic sweep (every 240 frames)
## where every completed hall/townhall without a townName gets
## drawUniqueCityName() — a name no other town in the game uses, falling back
## to 'Newhold <100-999>' when the city-name pool is exhausted.
##
## The Godot port only dealt city names at world spawn, so any hall completed
## later (player-built town halls, AI-founded settlements) never became a
## town: no registry entry, no paper-map label, no per-town housing-cap
## accounting, and conquest prompts fell back to "this settlement".
## This system closes the gap with the same sweep approach:
##   - a completed hall near an existing same-faction town JOINS it
##     (rebuilds and in-town second halls don't mint new towns);
##   - a completed hall far from any town FOUNDS one (unique city name,
##     Gazette story, hearsay rumor), up to Config.TOWNS_PER_FACTION;
##   - halls past the cap still function as drop-off/defense buildings under
##     the nearest town.
## Deliberate deviation: the HTML sweep also named necropolises, but in the
## Godot roster the necropolis is the undead WAR building, not a town center
## (undead town centers are town_halls like everyone else), so it is excluded
## here.

const HALL_TYPES: Array[String] = ["hall", "town_hall", "townhall"]
const SWEEP_INTERVAL := 4.0  # seconds; HTML swept every 240 frames (~4s @60fps)
const MERGE_RADIUS := 500.0  # a hall inside this of a same-faction town joins it

var _gs  # GameState (untyped per project convention)
var _sweep_t := 0.0


func _init(game_state) -> void:
	_gs = game_state


## Advance the sweep timer; call once per tick from the world update.
func tick(delta: float) -> void:
	_sweep_t += delta
	if _sweep_t < SWEEP_INTERVAL:
		return
	_sweep_t = 0.0
	sweep()


## One pass over all buildings: register every completed hall.
func sweep() -> void:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not bool(b.get("complete", false)):
			continue
		if not String(b.get("type", "")) in HALL_TYPES:
			continue
		register_hall(b)


## Registers one completed hall with the town system. Idempotent: halls whose
## town_id already resolves to a real town only get their display name synced
## (conquest renames propagate this way). Returns the town record the hall
## belongs to, or {} when the faction has no town in reach.
func register_hall(hall: Dictionary) -> Dictionary:
	var faction: String = String(hall.get("faction", ""))
	var pos: Vector2 = hall.get("position", Vector2.ZERO)
	# Already registered: keep the display name in sync with the town record.
	var town := town_by_id(int(hall.get("town_id", -1)))
	if not town.is_empty():
		_stamp(hall, town)
		return town
	# Rebuild / in-town hall: inside an existing same-faction town's radius.
	town = nearest_town(faction, pos, MERGE_RADIUS)
	if not town.is_empty():
		_stamp(hall, town)
		return town
	# Found a new town when the faction has room to grow.
	if towns_of(faction).size() < Config.TOWNS_PER_FACTION:
		town = _gs.found_town(faction, unique_city_name(), pos)
		_stamp(hall, town)
		_announce(town)
		return town
	# At the cap: the hall still functions, under the nearest town.
	town = nearest_town(faction, pos)
	if not town.is_empty():
		_stamp(hall, town)
	return town


## Stamp the hall's town association + display name from the town record.
func _stamp(hall: Dictionary, town: Dictionary) -> void:
	hall["town_id"] = int(town.get("id", -1))
	hall["town_name"] = String(town.get("name", ""))


## All town records belonging to a faction.
func towns_of(faction: String) -> Array:
	var out: Array = []
	for tid in _gs.towns.keys():
		var t: Dictionary = _gs.towns[tid]
		if String(t.get("faction", "")) == faction:
			out.append(t)
	return out


## Nearest town of a faction to a position, within max_dist (INF = any).
func nearest_town(faction: String, pos: Vector2,
		max_dist: float = INF) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_dist
	for tid in _gs.towns.keys():
		var t: Dictionary = _gs.towns[tid]
		if String(t.get("faction", "")) != faction:
			continue
		var d: float = pos.distance_to(t.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = t
	return best


## Fetch a town record by id. Coerces the key: very old saves may carry
## string keys for the towns dict (JSON round-trip); current code keeps ints.
func town_by_id(town_id: int) -> Dictionary:
	if town_id < 0:
		return {}
	if _gs.towns.has(town_id):
		return _gs.towns[town_id]
	if _gs.towns.has(str(town_id)):
		return _gs.towns[str(town_id)]
	return {}


## A city name no other town in this game uses (HTML drawUniqueCityName
## parity); 'Newhold <100-999>' when the pool is exhausted.
func unique_city_name() -> String:
	var used := {}
	for tid in _gs.towns.keys():
		var n: String = String((_gs.towns[tid] as Dictionary).get("name", ""))
		if n != "":
			used[n] = true
	var avail: Array[String] = []
	for n in Config.CITY_NAMES:
		if not used.has(n):
			avail.append(n)
	if avail.is_empty():
		return "Newhold %d" % (100 + randi_range(0, 899))
	return avail[randi_range(0, avail.size() - 1)]


## Gazette story + hearsay rumor so the realm hears about the founding.
func _announce(town: Dictionary) -> void:
	var faction: String = String(town.get("faction", ""))
	var tname: String = String(town.get("name", ""))
	var pretty: String = String(Config.FACTIONS.get(faction, {}).get("name", faction))
	if _gs.get("court_sys") != null:
		_gs.court_sys.publish_story(
			"New settlement founded: %s" % tname,
			"The %s raise a new town hall and name the settlement %s. Banners fly; the taverns are already full." % [pretty, tname],
			"town")
	var hearsay = null
	if _gs.get("phone_sys") != null:
		hearsay = _gs.phone_sys.get("hearsay")
	if hearsay != null:
		hearsay.seed_rumor(
			"Have you heard? The %s founded a new town — %s!" % [pretty, tname],
			"town", tname, 0.7)
