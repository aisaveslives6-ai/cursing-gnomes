extends SceneTree
## Cursing Gnomes — visible road construction (Jeremy's 2026-10-10 direct
## order): planned roads are visibly BUILT, not just painted.
##
## - A planned link starts SURVEYED: stakes mark the line, corridor open.
## - The claiming crew breaks ground: GRADING — dirt laid waypoint by
##   waypoint behind the work front; nothing paints ahead of the front.
## - A stocked faction then PAVES: stone over dirt on the walk back.
## - Segments under construction are CLOSED: barriers/cones render, the
##   nav grid routes around them, and foot/wagon/vehicle steering slides
##   around them (the crew itself is exempt).
## - Repairs are visible work zones for the whole channel — never an
##   instant paint-over.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_road_construction.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


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


func _roadbuilder(faction: String, pos: Vector2) -> Dictionary:
	return {"faction": faction, "job": "roadbuilder", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0, "work_state": "to_road", "id": 7}


func _open_map() -> Dictionary:
	var terrain := PackedByteArray()
	terrain.resize(256)
	var levels := PackedByteArray()
	levels.resize(256)
	for i in 256:
		levels[i] = 1
	return {"terrain": terrain, "levels": levels,
		"size_tiles": Vector2i(16, 16), "tile_size": 32}


func _initialize() -> void:
	print("=== Cursing Gnomes visible road construction tests ===")
	_test_plan_starts_surveyed()
	_test_claim_breaks_ground()
	_test_grade_walk_paints_dirt()
	_test_no_paint_ahead_of_front()
	_test_pave_pass_upgrades()
	_test_pave_reversed_claim()
	_test_closure_zones()
	_test_deflect_pushes_around()
	_test_repair_is_visible_work()
	_test_save_load_stages()
	_test_nav_flags_workzone()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## A fresh plan is surveyed: marked, open, nothing painted.
func _test_plan_starts_surveyed() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var v0: int = ai.road_work_version
	var lid := ai.plan_road_link("gnomes", Vector2(100, 100), Vector2(420, 100))
	_check("plan: id returned", lid > 0)
	var l: Dictionary = ai.road_links[0]
	_check("plan: stage surveyed",
		int(l.get("stage", -1)) == WorkerAI.ROAD_STAGE_SURVEYED)
	_check("plan: front zero", float(l.get("front", -1.0)) == 0.0)
	_check("plan: pass zero", int(l.get("pass", -1)) == 0)
	_check("plan: nothing painted", ai.roads.is_empty())
	_check("plan: version bumped", ai.road_work_version > v0)
	var zones := ai.road_work_zones()
	_check("plan: one marked zone", zones.size() == 1)
	var z: Dictionary = zones[0]
	_check("plan: zone is the corridor", String(z.get("kind", "")) == "seg")
	_check("plan: corridor NOT closed",
		not bool(z.get("closed", true)))


## Claiming the link breaks ground: grading stage, corridor closed.
func _test_claim_breaks_ground() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var gs: GameState = w["gs"]
	var a := Vector2(100, 100)
	var b := Vector2(420, 100)
	var lid := ai.plan_road_link("gnomes", a, b)
	var unit := _roadbuilder("gnomes", a)
	gs.units.append(unit)
	var order: Vector2 = ai._pick_road_order(unit)
	unit["_road_order"] = order
	_check("claim: order is the near endpoint", order == a)
	_check("claim: link id held", int(unit.get("_road_link", 0)) == lid)
	var l: Dictionary = ai.road_links[0]
	_check("claim: stage grading",
		int(l.get("stage", -1)) == WorkerAI.ROAD_STAGE_GRADING)
	_check("claim: walk direction stored",
		(l.get("from", Vector2.ZERO) as Vector2) == a \
		and (l.get("to", Vector2.ZERO) as Vector2) == b)
	var zones := ai.road_work_zones()
	_check("claim: one zone", zones.size() == 1)
	var z: Dictionary = zones[0]
	_check("claim: corridor closed", bool(z.get("closed", false)))
	_check("claim: corridor spans the link",
		(z.get("a", Vector2.ZERO) as Vector2) == a \
		and (z.get("b", Vector2.ZERO) as Vector2) == b)


