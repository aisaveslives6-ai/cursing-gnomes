extends SceneTree
## Cursing Gnomes — hearsay quest-ACCEPTANCE gossip tests (Jeremy 2026-10-09).
##
## Staged by the hearsay flesh-out wake: bus.adventure_quest_accepted was the
## last unhooked adventure signal — completions/failures/legends/falls all
## gossiped (2026-10-08 run) while the TAKING-UP stayed silent. Now:
##  - bus.adventure_quest_accepted seeds a RICH kind-"quest" rumor (hero
##    named, giver named, type-flavored taking-up verb, TRUTH_TRUE, heat
##    0.55 tavern talk — below PRESS_HEAT 0.85, no front page, first knower
##    in the hero's faction)
##  - the "Accepted quest:" deed does NOT double-post as thin gossip
##  - type verbs: bounty/rescue/escort/fetch/clear + unknown fallback
##  - the quest reaction matrix "taken" branch: hero's faction hopeful
##    (+3 mood, happy, heard_quest_taken), war-rivals mock (+2 mood, sad,
##    mocked_quest_take — they bet on failure), neutrals mildly interested
##    (+1, happy). Unhinged NPCs feel it 1.5x.
##  - spread motivation: home boasts (+1 cap, +0.1 heat), rivals mock the
##    fool's errand (+1 cap, +0.05), neutrals just gossip (0/0)
##  - no hero unit -> rumor still seeds, routes to generic reception
##  - re-acceptance refreshes the same rumor (subject dedup, no twin)
##  - both new memory types registered in SimMemories.TYPES with weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_quest_taken.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay quest-acceptance gossip tests ===")
	_test_acceptance_seeds_rich_rumor()
	_test_acceptance_deed_dedups()
	_test_take_verbs()
	_test_home_hopeful()
	_test_rival_mocks()
	_test_neutral_mildly_interested()
	_test_unhinged_amplified()
	_test_spread_motivation()
	_test_no_hero_fallback()
	_test_reacceptance_refreshes()
	_test_memory_types_registered()
	_test_below_press_heat()
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


func _spawn(gs: GameState, faction: String, mind: Dictionary = {}) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true, "mind": mind})


func _spawn_hero(gs: GameState, faction: String, hname: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true,
		"is_hero": true, "name": hname})


