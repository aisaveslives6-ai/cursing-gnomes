extends SceneTree
## Cursing Gnomes — Ruler's Voice ENVOY MECHANIC tests (Jeremy 2026-10-11).
##
## Covers the inter-advisor briefing layer in rulers_voice.gd:
##   - advisors brief each other on their domains (war burn, coffers,
##     unrest, casualty news, arms) with REAL numbers, through the bus
##   - true priority: urgent jumps routine; routine waits its turn
##   - per-topic cooldowns: no duplicate briefings within 2 days; urgent
##     bypasses the cooldown; independent topics don't block each other
##   - sovereignty: briefings inform, never command — no orders execute
##   - silence in peacetime / calm (no spam)
##   - player visibility: briefings land in the recipient's phone thread
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_rulers_voice_bus.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Ruler's Voice bus/briefing tests ===")
	_test_warburn_briefing_real_numbers()
	_test_coffers_briefing_urgent_when_broke()
	_test_unrest_briefing()
	_test_warnews_briefing_casualties()
	_test_arms_briefing_routine()
	_test_briefing_cooldown_no_duplicates()
	_test_briefing_cooldown_rearms()
	_test_briefing_urgent_bypasses_cooldown()
	_test_briefing_topics_independent()
	_test_briefing_priority_urgent_jumps_routine()
	_test_briefing_sovereignty_no_orders()
	_test_briefing_quiet_in_peacetime()
	_test_briefing_visible_in_thread()
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


func _cabinet(parts: Array) -> Dictionary:
	var gs: GameState = parts[0]
	return {
		"war": _advisor(gs, "humans", "advisor_war"),
		"tre": _advisor(gs, "humans", "advisor_economy"),
		"civ": _advisor(gs, "humans", "advisor_civic"),
		"gld": _advisor(gs, "humans", "guild_master"),
	}


func _at_war(parts: Array) -> void:
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	gs.diplomacy.set_rel("humans", "elves", "war")
	# Seed a war record directly (what _check_war_losses builds on day tick).
	rv._wars["humans|elves"] = {"foe": "elves", "start_day": 1,
		"ours_dead": 0, "theirs_dead": 0,
		"gold_hist": [5000.0, 4000.0, 3000.0, 2000.0]}


func _dms_to(phone, unit_id: int) -> Array:
	var out: Array = []
	for m: Dictionary in phone.sent:
		if int(m.get("unit_id", -1)) == unit_id:
			out.append(String(m.get("text", "")))
	return out


func _thread_has(phone, unit_id: int, needle: String) -> bool:
	for d: String in _dms_to(phone, unit_id):
		if d.contains(needle):
			return true
	return false


## --- briefing content ---------------------------------------------------------

func _test_warburn_briefing_real_numbers() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var cab := _cabinet(parts)
	_at_war(parts)
	gs.resources.add_resource("humans", "gold", -4950.0, true)  # 50g left
	rv._abus_briefings()
	rv._abus_dispatch()
	var tid := int((cab["tre"] as Dictionary).get("id", 0))
	_check("warburn: briefing reaches treasury thread",
		_thread_has(gs.phone_sys, tid, "burns 1000 gold a day"))
	_check("warburn: runway number real",
		_thread_has(gs.phone_sys, tid, "empties in 2 days"))
	_check("warburn: marked from the war advisor",
		_thread_has(gs.phone_sys, tid, "<<From Test advisor_war>>"))
	_free_world(parts)


func _test_coffers_briefing_urgent_when_broke() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var cab := _cabinet(parts)
	_at_war(parts)
	gs.resources.add_resource("humans", "gold", -4950.0, true)
	rv._abus_briefings()
	# Urgent: broke treasury during a war.
	var wid := int((cab["war"] as Dictionary).get("id", 0))
	var urgent := false
	for m: Dictionary in rv._abus:
		if String(m.get("topic", "")) == "brief_coffers":
			urgent = int(m.get("prio", 0)) >= SimRulersVoice.ABUS_URGENT
	_check("coffers: urgent when broke", urgent)
	rv._abus_dispatch()
	_check("coffers: war advisor warned with real gold",
		_thread_has(gs.phone_sys, wid, "coffers hold 50g"))
	_free_world(parts)


func _test_unrest_briefing() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var cab := _cabinet(parts)
	gs.court_sys.crime.state["crimesToday"] = 9
	rv._abus_briefings()
	rv._abus_dispatch()
	var wid := int((cab["war"] as Dictionary).get("id", 0))
	_check("unrest: civic briefs war with real crime count",
		_thread_has(gs.phone_sys, wid, "9 crimes today"))
	_free_world(parts)


func _test_warnews_briefing_casualties() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var cab := _cabinet(parts)
	_at_war(parts)
	var rec: Dictionary = rv._wars["humans|elves"]
	rec["ours_dead"] = 14
	rec["theirs_dead"] = 3
	rv._abus_briefings()
	rv._abus_dispatch()
	var cid := int((cab["civ"] as Dictionary).get("id", 0))
	_check("warnews: casualty numbers real",
		_thread_has(gs.phone_sys, cid, "we've lost 14, they've lost 3"))
	_check("warnews: losing badly flagged urgent",
		_thread_has(gs.phone_sys, cid, "We're bleeding"))
	_free_world(parts)


