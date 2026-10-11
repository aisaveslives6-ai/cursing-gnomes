extends SceneTree
## Cursing Gnomes — road wear tests (Jeremy 2026-10-10 direct order).
##
## Roads degrade with traffic: worn roads lose their movement bonus (wagon
## 1.25x scales to 1.0x; A* routing cost scales back toward off-road) and
## render shabby; roadbuilders pick worn segments as repair orders and
## channel them back to fresh as part of their job.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_road_wear.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes road wear tests ===")
	_test_paint_wear_zero()
	_test_wear_accrual_caps()
	_test_road_index_at()
	_test_version_bump_on_band_cross()
	_test_repaint_no_maintenance()
	_test_move_unit_wears_road()
	_test_save_load_roundtrip()
	_test_old_save_defaults()
	_test_repair_order_pick()
	_test_repair_channel_resets()
	_test_wagon_mult_scales()
	_test_pathfinder_worn_cost()
	_test_overlay_wear_band()
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


func _new_ai() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var ai := WorkerAI.new(gs)
	gs.worker_ai = ai  # move_unit's wear hook reads this
	return {"gs": gs, "ai": ai}


func _test_paint_wear_zero() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(100, 100), "humans", "dirt")
	_check("paint: one record", ai.roads.size() == 1)
	_check("paint: wear starts at 0", float(ai.roads[0].get("wear", -1.0)) == 0.0)


func _test_wear_accrual_caps() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(100, 100), "humans", "dirt")
	ai.wear_road_at(Vector2(100, 100), 0.3)
	_check("wear: accrues", absf(float(ai.roads[0]["wear"]) - 0.3) < 0.0001)
	ai.wear_road_at(Vector2(100, 100), 5.0)
	_check("wear: caps at 1.0", float(ai.roads[0]["wear"]) == 1.0)
	ai.wear_road_at(Vector2(900, 900), 1.0)  # nowhere near a road
	_check("wear: far point is a no-op", float(ai.roads[0]["wear"]) == 1.0)


func _test_road_index_at() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(100, 100), "humans", "dirt")
	ai.paint_road(Vector2(500, 500), "humans", "dirt")
	_check("index: finds near record", ai.road_index_at(Vector2(104, 104)) == 0)
	_check("index: finds second record", ai.road_index_at(Vector2(496, 504)) == 1)
	_check("index: -1 far away", ai.road_index_at(Vector2(900, 900)) == -1)


func _test_version_bump_on_band_cross() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(100, 100), "humans", "dirt")
	var v0: int = ai.road_wear_version
	ai.wear_road_at(Vector2(100, 100), 0.01)  # stays in band 0
	_check("version: no bump inside band", ai.road_wear_version == v0)
	ai.wear_road_at(Vector2(100, 100), 0.30)  # wear 0.31 -> band 1
	_check("version: bumps on band cross", ai.road_wear_version == v0 + 1)


func _test_repaint_no_maintenance() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(100, 100), "humans", "dirt")
	ai.wear_road_at(Vector2(100, 100), 0.8)
	var v0: int = ai.road_wear_version
	ai.paint_road(Vector2(102, 102), "humans", "dirt")  # merges
	_check("repaint: one record (merged)", ai.roads.size() == 1)
	# Jeremy 2026-10-10 visible road construction: repainting never
	# maintains — a worn road needs a real repair work zone, never an
	# instant paint-over.
	_check("repaint: wear NOT reset", float(ai.roads[0]["wear"]) == 0.8)
	_check("repaint: version untouched", ai.road_wear_version == v0)


func _test_move_unit_wears_road() -> void:
	var w := _new_ai()
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(100, 100), "humans", "dirt")
	var unit := {"position": Vector2(60, 100), "speed": 30.0}
	WorkerAI.move_unit(gs, unit, Vector2(200, 100), 1.0)
	_check("move: unit advanced", (unit["position"] as Vector2).x > 60.0)
	_check("move: road underfoot wore down",
		float(ai.roads[0].get("wear", 0.0)) > 0.0)
	var before: float = float(ai.roads[0]["wear"])
	var idle := {"position": Vector2(100, 100), "speed": 30.0}
	WorkerAI.move_unit(gs, idle, Vector2(100, 100), 1.0)  # already there
	_check("move: idle unit adds no wear",
		float(ai.roads[0]["wear"]) == before)


