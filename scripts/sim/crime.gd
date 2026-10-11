class_name SimCrime
extends RefCounted
## Cursing Gnomes — crime system (Milestone 7+).
##
## Faithful port of the HTML build's crime logic (candidates 55/57/58/60/61):
##   - per-unit crime records: {shady, desperate, klepto, criminal, jailedUntil,
##     c55: {crimes[], wanted, awaitingTrial, trialDay, evidence[], confessed,
##     stolenOnCrook, crimeKind}} (HTML ensureRec55)
##   - one-roll-ever criminal trait scan: criminal when shady > 0.86,
##     klepto > 0.9 or desperate > 0.93 (HTML scanTraits); the roll is
##     deterministic per unit id, like SimPersonality traits
##   - daily crime roll per town: chance = min(0.85,
##     crime_pressure_mult() * criminals * 0.16), at most one crime per town
##     per day (HTML crimeDayTick)
##   - crime causes are needs-gated (HTML dominantNeed57 / planCrime57):
##     hunger -> theft, poverty (coins < 15) -> pickpocket, anger (mood < 30)
##     -> vandalism, exhaustion (energy < 20) -> theft. A criminal with no
##     pressing need commits no crime that day
##   - daily crime kinds from the HTML crimeDayTick list
##     (pickpocket/burglary/vandalism/mugging); sentences + fines from the
##     exact HTML CRIME55 table
##   - guard response: a guard in the crook's town confronts; the suspect
##     confesses, flees (stays wanted — the watch re-dispatches), bluffs or
##     denies (HTML suspectRespond55) -> arrest -> jailed awaiting trial
##     -> verdict by evidence score (HTML endTrial55)
##   - mayor crimewave petition at >= 2 crimes in a day: raise militia /
##     fund crackdown (120g, 3 days, crime pressure x0.35) / ignore
##     (HTML maybeCrimePetition + crimePressure crackdown term)
##   - unhappy towns breed criminals: approval < 25 -> x1.6, < 40 -> x1.3
##     (HTML govUnrestCrimeMult, applied inside crime_pressure_mult)
##
## Daily granularity: the HTML ALSO runs a real-time stalk/flee/chase/trial
## movement pipeline (crimeLifeTick55, guardTick55, trialTick55, panic58).
## That is worker-AI/visual territory — here outcomes resolve at the daily
## tick and all state is exposed for the visual layer to animate later.
##
## State is a plain Dictionary (save-ready). Pure logic — no rendering,
## no input, no audio, no network.

## HTML CRIME55 — exact sentences (days), fines (gold), icons.
const CRIME_TABLE := {
	"pickpocket": {"label": "pickpocketing", "minDays": 1, "maxDays": 2,
		"fine": 25, "icon": "👛"},
	"theft": {"label": "theft", "minDays": 2, "maxDays": 3,
		"fine": 40, "icon": "🥷"},
	"assault": {"label": "assault", "minDays": 3, "maxDays": 4,
		"fine": 60, "icon": "🤜"},
	"vandalism": {"label": "vandalism", "minDays": 2, "maxDays": 3,
		"fine": 50, "icon": "🔨"},
	"murder": {"label": "murder", "minDays": 6, "maxDays": 7,
		"fine": 200, "icon": "🔪"},
	"burglary": {"label": "burglary", "minDays": 3, "maxDays": 5,
		"fine": 80, "icon": "🏚️"},
}
## HTML crimeDayTick's daily kind draw. 'mugging' is not in CRIME55: it falls
## back to theft's sentence and a 30g fine (HTML `(CRIME55[kind]||{}).fine || 30`).
const DAILY_KINDS: Array[String] = ["pickpocket", "burglary", "vandalism",
	"mugging", "pickpocket"]
const MUGGING_FINE := 30

## Crackdown (HTML maybeCrimePetition "Fund Crackdown"): 120g, 3 days,
## crime pressure x0.35 while active.
const CRACKDOWN_COST := 120.0
const CRACKDOWN_DAYS := 3

## Crimewave petition threshold (HTML maybeCrimePetition).
const CRIMEWAVE_THRESHOLD := 2


var state: Dictionary
var _gs: GameState
var court = null  # SimRoyalCourt (duck-typed, set by owner)
var life = null  # SimCrimeLife — real-time behavior layer (Jeremy 2026-10-04)


