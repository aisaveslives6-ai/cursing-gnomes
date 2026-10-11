extends SceneTree
## Cursing Gnomes — planned AI road networks (Jeremy 2026-10-10 direct order).
##
## The AI lays deliberate building-to-building road networks instead of only
## incidental crew trails: SimAIDirector._road_networks plans hall<->farm,
## hall<->lumber camp, hall<->shop, town<->town links; roadbuilder crews
## claim an undone link, walk its waypoint polyline, and paint it with the
## same crew machinery as trails. Player faction is excluded (manual
## control of their own roads — advisor mode / sovereignty).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_road_networks.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes road network tests ===")
	_test_plan_adds_link()
	_test_plan_dedup()
	_test_waypoint_spacing()
	_test_pick_prefers_link()
	_test_walk_completes_link()
	_test_stale_claim_releases()
	_test_stale_prune()
	_test_save_load_roundtrip()
	_test_old_save_defaults()
	_test_director_plans_for_ai()
	_test_director_skips_player()
	_test_director_no_double_plan()
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
	gs.worker_ai = ai
	return {"gs": gs, "ai": ai}


func _new_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	var ai := WorkerAI.new(gs)
	gs.worker_ai = ai
	var director := SimAIDirector.new(gs)
	_stories.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	_building(gs, "gnomes", "town_hall", Vector2(1000, 1000))
	_building(gs, "gnomes", "town_hall", Vector2(1900, 1900))
	_building(gs, "gnomes", "farm", Vector2(1150, 1000))
	_building(gs, "gnomes", "lumber_camp", Vector2(1000, 1250))
	_building(gs, "humans", "town_hall", Vector2(3000, 500))
	_building(gs, "humans", "farm", Vector2(3150, 500))
	return [gs, ai, director]


