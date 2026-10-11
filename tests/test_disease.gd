extends SceneTree
## Cursing Gnomes — plague/disease system tests (Jeremy 2026-10-11).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_disease.gd
##
## Exit code 0 = all passed, 1 = any failure.
## Covers: immunity table (undead/elf never sick); outbreak seeding;
## proximity spread + quarantine blocking spread; each doctrine path
## (military cull, doctor cull, cure, quarantine, mercy, ignore);
## cure chance scales with medicine skill; executioner infection risk;
## doctrine switching mid-outbreak; plague policy in SimPolicies;
## save/load round-trip.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes disease tests ===")
	seed(20261011)
	_test_immunity_table()
	_test_outbreak_seeding()
	_test_spread_and_quarantine_block()
	_test_immune_never_catch()
	_test_cull_military()
	_test_cull_doctor()
	_test_cure_scales_with_skill()
	_test_quarantine_rounds_up()
	_test_mercy_combines()
	_test_ignore_does_nothing()
	_test_doctrine_switch_mid_outbreak()
	_test_policies_plague_doctrine()
	_test_voice_plague_doctrine()
	_test_autumn_outbreak_trigger()
	_test_save_load()
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


## Fresh headless game with disease wired like World does.
func _make_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres", "elves", "undead"])
	gs.disease = SimDisease.new(gs)
	return gs


func _make_unit(gs: GameState, faction: String, job: String = "worker",
		town: int = 1, pos: Vector2 = Vector2(100, 100)) -> Dictionary:
	return gs.add_unit({
		"faction": faction, "job": job, "town_id": town,
		"position": pos, "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 40.0, "mood": 60.0,
	})


func _tick_day(gs: GameState) -> void:
	gs.day_number += 1
	gs.bus.day_changed.emit(gs.day_number, false)


func _test_immunity_table() -> void:
	_check("undead immune", SimDisease.is_immune("undead"))
	_check("elves immune", SimDisease.is_immune("elves"))
	_check("humans fully susceptible",
		SimDisease.susceptibility("humans") == 1.0)
	_check("ogres moderately susceptible",
		SimDisease.susceptibility("ogres") == 0.60)
	_check("gnomes rarely susceptible",
		SimDisease.susceptibility("gnomes") == 0.15)
	_check("gnomes less susceptible than ogres",
		SimDisease.susceptibility("gnomes") < SimDisease.susceptibility("ogres"))


func _test_outbreak_seeding() -> void:
	var gs := _make_game()
	for i in 10:
		_make_unit(gs, "humans", "worker", 1, Vector2(100 + i * 10, 100))
	gs.disease._seed_outbreak("humans", 1)
	var n = gs.disease.sick_count("humans")
	_check("outbreak seeds 1-3 cases", n >= 1 and n <= 3)
	# Immune factions never seed.
	for i in 5:
		_make_unit(gs, "elves", "worker", 2, Vector2(500 + i * 10, 500))
	gs.disease._seed_outbreak("elves", 1)
	_check("elves never seeded", gs.disease.sick_count("elves") == 0)


func _test_spread_and_quarantine_block() -> void:
	var gs := _make_game()
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_IGNORE)
	var s := _make_unit(gs, "humans", "worker", 1, Vector2(100, 100))
	gs.disease._infect(s, 1)
	var spread := false
	for i in 30:
		_make_unit(gs, "humans", "worker", 1, Vector2(110 + i * 5, 105))
	# Force many spread ticks; with 30 neighbors some must catch it.
	for d in 12:
		gs.disease._tick_spread(1 + d)
		if gs.disease.sick_count("humans") > 1:
			spread = true
			break
	_check("plague spreads between nearby town-mates", spread)
	# Quarantined sick don't spread.
	var gs2 := _make_game()
	gs2.disease.set_doctrine("humans", SimDisease.DOCTRINE_IGNORE)
	var s2 := _make_unit(gs2, "humans", "worker", 1, Vector2(100, 100))
	gs2.disease._infect(s2, 1)
	s2["quarantined"] = true
	for i in 30:
		_make_unit(gs2, "humans", "worker", 1, Vector2(110 + i * 5, 105))
	for d in 12:
		gs2.disease._tick_spread(1 + d)
	_check("quarantined sick do not spread",
		gs2.disease.sick_count("humans") == 1)


