extends SceneTree
## Cursing Gnomes — per-race lifespans + natural aging (Jeremy 2026-10-11).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_lifespans.gd
##
## Exit code 0 = all passed, 1 = any failure.
## Covers: Jeremy's lifespan table (elves 20 longest, undead ageless);
## seed_age spreads; aging + elder transition (0.85x move); quiet death
## inside the dying window (never before); undead never die of old age;
## obituary for notables; spouse/friend mourning (memory + mood);
## advisor succession refills the seat; save/load round-trip; long-run
## population stability.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes lifespans tests ===")
	seed(20261011)
	_test_lifespan_table()
	_test_seed_age()
	_test_seed_age_skips_undead_and_children()
	_test_aging_and_elder_transition()
	_test_quiet_death_in_window()
	_test_no_death_before_window()
	_test_undead_ageless()
	_test_obituary_for_notable()
	_test_no_obituary_for_commoner()
	_test_mourning()
	_test_succession()
	_test_save_load()
	_test_long_run_stability()
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


## Fresh headless game with lifespans wired like World does.
func _make_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres", "elves", "undead"])
	gs.lifespans = SimLifespans.new(gs)
	return gs


func _make_unit(gs: GameState, faction: String, job: String = "worker") -> Dictionary:
	var u: Dictionary = gs.add_unit({
		"faction": faction, "job": job, "town_id": 1,
		"position": Vector2(100, 100), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 40.0, "mood": 60.0,
	})
	SimLifespans.seed_age(u)
	return u


func _tick_days(gs: GameState, n: int) -> void:
	for i in n:
		gs.day_number += 1
		gs.bus.day_changed.emit(gs.day_number, false)


func _test_lifespan_table() -> void:
	_check("elves live 20 game years (longest)",
		SimLifespans.lifespan_years("elves") == 20.0)
	_check("gnomes live 14", SimLifespans.lifespan_years("gnomes") == 14.0)
	_check("humans live 12", SimLifespans.lifespan_years("humans") == 12.0)
	_check("ogres live 9", SimLifespans.lifespan_years("ogres") == 9.0)
	_check("elves are the longest-lived",
		SimLifespans.lifespan_years("elves") > SimLifespans.lifespan_years("gnomes") \
		and SimLifespans.lifespan_years("elves") > SimLifespans.lifespan_years("humans") \
		and SimLifespans.lifespan_years("elves") > SimLifespans.lifespan_years("ogres"))
	_check("undead are ageless", SimLifespans.is_ageless("undead"))
	_check("the living are not ageless",
		not SimLifespans.is_ageless("humans") and not SimLifespans.is_ageless("elves"))
	_check("a game year is 360 days", SimLifespans.DAYS_PER_YEAR == 360.0)
	_check("elf lifespan in days", SimLifespans.lifespan_days("elves") == 7200.0)


func _test_seed_age() -> void:
	var gs := _make_game()
	var u := _make_unit(gs, "humans")
	var span := SimLifespans.lifespan_days("humans")
	_check("seeded age is a young adult",
		float(u["age_days"]) >= span * 0.05 and float(u["age_days"]) <= span * 0.25)
	var dd := float(u["death_day"])
	_check("death day inside the dying window",
		dd >= span * SimLifespans.DEATH_LO and dd <= span * SimLifespans.DEATH_HI)
	_check("seeded stage is adult", String(u.get("age_stage", "")) == "adult")


func _test_seed_age_skips_undead_and_children() -> void:
	var gs := _make_game()
	var z: Dictionary = gs.add_unit({"faction": "undead", "job": "worker",
		"position": Vector2.ZERO, "alive": true})
	SimLifespans.seed_age(z)
	_check("undead get no age", not z.has("age_days"))
	_check("undead get no death day", not z.has("death_day"))
	var c: Dictionary = gs.add_unit({"faction": "humans", "job": "child",
		"position": Vector2.ZERO, "alive": true, "is_child": true})
	SimLifespans.seed_age(c)
	_check("children are not age-seeded", not c.has("age_days"))


