class_name SimPopulation
extends RefCounted
## Cursing Gnomes — population tracking and cap queries (Milestone 1: sim core).
##
## Single source of truth for "how many units where". The Spawner asks here
## before creating anything; Jeremy's laws are enforced from Config.
## Only ALIVE units count toward population. Dead units must be purged via
## GameState.purge_dead() (or they linger as corpses and still count as dead).
## Pure logic — no rendering, no input, no audio.


var _gs: GameState


## _init takes the owning GameState to read its unit list.
func _init(game_state: GameState) -> void:
	_gs = game_state


## Alive units assigned to a town. town_id < 0 counts as "countryside" (0 here).
func get_town_pop(town_id: int) -> int:
	var n: int = 0
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and int(u.get("town_id", -1)) == town_id:
			n += 1
	return n


## Alive units of a faction across all towns and countryside.
func get_faction_pop(faction: String) -> int:
	var n: int = 0
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == faction:
			n += 1
	return n


## Alive units in the whole world.
func get_global_pop() -> int:
	var n: int = 0
	for u: Dictionary in _gs.units:
		if u.get("alive", false):
			n += 1
	return n


## Alive units of a faction holding a given job (e.g. "firefighter").
func count_job(faction: String, job: String) -> int:
	var n: int = 0
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == faction \
				and String(u.get("job", "")) == job:
			n += 1
	return n


## Jeremy's law: hard cap of Config.POP_CAP_TOWN alive units per town.
## Essential-service jobs (Config.ESSENTIAL_JOBS) bypass this cap, as does the
## countryside (town_id < 0) — it has no town affiliation.
## Military jobs bypass too: soldiers live in barracks (25 beds each, not
## town houses), so a full town must not block barracks graduates — otherwise
## training silently completes and drops the graduate ("they don't even
## spawn in an army"). Faction/global caps still apply.
func can_spawn_in_town(town_id: int, job: String) -> bool:
	if town_id < 0:
		return true
	if job in Config.ESSENTIAL_JOBS:
		return true
	if JobDefs.is_military(job):
		return true
	return get_town_pop(town_id) < Config.POP_CAP_TOWN


## Jeremy's law: hard cap of Config.POP_CAP_FACTION alive units per faction.
func can_spawn_for_faction(faction: String) -> bool:
	return get_faction_pop(faction) < Config.POP_CAP_FACTION


## Jeremy's law: hard limit of Config.POP_CAP_GLOBAL alive units in the world.
func can_spawn_global() -> bool:
	return get_global_pop() < Config.POP_CAP_GLOBAL
