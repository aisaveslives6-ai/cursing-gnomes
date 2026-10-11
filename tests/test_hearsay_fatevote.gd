extends SceneTree
## Cursing Gnomes — fate-vote + peace-treaty gossip tests
## (Jeremy 2026-10-11 hearsay flesh-out).
##
## Jeremy's 2026-10-11 war-spare system emits three bus signals when a town
## hall falls — spare_vote_started, spare_vote_resolved, treaty_signed —
## and the grapevine was DEAF to all of it: the realm's biggest political
## event seeded no rumors. Now:
##  - bus.spare_vote_started seeds a RICH kind-"fatevote" rumor
##    (heat 0.85 = PRESS_HEAT, front-page eligible once talked about,
##    TRUTH_TRUE, subject-dedup "fatevote:<id>")
##  - bus.spare_vote_resolved seeds a second RICH kind-"fatevote" rumor
##    for the verdict (heat 0.9, subject "fatevote:<id>:verdict");
##    unknown results seed nothing
##  - bus.treaty_signed seeds a RICH kind-"peacetreaty" rumor (heat 0.7
##    tavern talk, never the front page, TRUTH_TRUE,
##    subject "peacetreaty:<loser>:<taker>:<day>")
##  - the fate-vote reaction matrix: the doomed feel dread
##    ("fatevote_dread", disaster); the taker's faction feels grim
##    satisfaction ("fatevote_thrill", victory); rivals of the loser mock
##    ("fatevote_mock", mocked); the unhinged thrill (cheerful); everyone
##    else is dismayed ("fatevote_news"). Unhinged x1.5.
##  - the verdict matrix: loser's faction relieved/griefing by outcome
##    ("fatevote_relief"/"fatevote_grief"); taker's shamed/gloating
##    ("fatevote_shame"/"fatevote_gloat"); every VOTER feels their own
##    ballot (spare-voters relieved or dismayed, kill-voters vindicated
##    or thwarted); neutrals cheer or mourn the outcome.
##  - the treaty matrix: signatories relieved ("treaty_relief", helped);
##    guarantors proud ("treaty_pride", praised); rivals of either side
##    suspicious ("treaty_suspicion", dismayed); the unhinged enjoy the
##    news; everyone else is glad the killing paused ("treaty_news").
##  - spread motivation: the doomed dread-spread (+2/+0.15, +2/+0.1 on a
##    mercy verdict), takers savor (+1/+0.1), rivals of the loser
##    gloat-spread (+1/+0.1), condemnations electrify neutrals
##    (+1/+0.05); treaty signatories and rivals carry it (+1/+0.05).
##  - witnessed fact — both kinds join the slur/famine/season/weather/
##    brigade/vehicle doubt-immunity club (nobody doubts the war council
##    met or the treaty was inked); old saves without fatevote_phase /
##    treaty_loser fall through to the generic path
##  - all 12 new memory types registered in SimMemories.TYPES with weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_fatevote.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay fate-vote tests ===")
	_test_started_seeds_rumor()
	_test_started_heat_truth_press()
	_test_empty_vote_seeds_nothing()
	_test_resolved_spared_seeds_verdict()
	_test_resolved_condemned()
	_test_unknown_result_seeds_nothing()
	_test_treaty_seeds_rumor()
	_test_treaty_heat_truth_press()
	_test_empty_treaty_seeds_nothing()
	_test_started_loser_dreads()
	_test_started_taker_thrills()
	_test_started_rival_mocks()
	_test_started_unhinged_thrills()
	_test_started_neutral_dismayed()
	_test_verdict_spared_relieves_loser()
	_test_verdict_spared_shames_taker()
	_test_verdict_spared_rewards_spare_voter()
	_test_verdict_condemned_grieves_loser()
	_test_verdict_condemned_gloats_taker()
	_test_verdict_condemned_rewards_kill_voter()
	_test_verdict_condemned_dismays_spare_voter()
	_test_treaty_relief_for_parties()
	_test_treaty_pride_for_guarantor()
	_test_treaty_suspicion_for_rival()
	_test_treaty_news_for_neutral()
	_test_spread_motivation()
	_test_memory_types_registered()
	_test_doubt_immunity()
	_test_old_save_fallthrough()
	_test_signals_connected()
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


