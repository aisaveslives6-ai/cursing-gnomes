extends SceneTree
## Cursing Gnomes — crime system tests.
##
## Covers: SimCrime record scan (one-roll-ever criminal traits), needs-gated
## motivation (HTML dominantNeed57), crime pressure multiplier terms
## (curfew -40%, crackdown x0.35, unrest x1.6/x1.3), crime effects
## (pickpocket coin transfer, vandalism building damage, happiness costs),
## guard response (wanted/arrest/jail), trials (guilty sentence + fine,
## acquittal), the mayor crimewave petition (militia / crackdown / ignore),
## and save round-trip.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_crime.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes crime tests ===")
	_test_scan()
	_test_motivation()
	_test_pressure_terms()
	_test_curfew_crime_effect()
	_test_pickpocket()
	_test_vandalism()
	_test_guard_response()
	_test_jail_and_trial()
	_test_acquit()
	_test_crimewave_petition()
	_test_save_roundtrip()
	_test_report()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## --- harness ------------------------------------------------------------------

## Fresh game + social systems. Towns use int ids (policies API is int-keyed).
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.towns[1] = {"id": 1, "name": "Town0", "faction": "humans",
		"pos": Vector2.ZERO, "owner": "humans"}
	gs.towns[2] = {"id": 2, "name": "Gnomestad", "faction": "gnomes",
		"pos": Vector2(300, 0), "owner": "gnomes"}
	for r: String in ["gold", "food", "wood"]:
		gs.resources.add_resource("humans", r, 1000.0, true)
	var mind := SimMind.new(gs)
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	return {"gs": gs, "mind": mind, "phone": phone, "court": court}


func _spawn(w: Dictionary, faction: String, job: String,
		town_id: int = 1) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, job, town_id,
		Vector2(100, 100))
	mind.ensure(u)
	return u


func _spawn_many(w: Dictionary, n: int) -> Array:
	# Spread across fresh human towns so the 16/town cap never bites.
	var gs: GameState = w["gs"]
	var out: Array = []
	var tid: int = 10
	var in_town: int = 0
	for i: int in n:
		if in_town == 0:
			gs.towns[tid] = {"id": tid, "name": "Town%d" % tid,
				"faction": "humans", "pos": Vector2(100 * tid, 0),
				"owner": "humans"}
		out.append(_spawn(w, "humans", "worker", tid))
		in_town += 1
		if in_town >= 16:
			in_town = 0
			tid += 1
	return out


func _stories(court: SimRoyalCourt) -> Array:
	return court.news_feed()


func _has_headline(court: SimRoyalCourt, text: String) -> bool:
	for s: Dictionary in _stories(court):
		if String(s.get("headline", "")).find(text) >= 0:
			return true
	return false


func _set_needs(u: Dictionary, hunger: float, mood: float, energy: float) -> void:
	var urges: Dictionary = u.get("urges", {})
	urges["hunger"] = hunger
	urges["mood"] = mood
	urges["energy"] = energy


## --- tests --------------------------------------------------------------------

func _test_scan() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = court.crime
	_check("court owns crime", crime != null)
	var units: Array = _spawn_many(w, 40)
	_check("spawned 40", units.size() == 40)
	crime.daily_tick()
	var by: Dictionary = crime.state["byUid"]
	_check("records for all scanned units", by.size() == 40)
	var criminals: int = 0
	for u: Dictionary in units:
		_check("scan flag set", bool(u.get("crime_scanned", false)))
		var rec: Dictionary = crime.rec_for(int(u.get("id", 0)))
		_check("record fields", rec.has("shady") and rec.has("criminal"))
		if bool(rec.get("criminal", false)):
			criminals += 1
	_check("some criminals exist (deterministic roll)", criminals >= 1)
	# Second tick: no duplicate records, flags stick.
	crime.daily_tick()
	_check("no duplicate records", (crime.state["byUid"] as Dictionary).size() == 40)


