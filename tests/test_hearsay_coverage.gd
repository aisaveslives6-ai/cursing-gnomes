extends SceneTree
## Cursing Gnomes — hearsay gap-coverage tests (Jeremy 2026-10-06, launch
## readiness deep systems pass).
##
## The 21:00 hearsay-fire run closed the wildfire gap and listed the
## remaining deaf threads; this file closes them:
##  - surrender_offered: the white flag flew with ZERO grapevine presence
##    (no rumor, no Squabble post). Now seeds a ("war","surrender:<loser>")
##    rumor + post. quest_spawned is set: confirmed news, not a scout lead
##    (the quest tick only understands faction-id subjects).
##  - surrender_accepted: previously only surfaced via the generic
##    peace_made rumor. Now seeds its own ("war","surrendered:<loser>")
##    rumor + post, with press_ok=false (diplomacy._report already printed
##    the official Gazette story — no double front page).
##  - surrender_refused: has NO bus signal (diplomacy only _record()s it),
##    so no handler exists. Covered via the Gazette story pipeline:
##    _report() publishes "SURRENDER REFUSED: ..." (kind "war") and
##    _on_story seeds a heat-1.0 war rumor from it. This test proves it.
##  - town_founded: bus.town_founded fired with nobody listening. Now seeds
##    a ("news","town:<name>") rumor + post.
##  - strategic_proposal_decided: only the proposal gossiped, never the
##    decision. Denied declare_war -> tavern comedy (rumor text corrected,
##    heat 0.65: reaches the ruler, too cool for quests/press); approved
##    -> war talk goes white-hot; expired -> drums go quiet, no post.
##    Player-faction and non-war decisions stay off the street.
##  - fire_out: fires raged in the grapevine but died in silence. The
##    shared ("disaster","wildfire") rumor now cools + posts relief.
##    (Both water put-outs and natural burnout route through
##    disasters.extinguish(), which emits fire_out.)
##  - disaster_left: fired with nobody listening. "flood" cools the flood
##    rumor + posts; junk kinds (disasters.gd emits unit job names here)
##    are ignored.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_coverage.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay-coverage tests ===")
	_test_surrender_offered_seeds_rumor()
	_test_surrender_offered_posts()
	_test_surrender_offer_dedups()
	_test_surrender_accepted()
	_test_surrender_refused_via_story()
	_test_town_founded()
	_test_proposal_denied_war()
	_test_proposal_denied_war_fresh()
	_test_proposal_approved_war()
	_test_proposal_expired_war()
	_test_proposal_decided_player_ignored()
	_test_proposal_decided_nonwar_ignored()
	_test_fire_out_cools()
	_test_fire_out_no_rumor()
	_test_disaster_left_flood()
	_test_disaster_left_junk_ignored()
	_test_save_roundtrip()
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
	var gs = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.set_ruler_name("ass")
	return gs


func _spawn(gs: GameState, faction: String, pos: Vector2,
		alive: bool = true) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "alive": alive})
	u["position"] = pos
	return u


func _harness() -> Array:
	var gs := _new_gs()
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	var hs = phone.hearsay
	_spawn(gs, "gnomes", Vector2(100, 100))
	_spawn(gs, "elves", Vector2(200, 200))
	return [gs, phone, hs]


func _posts(phone) -> Array:
	return phone.state["posts"]


func _post_count(phone) -> int:
	return (_posts(phone) as Array).size()


func _last_post_text(phone) -> String:
	var posts: Array = _posts(phone)
	return String((posts[posts.size() - 1] as Dictionary).get("text", ""))


func _ignite(gs: GameState, pos: Vector2) -> void:
	gs.bus.fire_started.emit({
		"id": 1, "position": pos, "intensity": 50.0, "radius": 90.0,
		"born": 0.0,
	})


func _war_proposal(faction: String, status: String) -> Dictionary:
	return {
		"id": 7, "faction": faction, "kind": "declare_war",
		"details": {"target": "ogres"}, "day": 1, "status": status,
	}


## --- surrender --------------------------------------------------------


func _test_surrender_offered_seeds_rumor() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var hs = parts[2]
	gs.bus.surrender_offered.emit("elves", "ogres")
	var r: Dictionary = hs._live_rumor("war", "surrender:elves")
	_check("surrender offer seeds rumor", not r.is_empty())
	_check("surrender offer rumor heat 0.9",
		is_equal_approx(float(r.get("heat", 0.0)), 0.9))
	_check("surrender offer is not a quest lead",
		bool(r.get("quest_spawned", false)))
	_check("surrender offer rumor is true",
		String(r.get("truth", "")) == "true")
	gs.queue_free()


