class_name SimDisease
extends RefCounted
## Cursing Gnomes — plague/disease system + plague doctrines (Jeremy 2026-10-11).
##
## The moral-choice centerpiece: twisted or benevolent, the ruler's call.
##
## Immunity (Jeremy's decree):
##   undead, elves — CANNOT get sick, ever (susceptibility 0.0)
##   gnomes — rare (0.15)
##   ogres  — moderate (0.60)
##   humans — full (1.0)
##
## Outbreaks: each autumn, every vulnerable faction rolls OUTBREAK_CHANCE for
## a plague strike; 1-3 initial cases seed in a random town. The plague
## SPREADS on the day tick — proximity transmission between vulnerable NPCs
## of the same town. Bounded: per-faction daily infection cap, town-sized
## scan sets (16/town cap), never per-frame.
##
## Sick NPCs are VISIBLE: u["sick"] drives a pale-green tint via
## UnitNode.set_sick (world.gd sync), and the status shows in profiles.
##
## Plague doctrines (policies, changeable ANYTIME — mid-outbreak switches
## apply the next day tick):
##   mercy         — save them all: quarantine-as-care + full treatment,
##                     no executions ever. (default)
##   cure          — doctors treat the sick where they stand.
##   quarantine    — the sick are rounded up to clinics; no spread from the
##                     quarantined; doctors treat them there.
##   cull_military — soldiers execute the sick on the spot. Fast, brutal —
##                     executioners risk infection doing it.
##   cull_doctor   — doctors put the sick down quietly. Still dark.
##   ignore        — do nothing; the plague runs its course.
## Every doctrine has visible consequences: Gazette coverage, NPC memories
## (fear of cullings, gratitude for saves), relations shifts. The player
## sets doctrine in the Policies app (phone) or via advisors; AI factions
## pick a doctrine by temperament at outbreak.
##
## NOT a disaster — kept out of the disaster roster per Jeremy's freeze.
## Pure sim logic — no rendering. Own day_changed hook.


const SUSCEPTIBILITY := {
	"humans": 1.0,
	"ogres": 0.60,
	"gnomes": 0.15,
	"elves": 0.0,   # immune, Jeremy's decree
	"undead": 0.0,  # immune, Jeremy's decree
}
const PEOPLE_FACTIONS: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]

## Doctrine keys + display (mirrored in SimPolicies.PLAGUE_POLICIES).
const DOCTRINE_MERCY := "mercy"
const DOCTRINE_CURE := "cure"
const DOCTRINE_QUARANTINE := "quarantine"
const DOCTRINE_CULL_MILITARY := "cull_military"
const DOCTRINE_CULL_DOCTOR := "cull_doctor"
const DOCTRINE_IGNORE := "ignore"
const DOCTRINES: Array[String] = [DOCTRINE_MERCY, DOCTRINE_CURE,
	DOCTRINE_QUARANTINE, DOCTRINE_CULL_MILITARY, DOCTRINE_CULL_DOCTOR,
	DOCTRINE_IGNORE]
const DEFAULT_DOCTRINE := DOCTRINE_MERCY

const OUTBREAK_CHANCE := 0.35       # per vulnerable faction each autumn
const SEED_CASES_MIN := 1
const SEED_CASES_MAX := 3
const SPREAD_RADIUS := 130.0        # px, same-town transmission
const SPREAD_CHANCE := 0.22         # per sick->vulnerable contact per day
const MAX_NEW_PER_DAY := 6          # per faction — bounds the sim
const DISEASE_DAYS_MIN := 6
const DISEASE_DAYS_MAX := 10
const NATURAL_RECOVERY := 0.10      # per day, untreated
const UNTREATED_DEATH := 0.10       # per day once sick_days > 3
const CULL_PER_DAY := 4             # executions per faction per day
const EXECUTION_INFECTION := 0.15   # military executioner risk
const DOCTOR_EXEC_INFECTION := 0.08 # doctors know precautions
const TREATMENTS_PER_DOCTOR := 2
## Cure math lives on SimSkills (CURE_BASE / CURE_PER_LEVEL) — the
## dependency runs one way: disease -> skills.
const QUARANTINE_PER_CLINIC := 4
const OUTBREAK_COOLDOWN_DAYS := 30  # a faction can't be re-seeded sooner


