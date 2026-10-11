extends SceneTree
## Cursing Gnomes — disaster tracking + response tests (Jeremy 2026-10-04).
##
## Covers: disaster log records (towns entered, death toll, causes),
## death attribution (slain / attacking / trampled / burned), military
## orders (attack/ignore/retreat affect the sim), citizen shelter orders
## (in_cover), Gazette story with death toll, outcome-based cartoon
## selection, forecast order carryover, save/load round trip.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_disaster_response.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes disaster response tests ===")
	_test_log_start()
	_test_log_towns()
	_test_log_deaths()
	_test_log_orders()
	_test_attribution_slain()
	_test_attribution_attacking()
	_test_attribution_trampled()
	_test_military_attack_order()
	_test_military_retreat_order()
	_test_citizen_shelter_order()
	_test_forecast_orders()
	_test_gazette_story()
	_test_cartoon_selection()
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


func _add_unit(gs: GameState, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	return gs.add_unit({
		"faction": faction, "job": job, "town_id": -1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"gender": "m",
	})


func _add_town(gs: GameState, faction: String, tname: String,
		pos: Vector2) -> Dictionary:
	var town: Dictionary = {
		"id": 100 + gs.towns.size(),
		"faction": faction,
		"name": tname,
		"position": pos,
	}
	gs.towns[town["id"]] = town
	return town


func _add_hall(gs: GameState, faction: String, town_id: int,
		pos: Vector2) -> Dictionary:
	return gs.add_building({
		"type": "town_hall", "faction": faction, "town_id": town_id,
		"position": pos, "alive": true, "hp": 500.0, "complete": true,
	})


## ---- log records ------------------------------------------------------------


func _test_log_start() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("giant_ass", Vector2(500, 500))
	_check("spawn opens log", not u.is_empty())
	var log_id: int = int(u.get("disaster_log_id", -1))
	_check("unit carries log id", log_id > 0)
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("record exists", not rec.is_empty())
	_check("record kind", String(rec.get("kind", "")) == "giant_ass")
	_check("record active", String(rec.get("status", "")) == "active")


func _test_log_towns() -> void:
	var gs := _new_game(["humans", "ogres"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("thicc_moose", Vector2(500, 500))
	var log_id: int = int(u.get("disaster_log_id", -1))
	var town: Dictionary = _add_town(gs, "ogres", "Goreholm", Vector2(600, 600))
	var hall: Dictionary = _add_hall(gs, "ogres", int(town["id"]), Vector2(600, 600))
	d._record_moon_town(u, hall)
	var rec: Dictionary = d.dlog.get_record(log_id)
	var towns: Array = rec.get("towns", [])
	_check("town recorded", towns.size() == 1)
	_check("town name", String(towns[0].get("name", "")) == "Goreholm")
	_check("town faction", String(towns[0].get("faction", "")) == "ogres")
	_check("moon counted", int(rec.get("moons", 0)) == 1)
	# Dedupe: same town twice records once.
	d._record_moon_town(u, hall)
	rec = d.dlog.get_record(log_id)
	_check("town deduped", (rec.get("towns", []) as Array).size() == 1)


func _test_log_deaths() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("giant_ass", Vector2(500, 500))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.dlog.record_death(log_id, "Bram", "humans", "worker", "slain", 5)
	d.dlog.record_death(log_id, "Mabel", "humans", "soldier", "attacking", 5)
	_check("death toll 2", d.dlog.death_toll(log_id) == 2)
	var sum: Dictionary = d.dlog.summary(log_id)
	_check("summary toll", int(sum.get("death_toll", 0)) == 2)
	var lines: Array = sum.get("death_lines", [])
	_check("death lines", lines.size() == 2)
	_check("death line names Bram",
		String(lines[0]).begins_with("Bram"))
	# Bad cause defaults to slain.
	d.dlog.record_death(log_id, "Pip", "humans", "worker", "bogus", 5)
	_check("bad cause defaults", d.dlog.death_toll(log_id) == 3)


func _test_log_orders() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("giant_ass", Vector2(500, 500))
	var log_id: int = int(u.get("disaster_log_id", -1))
	_check("military order set",
		d.set_military_order(log_id, "attack"))
	_check("military order bad rejected",
		not d.set_military_order(log_id, "nuke"))
	_check("citizen order set",
		d.set_citizen_order(log_id, "shelter"))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("military stored",
		String(rec.get("military_order", "")) == "attack")
	_check("citizen stored",
		String(rec.get("citizen_order", "")) == "shelter")


## ---- death attribution -------------------------------------------------------


func _test_attribution_slain() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var monster: Dictionary = d.spawn("giant_ass", Vector2(500, 500))
	var log_id: int = int(monster.get("disaster_log_id", -1))
	var victim: Dictionary = _add_unit(gs, "humans", "worker", Vector2(510, 510))
	d.attribute_death(victim, "monster", int(monster.get("id", -1)))
	_check("slain attributed", d.dlog.death_toll(log_id) == 1)
	var sum: Dictionary = d.dlog.summary(log_id)
	var lines: Array = sum.get("death_lines", [])
	_check("slain cause label",
		"slain by" in String(lines[0]))


func _test_attribution_attacking() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var monster: Dictionary = d.spawn("thicc_moose", Vector2(500, 500))
	var log_id: int = int(monster.get("disaster_log_id", -1))
	var soldier: Dictionary = _add_unit(gs, "humans", "soldier", Vector2(510, 510))
	# Soldier was ordered to hunt the moose, died (source unknown).
	soldier["disaster_hunt_id"] = int(monster.get("id", -1))
	d.attribute_death(soldier, "monster", -1)
	var sum: Dictionary = d.dlog.summary(log_id)
	var lines: Array = sum.get("death_lines", [])
	_check("attacking attributed", lines.size() == 1)
	_check("attacking cause label",
		"died attacking" in String(lines[0]))


func _test_attribution_trampled() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var monster: Dictionary = d.spawn("giant_ass", Vector2(500, 500))
	var log_id: int = int(monster.get("disaster_log_id", -1))
	# Civilian dies near the monster from an unknown source -> panic.
	var civ: Dictionary = _add_unit(gs, "humans", "worker", Vector2(520, 520))
	d.attribute_death(civ, "unknown", -1)
	var sum: Dictionary = d.dlog.summary(log_id)
	var lines: Array = sum.get("death_lines", [])
	_check("trampled attributed", lines.size() == 1)
	_check("trampled cause label",
		"trampled fleeing" in String(lines[0]))


## ---- orders affect the sim ---------------------------------------------------


func _test_military_attack_order() -> void:
	var gs := _new_game(["humans"])
	gs.player_faction = "humans"
	var d := _new_disasters(gs)
	var monster: Dictionary = d.spawn("giant_ass", Vector2(2000, 2000))
	var log_id: int = int(monster.get("disaster_log_id", -1))
	var soldier: Dictionary = _add_unit(gs, "humans", "soldier", Vector2(100, 100))
	d.set_military_order(log_id, "attack")
	d._apply_orders(0.1)
	_check("hunt id set",
		int(soldier.get("disaster_hunt_id", -1)) == int(monster.get("id", -1)))


func _test_military_retreat_order() -> void:
	var gs := _new_game(["humans"])
	gs.player_faction = "humans"
	var d := _new_disasters(gs)
	var monster: Dictionary = d.spawn("giant_ass", Vector2(2000, 2000))
	var log_id: int = int(monster.get("disaster_log_id", -1))
	var soldier: Dictionary = _add_unit(gs, "humans", "soldier", Vector2(100, 100))
	d.set_military_order(log_id, "retreat")
	d._apply_orders(0.1)
	_check("retreat defend mode", bool(soldier.get("defend_mode", false)))
	_check("retreat clears hunt",
		int(soldier.get("disaster_hunt_id", -1)) == -1)


func _test_citizen_shelter_order() -> void:
	var gs := _new_game(["humans"])
	gs.player_faction = "humans"
	var d := _new_disasters(gs)
	var monster: Dictionary = d.spawn("giant_ass", Vector2(2000, 2000))
	var log_id: int = int(monster.get("disaster_log_id", -1))
	var worker: Dictionary = _add_unit(gs, "humans", "worker", Vector2(100, 100))
	d.set_citizen_order(log_id, "shelter")
	d._apply_orders(0.1)
	_check("shelter in_cover", bool(worker.get("in_cover", false)))
	d.set_citizen_order(log_id, "free")
	d._apply_orders(0.1)
	_check("free releases cover", not bool(worker.get("in_cover", false)))


func _test_forecast_orders() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	d.forecast[12] = {"type": "giant_ass", "label": "Giant Ass",
		"done": false}
	_check("forecast military",
		d.set_forecast_orders(12, "retreat", ""))
	_check("forecast citizens",
		d.set_forecast_orders(12, "", "shelter"))
	var fo: Dictionary = d.forecast_orders(12)
	_check("forecast military stored",
		String(fo.get("military", "")) == "retreat")
	_check("forecast citizens stored",
		String(fo.get("citizens", "")) == "shelter")
	_check("forecast bad day rejected",
		not d.set_forecast_orders(99, "attack", "free"))


## ---- gazette ------------------------------------------------------------------


func _test_gazette_story() -> void:
	var gs := _new_game(["humans", "ogres"])
	var d := _new_disasters(gs)
	# Fake a court with publish_story.
	var court := RefCounted.new()
	court.set_meta("stories", [])
	# Use a simple dict-based stub via metadata is awkward; instead test
	# the story-building pieces directly.
	var monster: Dictionary = d.spawn("giant_ass", Vector2(500, 500))
	var log_id: int = int(monster.get("disaster_log_id", -1))
	var town: Dictionary = _add_town(gs, "humans", "Oakvale", Vector2(600, 600))
	d.dlog.record_town(log_id, int(town["id"]), "Oakvale", "humans", 5)
	d.dlog.record_death(log_id, "Bram", "humans", "worker", "slain", 5)
	var sum: Dictionary = d.dlog.summary(log_id)
	_check("story towns", (sum.get("towns", []) as Array) == ["Oakvale"])
	_check("story toll", int(sum.get("death_toll", 0)) == 1)
	_check("story lines", (sum.get("death_lines", []) as Array).size() == 1)


func _test_cartoon_selection() -> void:
	# Moose mooning humans, no deaths -> faction-specific funny image.
	var p1: String = SimGazette.disaster_cartoon_for(
		"thicc_moose", "humans", "funny")
	_check("moose humans funny", p1.ends_with("gaz_moose_humans.jpg"))
	# Moose mooning elves -> elves image.
	var p2: String = SimGazette.disaster_cartoon_for(
		"thicc_moose", "elves", "funny")
	_check("moose elves funny", p2.ends_with("gaz_moose_elves.jpg"))
	# Moose with deaths -> deaths pool (not the funny one).
	var p3: String = SimGazette.disaster_cartoon_for(
		"thicc_moose", "humans", "deaths")
	_check("moose deaths somber", not p3.ends_with("gaz_moose_humans.jpg"))
	# Giant ass battle -> battle pool image.
	var p4: String = SimGazette.disaster_cartoon_for(
		"giant_ass", "", "battle")
	_check("ass battle image", p4.ends_with(".jpg"))
	# Unknown kind -> global fallback.
	var p5: String = SimGazette.disaster_cartoon_for(
		"mystery", "", "calm")
	_check("fallback image", p5.ends_with("gaz_disaster_0.jpg"))


## ---- save/load ------------------------------------------------------------------


func _test_save_load() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("giant_ass", Vector2(500, 500))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.dlog.record_death(log_id, "Bram", "humans", "worker", "slain", 5)
	d.set_military_order(log_id, "attack")
	var saved: Dictionary = d.to_dict()
	_check("save has log", saved.has("disaster_log"))
	var d2 := DisasterSim.new(gs, SimCombat.new(gs))
	d2.from_dict(saved)
	var rec: Dictionary = d2.dlog.get_record(log_id)
	_check("load record", not rec.is_empty())
	_check("load deaths", d2.dlog.death_toll(log_id) == 1)
	_check("load order",
		String(rec.get("military_order", "")) == "attack")