## Walking the grade pass lays dirt waypoint by waypoint; a broke faction
## finishes the link as a dirt road (no paving pass).
func _test_grade_walk_paints_dirt() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var gs: GameState = w["gs"]
	var a := Vector2(100, 100)
	var b := Vector2(420, 100)
	ai.plan_road_link("gnomes", a, b)
	var unit := _roadbuilder("gnomes", a)
	gs.units.append(unit)
	var order: Vector2 = ai._pick_road_order(unit)
	unit["_road_order"] = order
	var walk_pts := WorkerAI.link_waypoints(a, b)
	for p in walk_pts:
		unit["position"] = p
		ai._do_roadwork(unit, 0.4)
	var l: Dictionary = ai.road_links[0]
	_check("grade: link done", bool(l.get("done", false)))
	_check("grade: stage done",
		int(l.get("stage", -1)) == WorkerAI.ROAD_STAGE_DONE)
	_check("grade: front complete", float(l.get("front", 0.0)) == 1.0)
	_check("grade: unit idle", String(unit.get("work_state", "")) == "idle")
	_check("grade: claim released", not unit.has("_road_link"))
	var dirt := 0
	var stone := 0
	for r in ai.roads:
		var t := String((r as Dictionary).get("type", ""))
		if t == "dirt":
			dirt += 1
		elif t == "stone":
			stone += 1
	_check("grade: dirt laid", dirt > 0)
	_check("grade: no stone when broke", stone == 0)
	_check("grade: zones cleared", ai.road_work_zones().is_empty())


## Nothing paints ahead of the work front mid-link.
func _test_no_paint_ahead_of_front() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var gs: GameState = w["gs"]
	var a := Vector2(0, 0)
	var b := Vector2(320, 0)
	ai.plan_road_link("gnomes", a, b)
	var unit := _roadbuilder("gnomes", a)
	gs.units.append(unit)
	var order: Vector2 = ai._pick_road_order(unit)
	unit["_road_order"] = order
	var walk_pts := WorkerAI.link_waypoints(a, b)
	# Walk two of three waypoints.
	for i in range(2):
		unit["position"] = walk_pts[i]
		ai._do_roadwork(unit, 0.4)
	var front := float((ai.road_links[0] as Dictionary).get("front", -1.0))
	_check("front: advanced", front > 0.0 and front < 1.0)
	var max_x := -1.0
	for r in ai.roads:
		max_x = maxf(max_x, ((r as Dictionary).get("position",
			Vector2.ZERO) as Vector2).x)
	_check("front: paint behind the front", max_x >= 0.0)
	_check("front: nothing ahead of the front",
		max_x <= 160.0 + 20.0)
	# The closed corridor starts at the front, not at the plan start.
	var zones := ai.road_work_zones()
	_check("front: corridor closed", zones.size() == 1 \
		and bool((zones[0] as Dictionary).get("closed", false)))
	var za: Vector2 = (zones[0] as Dictionary).get("a", Vector2.ZERO)
	_check("front: closure starts at the front", za.x > 100.0)


## A stocked faction paves: stone over dirt on the walk back.
func _test_pave_pass_upgrades() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var gs: GameState = w["gs"]
	gs.resources.add_resource("gnomes", "gold", 200.0, true)
	gs.resources.add_resource("gnomes", "wood", 200.0, true)
	var a := Vector2(100, 100)
	var b := Vector2(420, 100)
	ai.plan_road_link("gnomes", a, b)
	var unit := _roadbuilder("gnomes", a)
	gs.units.append(unit)
	var order: Vector2 = ai._pick_road_order(unit)
	unit["_road_order"] = order
	var walk_pts := WorkerAI.link_waypoints(a, b)
	for p in walk_pts:
		unit["position"] = p
		ai._do_roadwork(unit, 0.4)
	var l: Dictionary = ai.road_links[0]
	_check("pave: pass started",
		int(l.get("stage", -1)) == WorkerAI.ROAD_STAGE_PAVING \
		and not bool(l.get("done", false)))
	# Walk the paving pass back.
	var pave_pts: Array = unit.get("_road_link_pts", [])
	_check("pave: return waypoints issued", pave_pts.size() > 0)
	for p in pave_pts.duplicate():
		unit["position"] = p
		ai._do_roadwork(unit, 0.4)
	_check("pave: link done", bool(l.get("done", false)))
	var stone := 0
	for r in ai.roads:
		if String((r as Dictionary).get("type", "")) == "stone":
			stone += 1
	_check("pave: stone laid over the dirt", stone > 0)
	_check("pave: zones cleared", ai.road_work_zones().is_empty())