var _gs: GameState
var _mem: SimMemories
var _doctrines := {}       # faction -> doctrine key
var _last_outbreak := {}   # faction -> day of last seeded outbreak
var _last_month := -1
var _stats := {}           # faction -> {"saved": n, "culled": n, "died": n}
var _announced_keys := {}  # one-shot Gazette guards


func _init(game_state: GameState) -> void:
	_gs = game_state
	_mem = SimMemories.new(game_state)
	var bus = _gs.get("bus")
	if bus == null:
		return
	if bus.has_signal("day_changed"):
		bus.day_changed.connect(_on_day)


## --- Static helpers ---------------------------------------------------------

static func susceptibility(faction: String) -> float:
	return float(SUSCEPTIBILITY.get(faction, 0.0))


static func is_immune(faction: String) -> bool:
	return susceptibility(faction) <= 0.0


static func is_sick(unit: Dictionary) -> bool:
	return bool(unit.get("sick", false)) and bool(unit.get("alive", false))


## --- Doctrine access ----------------------------------------------------------

func doctrine_of(faction: String) -> String:
	if _doctrines.has(faction):
		return String(_doctrines[faction])
	if faction == _gs.player_faction:
		var pol = _policy_source()
		if pol != null:
			return String(pol.state.get("plague_policy", DEFAULT_DOCTRINE))
	return DEFAULT_DOCTRINE


func set_doctrine(faction: String, doctrine: String) -> void:
	if doctrine in DOCTRINES:
		_doctrines[faction] = doctrine


func _policy_source():
	var court = _gs.get("court_sys")
	if court != null and court.get("policies") != null:
		return court.policies
	return null


## --- Daily tick ---------------------------------------------------------------

func _on_day(day: int, _is_night: bool) -> void:
	_maybe_autumn_outbreak(day)
	_tick_spread(day)
	_tick_doctrines(day)
	_tick_recovery(day)


## Each autumn (month 9 arrival), vulnerable factions may catch the plague.
func _maybe_autumn_outbreak(day: int) -> void:
	var seasons = _gs.get("seasons")
	if seasons == null:
		return
	var month: int = seasons.month()
	var was := _last_month
	_last_month = month
	if was == month:
		return
	if month != 9:  # Fallingleaf — autumn's first month
		return
	for faction: String in PEOPLE_FACTIONS:
		if is_immune(faction):
			continue
		if day - int(_last_outbreak.get(faction, -OUTBREAK_COOLDOWN_DAYS - 1)) \
				< OUTBREAK_COOLDOWN_DAYS:
			continue
		if randf() < OUTBREAK_CHANCE:
			_seed_outbreak(faction, day)


func _seed_outbreak(faction: String, day: int) -> void:
	_last_outbreak[faction] = day
	_ai_pick_doctrine(faction)
	var candidates: Array = []
	for u in _gs.units:
		if not (u is Dictionary):
			continue
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if is_sick(u) or is_immune(String(u.get("faction", ""))):
			continue
		candidates.append(u)
	if candidates.is_empty():
		return
	candidates.shuffle()
	var n := randi_range(SEED_CASES_MIN, SEED_CASES_MAX)
	var seeded := 0
	for u in candidates:
		if seeded >= n:
			break
		_infect(u, day)
		seeded += 1
	if seeded > 0:
		var fname := _faction_name(faction)
		SimGazette.publish_or_emit(_gs,
			"PLAGUE IN %s LANDS" % fname.to_upper(),
			"A wasting sickness has taken hold among the %s. The sick grow pale and weak; wise rulers are choosing their doctrine — mercy or the sword. The court watches." % fname,
			"plague")


