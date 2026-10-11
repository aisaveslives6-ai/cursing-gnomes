extends SceneTree
## Cursing Gnomes — power tap menu (Jeremy 2026-10-11).
##
## Tapping a foreign faction's land opens the contextual power menu:
## Send Aid (resources / builder crew / relief caravan), Propose Trade,
## Offer Tribute, Message Leader, Request Aid, plus military orders when
## the player has an army. Aid reuses the disaster-aid mission driver and
## relations model; aid to war enemies is blocked.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_power_tap.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed := 0
var _failed := 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		push_error("FAIL: " + test_name)


func _initialize() -> void:
	_test_menu_action_lists()
	_test_aid_submenu_lists()
	_test_dispatch_builders()
	_test_dispatch_blocked_at_war()
	_test_dispatch_needs_crew()
	_test_dispatch_one_mission_per_faction()
	_test_resource_aid()
	_test_resource_aid_broke()
	_test_resource_aid_daily_cap()
	_test_mission_completes_and_boosts()
	_test_territory_owner_routing()
	print("=== power tap: %d passed, %d failed ===" % [_passed, _failed])
	for f in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## Fresh headless game: player = humans; systems wired like World does.
func _make_game() -> GameState:
	var gs := GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres", "elves", "undead"])
	gs.disaster_aid = SimDisasterAid.new(gs)
	gs.trade_deals = SimTradeDeals.new(gs)
	return gs


func _ids(actions: Array) -> Array[String]:
	var out: Array[String] = []
	for a in actions:
		out.append(String((a as Dictionary).get("id", "")))
	return out


func _test_menu_action_lists() -> void:
	var peace_army := _ids(Hud.power_menu_actions("peace", true))
	_check("menu has send aid", peace_army.has("aid"))
	_check("menu has propose trade", peace_army.has("trade"))
	_check("menu has offer tribute", peace_army.has("tribute"))
	_check("menu has message leader", peace_army.has("message"))
	_check("menu has request aid", peace_army.has("request_aid"))
	_check("menu has move army with military", peace_army.has("move_army"))
	_check("menu has attack-move with military",
		peace_army.has("attack_move"))
	_check("menu has cancel", peace_army.has("cancel"))
	var peace_no_army := _ids(Hud.power_menu_actions("peace", false))
	_check("no military actions without army",
		not peace_no_army.has("move_army")
		and not peace_no_army.has("attack_move"))
	_check("aid still offered without army", peace_no_army.has("aid"))


func _test_aid_submenu_lists() -> void:
	var aid := _ids(Hud.power_aid_actions())
	_check("aid submenu: food", aid.has("aid_food"))
	_check("aid submenu: wood", aid.has("aid_wood"))
	_check("aid submenu: gold", aid.has("aid_gold"))
	_check("aid submenu: builders", aid.has("aid_builders"))
	_check("aid submenu: caravan", aid.has("aid_caravan"))
	_check("aid submenu: back", aid.has("back"))
	var trib := _ids(Hud.power_tribute_actions())
	_check("tribute submenu: gold", trib.has("trib_gold"))
	_check("tribute submenu: back", trib.has("back"))


## Player with a free builder sends a crew to the elves.
func _aided_game() -> GameState:
	var gs := _make_game()
	gs.add_unit({"faction": "humans", "job": "builder",
		"position": Vector2(50, 50), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "speed": 55.0})
	gs.add_building({"type": "town_hall", "faction": "elves",
		"position": Vector2(900, 900), "alive": true, "complete": true,
		"hp": 50.0, "max_hp": 100.0})
	return gs


func _test_dispatch_builders() -> void:
	var gs := _aided_game()
	var r: Dictionary = gs.disaster_aid.dispatch_player_aid(
		"elves", Vector2(900, 900))
	_check("builder dispatch ok", bool(r.get("ok", false)))
	var missions: Array = gs.disaster_aid.missions_for("elves")
	_check("mission registered", missions.size() == 1)
	var tagged := false
	for u in gs.units:
		if String(u.get("faction", "")) == "humans" and u.has("aid_mission"):
			tagged = true
	_check("helper unit tagged with aid_mission", tagged)


func _test_dispatch_blocked_at_war() -> void:
	var gs := _aided_game()
	gs.diplomacy.declare_war("humans", "elves", "test")
	var r: Dictionary = gs.disaster_aid.dispatch_player_aid(
		"elves", Vector2(900, 900))
	_check("builder aid blocked at war", not bool(r.get("ok", false)))
	_check("war block message mentions war",
		String(r.get("msg", "")).to_lower().contains("war"))
	var r2: Dictionary = gs.disaster_aid.send_player_resources(
		"elves", "food", 100.0)
	_check("resource aid blocked at war", not bool(r2.get("ok", false)))


