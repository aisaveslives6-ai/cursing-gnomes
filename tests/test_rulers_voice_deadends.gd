extends SceneTree
## Cursing Gnomes — Ruler's Voice no-dead-end headless tests (2026-10-09).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_rulers_voice_deadends.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers the 2026-10-09 Ruler's Voice / war counsel no-dead-end audit fixes:
##   1. envoy answer fallback: envoy advisor AND war advisor dead -> any
##      living cabinet member carries the answer; whole cabinet dead ->
##      Gazette "WORD FROM THE {foe}" story. The promised answer never
##      dies in silence.
##   2. war-counsel plea fallback: no living war advisor -> the Treasury
##      Advisor carries the plea in their own voice (was: silent return).
##   3. war ends while the envoy rides -> the ruler gets the envoy's
##      empty-handed return spoken (was: offer erased in silence).
##   4. two pending pleas from one advisor: text naming a faction routes to
##      THAT war's plea; a bare verdict with several pleas open asks
##      "which war?" instead of answering the first in dict order.
##   5. stale clarifications expire after 3 days (was 5).


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Ruler's Voice dead-end tests ===")
	_test_terms_answer_envoy_dead_war_advisor_dead_treasury_speaks()
	_test_terms_answer_all_cabinet_dead_gazette_accept()
	_test_terms_answer_all_cabinet_dead_gazette_refuse_once()
	_test_terms_answer_normal_path_unchanged()
	_test_plea_tier_no_war_advisor_treasury_carries()
	_test_plea_tier_no_advisors_at_all()
	_test_envoy_returns_war_ended()
	_test_envoy_returns_war_ended_envoy_dead()
	_test_pending_plea_two_wars_named_routing()
	_test_pending_plea_two_wars_bare_verdict_ambiguous()
	_test_pending_plea_named_other_faction_falls_through()
	_test_pending_plea_single_unchanged()
	_test_plea_foe_list()
	_test_clarification_expires_after_3_days()
	_test_clarification_fresh_survives()
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
func _make_world(factions: Array[String] = ["humans", "elves", "ogres"]) -> Array:
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
	gs.add_building({"type": "town_hall", "faction": "ogres", "town_id": 3,
		"position": Vector2(500, 3000), "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
	gs.resources.add_resource("humans", "gold", 5000.0, true)
	gs.resources.add_resource("humans", "wood", 5000.0, true)
	gs.resources.add_resource("humans", "oil", 5000.0, true)
	gs.resources.add_resource("humans", "food", 5000.0, true)
	return [gs, rv]


func _advisor(gs: GameState, faction: String, job: String) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "job": job,
		"town_id": 1, "position": Vector2(2000, 2010), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0,
		"name": "Test Advisor"})
	u["is_advisor"] = true
	return u


func _kill(gs: GameState, u: Dictionary) -> void:
	# add_unit stores a duplicate(); only the stored record's flag counts.
	gs.kill_unit(int(u.get("id", 0)))


## Advance the sim clock to day n (headless tests set game_time directly,
## which does NOT advance day_number — so set both) and fire the daily
## signal the counsel listens to.
func _day(gs: GameState, n: int) -> void:
	gs.game_time = Config.DAY_LENGTH_SECONDS * float(maxi(0, n - 1))
	gs.day_number = n
	gs.bus.day_changed.emit(n, false)


## Seed a minimal war record the counsel machinery can read.
func _seed_war(rv: SimRulersVoice, foe: String) -> String:
	var key := "humans|%s" % foe
	rv._wars[key] = {
		"foe": foe, "start_day": 1,
		"ours_dead": 0, "theirs_dead": 0,
		"towns0": {}, "mons0": {}, "crys0": {},
		"halls0": {"ours": 1, "theirs": 1},
		"gold_hist": [5000.0, 5000.0, 5000.0],
		"fallen": [], "fallen_report_day": -99, "we_sued": false,
		"score": 0.0, "prev_score": 0.0,
	}
	return key


func _last_text(phone) -> String:
	var sent: Array = (phone as _StubPhone).sent
	if sent.is_empty():
		return ""
	return String(sent[sent.size() - 1].get("text", ""))