func _test_motivation() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = court.crime
	var u := _spawn(w, "humans", "worker")
	u["coins"] = 100.0
	_set_needs(u, 90.0, 90.0, 90.0)
	_check("no need -> no motivation", crime._motivation(u) == "")
	_set_needs(u, 10.0, 90.0, 90.0)
	_check("hunger -> theft", crime._motivation(u) == "theft")
	_set_needs(u, 90.0, 90.0, 90.0)
	u["coins"] = 0.0
	_check("poverty -> pickpocket", crime._motivation(u) == "pickpocket")
	u["coins"] = 100.0
	_set_needs(u, 90.0, 10.0, 90.0)
	_check("anger -> vandalism", crime._motivation(u) == "vandalism")
	_set_needs(u, 90.0, 90.0, 5.0)
	_check("exhaustion -> theft", crime._motivation(u) == "theft")


func _test_pressure_terms() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	var crime: SimCrime = court.crime
	_check("baseline pressure 1.0", pol.crime_pressure_mult() == 1.0)
	pol.set_approval(1, 20.0)
	_check("approval < 25 -> x1.6", pol.crime_pressure_mult() == 1.6)
	pol.set_approval(1, 30.0)
	_check("approval < 40 -> x1.3", pol.crime_pressure_mult() == 1.3)
	pol.set_approval(1, 60.0)
	crime.start_crackdown(3)
	_check("crackdown active", crime.crackdown_active())
	_check("crackdown -> x0.35",
		absf(pol.crime_pressure_mult() - 0.35) < 0.001)
	# Crackdown expires after its window.
	crime.state["day"] = int(crime.state["crackdownUntil"]) + 1
	_check("crackdown expires", not crime.crackdown_active())
	_check("pressure back to 1.0", pol.crime_pressure_mult() == 1.0)


func _test_curfew_crime_effect() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	var before: float = pol.crime_pressure_mult()
	_check("impose curfew", pol.toggle_curfew())
	var after: float = pol.crime_pressure_mult()
	_check("curfew cuts crime pressure 40%",
		absf(after - before * 0.6) < 0.001)
	_check("lift curfew", pol.toggle_curfew())
	_check("pressure restored",
		absf(pol.crime_pressure_mult() - before) < 0.001)


func _test_pickpocket() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = court.crime
	var pol = court.policies
	var crook := _spawn(w, "humans", "worker")
	var victim := _spawn(w, "humans", "worker")
	victim["coins"] = 50.0
	crook["coins"] = 0.0
	var hap_before: float = float(pol.state["happiness"])
	crime._commit("pickpocket", crook, gs.towns[1])
	var stolen: float = 50.0 - float(victim.get("coins", 0.0))
	_check("victim lost coins", stolen >= 10.0 and stolen <= 40.0)
	_check("crook gained the same coins",
		absf(float(crook.get("coins", 0.0)) - stolen) < 0.001)
	_check("pickpocket story posted", _has_headline(court, "PICKPOCKET STRIKES"))
	_check("pickpocket costs 1 happiness",
		absf(float(pol.state["happiness"]) - (hap_before - 1.0)) < 0.001)
	var rec: Dictionary = crime.rec_for(int(crook.get("id", 0)))
	_check("victim evidence logged",
		((rec.get("c55", {}) as Dictionary).get("evidence", []) as Array).size() == 1)


func _test_vandalism() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = court.crime
	var crook := _spawn(w, "humans", "worker")
	gs.buildings.append({"id": 1, "type": "house", "faction": "humans",
		"alive": true, "hp": 200.0, "max_hp": 200.0})
	crime._commit("vandalism", crook, gs.towns[1])
	var b: Dictionary = gs.buildings[0]
	var dmg: float = 200.0 - float(b.get("hp", 200.0))
	_check("vandalism damages building 40-100", dmg >= 40.0 and dmg <= 100.0)
	_check("vandalism story posted", _has_headline(court, "VANDALS SMASH"))


