extends SceneTree
## Cursing Gnomes — hearsay storm-omen gossip tests (Jeremy 2026-10-09).
##
## STAGED by the hearsay flesh-out wake: bus.crystal_struck was the last
## unhooked sim signal with a VISIBLE dramatic event — lightning hammers
## the rogue gods' dark crystals every storm (combat_fx "crystal_strike",
## flare + hum) and the mill heard NOTHING. Now:
##  - bus.crystal_struck seeds a RICH kind-"crystal" rumor (god named,
##    holding faction recorded, TRUTH_TRUE, heat 0.7 tavern talk — below
##    PRESS_HEAT 0.85, no front page)
##  - repeat strikes refresh the rumor via subject dedup (no twin per
##    bolt), Squabble posts only on the fresh seed
##  - the crystal reaction matrix: the holder's people read dread
##    (crystal_struck_omen, scared), unhinged holders cackle with the sky
##    (crystal_struck_glee, mocked), war-rivals gloat (glee, mocked),
##    wild crystals inspire awe (crystal_struck_wonder, helped), neutrals
##    feel mild unease (crystal_struck_news, scared). Unhinged x1.5.
##  - spread motivation: the owner's faction buries a bad omen, rivals
##    gloat-spread it, everyone else tells it straight
##  - missing roster / missing method fall back gracefully
##  - all 4 new memory types registered in SimMemories.TYPES with weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_crystal_strike.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay storm-omen gossip tests ===")
	_test_strike_seeds_rich_rumor()
	_test_below_press_heat()
	_test_truth_true()
	_test_owner_reads_dread()
	_test_unhinged_owner_cackles()
	_test_rival_gloats()
	_test_wild_crystal_wonder()
	_test_neutral_mildly_uneasy()
	_test_unhinged_amplified()
	_test_spread_motivation()
	_test_repeat_strike_refreshes()
	_test_witnesses()
	_test_no_roster_fallback()
	_test_memory_types_registered()
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


## Crystal roster: _gs.get("crystals") is a plain Dictionary roster in
## tests (an Object node in production — the handler handles both).
func _roster(gs: GameState, owner: String) -> void:
	gs.set("crystals", {"crystals": [
		{"id": 7, "god_id": "raijuk", "owner": owner,
			"position": Vector2.ZERO},
	]})


func _spawn(gs: GameState, faction: String, pos: Vector2,
		mind: Dictionary = {}) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "alive": true,
		"mind": mind})
	u["position"] = pos
	return u


func _unhinged_mind() -> Dictionary:
	return {"traits": {"unhinged": 1.0}}


func _strike(gs: GameState, pos: Vector2 = Vector2.ZERO) -> void:
	gs.bus.crystal_struck.emit(7, pos)


func _rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "crystal":
			return r
	return {}


func _count_crystal_rumors(hs) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "crystal":
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


func _test_strike_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_roster(gs, "ogres")
	_strike(gs)
	var r := _rumor(hs)
	_check("strike seeds a crystal rumor", not r.is_empty())
	_check("subject names the god", String(r.get("subject", "")) == "crystalstruck:raijuk")
	_check("owner recorded", String(r.get("crystal_owner", "")) == "ogres")
	_check("god recorded", String(r.get("crystal_god", "")) == "raijuk")
	_check("display name falls back sanely",
		String(r.get("crystal_name", "")).begins_with("the Dark Crystal of Raijuk"))
	_check("text names the crystal",
		String(r.get("text", "")).find("Raijuk") >= 0)


func _test_below_press_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_roster(gs, "ogres")
	_strike(gs)
	var r := _rumor(hs)
	_check("heat is tavern talk, not front page",
		float(r.get("heat", 0.0)) < 0.85)


func _test_truth_true() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_roster(gs, "ogres")
	_strike(gs)
	var r := _rumor(hs)
	# TRUTH_TRUE constant lives on the hearsay instance.
	_check("a lightning strike is witnessed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)


func _test_owner_reads_dread() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_roster(gs, "ogres")
	_strike(gs)
	var r := _rumor(hs)
	var holder: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var uid := int(holder.get("id", 0))
	hs._on_heard(holder, r, {})
	_check("holder remembers the omen",
		_recalled(holder, "crystal_struck_omen", int(r.get("id", 0))) > 0.0)
	_check("holder mood sinks with dread", conv.ruler_mood(uid) < 0.0)
	_check("holder feels scared", _emotion(holder) == "scared")


func _test_unhinged_owner_cackles() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_roster(gs, "ogres")
	_strike(gs)
	var r := _rumor(hs)
	var wild: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000),
		_unhinged_mind())
	var uid := int(wild.get("id", 0))
	hs._on_heard(wild, r, {})
	_check("unhinged holder cackles with the sky",
		_recalled(wild, "crystal_struck_glee", int(r.get("id", 0))) > 0.0)
	_check("unhinged holder mood rises", conv.ruler_mood(uid) > 0.0)
	_check("unhinged holder is mocked, not scared", _emotion(wild) == "sad")


func _test_rival_gloats() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_roster(gs, "ogres")
	_strike(gs)
	var r := _rumor(hs)
	var rival: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var uid := int(rival.get("id", 0))
	hs._on_heard(rival, r, {})
	_check("rival remembers gloating",
		_recalled(rival, "crystal_struck_glee", int(r.get("id", 0))) > 0.0)
	_check("rival mood rises with glee", conv.ruler_mood(uid) > 0.0)
	_check("rival emotion is mockery", _emotion(rival) == "sad")


