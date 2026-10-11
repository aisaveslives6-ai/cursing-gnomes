extends SceneTree
## Cursing Gnomes — thicc moose scareNearby panic tests (HTML port, 2026-10-04).
##
## Covers: the moose's scream cooldown panics nearby civilians (HTML scareNearby
## verbatim numbers: 220px/+35 stress while mooning, 140px/+18 while traveling,
## 1.2s/2.0s scream cadence). Cowards flee via the mind flee keys; the brave
## hold their ground (SimMind.on_attacked convention). Units inside buildings,
## the dead, and fellow monsters are skipped.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_moose_scare.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes moose scare tests ===")
	_test_big_scare_radius_and_stress()
	_test_small_scare_radius_and_stress()
	_test_stress_capped_at_100()
	_test_brave_holds_ground()
	_test_inside_building_skipped()
	_test_dead_and_monsters_skipped()
	_test_scared_emotion_applied()
	_test_flee_moves_unit_away()
	_test_scream_cooldown()
	_test_tick_moose_mooning_scare()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	# Towns must exist for spawn_unit to work (check_spawn validates town_id).
	gs.towns[1] = {"id": 1, "name": "Town0", "faction": "humans",
		"pos": Vector2.ZERO, "owner": "humans"}
	var mind := SimMind.new(gs)
	var combat := SimCombat.new(gs)
	combat.mind = mind  # world.gd wiring
	var dis := DisasterSim.new(gs, combat)
	return {"gs": gs, "mind": mind, "dis": dis}


func _spawn(w: Dictionary, faction: String, pos: Vector2,
		brave: float = 0.0) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, "worker", 1, pos)
	mind.ensure(u)
	u["mind"]["traits"]["brave"] = brave
	return u


func _moose(pos: Vector2) -> Dictionary:
	return {"id": 9001, "faction": "monster", "job": "thicc_moose",
		"alive": true, "position": pos, "moon_pause": 0.0, "scare_cd": 0.0}


func _test_big_scare_radius_and_stress() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var mpos := Vector2(500, 500)
	var near: Dictionary = _spawn(w, "humans", mpos + Vector2(100, 0))
	var edge: Dictionary = _spawn(w, "humans", mpos + Vector2(200, 0))
	var far: Dictionary = _spawn(w, "humans", mpos + Vector2(300, 0))
	dis._scare_nearby(_moose(mpos), true)
	_check("big scare: near civilian stress +35",
		is_equal_approx(float(near.get("stress", 0.0)), 35.0))
	_check("big scare: near civilian flees", bool(near.get("fleeing", false)))
	_check("big scare: near civilian threat_pos set",
		near.get("threat_pos", Vector2.INF) == mpos)
	_check("big scare: 200px civilian (in 220) stressed",
		float(edge.get("stress", 0.0)) > 0.0)
	_check("big scare: 300px civilian untouched",
		float(far.get("stress", 0.0)) == 0.0
		and not bool(far.get("fleeing", false)))


func _test_small_scare_radius_and_stress() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var mpos := Vector2(500, 500)
	var near: Dictionary = _spawn(w, "humans", mpos + Vector2(100, 0))
	var mid: Dictionary = _spawn(w, "humans", mpos + Vector2(200, 0))
	dis._scare_nearby(_moose(mpos), false)
	_check("small scare: near civilian stress +18",
		is_equal_approx(float(near.get("stress", 0.0)), 18.0))
	_check("small scare: near civilian flees", bool(near.get("fleeing", false)))
	_check("small scare: 200px civilian (beyond 140) untouched",
		float(mid.get("stress", 0.0)) == 0.0
		and not bool(mid.get("fleeing", false)))


func _test_stress_capped_at_100() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var mpos := Vector2(500, 500)
	var u: Dictionary = _spawn(w, "humans", mpos + Vector2(50, 0))
	u["stress"] = 90.0
	dis._scare_nearby(_moose(mpos), true)
	_check("stress capped at 100",
		is_equal_approx(float(u.get("stress", 0.0)), 100.0))


