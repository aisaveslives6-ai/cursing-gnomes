extends SceneTree
## Cursing Gnomes — inter-faction trade route tests.
##
## Covers the dedicated-porting 2026-10-05 item "trade routes" (port of
## HTML fix79 ensureTradeRoute / dissolveTradeRoutes / spawnTradeWagon /
## updateTradeWagons / loadWagonCargo / deliverWagonCargo):
##   - ensure_route builds the triple dirt road, raises both outposts,
##     spawns 2 wagons (one each way); idempotent on repeat calls
##   - extra_wagons adds one wagon each way
##   - cargo math is HTML-verbatim (gold min(25, 2%+8), wood min(30, 2%+10),
##     food min(15, 3%+5)); sender pays on load, receiver gains on delivery
##   - wagons move toward their target, speed up 1.25x on roads, arrive
##     within 8px, deliver, turn around and reload
##   - wagons hold during war between the parties (no movement)
##   - dissolve_routes kills the route + wagons (outposts stand)
##   - diplomacy hooks: activate_trade / form_alliance open routes,
##     declare_war dissolves them
##   - save/load roundtrip preserves routes and wagons
##   - TradeWagonLayer builds wagon + puff draw commands, culls off-view
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_trade_routes.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes trade route tests ===")
	_test_cargo_math_verbatim()
	_test_ensure_route_builds_road_outposts_wagons()
	_test_ensure_route_idempotent()
	_test_extra_wagons()
	_test_no_hall_no_route()
	_test_wagon_moves_toward_target()
	_test_wagon_arrives_delivers_turns_around()
	_test_wagons_hold_during_war()
	_test_dissolve_routes()
	_test_activate_trade_opens_route()
	_test_form_alliance_opens_route()
	_test_declare_war_dissolves_route()
	_test_save_load_roundtrip()
	_test_wagon_layer_commands()
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