func _harness() -> Array:
	var gs := _new_gs()
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return [gs, phone, phone.hearsay]


func _spawn(gs: GameState, faction: String, pos: Vector2 = Vector2.ZERO,
		mind: Dictionary = {}) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "alive": true,
		"mind": mind})
	u["position"] = pos
	return u


func _unhinged_mind() -> Dictionary:
	return {"traits": {"unhinged": 1.0}}


func _start_vote(gs: GameState, vid: int, loser: String, taker: String) -> void:
	gs.bus.spare_vote_started.emit({
		"id": vid, "loser": loser, "taker": taker,
		"loser_name": "Ogres", "taker_name": "Gnomes",
		"town": "Riverton", "votes": [], "player_votes": false,
		"player_vote": "pending", "resolved": false, "result": "",
		"wars": [],
	})


func _resolve_vote(gs: GameState, vid: int, loser: String, taker: String,
		result: String, spare: int, kill: int, votes: Array) -> void:
	gs.bus.spare_vote_resolved.emit({
		"id": vid, "loser": loser, "taker": taker,
		"loser_name": "Ogres", "taker_name": "Gnomes",
		"town": "Riverton", "votes": votes, "resolved": true,
		"result": result, "spare_count": spare, "kill_count": kill,
	})


func _sign_treaty(gs: GameState, loser: String, taker: String, day: int) -> void:
	gs.bus.treaty_signed.emit({
		"loser": loser, "taker": taker,
		"loser_name": "Ogres", "taker_name": "Gnomes",
		"day_signed": day, "duration_days": 30,
		"terms": [{"label": "tribute", "status": "active", "kind": "tribute"},
			{"label": "dmz", "status": "active", "kind": "dmz"}],
		"guarantors": ["elves"], "guarantor_names": ["Elves"],
	})


func _rumor(hs, kind: String, subject: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == kind \
				and String(r.get("subject", "")) == subject:
			return r
	return {}


func _count_kind(hs, kind: String) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == kind:
			n += 1
	return n


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _test_started_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres", "gnomes")
	var r := _rumor(hs, "fatevote", "fatevote:7")
	_check("vote call seeds a rumor", not r.is_empty())
	_check("vote records the phase",
		String(r.get("fatevote_phase", "")) == "started")
	_check("vote records the loser",
		String(r.get("fatevote_loser", "")) == "ogres")
	_check("vote records the taker",
		String(r.get("fatevote_taker", "")) == "gnomes")
	_check("vote records the town",
		String(r.get("fatevote_town", "")) == "Riverton")
	_check("vote text names the loser",
		String(r.get("text", "")).find("Ogres") >= 0)


func _test_started_heat_truth_press() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres", "gnomes")
	var r := _rumor(hs, "fatevote", "fatevote:7")
	_check("vote call is front-page eligible",
		float(r.get("heat", 0.0)) >= hs.PRESS_HEAT)
	# 0.85 clears QUEST_HEAT 0.7, but _quest_tick only proposes for kind
	# "war" (scouts) and "cache" (expeditions) — a fate vote is news,
	# not a scout target, so no advisor proposal ever spawns from it.
	_check("vote call is not a proposal-generating kind",
		String(r.get("kind", "")) != "war"
		and String(r.get("kind", "")) != "cache")
	_check("vote call is confirmed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("vote call is press-eligible",
		bool(r.get("press_ok", true)))


func _test_empty_vote_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 8, "", "gnomes")
	_resolve_vote(gs, 9, "ogres", "", "spared", 3, 1, [])
	_check("malformed votes seed nothing", _count_kind(hs, "fatevote") == 0)