func _test_brave_holds_ground() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var mpos := Vector2(500, 500)
	var brave: Dictionary = _spawn(w, "humans", mpos + Vector2(50, 0), 1.0)
	dis._scare_nearby(_moose(mpos), true)
	_check("brave: still stressed", float(brave.get("stress", 0.0)) > 0.0)
	_check("brave: holds ground (no flee)",
		not bool(brave.get("fleeing", false)))
	_check("brave: feels scared anyway",
		String(brave.get("emotion", {}).get("name", "")) == "scared")


func _test_inside_building_skipped() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var mpos := Vector2(500, 500)
	var indoors: Dictionary = _spawn(w, "humans", mpos + Vector2(50, 0))
	indoors["inside_building_id"] = 7
	dis._scare_nearby(_moose(mpos), true)
	_check("indoors: no stress", float(indoors.get("stress", 0.0)) == 0.0)
	_check("indoors: no flee", not bool(indoors.get("fleeing", false)))


func _test_dead_and_monsters_skipped() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var mpos := Vector2(500, 500)
	var dead: Dictionary = _spawn(w, "humans", mpos + Vector2(50, 0))
	dead["alive"] = false
	var beast: Dictionary = _spawn(w, "humans", mpos + Vector2(50, 0))
	beast["faction"] = "monster"
	dis._scare_nearby(_moose(mpos), true)
	_check("dead: no stress", float(dead.get("stress", 0.0)) == 0.0)
	_check("monster faction: no stress", float(beast.get("stress", 0.0)) == 0.0)
	_check("monster faction: no flee", not bool(beast.get("fleeing", false)))


func _test_scared_emotion_applied() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var mpos := Vector2(500, 500)
	var u: Dictionary = _spawn(w, "humans", mpos + Vector2(50, 0))
	dis._scare_nearby(_moose(mpos), false)
	_check("coward feels scared",
		String(u.get("emotion", {}).get("name", "")) == "scared")


func _test_flee_moves_unit_away() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var dis: DisasterSim = w["dis"]
	var mpos := Vector2(500, 500)
	var u: Dictionary = _spawn(w, "humans", mpos + Vector2(100, 0))
	dis._scare_nearby(_moose(mpos), true)
	var d0: float = u.get("position", mpos).distance_to(mpos)
	mind.tick_unit(u, 1.0)  # SimMind._tick_flee drives the panic dash
	var d1: float = u.get("position", mpos).distance_to(mpos)
	_check("fleeing civilian moves away from the moose", d1 > d0)


func _test_scream_cooldown() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var mpos := Vector2(500, 500)
	var u: Dictionary = _spawn(w, "humans", mpos + Vector2(50, 0))
	var moose: Dictionary = _moose(mpos)
	moose["scare_cd"] = 1.0
	dis._tick_moose_scare(moose, 0.5, true)
	_check("cooldown: no scare before expiry",
		float(u.get("stress", 0.0)) == 0.0)
	_check("cooldown: timer counts down",
		is_equal_approx(float(moose.get("scare_cd", 0.0)), 0.5))
	dis._tick_moose_scare(moose, 0.6, true)
	_check("cooldown: scare fires on expiry", float(u.get("stress", 0.0)) > 0.0)
	_check("cooldown: big resets to 1.2s",
		is_equal_approx(float(moose.get("scare_cd", 0.0)), 1.2))
	dis._tick_moose_scare(moose, 1.2, false)
	_check("cooldown: small resets to 2.0s",
		is_equal_approx(float(moose.get("scare_cd", 0.0)), 2.0))


func _test_tick_moose_mooning_scare() -> void:
	var w := _new_world()
	var dis: DisasterSim = w["dis"]
	var mpos := Vector2(500, 500)
	var u: Dictionary = _spawn(w, "humans", mpos + Vector2(50, 0))
	var moose: Dictionary = _moose(mpos)
	moose["moon_pause"] = 3.0
	moose["scare_cd"] = 0.0
	dis._tick_moose(moose, 110.0, 1.5)  # delta > 1.2s mooning scream cadence
	_check("mooning tick: civilian panics", bool(u.get("fleeing", false)))
	_check("mooning tick: scream cooldown rearmed",
		is_equal_approx(float(moose.get("scare_cd", 0.0)), 1.2))
	_check("mooning tick: still mooning",
		String(moose.get("combat_state", "")) == "mooning")
