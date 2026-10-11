extends SceneTree
## Cursing Gnomes — AI military oil-triage headless tests.
## Jeremy 2026-10-07: "AI factions not building any military buildings."
## Companion to test_ai_military_buildings.gd (the _train dupe-spam pass).
## This file covers the second pass: the barracks queue spot never
## validated (0/40), and cheap oil spenders drank the pump-oil trickle so
## 100 oil could never accumulate for a barracks.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ai_military_oil_triage.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes AI military oil-triage tests ===")
	seed(20261007)
	_test_barracks_spot_validates()
	_test_triage_holds_oil_for_barracks()
	_test_barracks_placed_once_oil_saved()
	_test_warb_reserved_after_barracks()
	_test_air_defense_triage_waits_for_core()
	_test_air_defense_resumes_after_core()
	_test_end_to_end_ai_raises_army_base()
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


## One AI faction (ogres) + player (humans). Fresh game per test.
func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	var mons := SimMonasteries.new()
	mons.setup(gs)
	gs.monasteries = mons
	var director := SimAIDirector.new(gs)
	gs.ai_director = director
	var hall: Dictionary = gs.add_building({"type": "town_hall",
		"faction": "ogres", "town_id": 1, "position": Vector2(2000, 2000),
		"alive": true, "complete": true, "progress": 1.0,
		"hp": 2000.0, "max_hp": 2000.0})
	for i in 8:
		gs.add_unit({"faction": "ogres", "job": "worker", "town_id": 1,
			"position": Vector2(2000, 2000) + Vector2(i * 9.0, 4.0),
			"alive": true, "hp": 100.0, "max_hp": 100.0, "speed": 95.0})
	return [gs, director, hall]


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


func _rich(gs: GameState, faction: String) -> void:
	gs.resources.add_resource(faction, "gold", 2000.0)
	gs.resources.add_resource(faction, "wood", 2000.0)


func _count(gs: GameState, faction: String, btype: String) -> int:
	var n := 0
	for b: Dictionary in gs.buildings:
		if bool(b.get("alive", false)) \
				and String(b.get("faction", "")) == faction \
				and String(b.get("type", "")) == btype:
			n += 1
	return n


func _oil(gs: GameState, faction: String) -> float:
	return gs.resources.get_amount(faction, "oil")


## The barracks ring spot must actually validate (the old hall-centered
## default validated 0/40 times — the zero-barracks root cause).
func _test_barracks_spot_validates() -> void:
	var parts := _make_world()
	var director: SimAIDirector = parts[1]
	var hall_pos := Vector2(2000, 2000)
	var ok := 0
	for i in 20:
		var spot: Vector2 = director._queue_spot(
			"ogres", hall_pos, "barracks", "war_hut")
		if director._valid_spot("ogres", "barracks", spot) != Vector2.INF:
			ok += 1
	_check("triage: barracks ring spot validates (got %d/20)" % ok, ok >= 10)
	_free_world(parts)


## With oil below the barracks cost, the queue must not spend oil at all —
## no medic camps / AA towers drinking the trickle.
func _test_triage_holds_oil_for_barracks() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var hall: Dictionary = parts[2]
	_rich(gs, "ogres")
	gs.resources.add_resource("ogres", "oil", 60.0)
	var st: Dictionary = director._analyze("ogres", hall)
	director._build_essentials("ogres", hall, st)
	_check("triage: oil untouched at 60 (no oil spent)",
		is_equal_approx(_oil(gs, "ogres"), 60.0))
	_check("triage: no medic camp drained the oil at 60",
		_count(gs, "ogres", "medic_camp") == 0)
	_free_world(parts)


## With oil saved past the barracks cost, the barracks goes up first.
func _test_barracks_placed_once_oil_saved() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var hall: Dictionary = parts[2]
	_rich(gs, "ogres")
	gs.resources.add_resource("ogres", "oil", 150.0)
	var st: Dictionary = director._analyze("ogres", hall)
	director._build_essentials("ogres", hall, st)
	_check("triage: barracks blueprint placed once oil saved",
		_count(gs, "ogres", "barracks") >= 1)
	_check("triage: oil was spent on the barracks",
		_oil(gs, "ogres") < 150.0)
	_free_world(parts)