## A reversed claim (crew nearer b) paves back toward a, not on a trek.
func _test_pave_reversed_claim() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var gs: GameState = w["gs"]
	gs.resources.add_resource("gnomes", "gold", 200.0, true)
	gs.resources.add_resource("gnomes", "wood", 200.0, true)
	var a := Vector2(100, 100)
	var b := Vector2(420, 100)
	ai.plan_road_link("gnomes", a, b)
	var unit := _roadbuilder("gnomes", b)  # nearer b: walks b -> a
	gs.units.append(unit)
	var order: Vector2 = ai._pick_road_order(unit)
	unit["_road_order"] = order
	_check("reversed: walks b first", order == b)
	var walk_pts := WorkerAI.link_waypoints(a, b)
	walk_pts.reverse()
	for p in walk_pts:
		unit["position"] = p
		ai._do_roadwork(unit, 0.4)
	var l: Dictionary = ai.road_links[0]
	_check("reversed: pave pass started",
		int(l.get("stage", -1)) == WorkerAI.ROAD_STAGE_PAVING \
		and not bool(l.get("done", false)))
	# The paver stands at a and works back toward b (contiguous, no trek).
	var pave_pts: Array = (unit.get("_road_link_pts", []) as Array).duplicate()
	unit["position"] = pave_pts[0]
	ai._do_roadwork(unit, 0.4)
	_check("reversed: pave continues toward b",
		(unit.get("_road_order") as Vector2) == b)
	for p in pave_pts:
		unit["position"] = p
		ai._do_roadwork(unit, 0.4)
	_check("reversed: link done", bool(l.get("done", false)))
	var stone := 0
	for r in ai.roads:
		if String((r as Dictionary).get("type", "")) == "stone":
			stone += 1
	_check("reversed: stone laid", stone > 0)


## Closed zones show in the zone list with the corridor geometry.
func _test_closure_zones() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var gs: GameState = w["gs"]
	var a := Vector2(96, 256)
	var b := Vector2(416, 256)
	ai.plan_road_link("humans", a, b)
	var unit := _roadbuilder("humans", a)
	gs.units.append(unit)
	ai._pick_road_order(unit)
	var zones := ai.road_work_zones()
	_check("zones: grading closes the corridor", zones.size() == 1)
	var z: Dictionary = zones[0]
	_check("zones: closed flag", bool(z.get("closed", false)))
	_check("zones: front point carried",
		(z.get("front", Vector2(-1, -1)) as Vector2) == a)


## Steering slides around a closed corridor; the crew is exempt.
func _test_deflect_pushes_around() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var gs: GameState = w["gs"]
	var a := Vector2(96, 256)
	var b := Vector2(416, 256)
	var lid := ai.plan_road_link("humans", a, b)
	var unit := _roadbuilder("humans", a)
	gs.units.append(unit)
	ai._pick_road_order(unit)
	var near := Vector2(250, 270)  # just below the corridor
	var dir := Vector2(1, 0)
	var out: Vector2 = ai.deflect_around_workzones(near, dir, {})
	_check("deflect: pushed off the corridor", out.y > 0.01)
	_check("deflect: keeps length", absf(out.length() - 1.0) < 0.001)
	var far := Vector2(250, 500)
	var out_far: Vector2 = ai.deflect_around_workzones(far, dir, {})
	_check("deflect: far away untouched", out_far == dir)
	var crew := _roadbuilder("humans", near)
	crew["_road_link"] = lid
	var out_crew: Vector2 = ai.deflect_around_workzones(near, dir, crew)
	_check("deflect: working crew exempt", out_crew == dir)


