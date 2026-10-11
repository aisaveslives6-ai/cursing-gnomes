extends SceneTree
## Cursing Gnomes — Ruler's Voice EXPANSION tests, wave 2 (Jeremy 2026-10-11).
##
## Covers:
##   - proactive advisors: crime / treasury / war-threat offers fire on real
##     thresholds, Accept executes the real system, Deny stands down, no spam
##     (cooldowns), nothing happens without the ruler's word (sovereignty).
##   - phone control: laws (gambling/alehouses/dueling), curfew, borders via
##     advisor orders -> real policies.
##   - military command: attack orders execute at war (deploy_for_war),
##     "raid their mines" resolves the single war, declare war stays
##     proposal-gated, "defend" digs troops in.
##   - inter-advisor bus: priority ordering (urgent jumps queue), per-day cap,
##     cooldowns prevent spam; war start spreads the word through the cabinet.
##   - envoys: "tell X to Y" reaches officials (urgent bus), foreign leaders
##     (voiced reply + report-back), unknown recipients refused.
##   - save/load round-trip of the new state.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_rulers_voice_proactive.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Ruler's Voice proactive/envoy tests ===")
	_test_proactive_crime_fires()
	_test_proactive_crime_accept()
	_test_proactive_crime_deny_no_action()
	_test_proactive_crime_no_spam()
	_test_proactive_treasury_fires_and_accept()
	_test_proactive_threat_fires_and_accept()
	_test_no_proactive_when_calm()
	_test_sovereignty_nothing_without_word()
	_test_law_orders()
	_test_law_income_real()
	_test_curfew_orders()
	_test_borders_orders()
	_test_foreign_cabinet_refuses_new_verbs()
	_test_attack_order_executes_at_war()
	_test_raid_resolves_single_war()
	_test_declare_war_stays_gated()
	_test_defend_order()
	_test_war_word_spreads_cabinet()
	_test_bus_priority_urgent_first()
	_test_bus_cooldown()
	_test_envoy_official()
	_test_envoy_leader()
	_test_envoy_unknown()
	_test_save_roundtrip()
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


## Player = humans. Hall + town + funded. Stub diplomacy/crime/leaders.
func _make_world(factions: Array[String] = ["humans", "elves", "ogres"]) -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)  # player = humans
	gs.set_ruler_name("ass")
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.hiring = GuildHiring.new(gs)
	gs.army = SimArmy.new(gs)
	var court := _StubCourt.new(gs)
	gs.court_sys = court
	court.crime = _StubCrime.new()
	gs.diplomacy = _StubDiplomacy.new()
	gs.faction_leaders = _StubLeaders.new()
	gs.proposals = SimProposals.new(gs)
	gs.phone_sys = _StubPhone.new(gs)
	var rv := SimRulersVoice.new(gs)
	gs.rulers_voice = rv
	gs.found_town("humans", "Testville", Vector2(2000, 2000))
	gs.add_building({"type": "town_hall", "faction": "humans", "town_id": 1,
		"position": Vector2(2000, 2000), "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
	_fund(gs, "humans", 5000.0, 5000.0)
	return [gs, rv]


func _free_world(parts: Array) -> void:
	var gs: GameState = parts[0]
	gs.queue_free()


func _fund(gs: GameState, faction: String, gold: float, wood: float) -> void:
	gs.resources.add_resource(faction, "gold", gold, true)
	gs.resources.add_resource(faction, "wood", wood, true)
	gs.resources.add_resource(faction, "oil", gold, true)
	gs.resources.add_resource(faction, "food", gold, true)


func _advisor(gs: GameState, faction: String, job: String) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "job": job,
		"town_id": 1, "position": Vector2(2000, 2010), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0,
		"name": "Test " + job})
	u["is_advisor"] = true
	return u


func _soldiers(gs: GameState, n: int) -> void:
	for i: int in n:
		gs.add_unit({"faction": "humans", "job": "soldier", "town_id": 1,
			"position": Vector2(2000 + i * 10, 2000), "alive": true,
			"hp": 100.0, "max_hp": 100.0, "speed": 95.0})


func _dms_to(phone, unit_id: int) -> Array:
	var out: Array = []
	for m: Dictionary in phone.sent:
		if int(m.get("unit_id", -1)) == unit_id:
			out.append(String(m.get("text", "")))
	return out


