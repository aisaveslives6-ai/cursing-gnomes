extends SceneTree
## Cursing Gnomes — AI faction economy health (dedicated-porting 2026-10-09).
##
## The 2026-10-08 pumpfix proved the AI economy can silently break (oil
## starvation via the unfinished-cap gate). This is a permanent regression
## guard: run the director through an extended opening and assert the
## economy health invariants — income secured, development happening,
## no faction stalled.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ai_economy_health.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes AI economy health tests ===")
	_test_income_secured()
	_test_development_happening()
	_test_no_faction_stalled()
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


## Two AI factions + the player. Halls at fixed spots; map 4096x4096.
func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.zoning = SimZoning.new(gs)
	gs.hiring = GuildHiring.new(gs)
	var director := SimAIDirector.new(gs)
	_hall(gs, "gnomes", Vector2(1000, 1000))
	_hall(gs, "ogres", Vector2(3000, 3000))
	_hall(gs, "humans", Vector2(2000, 500))
	return [gs, director]


func _hall(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "town_hall", "faction": faction,
		"town_id": 1, "position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})


func _fund(gs: GameState, faction: String, gold: float, wood: float) -> void:
	gs.resources.add_resource(faction, "gold", gold, true)
	gs.resources.add_resource(faction, "wood", wood, true)


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


func _count_type(gs: GameState, faction: String, btype: String) -> int:
	var n := 0
	for b: Dictionary in gs.buildings:
		if bool(b.get("alive", false)) \
				and String(b.get("faction", "")) == faction \
				and String(b.get("type", "")) == btype:
			n += 1
	return n


func _count_buildings(gs: GameState, faction: String) -> int:
	var n := 0
	for b: Dictionary in gs.buildings:
		if bool(b.get("alive", false)) \
				and String(b.get("faction", "")) == faction:
			n += 1
	return n


## Income: after an extended opening, each AI faction secures oil income
## (pumps) — the pumpfix invariant, extended to both AI factions.
func _test_income_secured() -> void:
	seed(20261009)
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "gnomes", 800, 800)
	_fund(gs, "ogres", 800, 800)
	for t in 12:
		director._think("gnomes")
		director._think("ogres")
	var gpumps := _count_type(gs, "gnomes", "oil_pump")
	var opumps := _count_type(gs, "ogres", "oil_pump")
	_check("econ: gnomes secure oil income (>=1 pump)", gpumps >= 1)
	_check("econ: ogres secure oil income (>=1 pump)", opumps >= 1)
	_free_world(parts)


## Development: buildings get placed (the faction develops, not stalls).
func _test_development_happening() -> void:
	seed(20261009)
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "gnomes", 1000, 1000)
	_fund(gs, "ogres", 1000, 1000)
	var g0 := _count_buildings(gs, "gnomes")
	var o0 := _count_buildings(gs, "ogres")
	for t in 12:
		director._think("gnomes")
		director._think("ogres")
	var g1 := _count_buildings(gs, "gnomes")
	var o1 := _count_buildings(gs, "ogres")
	_check("econ: gnomes develop (buildings grow)", g1 > g0)
	_check("econ: ogres develop (buildings grow)", o1 > o0)
	_free_world(parts)


## No stall: with modest funds, the director keeps making decisions
## (placements happen over an extended run).
func _test_no_faction_stalled() -> void:
	seed(20261009)
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "gnomes", 600, 600)
	_fund(gs, "ogres", 600, 600)
	for t in 20:
		director._think("gnomes")
		director._think("ogres")
	var g_bld := _count_buildings(gs, "gnomes")
	var o_bld := _count_buildings(gs, "ogres")
	# Halls + at least some development each.
	_check("econ: gnomes not stalled", g_bld >= 3)
	_check("econ: ogres not stalled", o_bld >= 3)
	_free_world(parts)
