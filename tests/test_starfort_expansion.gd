extends SceneTree
## Cursing Gnomes — StarFortBases live-wiring + lane-7 expansion tests.
##
## Covers what the sibling lane wired and what lane 7 added:
##   1. Wiring: starfort_bases is owned by game_state, ticks (AI commits one
##      fort per town), and round-trips through SaveSystem snapshot/restore.
##   2. Sovereignty: the AI tick never auto-builds for the player faction.
##   3. Ruler's Voice: "build a star fort" / "build a star fort at <town>"
##      commits a fort via the explicit player order path (advisors never
##      auto-do it); pending orders are polled.
##   4. Garrison + artillery: forts_of/garrison_report count troops and
##      artillery; SimGarrison homes troops at the fort.
##   5. War scoring: forts are snapshotted at war start and count in
##      _war_score when they change hands.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_starfort_expansion.gd

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


func _initialize() -> void:
	_test_ai_tick_wiring()
	_test_player_never_auto_built()
	_test_save_load_roundtrip()
	_test_rulers_voice_order()
	_test_rulers_voice_order_named_town()
	_test_rulers_voice_broke()
	_test_garrison_report_and_home()
	_test_war_score_forts()
	_test_order_fort_reasons()
	print("=== starfort expansion: %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _new_world(factions: Array[String]) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	gs.player_faction = factions[0]
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0, "water_bodies": []}
	# Mirror world.gd wiring (lane 7 / sibling lane).
	gs.starfort_bases = StarFortBases.new(gs)
	return {
		"gs": gs,
		"bases": gs.starfort_bases,
		"buildings": SimBuildings.new(gs),
		"wall_drag": WallDrag.new(),
	}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _give(gs: GameState, faction: String, amount: float = 100000.0) -> void:
	for res: String in Config.RESOURCES:
		gs.resources.add_resource(faction, res, amount, true)


