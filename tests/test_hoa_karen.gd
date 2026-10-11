extends SceneTree
## Cursing Gnomes — HOA Karen disaster tests (Jeremy 2026-10-04 massive-dev:
## original content, not an HTML port).
##
## Covers: spawn (job/faction/hp/singleton/label), town picking (richest
## town + hall position), citation cadence (fine range, treasury deduction,
## citation count, speech bubble, fine ledger), lien at 3 citations
## (flag + ledger note + production pause in industry lots, workplace oil
## and farm harvest), slain (fine refund, liens cleared, refund note),
## departure (liens cleared, no refund), natural-spawn day gate, map-edge
## spawn point, sandbox director mapping, gazette cartoon pool, unit art.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hoa_karen.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []  # [unit_id, text] from bus.unit_said


func _initialize() -> void:
	print("=== Cursing Gnomes HOA Karen tests ===")
	_test_spawn()
	_test_singleton()
	_test_label()
	_test_pick_town()
	_test_citation()
	_test_lien()
	_test_lien_pauses_industry()
	_test_workplace_oil_retired()
	_test_lien_pauses_harvest()
	_test_slain_refund()
	_test_departed()
	_test_natural_spawn_gate()
	_test_map_edge_point()
	_test_sandbox_mapping()
	_test_cartoon()
	_test_art()
	_test_unit_node_lists()
	_test_tick_movement()
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


func _spawn_karen(gs: GameState, d: DisasterSim) -> Dictionary:
	return d.spawn("hoa_karen", Vector2(100, 100))


## ---- spawn ---------------------------------------------------------------


func _test_spawn() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_karen(gs, d)
	_check("spawn returns unit", not u.is_empty())
	_check("spawn job", String(u.get("job", "")) == "hoa_karen")
	_check("spawn monster faction",
		String(u.get("faction", "")) == "monster")
	_check("spawn hp 700", float(u.get("hp", 0.0)) == 700.0)
	_check("spawn log record", int(u.get("disaster_log_id", -1)) >= 0)
	_check("spawn alive", bool(u.get("alive", false)))
	_check("spawn gender", String(u.get("gender", "")) == "f")


func _test_singleton() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_spawn_karen(gs, d)
	var u2 := _spawn_karen(gs, d)
	_check("singleton: second spawn refused", u2.is_empty())


func _test_label() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_check("label", d._label_for("hoa_karen") == "HOA Karen")


## ---- town picking --------------------------------------------------------


func _test_pick_town() -> void:
	var gs := _new_game(["humans", "elves"])
	var d := _new_disasters(gs)
	# Town 1 (humans): hall + 2 shops. Town 2 (elves): 1 house.
	var hall := _add_building(gs, "hall", "humans", 1, Vector2(500, 500))
	_add_building(gs, "shop", "humans", 1, Vector2(560, 500))
	_add_building(gs, "shop", "humans", 1, Vector2(440, 500))
	_add_building(gs, "house", "elves", 2, Vector2(3000, 3000))
	var u := _spawn_karen(gs, d)
	d._karen_pick_town(u)
	_check("picks richest town", int(u.get("karen_town", -1)) == 1)
	var hp: Vector2 = u.get("karen_hall_pos", Vector2.INF)
	_check("hall position picked",
		hp.distance_to(Vector2(500, 500)) < 1.0)
	_check("hall is the hall",
		hp.distance_to(hall.get("position", Vector2.ZERO)) < 1.0)


## ---- citations -----------------------------------------------------------


func _town_with_gold(gs: GameState, d: DisasterSim) -> Dictionary:
	_add_building(gs, "hall", "humans", 1, Vector2(500, 500))
	_add_building(gs, "shop", "humans", 1, Vector2(560, 500))
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	var u := _spawn_karen(gs, d)
	d._karen_pick_town(u)
	return u


func _test_citation() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _town_with_gold(gs, d)
	var before: float = gs.resources.get_amount("humans", "gold")
	_said.clear()
	d._karen_issue_citation(u)
	var after: float = gs.resources.get_amount("humans", "gold")
	var fine: float = before - after
	_check("fine in range",
		fine >= DisasterSim.KAREN_FINE_MIN - 0.01 \
		and fine <= DisasterSim.KAREN_FINE_MAX + 0.01)
	var cited := 0
	for b: Dictionary in gs.buildings:
		cited += int(b.get("hoa_citations", 0))
	_check("one citation stamped", cited == 1)
	_check("bubble shouted", _said.size() == 1)
	_check("bubble mentions fine",
		_said.size() == 1 and String(_said[0][1]).contains("fine"))
	var fines: Dictionary = u.get("karen_fines", {})
	_check("fine ledger tracked",
		absf(float(fines.get("humans", 0.0)) - fine) < 0.01)