func _init(game_state: GameState, royal_court = null) -> void:
	_gs = game_state
	court = royal_court
	state = {
		"byUid": {}, "townCd": {}, "crackdownUntil": 0,
		"crimesToday": 0, "day": 1,
	}
	life = SimCrimeLife.new(game_state, self)
	_gs.bus.day_changed.connect(_on_day)


func _on_day(_day: int, _is_night: bool) -> void:
	daily_tick()


## One in-game day of crime (HTML crimeDayTick body + scanTraits).
func daily_tick() -> void:
	var pf: String = _gs.player_faction
	if pf == "":
		return
	state["day"] = _gs.day_number
	state["crimesToday"] = 0
	_scan_traits(pf)
	_release_served()
	_resolve_trials()
	_crime_rolls(pf)
	_maybe_crime_petition(pf)


## --- records ------------------------------------------------------------------

## Lazily creates the per-unit crime record (HTML ensureRec55).
func ensure_rec(unit: Dictionary) -> Dictionary:
	var key: String = str(int(unit.get("id", 0)))
	var by: Dictionary = state["byUid"]
	if not by.has(key):
		by[key] = {
			"shady": 0.0, "desperate": 0.0, "klepto": 0.0,
			"criminal": false, "jailedUntil": 0.0,
			"c55": {"crimes": [], "wanted": false, "awaitingTrial": false,
				"trialDay": 0, "evidence": [], "confessed": false,
				"stolenOnCrook": false, "crimeKind": ""},
		}
	return by[key]


## Read-only record lookup ({} when the unit was never scanned).
func rec_for(unit_id: int) -> Dictionary:
	return (state["byUid"] as Dictionary).get(str(unit_id), {})


## Serving time (HTML isJailed: jailedUntil day not yet reached).
func is_jailed(unit_id: int) -> bool:
	var rec: Dictionary = rec_for(unit_id)
	return float(rec.get("jailedUntil", 0.0)) > float(state["day"])


## Crackdown active while the current day is within the window
## (HTML crimePressure: `crimeDay() > crackdownUntil ? 1 : x0.35`).
func crackdown_active() -> bool:
	return int(state["day"]) <= int(state["crackdownUntil"])


func start_crackdown(days: int = CRACKDOWN_DAYS) -> void:
	state["crackdownUntil"] = int(state["day"]) + maxi(1, days)


## --- trait scan ---------------------------------------------------------------

## One-roll-ever criminal assignment (HTML scanTraits). Deterministic per
## unit id so tests and saves behave — same seed scheme as SimPersonality.
func _scan_traits(pf: String) -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != pf:
			continue
		if bool(u.get("crime_scanned", false)):
			continue
		u["crime_scanned"] = true
		var rng := RandomNumberGenerator.new()
		rng.seed = int(u.get("id", 0)) * 7919 + 13
		var rec: Dictionary = ensure_rec(u)
		rec["shady"] = rng.randf()
		rec["desperate"] = rng.randf()
		rec["klepto"] = rng.randf()
		rec["criminal"] = float(rec["shady"]) > 0.86 \
			or float(rec["klepto"]) > 0.9 \
			or float(rec["desperate"]) > 0.93


## --- needs-gated motivation -----------------------------------------------------

## Unit coin purse; HTML units carry `u.coins` (default 0).
func _coins(u: Dictionary) -> float:
	return float(u.get("coins", 0.0))


func _add_coins(u: Dictionary, d: float) -> void:
	u["coins"] = maxf(0.0, _coins(u) + d)


## What pressing need would drive this unit to crime, if any
## (HTML dominantNeed57 — exact thresholds and scores).
func _motivation(u: Dictionary) -> String:
	var urges: Dictionary = u.get("urges", {})
	var hunger: float = float(urges.get("hunger", 60.0))
	var mood: float = float(urges.get("mood", 60.0))
	var energy: float = float(urges.get("energy", 60.0))
	var coins: float = _coins(u)
	var cands: Array = []
	if hunger < 57.0:
		cands.append({"crime": "theft", "score": 60.0 - hunger})
	if coins < 15.0:
		cands.append({"crime": "pickpocket",
			"score": 18.0 - minf(18.0, coins)})
	if mood < 31.0:
		cands.append({"crime": "vandalism", "score": 34.0 - mood})
	if energy < 21.0:
		cands.append({"crime": "theft", "score": 24.0 - energy})
	if cands.is_empty():
		return ""
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))
	return String(cands[0]["crime"])