func _test_save_load_roundtrip() -> void:
	var w := _new_ai()
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(100, 100), "humans", "dirt")
	ai.paint_road(Vector2(500, 500), "humans", "stone")
	ai.wear_road_at(Vector2(100, 100), 0.6)
	var data := ai.to_dict()
	var ai2 := WorkerAI.new(gs)
	ai2.from_dict(data)
	_check("save/load: count preserved", ai2.roads.size() == 2)
	_check("save/load: wear preserved",
		absf(float(ai2.roads[0].get("wear", -1.0)) - 0.6) < 0.0001)
	_check("save/load: fresh stays fresh",
		float(ai2.roads[1].get("wear", -1.0)) == 0.0)
	_check("save/load: grid rebuilt", ai2.road_index_at(Vector2(102, 98)) == 0)


func _test_old_save_defaults() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	ai.from_dict({"roads": [
		{"position": Vector2(10, 10), "type": "dirt", "faction": "humans"},
	]})
	_check("old save: wear defaults to 0",
		float(ai.roads[0].get("wear", -1.0)) == 0.0)
	_check("old save: grid works", ai.road_index_at(Vector2(10, 10)) == 0)


func _test_repair_order_pick() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(100, 100), "humans", "dirt")  # fresh: ignored
	ai.paint_road(Vector2(300, 300), "humans", "dirt")
	ai.wear_road_at(Vector2(300, 300), 0.8)
	ai.paint_road(Vector2(320, 320), "elves", "dirt")
	ai.wear_road_at(Vector2(320, 320), 0.9)  # wrong faction: ignored
	ai.paint_road(Vector2(2000, 2000), "humans", "dirt")
	ai.wear_road_at(Vector2(2000, 2000), 0.9)  # out of range: ignored
	var unit := {"faction": "humans", "position": Vector2(290, 290)}
	var order: Vector2 = ai._pick_road_order(unit)
	_check("repair: picks the worn human road", order == Vector2(300, 300))
	_check("repair: flag set", int(unit.get("_road_repair_idx", -1)) == 1)


func _test_repair_channel_resets() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	ai.paint_road(Vector2(300, 300), "humans", "dirt")
	ai.wear_road_at(Vector2(300, 300), 0.9)
	var unit := {
		"faction": "humans",
		"position": Vector2(300, 300),
		"work_state": "to_road",
		"_road_order": Vector2(300, 300),
		"_road_repair_idx": 0,
		"_road_paint_t": -1000.0,  # keep the paint cadence out of this test
	}
	ai._do_roadwork(unit, 1.0)
	ai._do_roadwork(unit, 1.0)
	_check("repair: still channeling", float(ai.roads[0]["wear"]) > 0.0)
	ai._do_roadwork(unit, 1.0)  # 3 s channel complete
	_check("repair: wear reset", float(ai.roads[0]["wear"]) == 0.0)
	_check("repair: flags cleared", not unit.has("_road_repair_idx"))
	_check("repair: order cleared", not unit.has("_road_order"))
	_check("repair: unit idle", String(unit.get("work_state", "")) == "idle")