func _test_guard_response() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = court.crime
	var crook := _spawn(w, "humans", "worker")
	var guard := _spawn(w, "humans", "soldier")
	(guard.get("mind", {}) as Dictionary)["is_guard"] = true
	var rec: Dictionary = crime.ensure_rec(crook)
	rec["criminal"] = true
	# Two pieces of seen evidence: deny and bluff both lead to arrest;
	# confess leads to arrest; flee leaves the crook wanted. Either way the
	# watch answered.
	((rec.get("c55", {}) as Dictionary).get("evidence", []) as Array).append(
		{"type": "seen", "uid": 9001, "day": 1})
	((rec.get("c55", {}) as Dictionary).get("evidence", []) as Array).append(
		{"type": "seen", "uid": 9002, "day": 1})
	crime._guard_response(crook, gs.towns[1], rec)
	var jailed: bool = crime.is_jailed(int(crook.get("id", 0)))
	var wanted: bool = bool((rec.get("c55", {}) as Dictionary).get("wanted", false))
	_check("guard answered: arrested or still wanted", jailed or wanted)
	# Without guards the crime goes unanswered: wanted stays false.
	var w2 := _new_world()
	var court2: SimRoyalCourt = w2["court"]
	var crime2: SimCrime = court2.crime
	var crook2 := _spawn(w2, "humans", "worker")
	var rec2: Dictionary = crime2.ensure_rec(crook2)
	rec2["criminal"] = true
	crime2._guard_response(crook2, (w2["gs"] as GameState).towns[1], rec2)
	_check("no guards, no wanted flag",
		not bool((rec2.get("c55", {}) as Dictionary).get("wanted", false)))


func _test_jail_and_trial() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = court.crime
	var crook := _spawn(w, "humans", "worker")
	crook["coins"] = 100.0
	var rec: Dictionary = crime.ensure_rec(crook)
	rec["criminal"] = true
	((rec.get("c55", {}) as Dictionary).get("crimes", []) as Array).append(
		{"kind": "theft", "day": 1})
	crime._arrest(crook, rec, "denied-but-evidence")
	_check("arrest holds until trial",
		absf(float(rec.get("jailedUntil", 0.0)) - 2.2) < 0.001)
	_check("awaiting trial flag",
		bool((rec.get("c55", {}) as Dictionary).get("awaitingTrial", false)))
	_check("arrest story posted", _has_headline(court, "ARREST MADE"))
	_check("jail story posted", _has_headline(court, "JAILED AWAITING TRIAL"))
	# Three witness statements: score >= 5 + noise -> guilty, always.
	((rec.get("c55", {}) as Dictionary).get("evidence", []) as Array).append(
		{"type": "witness", "uid": 1, "day": 1})
	((rec.get("c55", {}) as Dictionary).get("evidence", []) as Array).append(
		{"type": "witness", "uid": 2, "day": 1})
	((rec.get("c55", {}) as Dictionary).get("evidence", []) as Array).append(
		{"type": "witness", "uid": 3, "day": 1})
	crime.state["day"] = int((rec.get("c55", {}) as Dictionary).get("trialDay", 0))
	crime._resolve_trials()
	var until: float = float(rec.get("jailedUntil", 0.0))
	var day: float = float(crime.state["day"])
	_check("guilty: sentenced 2-3 days for theft",
		until >= day + 2.0 and until <= day + 3.0)
	_check("guilty: fined 40g for theft",
		absf(float(crook.get("coins", 0.0)) - 60.0) < 0.001)
	_check("guilty story posted", _has_headline(court, "GUILTY VERDICT"))


