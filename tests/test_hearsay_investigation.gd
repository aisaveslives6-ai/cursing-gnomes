extends SceneTree
## Cursing Gnomes — hearsay investigation + reputation + rumor quests
## (Jeremy 2026-10-06, lane 6).
##
## The player investigates rumors from the Rumors app: NPCs answer from
## what they actually know (DM flow), false claims denied by 2+ get
## DEBUNKED with a Gazette "RUMOR MILL CORRECTION", true claims confirmed
## by 2+ get VERIFIED. Believed rumors move reputations (per-NPC and
## per-faction). Hot rumors spawn advisor proposals (scout the buildup /
## investigate the cache). Covers:
##  - investigate true rumor -> confirms, verified, heat bump, DMs sent
##  - investigate false rumor -> debunked, correction story, press skips it
##  - correction story doesn't loop (exactly one from_gazette rumor)
##  - unknown-truth talk -> inconclusive, nothing buried
##  - SLUR HARD LINE: slur answers never deny, slur never debunked
##    (even via direct _debunk), offender rep tanked to 0, faction hit
##  - smear believers lower the target's NPC rep (capped per rumor)
##  - deed praise/grumble shifts player faction rep at seed
##  - reputation_of default 50 + rep_label bands
##  - hot war rumor -> scout_mission proposal (once); hot cache rumor ->
##    investigate_cache proposal
##  - scout approval -> War Advisor DM with intel
##  - cache approval -> expedition resolves with advisor DM
##  - enemy buildup proposal -> buildup rumor seeded (player's own don't)
##  - blocked NPCs are never asked
##  - from_dict backfills investigation/reputation schema
##  - PhoneRumors: Investigate button, DEBUNKED card, smear standing line
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_investigation.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


## Mimics SimRoyalCourt.publish_story: records the story AND emits
## bus.gazette_story, so the anti-loop path is exercised.
class MockCourt:
	extends RefCounted
	var gs: GameState
	var stories: Array = []
	func _init(g: GameState) -> void:
		gs = g
	func publish_story(headline: String, body: String,
			kind: String = "default") -> Dictionary:
		var s := {"id": stories.size(), "headline": headline,
			"body": body, "story": body, "kind": kind,
			"day": gs.day_number}
		stories.append(s)
		gs.bus.gazette_story.emit(s)
		return s


class MockProposals:
	extends RefCounted
	var calls: Array = []
	func propose(faction: String, kind: String,
			details: Dictionary = {}) -> Dictionary:
		calls.append({"faction": faction, "kind": kind,
			"details": details})
		return {"ok": true, "id": calls.size()}


class MockPhone:
	extends RefCounted
	var dms: Array = []  # {unit_id, text}
	var blocked := {}
	func npc_message(unit_id: int, text: String) -> void:
		dms.append({"unit_id": unit_id, "text": text})
	func is_blocked(unit_id: int) -> bool:
		return bool(blocked.get(unit_id, false))


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay-investigation tests ===")
	_test_investigate_confirms_true()
	_test_investigate_debunks_false()
	_test_correction_no_loop()
	_test_investigate_unknown_inconclusive()
	_test_slur_hard_line()
	_test_slur_rep_tank()
	_test_smear_rep_drip()
	_test_deed_rep()
	_test_rep_defaults_labels()
	_test_quest_scout_spawn()
	_test_quest_cache_spawn()
	_test_scout_approved_dm()
	_test_cache_approved_resolves()
	_test_buildup_rumor_hook()
	_test_blocked_never_asked()
	_test_from_dict_backfill_investigation()
	_test_phone_rumors_investigate_ui()
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


func _new_hs(gs: GameState, phone = null) -> Array:
	var hs = load("res://scripts/sim/hearsay.gd").new(gs, phone)
	var court := MockCourt.new(gs)
	gs.court_sys = court
	return [hs, court]


func _spawn(gs: GameState, faction: String, job: String = "peasant",
		npc_name: String = "") -> Dictionary:
	var d := {"faction": faction, "alive": true, "mind": {}, "job": job}
	if npc_name != "":
		d["name"] = npc_name
	return gs.add_unit(d)