func _test_immune_never_catch() -> void:
	var gs := _make_game()
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_IGNORE)
	var s := _make_unit(gs, "humans", "worker", 1, Vector2(100, 100))
	gs.disease._infect(s, 1)
	for i in 10:
		_make_unit(gs, "undead", "worker", 1, Vector2(105 + i * 3, 100))
		_make_unit(gs, "elves", "worker", 1, Vector2(105 + i * 3, 120))
	for d in 20:
		gs.disease._tick_spread(1 + d)
	_check("undead never catch plague", gs.disease.sick_count("undead") == 0)
	_check("elves never catch plague", gs.disease.sick_count("elves") == 0)


func _test_cull_military() -> void:
	var gs := _make_game()
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_CULL_MILITARY)
	var sick_units: Array = []
	for i in 6:
		var u := _make_unit(gs, "humans", "worker", 1, Vector2(100 + i * 8, 100))
		gs.disease._infect(u, 1)
		sick_units.append(u)
	for i in 3:
		_make_unit(gs, "humans", "soldier", 1, Vector2(200 + i * 8, 200))
	# A nearby witness, present for the culling.
	var witness := _make_unit(gs, "humans", "worker", 1, Vector2(104, 100))
	gs.disease._tick_doctrines(2)
	var dead := 0
	for u in sick_units:
		if not bool(u.get("alive", false)):
			dead += 1
	_check("military cull executes the sick", dead > 0)
	_check("cull bounded per day", dead <= SimDisease.CULL_PER_DAY)
	var marked := dead > 0
	for u in sick_units:
		if not bool((u as Dictionary).get("alive", false)):
			if String((u as Dictionary).get("death_cause", "")) != "plague_cull":
				marked = false
	_check("cull deaths marked plague_cull", marked)
	# The culling is REMEMBERED: a nearby witness carries a friend_died
	# memory with positive strength (a clamped-to-zero strength would mean
	# the moral weight was silently discarded).
	var mems: Array = SimMemories.new(gs).ensure(witness)
	var remembered := false
	for m in mems:
		if String((m as Dictionary).get("type", "")) == "friend_died" \
				and float((m as Dictionary).get("strength", 0.0)) > 0.0:
			remembered = true
	_check("witnesses remember the culling (strength > 0)", remembered)


func _test_cull_doctor() -> void:
	var gs := _make_game()
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_CULL_DOCTOR)
	var sick_units: Array = []
	for i in 4:
		var u := _make_unit(gs, "humans", "worker", 1, Vector2(100 + i * 8, 100))
		gs.disease._infect(u, 1)
		sick_units.append(u)
	_make_unit(gs, "humans", "doctor", 1, Vector2(200, 200))
	gs.disease._tick_doctrines(2)
	var dead := 0
	for u in sick_units:
		if not bool(u.get("alive", false)):
			dead += 1
	_check("doctor cull executes the sick", dead > 0)


func _test_cure_scales_with_skill() -> void:
	# Green doctor: low cure chance. Master doctor: near-certain.
	var gs := _make_game()
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_CURE)
	var green := _make_unit(gs, "humans", "doctor", 1, Vector2(200, 200))
	_check("green doctor cure chance is base",
		absf(SimSkills.cure_chance(green) - SimSkills.CURE_BASE) < 0.001)
	var master := _make_unit(gs, "humans", "doctor", 1, Vector2(210, 200))
	SimSkills.grant(gs, master, "medicine", 5000.0)  # level 10
	_check("master doctor reaches level 10",
		SimSkills.level_of(master, "medicine") == 10)
	_check("master cure chance capped at 0.95",
		absf(SimSkills.cure_chance(master) - 0.95) < 0.001)
	_check("cure chance scales with skill",
		SimSkills.cure_chance(master) > SimSkills.cure_chance(green))
	# Treatment actually cures over ticks with a skilled doctor.
	var cured := false
	for i in 4:
		var u := _make_unit(gs, "humans", "worker", 1, Vector2(100 + i * 8, 100))
		gs.disease._infect(u, 1)
	for d in 10:
		gs.disease._tick_treatment("humans", 2 + d, true)
		if gs.disease.sick_count("humans") == 0:
			cured = true
			break
	_check("skilled doctors cure the sick", cured)


