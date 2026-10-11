extends SceneTree
## Cursing Gnomes — trade route playability headless tests (Jeremy 2026-10-05).
##
## Covers the gate-1 deep systems pass on trade routes (no dead ends or
## silent failures):
##   - break_treaty (trade deal OR alliance) dissolves the physical route —
##     wagons must not run for a dead deal
##   - deal expiry in diplomacy _daily() dissolves the physical route
##   - an insult that strains an alliance to neutral dissolves the route
##   - a razed hall leaves no zombie route: wagons die on arrival and the
##     widowed record is purged by tick
##   - ensure_route revives a wagon-less record (same route id, pair re-seeds)
##     instead of returning a husk that can never trade again
##   - boost_routes (HTML boost_trade production hook) adds one wagon each
##     way on every route touching the faction
##   - the mayor_caravan court petition funds caravans (grant / honest
##     shortfall when broke / refuse)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_trade_routes_playability.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes trade-route playability tests ===")
	_test_break_treaty_dissolves_route()
	_test_break_alliance_dissolves_route()
	_test_deal_expiry_dissolves_route()
	_test_insult_strain_dissolves_route()
	_test_razed_hall_purges_zombie_route()
	_test_ensure_route_revives_wagonless()
	_test_boost_routes()
	_test_mayor_caravan_grant()
	_test_mayor_caravan_shortfall()
	_test_mayor_caravan_refuse()
	_test_caravan_template_gate()
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
	gs.setup(["humans", "ogres", "elves"])
	_stories.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
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


func _open_route(w: Dictionary) -> void:
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	(w["tr"] as SimTradeRoutes).ensure_route("humans", "ogres")


## --- deal-end paths dissolve the physical route --------------------------------


func _test_break_treaty_dissolves_route() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_open_route(w)
	gs.diplomacy.activate_trade("humans", "ogres", 3)
	_check("route open before break", not tr.route_between("humans", "ogres").is_empty())
	var res: Dictionary = gs.diplomacy.break_treaty("humans", "ogres")
	_check("break accepted", bool(res.get("ok", false)))
	_check("break dissolves the route",
		tr.route_between("humans", "ogres").is_empty())
	_check("break removes the wagons", tr.wagons.is_empty())
	_free_world(w)


func _test_break_alliance_dissolves_route() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	gs.diplomacy.form_alliance("humans", "ogres")
	_check("alliance opened a route",
		not tr.route_between("humans", "ogres").is_empty())
	var res: Dictionary = gs.diplomacy.break_treaty("humans", "ogres")
	_check("alliance break accepted", bool(res.get("ok", false)))
	_check("alliance break dissolves the route",
		tr.route_between("humans", "ogres").is_empty())
	_check("alliance break removes the wagons", tr.wagons.is_empty())
	_free_world(w)


func _test_deal_expiry_dissolves_route() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_open_route(w)
	gs.diplomacy.activate_trade("humans", "ogres", 3)
	_check("route open before expiry",
		not tr.route_between("humans", "ogres").is_empty())
	gs.day_number += 4  # past trade_until_day
	gs.diplomacy._daily()
	_check("expiry clears trade_active",
		not bool(gs.diplomacy._pair("humans", "ogres").get("trade_active", true)))
	_check("expiry dissolves the route",
		tr.route_between("humans", "ogres").is_empty())
	_check("expiry removes the wagons", tr.wagons.is_empty())
	_free_world(w)


func _test_insult_strain_dissolves_route() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	gs.diplomacy.form_alliance("humans", "ogres")
	_check("route open before insult",
		not tr.route_between("humans", "ogres").is_empty())
	gs.diplomacy.insult("humans", "ogres", "")
	_check("insult strained the alliance",
		String(gs.diplomacy._pair("humans", "ogres").get("state", "")) == "neutral")
	_check("insult strain dissolves the route",
		tr.route_between("humans", "ogres").is_empty())
	_check("insult strain removes the wagons", tr.wagons.is_empty())
	_free_world(w)


## --- razed halls leave no zombie routes -------------------------------------------


func _test_razed_hall_purges_zombie_route() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	var ogre_hall := _hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	tr.ensure_route("humans", "ogres")
	var rid := int(tr.route_between("humans", "ogres").get("id", -1))
	# Raze the ogre hall, then drive every wagon into its missing hall.
	gs.erase_building(ogre_hall)
	for wg in tr.wagons:
		wg["pos"] = wg["target"]
	tr.tick(0.1)
	_check("wagons all dead after hall razed", tr.wagons.is_empty())
	_check("widowed route record purged",
		tr.route_between("humans", "ogres").is_empty())
	_check("no route keeps the old id", tr._route_by_id(rid).is_empty())
	_free_world(w)


func _test_ensure_route_revives_wagonless() -> void:
	var w := _new_world()
	var tr: SimTradeRoutes = w["tr"]
	_open_route(w)
	var rid := int(tr.route_between("humans", "ogres").get("id", -1))
	# Lose every wagon (raided, eaten, whatever) — record survives.
	for wg in tr.wagons:
		wg["dead"] = true
	tr.tick(0.1)
	_check("wagons swept", tr.wagons.is_empty())
	_check("record survives while halls stand",
		not tr.route_between("humans", "ogres").is_empty())
	# A new deal must restart trade, not return a husk.
	var route := tr.ensure_route("humans", "ogres")
	_check("revive keeps the same route", int(route.get("id", -1)) == rid)
	_check("revive re-seeds the pair", tr.wagons.size() == 2)
	_check("no duplicate record", tr.routes.size() == 1)
	_free_world(w)


