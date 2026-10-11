extends SceneTree
## Cursing Gnomes — hearsay court-FILING tests (Jeremy 2026-10-09).
##
## Covers the hearsay flesh-out run: court petitions being FILED were a deaf
## thread — the crown's RULING gossiped since 10-08 (petition_decided), but a
## courtier standing up to ASK never reached the mill. Now bus.petition_opened
## seeds a witnessed-fact "news" rumor (subject "petition_filed:<id>",
## disjoint from the verdict's "petition:<id>") and the realm reacts:
##  - the petitioner feels pride and hope (filed_petition, "hopeful")
##  - their own faction takes an interest (heard_petition_filed)
##  - friends drum up support (backed_petition_filing)
##  - rivals mock the ask (mocked_petition_filing, amused)
##  - a war-shaped plea filed against YOUR people lands as dread
##    (dreaded_petition_filing, angry) — not gossip
##  - hot filings (threat/betrayal/raids/drafts) run at 0.7, routine at 0.55
##  - spread: friends push (+1), rivals mock-spread (+1, hotter)
##  - unhinged NPCs feel it 1.5x (verdict parity)
##  - Squabble posts for filings (normal + hot pools)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_petition_filing.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay court-filing tests ===")
	_test_filing_seeds_rumor()
	_test_hot_filing_seeds_hot()
	_test_hot_kind_detection()
	_test_petitioner_hopeful()
	_test_own_faction_interest()
	_test_friend_backs_filing()
	_test_rival_mocks_filing()
	_test_war_plea_dread()
	_test_nonhot_filing_no_dread()
	_test_unhinged_amplified()
	_test_spread_motivation_filing()
	_test_truth_true_witnessed_fact()
	_test_unknown_petitioner_no_crash()
	_test_dedup_same_filing()
	_test_verdict_coexists()
	_test_squabble_post()
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


## Emit a real bus.petition_opened (the royal_court payload shape).
func _file(gs: GameState, pid: int, pname: String, faction: String,
		kind: String, num: int = 4242) -> Dictionary:
	var p := {
		"id": num, "day": 3,
		"from_key": "u%d" % pid, "from_name": pname,
		"role": "Mayor", "faction": faction, "kind": kind,
		"text": "Please %s." % kind, "options": ["Grant", "Refuse"],
		"resolved": false, "choice": -1,
	}
	gs.bus.petition_opened.emit(p)
	return p


func _filing_rumor(hs, num: int = 4242) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "news" \
				and String(r.get("subject", "")) == "petition_filed:%d" % num:
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


func _test_filing_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_file(gs, pid, "Marla", "ogres", "mayor_grain")
	var r: Dictionary = _filing_rumor(hs)
	_check("filing seeds a news rumor", not r.is_empty())
	_check("filing kind recorded", String(r.get("petition_filing", "")) == "Mayor Grain")
	_check("routine filing is cool talk (0.55)", absf(float(r.get("heat", 0.0)) - 0.55) < 0.01)
	_check("not a hot filing", not bool(r.get("petition_hot", true)))
	_check("petitioner id recorded", int(r.get("petitioner_id", 0)) == pid)
	_check("petitioner name recorded", String(r.get("petitioner_name", "")) == "Marla")
	_check("petitioner faction recorded", String(r.get("petitioner_faction", "")) == "ogres")
	_check("petitioner heard it first (knower)", (r.get("knowers", []) as Array).has(pid))
	_check("petitioner named in text", String(r.get("text", "")).contains("Marla"))


func _test_hot_filing_seeds_hot() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	_file(gs, int(pet.get("id", 0)), "Graz", "ogres", "threat")
	var r: Dictionary = _filing_rumor(hs)
	_check("hot filing seeds a news rumor", not r.is_empty())
	_check("hot filing runs hotter (0.7)", absf(float(r.get("heat", 0.0)) - 0.7) < 0.01)
	_check("hot filing flagged", bool(r.get("petition_hot", false)))
	_check("hot filing quiets the tavern", String(r.get("text", "")).contains("gone very quiet"))


func _test_hot_kind_detection() -> void:
	var h: Array = _harness()
	var hs = h[2]
	_check("threat is hot", hs._petition_filing_hot("threat"))
	_check("betrayal is hot", hs._petition_filing_hot("betrayal"))
	_check("lord_raid is hot", hs._petition_filing_hot("lord_raid"))
	_check("commander_draft is hot", hs._petition_filing_hot("commander_draft"))
	_check("commander_guns is hot", hs._petition_filing_hot("commander_guns"))
	_check("mayor_grain is not hot", not hs._petition_filing_hot("mayor_grain"))
	_check("bc_trade is not hot", not hs._petition_filing_hot("bc_trade"))
	_check("alliance is not hot", not hs._petition_filing_hot("alliance"))


