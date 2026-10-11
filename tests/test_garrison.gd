extends SceneTree
## Cursing Gnomes — peacetime garrison AI tests.
##
## Covers the AI-first phase military AI checklist item "garrison" (port of
## HTML fix79 c44TickGarrison + garrisonMilitaryNPC + militaryBaseHome):
##   - idle military is stationed at the base during peacetime (defend_mode,
##     walks back when beyond the 240px yard — no teleport pop-in)
##   - base home preference: M-zone fort > barracks/war-unique > hall+offset
##   - at-war factions are skipped (war systems own the troops)
##   - guards, player-ordered, mustering, withdrawing, deployed, fleeing,
##     and indoors units are never touched
##   - yard threat: hostile inside 320px drops far combat targets and holds
##     the yard without issuing move orders that would fight combat AI
##   - 0.5 s throttle on tick()
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_garrison.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes garrison tests ===")
	_test_stations_far_troop_at_base()
	_test_idle_troop_holds_yard()
	_test_barracks_preferred_over_hall()
	_test_no_base_no_crash()
	_test_guard_skipped()
	_test_player_order_skipped()
	_test_mustering_skipped()
	_test_deployed_skipped()
	_test_at_war_faction_skipped()
	_test_yard_threat_drops_far_target()
	_test_yard_threat_no_move_order()
	_test_indoors_skipped()
	_test_throttle()
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


## Fresh game + combat + garrison. player_faction defaults to "humans".
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var combat := SimCombat.new(gs)
	combat.diplomacy = gs.diplomacy
	var garrison := SimGarrison.new(gs, combat)
	return {"gs": gs, "combat": combat, "garrison": garrison}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