## AI factions pick a doctrine by temperament at outbreak.
func _ai_pick_doctrine(faction: String) -> void:
	if _doctrines.has(faction):
		return
	var roll := randf()
	var d := DOCTRINE_QUARANTINE
	if roll < 0.15:
		d = DOCTRINE_MERCY
	elif roll < 0.40:
		d = DOCTRINE_CURE
	elif roll < 0.50:
		d = DOCTRINE_IGNORE
	elif roll < 0.60:
		d = DOCTRINE_CULL_MILITARY
	_doctrines[faction] = d


func _infect(u: Dictionary, _day: int) -> void:
	if is_sick(u):
		return
	u["sick"] = true
	u["sick_days"] = 0
	u["sick_duration"] = randi_range(DISEASE_DAYS_MIN, DISEASE_DAYS_MAX)
	u["quarantined"] = false


func _cure(u: Dictionary) -> void:
	u["sick"] = false
	u.erase("sick_days")
	u.erase("sick_duration")
	u["quarantined"] = false


## --- Spread -------------------------------------------------------------------

func _tick_spread(day: int) -> void:
	# Per faction: sick units infect nearby vulnerable town-mates.
	var sick_by_faction := {}
	for u in _gs.units:
		if not is_sick(u):
			continue
		if bool(u.get("quarantined", false)):
			continue  # the quarantined don't spread
		var f := String(u.get("faction", ""))
		if not sick_by_faction.has(f):
			sick_by_faction[f] = []
		(sick_by_faction[f] as Array).append(u)
	for faction: String in sick_by_faction.keys():
		var new_cases := 0
		var sick_list: Array = sick_by_faction[faction]
		for s in sick_list:
			if new_cases >= MAX_NEW_PER_DAY:
				break
			var spos: Vector2 = s.get("position", Vector2.ZERO)
			var town := int(s.get("town_id", -1))
			for u in _gs.units:
				if new_cases >= MAX_NEW_PER_DAY:
					break
				if not (u is Dictionary) or not bool(u.get("alive", false)):
					continue
				if String(u.get("faction", "")) != faction:
					continue
				if is_sick(u) or int(u.get("town_id", -2)) != town:
					continue
				if randf() > susceptibility(faction):
					continue  # susceptibility gate (gnomes rarely catch)
				var upos: Vector2 = u.get("position", Vector2.ZERO)
				if spos.distance_to(upos) > SPREAD_RADIUS:
					continue
				if randf() < SPREAD_CHANCE:
					_infect(u, day)
					new_cases += 1


## --- Doctrines ------------------------------------------------------------------

func _tick_doctrines(day: int) -> void:
	for faction: String in PEOPLE_FACTIONS:
		if is_immune(faction):
			continue
		var doctrine := doctrine_of(faction)
		match doctrine:
			DOCTRINE_CULL_MILITARY:
				_tick_cull(faction, day, true)
			DOCTRINE_CULL_DOCTOR:
				_tick_cull(faction, day, false)
			DOCTRINE_QUARANTINE:
				_tick_quarantine(faction, day, true)
			DOCTRINE_CURE:
				_tick_treatment(faction, day, false)
			DOCTRINE_MERCY:
				_tick_quarantine(faction, day, false)
				_tick_treatment(faction, day, true)
			DOCTRINE_IGNORE:
				pass


func _sick_of(faction: String) -> Array:
	var out: Array = []
	for u in _gs.units:
		if not (u is Dictionary):
			continue
		if is_sick(u) and String(u.get("faction", "")) == faction:
			out.append(u)
	return out


func _doctors_of(faction: String) -> Array:
	var out: Array = []
	for u in _gs.units:
		if not (u is Dictionary):
			continue
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("job", "")) == "doctor":
			out.append(u)
	return out


func _soldiers_of(faction: String) -> Array:
	var out: Array = []
	for u in _gs.units:
		if not (u is Dictionary):
			continue
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if JobDefs.is_military(String(u.get("job", ""))):
			out.append(u)
	return out