func _story_headlines(court) -> Array:
	var out: Array = []
	for s: Dictionary in (court as _StubCourt).stories:
		out.append(String(s.get("headline", "")))
	return out


## --- 1. envoy answer fallbacks ----------------------------------------------

func _test_terms_answer_envoy_dead_war_advisor_dead_treasury_speaks() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	gs.diplomacy.declare_war("humans", "elves", "test")
	var envoy := _advisor(gs, "humans", "advisor_civic")
	var treas := _advisor(gs, "humans", "advisor_economy")
	var key := _seed_war(rv, "elves")
	_kill(gs, envoy)
	# No war advisor spawned at all.
	var pt := {"advisor_id": int(envoy.get("id", 0)), "state": "offered",
		"day": 1, "foe": "elves", "amount": 500}
	rv._deliver_terms_answer(key, pt, "elves", 500, {"verdict": "accept"})
	var sent: Array = (gs.phone_sys as _StubPhone).sent
	_check("terms-envoy-dead: message still sent",
		not sent.is_empty())
	if not sent.is_empty():
		_check("terms-envoy-dead: treasury advisor carries it",
			int(sent[sent.size() - 1].get("unit_id", 0))
				== int(treas.get("id", 0)))
	_check("terms-envoy-dead: text says ACCEPT",
		_last_text(gs.phone_sys).contains("ACCEPT"))
	_check("terms-envoy-dead: war still ended",
		gs.diplomacy.relation_state("humans", "elves") != "war")


func _test_terms_answer_all_cabinet_dead_gazette_accept() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	gs.diplomacy.declare_war("humans", "elves", "test")
	var envoy := _advisor(gs, "humans", "advisor_civic")
	_kill(gs, envoy)
	# No other advisors exist at all.
	var key := _seed_war(rv, "elves")
	var pt := {"advisor_id": int(envoy.get("id", 0)), "state": "offered",
		"day": 1, "foe": "elves", "amount": 500}
	rv._deliver_terms_answer(key, pt, "elves", 500, {"verdict": "accept"})
	_check("terms-all-dead: Gazette story published",
		_story_headlines(gs.court_sys).has("WORD FROM THE ELVES"))
	_check("terms-all-dead: no phantom unit-0 message",
		(gs.phone_sys as _StubPhone).sent.is_empty())
	_check("terms-all-dead: war still ended",
		gs.diplomacy.relation_state("humans", "elves") != "war")


func _test_terms_answer_all_cabinet_dead_gazette_refuse_once() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	gs.diplomacy.declare_war("humans", "elves", "test")
	var envoy := _advisor(gs, "humans", "advisor_civic")
	_kill(gs, envoy)
	var key := _seed_war(rv, "elves")
	var pt := {"advisor_id": int(envoy.get("id", 0)), "state": "offered",
		"day": 1, "foe": "elves", "amount": 500}
	rv._deliver_terms_answer(key, pt, "elves", 500, {"verdict": "refuse"})
	var heads := _story_headlines(gs.court_sys)
	var n := 0
	for h: String in heads:
		if h == "PEACE SPURNED":
			n += 1
	_check("terms-refuse-all-dead: exactly one PEACE SPURNED story", n == 1)
	_check("terms-refuse-all-dead: terms erased",
		not rv._peace_terms.has(key))


func _test_terms_answer_normal_path_unchanged() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	gs.diplomacy.declare_war("humans", "elves", "test")
	var envoy := _advisor(gs, "humans", "advisor_civic")
	var treas := _advisor(gs, "humans", "advisor_economy")
	var key := _seed_war(rv, "elves")
	var pt := {"advisor_id": int(envoy.get("id", 0)), "state": "offered",
		"day": 1, "foe": "elves", "amount": 500}
	rv._deliver_terms_answer(key, pt, "elves", 500,
		{"verdict": "counter", "counter": 800})
	var sent: Array = (gs.phone_sys as _StubPhone).sent
	_check("terms-normal: counter delivered by the envoy",
		not sent.is_empty() and int(sent[sent.size() - 1].get("unit_id", 0))
			== int(envoy.get("id", 0)))
	_check("terms-normal: counter text names 800",
		_last_text(gs.phone_sys).contains("800"))
	_check("terms-normal: no Gazette story needed",
		(gs.court_sys as _StubCourt).stories.is_empty())
	_check("terms-normal: treasury advisor untouched",
		int(treas.get("id", 0)) != 0)


