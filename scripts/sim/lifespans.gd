class_name SimLifespans
extends RefCounted
## Cursing Gnomes — per-race lifespans + natural aging (Jeremy 2026-10-11).
##
## The FIRST natural-death mechanic: neither the HTML original nor the Godot
## build had old-age death. Kept gentle and dignified, per Jeremy's design
## philosophy (the game rewards empathy — how a society treats its elders
## and remembers its dead says everything):
##   - Units age in game years (360 days: SimSeasons 12 months x 30).
##     Life stages: youth (child) -> adult -> elder (final quarter).
##     Elders move a little slower (0.85x) — visible, never cruel.
##   - Death arrives in a randomized window around the racial lifespan
##     (0.90x-1.08x), never a cliff. A quiet passing — no sirens, no gore.
##   - Notables (advisors, guild masters) get a Gazette obituary with a
##     funeral notice; spouses and friends mourn (memory + mood dip), even
##     at a distance. Feeds the quote-memory system via "friend_died".
##   - Empty advisor seats are refilled (succession) — the phone's
##     government section never dead-ends on a null advisor.
##   - Undead are ageless: they do not die of old age. (They can still be
##     destroyed; they just don't crumble from birthdays.)
##
## Pure sim logic — no rendering. Own day_changed hook.


## Jeremy's decree (2026-10-11): elves live 20 game years, longest of all.
## Undead are NOT in this table: ageless, exempt from old-age death.
const LIFESPAN_YEARS := {
	"elves": 20.0,
	"gnomes": 14.0,
	"humans": 12.0,
	"ogres": 9.0,  # brutish, burn bright
}
const DAYS_PER_YEAR := 360.0  # SimSeasons: 12 months x 30 days
const ELDER_FRACTION := 0.75  # final quarter of life = elder
const DEATH_LO := 0.90        # dying window: randomized, no cliff
const DEATH_HI := 1.08
const ELDER_MOVE_MULT := 0.85
const OBITUARY_COOLDOWN_DAYS := 3
const MOURN_MOOD_DIP := 12.0
const HALL_TYPES := ["town_hall", "hall"]
const PEOPLE_FACTIONS := ["humans", "ogres", "elves", "gnomes", "undead"]


var _gs: GameState
var _mem: SimMemories
var _obit_day := {}  # faction -> last obituary day (Gazette spam guard)


func _init(game_state: GameState) -> void:
	_gs = game_state
	_mem = SimMemories.new(game_state)
	var bus = _gs.get("bus")
	if bus == null:
		return
	if bus.has_signal("day_changed"):
		bus.day_changed.connect(_on_day)


## --- Static helpers -------------------------------------------------------

## Undead are ageless — no old-age death, ever.
static func is_ageless(faction: String) -> bool:
	return faction == "undead"


static func lifespan_years(faction: String) -> float:
	return float(LIFESPAN_YEARS.get(faction, 0.0))


static func lifespan_days(faction: String) -> float:
	return lifespan_years(faction) * DAYS_PER_YEAR


## Seed a fresh adult's age: young adult, 5-25% into their lifespan, with a
## randomized death day in the dying window. Called from Spawner.spawn_unit.
## Children skip seeding — SimFamily owns childhood; the first adult-day
## tick seeds them instead.
static func seed_age(unit: Dictionary) -> void:
	if String(unit.get("job", "")) == "child":
		return
	var faction := String(unit.get("faction", ""))
	if is_ageless(faction) or not faction in PEOPLE_FACTIONS:
		return
	var span := lifespan_days(faction)
	if span <= 0.0:
		return
	unit["age_days"] = span * randf_range(0.05, 0.25)
	unit["death_day"] = span * randf_range(DEATH_LO, DEATH_HI)
	unit["age_stage"] = "adult"


## Whole years lived, for obituaries.
static func age_years(unit: Dictionary) -> float:
	return float(unit.get("age_days", 0.0)) / DAYS_PER_YEAR


## --- Daily tick ------------------------------------------------------------

func _on_day(day: int, _is_night: bool) -> void:
	# Iterate a copy: _pass_away -> _ensure_succession can append a
	# successor to _gs.units mid-loop.
	for u in _gs.units.duplicate():
		if not (u is Dictionary):
			continue
		if not bool(u.get("alive", false)):
			continue
		var faction := String(u.get("faction", ""))
		if is_ageless(faction) or not faction in PEOPLE_FACTIONS:
			continue
		if bool(u.get("is_child", false)):
			continue  # SimFamily owns childhood aging; we take over at grow-up
		_tick_unit(u, day)


func _tick_unit(u: Dictionary, day: int) -> void:
	var faction := String(u.get("faction", ""))
	var span := lifespan_days(faction)
	if span <= 0.0:
		return
	# Legacy saves / hand-built test units: seed on first sight (young, so
	# no surprise mass die-off the day this ships).
	if not u.has("age_days") or not u.has("death_day"):
		seed_age(u)
	u["age_days"] = float(u.get("age_days", 0.0)) + 1.0
	var age := float(u.get("age_days", 0.0))
	# Elder transition: final quarter of life. Gentle slowdown, applied once.
	if age >= span * ELDER_FRACTION and String(u.get("age_stage", "adult")) != "elder":
		u["age_stage"] = "elder"
		u["age_move_mult"] = ELDER_MOVE_MULT
	# Quiet passing: inside the randomized dying window.
	if age >= float(u.get("death_day", span * DEATH_HI)):
		_pass_away(u, day)