func _test_surrender_offered_posts() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var before: int = _post_count(phone)
	gs.bus.surrender_offered.emit("elves", "ogres")
	_check("surrender offer posts to Squabble",
		_post_count(phone) == before + 1)
	var t: String = _last_post_text(phone).to_lower()
	_check("surrender offer post is white-flag flavor",
		t.contains("white flag") or t.contains("surrender"))
	gs.queue_free()


func _test_surrender_offer_dedups() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var hs = parts[2]
	gs.bus.surrender_offered.emit("elves", "ogres")
	gs.bus.surrender_offered.emit("elves", "ogres")
	var n: int = 0
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("kind", "")) == "war" \
				and String(r2.get("subject", "")) == "surrender:elves":
			n += 1
	_check("repeat surrender offer does not duplicate rumor", n == 1)
	gs.queue_free()


func _test_surrender_accepted() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var hs = parts[2]
	var before: int = _post_count(phone)
	gs.bus.surrender_accepted.emit("elves", "ogres")
	var r: Dictionary = hs._live_rumor("war", "surrendered:elves")
	_check("surrender accepted seeds rumor", not r.is_empty())
	_check("surrender accepted rumor heat 1.0",
		is_equal_approx(float(r.get("heat", 0.0)), 1.0))
	_check("surrender accepted rumor skips press (official story printed)",
		not bool(r.get("press_ok", true)))
	_check("surrender accepted posts to Squabble",
		_post_count(phone) == before + 1)
	var t: String = _last_post_text(phone).to_lower()
	_check("surrender accepted post mentions yielding",
		t.contains("yield") or t.contains("accept") or t.contains("over"))
	gs.queue_free()


func _test_surrender_refused_via_story() -> void:
	# Refusals have no bus signal; they ride the Gazette story pipeline.
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var hs = parts[2]
	gs.bus.gazette_story.emit({
		"headline": "SURRENDER REFUSED: the Elves fight on",
		"body": "The Ogres refused the Elves surrender on day 1.",
		"kind": "war",
	})
	var found: Dictionary = {}
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("text", "")) == \
				"SURRENDER REFUSED: the Elves fight on":
			found = r2
	_check("surrender refusal reaches the grapevine via Gazette",
		not found.is_empty())
	_check("refusal rumor is hot war news",
		is_equal_approx(float(found.get("heat", 0.0)), 1.0))
	gs.queue_free()


## --- towns ------------------------------------------------------------


func _test_town_founded() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var hs = parts[2]
	var before: int = _post_count(phone)
	gs.bus.town_founded.emit({
		"id": 7, "faction": "elves", "name": "Testville",
		"position": Vector2(300, 300),
	})
	var r: Dictionary = hs._live_rumor("news", "town:Testville")
	_check("town founding seeds rumor", not r.is_empty())
	_check("town founding posts to Squabble",
		_post_count(phone) == before + 1)
	_check("town post names the town",
		_last_post_text(phone).contains("Testville"))
	gs.queue_free()


## --- proposal decisions -----------------------------------------------


func _seed_war_proposal_rumor(gs: GameState) -> void:
	# The realistic flow: the proposal itself gossips first.
	gs.bus.strategic_proposal.emit({
		"id": 7, "faction": "elves", "kind": "declare_war",
		"details": {"target": "ogres"}, "day": 1, "status": "open",
	})


func _test_proposal_denied_war() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var hs = parts[2]
	_seed_war_proposal_rumor(gs)
	var before: int = _post_count(phone)
	gs.bus.strategic_proposal_decided.emit(
		_war_proposal("elves", "denied"), false)
	var r: Dictionary = hs._live_rumor("war", "elves")
	_check("denied war proposal keeps one rumor", not r.is_empty())
	_check("denied war corrects the rumor text",
		String(r.get("text", "")).contains("chickened out"))
	_check("denied war rumor heat 0.65 (below quest/press)",
		is_equal_approx(float(r.get("heat", 0.0)), 0.65))
	_check("denied war rumor is not a quest lead",
		bool(r.get("quest_spawned", false)))
	_check("denied war posts tavern comedy",
		_post_count(phone) == before + 1)
	var t: String = _last_post_text(phone).to_lower()
	_check("denied post mocks the cold feet",
		t.contains("chicken") or t.contains("cancelled") \
			or t.contains("decorative"))
	gs.queue_free()


func _test_proposal_denied_war_fresh() -> void:
	# Denial with no prior proposal rumor (e.g. missed the proposal).
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var hs = parts[2]
	gs.bus.strategic_proposal_decided.emit(
		_war_proposal("undead", "denied"), false)
	var r: Dictionary = hs._live_rumor("war", "undead")
	_check("denied war seeds fresh rumor when none exists",
		not r.is_empty())
	_check("fresh denied rumor is not a quest lead",
		bool(r.get("quest_spawned", false)))
	gs.queue_free()