## --- boost_trade production hook ----------------------------------------------------


func _test_boost_routes() -> void:
	var w := _new_world()
	var tr: SimTradeRoutes = w["tr"]
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_hall(w, "elves", Vector2(1000, 4000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	_fund(w, "elves", 1000.0)
	tr.ensure_route("humans", "ogres")
	tr.ensure_route("humans", "elves")
	_check("two routes, four wagons", tr.wagons.size() == 4)
	var added: int = tr.boost_routes("humans")
	_check("boost adds one each way per touching route", added == 4)
	_check("wagons doubled", tr.wagons.size() == 8)
	var added2: int = tr.boost_routes("ogres")
	_check("ogres touch one route", added2 == 2)
	_check("ogre boost wagons roll", tr.wagons.size() == 10)
	_check("uninvolved faction boosts nothing",
		tr.boost_routes("gnomes") == 0)
	_free_world(w)


## --- mayor_caravan court petition -----------------------------------------------------


## Court + mayor + live route, mirroring test_royal_court_playability.
func _court_world() -> Dictionary:
	var w := _new_world()
	var gs: GameState = w["gs"]
	for i in 6:
		gs.add_unit({"faction": "humans", "job": "worker", "town_id": 1,
			"position": Vector2(200, 200), "alive": true, "hp": 100.0,
			"max_hp": 100.0, "mind": {}})
	var army := SimArmy.new(gs)
	army.ensure_government("humans")
	_hall(w, "humans", Vector2(1000, 1000))
	_hall(w, "ogres", Vector2(4000, 1000))
	_fund(w, "humans", 1000.0)
	_fund(w, "ogres", 1000.0)
	(w["tr"] as SimTradeRoutes).ensure_route("humans", "ogres")
	var court := SimRoyalCourt.new(gs)
	w["court"] = court
	return w


func _mayor(w: Dictionary) -> Dictionary:
	var gs: GameState = w["gs"]
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == gs.player_faction \
				and String((u.get("mind", {}) as Dictionary).get("gov_role", "")) == "mayor":
			return u
	return {}


func _craft_caravan(w: Dictionary) -> Dictionary:
	var court: SimRoyalCourt = w["court"]
	var holder := _mayor(w)
	if holder.is_empty():
		return {}
	var p: Dictionary = court.petition(holder, "mayor_caravan",
		"thin trickles, sire", ["Fund Caravans (100g)", "Refuse"])
	p["tpl"] = "mayor_caravan"
	return p


func _test_mayor_caravan_grant() -> void:
	var w := _court_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	var court: SimRoyalCourt = w["court"]
	var p := _craft_caravan(w)
	_check("petition crafted", not p.is_empty())
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	court.decide(int(p.get("id", -1)), 0)
	# The grant costs 100 gold; the new human wagon also loads its cargo
	# on spawn (HTML parity — wagons always leave loaded).
	var cargo_gold: float = float(SimTradeRoutes.cargo_for(
		gold_before - 100.0, 0.0, 0.0)["gold"])
	_check("grant costs 100 gold (+ the new wagon's cargo)",
		is_equal_approx(gold_before - gs.resources.get_amount("humans", "gold"),
			100.0 + cargo_gold))
	_check("grant adds a wagon each way", tr.wagons.size() == 4)
	_check("grant publishes a story", _stories.size() >= 1)
	_free_world(w)


func _test_mayor_caravan_shortfall() -> void:
	var w := _court_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	var court: SimRoyalCourt = w["court"]
	# Bare coffers: the grant must fail loudly, spending nothing.
	gs.resources.add_resource("humans", "gold",
		-gs.resources.get_amount("humans", "gold"))
	var p := _craft_caravan(w)
	court.decide(int(p.get("id", -1)), 0)
	_check("shortfall spends no gold",
		gs.resources.get_amount("humans", "gold") == 0.0)
	_check("shortfall adds no wagons", tr.wagons.size() == 2)
	_check("shortfall publishes an honest story", _stories.size() >= 1)
	_free_world(w)


func _test_mayor_caravan_refuse() -> void:
	var w := _court_world()
	var gs: GameState = w["gs"]
	var tr: SimTradeRoutes = w["tr"]
	var court: SimRoyalCourt = w["court"]
	var p := _craft_caravan(w)
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	court.decide(int(p.get("id", -1)), 1)
	_check("refuse spends no gold",
		is_equal_approx(gs.resources.get_amount("humans", "gold"), gold_before))
	_check("refuse adds no wagons", tr.wagons.size() == 2)
	_free_world(w)


func _test_caravan_template_gate() -> void:
	var w := _court_world()
	var court: SimRoyalCourt = w["court"]
	_check("caravan template eligible with a live route",
		court._template_when_ok({"when": "traderoute"}))
	_free_world(w)
	var w2 := _new_world()
	var gs2: GameState = w2["gs"]
	_hall(w2, "humans", Vector2(1000, 1000))
	var court2 := SimRoyalCourt.new(gs2)
	_check("caravan template ineligible with no route",
		not court2._template_when_ok({"when": "traderoute"}))
	_free_world(w2)
