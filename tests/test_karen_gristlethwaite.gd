extends SceneTree
## Cursing Gnomes — HOA Karen flesh-out tests (wake rapid-iteration
## 2026-10-07: "Karen Gristlethwaite, HOA President" — the Zorblax
## treatment for the thinnest named disaster).
##
## Covers: named identity (const + arrival headline flag + greeting),
## assault complaints (HP-drop detection, soldier-faction surcharge,
## town-fallback billing, throttle + rearm, non-refundable on slay),
## escalating citation fines (base range first, capped 3x deep in visit),
## citizen citations (fallback when none in range, fine range, shout
## discipline, escalation tally), ruler demands (shout + rearm),
## first-lien Gazette announcement, slain/departed TALLY ledger notes.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_karen_gristlethwaite.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []  # [unit_id, text] from bus.unit_said


func _initialize() -> void:
	print("=== Cursing Gnomes Karen Gristlethwaite tests ===")
	_test_consts()
	_test_arrival()
	_test_assault_complaint()
	_test_assault_bills_town()
	_test_escalation()
	_test_unit_citation()
	_test_demand()
	_test_first_lien_announced()
	_test_slain()
	_test_departed()
	_test_town_faction()
	_test_prev_hp()
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
	d.setup_bounds(Rect2(0, 0, 4000, 4000))
	_said.clear()
	gs.bus.unit_said.connect(_on_unit_said)
	return d


func _on_unit_said(unit_id: int, text: String) -> void:
	_said.append([unit_id, text])


func _add_building(gs: GameState, btype: String, faction: String,
		town_id: int, pos: Vector2) -> Dictionary:
	return gs.add_building({
		"faction": faction, "type": btype, "town_id": town_id,
		"position": pos, "alive": true, "complete": true,
	})


func _add_citizen(gs: GameState, faction: String, pos: Vector2,
		job: String = "worker", hp: float = 100.0) -> Dictionary:
	return gs.add_unit({
		"faction": faction, "job": job, "town_id": -1,
		"position": pos, "alive": true, "hp": hp, "max_hp": hp,
	})


func _spawn_karen(gs: GameState, d: DisasterSim) -> Dictionary:
	_add_building(gs, "hall", "humans", 1, Vector2(500, 500))
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	var u := d.spawn("hoa_karen", Vector2(100, 100))
	d._karen_pick_town(u)
	return u


func _notes(d: DisasterSim, u: Dictionary) -> Array:
	var log_id: int = int(u.get("disaster_log_id", -1))
	return d.dlog.summary(log_id).get("notes", [])


## ---- identity ------------------------------------------------------------


func _test_consts() -> void:
	_check("name const",
		DisasterSim.KAREN_NAME == "Karen Gristlethwaite")
	_check("arrive pool", not DisasterSim.KAREN_ARRIVE_LINES.is_empty())
	_check("assault pool", not DisasterSim.KAREN_ASSAULT_LINES.is_empty())
	_check("unit citation pool",
		not DisasterSim.KAREN_UNIT_CITATIONS.is_empty())
	_check("demand pool", not DisasterSim.KAREN_DEMAND_LINES.is_empty())
	_check("hall pool", not DisasterSim.KAREN_HALL_LINES.is_empty())


func _test_arrival() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_add_building(gs, "hall", "humans", 1, Vector2(500, 500))
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	_said.clear()
	var u := d.spawn("hoa_karen", Vector2(100, 100))
	d.tick(0.2)
	_check("arrival announced", bool(u.get("karen_announced", false)))
	var greeted := false
	for s in _said:
		if String(s[1]) in DisasterSim.KAREN_ARRIVE_LINES:
			greeted = true
	_check("arrival greeting", greeted)


## ---- assault complaints --------------------------------------------------


func _test_assault_complaint() -> void:
	var gs := _new_game(["humans", "elves"])
	var d := _new_disasters(gs)
	_add_building(gs, "hall", "humans", 1, Vector2(500, 500))
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	gs.resources.add_resource("elves", "gold", 1000.0, true)
	var u := d.spawn("hoa_karen", Vector2(100, 100))
	d.tick(0.2)  # picks town, arms karen_prev_hp at 700
	_check("no complaint undamaged",
		int(u.get("karen_complaints", -1)) == 0)
	_add_citizen(gs, "elves", Vector2(150, 100), "soldier", 100.0)
	u["hp"] = 650.0
	var before: float = gs.resources.get_amount("elves", "gold")
	_said.clear()
	d.tick(0.2)
	_check("complaint filed", int(u.get("karen_complaints", 0)) == 1)
	_check("assault fined soldier faction",
		absf(before - gs.resources.get_amount("elves", "gold") \
			- DisasterSim.KAREN_ASSAULT_FINE) < 0.01)
	var shouted := false
	for s in _said:
		if String(s[1]) in DisasterSim.KAREN_ASSAULT_LINES:
			shouted = true
	_check("assault shout", shouted)
	# Throttle: a second hit inside the cooldown files nothing.
	u["hp"] = 600.0
	d.tick(0.2)
	_check("complaint throttled", int(u.get("karen_complaints", 0)) == 1)
	# Cooldown expiry rearms the paperwork.
	u["karen_complaint_cd"] = 0.0
	u["hp"] = 550.0
	d.tick(0.2)
	_check("complaint rearms after cd",
		int(u.get("karen_complaints", 0)) == 2)


