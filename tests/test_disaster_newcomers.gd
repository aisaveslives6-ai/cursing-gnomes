extends SceneTree
## Cursing Gnomes — newcomer disaster tests (Jeremy 2026-10-07 wake
## deep-disasters: seagull_swarm, taxman, booze_ooze).
##
## Covers: singleton rule, log records, seagull food theft + crap aura,
## taxman richest-faction targeting + treasury garnish (+ broke-faction
## tut, no negative gold), ooze stress relief + town hopping, budget
## expiry -> leaving -> ledger closed, slain -> ledger closed with notes,
## labels, and no-town/no-gold edge cases (no crashes, no dead ends).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_disaster_newcomers.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes newcomer disaster tests ===")
	_test_singletons()
	_test_labels()
	_test_seagull_theft()
	_test_seagull_crap()
	_test_seagull_no_town()
	_test_seagull_leaves_and_closes()
	_test_seagull_slain_note()
	_test_taxman_targets_richest()
	_test_taxman_audit()
	_test_taxman_broke_tut()
	_test_taxman_slain_note()
	_test_ooze_stress_relief()
	_test_ooze_town_hop()
	_test_ooze_leaves_and_closes()
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


func _add_bldg(gs: GameState, btype: String, faction: String, tid: int,
		pos: Vector2) -> Dictionary:
	return gs.add_building({
		"type": btype, "faction": faction, "town_id": tid,
		"position": pos, "alive": true, "hp": 500.0, "complete": true,
	})


