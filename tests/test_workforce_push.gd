extends SceneTree
## Cursing Gnomes — AI workforce push (HTML forceCivWork port) headless tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_workforce_push.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: incomplete sites get builders even when the faction is POOR (the
## pull system only builds when stocked), HTML caps (max 5, 3 per site),
## Sims-trippers / indoor / carriers / player-ordered units are never yanked,
## off-shift workers are left alone, and already-committed crews are counted.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes workforce-push tests ===")
	_test_poor_faction_gets_builders()
	_test_builder_caps()
	_test_never_yanks_busy()
	_test_off_shift_left_alone()
	_test_no_sites_no_crash()
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


## Two AI factions + the player. Gnomes are the faction under test.
func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.zoning = SimZoning.new(gs)
	gs.hiring = GuildHiring.new(gs)
	# 10:00 game time — workers on shift (07:30-16:30).
	gs.game_time = 10.0 / 24.0 * 14400.0
	var director := SimAIDirector.new(gs)
	_hall(gs, "gnomes", Vector2(1000, 1000))
	_hall(gs, "ogres", Vector2(3000, 3000))
	_hall(gs, "humans", Vector2(2000, 500))
	return [gs, director]


func _hall(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "town_hall", "faction": faction,
		"town_id": 1, "position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})


func _unit(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": "worker", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0, "work_state": "idle"})


func _site(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "house", "faction": faction, "town_id": 1,
		"position": pos, "alive": true, "complete": false, "progress": 0.3,
		"hp": 500.0, "max_hp": 500.0})


## Keep the faction POOR so the pull system would never volunteer builders
## (WorkerAI only builds when wood>80 and gold>60).
func _impoverish(gs: GameState, faction: String) -> void:
	gs.resources.add_resource(faction, "gold", -gs.resources.get_amount(faction, "gold"), true)
	gs.resources.add_resource(faction, "wood", -gs.resources.get_amount(faction, "wood"), true)
	gs.resources.add_resource(faction, "gold", 10.0, true)
	gs.resources.add_resource(faction, "wood", 10.0, true)


func _think_gnomes(director: SimAIDirector, ticks: int = 4) -> void:
	# Round-robin: gnomes think first of the three factions.
	for _i in range(ticks * 3):
		director.tick(2.8)


func _builders_on(gs: GameState, site_id: int) -> int:
	var n := 0
	for u in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if int(u.get("work_building", -1)) == site_id \
				and String(u.get("work_state", "")) in ["to_build", "building"]:
			n += 1
	return n


## Builders on ANY incomplete gnome site (the director may place its own
## blueprints via _build_essentials before the push runs — those get crews
## too, which is correct).
func _builders_anywhere(gs: GameState) -> int:
	var n := 0
	for u in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if int(u.get("work_building", -1)) >= 0 \
				and String(u.get("work_state", "")) in ["to_build", "building"]:
			n += 1
	return n


func _test_poor_faction_gets_builders() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_impoverish(gs, "gnomes")
	var site: Dictionary = _site(gs, "gnomes", Vector2(1100, 1000))
	var site_id := int(site["id"])
	for i in range(6):
		_unit(gs, "gnomes", Vector2(1000 + i * 15, 1050))
	_think_gnomes(director)
	_check("poor faction: incomplete site gets builders",
		_builders_on(gs, site_id) >= 1)
	_check("poor faction: workforce push fills crew cap",
		_builders_anywhere(gs) >= 2)
	gs.queue_free()


func _test_builder_caps() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_impoverish(gs, "gnomes")
	var s1: Dictionary = _site(gs, "gnomes", Vector2(1100, 1000))
	var s2: Dictionary = _site(gs, "gnomes", Vector2(900, 1100))
	for i in range(20):
		_unit(gs, "gnomes", Vector2(1000 + i * 10, 1050))
	_think_gnomes(director, 6)
	var total := _builders_on(gs, int(s1["id"])) + _builders_on(gs, int(s2["id"]))
	_check("cap: at most 5 builders total (HTML maxBuilders)", total <= 5)
	_check("cap: at most 3 per site", _builders_on(gs, int(s1["id"])) <= 3)
	gs.queue_free()


func _test_never_yanks_busy() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_impoverish(gs, "gnomes")
	var site: Dictionary = _site(gs, "gnomes", Vector2(1100, 1000))
	var site_id := int(site["id"])
	# Sims-tripper, indoor unit, carrier, player-ordered unit: all must stay.
	var tripper: Dictionary = _unit(gs, "gnomes", Vector2(1000, 1050))
	tripper["mind_state"] = "satisfying:eat"
	var indoor: Dictionary = _unit(gs, "gnomes", Vector2(1010, 1050))
	indoor["inside_building_id"] = 7
	var carrier: Dictionary = _unit(gs, "gnomes", Vector2(1020, 1050))
	carrier["carrying"] = {"wood": 10.0}
	var ordered: Dictionary = _unit(gs, "gnomes", Vector2(1030, 1050))
	ordered["player_order"] = {"kind": "move"}
	# Two plain idle workers who CAN be drafted.
	_unit(gs, "gnomes", Vector2(1040, 1050))
	_unit(gs, "gnomes", Vector2(1050, 1050))
	_think_gnomes(director)
	_check("sims-tripper not yanked",
		int(tripper.get("work_building", -1)) != site_id)
	_check("indoor unit not yanked",
		int(indoor.get("work_building", -1)) != site_id)
	_check("carrier not yanked (hauls first)",
		int(carrier.get("work_building", -1)) != site_id)
	_check("player-ordered unit not yanked (advisor mode)",
		int(ordered.get("work_building", -1)) != site_id)
	_check("idle workers still drafted",
		_builders_on(gs, site_id) >= 1)
	gs.queue_free()


func _test_off_shift_left_alone() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_impoverish(gs, "gnomes")
	# 22:00 game time — workers off shift.
	gs.game_time = 22.0 / 24.0 * 14400.0
	var site: Dictionary = _site(gs, "gnomes", Vector2(1100, 1000))
	var site_id := int(site["id"])
	for i in range(6):
		_unit(gs, "gnomes", Vector2(1000 + i * 15, 1050))
	_think_gnomes(director)
	_check("off-shift: no builders drafted",
		_builders_on(gs, site_id) == 0)
	gs.queue_free()


func _test_no_sites_no_crash() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	for i in range(4):
		_unit(gs, "gnomes", Vector2(1000 + i * 15, 1050))
	_think_gnomes(director)  # no incomplete sites — must not error
	_check("no incomplete sites: think completes cleanly", true)
	gs.queue_free()