func _test_aging_and_elder_transition() -> void:
	var gs := _make_game()
	var u := _make_unit(gs, "ogres")
	var span := SimLifespans.lifespan_days("ogres")
	# Age to just past the elder threshold; death day pushed far out.
	u["age_days"] = span * SimLifespans.ELDER_FRACTION + 1.0
	u["death_day"] = span * 2.0
	_tick_days(gs, 1)
	_check("elder stage reached", String(u.get("age_stage", "")) == "elder")
	_check("elders move slower",
		is_equal_approx(float(u.get("age_move_mult", 1.0)), SimLifespans.ELDER_MOVE_MULT))
	_check("elder still alive", bool(u.get("alive", false)))
	# Before the threshold: still adult, full speed.
	var v := _make_unit(gs, "ogres")
	v["age_days"] = span * 0.5
	v["death_day"] = span * 2.0
	_tick_days(gs, 1)
	_check("mid-life is adult", String(v.get("age_stage", "")) == "adult")
	_check("adults keep full speed", float(v.get("age_move_mult", 1.0)) == 1.0)


func _test_quiet_death_in_window() -> void:
	var gs := _make_game()
	var u := _make_unit(gs, "humans")
	var span := SimLifespans.lifespan_days("humans")
	u["death_day"] = span * 1.0
	u["age_days"] = float(u["death_day"]) - 1.0
	_tick_days(gs, 2)
	_check("unit passed away in the dying window", not bool(u.get("alive", false)))
	_check("death cause is old age", String(u.get("death_cause", "")) == "old_age")
	_check("age at death recorded", float(u.get("age_at_death", 0.0)) > 11.0)


func _test_no_death_before_window() -> void:
	var gs := _make_game()
	var u := _make_unit(gs, "elves")
	var span := SimLifespans.lifespan_days("elves")
	u["age_days"] = span * 0.5
	u["death_day"] = span * 1.0
	_tick_days(gs, 100)
	_check("no premature death at mid-life", bool(u.get("alive", false)))
	_check("no death cause set", String(u.get("death_cause", "")) == "")


func _test_undead_ageless() -> void:
	var gs := _make_game()
	var z: Dictionary = gs.add_unit({"faction": "undead", "job": "worker",
		"position": Vector2.ZERO, "alive": true, "hp": 100.0, "max_hp": 100.0})
	# Even an "ancient" undead never dies of old age.
	z["age_days"] = 999999.0
	z["death_day"] = 1.0
	_tick_days(gs, 50)
	_check("undead never die of old age", bool(z.get("alive", false)))
	_check("undead get no death cause", String(z.get("death_cause", "")) == "")


func _test_obituary_for_notable() -> void:
	var gs := _make_game()
	var stories: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: stories.append(s))
	var adv := _make_unit(gs, "humans", "advisor_economy")
	adv["is_advisor"] = true
	var span := SimLifespans.lifespan_days("humans")
	adv["death_day"] = span * 1.0
	adv["age_days"] = float(adv["death_day"]) - 1.0
	_tick_days(gs, 2)
	_check("advisor died of old age", String(adv.get("death_cause", "")) == "old_age")
	var found := false
	for s in stories:
		if String(s.get("kind", "")) == "obituary":
			found = true
	_check("Gazette published an obituary", found)


func _test_no_obituary_for_commoner() -> void:
	var gs := _make_game()
	var stories: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: stories.append(s))
	var u := _make_unit(gs, "humans", "worker")
	var span := SimLifespans.lifespan_days("humans")
	u["death_day"] = span * 1.0
	u["age_days"] = float(u["death_day"]) - 1.0
	_tick_days(gs, 2)
	_check("commoner died quietly", String(u.get("death_cause", "")) == "old_age")
	var found := false
	for s in stories:
		if String(s.get("kind", "")) == "obituary":
			found = true
	_check("no obituary for a commoner", not found)


