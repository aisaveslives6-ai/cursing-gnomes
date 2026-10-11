extends SceneTree
## Cursing Gnomes — road network continuity + persistence tests.
##
## Jeremy 2026-10-07 bug "AI not rebuilding roads": the dirt road network
## rendered as dashed fragments with gaps, and the whole painted network
## vanished on every save/load. Root causes fixed alongside:
##   1. SimZoning.ROAD_RING_STEP was 48 px while road discs are 26 px wide
##      (HTML ROAD_CELL = 22) -> dashed block rings.
##   2. WorkerAI.ROAD_MERGE_RADIUS was 24 px while painters step 18-22 px ->
##      dense paints self-merged to ~44 px effective spacing.
##   3. The roadbuilder crew dropped the HTML's gap-fill interpolation
##      ("fill gaps toward order for a continuous painted strip").
##   4. WorkerAI.roads was never saved/loaded (HTML saves data.roads).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_road_rebuild.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes road rebuild tests ===")
	_test_ring_spacing_continuous()
	_test_merge_behavior()
	_test_paint_cap()
	_test_persistence_roundtrip()
	_test_crew_trail_continuous()
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


func _new_world(factions: Array[String]) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	var w := {
		"gs": gs,
		"buildings": SimBuildings.new(gs),
		"ai": WorkerAI.new(gs),
	}
	return w


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _found(w: Dictionary, faction: String) -> Dictionary:
	var gs: GameState = w["gs"]
	var town: Dictionary = gs.found_town(faction, "T", Vector2(500, 500))
	var hall: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		"town_hall", faction, int(town["id"]), Vector2(500, 500))
	hall["complete"] = true
	hall["progress"] = 1.0
	return town


func _give(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	for res: String in Config.RESOURCES:
		gs.resources.add_resource(faction, res, 10000.0, true)


## Max nearest-neighbor distance between painted dots (continuity metric).
## Road discs are 26 px wide (DIRT_RADIUS 13), so a continuous road needs
## every dot within 26 px of another dot.
func _max_nn_gap(roads: Array) -> float:
	var worst := 0.0
	for i in range(roads.size()):
		var pi: Vector2 = (roads[i] as Dictionary).get("position", Vector2.ZERO)
		var best := INF
		for j in range(roads.size()):
			if i == j:
				continue
			var pj: Vector2 = (roads[j] as Dictionary).get("position", Vector2.ZERO)
			best = minf(best, pi.distance_to(pj))
		if best < INF:
			worst = maxf(worst, best)
	return worst


## 1. Block-ring painting at SimZoning.ROAD_RING_STEP must be continuous:
## dots every ROAD_RING_STEP px along an edge, none merging away, no gaps
## wider than a disc (26 px).
func _test_ring_spacing_continuous() -> void:
	var w := _new_world(["gnomes"])
	var ai: WorkerAI = w["ai"]
	_check("ring step matches HTML ROAD_CELL",
		is_equal_approx(SimZoning.ROAD_RING_STEP, 22.0))
	var step := SimZoning.ROAD_RING_STEP
	var n := 12
	for i in range(n):
		ai.paint_road(Vector2(100.0 + float(i) * step, 200.0), "gnomes", "dirt")
	_check("ring paints do not self-merge", ai.roads.size() == n)
	_check("ring has no gaps wider than a disc",
		_max_nn_gap(ai.roads) <= 26.0)
	_free_world(w)


## 2. Near-duplicates still merge (no stacking); distinct steps do not.
func _test_merge_behavior() -> void:
	var w := _new_world(["gnomes"])
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(100, 100), "gnomes", "dirt")
	ai.paint_road(Vector2(105, 100), "gnomes", "stone")
	_check("same-spot repaint merges", ai.roads.size() == 1)
	_check("merge refreshes type",
		String((ai.roads[0] as Dictionary).get("type", "")) == "stone")
	ai.paint_road(Vector2(122, 100), "gnomes", "dirt")
	_check("22 px step is a new record", ai.roads.size() == 2)
	_free_world(w)


## 3. HTML-verbatim hard cap bounds the list (perf + save size).
func _test_paint_cap() -> void:
	var w := _new_world(["gnomes"])
	var ai: WorkerAI = w["ai"]
	for i in range(WorkerAI.ROAD_MAX):
		ai.roads.append({"position": Vector2(i * 30, 0),
			"type": "dirt", "faction": "gnomes"})
	ai.paint_road(Vector2(99999, 99999), "gnomes", "dirt")
	_check("paint capped at ROAD_MAX", ai.roads.size() == WorkerAI.ROAD_MAX)
	_check("cap matches HTML", WorkerAI.ROAD_MAX == 4500)
	_free_world(w)


## 4. Roads survive a save/load round-trip (positions, types, factions).
func _test_persistence_roundtrip() -> void:
	var w := _new_world(["gnomes"])
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(111, 222), "gnomes", "dirt")
	ai.paint_road(Vector2(333, 444), "gnomes", "stone")
	var enc: Dictionary = SaveSystem._encode_value(ai.to_dict())
	var w2 := _new_world(["gnomes"])
	var ai2: WorkerAI = w2["ai"]
	ai2.from_dict(SaveSystem._decode_value(enc) as Dictionary)
	_check("round-trip keeps count", ai2.roads.size() == 2)
	var p0: Vector2 = (ai2.roads[0] as Dictionary).get("position", Vector2.ZERO)
	_check("round-trip keeps positions", p0.distance_to(Vector2(111, 222)) < 0.01)
	_check("round-trip keeps types",
		String((ai2.roads[1] as Dictionary).get("type", "")) == "stone")
	_check("round-trip keeps factions",
		String((ai2.roads[0] as Dictionary).get("faction", "")) == "gnomes")
	# Old saves have no "roads" key -> empty network, no crash.
	var ai3: WorkerAI = w2["ai"]
	ai3.from_dict({})
	_check("missing key loads empty", ai3.roads.is_empty())
	_free_world(w)
	_free_world(w2)


## 5. End-to-end: a roadbuilder walking its order leaves a continuous trail
## (gap-fill interpolation ported from the HTML crew).
func _test_crew_trail_continuous() -> void:
	var w := _new_world(["elves"])
	_give(w, "elves")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "elves")
	var tid: int = int(town["id"])
	# Hall is at (500,500); spawn the crew 200 px away so it walks an order.
	var u: Dictionary = gs.spawner.spawn_unit("elves", "roadbuilder", tid,
		Vector2(300, 500))
	for i: int in range(1200):
		ai.tick_unit(u, bs, 1.0 / 60.0)
	_check("crew painted a trail", ai.roads.size() >= 8)
	_check("crew trail has no gaps wider than a disc",
		_max_nn_gap(ai.roads) <= 26.0)
	_free_world(w)