func _test_dispatch_needs_crew() -> void:
	var gs := _make_game()
	gs.add_building({"type": "town_hall", "faction": "elves",
		"position": Vector2(900, 900), "alive": true, "complete": true,
		"hp": 50.0, "max_hp": 100.0})
	var r: Dictionary = gs.disaster_aid.dispatch_player_aid(
		"elves", Vector2(900, 900))
	_check("dispatch refused with no crew", not bool(r.get("ok", false)))


func _test_dispatch_one_mission_per_faction() -> void:
	var gs := _aided_game()
	gs.add_unit({"faction": "humans", "job": "worker",
		"position": Vector2(60, 60), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "speed": 55.0})
	var r1: Dictionary = gs.disaster_aid.dispatch_player_aid(
		"elves", Vector2(900, 900))
	_check("first dispatch ok", bool(r1.get("ok", false)))
	var r2: Dictionary = gs.disaster_aid.dispatch_player_aid(
		"elves", Vector2(900, 900))
	_check("second dispatch to same faction blocked",
		not bool(r2.get("ok", false)))


func _res_game() -> GameState:
	var gs := _make_game()
	gs.resources.add_resource("humans", "food", 500.0)
	gs.resources.add_resource("humans", "wood", 500.0)
	gs.resources.add_resource("humans", "gold", 500.0)
	return gs


func _test_resource_aid() -> void:
	var gs := _res_game()
	var before: float = gs.diplomacy.relation_score("elves", "humans")
	var r: Dictionary = gs.disaster_aid.send_player_resources(
		"elves", "food", 100.0)
	_check("resource aid ok", bool(r.get("ok", false)))
	_check("sent amount reported", float(r.get("sent", 0.0)) == 100.0)
	_check("player stockpile debited",
		gs.resources.get_amount("humans", "food") == 400.0)
	_check("victim stockpile credited",
		gs.resources.get_amount("elves", "food") == 100.0)
	_check("relations warmed",
		gs.diplomacy.relation_score("elves", "humans") > before)


func _test_resource_aid_broke() -> void:
	var gs := _make_game()
	var r: Dictionary = gs.disaster_aid.send_player_resources(
		"elves", "food", 100.0)
	_check("broke player cannot send", not bool(r.get("ok", false)))


func _test_resource_aid_daily_cap() -> void:
	var gs := _res_game()
	var ok := 0
	for i in 4:
		var r: Dictionary = gs.disaster_aid.send_player_resources(
			"elves", "food", 10.0)
		if bool(r.get("ok", false)):
			ok += 1
	_check("daily cap allows 3, blocks 4th", ok == 3)


## Fast-forward the mission: helpers repair, duration expires, they return.
func _test_mission_completes_and_boosts() -> void:
	var gs := _aided_game()
	var before: float = gs.diplomacy.relation_score("elves", "humans")
	var r: Dictionary = gs.disaster_aid.dispatch_player_aid(
		"elves", Vector2(900, 900))
	_check("dispatch ok", bool(r.get("ok", false)))
	var m: Dictionary = gs.disaster_aid.missions_for("elves")[0]
	m["until_day"] = gs.day_number  # expire immediately
	# Drive ticks until every helper is home.
	for i in 200:
		gs.disaster_aid.tick(1.0)
		var done := true
		for u in gs.units:
			if u.has("aid_mission"):
				done = false
		if done:
			break
	var home := true
	for u in gs.units:
		if u.has("aid_mission"):
			home = false
	_check("helpers returned home", home)
	_check("mission marked done", String(m.get("status", "")) == "done")
	_check("relations boosted well past dispatch bump",
		gs.diplomacy.relation_score("elves", "humans") >= before + 15.0)


## Tap routing: foreign claimed land resolves to the tapped faction.
func _test_territory_owner_routing() -> void:
	var gs := _make_game()
	gs.add_building({"type": "town_hall", "faction": "elves",
		"position": Vector2(900, 900), "alive": true, "complete": true,
		"hp": 100.0, "max_hp": 100.0})
	var owner := SimTerritory.claim_owner_at(
		gs.buildings, Vector2(920, 920))
	_check("tap on elf town resolves to elves", owner == "elves")
	var empty := SimTerritory.claim_owner_at(
		gs.buildings, Vector2(5000, 5000))
	_check("tap on empty land resolves to nobody", empty == "")
