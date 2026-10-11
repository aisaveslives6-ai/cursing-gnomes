extends SceneTree
## Cursing Gnomes — player smear pipeline tests (Jeremy 2026-10-06).
##
## When the player trash-talks a third party in a DM ("Grak smells like
## ass"), it seeds a REAL rumor with the player as source. NPCs react
## based on how they feel about the TARGET: like -> enraged at the
## player, dislike -> amused (and warmer to the player), target hears ->
## furious. Leader targets use faction standing.
##
## JEREMY'S HARD LINE: IRL racial / anti-LGBTQ slurs are NEVER funny —
## they bypass the matrix entirely into universal condemnation.
## Also covers directive #2 (slur cascade escalation) and #3 (100+ roasts).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_player_smear.gd
##
## Exit code 0 = all passed, 1 = any failure.


const FACTIONS := ["humans", "ogres", "elves", "gnomes", "undead"]

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes player-smear tests ===")
	_test_third_party_insult_seeds_smear()
	_test_direct_insult_not_seeded()
	_test_like_target_enraged()
	_test_dislike_target_amused()
	_test_target_hears_furious()
	_test_leader_target_faction_reactions()
	_test_spread_carries_smear()
	_test_rant_dedups()
	_test_slur_never_funny()
	_test_slur_reply_path_condemns()
	_test_cascade_other_racial_slur()
	_test_cascade_anti_lgbtq_slur()
	_test_npc_trashtalk_no_cascade()
	_test_roast_pool_size()
	_test_roast_no_repeats()
	_test_roast_no_slurs()
	_test_roast_style_mapping()
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
	var farr: Array[String] = []
	farr.assign(FACTIONS)
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.set_ruler_name("ass")
	return gs


func _new_phone(gs: GameState):
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return phone


func _spawn(gs: GameState, faction: String, unit_name: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true,
		"name": unit_name, "mind": {}})


func _smears(hs) -> Array:
	var out: Array = []
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "smear":
			out.append(r)
	return out


func _mem_strength(gs: GameState, unit: Dictionary, mtype: String,
		subject_id: int) -> float:
	var mems: Array = unit.get("memories", [])
	var best := 0.0
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			best = maxf(best, float(m.get("strength", 0.0)))
	return best


## Find a hearer/target pair whose stance clears the threshold.
func _find_pair(gs: GameState, hearer_faction: String,
		target_faction: String, want_high: bool) -> Array:
	var hearers: Array = []
	var targets: Array = []
	for i in range(12):
		hearers.append(_spawn(gs, hearer_faction, "H%d" % i))
		targets.append(_spawn(gs, target_faction, "T%d" % i))
	for h in hearers:
		for t in targets:
			var s: float = SimLikesDislikes.npc_stance(h,
				{"id": int(t.get("id", 0)),
					"faction": target_faction, "name": "Tx",
					"is_leader": false}, gs)
			if want_high and s >= 0.3:
				return [h, t]
			if not want_high and s <= -0.3:
				return [h, t]
	return []


# --- Smear pipeline -------------------------------------------------


func _test_third_party_insult_seeds_smear() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var grak := _spawn(gs, "ogres", "Grak")
	var mira := _spawn(gs, "gnomes", "Mira")
	var res: Dictionary = phone.conversation.reply(mira,
		"Grak smells like ass", gs)
	_check("smear: reply produced", String(res.get("text", "")) != "")
	var found := false
	var first_knower := false
	for r in _smears(hs):
		if String(r.get("target_name", "")) == "Grak":
			found = true
			first_knower = int(mira.get("id", 0)) in (r["knowers"] as Array)
	_check("smear: rumor seeded for named target", found)
	_check("smear: conversation partner is first knower", first_knower)
	gs.queue_free()


func _test_direct_insult_not_seeded() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	_spawn(gs, "ogres", "Grak")
	var mira := _spawn(gs, "gnomes", "Mira")
	phone.conversation.reply(mira, "you are an idiot", gs)
	_check("smear: direct insult seeds no rumor", _smears(hs).is_empty())
	gs.queue_free()


