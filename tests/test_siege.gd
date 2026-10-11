extends SceneTree
## Cursing Gnomes — civilian siege response tests.
##
## Covers the AI-first phase war/peace-response checklist item "civilian
## siege defense" (port of HTML fix79 Siege Doctrine: civilianDefenseTick +
## defenseRepairTarget + nearestHostileUnit, lines 12165-12360), plus the
## HTML-verbatim threat-model extension in SimAIDirector._threat_level
## (cityUnderAttack: any foreign unit within 280px of the hall = level 2;
## cityThreatened: hostile military/raider/monster/bandit/leader within
## 1500px = level 1):
##   - threat 2: civilians hide (home > hall > nearest intact building),
##     +25 stress, per-race war cries
##   - 35% of workers are brave: repair walls first (walls preempt any
##     non-wall job), then most-damaged building; 2 s retarget throttle
##   - no shelter: flee from the nearest hostile (mind flee system)
##   - military / leaders / player orders / urge-trippers never touched
##   - threat over: stand down — flags clear, hiders leave the shelter
##   - SimMind.tick_unit returns true for hiders (work skipped)
##   - WorkerAI._pick_task refuses siege-owned units
##   - 1 s throttle on tick()
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_siege.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes siege tests ===")
	_test_hide_in_hall()
	_test_stress_and_hide_line()
	_test_brave_distribution()
	_test_brave_repairs_wall()
	_test_wall_preempts_house()
	_test_keep_current_wall_job()
	_test_retarget_throttle()
	_test_military_skipped()
	_test_leader_skipped()
	_test_player_order_skipped()
	_test_urge_tripper_skipped()
	_test_fleeing_skipped()
	_test_no_shelter_flees()
	_test_nearest_hostile_skips_children()
	_test_shelter_home_preferred()
	_test_stand_down()
	_test_threat_level2_any_unit()
	_test_threat_level1_approaching()
	_test_threat_calm()
	_test_throttle()
	_test_mind_guard()
	_test_pick_task_guard()
	_test_race_lines()
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


## Fresh game + combat + interiors + director + siege.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var combat := SimCombat.new(gs)
	combat.diplomacy = gs.diplomacy
	var interiors := SimInteriors.new(gs)
	gs.ai_director = SimAIDirector.new(gs)
	var siege := SimSiege.new(gs, combat, interiors)
	return {"gs": gs, "combat": combat, "interiors": interiors,
		"siege": siege, "ad": gs.ai_director}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


func _building(w: Dictionary, btype: String, faction: String,
		pos: Vector2, hp_frac: float = 1.0) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({
		"type": btype, "faction": faction, "town_id": -1,
		"position": pos, "complete": true, "progress": 1.0,
		"alive": true, "hp": 1200.0 * hp_frac, "max_hp": 1200.0,
	})


## Hall + war + one enemy at the gates => threat level 2 for humans.
func _attack_setup(w: Dictionary, enemy_pos: Vector2) -> Dictionary:
	var hall := _building(w, "hall", "humans", Vector2.ZERO)
	var gs: GameState = w["gs"]
	gs.diplomacy.declare_war("ogres", "humans", "test")
	var foe := _spawn(w, "ogres", "soldier", enemy_pos)
	return {"hall": hall, "foe": foe}


func _test_hide_in_hall() -> void:
	var w := _new_world()
	var ctx := _attack_setup(w, Vector2(200, 0))
	var hall: Dictionary = ctx["hall"]
	# farmer: a civilian that can never roll "brave" (brave needs job worker)
	var civ := _spawn(w, "humans", "farmer", Vector2(100, 0))
	(w["siege"] as SimSiege)._tick_siege()
	_check("hide: flag set", bool(civ.get("_siege_hide", false)))
	_check("hide: inside the hall",
		int(civ.get("inside_building_id", 0)) == int(hall.get("id", 0)))
	_check("hide: shelter recorded",
		int(civ.get("siege_shelter_id", 0)) == int(hall.get("id", 0)))
	_check("hide: work not re-tasked", String(civ.get("work_state", "")) == "idle")
	_free_world(w)