func _test_investigate_confirms_true() -> void:
	seed(20261006)
	var gs := _new_gs()
	var mp := MockPhone.new()
	var pair: Array = _new_hs(gs, mp)
	var hs = pair[0]
	var u1: Dictionary = _spawn(gs, "gnomes")
	var u2: Dictionary = _spawn(gs, "gnomes")
	var u3: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("WAR with the Ogres! The drums beat.",
		"war", "ogres", 0.8, -1, false, "true")
	r["knowers"] = [int(u1.get("id", 0)), int(u2.get("id", 0)),
		int(u3.get("id", 0))]
	var res: Dictionary = hs.investigate_rumor(int(r.get("id", 0)))
	_check("investigate ok", bool(res.get("ok", false)))
	_check("true rumor confirmed", String(res.get("outcome", "")) == "confirmed")
	_check("rumor marked verified", bool(r.get("verified", false)))
	_check("heat bumped", float(r.get("heat", 0.0)) > 0.8)
	var answers: Array = res.get("answers", [])
	_check("three answers", answers.size() == 3)
	var confirms := 0
	for a: Dictionary in answers:
		if String(a.get("stance", "")) == "confirm":
			confirms += 1
	_check("all three confirm", confirms == 3)
	_check("answers DM'd", mp.dms.size() == 3)
	gs.queue_free()


func _test_investigate_debunks_false() -> void:
	seed(20261006)
	var gs := _new_gs()
	var mp := MockPhone.new()
	var pair: Array = _new_hs(gs, mp)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var u1: Dictionary = _spawn(gs, "gnomes")
	var u2: Dictionary = _spawn(gs, "gnomes")
	var u3: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("The Ogres built a moon cannon. Probably.",
		"war", "ogres", 0.9, -1, false, "false")
	r["knowers"] = [int(u1.get("id", 0)), int(u2.get("id", 0)),
		int(u3.get("id", 0))]
	var res: Dictionary = hs.investigate_rumor(int(r.get("id", 0)))
	_check("false rumor debunked", String(res.get("outcome", "")) == "debunked")
	_check("rumor flagged debunked", bool(r.get("debunked", false)))
	_check("debunked heat zeroed", float(r.get("heat", 0.0)) == 0.0)
	_check("correction published", court.stories.size() == 1)
	var s: Dictionary = court.stories[0]
	_check("correction headline labeled",
		String(s.get("headline", "")).begins_with("RUMOR MILL CORRECTION: "))
	var denies := 0
	for a: Dictionary in res.get("answers", []):
		if String(a.get("stance", "")) == "deny":
			denies += 1
	_check("knowers denied the false claim", denies >= 2)
	hs._press_tick()
	_check("press never prints debunked rumors", court.stories.size() == 1)
	gs.queue_free()


func _test_correction_no_loop() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var r: Dictionary = hs.seed_rumor("The moon is cheese. Trust me.",
		"misc", "", 0.9, -1, false, "false")
	var before: int = (hs.state["rumors"] as Array).size()
	hs._debunk(r)  # mock court emits gazette_story inside publish_story
	var after: int = (hs.state["rumors"] as Array).size()
	_check("correction seeds exactly one gossip rumor", after == before + 1)
	var gr: Dictionary = (hs.state["rumors"] as Array)[after - 1]
	_check("correction gossip is gazette-born",
		bool(gr.get("from_gazette", false)))
	hs.daily_tick()
	_check("no second correction, no ping-pong",
		(pair[1] as MockCourt).stories.size() == 1)
	gs.queue_free()


func _test_investigate_unknown_inconclusive() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var u1: Dictionary = _spawn(gs, "gnomes")
	var u2: Dictionary = _spawn(gs, "gnomes")
	var u3: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor(
		"Heard the tavern keeper waters down the ale.", "life", "", 0.7)
	r["knowers"] = [int(u1.get("id", 0)), int(u2.get("id", 0)),
		int(u3.get("id", 0))]
	var res: Dictionary = hs.investigate_rumor(int(r.get("id", 0)))
	_check("unknown truth inconclusive",
		String(res.get("outcome", "")) == "inconclusive")
	_check("not debunked", not bool(r.get("debunked", false)))
	_check("not verified", not bool(r.get("verified", false)))
	_check("no correction for inconclusive", court.stories.is_empty())
	gs.queue_free()


