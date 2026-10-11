extends SceneTree
## Cursing Gnomes — Bill the Borg Crab disaster tests (wake 2026-10-08:
## borg_crab_bill).
##
## Covers: singleton rule, label, nearest-town targeting, arrival story
## flag, building assimilation (borg_upgraded flag, -15% efficiency via
## borg_building_mult, occupant complaints), soldier drive-off (upgrades
## ejected, fled note, ledger closed), slain (upgrades ejected,
## DE-ASSIMILATED story, ledger closed), budget expiry ("finished
## helping" — upgrades stay), and the no-town edge case.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_borg_crab_bill.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Borg Crab Bill tests ===")
	_test_singleton_and_label()
	_test_picks_nearest_town()
	_test_assimilate_building()
	_test_efficiency_penalty()
	_test_occupant_complaints()
	_test_flees_from_soldiers_ejects()
	_test_slain_ejects_upgrades()
	_test_budget_keeps_upgrades()
	_test_no_town_no_crash()
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


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	return gs


func _new_disasters(gs: GameState) -> DisasterSim:
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	gs.disasters = d
	return d


func _add_town(gs: GameState, tid: int, faction: String, pos: Vector2) -> void:
	gs.towns[tid] = {"id": tid, "faction": faction, "name": "T%d" % tid,
		"position": pos}


func _add_citizen(gs: GameState, faction: String, tid: int,
		pos: Vector2, job: String = "worker") -> Dictionary:
	var u: Dictionary = gs.add_unit({
		"faction": faction, "job": job, "town_id": tid,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"stress": 10.0,
	})
	return u


func _add_building(gs: GameState, bid: int, btype: String, faction: String,
		pos: Vector2) -> void:
	gs.buildings.append({"id": bid, "type": btype, "name": btype,
		"alive": true, "complete": true, "position": pos,
		"faction": faction})


func _new_borg_world() -> Array:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	# Two towns: 100 is near (500,500), 200 is far (4000,4000).
	_add_town(gs, 100, "humans", Vector2(500, 500))
	_add_town(gs, 200, "humans", Vector2(4000, 4000))
	_add_building(gs, 1001, "farm", "humans", Vector2(520, 520))
	_add_building(gs, 1002, "town_hall", "humans", Vector2(560, 480))
	return [gs, d]


func _test_singleton_and_label() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var a: Dictionary = d.spawn("borg_crab_bill", Vector2(500, 500))
	_check("borg: spawns", not a.is_empty())
	_check("borg: label", d._label_for("borg_crab_bill") == "Bill the Borg Crab")
	_check("borg: log opened", int(a.get("disaster_log_id", -1)) > 0)
	var b: Dictionary = d.spawn("borg_crab_bill", Vector2(600, 600))
	_check("borg: singleton (second refused)", b.is_empty())


func _test_picks_nearest_town() -> void:
	var parts: Array = _new_borg_world()
	var d: DisasterSim = parts[1]
	# Spawn right next to town 100 — Bill scuttles to the NEAREST town.
	var u: Dictionary = d.spawn("borg_crab_bill", Vector2(100, 100))
	d.tick(0.2)  # first tick: pick town + announce
	var center: Vector2 = u.get("borg_center", Vector2(-1, -1))
	_check("borg: targets nearest town (100)",
		center.distance_to(Vector2(500, 500)) < 1.0)
	_check("borg: arrival story announced",
		bool(u.get("borg_announced", false)))
	_check("borg: town name recorded",
		String(u.get("borg_town_name", "")) == "T100")


func _test_assimilate_building() -> void:
	var parts: Array = _new_borg_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("borg_crab_bill", Vector2(100, 100))
	d.tick(0.2)
	# Park Bill next to the farm; force the assimilate timer to fire.
	u["position"] = Vector2(520, 540)
	u["borg_cd"] = 0.0
	d.tick(0.2)
	var farm: Dictionary = gs.buildings[0]
	_check("borg: farm assimilated (borg_upgraded)",
		bool(farm.get("borg_upgraded", false)))
	_check("borg: upgrade counted",
		int(u.get("borg_upgrades", 0)) == 1)
	_check("borg: first-upgrade Gazette story",
		bool(u.get("borg_first_upgrade_story", false)))
	# Second building stays clean until the next cooldown.
	_check("borg: town hall untouched",
		not bool(gs.buildings[1].get("borg_upgraded", false)))