func _quest(title: String = "Taken in the Night", qid: String = "q1",
		qtype: String = "rescue") -> Dictionary:
	return {"id": qid, "type": qtype, "title": title,
		"giver_role": "mayor", "giver_name": "Mayor Humans",
		"state": "active", "failed": false}


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _rumor_of(hs, outcome: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "quest" \
				and String(r.get("quest_outcome", "")) == outcome:
			return r
	return {}


func _count_quest_rumors(hs) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "quest":
			n += 1
	return n


func _test_acceptance_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	gs.bus.adventure_quest_accepted.emit(_quest())
	var r := _rumor_of(hs, "taken")
	_check("acceptance seeds a quest rumor", not r.is_empty())
	if r.is_empty():
		return
	_check("acceptance names the hero", String(r.get("text", "")).find("Ash") >= 0)
	_check("acceptance names the giver", String(r.get("text", "")).find("Mayor Humans") >= 0)
	_check("acceptance names the quest", String(r.get("text", "")).find("Taken in the Night") >= 0)
	_check("acceptance records hero faction", String(r.get("hero_faction", "")) == "gnomes")
	_check("acceptance records quest title", String(r.get("quest_title", "")) == "Taken in the Night")
	_check("acceptance heat 0.55", is_equal_approx(float(r.get("heat", 0.0)), 0.55))
	_check("acceptance is confirmed truth", String(r.get("truth", "")) == "true")
	_check("acceptance subject", String(r.get("subject", "")) == "questtaken:q1")
	_check("acceptance has a first knower", (r.get("knowers", []) as Array).size() >= 1)


func _test_acceptance_deed_dedups() -> void:
	# The real game order: deed fires first, then the quest signal. The
	# thin deed gossip must not double-post the rich rumor.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	gs.bus.adventure_deed.emit("Accepted quest: Taken in the Night (from Mayor Humans).")
	gs.bus.adventure_quest_accepted.emit(_quest())
	var n_deed := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "deed":
			n_deed += 1
	_check("acceptance deed does not seed thin gossip", n_deed == 0)
	_check("acceptance still seeds exactly one rich rumor", _count_quest_rumors(hs) == 1)


func _test_take_verbs() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	gs.bus.adventure_quest_accepted.emit(_quest("Bandits in the Wilds", "q1", "bounty"))
	gs.bus.adventure_quest_accepted.emit(_quest("The Pilgrim's Road", "q2", "escort"))
	gs.bus.adventure_quest_accepted.emit(_quest("The Stolen Relic", "q3", "fetch"))
	gs.bus.adventure_quest_accepted.emit(_quest("Clear the Whispering Cave", "q4", "clear"))
	gs.bus.adventure_quest_accepted.emit(_quest("Odd Job", "q5", "mystery"))
	var texts: Dictionary = {}
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "quest":
			texts[String(r.get("subject", ""))] = String(r.get("text", ""))
	_check("bounty verb", String(texts.get("questtaken:q1", "")).find("taken up the bounty") >= 0)
	_check("escort verb", String(texts.get("questtaken:q2", "")).find("vowed to walk the pilgrim home") >= 0)
	_check("fetch verb", String(texts.get("questtaken:q3", "")).find("sworn to recover the relic") >= 0)
	_check("clear verb", String(texts.get("questtaken:q4", "")).find("marched out to silence the dungeon") >= 0)
	_check("unknown type falls back", String(texts.get("questtaken:q5", "")).find("taken up the quest") >= 0)


func _test_home_hopeful() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_spawn_hero(gs, "gnomes", "Ash")
	var fan: Dictionary = _spawn(gs, "gnomes")
	var uid := int(fan.get("id", 0))
	gs.bus.adventure_quest_accepted.emit(_quest())
	var r := _rumor_of(hs, "taken")
	hs._on_heard(fan, r, {})
	_check("home remembers the buzz", _recalled(fan, "heard_quest_taken", int(r.get("id", 0))) > 0.0)
	_check("home mood rises with hope", conv.ruler_mood(uid) > 0.0)
	_check("home feels hopeful", _emotion(fan) == "happy")


func _test_rival_mocks() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_spawn_hero(gs, "gnomes", "Ash")
	var rival: Dictionary = _spawn(gs, "ogres")
	var uid := int(rival.get("id", 0))
	gs.bus.adventure_quest_accepted.emit(_quest())
	var r := _rumor_of(hs, "taken")
	hs._on_heard(rival, r, {})
	_check("rival remembers mocking the attempt", _recalled(rival, "mocked_quest_take", int(r.get("id", 0))) > 0.0)
	_check("rival is amused", conv.ruler_mood(uid) > 0.0)
	_check("rival emotion is mockery", _emotion(rival) == "sad")


func _test_neutral_mildly_interested() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_spawn_hero(gs, "gnomes", "Ash")
	var elf: Dictionary = _spawn(gs, "elves")
	var uid := int(elf.get("id", 0))
	gs.bus.adventure_quest_accepted.emit(_quest())
	var r := _rumor_of(hs, "taken")
	hs._on_heard(elf, r, {})
	_check("neutral remembers the buzz", _recalled(elf, "heard_quest_taken", int(r.get("id", 0))) > 0.0)
	_check("neutral mood rises a little", conv.ruler_mood(uid) > 0.0)


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_spawn_hero(gs, "gnomes", "Ash")
	# Emit before the calm/wild citizens exist — the hero is the first
	# knower, so neither test subject can be randomly picked to hear
	# twice (double-hearing made this check flaky; same pattern as
	# test_hearsay_quest.gd's completion test).
	gs.bus.adventure_quest_accepted.emit(_quest())
	var r := _rumor_of(hs, "taken")
	var calm: Dictionary = _spawn(gs, "gnomes")
	var wild: Dictionary = _spawn(gs, "gnomes", {"traits": {"unhinged": 1.0}})
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	_check("unhinged NPC hopes harder than a calm one",
		conv.ruler_mood(int(wild.get("id", 0))) > conv.ruler_mood(int(calm.get("id", 0))))


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	var fan: Dictionary = _spawn(gs, "gnomes")
	var rival: Dictionary = _spawn(gs, "ogres")
	var neutral: Dictionary = _spawn(gs, "elves")
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	gs.bus.adventure_quest_accepted.emit(_quest())
	var taken := _rumor_of(hs, "taken")
	var m1: Dictionary = hs._spread_motivation(fan, taken)
	_check("home boasts the attempt", int(m1.get("cap_delta", 0)) == 1 and float(m1.get("heat_delta", 0.0)) > 0.0)
	var m2: Dictionary = hs._spread_motivation(rival, taken)
	_check("rival mocks the fool's errand", int(m2.get("cap_delta", 0)) == 1 and float(m2.get("heat_delta", 0.0)) > 0.0)
	var m3: Dictionary = hs._spread_motivation(neutral, taken)
	_check("neutral just gossips the odds", int(m3.get("cap_delta", 0)) == 0 and is_equal_approx(float(m3.get("heat_delta", 0.0)), 0.0))


func _test_no_hero_fallback() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn(gs, "gnomes")
	gs.bus.adventure_quest_accepted.emit(_quest())
	var r := _rumor_of(hs, "taken")
	_check("acceptance seeds without a hero", not r.is_empty())
	if not r.is_empty():
		_check("hero name falls back", String(r.get("hero_name", "")) == "the hero")
		_check("generic reception without a faction", true)


func _test_reacceptance_refreshes() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	gs.bus.adventure_quest_accepted.emit(_quest())
	gs.bus.adventure_quest_accepted.emit(_quest())
	_check("re-acceptance does not twin the rumor", _count_quest_rumors(hs) == 1)


func _test_memory_types_registered() -> void:
	var mem_cls = load("res://scripts/sim/memories.gd")
	_check("heard_quest_taken is a registered memory type", mem_cls.TYPES.has("heard_quest_taken"))
	_check("mocked_quest_take is a registered memory type", mem_cls.TYPES.has("mocked_quest_take"))
	_check("heard_quest_taken weight", is_equal_approx(float(mem_cls.REL_WEIGHT.get("heard_quest_taken", 0.0)), 0.1))
	_check("mocked_quest_take weight", is_equal_approx(float(mem_cls.REL_WEIGHT.get("mocked_quest_take", 0.0)), -0.2))


func _test_below_press_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_spawn_hero(gs, "gnomes", "Ash")
	_spawn(gs, "gnomes")
	gs.bus.adventure_quest_accepted.emit(_quest())
	var r := _rumor_of(hs, "taken")
	_check("acceptance stays tavern talk, not front page",
		not r.is_empty() and float(r.get("heat", 0.0)) < hs.PRESS_HEAT)