## Repairs are visible work zones for the whole channel — never instant.
func _test_repair_is_visible_work() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var gs: GameState = w["gs"]
	ai.paint_road(Vector2(300, 300), "humans", "dirt")
	ai.wear_road_at(Vector2(300, 300), 0.9)
	var unit := _roadbuilder("humans", Vector2(300, 300))
	gs.units.append(unit)
	var order: Vector2 = ai._pick_road_order(unit)
	_check("repair: order picked", order == Vector2(300, 300))
	_check("repair: no zone while en route",
		ai.road_work_zones().is_empty())
	unit["_road_order"] = order
	ai._do_roadwork(unit, 1.0)  # arrival: channel starts, barriers up
	_check("repair: working flag", bool(unit.get("_repair_working", false)))
	_check("repair: work pose", String(unit.get("work_pose", "")) == "work")
	var zones := ai.road_work_zones()
	_check("repair: zone live", zones.size() == 1)
	_check("repair: zone is a disc",
		String((zones[0] as Dictionary).get("kind", "")) == "disc")
	_check("repair: wear not reset mid-work",
		float(ai.roads[0]["wear"]) > 0.0)
	ai._do_roadwork(unit, 1.0)
	ai._do_roadwork(unit, 1.0)  # 3 s channel complete
	_check("repair: wear reset", float(ai.roads[0]["wear"]) == 0.0)
	_check("repair: zone cleared", ai.road_work_zones().is_empty())
	_check("repair: pose cleared", unit.get("work_pose", null) == null)


## Staging persists across save/load; old saves get sane defaults.
func _test_save_load_stages() -> void:
	var w := _new_ai()
	var ai: WorkerAI = w["ai"]
	var gs: GameState = w["gs"]
	var a := Vector2(100, 100)
	var b := Vector2(420, 100)
	ai.plan_road_link("gnomes", a, b)
	var unit := _roadbuilder("gnomes", a)
	gs.units.append(unit)
	var order: Vector2 = ai._pick_road_order(unit)
	unit["_road_order"] = order
	var walk_pts := WorkerAI.link_waypoints(a, b)
	unit["position"] = walk_pts[0]
	ai._do_roadwork(unit, 0.4)
	var data := ai.to_dict()
	var ai2 := WorkerAI.new(gs)
	ai2.from_dict(data)
	_check("save/load: one link", ai2.road_links.size() == 1)
	var l2: Dictionary = ai2.road_links[0]
	_check("save/load: stage persists",
		int(l2.get("stage", -1)) == WorkerAI.ROAD_STAGE_GRADING)
	_check("save/load: front persists",
		float(l2.get("front", -1.0)) > 0.0)
	_check("save/load: pass persists", int(l2.get("pass", -1)) == 0)
	_check("save/load: from/to persist",
		(l2.get("from", Vector2.ZERO) as Vector2) == a)
	var ai3 := WorkerAI.new(gs)
	ai3.from_dict({"road_links": [{"id": 5, "faction": "gnomes",
		"a": Vector2(0, 0), "b": Vector2(100, 0)}]})
	var l3: Dictionary = ai3.road_links[0]
	_check("old save: stage defaults",
		int(l3.get("stage", -1)) == WorkerAI.ROAD_STAGE_GRADING)
	_check("old save: from/to default to a/b",
		(l3.get("from", Vector2.ZERO) as Vector2) == Vector2(0, 0) \
		and (l3.get("to", Vector2.ZERO) as Vector2) == Vector2(100, 0))


## The nav grid flags closed work-zone cells for A* rerouting.
func _test_nav_flags_workzone() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = _open_map()
	var ai := WorkerAI.new(gs)
	gs.worker_ai = ai
	var pf := SimPathfinder.new(gs)
	pf.unlimited_budget = true
	gs.pathfinder = pf
	pf.bind_roads(ai)
	var a := Vector2(96, 256)
	var b := Vector2(416, 256)
	ai.plan_road_link("humans", a, b)
	var unit := _roadbuilder("humans", a)
	gs.units.append(unit)
	ai._pick_road_order(unit)  # claim -> grading, corridor closed
	pf.mark_dirty()
	pf.sync()
	var cell := pf._cell_of(Vector2(300, 256))
	var ck: int = pf._key(cell.x, cell.y)
	_check("nav: corridor cell flagged", pf._nav_workzone[ck] == 1)
	var far := pf._cell_of(Vector2(64, 64))
	var fk: int = pf._key(far.x, far.y)
	_check("nav: far cell clear", pf._nav_workzone[fk] == 0)
	_check("nav: work version tracked",
		pf._nav_work_ver == ai.road_work_version)
