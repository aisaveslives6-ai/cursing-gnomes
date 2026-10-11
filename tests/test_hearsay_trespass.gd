extends SceneTree
## Cursing Gnomes — hearsay trespass gossip tests (Jeremy 2026-10-10).
##
## bus.interior_entered was a deaf thread: NPCs visibly slip into other
## people's houses and the mill heard nothing. Now:
##  - entering a stranger's OWNED house seeds a RICH kind-"trespass"
##    rumor (snoop + owner named, subject "trespass:<building_id>",
##    dedup refreshes repeat visits)
##  - hard gates: houses only, living owner, entrant NOT a resident
##    (coming home is not news); rumor-worthy only at night or with a
##    real witness (occupant still inside, or a bystander within 250px
##    by day) — a quiet daytime visit to an empty house seeds nothing
##  - witnessed = TRUTH_TRUE heat 0.65 (tavern scandal, below
##    PRESS_HEAT 0.85, no front page); night second-hand = TRUTH_UNKNOWN
##    heat 0.45; Squabble posts on the fresh seed only
##  - the trespass reaction matrix: the owner is furious (trespass_anger,
##    angry), the household is uneasy (trespass_wary, scared), the snoop
##    is shamed (trespass_shame, scared) — or defiant and delighted if
##    unhinged (trespass_glee) — the snoop's rivals cackle (glee), the
##    snoop's friends go quiet (wary), everyone else is entertained
##    (trespass_news, happy). Unhinged x1.5.
##  - spread motivation: the snoop buries it, the owner/household
##    name-and-shame it, the snoop's rivals gloat-spread it, the snoop's
##    friends help bury it, neutrals tell it straight
##  - all 5 new memory types registered in SimMemories.TYPES with weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_trespass.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay trespass gossip tests ===")
	_test_night_entry_seeds_secondhand()
	_test_day_visit_to_empty_house_seeds_nothing()
	_test_day_bystander_witness_seeds_witnessed()
	_test_occupant_witness_seeds_witnessed()
	_test_resident_coming_home_seeds_nothing()
	_test_unowned_house_seeds_nothing()
	_test_non_house_seeds_nothing()
	_test_dead_owner_seeds_nothing()
	_test_repeat_visits_refresh_not_duplicate()
	_test_below_press_heat()
	_test_owner_furious()
	_test_snoop_shamed()
	_test_unhinged_snoop_defiant()
	_test_household_wary()
	_test_rival_cackles()
	_test_friend_goes_quiet()
	_test_neutral_entertained()
	_test_unhinged_amplified()
	_test_spread_motivation()
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


func _spawn(gs: GameState, faction: String, pos: Vector2 = Vector2.ZERO,
		mind: Dictionary = {}) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "alive": true,
		"mind": mind})
	u["position"] = pos
	return u


func _unhinged_mind() -> Dictionary:
	return {"traits": {"unhinged": 1.0}}


## An owned house at pos; owner (+ optional extra residents) registered.
## Returns the LIVE building dict (add_building indexes a duplicate).
func _house(gs: GameState, owner: Dictionary, pos: Vector2,
		extra_residents: Array = [], occupants: Array = [],
		btype: String = "house", owner_override: int = -2) -> Dictionary:
	var oid := int(owner.get("id", 0))
	var residents: Array = [oid] + extra_residents
	var orec: Dictionary = {
		"type": btype, "faction": String(owner.get("faction", "gnomes")),
		"alive": true, "complete": true, "position": pos,
		"owner_unit": oid if owner_override == -2 else owner_override,
		"residents": residents,
		"interior": {"occupants": occupants},
	}
	return gs.add_building(orec)


func _enter(gs: GameState, building_id: int, unit_id: int) -> void:
	gs.bus.interior_entered.emit(building_id, unit_id)


func _rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "trespass":
			return r
	return {}


func _count_trespass(hs) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "trespass":
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


