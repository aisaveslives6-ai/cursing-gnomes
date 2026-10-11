extends SceneTree
## Cursing Gnomes — real-time criminal justice tests (Jeremy 2026-10-04).
##
## Covers SimCrimeLife: criminal/violent traits, crime planning, tool theft
## (steal-don't-buy from the disliked), sneak mode, detection/witnesses,
## guard dispatch/hunt/arrest, violent resistance + lethal force, escort,
## jail cells + pretrial detention + release, live courtroom trials
## (cast, phases, verdict, sentencing), judge auto-staffing, jail building.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_crime_life.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes crime-life tests ===")
	_test_traits()
	_test_jail_building_type()
	_test_judge_staffing()
	_test_tool_theft_plan()
	_test_stalk_and_sneak()
	_test_commit_steal_coins()
	_test_detection_and_witness_report()
	_test_guard_dispatch_hunt_arrest()
	_test_violent_resist_lethal()
	_test_escort_to_jail()
	_test_jail_and_release()
	_test_trial_full_cast_and_verdict()
	_test_trial_acquittal()
	_test_daily_resolver_skips_live_trial()
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

func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.towns[1] = {"id": 1, "name": "Town0", "faction": "humans",
		"pos": Vector2.ZERO, "owner": "humans"}
	for r: String in ["gold", "food", "wood", "oil"]:
		gs.resources.add_resource("humans", r, 10000.0, true)
	var mind := SimMind.new(gs)
	var court := SimRoyalCourt.new(gs)
	var life: SimCrimeLife = court.crime.life
	# A jail + courthouse so the pipeline has somewhere to go.
	gs.add_building({"type": "jail", "faction": "humans", "town_id": 1,
		"position": Vector2(200, 0), "alive": true, "complete": true,
		"progress": 1.0, "hp": 700.0, "max_hp": 700.0})
	gs.add_building({"type": "courthouse", "faction": "humans", "town_id": 1,
		"position": Vector2(-200, 0), "alive": true, "complete": true,
		"progress": 1.0, "hp": 900.0, "max_hp": 900.0})
	return {"gs": gs, "mind": mind, "court": court, "life": life,
		"crime": court.crime}


func _spawn(w: Dictionary, job: String, pos: Vector2 = Vector2(100, 100)) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit("humans", job, 1, pos)
	mind.ensure(u)
	return u


## Force deterministic traits on a unit's mind.
func _set_traits(u: Dictionary, criminal: float, violent: float) -> void:
	var traits: Dictionary = (u["mind"] as Dictionary)["traits"]
	traits["criminal"] = criminal
	traits["violent"] = violent
	traits["brave"] = 0.5
	traits["diligent"] = 0.5


## --- tests --------------------------------------------------------------------

func _test_traits() -> void:
	var t1: Dictionary = SimPersonality.traits_for(42, "humans")
	_check("traits has criminal", t1.has("criminal"))
	_check("traits has violent", t1.has("violent"))
	# Deterministic.
	var t2: Dictionary = SimPersonality.traits_for(42, "humans")
	_check("traits deterministic", float(t1["criminal"]) == float(t2["criminal"]))
	# Original five untouched by the append (same seed, same first 5 rolls).
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 * 7919 + 13
	_check("brave unchanged", is_equal_approx(float(t1["brave"]), rng.randf()))
	_check("friendly unchanged", is_equal_approx(float(t1["friendly"]), rng.randf()))
	_check("is_criminal_minded high", SimPersonality.is_criminal_minded({"mind": {"traits": {"criminal": 0.9}}}))
	_check("is_criminal_minded low", not SimPersonality.is_criminal_minded({"mind": {"traits": {"criminal": 0.1}}}))
	_check("is_violent high", SimPersonality.is_violent({"mind": {"traits": {"violent": 0.9}}}))
	_check("is_violent low", not SimPersonality.is_violent({"mind": {"traits": {"violent": 0.1}}}))


func _test_jail_building_type() -> void:
	_check("jail is a building", SimBuildings.is_building("jail"))
	_check("jail player-buildable", SimBuildings.is_player_buildable("jail"))
	_check("jail name", SimBuildings.building_name("jail") == "Jail")