func _building(w: Dictionary, btype: String, faction: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({
		"type": btype, "faction": faction, "town_id": -1,
		"position": pos, "complete": true, "progress": 1.0,
		"alive": true, "hp": 1200.0, "max_hp": 1200.0,
	})


func _home_of_hall(hall_pos: Vector2) -> Vector2:
	return hall_pos + Vector2(320, -180)  # SimGarrison.HALL_OFFSET


func _intruder(w: Dictionary, pos: Vector2) -> Dictionary:
	# Hostile "monster"-faction intruder, added directly (the spawner only
	# accepts the five playable factions). Monsters are always hostile via
	# combat.can_fight without any war state.
	var gs: GameState = w["gs"]
	return gs.add_unit({
		"faction": "monster", "job": "soldier", "town_id": -1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
	})


## --- stationing ---------------------------------------------------------------

func _test_stations_far_troop_at_base() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	var hall_pos := Vector2(5000, 5000)
	_building(w, "town_hall", "ogres", hall_pos)
	var u := _spawn(w, "ogres", "soldier", Vector2(100, 100))
	g._tick_garrison()
	_check("far troop: defend_mode set", bool(u.get("defend_mode", false)))
	var mt = u.get("move_target", null)
	_check("far troop: got a move_target", mt is Vector2)
	if mt is Vector2:
		var home := _home_of_hall(hall_pos)
		_check("far troop: move_target inside compound",
			(mt as Vector2).distance_to(home) <= 200.0)
		# No teleport pop-in: the unit itself has not moved.
		_check("far troop: unit not teleported",
			(u.get("position", Vector2.ZERO) as Vector2).distance_to(
				Vector2(100, 100)) < 1.0)
	_free_world(w)


func _test_idle_troop_holds_yard() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	var hall_pos := Vector2(5000, 5000)
	_building(w, "town_hall", "ogres", hall_pos)
	var home := _home_of_hall(hall_pos)
	var u := _spawn(w, "ogres", "soldier", home + Vector2(40, 20))
	g._tick_garrison()
	_check("yard troop: defend_mode set", bool(u.get("defend_mode", false)))
	_check("yard troop: position unchanged",
		(u.get("position", Vector2.ZERO) as Vector2).distance_to(
			home + Vector2(40, 20)) < 1.0)
	_free_world(w)


func _test_barracks_preferred_over_hall() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	_building(w, "town_hall", "ogres", Vector2(9000, 9000))
	var rax_pos := Vector2(5000, 5000)
	_building(w, "barracks", "ogres", rax_pos)
	var u := _spawn(w, "ogres", "soldier", Vector2(100, 100))
	g._tick_garrison()
	var mt = u.get("move_target", null)
	_check("barracks: got a move_target", mt is Vector2)
	if mt is Vector2:
		_check("barracks: home is the barracks, not the hall",
			(mt as Vector2).distance_to(rax_pos) <= 200.0)
	_free_world(w)


func _test_no_base_no_crash() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	# Elves have no buildings at all.
	var u := _spawn(w, "elves", "soldier", Vector2(100, 100))
	g._tick_garrison()  # must not crash
	_check("no base: troop untouched",
		not bool(u.get("defend_mode", false)) \
		and u.get("move_target", null) == null)
	_free_world(w)


## --- skips -------------------------------------------------------------------

func _test_guard_skipped() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	_building(w, "town_hall", "ogres", Vector2(5000, 5000))
	var u := _spawn(w, "ogres", "guard", Vector2(100, 100))
	g._tick_garrison()
	_check("guard: untouched (crime pipeline owns guards)",
		not bool(u.get("defend_mode", false)) \
		and u.get("move_target", null) == null)
	_free_world(w)


func _test_player_order_skipped() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	_building(w, "town_hall", "humans", Vector2(5000, 5000))
	var u := _spawn(w, "humans", "soldier", Vector2(100, 100))
	u["player_order"] = {"type": "guard"}
	g._tick_garrison()
	_check("player order: untouched",
		not bool(u.get("defend_mode", false)) \
		and u.get("move_target", null) == null)
	_free_world(w)


func _test_mustering_skipped() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	_building(w, "town_hall", "ogres", Vector2(5000, 5000))
	var u := _spawn(w, "ogres", "soldier", Vector2(100, 100))
	u["mustering"] = true
	g._tick_garrison()
	_check("mustering: untouched", u.get("move_target", null) == null)
	_free_world(w)


func _test_deployed_skipped() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	_building(w, "town_hall", "ogres", Vector2(5000, 5000))
	var u := _spawn(w, "ogres", "soldier", Vector2(100, 100))
	u["deployed_for_war"] = true
	u["deploy_target_id"] = 4242
	g._tick_garrison()
	_check("deployed: untouched", u.get("move_target", null) == null)
	_free_world(w)


func _test_indoors_skipped() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	_building(w, "town_hall", "ogres", Vector2(5000, 5000))
	var u := _spawn(w, "ogres", "soldier", Vector2(100, 100))
	u["inside_building_id"] = 7
	g._tick_garrison()
	_check("indoors: untouched", u.get("move_target", null) == null)
	_free_world(w)


func _test_at_war_faction_skipped() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var g: SimGarrison = w["garrison"]
	_building(w, "town_hall", "ogres", Vector2(5000, 5000))
	_building(w, "town_hall", "humans", Vector2(100, 100))
	gs.diplomacy.declare_war("ogres", "humans", "test")
	var u := _spawn(w, "ogres", "soldier", Vector2(200, 200))
	g._tick_garrison()
	_check("at war: faction skipped, war systems own troops",
		not bool(u.get("defend_mode", false)) \
		and u.get("move_target", null) == null)
	_free_world(w)


## --- yard threat ---------------------------------------------------------------

func _test_yard_threat_drops_far_target() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	# Monsters are always hostile (combat.can_fight) without a war state,
	# so the faction stays garrison-eligible while the yard is hot.
	var hall_pos := Vector2(5000, 5000)
	_building(w, "town_hall", "ogres", hall_pos)
	var home := _home_of_hall(hall_pos)
	var defender := _spawn(w, "ogres", "soldier", home + Vector2(30, 0))
	var far_foe := _spawn(w, "humans", "soldier", Vector2(100, 100))
	defender["combat_target"] = int(far_foe.get("id", -1))
	# Monster inside the 320px yard scan.
	_intruder(w, home + Vector2(200, 0))
	g._tick_garrison()
	_check("yard hot: far combat target dropped",
		int(defender.get("combat_target", -2)) == -1)
	_check("yard hot: defend_mode set",
		bool(defender.get("defend_mode", false)))
	_free_world(w)


func _test_yard_threat_no_move_order() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	var hall_pos := Vector2(5000, 5000)
	_building(w, "town_hall", "ogres", hall_pos)
	var home := _home_of_hall(hall_pos)
	var defender := _spawn(w, "ogres", "soldier", home + Vector2(30, 0))
	_intruder(w, home + Vector2(200, 0))
	g._tick_garrison()
	# Garrison must not issue move orders during a yard fight — combat AI
	# owns the engagement (chase/attack via aggro).
	_check("yard hot: no move_target issued",
		defender.get("move_target", null) == null)
	_free_world(w)


## --- throttle ------------------------------------------------------------------

func _test_throttle() -> void:
	var w := _new_world()
	var g: SimGarrison = w["garrison"]
	_building(w, "town_hall", "ogres", Vector2(5000, 5000))
	var u := _spawn(w, "ogres", "soldier", Vector2(100, 100))
	g.tick(0.1)
	_check("throttle: 0.1s does not run the garrison",
		not bool(u.get("defend_mode", false)))
	g.tick(0.4)
	_check("throttle: accumulated 0.5s runs the garrison",
		bool(u.get("defend_mode", false)))
	_free_world(w)
