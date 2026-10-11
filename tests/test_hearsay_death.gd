extends SceneTree
## Cursing Gnomes — hearsay death-of-notable reaction tests
## (Jeremy 2026-10-07, hearsay flesh-out).
##
## The obituary thread was the weakest grapevine thread: deaths of notables
## seeded rumors but the signal's faction was DISCARDED (param literally named
## _faction) and every hearer got the same generic "friend_died" beat — an
## ogre hearing the ELVEN spymaster died mourned the same as an elf. Now
## the obituary records the dead's faction at seed and hearers react in
## character (the death reaction matrix):
##  - own faction mourns: mood down hard, "mourned_our_dead"
##  - war/hostile rival cackles (schadenfreude): mood up, "rival_dead"
##  - everyone else pays respects: mild dip, "heard_dead_other"
##  - facet-less obituaries (old saves, Gazette-seeded): generic reception
##  - unhinged NPCs feel it 1.5x (war/smear/diplomacy parity)
##  - per-notable subject: two dead advisors don't collapse into one rumor
##  - dedup + save/load keep dead_faction
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_death.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay death-reaction tests ===")
	_test_death_records_faction()
	_test_own_faction_mourns()
	_test_war_rival_cackles()
	_test_neutral_pays_respects()
	_test_faceless_obituary_generic()
	_test_unhinged_amplified()
	_test_per_notable_subject()
	_test_save_load_roundtrip()
	_test_non_notable_no_rumor()
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


func _spawn_notable(gs: GameState, faction: String, role: String = "war_chief") -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true,
		"mind": {"gov_role": role}})


func _death_rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "death":
			return r
	return {}


func _set_relation(gs: GameState, a: String, b: String, st: String) -> void:
	var rec: Dictionary = gs.diplomacy._pair(a, b)
	if not rec.is_empty():
		rec["state"] = st


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _test_death_records_faction() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var notable: Dictionary = _spawn_notable(gs, "ogres", "war_chief")
	var nid := int(notable.get("id", 0))
	gs.bus.unit_died.emit(nid, "ogres")
	var r: Dictionary = _death_rumor(hs)
	_check("death rumor seeded", not r.is_empty())
	_check("dead_faction recorded", String(r.get("dead_faction", "")) == "ogres")
	_check("rumor text names the faction",
		String(r.get("text", "")).find("Ogres") >= 0)
	_check("subject is per-notable",
		String(r.get("subject", "")) == "death:" + str(nid))


func _test_own_faction_mourns() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var notable: Dictionary = _spawn_notable(gs, "ogres", "spymaster")
	gs.bus.unit_died.emit(int(notable.get("id", 0)), "ogres")
	var r: Dictionary = _death_rumor(hs)
	var mourner: Dictionary = _spawn(gs, "ogres")
	var mid := int(mourner.get("id", 0))
	var mood_before: float = conv.ruler_mood(mid)
	hs._on_heard(mourner, r, {})
	_check("own faction mood drops on notable death",
		conv.ruler_mood(mid) < mood_before)
	_check("mourner remembers mourned_our_dead",
		_recalled(mourner, "mourned_our_dead", int(r.get("id", 0))) > 0.0)


func _test_war_rival_cackles() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var notable: Dictionary = _spawn_notable(gs, "ogres", "war_chief")
	gs.bus.unit_died.emit(int(notable.get("id", 0)), "ogres")
	var r: Dictionary = _death_rumor(hs)
	_set_relation(gs, "elves", "ogres", "war")
	var rival: Dictionary = _spawn(gs, "elves")
	var rid := int(rival.get("id", 0))
	var mood_before: float = conv.ruler_mood(rid)
	hs._on_heard(rival, r, {})
	_check("war rival mood RISES on enemy notable death",
		conv.ruler_mood(rid) > mood_before)
	_check("rival remembers rival_dead",
		_recalled(rival, "rival_dead", int(r.get("id", 0))) > 0.0)