func _test_judge_staffing() -> void:
	_check("courthouse staffs judge", String(SimBuildings.SERVICE_BUILDINGS["courthouse"]) == "judge")
	_check("judge job exists", JobDefs.JOBS.has("judge"))
	_check("service_want judge", SimBuildings.service_want("judge") == 1)


func _test_tool_theft_plan() -> void:
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var crook: Dictionary = _spawn(w, "woodcutter", Vector2(0, 0))
	_set_traits(crook, 0.95, 0.1)
	crook["tools"] = []  # no axe — needs one, won't buy it
	var victim: Dictionary = _spawn(w, "miner", Vector2(500, 0))
	victim["tools"] = ["axe"]
	# Crook dislikes the victim (grudge) — the preferred mark.
	(w["mind"] as SimMind).memories.remember(crook, "hurt_by",
		int(victim.get("id", 0)), "Vic", "humans", 2.0)
	seed(1234)
	var planned: bool = life._plan_crime(crook, (w["crime"] as SimCrime).ensure_rec(crook))
	_check("tool theft planned", planned)
	_check("stalk phase", String(crook.get("crime_phase", "")) == "stalk")
	_check("sneaking on", bool(crook.get("sneaking", false)))
	_check("tool motive", String(crook.get("crime_tool", "")) == "axe")
	_check("targets the disliked mark", int(crook.get("crime_target", -1)) == int(victim.get("id", 0)))


func _test_stalk_and_sneak() -> void:
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_set_traits(crook, 0.95, 0.1)
	var victim: Dictionary = _spawn(w, "worker", Vector2(400, 0))
	crook["crime_phase"] = "stalk"
	crook["crime_kind"] = "pickpocket"
	crook["crime_tool"] = ""
	crook["crime_target"] = int(victim.get("id", 0))
	crook["crime_t"] = 0.0
	crook["sneaking"] = true
	crook["speed"] = 55.0
	var d0: float = (crook.get("position") as Vector2).distance_to(victim.get("position"))
	life._tick_stalk(crook, 1.0)
	var d1: float = (crook.get("position") as Vector2).distance_to(victim.get("position"))
	_check("stalk closes distance", d1 < d0)
	_check("stalk keeps sneaking", bool(crook.get("sneaking", false)))
	# Stalk timeout: lost nerve.
	crook["crime_t"] = 89.0
	life._tick_stalk(crook, 2.0)
	_check("stalk timeout clears", String(crook.get("crime_phase", "")) == "")
	_check("sneak off after timeout", not bool(crook.get("sneaking", false)))


func _test_commit_steal_coins() -> void:
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var crime: SimCrime = w["crime"]
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_set_traits(crook, 0.95, 0.1)
	crook["coins"] = 0.0
	var victim: Dictionary = _spawn(w, "worker", Vector2(10, 0))
	victim["coins"] = 100.0
	crook["crime_phase"] = "stalk"
	crook["crime_kind"] = "pickpocket"
	crook["crime_tool"] = ""
	crook["crime_target"] = int(victim.get("id", 0))
	crook["sneaking"] = true  # mid-stalk when the steal happens
	seed(7)
	life._commit_steal(crook, victim)
	_check("coins moved", float(victim.get("coins", 100.0)) < 100.0)
	_check("crook got coins", float(crook.get("coins", 0.0)) > 0.0)
	_check("flee phase after steal", String(crook.get("crime_phase", "")) == "flee")
	_check("still sneaking on getaway", bool(crook.get("sneaking", false)))
	var rec: Dictionary = crime.ensure_rec(crook)
	_check("crime recorded", ((rec["c55"] as Dictionary)["crimes"] as Array).size() == 1)


func _test_commit_steal_tool() -> void:
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var crook: Dictionary = _spawn(w, "woodcutter", Vector2(0, 0))
	_set_traits(crook, 0.95, 0.1)
	crook["tools"] = []
	var victim: Dictionary = _spawn(w, "miner", Vector2(10, 0))
	victim["tools"] = ["axe"]
	crook["crime_phase"] = "stalk"
	crook["crime_kind"] = "tool_theft"
	crook["crime_tool"] = "axe"
	crook["crime_target"] = int(victim.get("id", 0))
	seed(9)
	life._commit_steal(crook, victim)
	_check("tool stolen", "axe" in (crook.get("tools", []) as Array))
	_check("victim lost tool", not ("axe" in (victim.get("tools", []) as Array)))


