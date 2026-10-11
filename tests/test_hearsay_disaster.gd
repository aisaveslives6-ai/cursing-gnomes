extends SceneTree
## Cursing Gnomes — hearsay disaster reaction tests
## (Jeremy 2026-10-07, hearsay flesh-out).
##
## Covers the disaster reaction matrix: disaster rumors record the
## STRICKEN TOWN (hit_faction/hit_town) so the realm reacts in character
## instead of a uniform shrug:
##  - the stricken faction panics (mood down, "disaster", "disaster_hit_us")
##  - war/hostile rivals laugh at the misery (mood up, "mocked",
##    "rival_disaster" — schadenfreude)
##  - everyone else grieves in sympathy (mood down a little, "helped",
##    "ally_disaster")
##  - wildfires name their town on the shared outbreak rumor
##  - disasters in the wilds (no town in range) stay generic
##  - unhinged NPCs feel it 1.5x (war/smear parity)
##  - a second disaster of the same kind refreshes the rumor and rewrites
##    the fields to name the NEWEST stricken town (conquest parity)
##  - save/load roundtrip: hit fields survive
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_disaster.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay disaster tests ===")
	_test_disaster_records_hit_town()
	_test_wilderness_disaster_generic()
	_test_victim_panics()
	_test_rival_schadenfreude()
	_test_ally_grieves()
	_test_unhinged_amplified()
	_test_wildfire_records_hit()
	_test_dedup_refresh_updates_hit()
	_test_save_load_roundtrip()
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


func _add_town(gs: GameState, tid: int, faction: String, pos: Vector2,
		name: String) -> void:
	gs.towns[tid] = {"id": tid, "faction": faction, "position": pos,
		"name": name}


func _set_relation(gs: GameState, a: String, b: String, st: String) -> void:
	var rec: Dictionary = gs.diplomacy._pair(a, b)
	if not rec.is_empty():
		rec["state"] = st