func _test_neutral_pays_respects() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var notable: Dictionary = _spawn_notable(gs, "ogres", "war_chief")
	gs.bus.unit_died.emit(int(notable.get("id", 0)), "ogres")
	var r: Dictionary = _death_rumor(hs)
	var neutral: Dictionary = _spawn(gs, "gnomes")
	var nid2 := int(neutral.get("id", 0))
	var mood_before: float = conv.ruler_mood(nid2)
	hs._on_heard(neutral, r, {})
	_check("neutral pays respects (memory heard_dead_other)",
		_recalled(neutral, "heard_dead_other", int(r.get("id", 0))) > 0.0)
	_check("neutral mood dips only mildly",
		conv.ruler_mood(nid2) < mood_before)


func _test_faceless_obituary_generic() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# Facet-less obituary (old save / Gazette-seeded): no dead_faction.
	var r: Dictionary = hs.seed_rumor("A great hero has fallen.", "death",
		"oldobit", 0.7, -1, false, hs.TRUTH_UNKNOWN)
	_check("facet-less obituary seeded", not r.is_empty())
	var hearer: Dictionary = _spawn(gs, "elves")
	hs._on_heard(hearer, r, {})
	_check("facet-less obituary gets generic reception",
		_recalled(hearer, "heard_rumor", int(r.get("id", 0))) > 0.0)


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var notable: Dictionary = _spawn_notable(gs, "ogres", "war_chief")
	gs.bus.unit_died.emit(int(notable.get("id", 0)), "ogres")
	var r: Dictionary = _death_rumor(hs)
	var sane: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres", true)
	var sid := int(sane.get("id", 0))
	var wid := int(wild.get("id", 0))
	var sane_before: float = conv.ruler_mood(sid)
	var wild_before: float = conv.ruler_mood(wid)
	hs._on_heard(sane, r, {})
	hs._on_heard(wild, r, {})
	var sane_drop: float = sane_before - conv.ruler_mood(sid)
	var wild_drop: float = wild_before - conv.ruler_mood(wid)
	_check("sane mourner feels the loss", sane_drop > 0.0)
	_check("unhinged mourner grieves ~1.5x", wild_drop > sane_drop * 1.25)


func _test_per_notable_subject() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var n1: Dictionary = _spawn_notable(gs, "ogres", "war_chief")
	var n2: Dictionary = _spawn_notable(gs, "ogres", "spymaster")
	gs.bus.unit_died.emit(int(n1.get("id", 0)), "ogres")
	gs.bus.unit_died.emit(int(n2.get("id", 0)), "ogres")
	var count := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "death" \
				and String(r.get("subject", "")).begins_with("death:"):
			count += 1
	_check("two dead notables seed two rumors (no dedup collapse)", count == 2)
	# Same notable reported twice does NOT duplicate.
	gs.bus.unit_died.emit(int(n1.get("id", 0)), "ogres")
	var count2 := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("subject", "")) == "death:" + str(int(n1.get("id", 0))):
			count2 += 1
	_check("same notable re-reported does not duplicate", count2 == 1)


func _test_save_load_roundtrip() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var notable: Dictionary = _spawn_notable(gs, "elves", "archmage")
	gs.bus.unit_died.emit(int(notable.get("id", 0)), "elves")
	var saved: Dictionary = hs.to_dict()
	var h2: Array = _harness()
	var hs2 = h2[2]
	hs2.from_dict(saved)
	var found := false
	for r: Dictionary in hs2.state["rumors"]:
		if String(r.get("kind", "")) == "death" \
				and String(r.get("dead_faction", "")) == "elves":
			found = true
	_check("dead_faction survives save/load", found)


func _test_non_notable_no_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var grunt: Dictionary = _spawn(gs, "ogres")
	var before := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "death":
			before += 1
	gs.bus.unit_died.emit(int(grunt.get("id", 0)), "ogres")
	var after := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "death":
			after += 1
	_check("non-notable deaths still seed no obituary", after == before)