func _test_slur_hard_line() -> void:
	seed(20261006)
	var gs := _new_gs()
	var mp := MockPhone.new()
	var pair: Array = _new_hs(gs, mp)
	var hs = pair[0]
	var court: MockCourt = pair[1]
	var u1: Dictionary = _spawn(gs, "gnomes")
	var u2: Dictionary = _spawn(gs, "gnomes")
	# Euphemized condemnation line (reporters never quote the slur).
	var r: Dictionary = hs.seed_rumor(
		"Spread the word: Grak is racist. Don't let them forget it.",
		"slur", "ogres", 0.95, -1, false, "true")
	r["knowers"] = [int(u1.get("id", 0)), int(u2.get("id", 0))]
	var res: Dictionary = hs.investigate_rumor(int(r.get("id", 0)))
	var answers: Array = res.get("answers", [])
	var confirms := 0
	var denies := 0
	for a: Dictionary in answers:
		if String(a.get("stance", "")) == "confirm":
			confirms += 1
		if String(a.get("stance", "")) == "deny":
			denies += 1
	_check("slur answers always confirm", confirms == answers.size())
	_check("slur answers never deny", denies == 0)
	_check("slur never debunked by investigation",
		not bool(r.get("debunked", false)))
	hs._debunk(r)  # direct call must also refuse
	_check("slur never debunked directly",
		not bool(r.get("debunked", false)))
	_check("no correction story for slur", court.stories.is_empty())
	gs.queue_free()


func _test_slur_rep_tank() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var grak: Dictionary = _spawn(gs, "ogres", "peasant", "Grak")
	var gid := int(grak.get("id", 0))
	_check("rep starts at 50", hs.reputation_of(gid) == 50.0)
	var before: float = gs.diplomacy.reputation_of("ogres")
	hs._on_slur_incident("ogres", "", "ignored-exact-text", "Grak")
	_check("named offender rep tanked to 0", hs.reputation_of(gid) == 0.0)
	_check("offender faction rep hit",
		gs.diplomacy.reputation_of("ogres") < before)
	gs.queue_free()


func _test_smear_rep_drip() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var target: Dictionary = _spawn(gs, "ogres")
	var tid := int(target.get("id", 0))
	var hearers: Array = []
	for i in 3:
		hearers.append(_spawn(gs, "gnomes"))
	var r: Dictionary = hs.seed_rumor("Word from the crown: Grak smells.",
		"smear", "npc:%d" % tid, 0.8, -1)
	r["target_id"] = tid
	r["target_name"] = "Grak"
	r["target_faction"] = "ogres"
	for h: Dictionary in hearers:
		hs._on_heard(h, r, {})
	_check("three believers lower rep by 6",
		is_equal_approx(hs.reputation_of(tid), 44.0))
	# Cap: a mob can't push past -30 for one rumor.
	for i in 40:
		hs._on_heard(_spawn(gs, "gnomes"), r, {})
	_check("per-rumor rep cap holds",
		hs.reputation_of(tid) >= 20.0)
	gs.queue_free()


func _test_deed_rep() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var before: float = gs.diplomacy.reputation_of("gnomes")
	hs.gossip_deed("saved a kitten from a well", true)
	_check("praised deed lifts faction rep",
		is_equal_approx(gs.diplomacy.reputation_of("gnomes"), before + 1.0))
	hs.gossip_deed("taxed the orphans", false)
	_check("grumbled deed lowers faction rep",
		is_equal_approx(gs.diplomacy.reputation_of("gnomes"), before - 0.5))
	gs.queue_free()


func _test_rep_defaults_labels() -> void:
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	_check("unknown npc rep defaults 50", hs.reputation_of(424242) == 50.0)
	_check("label beloved", hs.rep_label(85.0) == "Beloved")
	_check("label liked", hs.rep_label(65.0) == "Liked")
	_check("label known", hs.rep_label(50.0) == "Known")
	_check("label shady", hs.rep_label(30.0) == "Shady")
	_check("label despised", hs.rep_label(10.0) == "Despised")
	gs.queue_free()


func _test_quest_scout_spawn() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var mp2 := MockProposals.new()
	gs.proposals = mp2
	var r: Dictionary = hs.seed_rumor("WAR with the Ogres! Drums beat.",
		"war", "ogres", 0.9)
	hs._quest_tick()
	_check("hot war rumor spawns a proposal", mp2.calls.size() == 1)
	var c: Dictionary = mp2.calls[0]
	_check("proposal is a scout mission",
		String(c.get("kind", "")) == "scout_mission")
	_check("scout targets the rumored faction",
		String((c.get("details", {}) as Dictionary).get("target", "")) == "ogres")
	_check("proposal carries a brief",
		String((c.get("details", {}) as Dictionary).get("brief", "")) != "")
	_check("rumor flagged quest_spawned", bool(r.get("quest_spawned", false)))
	hs._quest_tick()
	_check("no duplicate proposal", mp2.calls.size() == 1)
	gs.queue_free()


