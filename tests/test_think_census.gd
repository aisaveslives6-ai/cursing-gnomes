extends SceneTree
## Cursing Gnomes — R20 think-census tests (2026-10-05).
##
## Perf R20: SimAIDirector._think used to run ~40 full scans of _gs.units /
## _gs.buildings per think (every _count_build / _count_job / _pop_of /
## _army_of / _workers_of walked the whole array; faction_needs_unit and
## queue_training's count_job did too; _valid_spot re-validated every queue
## entry). Now each think builds ONE census and the helpers read it.
## These tests pin the census contract:
##   - census counts match live scans exactly (units + buildings + towns)
##   - _place bumps the census mid-think (no stale counts)
##   - census is invalid after _think (direct world edits stay visible)
##   - _needs_unit memo matches the spawner predicate
##   - _qtrain enforces UNIT_TYPE_CAP identically to the raw call
##   - broke factions skip validation cleanly; funded factions still build
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_think_census.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes think-census (R20) tests ===")
	seed(20261005)
	_test_census_matches_live()
	_test_place_bumps_census()
	_test_census_invalid_after_think()
	_test_needs_unit_memo()
	_test_qtrain_cap()
	_test_broke_build_essentials()
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


## Two AI factions + the player (humans). Halls at fixed spots.
func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.zoning = SimZoning.new(gs)
	gs.hiring = GuildHiring.new(gs)
	var director := SimAIDirector.new(gs)
	gs.ai_director = director
	_hall(gs, "gnomes", Vector2(1000, 1000))
	_hall(gs, "ogres", Vector2(3000, 3000))
	_hall(gs, "humans", Vector2(2000, 500))
	return [gs, director]


func _hall(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "town_hall", "faction": faction,
		"town_id": 1, "position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})


func _unit(gs: GameState, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0})


func _bld(gs: GameState, faction: String, btype: String, pos: Vector2,
		town_id: int = 1, complete: bool = true) -> Dictionary:
	return gs.add_building({"type": btype, "faction": faction,
		"town_id": town_id, "position": pos, "alive": true,
		"complete": complete, "progress": 1.0 if complete else 0.5,
		"hp": 500.0, "max_hp": 500.0})


func _live_unit_count(gs: GameState, faction: String, job: String) -> int:
	var n := 0
	for u: Dictionary in gs.units:
		if bool(u.get("alive", false)) \
				and String(u.get("faction", "")) == faction \
				and String(u.get("job", "")) == job:
			n += 1
	return n


func _live_build_count(gs: GameState, faction: String, btype: String,
		town_id: int = -1) -> int:
	var n := 0
	for b: Dictionary in gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) != btype:
			continue
		if town_id >= 0 and int(b.get("town_id", -1)) != town_id:
			continue
		n += 1
	return n


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


func _test_census_matches_live() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_unit(gs, "gnomes", "worker", Vector2(1010, 1010))
	_unit(gs, "gnomes", "worker", Vector2(1020, 1010))
	_unit(gs, "gnomes", "soldier", Vector2(1030, 1010))
	_unit(gs, "gnomes", "farmer", Vector2(1040, 1010))
	_unit(gs, "ogres", "soldier", Vector2(3010, 3010))
	_bld(gs, "gnomes", "house", Vector2(1100, 1000), 1)
	_bld(gs, "gnomes", "house", Vector2(900, 1000), 2)
	_bld(gs, "gnomes", "barracks", Vector2(1100, 1100), 1)
	director._rebuild_think_census("gnomes")
	_check("census: army matches live",
		director._army_of("gnomes").size() == _live_unit_count(gs, "gnomes", "soldier"))
	_check("census: workers matches live",
		director._workers_of("gnomes").size() == 2)
	_check("census: pop matches live", director._pop_of("gnomes") == 4)
	_check("census: count_job matches live",
		director._count_job("gnomes", "farmer") == _live_unit_count(gs, "gnomes", "farmer"))
	_check("census: count_build matches live",
		director._count_build("gnomes", "house") == _live_build_count(gs, "gnomes", "house"))
	_check("census: count_build town matches live",
		director._count_build("gnomes", "house", 2) == _live_build_count(gs, "gnomes", "house", 2))
	_check("census: other faction falls back to live",
		director._count_build("ogres", "town_hall") == _live_build_count(gs, "ogres", "town_hall"))
	_check("census: other faction units fall back to live",
		director._pop_of("ogres") == 1)
	director._tc_valid = false
	_free_world(parts)