func _test_arms_briefing_routine() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var cab := _cabinet(parts)
	_at_war(parts)
	rv._abus_briefings()
	var routine := false
	for m: Dictionary in rv._abus:
		if String(m.get("topic", "")) == "brief_arms":
			routine = int(m.get("prio", 9)) == SimRulersVoice.ABUS_ROUTINE
	_check("arms: guild briefing is routine priority", routine)
	rv._abus_dispatch()
	var tid := int((cab["tre"] as Dictionary).get("id", 0))
	_check("arms: reaches treasury thread",
		_thread_has(gs.phone_sys, tid, "Weapons priority"))
	_free_world(parts)


## --- cooldowns / priority -----------------------------------------------------

func _test_briefing_cooldown_no_duplicates() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_cabinet(parts)
	_at_war(parts)
	rv._abus_briefings()
	var n1 := rv._abus.size()
	rv._abus_briefings()  # same day: every stream cooled down
	var n2 := rv._abus.size()
	_check("cooldown: briefing queued once", n1 > 0)
	_check("cooldown: no duplicates same day", n2 == n1)
	_free_world(parts)


func _test_briefing_cooldown_rearms() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_cabinet(parts)
	_at_war(parts)
	rv._abus_briefings()
	var n1 := rv._abus.size()
	gs.day_number = 3  # two days later: cooldowns expire
	rv._abus_briefings()
	_check("cooldown: streams re-arm after 2 days", rv._abus.size() > n1)
	_free_world(parts)


func _test_briefing_urgent_bypasses_cooldown() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var cab := _cabinet(parts)
	_at_war(parts)
	var wid := int((cab["war"] as Dictionary).get("id", 0))
	var tid := int((cab["tre"] as Dictionary).get("id", 0))
	# A normal warburn briefing lands first (cooldown armed)...
	rv.abus_send(wid, tid, "burn memo", SimRulersVoice.ABUS_NORMAL,
		"brief_warburn")
	# ...but an URGENT warburn still jumps through on the same topic.
	var ok: bool = rv.abus_send(wid, tid, "TREASURY COLLAPSING",
		SimRulersVoice.ABUS_URGENT, "brief_warburn")
	_check("cooldown: urgent bypasses topic cooldown", ok)
	_free_world(parts)


func _test_briefing_topics_independent() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_cabinet(parts)
	_at_war(parts)
	gs.resources.add_resource("humans", "gold", -4950.0, true)
	rv._abus_briefings()
	var topics := {}
	for m: Dictionary in rv._abus:
		topics[String(m.get("topic", ""))] = true
	_check("topics: warburn queued", topics.has("brief_warburn"))
	_check("topics: coffers queued alongside", topics.has("brief_coffers"))
	_check("topics: arms queued alongside", topics.has("brief_arms"))
	_free_world(parts)


func _test_briefing_priority_urgent_jumps_routine() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var cab := _cabinet(parts)
	_at_war(parts)
	gs.resources.add_resource("humans", "gold", -4950.0, true)
	var wid := int((cab["war"] as Dictionary).get("id", 0))
	var tid := int((cab["tre"] as Dictionary).get("id", 0))
	# Three routine memos fill the day's lane first...
	for i: int in 3:
		rv.abus_send(wid, tid, "routine %d" % i,
			SimRulersVoice.ABUS_ROUTINE, "r%d" % i)
	# ...then the urgent warburn briefing arrives.
	rv._abus_briefings()
	rv._abus_dispatch()
	var dms := _dms_to(gs.phone_sys, tid)
	_check("priority: urgent briefing delivered first",
		dms.size() > 0 and String(dms[0]).contains("burns 1000 gold a day"))
	# The urgent coffers briefing rode the other way, also jumping the queue.
	_check("priority: urgent coffers briefing delivered",
		_thread_has(gs.phone_sys, wid, "coffers hold 50g"))
	_free_world(parts)


## --- sovereignty / silence / visibility ---------------------------------------

func _test_briefing_sovereignty_no_orders() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_cabinet(parts)
	_at_war(parts)
	gs.resources.add_resource("humans", "gold", -4950.0, true)
	gs.court_sys.crime.state["crimesToday"] = 9
	rv._abus_briefings()
	rv._abus_dispatch()
	_check("sovereignty: briefings create no proposals",
		gs.proposals.proposals.is_empty())
	_check("sovereignty: tax untouched",
		int((gs.court_sys.policies.get("state") as Dictionary).get("tax", 10)) == 10)
	_check("sovereignty: guard untouched",
		String((gs.court_sys.policies.get("state") as Dictionary).get("guard", "none")) == "none")
	var deployed := 0
	for u: Dictionary in gs.units:
		if bool(u.get("deployed_for_war", false)):
			deployed += 1
	_check("sovereignty: no troops move", deployed == 0)
	_free_world(parts)


func _test_briefing_quiet_in_peacetime() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_cabinet(parts)
	gs.court_sys.crime.state["crimesToday"] = 0
	rv._abus_briefings()
	_check("silence: no briefings when calm", rv._abus.is_empty())
	_free_world(parts)


func _test_briefing_visible_in_thread() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var cab := _cabinet(parts)
	_at_war(parts)
	rv._abus_briefings()
	rv._abus_dispatch()
	# Every queued briefing lands in SOME advisor's thread, tagged by sender.
	var tagged := 0
	for m: Dictionary in gs.phone_sys.sent:
		if String(m.get("text", "")).begins_with("<<From "):
			tagged += 1
	_check("visibility: briefings land in recipient threads tagged",
		tagged > 0)
	var tid := int((cab["tre"] as Dictionary).get("id", 0))
	_check("visibility: sender attribution present",
		_thread_has(gs.phone_sys, tid, "<<From "))
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