func _add(w: Dictionary, faction: String, btype: String, town_id: int,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({
		"type": btype, "faction": faction, "town_id": town_id,
		"position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 400.0, "max_hp": 400.0,
	})


func _town(w: Dictionary, faction: String, tname: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	var town: Dictionary = gs.found_town(faction, tname, pos)
	var hall: Dictionary = _add(w, faction, "town_hall", int(town["id"]), pos)
	return {"town": town, "hall": hall}


func _fort_buildings(w: Dictionary, faction: String) -> Array:
	var gs: GameState = w["gs"]
	var out: Array = []
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == faction \
				and String(b.get("fort_plan", "")) == "star":
			out.append(b)
	return out


## --- 1. wiring ---------------------------------------------------------------


func _test_ai_tick_wiring() -> void:
	var w := _new_world(["humans", "elves"])
	var gs: GameState = w["gs"]
	var bases: StarFortBases = w["bases"]
	var th := _town(w, "elves", "Elftown", Vector2(1000, 1000))
	_add(w, "elves", "barracks", int(th["town"]["id"]), Vector2(1050, 1000))
	_add(w, "elves", "barracks", int(th["town"]["id"]), Vector2(950, 1000))
	_give(gs, "elves")
	_check("wiring: starfort_bases owned by game_state", gs.starfort_bases == bases)
	bases.tick("elves", false, w["buildings"], w["wall_drag"])
	var built := _fort_buildings(w, "elves")
	_check("wiring: AI tick commits a fort for AI town", not built.is_empty())
	_check("wiring: fort recorded in forts dict",
		bases.forts.has(int(th["hall"]["id"])))
	var rec: Dictionary = bases.forts[int(th["hall"]["id"])]
	_check("wiring: fort rec has center+radius",
		rec.has("center") and rec.has("radius"))
	_free_world(w)


func _test_player_never_auto_built() -> void:
	var w := _new_world(["humans", "elves"])
	var gs: GameState = w["gs"]
	var bases: StarFortBases = w["bases"]
	var th := _town(w, "humans", "Hometown", Vector2(1000, 1000))
	_add(w, "humans", "barracks", int(th["town"]["id"]), Vector2(1050, 1000))
	_add(w, "humans", "barracks", int(th["town"]["id"]), Vector2(950, 1000))
	_give(gs, "humans")
	bases.tick("humans", true, w["buildings"], w["wall_drag"])
	_check("sovereignty: AI tick never builds for the player",
		_fort_buildings(w, "humans").is_empty())
	_check("sovereignty: no fort record for player town", bases.forts.is_empty())
	_free_world(w)


## --- 2. save/load --------------------------------------------------------------


func _test_save_load_roundtrip() -> void:
	var w := _new_world(["humans", "elves"])
	var gs: GameState = w["gs"]
	var bases: StarFortBases = w["bases"]
	var th := _town(w, "elves", "Elftown", Vector2(1000, 1000))
	_add(w, "elves", "barracks", int(th["town"]["id"]), Vector2(1050, 1000))
	_add(w, "elves", "barracks", int(th["town"]["id"]), Vector2(950, 1000))
	_give(gs, "elves")
	bases.tick("elves", false, w["buildings"], w["wall_drag"])
	var hid := int(th["hall"]["id"])
	var center0: Vector2 = (bases.forts[hid] as Dictionary)["center"]
	var snap: Dictionary = SaveSystem.snapshot(gs)
	# Restore into a fresh wired world (like Continue does).
	var w2 := _new_world(["humans", "elves"])
	var gs2: GameState = w2["gs"]
	var ok := SaveSystem.restore(gs2, snap)
	var bases2: StarFortBases = w2["bases"]
	_check("save: snapshot/restore succeeds", ok)
	_check("save: fort survives restore", bases2.forts.has(hid))
	if bases2.forts.has(hid):
		var c2: Vector2 = (bases2.forts[hid] as Dictionary)["center"]
		_check("save: fort center preserved", c2.distance_to(center0) < 1.0)
	_free_world(w)
	_free_world(w2)


## --- 3. Ruler's Voice orders -----------------------------------------------------


func _make_rv_world() -> Array:
	var w := _new_world(["humans", "elves"])
	var gs: GameState = w["gs"]
	var th := _town(w, "humans", "Testville", Vector2(2000, 2000))
	_give(gs, "humans")
	gs.army = SimArmy.new(gs)
	var adv: Dictionary = gs.add_unit({"faction": "humans",
		"job": "advisor_economy", "town_id": int(th["town"]["id"]),
		"position": Vector2(2000, 2010), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0, "name": "Test Advisor"})
	adv["is_advisor"] = true
	var rv := SimRulersVoice.new(gs)
	gs.rulers_voice = rv
	return [w, gs, rv, adv, th]


func _free_rv(parts: Array) -> void:
	_free_world(parts[0])


func _test_rulers_voice_order() -> void:
	var parts := _make_rv_world()
	var w: Dictionary = parts[0]
	var gs: GameState = parts[1]
	var rv: SimRulersVoice = parts[2]
	var adv: Dictionary = parts[3]
	var before := gs.buildings.size()
	var ack := rv.try_order(adv, "build a star fort")
	_check("rv: ack non-empty", ack != "")
	_check("rv: ack mentions fort", ack.to_lower().contains("fort"))
	_check("rv: fort blueprints placed", gs.buildings.size() > before)
	var tagged := 0
	for b: Dictionary in gs.buildings:
		if bool(b.get("player_placed", false)) \
				and String(b.get("fort_plan", "")) == "star":
			tagged += 1
	_check("rv: placed fort tagged player_placed", tagged > 0)
	var tracked := 0
	for o: Dictionary in rv._pending:
		if String(o.get("kind", "")) == "starfort":
			tracked += 1
	_check("rv: starfort order tracked pending", tracked == 1)
	var hid := int((parts[4] as Dictionary)["hall"]["id"])
	_check("rv: fort recorded in forts dict",
		(w["bases"] as StarFortBases).forts.has(hid))
	# Player order is the only path: second order is refused as duplicate.
	var ack2 := rv.try_order(adv, "build a star fort")
	_check("rv: duplicate fort refused", ack2.to_lower().contains("already"))
	_free_rv(parts)


func _test_rulers_voice_order_named_town() -> void:
	var parts := _make_rv_world()
	var w: Dictionary = parts[0]
	var gs: GameState = parts[1]
	var rv: SimRulersVoice = parts[2]
	var adv: Dictionary = parts[3]
	_town(w, "humans", "Farburg", Vector2(500, 500))
	var ack := rv.try_order(adv, "build a star fort at farburg")
	_check("rv: named-town order acks", ack.to_lower().contains("fort"))
	var bases: StarFortBases = w["bases"]
	var far_hid := -1
	for hid: Variant in bases.forts.keys():
		var rec := bases.forts[hid] as Dictionary
		if int(rec.get("town_id", -1)) == 2:
			far_hid = int(hid)
	_check("rv: named town got the fort", far_hid >= 0)
	_check("rv: ack names the town", ack.to_lower().contains("farburg"))
	_free_rv(parts)


func _test_rulers_voice_broke() -> void:
	var parts := _make_rv_world()
	var gs: GameState = parts[1]
	var rv: SimRulersVoice = parts[2]
	var adv: Dictionary = parts[3]
	# Drain the treasury: no coin, no fort.
	for res: String in Config.RESOURCES:
		gs.resources.add_resource("humans", res, -100000.0, true)
	var ack := rv.try_order(adv, "build a star fort")
	_check("rv: broke order refused plainly",
		ack.to_lower().contains("coffers") or ack.to_lower().contains("coin"))
	_free_rv(parts)


## --- 4. garrison + artillery -----------------------------------------------------


func _test_garrison_report_and_home() -> void:
	var w := _new_world(["humans", "elves"])
	var gs: GameState = w["gs"]
	var bases: StarFortBases = w["bases"]
	var th := _town(w, "humans", "Hometown", Vector2(2000, 2000))
	_add(w, "humans", "barracks", int(th["town"]["id"]), Vector2(2050, 2000))
	_add(w, "humans", "barracks", int(th["town"]["id"]), Vector2(1950, 2000))
	_give(gs, "humans")
	var res: Dictionary = bases.order_fort("humans", int(th["hall"]["id"]),
		int(th["town"]["id"]), Vector2(2000, 2000), w["buildings"],
		w["wall_drag"])
	_check("garrison: order_fort commits", bool(res.get("ok", false)))
	var center: Vector2 = (res["fort"] as Dictionary)["center"]
	# Troops stationed at the fort.
	gs.add_unit({"faction": "humans", "job": "soldier",
		"position": center + Vector2(30, 0), "alive": true,
		"hp": 100.0, "max_hp": 100.0})
	gs.add_unit({"faction": "humans", "job": "archer",
		"position": center + Vector2(-40, 20), "alive": true,
		"hp": 100.0, "max_hp": 100.0})
	gs.add_unit({"faction": "humans", "job": "farmer",
		"position": center + Vector2(10, 10), "alive": true,
		"hp": 100.0, "max_hp": 100.0})
	# Artillery parked at the fort.
	var arty := SimArtillery.new(gs)
	gs.arty = arty
	arty.vehicles.append({"id": 1, "type": "cannon", "faction": "humans",
		"town_id": int(th["town"]["id"]), "position": center + Vector2(60, -20),
		"alive": true, "parked": true})
	var report: Array = bases.garrison_report("humans")
	_check("garrison: report has one fort", report.size() == 1)
	if not report.is_empty():
		var r := report[0] as Dictionary
		_check("garrison: 2 military troops counted", int(r["troops"]) == 2)
		_check("garrison: by_job breakdown",
			int((r["by_job"] as Dictionary).get("soldier", 0)) == 1 \
			and int((r["by_job"] as Dictionary).get("archer", 0)) == 1)
		_check("garrison: artillery counted", int(r["artillery"]) == 1)
	# SimGarrison homes troops at the star fort first.
	var g := SimGarrison.new(gs, null)
	var home: Vector2 = g._base_home("humans")
	_check("garrison: base home is the fort",
		home.distance_to(center) < 1.0)
	_free_world(w)


## --- 5. war scoring ----------------------------------------------------------------


func _test_war_score_forts() -> void:
	var parts := _make_rv_world()
	var gs: GameState = parts[1]
	var rv: SimRulersVoice = parts[2]
	var adv: Dictionary = parts[3]
	var ack := rv.try_order(adv, "build a star fort")
	_check("war: fort order placed for war test", ack.to_lower().contains("fort"))
	# War starts: snapshot holders.
	var rec: Dictionary = rv._new_war_record("elves")
	_check("war: forts0 snapshotted", not (rec.get("forts0", {}) as Dictionary).is_empty())
	# The town (and its fort) falls to the enemy.
	gs.towns[1]["faction"] = "elves"
	var ws: Dictionary = rv._war_score("humans|elves", rec)
	_check("war: lost fort raises score", float(ws["score"]) > 0.0)
	var reasons: Array = ws["reasons"]
	var mentions := false
	for r2: String in reasons:
		if r2.to_lower().contains("star fort"):
			mentions = true
	_check("war: reasons mention the star fort", mentions)
	_free_rv(parts)


## --- order_fort reasons -------------------------------------------------------------


func _test_order_fort_reasons() -> void:
	var w := _new_world(["humans", "elves"])
	var gs: GameState = w["gs"]
	var bases: StarFortBases = w["bases"]
	var th := _town(w, "humans", "Hometown", Vector2(2000, 2000))
	_give(gs, "humans")
	var r1: Dictionary = bases.order_fort("humans", int(th["hall"]["id"]),
		int(th["town"]["id"]), Vector2(2000, 2000), w["buildings"],
		w["wall_drag"])
	_check("order: first fort ok", bool(r1.get("ok", false)))
	var r2: Dictionary = bases.order_fort("humans", int(th["hall"]["id"]),
		int(th["town"]["id"]), Vector2(2000, 2000), w["buildings"],
		w["wall_drag"])
	_check("order: duplicate -> has_fort",
		not bool(r2.get("ok", false)) \
		and String(r2.get("reason", "")) == "has_fort")
	# Broke faction.
	var th2 := _town(w, "elves", "Elftown", Vector2(800, 800))
	var r3: Dictionary = bases.order_fort("elves", int(th2["hall"]["id"]),
		int(th2["town"]["id"]), Vector2(800, 800), w["buildings"],
		w["wall_drag"])
	_check("order: broke -> broke",
		not bool(r3.get("ok", false)) \
		and String(r3.get("reason", "")) == "broke")
	_free_world(w)
