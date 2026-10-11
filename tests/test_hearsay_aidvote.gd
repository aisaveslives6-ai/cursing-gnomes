extends SceneTree
## Cursing Gnomes — disaster aid-vote gossip tests
## (Jeremy 2026-10-11 hearsay flesh-out).
##
## disaster_aid.gd emits aid_vote_started / aid_vote_resolved when a faction
## is ruined by disaster and the council votes on sending builders — but the
## grapevine was DEAF to it: zero hooks in hearsay.gd. Now:
##  - bus.aid_vote_started seeds a RICH kind-"aidvote" rumor
##    (heat 0.85 = PRESS_HEAT, front-page eligible once talked about,
##    TRUTH_TRUE, subject-dedup "aidvote:<id>")
##  - bus.aid_vote_resolved seeds a second RICH kind-"aidvote" rumor
##    for the verdict (subject "aidvote:<id>:verdict"); "aided" rides
##    heat 0.8 (good news travels fast), "alone" rides heat 0.9 (an
##    abandoned faction is a scandal); unknown results seed nothing
##  - the aid-vote reaction matrix: the victim's faction feels hope
##    ("aidvote_hope", hopeful) when the vote is called; on the verdict
##    the victim feels relief or grief ("aidvote_relief"/"aidvote_grief"),
##    the helpers feel pride ("aidvote_pride", praised), the unhinged
##    thrill (cheerful), everyone else is warmed or chilled
##    ("aidvote_news", helped/dismayed). Unhinged x1.5.
##  - spread motivation: the victim spreads word hoping for help
##    (+2/+0.1, +2/+0.15 when abandoned), helpers carry it proudly
##    (+1/+0.1), neutrals carry the verdict (+1/+0.05); the unhinged
##    thrill-spread (+1/+0.1)
##  - witnessed fact — aidvote joins the slur/famine/season/weather/
##    brigade/vehicle/fatevote/peacetreaty doubt-immunity club (nobody
##    doubts the council met); old saves without aidvote_phase fall
##    through to the generic path
##  - all 6 new memory types registered in SimMemories.TYPES with weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_aidvote.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay aid-vote tests ===")
	_test_started_seeds_rumor()
	_test_started_heat_truth_press()
	_test_empty_vote_seeds_nothing()
	_test_resolved_aided_seeds_verdict()
	_test_resolved_alone_seeds_verdict()
	_test_unknown_result_seeds_nothing()
	_test_victim_hopes()
	_test_neutral_moved()
	_test_unhinged_thrills_on_call()
	_test_verdict_aided_relief()
	_test_verdict_aided_helper_pride()
	_test_verdict_alone_grief()
	_test_verdict_alone_neutral_chilled()
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


func _start_vote(gs: GameState, vid: int, victim: String) -> void:
	gs.bus.aid_vote_started.emit({
		"id": vid, "victim": victim, "victim_name": "Ogres",
		"cause": "fire", "cause_text": "a great fire",
		"day": 10, "votes": [], "player_votes": false,
		"player_vote": "pending", "resolved": false, "result": "",
	})