func _policies(gs: GameState):
	return gs.court_sys.policies


## --- proactive: crime ---------------------------------------------------------

func _test_proactive_crime_fires() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	gs.court_sys.crime.state["crimesToday"] = 5
	rv._on_day(2, false)
	var dms := _dms_to(gs.phone_sys, int(adv.get("id", 0)))
	var offered := false
	for d: String in dms:
		if d.contains("Crime's getting bad"):
			offered = true
	_check("proactive crime: offer DM sent", offered)
	_check("proactive crime: offer recorded",
		String((rv._proactive.get("crime", {}) as Dictionary).get("state", "")) == "offered")
	_free_world(parts)


func _test_proactive_crime_accept() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	gs.court_sys.crime.state["crimesToday"] = 5
	rv._on_day(2, false)
	var ack: String = rv.try_order(adv, "yes, do it")
	_check("proactive crime: accept ack non-empty", ack != "")
	_check("proactive crime: guard professional via real policies",
		String((_policies(gs).get("state") as Dictionary).get("guard", "")) == "professional")
	_free_world(parts)


func _test_proactive_crime_deny_no_action() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	gs.court_sys.crime.state["crimesToday"] = 5
	rv._on_day(2, false)
	var ack: String = rv.try_order(adv, "no")
	_check("proactive crime: deny ack non-empty", ack != "")
	_check("proactive crime: deny leaves guard alone",
		String((_policies(gs).get("state") as Dictionary).get("guard", "")) == "none")
	# Cooldown: no re-offer the next day.
	gs.phone_sys.sent.clear()
	rv._on_day(3, false)
	var dms := _dms_to(gs.phone_sys, int(adv.get("id", 0)))
	var reoffered := false
	for d: String in dms:
		if d.contains("Crime's getting bad"):
			reoffered = true
	_check("proactive crime: deny cools down (no re-offer)", not reoffered)
	_free_world(parts)


func _test_proactive_crime_no_spam() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	gs.court_sys.crime.state["crimesToday"] = 5
	rv._on_day(2, false)
	rv._on_day(3, false)
	var dms := _dms_to(gs.phone_sys, int(adv.get("id", 0)))
	var n := 0
	for d: String in dms:
		if d.contains("Crime's getting bad"):
			n += 1
	_check("proactive crime: single offer across days", n == 1)
	_free_world(parts)


func _test_proactive_treasury_fires_and_accept() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	gs.resources.add_resource("humans", "gold", -4950.0, true)
	rv._on_day(2, false)
	var dms := _dms_to(gs.phone_sys, int(adv.get("id", 0)))
	var offered := false
	for d: String in dms:
		if d.contains("coffers are nearly bare"):
			offered = true
	_check("proactive treasury: offer DM sent", offered)
	var ack: String = rv.try_order(adv, "yes")
	_check("proactive treasury: accept raises tax via real policies",
		int((_policies(gs).get("state") as Dictionary).get("tax", 0)) == 15)
	_check("proactive treasury: ack mentions tax", ack.to_lower().contains("tax"))
	_free_world(parts)


func _test_proactive_threat_fires_and_accept() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	gs.diplomacy.set_rel("humans", "elves", "hostile")
	_soldiers(gs, 3)
	rv._on_day(2, false)
	var dms := _dms_to(gs.phone_sys, int(adv.get("id", 0)))
	var offered := false
	for d: String in dms:
		if d.contains("massing on the border"):
			offered = true
	_check("proactive threat: offer DM sent", offered)
	var ack: String = rv.try_order(adv, "yes")
	_check("proactive threat: accept ack non-empty", ack != "")
	_check("proactive threat: ack mentions muster/footing",
		ack.to_lower().contains("muster") or ack.to_lower().contains("footing"))
	_free_world(parts)


func _test_no_proactive_when_calm() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	gs.court_sys.crime.state["crimesToday"] = 0
	rv._on_day(2, false)
	_check("proactive: silence when calm", gs.phone_sys.sent.is_empty())
	_free_world(parts)