func _test_lien() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	# One building only, so all citations land on it.
	_add_building(gs, "hall", "humans", 1, Vector2(500, 500))
	gs.resources.add_resource("humans", "gold", 10000.0, true)
	var u := _spawn_karen(gs, d)
	d._karen_pick_town(u)
	d._karen_issue_citation(u)
	d._karen_issue_citation(u)
	var b: Dictionary = gs.buildings[0]
	_check("no lien before 3", not bool(b.get("hoa_lien", false)))
	d._karen_issue_citation(u)
	_check("lien at 3 citations", bool(b.get("hoa_lien", false)))
	_check("lien bubble shouted", _said.size() == 4)  # 3 fines + lien
	var log_id: int = int(u.get("disaster_log_id", -1))
	var notes: Array = d.dlog.summary(log_id).get("notes", [])
	var lien_notes := 0
	for n in notes:
		if String(n).begins_with("LIEN"):
			lien_notes += 1
	_check("lien ledger note", lien_notes == 1)


## ---- production pause ----------------------------------------------------


func _test_lien_pauses_industry() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	# Stub zoning: everything is industrial.
	var stub := _ZoneStub.new()
	gs.zoning = stub
	var b := _add_building(gs, "sawmill", "humans", 1, Vector2(500, 500))
	var ind := SimIndustry.new(gs)
	# Jeremy 2026-10-05: oil is pumps-only, so lots pay wood/gold (no oil).
	var before: float = gs.resources.get_amount("humans", "wood")
	var before_oil: float = gs.resources.get_amount("humans", "oil")
	ind._tick_lot_production(10.0)
	var produced: float = gs.resources.get_amount("humans", "wood") - before
	_check("industrial lot produces wood", produced > 0.0)
	_check("industrial lot produces no oil",
		gs.resources.get_amount("humans", "oil") - before_oil == 0.0)
	b["hoa_lien"] = true
	var before2: float = gs.resources.get_amount("humans", "wood")
	ind._tick_lot_production(10.0)
	var produced2: float = gs.resources.get_amount("humans", "wood") - before2
	_check("liened lot produces nothing", produced2 == 0.0)


class _ZoneStub extends RefCounted:
	func zone_at(_pos: Vector2, _faction: String) -> String:
		return SimZoning.INDUSTRIAL


## Jeremy 2026-10-05: workplace oil is RETIRED (oil comes ONLY from oil
## pumps). Even a unit carrying a legacy "workplace" key must gain zero
## oil — this guards the oil-pumps-only order against re-introduction.
func _test_workplace_oil_retired() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var b := _add_building(gs, "sawmill", "humans", 1, Vector2(500, 500))
	var u: Dictionary = gs.add_unit({
		"faction": "humans", "job": "worker", "town_id": 1,
		"position": Vector2(510, 500), "alive": true,
		"workplace": int(b.get("id", 0)),
	})
	var ind := SimIndustry.new(gs)
	var before: float = gs.resources.get_amount("humans", "oil")
	ind.tick(10.0)
	_check("workplace oil retired: no oil from workers at buildings",
		gs.resources.get_amount("humans", "oil") - before == 0.0)


func _test_lien_pauses_harvest() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var farm := SimFarming.new(gs)
	var plot := {"faction": "humans", "id": 7, "seed_bin": 5,
		"tiles": [{"crop": {"g": 1.0, "watered": true, "waterT": 5.0}}]}
	var out: Dictionary = farm.harvest(plot, 0)
	_check("harvest works", float(out.get("food", 0.0)) > 0.0)
	var plot2 := {"faction": "humans", "id": 8, "seed_bin": 5,
		"hoa_lien": true,
		"tiles": [{"crop": {"g": 1.0, "watered": true, "waterT": 5.0}}]}
	var out2: Dictionary = farm.harvest(plot2, 0)
	_check("liened harvest seized",
		float(out2.get("food", 0.0)) == 0.0 \
		and float(out2.get("seeds", 0.0)) == 0.0)


## ---- death / departure ----------------------------------------------------


