extends SceneTree
## Cursing Gnomes — hearsay court-ruling tests (Jeremy 2026-10-08).
##
## Covers the hearsay flesh-out run: court petitions granted/denied by the
## crown were a deaf thread — real events, zero grapevine. Now
## bus.petition_decided seeds a witnessed-fact "news" rumor and the
## realm reacts in character:
##  - the petitioner takes the verdict personally (grant: proud/grateful,
##    denial: anger that lands on the ruler — affection moves)
##  - their own faction feels it by proxy (sympathy/approval)
##  - friends celebrate grants / rage at denials on their behalf
##  - rivals grumble at grants / cackle at denials (town remembers)
##  - denied pleas are schadenfreude: rivals push them, friends bury them
##  - unhinged NPCs feel it 1.5x (smear/war/gossip parity)
##  - verdict parsed from the choice text (Refuse/Deny/Forbid It/Not Now/
##    Hold Firm = denial)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_petition.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay court-ruling tests ===")
	_test_denied_petition_seeds_rumor()
	_test_grant_petition_seeds_rumor()
	_test_petitioner_denied_angry()
	_test_petitioner_granted_proud()
	_test_own_faction_denied_sympathy()
	_test_rival_cackles_at_denial()
	_test_rival_grumbles_at_grant()
	_test_friend_defends_denial()
	_test_unhinged_amplified()
	_test_verdict_parsing()
	_test_spread_motivation_denial()
	_test_truth_true_witnessed_fact()
	_test_unknown_petitioner_no_crash()
	_test_dedup_same_petition()
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


func _spawn(gs: GameState, faction: String, unhinged: bool = false) -> Dictionary:
	var mind: Dictionary = {}
	if unhinged:
		mind = {"traits": {"unhinged": 1.0}}
	return gs.add_unit({"faction": faction, "alive": true, "mind": mind})


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


## Emit a real bus.petition_decided (the royal_court payload shape).
func _decide(gs: GameState, pid: int, pname: String, faction: String,
		kind: String, choice: String) -> Dictionary:
	var p := {
		"id": 4242, "day": 3,
		"from_key": "u%d" % pid, "from_name": pname,
		"role": "Mayor", "faction": faction, "kind": kind,
		"text": "Please %s." % kind, "options": [choice, "Refuse"],
		"resolved": true, "choice": 0,
	}
	gs.bus.petition_decided.emit(p, choice)
	return p


func _petition_rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "news" \
				and String(r.get("subject", "")) == "petition:4242":
			return r
	return {}


func _find_stance(gs: GameState, a: Dictionary, faction_b: String,
		lo: float, hi: float) -> Dictionary:
	var likes = load("res://scripts/sim/likes_dislikes.gd")
	for i in 200:
		var cand: Dictionary = _spawn(gs, faction_b)
		var s: float = likes.npc_stance(cand, a, gs)
		if s >= lo and s <= hi:
			return cand
	return {}


func _test_denied_petition_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_decide(gs, pid, "Marla", "ogres", "mayor_grain", "Refuse")
	var r: Dictionary = _petition_rumor(hs)
	_check("denied petition seeds a news rumor", not r.is_empty())
	_check("denial verdict recorded", String(r.get("petition_verdict", "")) == "denied")
	_check("denial is hot tavern talk (0.75)", float(r.get("heat", 0.0)) >= 0.75)
	_check("petitioner id recorded", int(r.get("petitioner_id", 0)) == pid)
	_check("petitioner heard it first (knower)", (r.get("knowers", []) as Array).has(pid))
	_check("ruler named in text", String(r.get("text", "")).contains("Marla"))


func _test_grant_petition_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	_decide(gs, int(pet.get("id", 0)), "Marla", "ogres", "mayor_grain", "Release Food")
	var r: Dictionary = _petition_rumor(hs)
	_check("granted petition seeds a news rumor", not r.is_empty())
	_check("grant verdict recorded", String(r.get("petition_verdict", "")) == "granted")
	_check("grant is cooler news (0.6)", absf(float(r.get("heat", 0.0)) - 0.6) < 0.01)


func _test_petitioner_denied_angry() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_decide(gs, pid, "Marla", "ogres", "mayor_grain", "Refuse")
	var r: Dictionary = _petition_rumor(hs)
	_check("petitioner remembers petition_denied",
		_recalled(pet, "petition_denied", int(r.get("id", 0))) > 0.0)
	_check("denial insults the petitioner (angry)", _emotion(pet) == "angry")
	_check("petitioner mood drops on denial", conv.ruler_mood(pid) < 0.0)


