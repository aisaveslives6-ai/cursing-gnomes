extends SceneTree
## Cursing Gnomes — oil pump tests (Jeremy 2026-10-05).
##
## Oil piles are gone. Oil comes from oil pumps placed in industrial zones:
## each completed pump inside an industrial zone trickles oil into the
## faction stockpile (the shop-in-commercial-zone pattern). The AI builds
## 4 pumps per town inside industrial zones.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_oil_pump.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes oil-pump tests ===")
	_test_pump_generates_in_industrial()
	_test_pump_idle_outside_industrial()
	_test_pump_idle_when_incomplete()
	_test_no_oil_in_mapgen()
	_test_rock_sites_dropped_on_load()
	_test_miner_uses_gold_vein()
	_test_ai_paints_industrial_zone()
	_test_ai_no_duplicate_industrial_zone()
	_test_ai_pump_spot_inside_zone()
	_test_ai_builds_four_pumps_per_town()
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


func _new_gs() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	return gs


func _pump(gs: GameState, pos: Vector2, complete: bool = true) -> Dictionary:
	return gs.add_building({
		"alive": true, "complete": complete, "faction": "humans",
		"type": "oil_pump", "position": pos})


## A completed pump inside an industrial zone trickles oil.
func _test_pump_generates_in_industrial() -> void:
	var gs: GameState = _new_gs()
	gs.zoning.paint_zone("I", "humans", Rect2(Vector2(0, 0), Vector2(400, 400)))
	_pump(gs, Vector2(100, 100))
	var before: float = gs.resources.get_amount("humans", "oil")
	gs.zoning.tick(10.0)
	var after: float = gs.resources.get_amount("humans", "oil")
	_check("pump: oil generated in industrial zone", after > before)
	_check("pump: rate matches",
		is_equal_approx(after - before, SimZoning.OIL_PUMP_OIL_PER_SEC * 10.0))


## Outside an industrial zone the pump sits idle.
func _test_pump_idle_outside_industrial() -> void:
	var gs: GameState = _new_gs()
	gs.zoning.paint_zone("I", "humans", Rect2(Vector2(0, 0), Vector2(400, 400)))
	_pump(gs, Vector2(900, 900))
	var before: float = gs.resources.get_amount("humans", "oil")
	gs.zoning.tick(10.0)
	_check("pump: no oil outside industrial zone",
		is_equal_approx(gs.resources.get_amount("humans", "oil"), before))


## Incomplete pumps don't produce.
func _test_pump_idle_when_incomplete() -> void:
	var gs: GameState = _new_gs()
	gs.zoning.paint_zone("I", "humans", Rect2(Vector2(0, 0), Vector2(400, 400)))
	_pump(gs, Vector2(100, 100), false)
	var before: float = gs.resources.get_amount("humans", "oil")
	gs.zoning.tick(10.0)
	_check("pump: incomplete pump idle",
		is_equal_approx(gs.resources.get_amount("humans", "oil"), before))


## MapGen no longer emits oil clusters.
func _test_no_oil_in_mapgen() -> void:
	var map: Dictionary = MapGen.new().generate(
		["humans", "ogres", "elves", "gnomes"], 42)
	var has_oil := false
	for r: Dictionary in map["resources"]:
		if String(r.get("type", "")) == "oil":
			has_oil = true
	_check("mapgen: no oil resources", not has_oil)
	# Gold still generates.
	var has_gold := false
	for r: Dictionary in map["resources"]:
		if String(r.get("type", "")) == "gold":
			has_gold = true
	_check("mapgen: gold still generates", has_gold)


## Old saves' rock (oil) sites are dropped on load.
func _test_rock_sites_dropped_on_load() -> void:
	var gs: GameState = _new_gs()
	gs.add_work_site({"kind": "rock", "position": Vector2(10, 10),
		"amount": 150.0})
	gs.add_work_site({"kind": "gold_vein", "position": Vector2(20, 20),
		"amount": 150.0})
	var data: Dictionary = SaveSystem.snapshot(gs)
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans"])
	_check("save: restore ok", SaveSystem.restore(gs2, data))
	var kinds: Array = []
	for s: Dictionary in gs2.work_sites:
		kinds.append(String(s.get("kind", "")))
	_check("save: rock sites dropped", not kinds.has("rock"))
	_check("save: gold veins kept", kinds.has("gold_vein"))


## Miners work gold veins now (oil rocks are gone).
func _test_miner_uses_gold_vein() -> void:
	var gs: GameState = _new_gs()
	var wai: WorkerAI = WorkerAI.new(gs)
	var vein: Dictionary = gs.add_work_site(
		{"kind": "gold_vein", "position": Vector2(300, 300), "amount": 150.0})
	var u: Dictionary = gs.add_unit({
		"alive": true, "faction": "humans", "job": "miner",
		"position": Vector2(300, 300), "work_state": "idle", "carrying": {}})
	_check("miner: assigned a vein", wai._assign_gather(u, "miner"))
	_check("miner: assigned the gold vein",
		int(u["work_site"]) == int(vein["id"]))