func _test_quest_cache_spawn() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var mp2 := MockProposals.new()
	gs.proposals = mp2
	var r: Dictionary = hs.seed_rumor(
		"They say a bandit cache is buried out in the wilds.", "cache",
		"", 0.9)
	hs._quest_tick()
	_check("hot cache rumor spawns a proposal", mp2.calls.size() == 1)
	_check("proposal is a cache investigation",
		String((mp2.calls[0] as Dictionary).get("kind", "")) == "investigate_cache")
	_check("cache rumor flagged quest_spawned",
		bool(r.get("quest_spawned", false)))
	gs.queue_free()


func _test_scout_approved_dm() -> void:
	seed(20261006)
	var gs := _new_gs()
	var mp := MockPhone.new()
	var pair: Array = _new_hs(gs, mp)
	var hs = pair[0]
	var adv: Dictionary = _spawn(gs, "gnomes", "advisor_war")
	var aid := int(adv.get("id", 0))
	hs.quest_approved("scout_mission", {"target": "ogres", "rumor_id": 0})
	_check("war advisor DM'd the report", mp.dms.size() == 1)
	var dm: Dictionary = mp.dms[0]
	_check("DM from the war advisor", int(dm.get("unit_id", 0)) == aid)
	_check("DM carries scout intel",
		String(dm.get("text", "")).contains("Scout report"))
	gs.queue_free()


func _test_cache_approved_resolves() -> void:
	seed(20261006)
	var gs := _new_gs()
	var mp := MockPhone.new()
	var pair: Array = _new_hs(gs, mp)
	var hs = pair[0]
	var adv: Dictionary = _spawn(gs, "gnomes", "advisor_civic")
	var aid := int(adv.get("id", 0))
	hs.quest_approved("investigate_cache", {"rumor_id": 0})
	_check("expedition dispatched",
		(hs.state["pending_caches"] as Array).size() == 1)
	_check("dispatch DM sent", mp.dms.size() == 1)
	# Fast-forward: the party reports back.
	((hs.state["pending_caches"] as Array)[0] as Dictionary)["day"] = 1
	mp.dms.clear()
	hs._resolve_pending_caches()
	_check("pending cache resolved",
		(hs.state["pending_caches"] as Array).is_empty())
	_check("report DM from civic advisor", mp.dms.size() == 1
		and int((mp.dms[0] as Dictionary).get("unit_id", 0)) == aid)
	_check("report mentions the cache",
		String((mp.dms[0] as Dictionary).get("text", "")).to_lower().contains("cache"))
	gs.queue_free()


func _test_buildup_rumor_hook() -> void:
	seed(20261006)
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	var before: int = (hs.state["rumors"] as Array).size()
	gs.bus.strategic_proposal.emit({"faction": "ogres",
		"kind": "major_buildup", "details": {}})
	var after: int = (hs.state["rumors"] as Array).size()
	_check("enemy buildup seeds a rumor", after == before + 1)
	var br: Dictionary = (hs.state["rumors"] as Array)[after - 1]
	_check("buildup rumor subjects the builder",
		String(br.get("subject", "")) == "ogres")
	_check("buildup rumor is war kind", String(br.get("kind", "")) == "war")
	gs.bus.strategic_proposal.emit({"faction": "gnomes",
		"kind": "major_buildup", "details": {}})
	_check("player proposals seed no gossip",
		(hs.state["rumors"] as Array).size() == after)
	gs.queue_free()


func _test_blocked_never_asked() -> void:
	seed(20261006)
	var gs := _new_gs()
	var mp := MockPhone.new()
	var pair: Array = _new_hs(gs, mp)
	var hs = pair[0]
	var u1: Dictionary = _spawn(gs, "gnomes")
	var u2: Dictionary = _spawn(gs, "gnomes")
	var u3: Dictionary = _spawn(gs, "gnomes")
	mp.blocked[int(u1.get("id", 0))] = true
	var r: Dictionary = hs.seed_rumor("WAR with the Elves! Arrows at dawn.",
		"war", "elves", 0.8, -1, false, "true")
	r["knowers"] = [int(u1.get("id", 0)), int(u2.get("id", 0)),
		int(u3.get("id", 0))]
	var res: Dictionary = hs.investigate_rumor(int(r.get("id", 0)))
	var answers: Array = res.get("answers", [])
	var asked: Array = []
	for a: Dictionary in answers:
		asked.append(int(a.get("unit_id", 0)))
	_check("blocked NPC never asked",
		not asked.has(int(u1.get("id", 0))))
	_check("blocked NPC never DM'd",
		not mp.dms.any(func(d: Dictionary) -> bool:
			return int(d.get("unit_id", 0)) == int(u1.get("id", 0))))
	gs.queue_free()