func _test_detection_and_witness_report() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var life: SimCrimeLife = w["life"]
	var crime: SimCrime = w["crime"]
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_set_traits(crook, 0.95, 0.1)
	var victim: Dictionary = _spawn(w, "worker", Vector2(300, 0))
	crook["crime_phase"] = "stalk"
	crook["crime_kind"] = "pickpocket"
	crook["crime_target"] = int(victim.get("id", 0))
	crook["sneaking"] = true
	# A bystander right on top of the crook spots them.
	var bystander: Dictionary = _spawn(w, "worker", Vector2(5, 0))
	_set_traits(bystander, 0.1, 0.1)
	(bystander["mind"] as Dictionary)["traits"]["diligent"] = 1.0
	seed(42)
	var spotted := false
	for i: int in 60:
		life._detection_tick(crook, 1.0)
		if String(bystander.get("crime_phase", "")) == "witness":
			spotted = true
			break
	_check("bystander spots the sneak", spotted)
	# Witness runs to the guard and reports.
	var guard: Dictionary = _spawn(w, "guard", Vector2(60, 0))
	guard["position"] = Vector2(60, 0)
	bystander["position"] = Vector2(55, 0)
	bystander["speed"] = 200.0
	for i: int in 30:
		life._tick_witness(bystander, 0.5)
		if String(bystander.get("crime_phase", "")) == "":
			break
	var rec: Dictionary = crime.ensure_rec(crook)
	_check("witness reported: wanted", bool((rec["c55"] as Dictionary).get("wanted", false)))
	_check("witness evidence", ((rec["c55"] as Dictionary)["evidence"] as Array).size() >= 1)


func _test_guard_dispatch_hunt_arrest() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var life: SimCrimeLife = w["life"]
	var crime: SimCrime = w["crime"]
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_set_traits(crook, 0.2, 0.1)  # not violent — will submit
	(w["mind"] as SimMind).ensure(crook)
	(crook["mind"] as Dictionary)["traits"]["brave"] = 0.2
	var guard: Dictionary = _spawn(w, "guard", Vector2(30, 0))
	guard["speed"] = 70.0
	crook["speed"] = 55.0
	var rec: Dictionary = crime.ensure_rec(crook)
	(rec["c55"] as Dictionary)["wanted"] = true
	# Dispatch assigns the hunt.
	life._dispatch_guards()
	_check("guard hunting", String(guard.get("crime_phase", "")) == "guard_hunt")
	_check("suspect hunted", String(crook.get("crime_phase", "")) == "hunted")
	# Run the chase to contact.
	seed(5)
	var arrested := false
	for i: int in 200:
		life._tick_guard_hunt(guard, 0.25)
		life._tick_hunted(crook, 0.25)
		var ph: String = String(crook.get("crime_phase", ""))
		if ph == "escort" or ph == "resist" or ph == "jailed":
			arrested = true
			break
		if not crook.get("alive", false):
			break
	_check("chase ends in arrest or resist", arrested)
	_check("not wanted once in custody",
		not bool(((crime.ensure_rec(crook)["c55"]) as Dictionary).get("wanted", false)))