func _test_slain_refund() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _town_with_gold(gs, d)
	# Two citations on the single shop to build a fine total.
	gs.buildings.clear()
	_add_building(gs, "shop", "humans", 1, Vector2(560, 500))
	d._karen_pick_town(u)
	d._karen_issue_citation(u)
	d._karen_issue_citation(u)
	d._karen_issue_citation(u)  # lien
	var fines: Dictionary = u.get("karen_fines", {})
	var total: float = float(fines.get("humans", 0.0))
	_check("fines collected", total > 0.0)
	var before: float = gs.resources.get_amount("humans", "gold")
	u["alive"] = false
	d._check_dead_disaster(u)
	var refunded: float = gs.resources.get_amount("humans", "gold") - before
	_check("fines refunded", absf(refunded - total) < 0.01)
	var lien_left := false
	for b: Dictionary in gs.buildings:
		if bool(b.get("hoa_lien", false)):
			lien_left = true
	_check("liens cleared on slain", not lien_left)
	var log_id: int = int(u.get("disaster_log_id", -1))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("ledger closed as slain", String(rec.get("status", "")) == "slain")
	var notes: Array = d.dlog.summary(log_id).get("notes", [])
	var refund_notes := 0
	for n in notes:
		if String(n).begins_with("REFUNDED"):
			refund_notes += 1
	_check("refund ledger note", refund_notes == 1)


func _test_departed() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _town_with_gold(gs, d)
	gs.buildings.clear()
	_add_building(gs, "shop", "humans", 1, Vector2(560, 500))
	d._karen_pick_town(u)
	d._karen_issue_citation(u)
	d._karen_issue_citation(u)
	d._karen_issue_citation(u)  # lien
	var before: float = gs.resources.get_amount("humans", "gold")
	d._karen_departed(u)
	var lien_left := false
	for b: Dictionary in gs.buildings:
		if bool(b.get("hoa_lien", false)):
			lien_left = true
	_check("liens cleared on departure", not lien_left)
	_check("no refund on departure",
		gs.resources.get_amount("humans", "gold") == before)


## ---- scheduling -----------------------------------------------------------


func _test_natural_spawn_gate() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	gs.day_number = 5
	d._maybe_spawn_hoa_karen()
	var found := false
	for u: Dictionary in gs.units:
		if String(u.get("job", "")) == "hoa_karen":
			found = true
	_check("no natural spawn before day 10", not found)


func _test_map_edge_point() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	for i in 12:
		var p: Vector2 = d._map_edge_point()
		var off: bool = p.x < 0.0 or p.y < 0.0 \
			or p.x > 4000.0 or p.y > 4000.0
		if not off:
			_check("edge point off-map", false)
			return
	_check("edge point off-map", true)


## ---- integration ----------------------------------------------------------


func _test_sandbox_mapping() -> void:
	_check("sandbox maps karen",
		String(SimSandbox.DIRECTOR_DISASTERS.get("karen", "")) \
		== "hoa_karen")


func _test_cartoon() -> void:
	var path: String = SimGazette.disaster_cartoon_for(
		"hoa_karen", "humans", "funny")
	_check("karen cartoon resolves", path.ends_with("gaz_karen_0.jpg"))


func _test_art() -> void:
	_check("karen sprite resolves", Art.animal_texture("karen") != null)


func _test_unit_node_lists() -> void:
	_check("monster jobs list", "hoa_karen" in UnitNode._MONSTER_JOBS)


## ---- flight loop ----------------------------------------------------------


func _test_tick_movement() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_add_building(gs, "hall", "humans", 1, Vector2(2000, 2000))
	_add_building(gs, "shop", "humans", 1, Vector2(2060, 2000))
	gs.resources.add_resource("humans", "gold", 5000.0, true)
	var u := d.spawn("hoa_karen", Vector2(100, 100))
	var start: Vector2 = u.get("position", Vector2.ZERO)
	# Fly toward the town for 5 seconds.
	for i in 5:
		d.tick(1.0)
	var now: Vector2 = u.get("position", Vector2.ZERO)
	_check("karen picked a town", u.has("karen_hall_pos"))
	_check("karen flies toward town",
		now.distance_to(Vector2(2000, 2000)) \
		< start.distance_to(Vector2(2000, 2000)))
	# Park her in orbit with the citation timer expired: she cites.
	u["position"] = Vector2(2000, 2000) + Vector2(150, 0)
	u["cite_cd"] = 0.0
	_said.clear()
	d.tick(0.5)
	var cited := 0
	for b: Dictionary in gs.buildings:
		cited += int(b.get("hoa_citations", 0))
	_check("orbit tick cites", cited >= 1)
	_check("cite bubble in tick", _said.size() >= 1)
	# Budget expiry sends her home.
	u["age"] = DisasterSim.MONSTERS["hoa_karen"]["budget"] + 1.0
	d.tick(0.5)
	_check("budget expiry starts leaving", bool(u.get("leaving", false)))