func _test_proposal_approved_war() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var hs = parts[2]
	_seed_war_proposal_rumor(gs)
	var before: int = _post_count(phone)
	gs.bus.strategic_proposal_decided.emit(
		_war_proposal("elves", "approved"), true)
	var r: Dictionary = hs._live_rumor("war", "elves")
	_check("approved war heats the talk to full",
		is_equal_approx(float(r.get("heat", 0.0)), 1.0))
	_check("approved war adds no new rumor", not r.is_empty())
	_check("approved war posts nothing (war_declared covers it)",
		_post_count(phone) == before)
	gs.queue_free()


func _test_proposal_expired_war() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var hs = parts[2]
	_seed_war_proposal_rumor(gs)
	var before: int = _post_count(phone)
	gs.bus.strategic_proposal_decided.emit(
		_war_proposal("elves", "expired"), false)
	var r: Dictionary = hs._live_rumor("war", "elves")
	_check("expired war cools the drums",
		float(r.get("heat", 0.0)) <= 0.35001)
	_check("expired war posts nothing", _post_count(phone) == before)
	gs.queue_free()


func _test_proposal_decided_player_ignored() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var hs = parts[2]
	var rumors_before: int = (hs.state["rumors"] as Array).size()
	var before: int = _post_count(phone)
	gs.bus.strategic_proposal_decided.emit(
		_war_proposal("gnomes", "denied"), false)
	_check("player decision stays off the street (no rumor)",
		(hs.state["rumors"] as Array).size() == rumors_before)
	_check("player decision stays off the street (no post)",
		_post_count(phone) == before)
	gs.queue_free()


func _test_proposal_decided_nonwar_ignored() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var hs = parts[2]
	var rumors_before: int = (hs.state["rumors"] as Array).size()
	var before: int = _post_count(phone)
	gs.bus.strategic_proposal_decided.emit({
		"id": 8, "faction": "elves", "kind": "major_buildup",
		"details": {}, "day": 1, "status": "denied",
	}, false)
	_check("non-war decision adds no rumor",
		(hs.state["rumors"] as Array).size() == rumors_before)
	_check("non-war decision posts nothing", _post_count(phone) == before)
	gs.queue_free()


## --- fire / disaster endings -------------------------------------------


func _test_fire_out_cools() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var hs = parts[2]
	_ignite(gs, Vector2(100, 100))
	var before: int = _post_count(phone)
	gs.bus.fire_out.emit(1)
	var r: Dictionary = hs._live_rumor("disaster", "wildfire")
	_check("fire_out cools the wildfire rumor",
		float(r.get("heat", 0.0)) <= 0.30001)
	_check("fire_out posts relief", _post_count(phone) == before + 1)
	var t: String = _last_post_text(phone).to_lower()
	_check("fire_out post says the fire is out",
		t.contains("out") or t.contains("extinguish"))
	gs.queue_free()


func _test_fire_out_no_rumor() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var before: int = _post_count(phone)
	gs.bus.fire_out.emit(99)
	_check("fire_out with no live rumor is silent",
		_post_count(phone) == before)
	gs.queue_free()


func _test_disaster_left_flood() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var hs = parts[2]
	gs.bus.disaster_spawned.emit("flood", Vector2(400, 400))
	var r0: Dictionary = hs._live_rumor("disaster", "flood")
	_check("flood seeds a rumor", not r0.is_empty())
	var before: int = _post_count(phone)
	gs.bus.disaster_left.emit("flood")
	var r: Dictionary = hs._live_rumor("disaster", "flood")
	_check("disaster_left cools the flood rumor",
		float(r.get("heat", 0.0)) <= 0.30001)
	_check("disaster_left posts relief", _post_count(phone) == before + 1)
	gs.queue_free()


func _test_disaster_left_junk_ignored() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var before: int = _post_count(phone)
	# disasters.gd emits unit job names on this signal — not disasters.
	gs.bus.disaster_left.emit("farmer")
	_check("junk disaster_left kind is ignored",
		_post_count(phone) == before)
	gs.queue_free()


## --- persistence --------------------------------------------------------


func _test_save_roundtrip() -> void:
	var parts: Array = _harness()
	var gs: GameState = parts[0]
	var hs = parts[2]
	gs.bus.surrender_offered.emit("elves", "ogres")
	var r: Dictionary = hs._live_rumor("war", "surrender:elves")
	var rid: int = int(r.get("id", -1))
	hs.from_dict(hs.to_dict())
	var r2: Dictionary = hs._rumor_by_id(rid)
	_check("surrender rumor survives save/load", not r2.is_empty())
	_check("quest_spawned flag survives save/load",
		bool(r2.get("quest_spawned", false)))
	gs.queue_free()
