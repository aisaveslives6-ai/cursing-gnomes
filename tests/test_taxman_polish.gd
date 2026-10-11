extends SceneTree
## Cursing Gnomes — Taxman "Full Audit" polish tests (deep-work lane 2026-10-09).
##
## Covers: aura consts sane, line pools non-empty + U+FE0F-free, arrival voice
## on first tick, audit-dread aura builds stress in radius (skips out-of-range
## / monster / indoor), dread barks fire past the stress threshold on cooldown,
## audit count tracks, slain relief burst + TALLY ledger, departure voice +
## ledger, slain dispatcher routes to _taxman_slain, GARNISHED note format
## preserved for the Gazette summary parser.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_taxman_polish.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []  # [unit_id, text] from bus.unit_said


func _initialize() -> void:
	print("=== Cursing Gnomes Taxman polish tests ===")
	_test_consts()
	_test_line_pools()
	_test_arrival_voice()
	_test_dread_aura_builds()
	_test_dread_aura_skips()
	_test_dread_bark()
	_test_audit_count()
	_test_slain_relief_and_ledger()
	_test_departed_voice_and_ledger()
	_test_slain_dispatcher()
	_test_garnished_format()
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


func _add_citizen(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_unit({
		"faction": faction, "job": "worker", "town_id": -1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
	})


func _spawn_taxman(gs: GameState, d: DisasterSim, pos: Vector2) -> Dictionary:
	_add_building(gs, "hall", "humans", 1, Vector2(500, 500))
	return d.spawn("taxman", pos)


func _plant(d: DisasterSim, u: Dictionary) -> void:
	# Pin the taxman at his own position so the planted branch runs.
	u["tax_hall_pos"] = u.get("position", Vector2.ZERO)
	d._tick_taxman(u, 70.0, 0.01)


func _said_texts() -> Array[String]:
	var out: Array[String] = []
	for s in _said:
		out.append(String(s[1]))
	return out


func _notes(d: DisasterSim, u: Dictionary) -> Array:
	var log_id: int = int(u.get("disaster_log_id", -1))
	if log_id < 0:
		return []
	return d.dlog.summary(log_id).get("notes", [])


## ---- consts --------------------------------------------------------------


func _test_consts() -> void:
	_check("dread radius positive", DisasterSim.TAXMAN_DREAD_RADIUS > 0.0)
	_check("dread rate positive", DisasterSim.TAXMAN_DREAD_RATE > 0.0)
	_check("bark threshold sane",
		DisasterSim.TAXMAN_DREAD_BARK_AT > 0.0 \
		and DisasterSim.TAXMAN_DREAD_BARK_AT <= 100.0)
	_check("bark cd positive", DisasterSim.TAXMAN_DREAD_BARK_CD > 0.0)
	_check("relief radius covers aura",
		DisasterSim.TAXMAN_RELIEF_RADIUS >= DisasterSim.TAXMAN_DREAD_RADIUS)
	_check("relief amount positive", DisasterSim.TAXMAN_RELIEF_STRESS > 0.0)


func _test_line_pools() -> void:
	_check("audit lines >= 10", DisasterSim.TAXMAN_LINES.size() >= 10)
	_check("arrive lines non-empty", DisasterSim.TAXMAN_ARRIVE_LINES.size() > 0)
	_check("depart lines non-empty", DisasterSim.TAXMAN_DEPART_LINES.size() > 0)
	_check("dread bursts non-empty", DisasterSim.TAXMAN_DREAD_BURSTS.size() > 0)
	var pools: Array = [
		DisasterSim.TAXMAN_LINES, DisasterSim.TAXMAN_ARRIVE_LINES,
		DisasterSim.TAXMAN_DEPART_LINES, DisasterSim.TAXMAN_DREAD_BURSTS,
	]
	var clean := true
	for pool in pools:
		for line in pool:
			var s := String(line)
			if s.is_empty() or s.find("﻿") >= 0:
				clean = false
	_check("all lines non-empty and U+FE0F-free", clean)


## ---- arrival -------------------------------------------------------------


func _test_arrival_voice() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_taxman(gs, d, Vector2(100, 100))
	_check("spawned", not u.is_empty())
	_said.clear()
	# First tick: no tax_hall_pos yet -> pick target + announce + greet.
	d._tick_taxman(u, 70.0, 0.1)
	_check("greeted flag set", bool(u.get("tax_greeted", false)))
	var texts := _said_texts()
	var arrived := false
	for t in texts:
		if DisasterSim.TAXMAN_ARRIVE_LINES.has(t):
			arrived = true
	_check("arrival line spoken", arrived)
	_said.clear()
	d._tick_taxman(u, 70.0, 0.1)
	_check("greeting fires once", _said.is_empty())


## ---- dread aura -----------------------------------------------------------


func _test_dread_aura_builds() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_taxman(gs, d, Vector2(500, 500))
	_plant(d, u)
	var c := _add_citizen(gs, "humans", Vector2(520, 500))
	c["stress"] = 0.0
	_said.clear()
	d._tick_taxman(u, 70.0, 1.0)
	var stress: float = float(c.get("stress", 0.0))
	_check("stress builds in radius",
		stress >= DisasterSim.TAXMAN_DREAD_RATE * 0.9)
	_check("stress capped at 100", stress <= 100.0)


func _test_dread_aura_skips() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_taxman(gs, d, Vector2(500, 500))
	_plant(d, u)
	var far := _add_citizen(gs, "humans", Vector2(2000, 2000))
	far["stress"] = 0.0
	var mon := gs.add_unit({
		"faction": "monster", "job": "bandit", "town_id": -1,
		"position": Vector2(510, 500), "alive": true,
		"hp": 100.0, "max_hp": 100.0,
	})
	mon["stress"] = 0.0
	var indoor := _add_citizen(gs, "humans", Vector2(515, 500))
	indoor["stress"] = 0.0
	indoor["inside_building_id"] = 7
	d._tick_taxman(u, 70.0, 1.0)
	_check("far citizen untouched", float(far.get("stress", -1.0)) == 0.0)
	_check("monster untouched", float(mon.get("stress", -1.0)) == 0.0)
	_check("indoor citizen untouched", float(indoor.get("stress", -1.0)) == 0.0)


func _test_dread_bark() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_taxman(gs, d, Vector2(500, 500))
	_plant(d, u)
	var c := _add_citizen(gs, "humans", Vector2(520, 500))
	c["stress"] = 90.0  # past the bark threshold
	c["tax_bark_cd"] = 0.0
	_said.clear()
	d._tick_taxman(u, 70.0, 0.5)
	var texts := _said_texts()
	var barked := false
	for t in texts:
		if DisasterSim.TAXMAN_DREAD_BURSTS.has(t):
			barked = true
	_check("stressed citizen complains", barked)
	_check("bark cooldown armed", float(c.get("tax_bark_cd", 0.0)) > 0.0)
	# Calm citizen stays quiet.
	var calm := _add_citizen(gs, "humans", Vector2(525, 505))
	calm["stress"] = 0.0
	_said.clear()
	d._tick_taxman(u, 70.0, 0.5)
	var calm_barked := false
	for s in _said:
		if int(s[0]) == int(calm.get("id", -1)) \
				and DisasterSim.TAXMAN_DREAD_BURSTS.has(String(s[1])):
			calm_barked = true
	_check("calm citizen stays quiet", not calm_barked)


## ---- audit ---------------------------------------------------------------


func _test_audit_count() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_taxman(gs, d, Vector2(500, 500))
	u["tax_faction"] = "humans"
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	var before: float = float(u.get("tax_audits", 0))
	d._taxman_audit(u)
	_check("audit count increments", int(u.get("tax_audits", 0)) == int(before) + 1)
	_check("gold garnished", float(u.get("tax_collected", 0.0)) > 0.0)


## ---- slain / departed ------------------------------------------------------


func _test_slain_relief_and_ledger() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_taxman(gs, d, Vector2(500, 500))
	var c := _add_citizen(gs, "humans", Vector2(520, 500))
	c["stress"] = 80.0
	u["tax_collected"] = 120.0
	u["tax_audits"] = 3
	d._taxman_slain(u)
	_check("relief burst wipes stress",
		float(c.get("stress", -1.0)) <= 80.0 - DisasterSim.TAXMAN_RELIEF_STRESS + 0.01)
	var notes := _notes(d, u)
	var has_garnished := false
	var has_tally := false
	for n in notes:
		var ns := String(n)
		if ns.begins_with("GARNISHED"):
			has_garnished = true
		if ns.begins_with("TALLY"):
			has_tally = true
			_check("tally counts audits", ns.find("3 audits") >= 0)
	_check("GARNISHED note filed", has_garnished)
	_check("TALLY note filed", has_tally)


func _test_departed_voice_and_ledger() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_taxman(gs, d, Vector2(500, 500))
	u["tax_collected"] = 200.0
	u["tax_audits"] = 5
	_said.clear()
	d._taxman_departed(u)
	var texts := _said_texts()
	var departed := false
	for t in texts:
		if DisasterSim.TAXMAN_DEPART_LINES.has(t):
			departed = true
	_check("departure line spoken", departed)
	var notes := _notes(d, u)
	var has_tally := false
	for n in notes:
		if String(n).begins_with("TALLY"):
			has_tally = true
	_check("departure files TALLY", has_tally)


func _test_slain_dispatcher() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_taxman(gs, d, Vector2(500, 500))
	var c := _add_citizen(gs, "humans", Vector2(520, 500))
	c["stress"] = 70.0
	u["alive"] = false  # slain by soldiers
	d._check_dead_disaster(u)
	_check("dispatcher routes slain to relief",
		float(c.get("stress", -1.0)) <= 70.0 - DisasterSim.TAXMAN_RELIEF_STRESS + 0.01)


func _test_garnished_format() -> void:
	# The Gazette summary parser reads "GARNISHED <n> gold" — keep it stable.
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_taxman(gs, d, Vector2(500, 500))
	u["tax_collected"] = 321.0
	u["tax_audits"] = 2
	d._taxman_close_ledger(u)
	var notes := _notes(d, u)
	var ok := false
	for n in notes:
		if String(n) == "GARNISHED 321 gold":
			ok = true
	_check("GARNISHED note format stable", ok)