## --- jail & trials --------------------------------------------------------------

## Release everyone whose sentence is served (HTML isJailed gate).
func _release_served() -> void:
	var day: float = float(state["day"])
	for key: Variant in (state["byUid"] as Dictionary).keys():
		var rec: Dictionary = (state["byUid"] as Dictionary)[key]
		if float(rec.get("jailedUntil", 0.0)) > 0.0 \
				and day >= float(rec.get("jailedUntil", 0.0)):
			rec["jailedUntil"] = 0.0


## Run every due trial (HTML endTrial55, daily granularity).
## Skips trials running live in the courtroom (SimCrimeLife) — those
## verdict through resolve_verdict() when the scene plays out.
func _resolve_trials() -> void:
	for key: Variant in (state["byUid"] as Dictionary).keys():
		var rec: Dictionary = (state["byUid"] as Dictionary)[key]
		var c55: Dictionary = rec.get("c55", {})
		if bool(c55.get("awaitingTrial", false)) \
				and int(state["day"]) >= int(c55.get("trialDay", 0)) \
				and not bool(c55.get("trial_live", false)):
			_verdict(int(key), rec)


## Verdict by evidence score (HTML trialEvidenceScore55 + endTrial55).
## score = witness evidence x2 + confession x4 + stolen goods on crook x3
## +/- noise; guilty at >= 5. Sentence from CRIME55, hard-capped at 7 days;
## a confession shaves one day (min 1). Acquittal releases.
func _verdict(unit_id: int, rec: Dictionary) -> void:
	var c55: Dictionary = rec["c55"]
	c55["awaitingTrial"] = false
	var unit: Dictionary = _gs.get_unit(unit_id)
	if unit.is_empty() or not unit.get("alive", false):
		rec["jailedUntil"] = 0.0
		c55["wanted"] = false
		return
	var wit_n: int = 0
	for e: Variant in (c55["evidence"] as Array):
		var t: String = String((e as Dictionary).get("type", ""))
		if t == "victim" or t == "seen" or t == "witness":
			wit_n += 1
	var score: float = float(wit_n) * 2.0
	if bool(c55.get("confessed", false)):
		score += 4.0
	if bool(c55.get("stolenOnCrook", false)):
		score += 3.0
	score += randf_range(-1.0, 1.0)
	var kind: String = String(c55.get("crimeKind", "theft"))
	var cdef: Dictionary = CRIME_TABLE.get(kind, CRIME_TABLE["theft"])
	var cname: String = SimPersonality.display_name(unit)
	if score >= 5.0:
		var days: int = mini(7,
			randi_range(int(cdef["minDays"]), int(cdef["maxDays"])))
		if bool(c55.get("confessed", false)):
			days = maxi(1, days - 1)  # honesty discount (HTML)
		var fine: int = MUGGING_FINE if kind == "mugging" else int(cdef["fine"])
		rec["jailedUntil"] = float(state["day"]) + float(days)
		_add_coins(unit, -float(fine))
		_story("GUILTY VERDICT",
			"%s was found GUILTY of %s — sentenced to %d days and fined %d gold."
			% [cname, String(cdef["label"]), days, fine], "⚖️")
	else:
		rec["jailedUntil"] = 0.0
		c55["wanted"] = false
		_story("NOT GUILTY",
			"%s was acquitted of %s. The evidence just wasn't there."
			% [cname, String(cdef["label"])], "⚖️")
	c55["confessed"] = false
	c55["stolenOnCrook"] = false


## --- daily crime rolls ------------------------------------------------------------

