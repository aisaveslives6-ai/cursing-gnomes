extends SceneTree
## Cursing Gnomes — disaster-aid votes (Jeremy 2026-10-11).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_disaster_aid.gd
##
## Exit code 0 = all passed, 1 = any failure.
## Covers: disaster hall loss -> aid vote (NOT fate vote); faction-caused
## destruction -> fate vote (NOT aid); yes-voters dispatch helpers; helpers
## actually repair; helpers return home after the mission duration;
## relations boost + aid_given history; player as helper and as helped.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes disaster-aid tests ===")
	_test_disaster_triggers_aid_not_fate()
	_test_faction_destroy_triggers_fate_not_aid()
	_test_ai_votes_on_likes()
	_test_helpers_dispatched()
	_test_helpers_repair_and_return()
	_test_relations_boost()
	_test_player_as_helper()
	_test_player_as_helped()
	_test_aid_vote_only_once()
	_test_save_load()
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


## Fresh headless game: player = humans; both systems wired like World does.
func _make_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres", "elves", "undead"])
	gs.war_spare = SimWarSpare.new(gs)
	gs.disaster_aid = SimDisasterAid.new(gs)
	return gs


func _disaster(gs: GameState, victim: String, cause: String = "fire") -> void:
	gs.bus.building_destroyed.emit({"type": "town_hall",
		"faction": victim, "destroyed_by": cause,
		"position": Vector2(100, 100)})


func _test_disaster_triggers_aid_not_fate() -> void:
	var gs := _make_game()
	_disaster(gs, "ogres", "fire")
	_check("disaster starts an aid vote",
		not gs.disaster_aid.active_vote().is_empty())
	_check("disaster does NOT start a fate vote",
		gs.war_spare.active_vote().is_empty())


func _test_faction_destroy_triggers_fate_not_aid() -> void:
	var gs := _make_game()
	_disaster(gs, "ogres", "elves")
	_check("faction destruction starts a fate vote",
		not gs.war_spare.active_vote().is_empty())
	_check("faction destruction does NOT start an aid vote",
		gs.disaster_aid.active_vote().is_empty())


func _test_ai_votes_on_likes() -> void:
	var gs := _make_game()
	gs.diplomacy.adjust_score("gnomes", "ogres", 70.0)
	gs.diplomacy.adjust_score("undead", "ogres", -80.0)
	# "tornado" is never a raw destroyed_by in the real game — twisters fell
	# buildings via MONSTER_FACTION ("monster"); use the real source value.
	_disaster(gs, "ogres", "monster")
	var v: Dictionary = gs.disaster_aid.active_vote()
	var gn := ""
	var un := ""
	for e in v.get("votes", []):
		if String(e.get("voter", "")) == "gnomes":
			gn = String(e.get("vote", ""))
		if String(e.get("voter", "")) == "undead":
			un = String(e.get("vote", ""))
	_check("liking AI votes to send aid", gn == "yes")
	_check("hating AI declines aid", un == "no")


## Kind factions + player votes YES: helpers walk to the stricken town.
func _aided_setup() -> GameState:
	var gs := _make_game()
	# Humans are the player — no other human votes needed for determinism.
	gs.diplomacy.adjust_score("gnomes", "elves", 70.0)
	gs.diplomacy.adjust_score("ogres", "elves", 70.0)
	gs.diplomacy.adjust_score("undead", "elves", 70.0)
	gs.diplomacy.adjust_score("humans", "elves", 70.0)
	gs.add_unit({"faction": "gnomes", "job": "worker",
		"position": Vector2(500, 500), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "speed": 55.0})
	_disaster(gs, "elves", "fire")
	gs.disaster_aid.cast_player_vote(true)
	return gs


func _test_helpers_dispatched() -> void:
	var gs := _aided_setup()
	var missions: Array = gs.disaster_aid.missions_for("elves")
	_check("aid missions dispatched", missions.size() >= 1)
	var helpers := 0
	for m in missions:
		helpers += ((m as Dictionary).get("unit_ids", []) as Array).size()
	_check("helpers are tagged as guest missions", helpers >= 1)
	for m in missions:
		for uid in (m as Dictionary).get("unit_ids", []):
			var u: Dictionary = gs.get_unit(int(uid))
			_check("helper flagged aid_mission", u.has("aid_mission"))
			# Phase lives inside the unit's aid_mission dict, not a flat key.
			_check("helper marked traveling",
				String((u.get("aid_mission", {}) as Dictionary).get("phase", "")) \
					== "travel")


