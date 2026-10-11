extends SceneTree
## Cursing Gnomes — counter-raid retaliation doctrine tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_counter_raid.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
##
## Covers SimAIDirector._counter_raid (Jeremy 2026-10-05, deliberate
## improvement over HTML): a faction under attack punches back at the
## attacker's undefended home — launch gates (under attack, at war, weak
## enemy home guard, surplus troops), muster skip (raiders not recalled),
## player faction gets an adviser warning instead of a launch, raid flags
## clear on arrival / peace / withdrawal, one launch per day, save/load.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes counter-raid tests ===")
	_test_launch_when_attacked_and_door_open()
	_test_no_launch_when_home_guard_strong()
	_test_no_launch_without_surplus()
	_test_no_launch_when_not_under_attack()
	_test_muster_does_not_recall_raiders()
	_test_player_gets_warning_not_raid()
	_test_raid_clears_on_arrival()
	_test_raid_clears_on_peace()
	_test_one_launch_per_day()
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


## Three factions; player = humans. Gnomes are the faction under test.
func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.zoning = SimZoning.new(gs)
	gs.hiring = GuildHiring.new(gs)
	gs.game_time = 10.0 / 24.0 * 14400.0
	var director := SimAIDirector.new(gs)
	_stories.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	_hall(gs, "gnomes", Vector2(1000, 1000))
	_hall(gs, "ogres", Vector2(3000, 3000))
	_hall(gs, "humans", Vector2(2000, 500))
	return [gs, director]


