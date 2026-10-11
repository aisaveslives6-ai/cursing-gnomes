class_name JobDefs
extends RefCounted
## Cursing Gnomes — job registry (Milestone 3: jobs & buildings).
##
## Every unit has a "job" (stored on its GameState record). This file is the
## single source of truth for what jobs exist, their display names, and which
## category they belong to. Behavior lives in WorkerAI (civilians/services)
## and the combat systems (military, Milestone 4).
##
## Design ported from the HTML build's job roster (not its code):
##   worker / woodcutter / miner / farmer / fisher / builder / roadbuilder  (civilian)
##   shopkeeper / cashier / barkeep / innkeeper / smith / repairman          (civilian — shop staff)
##   doctor / firefighter / adviser / clerk / diplomat / watchcaptain       (service)
##   guard / soldier / archer / ranger / mage / cannoneer                    (military)
##
## Pure logic — no rendering, no input, no audio.


## job_id -> {name, category, desc}.
## category is one of: "civilian" | "service" | "military".
const JOBS := {
	"worker":      {"name": "Worker",      "category": "civilian",
		"desc": "General laborer. Gathers whatever is nearest."},
	"woodcutter":  {"name": "Woodcutter",  "category": "civilian",
		"desc": "Fells trees, hauls wood to the stockpile."},
	"miner":       {"name": "Miner",       "category": "civilian",
		"desc": "Works stone quarries and gold mines."},
	"farmer":      {"name": "Farmer",      "category": "civilian",
		"desc": "Tends farms, hauls food to the granary."},
	"builder":     {"name": "Builder",     "category": "civilian",
		"desc": "Raises blueprints into finished buildings."},
	"roadbuilder": {"name": "Roadbuilder", "category": "civilian",
		"desc": "Lays roads between towns."},
	"fisher":      {"name": "Fisher",      "category": "civilian",
		"desc": "Works docks and water, hauls food."},
	"hunter":      {"name": "Hunter",      "category": "civilian",
		"desc": "Hunts wild animals for meat."},
	"shopkeeper":  {"name": "Shopkeeper",  "category": "civilian",
		"desc": "Tends shops. Staffs the trading post."},
	"cashier":     {"name": "Cashier",     "category": "civilian",
		"desc": "Works the register at the general store."},
	"barkeep":     {"name": "Barkeep",     "category": "civilian",
		"desc": "Tends the bar."},
	"innkeeper":   {"name": "Innkeeper",   "category": "civilian",
		"desc": "Minds the front desk of the inn."},
	"smith":       {"name": "Smith",       "category": "civilian",
		"desc": "Hammers at the forge."},
	"repairman":   {"name": "Repairman",   "category": "civilian",
		"desc": "Fixes gear at the repair shop."},
	"unemployed":  {"name": "Unemployed",  "category": "civilian",
		"desc": "Between jobs. Seeking work at the guild hall."},
	"doctor":      {"name": "Doctor",      "category": "service",
		"desc": "Staffs clinics. Heals the sick and injured."},
	"firefighter": {"name": "Firefighter", "category": "service",
		"desc": "Staffs fire stations. Fights fires, drives trucks."},
	"adviser":     {"name": "Adviser",     "category": "service",
		"desc": "Government officer. Balances the books from a hall cubicle."},
	# Jeremy 2026-10-04: government-district staff (HTML ensureGovernmentDistrict
	# roles, SimBuildings.GOV_ADVISOR_ROLES). Spawned once per faction with the
	# district; staff the offices, non-workers.
	"advisor_economy": {"name": "Treasury Advisor", "category": "service",
		"desc": "Government officer. Treasury advisor to the faction."},
	"advisor_war": {"name": "War Advisor", "category": "service",
		"desc": "Government officer. War advisor to the faction."},
	"advisor_civic": {"name": "Civic Advisor", "category": "service",
		"desc": "Government officer. Civic advisor to the faction."},
	"clerk":       {"name": "Clerk",       "category": "service",
		"desc": "Filing paperwork at the government hall."},
	"diplomat":    {"name": "Diplomat",    "category": "service",
		"desc": "Drafting letters at the government hall."},
	"watchcaptain": {"name": "Watch Captain", "category": "service",
		"desc": "Government officer. Commands the watch from a hall cubicle."},
	"guild_master": {"name": "Guild Master", "category": "service",
		"desc": "Staffs guild halls. Hires workers, keeps shops staffed."},
	"judge":       {"name": "Judge",       "category": "service",
		"desc": "Presides over trials at the courthouse. Hands down the verdicts."},
	"guard":       {"name": "Guard",       "category": "military",
		"desc": "Holds a post. Attacks hostiles in range."},
	"soldier":     {"name": "Soldier",     "category": "military",
		"desc": "Melee infantry. Sword and shield."},
	"archer":      {"name": "Archer",      "category": "military",
		"desc": "Ranged infantry. Bow and arrows."},
	"ranger":      {"name": "Ranger",      "category": "military",
		"desc": "Fast scout skirmisher."},
	"mage":        {"name": "Mage",        "category": "military",
		"desc": "Battle magic. Squishy, expensive, worth it."},
	"cannoneer":   {"name": "Cannoneer",   "category": "military",
		"desc": "Crew for field and grape cannons."},
	"bandit":      {"name": "Bandit",      "category": "military",
		"desc": "Raider. Not trainable — disaster only."},
	## Faction military rosters (HTML C61 uniques + faction basics).
	## Humans
	"swordsman":   {"name": "Swordsman",   "category": "military",
		"desc": "Human line infantry. Sword and shield."},
	"knight":      {"name": "Knight",      "category": "military",
		"desc": "Human elite. Fast slashes, cavalry charge."},
	"cleric":      {"name": "Cleric",      "category": "military",
		"desc": "Holy support. Smites undead, heals, cures plague."},
	## Ogres
	"clubber":     {"name": "Clubber",     "category": "military",
		"desc": "Ogre line infantry. Big club."},
	"musketeer":   {"name": "Musketeer",   "category": "military",
		"desc": "Ogre gunner. Slow, reaches far."},
	"berserker":   {"name": "Berserker",   "category": "military",
		"desc": "Ogre elite. Hammer smash splash."},
	"warlord":     {"name": "Warlord",     "category": "military",
		"desc": "Ogre commander. Aura buffs nearby allies' attacks."},
	"blunderbuss": {"name": "Blunderbuss", "category": "military",
		"desc": "Ogre shotgun. 5-pellet cone, devastating up close."},
	## Gnomes
	"axeman":      {"name": "Axeman",      "category": "military",
		"desc": "Gnome line infantry. Axe and attitude."},
	"tinker_mech": {"name": "Tinker Mech", "category": "military",
		"desc": "Gnome mech suit. Tanky, big splash punches."},
	"saboteur":    {"name": "Saboteur",    "category": "military",
		"desc": "Gnome infiltrator. Shreds walls."},
	## Elves
	"warlock":     {"name": "Warlock",     "category": "military",
		"desc": "Elf elite. Summons nature spirits."},
	"treant":      {"name": "Treant",      "category": "military",
		"desc": "Elf siege. Slow, huge, shreds buildings."},
	"spellweaver": {"name": "Spellweaver", "category": "military",
		"desc": "Elf crowd control. Snares enemies."},
	## Summoned
	"spirit":      {"name": "Nature Spirit", "category": "military",
		"desc": "Warlock summon. Fades after 18 seconds."},
}