## Executions: bounded per day. Executioners risk infection.
func _tick_cull(faction: String, day: int, military: bool) -> void:
	var sick := _sick_of(faction)
	if sick.is_empty():
		return
	var crew := _soldiers_of(faction) if military else _doctors_of(faction)
	if crew.is_empty():
		return
	var risk := EXECUTION_INFECTION if military else DOCTOR_EXEC_INFECTION
	var done := 0
	crew.shuffle()
	sick.shuffle()
	for s in sick:
		if done >= CULL_PER_DAY:
			break
		var ex: Dictionary = crew[done % crew.size()]
		var uid := int(s.get("id", -1))
		var dname := SimPersonality.display_name(s)
		s["death_cause"] = "plague_cull"
		_gs.kill_unit(uid)
		_bump_stat(faction, "culled")
		# Witnesses remember the culling — the fear sticks. Strength is
		# salience (clamped [0,2]); the "friend_died" type carries the
		# negative valence via the emotion map. The culling must be
		# REMEMBERED — that's the moral weight.
		_remember_near(s, "friend_died", uid, dname, 1.2)
		done += 1
		# The executioner breathes the same air.
		if not is_immune(String(ex.get("faction", ""))) \
				and not is_sick(ex) and randf() < risk:
			_infect(ex, day)
	if done > 0:
		_gazette_cull(faction, done, military, day)


func _gazette_cull(faction: String, n: int, military: bool, day: int) -> void:
	var fname := _faction_name(faction)
	var key := "cull_%s_%d" % [faction, day]
	if _announced(key):
		return
	if military:
		SimGazette.publish_or_emit(_gs,
			"THE CULLING IN %s" % fname.to_upper(),
			"%d plague-sick souls were put to the sword in %s lands by order of the crown. Soldiers did the deed at spearpoint; none resisted — the sick could barely stand. The realm will remember this day, one way or another." % [n, fname],
			"plague")
	else:
		SimGazette.publish_or_emit(_gs,
			"QUIET MERCY KILLINGS IN %s" % fname.to_upper(),
			"%d of the plague-sick were quietly put down by %s doctors. No soldiers, no spectacle — just closed doors and lowered voices. Whether it was mercy or murder depends on who you ask." % [n, fname],
			"plague")


## Quarantine: round the sick up to clinics (capacity-bounded). The
## quarantined don't spread. Under mercy, quarantine is a care ward.
func _tick_quarantine(faction: String, day: int, strict: bool) -> void:
	var clinics := _clinics_of(faction)
	if clinics.is_empty():
		return  # no clinic — the sick stay home (still treated if mercy)
	var cap := clinics.size() * QUARANTINE_PER_CLINIC
	var in_q := 0
	for u in _gs.units:
		if bool(u.get("quarantined", false)) \
				and String(u.get("faction", "")) == faction \
				and bool(u.get("alive", false)):
			in_q += 1
	for s in _sick_of(faction):
		if in_q >= cap:
			break
		if bool(s.get("quarantined", false)):
			continue
		s["quarantined"] = true
		in_q += 1


