extends SceneTree
## Cursing Gnomes — wildfire ledger tests (Jeremy 2026-10-05).
##
## Covers: ignite() opens a shared "wildfire" DisasterLog record; burn
## deaths reach the ledger (the survey gap — attribute_death() could never
## match a fire death before, toll was always 0); the record closes when
## the last fire burns out; the Gazette story publishes only when someone
## died; save/load re-links the record.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_wildfire_ledger.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


class _FakeCourt:
	var stories: Array = []
	func publish_story(headline: String, body: String,
			kind: String = "default") -> Dictionary:
		stories.append({"headline": headline, "body": body,
			"kind": kind})
		return {}


func _initialize() -> void:
	print("=== Cursing Gnomes wildfire ledger tests ===")
	_test_ignite_opens_record()
	_test_ignites_share_one_record()
	_test_burn_death_reaches_ledger()
	_test_close_publishes_story_on_toll()
	_test_close_silent_without_deaths()
	_test_save_load_relinks()
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


func _add_unit(gs: GameState, pos: Vector2) -> Dictionary:
	return gs.add_unit({
		"faction": "humans", "job": "worker", "town_id": -1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
	})


func _kill_by_fire(d: DisasterSim, gs: GameState, pos: Vector2) -> void:
	var u: Dictionary = _add_unit(gs, pos)
	var combat: SimCombat = d.get("_combat")
	combat.damage_unit(int(u.get("id", 0)), 500.0, "fire")


func _test_ignite_opens_record() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_check("no record before ignite",
		dlog_active(d).is_empty())
	var f: Dictionary = d.ignite(Vector2(2000, 2000), 60.0)
	_check("fire created", not f.is_empty())
	var rec: Dictionary = dlog_active(d)
	_check("record opened", not rec.is_empty())
	_check("record kind wildfire",
		String(rec.get("kind", "")) == "wildfire")
	_check("record status active",
		String(rec.get("status", "")) == "active")


func _test_ignites_share_one_record() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	d.ignite(Vector2(2000, 2000), 60.0)
	d.ignite(Vector2(2100, 2100), 60.0)
	d.ignite(Vector2(2200, 2200), 60.0)
	var n := 0
	for r in d.dlog.active_records():
		if String(r.get("kind", "")) == "wildfire":
			n += 1
	_check("one shared record for three fires", n == 1)


func _test_burn_death_reaches_ledger() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var pos := Vector2(2000, 2000)
	d.ignite(pos, 60.0)
	_kill_by_fire(d, gs, pos)
	var rec: Dictionary = dlog_active(d)
	var deaths: Array = rec.get("deaths", [])
	_check("burn death recorded", deaths.size() == 1)
	if deaths.size() == 1:
		_check("burn cause",
			String(deaths[0].get("cause", "")) == "burned")


func _test_close_publishes_story_on_toll() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var court := _FakeCourt.new()
	gs.court_sys = court
	var pos := Vector2(2000, 2000)
	var f: Dictionary = d.ignite(pos, 60.0)
	_kill_by_fire(d, gs, pos)
	d.extinguish(f)
	_check("record closed",
		dlog_active(d).is_empty())
	# _wildfire_log_id resets to -1 on close; fetch via history.
	var hist: Array = d.dlog.history()
	var closed: Dictionary = {}
	for r in hist:
		if String(r.get("kind", "")) == "wildfire":
			closed = r
			break
	_check("closed status burned_out",
		String(closed.get("status", "")) == "burned_out")
	_check("story published", court.stories.size() == 1)
	if court.stories.size() == 1:
		var h := String(court.stories[0].get("headline", ""))
		_check("headline names wildfire + toll",
			h.contains("WILDFIRE") and h.contains("1 DEAD"))


func _test_close_silent_without_deaths() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var court := _FakeCourt.new()
	gs.court_sys = court
	var f: Dictionary = d.ignite(Vector2(2000, 2000), 60.0)
	d.extinguish(f)
	_check("record closed", dlog_active(d).is_empty())
	_check("no story for harmless fire", court.stories.is_empty())
	# Ledger still keeps the event in history.
	var found := false
	for r in d.dlog.history():
		if String(r.get("kind", "")) == "wildfire":
			found = true
	_check("ledger keeps harmless fire", found)


func _test_save_load_relinks() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var pos := Vector2(2000, 2000)
	d.ignite(pos, 60.0)
	_kill_by_fire(d, gs, pos)
	var log_id: int = d.get("_wildfire_log_id")
	_check("log id valid pre-save", log_id > 0)
	var data: Dictionary = d.to_dict()
	var combat2 := SimCombat.new(gs)
	var d2 := DisasterSim.new(gs, combat2)
	gs.disasters = d2
	d2.from_dict(data)
	_check("fires restored", d2.fires.size() == 1)
	_check("log id re-linked", d2.get("_wildfire_log_id") == log_id)
	var rec: Dictionary = dlog_active(d2)
	_check("record still active", not rec.is_empty())
	_check("death survived save",
		(rec.get("deaths", []) as Array).size() == 1)
	# Deaths after load still reach the ledger.
	_kill_by_fire(d2, gs, pos)
	var rec2: Dictionary = dlog_active(d2)
	_check("post-load burn death recorded",
		(rec2.get("deaths", []) as Array).size() == 2)


func dlog_active(d: DisasterSim) -> Dictionary:
	return d.dlog.active_for_kind("wildfire")