func _resolve_vote(gs: GameState, vid: int, victim: String, result: String,
		helpers: Array) -> void:
	gs.bus.aid_vote_resolved.emit({
		"id": vid, "victim": victim, "victim_name": "Ogres",
		"cause": "fire", "cause_text": "a great fire",
		"day": 10, "votes": [], "resolved": true,
		"result": result, "helpers": helpers,
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
	_start_vote(gs, 7, "ogres")
	var r := _rumor(hs, "aidvote", "aidvote:7")
	_check("aid vote seeds an aidvote rumor", not r.is_empty())
	_check("rumor carries victim metadata",
		String(r.get("aidvote_victim", "")) == "ogres")
	_check("rumor carries cause metadata",
		String(r.get("aidvote_cause", "")) == "a great fire")
	_check("start phase marked",
		String(r.get("aidvote_phase", "")) == "started")


func _test_started_heat_truth_press() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	var r := _rumor(hs, "aidvote", "aidvote:7")
	_check("aid vote rumor is PRESS hot",
		float(r.get("heat", 0.0)) >= hs.PRESS_HEAT)
	_check("aid vote rumor is witnessed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)


func _test_empty_vote_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "")
	_check("empty victim seeds nothing", _count_kind(hs, "aidvote") == 0)


func _test_resolved_aided_seeds_verdict() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	_resolve_vote(gs, 7, "ogres", "aided", ["gnomes", "elves"])
	var r := _rumor(hs, "aidvote", "aidvote:7:verdict")
	_check("aided verdict seeds a verdict rumor", not r.is_empty())
	_check("aided heat is good-news-fast",
		is_equal_approx(float(r.get("heat", 0.0)), 0.8))
	_check("verdict records the helpers",
		(r.get("aidvote_helpers", []) as Array) == ["gnomes", "elves"])
	_check("verdict records the result",
		String(r.get("aidvote_result", "")) == "aided")
	_check("verdict phase marked",
		String(r.get("aidvote_phase", "")) == "resolved")


func _test_resolved_alone_seeds_verdict() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	_resolve_vote(gs, 7, "ogres", "alone", [])
	var r := _rumor(hs, "aidvote", "aidvote:7:verdict")
	_check("alone verdict seeds a verdict rumor", not r.is_empty())
	_check("alone heat is scandal-hot",
		is_equal_approx(float(r.get("heat", 0.0)), 0.9))


func _test_unknown_result_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	_resolve_vote(gs, 7, "ogres", "maybe", [])
	_check("unknown result seeds nothing",
		_rumor(hs, "aidvote", "aidvote:7:verdict").is_empty())


func _test_victim_hopes() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	var r := _rumor(hs, "aidvote", "aidvote:7")
	var victim := _spawn(gs, "ogres")
	hs._on_heard(victim, r, {})
	_check("the victim remembers hope",
		_recalled(victim, "aidvote_hope", int(r.get("id", 0))) > 0.0)
	_check("hope feels happy", _emotion(victim) == "happy")


func _test_neutral_moved() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	var r := _rumor(hs, "aidvote", "aidvote:7")
	var neutral := _spawn(gs, "elves")
	hs._on_heard(neutral, r, {})
	_check("neutrals remember the kindness call",
		_recalled(neutral, "aidvote_news", int(r.get("id", 0))) > 0.0)


func _test_unhinged_thrills_on_call() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	var r := _rumor(hs, "aidvote", "aidvote:7")
	var wild := _spawn(gs, "elves", Vector2.ZERO, _unhinged_mind())
	hs._on_heard(wild, r, {})
	_check("the unhinged thrill at the theatre",
		_recalled(wild, "aidvote_thrill", int(r.get("id", 0))) > 0.0)
	_check("thrill feels happy", _emotion(wild) == "happy")


func _test_verdict_aided_relief() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	_resolve_vote(gs, 7, "ogres", "aided", ["gnomes", "elves"])
	var r := _rumor(hs, "aidvote", "aidvote:7:verdict")
	var victim := _spawn(gs, "ogres")
	hs._on_heard(victim, r, {})
	_check("the aided victim remembers relief",
		_recalled(victim, "aidvote_relief", int(r.get("id", 0))) > 0.0)
	_check("relief feels happy", _emotion(victim) == "happy")


func _test_verdict_aided_helper_pride() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	_resolve_vote(gs, 7, "ogres", "aided", ["gnomes", "elves"])
	var r := _rumor(hs, "aidvote", "aidvote:7:verdict")
	var helper := _spawn(gs, "gnomes")
	hs._on_heard(helper, r, {})
	_check("a helper remembers pride",
		_recalled(helper, "aidvote_pride", int(r.get("id", 0))) > 0.0)
	_check("pride feels proud", _emotion(helper) == "proud")


func _test_verdict_alone_grief() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	_resolve_vote(gs, 7, "ogres", "alone", [])
	var r := _rumor(hs, "aidvote", "aidvote:7:verdict")
	var victim := _spawn(gs, "ogres")
	hs._on_heard(victim, r, {})
	_check("the abandoned victim remembers grief",
		_recalled(victim, "aidvote_grief", int(r.get("id", 0))) > 0.0)
	_check("grief feels scared", _emotion(victim) == "scared")


func _test_verdict_alone_neutral_chilled() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	_resolve_vote(gs, 7, "ogres", "alone", [])
	var r := _rumor(hs, "aidvote", "aidvote:7:verdict")
	var neutral := _spawn(gs, "elves")
	hs._on_heard(neutral, r, {})
	_check("neutrals remember the silence",
		_recalled(neutral, "aidvote_news", int(r.get("id", 0))) > 0.0)
	_check("the silence chills", _emotion(neutral) == "sad")


func _test_memory_types_registered() -> void:
	var mem_types: Array = load(
		"res://scripts/sim/memories.gd").TYPES
	for t: String in ["aidvote_hope", "aidvote_thrill", "aidvote_news",
			"aidvote_relief", "aidvote_grief", "aidvote_pride"]:
		_check("memory type registered: " + t, mem_types.has(t))


func _test_doubt_immunity() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_start_vote(gs, 7, "ogres")
	var r := _rumor(hs, "aidvote", "aidvote:7")
	var teller := _spawn(gs, "gnomes")
	var hearer := _spawn(gs, "gnomes")
	var clean_v: float = hs._belief(teller, hearer, r)
	var doubters: Array = []
	for i in 24:
		doubters.append(1000 + i)
	r["doubters"] = doubters
	r["distortions"] = 3
	_check("doubt can't dent an aid vote",
		is_equal_approx(hs._belief(teller, hearer, r), clean_v))


func _test_old_save_fallthrough() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# A kind-"aidvote" rumor with no aidvote_phase (old save) takes the
	# generic reception path — real memory, default handling.
	var r: Dictionary = hs.seed_rumor("Old aid talk.", "aidvote",
		"oldaids", 0.5, -1, false, hs.TRUTH_TRUE)
	var gnome := _spawn(gs, "gnomes")
	hs._on_heard(gnome, r, {})
	_check("old aidvote rumor falls through to generic path",
		_recalled(gnome, "heard_rumor", int(r.get("id", 0))) > 0.0)


func _test_signals_connected() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_check("aid_vote_started is wired to the handler",
		gs.bus.is_connected("aid_vote_started",
			Callable(hs, "_on_aid_vote_started")))
	_check("aid_vote_resolved is wired to the handler",
		gs.bus.is_connected("aid_vote_resolved",
			Callable(hs, "_on_aid_vote_resolved")))
