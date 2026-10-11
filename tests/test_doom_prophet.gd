extends SceneTree
## Cursing Gnomes — Doom Prophet disaster tests (wake rapid-iteration
## 2026-10-07: doom_prophet).
##
## Covers: singleton rule, label, most-populous-town targeting, arrival
## story flag, doom-preach stress aura, coward's flee from soldiers
## (ledger closed, "fled screaming" note), budget expiry -> shame-leave
## ("DOOMSDAY POSTPONED" story), slain -> ledger closed with DOOMED note,
## and the no-town edge case (no crash, no dead end).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_doom_prophet.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Doom Prophet tests ===")
	_test_singleton_and_label()
	_test_picks_most_populous_town()
	_test_preach_stress_aura()
	_test_flees_from_soldiers()
	_test_budget_shame_leave()
	_test_slain_closes_ledger()
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


func _new_prophet_world() -> Array:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_add_town(gs, 100, "humans", Vector2(1000, 1000))
	_add_town(gs, 200, "humans", Vector2(3000, 3000))
	# Town 100 is the populous one: 5 citizens. Town 200: 1 citizen.
	for i in 5:
		_add_citizen(gs, "humans", 100, Vector2(1000 + i * 10, 1000))
	_add_citizen(gs, "humans", 200, Vector2(3000, 3000))
	return [gs, d]


func _test_singleton_and_label() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var a: Dictionary = d.spawn("doom_prophet", Vector2(500, 500))
	_check("prophet: spawns", not a.is_empty())
	_check("prophet: label", d._label_for("doom_prophet") == "Doom Prophet")
	_check("prophet: log opened", int(a.get("disaster_log_id", -1)) > 0)
	var b: Dictionary = d.spawn("doom_prophet", Vector2(600, 600))
	_check("prophet: singleton (second refused)", b.is_empty())


func _test_picks_most_populous_town() -> void:
	var parts: Array = _new_prophet_world()
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("doom_prophet", Vector2(100, 100))
	d.tick(0.2)  # first tick: pick town + announce
	var center: Vector2 = u.get("prophet_center", Vector2(-1, -1))
	_check("prophet: targets most populous town (100)",
		center.distance_to(Vector2(1000, 1000)) < 1.0)
	_check("prophet: arrival story announced",
		bool(u.get("prophet_announced", false)))
	_check("prophet: town name recorded",
		String(u.get("prophet_town_name", "")) == "T100")


func _test_preach_stress_aura() -> void:
	var parts: Array = _new_prophet_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("doom_prophet", Vector2(100, 100))
	d.tick(0.2)
	# Park the prophet in the plaza; a calm citizen stands next to him.
	u["position"] = Vector2(1000, 1000)
	var w: Dictionary = _add_citizen(gs, "humans", 100, Vector2(1010, 1000))
	_check("prophet: citizen starts calm",
		float(w.get("stress", -1.0)) == 10.0)
	d.tick(1.0)
	_check("prophet: preaching state",
		String(u.get("combat_state", "")) == "preaching")
	_check("prophet: dread stresses citizens (%.1f)" % float(w.get("stress", 0.0)),
		float(w.get("stress", 0.0)) > 10.0)
	_check("prophet: dread never exceeds 100",
		float(w.get("stress", 0.0)) <= 100.0)
	_check("prophet: doom tracked",
		float(u.get("prophet_doomed", 0.0)) > 0.0)


func _test_flees_from_soldiers() -> void:
	var parts: Array = _new_prophet_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("doom_prophet", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	# A soldier closes in before the first tick finishes targeting.
	_add_citizen(gs, "humans", 100, Vector2(150, 120), "soldier")
	d.tick(0.2)
	_check("prophet: fled flag", bool(u.get("prophet_fled", false)))
	_check("prophet: leaving", bool(u.get("leaving", false)))
	_check("prophet: fled story announced",
		bool(u.get("prophet_fled_story", false)))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("prophet: flee closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).find("fled screaming") >= 0:
			saw = true
	_check("prophet: 'fled screaming' note filed", saw)


func _test_budget_shame_leave() -> void:
	var parts: Array = _new_prophet_world()
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("doom_prophet", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["age"] = 99999.0  # doomsday came and went, uneventfully
	d.tick(0.2)
	_check("prophet: leaving after budget", bool(u.get("leaving", false)))
	_check("prophet: DOOMSDAY POSTPONED story",
		bool(u.get("prophet_shame_story", false)))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("prophet: shame closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).find("doomsday postponed") >= 0:
			saw = true
	_check("prophet: 'doomsday postponed' note filed", saw)


func _test_slain_closes_ledger() -> void:
	var parts: Array = _new_prophet_world()
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("doom_prophet", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["alive"] = false
	d.tick(0.3)
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("prophet: slain closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).begins_with("DOOMED"):
			saw = true
	_check("prophet: DOOMED note filed", saw)


func _test_no_town_no_crash() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("doom_prophet", Vector2(100, 100))
	d.tick(0.5)
	_check("prophet: no towns -> preaches at spawn, no crash",
		not u.is_empty() and bool(u.get("prophet_announced", false)))