func _test_wild_crystal_wonder() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_roster(gs, "")
	_strike(gs)
	var r := _rumor(hs)
	_check("wild crystal seeds under the wild subject",
		String(r.get("subject", "")) == "crystalstruck:raijuk")
	var gazer: Dictionary = _spawn(gs, "elves", Vector2(5000, 5000))
	var uid := int(gazer.get("id", 0))
	hs._on_heard(gazer, r, {})
	_check("wild strike remembered with wonder",
		_recalled(gazer, "crystal_struck_wonder", int(r.get("id", 0))) > 0.0)
	_check("wonder lifts mood", conv.ruler_mood(uid) > 0.0)
	_check("wonder feels happy", _emotion(gazer) == "happy")


func _test_neutral_mildly_uneasy() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_roster(gs, "ogres")
	_strike(gs)
	var r := _rumor(hs)
	var neutral: Dictionary = _spawn(gs, "elves", Vector2(5000, 5000))
	var uid := int(neutral.get("id", 0))
	hs._on_heard(neutral, r, {})
	_check("neutral remembers the news",
		_recalled(neutral, "crystal_struck_news", int(r.get("id", 0))) > 0.0)
	_check("neutral mood dips", conv.ruler_mood(uid) < 0.0)
	_check("neutral feels scared", _emotion(neutral) == "scared")


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_roster(gs, "ogres")
	_strike(gs)
	var r := _rumor(hs)
	var calm: Dictionary = _spawn(gs, "elves", Vector2(5000, 5000))
	var wild: Dictionary = _spawn(gs, "elves", Vector2(6000, 6000),
		_unhinged_mind())
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	var calm_mood = conv.ruler_mood(int(calm.get("id", 0)))
	var wild_mood = conv.ruler_mood(int(wild.get("id", 0)))
	_check("unhinged feels the omen 1.5x",
		wild_mood < calm_mood and absf(wild_mood - calm_mood * 1.5) < 0.01)


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_roster(gs, "ogres")
	_strike(gs)
	var r := _rumor(hs)
	var owner_u: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var neutral_u: Dictionary = _spawn(gs, "elves", Vector2(6000, 6000))
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var rival_u: Dictionary = _spawn(gs, "gnomes", Vector2(7000, 7000))
	var bury: Dictionary = hs._spread_motivation(owner_u, r)
	var gloat: Dictionary = hs._spread_motivation(rival_u, r)
	var plain: Dictionary = hs._spread_motivation(neutral_u, r)
	_check("owner buries a bad omen",
		int(bury.get("cap_delta", 0)) == -1 and float(bury.get("heat_delta", 0.0)) < 0.0)
	_check("rival gloat-spreads it",
		int(gloat.get("cap_delta", 0)) == 1 and float(gloat.get("heat_delta", 0.0)) > 0.0)
	_check("neutral tells it straight",
		int(plain.get("cap_delta", 0)) == 0 and float(plain.get("heat_delta", 1.0)) == 0.0)


func _test_repeat_strike_refreshes() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_roster(gs, "ogres")
	_strike(gs)
	var r := _rumor(hs)
	r["heat"] = 0.1
	_strike(gs)
	_check("no twin per bolt", _count_crystal_rumors(hs) == 1)
	var r2 := _rumor(hs)
	_check("repeat strike refreshes heat", float(r2.get("heat", 0.0)) >= 0.7)


func _test_witnesses() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_roster(gs, "ogres")
	var near: Dictionary = _spawn(gs, "elves", Vector2(50, 0))
	var far: Dictionary = _spawn(gs, "elves", Vector2(5000, 5000))
	_strike(gs, Vector2.ZERO)
	var r := _rumor(hs)
	var knowers: Array = r.get("knowers", [])
	var wits: Array = r.get("witnesses", [])
	_check("nearby NPC witnesses the strike",
		knowers.has(int(near.get("id", 0))) and wits.has(int(near.get("id", 0))))
	_check("distant NPC does not",
		not knowers.has(int(far.get("id", 0))))
	_check("witness remembers seeing it",
		_recalled(near, "witnessed_rumor", int(r.get("id", 0))) > 0.0)


func _test_no_roster_fallback() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# No "crystals" set at all — old save / pre-placement.
	_strike(gs)
	var r := _rumor(hs)
	_check("strike still seeds with no roster", not r.is_empty())
	_check("owner defaults to wild", String(r.get("crystal_owner", "X")) == "")
	_check("name falls back gracefully",
		String(r.get("crystal_name", "")) == "a dark crystal")


func _test_memory_types_registered() -> void:
	_check("omen type registered",
		"crystal_struck_omen" in SimMemories.TYPES)
	_check("glee type registered",
		"crystal_struck_glee" in SimMemories.TYPES)
	_check("wonder type registered",
		"crystal_struck_wonder" in SimMemories.TYPES)
	_check("news type registered",
		"crystal_struck_news" in SimMemories.TYPES)
	_check("omen weight self-directed",
		float(SimMemories.REL_WEIGHT.get("crystal_struck_omen", 9.9)) == 0.0)
	_check("glee weight cools like other mocks",
		float(SimMemories.REL_WEIGHT.get("crystal_struck_glee", 9.9)) == -0.2)
	_check("wonder weight fond",
		float(SimMemories.REL_WEIGHT.get("crystal_struck_wonder", 9.9)) == 0.1)
	_check("news weight neutral",
		float(SimMemories.REL_WEIGHT.get("crystal_struck_news", 9.9)) == 0.0)
