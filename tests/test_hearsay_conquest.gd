extends SceneTree
## Cursing Gnomes — hearsay conquest/betrayal reaction tests
## (Jeremy 2026-10-07, hearsay flesh-out).
##
## Covers the conquest & betrayal reaction matrix: capture rumors record
## BOTH sides (holder_old/holder_new), so NPCs react in character instead
## of shrugging at dead-end news.
##  - monastery capture: the LOSING side feels shame/fury (mood down,
##    "attacked" — brave NPCs get angry via stands_ground parity — and a
##    "lost_post" memory); the TAKING side feels pride (mood up, "victory",
##    "took_post"); neutrals get the generic reception
##  - unhinged NPCs feel conquest news 1.5x (war/smear parity)
##  - unclaimed-post captures (no snapshot entry): generic, no crash
##  - crystal captures: same both-sides recording
##  - recapture of the same post: one rumor, text follows the newest taker
##  - different posts: different rumors (per-post subjects)
##  - town command-post captures via the bus signal: both sides recorded
##  - treaty broken: betrayed side outraged ("betrayed_by"), breaker side
##    defiant ("broke_treaty")
##  - tribute refused: refuser side defiant ("refused_tribute"), demander
##    side humiliated ("tribute_refused_us")
##  - building destroyed: owning faction mourns ("building_lost"), others
##    get the generic reception
##  - save/load roundtrip: holder fields + snapshot survive
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_conquest.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


class MockProposals:
	extends RefCounted
	var calls: Array = []
	func propose(faction: String, kind: String,
			details: Dictionary = {}) -> Dictionary:
		calls.append({"faction": faction, "kind": kind,
			"details": details})
		return {"ok": true, "id": calls.size()}


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay conquest/betrayal tests ===")
	_test_monastery_capture_records_both_sides()
	_test_loser_side_shame_and_fury()
	_test_taker_side_pride()
	_test_neutral_gets_generic()
	_test_unhinged_amplified()
	_test_unclaimed_capture_generic_no_crash()
	_test_crystal_capture_both_sides()
	_test_recapture_refreshes_text_and_sides()
	_test_different_posts_different_rumors()
	_test_town_post_capture()
	_test_treaty_broken_matrix()
	_test_tribute_refused_matrix()
	_test_building_destroyed_mourned()
	_test_conquest_no_scout_quest()
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


func _conquest_rumor(hs, subject: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("subject", "")) == subject:
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


func _seed_holders(hs, key: String, faction: String) -> void:
	# The bus signals don't carry the old holder; the snapshot does.
	var holders: Dictionary = hs.state.get("holders", {})
	holders[key] = faction
	hs.state["holders"] = holders


func _test_monastery_capture_records_both_sides() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_seed_holders(hs, "monastery:godx", "ogres")
	gs.bus.monastery_captured.emit("godx", "elves")
	var r: Dictionary = _conquest_rumor(hs, "monastery:godx")
	_check("monastery rumor seeded", not r.is_empty())
	_check("monastery holder_old recorded", String(r.get("holder_old", "")) == "ogres")
	_check("monastery holder_new recorded", String(r.get("holder_new", "")) == "elves")
	_check("monastery rumor is war-kind", String(r.get("kind", "")) == "war")


func _test_loser_side_shame_and_fury() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_seed_holders(hs, "monastery:godx", "ogres")
	var loser: Dictionary = _spawn(gs, "ogres")
	var lid := int(loser.get("id", 0))
	gs.bus.monastery_captured.emit("godx", "elves")
	var r: Dictionary = _conquest_rumor(hs, "monastery:godx")
	var mood_before: float = conv.ruler_mood(lid)
	hs._on_heard(loser, r, {})
	_check("loser mood drops on capture news", conv.ruler_mood(lid) < mood_before)
	_check("loser scared or angry (brave)", _emotion(loser) == "scared" \
		or _emotion(loser) == "angry")
	_check("loser remembers lost_post", _recalled(loser, "lost_post",
		int(r.get("id", 0))) > 0.0)


func _test_taker_side_pride() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_seed_holders(hs, "monastery:godx", "ogres")
	var taker: Dictionary = _spawn(gs, "elves")
	var tid := int(taker.get("id", 0))
	gs.bus.monastery_captured.emit("godx", "elves")
	var r: Dictionary = _conquest_rumor(hs, "monastery:godx")
	var mood_before: float = conv.ruler_mood(tid)
	hs._on_heard(taker, r, {})
	_check("taker mood rises on capture news", conv.ruler_mood(tid) > mood_before)
	_check("taker feels victory", _emotion(taker) == "victory" \
		or _emotion(taker) == "proud")
	_check("taker remembers took_post", _recalled(taker, "took_post",
		int(r.get("id", 0))) > 0.0)