func _test_mourning() -> void:
	var gs := _make_game()
	gs.family = SimFamily.new(gs)
	var adv := _make_unit(gs, "humans", "advisor_civic")
	adv["is_advisor"] = true
	var spouse := _make_unit(gs, "humans", "worker")
	gs.family.ensure(spouse)
	spouse["spouse_uid"] = int(adv["id"])
	var stranger := _make_unit(gs, "humans", "worker")
	stranger["position"] = Vector2(5000, 5000)
	var span := SimLifespans.lifespan_days("humans")
	adv["death_day"] = span * 1.0
	adv["age_days"] = float(adv["death_day"]) - 1.0
	var mood_before := float(spouse.get("mood", 60.0))
	_tick_days(gs, 2)
	_check("spouse's mood dipped", float(spouse.get("mood", 60.0)) < mood_before)
	var mems: Array = spouse.get("memories", [])
	var remembered := false
	for m in mems:
		if String(m.get("type", "")) == "friend_died" \
				and int(m.get("subject_id", -1)) == int(adv["id"]):
			remembered = true
	_check("spouse remembers the passing", remembered)
	_check("stranger unaffected",
		is_equal_approx(float(stranger.get("mood", 60.0)), 60.0))


func _test_succession() -> void:
	var gs := _make_game()
	gs.towns[1] = {"id": 1, "faction": "humans"}
	gs.buildings.append({"type": "town_hall", "faction": "humans",
		"town_id": 1, "position": Vector2(100, 100), "id": 7})
	var adv := _make_unit(gs, "humans", "advisor_war")
	adv["is_advisor"] = true
	adv["mind"] = {"gov_role": "war_counsel"}
	var span := SimLifespans.lifespan_days("humans")
	adv["death_day"] = span * 1.0
	adv["age_days"] = float(adv["death_day"]) - 1.0
	_tick_days(gs, 2)
	_check("old advisor passed", not bool(adv.get("alive", false)))
	var replacement := false
	for u in gs.units:
		if not (u is Dictionary):
			continue
		if bool(u.get("alive", false)) \
				and String(u.get("job", "")) == "advisor_war" \
				and int(u.get("id", -1)) != int(adv["id"]):
			replacement = true
	_check("a successor was appointed", replacement)


func _test_save_load() -> void:
	var gs := _make_game()
	gs.lifespans._obit_day = {"humans": 42}
	var d: Dictionary = gs.lifespans.to_dict()
	var gs2 := _make_game()
	gs2.lifespans.from_dict(d)
	_check("obituary cooldown survives save/load",
		int(gs2.lifespans._obit_day.get("humans", -1)) == 42)
	# Unit ages ride on the unit records themselves.
	var u := _make_unit(gs, "gnomes")
	_check("age persists on the unit record", u.has("age_days") and u.has("death_day"))


func _test_long_run_stability() -> void:
	var gs := _make_game()
	# A lived-in faction: spread ages across the whole lifespan so deaths
	# actually occur during the run.
	var span := SimLifespans.lifespan_days("humans")
	for i in 30:
		var u := _make_unit(gs, "humans")
		u["age_days"] = span * randf_range(0.1, 0.99)
		u["death_day"] = span * randf_range(
			SimLifespans.DEATH_LO, SimLifespans.DEATH_HI)
	_tick_days(gs, 400)
	var alive := 0
	var elders := 0
	for u in gs.units:
		if not (u is Dictionary) or not bool(u.get("alive", false)):
			continue
		alive += 1
		if String(u.get("age_stage", "")) == "elder":
			elders += 1
	_check("old-age deaths occurred during the run", alive < 30)
	_check("faction did not hollow out", alive >= 10)
	_check("elders exist in the population", elders > 0)
	# Deaths are peaceful: no violent causes recorded.
	var violent := 0
	for u in gs.units:
		if String(u.get("death_cause", "")) not in ["", "old_age"]:
			violent += 1
	_check("all recorded deaths were natural", violent == 0)