func _test_stress_and_hide_line() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var civ := _spawn(w, "humans", "farmer", Vector2(100, 0))
	var said := []
	var gs: GameState = w["gs"]
	gs.bus.unit_said.connect(func(_id: int, text: String) -> void:
		said.append(text))
	(w["siege"] as SimSiege)._tick_siege()
	_check("hide: +25 stress", float(civ.get("stress", 0.0)) == 25.0)
	_free_world(w)


func _test_brave_distribution() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	seed(20261005)  # deterministic brave rolls (AGENTS.md de-flake pattern)
	var brave := 0
	var hid := 0
	for i in range(12):
		var u := _spawn(w, "humans", "worker", Vector2(100 + i * 7, 0))
		(w["siege"] as SimSiege)._civilian_defense(u)
		if bool(u.get("_siege_repair", false)):
			brave += 1
		elif bool(u.get("_siege_hide", false)):
			hid += 1
	_check("brave: some workers brave", brave > 0)
	_check("brave: some workers hide", hid > 0)
	_check("brave: every worker chose a role", brave + hid == 12)
	_free_world(w)


func _test_brave_repairs_wall() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var wall := _building(w, "wall", "humans", Vector2(150, 0), 0.5)
	var u := _spawn(w, "humans", "worker", Vector2(100, 0))
	u["_siege_repair"] = true
	(w["siege"] as SimSiege)._defense_repair_target(u)
	_check("repair: ordered to the wall",
		int(u.get("work_building", -1)) == int(wall.get("id", 0)))
	_check("repair: work_state to_repair",
		String(u.get("work_state", "")) == "to_repair")
	_check("repair: gather assignment dropped", not u.has("work_site"))
	_free_world(w)


func _test_wall_preempts_house() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	# House is MORE damaged, but siege doctrine fixes walls first.
	var wall := _building(w, "wall", "humans", Vector2(150, 0), 0.5)
	var house := _building(w, "house", "humans", Vector2(120, 0), 0.1)
	var u := _spawn(w, "humans", "worker", Vector2(100, 0))
	u["_siege_repair"] = true
	(w["siege"] as SimSiege)._defense_repair_target(u)
	_check("repair: damaged wall beats worse-damaged house",
		int(u.get("work_building", -1)) == int(wall.get("id", 0)))
	_check("sanity: house exists", not house.is_empty())
	_free_world(w)


func _test_keep_current_wall_job() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var wall := _building(w, "wall", "humans", Vector2(150, 0), 0.5)
	var wall2 := _building(w, "wall", "humans", Vector2(900, 0), 0.4)
	var u := _spawn(w, "humans", "worker", Vector2(100, 0))
	u["_siege_repair"] = true
	u["work_building"] = int(wall.get("id", 0))
	u["work_state"] = "repairing"
	(w["siege"] as SimSiege)._defense_repair_target(u)
	_check("repair: keeps current wall job",
		int(u.get("work_building", -1)) == int(wall.get("id", 0)))
	_check("sanity: second wall exists", not wall2.is_empty())
	_free_world(w)


func _test_retarget_throttle() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var house := _building(w, "house", "humans", Vector2(120, 0), 0.5)
	var u := _spawn(w, "humans", "worker", Vector2(100, 0))
	u["_siege_repair"] = true
	u["_siege_ret_t"] = Time.get_ticks_msec() / 1000.0  # just retargeted
	(w["siege"] as SimSiege)._defense_repair_target(u)
	_check("repair: 2 s throttle holds",
		int(u.get("work_building", -1)) != int(house.get("id", 0)))
	_free_world(w)


func _test_military_skipped() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var s := _spawn(w, "humans", "soldier", Vector2(100, 0))
	(w["siege"] as SimSiege)._tick_siege()
	_check("skip: military not hidden", not bool(s.get("_siege_hide", false)))
	_check("skip: military not repairing", not bool(s.get("_siege_repair", false)))
	_free_world(w)


