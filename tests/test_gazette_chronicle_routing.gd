extends SceneTree
## Cursing Gnomes — Gazette Chronicle routing tests.
##
## Jeremy 2026-10-06 standing news-desk rule: stories must land in the
## Chronicle archive (court_sys.stories, the phone newspaper) AND fire the
## bus. Direct bus.gazette_story.emit only reaches the toast path.
## SimGazette.publish_or_emit is the single router: court_sys when present,
## direct emit fallback when absent (headless tests / boot).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gazette_chronicle_routing.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _bus_stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes gazette chronicle routing tests ===")
	_test_router_with_court()
	_test_router_fallback_no_court()
	_test_router_extra_urgent_with_court()
	_test_router_extra_urgent_fallback()
	_test_router_extra_icon()
	_test_hydro_routes_to_chronicle()
	_test_command_posts_routes_to_chronicle()
	_test_army_routes_to_chronicle()
	_test_combat_destroyed_building_chronicle_urgent()
	_test_diplomacy_slur_article_chronicle()
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


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	return gs


func _capture(gs: GameState) -> void:
	_bus_stories.clear()
	gs.bus.gazette_story.connect(_on_story)


func _on_story(s: Dictionary) -> void:
	_bus_stories.append(s)


func _archived(court: SimRoyalCourt, headline: String) -> Dictionary:
	for s: Dictionary in court.stories:
		if String(s.get("headline", "")) == headline:
			return s
	return {}


func _test_router_with_court() -> void:
	var gs := _new_game()
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	_capture(gs)
	SimGazette.publish_or_emit(gs, "Test Headline", "Test body.", "news")
	_check("router+court: bus fires", _bus_stories.size() == 1)
	var a := _archived(court, "Test Headline")
	_check("router+court: archived in Chronicle", not a.is_empty())
	_check("router+court: kind preserved", String(a.get("kind", "")) == "news")
	_check("router+court: bus payload has headline",
		String(_bus_stories[0].get("headline", "")) == "Test Headline")


func _test_router_fallback_no_court() -> void:
	var gs := _new_game()
	# court_sys is null after setup() — the headless/boot fallback path.
	_capture(gs)
	SimGazette.publish_or_emit(gs, "Fallback Headline", "Fallback body.", "trade")
	_check("router fallback: bus fires", _bus_stories.size() == 1)
	_check("router fallback: kind preserved",
		String(_bus_stories[0].get("kind", "")) == "trade")
	_check("router fallback: day present",
		int(_bus_stories[0].get("day", 0)) >= 1)


func _test_router_extra_urgent_with_court() -> void:
	var gs := _new_game()
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	_capture(gs)
	SimGazette.publish_or_emit(gs, "Urgent Headline", "Urgent body.", "war",
		{"urgent": true})
	var a := _archived(court, "Urgent Headline")
	_check("router extra: archived story keeps urgent",
		bool(a.get("urgent", false)) == true)
	_check("router extra: bus payload keeps urgent",
		bool(_bus_stories[0].get("urgent", false)) == true)


func _test_router_extra_urgent_fallback() -> void:
	var gs := _new_game()
	_capture(gs)
	SimGazette.publish_or_emit(gs, "Urgent Fallback", "Body.", "war",
		{"urgent": true})
	_check("router extra fallback: bus payload keeps urgent",
		bool(_bus_stories[0].get("urgent", false)) == true)


func _test_router_extra_icon() -> void:
	# Backchannel shape: icon + urgent ride both paths via extra.
	var gs := _new_game()
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	_capture(gs)
	SimGazette.publish_or_emit(gs, "Court Whispers", "Body.", "court",
		{"icon": "sealed_letter", "urgent": false})
	var a := _archived(court, "Court Whispers")
	_check("router extra: archived story keeps icon",
		String(a.get("icon", "")) == "sealed_letter")
	_check("router extra: bus payload keeps icon",
		String(_bus_stories[0].get("icon", "")) == "sealed_letter")


func _test_hydro_routes_to_chronicle() -> void:
	var gs := _new_game()
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	_capture(gs)
	var combat := SimCombat.new(gs)
	var h := HydroSim.new(gs, combat)
	h.setup_bounds(Rect2(0, 0, 2000, 2000))
	h._gazette("FLOOD!", "Test flood body.")
	_check("hydro: bus fires", _bus_stories.size() == 1)
	var a := _archived(court, "FLOOD!")
	_check("hydro: archived in Chronicle", not a.is_empty())
	_check("hydro: kind is flood", String(a.get("kind", "")) == "flood")


func _test_command_posts_routes_to_chronicle() -> void:
	var gs := _new_game()
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	_capture(gs)
	var cps := SimCommandPosts.new()
	cps.setup(gs)
	gs.command_posts = cps
	cps._gazette("BESIEGED: Test Post", "Test siege body.", "war")
	_check("command_posts: bus fires", _bus_stories.size() == 1)
	var a := _archived(court, "BESIEGED: Test Post")
	_check("command_posts: archived in Chronicle", not a.is_empty())
	_check("command_posts: kind preserved", String(a.get("kind", "")) == "war")


func _test_army_routes_to_chronicle() -> void:
	var gs := _new_game()
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	_capture(gs)
	var army := SimArmy.new(gs)
	army._gazette("TROOPS MUSTERING", "Test muster body.")
	_check("army: bus fires", _bus_stories.size() == 1)
	var a := _archived(court, "TROOPS MUSTERING")
	_check("army: archived in Chronicle", not a.is_empty())
	_check("army: kind is war", String(a.get("kind", "")) == "war")


func _test_combat_destroyed_building_chronicle_urgent() -> void:
	var gs := _new_game()
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	_capture(gs)
	# The destroyed-story is player-facing: only the PLAYER faction's
	# buildings trigger it (AI-vs-AI stays toast-quiet by design).
	var house := {
		"id": 1, "type": "house", "faction": "humans",
		"position": Vector2(500, 500), "alive": true, "complete": true,
		"hp": 400.0, "max_hp": 400.0, "town_id": -1,
	}
	gs.buildings.append(house)
	gs.building_by_id[1] = house
	var combat := SimCombat.new(gs)
	var destroyed: bool = combat.damage_building(1, 5000.0, "humans")
	_check("combat destroyed: damage returns true", destroyed)
	_check("combat destroyed: bus fires", _bus_stories.size() >= 1)
	var found := {}
	for s: Dictionary in _bus_stories:
		if String(s.get("headline", "")).contains("was destroyed!"):
			found = s
	_check("combat destroyed: bus headline intact", not found.is_empty())
	var a := _archived(court, String(found.get("headline", "")))
	_check("combat destroyed: archived in Chronicle", not a.is_empty())
	_check("combat destroyed: urgent preserved",
		bool(a.get("urgent", false)) == true)


func _test_diplomacy_slur_article_chronicle() -> void:
	var gs := _new_game()
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	_capture(gs)
	var dip := SimDiplomacy.new(gs)
	dip._gazette_slur_article("humans", "gnomes", "test insult text")
	_check("diplomacy slur: bus fires", _bus_stories.size() == 1)
	_check("diplomacy slur: kind is scandal",
		String(_bus_stories[0].get("kind", "")) == "scandal")
	var a := _archived(court, String(_bus_stories[0].get("headline", "")))
	_check("diplomacy slur: archived in Chronicle", not a.is_empty())