## Spawn units in faction_b until one has npc_stance vs a inside [lo, hi].
func _find_stance(gs: GameState, a: Dictionary, faction_b: String,
		lo: float, hi: float) -> Dictionary:
	var likes = load("res://scripts/sim/likes_dislikes.gd")
	for i in 200:
		var cand: Dictionary = _spawn(gs, faction_b)
		var s: float = likes.npc_stance(cand, a, gs)
		if s >= lo and s <= hi:
			return cand
	return {}


func _test_night_entry_seeds_secondhand() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.is_night = true
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(400, 0))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var b := _house(gs, owner, Vector2.ZERO)
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	var r := _rumor(hs)
	_check("night entry seeds a trespass rumor", not r.is_empty())
	_check("subject keys the house",
		String(r.get("subject", "")) == "trespass:" + str(int(b.get("id", 0))))
	_check("snoop recorded", int(r.get("trespass_snoop_id", 0)) == int(snoop.get("id", 0)))
	_check("owner recorded", int(r.get("trespass_owner_id", 0)) == int(owner.get("id", 0)))
	_check("night second-hand is unverified talk",
		String(r.get("truth", "")) == hs.TRUTH_UNKNOWN)
	_check("second-hand heat is quiet",
		is_equal_approx(float(r.get("heat", 0.0)), 0.45))
	_check("text names the owner",
		String(r.get("text", "")).find("slipped into") >= 0)


func _test_day_visit_to_empty_house_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.is_night = false
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var b := _house(gs, owner, Vector2.ZERO)
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	_check("quiet daytime visit to an empty house seeds nothing",
		_rumor(hs).is_empty())


func _test_day_bystander_witness_seeds_witnessed() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.is_night = false
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var bystander: Dictionary = _spawn(gs, "elves", Vector2(100, 0))
	var b := _house(gs, owner, Vector2.ZERO)
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	var r := _rumor(hs)
	_check("daytime entry with a bystander seeds", not r.is_empty())
	_check("witnessed entry is verified fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("witnessed heat is tavern scandal",
		is_equal_approx(float(r.get("heat", 0.0)), 0.65))
	_check("bystander marked as first-hand witness",
		(r.get("witnesses", []) as Array).has(int(bystander.get("id", 0))))
	_check("text says broad daylight",
		String(r.get("text", "")).find("broad daylight") >= 0)