## After the first barracks, the elite war building gets oil priority over
## further barracks: the queue must not raise barracks #2 before the war
## building stands.
func _test_warb_reserved_after_barracks() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var hall: Dictionary = parts[2]
	_rich(gs, "ogres")
	gs.resources.add_resource("ogres", "oil", 200.0)
	gs.add_building({"type": "barracks", "faction": "ogres", "town_id": 1,
		"position": Vector2(2300, 2000), "alive": true, "complete": true,
		"progress": 1.0, "hp": 800.0, "max_hp": 800.0})
	var st: Dictionary = director._analyze("ogres", hall)
	director._build_essentials("ogres", hall, st)
	_check("triage: war building placed before barracks #2",
		_count(gs, "ogres", "war_hut") >= 1)
	_check("triage: no second barracks before the war building",
		_count(gs, "ogres", "barracks") == 1)
	_free_world(parts)


## Paid AA towers wait while the faction has no barracks (only the 2 free
## towers go up); oil is not burned.
func _test_air_defense_triage_waits_for_core() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var hall: Dictionary = parts[2]
	_rich(gs, "ogres")
	gs.resources.add_resource("ogres", "oil", 200.0)
	director._air_defenses("ogres", hall)
	_check("triage: only the 2 free AA towers before a barracks exists",
		_count(gs, "ogres", "aa_tower") == 2)
	_check("triage: paid AA did not burn oil before a barracks exists",
		is_equal_approx(_oil(gs, "ogres"), 200.0))
	_free_world(parts)


## Once barracks + war building stand, paid AA resumes.
func _test_air_defense_resumes_after_core() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var hall: Dictionary = parts[2]
	_rich(gs, "ogres")
	gs.resources.add_resource("ogres", "oil", 200.0)
	gs.add_building({"type": "barracks", "faction": "ogres", "town_id": 1,
		"position": Vector2(2300, 2000), "alive": true, "complete": true,
		"progress": 1.0, "hp": 800.0, "max_hp": 800.0})
	gs.add_building({"type": "war_hut", "faction": "ogres", "town_id": 1,
		"position": Vector2(1700, 2000), "alive": true, "complete": true,
		"progress": 1.0, "hp": 1200.0, "max_hp": 1200.0})
	director._air_defenses("ogres", hall)
	_check("triage: paid AA resumes after core military stands",
		_count(gs, "ogres", "aa_tower") > 2)
	_check("triage: paid AA spent oil after core military stands",
		_oil(gs, "ogres") < 200.0)
	_free_world(parts)


## End to end: the full pump-oil loop over simulated minutes raises a real
## military base — barracks plus the elite war building.
func _test_end_to_end_ai_raises_army_base() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	var mons := SimMonasteries.new()
	mons.setup(gs)
	gs.monasteries = mons
	var director := SimAIDirector.new(gs)
	gs.ai_director = director
	var spots := {"gnomes": Vector2(1000, 1000),
		"ogres": Vector2(3000, 3000)}
	for f: String in spots.keys():
		gs.add_building({"type": "town_hall", "faction": f, "town_id": 1,
			"position": spots[f], "alive": true, "complete": true,
			"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
		for i in 8:
			gs.add_unit({"faction": f, "job": "worker", "town_id": 1,
				"position": spots[f] + Vector2(i * 9.0, 4.0), "alive": true,
				"hp": 100.0, "max_hp": 100.0, "speed": 95.0})
		gs.resources.add_resource(f, "gold", 600.0)
		gs.resources.add_resource(f, "wood", 600.0)
	# 200 thinks x 2.8s ~= 9 simulated minutes with the zone economy live.
	for t in 200:
		for f: String in spots.keys():
			director._think(f)
		gs.zoning.tick(2.8)
	var war_b := {"gnomes": "mage_spire", "ogres": "war_hut"}
	for f: String in spots.keys():
		_check("triage e2e: %s raised a barracks" % f,
			_count(gs, f, "barracks") >= 1)
		_check("triage e2e: %s raised its elite war building" % f,
			_count(gs, f, String(war_b[f])) >= 1)
	gs.queue_free()