## Fresh game + worker AI + trade routes. player_faction defaults to "humans".
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var wai := WorkerAI.new(gs)
	var tr := SimTradeRoutes.new(gs)
	tr.worker_ai = wai
	gs.trade_routes = tr
	return {"gs": gs, "wai": wai, "tr": tr}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _hall(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({
		"type": "town_hall", "faction": faction, "town_id": -1,
		"position": pos, "complete": true, "progress": 1.0,
		"alive": true, "hp": 2000.0, "max_hp": 2000.0,
	})


func _fund(w: Dictionary, faction: String, amount: float) -> void:
	var gs: GameState = w["gs"]
	gs.resources.add_resource(faction, "gold", amount, true)
	gs.resources.add_resource(faction, "wood", amount, true)
	gs.resources.add_resource(faction, "food", amount, true)


## --- cargo math -----------------------------------------------------------------


func _test_cargo_math_verbatim() -> void:
	# HTML loadWagonCargo: gold min(25, 2%+8), wood min(30, 2%+10),
	# food min(15, 3%+5).
	var c: Dictionary = SimTradeRoutes.cargo_for(1000.0, 1000.0, 1000.0)
	_check("cargo: rich faction hits all caps",
		c["gold"] == 25.0 and c["wood"] == 30.0 and c["food"] == 15.0)
	var c2: Dictionary = SimTradeRoutes.cargo_for(100.0, 100.0, 100.0)
	_check("cargo: 100 stock -> 10/12/8",
		c2["gold"] == 10.0 and c2["wood"] == 12.0 and c2["food"] == 8.0)
	var c3: Dictionary = SimTradeRoutes.cargo_for(0.0, 0.0, 0.0)
	_check("cargo: broke faction still loads the base stipend",
		c3["gold"] == 8.0 and c3["wood"] == 10.0 and c3["food"] == 5.0)


## --- route lifecycle --------------------------------------------------------------


func _test_ensure_route_builds_road_outposts_wagons() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	var wai: WorkerAI = w["wai"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(2000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	var route := tr.ensure_route("humans", "ogres")
	_check("route created", not route.is_empty())
	_check("one live route", tr.routes.size() == 1)
	_check("2 initial wagons", tr.wagons.size() == 2)
	var dirs := {}
	for wagon in tr.wagons:
		dirs[String(wagon["from_race"])] = true
	_check("wagons leave from both halls",
		dirs.has("humans") and dirs.has("ogres"))
	_check("triple dirt road painted", wai.roads.size() >= 30)
	var dirt := 0
	for r in wai.roads:
		if String(r.get("type", "")) == "dirt":
			dirt += 1
	_check("trade road is dirt (HTML verbatim)", dirt == wai.roads.size())
	var outposts := 0
	for b in gs.buildings:
		if String(b.get("type", "")) == "trade_outpost":
			outposts += 1
	_check("2 trade outposts raised", outposts == 2)
	_check("outposts complete", _outposts_complete(gs))
	_free_world(w)


func _outposts_complete(gs: GameState) -> bool:
	for b in gs.buildings:
		if String(b.get("type", "")) == "trade_outpost" \
				and not bool(b.get("complete", false)):
			return false
	return true


func _test_ensure_route_idempotent() -> void:
	var w := _new_world()
	var tr: SimTradeRoutes = w["tr"]
	var wai: WorkerAI = w["wai"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(2000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	var r1 := tr.ensure_route("humans", "ogres")
	var roads1 := wai.roads.size()
	var r2 := tr.ensure_route("ogres", "humans")  # reversed pair
	_check("repeat call returns the same route",
		int(r1["id"]) == int(r2["id"]))
	_check("no duplicate route", tr.routes.size() == 1)
	_check("no extra wagons", tr.wagons.size() == 2)
	_check("no extra road paint", wai.roads.size() == roads1)
	_free_world(w)


func _test_extra_wagons() -> void:
	var w := _new_world()
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(2000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	tr.ensure_route("humans", "ogres", true)
	_check("extra_wagons adds one each way", tr.wagons.size() == 4)
	_free_world(w)


func _test_no_hall_no_route() -> void:
	var w := _new_world()
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	# ogres have no hall: HTML returns null.
	var route := tr.ensure_route("humans", "ogres")
	_check("no hall -> no route", route.is_empty())
	_check("no wagons spawned", tr.wagons.is_empty())
	_free_world(w)


## --- wagon movement -----------------------------------------------------------------


func _test_wagon_moves_toward_target() -> void:
	var w := _new_world()
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	tr.ensure_route("humans", "ogres")
	var wagon: Dictionary = tr.wagons[0]
	var before: float = (wagon["pos"] as Vector2) \
		.distance_to(wagon["target"] as Vector2)
	tr.tick(1.0)
	var after: float = (wagon["pos"] as Vector2) \
		.distance_to(wagon["target"] as Vector2)
	_check("wagon closes on its target", after < before)
	var moved := before - after
	_check("wagon speed in HTML band (40-55, road 1.25x)",
		moved >= 40.0 and moved <= 55.0 * 1.25 + 1.0)
	_free_world(w)


func _test_wagon_arrives_delivers_turns_around() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	tr.ensure_route("humans", "ogres")
	# Grab the humans->ogres wagon and park it on the ogre hall.
	var wagon: Dictionary = {}
	for wg in tr.wagons:
		if String(wg["from_race"]) == "humans":
			wagon = wg
	_check("found the humans wagon", not wagon.is_empty())
	var cargo: Dictionary = (wagon["cargo"] as Dictionary).duplicate()
	# Delivery in isolation: receiver gains exactly the wagon's cargo.
	var ogre_gold_before: float = gs.resources.get_amount("ogres", "gold")
	tr._deliver(wagon)
	var ogre_gold_after: float = gs.resources.get_amount("ogres", "gold")
	_check("cargo delivered to receiver",
		is_equal_approx(ogre_gold_after - ogre_gold_before,
			float(cargo["gold"])))
	# Arrival through tick: deliver + turn around + reload at the far hall.
	wagon["cargo"] = cargo.duplicate()
	wagon["pos"] = wagon["target"]  # on top of the target hall
	tr.tick(0.1)
	_check("wagon turned around (now ogres->humans)",
		String(wagon["from_race"]) == "ogres" \
		and String(wagon["to_race"]) == "humans")
	_check("wagon reloaded at the ogre hall",
		not (wagon["cargo"] as Dictionary).is_empty())
	_free_world(w)


func _test_wagons_hold_during_war() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	tr.ensure_route("humans", "ogres")
	# War without the declare_war dissolve path (defensive HTML parity:
	# updateTradeWagons skips movement while the pair is at war).
	gs.diplomacy._pair("humans", "ogres")["state"] = "war"
	var wagon: Dictionary = tr.wagons[0]
	var pos_before: Vector2 = wagon["pos"]
	tr.tick(1.0)
	_check("wagon holds position during war",
		(wagon["pos"] as Vector2) == pos_before)
	_free_world(w)


func _test_dissolve_routes() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	tr.ensure_route("humans", "ogres")
	var killed := tr.dissolve_routes("humans", "ogres")
	_check("dissolve reports 1 route", killed == 1)
	_check("route gone", tr.route_between("humans", "ogres").is_empty())
	_check("wagons gone", tr.wagons.is_empty())
	var outposts := 0
	for b in gs.buildings:
		if String(b.get("type", "")) == "trade_outpost":
			outposts += 1
	_check("outposts stand after dissolve (HTML parity)", outposts == 2)
	_check("dissolve of nothing returns 0",
		tr.dissolve_routes("humans", "elves") == 0)
	_free_world(w)


## --- diplomacy hooks ------------------------------------------------------------------


func _test_activate_trade_opens_route() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	gs.diplomacy.activate_trade("humans", "ogres", 3)
	_check("trade deal opens a physical route",
		not tr.route_between("humans", "ogres").is_empty())
	_check("wagons rolling", tr.wagons.size() == 2)
	_free_world(w)


func _test_form_alliance_opens_route() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "elves", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "elves", 1000.0)
	gs.diplomacy.form_alliance("humans", "elves")
	_check("alliance opens a trade route",
		not tr.route_between("humans", "elves").is_empty())
	_free_world(w)


func _test_declare_war_dissolves_route() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	gs.diplomacy.activate_trade("humans", "ogres", 3)
	_check("route open before war",
		not tr.route_between("humans", "ogres").is_empty())
	gs.diplomacy.declare_war("humans", "ogres", "test")
	_check("war dissolves the route",
		tr.route_between("humans", "ogres").is_empty())
	_check("war removes the wagons", tr.wagons.is_empty())
	_free_world(w)


## --- save / load ------------------------------------------------------------------------


func _test_save_load_roundtrip() -> void:
	var w := _new_world()
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	tr.ensure_route("humans", "ogres")
	tr.tick(0.5)  # wagons mid-road
	var data := tr.to_dict()
	var w2 := _new_world()
	var tr2: SimTradeRoutes = w2["tr"]
	_hall(w2, "humans", Vector2(1000, 1000))
	_hall(w2, "ogres", Vector2(4000, 1000))
	tr2.from_dict(data)
	_check("routes survive save/load", tr2.routes.size() == 1)
	_check("wagons survive save/load", tr2.wagons.size() == 2)
	var a: Dictionary = tr.wagons[0]
	var b: Dictionary = tr2.wagons[0]
	_check("wagon positions survive",
		(a["pos"] as Vector2).distance_to(b["pos"] as Vector2) < 0.01)
	_check("wagon cargo survives",
		float((a["cargo"] as Dictionary)["gold"]) \
		== float((b["cargo"] as Dictionary)["gold"]))
	_free_world(w)
	_free_world(w2)


## --- wagon layer --------------------------------------------------------------------------


func _test_wagon_layer_commands() -> void:
	var layer := TradeWagonLayer.new()
	root.add_child(layer)
	layer.set_provider(func() -> Array:
		return [{
			"pos": Vector2(500, 500),
			"from_race": "gnomes",
			"facing": 1.0,
			"bob": 0.0,
		}])
	layer._process(0.1)
	var wagons := 0
	var puffs := 0
	for c in layer._commands:
		if String(c["kind"]) == "wagon":
			wagons += 1
			_check("wagon command carries faction color",
				(c["color"] as Color) == Color(0.9, 0.6, 0.2))  # gnomes
		elif String(c["kind"]) == "puff":
			puffs += 1
	_check("layer builds one wagon command", wagons == 1)
	_check("layer is visible while wagons roll", layer.visible)
	# Empty provider -> layer hides itself (zero per-frame cost).
	layer.set_provider(func() -> Array: return [])
	layer._process(0.1)
	_check("layer hides when no wagons", not layer.visible)
	layer.free()
