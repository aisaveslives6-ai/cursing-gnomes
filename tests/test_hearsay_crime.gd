extends SceneTree
## Cursing Gnomes — hearsay crime-rumor tests (Jeremy 2026-10-08).
##
## Covers the hearsay flesh-out run: crimes were a deaf thread — the
## Gazette blotted them with no parties, so victims, thieves, and
## townsfolk all shrugged through the generic path. Now the crime
## systems emit bus.crime_committed with the parties BEFORE the Gazette
## story publishes, and the mill seeds a NAMED crime rumor:
##  - the victim is outraged (grudge aimed at the crook)
##  - the named thief is caught out (unhinged ones brag)
##  - the town feels unsafe, rivals mock the thief, friends are shamed
##  - the thief's reputation bleeds with every hearer (capped)
##  - an UNSEEN thief (live-path spot check failed) still outrages the
##    victim but can't be named, mocked, or shamed
##  - name-and-shame spread: victims/rivals push, friends bury
##  - the Gazette story dedups against the rich rumor (no double seed)
##  - stories with no rich counterpart still seed the generic blotter
##  - investigators confirm named crimes ("THIEF! I SAW THE WHOLE
##    THING!" — HTML parity) and unseen ones honestly
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_crime.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay crime-rumor tests ===")
	_test_signal_seeds_named_rumor()
	_test_victim_outraged()
	_test_crook_caught_out()
	_test_unhinged_crook_brags()
	_test_unseen_thief()
	_test_townsfolk_uneasy()
	_test_rival_mocks_thief()
	_test_friend_shamed()
	_test_spread_motivation()
	_test_rep_bleeds()
	_test_story_dedup()
	_test_story_fallback_generic()
	_test_investigation_named()
	_test_investigation_unseen()
	_test_repeat_offender()
	_test_truth_true()
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


## True when the answer text came from the given line pool (pool lines
## are picked by RNG, so match on the line's distinctive core text).
func _pool_hit(text: String, pool: Array) -> bool:
	for line: Variant in pool:
		var core := String(line).replace("{t}", "").strip_edges()
		if core != "" and text.contains(core):
			return true
	return false


## Emit a real bus.crime_committed (the crime.gd payload shape).
func _commit_crime(gs: GameState, kind: String, crook_id: int,
		victim_id: int, town: String, loot: int,
		headline: String) -> void:
	gs.bus.crime_committed.emit(kind, crook_id, victim_id, town, loot,
		headline)