func _test_place_bumps_census() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.resources.add_resource("gnomes", "gold", 5000.0, true)
	gs.resources.add_resource("gnomes", "wood", 5000.0, true)
	gs.resources.add_resource("gnomes", "oil", 5000.0, true)
	director._rebuild_think_census("gnomes")
	var before: int = director._count_build("gnomes", "house")
	var bp: Dictionary = director._place("gnomes", "house", 1, Vector2(1300, 1000))
	_check("census: _place succeeds", not bp.is_empty())
	_check("census: count_build sees the placement",
		director._count_build("gnomes", "house") == before + 1)
	_check("census: town count sees the placement",
		director._count_build("gnomes", "house", 1) == before + 1)
	_check("census: bump matches live",
		director._count_build("gnomes", "house") == _live_build_count(gs, "gnomes", "house"))
	director._tc_valid = false
	_free_world(parts)


func _test_census_invalid_after_think() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# A real think must leave the census invalid so later direct reads
	# (tests, world, other systems) always see live state.
	director._think("gnomes")
	_check("census: invalid after _think", not director._tc_valid)
	var before: int = director._count_build("gnomes", "house")
	_bld(gs, "gnomes", "house", Vector2(1400, 1000))
	_check("census: direct world edit visible post-think",
		director._count_build("gnomes", "house") == before + 1)
	_free_world(parts)


func _test_needs_unit_memo() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_unit(gs, "gnomes", "worker", Vector2(1010, 1010))
	_unit(gs, "gnomes", "soldier", Vector2(1020, 1010))
	director._rebuild_think_census("gnomes")
	for job: String in ["worker", "soldier", "roadbuilder"]:
		var direct: bool = gs.spawner.faction_needs_unit("gnomes", job, 20)
		var memo: bool = director._needs_unit("gnomes", job, 20)
		_check("census: _needs_unit matches spawner (%s)" % job, memo == direct)
		_check("census: _needs_unit memoized (%s)" % job,
			director._tc_needs.get(job, null) == direct)
	director._tc_valid = false
	_free_world(parts)


func _test_qtrain_cap() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var br: Dictionary = _bld(gs, "gnomes", "barracks", Vector2(1100, 1100))
	gs.resources.add_resource("gnomes", "gold", 9000.0, true)
	gs.resources.add_resource("gnomes", "wood", 9000.0, true)
	# At cap: both paths refuse with type_capped.
	for i in range(GuildHiring.UNIT_TYPE_CAP):
		_unit(gs, "gnomes", "soldier", Vector2(1000 + i * 10, 1000))
	director._rebuild_think_census("gnomes")
	_check("census: _qtrain refuses at cap",
		not director._qtrain("gnomes", br, "soldier"))
	_check("census: cap refusal reason",
		String(gs.hiring.last_train_block) == "type_capped")
	director._tc_valid = false
	_free_world(parts)


func _test_broke_build_essentials() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# Broke faction: the affordability pre-check must skip validation and
	# placement cleanly (no crash, no buildings).
	director._think("gnomes")
	var broke_buildings: int = director._count_build("gnomes", "house") \
		+ director._count_build("gnomes", "barracks")
	_check("census: broke faction places nothing", broke_buildings == 0)
	# Funded faction (oil included): essentials still build.
	gs.resources.add_resource("ogres", "gold", 9000.0, true)
	gs.resources.add_resource("ogres", "wood", 9000.0, true)
	gs.resources.add_resource("ogres", "oil", 9000.0, true)
	var o_before: int = director._count_build("ogres", "house") \
		+ director._count_build("ogres", "storage") \
		+ director._count_build("ogres", "barracks")
	director._think("ogres")
	var o_after: int = director._count_build("ogres", "house") \
		+ director._count_build("ogres", "storage") \
		+ director._count_build("ogres", "barracks")
	_check("census: funded faction still builds", o_after > o_before)
	_free_world(parts)
