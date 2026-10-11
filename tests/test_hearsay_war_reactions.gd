extends SceneTree
## Cursing Gnomes — hearsay war-reaction tests (Jeremy 2026-10-07).
##
## Covers the hearsay flesh-out run: the war-news reaction matrix.
##  - war declared: the attacked side fears the drums (mood down,
##    scared — brave NPCs get angry via stands_ground parity — and a
##    "war_on_us" memory); the attacking side rallies (mood up, proud,
##    "war_declared_by_us" memory)
##  - neutral factions get the generic reception (no war memories)
##  - unhinged NPCs feel war news 1.5x (matching the smear path)
##  - surrender accepted: losers demoralized ("we_surrendered", mood
##    down), winners celebrate ("enemy_surrendered", mood up, proud)
##  - surrender offered: milder dread/anticipation on both sides
##  - rumors with no recorded sides (old saves, Gazette-seeded): the
##    generic reception path, no crash
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_war_reactions.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay war-reaction tests ===")
	_test_war_attacked_side_fears()
	_test_war_attacking_side_rallies()
	_test_war_neutral_gets_generic()
	_test_war_unhinged_amplified()
	_test_surrender_accepted_reactions()
	_test_surrender_offered_milder()
	_test_war_no_sides_generic_no_crash()
	_test_war_sides_saved()
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


func _war_rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "war" \
				and not String(r.get("subject", "")).begins_with("surrender"):
			return r
	return {}


func _mem() -> RefCounted:
	return load("res://scripts/sim/memories.gd").new(_new_gs())


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	# Memories live on the unit dict; a fresh SimMemories reads them.
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _test_war_attacked_side_fears() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var defender: Dictionary = _spawn(gs, "ogres")
	var did := int(defender.get("id", 0))
	gs.bus.war_declared.emit("elves", "ogres")
	var r: Dictionary = _war_rumor(hs)
	_check("war rumor seeded with sides", not r.is_empty() \
		and String(r.get("side_a", "")) == "elves" \
		and String(r.get("side_b", "")) == "ogres")
	var mood_before: float = conv.ruler_mood(did)
	hs._on_heard(defender, r, {})
	_check("defender mood drops on war news", conv.ruler_mood(did) < mood_before)
	_check("defender scared or angry (brave)", _emotion(defender) == "scared" \
		or _emotion(defender) == "angry")
	_check("defender remembers war_on_us",
		_recalled(defender, "war_on_us", int(r.get("id", 0))) > 0.0)


func _test_war_attacking_side_rallies() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var attacker: Dictionary = _spawn(gs, "elves")
	var aid := int(attacker.get("id", 0))
	gs.bus.war_declared.emit("elves", "ogres")
	var r: Dictionary = _war_rumor(hs)
	var mood_before: float = conv.ruler_mood(aid)
	hs._on_heard(attacker, r, {})
	_check("attacker mood rises on war news", conv.ruler_mood(aid) > mood_before)
	_check("attacker proud", _emotion(attacker) == "proud")
	_check("attacker remembers war_declared_by_us",
		_recalled(attacker, "war_declared_by_us", int(r.get("id", 0))) > 0.0)


func _test_war_neutral_gets_generic() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var neutral: Dictionary = _spawn(gs, "gnomes")
	var nid := int(neutral.get("id", 0))
	gs.bus.war_declared.emit("elves", "ogres")
	var r: Dictionary = _war_rumor(hs)
	var mood_before: float = conv.ruler_mood(nid)
	hs._on_heard(neutral, r, {})
	_check("neutral mood untouched by foreign war",
		is_equal_approx(conv.ruler_mood(nid), mood_before))
	_check("neutral gets no war_on_us memory",
		_recalled(neutral, "war_on_us", int(r.get("id", 0))) == 0.0)
	_check("neutral gets no war_declared_by_us memory",
		_recalled(neutral, "war_declared_by_us", int(r.get("id", 0))) == 0.0)
	_check("neutral gets generic heard_rumor memory",
		_recalled(neutral, "heard_rumor", int(r.get("id", 0))) > 0.0)


func _test_war_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var calm: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres", true)
	gs.bus.war_declared.emit("elves", "ogres")
	var r: Dictionary = _war_rumor(hs)
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	var calm_delta: float = conv.ruler_mood(int(calm.get("id", 0)))
	var wild_delta: float = conv.ruler_mood(int(wild.get("id", 0)))
	_check("unhinged defender fears war 1.5x",
		wild_delta < calm_delta and is_equal_approx(wild_delta, calm_delta * 1.5))


