extends SceneTree
## Cursing Gnomes — player road tool (Jeremy 2026-10-11, road infrastructure
## direct order: "Player keeps manual control of their own roads" +
## "Player roads follow the same visible construction whenever a player
## road tool exists").
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_player_road_tool.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: the road tool arms like the wall-drag path (start_placement accepts
## "road", rejects junk btypes), a dry drag plans a SURVEYED road link through
## the construction pipeline, a tap plans nothing, a water-crossing drag is
## rejected with a toast, duplicate drags dedupe, and the tool cancels after
## every release.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _toasts: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes player-road-tool tests ===")
	_test_tool_arms()
	_test_junk_btype_rejected()
	_test_dry_drag_plans_link()
	_test_tap_plans_nothing()
	_test_wet_drag_rejected_with_toast()
	_test_duplicate_drag_dedupes()
	_test_water_sample_helper()
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


## Boots a headless game with a WorkerAI wired the way World wires it, and
## a BuildingPlacement node bound to it. wet_stripe=true paints a vertical
## river of TILE_WATER at x in [960, 1280).
func _new_tool(wet_stripe: bool) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var w := 128
	var terrain := PackedByteArray()
	terrain.resize(w * w)
	terrain.fill(MapGen.TILE_GRASS)
	if wet_stripe:
		for ty in range(w):
			for tx in range(30, 40):
				terrain[ty * w + tx] = MapGen.TILE_WATER
	var md := {"world_w": 4096.0, "world_h": 4096.0,
		"size_tiles": Vector2i(w, w), "tile_size": 32.0,
		"terrain": terrain}
	gs.map_data = md
	var wai := WorkerAI.new(gs)
	gs.worker_ai = wai
	_toasts.clear()
	if gs.bus != null:
		gs.bus.toast.connect(_on_toast)
	var p := BuildingPlacement.new()
	root.add_child(p)
	p.setup(gs, SimBuildings.new(gs), Rect2(0, 0, 4096, 4096), "humans")
	p.map_data = md
	return {"gs": gs, "wai": wai, "p": p}


func _on_toast(text: String) -> void:
	_toasts.append(text)


func _test_tool_arms() -> void:
	var t := _new_tool(false)
	var p: BuildingPlacement = t["p"]
	p.start_placement("road")
	_check("tool arms for road", p.placing and p.btype == "road")
	# Tapping the active tool again cancels (touch-friendly toggle parity).
	p.start_placement("road")
	_check("re-tap cancels road tool", not p.placing)


func _test_junk_btype_rejected() -> void:
	var t := _new_tool(false)
	var p: BuildingPlacement = t["p"]
	p.start_placement("not_a_thing")
	_check("junk btype rejected", not p.placing)


func _test_dry_drag_plans_link() -> void:
	var t := _new_tool(false)
	var p: BuildingPlacement = t["p"]
	var wai: WorkerAI = t["wai"]
	p.start_placement("road")
	p.on_road_press(Vector2(200, 200))
	p.on_road_move(Vector2(600, 200))
	p.on_road_release(Vector2(600, 200))
	_check("dry drag plans one link", wai.road_links.size() == 1)
	if wai.road_links.size() == 1:
		var l: Dictionary = wai.road_links[0]
		_check("link faction is player", String(l.get("faction", "")) == "humans")
		_check("link starts SURVEYED",
			int(l.get("stage", -1)) == WorkerAI.ROAD_STAGE_SURVEYED)
		_check("link not done", not bool(l.get("done", true)))
		_check("link endpoints match drag",
			(l.get("a", Vector2.ZERO) as Vector2).distance_to(Vector2(200, 200)) < 1.0 \
			and (l.get("b", Vector2.ZERO) as Vector2).distance_to(Vector2(600, 200)) < 1.0)
	_check("tool cancels after release", not p.placing)


func _test_tap_plans_nothing() -> void:
	var t := _new_tool(false)
	var p: BuildingPlacement = t["p"]
	var wai: WorkerAI = t["wai"]
	p.start_placement("road")
	p.on_road_press(Vector2(200, 200))
	p.on_road_release(Vector2(200, 200))
	_check("tap plans no link", wai.road_links.is_empty())


func _test_wet_drag_rejected_with_toast() -> void:
	var t := _new_tool(true)
	var p: BuildingPlacement = t["p"]
	var wai: WorkerAI = t["wai"]
	# The wet stripe sits at x in [960, 1280); drag straight through it.
	p.start_placement("road")
	p.on_road_press(Vector2(400, 640))
	p.on_road_move(Vector2(1600, 640))
	_check("wet preview flags", p._road_wet)
	p.on_road_release(Vector2(1600, 640))
	_check("wet drag plans no link", wai.road_links.is_empty())
	_check("wet drag toasts", _toasts.size() == 1 \
		and _toasts[0].find("bridge") >= 0)
	_check("tool cancels after wet release", not p.placing)


func _test_duplicate_drag_dedupes() -> void:
	var t := _new_tool(false)
	var p: BuildingPlacement = t["p"]
	var wai: WorkerAI = t["wai"]
	for i in range(2):
		p.start_placement("road")
		p.on_road_press(Vector2(200, 200))
		p.on_road_release(Vector2(600, 200))
	_check("duplicate drag dedupes to one link", wai.road_links.size() == 1)


func _test_water_sample_helper() -> void:
	var t := _new_tool(true)
	var p: BuildingPlacement = t["p"]
	_check("dry segment not wet",
		not p._road_crosses_water(Vector2(100, 100), Vector2(800, 100)))
	_check("segment through stripe is wet",
		p._road_crosses_water(Vector2(400, 640), Vector2(1600, 640)))
	_check("empty map_data never wet",
		not (func() -> bool:
			var q: BuildingPlacement = BuildingPlacement.new()
			root.add_child(q)
			var wet: bool = q._road_crosses_water(Vector2(0, 0), Vector2(5000, 5000))
			q.queue_free()
			return wet).call())