func _test_efficiency_penalty() -> void:
	_check("borg: clean building = 1.0x",
		is_equal_approx(DisasterSim.borg_building_mult({}), 1.0))
	_check("borg: assimilated building = 0.85x",
		is_equal_approx(
			DisasterSim.borg_building_mult({"borg_upgraded": true}), 0.85))


func _test_occupant_complaints() -> void:
	var parts: Array = _new_borg_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("borg_crab_bill", Vector2(100, 100))
	d.tick(0.2)
	u["position"] = Vector2(520, 540)
	var w: Dictionary = _add_citizen(gs, "humans", 100, Vector2(525, 545))
	_check("borg: citizen starts calm",
		float(w.get("stress", -1.0)) == 10.0)
	u["borg_cd"] = 0.0
	d.tick(0.2)  # assimilate -> complaints
	_check("borg: nearby citizen stressed by upgrade (%.1f)"
		% float(w.get("stress", 0.0)),
		float(w.get("stress", 0.0)) > 10.0)


func _test_flees_from_soldiers_ejects() -> void:
	var parts: Array = _new_borg_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("borg_crab_bill", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	# Assimilate first so there's something to eject.
	u["position"] = Vector2(520, 540)
	u["borg_cd"] = 0.0
	d.tick(0.2)
	_check("borg: upgrade in place before flee",
		bool(gs.buildings[0].get("borg_upgraded", false)))
	# A soldier closes in.
	_add_citizen(gs, "humans", 100, Vector2(530, 545), "soldier")
	d.tick(0.2)
	_check("borg: fled flag", bool(u.get("borg_fled", false)))
	_check("borg: leaving", bool(u.get("leaving", false)))
	_check("borg: upgrades ejected on flee",
		not bool(gs.buildings[0].get("borg_upgraded", false)))
	_check("borg: fled story announced",
		bool(u.get("borg_fled_story", false)))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("borg: flee closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).find("fled") >= 0:
			saw = true
	_check("borg: 'fled' note filed", saw)


func _test_slain_ejects_upgrades() -> void:
	var parts: Array = _new_borg_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("borg_crab_bill", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["position"] = Vector2(520, 540)
	u["borg_cd"] = 0.0
	d.tick(0.2)
	_check("borg: upgrade in place before slaying",
		bool(gs.buildings[0].get("borg_upgraded", false)))
	u["alive"] = false
	d.tick(0.3)
	_check("borg: upgrades ejected on slain",
		not bool(gs.buildings[0].get("borg_upgraded", false)))
	_check("borg: DE-ASSIMILATED story",
		bool(u.get("borg_slain_story", false)))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("borg: slain closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).find("slain") >= 0:
			saw = true
	_check("borg: 'slain' note filed", saw)


func _test_budget_keeps_upgrades() -> void:
	var parts: Array = _new_borg_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("borg_crab_bill", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["position"] = Vector2(520, 540)
	u["borg_cd"] = 0.0
	d.tick(0.2)
	u["age"] = 99999.0  # budget spent: he finished "helping"
	d.tick(0.2)
	_check("borg: leaving after budget", bool(u.get("leaving", false)))
	_check("borg: finished-helping story",
		bool(u.get("borg_done_story", false)))
	# Budget path: he leaves the toasters behind (nobody pried them off).
	_check("borg: upgrades REMAIN after budget expiry",
		bool(gs.buildings[0].get("borg_upgraded", false)))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("borg: budget closes ledger",
		String(rec.get("status", "")) != "active")


func _test_no_town_no_crash() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("borg_crab_bill", Vector2(100, 100))
	d.tick(0.5)
	_check("borg: no towns -> scuttles at spawn, no crash",
		not u.is_empty() and bool(u.get("borg_announced", false)))
	# No buildings to assimilate: the cooldown must not crash.
	u["borg_cd"] = 0.0
	d.tick(0.5)
	_check("borg: no buildings -> no crash, no phantom upgrades",
		int(u.get("borg_upgrades", 0)) == 0)