func _test_sovereignty_nothing_without_word() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_advisor(gs, "humans", "advisor_civic")
	gs.court_sys.crime.state["crimesToday"] = 9
	# Three days pass with no answer: the advisor asks, never acts.
	rv._on_day(2, false)
	rv._on_day(3, false)
	rv._on_day(4, false)
	_check("sovereignty: no unprompted guard change",
		String((_policies(gs).get("state") as Dictionary).get("guard", "")) == "none")
	_check("sovereignty: no unprompted curfew",
		not bool((_policies(gs).get("state") as Dictionary).get("curfew", false)))
	_free_world(parts)


## --- phone control ------------------------------------------------------------

func _test_law_orders() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var ack: String = rv.try_order(adv, "legalize gambling")
	_check("laws: legalize ack non-empty", ack != "")
	_check("laws: gambling legal in real policies",
		_policies(gs).law_allowed("gambling"))
	var ack2: String = rv.try_order(adv, "ban gambling")
	_check("laws: ban ack non-empty", ack2 != "")
	_check("laws: gambling banned in real policies",
		not _policies(gs).law_allowed("gambling"))
	_free_world(parts)


func _test_law_income_real() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	# A few citizens so vice pays.
	for i: int in 10:
		gs.add_unit({"faction": "humans", "job": "farmer", "town_id": 1,
			"position": Vector2(2000 + i, 2000), "alive": true,
			"hp": 100.0, "max_hp": 100.0, "speed": 95.0})
	rv.try_order(adv, "legalize gambling")
	_check("laws: income positive with citizens",
		_policies(gs).law_income() > 0)
	# Drain below the treasury cap (daily income respects the cap, like taxes).
	gs.resources.add_resource("humans", "gold", -4950.0, true)
	var before: float = gs.resources.get_amount("humans", "gold")
	_policies(gs).daily_tick()
	_check("laws: daily tick pays the crown",
		gs.resources.get_amount("humans", "gold") > before)
	_free_world(parts)


func _test_curfew_orders() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	rv.try_order(adv, "impose a curfew")
	_check("curfew: imposed via real policies",
		bool((_policies(gs).get("state") as Dictionary).get("curfew", false)))
	rv.try_order(adv, "lift the curfew")
	_check("curfew: lifted via real policies",
		not bool((_policies(gs).get("state") as Dictionary).get("curfew", false)))
	_free_world(parts)


func _test_borders_orders() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	rv.try_order(adv, "close the borders")
	_check("borders: closed via real policies",
		String((_policies(gs).get("state") as Dictionary).get("borders", "")) == "closed")
	rv.try_order(adv, "open the borders")
	_check("borders: opened via real policies",
		String((_policies(gs).get("state") as Dictionary).get("borders", "")) == "open")
	_free_world(parts)


func _test_foreign_cabinet_refuses_new_verbs() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "elves", "advisor_economy")
	var ack: String = rv.try_order(adv, "legalize gambling")
	_check("foreign: new verbs refused", ack != "")
	_check("foreign: law untouched",
		not _policies(gs).law_allowed("gambling"))
	_free_world(parts)


## --- military command ---------------------------------------------------------

func _test_attack_order_executes_at_war() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	_soldiers(gs, 4)
	for i: int in 2:
		gs.add_unit({"faction": "elves", "job": "soldier", "town_id": 2,
			"position": Vector2(500 + i * 10, 500), "alive": true,
			"hp": 100.0, "max_hp": 100.0, "speed": 95.0})
	gs.diplomacy.set_rel("humans", "elves", "war")
	var ack: String = rv.try_order(adv, "attack the elves")
	_check("attack: ack non-empty", ack != "")
	var deployed := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == "humans" \
				and String(u.get("job", "")) == "soldier" \
				and bool(u.get("deployed_for_war", false)):
			deployed += 1
	_check("attack: troops deployed for real", deployed > 0)
	_check("attack: no new proposal (already at war)",
		gs.proposals.proposals.is_empty())
	_free_world(parts)


func _test_raid_resolves_single_war() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	_soldiers(gs, 3)
	gs.diplomacy.set_rel("humans", "elves", "war")
	var ack: String = rv.try_order(adv, "raid their mines")
	_check("raid: ack non-empty", ack != "")
	_check("raid: not the 'attack WHOM' dead-end",
		not ack.contains("attack WHOM"))
	_free_world(parts)


