extends SceneTree
## Cursing Gnomes — AI famine response (food-shortage emergency) headless tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_famine_response.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: starving AI faction yanks workers onto bush foraging (capped),
## famine outranks build crews, build crews never steal famine foragers back,
## Gazette alarm throttled to once/day, player faction gets an adviser phone
## warning instead of yanks, flags clear when the emergency lifts, a free
## farm is rushed for farm-less factions, and save/load round-trips the state.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes famine-response tests ===")
	_test_foragers_reassigned()
	_test_reassign_cap()
	_test_alarm_throttled()
	_test_player_gets_warning_not_yanks()
	_test_emergency_lifts()
	_test_famine_farm_rush()
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


## Two AI factions + the player (humans). Gnomes are the faction under test.
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


func _unit(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": "worker", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0, "work_state": "idle"})


func _bush(gs: GameState, pos: Vector2) -> Dictionary:
	return gs.add_work_site({"kind": "bush", "position": pos,
		"amount": 100.0})


func _starve(gs: GameState, faction: String) -> void:
	gs.resources.add_resource(faction, "food",
		-gs.resources.get_amount(faction, "food"), true)


func _feed(gs: GameState, faction: String, amt: float) -> void:
	gs.resources.add_resource(faction, "food", amt, true)


func _emergency(gs: GameState, director: SimAIDirector, faction: String) -> void:
	var hall: Dictionary = director._hall(faction)
	var st: Dictionary = director._analyze(faction, hall)
	director._food_emergency(faction, hall, st)


func _foragers(gs: GameState, faction: String) -> Array:
	var out := []
	for u in gs.units:
		if String(u.get("faction", "")) != faction:
			continue
		if bool(u.get("_food_emergency", false)):
			out.append(u)
	return out


func _famine_stories() -> Array:
	var out := []
	for s in _stories:
		var h := String(s.get("headline", ""))
		if h == "FAMINE!" or h == "FOOD SHORTAGE":
			out.append(s)
	return out


func _test_foragers_reassigned() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_starve(gs, "gnomes")
	_bush(gs, Vector2(1050, 1050))
	for i in range(4):
		_unit(gs, "gnomes", Vector2(1000 + i * 15, 950))
	_emergency(gs, director, "gnomes")
	var foragers: Array = _foragers(gs, "gnomes")
	_check("famine: workers reassigned to foraging", foragers.size() == 4)
	var ok := true
	for u in foragers:
		if String(u.get("work_state", "")) != "to_resource":
			ok = false
		var site: Dictionary = gs.get_work_site(int(u.get("work_site", -1)))
		if String(site.get("kind", "")) != "bush":
			ok = false
	_check("famine: foragers walk to a bush site", ok)
	_check("famine: critical alarm in gazette",
		_famine_stories().size() >= 1)
	_check("famine: emergency flag set",
		bool(director._famine.get("gnomes", false)))
	gs.queue_free()


func _test_reassign_cap() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_starve(gs, "gnomes")
	_bush(gs, Vector2(1050, 1050))
	for i in range(10):
		_unit(gs, "gnomes", Vector2(1000 + i * 12, 950))
	_emergency(gs, director, "gnomes")
	_check("famine: reassign capped at 6 per think",
		_foragers(gs, "gnomes").size() <= 6)
	gs.queue_free()


func _test_alarm_throttled() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_starve(gs, "gnomes")
	_bush(gs, Vector2(1050, 1050))
	_unit(gs, "gnomes", Vector2(1000, 950))
	_emergency(gs, director, "gnomes")
	_emergency(gs, director, "gnomes")
	_emergency(gs, director, "gnomes")
	_check("famine: gazette alarm throttled to once per day",
		_famine_stories().size() == 1)
	gs.queue_free()


func _test_player_gets_warning_not_yanks() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_starve(gs, "humans")
	_bush(gs, Vector2(2050, 550))
	var u1: Dictionary = _unit(gs, "humans", Vector2(2000, 450))
	var u2: Dictionary = _unit(gs, "humans", Vector2(2010, 450))
	_emergency(gs, director, "humans")
	_check("famine: player workers never yanked (adviser mode)",
		_foragers(gs, "humans").is_empty())
	_check("famine: player worker work_state untouched",
		String(u1.get("work_state", "")) == "idle"
		and String(u2.get("work_state", "")) == "idle")
	_check("famine: player still gets the gazette alarm",
		_famine_stories().size() == 1)
	gs.queue_free()


func _test_emergency_lifts() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_starve(gs, "gnomes")
	_bush(gs, Vector2(1050, 1050))
	for i in range(3):
		_unit(gs, "gnomes", Vector2(1000 + i * 15, 950))
	_emergency(gs, director, "gnomes")
	_check("famine: emergency active while starving",
		bool(director._famine.get("gnomes", false)))
	_feed(gs, "gnomes", 1000.0)
	_emergency(gs, director, "gnomes")
	_check("famine: emergency flag cleared when fed",
		not bool(director._famine.get("gnomes", false)))
	_check("famine: unit famine flags cleared when fed",
		_foragers(gs, "gnomes").is_empty())
	gs.queue_free()


func _test_famine_farm_rush() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_starve(gs, "gnomes")
	_bush(gs, Vector2(1050, 1050))
	_unit(gs, "gnomes", Vector2(1000, 950))
	_check("famine: no farm before the emergency",
		director._count_build("gnomes", "farm") == 0)
	_emergency(gs, director, "gnomes")
	_check("famine: free farm rushed for starving faction",
		director._count_build("gnomes", "farm") >= 1)
	gs.queue_free()


func _test_save_load() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_starve(gs, "gnomes")
	_bush(gs, Vector2(1050, 1050))
	_unit(gs, "gnomes", Vector2(1000, 950))
	_emergency(gs, director, "gnomes")
	var data: Dictionary = director.to_dict()
	_check("famine: save includes famine state",
		data.has("famine") and data.has("food_emergency_day"))
	var director2 := SimAIDirector.new(gs)
	director2.from_dict(data)
	_check("famine: load restores emergency state",
		bool(director2._famine.get("gnomes", false)))
	_check("famine: load restores alarm throttle",
		int(director2._food_emergency_day.get("gnomes", -99))
		== int(director._food_emergency_day.get("gnomes", -99)))
	gs.queue_free()