func _test_like_target_enraged() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	# Same faction: loyalty (+0.4) usually clears the defend threshold.
	var pair := _find_pair(gs, "ogres", "ogres", true)
	_check("smear: found like-pair", not pair.is_empty())
	if pair.is_empty():
		gs.queue_free()
		return
	var hearer: Dictionary = pair[0]
	var target: Dictionary = pair[1]
	var tid := int(target.get("id", 0))
	var hid := int(hearer.get("id", 0))
	var before: float = phone.conversation.ruler_mood(hid)
	var r: Dictionary = hs.seed_player_smear(
		{"name": "Tx", "id": tid, "faction": "ogres", "is_leader": false,
			"key": "npc:%d" % tid, "insult": "idiot",
			"phrase": "is an idiot"}, "Tx is an idiot", "idiot", hid)
	hs._smear_reaction(hearer, r)
	_check("smear: defender mood drops",
		phone.conversation.ruler_mood(hid) < before)
	_check("smear: defender memory written",
		_mem_strength(gs, hearer, "player_smeared_friend", tid) > 0.0)
	gs.queue_free()


func _test_dislike_target_amused() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var pair := _find_pair(gs, "elves", "ogres", false)
	_check("smear: found dislike-pair", not pair.is_empty())
	if pair.is_empty():
		gs.queue_free()
		return
	var hearer: Dictionary = pair[0]
	var target: Dictionary = pair[1]
	var tid := int(target.get("id", 0))
	var hid := int(hearer.get("id", 0))
	var mood_before: float = phone.conversation.ruler_mood(hid)
	var ckey := SimChatxCitizen.key_for(hid)
	var aff_before: float = phone.conversation.chatx_cit.aff(ckey)
	var r: Dictionary = hs.seed_player_smear(
		{"name": "Tx", "id": tid, "faction": "ogres", "is_leader": false,
			"key": "npc:%d" % tid, "insult": "idiot",
			"phrase": "is an idiot"}, "Tx is an idiot", "idiot", hid)
	hs._smear_reaction(hearer, r)
	_check("smear: amused mood rises",
		phone.conversation.ruler_mood(hid) > mood_before)
	_check("smear: amused affection rises",
		phone.conversation.chatx_cit.aff(ckey) > aff_before)
	_check("smear: amused memory written",
		_mem_strength(gs, hearer, "player_roasted_enemy", tid) > 0.0)
	gs.queue_free()


func _test_target_hears_furious() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var target := _spawn(gs, "ogres", "Grak")
	var hearer := _spawn(gs, "gnomes", "Mira")
	var tid := int(target.get("id", 0))
	var hid := int(hearer.get("id", 0))
	var r: Dictionary = hs.seed_player_smear(
		{"name": "Grak", "id": tid, "faction": "ogres", "is_leader": false,
			"key": "npc:%d" % tid, "insult": "ass",
			"phrase": "smells like ass"}, "Grak smells like ass", "ass",
		hid)
	hs._smear_reaction(target, r)
	_check("smear: target furious (mood <= -25)",
		phone.conversation.ruler_mood(tid) <= -25.0)
	_check("smear: target memory written",
		_mem_strength(gs, target, "player_smeared_me", tid) > 0.0)
	gs.queue_free()


func _test_leader_target_faction_reactions() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var hearer := _spawn(gs, "ogres", "Grom")
	var hid := int(hearer.get("id", 0))
	# Find an ogre hearer whose stance toward their own leader defends.
	var stance: float = SimLikesDislikes.npc_stance(hearer,
		{"id": 0, "faction": "ogres", "name": "Warlord",
			"is_leader": true}, gs)
	if stance < 0.3:
		# Spawn more until one defends (loyalty + leader bump ≈ P0.9).
		for i in range(10):
			var h2 := _spawn(gs, "ogres", "G%d" % i)
			var s2: float = SimLikesDislikes.npc_stance(h2,
				{"id": 0, "faction": "ogres", "name": "Warlord",
					"is_leader": true}, gs)
			if s2 >= 0.3:
				hearer = h2
				hid = int(h2.get("id", 0))
				break
	var before: float = phone.conversation.ruler_mood(hid)
	var r: Dictionary = hs.seed_player_smear(
		{"name": "Warlord Grak", "id": 0, "faction": "ogres",
			"is_leader": true, "key": "leader:ogres", "insult": "coward",
			"phrase": "is a coward"}, "Warlord Grak is a coward",
		"coward", hid)
	_check("smear: leader rumor flagged", bool(r.get("target_is_leader", false)))
	hs._smear_reaction(hearer, r)
	_check("smear: leader's own faction defends (mood drops)",
		phone.conversation.ruler_mood(hid) < before)
	gs.queue_free()