func _clinics_of(faction: String) -> Array:
	var out: Array = []
	for b in _gs.buildings:
		if not (b is Dictionary):
			continue
		if String(b.get("type", "")) != "clinic":
			continue
		if not bool(b.get("complete", false)) or bool(b.get("destroyed", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		out.append(b)
	return out


## Treatment: doctors cure the sick; success scales with medicine skill.
func _tick_treatment(faction: String, day: int, include_home: bool) -> void:
	var doctors := _doctors_of(faction)
	if doctors.is_empty():
		return
	var sick := _sick_of(faction)
	if sick.is_empty():
		return
	# Quarantined first, then the rest (mercy treats everyone).
	sick.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return bool(a.get("quarantined", false)) \
			and not bool(b.get("quarantined", false)))
	var treated := 0
	var cured := 0
	for doc in doctors:
		var done := 0
		for s in sick:
			if done >= TREATMENTS_PER_DOCTOR:
				break
			if not bool(s.get("alive", false)) or not is_sick(s):
				continue
			if not include_home and not bool(s.get("quarantined", false)):
				continue
			done += 1
			treated += 1
			SimSkills.grant(_gs, doc, "medicine", 8.0)
			if randf() < SimSkills.cure_chance(doc):
				_cure(s)
				cured += 1
				_bump_stat(faction, "saved")
				_mem.remember(s, "saved_by", int(doc.get("id", -1)),
					SimPersonality.display_name(doc), faction, 0.8)
	if cured >= 3:
		SimGazette.publish_or_emit(_gs,
			"THE DOCTORS PREVAIL IN %s" % _faction_name(faction).to_upper(),
			"%s healers pulled %d souls back from the plague this week. %s" % [
				_faction_name(faction), cured,
				"Their medicine grows sharper with every life saved."
				if cured >= 5 else "The wards hold — barely."],
			"plague")


## --- Natural course: recovery or death ------------------------------------------

func _tick_recovery(_day: int) -> void:
	for u in _gs.units.duplicate():
		if not (u is Dictionary):
			continue
		if not is_sick(u):
			continue
		u["sick_days"] = int(u.get("sick_days", 0)) + 1
		var days := int(u.get("sick_days", 0))
		var dur := int(u.get("sick_duration", DISEASE_DAYS_MAX))
		# Recovered on their own.
		if days >= dur or randf() < NATURAL_RECOVERY:
			_cure(u)
			continue
		# The plague takes its tithe.
		if days > 3 and randf() < UNTREATED_DEATH:
			var uid := int(u.get("id", -1))
			var faction := String(u.get("faction", ""))
			var dname := SimPersonality.display_name(u)
			u["death_cause"] = "plague"
			_gs.kill_unit(uid)
			_bump_stat(faction, "died")
			_remember_near(u, "friend_died", uid, dname, 0.8)


## --- Helpers --------------------------------------------------------------------

func _remember_near(dead: Dictionary, key: String, subject_id: int,
		subject_name: String, weight: float) -> void:
	var dpos: Vector2 = dead.get("position", Vector2.ZERO)
	var faction := String(dead.get("faction", ""))
	for u in _gs.units:
		if not (u is Dictionary) or not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		if dpos.distance_to(upos) > 400.0:
			continue
		_mem.remember(u, key, subject_id, subject_name, faction, weight)


func _faction_name(faction: String) -> String:
	return String(Config.FACTIONS.get(faction, {}).get("name", faction))


func _bump_stat(faction: String, key: String) -> void:
	var st: Dictionary = _stats.get(faction, {"saved": 0, "culled": 0, "died": 0})
	st[key] = int(st.get(key, 0)) + 1
	_stats[faction] = st


func stats_of(faction: String) -> Dictionary:
	return (_stats.get(faction, {"saved": 0, "culled": 0, "died": 0}) as Dictionary).duplicate()


func sick_count(faction: String = "") -> int:
	var n := 0
	for u in _gs.units:
		if not (u is Dictionary):
			continue
		if is_sick(u) and (faction == "" or String(u.get("faction", "")) == faction):
			n += 1
	return n


func _announced(key: String) -> bool:
	if _announced_keys.has(key):
		return true
	_announced_keys[key] = true
	return false


## --- Save / load ------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"doctrines": _doctrines.duplicate(true),
		"last_outbreak": _last_outbreak.duplicate(true),
		"last_month": _last_month,
		"stats": _stats.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	_doctrines = (data.get("doctrines", {}) as Dictionary).duplicate(true)
	_last_outbreak = (data.get("last_outbreak", {}) as Dictionary).duplicate(true)
	_last_month = int(data.get("last_month", -1))
	_stats = (data.get("stats", {}) as Dictionary).duplicate(true)