func _crime_rumor(hs, headline: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "crime" \
				and String(r.get("text", "")) == headline:
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


func _test_signal_seeds_named_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var crook: Dictionary = _spawn(gs, "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	var cid := int(crook.get("id", 0))
	var vid := int(victim.get("id", 0))
	_commit_crime(gs, "pickpocket", cid, vid, "Oakhollow", 25,
		"PICKPOCKET STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "PICKPOCKET STRIKES OAKHOLLOW!")
	_check("signal seeds a crime rumor", not r.is_empty())
	_check("crook recorded", int(r.get("crook_id", 0)) == cid)
	_check("victim recorded", int(r.get("victim_id", 0)) == vid)
	_check("town recorded", String(r.get("town_name", "")) == "Oakhollow")
	_check("loot recorded", int(r.get("loot", 0)) == 25)
	_check("crime kind recorded", String(r.get("crime_kind", "")) == "pickpocket")
	_check("victim heard it first (knower)", (r.get("knowers", []) as Array).has(vid))
	_check("crook knows the town is talking", (r.get("knowers", []) as Array).has(cid))


func _test_victim_outraged() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var crook: Dictionary = _spawn(gs, "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	var cid := int(crook.get("id", 0))
	var vid := int(victim.get("id", 0))
	_commit_crime(gs, "mugging", cid, vid, "Oakhollow", 0,
		"MUGGING ON OAKHOLLOW STREETS!")
	var r: Dictionary = _crime_rumor(hs, "MUGGING ON OAKHOLLOW STREETS!")
	_check("mugging rumor exists", not r.is_empty())
	_check("mugging is hot (0.8)", absf(float(r.get("heat", 0.0)) - 0.8) < 0.01)
	_check("victim remembers crime_victim aimed at crook",
		_recalled(victim, "crime_victim", cid) > 0.0)
	_check("victim outraged (insulted -> angry)", _emotion(victim) == "angry")
	_check("victim mood drops hard", conv.ruler_mood(vid) <= -10.0)


func _test_crook_caught_out() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# A meek crook (brave 0.0) cowers; a brave one stands defiant.
	var crook: Dictionary = gs.add_unit({"faction": "ogres", "alive": true,
		"mind": {"traits": {"brave": 0.0}}})
	var victim: Dictionary = _spawn(gs, "ogres")
	var cid := int(crook.get("id", 0))
	_commit_crime(gs, "burglary", cid, int(victim.get("id", 0)),
		"Oakhollow", 40, "BURGLAR STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "BURGLAR STRIKES OAKHOLLOW!")
	_check("burglary heat 0.7", absf(float(r.get("heat", 0.0)) - 0.7) < 0.01)
	_check("crook remembers crime_caught_out",
		_recalled(crook, "crime_caught_out", int(r.get("id", 0))) > 0.0)
	_check("meek crook scared (attacked -> scared)", _emotion(crook) == "scared")
	var brave: Dictionary = _spawn(gs, "ogres")
	var v2: Dictionary = _spawn(gs, "ogres")
	_commit_crime(gs, "burglary", int(brave.get("id", 0)),
		int(v2.get("id", 0)), "Oakhollow", 40, "BURGLAR STRIKES TWICE!")
	# Ogres spawn brave — defiance, not cowering (stands_ground parity).
	_check("brave crook defiant (attacked -> angry)", _emotion(brave) == "angry")


func _test_unhinged_crook_brags() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var crook: Dictionary = _spawn(gs, "ogres", true)
	var victim: Dictionary = _spawn(gs, "ogres")
	_commit_crime(gs, "pickpocket", int(crook.get("id", 0)),
		int(victim.get("id", 0)), "Oakhollow", 15,
		"PICKPOCKET STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "PICKPOCKET STRIKES OAKHOLLOW!")
	_check("unhinged crook remembers crime_bragged",
		_recalled(crook, "crime_bragged", int(r.get("id", 0))) > 0.0)
	_check("unhinged crook amused (liked_topic -> happy)",
		_emotion(crook) == "happy")


func _test_unseen_thief() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_commit_crime(gs, "pickpocket", 0, vid, "Oakhollow", 20,
		"PICKPOCKET STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "PICKPOCKET STRIKES OAKHOLLOW!")
	_check("unseen-thief rumor seeds", not r.is_empty())
	_check("no crook recorded", int(r.get("crook_id", 0)) == 0)
	_check("crook named as unseen", String(r.get("crook_name", "")) == "an unseen thief")
	_check("victim still outraged", _emotion(victim) == "angry")
	_check("victim remembers crime_victim (unseen)",
		_recalled(victim, "crime_victim", int(r.get("id", 0))) > 0.0)
	_check("unseen thief dodges the rep dock",
		absf(hs.reputation_of(999999) - 50.0) < 0.01)
	var kin: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(kin, r, {})
	_check("victim's folk uneasy (heard_crime)",
		_recalled(kin, "heard_crime", int(r.get("id", 0))) > 0.0)
	_check("folk mood dips", conv.ruler_mood(int(kin.get("id", 0))) < 0.0)


func _test_townsfolk_uneasy() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var crook: Dictionary = _spawn(gs, "ogres")
	var victim: Dictionary = _spawn(gs, "elves")
	_commit_crime(gs, "vandalism", int(crook.get("id", 0)),
		int(victim.get("id", 0)), "Oakhollow", 0,
		"VANDALS SMASH MARKET STALL!")
	var r: Dictionary = _crime_rumor(hs, "VANDALS SMASH MARKET STALL!")
	_check("vandalism heat 0.6", absf(float(r.get("heat", 0.0)) - 0.6) < 0.01)
	var kin: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(kin, r, {})
	_check("crook's townsfolk uneasy (heard_crime)",
		_recalled(kin, "heard_crime", int(crook.get("id", 0))) > 0.0)
	_check("townsfolk mood dips", conv.ruler_mood(int(kin.get("id", 0))) < 0.0)


func _test_rival_mocks_thief() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	gs.bus.war_declared.emit("elves", "ogres")
	var crook: Dictionary = _spawn(gs, "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	var cid := int(crook.get("id", 0))
	_commit_crime(gs, "pickpocket", cid, int(victim.get("id", 0)),
		"Oakhollow", 10, "PICKPOCKET STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "PICKPOCKET STRIKES OAKHOLLOW!")
	var likes = load("res://scripts/sim/likes_dislikes.gd")
	var rival: Dictionary = _find_stance(gs, crook, "elves", -1.0, -0.3)
	_check("rival found", not rival.is_empty())
	if rival.is_empty():
		return
	hs._on_heard(rival, r, {})
	_check("rival remembers mocked_thief",
		_recalled(rival, "mocked_thief", cid) > 0.0)
	_check("rival amused (liked_topic -> happy)", _emotion(rival) == "happy")
	_check("rival mood rises", conv.ruler_mood(int(rival.get("id", 0))) > 0.0)


func _test_friend_shamed() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var crook: Dictionary = _spawn(gs, "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	var cid := int(crook.get("id", 0))
	_commit_crime(gs, "pickpocket", cid, int(victim.get("id", 0)),
		"Oakhollow", 10, "PICKPOCKET STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "PICKPOCKET STRIKES OAKHOLLOW!")
	var friend: Dictionary = _find_stance(gs, crook, "elves", 0.3, 1.0)
	_check("friend found", not friend.is_empty())
	if friend.is_empty():
		return
	hs._on_heard(friend, r, {})
	_check("friend remembers crook_friend_shame",
		_recalled(friend, "crook_friend_shame", cid) > 0.0)
	_check("friend disappointed (insulted -> angry)", _emotion(friend) == "angry")
	_check("friend mood drops", conv.ruler_mood(int(friend.get("id", 0))) < 0.0)


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var crook: Dictionary = _spawn(gs, "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	var cid := int(crook.get("id", 0))
	var vid := int(victim.get("id", 0))
	_commit_crime(gs, "pickpocket", cid, vid, "Oakhollow", 10,
		"PICKPOCKET STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "PICKPOCKET STRIKES OAKHOLLOW!")
	# Find the neutral BEFORE war_declared (war shifts cross-faction
	# stance for everyone).
	var neutral: Dictionary = _find_stance(gs, crook, "gnomes", -0.29, 0.29)
	_check("neutral found", not neutral.is_empty())
	if not neutral.is_empty():
		var mv4 = hs._spread_motivation(neutral, r)
		_check("neutral tells it straight", int(mv4.get("cap_delta", 0)) == 0)
	gs.bus.war_declared.emit("elves", "ogres")
	var mv = hs._spread_motivation(victim, r)
	_check("victim pushes the name-and-shame",
		int(mv.get("cap_delta", 0)) == 1)
	var rival: Dictionary = _find_stance(gs, crook, "elves", -1.0, -0.3)
	if not rival.is_empty():
		var mv2 = hs._spread_motivation(rival, r)
		_check("rival pushes it gleefully", int(mv2.get("cap_delta", 0)) == 1)
	var friend: Dictionary = _find_stance(gs, crook, "elves", 0.3, 1.0)
	if not friend.is_empty():
		var mv3 = hs._spread_motivation(friend, r)
		_check("friend buries it", int(mv3.get("cap_delta", 0)) == -1)


func _test_rep_bleeds() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var crook: Dictionary = _spawn(gs, "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	var cid := int(crook.get("id", 0))
	var before: float = hs.reputation_of(cid)
	_commit_crime(gs, "pickpocket", cid, int(victim.get("id", 0)),
		"Oakhollow", 10, "PICKPOCKET STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "PICKPOCKET STRIKES OAKHOLLOW!")
	_check("rumor docked the crook's rep", hs.reputation_of(cid) < before)
	# Seed knowers (victim + crook) plus twelve more hearers = 14 x 1.5
	# = 21 — the last hit lands just past the 20.0 cap (same one-hit
	# overshoot semantics as the smear path), then it must stop.
	for i in 12:
		var hearer: Dictionary = _spawn(gs, "gnomes")
		hs._on_heard(hearer, r, {})
	var capped: float = hs.reputation_of(cid)
	_check("rep dock capped near REP_CRIME_CAP 20",
		capped <= before - 20.0 + 0.01)
	for i in 10:
		var late: Dictionary = _spawn(gs, "gnomes")
		hs._on_heard(late, r, {})
	_check("no further bleed past the cap",
		absf(hs.reputation_of(cid) - capped) < 0.01)


func _test_story_dedup() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var crook: Dictionary = _spawn(gs, "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	_commit_crime(gs, "pickpocket", int(crook.get("id", 0)),
		int(victim.get("id", 0)), "Oakhollow", 25,
		"PICKPOCKET STRIKES OAKHOLLOW!")
	var before: int = (hs.state["rumors"] as Array).size()
	# The Gazette story publishes AFTER the signal (the real order in
	# crime.gd) — the party-less seed must not duplicate the rich rumor.
	gs.bus.gazette_story.emit({"headline": "PICKPOCKET STRIKES OAKHOLLOW!",
		"kind": "crime", "body": "x"})
	var after: int = (hs.state["rumors"] as Array).size()
	_check("story does not double-seed the crime", after == before)


func _test_story_fallback_generic() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# A crime story with NO rich counterpart (arrest blotter, old save)
	# still seeds the generic line — and it routes generic, no crash.
	gs.bus.gazette_story.emit({"headline": "ARREST MADE", "kind": "crime",
		"body": "x"})
	var r: Dictionary = _crime_rumor(hs, "ARREST MADE")
	_check("blotter story seeds a crime rumor", not r.is_empty())
	_check("no parties on the blotter line", not r.has("crime_kind"))
	var u: Dictionary = _spawn(gs, "gnomes")
	hs._on_heard(u, r, {})
	_check("blotter routes generic (heard_rumor)",
		_recalled(u, "heard_rumor", int(r.get("id", 0))) > 0.0)


func _test_investigation_named() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var crook: Dictionary = _spawn(gs, "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_commit_crime(gs, "pickpocket", int(crook.get("id", 0)), vid,
		"Oakhollow", 25, "PICKPOCKET STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "PICKPOCKET STRIKES OAKHOLLOW!")
	var a: Dictionary = hs.answer_about_rumor(victim, r)
	_check("victim confirms the crime", String(a.get("stance", "")) == "confirm")
	_check("witness answers from the crime pool (not generic)",
		_pool_hit(String(a.get("text", "")), hs.INVEST_CRIME_CONFIRM))
	_check("pool carries the HTML line",
		String(hs.INVEST_CRIME_CONFIRM[0]).contains("THIEF! I SAW THE WHOLE THING!"))
	var stranger: Dictionary = _spawn(gs, "gnomes")
	var a2: Dictionary = hs.answer_about_rumor(stranger, r)
	_check("non-knower shrugs", String(a2.get("stance", "")) == "shrug")


func _test_investigation_unseen() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	_commit_crime(gs, "pickpocket", 0, vid, "Oakhollow", 20,
		"PICKPOCKET STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "PICKPOCKET STRIKES OAKHOLLOW!")
	var a: Dictionary = hs.answer_about_rumor(victim, r)
	_check("victim confirms the unseen crime",
		String(a.get("stance", "")) == "confirm")
	_check("unseen answer from the unseen pool",
		_pool_hit(String(a.get("text", "")), hs.INVEST_CRIME_UNSEEN))
	_check("unseen thief not named as seen",
		not String(a.get("text", "")).contains("I SAW THE WHOLE THING"))


func _test_repeat_offender() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var crook: Dictionary = _spawn(gs, "ogres")
	var v1: Dictionary = _spawn(gs, "ogres")
	var v2: Dictionary = _spawn(gs, "ogres")
	var cid := int(crook.get("id", 0))
	_commit_crime(gs, "pickpocket", cid, int(v1.get("id", 0)),
		"Oakhollow", 10, "PICKPOCKET STRIKES OAKHOLLOW!")
	_commit_crime(gs, "mugging", cid, int(v2.get("id", 0)),
		"Oakhollow", 0, "MUGGING ON OAKHOLLOW STREETS!")
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "crime" \
				and int(r.get("crook_id", 0)) == cid:
			n += 1
	_check("each crime is its own rumor", n == 2)


func _test_truth_true() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var crook: Dictionary = _spawn(gs, "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	_commit_crime(gs, "pickpocket", int(crook.get("id", 0)),
		int(victim.get("id", 0)), "Oakhollow", 25,
		"PICKPOCKET STRIKES OAKHOLLOW!")
	var r: Dictionary = _crime_rumor(hs, "PICKPOCKET STRIKES OAKHOLLOW!")
	_check("crime is witnessed fact (TRUTH_TRUE)",
		hs.rumor_truth(r) == "true")