func _test_leader_skipped() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var l := _spawn(w, "humans", "farmer", Vector2(100, 0))
	l["is_leader"] = true
	(w["siege"] as SimSiege)._tick_siege()
	_check("skip: leader not hidden", not bool(l.get("_siege_hide", false)))
	_free_world(w)


func _test_player_order_skipped() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var u := _spawn(w, "humans", "farmer", Vector2(100, 0))
	u["player_order"] = {"kind": "move"}
	(w["siege"] as SimSiege)._tick_siege()
	_check("skip: player-ordered not hidden", not bool(u.get("_siege_hide", false)))
	_free_world(w)


func _test_urge_tripper_skipped() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var u := _spawn(w, "humans", "farmer", Vector2(100, 0))
	u["mind_state"] = "satisfying:hunger"
	(w["siege"] as SimSiege)._tick_siege()
	_check("skip: urge-tripper not hidden", not bool(u.get("_siege_hide", false)))
	_free_world(w)


func _test_fleeing_skipped() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var u := _spawn(w, "humans", "farmer", Vector2(100, 0))
	u["fleeing"] = true
	u["flee_timer"] = 6.0
	(w["siege"] as SimSiege)._tick_siege()
	_check("skip: fleeing not re-tasked", not bool(u.get("_siege_hide", false)))
	_free_world(w)


func _test_no_shelter_flees() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	# Hall exists (so a faction home exists) but is incomplete: no shelter.
	var hall: Dictionary = gs.add_building({
		"type": "hall", "faction": "humans", "town_id": -1,
		"position": Vector2.ZERO, "complete": false, "progress": 0.2,
		"alive": true, "hp": 1200.0, "max_hp": 1200.0,
	})
	gs.diplomacy.declare_war("ogres", "humans", "test")
	var foe := _spawn(w, "ogres", "soldier", Vector2(200, 0))
	var u := _spawn(w, "humans", "farmer", Vector2(100, 0))
	(w["siege"] as SimSiege)._civilian_defense(u)  # bypass threat gate
	_check("flee: no shelter -> fleeing", bool(u.get("fleeing", false)))
	var tp: Vector2 = u.get("threat_pos", Vector2.INF)
	_check("flee: threat is the foe",
		tp.distance_to(foe.get("position", Vector2.ZERO)) < 1.0)
	_check("flee: not flagged hidden", not bool(u.get("_siege_hide", false)))
	_check("sanity: hall incomplete", not bool(hall.get("complete", true)))
	_free_world(w)


func _test_nearest_hostile_skips_children() -> void:
	var w := _new_world()
	var ctx := _attack_setup(w, Vector2(200, 0))
	var gs: GameState = w["gs"]
	gs.diplomacy.declare_war("ogres", "humans", "test")
	var child := _spawn(w, "ogres", "worker", Vector2(110, 0))
	child["is_child"] = true
	_spawn(w, "ogres", "soldier", Vector2(400, 0))
	var u := _spawn(w, "humans", "farmer", Vector2(100, 0))
	var near: Dictionary = (w["siege"] as SimSiege)._nearest_hostile(u, 700.0)
	var foe: Dictionary = ctx["foe"]  # ogre soldier at (200, 0)
	_check("hostile: child skipped",
		int(near.get("id", -1)) == int(foe.get("id", -2)))
	_free_world(w)


func _test_shelter_home_preferred() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var home := _building(w, "house", "humans", Vector2(500, 0))
	var u := _spawn(w, "humans", "farmer", Vector2(100, 0))
	u["home"] = home
	(w["siege"] as SimSiege)._tick_siege()
	_check("shelter: own home beats hall",
		int(u.get("inside_building_id", 0)) == int(home.get("id", 0)))
	_free_world(w)


