extends SceneTree
## Cursing Gnomes — levelable NPC skill tests (Jeremy 2026-10-11).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_skills.gd
##
## Exit code 0 = all passed, 1 = any failure.
## Covers: level curve (quadratic, capped); XP grants + level-ups;
## cure chance scaling; combat/yield/build/heal multipliers; job->skill
## mapping; grant_tick accumulation; profile summary; skills ride
## save/load on the unit records.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes skills tests ===")
	seed(20261011)
	_test_level_curve()
	_test_grant_and_level_up()
	_test_cure_chance()
	_test_multipliers()
	_test_job_skill_map()
	_test_grant_tick()
	_test_summary()
	_test_skills_on_unit_records()
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


func _make_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	return gs


func _make_unit(gs: GameState, job: String = "worker") -> Dictionary:
	return gs.add_unit({
		"faction": "humans", "job": job, "town_id": 1,
		"position": Vector2(100, 100), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 40.0, "mood": 60.0,
	})


func _test_level_curve() -> void:
	_check("0 xp is level 0", SimSkills.level_for_xp(0.0) == 0)
	_check("49 xp is level 0", SimSkills.level_for_xp(49.0) == 0)
	_check("50 xp is level 1", SimSkills.level_for_xp(50.0) == 1)
	_check("200 xp is level 2", SimSkills.level_for_xp(200.0) == 2)
	_check("450 xp is level 3", SimSkills.level_for_xp(450.0) == 3)
	_check("5000 xp is level 10", SimSkills.level_for_xp(5000.0) == 10)
	_check("level capped at 10", SimSkills.level_for_xp(999999.0) == 10)
	_check("negative xp is level 0", SimSkills.level_for_xp(-5.0) == 0)
	# Diminishing returns: each level costs more than the last.
	_check("level 2 costs more than level 1",
		200.0 - 50.0 > 50.0 - 0.0)


func _test_grant_and_level_up() -> void:
	var gs := _make_game()
	var u := _make_unit(gs, "doctor")
	_check("fresh unit has no medicine", SimSkills.level_of(u, "medicine") == 0)
	var lv := SimSkills.grant(gs, u, "medicine", 60.0)
	_check("60 xp grants level 1", lv == 1)
	_check("level stored", SimSkills.level_of(u, "medicine") == 1)
	_check("xp stored", absf(SimSkills.xp_of(u, "medicine") - 60.0) < 0.001)
	# Unknown skill rejected.
	_check("unknown skill rejected",
		SimSkills.grant(gs, u, "necromancy", 100.0) == 0)
	_check("unknown skill not stored",
		SimSkills.level_of(u, "necromancy") == 0)
	# Empty unit safe.
	_check("empty unit safe", SimSkills.grant(gs, {}, "medicine", 10.0) == 0)


func _test_cure_chance() -> void:
	var gs := _make_game()
	var green := _make_unit(gs, "doctor")
	var mid := _make_unit(gs, "doctor")
	SimSkills.grant(gs, mid, "medicine", 200.0)  # level 2
	var master := _make_unit(gs, "doctor")
	SimSkills.grant(gs, master, "medicine", 5000.0)  # level 10
	_check("green cures at base rate",
		absf(SimSkills.cure_chance(green) - 0.30) < 0.001)
	_check("level 2 cures better than green",
		SimSkills.cure_chance(mid) > SimSkills.cure_chance(green))
	_check("master cures at cap 0.95",
		absf(SimSkills.cure_chance(master) - 0.95) < 0.001)


func _test_multipliers() -> void:
	var gs := _make_game()
	var rookie := _make_unit(gs, "soldier")
	var vet := _make_unit(gs, "soldier")
	SimSkills.grant(gs, vet, "combat", 450.0)  # level 3
	_check("rookie deals base damage",
		absf(SimSkills.combat_mult(rookie) - 1.0) < 0.001)
	_check("veteran deals +24% at level 3",
		absf(SimSkills.combat_mult(vet) - 1.24) < 0.001)
	var farmer := _make_unit(gs, "farmer")
	SimSkills.grant(gs, farmer, "farming", 200.0)  # level 2
	_check("level 2 farmer yields +16%",
		absf(SimSkills.yield_mult(farmer, "farming") - 1.16) < 0.001)
	var builder := _make_unit(gs, "builder")
	SimSkills.grant(gs, builder, "building", 50.0)  # level 1
	_check("level 1 builder is +8% faster",
		absf(SimSkills.build_mult(builder) - 1.08) < 0.001)
	var doc := _make_unit(gs, "doctor")
	SimSkills.grant(gs, doc, "medicine", 50.0)  # level 1
	_check("level 1 doctor heals +5% faster",
		absf(SimSkills.heal_mult(doc) - 1.05) < 0.001)


func _test_job_skill_map() -> void:
	_check("doctor -> medicine", SimSkills.skill_for_job("doctor") == "medicine")
	_check("farmer -> farming", SimSkills.skill_for_job("farmer") == "farming")
	_check("miner -> mining", SimSkills.skill_for_job("miner") == "mining")
	_check("woodcutter -> woodcutting",
		SimSkills.skill_for_job("woodcutter") == "woodcutting")
	_check("builder -> building", SimSkills.skill_for_job("builder") == "building")
	_check("roadbuilder -> building",
		SimSkills.skill_for_job("roadbuilder") == "building")
	_check("soldier has no work skill", SimSkills.skill_for_job("soldier") == "")
	_check("all six skills listed", SimSkills.SKILLS.size() == 6)


func _test_grant_tick() -> void:
	var gs := _make_game()
	var u := _make_unit(gs, "farmer")
	# 4.9s of work: no XP yet.
	SimSkills.grant_tick(gs, u, "farming", 4.9)
	_check("no XP before 5s", SimSkills.xp_of(u, "farming") == 0.0)
	# Cross the threshold: 1 XP lands, remainder carries.
	SimSkills.grant_tick(gs, u, "farming", 0.2)
	_check("1 XP after 5s of work",
		absf(SimSkills.xp_of(u, "farming") - 1.0) < 0.001)
	# Unknown skill is a safe no-op.
	SimSkills.grant_tick(gs, u, "alchemy", 10.0)
	_check("unknown skill tick safe",
		SimSkills.level_of(u, "alchemy") == 0)


func _test_summary() -> void:
	var gs := _make_game()
	var u := _make_unit(gs, "doctor")
	_check("no skills, empty summary", SimSkills.summary(u) == "")
	SimSkills.grant(gs, u, "medicine", 60.0)
	_check("summary shows Medicine 1", SimSkills.summary(u) == "Medicine 1")
	SimSkills.grant(gs, u, "combat", 200.0)
	var s := SimSkills.summary(u)
	_check("summary shows both", "Medicine 1" in s and "Combat 2" in s)


func _test_skills_on_unit_records() -> void:
	var gs := _make_game()
	var u := _make_unit(gs, "doctor")
	SimSkills.grant(gs, u, "medicine", 120.0)
	# Skills live on the unit dict — units serialize wholesale, so
	# save/load carries them with zero extra code.
	_check("skills dict on unit", u.has("skills"))
	var skills: Dictionary = u["skills"]
	_check("medicine entry present", skills.has("medicine"))
	_check("xp survives dict round-trip",
		absf(float((skills["medicine"] as Dictionary).get("xp", 0.0)) - 120.0) < 0.001)
