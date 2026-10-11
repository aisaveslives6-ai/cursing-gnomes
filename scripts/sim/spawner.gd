class_name Spawner
extends RefCounted
## Cursing Gnomes — unit spawning with Jeremy's population laws enforced
## (Milestone 1: sim core).
##
## Every unit in the game is born here. Caps are checked BEFORE the unit record
## is created, so they can NEVER be exceeded — even under spawn spam, because
## check-then-create is synchronous (no threads in the sim).
##
## Laws (from Config):
##   - 16 alive units per town (essential services bypass)
##   - 48 alive units per faction
##   - 240 alive units globally
##   - max 2 firefighters per faction, max 1 doctor per faction
##     (essential services: bypass the per-town cap per Jeremy 2026-10-02)
## Pure logic — no rendering, no input, no audio.


## Human-readable reason from the last blocked spawn ("" if last spawn ok).
var last_block_reason: String = ""


## Worker-type jobs covered by the idle-hands check (gatherers + builders).
const WORKER_JOBS := ["worker", "woodcutter", "miner", "farmer", "fisher",
	"builder", "roadbuilder", "hunter"]

## Idle hands are already waiting — this many available workers blocks
## training another (one mid-transition shouldn't stall the economy).
const IDLE_WORKER_SURPLUS := 2


var _gs: GameState


## _init takes the owning GameState (units list, population, event bus).
func _init(game_state: GameState) -> void:
	_gs = game_state


## Dry-run cap check. Returns "ok" or a reason string:
## "bad_faction" | "bad_town" | "job_capped" | "town_capped"
## "faction_capped" | "global_capped".
func check_spawn(faction: String, job: String, town_id: int) -> String:
	if not faction in Config.FACTIONS:
		return "bad_faction"
	if town_id >= 0 and not _gs.towns.has(town_id):
		return "bad_town"
	# Per-job hard caps for essential services (counted per faction).
	if job == "firefighter" and _gs.population.count_job(faction, "firefighter") >= Config.FIREFIGHTERS_PER_STATION:
		return "job_capped"
	if job == "doctor" and _gs.population.count_job(faction, "doctor") >= Config.DOCTORS_PER_CLINIC:
		return "job_capped"
	if job == "guild_master" and _gs.population.count_job(faction, "guild_master") >= Config.GUILDMASTERS_PER_HALL:
		return "job_capped"
	if not _gs.population.can_spawn_in_town(town_id, job):
		return "town_capped"
	if not _gs.population.can_spawn_for_faction(faction):
		return "faction_capped"
	if not _gs.population.can_spawn_global():
		return "global_capped"
	return "ok"


## Jeremy 2026-10-04: population control — only spawn/train units the
## faction actually NEEDS. Consulted by the AI director and the guild
## hiring sweep BEFORE queueing training (hard caps stay enforced in
## check_spawn/spawn_unit):
##   - military: only while below the threat-based army target (1.35x the
##     living enemy army + 4, race floors — the director's doctrine; pass
##     the director's computed army_target to share one number)
##   - essential services (Config.ESSENTIAL_JOBS): always needed — their
##     roster caps in check_spawn are the real limit
##   - everyone else: not when the countryside is full too (homeless
##     migrate there per SimHousing — but when even the countryside is
##     full, growth stops), and never another worker-type while idle
##     workers are already waiting for work
func faction_needs_unit(faction: String, job: String,
		army_target: int = -1) -> bool:
	if not faction in Config.FACTIONS:
		return false
	if not _gs.population.can_spawn_for_faction(faction):
		return false
	if not _gs.population.can_spawn_global():
		return false
	if JobDefs.is_military(job):
		var target := army_target
		if target < 0:
			target = _estimate_army_target(faction)
		return _count_military(faction) < target
	if job in Config.ESSENTIAL_JOBS:
		return true
	var housing = _gs.get("housing")
	if housing != null \
			and housing.countryside_house_count(faction) \
				>= SimHousing.COUNTRYSIDE_HOUSE_CAP:
		return false
	if job in WORKER_JOBS:
		if _idle_workers(faction) >= IDLE_WORKER_SURPLUS:
			return false
	return true


## Threat-based army target estimate (AI director doctrine without the
## hall context: 1.35x the living enemy army + 4, race floors).
func _estimate_army_target(faction: String) -> int:
	var enemy_army := 0
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) == faction:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		enemy_army += 1
	var floor := 16
	if faction == "ogres":
		floor = 14
	elif faction == "gnomes":
		floor = 12
	return maxi(floor, int(ceil(float(enemy_army) * 1.35)) + 4)