func _test_declare_war_stays_gated() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var ack: String = rv.try_order(adv, "declare war on the ogres")
	var found := false
	var is_open := false
	for p: Dictionary in gs.proposals.proposals:
		if String(p.get("kind", "")) == "declare_war":
			found = true
			is_open = String(p.get("status", "")) == "open"
	_check("declare war: proposal created", found)
	_check("declare war: still open (never surprise)", is_open)
	var deployed := 0
	for u: Dictionary in gs.units:
		if bool(u.get("deployed_for_war", false)):
			deployed += 1
	_check("declare war: no troops move before approval", deployed == 0)
	_free_world(parts)


func _test_defend_order() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	_soldiers(gs, 3)
	var ack: String = rv.try_order(adv, "defend the north pass")
	_check("defend: ack non-empty", ack != "")
	_check("defend: ack mentions holding/digging in",
		ack.to_lower().contains("dig in") or ack.to_lower().contains("holding"))
	_free_world(parts)


## --- inter-advisor bus --------------------------------------------------------

func _test_war_word_spreads_cabinet() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var war := _advisor(gs, "humans", "advisor_war")
	var tre := _advisor(gs, "humans", "advisor_economy")
	var civ := _advisor(gs, "humans", "advisor_civic")
	var gld := _advisor(gs, "humans", "guild_master")
	# The ruler's war declaration is approved -> cabinet hears it.
	rv._on_proposal_decided({"kind": "declare_war", "faction": "humans",
		"details": {"target": "elves"}}, true)
	rv._on_day(2, false)  # bus dispatches
	var heard := 0
	for uid: int in [int(tre.get("id", 0)), int(civ.get("id", 0)),
			int(gld.get("id", 0))]:
		for d: String in _dms_to(gs.phone_sys, uid):
			if d.contains("War with the"):
				heard += 1
	_check("war word: all three cabinet desks notified", heard == 3)
	var summary := false
	for d: String in _dms_to(gs.phone_sys, int(war.get("id", 0))):
		if d.contains("The word's gone out"):
			summary = true
	_check("war word: ruler gets the summary", summary)
	_free_world(parts)


func _test_bus_priority_urgent_first() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var a := _advisor(gs, "humans", "advisor_war")
	var b := _advisor(gs, "humans", "advisor_economy")
	var aid := int(a.get("id", 0))
	var bid := int(b.get("id", 0))
	# Five routine notes, then one urgent — urgent must jump the queue.
	for i: int in 5:
		rv.abus_send(aid, bid, "routine %d" % i, SimRulersVoice.ABUS_ROUTINE, "r%d" % i)
	rv.abus_send(aid, bid, "WAR NEWS", SimRulersVoice.ABUS_URGENT, "war")
	rv._abus_dispatch()
	var dms := _dms_to(gs.phone_sys, bid)
	_check("bus: urgent delivered day one",
		dms.size() > 0 and String(dms[0]).contains("WAR NEWS"))
	_check("bus: routine capped at 3/day", dms.size() == 4)  # urgent + 3
	rv._abus_dispatch()
	var dms2 := _dms_to(gs.phone_sys, bid)
	_check("bus: remainder flows next day", dms2.size() == 6)
	_free_world(parts)


func _test_bus_cooldown() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var a := _advisor(gs, "humans", "advisor_war")
	var b := _advisor(gs, "humans", "advisor_economy")
	var ok1: bool = rv.abus_send(int(a.get("id", 0)), int(b.get("id", 0)),
		"report", SimRulersVoice.ABUS_NORMAL, "treasury_report")
	var ok2: bool = rv.abus_send(int(a.get("id", 0)), int(b.get("id", 0)),
		"report again", SimRulersVoice.ABUS_NORMAL, "treasury_report")
	_check("bus: first send accepted", ok1)
	_check("bus: duplicate topic cooled down", not ok2)
	_free_world(parts)


## --- envoys -------------------------------------------------------------------

