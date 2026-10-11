extends SceneTree
## Cursing Gnomes — hearsay peace-feeler tests (Jeremy 2026-10-09).
##
## Covers the hearsay flesh-out run: the strategic-proposal grapevine was
## half-dead in live play. bus.strategic_proposal only fires for the
## PLAYER's faction (proposals.gd emit is player-gated) while hearsay's
## handler ignores the player — so AI war plots and troop buildups never
## gossiped (the war-plot tests emitted the signal by hand). AI factions
## decide synchronously inside propose(), so the decided signal is the
## grapevine's only hook:
##   - approved major_buildup -> "mass troops" rumor (scout-quest eligible)
##   - denied sue_for_peace -> peace-feeler gossip (the beaten faction
##     debated begging and said no) with a full reaction matrix
##   - approved sue_for_peace -> NO feeler rumor (the surrender offer
##     lands the same tick via _on_surrender_offered — no double coverage)
##   - denied buildup / player-faction proposals -> silence
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_peace_feeler.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay peace-feeler tests ===")
	_test_propose_denied_feeler_seeds_via_live_wiring()
	_test_feeler_records_sides()
	_test_approved_feeler_stays_quiet()
	_test_expired_feeler_stays_quiet()
	_test_buildup_approved_seeds_mass_troops()
	_test_buildup_denied_silent()
	_test_player_proposal_ignored()
	_test_feeler_proud_shame()
	_test_feeler_hawk_defiant()
	_test_feeler_dove_despairs()
	_test_feeler_target_gloats()
	_test_feeler_rival_cackles()
	_test_feeler_ally_grieves()
	_test_feeler_unhinged_amplified()
	_test_feeler_spread_motivation()
	_test_feeler_cross_border()
	_test_feeler_save_roundtrip()
	_test_dismayed_event_registered()
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
	gs.set("proposals", load("res://scripts/sim/proposals.gd").new(gs))
	return [gs, phone, phone.hearsay, gs.get("proposals")]


func _spawn(gs: GameState, faction: String, mind: Dictionary = {}) -> Dictionary:
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


func _deny_feeler(gs: GameState, faction: String = "elves",
		target: String = "ogres") -> void:
	gs.bus.strategic_proposal_decided.emit({
		"id": 11, "faction": faction, "kind": "sue_for_peace",
		"details": {"target": target}, "day": 1, "status": "denied",
	}, false)


func _feeler(gs: GameState) -> Dictionary:
	var hs = gs.get("phone_sys").get("hearsay")
	return hs._live_rumor("war", "peacefeeler:elves")


func _test_propose_denied_feeler_seeds_via_live_wiring() -> void:
	# THE wiring regression test: a real SimProposals.propose() for an AI
	# faction (not at war -> _ai_peace_ok false -> denied) must gossip.
	# Before the fix, nothing downstream of propose() ever reached the
	# mill for AI factions.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var props = h[3]
	var res: Dictionary = props.propose("elves",
		load("res://scripts/sim/proposals.gd").KIND_SUE_FOR_PEACE,
		{"target": "ogres"})
	_check("ai peace proposal evaluated", bool(res.get("ok", false)))
	_check("ai denied the feeler (not at war)",
		String(res.get("status", "")) == "denied")
	var r: Dictionary = _feeler(gs)
	_check("denied peace feeler seeds rumor via live propose()",
		not r.is_empty())
	_check("feeler flags peace_feeler", bool(r.get("peace_feeler", false)))
	_check("feeler text names the begging",
		String(r.get("text", "")).contains("begging"))
	gs.queue_free()


func _test_feeler_records_sides() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	_deny_feeler(gs)
	var r: Dictionary = _feeler(gs)
	_check("feeler records beggars as side_a",
		String(r.get("side_a", "")) == "elves")
	_check("feeler records recipients as side_b",
		String(r.get("side_b", "")) == "ogres")
	_check("feeler heat 0.75",
		absf(float(r.get("heat", 0.0)) - 0.75) < 0.001)
	_check("feeler is confirmed gossip, not a scout lead",
		bool(r.get("quest_spawned", false)))
	gs.queue_free()


func _test_approved_feeler_stays_quiet() -> void:
	# An approved feeler needs no rumor: the surrender offer lands the
	# same tick via _on_surrender_offered. No double coverage.
	var h: Array = _harness()
	var gs: GameState = h[0]
	gs.bus.strategic_proposal_decided.emit({
		"id": 12, "faction": "elves", "kind": "sue_for_peace",
		"details": {"target": "ogres"}, "day": 1, "status": "approved",
	}, true)
	_check("approved feeler seeds no feeler rumor",
		_feeler(gs).is_empty())
	gs.queue_free()