func _test_helpers_repair_and_return() -> void:
	var gs := _aided_setup()
	# A damaged elven house to repair near the disaster site.
	var house: Dictionary = gs.add_building({"type": "house",
		"faction": "elves", "position": Vector2(120, 120),
		"hp": 20.0, "max_hp": 100.0, "built": true, "complete": true,
		"work_done": 1.0, "alive": true})
	var da = gs.disaster_aid
	var missions: Array = da.missions_for("elves")
	_check("mission exists for repair test", not missions.is_empty())
	var m0: Dictionary = missions[0]
	var aid_units: Array = (m0.get("unit_ids", []) as Array).duplicate()
	_check("mission has a helper", not aid_units.is_empty())
	# Give the mission plenty of days left so helpers WORK first…
	m0["until_day"] = gs.day_number + 5
	for uid in aid_units:
		gs.get_unit(int(uid))["position"] = Vector2(125, 125)
	for i in 60:
		da.tick(1.0)
	_check("helpers actually repair damaged buildings",
		float(house.get("hp", 0.0)) > 20.0)
	# …then expire it: helpers head home, get unflagged, mission closes.
	m0["until_day"] = gs.day_number
	for i in 80:
		da.tick(1.0)
	_check("mission finished after duration",
		da.missions_for("elves").is_empty())
	var home := true
	for uid in aid_units:
		if gs.get_unit(int(uid)).has("aid_mission"):
			home = false
	_check("helpers unflagged after mission", home)


func _test_relations_boost() -> void:
	var gs := _aided_setup()
	var before := float(gs.diplomacy.relation_score("gnomes", "elves"))
	var da = gs.disaster_aid
	var missions: Array = da.missions_for("elves")
	for m in missions:
		var md: Dictionary = m
		md["until_day"] = gs.day_number
		for uid in (md.get("unit_ids", []) as Array):
			gs.get_unit(int(uid))["position"] = Vector2(125, 125)
	for i in 80:
		da.tick(1.0)
	var after := float(gs.diplomacy.relation_score("gnomes", "elves"))
	_check("aid boosts relations", after > before + 5.0)
	var hist: Array = gs.diplomacy.pair_history("gnomes", "elves")
	var kinds: Array = []
	for h in hist:
		kinds.append(String((h as Dictionary).get("type", "")))
	_check("kindness recorded in pair history", "aid_given" in kinds)


func _test_player_as_helper() -> void:
	var gs := _make_game()
	gs.diplomacy.adjust_score("humans", "ogres", 70.0)
	gs.add_unit({"faction": "humans", "job": "worker",
		"position": Vector2(500, 500), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "speed": 55.0})
	_disaster(gs, "ogres", "fire")
	gs.disaster_aid.cast_player_vote(true)
	var missions: Array = gs.disaster_aid.missions_for("ogres")
	var player_helpers := 0
	for m in missions:
		# Mission carries a "helpers" array (factions), not a flat "helper".
		if "humans" in ((m as Dictionary).get("helpers", []) as Array):
			player_helpers += (((m as Dictionary).get("unit_ids", [])) \
				as Array).size()
	_check("player's vote dispatches player's workers", player_helpers >= 1)


func _test_player_as_helped() -> void:
	var gs := _make_game()
	# Everyone loves the player; ogres help.
	gs.diplomacy.adjust_score("ogres", "humans", 70.0)
	gs.diplomacy.adjust_score("gnomes", "humans", 70.0)
	gs.diplomacy.adjust_score("elves", "humans", 70.0)
	gs.diplomacy.adjust_score("undead", "humans", 70.0)
	gs.add_unit({"faction": "ogres", "job": "worker",
		"position": Vector2(500, 500), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "speed": 55.0})
	# "earthquake" is never a raw destroyed_by in the real game — disasters
	# fell buildings via "fire"/"monster"/""; use the real source value.
	_disaster(gs, "humans", "monster")
	# Player doesn't vote on aid to themselves; AI resolves immediately.
	_check("player-victim aid vote auto-resolves",
		gs.disaster_aid.active_vote().is_empty())
	var missions: Array = gs.disaster_aid.missions_for("humans")
	_check("foreign helpers come to the player's aid",
		not missions.is_empty())


func _test_aid_vote_only_once() -> void:
	var gs := _make_game()
	_disaster(gs, "ogres", "fire")
	gs.disaster_aid.cast_player_vote(true)
	# Second REAL disaster source: the 10-day per-victim cooldown must block
	# a new vote (a bogus source would pass trivially without exercising it).
	_disaster(gs, "ogres", "fire")
	_check("one aid vote per disaster cooldown",
		gs.disaster_aid.active_vote().is_empty())


func _test_save_load() -> void:
	var gs := _aided_setup()
	var da = gs.disaster_aid
	var data: Dictionary = da.to_dict()
	var gs2 := _make_game()
	gs2.disaster_aid.from_dict(data)
	# to_dict's contract is missions + seq + vote cooldowns (the transient
	# in-progress vote popup is deliberately not persisted); the active
	# mission is what must survive the roundtrip.
	_check("aid state survives save/load roundtrip", data.has("missions"))
	_check("mission restored after load",
		not gs2.disaster_aid.missions_for("elves").is_empty())