func _test_envoy_official() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var tre := _advisor(gs, "humans", "advisor_economy")
	var gld := _advisor(gs, "humans", "guild_master")
	var ack: String = rv.try_order(tre, "tell the guild master to prioritize weapons")
	_check("envoy: dispatch ack non-empty", ack != "")
	_check("envoy: ack names the carrier run", ack.to_lower().contains("carry"))
	# The message rode the urgent bus lane.
	rv._on_day(2, false)
	var carried := false
	for d: String in _dms_to(gs.phone_sys, int(gld.get("id", 0))):
		if d.contains("prioritize weapons"):
			carried = true
	_check("envoy: official receives the words", carried)
	# And the carrier reports back to the ruler.
	var reported := false
	for d: String in _dms_to(gs.phone_sys, int(tre.get("id", 0))):
		if d.contains("Word back"):
			reported = true
	_check("envoy: carrier reports back", reported)
	_free_world(parts)


func _test_envoy_leader() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var tre := _advisor(gs, "humans", "advisor_economy")
	var ack: String = rv.try_order(tre, "tell the ogre leader we accept their tribute")
	_check("envoy: leader dispatch ack non-empty", ack != "")
	var sent := false
	for m: Dictionary in gs.phone_sys.leader_sent:
		if String(m.get("faction", "")) == "ogres":
			sent = true
	_check("envoy: message sent to the foreign leader", sent)
	rv._on_day(2, false)
	var reported := false
	for d: String in _dms_to(gs.phone_sys, int(tre.get("id", 0))):
		if d.contains("leader answers"):
			reported = true
	_check("envoy: leader reaction reported back", reported)
	_free_world(parts)


func _test_envoy_unknown() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var tre := _advisor(gs, "humans", "advisor_economy")
	var ack: String = rv.try_order(tre, "tell the moon king to dance")
	_check("envoy: unknown recipient refused plainly",
		ack.contains("don't know"))
	_free_world(parts)


func _test_save_roundtrip() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var a := _advisor(gs, "humans", "advisor_war")
	var b := _advisor(gs, "humans", "advisor_economy")
	rv._proactive["crime"] = {"state": "offered", "day": 2,
		"advisor_id": int(b.get("id", 0)), "action": "guards"}
	rv.abus_send(int(a.get("id", 0)), int(b.get("id", 0)), "hello",
		SimRulersVoice.ABUS_NORMAL, "t")
	rv._envoys.append({"carrier_id": int(a.get("id", 0)), "kind": "npc",
		"rid": 7, "message": "hi", "day": 2, "state": "sent"})
	var data: Dictionary = rv.to_dict()
	var rv2 := SimRulersVoice.new(gs)
	rv2.from_dict(data)
	_check("save: proactive survives",
		String((rv2._proactive.get("crime", {}) as Dictionary).get("state", "")) == "offered")
	_check("save: bus queue survives", rv2._abus.size() == 1)
	_check("save: envoys survive", rv2._envoys.size() == 1)
	_free_world(parts)


## --- stubs ----------------------------------------------------------------------

class _StubPhone:
	extends RefCounted
	var sent: Array = []
	var leader_sent: Array = []

	func _init(_gs = null) -> void:
		pass

	func npc_message(unit_id: int, text: String) -> void:
		sent.append({"unit_id": unit_id, "text": text})

	func send_leader_message(faction: String, text: String) -> void:
		leader_sent.append({"faction": faction, "text": text})


class _StubCrime:
	extends RefCounted
	var state: Dictionary = {"crimesToday": 0}
	var _crackdown := false

	func crackdown_active() -> bool:
		return _crackdown

	func start_crackdown(days: int = 3) -> void:
		_crackdown = true


class _StubDiplomacy:
	extends RefCounted
	var rels: Dictionary = {}

	func set_rel(a: String, b: String, st: String) -> void:
		rels["%s|%s" % [a, b]] = st
		rels["%s|%s" % [b, a]] = st

	func relation_state(a: String, b: String) -> String:
		return String(rels.get("%s|%s" % [a, b], "neutral"))

	func military_strength(_f: String = "") -> float:
		return 1.0

	func ruler_react_to(_event: String, _data: Dictionary) -> void:
		pass


class _StubLeaders:
	extends RefCounted

	func reply_to(faction: String, player_faction: String, text: String) -> String:
		return "The %s hear you: '%s'. We shall consider it." % [faction, text]


class _StubCourt:
	extends RefCounted
	var policies = null
	var crime = null

	func _init(gs) -> void:
		policies = SimPolicies.new(gs, self)