## One roll per player town (HTML crimeDayTick; per-town cooldown is the
## natural generalization of the HTML's single-hall townCd).
func _crime_rolls(pf: String) -> void:
	var mult: float = _crime_pressure()
	for tid: Variant in _gs.towns:
		var town: Dictionary = _gs.towns[tid]
		if String(town.get("faction", "")) != pf:
			continue
		var tkey: String = "t" + str(int(town.get("id", 0)))
		if int(state["day"]) < int((state["townCd"] as Dictionary).get(tkey, 0)):
			continue
		var criminals: Array = []
		for u: Dictionary in _gs.units:
			if not u.get("alive", false):
				continue
			if String(u.get("faction", "")) != pf:
				continue
			if int(u.get("town_id", -1)) != int(town.get("id", 0)):
				continue
			# Already mid-crime in the real-time layer — don't double-book.
			if String(u.get("crime_phase", "")) != "":
				continue
			var rec: Dictionary = rec_for(int(u.get("id", 0)))
			if rec.is_empty() or not bool(rec.get("criminal", false)):
				continue
			if is_jailed(int(u.get("id", 0))):
				continue
			if _motivation(u) == "":
				continue  # no pressing need, no crime (HTML planCrime57 gate)
			criminals.append(u)
		if criminals.is_empty():
			continue
		var pressure: float = mult * float(criminals.size()) * 0.16
		if randf() > minf(0.85, pressure):
			continue
		var crook: Dictionary = criminals[randi() % criminals.size()]
		var kind: String = DAILY_KINDS[randi() % DAILY_KINDS.size()]
		(state["townCd"] as Dictionary)[tkey] = int(state["day"]) + 1
		state["crimesToday"] = int(state["crimesToday"]) + 1
		_commit(kind, crook, town)


## Policy multiplier for this tick (HTML crimePressure body).
func _crime_pressure() -> float:
	if court == null:
		return 1.0
	var pol = court.policies
	if pol == null or not pol.has_method("crime_pressure_mult"):
		return 1.0
	return float(pol.crime_pressure_mult())


## --- committing crimes --------------------------------------------------------------

## Victim pick: random same-faction, same-town, non-crook, non-jailed,
## non-guard adult (HTML pickVictim55 prefers strangers within 700px; Godot
## has no bond scores, so the pick is uniform within the town).
func _pick_victim(crook: Dictionary, town: Dictionary) -> Dictionary:
	var cands: Array = []
	var cid: int = int(crook.get("id", 0))
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if int(u.get("id", 0)) == cid:
			continue
		if String(u.get("faction", "")) != String(crook.get("faction", "")):
			continue
		if int(u.get("town_id", -1)) != int(town.get("id", 0)):
			continue
		if is_jailed(int(u.get("id", 0))):
			continue
		if bool((u.get("mind", {}) as Dictionary).get("is_guard", false)):
			continue
		cands.append(u)
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


## Alive same-town residents for burglary (excludes the crook and jailbirds).
func _town_residents(town: Dictionary, crook: Dictionary) -> Array:
	var out: Array = []
	var cid: int = int(crook.get("id", 0))
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if int(u.get("id", 0)) == cid:
			continue
		if String(u.get("faction", "")) != String(crook.get("faction", "")):
			continue
		if int(u.get("town_id", -1)) != int(town.get("id", 0)):
			continue
		if is_jailed(int(u.get("id", 0))):
			continue
		out.append(u)
	return out


## Random non-hall player building to vandalize.
func _random_building(pf: String) -> Dictionary:
	var cands: Array = []
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) != pf:
			continue
		var t: String = String(b.get("type", ""))
		if t == "hall" or t == "townhall":
			continue
		cands.append(b)
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


func _add_evidence(rec: Dictionary, ev: Dictionary) -> void:
	((rec["c55"] as Dictionary)["evidence"] as Array).append(ev)