func _test_from_dict_backfill_investigation() -> void:
	var gs := _new_gs()
	var pair: Array = _new_hs(gs)
	var hs = pair[0]
	hs.from_dict({"rumors": [{
		"id": 7, "text": "Old war talk.", "text_orig": "Old war talk.",
		"kind": "war", "subject": "ogres", "day": 3, "heat": 0.9,
		"knowers": [1], "reached_ruler": false, "distortions": 0,
		"published": false, "from_gazette": false,
	}], "seq": 8})
	var r: Dictionary = (hs.state["rumors"] as Array)[0]
	_check("backfill truth unknown", String(r.get("truth", "")) == "unknown")
	_check("backfill debunked false", r.has("debunked")
		and not bool(r.get("debunked", true)))
	_check("backfill verified false", r.has("verified")
		and not bool(r.get("verified", true)))
	_check("backfill quest_spawned false", r.has("quest_spawned")
		and not bool(r.get("quest_spawned", true)))
	_check("backfill npc_rep", hs.state.has("npc_rep"))
	_check("backfill pending_caches", hs.state.has("pending_caches"))
	_check("old rep defaults 50", hs.reputation_of(7) == 50.0)
	gs.queue_free()


func _count_buttons(node: Node) -> int:
	var n := 0
	if node is Button:
		n += 1
	for ch: Node in node.get_children():
		n += _count_buttons(ch)
	return n


func _test_phone_rumors_investigate_ui() -> void:
	var PhoneRumorsScript = load("res://scripts/ui/phone_rumors.gd")
	_check("kind cache", PhoneRumorsScript.kind_label("cache") == "CACHE")
	var rep_of := func(uid: int) -> float: return 30.0
	var investigated: Array = []
	var on_inv := func(rid: int) -> void: investigated.append(rid)
	var live := {"id": 11, "text": "WAR with the Ogres!", "kind": "war",
		"heat": 0.9, "day": 2, "knowers": [1, 2], "distortions": 0,
		"from_gazette": false, "debunked": false, "verified": false}
	var dead := {"id": 12, "text": "The moon is cheese.", "kind": "misc",
		"heat": 0.0, "day": 2, "knowers": [3], "distortions": 0,
		"from_gazette": false, "debunked": true, "verified": false}
	var smear := {"id": 13, "text": "Grak smells.", "kind": "smear",
		"heat": 0.8, "day": 2, "knowers": [4], "distortions": 0,
		"from_gazette": false, "debunked": false, "verified": false,
		"target_id": 99, "target_name": "Grak"}
	var box := VBoxContainer.new()
	PhoneRumorsScript.build(box, [live, dead, smear], rep_of, on_inv)
	# 1 summary + 3 cards.
	_check("three cards built", box.get_child_count() == 4)
	var cards: Array = [box.get_child(1), box.get_child(2), box.get_child(3)]
	_check("live rumor gets Investigate button",
		_count_buttons(cards[0]) == 1)
	_check("debunked rumor gets no button", _count_buttons(cards[2 - 1]) == 0)
	var meta_live: String = PhoneRumorsScript.meta_line(live, rep_of)
	_check("live meta has no standing line",
		not meta_live.contains("standing"))
	var meta_smear: String = PhoneRumorsScript.meta_line(smear, rep_of)
	_check("smear meta shows standing",
		meta_smear.contains("standing: 30"))
	_check("smear meta shows rep word", meta_smear.contains("shady"))
	var meta_dead: String = PhoneRumorsScript.meta_line(dead, rep_of)
	_check("debunked meta notes correction", meta_dead.contains("DEBUNKED"))
	# Pressing the button fires the injected callable with the rumor id.
	var btn := _find_button(cards[0])
	_check("button found", btn != null)
	if btn != null:
		btn.pressed.emit()
		_check("investigate fired with rumor id", investigated == [11])
	box.queue_free()


func _find_button(node: Node) -> Button:
	if node is Button:
		return node
	for ch: Node in node.get_children():
		var b := _find_button(ch)
		if b != null:
			return b
	return null