## Resource each gatherer job collects: job_id -> resource id (Config.RESOURCES).
const GATHER_RESOURCE := {
	"woodcutter": "wood",
	"miner": "oil",   # gold mines handled by work site type, not job
	"farmer": "food",
	"fisher": "food",
	"hunter": "food",
	"worker": "wood",
}

## Placeholder job colors for the programmer-art job dot on UnitNode.
const JOB_DOT_COLORS := {
	"worker": Color(0.75, 0.75, 0.75),
	"woodcutter": Color(0.55, 0.35, 0.2),
	"miner": Color(0.5, 0.5, 0.55),
	"farmer": Color(0.95, 0.85, 0.3),
	"builder": Color(0.95, 0.6, 0.2),
	"roadbuilder": Color(0.6, 0.5, 0.4),
	"fisher": Color(0.35, 0.65, 0.9),
	"hunter": Color(0.5, 0.7, 0.3),
	"shopkeeper": Color(0.95, 0.75, 0.35),
	"cashier": Color(0.85, 0.7, 0.45),
	"barkeep": Color(0.8, 0.5, 0.25),
	"innkeeper": Color(0.7, 0.6, 0.8),
	"smith": Color(0.9, 0.45, 0.15),
	"repairman": Color(0.55, 0.65, 0.75),
	"unemployed": Color(0.45, 0.45, 0.52),
	"adviser": Color(0.55, 0.75, 0.55),
	"clerk": Color(0.7, 0.75, 0.7),
	"diplomat": Color(0.75, 0.65, 0.9),
	"watchcaptain": Color(0.45, 0.45, 0.95),
	"doctor": Color(1.0, 1.0, 1.0),
	"firefighter": Color(1.0, 0.25, 0.2),
	"guild_master": Color(0.85, 0.65, 0.2),
	"guard": Color(0.3, 0.3, 0.9),
	"soldier": Color(0.9, 0.2, 0.2),
	"archer": Color(0.2, 0.8, 0.2),
	"ranger": Color(0.2, 0.6, 0.2),
	"mage": Color(0.7, 0.3, 0.9),
	"cannoneer": Color(0.25, 0.25, 0.25),
}