func _test_neutral_gets_generic() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_seed_holders(hs, "monastery:godx", "ogres")
	var neutral: Dictionary = _spawn(gs, "gnomes")
	gs.bus.monastery_captured.emit("godx", "elves")
	var r: Dictionary = _conquest_rumor(hs, "monastery:godx")
	hs._on_heard(neutral, r, {})
	_check("neutral gets no lost_post memory", _recalled(neutral, "lost_post",
		int(r.get("id", 0))) == 0.0)
	_check("neutral gets no took_post memory", _recalled(neutral, "took_post",
		int(r.get("id", 0))) == 0.0)
	_check("neutral gets generic heard_rumor", _recalled(neutral, "heard_rumor",
		int(r.get("id", 0))) > 0.0)


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_seed_holders(hs, "monastery:godx", "ogres")
	var calm: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres", true)
	gs.bus.monastery_captured.emit("godx", "elves")
	var r: Dictionary = _conquest_rumor(hs, "monastery:godx")
	var calm_before: float = conv.ruler_mood(int(calm.get("id", 0)))
	var wild_before: float = conv.ruler_mood(int(wild.get("id", 0)))
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	var calm_drop: float = calm_before - conv.ruler_mood(int(calm.get("id", 0)))
	var wild_drop: float = wild_before - conv.ruler_mood(int(wild.get("id", 0)))
	_check("unhinged loser drops harder", wild_drop > calm_drop)


func _test_unclaimed_capture_generic_no_crash() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# No snapshot entry: a fresh unclaimed monastery falls to the elves.
	var npc: Dictionary = _spawn(gs, "ogres")
	gs.bus.monastery_captured.emit("freshgod", "elves")
	var r: Dictionary = _conquest_rumor(hs, "monastery:freshgod")
	_check("unclaimed capture seeded", not r.is_empty())
	_check("unclaimed capture has empty holder_old",
		String(r.get("holder_old", "x")) == "")
	hs._on_heard(npc, r, {})
	_check("unclaimed capture: generic path, no lost_post",
		_recalled(npc, "lost_post", int(r.get("id", 0))) == 0.0)


func _test_crystal_capture_both_sides() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_seed_holders(hs, "crystal:cry", "undead")
	gs.bus.crystal_captured.emit("cry", "humans")
	var r: Dictionary = _conquest_rumor(hs, "crystal:cry")
	_check("crystal rumor seeded", not r.is_empty())
	_check("crystal holder_old recorded", String(r.get("holder_old", "")) == "undead")
	_check("crystal holder_new recorded", String(r.get("holder_new", "")) == "humans")


func _test_recapture_refreshes_text_and_sides() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_seed_holders(hs, "monastery:godx", "ogres")
	gs.bus.monastery_captured.emit("godx", "elves")
	var count1 := 0
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("subject", "")) == "monastery:godx":
			count1 += 1
	gs.bus.monastery_captured.emit("godx", "ogres")  # elves lose it back
	var count2 := 0
	var r: Dictionary = {}
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("subject", "")) == "monastery:godx":
			count2 += 1
			r = r2
	_check("recapture does not duplicate", count1 == 1 and count2 == 1)
	_check("recapture text names the newest taker",
		String(r.get("text", "")).contains("Ogres"))
	_check("recapture holder_old updated", String(r.get("holder_old", "")) == "elves")
	_check("recapture holder_new updated", String(r.get("holder_new", "")) == "ogres")


func _test_different_posts_different_rumors() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_seed_holders(hs, "monastery:godx", "ogres")
	_seed_holders(hs, "monastery:gody", "elves")
	gs.bus.monastery_captured.emit("godx", "elves")
	gs.bus.monastery_captured.emit("gody", "ogres")
	_check("two posts seed two rumors",
		not _conquest_rumor(hs, "monastery:godx").is_empty() \
		and not _conquest_rumor(hs, "monastery:gody").is_empty())
	_check("per-post sides independent",
		String(_conquest_rumor(hs, "monastery:godx").get("holder_old", "")) == "ogres" \
		and String(_conquest_rumor(hs, "monastery:gody").get("holder_old", "")) == "elves")


func _test_town_post_capture() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var loser: Dictionary = _spawn(gs, "ogres")
	var lid := int(loser.get("id", 0))
	gs.bus.command_post_captured.emit("town", 7, "ogres", "elves", Vector2.ZERO)
	var r: Dictionary = _conquest_rumor(hs, "townpost:7")
	_check("town post rumor seeded", not r.is_empty())
	_check("town post sides recorded",
		String(r.get("holder_old", "")) == "ogres" \
		and String(r.get("holder_new", "")) == "elves")
	var mood_before: float = conv.ruler_mood(lid)
	hs._on_heard(loser, r, {})
	_check("town loser mood drops", conv.ruler_mood(lid) < mood_before)
	_check("town loser remembers lost_post", _recalled(loser, "lost_post",
		int(r.get("id", 0))) > 0.0)