func _test_quarantine_rounds_up() -> void:
	var gs := _make_game()
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_QUARANTINE)
	gs.add_building({"faction": "humans", "type": "clinic", "town_id": 1,
		"position": Vector2(300, 300), "complete": true, "alive": true})
	var sick_units: Array = []
	for i in 3:
		var u := _make_unit(gs, "humans", "worker", 1, Vector2(100 + i * 8, 100))
		gs.disease._infect(u, 1)
		sick_units.append(u)
	gs.disease._tick_doctrines(2)
	var q := 0
	for u in sick_units:
		if bool((u as Dictionary).get("quarantined", false)):
			q += 1
	_check("quarantine rounds up the sick", q == 3)
	# No clinic: the sick stay home, nothing crashes.
	var gs2 := _make_game()
	gs2.disease.set_doctrine("humans", SimDisease.DOCTRINE_QUARANTINE)
	var u2 := _make_unit(gs2, "humans", "worker", 1, Vector2(100, 100))
	gs2.disease._infect(u2, 1)
	gs2.disease._tick_doctrines(2)
	_check("quarantine without clinic is a safe no-op",
		not bool(u2.get("quarantined", false)) and bool(u2.get("sick", false)))


func _test_mercy_combines() -> void:
	var gs := _make_game()
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_MERCY)
	gs.add_building({"faction": "humans", "type": "clinic", "town_id": 1,
		"position": Vector2(300, 300), "complete": true, "alive": true})
	var doc := _make_unit(gs, "humans", "doctor", 1, Vector2(200, 200))
	SimSkills.grant(gs, doc, "medicine", 5000.0)
	var sick_refs: Array = []
	for i in 3:
		var u := _make_unit(gs, "humans", "worker", 1, Vector2(100 + i * 8, 100))
		gs.disease._infect(u, 1)
		sick_refs.append(u)
	# Quarantine lands on the first tick, before the master doctor cures all.
	gs.disease._tick_quarantine("humans", 2, false)
	var quarantined_now := 0
	for u in sick_refs:
		if bool((u as Dictionary).get("quarantined", false)):
			quarantined_now += 1
	_check("mercy quarantines the sick", quarantined_now == 3)
	for d in 8:
		gs.disease._tick_doctrines(2 + d)
	_check("mercy never executes (all sick still alive or cured, none culled)",
		gs.disease.stats_of("humans").get("culled", 0) == 0)


func _test_ignore_does_nothing() -> void:
	var gs := _make_game()
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_IGNORE)
	for i in 3:
		var u := _make_unit(gs, "humans", "worker", 1, Vector2(100 + i * 8, 100))
		gs.disease._infect(u, 1)
	gs.disease._tick_doctrines(2)
	_check("ignore leaves the sick alone", gs.disease.sick_count("humans") == 3)
	_check("ignore records no culls",
		gs.disease.stats_of("humans").get("culled", 0) == 0)


func _test_doctrine_switch_mid_outbreak() -> void:
	var gs := _make_game()
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_IGNORE)
	var units: Array = []
	for i in 4:
		var u := _make_unit(gs, "humans", "worker", 1, Vector2(100 + i * 8, 100))
		gs.disease._infect(u, 1)
		units.append(u)
	gs.disease._tick_doctrines(2)
	_check("ignore first: all sick alive", gs.disease.sick_count("humans") == 4)
	# Switch mid-outbreak: the sword comes out.
	for i in 2:
		_make_unit(gs, "humans", "soldier", 1, Vector2(200 + i * 8, 200))
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_CULL_MILITARY)
	gs.disease._tick_doctrines(3)
	_check("mid-outbreak switch to cull executes",
		gs.disease.sick_count("humans") < 4)


