extends SceneTree
## Cursing Gnomes — raid-alert tests (Jeremy 2026-10-08 wake rapid-iteration).
##
## Queued recon finding from the damage-numbers lane: no player-facing alert
## when YOUR buildings are destroyed mid-raid. SimCombat.damage_building now
## publishes an urgent Gazette story for player-faction destruction (routes to
## UrgentToast + Chronicle), and the _flip_hall "seizes" story is marked urgent
## when the LOSER is the player faction. AI-vs-AI stays toast-quiet.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_raid_alert.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes raid-alert tests ===")
	_test_player_building_destroyed_alerts()
	_test_ai_building_destroyed_stays_quiet()
	_test_player_building_disaster_alert()
	_test_player_hall_capture_urgent()
	_test_ai_hall_capture_not_urgent()
	_test_alert_is_toast_worthy()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("FAIL: " + f)
		quit(1)
	else:
		quit(0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(label)


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var combat := SimCombat.new(gs)
	return {"gs": gs, "combat": combat}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _add_bldg(gs: GameState, btype: String, faction: String) -> Dictionary:
	return gs.add_building({
		"type": btype, "faction": faction, "town_id": -1,
		"position": Vector2(0, 0), "complete": true, "progress": 1.0,
		"hp": 400.0, "max_hp": 400.0, "town_name": "Testville",
	})


func _test_player_building_destroyed_alerts() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	_check("raid alert: player_faction is humans", gs.player_faction == "humans")
	var stories: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary): stories.append(s))
	var b: Dictionary = _add_bldg(gs, "watchtower", "humans")
	_check("raid alert: destroy returns true",
		combat.damage_building(int(b["id"]), 500.0, "ogres"))
	var dname: String = SimBuildings.building_name("watchtower")
	_check("raid alert: one story published", stories.size() == 1)
	var s: Dictionary = stories[0] as Dictionary
	_check("raid alert: headline names the building",
		String(s.get("headline", "")) == "Your %s was destroyed!" % dname)
	_check("raid alert: urgent flag set", bool(s.get("urgent", false)))
	_check("raid alert: kind is war", String(s.get("kind", "")) == "war")
	_check("raid alert: body names the attacker",
		String(s.get("body", "")).find("Ogres") >= 0)
	_free_world(w)


func _test_ai_building_destroyed_stays_quiet() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var stories: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary): stories.append(s))
	var b: Dictionary = _add_bldg(gs, "watchtower", "ogres")
	_check("raid alert: AI destroy returns true",
		combat.damage_building(int(b["id"]), 500.0, "elves"))
	_check("raid alert: no story for AI-vs-AI destruction", stories.is_empty())
	_free_world(w)


func _test_player_building_disaster_alert() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var stories: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary): stories.append(s))
	var b: Dictionary = _add_bldg(gs, "house", "humans")
	_check("raid alert: disaster destroy returns true",
		combat.damage_building(int(b["id"]), 500.0, ""))
	_check("raid alert: disaster story published", stories.size() == 1)
	var s: Dictionary = stories[0] as Dictionary
	_check("raid alert: disaster kind is disaster",
		String(s.get("kind", "")) == "disaster")
	_check("raid alert: disaster story urgent", bool(s.get("urgent", false)))
	_free_world(w)


func _test_player_hall_capture_urgent() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var stories: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary): stories.append(s))
	var hall: Dictionary = _add_bldg(gs, "town_hall", "humans")
	combat._flip_hall(hall, "ogres")
	_check("raid alert: hall now ogre-owned",
		String(hall.get("faction", "")) == "ogres")
	_check("raid alert: capture story published", stories.size() == 1)
	var s: Dictionary = stories[0] as Dictionary
	_check("raid alert: capture headline", String(s.get("headline", "")) \
		== "Ogres seizes Testville")
	_check("raid alert: losing YOUR hall is urgent",
		bool(s.get("urgent", false)))
	_free_world(w)


func _test_ai_hall_capture_not_urgent() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var stories: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary): stories.append(s))
	var hall: Dictionary = _add_bldg(gs, "town_hall", "ogres")
	combat._flip_hall(hall, "elves")
	_check("raid alert: AI capture story published", stories.size() == 1)
	var s: Dictionary = stories[0] as Dictionary
	_check("raid alert: AI-vs-AI capture not urgent",
		not bool(s.get("urgent", false)))
	_free_world(w)


func _test_alert_is_toast_worthy() -> void:
	# The urgent flag is what pops the UrgentToast (HTML showToast parity).
	_check("raid alert: urgent=true pops the toast",
		UrgentToast.is_urgent("Your Watchtower was destroyed!", true))
	_check("raid alert: capture of your town pops the toast",
		UrgentToast.is_urgent("Ogres seizes Testville", true))