func _add_unit(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_unit({
		"faction": faction, "job": "worker", "town_id": -1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"stress": 80.0,
	})


## ---- singletons + labels ---------------------------------------------------


func _test_singletons() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	for kind in ["seagull_swarm", "taxman", "booze_ooze"]:
		var a: Dictionary = d.spawn(kind, Vector2(500, 500))
		_check(kind + ": spawns", not a.is_empty())
		var b: Dictionary = d.spawn(kind, Vector2(600, 600))
		_check(kind + ": singleton (second refused)", b.is_empty())
	# A third spawn of an already-live kind is still refused.
	var c: Dictionary = d.spawn("taxman", Vector2(700, 700))
	_check("taxman: still singleton after others", c.is_empty())


func _test_labels() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_check("label gulls", d._label_for("seagull_swarm") == "Seagull Swarm")
	_check("label taxman", d._label_for("taxman") == "The Taxman")
	_check("label ooze", d._label_for("booze_ooze") == "Booze Ooze")


## ---- seagulls ---------------------------------------------------------------


func _new_gull_world() -> Array:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_add_town(gs, 100, "humans", Vector2(1000, 1000))
	_add_bldg(gs, "town_hall", "humans", 100, Vector2(1000, 1000))
	_add_bldg(gs, "farm", "humans", 100, Vector2(1100, 1000))
	_add_bldg(gs, "fishing_hut", "humans", 100, Vector2(900, 1000))
	gs.resources.add_resource("humans", "food", 500.0)
	return [gs, d]


func _test_seagull_theft() -> void:
	var parts: Array = _new_gull_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("seagull_swarm", Vector2(100, 100))
	_check("gulls: log opened",
		int(u.get("disaster_log_id", -1)) > 0)
	d.tick(0.2)  # first tick: pick town + announce
	_check("gulls: town picked", int(u.get("gull_town", -1)) == 100)
	_check("gulls: faction picked",
		String(u.get("gull_faction", "")) == "humans")
	u["steal_cd"] = 0.01
	var before: float = gs.resources.get_amount("humans", "food")
	d.tick(0.2)
	var after: float = gs.resources.get_amount("humans", "food")
	_check("gulls: food stolen (%.0f -> %.0f)" % [before, after],
		after < before)
	_check("gulls: theft tracked", float(u.get("gull_stolen", 0.0)) > 0.0)
	_check("gulls: food never negative", after >= 0.0)


func _test_seagull_crap() -> void:
	var parts: Array = _new_gull_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("seagull_swarm", Vector2(100, 100))
	d.tick(0.2)
	# Force several thefts (50% crap chance each), then park a citizen
	# next to whichever building got crapped.
	var crapped_b: Dictionary = {}
	for i in 12:
		u["steal_cd"] = 0.01
		d.tick(0.2)
		for b: Dictionary in gs.buildings:
			if float(b.get("seagull_crap_t", 0.0)) > 0.0:
				crapped_b = b
				break
		if not crapped_b.is_empty():
			break
	_check("gulls: some building got crapped", not crapped_b.is_empty())
	# Crap aura stresses nearby citizens.
	var w: Dictionary = _add_unit(gs, "humans",
		crapped_b.get("position", Vector2(1000, 1000)))
	w["town_id"] = 100
	w["stress"] = 10.0
	d.tick(1.0)
	_check("gulls: crap aura stresses (%.1f)" % float(w.get("stress", 0.0)),
		float(w.get("stress", 0.0)) > 10.0)


func _test_seagull_no_town() -> void:
	# No towns at all: no crash, squawks anyway, no theft.
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("seagull_swarm", Vector2(500, 500))
	_check("gulls: spawns with no towns", not u.is_empty())
	d.tick(0.5)
	_check("gulls: no crash without towns", bool(u.get("alive", false)))
	u["steal_cd"] = 0.01
	d.tick(0.5)
	_check("gulls: nothing stolen with no faction",
		float(u.get("gull_stolen", 0.0)) == 0.0)


func _test_seagull_leaves_and_closes() -> void:
	var parts: Array = _new_gull_world()
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("seagull_swarm", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["steal_cd"] = 0.01
	d.tick(0.2)
	u["age"] = 99999.0
	d.tick(0.2)
	_check("gulls: leaving flag", bool(u.get("leaving", false)))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("gulls: ledger closed",
		String(rec.get("status", "")) != "active")
	var notes: Array = rec.get("notes", [])
	var saw := false
	for n in notes:
		if String(n).begins_with("STOLEN"):
			saw = true
	_check("gulls: STOLEN note filed", saw)


func _test_seagull_slain_note() -> void:
	var parts: Array = _new_gull_world()
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("seagull_swarm", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["steal_cd"] = 0.01
	d.tick(0.2)
	u["alive"] = false
	d.tick(0.3)  # cache tick sees the corpse -> _check_dead_disaster
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("gulls: slain closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).begins_with("STOLEN"):
			saw = true
	_check("gulls: slain still files STOLEN note", saw)


## ---- taxman -----------------------------------------------------------------


func _new_tax_world() -> Array:
	var gs := _new_game(["humans", "ogres"])
	var d := _new_disasters(gs)
	_add_town(gs, 100, "humans", Vector2(1000, 1000))
	_add_bldg(gs, "town_hall", "humans", 100, Vector2(1000, 1000))
	_add_town(gs, 200, "ogres", Vector2(3000, 3000))
	_add_bldg(gs, "town_hall", "ogres", 200, Vector2(3000, 3000))
	gs.resources.add_resource("humans", "gold", 1000.0)
	gs.resources.add_resource("ogres", "gold", 100.0)
	return [gs, d]


func _test_taxman_targets_richest() -> void:
	var parts: Array = _new_tax_world()
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("taxman", Vector2(50, 50))
	d.tick(0.2)
	_check("taxman: targets richest faction",
		String(u.get("tax_faction", "")) == "humans")
	var hp: Vector2 = u.get("tax_hall_pos", Vector2.ZERO)
	_check("taxman: hall found (%.0f, %.0f)" % [hp.x, hp.y],
		hp.distance_to(Vector2(1000, 1000)) < 200.0)


func _test_taxman_audit() -> void:
	var parts: Array = _new_tax_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("taxman", Vector2(50, 50))
	d.tick(0.2)
	# Plant him at the hall so he audits instead of marching.
	u["position"] = Vector2(1000, 1000)
	u["audit_cd"] = 0.01
	var before: float = gs.resources.get_amount("humans", "gold")
	d.tick(0.2)
	var after: float = gs.resources.get_amount("humans", "gold")
	var expect: float = before - clampf(before * 0.08, 10.0, 250.0)
	_check("taxman: garnished 8%% (%.0f -> %.0f)" % [before, after],
		absf(after - expect) < 1.0)
	_check("taxman: collection tracked",
		float(u.get("tax_collected", 0.0)) > 0.0)
	_check("taxman: auditing state",
		String(u.get("combat_state", "")) == "auditing")


func _test_taxman_broke_tut() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_add_town(gs, 100, "humans", Vector2(1000, 1000))
	_add_bldg(gs, "town_hall", "humans", 100, Vector2(1000, 1000))
	# Zero gold: the audit tuts instead of crashing or going negative.
	var u: Dictionary = d.spawn("taxman", Vector2(50, 50))
	d.tick(0.2)
	u["position"] = Vector2(1000, 1000)
	u["audit_cd"] = 0.01
	d.tick(0.2)
	_check("taxman: broke faction stays at 0",
		gs.resources.get_amount("humans", "gold") == 0.0)
	_check("taxman: still alive after tut", bool(u.get("alive", false)))


func _test_taxman_slain_note() -> void:
	var parts: Array = _new_tax_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("taxman", Vector2(50, 50))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["position"] = Vector2(1000, 1000)
	u["audit_cd"] = 0.01
	d.tick(0.2)
	u["alive"] = false
	d.tick(0.3)
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("taxman: slain closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).begins_with("GARNISHED"):
			saw = true
	_check("taxman: GARNISHED note filed", saw)


## ---- booze ooze ---------------------------------------------------------------


func _new_ooze_world() -> Array:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_add_town(gs, 100, "humans", Vector2(1000, 1000))
	_add_town(gs, 200, "humans", Vector2(3000, 3000))
	return [gs, d]


func _test_ooze_stress_relief() -> void:
	var parts: Array = _new_ooze_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("booze_ooze", Vector2(1000, 1000))
	var w: Dictionary = _add_unit(gs, "humans", Vector2(1050, 1000))
	_check("ooze: starts stressed", float(w.get("stress", 0.0)) == 80.0)
	d.tick(1.0)
	_check("ooze: party wipes stress (%.1f)" % float(w.get("stress", 0.0)),
		float(w.get("stress", 0.0)) < 80.0)
	_check("ooze: oozing state",
		String(u.get("combat_state", "")) == "oozing")


func _test_ooze_town_hop() -> void:
	var parts: Array = _new_ooze_world()
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("booze_ooze", Vector2(1000, 1000))
	d.tick(0.2)
	var first_town: int = int(u.get("ooze_town", -1))
	_check("ooze: picked a town", first_town == 100 or first_town == 200)
	# Park it on its target: next tick it parties out and re-picks.
	u["position"] = u.get("ooze_center", Vector2(1000, 1000))
	for i in 6:
		d.tick(0.5)
	_check("ooze: still alive and oozing", bool(u.get("alive", false)))
	var t: int = int(u.get("ooze_town", -1))
	_check("ooze: town id valid", t == 100 or t == 200)


func _test_ooze_leaves_and_closes() -> void:
	var parts: Array = _new_ooze_world()
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("booze_ooze", Vector2(1000, 1000))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["age"] = 99999.0
	d.tick(0.2)
	_check("ooze: leaving flag", bool(u.get("leaving", false)))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("ooze: ledger closed",
		String(rec.get("status", "")) != "active")