## Living military units of a faction.
func _count_military(faction: String) -> int:
	var n := 0
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if JobDefs.is_military(String(u.get("job", ""))):
			n += 1
	return n


## Worker-type units of a faction currently sitting idle (work_state
## "idle" — off-shift resters don't count as available labor). Fresh
## spawns have no work_state yet and count as available.
func _idle_workers(faction: String) -> int:
	var n := 0
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if not String(u.get("job", "")) in WORKER_JOBS:
			continue
		if String(u.get("work_state", "idle")) == "idle":
			n += 1
	return n


## Creates a unit or returns {} when blocked. On success the unit record is
## added to GameState.units and unit_spawned is emitted.
## town_id < 0 means countryside (skips the per-town cap).
func spawn_unit(faction: String, job: String, town_id: int, position: Vector2) -> Dictionary:
	var reason: String = check_spawn(faction, job, town_id)
	if reason != "ok":
		last_block_reason = reason
		return {}
	last_block_reason = ""
	# Race-based HP (HTML RACES table): ogres 550, humans 200, etc.
	var race_hp := 100.0
	var rmod: Dictionary = SimCombat.RACE_COMBAT.get(faction, {})
	if not rmod.is_empty():
		race_hp = float(rmod.get("hp", 100.0))
	var unit: Dictionary = _gs.add_unit({
		"faction": faction,
		"job": job,
		"town_id": town_id,
		"position": position,
		"alive": true,
		"hp": race_hp,
		"max_hp": race_hp,
	})
	# Deterministic gender from the unit id (HTML units have gender; it picks
	# the m/f sprite variant and survives save/load with no extra state).
	unit["gender"] = "m" if int(unit.get("id", 0)) % 2 == 0 else "f"
	# Faction-correct starting weapons (HTML ensureCombatSkills, 2026-09-19):
	# ogres alternate Musket / Blunderbuss by unit id parity — never a
	# universal "Issue Rifle". Everyone else starts on their basic arm.
	var fw: String = "basic"
	if faction == "ogres" and int(unit.get("id", 0)) % 2 == 1:
		fw = "shotgun"
	unit["firearm"] = fw
	unit["weapon_level"] = 0
	# Government: a spawned guild master pins to the phone's "My Government"
	# section (phone.gd government_contacts reads mind.gov_role).
	if job == "guild_master":
		SimArmy.assign_gov_role(unit, "guild_master")
	# Faction roster stats: stamp the HTML job-branch multipliers (hp/dmg/
	# speed/range/special flags) so faction uniques fight with their proper
	# stats instead of falling back to generic soldier melee.
	SimFactions.apply_faction_stats(unit)
	# Jeremy 2026-10-11: per-race lifespans — fresh adults start young, with
	# a randomized death day in the dying window. Undead are ageless.
	SimLifespans.seed_age(unit)
	_gs.bus.unit_spawned.emit(unit)
	return unit


## HTML ensureGovernmentDistrict parity: spawns the four district staff
## (Treasury/War/Civic advisors + Draft Clerk) once per faction at the hall.
## Advisors are non-workers (is_advisor) who staff the government offices.
## Idempotent per hall record (hall["gov_staff_spawned"]), and skips any role
## that already has a living unit of the faction (HTML same-job check).
## Goes through spawn_unit, so Jeremy's population caps still apply and a
## blocked role is skipped, not forced. Returns the spawned unit records.
## Jeremy 2026-10-04: faction advisors must spawn in — they were missing from
## the Godot build entirely (only a data contract existed in SimBuildings).
func spawn_government_staff(faction: String, town_id: int,
		hall: Dictionary) -> Array:
	var spawned: Array = []
	if hall.is_empty() or bool(hall.get("gov_staff_spawned", false)):
		return spawned
	hall["gov_staff_spawned"] = true
	var hp: Vector2 = hall.get("position", Vector2.ZERO)
	var i := 0
	for r: Dictionary in SimBuildings.GOV_ADVISOR_ROLES:
		var job: String = String(r.get("job", ""))
		var already := false
		for u: Dictionary in _gs.units:
			if u.get("alive", false) \
					and String(u.get("faction", "")) == faction \
					and String(u.get("job", "")) == job:
				already = true
				break
		if not already:
			# HTML: hall.x - 40 + i * 28, hall.y - cell * 2.5 (cell = 96).
			var pos := hp + Vector2(-40.0 + float(i) * 28.0, -240.0)
			var unit: Dictionary = spawn_unit(faction, job, town_id, pos)
			if not unit.is_empty():
				unit["is_advisor"] = true
				unit["is_worker"] = false
				unit["advisor_role"] = String(r.get("name", job))
				spawned.append(unit)
		i += 1
	return spawned