## True if the job id is a known job.
static func is_job(job: String) -> bool:
	return JOBS.has(job)


## Display name for a job id ("woodcutter" -> "Woodcutter").
static func job_name(job: String) -> String:
	var d: Dictionary = JOBS.get(job, {})
	return String(d.get("name", job))


## Category of a job id ("civilian" | "service" | "military"), "" if unknown.
static func category(job: String) -> String:
	var d: Dictionary = JOBS.get(job, {})
	return String(d.get("category", ""))


static func is_civilian(job: String) -> bool:
	return category(job) == "civilian"


static func is_service(job: String) -> bool:
	return category(job) == "service"


static func is_military(job: String) -> bool:
	return category(job) == "military"


## Resource id a gatherer job collects, "" if the job doesn't gather.
static func gather_resource(job: String) -> String:
	return String(GATHER_RESOURCE.get(job, ""))


## All job ids in a category, for build menus / training lists.
static func jobs_in_category(cat: String) -> Array[String]:
	var out: Array[String] = []
	for job_id: String in JOBS.keys():
		if String((JOBS[job_id] as Dictionary).get("category", "")) == cat:
			out.append(job_id)
	return out


## Workplace roster table — port of the HTML build's ROSTER57_WORKPLACES
## (MISS 13/14). Each entry: {types: [building types], job, slots: base
## slots per building, spot: work spot inside/near the building,
## act: visible activity label}.
##
## Godot building ids replace the HTML roster's storage/seedshop/
## restaurant/inn/hotel/weaponsmith/cannon_foundry/armory/medic_camp set
## (only Godot-existing types are listed). Officer posts (guild_master,
## adviser, watchcaptain) anchor on the town hall — unique per town, like
## the HTML's "anchor them on the hall only" rule; the guild master's
## *office* is the guild hall (WorkerAI handles that).
const WORKPLACES: Array[Dictionary] = [
	{"types": ["storage"], "job": "cashier", "slots": 1, "spot": "counter",
		"act": "working the register"},
	{"types": ["shop"], "job": "shopkeeper", "slots": 1, "spot": "counter",
		"act": "tending the shop"},
	{"types": ["restaurant"], "job": "shopkeeper", "slots": 1, "spot": "counter",
		"act": "serving food"},
	{"types": ["soul_cafe"], "job": "shopkeeper", "slots": 1, "spot": "counter",
		"act": "serving essence"},
	{"types": ["repair_shop"], "job": "repairman", "slots": 1, "spot": "site",
		"act": "repairing gear"},
	{"types": ["clinic"], "job": "doctor", "slots": 1, "spot": "desk",
		"act": "treating patients"},
	{"types": ["fire_station"], "job": "firefighter", "slots": 1, "spot": "stage",
		"act": "standing ready"},
	{"types": ["guard_tower", "guard_house"], "job": "guard", "slots": 1,
		"spot": "patrol", "act": "on patrol"},
	{"types": ["barracks", "war_hut"], "job": "soldier", "slots": 2,
		"spot": "patrol", "act": "on patrol"},
	{"types": ["town_hall", "hall"], "job": "guild_master", "slots": 1,
		"spot": "desk", "act": "running the guild"},
	{"types": ["town_hall", "hall"], "job": "adviser", "slots": 1,
		"spot": "desk", "act": "balancing the books"},
	{"types": ["town_hall", "hall"], "job": "clerk", "slots": 1,
		"spot": "desk", "act": "filing paperwork"},
	{"types": ["town_hall", "hall"], "job": "diplomat", "slots": 1,
		"spot": "desk", "act": "drafting letters"},
	{"types": ["town_hall", "hall"], "job": "watchcaptain", "slots": 1,
		"spot": "desk", "act": "commanding the watch"},
]