## --- AI auto-build rule: 4 pumps per town inside an industrial zone -------

func _new_ai_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])  # gnomes = AI faction under test
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.zoning = SimZoning.new(gs)
	var director := SimAIDirector.new(gs)
	var hall: Dictionary = gs.add_building({"type": "town_hall",
		"faction": "gnomes", "town_id": 1, "position": Vector2(1000, 1000),
		"alive": true, "complete": true, "progress": 1.0,
		"hp": 2000.0, "max_hp": 2000.0})
	for r: String in ["wood", "gold", "oil", "food"]:
		gs.resources.add_resource("gnomes", r, 100000.0)
	var st := {"hall_pos": Vector2(1000, 1000), "maneuver": "expand",
		"war_b": "watch_tower", "barracks": 0, "houses": 0, "housing_gap": 0}
	return [gs, director, hall, st]


func _industrial_zones(gs: GameState) -> Array:
	var out: Array = []
	for z: Dictionary in gs.zoning.zones_of(SimZoning.INDUSTRIAL, "gnomes"):
		out.append(z)
	return out


## _ensure_industrial_zone paints a zone by the hall when none exists.
func _test_ai_paints_industrial_zone() -> void:
	var w := _new_ai_world()
	var gs: GameState = w[0]
	var director: SimAIDirector = w[1]
	_check("ai: no industrial zone at start", _industrial_zones(gs).is_empty())
	director._ensure_industrial_zone("gnomes", Vector2(1000, 1000))
	var zones := _industrial_zones(gs)
	_check("ai: industrial zone painted", zones.size() == 1)
	var rect: Rect2 = zones[0].get("rect", Rect2())
	_check("ai: zone by the hall",
		Vector2(1000, 1000).distance_to(rect.get_center()) < 900.0)


## _ensure_industrial_zone does not duplicate an existing zone.
func _test_ai_no_duplicate_industrial_zone() -> void:
	var w := _new_ai_world()
	var gs: GameState = w[0]
	var director: SimAIDirector = w[1]
	director._ensure_industrial_zone("gnomes", Vector2(1000, 1000))
	var before := _industrial_zones(gs).size()
	director._ensure_industrial_zone("gnomes", Vector2(1000, 1000))
	_check("ai: zone not duplicated", _industrial_zones(gs).size() == before)


## _inside_industrial returns a point inside the painted zone.
func _test_ai_pump_spot_inside_zone() -> void:
	var w := _new_ai_world()
	var gs: GameState = w[0]
	var director: SimAIDirector = w[1]
	director._ensure_industrial_zone("gnomes", Vector2(1000, 1000))
	var spot: Vector2 = director._inside_industrial("gnomes", Vector2(1000, 1000))
	var inside := false
	for z: Dictionary in _industrial_zones(gs):
		if (z.get("rect", Rect2()) as Rect2).has_point(spot):
			inside = true
	_check("ai: pump spot inside industrial zone", inside)


## The AI build queue lands exactly 4 oil pumps for the town, each inside an
## industrial zone (builders simulated by completing blueprints each round).
func _test_ai_builds_four_pumps_per_town() -> void:
	var w := _new_ai_world()
	var gs: GameState = w[0]
	var director: SimAIDirector = w[1]
	var hall: Dictionary = w[2]
	var st: Dictionary = w[3]
	var rounds := 0
	while director._count_build("gnomes", "oil_pump", 1) < 4 and rounds < 40:
		director._build_essentials("gnomes", hall, st)
		rounds += 1
		# Simulate builders: complete everything so UNFINISHED_CAP (8)
		# never blocks the pump placements.
		for b: Dictionary in gs.buildings:
			if String(b.get("faction", "")) == "gnomes":
				b["complete"] = true
				b["progress"] = 1.0
	var pumps: Array = []
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == "gnomes" \
				and int(b.get("town_id", -1)) == 1 \
				and String(b.get("type", "")) == "oil_pump" \
				and bool(b.get("alive", false)):
			pumps.append(b)
	_check("ai: 4 oil pumps built for the town", pumps.size() == 4)
	var all_inside := true
	for p: Dictionary in pumps:
		var pos: Vector2 = p.get("position", Vector2.ZERO)
		if gs.zoning.zone_at(pos, "gnomes") != SimZoning.INDUSTRIAL:
			all_inside = false
	_check("ai: all 4 pumps inside an industrial zone", all_inside)
