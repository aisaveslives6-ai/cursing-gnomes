extends SceneTree
## Cursing Gnomes — War Counsel EXPANSION headless tests (Lane 2, 2026-10-06).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_war_counsel_expansion.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers the six Lane-2 expansions on top of the base war counsel:
##   1. named notable-fallen reports (warlords / high-kill veterans named in
##      Messenger, throttled one report per war per day)
##   2. war exhaustion / morale (losing wars grind morale down faster via the
##      AI director; exhausted armies reinforce at half strength; counsel
##      surfaces "the men are exhausted / another push risks rout")
##   3. peace-terms negotiation in chat ("offer peace for 500 gold" ->
##      envoy -> AI accept/counter/refuse in Messenger; "demand tribute"
##      through the diplomacy channel)
##   4. multi-war dashboard ("wars" status query lists every active war with
##      score, tier, and trend)
##   5. advisor debate (War wants to fight on, Treasury says the coffers
##      can't take it -> both argue in-voice, ruler decides ACCEPT/DENY)
##   6. post-war analysis (Gazette story with real numbers when a war ends)


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes War Counsel expansion tests ===")
	_test_fallen_warlord_named()
	_test_fallen_veteran_kills_named()
	_test_fallen_unnamed_fallback()
	_test_fallen_civilian_ignored()
	_test_fallen_throttled_one_per_day()
	_test_kill_credit()
	_test_exhaustion_in_score()
	_test_exhaustion_rout_line()
	_test_exhaustion_tick_drains_morale()
	_test_faction_exhausted()
	_test_debate_fires()
	_test_debate_accept_sues_for_peace()
	_test_debate_deny_rearms()
	_test_debate_no_war_advisor_fallback()
	_test_peace_terms_offer_accept()
	_test_peace_terms_counter()
	_test_peace_terms_refuse_blocks_reoffer()
	_test_peace_terms_unknown_faction()
	_test_demand_tribute_during_war()
	_test_dashboard_two_wars()
	_test_dashboard_trend()
	_test_dashboard_peace()
	_test_post_war_analysis()
	_test_expansion_save_roundtrip()
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