func _hall(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "town_hall", "faction": faction,
		"town_id": 1, "position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})


func _soldier(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": "soldier", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0})


## Gnomes at war with ogres; 3 ogre attackers at the gnome hall; 14 gnome
## soldiers home; ogre home guard empty. Returns [gs, director].
func _attacked_world() -> Array:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_soldier(gs, "ogres", Vector2(1100, 1000))
	_soldier(gs, "ogres", Vector2(1100, 1050))
	_soldier(gs, "ogres", Vector2(1050, 1100))
	for i: int in range(14):
		_soldier(gs, "gnomes",
			Vector2(900 + float(i % 7) * 20.0, 900 + float(i / 7) * 20.0))
	return parts


func _raiders(gs: GameState, faction: String) -> Array:
	var out: Array = []
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == faction and u.has("counter_raid"):
			out.append(u)
	return out


func _launch(parts: Array, faction: String) -> Dictionary:
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var hall: Dictionary = director._hall(faction)
	var st: Dictionary = director._analyze(faction, hall)
	director._counter_raid(faction, st)
	return st


func _test_launch_when_attacked_and_door_open() -> void:
	var parts: Array = _attacked_world()
	var gs: GameState = parts[0]
	_launch(parts, "gnomes")
	var raiders: Array = _raiders(gs, "gnomes")
	_check("counter-raid: launches exactly 3 raiders", raiders.size() == 3)
	var ok := true
	for u: Dictionary in raiders:
		var cr: Dictionary = u["counter_raid"]
		ok = ok and String(cr.get("enemy", "")) == "ogres"
		ok = ok and bool(u.get("deployed_for_war", false))
		ok = ok and not bool(u.get("defend_mode", true))
		var mt: Vector2 = u.get("move_target", Vector2.INF)
		ok = ok and mt.distance_to(Vector2(3000, 3000)) < 120.0
	_check("counter-raid: raiders target ogre hall, war-deployed, off defense", ok)
	var gaz := false
	for s: Dictionary in _stories:
		if String(s.get("headline", "")) == "COUNTER-RAID!":
			gaz = true
	_check("counter-raid: gazette announces the launch", gaz)
	gs.queue_free()


func _test_no_launch_when_home_guard_strong() -> void:
	var parts: Array = _attacked_world()
	var gs: GameState = parts[0]
	for i: int in range(5):
		_soldier(gs, "ogres", Vector2(2950 + float(i) * 15.0, 2950))
	_launch(parts, "gnomes")
	_check("counter-raid: no launch when enemy home guard is strong",
		_raiders(gs, "gnomes").is_empty())
	gs.queue_free()


func _test_no_launch_without_surplus() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_soldier(gs, "ogres", Vector2(1100, 1000))
	_soldier(gs, "ogres", Vector2(1100, 1050))
	_soldier(gs, "ogres", Vector2(1050, 1100))
	for i: int in range(10):
		_soldier(gs, "gnomes", Vector2(900 + float(i) * 20.0, 900))
	_launch(parts, "gnomes")
	_check("counter-raid: no launch without surplus troops",
		_raiders(gs, "gnomes").is_empty())
	gs.queue_free()


func _test_no_launch_when_not_under_attack() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	# Ogre soldiers far from the gnome hall — no attack underway.
	_soldier(gs, "ogres", Vector2(2000, 2000))
	_soldier(gs, "ogres", Vector2(2050, 2000))
	_soldier(gs, "ogres", Vector2(2000, 2050))
	for i: int in range(14):
		_soldier(gs, "gnomes", Vector2(900 + float(i) * 20.0, 900))
	_launch(parts, "gnomes")
	_check("counter-raid: no launch when not under attack",
		_raiders(gs, "gnomes").is_empty())
	gs.queue_free()


func _test_muster_does_not_recall_raiders() -> void:
	var parts: Array = _attacked_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var st: Dictionary = _launch(parts, "gnomes")
	var raiders: Array = _raiders(gs, "gnomes")
	# Attackers 100px from the hall = threat 2; muster would recall
	# everyone not explicitly skipped.
	var hall: Dictionary = director._hall("gnomes")
	director._muster_defense("gnomes", hall, st)
	var ok := raiders.size() == 3
	for u: Dictionary in raiders:
		var mt: Vector2 = u.get("move_target", Vector2.INF)
		ok = ok and mt.distance_to(Vector2(3000, 3000)) < 120.0
	_check("counter-raid: muster does not recall raiders mid-flight", ok)
	gs.queue_free()


func _test_player_gets_warning_not_raid() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.diplomacy.declare_war("humans", "ogres", "test")
	_soldier(gs, "ogres", Vector2(2100, 500))
	_soldier(gs, "ogres", Vector2(2100, 550))
	_soldier(gs, "ogres", Vector2(2050, 550))
	for i: int in range(14):
		_soldier(gs, "humans", Vector2(1900 + float(i) * 20.0, 400))
	_launch(parts, "humans")
	_check("counter-raid: player faction never auto-launches (adviser mode)",
		_raiders(gs, "humans").is_empty())
	_check("counter-raid: player warning throttled to once/day",
		int(director._counter_raid_day.get("humans", -99)) == int(gs.day_number))
	gs.queue_free()


func _test_raid_clears_on_arrival() -> void:
	var parts: Array = _attacked_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_launch(parts, "gnomes")
	var raiders: Array = _raiders(gs, "gnomes")
	raiders[0]["position"] = Vector2(2950, 2950)  # arrived at ogre hall
	director._clear_finished_raids("gnomes")
	var rest: Array = _raiders(gs, "gnomes")
	_check("counter-raid: arrived raider stands down",
		rest.size() == 2 and not raiders[0].has("counter_raid"))
	_check("counter-raid: arrival releases the war deployment",
		not bool(raiders[0].get("deployed_for_war", false)))
	gs.queue_free()


func _test_raid_clears_on_peace() -> void:
	var parts: Array = _attacked_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_launch(parts, "gnomes")
	gs.diplomacy.make_peace("gnomes", "ogres")
	director._clear_finished_raids("gnomes")
	_check("counter-raid: peace stands the raid down",
		_raiders(gs, "gnomes").is_empty())
	gs.queue_free()


func _test_one_launch_per_day() -> void:
	var parts: Array = _attacked_world()
	var gs: GameState = parts[0]
	_launch(parts, "gnomes")
	_launch(parts, "gnomes")
	_check("counter-raid: at most one launch per faction per day",
		_raiders(gs, "gnomes").size() == 3)
	gs.queue_free()


func _test_save_load() -> void:
	var parts: Array = _attacked_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_launch(parts, "gnomes")
	var d2 := SimAIDirector.new(gs)
	d2.from_dict(director.to_dict())
	_check("counter-raid: throttle day survives save/load",
		int(d2._counter_raid_day.get("gnomes", -99)) == int(gs.day_number))
	gs.queue_free()