func _building(gs: GameState, faction: String, btype: String,
		pos: Vector2) -> void:
	gs.add_building({"type": btype, "faction": faction, "town_id": 1,
		"position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})


func _roadbuilder(faction: String, pos: Vector2) -> Dictionary:
	return {"faction": faction, "job": "roadbuilder", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0, "work_state": "to_road"}


func _test_plan_adds_link() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var lid := ai.plan_road_link("gnomes", Vector2(100, 100), Vector2(400, 100))
	_check("plan: id returned", lid > 0)
	_check("plan: one record", ai.road_links.size() == 1)
	var l: Dictionary = ai.road_links[0]
	_check("plan: faction stored", String(l.get("faction", "")) == "gnomes")
	_check("plan: endpoint a", (l.get("a") as Vector2) == Vector2(100, 100))
	_check("plan: endpoint b", (l.get("b") as Vector2) == Vector2(400, 100))
	_check("plan: not done", not bool(l.get("done", true)))
	_check("plan: zero-length rejected",
		ai.plan_road_link("gnomes", Vector2(5, 5), Vector2(5, 5)) == 0)


func _test_plan_dedup() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var a := Vector2(100, 100)
	var b := Vector2(400, 100)
	_check("dedup: first plans", ai.plan_road_link("gnomes", a, b) > 0)
	_check("dedup: same endpoints rejected",
		ai.plan_road_link("gnomes", a, b) == 0)
	_check("dedup: reversed endpoints rejected",
		ai.plan_road_link("gnomes", b, a) == 0)
	_check("dedup: near endpoints rejected",
		ai.plan_road_link("gnomes", a + Vector2(10, 10), b) == 0)
	_check("dedup: other faction may plan same stretch",
		ai.plan_road_link("ogres", a, b) > 0)
	_check("dedup: only two records", ai.road_links.size() == 2)


func _test_waypoint_spacing() -> void:
	var pts := WorkerAI.link_waypoints(Vector2.ZERO, Vector2(320, 0))
	_check("waypoints: 320px -> 3 points", pts.size() == 3)
	_check("waypoints: starts at a", (pts[0] as Vector2) == Vector2.ZERO)
	_check("waypoints: ends at b", (pts[2] as Vector2) == Vector2(320, 0))
	var ok := true
	for i in range(pts.size() - 1):
		if (pts[i] as Vector2).distance_to(pts[i + 1]) > 160.001:
			ok = false
	_check("waypoints: spacing <= 160px", ok)
	var short := WorkerAI.link_waypoints(Vector2(10, 10), Vector2(70, 10))
	_check("waypoints: short link -> 2 points", short.size() == 2)
	_check("waypoints: degenerate -> empty",
		WorkerAI.link_waypoints(Vector2(3, 3), Vector2(3, 3)).is_empty())


func _test_pick_prefers_link() -> void:
	var parts := _new_world()
	var gs: GameState = parts[0]
	var ai: WorkerAI = parts[1]
	var lid := ai.plan_road_link("gnomes", Vector2(1000, 1000),
		Vector2(1150, 1000))
	_check("pick: link planned", lid > 0)
	var unit := _roadbuilder("gnomes", Vector2(900, 900))
	var order: Vector2 = ai._pick_road_order(unit)
	# Unit is nearer (1000,1000) than (1150,1000): no backtracking.
	_check("pick: link outranks hall fallback", order == Vector2(1000, 1000))
	_check("pick: link claimed", int(unit.get("_road_link", 0)) == lid)
	_check("pick: waypoints stored",
		(unit.get("_road_link_pts", []) as Array).size() >= 2)
	# A second crew does not claim the same link twice.
	var unit2 := _roadbuilder("gnomes", Vector2(950, 950))
	gs.units.append(unit)
	gs.units.append(unit2)
	var order2: Vector2 = ai._pick_road_order(unit2)
	_check("pick: second crew skips claimed link",
		int(unit2.get("_road_link", 0)) != lid)
	_check("pick: second crew falls back to hall",
		order2 == Vector2(1000, 1000))


func _test_walk_completes_link() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var a := Vector2(100, 100)
	var b := Vector2(420, 100)
	var lid := ai.plan_road_link("gnomes", a, b)
	var pts := WorkerAI.link_waypoints(a, b)
	var unit := _roadbuilder("gnomes", a)
	unit["_road_link"] = lid
	unit["_road_link_pts"] = pts.duplicate()
	unit["_road_order"] = pts[0]
	# Teleport along the polyline: each tick the arrival branch advances.
	for p in pts:
		unit["position"] = p
		for t in range(4):
			ai._do_roadwork(unit, 0.4)
	_check("walk: road painted along the link", ai.roads.size() > 0)
	_check("walk: link marked done",
		bool((ai.road_links[0] as Dictionary).get("done", false)))
	_check("walk: unit idles", String(unit.get("work_state", "")) == "idle")
	_check("walk: claim released", not unit.has("_road_link"))
	# Mid-link progress: first waypoint advances, link stays open.
	var lid2 := ai.plan_road_link("gnomes", Vector2(0, 0), Vector2(320, 0))
	var pts2 := WorkerAI.link_waypoints(Vector2(0, 0), Vector2(320, 0))
	var u2 := _roadbuilder("gnomes", pts2[0])
	u2["_road_link"] = lid2
	u2["_road_link_pts"] = pts2.duplicate()
	u2["_road_order"] = pts2[0]
	ai._do_roadwork(u2, 0.4)
	_check("walk: mid-link advances to next waypoint",
		(u2.get("_road_order") as Vector2) == (pts2[1] as Vector2))
	_check("walk: mid-link still open",
		not bool((ai.road_links[1] as Dictionary).get("done", false)))


func _test_stale_claim_releases() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var lid := ai.plan_road_link("gnomes", Vector2(100, 100), Vector2(400, 100))
	# Another crew already finished the link; this unit's claim is stale.
	(ai.road_links[0] as Dictionary)["done"] = true
	var unit := _roadbuilder("gnomes", Vector2(200, 200))
	unit["_road_link"] = lid
	unit["_road_link_pts"] = [Vector2(100, 100)]
	unit["_road_order"] = Vector2(100, 100)
	ai._do_roadwork(unit, 0.4)
	_check("stale: dead claim released", not unit.has("_road_link"))
	_check("stale: no crash, unit working or idle",
		String(unit.get("work_state", "")) != "")


func _test_stale_prune() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	ai.plan_road_link("gnomes", Vector2(100, 100), Vector2(400, 100))
	ai.plan_road_link("gnomes", Vector2(500, 500), Vector2(700, 700))
	(ai.road_links[0] as Dictionary)["day"] = -100  # ancient plan
	(ai.road_links[1] as Dictionary)["done"] = true
	(ai.road_links[1] as Dictionary)["day"] = -100
	ai.prune_stale_links("gnomes")
	_check("prune: stale undone dropped, done kept",
		ai.road_links.size() == 1)
	_check("prune: undone count zero", ai.undone_link_count("gnomes") == 0)


func _test_save_load_roundtrip() -> void:
	var w := _new_ai()
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var id1 := ai.plan_road_link("gnomes", Vector2(100, 100), Vector2(400, 100))
	var id2 := ai.plan_road_link("ogres", Vector2(10, 10), Vector2(20, 60))
	(ai.road_links[0] as Dictionary)["done"] = true
	var data := ai.to_dict()
	var ai2 := WorkerAI.new(gs)
	ai2.from_dict(data)
	_check("save/load: links preserved", ai2.road_links.size() == 2)
	var l0: Dictionary = ai2.road_links[0]
	_check("save/load: endpoints survive",
		(l0.get("a") as Vector2) == Vector2(100, 100)
		and (l0.get("b") as Vector2) == Vector2(400, 100))
	_check("save/load: done flag survives", bool(l0.get("done", false)))
	_check("save/load: faction survives",
		String((ai2.road_links[1] as Dictionary).get("faction", "")) == "ogres")
	var id3 := ai2.plan_road_link("gnomes", Vector2(900, 900), Vector2(950, 950))
	_check("save/load: ids stay monotonic", id3 > maxi(id1, id2))


func _test_old_save_defaults() -> void:
	var w := _new_ai()
	var gs: GameState = w["gs"]
	var ai2 := WorkerAI.new(gs)
	ai2.from_dict({})
	_check("old save: links default empty", ai2.road_links.is_empty())
	_check("old save: planning still works",
		ai2.plan_road_link("gnomes", Vector2(1, 1), Vector2(2, 2)) > 0)


func _test_director_plans_for_ai() -> void:
	var parts := _new_world()
	var ai: WorkerAI = parts[1]
	var director: SimAIDirector = parts[2]
	_check("director: starts with no links",
		ai.undone_link_count("gnomes") == 0)
	director._road_networks("gnomes")
	var n := ai.undone_link_count("gnomes")
	_check("director: planned a batch", n > 0 and n <= 4)
	# Links tie halls to halls and halls to key buildings.
	var trunk := false
	var spoke := false
	for l: Dictionary in ai.road_links:
		var la := l.get("a") as Vector2
		var lb := l.get("b") as Vector2
		var halls := [Vector2(1000, 1000), Vector2(1900, 1900)]
		if la in halls and lb in halls:
			trunk = true
		if (la in halls) != (lb in halls):
			spoke = true
	_check("director: town-to-town trunk planned", trunk)
	_check("director: hall-to-building spoke planned", spoke)
	_check("director: roadworks gazette published",
		_stories.any(func(s: Dictionary) -> bool:
			return String(s.get("headline", "")).to_upper().contains("ROADWORKS")))


func _test_director_skips_player() -> void:
	var parts := _new_world()
	var ai: WorkerAI = parts[1]
	var director: SimAIDirector = parts[2]
	director._road_networks("humans")  # player faction: manual control
	_check("director: no links for player faction",
		ai.undone_link_count("humans") == 0)


func _test_director_no_double_plan() -> void:
	var parts := _new_world()
	var ai: WorkerAI = parts[1]
	var director: SimAIDirector = parts[2]
	director._road_networks("gnomes")
	var n := ai.road_links.size()
	director._road_networks("gnomes")  # crew still on it: no new batch
	_check("director: no second batch while undone exist",
		ai.road_links.size() == n)