func _disaster_rumor(hs, subject: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "disaster" \
				and String(r.get("subject", "")) == subject:
			return r
	return {}


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


# Towns are far from the origin so spawned units (at 0,0) never
# auto-witness: reception is driven by explicit _on_heard calls.
func _test_disaster_records_hit_town() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	gs.bus.disaster_spawned.emit("volcano", Vector2(5100, 5050))
	var r: Dictionary = _disaster_rumor(hs, "volcano")
	_check("disaster rumor seeded", not r.is_empty())
	_check("hit_faction recorded",
		String(r.get("hit_faction", "")) == "ogres")
	_check("hit_town recorded",
		String(r.get("hit_town", "")) == "Gristleburg")
	_check("rumor text names the town",
		String(r.get("text", "")).find("Gristleburg") >= 0)


func _test_wilderness_disaster_generic() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	var u: Dictionary = _spawn(gs, "ogres")
	var uid := int(u.get("id", 0))
	# Deep wilds — no town within 700px.
	gs.bus.disaster_spawned.emit("volcano", Vector2(50000, 50000))
	var r: Dictionary = _disaster_rumor(hs, "volcano")
	_check("wilderness rumor has no hit_faction",
		String(r.get("hit_faction", "")) == "")
	var conv = phone.get("conversation")
	var mood_before: float = conv.ruler_mood(uid)
	hs._on_heard(u, r, {})
	_check("wilderness victim gets generic heard_rumor",
		_recalled(u, "heard_rumor", int(r.get("id", 0))) > 0.0)
	_check("wilderness victim gets no disaster_hit_us memory",
		_recalled(u, "disaster_hit_us", int(r.get("id", 0))) == 0.0)
	_check("generic path does not move ruler mood",
		is_equal_approx(conv.ruler_mood(uid), mood_before))


func _test_victim_panics() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	gs.bus.disaster_spawned.emit("volcano", Vector2(5100, 5050))
	var r: Dictionary = _disaster_rumor(hs, "volcano")
	var conv = phone.get("conversation")
	var mood_before: float = conv.ruler_mood(vid)
	hs._on_heard(victim, r, {})
	_check("victim mood drops", conv.ruler_mood(vid) < mood_before)
	_check("victim is scared", _emotion(victim) == "scared")
	_check("victim remembers disaster_hit_us",
		_recalled(victim, "disaster_hit_us", int(r.get("id", 0))) > 0.0)


func _test_rival_schadenfreude() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_set_relation(gs, "elves", "ogres", "war")
	var rival: Dictionary = _spawn(gs, "elves")
	var rid2 := int(rival.get("id", 0))
	gs.bus.disaster_spawned.emit("volcano", Vector2(5100, 5050))
	var r: Dictionary = _disaster_rumor(hs, "volcano")
	var conv = phone.get("conversation")
	var mood_before: float = conv.ruler_mood(rid2)
	hs._on_heard(rival, r, {})
	_check("rival mood rises (schadenfreude)",
		conv.ruler_mood(rid2) > mood_before)
	_check("rival sneers (mocked -> sad, proud -> angry)",
		_emotion(rival) == "sad" or _emotion(rival) == "angry")
	_check("rival remembers rival_disaster",
		_recalled(rival, "rival_disaster", int(r.get("id", 0))) > 0.0)


func _test_ally_grieves() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	var neutral: Dictionary = _spawn(gs, "gnomes")
	var nid := int(neutral.get("id", 0))
	gs.bus.disaster_spawned.emit("volcano", Vector2(5100, 5050))
	var r: Dictionary = _disaster_rumor(hs, "volcano")
	var conv = phone.get("conversation")
	var mood_before: float = conv.ruler_mood(nid)
	hs._on_heard(neutral, r, {})
	_check("neutral mood dips (sympathy)",
		conv.ruler_mood(nid) < mood_before)
	_check("neutral feels for them (helped -> happy)",
		_emotion(neutral) == "happy")
	_check("neutral remembers ally_disaster",
		_recalled(neutral, "ally_disaster", int(r.get("id", 0))) > 0.0)
	_check("neutral gets no victim memory",
		_recalled(neutral, "disaster_hit_us", int(r.get("id", 0))) == 0.0)


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	var calm: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres", true)
	var cid := int(calm.get("id", 0))
	var wid := int(wild.get("id", 0))
	gs.bus.disaster_spawned.emit("volcano", Vector2(5100, 5050))
	var r: Dictionary = _disaster_rumor(hs, "volcano")
	var conv = phone.get("conversation")
	var calm_before: float = conv.ruler_mood(cid)
	var wild_before: float = conv.ruler_mood(wid)
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	var calm_drop: float = calm_before - conv.ruler_mood(cid)
	var wild_drop: float = wild_before - conv.ruler_mood(wid)
	_check("unhinged victim panics harder (1.5x)",
		wild_drop > calm_drop * 1.2)


func _test_wildfire_records_hit() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "elves", Vector2(5000, 5000), "Leafholm")
	gs.bus.fire_started.emit({"position": Vector2(4950, 5050)})
	var r: Dictionary = _disaster_rumor(hs, "wildfire")
	_check("wildfire rumor seeded", not r.is_empty())
	_check("wildfire hit_faction recorded",
		String(r.get("hit_faction", "")) == "elves")
	_check("wildfire hit_town recorded",
		String(r.get("hit_town", "")) == "Leafholm")


func _test_dedup_refresh_updates_hit() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	_add_town(gs, 2, "elves", Vector2(9000, 9000), "Leafholm")
	gs.bus.disaster_spawned.emit("volcano", Vector2(5100, 5050))
	gs.bus.disaster_spawned.emit("volcano", Vector2(9050, 8950))
	var count := 0
	var r: Dictionary = {}
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("kind", "")) == "disaster" \
				and String(r2.get("subject", "")) == "volcano":
			count += 1
			r = r2
	_check("no duplicate rumor on refresh", count == 1)
	_check("hit fields follow the newest town",
		String(r.get("hit_faction", "")) == "elves" \
		and String(r.get("hit_town", "")) == "Leafholm")
	_check("text follows the newest town",
		String(r.get("text", "")).find("Leafholm") >= 0)


func _test_save_load_roundtrip() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_add_town(gs, 1, "ogres", Vector2(5000, 5000), "Gristleburg")
	gs.bus.disaster_spawned.emit("volcano", Vector2(5100, 5050))
	var data: Dictionary = hs.to_dict()
	# A fresh hearsay loads the saved state.
	var gs2 := _new_gs()
	var phone2 = load("res://scripts/sim/phone.gd").new(gs2)
	var hs2 = phone2.hearsay
	hs2.from_dict(data)
	var r: Dictionary = _disaster_rumor(hs2, "volcano")
	_check("hit fields survive load",
		String(r.get("hit_faction", "")) == "ogres" \
		and String(r.get("hit_town", "")) == "Gristleburg")