func _test_spread_carries_smear() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var target := _spawn(gs, "ogres", "Grak")
	var hearer := _spawn(gs, "gnomes", "Mira")
	for i in range(20):
		_spawn(gs, "gnomes", "C%d" % i)
	var r: Dictionary = hs.seed_player_smear(
		{"name": "Grak", "id": int(target.get("id", 0)), "faction": "ogres",
			"is_leader": false,
			"key": "npc:%d" % int(target.get("id", 0)), "insult": "ass",
			"phrase": "smells like ass"}, "Grak smells like ass", "ass",
		int(hearer.get("id", 0)))
	seed(1234)
	hs._spread(r)
	_check("smear: spread reaches new knowers",
		(r["knowers"] as Array).size() > 1)
	_check("smear: still kind smear after spread",
		String(r.get("kind", "")) == "smear")
	gs.queue_free()


func _test_rant_dedups() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var target := _spawn(gs, "ogres", "Grak")
	var hearer := _spawn(gs, "gnomes", "Mira")
	var td := {"name": "Grak", "id": int(target.get("id", 0)),
		"faction": "ogres", "is_leader": false,
		"key": "npc:%d" % int(target.get("id", 0)), "insult": "ass",
		"phrase": "smells like ass"}
	hs.seed_player_smear(td, "Grak smells like ass", "ass",
		int(hearer.get("id", 0)))
	hs.seed_player_smear(td, "Grak smells like ass", "ass",
		int(hearer.get("id", 0)))
	hs.seed_player_smear(td, "Grak smells like ass", "ass",
		int(hearer.get("id", 0)))
	_check("smear: rant dedups to one rumor", _smears(hs).size() == 1)
	gs.queue_free()


# --- Hard guardrail: slurs are NEVER funny ---------------------------


func _test_slur_never_funny() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	# Hearer HATES the target (at war) — would laugh at a normal smear.
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var pair := _find_pair(gs, "elves", "ogres", false)
	_check("guardrail: found dislike-pair", not pair.is_empty())
	if pair.is_empty():
		gs.queue_free()
		return
	var hearer: Dictionary = pair[0]
	var target: Dictionary = pair[1]
	var tid := int(target.get("id", 0))
	var hid := int(hearer.get("id", 0))
	var mood_before: float = phone.conversation.ruler_mood(hid)
	var ckey := SimChatxCitizen.key_for(hid)
	var aff_before: float = phone.conversation.chatx_cit.aff(ckey)
	var fired := [false]
	gs.bus.slur_incident.connect(func(_a, _b, _c, _d): fired[0] = true)
	var r: Dictionary = hs.seed_player_smear(
		{"name": "Tx", "id": tid, "faction": "ogres", "is_leader": false,
			"key": "npc:%d" % tid, "insult": "slur",
			"phrase": "was slurred by the crown"},
		"Tx is a kike", "kike", hid)
	_check("guardrail: slur seeds no smear", r.is_empty())
	_check("guardrail: no smear rumor exists", _smears(hs).is_empty())
	_check("guardrail: slur_incident fired", fired[0])
	_check("guardrail: no mood gain (never amused)",
		phone.conversation.ruler_mood(hid) <= mood_before)
	_check("guardrail: no affection gain",
		phone.conversation.chatx_cit.aff(ckey) <= aff_before)
	_check("guardrail: condemnation rumor seeded",
		_has_kind(hs, "slur"))
	gs.queue_free()