func _test_occupant_witness_seeds_witnessed() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.is_night = false
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(50, 0))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	# The owner is home when the snoop walks in — caught red-handed.
	var b := _house(gs, owner, Vector2.ZERO, [], [int(owner.get("id", 0))])
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	var r := _rumor(hs)
	_check("owner-at-home witnesses the entry", not r.is_empty())
	_check("occupant witness is verified fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)


func _test_resident_coming_home_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.is_night = true  # even at night, coming home is not news
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var b := _house(gs, owner, Vector2.ZERO)
	_enter(gs, int(b.get("id", 0)), int(owner.get("id", 0)))
	_check("owner entering their own house seeds nothing",
		_rumor(hs).is_empty())
	var mate: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var b2 := _house(gs, owner, Vector2(900, 0), [int(mate.get("id", 0))])
	_enter(gs, int(b2.get("id", 0)), int(mate.get("id", 0)))
	_check("housemate entering their own house seeds nothing",
		_count_trespass(hs) == 0)


func _test_unowned_house_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.is_night = true
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var b := _house(gs, owner, Vector2.ZERO, [], [], "house", -1)
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	_check("ownerless house entry seeds nothing", _rumor(hs).is_empty())


func _test_non_house_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.is_night = true
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var b := _house(gs, owner, Vector2.ZERO, [], [], "shop")
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	_check("non-house entry seeds nothing", _rumor(hs).is_empty())


func _test_dead_owner_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.is_night = true
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	owner["alive"] = false
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var b := _house(gs, owner, Vector2.ZERO)
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	_check("dead owner's house seeds nothing", _rumor(hs).is_empty())


func _test_repeat_visits_refresh_not_duplicate() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.is_night = true
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var b := _house(gs, owner, Vector2.ZERO)
	var bid := int(b.get("id", 0))
	_enter(gs, bid, int(snoop.get("id", 0)))
	_enter(gs, bid, int(snoop.get("id", 0)))
	_check("repeat visits refresh instead of twinning", _count_trespass(hs) == 1)


func _test_below_press_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.is_night = false
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	_spawn(gs, "elves", Vector2(100, 0))
	var b := _house(gs, owner, Vector2.ZERO)
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	var r := _rumor(hs)
	_check("trespass stays tavern talk, never front page",
		float(r.get("heat", 0.0)) < 0.85)


func _seed_night(gs: GameState, hs) -> Array:
	gs.is_night = true
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var b := _house(gs, owner, Vector2.ZERO)
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	return [owner, snoop, _rumor(hs)]


func _test_owner_furious() -> void:
	var h: Array = _harness()
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var s: Array = _seed_night(h[0], hs)
	var owner: Dictionary = s[0]
	var r: Dictionary = s[2]
	var uid := int(owner.get("id", 0))
	hs._on_heard(owner, r, {})
	_check("owner remembers the violation",
		_recalled(owner, "trespass_anger", int(r.get("id", 0))) > 0.0)
	_check("owner mood sinks with fury", conv.ruler_mood(uid) < 0.0)
	_check("owner feels angry", _emotion(owner) == "angry")


func _test_snoop_shamed() -> void:
	var h: Array = _harness()
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var s: Array = _seed_night(h[0], hs)
	var snoop: Dictionary = s[1]
	var r: Dictionary = s[2]
	var uid := int(snoop.get("id", 0))
	hs._on_heard(snoop, r, {})
	_check("snoop remembers the shame",
		_recalled(snoop, "trespass_shame", int(r.get("id", 0))) > 0.0)
	_check("snoop mood sinks", conv.ruler_mood(uid) < 0.0)
	_check("snoop feels scared", _emotion(snoop) == "scared")


func _test_unhinged_snoop_defiant() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.is_night = true
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000),
		_unhinged_mind())
	var b := _house(gs, owner, Vector2.ZERO)
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	var r := _rumor(hs)
	var uid := int(snoop.get("id", 0))
	hs._on_heard(snoop, r, {})
	_check("unhinged snoop is delighted, not shamed",
		_recalled(snoop, "trespass_glee", int(r.get("id", 0))) > 0.0)
	_check("unhinged snoop mood rises", conv.ruler_mood(uid) > 0.0)


func _test_household_wary() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.is_night = true
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var mate: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var b := _house(gs, owner, Vector2.ZERO, [int(mate.get("id", 0))])
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	var r := _rumor(hs)
	var uid := int(mate.get("id", 0))
	hs._on_heard(mate, r, {})
	_check("housemate remembers unease",
		_recalled(mate, "trespass_wary", int(r.get("id", 0))) > 0.0)
	_check("housemate mood dips", conv.ruler_mood(uid) < 0.0)
	_check("housemate feels scared", _emotion(mate) == "scared")


func _test_rival_cackles() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	# War makes cross-faction stance reliably hostile (gossip-test
	# pattern) — without it the pair-hash walk may never dip <= -0.3.
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var s: Array = _seed_night(gs, hs)
	var snoop: Dictionary = s[1]
	var r: Dictionary = s[2]
	var rival: Dictionary = _find_stance(gs, snoop, "elves", -1.0, -0.3)
	_check("rival found (stance <= -0.3)", not rival.is_empty())
	var uid := int(rival.get("id", 0))
	hs._on_heard(rival, r, {})
	_check("rival remembers gloating",
		_recalled(rival, "trespass_glee", int(r.get("id", 0))) > 0.0)
	_check("rival mood rises", conv.ruler_mood(uid) > 0.0)
	_check("rival emotion is mockery", _emotion(rival) == "sad")


