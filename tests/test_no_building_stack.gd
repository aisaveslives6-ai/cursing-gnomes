extends SceneTree
## Cursing Gnomes — building stacking regression test.
## Jeremy 2026-10-07 (screenshot): a wooden shack was placed directly ON TOP
## of another building's roof. Root cause: SimAIDirector._place called
## place_blueprint directly without overlap validation — only the callers
## that remembered _valid_spot got spacing checks. Fixed by validating
## EVERY placement inside _place itself (the single choke point).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_no_building_stack.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes no-building-stack tests ===")
	_test_place_rejects_overlap()
	_test_place_nudges_to_valid_spot()
	_test_place_allows_spaced_buildings()
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


func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.zoning = SimZoning.new(gs)
	gs.hiring = GuildHiring.new(gs)
	var director := SimAIDirector.new(gs)
	var t: Dictionary = gs.found_town("gnomes", "Teston", Vector2(1000, 1000))
	var tid := int(t.get("id", 1))
	gs.add_building({"type": "town_hall", "faction": "gnomes",
		"town_id": tid, "position": Vector2(1000, 1000), "alive": true,
		"complete": true, "progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
	gs.resources.add_resource("gnomes", "wood", 10000.0, true)
	gs.resources.add_resource("gnomes", "oil", 10000.0, true)
	gs.resources.add_resource("gnomes", "gold", 10000.0, true)
	return [gs, director, tid]


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()
	# SimAIDirector is RefCounted, not a Node: queue_free() does not exist.
	# It frees itself when its last reference drops (end of each test func).


## Placing a building directly on top of an existing one must NOT stack —
## _place validates and either nudges to a clear spot or refuses ({}).
func _test_place_rejects_overlap() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var tid: int = parts[2]
	# First house at a clear spot.
	var b1: Dictionary = director._place("gnomes", "house", tid, Vector2(1500, 1500))
	_check("stack: first house placed", not b1.is_empty())
	# Second house at the EXACT same spot — must not stack.
	var b2: Dictionary = director._place("gnomes", "house", tid, Vector2(1500, 1500))
	if b2.is_empty():
		# Refused outright — acceptable (no stacking).
		_check("stack: overlapping placement refused or moved", true)
	else:
		var p1: Vector2 = b1.get("position", Vector2.ZERO)
		var p2: Vector2 = b2.get("position", Vector2.ZERO)
		var min_sep: float = SimBuildings.footprint("house") * 2.0 \
			+ SimBuildings.PLACEMENT_GAP
		_check("stack: overlapping placement moved apart (dist=%.0f need=%.0f)"
			% [p1.distance_to(p2), min_sep], p1.distance_to(p2) >= min_sep - 1.0)
	_free_world(parts)


## A slightly-offset overlapping spot gets nudged to a valid position,
## not stacked.
func _test_place_nudges_to_valid_spot() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var tid: int = parts[2]
	var b1: Dictionary = director._place("gnomes", "house", tid, Vector2(2000, 2000))
	_check("nudge: first house placed", not b1.is_empty())
	# 50px away — inside the footprint+gap exclusion, so it must move.
	var b2: Dictionary = director._place("gnomes", "house", tid, Vector2(2050, 2000))
	if b2.is_empty():
		_check("nudge: near-overlap refused or moved", true)
	else:
		var p1: Vector2 = b1.get("position", Vector2.ZERO)
		var p2: Vector2 = b2.get("position", Vector2.ZERO)
		_check("nudge: near-overlap moved (dist=%.0f)" % p1.distance_to(p2),
			p1.distance_to(p2) >= 50.0 + SimBuildings.PLACEMENT_GAP - 1.0)
	_free_world(parts)


## Buildings placed far apart still work normally — the validation
## must not block legitimate spaced-out construction.
func _test_place_allows_spaced_buildings() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var tid: int = parts[2]
	var b1: Dictionary = director._place("gnomes", "house", tid, Vector2(1500, 1500))
	var b2: Dictionary = director._place("gnomes", "house", tid, Vector2(2500, 2500))
	_check("spaced: both houses placed", not b1.is_empty() and not b2.is_empty())
	if not b1.is_empty() and not b2.is_empty():
		var p1: Vector2 = b1.get("position", Vector2.ZERO)
		var p2: Vector2 = b2.get("position", Vector2.ZERO)
		# Far-apart requests should land essentially where asked.
		_check("spaced: first house near request", p1.distance_to(Vector2(1500, 1500)) < 200.0)
		_check("spaced: second house near request", p2.distance_to(Vector2(2500, 2500)) < 200.0)
	_free_world(parts)