func _test_resolved_spared_seeds_verdict() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_resolve_vote(gs, 7, "ogres", "gnomes", "spared", 3, 1,
		[{"voter": "elves", "vote": "spare"}])
	var r := _rumor(hs, "fatevote", "fatevote:7:verdict")
	_check("verdict seeds its own rumor", not r.is_empty())
	_check("verdict records the phase",
		String(r.get("fatevote_phase", "")) == "resolved")
	_check("verdict records the result",
		String(r.get("fatevote_result", "")) == "spared")
	_check("verdict records the counts",
		int(r.get("fatevote_spare", 0)) == 3
		and int(r.get("fatevote_kill", 0)) == 1)
	_check("verdict stashes the votes",
		(r.get("fatevote_votes", []) as Array).size() == 1)
	_check("verdict is hotter than the call",
		float(r.get("heat", 0.0)) > hs.PRESS_HEAT)
	_check("verdict is confirmed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)


func _test_resolved_condemned() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_resolve_vote(gs, 11, "ogres", "gnomes", "condemned", 1, 4,
		[{"voter": "elves", "vote": "kill"}])
	var r := _rumor(hs, "fatevote", "fatevote:11:verdict")
	_check("condemnation seeds a verdict rumor", not r.is_empty())
	_check("condemnation records the result",
		String(r.get("fatevote_result", "")) == "condemned")


func _test_unknown_result_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_resolve_vote(gs, 12, "ogres", "gnomes", "bogus", 2, 2, [])
	_check("unknown verdict seeds nothing", _count_kind(hs, "fatevote") == 0)


func _test_treaty_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_sign_treaty(gs, "ogres", "gnomes", 12)
	var r := _rumor(hs, "peacetreaty", "peacetreaty:ogres:gnomes:12")
	_check("treaty seeds a rumor", not r.is_empty())
	_check("treaty records the parties",
		String(r.get("treaty_loser", "")) == "ogres"
		and String(r.get("treaty_taker", "")) == "gnomes")
	_check("treaty records the days",
		int(r.get("treaty_days", 0)) == 30)
	_check("treaty records the terms",
		(r.get("treaty_terms", []) as Array).size() == 2)
	_check("treaty records the guarantors",
		(r.get("treaty_guarantors", []) as Array) == ["elves"])
	_check("treaty text names the terms",
		String(r.get("text", "")).find("tribute") >= 0)


func _test_treaty_heat_truth_press() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_sign_treaty(gs, "ogres", "gnomes", 12)
	var r := _rumor(hs, "peacetreaty", "peacetreaty:ogres:gnomes:12")
	_check("treaty stays tavern talk",
		float(r.get("heat", 0.0)) < hs.PRESS_HEAT)
	_check("treaty is confirmed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("treaty is not press-eligible",
		not bool(r.get("press_ok", true)))


func _test_empty_treaty_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_sign_treaty(gs, "", "gnomes", 12)
	_sign_treaty(gs, "ogres", "", 13)
	_check("malformed treaties seed nothing", _count_kind(hs, "peacetreaty") == 0)


func _test_started_loser_dreads() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres", "gnomes")
	var r := _rumor(hs, "fatevote", "fatevote:7")
	var doomed := _spawn(gs, "ogres")
	hs._on_heard(doomed, r, {})
	_check("the doomed remember dread",
		_recalled(doomed, "fatevote_dread", int(r.get("id", 0))) > 0.0)
	_check("dread feels scared", _emotion(doomed) == "scared")


func _test_started_taker_thrills() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres", "gnomes")
	var r := _rumor(hs, "fatevote", "fatevote:7")
	var taker := _spawn(gs, "gnomes")
	hs._on_heard(taker, r, {})
	_check("the taker remembers the thrill",
		_recalled(taker, "fatevote_thrill", int(r.get("id", 0))) > 0.0)
	_check("grim satisfaction feels proud", _emotion(taker) == "proud")


func _test_started_rival_mocks() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("elves", "ogres", "test")
	_start_vote(gs, 7, "ogres", "gnomes")
	var r := _rumor(hs, "fatevote", "fatevote:7")
	var rival := _spawn(gs, "elves")
	hs._on_heard(rival, r, {})
	_check("the loser's rival remembers mockery",
		_recalled(rival, "fatevote_mock", int(r.get("id", 0))) > 0.0)
	_check("mockery feels sad", _emotion(rival) == "sad")


func _test_started_unhinged_thrills() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres", "gnomes")
	var r := _rumor(hs, "fatevote", "fatevote:7")
	var wild := _spawn(gs, "humans", Vector2.ZERO, _unhinged_mind())
	hs._on_heard(wild, r, {})
	_check("the unhinged thrill at the theatre",
		_recalled(wild, "fatevote_thrill", int(r.get("id", 0))) > 0.0)
	_check("theatre-thrill feels happy", _emotion(wild) == "happy")


func _test_started_neutral_dismayed() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres", "gnomes")
	var r := _rumor(hs, "fatevote", "fatevote:7")
	var neutral := _spawn(gs, "humans")
	hs._on_heard(neutral, r, {})
	_check("neutrals remember the news",
		_recalled(neutral, "fatevote_news", int(r.get("id", 0))) > 0.0)
	_check("dread news feels sad", _emotion(neutral) == "sad")


func _test_verdict_spared_relieves_loser() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_resolve_vote(gs, 7, "ogres", "gnomes", "spared", 3, 1, [])
	var r := _rumor(hs, "fatevote", "fatevote:7:verdict")
	var doomed := _spawn(gs, "ogres")
	hs._on_heard(doomed, r, {})
	_check("the spared remember relief",
		_recalled(doomed, "fatevote_relief", int(r.get("id", 0))) > 0.0)
	_check("relief feels happy", _emotion(doomed) == "happy")


func _test_verdict_spared_shames_taker() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_resolve_vote(gs, 7, "ogres", "gnomes", "spared", 3, 1, [])
	var r := _rumor(hs, "fatevote", "fatevote:7:verdict")
	var taker := _spawn(gs, "gnomes")
	hs._on_heard(taker, r, {})
	_check("the thwarted taker remembers shame",
		_recalled(taker, "fatevote_shame", int(r.get("id", 0))) > 0.0)
	_check("shame feels angry", _emotion(taker) == "angry")


func _test_verdict_spared_rewards_spare_voter() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_resolve_vote(gs, 7, "ogres", "gnomes", "spared", 3, 1,
		[{"voter": "elves", "vote": "spare"},
			{"voter": "humans", "vote": "kill"}])
	var r := _rumor(hs, "fatevote", "fatevote:7:verdict")
	var dove := _spawn(gs, "elves")
	hs._on_heard(dove, r, {})
	_check("the spare-voter remembers relief",
		_recalled(dove, "fatevote_relief", int(r.get("id", 0))) > 0.0)
	_check("vindicated dove feels happy", _emotion(dove) == "happy")


func _test_verdict_condemned_grieves_loser() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_resolve_vote(gs, 11, "ogres", "gnomes", "condemned", 1, 4, [])
	var r := _rumor(hs, "fatevote", "fatevote:11:verdict")
	var doomed := _spawn(gs, "ogres")
	hs._on_heard(doomed, r, {})
	_check("the condemned remember grief",
		_recalled(doomed, "fatevote_grief", int(r.get("id", 0))) > 0.0)
	_check("grief feels scared", _emotion(doomed) == "scared")


func _test_verdict_condemned_gloats_taker() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_resolve_vote(gs, 11, "ogres", "gnomes", "condemned", 1, 4, [])
	var r := _rumor(hs, "fatevote", "fatevote:11:verdict")
	var taker := _spawn(gs, "gnomes")
	hs._on_heard(taker, r, {})
	_check("the vindicated taker remembers gloating",
		_recalled(taker, "fatevote_gloat", int(r.get("id", 0))) > 0.0)
	_check("gloating feels proud", _emotion(taker) == "proud")


func _test_verdict_condemned_rewards_kill_voter() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_resolve_vote(gs, 11, "ogres", "gnomes", "condemned", 1, 4,
		[{"voter": "elves", "vote": "kill"}])
	var r := _rumor(hs, "fatevote", "fatevote:11:verdict")
	var hawk := _spawn(gs, "elves")
	hs._on_heard(hawk, r, {})
	_check("the kill-voter remembers gloating",
		_recalled(hawk, "fatevote_gloat", int(r.get("id", 0))) > 0.0)


func _test_verdict_condemned_dismays_spare_voter() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_resolve_vote(gs, 11, "ogres", "gnomes", "condemned", 1, 4,
		[{"voter": "elves", "vote": "spare"}])
	var r := _rumor(hs, "fatevote", "fatevote:11:verdict")
	var dove := _spawn(gs, "elves")
	hs._on_heard(dove, r, {})
	_check("the outvoted dove remembers grief",
		_recalled(dove, "fatevote_grief", int(r.get("id", 0))) > 0.0)
	_check("outvoted grief feels sad", _emotion(dove) == "sad")


func _test_treaty_relief_for_parties() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_sign_treaty(gs, "ogres", "gnomes", 12)
	var r := _rumor(hs, "peacetreaty", "peacetreaty:ogres:gnomes:12")
	var ogre := _spawn(gs, "ogres")
	var gnome := _spawn(gs, "gnomes")
	hs._on_heard(ogre, r, {})
	hs._on_heard(gnome, r, {})
	_check("the loser remembers relief",
		_recalled(ogre, "treaty_relief", int(r.get("id", 0))) > 0.0)
	_check("the taker remembers relief",
		_recalled(gnome, "treaty_relief", int(r.get("id", 0))) > 0.0)
	_check("treaty relief feels happy", _emotion(ogre) == "happy")


func _test_treaty_pride_for_guarantor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_sign_treaty(gs, "ogres", "gnomes", 12)
	var r := _rumor(hs, "peacetreaty", "peacetreaty:ogres:gnomes:12")
	var elf := _spawn(gs, "elves")
	hs._on_heard(elf, r, {})
	_check("the guarantor remembers pride",
		_recalled(elf, "treaty_pride", int(r.get("id", 0))) > 0.0)
	_check("guarantor pride feels proud", _emotion(elf) == "proud")


func _test_treaty_suspicion_for_rival() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("undead", "gnomes", "test")
	_sign_treaty(gs, "ogres", "gnomes", 12)
	var r := _rumor(hs, "peacetreaty", "peacetreaty:ogres:gnomes:12")
	var spook := _spawn(gs, "undead")
	hs._on_heard(spook, r, {})
	_check("the taker's rival remembers suspicion",
		_recalled(spook, "treaty_suspicion", int(r.get("id", 0))) > 0.0)
	_check("suspicion feels sad", _emotion(spook) == "sad")


func _test_treaty_news_for_neutral() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_sign_treaty(gs, "ogres", "gnomes", 12)
	var r := _rumor(hs, "peacetreaty", "peacetreaty:ogres:gnomes:12")
	var human := _spawn(gs, "humans")
	hs._on_heard(human, r, {})
	_check("neutrals remember the news",
		_recalled(human, "treaty_news", int(r.get("id", 0))) > 0.0)
	_check("peace news feels happy", _emotion(human) == "happy")


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("elves", "ogres", "test")
	_start_vote(gs, 7, "ogres", "gnomes")
	var r := _rumor(hs, "fatevote", "fatevote:7")
	var doomed := _spawn(gs, "ogres")
	var taker := _spawn(gs, "gnomes")
	var rival := _spawn(gs, "elves")
	var neutral := _spawn(gs, "humans")
	var dread: Dictionary = hs._spread_motivation(doomed, r)
	_check("the doomed dread-spread",
		int(dread.get("cap_delta", 0)) == 2
		and float(dread.get("heat_delta", 0.0)) > 0.0)
	var savor: Dictionary = hs._spread_motivation(taker, r)
	_check("the taker savors-spreads",
		int(savor.get("cap_delta", 0)) == 1)
	var gloat: Dictionary = hs._spread_motivation(rival, r)
	_check("the loser's rival gloat-spreads",
		int(gloat.get("cap_delta", 0)) == 1)
	var straight: Dictionary = hs._spread_motivation(neutral, r)
	_check("neutrals tell the vote straight",
		is_equal_approx(float(straight.get("cap_delta", 0.0)), 0.0))
	_resolve_vote(gs, 11, "ogres", "gnomes", "condemned", 1, 4, [])
	var v := _rumor(hs, "fatevote", "fatevote:11:verdict")
	var shock: Dictionary = hs._spread_motivation(neutral, v)
	_check("a condemnation electrifies neutrals",
		int(shock.get("cap_delta", 0)) == 1)
	_sign_treaty(gs, "ogres", "gnomes", 12)
	var t := _rumor(hs, "peacetreaty", "peacetreaty:ogres:gnomes:12")
	var carry: Dictionary = hs._spread_motivation(taker, t)
	_check("signatories carry the treaty home",
		int(carry.get("cap_delta", 0)) == 1)
	gs.diplomacy.declare_war("undead", "gnomes", "test")
	var spook := _spawn(gs, "undead")
	var mutter: Dictionary = hs._spread_motivation(spook, t)
	_check("rivals mutter the treaty about",
		int(mutter.get("cap_delta", 0)) == 1)
	var calm: Dictionary = hs._spread_motivation(neutral, t)
	_check("neutrals tell the treaty straight",
		is_equal_approx(float(calm.get("cap_delta", 0.0)), 0.0))


func _test_memory_types_registered() -> void:
	var mem_cls = load("res://scripts/sim/memories.gd")
	var types: Array = mem_cls.TYPES
	for mtype: String in ["fatevote_dread", "fatevote_thrill",
			"fatevote_news", "fatevote_mock", "fatevote_relief",
			"fatevote_grief", "fatevote_gloat", "fatevote_shame",
			"treaty_relief", "treaty_suspicion", "treaty_news",
			"treaty_pride"]:
		_check("memory type registered: " + mtype, mtype in types)
	_check("dread cools hard",
		is_equal_approx(float(mem_cls.REL_WEIGHT["fatevote_dread"]), -0.5))
	_check("relief warms",
		is_equal_approx(float(mem_cls.REL_WEIGHT["fatevote_relief"]), 0.5))


func _test_doubt_immunity() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres", "gnomes")
	_sign_treaty(gs, "ogres", "gnomes", 12)
	var r := _rumor(hs, "fatevote", "fatevote:7")
	var t := _rumor(hs, "peacetreaty", "peacetreaty:ogres:gnomes:12")
	var teller := _spawn(gs, "gnomes")
	var hearer := _spawn(gs, "gnomes")
	var clean_v: float = hs._belief(teller, hearer, r)
	var clean_t: float = hs._belief(teller, hearer, t)
	var doubters: Array = []
	for i in 24:
		doubters.append(1000 + i)
	r["doubters"] = doubters
	r["distortions"] = 3
	t["doubters"] = doubters
	t["distortions"] = 3
	_check("doubt can't dent a fate vote",
		is_equal_approx(hs._belief(teller, hearer, r), clean_v))
	_check("doubt can't dent a signed treaty",
		is_equal_approx(hs._belief(teller, hearer, t), clean_t))


func _test_old_save_fallthrough() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# A kind-"fatevote" rumor with no fatevote_phase (old save) takes the
	# generic reception path — real memory, default handling.
	var r: Dictionary = hs.seed_rumor("Old vote talk.", "fatevote",
		"oldvote", 0.5, -1, false, hs.TRUTH_TRUE)
	var gnome := _spawn(gs, "gnomes")
	hs._on_heard(gnome, r, {})
	_check("old fatevote rumor falls through to generic path",
		_recalled(gnome, "heard_rumor", int(r.get("id", 0))) > 0.0)
	var t: Dictionary = hs.seed_rumor("Old treaty talk.", "peacetreaty",
		"oldtreaty", 0.5, -1, false, hs.TRUTH_TRUE)
	var elf := _spawn(gs, "elves")
	hs._on_heard(elf, t, {})
	_check("old treaty rumor falls through to generic path",
		_recalled(elf, "heard_rumor", int(t.get("id", 0))) > 0.0)


func _test_signals_connected() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_check("spare_vote_started is wired to the handler",
		gs.bus.is_connected("spare_vote_started",
			Callable(hs, "_on_spare_vote_started")))
	_check("spare_vote_resolved is wired to the handler",
		gs.bus.is_connected("spare_vote_resolved",
			Callable(hs, "_on_spare_vote_resolved")))
	_check("treaty_signed is wired to the handler",
		gs.bus.is_connected("treaty_signed",
			Callable(hs, "_on_treaty_signed")))