## --- The quiet passing -----------------------------------------------------

func _pass_away(u: Dictionary, day: int) -> void:
	var uid := int(u.get("id", -1))
	var faction := String(u.get("faction", ""))
	var years := age_years(u)
	u["death_cause"] = "old_age"
	u["age_at_death"] = years
	var notable := _is_notable(u)
	var dname := SimPersonality.display_name(u)
	var role := SimArmy.gov_role_of(u)
	var job := String(u.get("job", ""))
	var town_id := int(u.get("town_id", -1))
	# Mark dead through the canonical path (fires unit_died -> nearby
	# friends grieve via SimMind, adventure hooks, etc.). No gore, no FX:
	# this is a peaceful passing, not a kill.
	_gs.kill_unit(uid)
	if notable:
		_mourn_distant(u, uid, faction, dname)
		_publish_obituary(faction, dname, years, role, job, day)
	_ensure_succession(faction, job, role, town_id)


## Advisors, guild masters, and anyone holding a government role get the
## obituary + funeral treatment. Ordinary folk are mourned privately by
## whoever loved them (via the unit_died -> SimMind grief path).
func _is_notable(u: Dictionary) -> bool:
	if bool(u.get("is_advisor", false)):
		return true
	if SimArmy.gov_role_of(u) != "":
		return true
	return String(u.get("job", "")) == "guild_master"


func _publish_obituary(faction: String, dname: String, years: float,
		role: String, job: String, day: int) -> void:
	var last := int(_obit_day.get(faction, -OBITUARY_COOLDOWN_DAYS - 1))
	if day - last < OBITUARY_COOLDOWN_DAYS:
		return  # an elder generation passing together gets one notice
	_obit_day[faction] = day
	var fname := String(Config.FACTIONS.get(faction, {}).get("name", faction))
	var title := role
	if title == "":
		match job:
			"advisor_economy":
				title = "Treasury Advisor"
			"advisor_war":
				title = "War Advisor"
			"advisor_civic":
				title = "Civic Advisor"
			"clerk":
				title = "Draft Clerk"
			"guild_master":
				title = "Guild Master"
			_:
				title = job.replace("_", " ").capitalize()
	SimGazette.publish_or_emit(_gs,
		"OBITUARY — %s" % dname,
		"%s, %s of the %s, has passed away peacefully at the age of %d, after a full life of service. %s. A quiet funeral will be held at dusk; all are welcome to pay their respects." % [
			dname, title, fname, int(years),
			"Their counsel will be missed" if role != "" or job.begins_with("advisor") else "They will be missed"],
		"obituary")


## Friends and spouses beyond earshot still feel it: a memory that feeds
## the quote-memory system, and a real mood dip. (Nearby friends are
## already covered by SimMind.on_unit_died via the unit_died signal.)
func _mourn_distant(dead: Dictionary, uid: int, faction: String, dname: String) -> void:
	var fam = _gs.get("family")
	for u in _gs.units:
		if not (u is Dictionary):
			continue
		if not bool(u.get("alive", false)):
			continue
		if int(u.get("id", -1)) == uid:
			continue
		if String(u.get("faction", "")) != faction:
			continue
		var is_spouse := int(u.get("spouse_uid", -1)) == uid
		var is_friend := fam != null \
			and float(fam.get_affinity(u, dead)) >= SimFamily.FRIEND_SCORE
		if not (is_spouse or is_friend):
			continue
		_mem.remember(u, "friend_died", uid, dname, faction, 1.0)
		u["mood"] = clampf(float(u.get("mood", 60.0)) - MOURN_MOOD_DIP, 0.0, 100.0)


## Succession: if the dead unit held a job no living faction-mate holds
## anymore (advisor seats, guild master), appoint a replacement at a town
## hall. The phone's government section never dead-ends.
func _ensure_succession(faction: String, job: String, gov_role: String, town_id: int) -> void:
	if job == "" or job == "child":
		return
	for u in _gs.units:
		if not (u is Dictionary):
			continue
		if bool(u.get("alive", false)) \
				and String(u.get("faction", "")) == faction \
				and String(u.get("job", "")) == job:
			return  # seat already filled
	var hall := _find_hall(faction, town_id)
	if hall.is_empty():
		return  # no hall standing — nothing to staff
	var spawner = _gs.get("spawner")
	if spawner == null or not spawner.has_method("spawn_unit"):
		return
	var pos: Vector2 = hall.get("position", Vector2.ZERO) + Vector2(-40.0, -240.0)
	var nu: Dictionary = spawner.spawn_unit(faction, job,
		int(hall.get("town_id", town_id)), pos)
	if nu.is_empty():
		return  # caps said no — the spawner is the law
	nu["is_advisor"] = true
	if gov_role != "":
		SimArmy.assign_gov_role(nu, gov_role)


func _find_hall(faction: String, prefer_town: int) -> Dictionary:
	var fallback := {}
	for b in _gs.buildings:
		if not (b is Dictionary):
			continue
		if not String(b.get("type", "")) in HALL_TYPES:
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if bool(b.get("destroyed", false)):
			continue
		if int(b.get("town_id", -1)) == prefer_town:
			return b
		if fallback.is_empty():
			fallback = b
	return fallback


## --- Save / load ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"obit_day": _obit_day.duplicate()}


func from_dict(data: Dictionary) -> void:
	_obit_day = (data.get("obit_day", {}) as Dictionary).duplicate()