func _has_kind(hs, kind: String) -> bool:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == kind:
			return true
	return false


func _test_slur_reply_path_condemns() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var grak := _spawn(gs, "ogres", "Grak")
	var mira := _spawn(gs, "gnomes", "Mira")
	var hid := int(mira.get("id", 0))
	var mood_before: float = phone.conversation.ruler_mood(hid)
	# Direct reply path (bypasses phone.gd's DM check) — the guardrail
	# must still route to condemnation, never amusement.
	phone.conversation.reply(mira, "Grak is a faggot", gs)
	_check("guardrail: reply path seeds no smear", _smears(hs).is_empty())
	_check("guardrail: reply path condemns", _has_kind(hs, "slur"))
	_check("guardrail: reply path, no mood gain",
		phone.conversation.ruler_mood(hid) <= mood_before)
	_check("guardrail: reply path, no amused memory",
		_mem_strength(gs, mira, "player_roasted_enemy",
			int(grak.get("id", 0))) <= 0.0)
	gs.queue_free()


# --- Directive #2: slur cascade escalation ---------------------------


func _cascade_gs():
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var farr: Array[String] = []
	farr.assign(FACTIONS)
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.ruler_name = "TestRuler"
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	phone._court = load("res://scripts/sim/royal_court.gd").new(gs)
	var ids := {}
	for f in FACTIONS:
		ids[f] = []
		for i in range(2):
			var u: Dictionary = gs.add_unit(
				{"faction": f, "alive": true, "mind": {"persona": "blunt"}})
			(ids[f] as Array).append(int(u["id"]))
	return [gs, phone, ids]


func _has_headline(phone) -> bool:
	for s in phone._court.stories:
		if String(s.get("headline", "")) == SimRacistOutrage.HEADLINE:
			return true
	return false


func _has_scandal_rumor(phone) -> bool:
	for r in phone.hearsay.state["rumors"]:
		if "racist rant" in String(r.get("text", "")).to_lower():
			return true
	return false


func _dm_count(phone, ids: Dictionary, target_id: int) -> int:
	var n := 0
	for f in FACTIONS:
		for uid in (ids[f] as Array):
			if uid == target_id:
				continue
			var th: Dictionary = phone.state["threads"].get("u%d" % uid, {})
			if int(th.get("unread", 0)) > 0:
				n += 1
	return n


func _test_cascade_other_racial_slur() -> void:
	var parts: Array = _cascade_gs()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var ids: Dictionary = parts[2]
	var target_id: int = (ids["humans"] as Array)[0]
	phone.send_message(target_id, "you are a kike")
	for f in FACTIONS:
		if f == "gnomes":
			continue
		_check("cascade: racial slur → %s at war" % f,
			gs.diplomacy.relation_state(f, "gnomes") == "war")
	_check("cascade: racial slur → gazette scandal", _has_headline(phone))
	_check("cascade: racial slur → hearsay scandal", _has_scandal_rumor(phone))
	gs.game_time += 10.0
	phone.tick(0.0)
	_check("cascade: racial slur → furious DMs sent",
		_dm_count(phone, ids, target_id) >= 4)


func _test_cascade_anti_lgbtq_slur() -> void:
	var parts: Array = _cascade_gs()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var ids: Dictionary = parts[2]
	var target_id: int = (ids["humans"] as Array)[0]
	phone.send_message(target_id, "you are a faggot")
	for f in FACTIONS:
		if f == "gnomes":
			continue
		_check("cascade: anti-lgbtq slur → %s at war" % f,
			gs.diplomacy.relation_state(f, "gnomes") == "war")
	_check("cascade: anti-lgbtq slur → gazette scandal", _has_headline(phone))
	_check("cascade: anti-lgbtq slur → hearsay scandal",
		_has_scandal_rumor(phone))
	gs.game_time += 10.0
	phone.tick(0.0)
	_check("cascade: anti-lgbtq slur → furious DMs sent",
		_dm_count(phone, ids, target_id) >= 4)