## Applies one crime's effects, records it, posts the story, and lets the
## watch respond (HTML commitCrime + commitCrime55 merged at daily scale).
func _commit(kind: String, crook: Dictionary, town: Dictionary) -> void:
	var rec: Dictionary = ensure_rec(crook)
	var pf: String = String(crook.get("faction", ""))
	var tname: String = String(town.get("name", "town"))
	var cname: String = SimPersonality.display_name(crook)
	var head: String = ""
	var body: String = ""
	var icon: String = "🔪"
	var committed: bool = true
	# Jeremy 2026-10-08 (hearsay flesh-out): the grapevine names names —
	# victim/loot ride the bus so hearsay seeds a crime rumor with real
	# parties instead of a party-less blotter line.
	var victim_uid := 0
	var loot_amt := 0
	match kind:
		"pickpocket":
			var victim: Dictionary = _pick_victim(crook, town)
			var amt: int = 0
			if not victim.is_empty():
				victim_uid = int(victim.get("id", 0))
				amt = mini(int(_coins(victim)), randi_range(10, 40))
				if amt > 0:
					_add_coins(victim, -float(amt))
					_add_coins(crook, float(amt))
					_add_evidence(rec, {"type": "victim",
						"uid": int(victim.get("id", 0)),
						"day": int(state["day"])})
			head = "PICKPOCKET STRIKES " + tname.to_upper() + "!"
			if amt > 0:
				body = "%s lifted %d gold from the market crowd and vanished into the alleys." % [cname, amt]
			else:
				body = "%s picked the wrong pocket — not a single coin in it — and vanished into the alleys anyway." % cname
			icon = "👛"
			loot_amt = amt
			_add_happiness(-1.0)
		"burglary":
			var loot: int = 0
			var residents: Array = _town_residents(town, crook)
			var n: int = mini(3, residents.size())
			for i: int in n:
				var rv: Dictionary = residents[randi() % residents.size()]
				if victim_uid == 0:
					victim_uid = int(rv.get("id", 0))
				var take: int = mini(int(_coins(rv)), randi_range(15, 45))
				if take > 0:
					_add_coins(rv, -float(take))
					loot += take
			if loot <= 0:
				loot = randi_range(5, 20)  # petty valuables fenced anyway (HTML)
			loot_amt = loot
			_add_coins(crook, float(loot))
			(rec["c55"] as Dictionary)["stolenOnCrook"] = true
			_add_evidence(rec, {"type": "burglary", "day": int(state["day"])})
			head = "BURGLAR STRIKES " + tname.to_upper() + "!"
			body = "%s pried open a home under cover of dark and made off with %d gold." % [cname, loot]
			icon = "🏚️"
			_add_happiness(-2.0)
		"vandalism":
			var b: Dictionary = _random_building(pf)
			if b.is_empty():
				committed = false  # HTML: nothing to smash -> no crime
			else:
				b["hp"] = maxf(1.0,
					float(b.get("hp", 100.0)) - float(randi_range(40, 100)))
				var bt: String = String(b.get("type", "building")).replace("_", " ")
				head = "VANDALS SMASH " + bt.to_upper() + "!"
				body = "%s took a hammer to the %s under cover of dark. Repairs will be needed." % [cname, bt]
				icon = "🔨"
				_add_happiness(-1.0)
		_:  # "mugging"
			var v2: Dictionary = _pick_victim(crook, town)
			if not v2.is_empty():
				victim_uid = int(v2.get("id", 0))
				_add_evidence(rec, {"type": "victim",
					"uid": int(v2.get("id", 0)), "day": int(state["day"])})
			head = "MUGGING ON " + tname.to_upper() + " STREETS!"
			body = "%s set upon a citizen near the square and robbed them." % cname
			icon = "🌃"
			_add_happiness(-3.0)
	if not committed:
		return
	(((rec["c55"] as Dictionary)["crimes"]) as Array).append(
		{"kind": kind, "day": int(state["day"])})
	if (((rec["c55"] as Dictionary)["crimes"]) as Array).size() > 8:
		(((rec["c55"] as Dictionary)["crimes"]) as Array).pop_front()
	# Jeremy 2026-10-08 (hearsay flesh-out): the grapevine names names.
	# Emitted BEFORE the Gazette story publishes so hearsay seeds the
	# rich rumor first and dedups the party-less story seed.
	_gs.bus.crime_committed.emit(kind, int(crook.get("id", 0)),
		victim_uid, tname, loot_amt, head)
	_story(head, body, icon)
	_guard_response(crook, town, rec)


## --- guard response -------------------------------------------------------------------

## Empty-watch feedback (no silent failures): a crime that goes unanswered
## because no guard walks the streets publishes one throttled Gazette story
## naming the fix (Policies > Town Watch). Max 1 per 3 days.
func _no_guard_story() -> void:
	var day: int = int(state["day"])
	if day - int(state.get("lastNoGuardDay", -99)) < 3:
		return
	state["lastNoGuardDay"] = day
	_story("THE WATCH IS EMPTY",
		"A crime went unanswered — no guard walks our streets. Open the Policies app and raise a Town Watch before the alleys grow bolder.",
		"🚔")