func _test_violent_resist_lethal() -> void:
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_set_traits(crook, 0.9, 0.95)  # violent — will fight
	crook["hp"] = 100.0
	crook["max_hp"] = 100.0
	var guard: Dictionary = _spawn(w, "guard", Vector2(10, 0))
	guard["hp"] = 200.0
	guard["max_hp"] = 200.0
	# Lethal assignment is deterministic: phases + cover blown.
	life._assign_lethal(guard, crook)
	_check("violent resists", String(crook.get("crime_phase", "")) == "resist")
	_check("guard goes lethal", String(guard.get("crime_phase", "")) == "guard_lethal")
	_check("sneak off when fighting", not bool(crook.get("sneaking", false)))
	# The arrest attempt routes violent suspects to resistance (seed scan
	# is deterministic: at least one seed in 1..40 must trigger it).
	var routed := false
	for s: int in range(1, 41):
		crook["crime_phase"] = ""
		guard["crime_phase"] = ""
		seed(s)
		life._arrest_attempt(guard, crook)
		if String(crook.get("crime_phase", "")) == "resist":
			routed = true
			break
	_check("arrest attempt routes violent to resist", routed)
	# Reset to a clean fight and let it play out. The guard should win
	# (lethal force) or the suspect surrenders.
	life._assign_lethal(guard, crook)
	crook["hp"] = 100.0
	guard["hp"] = 200.0
	seed(77)
	var resolved := false
	for i: int in 400:
		life.tick_unit(crook, 0.25)
		life.tick_unit(guard, 0.25)
		if not crook.get("alive", false):
			resolved = true
			_check("resister slain by guards", true)
			break
		var ph: String = String(crook.get("crime_phase", ""))
		if ph == "escort" or ph == "jailed":
			resolved = true
			_check("resister surrendered", true)
			break
	_check("resist resolved", resolved)


func _test_escort_to_jail() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var life: SimCrimeLife = w["life"]
	var crime: SimCrime = w["crime"]
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_set_traits(crook, 0.2, 0.1)
	var guard: Dictionary = _spawn(w, "guard", Vector2(5, 0))
	guard["speed"] = 90.0
	crook["speed"] = 90.0
	life._arrest(guard, crook)
	_check("escort phase", String(crook.get("crime_phase", "")) == "escort")
	_check("guard escort phase", String(guard.get("crime_phase", "")) == "guard_escort")
	# Jail is at (200, 0); walk them there via the real phase routing.
	var jailed := false
	for i: int in 300:
		life.tick_unit(guard, 0.25)
		life.tick_unit(crook, 0.25)
		if String(crook.get("crime_phase", "")) == "jailed":
			jailed = true
			break
	_check("escort ends in jail", jailed)
	_check("pretrial flag", bool(((crime.ensure_rec(crook)["c55"]) as Dictionary).get("awaitingTrial", false)))
	# Cell recorded on the jail.
	var cell_found := false
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "jail" \
				and int(crook.get("id", 0)) in (b.get("cells", []) as Array):
			cell_found = true
	_check("prisoner in a cell", cell_found)


func _test_jail_and_release() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var life: SimCrimeLife = w["life"]
	var crime: SimCrime = w["crime"]
	var crook: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_set_traits(crook, 0.2, 0.1)
	var rec: Dictionary = crime.ensure_rec(crook)
	rec["jailedUntil"] = float(crime.state["day"]) + 5.0
	life._jail_unit(crook, false)
	_check("jailed phase", String(crook.get("crime_phase", "")) == "jailed")
	_check("is_jailed", crime.is_jailed(int(crook.get("id", 0))))
	# Sentence served.
	rec["jailedUntil"] = float(crime.state["day"])
	life._release_jailed()
	_check("released after time served", String(crook.get("crime_phase", "")) == "")
	var still_celled := false
	for b: Dictionary in gs.buildings:
		if int(crook.get("id", 0)) in (b.get("cells", []) as Array):
			still_celled = true
	_check("cell freed", not still_celled)