func _surrender_rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("subject", "")).begins_with("surrendered:"):
			return r
	return {}


func _offer_rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("subject", "")).begins_with("surrender:"):
			return r
	return {}


func _test_surrender_accepted_reactions() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var loser: Dictionary = _spawn(gs, "ogres")
	var winner: Dictionary = _spawn(gs, "elves")
	gs.bus.surrender_accepted.emit("ogres", "elves")
	var r: Dictionary = _surrender_rumor(hs)
	_check("surrender rumor records loser/winner", not r.is_empty() \
		and String(r.get("loser", "")) == "ogres" \
		and String(r.get("winner", "")) == "elves")
	hs._on_heard(loser, r, {})
	hs._on_heard(winner, r, {})
	_check("loser demoralized", conv.ruler_mood(int(loser.get("id", 0))) < 0.0)
	_check("loser remembers we_surrendered",
		_recalled(loser, "we_surrendered", int(r.get("id", 0))) > 0.0)
	_check("winner mood up", conv.ruler_mood(int(winner.get("id", 0))) > 0.0)
	_check("winner proud", _emotion(winner) == "proud")
	_check("winner remembers enemy_surrendered",
		_recalled(winner, "enemy_surrendered", int(r.get("id", 0))) > 0.0)


func _test_surrender_offered_milder() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var loser: Dictionary = _spawn(gs, "ogres")
	var winner: Dictionary = _spawn(gs, "elves")
	gs.bus.surrender_offered.emit("ogres", "elves")
	var r: Dictionary = _offer_rumor(hs)
	_check("offer rumor records loser/winner", not r.is_empty() \
		and String(r.get("loser", "")) == "ogres" \
		and String(r.get("winner", "")) == "elves")
	hs._on_heard(loser, r, {})
	hs._on_heard(winner, r, {})
	var loser_mood: float = conv.ruler_mood(int(loser.get("id", 0)))
	var winner_mood: float = conv.ruler_mood(int(winner.get("id", 0)))
	_check("offer rattles loser mildly", loser_mood < 0.0 and loser_mood > -10.0)
	_check("offer lifts winner mildly", winner_mood > 0.0 and winner_mood < 10.0)
	_check("loser remembers surrender_offered",
		_recalled(loser, "surrender_offered", int(r.get("id", 0))) > 0.0)


func _test_war_no_sides_generic_no_crash() -> void:
	# Old saves and Gazette-seeded war rumors carry no sides — they must
	# take the generic reception path without crashing.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var u: Dictionary = _spawn(gs, "ogres")
	var r: Dictionary = {"id": 4242, "kind": "war", "subject": "elves",
		"text": "WAR with the Elves!", "heat": 0.9}
	hs._on_heard(u, r, {})
	_check("sideless war rumor: generic heard_rumor memory",
		_recalled(u, "heard_rumor", 4242) > 0.0)
	_check("sideless war rumor: no war_on_us memory",
		_recalled(u, "war_on_us", 4242) == 0.0)
	# Save/load backfill: pre-matrix saves gain the new fields.
	var d: Dictionary = hs.to_dict()
	hs.from_dict({"rumors": [{"id": 7, "kind": "war", "subject": "elves",
		"text": "old", "heat": 0.5}]})
	var backfilled: Dictionary = hs.state["rumors"][0]
	_check("backfill adds side_a", backfilled.get("side_a", "MISSING") == "")
	_check("backfill adds side_b", backfilled.get("side_b", "MISSING") == "")
	_check("backfill adds loser", backfilled.get("loser", "MISSING") == "")
	_check("backfill adds winner", backfilled.get("winner", "MISSING") == "")


func _test_war_sides_saved() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.war_declared.emit("elves", "ogres")
	var d: Dictionary = hs.to_dict()
	var hs2 = load("res://scripts/sim/hearsay.gd").new(gs)
	hs2.from_dict(d)
	var found := false
	for r: Dictionary in hs2.state["rumors"]:
		if String(r.get("kind", "")) == "war" \
				and String(r.get("side_a", "")) == "elves" \
				and String(r.get("side_b", "")) == "ogres":
			found = true
	_check("war sides survive save/load roundtrip", found)