func _test_expired_feeler_stays_quiet() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	gs.bus.strategic_proposal_decided.emit({
		"id": 13, "faction": "elves", "kind": "sue_for_peace",
		"details": {"target": "ogres"}, "day": 1, "status": "expired",
	}, false)
	_check("expired feeler seeds no rumor", _feeler(gs).is_empty())
	gs.queue_free()


func _test_buildup_approved_seeds_mass_troops() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	gs.bus.strategic_proposal_decided.emit({
		"id": 14, "faction": "elves", "kind": "major_buildup",
		"details": {}, "day": 1, "status": "approved",
	}, true)
	var r: Dictionary = hs._live_rumor("war", "elves")
	_check("approved buildup seeds mass-troops rumor", not r.is_empty())
	_check("buildup text names the buildup",
		String(r.get("text", "")).contains("massing troops"))
	_check("buildup heat 0.8 (scout-quest eligible)",
		absf(float(r.get("heat", 0.0)) - 0.8) < 0.001)
	_check("buildup truth unknown (tavern talk)",
		String(r.get("truth", "")) == "unknown")
	_check("buildup stays scout-eligible",
		not bool(r.get("quest_spawned", false)))
	gs.queue_free()


func _test_buildup_denied_silent() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	gs.bus.strategic_proposal_decided.emit({
		"id": 15, "faction": "elves", "kind": "major_buildup",
		"details": {}, "day": 1, "status": "denied",
	}, false)
	_check("denied buildup beats no drums",
		hs._live_rumor("war", "elves").is_empty())
	gs.queue_free()


func _test_player_proposal_ignored() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	gs.bus.strategic_proposal_decided.emit({
		"id": 16, "faction": "gnomes", "kind": "sue_for_peace",
		"details": {"target": "ogres"}, "day": 1, "status": "denied",
	}, false)
	gs.bus.strategic_proposal_decided.emit({
		"id": 17, "faction": "gnomes", "kind": "major_buildup",
		"details": {}, "day": 1, "status": "approved",
	}, true)
	_check("player feeler stays off the street",
		hs._live_rumor("war", "peacefeeler:gnomes").is_empty())
	_check("player buildup stays off the street",
		hs._live_rumor("war", "gnomes").is_empty())
	gs.queue_free()


func _test_feeler_proud_shame() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	var conv = h[1].get("conversation")
	_deny_feeler(gs)
	var r: Dictionary = _feeler(gs)
	var proud_elf: Dictionary = _spawn(gs, "elves",
		{"traits": {"persona": "proud"}})
	var before: float = conv.ruler_mood(int(proud_elf.get("id", 0)))
	hs._on_heard(proud_elf, r, {})
	_check("proud elf remembers the shame",
		_recalled(proud_elf, "peace_feeler_shame", int(r.get("id", 0))) > 0.0)
	_check("proud elf mood drops",
		conv.ruler_mood(int(proud_elf.get("id", 0))) < before)
	_check("proud elf furious (insulted -> angry)",
		_emotion(proud_elf) == "angry")
	gs.queue_free()


func _test_feeler_hawk_defiant() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	var conv = h[1].get("conversation")
	_deny_feeler(gs)
	var r: Dictionary = _feeler(gs)
	var hawk: Dictionary = _spawn(gs, "elves",
		{"traits": {"brave": 1.0, "proud": 0.0}})
	var before: float = conv.ruler_mood(int(hawk.get("id", 0)))
	hs._on_heard(hawk, r, {})
	_check("hawk remembers defiance",
		_recalled(hawk, "peace_feeler_defiant", int(r.get("id", 0))) > 0.0)
	_check("hawk mood rises (rather fight than beg)",
		conv.ruler_mood(int(hawk.get("id", 0))) > before)
	gs.queue_free()


func _test_feeler_dove_despairs() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	var conv = h[1].get("conversation")
	_deny_feeler(gs)
	var r: Dictionary = _feeler(gs)
	# Default traits: proud 0.5 (not stuffy), brave 0.5 (not hawk).
	var dove: Dictionary = _spawn(gs, "elves")
	var before: float = conv.ruler_mood(int(dove.get("id", 0)))
	hs._on_heard(dove, r, {})
	_check("dove remembers despair",
		_recalled(dove, "peace_feeler_despair", int(r.get("id", 0))) > 0.0)
	_check("dove mood drops",
		conv.ruler_mood(int(dove.get("id", 0))) < before)
	_check("dove saddened", _emotion(dove) == "sad")
	gs.queue_free()