## Player = humans (first faction). Hall + town + funded.
func _make_world(factions: Array[String] = ["humans", "elves"]) -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)  # player = humans
	gs.set_ruler_name("ass")
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.hiring = GuildHiring.new(gs)
	gs.army = SimArmy.new(gs)
	gs.court_sys = _StubCourt.new(gs)
	gs.proposals = SimProposals.new(gs)
	gs.phone_sys = _StubPhone.new(gs)
	var rv := SimRulersVoice.new(gs)
	gs.rulers_voice = rv
	gs.found_town("humans", "Testville", Vector2(2000, 2000))
	gs.add_building({"type": "town_hall", "faction": "humans", "town_id": 1,
		"position": Vector2(2000, 2000), "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
	gs.add_building({"type": "town_hall", "faction": "elves", "town_id": 2,
		"position": Vector2(500, 500), "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
	_fund(gs, "humans", 5000.0, 5000.0)
	return [gs, rv]


func _fund(gs: GameState, faction: String, gold: float, wood: float) -> void:
	gs.resources.add_resource(faction, "gold", gold, true)
	gs.resources.add_resource(faction, "wood", wood, true)
	gs.resources.add_resource(faction, "oil", gold, true)
	gs.resources.add_resource(faction, "food", gold, true)


func _advisor(gs: GameState, faction: String, job: String) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "job": job,
		"town_id": 1, "position": Vector2(2000, 2010), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0,
		"name": "Test Advisor"})
	u["is_advisor"] = true
	return u


func _soldier(gs: GameState, faction: String, town_id: int,
		pos: Vector2) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": "soldier",
		"town_id": town_id, "position": pos, "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0})


func _start_test_war(gs: GameState) -> void:
	gs.diplomacy.declare_war("humans", "elves", "test")


## Advance the sim clock to day n (day_number derives from game_time in the
## live game, but headless tests set game_time directly, which does NOT
## advance it — so set both) and fire the daily signal the counsel
## listens to.
func _day(gs: GameState, n: int) -> void:
	gs.game_time = Config.DAY_LENGTH_SECONDS * float(maxi(0, n - 1))
	gs.day_number = n
	gs.bus.day_changed.emit(n, false)


## Seed a war record with lopsided casualties (bypasses signal plumbing).
func _seed_war(rv: SimRulersVoice, foe: String, ours_dead: int,
		theirs_dead: int) -> String:
	var key := "humans|%s" % foe
	rv._wars[key] = {
		"foe": foe, "start_day": 1,
		"ours_dead": ours_dead, "theirs_dead": theirs_dead,
		"towns0": {}, "mons0": {}, "crys0": {},
		"halls0": {"ours": 1, "theirs": 1},
		"gold_hist": [5000.0, 5000.0, 5000.0],
		"fallen": [], "fallen_report_day": -99, "we_sued": false,
		"score": 0.0, "prev_score": 0.0,
	}
	return key


## Treasury collapsing: 5000 -> 3000 -> 1000 (1000+/day burn, runway < 12).
func _seed_drain(gs: GameState, rv: SimRulersVoice) -> String:
	var key := _seed_war(rv, "elves", 0, 0)
	rv._wars[key]["gold_hist"] = [5000.0, 3000.0]
	gs.resources.spend("humans", {"gold": 4000.0})
	return key


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


class _StubPhone:
	extends RefCounted
	var _gs = null
	var sent: Array = []

	func _init(gs) -> void:
		_gs = gs

	func npc_message(unit_id: int, text: String) -> void:
		sent.append({"unit_id": unit_id, "text": text})


## Minimal court stand-in: real SimPolicies + a recording publish_story.
class _StubCourt:
	extends RefCounted
	var policies = null
	var stories: Array = []

	func _init(gs) -> void:
		policies = SimPolicies.new(gs, self)

	func publish_story(headline: String, body: String,
			kind: String = "default") -> Dictionary:
		var s := {"headline": headline, "body": body, "kind": kind}
		stories.append(s)
		return s


## --- 1. named notable-fallen reports ----------------------------------------


func _test_fallen_warlord_named() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	var wl: Dictionary = gs.add_unit({"faction": "humans", "job": "warlord",
		"town_id": 1, "position": Vector2(2000, 2000), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0, "name": "Grimbash"})
	gs.bus.unit_killed.emit(int(wl.get("id", 0)), "elves")
	var phone = gs.phone_sys
	_check("fallen: warlord death reported",
		phone.sent.size() == 1)
	var txt := String(phone.sent[0].get("text", ""))
	_check("fallen: warlord named", txt.contains("Grimbash"))
	_check("fallen: from war advisor",
		int(phone.sent[0].get("unit_id", 0)) == int(wa.get("id", 0)))
	_free_world(parts)


func _test_fallen_veteran_kills_named() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	var vet := _soldier(gs, "humans", 1, Vector2(2000, 2000))
	vet["name"] = "Mira"
	vet["kills"] = 14
	gs.bus.unit_killed.emit(int(vet.get("id", 0)), "elves")
	var phone = gs.phone_sys
	_check("fallen: veteran reported", phone.sent.size() == 1)
	var txt := String(phone.sent[0].get("text", ""))
	_check("fallen: veteran named with kills",
		txt.contains("Mira") and txt.contains("14"))
	_check("fallen: names the town", txt.contains("Testville"))
	_free_world(parts)


func _test_fallen_unnamed_fallback() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	var vet := _soldier(gs, "humans", 1, Vector2(2000, 2000))
	vet["kills"] = 9  # no name set
	gs.bus.unit_killed.emit(int(vet.get("id", 0)), "elves")
	var phone = gs.phone_sys
	_check("fallen: unnamed veteran reported", phone.sent.size() == 1)
	_check("fallen: fallback names the rank",
		String(phone.sent[0].get("text", "")).contains("veteran soldier"))
	_free_world(parts)


func _test_fallen_civilian_ignored() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	var f: Dictionary = gs.add_unit({"faction": "humans", "job": "farmer",
		"town_id": 1, "position": Vector2(2000, 2000), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0, "name": "Pippa"})
	gs.bus.unit_killed.emit(int(f.get("id", 0)), "elves")
	_check("fallen: civilian death not headlined",
		(gs.phone_sys as _StubPhone).sent.is_empty())
	_free_world(parts)


func _test_fallen_throttled_one_per_day() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	var v1 := _soldier(gs, "humans", 1, Vector2(2000, 2000))
	v1["name"] = "One"
	v1["kills"] = 6
	var v2 := _soldier(gs, "humans", 1, Vector2(2000, 2000))
	v2["name"] = "Two"
	v2["kills"] = 7
	gs.bus.unit_killed.emit(int(v1.get("id", 0)), "elves")
	gs.bus.unit_killed.emit(int(v2.get("id", 0)), "elves")
	var phone = gs.phone_sys
	_check("fallen: one report per war per day", phone.sent.size() == 1)
	# Next day: another notable death gets its own report.
	_day(gs, 2)
	var v3 := _soldier(gs, "humans", 1, Vector2(2000, 2000))
	v3["name"] = "Three"
	v3["kills"] = 8
	gs.bus.unit_killed.emit(int(v3.get("id", 0)), "elves")
	_check("fallen: new day, new report", phone.sent.size() == 2)
	_check("fallen: second report names the new loss",
		String(phone.sent[1].get("text", "")).contains("Three"))
	_free_world(parts)


func _test_kill_credit() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var combat := SimCombat.new(gs)
	var a := _soldier(gs, "humans", 1, Vector2(2000, 2000))
	var v := _soldier(gs, "elves", 2, Vector2(2005, 2000))
	# Artillery-kind kills outright (no downed state) and credits the killer.
	var died: bool = combat.damage_unit(int(v.get("id", 0)), 9999.0,
		"humans", int(a.get("id", 0)), "cannonball")
	_check("kills: lethal hit kills", died)
	_check("kills: attacker credited",
		int(gs.get_unit(int(a.get("id", 0))).get("kills", 0)) == 1)
	_free_world(parts)


## --- 2. war exhaustion / morale --------------------------------------------


func _test_exhaustion_in_score() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_start_test_war(gs)
	# Long grinding war + battered morale.
	gs.diplomacy.adjust_morale("humans", -35.0)
	var key := _seed_war(rv, "elves", 0, 0)
	rv._wars[key]["start_day"] = 1
	_day(gs, 20)
	var ws := rv._war_score(key, rv._wars[key])
	var reasons: Array = ws.get("reasons", [])
	var found := false
	for r: String in reasons:
		if r.contains("exhausted"):
			found = true
	_check("exhaustion: scored as a reason", found)
	_check("exhaustion: flag set on record",
		bool(rv._wars[key].get("exhausted", false)))
	_free_world(parts)


func _test_exhaustion_rout_line() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var txt: String = rv._plea_text(3, "Elven", [], true)
	_check("exhaustion: desperate plea warns of rout",
		txt.contains("rout"))
	var calm: String = rv._plea_text(3, "Elven", [], false)
	_check("exhaustion: no rout line when fresh",
		not calm.contains("rout"))
	_free_world(parts)


func _test_exhaustion_tick_drains_morale() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var director := SimAIDirector.new(gs)
	gs.ai_director = director
	_start_test_war(gs)
	# Elves field a real army; humans field almost nothing -> losing badly.
	for i: int in range(10):
		_soldier(gs, "elves", 2, Vector2(500, 500))
	_soldier(gs, "humans", 1, Vector2(2000, 2000))
	var before: float = gs.diplomacy.morale_of("humans")
	director._war_exhaustion_tick("humans")
	var after: float = gs.diplomacy.morale_of("humans")
	_check("exhaustion: losing side loses extra morale", after < before)
	# The winning side is untouched.
	var e_before: float = gs.diplomacy.morale_of("elves")
	director._war_exhaustion_tick("elves")
	_check("exhaustion: winning side spared",
		gs.diplomacy.morale_of("elves") == e_before)
	_free_world(parts)


func _test_faction_exhausted() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var director := SimAIDirector.new(gs)
	gs.ai_director = director
	_start_test_war(gs)
	_check("exhausted: fresh army not exhausted",
		not director._faction_exhausted("humans"))
	gs.diplomacy.adjust_morale("humans", -45.0)
	_check("exhausted: battered army at war is exhausted",
		director._faction_exhausted("humans"))
	gs.diplomacy.make_peace("humans", "elves")
	_check("exhausted: peace cures exhaustion",
		not director._faction_exhausted("humans"))
	_free_world(parts)


## --- 5. advisor debate ------------------------------------------------------
## (tested before peace terms: the debate owns the tier-0 + drain corner)


func _test_debate_fires() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	var ta := _advisor(gs, "humans", "advisor_economy")
	_start_test_war(gs)
	# Tier 0 (no casualties) + severe drain -> the advisors disagree.
	_seed_drain(gs, rv)
	_day(gs, 2)
	var phone = gs.phone_sys
	_check("debate: two voices speak", phone.sent.size() == 2)
	var t0 := String(phone.sent[0].get("text", ""))
	var t1 := String(phone.sent[1].get("text", ""))
	_check("debate: treasury opens",
		int(phone.sent[0].get("unit_id", 0)) == int(ta.get("id", 0)))
	_check("debate: treasury cites the coffers",
		t0.contains("treasury"))
	_check("debate: war advisor rebuts",
		int(phone.sent[1].get("unit_id", 0)) == int(wa.get("id", 0)))
	_check("debate: decision prompt offered",
		t1.contains("ACCEPT") and t1.contains("DENY"))
	var deb: Dictionary = rv._pending_debate_for(int(wa.get("id", 0)))
	_check("debate: pending state tracked", not deb.is_empty())
	_free_world(parts)


func _test_debate_accept_sues_for_peace() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_advisor(gs, "humans", "advisor_economy")
	_start_test_war(gs)
	_seed_drain(gs, rv)
	_day(gs, 2)
	var ack := rv.try_order(wa, "accept")
	_check("debate accept: ack non-empty", ack != "")
	var offers: Array = gs.diplomacy.pending_surrender_offers()
	_check("debate accept: surrender offered through diplomacy",
		offers.size() == 1)
	_check("debate accept: we sued recorded",
		bool(rv._wars["humans|elves"].get("we_sued", false)))
	_free_world(parts)


func _test_debate_deny_rearms() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_advisor(gs, "humans", "advisor_economy")
	_start_test_war(gs)
	_seed_drain(gs, rv)
	_day(gs, 2)
	var ack := rv.try_order(wa, "deny")
	_check("debate deny: grim ack", ack != "" and ack.contains("FIGHT ON"))
	var n: int = (gs.phone_sys as _StubPhone).sent.size()
	# Drain persists; the debate re-arms after 5 days.
	for d: int in range(3, 8):
		_day(gs, d)
	_check("debate deny: re-debates after cooldown",
		(gs.phone_sys as _StubPhone).sent.size() > n)
	_free_world(parts)


func _test_debate_no_war_advisor_fallback() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var ta := _advisor(gs, "humans", "advisor_economy")
	# No war advisor alive: the old solo treasury warning stands.
	_start_test_war(gs)
	_seed_drain(gs, rv)
	_day(gs, 2)
	var phone = gs.phone_sys
	_check("debate fallback: solo warning sent", phone.sent.size() == 1)
	_check("debate fallback: from treasury advisor",
		int(phone.sent[0].get("unit_id", 0)) == int(ta.get("id", 0)))
	_check("debate fallback: no debate state",
		rv._war_debates.is_empty())
	_free_world(parts)


## --- 3. peace-terms negotiation ---------------------------------------------


func _test_peace_terms_offer_accept() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	# Elves: weak and humble -> they take the deal.
	gs.diplomacy.set_faction_traits("elves", {"proud": 0.3})
	for i: int in range(8):
		_soldier(gs, "humans", 1, Vector2(2000, 2000))
	var ack := rv.try_order(wa, "offer peace for 500 gold")
	_check("terms: envoy ack", ack != "" and ack.contains("500"))
	_check("terms: offer tracked",
		String(rv._peace_terms["humans|elves"].get("state", "")) == "offered")
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	_day(gs, 2)
	var phone = gs.phone_sys
	var answered := false
	for m: Dictionary in phone.sent:
		if String(m.get("text", "")).contains("ACCEPT"):
			answered = true
	_check("terms: AI answer delivered", answered)
	_check("terms: war ended",
		gs.diplomacy.relation_state("humans", "elves") == "neutral")
	_check("terms: tribute moved",
		gs.resources.get_amount("humans", "gold") < gold_before)
	_check("terms: we sued recorded",
		bool(rv._wars["humans|elves"].get("we_sued", false)))
	_free_world(parts)


func _test_peace_terms_counter() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	# Even strength, middling pride, bitter war -> they counter.
	gs.diplomacy.set_faction_traits("elves", {"proud": 0.5})
	for i: int in range(5):
		_soldier(gs, "humans", 1, Vector2(2000, 2000))
		_soldier(gs, "elves", 2, Vector2(500, 500))
	var ack := rv.try_order(wa, "offer peace for 200 gold")
	_check("terms counter: envoy ack", ack != "")
	_day(gs, 2)
	var phone = gs.phone_sys
	var txt := ""
	for m: Dictionary in phone.sent:
		var t := String(m.get("text", ""))
		if t.contains("counter"):
			txt = t
	_check("terms counter: counter offered", txt != "")
	_check("terms counter: has ACCEPT/DENY",
		txt.contains("ACCEPT") and txt.contains("DENY"))
	# Accepting the counter pays THEIR price and ends the war.
	var counter: int = int(rv._peace_terms["humans|elves"].get("counter_amount", 0))
	_check("terms counter: price recorded", counter > 0)
	var ack2 := rv.try_order(wa, "accept")
	_check("terms counter: accept ack", ack2 != "")
	_check("terms counter: war ended",
		gs.diplomacy.relation_state("humans", "elves") == "neutral")
	_free_world(parts)


func _test_peace_terms_refuse_blocks_reoffer() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	# Strong and proud -> they spit on it.
	gs.diplomacy.set_faction_traits("elves", {"proud": 0.9})
	_soldier(gs, "humans", 1, Vector2(2000, 2000))
	for i: int in range(10):
		_soldier(gs, "elves", 2, Vector2(500, 500))
	rv.try_order(wa, "offer peace for 100 gold")
	_day(gs, 2)
	var phone = gs.phone_sys
	var refused := false
	for m: Dictionary in phone.sent:
		if String(m.get("text", "")).contains("spit on your offer"):
			refused = true
	_check("terms refuse: refusal delivered", refused)
	_check("terms refuse: war grinds on",
		gs.diplomacy.relation_state("humans", "elves") == "war")
	var ack := rv.try_order(wa, "offer peace for 100 gold")
	_check("terms refuse: one offer per war",
		ack.contains("already offered"))
	_free_world(parts)


func _test_peace_terms_unknown_faction() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	var ack := rv.try_order(wa, "offer peace for 500 gold")
	_check("terms: no faction named -> asks whom",
		ack != "" and ack.contains("Name a faction"))
	_free_world(parts)


func _test_demand_tribute_during_war() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	var ack := rv.try_order(wa, "demand tribute from the elves")
	_check("tribute: laughed out mid-war",
		ack != "" and ack.to_lower().contains("laugh"))
	_free_world(parts)


## --- 4. multi-war dashboard --------------------------------------------------


func _test_dashboard_two_wars() -> void:
	var parts := _make_world(["humans", "elves", "ogres"])
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	gs.diplomacy.declare_war("humans", "elves", "test")
	gs.diplomacy.declare_war("humans", "ogres", "test")
	_seed_war(rv, "elves", 30, 5)
	_seed_war(rv, "ogres", 2, 20)
	_day(gs, 2)
	var txt := rv.try_order(wa, "wars")
	_check("dashboard: non-empty", txt != "")
	_check("dashboard: lists the elven war", txt.contains("Elv"))
	_check("dashboard: lists the ogre war",
		txt.contains("Ogr"))
	_check("dashboard: shows a tier",
		txt.contains("CONCERNED") or txt.contains("URGENT") \
		or txt.contains("DESPERATE"))
	_check("dashboard: shows a trend",
		txt.contains("worsening") or txt.contains("holding") \
		or txt.contains("improving"))
	_free_world(parts)


func _test_dashboard_trend() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	_seed_war(rv, "elves", 4, 3)
	_day(gs, 2)
	_day(gs, 2)  # second close settles the baseline -> holding
	var t1 := rv.try_order(wa, "wars")
	_check("dashboard: steady trend first", t1.contains("holding"))
	# Pile on losses: the score climbs -> worsening.
	rv._wars["humans|elves"]["ours_dead"] = 30
	_day(gs, 3)
	var t2 := rv.try_order(wa, "wars")
	_check("dashboard: worsening trend", t2.contains("worsening"))
	_free_world(parts)


func _test_dashboard_peace() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	var txt := rv.try_order(wa, "wars")
	_check("dashboard: peacetime line",
		txt.contains("at peace"))
	_free_world(parts)


## --- 6. post-war analysis ----------------------------------------------------


func _test_post_war_analysis() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	var key := _seed_war(rv, "elves", 10, 4)
	rv._wars[key]["start_day"] = 1
	rv._wars[key]["we_sued"] = true
	# Five days of war, then peace.
	_day(gs, 6)
	gs.diplomacy.make_peace("humans", "elves")
	_day(gs, 7)
	var court = gs.court_sys
	_check("analysis: gazette story published", court.stories.size() == 1)
	var body := String(court.stories[0].get("body", ""))
	_check("analysis: names both casualty counts",
		body.contains("10") and body.contains("4"))
	_check("analysis: names the duration", body.contains("6 days"))
	_check("analysis: names who sued",
		body.contains("sued for peace"))
	_check("analysis: headline is war's end",
		String(court.stories[0].get("headline", "")).contains("WAR'S END"))
	var phone = gs.phone_sys
	var last: Dictionary = phone.sent[phone.sent.size() - 1]
	_check("analysis: war advisor DMs the summary",
		int(last.get("unit_id", 0)) == int(wa.get("id", 0)) \
		and String(last.get("text", "")).contains("It's over"))
	_check("analysis: record cleaned up", rv._wars.is_empty())
	_free_world(parts)


## --- persistence --------------------------------------------------------------


func _test_expansion_save_roundtrip() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_advisor(gs, "humans", "advisor_war")
	_advisor(gs, "humans", "advisor_economy")
	_start_test_war(gs)
	_seed_drain(gs, rv)
	_day(gs, 2)  # debate fires
	rv.try_order(_advisor(gs, "humans", "advisor_war"), "offer peace for 500 gold")
	var d := rv.to_dict()
	_check("save: debates persist", d.has("war_debates"))
	_check("save: terms persist", d.has("peace_terms"))
	_check("save: terms done-keys persist", d.has("peace_terms_done"))
	var rv2 := SimRulersVoice.new(gs)
	rv2.from_dict(d)
	_check("save: debate restored", not rv2._war_debates.is_empty())
	_check("save: terms restored", not rv2._peace_terms.is_empty())
	_free_world(parts)