## --- 2. war-counsel plea fallback --------------------------------------------

func _test_plea_tier_no_war_advisor_treasury_carries() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var treas := _advisor(gs, "humans", "advisor_economy")
	# No war advisor spawned at all.
	var key := _seed_war(rv, "elves")
	rv._handle_plea_tier(key, {}, "elves", 2,
		["the war burns 500 gold a day"], false)
	var plea: Dictionary = rv._peace_pleas.get(key, {})
	_check("plea-no-war-advisor: plea recorded",
		not plea.is_empty())
	_check("plea-no-war-advisor: treasury advisor carries it",
		int(plea.get("advisor_id", 0)) == int(treas.get("id", 0)))
	_check("plea-no-war-advisor: treasury voice opener",
		_last_text(gs.phone_sys).contains("hear it from the treasury"))


func _test_plea_tier_no_advisors_at_all() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var key := _seed_war(rv, "elves")
	rv._handle_plea_tier(key, {}, "elves", 2,
		["the war burns 500 gold a day"], false)
	_check("plea-no-advisors: no plea recorded, no crash",
		rv._peace_pleas.get(key, {}).is_empty()
			and (gs.phone_sys as _StubPhone).sent.is_empty())


## --- 3. envoy returns empty-handed -------------------------------------------

func _test_envoy_returns_war_ended() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	gs.diplomacy.declare_war("humans", "elves", "test")
	var envoy := _advisor(gs, "humans", "advisor_civic")
	_day(gs, 1)
	rv._peace_terms["humans|elves"] = {"state": "offered", "day": 1,
		"foe": "elves", "amount": 500,
		"advisor_id": int(envoy.get("id", 0))}
	gs.diplomacy.make_peace("humans", "elves")
	_day(gs, 3)
	rv._check_peace_terms()
	_check("envoy-returned: terms erased",
		not rv._peace_terms.has("humans|elves"))
	var sent: Array = (gs.phone_sys as _StubPhone).sent
	_check("envoy-returned: ruler is told",
		not sent.is_empty())
	if not sent.is_empty():
		_check("envoy-returned: envoy carries it",
			int(sent[sent.size() - 1].get("unit_id", 0))
				== int(envoy.get("id", 0)))
	_check("envoy-returned: text names the return",
		_last_text(gs.phone_sys).contains("envoy returns"))


func _test_envoy_returns_war_ended_envoy_dead() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	gs.diplomacy.declare_war("humans", "elves", "test")
	var envoy := _advisor(gs, "humans", "advisor_civic")
	var treas := _advisor(gs, "humans", "advisor_economy")
	_kill(gs, envoy)
	_day(gs, 1)
	rv._peace_terms["humans|elves"] = {"state": "offered", "day": 1,
		"foe": "elves", "amount": 500,
		"advisor_id": int(envoy.get("id", 0))}
	gs.diplomacy.make_peace("humans", "elves")
	_day(gs, 3)
	rv._check_peace_terms()
	var sent: Array = (gs.phone_sys as _StubPhone).sent
	_check("envoy-returned-dead: treasury carries it",
		not sent.is_empty() and int(sent[sent.size() - 1].get("unit_id", 0))
			== int(treas.get("id", 0)))


## --- 4. multi-plea routing -----------------------------------------------------

func _seed_two_pleas(rv: SimRulersVoice, aid: int) -> void:
	rv._peace_pleas["humans|elves"] = {"tier": 2, "state": "pending",
		"advisor_id": aid, "foe": "elves", "day": 1, "had_drain": false}
	rv._peace_pleas["humans|ogres"] = {"tier": 1, "state": "pending",
		"advisor_id": aid, "foe": "ogres", "day": 1, "had_drain": false}


func _test_pending_plea_two_wars_named_routing() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var war := _advisor(gs, "humans", "advisor_war")
	var aid := int(war.get("id", 0))
	_seed_two_pleas(rv, aid)
	var plea := rv._pending_plea_for(aid, "yes, the elves")
	_check("plea-route: named faction routes to its plea",
		String(plea.get("foe", "")) == "elves")
	var plea2 := rv._pending_plea_for(aid, "deny, we fight the ogres")
	_check("plea-route: other named faction routes to its plea",
		String(plea2.get("foe", "")) == "ogres")