func _test_acquit() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = court.crime
	var crook := _spawn(w, "humans", "worker")
	var rec: Dictionary = crime.ensure_rec(crook)
	rec["criminal"] = true
	((rec.get("c55", {}) as Dictionary).get("crimes", []) as Array).append(
		{"kind": "pickpocket", "day": 1})
	crime._arrest(crook, rec, "denied-but-evidence")
	# No evidence, no confession: score in [-1, 1) -> acquittal, always.
	crime.state["day"] = int((rec.get("c55", {}) as Dictionary).get("trialDay", 0))
	crime._resolve_trials()
	_check("acquitted: released",
		float(rec.get("jailedUntil", 0.0)) == 0.0)
	_check("acquitted: not wanted",
		not bool((rec.get("c55", {}) as Dictionary).get("wanted", false)))
	_check("acquittal story posted", _has_headline(court, "NOT GUILTY"))


func _test_crimewave_petition() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = court.crime
	var pol = court.policies
	_spawn(w, "humans", "worker")
	_spawn(w, "humans", "worker")
	crime.state["crimesToday"] = 2
	crime._maybe_crime_petition("humans")
	var found: Dictionary = {}
	for p: Dictionary in court.open_petitions():
		if String(p.get("tpl", "")) == "mayor_crimewave":
			found = p
	_check("crimewave petition raised", not found.is_empty())
	_check("three options", (found.get("options", []) as Array).size() == 3)
	# Option 0: raise militia (monarchy policyCost 0.5 -> 50g fee).
	court.decide(int(found.get("id", 0)), 0)
	_check("militia raised", String(pol.state.get("guard", "")) == "militia")
	# Option 1: fund crackdown.
	crime.state["crimesToday"] = 2
	crime._maybe_crime_petition("humans")
	var p2: Dictionary = {}
	for p: Dictionary in court.open_petitions():
		if String(p.get("tpl", "")) == "mayor_crimewave" \
				and not bool(p.get("resolved", false)):
			p2 = p
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	court.decide(int(p2.get("id", 0)), 1)
	_check("crackdown costs 120g",
		absf(gs.resources.get_amount("humans", "gold") - (gold_before - 120.0)) < 0.01)
	_check("crackdown ordered", _has_headline(court, "CRACKDOWN ORDERED"))
	_check("crackdown live", crime.crackdown_active())
	# Option 2: ignore.
	crime.state["crimesToday"] = 2
	crime._maybe_crime_petition("humans")
	var p3: Dictionary = {}
	for p: Dictionary in court.open_petitions():
		if String(p.get("tpl", "")) == "mayor_crimewave" \
				and not bool(p.get("resolved", false)):
			p3 = p
	var hap_before: float = float(pol.state["happiness"])
	court.decide(int(p3.get("id", 0)), 2)
	_check("ignored: -4 happiness",
		absf(float(pol.state["happiness"]) - (hap_before - 4.0)) < 0.001)


func _test_save_roundtrip() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = court.crime
	var u := _spawn(w, "humans", "worker")
	crime.daily_tick()
	crime.start_crackdown(3)
	crime.state["crimesToday"] = 5
	var snap: Dictionary = crime.to_dict()
	var w2 := _new_world()
	var crime2: SimCrime = (w2["court"] as SimRoyalCourt).crime
	crime2.from_dict(snap)
	_check("byUid survives",
		(crime2.state["byUid"] as Dictionary).size() == (crime.state["byUid"] as Dictionary).size())
	_check("crackdownUntil survives",
		int(crime2.state["crackdownUntil"]) == int(crime.state["crackdownUntil"]))
	_check("crimesToday survives", int(crime2.state["crimesToday"]) == 5)
	var rec: Dictionary = crime2.rec_for(int(u.get("id", 0)))
	_check("record fields survive",
		rec.has("criminal") and (rec.get("c55", {}) as Dictionary).has("evidence"))


func _test_report() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var crime: SimCrime = court.crime
	_spawn_many(w, 16)
	crime.daily_tick()
	var rep: Dictionary = crime.crime_report()
	_check("report has keys",
		rep.has("today") and rep.has("criminals") and rep.has("jailed")
		and rep.has("wanted") and rep.has("crackdown"))
	_check("report counts sane", int(rep["criminals"]) >= 0
		and int(rep["today"]) >= 0)