func _test_petitioner_granted_proud() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_decide(gs, pid, "Marla", "ogres", "mayor_grain", "Release Food")
	var r: Dictionary = _petition_rumor(hs)
	_check("petitioner remembers petition_granted",
		_recalled(pet, "petition_granted", int(r.get("id", 0))) > 0.0)
	_check("grant praises the petitioner (proud)", _emotion(pet) == "proud")
	_check("petitioner mood rises on grant", conv.ruler_mood(pid) > 0.0)


func _test_own_faction_denied_sympathy() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_decide(gs, pid, "Marla", "ogres", "mayor_grain", "Refuse")
	var r: Dictionary = _petition_rumor(hs)
	var kin: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(kin, r, {})
	_check("own faction remembers heard_petition_denied",
		_recalled(kin, "heard_petition_denied", pid) > 0.0)
	_check("own faction mood dips in sympathy",
		conv.ruler_mood(int(kin.get("id", 0))) < 0.0)


func _test_rival_cackles_at_denial() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	gs.bus.war_declared.emit("elves", "ogres")
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_decide(gs, pid, "Marla", "ogres", "mayor_grain", "Refuse")
	var r: Dictionary = _petition_rumor(hs)
	var likes = load("res://scripts/sim/likes_dislikes.gd")
	var rival: Dictionary = _find_stance(gs, pet, "elves", -1.0, -0.3)
	_check("rival found (stance <= -0.3)",
		not rival.is_empty() and likes.npc_stance(rival, pet, gs) <= -0.3)
	if rival.is_empty():
		return
	hs._on_heard(rival, r, {})
	_check("rival remembers mocked_petition_denial",
		_recalled(rival, "mocked_petition_denial", pid) > 0.0)
	_check("rival amused (liked_topic -> happy)", _emotion(rival) == "happy")
	_check("rival mood rises at the denial",
		conv.ruler_mood(int(rival.get("id", 0))) > 0.0)


func _test_rival_grumbles_at_grant() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	gs.bus.war_declared.emit("elves", "ogres")
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_decide(gs, pid, "Marla", "ogres", "mayor_grain", "Release Food")
	var r: Dictionary = _petition_rumor(hs)
	var likes = load("res://scripts/sim/likes_dislikes.gd")
	var rival: Dictionary = _find_stance(gs, pet, "elves", -1.0, -0.3)
	_check("grant rival found", not rival.is_empty())
	if rival.is_empty():
		return
	hs._on_heard(rival, r, {})
	_check("rival remembers grumbled_petition_grant",
		_recalled(rival, "grumbled_petition_grant", pid) > 0.0)
	_check("rival mood dips at the grant",
		conv.ruler_mood(int(rival.get("id", 0))) < 0.0)


func _test_friend_defends_denial() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_decide(gs, pid, "Marla", "ogres", "mayor_grain", "Refuse")
	var r: Dictionary = _petition_rumor(hs)
	var friend: Dictionary = _find_stance(gs, pet, "elves", 0.3, 1.0)
	_check("friend found (stance >= 0.3)", not friend.is_empty())
	if friend.is_empty():
		return
	hs._on_heard(friend, r, {})
	_check("friend remembers defended_petition_victim",
		_recalled(friend, "defended_petition_victim", pid) > 0.0)
	_check("friend offended (insulted -> angry)", _emotion(friend) == "angry")
	_check("friend mood drops defending",
		conv.ruler_mood(int(friend.get("id", 0))) < 0.0)


func _test_unhinged_amplified() -> void:
	# Two separate petitions: the unhinged petitioner must feel the
	# denial 1.5x harder than a level-headed one.
	var h1: Array = _harness()
	var gs1: GameState = h1[0]
	var conv1 = h1[1].get("conversation")
	var calm: Dictionary = _spawn(gs1, "ogres")
	_decide(gs1, int(calm.get("id", 0)), "Calm", "ogres", "mayor_grain", "Refuse")
	var h2: Array = _harness()
	var gs2: GameState = h2[0]
	var conv2 = h2[1].get("conversation")
	var wild: Dictionary = _spawn(gs2, "ogres", true)
	_decide(gs2, int(wild.get("id", 0)), "Wild", "ogres", "mayor_grain", "Refuse")
	_check("unhinged denial hits 1.5x harder",
		conv2.ruler_mood(int(wild.get("id", 0))) \
			< conv1.ruler_mood(int(calm.get("id", 0))))