func _test_assault_bills_town() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_karen(gs, d)
	d.tick(0.2)
	u["hp"] = 650.0  # no soldiers anywhere — she bills the town
	var before: float = gs.resources.get_amount("humans", "gold")
	d.tick(0.2)
	_check("town billed for assault",
		absf(before - gs.resources.get_amount("humans", "gold") \
			- DisasterSim.KAREN_ASSAULT_FINE) < 0.01)


## ---- escalation ----------------------------------------------------------


func _test_escalation() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_karen(gs, d)
	# First citation of the visit uses the base range.
	var b0: float = gs.resources.get_amount("humans", "gold")
	d._karen_issue_citation(u)
	var f0: float = b0 - gs.resources.get_amount("humans", "gold")
	_check("first citation base range", f0 >= 14.99 and f0 <= 40.01)
	_check("cite_total increments", int(u.get("karen_cite_total", 0)) == 1)
	# Deep into the visit the repeat-offender multiplier caps at 3x.
	u["karen_cite_total"] = 20
	var b1: float = gs.resources.get_amount("humans", "gold")
	d._karen_issue_citation(u)
	var f1: float = b1 - gs.resources.get_amount("humans", "gold")
	_check("escalated fine capped 3x", f1 >= 44.99 and f1 <= 120.01)


## ---- citizen citations ---------------------------------------------------


func _test_unit_citation() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_karen(gs, d)
	_check("unit citation false with no citizens",
		not d._karen_issue_unit_citation(u))
	_add_citizen(gs, "humans", Vector2(520, 500), "worker", 100.0)
	var before: float = gs.resources.get_amount("humans", "gold")
	_said.clear()
	var ok: bool = d._karen_issue_unit_citation(u)
	var fine: float = before - gs.resources.get_amount("humans", "gold")
	_check("unit citation fires", ok)
	_check("unit fine in range", fine >= 4.99 and fine <= 15.01)
	_check("unit fine tracked",
		absf(float(u.get("karen_fines", {}).get("humans", 0.0)) \
			- fine) < 0.01)
	_check("unit citation counts to escalation",
		int(u.get("karen_cite_total", 0)) == 1)
	_check("unit citation shouts once with fine",
		_said.size() == 1 and String(_said[0][1]).contains("fine"))


## ---- demands -------------------------------------------------------------


func _test_demand() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_karen(gs, d)
	d.tick(0.2)
	_said.clear()
	u["karen_demand_cd"] = 0.05
	d.tick(0.1)
	var demanded := false
	for s in _said:
		if String(s[1]) in DisasterSim.KAREN_DEMAND_LINES:
			demanded = true
	_check("demand shout", demanded)
	_check("demand rearms",
		absf(float(u.get("karen_demand_cd", 0.0)) \
			- DisasterSim.KAREN_DEMAND_INTERVAL) < 0.01)


## ---- first lien ----------------------------------------------------------


func _test_first_lien_announced() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_karen(gs, d)
	_check("not announced before lien",
		not bool(u.get("karen_lien_announced", false)))
	d._karen_issue_citation(u)
	d._karen_issue_citation(u)
	d._karen_issue_citation(u)  # 3rd -> lien on the lone hall
	_check("first lien announced",
		bool(u.get("karen_lien_announced", false)))
	# The hall citation uses the hall line pool (still exactly one shout).
	var hall_shouted := false
	for s in _said:
		for line in DisasterSim.KAREN_HALL_LINES:
			if String(s[1]).begins_with(line):
				hall_shouted = true
	_check("hall citation uses hall line", hall_shouted)


## ---- slain / departed -----------------------------------------------------


func _test_slain() -> void:
	var gs := _new_game(["humans", "elves"])
	var d := _new_disasters(gs)
	_add_building(gs, "hall", "humans", 1, Vector2(500, 500))
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	gs.resources.add_resource("elves", "gold", 1000.0, true)
	var u := d.spawn("hoa_karen", Vector2(100, 100))
	d._karen_pick_town(u)
	d._karen_issue_citation(u)  # citation fine on humans
	var humans_after_cite: float = \
		gs.resources.get_amount("humans", "gold")
	_add_citizen(gs, "elves", Vector2(120, 100), "soldier", 100.0)
	d._karen_assault_complaint(u)  # $25 surcharge on elves
	var elves_after_assault: float = \
		gs.resources.get_amount("elves", "gold")
	d._karen_slain(u)
	_check("citation fines refunded",
		gs.resources.get_amount("humans", "gold") \
			> humans_after_cite - 0.01)
	_check("assault surcharge NOT refunded",
		absf(gs.resources.get_amount("elves", "gold") \
			- elves_after_assault) < 0.01)
	var tally := false
	for n in _notes(d, u):
		if String(n).begins_with("TALLY"):
			tally = true
	_check("slain tally note", tally)


func _test_departed() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_karen(gs, d)
	d._karen_issue_citation(u)
	var after_cite: float = gs.resources.get_amount("humans", "gold")
	d._karen_departed(u)
	_check("departed keeps fines",
		absf(gs.resources.get_amount("humans", "gold") - after_cite) \
			< 0.01)
	var tally := false
	for n in _notes(d, u):
		var ns := String(n)
		if ns.begins_with("TALLY") and ns.contains("no refund"):
			tally = true
	_check("departed tally note", tally)


## ---- misc ----------------------------------------------------------------


func _test_town_faction() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_karen(gs, d)
	_check("town faction", d._karen_town_faction(u) == "humans")


func _test_prev_hp() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_karen(gs, d)
	d.tick(0.2)
	_check("prev_hp tracked",
		absf(float(u.get("karen_prev_hp", -1.0)) \
			- float(u.get("hp", 0.0))) < 0.01)