func _test_trial_full_cast_and_verdict() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var life: SimCrimeLife = w["life"]
	var crime: SimCrime = w["crime"]
	# The accused + a full town.
	var accused: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_set_traits(accused, 0.9, 0.1)
	var townsfolk: Array = []
	for i: int in 15:
		townsfolk.append(_spawn(w, "worker", Vector2(20 + i * 8, 20)))
	var victim: Dictionary = townsfolk[0]
	var wit1: Dictionary = townsfolk[1]
	var wit2: Dictionary = townsfolk[2]
	# Load the evidence: two witnesses + stolen goods on the crook.
	var rec: Dictionary = crime.ensure_rec(accused)
	var c55: Dictionary = rec["c55"]
	crime.add_evidence(rec, {"type": "witness", "uid": int(wit1.get("id", 0)), "day": 1})
	crime.add_evidence(rec, {"type": "witness", "uid": int(wit2.get("id", 0)), "day": 1})
	crime.add_evidence(rec, {"type": "victim", "uid": int(victim.get("id", 0)), "day": 1})
	c55["stolenOnCrook"] = true
	(c55["crimes"] as Array).append({"kind": "theft", "day": 1,
		"victimUid": int(victim.get("id", 0))})
	c55["crimeKind"] = "theft"
	c55["awaitingTrial"] = true
	c55["trialDay"] = int(crime.state["day"])
	rec["jailedUntil"] = float(crime.state["day"]) + 1.2
	life._jail_unit(accused, false)
	# The trial begins.
	seed(3)
	life._start_due_trials()
	_check("live trial started", bool(c55.get("trial_live", false)))
	var trial: Dictionary = c55["trial"]
	var cast: Dictionary = trial["cast"]
	_check("judge seated", int(cast.get("judge", -1)) > 0)
	_check("jury picked", ((cast.get("jury", []) as Array).size() >= 3))
	_check("accused in courtroom", String(accused.get("crime_phase", "")) == "trial")
	# Fast-forward the whole trial.
	seed(3)
	for i: int in 90:
		life._tick_live_trial(1.0)
		if (c55.get("trial", {}) as Dictionary).is_empty():
			break
	_check("trial concluded", (c55.get("trial", {}) as Dictionary).is_empty())
	_check("trial_live cleared", not bool(c55.get("trial_live", false)))
	# Strong evidence -> guilty -> back in jail with a sentence.
	_check("guilty: sentenced", crime.is_jailed(int(accused.get("id", 0))))
	_check("guilty: back in cell", String(accused.get("crime_phase", "")) == "jailed")
	# Cast released back to normal life.
	var juror: Dictionary = gs.get_unit(int((cast.get("jury", []) as Array)[0]))
	_check("jury released", String(juror.get("crime_phase", "")) == "")


func _test_trial_acquittal() -> void:
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var crime: SimCrime = w["crime"]
	var accused: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	_set_traits(accused, 0.9, 0.1)
	for i: int in 12:
		_spawn(w, "worker", Vector2(20 + i * 8, 20))
	# No evidence at all.
	var rec: Dictionary = crime.ensure_rec(accused)
	var c55: Dictionary = rec["c55"]
	(c55["crimes"] as Array).append({"kind": "pickpocket", "day": 1})
	c55["crimeKind"] = "pickpocket"
	c55["awaitingTrial"] = true
	c55["trialDay"] = int(crime.state["day"])
	rec["jailedUntil"] = float(crime.state["day"]) + 1.2
	seed(21)
	life._start_due_trials()
	_check("acquittal trial started", bool(c55.get("trial_live", false)))
	seed(21)
	for i: int in 90:
		life._tick_live_trial(1.0)
		if (c55.get("trial", {}) as Dictionary).is_empty():
			break
	_check("acquitted: free", not crime.is_jailed(int(accused.get("id", 0))))
	_check("acquitted: no phase", String(accused.get("crime_phase", "")) == "")


func _test_daily_resolver_skips_live_trial() -> void:
	var w: Dictionary = _new_world()
	var life: SimCrimeLife = w["life"]
	var crime: SimCrime = w["crime"]
	var accused: Dictionary = _spawn(w, "worker", Vector2(0, 0))
	for i: int in 12:
		_spawn(w, "worker", Vector2(20 + i * 8, 20))
	var rec: Dictionary = crime.ensure_rec(accused)
	var c55: Dictionary = rec["c55"]
	(c55["crimes"] as Array).append({"kind": "theft", "day": 1})
	c55["crimeKind"] = "theft"
	c55["awaitingTrial"] = true
	c55["trialDay"] = int(crime.state["day"])
	rec["jailedUntil"] = float(crime.state["day"]) + 1.2
	seed(4)
	life._start_due_trials()
	_check("live trial running", bool(c55.get("trial_live", false)))
	# The daily resolver must not double-verdict a live trial.
	crime.daily_tick()
	_check("daily tick leaves live trial alone", bool(c55.get("trial_live", false)))
	_check("no double sentence", float(rec.get("jailedUntil", 0.0)) < float(crime.state["day"]) + 7.0)