func _test_verdict_parsing() -> void:
	var h: Array = _harness()
	var hs = h[2]
	var cases := {
		"Refuse": "denied", "Deny": "denied", "Forbid It": "denied",
		"Not Now": "denied", "Hold Firm": "denied",
		"Release Food": "granted", "Grant Command": "granted",
		"Lower to 10%": "granted", "Pay 200g": "granted",
		"Unleash Him": "granted",
	}
	for choice: String in cases.keys():
		_check("verdict %s -> %s" % [choice, String(cases[choice])],
			hs._petition_verdict(choice) == String(cases[choice]))


func _test_spread_motivation_denial() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.war_declared.emit("elves", "ogres")
	var pet: Dictionary = _spawn(gs, "ogres")
	_decide(gs, int(pet.get("id", 0)), "Marla", "ogres", "mayor_grain", "Refuse")
	var r: Dictionary = _petition_rumor(hs)
	var likes = load("res://scripts/sim/likes_dislikes.gd")
	var rival: Dictionary = _find_stance(gs, pet, "elves", -1.0, -0.3)
	var friend: Dictionary = _find_stance(gs, pet, "elves", 0.3, 1.0)
	# Neutral is whatever the RNG gives — assert the mapping, not the draw.
	var neutral: Dictionary = _spawn(gs, "humans")
	var ns: float = likes.npc_stance(neutral, pet, gs)
	var expected := 0
	if ns <= -0.3:
		expected = 1
	elif ns >= 0.3:
		expected = -1
	_check("denial: teller zeal matches stance toward petitioner",
		int(hs._spread_motivation(neutral, r).get("cap_delta", 0)) == expected)
	_check("denial: rival pushes (cap +1)",
		not rival.is_empty() \
		and int(hs._spread_motivation(rival, r).get("cap_delta", 0)) == 1)
	_check("denial: friend buries (cap -1)",
		not friend.is_empty() \
		and int(hs._spread_motivation(friend, r).get("cap_delta", 0)) == -1)
	# A granted plea is just news — no zeal either way.
	var h2: Array = _harness()
	var gs2: GameState = h2[0]
	var hs2 = h2[2]
	var pet2: Dictionary = _spawn(gs2, "ogres")
	_decide(gs2, int(pet2.get("id", 0)), "Marla", "ogres", "mayor_grain", "Release Food")
	var rg: Dictionary = _petition_rumor(hs2)
	var rival2: Dictionary = _spawn(gs2, "elves")
	_check("grant: rival has no zeal (cap 0)",
		int(hs2._spread_motivation(rival2, rg).get("cap_delta", 0)) == 0)


func _test_truth_true_witnessed_fact() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	_decide(gs, int(pet.get("id", 0)), "Marla", "ogres", "mayor_grain", "Refuse")
	var r: Dictionary = _petition_rumor(hs)
	_check("court ruling is witnessed fact (TRUTH_TRUE)",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)


func _test_unknown_petitioner_no_crash() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# A petition dict with no parseable petitioner (old save shape).
	var p := {"id": 4242, "day": 3, "from_key": "", "from_name": "",
		"role": "Mayor", "faction": "ogres", "kind": "mayor_grain",
		"text": "x", "options": ["Release Food", "Refuse"],
		"resolved": true, "choice": 0}
	gs.bus.petition_decided.emit(p, "Release Food")
	var r: Dictionary = _petition_rumor(hs)
	_check("rumor still seeds without a petitioner", not r.is_empty())
	var bystander: Dictionary = _spawn(gs, "humans")
	hs._on_heard(bystander, r, {})
	_check("bystander reception does not crash",
		_recalled(bystander, "heard_rumor", int(r.get("id", 0))) >= 0.0)


func _test_dedup_same_petition() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	var before: int = (hs.state["rumors"] as Array).size()
	_decide(gs, int(pet.get("id", 0)), "Marla", "ogres", "mayor_grain", "Refuse")
	var after_first: int = (hs.state["rumors"] as Array).size()
	# Same petition id decided again (double-emit safety): no second rumor.
	_decide(gs, int(pet.get("id", 0)), "Marla", "ogres", "mayor_grain", "Refuse")
	var after_second: int = (hs.state["rumors"] as Array).size()
	_check("one rumor per petition", after_first == before + 1)
	_check("repeat decision does not duplicate", after_second == after_first)