func _test_pending_plea_two_wars_bare_verdict_ambiguous() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var war := _advisor(gs, "humans", "advisor_war")
	var aid := int(war.get("id", 0))
	_seed_two_pleas(rv, aid)
	var plea := rv._pending_plea_for(aid, "accept")
	_check("plea-ambiguous: bare verdict flags ambiguous",
		bool(plea.get("ambiguous", false)))
	# The crown is ASKED which war — no plea is answered in dict order.
	var before := String(rv._peace_pleas["humans|elves"].get("state", ""))
	var line := rv.try_order(war, "accept")
	_check("plea-ambiguous: no plea answered silently",
		String(rv._peace_pleas["humans|elves"].get("state", "")) == before)
	_check("plea-ambiguous: ruler asked which war",
		line.contains("Which war"))


func _test_pending_plea_named_other_faction_falls_through() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var war := _advisor(gs, "humans", "advisor_war")
	var aid := int(war.get("id", 0))
	_seed_two_pleas(rv, aid)
	var plea := rv._pending_plea_for(aid, "make peace with the gnomes")
	_check("plea-fallthrough: unknown faction -> no plea match",
		plea.is_empty())


func _test_pending_plea_single_unchanged() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var war := _advisor(gs, "humans", "advisor_war")
	var aid := int(war.get("id", 0))
	rv._peace_pleas["humans|elves"] = {"tier": 2, "state": "pending",
		"advisor_id": aid, "foe": "elves", "day": 1, "had_drain": false}
	var plea := rv._pending_plea_for(aid, "accept")
	_check("plea-single: one plea answers directly",
		String(plea.get("foe", "")) == "elves"
			and not bool(plea.get("ambiguous", false)))
	# phone_ui's one-arg call still works (default t="").
	var plea1 := rv._pending_plea_for(aid)
	_check("plea-single: one-arg call unchanged",
		String(plea1.get("foe", "")) == "elves")


func _test_plea_foe_list() -> void:
	var parts := _make_world()
	var rv: SimRulersVoice = parts[1]
	var names := rv._plea_foe_list({"ambiguous": true,
		"pleas": [{"foe": "elves"}, {"foe": "ogres"}]})
	_check("plea-foe-list: two foes joined",
		names == "Elves and Ogres")
	var names3 := rv._plea_foe_list({"ambiguous": true,
		"pleas": [{"foe": "elves"}, {"foe": "ogres"}, {"foe": "undead"}]})
	_check("plea-foe-list: three foes oxford",
		names3 == "Elves, Ogres, and Undead")


## --- 5. stale clarifications ---------------------------------------------------

func _test_clarification_expires_after_3_days() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var unit := {"id": 42}
	rv._clarifications["42"] = {"question": "which monastery?",
		"kind": "guard_monastery", "day": 1}
	gs.day_number = 5  # age 4 > 3 -> expired
	var ctx := rv._clarification_for(unit)
	_check("clarify: 4-day-old hold expires", ctx.is_empty())
	_check("clarify: expired hold erased from dict",
		not rv._clarifications.has("42"))


func _test_clarification_fresh_survives() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var unit := {"id": 42}
	rv._clarifications["42"] = {"question": "which monastery?",
		"kind": "guard_monastery", "day": 1}
	gs.day_number = 3  # age 2 -> survives
	var ctx := rv._clarification_for(unit)
	_check("clarify: 2-day-old hold survives", not ctx.is_empty())
	gs.day_number = 4  # age 3 -> "older than 3 days" is false, survives
	var ctx2 := rv._clarification_for(unit)
	_check("clarify: exactly-3-day hold survives", not ctx2.is_empty())


## Minimal phone stand-in: records messages for assertion.
class _StubPhone:
	extends RefCounted
	var _gs = null
	var sent: Array = []

	func _init(gs) -> void:
		_gs = gs

	func npc_message(unit_id: int, text: String) -> void:
		sent.append({"unit_id": unit_id, "text": text})


## Minimal court stand-in: records Gazette stories for assertion.
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