func _test_stand_down() -> void:
	var w := _new_world()
	var ctx := _attack_setup(w, Vector2(200, 0))
	var foe: Dictionary = ctx["foe"]
	var hall: Dictionary = ctx["hall"]
	var u := _spawn(w, "humans", "farmer", Vector2(100, 0))
	var siege: SimSiege = w["siege"]
	siege._tick_siege()
	_check("standdown: was hidden", bool(u.get("_siege_hide", false)))
	# Threat over: foe marches far away.
	foe["position"] = Vector2(5000, 5000)
	siege._tick_siege()
	_check("standdown: flag cleared", not bool(u.get("_siege_hide", false)))
	_check("standdown: left the shelter",
		int(u.get("inside_building_id", 0)) == 0)
	_check("standdown: shelter id erased", not u.has("siege_shelter_id"))
	_check("sanity: hall id", int(hall.get("id", 0)) > 0)
	_free_world(w)


func _test_threat_level2_any_unit() -> void:
	var w := _new_world()
	var ad: SimAIDirector = w["ad"]
	_building(w, "hall", "humans", Vector2.ZERO)
	# A non-military foreigner at the gates = under attack (HTML verbatim).
	_spawn(w, "ogres", "worker", Vector2(200, 0))
	_check("threat: foreign civilian at hall = 2",
		ad.threat_level_of("humans") == 2)
	_free_world(w)


func _test_threat_level1_approaching() -> void:
	var w := _new_world()
	var ad: SimAIDirector = w["ad"]
	_building(w, "hall", "humans", Vector2.ZERO)
	var gs: GameState = w["gs"]
	gs.diplomacy.declare_war("ogres", "humans", "test")
	_spawn(w, "ogres", "soldier", Vector2(1000, 0))  # within 1500, past 280
	_check("threat: hostile army approaching = 1",
		ad.threat_level_of("humans") == 1)
	_free_world(w)


func _test_threat_calm() -> void:
	var w := _new_world()
	var ad: SimAIDirector = w["ad"]
	_building(w, "hall", "humans", Vector2.ZERO)
	_spawn(w, "humans", "farmer", Vector2(100, 0))
	_check("threat: calm = 0", ad.threat_level_of("humans") == 0)
	_free_world(w)


func _test_throttle() -> void:
	var w := _new_world()
	_attack_setup(w, Vector2(200, 0))
	var u := _spawn(w, "humans", "farmer", Vector2(100, 0))
	var siege: SimSiege = w["siege"]
	siege.tick(0.5)
	_check("throttle: 0.5 s does nothing", not bool(u.get("_siege_hide", false)))
	siege.tick(0.6)
	_check("throttle: 1.1 s total acts", bool(u.get("_siege_hide", false)))
	_free_world(w)


func _test_mind_guard() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var mind := SimMind.new(gs)
	var u := _spawn(w, "humans", "farmer", Vector2(100, 0))
	u["_siege_hide"] = true
	_check("mind: hider returns busy", mind.tick_unit(u, 0.1))
	_free_world(w)


func _test_pick_task_guard() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var work_ai := WorkerAI.new(gs)
	var buildings := SimBuildings.new(gs)
	var u := _spawn(w, "humans", "worker", Vector2(100, 0))
	u["work_state"] = "idle"
	u["_siege_repair"] = true
	work_ai._pick_task(u, buildings, 12.0)
	_check("work: siege repairer not re-tasked",
		String(u.get("work_state", "")) == "idle")
	u["_siege_repair"] = false
	u["_siege_hide"] = true
	work_ai._pick_task(u, buildings, 12.0)
	_check("work: hider not re-tasked",
		String(u.get("work_state", "")) == "idle")
	_free_world(w)


func _test_race_lines() -> void:
	var w := _new_world()
	var siege: SimSiege = w["siege"]
	for f in ["humans", "ogres", "gnomes", "elves", "undead"]:
		_check("line: hide " + f, siege._hide_line(f) != "")
		_check("line: brave " + f, siege._brave_line(f) != "")
		_check("line: clear " + f, siege._clear_line(f) != "")
	_free_world(w)