## The watch responds when a guard serves the crook's town (HTML tryGuardArrest
## + suspectRespond55, resolved at daily granularity). No omniscient chase:
## with no guards on the streets, the crime goes unanswered.
func _guard_response(crook: Dictionary, town: Dictionary, rec: Dictionary) -> void:
	if court == null:
		return
	var pol = court.policies
	if pol == null or not pol.has_method("guard_units"):
		return
	var guards: Array = []
	for g: Dictionary in pol.guard_units():
		if int(g.get("town_id", -1)) == int(town.get("id", 0)):
			guards.append(g)
	if guards.is_empty():
		_no_guard_story()
		return
	var guard: Dictionary = guards[randi() % guards.size()]
	var c55: Dictionary = rec["c55"]
	c55["wanted"] = true
	_add_evidence(rec, {"type": "seen", "uid": int(guard.get("id", 0)),
		"day": int(state["day"])})
	var ev_count: int = (c55["evidence"] as Array).size()
	var traits: Dictionary = (crook.get("mind", {}) as Dictionary).get("traits", {})
	# HTML suspectRespond55: personality + shadiness + evidence -> response.
	var confess_p: float = 0.12
	if float(traits.get("friendly", 0.5)) > 0.7:
		confess_p += 0.25  # Godot analog of HTML's 'gentle'
	if ev_count >= 3:
		confess_p += 0.25
	var flee_p: float = 0.15
	if float(traits.get("brave", 0.5)) < 0.3:
		flee_p += 0.2  # Godot analog of HTML's 'cowardly'
	if float(rec.get("shady", 0.0)) > 0.8:
		flee_p += 0.2
	flee_p -= float(ev_count) * 0.05
	var roll: float = randf()
	if roll < confess_p:
		c55["confessed"] = true
		_arrest(crook, rec, "confessed")
	elif roll < confess_p + flee_p:
		pass  # slips away but stays wanted — the watch re-dispatches (HTML C60)
	elif roll < confess_p + flee_p + 0.35:
		if ev_count >= 3 or randf() < 0.5:
			_arrest(crook, rec, "bluff-failed")
		else:
			_clear_suspicion(rec)
	else:
		if ev_count >= 2:
			_arrest(crook, rec, "denied-but-evidence")
		else:
			_clear_suspicion(rec)


func _clear_suspicion(rec: Dictionary) -> void:
	var c55: Dictionary = rec["c55"]
	c55["wanted"] = false
	(c55["evidence"] as Array).clear()


## Arrest -> escort -> jailed awaiting trial (HTML arrestSuspect55 +
## jailSuspect55; the walk to the cells is visual-layer territory).
func _arrest(crook: Dictionary, rec: Dictionary, how: String) -> void:
	var cname: String = SimPersonality.display_name(crook)
	var suffix: String = ""
	if how == "confessed":
		suffix = " after a full confession"
	elif how == "denied-but-evidence" or how == "bluff-failed":
		suffix = " without saying a word"
	_story("ARREST MADE", "%s was arrested%s." % [cname, suffix], "🚔")
	var c55: Dictionary = rec["c55"]
	c55["wanted"] = false
	c55["awaitingTrial"] = true
	c55["trialDay"] = int(state["day"]) + 1
	var crimes: Array = c55["crimes"]
	var last: Dictionary = crimes.back() if not crimes.is_empty() else {"kind": "theft"}
	c55["crimeKind"] = String(last.get("kind", "theft"))
	rec["jailedUntil"] = float(state["day"]) + 1.2  # held until trial (HTML)
	var cdef: Dictionary = CRIME_TABLE.get(String(c55["crimeKind"]), CRIME_TABLE["theft"])
	_story("JAILED AWAITING TRIAL",
		"%s sits in the cells awaiting trial for %s."
		% [cname, String(cdef["label"])], "⛓️")


## --- crimewave petition -----------------------------------------------------------------