func _test_petitioner_hopeful() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_file(gs, pid, "Marla", "ogres", "mayor_grain")
	var r: Dictionary = _filing_rumor(hs)
	_check("petitioner remembers filing",
		_recalled(pet, "filed_petition", int(r.get("id", 0))) > 0.0)
	_check("filing makes the petitioner hopeful (happy)", _emotion(pet) == "happy")
	_check("petitioner mood lifts on filing", conv.ruler_mood(pid) > 0.0)


func _test_own_faction_interest() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_file(gs, pid, "Marla", "ogres", "mayor_grain")
	var r: Dictionary = _filing_rumor(hs)
	var folk: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(folk, r, {})
	_check("own faction notes the filing",
		_recalled(folk, "heard_petition_filed", pid) > 0.0)


func _test_friend_backs_filing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_file(gs, pid, "Marla", "ogres", "mayor_grain")
	var r: Dictionary = _filing_rumor(hs)
	var friend: Dictionary = _find_stance(gs, pet, "elves", 0.3, 1.0)
	_check("found a friend of the petitioner", not friend.is_empty())
	if friend.is_empty():
		return
	hs._on_heard(friend, r, {})
	_check("friend drums up support",
		_recalled(friend, "backed_petition_filing", pid) > 0.0)


func _test_rival_mocks_filing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_file(gs, pid, "Marla", "ogres", "mayor_grain")
	var r: Dictionary = _filing_rumor(hs)
	var rival: Dictionary = _find_stance(gs, pet, "elves", -1.0, -0.3)
	_check("found a rival of the petitioner", not rival.is_empty())
	if rival.is_empty():
		return
	hs._on_heard(rival, r, {})
	_check("rival mocks the ask",
		_recalled(rival, "mocked_petition_filing", pid) > 0.0)
	_check("mockery amuses the rival (happy)", _emotion(rival) == "happy")


func _test_war_plea_dread() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("ogres", "elves")
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_file(gs, pid, "Graz", "ogres", "threat")
	var r: Dictionary = _filing_rumor(hs)
	var elf: Dictionary = _spawn(gs, "elves")
	hs._on_heard(elf, r, {})
	_check("war-plea target dreads the filing",
		_recalled(elf, "dreaded_petition_filing", pid) > 0.0)
	_check("dread angers the target", _emotion(elf) == "angry")


func _test_nonhot_filing_no_dread() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("ogres", "elves")
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_file(gs, pid, "Marla", "ogres", "mayor_grain")
	var r: Dictionary = _filing_rumor(hs)
	var elf: Dictionary = _spawn(gs, "elves")
	hs._on_heard(elf, r, {})
	_check("routine filing at a war-rival is not dread",
		_recalled(elf, "dreaded_petition_filing", pid) == 0.0)


func _test_unhinged_amplified() -> void:
	# Two separate filings: the unhinged petitioner must feel the hope
	# 1.5x harder than a level-headed one.
	var h1: Array = _harness()
	var gs1: GameState = h1[0]
	var conv1 = h1[1].get("conversation")
	var calm: Dictionary = _spawn(gs1, "ogres")
	_file(gs1, int(calm.get("id", 0)), "Calm", "ogres", "mayor_grain")
	var h2: Array = _harness()
	var gs2: GameState = h2[0]
	var conv2 = h2[1].get("conversation")
	var wild: Dictionary = _spawn(gs2, "ogres", true)
	_file(gs2, int(wild.get("id", 0)), "Wild", "ogres", "mayor_grain")
	_check("unhinged hope hits 1.5x harder",
		conv2.ruler_mood(int(wild.get("id", 0))) \
			> conv1.ruler_mood(int(calm.get("id", 0))))