func _test_wagon_mult_scales() -> void:
	var w := _new_ai()
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var tr := SimTradeRoutes.new(gs)
	tr.worker_ai = ai
	ai.paint_road(Vector2(100, 100), "humans", "dirt")
	var m_fresh: float = tr._road_speed_mult(Vector2(100, 100), 0.0)
	_check("wagon: fresh road 1.25x", absf(m_fresh - 1.25) < 0.0001)
	ai.roads[0]["wear"] = 1.0
	var m_worn: float = tr._road_speed_mult(Vector2(100, 100), 0.0)
	_check("wagon: worn road 1.0x (bonus lost)", absf(m_worn - 1.0) < 0.0001)
	ai.roads[0]["wear"] = 0.5
	var m_half: float = tr._road_speed_mult(Vector2(100, 100), 0.0)
	_check("wagon: half wear 1.125x", absf(m_half - 1.125) < 0.0001)
	_check("wagon: no road 1.0x",
		tr._road_speed_mult(Vector2(900, 900), 0.0) == 1.0)
	tr.worker_ai = null
	_check("wagon: null host 1.0x",
		tr._road_speed_mult(Vector2(100, 100), 0.0) == 1.0)
	tr.worker_ai = ai
	ai.roads[0]["wear"] = 0.0
	tr._road_speed_mult(Vector2(100, 100), 10.0)
	_check("wagon: grinds wear into the road",
		float(ai.roads[0]["wear"]) > 0.0)


func _open_map() -> Dictionary:
	var terrain := PackedByteArray()
	terrain.resize(256)
	var levels := PackedByteArray()
	levels.resize(256)
	for i in 256:
		levels[i] = 1
	return {"terrain": terrain, "levels": levels,
		"size_tiles": Vector2i(16, 16), "tile_size": 32}


func _test_pathfinder_worn_cost() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = _open_map()
	var pf := SimPathfinder.new(gs)
	pf.unlimited_budget = true
	gs.pathfinder = pf
	var host := WorkerAI.new(gs)
	# L-shaped dirt corridor: (96,256) -> (256,256) -> (256,416).
	var p := Vector2(96, 256)
	while p.x <= 256.0:
		host.paint_road(p, "humans", "dirt")
		p.x += 24.0
	p = Vector2(256, 280)
	while p.y <= 416.0:
		host.paint_road(p, "humans", "dirt")
		p.y += 24.0
	pf.bind_roads(host)
	pf.mark_dirty()
	pf.sync()
	var ck: int = pf._key(3, 8)  # corridor cell
	_check("pf: fresh nav wear byte is 0", pf._nav_road_wear[ck] == 0)
	_check("pf: fresh corridor cell is dirt", pf._nav_road[ck] == 1)
	# Worn out: version bump triggers a nav rebuild carrying wear bytes.
	for rd in host.roads:
		rd["wear"] = 1.0
	host.road_wear_version += 1
	pf.mark_dirty()
	pf.sync()
	_check("pf: rebuild picked up the wear version",
		pf._nav_road_wear_ver == host.road_wear_version)
	_check("pf: worn nav wear byte is 255", pf._nav_road_wear[ck] == 255)
	# The bonus-loss formula itself (the hot loop calls this):
	_check("pf: fresh dirt costs dirt",
		SimPathfinder.road_step_cost(
			SimPathfinder.COST_DIRT_ROAD, 0.0) \
			== SimPathfinder.COST_DIRT_ROAD)
	_check("pf: worn dirt costs off-road (bonus lost)",
		SimPathfinder.road_step_cost(
			SimPathfinder.COST_DIRT_ROAD, 1.0) \
			== SimPathfinder.COST_OFFROAD)
	_check("pf: half-worn stone scales linearly",
		absf(SimPathfinder.road_step_cost(
			SimPathfinder.COST_STONE_ROAD, 0.5) - 0.89) < 0.0001)
	_check("pf: worn stone costs off-road too",
		SimPathfinder.road_step_cost(
			SimPathfinder.COST_STONE_ROAD, 1.0) \
			== SimPathfinder.COST_OFFROAD)
	gs.queue_free()


func _test_overlay_wear_band() -> void:
	_check("overlay: band 0.0 -> 0", RoadOverlay.wear_band(0.0) == 0)
	_check("overlay: band 0.32 -> 0", RoadOverlay.wear_band(0.32) == 0)
	_check("overlay: band 0.34 -> 1", RoadOverlay.wear_band(0.34) == 1)
	_check("overlay: band 0.65 -> 1", RoadOverlay.wear_band(0.65) == 1)
	_check("overlay: band 0.67 -> 2", RoadOverlay.wear_band(0.67) == 2)
	_check("overlay: band 1.0 -> 2", RoadOverlay.wear_band(1.0) == 2)