func _test_treaty_broken_matrix() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var victim: Dictionary = _spawn(gs, "ogres")
	var breaker_npc: Dictionary = _spawn(gs, "elves")
	gs.bus.treaty_broken.emit("elves", "ogres")
	var r: Dictionary = {}
	for r2: Dictionary in hs.state["rumors"]:
		if r2.has("betrayer"):
			r = r2
	_check("treaty rumor records betrayer", String(r.get("betrayer", "")) == "elves")
	_check("treaty rumor records betrayed", String(r.get("betrayed", "")) == "ogres")
	var vm_before: float = conv.ruler_mood(int(victim.get("id", 0)))
	var bm_before: float = conv.ruler_mood(int(breaker_npc.get("id", 0)))
	hs._on_heard(victim, r, {})
	hs._on_heard(breaker_npc, r, {})
	_check("betrayed side mood drops", conv.ruler_mood(int(victim.get("id", 0))) < vm_before)
	_check("betrayed side remembers betrayed_by",
		_recalled(victim, "betrayed_by", int(r.get("id", 0))) > 0.0)
	_check("betrayed side outraged", _emotion(victim) == "insulted" \
		or _emotion(victim) == "angry")
	_check("breaker side defiant", conv.ruler_mood(int(breaker_npc.get("id", 0))) > bm_before)
	_check("breaker side remembers broke_treaty",
		_recalled(breaker_npc, "broke_treaty", int(r.get("id", 0))) > 0.0)


func _test_tribute_refused_matrix() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var refuser: Dictionary = _spawn(gs, "ogres")
	var demander: Dictionary = _spawn(gs, "elves")
	gs.bus.tribute_refused.emit("elves", "ogres")
	var r: Dictionary = {}
	for r2: Dictionary in hs.state["rumors"]:
		if r2.has("refuser"):
			r = r2
	_check("refusal records refuser", String(r.get("refuser", "")) == "ogres")
	_check("refusal records demander", String(r.get("demander", "")) == "elves")
	var rm_before: float = conv.ruler_mood(int(refuser.get("id", 0)))
	var dm_before: float = conv.ruler_mood(int(demander.get("id", 0)))
	hs._on_heard(refuser, r, {})
	hs._on_heard(demander, r, {})
	_check("refuser side defiant", conv.ruler_mood(int(refuser.get("id", 0))) > rm_before)
	_check("refuser remembers refused_tribute",
		_recalled(refuser, "refused_tribute", int(r.get("id", 0))) > 0.0)
	_check("demander side humiliated", conv.ruler_mood(int(demander.get("id", 0))) < dm_before)
	_check("demander remembers tribute_refused_us",
		_recalled(demander, "tribute_refused_us", int(r.get("id", 0))) > 0.0)


func _test_building_destroyed_mourned() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var owner_npc: Dictionary = _spawn(gs, "ogres")
	var outsider: Dictionary = _spawn(gs, "elves")
	gs.bus.building_destroyed.emit({"type": "barracks", "name": "War Hall",
		"faction": "ogres"})
	var r: Dictionary = {}
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("kind", "")) == "building" \
				and String(r2.get("subject", "")) == "barracks":
			r = r2
	_check("destroyed building records holder", String(r.get("lost_holder", "")) == "ogres")
	var om_before: float = conv.ruler_mood(int(owner_npc.get("id", 0)))
	hs._on_heard(owner_npc, r, {})
	hs._on_heard(outsider, r, {})
	_check("owner mourns the loss", conv.ruler_mood(int(owner_npc.get("id", 0))) < om_before)
	_check("owner remembers building_lost",
		_recalled(owner_npc, "building_lost", int(r.get("id", 0))) > 0.0)
	_check("outsider gets generic", _recalled(outsider, "building_lost",
		int(r.get("id", 0))) == 0.0)


func _test_conquest_no_scout_quest() -> void:
	# Conquest rumors are confirmed-true captures, not buildup talk —
	# the crown must not propose "scout the monastery:godx" missions.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var mp := MockProposals.new()
	gs.proposals = mp
	_seed_holders(hs, "monastery:godx", "ogres")
	gs.bus.monastery_captured.emit("godx", "elves")
	hs._quest_tick()
	_check("conquest rumor spawns no scout quest", mp.calls.is_empty())
	_check("conquest rumor not flagged quest_spawned",
		not bool(_conquest_rumor(hs, "monastery:godx").get(
			"quest_spawned", false)))


func _test_save_load_roundtrip() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_seed_holders(hs, "monastery:godx", "ogres")
	gs.bus.monastery_captured.emit("godx", "elves")
	gs.bus.treaty_broken.emit("elves", "ogres")
	var data: Dictionary = hs.to_dict()
	# A fresh hearsay loads the saved state.
	var gs2 := _new_gs()
	var phone2 = load("res://scripts/sim/phone.gd").new(gs2)
	var hs2 = phone2.hearsay
	hs2.from_dict(data)
	var r: Dictionary = _conquest_rumor(hs2, "monastery:godx")
	_check("conquest sides survive load",
		String(r.get("holder_old", "")) == "ogres" \
		and String(r.get("holder_new", "")) == "elves")
	_check("holder snapshot survives load",
		String((hs2.state.get("holders", {}) as Dictionary).get(
			"monastery:godx", "")) == "elves")
	var found_betrayal := false
	for r2: Dictionary in hs2.state["rumors"]:
		if String(r2.get("betrayer", "")) == "elves" \
				and String(r2.get("betrayed", "")) == "ogres":
			found_betrayal = true
	_check("betrayal sides survive load", found_betrayal)