func _test_feeler_target_gloats() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	var conv = h[1].get("conversation")
	_deny_feeler(gs)
	var r: Dictionary = _feeler(gs)
	var ogre: Dictionary = _spawn(gs, "ogres")
	var before: float = conv.ruler_mood(int(ogre.get("id", 0)))
	hs._on_heard(ogre, r, {})
	_check("target remembers gloating",
		_recalled(ogre, "peace_feeler_gloated", int(r.get("id", 0))) > 0.0)
	_check("target mood rises",
		conv.ruler_mood(int(ogre.get("id", 0))) > before)
	gs.queue_free()


func _test_feeler_rival_cackles() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	_deny_feeler(gs, "elves", "ogres")
	# Make undead a war-rival of the beggars.
	gs.diplomacy.declare_war("undead", "elves", "test")
	var r: Dictionary = _feeler(gs)
	var ghoul: Dictionary = _spawn(gs, "undead")
	hs._on_heard(ghoul, r, {})
	_check("rival remembers mocking",
		_recalled(ghoul, "peace_feeler_mocked", int(r.get("id", 0))) > 0.0)
	gs.queue_free()


func _test_feeler_ally_grieves() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	_deny_feeler(gs)
	var r: Dictionary = _feeler(gs)
	# Ally the humans with the beggars.
	gs.diplomacy.form_alliance("humans", "elves")
	var human: Dictionary = _spawn(gs, "humans")
	hs._on_heard(human, r, {})
	_check("ally remembers hearing",
		_recalled(human, "heard_peace_feeler", int(r.get("id", 0))) > 0.0)
	_check("ally saddened", _emotion(human) == "sad")
	gs.queue_free()


func _test_feeler_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	var conv = h[1].get("conversation")
	_deny_feeler(gs)
	var r: Dictionary = _feeler(gs)
	var sane: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres",
		{"traits": {"unhinged": 1.0}})
	var sane_before: float = conv.ruler_mood(int(sane.get("id", 0)))
	var wild_before: float = conv.ruler_mood(int(wild.get("id", 0)))
	hs._on_heard(sane, r, {})
	hs._on_heard(wild, r, {})
	var sane_gain: float = conv.ruler_mood(int(sane.get("id", 0))) - sane_before
	var wild_gain: float = conv.ruler_mood(int(wild.get("id", 0))) - wild_before
	_check("unhinged target gloats 1.5x harder", wild_gain > sane_gain)
	gs.queue_free()


func _test_feeler_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	_deny_feeler(gs)
	var r: Dictionary = _feeler(gs)
	var beggar: Dictionary = _spawn(gs, "elves")
	var recipient: Dictionary = _spawn(gs, "ogres")
	var m_beggar: Dictionary = hs._spread_motivation(beggar, r)
	var m_recip: Dictionary = hs._spread_motivation(recipient, r)
	_check("beggars bury their shame",
		int(m_beggar.get("cap_delta", 0)) == -1)
	_check("recipients gloat-spread",
		int(m_recip.get("cap_delta", 0)) == 1)
	gs.queue_free()


func _test_feeler_cross_border() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	_deny_feeler(gs)
	var r: Dictionary = _feeler(gs)
	var teller: Dictionary = _spawn(gs, "elves")
	var route: Dictionary = hs._cross_target(teller, r)
	_check("feeler routes to the would-be recipients",
		String(route.get("faction", "")) == "ogres")
	_check("feeler cross-border chance 0.4",
		absf(float(route.get("chance", 0.0)) - 0.4) < 0.001)
	gs.queue_free()


func _test_feeler_save_roundtrip() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = gs.get("phone_sys").get("hearsay")
	_deny_feeler(gs)
	var d: Dictionary = hs.to_dict()
	var hs2 = load("res://scripts/sim/hearsay.gd").new(gs)
	hs2.from_dict(d)
	var r2: Dictionary = hs2._live_rumor("war", "peacefeeler:elves")
	_check("peace feeler survives save/load", not r2.is_empty())
	_check("peace_feeler flag survives", bool(r2.get("peace_feeler", false)))
	_check("feeler sides survive",
		String(r2.get("side_a", "")) == "elves" \
		and String(r2.get("side_b", "")) == "ogres")
	gs.queue_free()


func _test_dismayed_event_registered() -> void:
	var emo = load("res://scripts/sim/emotion.gd")
	_check("dismayed event registered",
		emo.EVENT_MAP.has("dismayed"))
	_check("dismayed maps to sad",
		String(emo.EVENT_MAP["dismayed"].get("emotion", "")) == "sad")