func _test_npc_trashtalk_no_cascade() -> void:
	# NPC war trash-talk uses other-tier slurs with NO cascade — the gate
	# is player-text-only. Simulate the NPC gossip path directly.
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	for i in range(6):
		_spawn(gs, "ogres", "O%d" % i)
		_spawn(gs, "elves", "E%d" % i)
	var before: String = gs.diplomacy.relation_state("ogres", "elves")
	_check("trashtalk: other-tier slur detected (informational)",
		SimHateSpeech.is_racist("those chinks"))
	hs.seed_rumor("An ogre called the elves chinks. Tasteless.", "slur",
		"ogres", 0.9)
	seed(7)
	hs.daily_tick()
	_check("trashtalk: NPC slur gossip triggers no war",
		gs.diplomacy.relation_state("ogres", "elves") == before)
	gs.queue_free()


# --- Directive #3: 100+ roasts ---------------------------------------


func _test_roast_pool_size() -> void:
	var total := 0
	var seen := {}
	for style in SimRacistOutrage.LINES:
		var pool: Array = SimRacistOutrage.LINES[style]
		_check("roast: style %s has >= 25 lines (got %d)" % [style, pool.size()],
			pool.size() >= 25)
		for line in pool:
			total += 1
			seen[String(line)] = true
	_check("roast: total >= 100 (got %d)" % total, total >= 100)
	_check("roast: all lines distinct", seen.size() == total)


func _test_roast_no_repeats() -> void:
	SimRacistOutrage._used.clear()
	seed(12345)
	var unit := {"id": 4242, "faction": "ogres",
		"mind": {"persona": "grizzled"}}
	var style := "furious"  # grizzled -> furious
	var pool: Array = SimRacistOutrage.LINES[style]
	var got := {}
	for i in range(pool.size()):
		var line := SimRacistOutrage.outrage_reply_for(unit, "ass")
		_check("roast: no repeat within cycle (draw %d)" % i,
			not got.has(line))
		got[line] = true
	# Pool exhausted -> reshuffle: next line repeats an earlier one.
	var again := SimRacistOutrage.outrage_reply_for(unit, "ass")
	_check("roast: reshuffles after exhaustion", got.has(again))
	_check("roast: {ruler} substituted", not "{ruler}" in again)
	_check("roast: ruler name roasted in", "ass" in again)


func _test_roast_no_slurs() -> void:
	var pats: Array = []
	pats.append_array(HateTerms.HARD_R_PATTERNS)
	pats.append_array(HateTerms.OTHER_PATTERNS)
	pats.append_array(HateTerms.ANTI_LGBTQ_PATTERNS)
	var rx := RegEx.new()
	_check("roast: hate patterns compile",
		rx.compile("(?i)(?:" + "|".join(PackedStringArray(pats)) + ")") == OK)
	var bad := 0
	for style in SimRacistOutrage.LINES:
		for line in (SimRacistOutrage.LINES[style] as Array):
			if rx.search(String(line)) != null:
				bad += 1
				print("  SLUR MATCH: ", line)
	_check("roast: zero lines match any hate-term pattern", bad == 0)


func _test_roast_style_mapping() -> void:
	var expect := {
		"proud": "furious", "grizzled": "furious", "blunt": "furious",
		"honorable": "disgusted", "earnest": "disgusted",
		"haughty": "disgusted", "loyal": "disappointed",
		"worried": "disappointed", "pragmatic": "disappointed",
		"scheming": "cold", "oily": "cold", "jolly": "cold",
	}
	for persona in expect:
		var got: String = SimRacistOutrage.STYLE_FOR_PERSONA.get(persona, "")
		_check("roast: persona %s -> %s" % [persona, expect[persona]],
			got == String(expect[persona]))
	# dm_line_for works for every style too.
	for persona in expect:
		var unit := {"id": 99, "faction": "humans",
			"mind": {"persona": persona}}
		var line := SimRacistOutrage.dm_line_for(unit, "ass")
		_check("roast: dm_line_for %s" % persona,
			line != "" and not "{ruler}" in line)