func _test_spread_motivation_filing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	_file(gs, int(pet.get("id", 0)), "Marla", "ogres", "mayor_grain")
	var r: Dictionary = _filing_rumor(hs)
	var likes = load("res://scripts/sim/likes_dislikes.gd")
	var rival: Dictionary = _find_stance(gs, pet, "elves", -1.0, -0.3)
	var friend: Dictionary = _find_stance(gs, pet, "elves", 0.3, 1.0)
	# Neutral is whatever the RNG gives — assert the mapping, not the draw.
	var neutral: Dictionary = _spawn(gs, "humans")
	var ns: float = likes.npc_stance(neutral, pet, gs)
	var expected := 0
	if ns <= -0.3 or ns >= 0.3:
		expected = 1
	_check("filing: teller zeal matches stance toward petitioner",
		int(hs._spread_motivation(neutral, r).get("cap_delta", 0)) == expected)
	_check("filing: friend drums up support (cap +1)",
		not friend.is_empty() \
		and int(hs._spread_motivation(friend, r).get("cap_delta", 0)) == 1)
	_check("filing: rival mock-spreads (cap +1)",
		not rival.is_empty() \
		and int(hs._spread_motivation(rival, r).get("cap_delta", 0)) == 1)
	_check("filing: rival mock-spread runs hotter",
		not rival.is_empty() \
		and float(hs._spread_motivation(rival, r).get("heat_delta", 0.0)) > 0.05)


func _test_truth_true_witnessed_fact() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	_file(gs, int(pet.get("id", 0)), "Marla", "ogres", "mayor_grain")
	var r: Dictionary = _filing_rumor(hs)
	_check("filing is a witnessed court fact", String(r.get("truth", "")) == "true")


func _test_unknown_petitioner_no_crash() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# from_key points at a unit that doesn't exist; from_name blank.
	var p := {
		"id": 4242, "day": 3,
		"from_key": "u99999", "from_name": "",
		"role": "Mayor", "faction": "ogres", "kind": "mayor_grain",
		"text": "Please.", "options": ["Grant", "Refuse"],
		"resolved": false, "choice": -1,
	}
	gs.bus.petition_opened.emit(p)
	var r: Dictionary = _filing_rumor(hs)
	_check("unknown petitioner still seeds", not r.is_empty())
	_check("blank name falls back", String(r.get("text", "")).contains("A petitioner"))
	_check("no phantom knower", not (r.get("knowers", []) as Array).has(99999))


func _test_dedup_same_filing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	_file(gs, int(pet.get("id", 0)), "Marla", "ogres", "mayor_grain")
	_file(gs, int(pet.get("id", 0)), "Marla", "ogres", "mayor_grain")
	var n := 0
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("subject", "")) == "petition_filed:4242":
			n += 1
	_check("repeat filing refreshes, never twins", n == 1)


func _test_verdict_coexists() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var pet: Dictionary = _spawn(gs, "ogres")
	var pid := int(pet.get("id", 0))
	_file(gs, pid, "Marla", "ogres", "mayor_grain")
	# The crown rules on the same petition — the verdict seeds its own rumor.
	var p := {
		"id": 4242, "day": 3,
		"from_key": "u%d" % pid, "from_name": "Marla",
		"role": "Mayor", "faction": "ogres", "kind": "mayor_grain",
		"text": "Please mayor_grain.", "options": ["Release Food", "Refuse"],
		"resolved": true, "choice": 0,
	}
	gs.bus.petition_decided.emit(p, "Release Food")
	var filing: Dictionary = _filing_rumor(hs)
	var verdict: Dictionary = {}
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("subject", "")) == "petition:4242":
			verdict = r2
	_check("filing rumor survives the verdict", not filing.is_empty())
	_check("verdict seeds its own rumor", not verdict.is_empty())
	_check("verdict recorded on the verdict rumor",
		String(verdict.get("petition_verdict", "")) == "granted")


func _test_squabble_post() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_spawn(gs, "gnomes")  # player-faction author for the post
	var pet: Dictionary = _spawn(gs, "ogres")
	_file(gs, int(pet.get("id", 0)), "Marla", "ogres", "mayor_grain")
	var found := false
	for post: Dictionary in (phone.state["posts"] as Array):
		if String(post.get("kind", "")) == "petition_filing" \
				and String(post.get("text", "")).contains("Marla"):
			found = true
	_check("filing becomes a Squabble post", found)
	# Hot filings post from the hot pool.
	_file(gs, int(pet.get("id", 0)), "Graz", "ogres", "threat", 4243)
	var hot_found := false
	for post: Dictionary in (phone.state["posts"] as Array):
		if String(post.get("kind", "")) == "petition_filing" \
				and String(post.get("text", "")).contains("Graz"):
			hot_found = true
	_check("hot filing becomes a Squabble post", hot_found)