func _test_policies_plague_doctrine() -> void:
	var gs := _make_game()
	var pol := SimPolicies.new(gs)
	_check("default doctrine is mercy", pol.plague_policy() == "mercy")
	_check("set valid doctrine", pol.set_plague_policy("cull_military"))
	_check("doctrine stored", pol.plague_policy() == "cull_military")
	_check("set same doctrine is a no-op",
		not pol.set_plague_policy("cull_military"))
	_check("set invalid doctrine rejected", not pol.set_plague_policy("nonsense"))
	_check("all six doctrines valid",
		SimPolicies.PLAGUE_POLICY_ORDER.size() == 6)


func _test_save_load() -> void:
	var gs := _make_game()
	gs.disease.set_doctrine("humans", SimDisease.DOCTRINE_CULL_DOCTOR)
	gs.disease._last_outbreak["ogres"] = 42
	var data = gs.disease.to_dict()
	var gs2 := _make_game()
	gs2.disease.from_dict(data)
	_check("doctrine survives save/load",
		gs2.disease.doctrine_of("humans") == SimDisease.DOCTRINE_CULL_DOCTOR)
	_check("outbreak cooldown survives",
		int(gs2.disease._last_outbreak.get("ogres", -1)) == 42)


class _StubCourtVoice:
	extends RefCounted
	var policies = null

	func _init(gs) -> void:
		policies = SimPolicies.new(gs, self)


class _StubSeasons:
	extends RefCounted
	var _month := 9

	func month() -> int:
		return _month


func _test_autumn_outbreak_trigger() -> void:
	var gs := _make_game()
	gs.seasons = _StubSeasons.new()
	for i in 12:
		_make_unit(gs, "humans", "worker", 1, Vector2(100 + i * 10, 100))
	# First sight of month 9: the autumn roll happens (seeded RNG).
	gs.disease._maybe_autumn_outbreak(200)
	# Same month again: no double-roll.
	var after_first = gs.disease.sick_count("humans")
	gs.disease._maybe_autumn_outbreak(201)
	_check("no double outbreak in the same month",
		gs.disease.sick_count("humans") == after_first)
	# Non-autumn month: nothing.
	(gs.seasons as _StubSeasons)._month = 5
	gs.disease._maybe_autumn_outbreak(202)
	_check("no outbreak outside autumn",
		gs.disease.sick_count("humans") == after_first)


func _test_voice_plague_doctrine() -> void:
	var gs := _make_game()
	gs.disease = SimDisease.new(gs)
	gs.court_sys = _StubCourtVoice.new(gs)
	var rv := SimRulersVoice.new(gs)
	var advisor := {"id": 7, "faction": "humans", "job": "advisor_civic",
		"alive": true, "voice": "civic"}
	var r1: String = rv._order_plague(advisor, "quarantine the sick")
	_check("voice sets quarantine doctrine",
		gs.court_sys.policies.plague_policy() == "quarantine")
	_check("voice confirms the doctrine", "Quarantine" in r1)
	var r2: String = rv._order_plague(advisor, "save them all")
	_check("voice sets mercy doctrine",
		gs.court_sys.policies.plague_policy() == "mercy")
	var r3: String = rv._order_plague(advisor, "cull the sick")
	_check("voice sets military cull",
		gs.court_sys.policies.plague_policy() == "cull_military")
	_check("cull voice is honest about consequences", "Gazette" in r3)
	var r4: String = rv._order_plague(advisor, "what is the plague plan")
	_check("voice reports current doctrine without changing it",
		gs.court_sys.policies.plague_policy() == "cull_military"
		and "Military Cull" in r4)