## >= 2 crimes in a day brings the mayor to the throne room
## (HTML maybeCrimePetition) — or a single unanswered crime when the watch
## is empty: early kingdoms have one town, and one crime/day is all the
## rolls allow, so the threshold was unreachable before the second town.
func _maybe_crime_petition(pf: String) -> void:
	var today: int = int(state["crimesToday"])
	if today < CRIMEWAVE_THRESHOLD and not _begging_for_watch(today):
		return
	if court == null:
		return
	for p: Dictionary in court.open_petitions():
		if String(p.get("tpl", "")) == "mayor_crimewave":
			return  # already nagging about this
	var from: Dictionary = _mayor(pf)
	if from.is_empty():
		from = _random_citizen(pf)
	if from.is_empty():
		return
	var text: String
	if today >= CRIMEWAVE_THRESHOLD:
		text = "Sire, the streets grow lawless — %d crimes in a single day! " \
			% today \
			+ "The watch is a joke told in taverns. Will you give me coin for a proper guard?"
	else:
		text = "Sire, a crime went unanswered in our streets — and we have no watch at all! Will you give me coin for a proper guard?"
	var opts: Array[String] = ["Raise Militia", "Fund Crackdown (120g)", "Ignore"]
	var p: Dictionary = court.petition(from, "mayor_crimewave", text, opts)
	p["tpl"] = "mayor_crimewave"


## One unanswered crime with an empty watch still earns the mayor's plea.
func _begging_for_watch(today: int) -> bool:
	if today < 1:
		return false
	if court == null:
		return false
	var pol = court.policies
	if pol == null or not pol.has_method("guard_units"):
		return false
	return (pol.guard_units() as Array).is_empty()


func _mayor(pf: String) -> Dictionary:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != pf:
			continue
		if String((u.get("mind", {}) as Dictionary).get("gov_role", "")) == "mayor":
			return u
	return {}


func _random_citizen(pf: String) -> Dictionary:
	var cands: Array = []
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == pf:
			cands.append(u)
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


## --- helpers ------------------------------------------------------------------------------

func _story(headline: String, body: String, icon: String = "") -> void:
	if court == null or not court.has_method("publish_story"):
		return
	var h: String = (icon + " " + headline).strip_edges() if icon != "" else headline
	court.publish_story(h, body, "crime")


func _add_happiness(d: float) -> void:
	if court == null:
		return
	var pol = court.policies
	if pol != null and pol.has_method("add_happiness"):
		pol.add_happiness(d)


## --- real-time layer API ----------------------------------------------------------
## Public wrappers for SimCrimeLife (the visible behavior layer). The math
## stays private; the behavior layer drives it through these.

## Needs-gated crime motivation for a unit (HTML dominantNeed57).
func motivation_for(unit: Dictionary) -> String:
	return _motivation(unit)


func add_evidence(rec: Dictionary, ev: Dictionary) -> void:
	_add_evidence(rec, ev)


func publish(headline: String, body: String, icon: String = "") -> void:
	_story(headline, body, icon)


## Verdict entry for a live courtroom trial: same evidence scoring and
## sentencing as the daily abstract path (HTML endTrial55).
func resolve_verdict(unit_id: int) -> void:
	var rec: Dictionary = rec_for(unit_id)
	if rec.is_empty():
		return
	_verdict(unit_id, rec)


## Crime table entry for a kind (label/sentence/fine) — for the live trial.
func crime_def(kind: String) -> Dictionary:
	return CRIME_TABLE.get(kind, CRIME_TABLE["theft"])


## Small status snapshot for the HUD/debug layer.
func crime_report() -> Dictionary:
	var criminals: int = 0
	var jailed: int = 0
	var wanted: int = 0
	for key: Variant in (state["byUid"] as Dictionary).keys():
		var rec: Dictionary = (state["byUid"] as Dictionary)[key]
		if bool(rec.get("criminal", false)):
			criminals += 1
		if is_jailed(int(key)):
			jailed += 1
		if bool((rec.get("c55", {}) as Dictionary).get("wanted", false)):
			wanted += 1
	return {"today": int(state["crimesToday"]), "criminals": criminals,
		"jailed": jailed, "wanted": wanted,
		"crackdown": crackdown_active()}


## --- save -----------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	var fresh: Dictionary = {
		"byUid": {}, "townCd": {}, "crackdownUntil": 0,
		"crimesToday": 0, "day": 1,
	}
	for k: String in fresh.keys():
		if data.has(k):
			fresh[k] = data[k]
	state = fresh