func _test_friend_goes_quiet() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var s: Array = _seed_night(gs, hs)
	var snoop: Dictionary = s[1]
	var r: Dictionary = s[2]
	var friend: Dictionary = _find_stance(gs, snoop, "ogres", 0.3, 1.0)
	_check("friend found (stance >= 0.3)", not friend.is_empty())
	var uid := int(friend.get("id", 0))
	hs._on_heard(friend, r, {})
	_check("friend remembers unease, not glee",
		_recalled(friend, "trespass_wary", int(r.get("id", 0))) > 0.0)
	_check("friend mood dips", conv.ruler_mood(uid) < 0.0)


func _test_neutral_entertained() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var s: Array = _seed_night(gs, hs)
	var snoop: Dictionary = s[1]
	var r: Dictionary = s[2]
	var neutral: Dictionary = _find_stance(gs, snoop, "humans", -0.29, 0.29)
	_check("neutral found (|stance| < 0.3)", not neutral.is_empty())
	var uid := int(neutral.get("id", 0))
	hs._on_heard(neutral, r, {})
	_check("neutral remembers the news",
		_recalled(neutral, "trespass_news", int(r.get("id", 0))) > 0.0)
	_check("neutral is entertained", conv.ruler_mood(uid) > 0.0)
	_check("neutral feels happy", _emotion(neutral) == "happy")


func _owner_mood_after_hearing(unhinged: bool) -> float:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.is_night = true
	var mind := _unhinged_mind() if unhinged else {}
	var owner: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000), mind)
	var snoop: Dictionary = _spawn(gs, "ogres", Vector2(5000, 5000))
	var b := _house(gs, owner, Vector2.ZERO)
	_enter(gs, int(b.get("id", 0)), int(snoop.get("id", 0)))
	var r := _rumor(hs)
	hs._on_heard(owner, r, {})
	return conv.ruler_mood(int(owner.get("id", 0)))


func _test_unhinged_amplified() -> void:
	var calm_mood := _owner_mood_after_hearing(false)
	var wild_mood := _owner_mood_after_hearing(true)
	_check("calm owner fury lands", calm_mood < 0.0)
	_check("unhinged fury hits harder than calm fury", wild_mood < calm_mood)


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var s: Array = _seed_night(gs, hs)
	var owner: Dictionary = s[0]
	var snoop: Dictionary = s[1]
	var r: Dictionary = s[2]
	var rival: Dictionary = _find_stance(gs, snoop, "elves", -1.0, -0.3)
	var friend: Dictionary = _find_stance(gs, snoop, "ogres", 0.3, 1.0)
	var neutral: Dictionary = _find_stance(gs, snoop, "humans", -0.29, 0.29)
	_check("neutral found (|stance| < 0.3)", not neutral.is_empty())
	var bury: Dictionary = hs._spread_motivation(snoop, r)
	var push: Dictionary = hs._spread_motivation(owner, r)
	var gloat: Dictionary = hs._spread_motivation(rival, r)
	var hide: Dictionary = hs._spread_motivation(friend, r)
	var plain: Dictionary = hs._spread_motivation(neutral, r)
	_check("snoop buries it",
		int(bury.get("cap_delta", 0)) == -1 and float(bury.get("heat_delta", 0.0)) < 0.0)
	_check("owner name-and-shames it",
		int(push.get("cap_delta", 0)) == 1 and float(push.get("heat_delta", 0.0)) > 0.0)
	_check("rival gloat-spreads it",
		int(gloat.get("cap_delta", 0)) == 1 and float(gloat.get("heat_delta", 0.0)) > 0.0)
	_check("snoop's friend helps bury it",
		int(hide.get("cap_delta", 0)) == -1 and float(hide.get("heat_delta", 0.0)) < 0.0)
	_check("neutral tells it straight",
		int(plain.get("cap_delta", 0)) == 0 and float(plain.get("heat_delta", 1.0)) == 0.0)


func _test_memory_types_registered() -> void:
	var mem = load("res://scripts/sim/memories.gd")
	for t: String in ["trespass_anger", "trespass_wary", "trespass_glee",
			"trespass_shame", "trespass_news"]:
		_check("memory type registered: " + t, mem.TYPES.has(t))
		_check("memory weight set: " + t, mem.REL_WEIGHT.has(t))