## Open hours per building type — port of the HTML's ROSTER57_OPEN_HOURS
## (MISS 15). Shops need enough staff to cover every 8 h workday.
const OPEN_HOURS := {
	"storage": 12, "shop": 12, "restaurant": 12, "soul_cafe": 12,
	"repair_shop": 10,
	"clinic": 12, "fire_station": 24,
	"guard_tower": 24, "guard_house": 24, "barracks": 24, "war_hut": 24,
	"town_hall": 10, "hall": 10, "guild_hall": 10,
}

## Workday length (hours) used by the coverage formula.
const WORKDAY_LEN := 8.0


## Coverage headcount — port of rosterSlotsFor57 (MISS 15):
## slots = ceil(openHours / workdayLen) * baseSlots, minimum 1.
## A 12 h shop with 8 h workdays needs 2 staff per base slot.
static func slots_for(btype: String, base: int) -> int:
	var open: float = float(OPEN_HOURS.get(btype, 10))
	var shifts: int = maxi(1, int(ceil(open / WORKDAY_LEN)))
	return shifts * maxi(1, base)


## The workplace entry for a job id ({} when the job has no station).
static func workplace_for(job: String) -> Dictionary:
	for e: Dictionary in WORKPLACES:
		if String(e.get("job", "")) == job:
			return e
	return {}


## True when the job works at a building station (HTML stationTick57
## roster jobs) rather than free-roaming.
static func is_station_job(job: String) -> bool:
	return not workplace_for(job).is_empty()


## True when the job works at a desk (advisers, clerks, diplomats,
## officers) — claims a cubicle desk in the government building.
static func is_desk_job(job: String) -> bool:
	return String(workplace_for(job).get("spot", "")) == "desk"


## Work spot offset from the building center — port of stationSpotXY57.
## "patrol" is handled per-tick by WorkerAI (time-based legs).
static func spot_offset(spot: String, size: float, job: String) -> Vector2:
	var front: float = size * 0.62
	match spot:
		"counter":
			return Vector2(14.0 if job == "shopkeeper" else -14.0, front)
		"bar":
			return Vector2(0.0, front)
		"desk":
			return Vector2(10.0, front * 0.7)
		"forge":
			return Vector2(front, 6.0)
		"stage":
			return Vector2(0.0, 10.0)
		"site":
			return Vector2(front * 0.8, front * 0.5)
	return Vector2(0.0, front)
