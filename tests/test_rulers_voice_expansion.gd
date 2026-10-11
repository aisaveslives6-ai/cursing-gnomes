extends SceneTree
## Cursing Gnomes — Ruler's Voice EXPANSION tests (Jeremy 2026-10-06).
##
## Lane 1 expansion coverage:
##   - multi-part commands ("train 10 soldiers and build 3 farms")
##   - diplomacy verbs: make peace (proposal flow), send tribute,
##     threaten (diplomacy path)
##   - scouting verb ("scout the elves")
##   - construction detail: wall-around-town, oil pumps
##   - maneuvers: patrol, retreat, guard monastery
##   - clarifying questions ("build a farm" -> "which town?")
##   - status queries with real numbers (war/food/army/treasury)
##   - foreign cabinets still refuse the new verbs (sovereignty)
##   - war orders stay proposal-gated even inside multi-part commands
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_rulers_voice_expansion.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Ruler's Voice expansion tests ===")
	_test_multi_build_train()
	_test_multi_tax_festival()
	_test_multi_partial_falls_back()
	_test_multi_war_stays_gated()
	_test_peace_opens_proposal()
	_test_peace_not_at_war()
	_test_peace_asks_faction()
	_test_tribute_send()
	_test_tribute_default_amount()
	_test_tribute_asks_faction()
	_test_threaten()
	_test_threaten_at_war_refused()
	_test_scout_dispatch_and_report()
	_test_scout_asks_faction()
	_test_build_wall_around_town()
	_test_build_oil_pumps()
	_test_patrol_dispatch()
	_test_patrol_recall()
	_test_retreat()
	_test_guard_monastery()
	_test_clarify_build_town()
	_test_status_war()
	_test_status_food()
	_test_status_army()
	_test_status_treasury()
	_test_status_realm()
	_test_foreign_refuses_new_verbs()
	_test_clarification_save_roundtrip()
	_test_patrol_save_roundtrip()
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
func _make_world(factions: Array[String] = ["humans", "elves", "gnomes"]) -> Array:
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
	gs.add_building({"type": "town_hall", "faction": "gnomes", "town_id": 3,
		"position": Vector2(3500, 500), "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
	_fund(gs, "humans", 5000.0, 5000.0)
	return [gs, rv]


func _fund(gs: GameState, faction: String, gold: float, wood: float) -> void:
	gs.resources.add_resource(faction, "gold", gold, true)
	gs.resources.add_resource(faction, "wood", wood, true)
	gs.resources.add_resource(faction, "oil", gold, true)
	gs.resources.add_resource(faction, "food", gold, true)


## Set an exact gold amount under the storage cap (pay_tribute clamps
## through the cap, so exact-amount assertions need under-cap funding).
func _set_gold(gs: GameState, faction: String, amount: float) -> void:
	gs.resources.add_resource(faction, "gold", -999999.0)
	gs.resources.add_resource(faction, "gold", amount)


func _advisor(gs: GameState, faction: String, job: String) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "job": job,
		"town_id": 1, "position": Vector2(2000, 2010), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0,
		"name": "Test Advisor"})
	u["is_advisor"] = true
	return u


func _soldier(gs: GameState, faction: String, town: int,
		pos: Vector2) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": "soldier",
		"town_id": town, "position": pos, "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0})


func _monasteries(gs: GameState) -> SimMonasteries:
	var mons := SimMonasteries.new()
	mons.setup(gs)
	gs.monasteries = mons
	return mons


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


## --- multi-part commands --------------------------------------------------


func _test_multi_build_train() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	_barracks(gs)
	var before := gs.buildings.size()
	var ack := rv.try_order(adv, "train 10 soldiers and build 2 farms")
	_check("multi: consolidated ack", ack != "")
	var farms := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "farm" \
				and bool(b.get("player_placed", false)):
			farms += 1
	_check("multi: build part executed (2 farms)",
		gs.buildings.size() == before + 2 and farms == 2)
	_check("multi: train part set priority",
		String(gs.hiring.get_recruit_priority("humans")) == "soldier")
	_check("multi: ack covers both",
		ack.to_lower().contains("farm") and ack.to_lower().contains("soldier"))
	_free_world(parts)


func _test_multi_tax_festival() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	var pol = gs.court_sys.policies
	var before: int = int((pol.get("state") as Dictionary).get("tax", 10))
	var ack := rv.try_order(adv, "raise taxes and hold a festival")
	var after: int = int((pol.get("state") as Dictionary).get("tax", 10))
	_check("multi tax: raised", after > before)
	_check("multi festival: ack mentions festival",
		ack.to_lower().contains("festival"))
	_free_world(parts)


func _test_multi_partial_falls_back() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	# "the ogres" alone isn't an order -> whole text handled as one order.
	var ack := rv.try_order(adv, "attack the elves and the ogres")
	_check("multi partial: war order still gated",
		ack != "" and ack.to_lower().contains("war council"))
	_check("multi partial: proposal filed",
		not gs.proposals.proposals.is_empty())
	_free_world(parts)


func _test_multi_war_stays_gated() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var before := gs.buildings.size()
	var ack := rv.try_order(adv, "attack the elves and build 3 farms")
	_check("multi war: both parts acknowledged", ack != "")
	_check("multi war: farms built", gs.buildings.size() == before + 3)
	_check("multi war: proposal filed, not executed",
		not gs.proposals.proposals.is_empty())
	_check("multi war: no surprise war",
		gs.diplomacy.relation_state("humans", "elves") != "war")
	_free_world(parts)


## --- diplomacy verbs ------------------------------------------------------


func _test_peace_opens_proposal() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	gs.diplomacy.declare_war("humans", "elves", "test")
	var ack := rv.try_order(adv, "make peace with the elves")
	_check("peace: ack non-empty", ack != "")
	var found := false
	for p: Dictionary in gs.proposals.proposals:
		if String(p.get("kind", "")) == "sue_for_peace" \
				and String((p.get("details", {}) as Dictionary).get("target", "")) == "elves":
			found = true
	_check("peace: sue_for_peace proposal filed", found)
	_check("peace: not executed without approval",
		gs.diplomacy.relation_state("humans", "elves") == "war")
	_free_world(parts)


func _test_peace_not_at_war() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var ack := rv.try_order(adv, "make peace with the elves")
	_check("peace not at war: plain refusal",
		ack != "" and ack.to_lower().contains("not at war"))
	_check("peace not at war: no proposal",
		gs.proposals.proposals.is_empty())
	_free_world(parts)


func _test_peace_asks_faction() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	gs.diplomacy.declare_war("humans", "elves", "test")
	var q := rv.try_order(adv, "make peace")
	_check("peace: asks which faction",
		q != "" and q.to_lower().contains("whom"))
	_check("peace: order held pending",
		not (rv._clarifications as Dictionary).is_empty())
	var ack := rv.try_order(adv, "the elves")
	var found := false
	for p: Dictionary in gs.proposals.proposals:
		if String(p.get("kind", "")) == "sue_for_peace":
			found = true
	_check("peace: resumes on answer", found and ack != "")
	_free_world(parts)


func _test_tribute_send() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	_set_gold(gs, "humans", 1000.0)
	_set_gold(gs, "gnomes", 0.0)
	var h0 = gs.resources.get_amount("humans", "gold")
	var g0 = gs.resources.get_amount("gnomes", "gold")
	var ack := rv.try_order(adv, "send the gnomes 100 gold tribute")
	_check("tribute: ack non-empty", ack != "")
	_check("tribute: gold moved",
		gs.resources.get_amount("humans", "gold") == h0 - 100.0 \
		and gs.resources.get_amount("gnomes", "gold") == g0 + 100.0)
	_check("tribute: ack cites amount", ack.contains("100"))
	_free_world(parts)


func _test_tribute_default_amount() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	_set_gold(gs, "humans", 1000.0)
	var h0 = gs.resources.get_amount("humans", "gold")
	rv.try_order(adv, "send the elves tribute")
	_check("tribute default: 100 gold sent",
		gs.resources.get_amount("humans", "gold") == h0 - 100.0)
	_free_world(parts)


func _test_tribute_asks_faction() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var q := rv.try_order(adv, "send 50 gold tribute")
	_check("tribute: asks whom",
		q != "" and q.to_lower().contains("whom"))
	_set_gold(gs, "humans", 1000.0)
	var h0 = gs.resources.get_amount("humans", "gold")
	var ack := rv.try_order(adv, "the gnomes")
	_check("tribute: resumes with stored amount",
		ack.contains("50") \
		and gs.resources.get_amount("humans", "gold") == h0 - 50.0)
	_free_world(parts)


func _test_threaten() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var s1: float = gs.diplomacy.relation_score("humans", "elves")
	var ack := rv.try_order(adv, "threaten the elves")
	_check("threaten: ack non-empty", ack != "")
	_check("threaten: relation score drops",
		gs.diplomacy.relation_score("humans", "elves") < s1)
	_check("threaten: no war declared by the threat itself",
		gs.diplomacy.relation_state("humans", "elves") != "war")
	_free_world(parts)


func _test_threaten_at_war_refused() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	gs.diplomacy.declare_war("humans", "elves", "test")
	var ack := rv.try_order(adv, "threaten the elves")
	_check("threaten at war: told to save breath",
		ack != "" and ack.to_lower().contains("already at war"))
	_free_world(parts)


## --- scouting -------------------------------------------------------------


func _test_scout_dispatch_and_report() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var ack := rv.try_order(adv, "scout the elves")
	_check("scout: ack non-empty", ack != "")
	var tracked := false
	for o: Dictionary in rv._pending:
		if String(o.get("kind", "")) == "scout" \
				and String(o.get("foe", "")) == "elves":
			tracked = true
	_check("scout: dispatch tracked", tracked)
	# Two days later the riders report back with intel.
	gs.day_number = 3
	gs.bus.day_changed.emit(3, false)
	var phone = gs.phone_sys
	var got := false
	for m: Dictionary in phone.sent:
		var txt := String(m.get("text", "")).to_lower()
		if txt.contains("scout") and txt.contains("elves"):
			got = true
	_check("scout: intel DM arrives", got)
	_free_world(parts)


func _test_scout_asks_faction() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var q := rv.try_order(adv, "scout")
	_check("scout: asks whom", q != "" and q.to_lower().contains("whom"))
	var ack := rv.try_order(adv, "the elves")
	_check("scout: resumes on answer", ack.to_lower().contains("riders"))
	_free_world(parts)


## --- construction detail --------------------------------------------------


func _test_build_wall_around_town() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	var ack := rv.try_order(adv, "build a wall around my town")
	_check("wall around: routed to civic",
		rv._match_order(rv._norm("build a wall around my town")) == "civic")
	_check("wall around: ack non-empty", ack != "")
	_free_world(parts)


func _test_build_oil_pumps() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var before := gs.buildings.size()
	var ack := rv.try_order(adv, "build 2 oil pumps")
	var pumps := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "oil_pump":
			pumps += 1
	_check("oil pumps: 2 blueprints", gs.buildings.size() == before + 2 \
		and pumps == 2)
	_check("oil pumps: ack mentions pump", ack.to_lower().contains("pump"))
	_free_world(parts)


## --- maneuvers ------------------------------------------------------------


func _test_patrol_dispatch() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	for i: int in 4:
		_soldier(gs, "humans", 1, Vector2(2000 + i * 10, 2000))
	var ack := rv.try_order(adv, "patrol the north border")
	_check("patrol: ack non-empty", ack != "")
	var marked := 0
	for u: Dictionary in gs.units:
		var po: Dictionary = u.get("player_order", {})
		if String(po.get("type", "")) == "patrol":
			marked += 1
	_check("patrol: detachment marked", marked == 4)
	_check("patrol: tracked", not (rv._patrols as Dictionary).is_empty())
	# Waypoints rotate on the daily tick (real patrol movement).
	gs.bus.day_changed.emit(2, false)
	var moved := 0
	for u: Dictionary in gs.units:
		var po: Dictionary = u.get("player_order", {})
		if String(po.get("type", "")) == "patrol" \
				and u.get("move_target", null) != null:
			moved += 1
	_check("patrol: waypoints live", moved > 0)
	_free_world(parts)


func _test_patrol_recall() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	for i: int in 3:
		_soldier(gs, "humans", 1, Vector2(2000 + i * 10, 2000))
	rv.try_order(adv, "patrol the border")
	var ack := rv.try_order(adv, "recall the patrol")
	_check("patrol recall: ack", ack.to_lower().contains("recalled"))
	_check("patrol recall: cleared",
		(rv._patrols as Dictionary).is_empty())
	var marked := 0
	for u: Dictionary in gs.units:
		var po: Dictionary = u.get("player_order", {})
		if String(po.get("type", "")) == "patrol":
			marked += 1
	_check("patrol recall: orders lifted", marked == 0)
	_free_world(parts)


func _test_retreat() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var s1 := _soldier(gs, "humans", 1, Vector2(900, 900))
	s1["deployed_for_war"] = true
	var ack := rv.try_order(adv, "retreat the army")
	_check("retreat: ack", ack.to_lower().contains("retreat"))
	_check("retreat: troop withdrawing",
		bool(s1.get("withdrawing", false)))
	_free_world(parts)


func _test_guard_monastery() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var mons := _monasteries(gs)
	mons.monasteries.append({
		"id": 7, "god_id": "auriel",
		"position": Vector2(2500, 2500), "owner": "humans",
		"name": "Monastery of Auriel the Dawnmother",
	})
	for i: int in 5:
		_soldier(gs, "humans", 1, Vector2(2000 + i * 10, 2000))
	var ack := rv.try_order(adv, "guard the monastery")
	_check("guard monastery: ack", ack != "")
	var guards := 0
	for u: Dictionary in gs.units:
		if u.has("monastery_guard"):
			guards += 1
	_check("guard monastery: detachment posted", guards > 0)
	# Losing the monastery reports back.
	mons.monasteries[0]["owner"] = "elves"
	gs.bus.day_changed.emit(4, false)
	var got := false
	for m: Dictionary in (gs.phone_sys as _StubPhone).sent:
		if String(m.get("text", "")).to_lower().contains("lost"):
			got = true
	_check("guard monastery: loss reported", got)
	_free_world(parts)


## --- clarifying questions -------------------------------------------------


func _test_clarify_build_town() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	gs.found_town("humans", "Otherton", Vector2(3000, 3000))
	var q := rv.try_order(adv, "build a farm")
	_check("clarify: asks which town",
		q != "" and q.to_lower().contains("which town"))
	var before := gs.buildings.size()
	var ack := rv.try_order(adv, "Otherton")
	_check("clarify: order resumes", ack.to_lower().contains("farm"))
	_check("clarify: blueprint lands in Otherton",
		gs.buildings.size() == before + 1 \
		and int(gs.buildings[gs.buildings.size() - 1].get("town_id", 0)) == 2)
	_free_world(parts)


## --- status queries -------------------------------------------------------


func _test_status_war() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	gs.diplomacy.declare_war("humans", "elves", "test")
	var key := "humans|elves"
	rv._wars[key] = {
		"foe": "elves", "start_day": 1,
		"ours_dead": 12, "theirs_dead": 4,
		"towns0": {}, "mons0": {}, "crys0": {},
		"halls0": {"ours": 1, "theirs": 1},
		"gold_hist": [5000.0, 5000.0, 5000.0],
	}
	var ack := rv.try_order(adv, "report on the war")
	_check("status war: answered", ack != "")
	_check("status war: real numbers",
		ack.contains("12") and ack.contains("4"))
	_check("status war: names foe", ack.to_lower().contains("elves"))
	_free_world(parts)


func _test_status_food() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var ack := rv.try_order(adv, "how's our food?")
	_check("status food: answered", ack != "")
	_check("status food: per-head figure", ack.contains("per head"))
	_free_world(parts)


func _test_status_army() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	for i: int in 3:
		_soldier(gs, "humans", 1, Vector2(2000 + i * 10, 2000))
	var ack := rv.try_order(adv, "what is my army doing?")
	_check("status army: answered", ack != "")
	_check("status army: troop count", ack.contains("3"))
	_check("status army: stance", ack.to_lower().contains("stance"))
	_free_world(parts)


func _test_status_treasury() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var ack := rv.try_order(adv, "how much gold do we have?")
	_check("status treasury: answered", ack != "")
	_check("status treasury: real gold figure",
		ack.contains(str(int(gs.resources.get_amount("humans", "gold")))))
	_free_world(parts)


func _test_status_realm() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	var ack := rv.try_order(adv, "status report")
	_check("status realm: answered", ack != "")
	_check("status realm: covers gold and wars",
		ack.to_lower().contains("gold") and ack.to_lower().contains("war"))
	_free_world(parts)


## --- sovereignty / safety -------------------------------------------------


func _test_foreign_refuses_new_verbs() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var foreign := _advisor(gs, "elves", "advisor_war")
	var elf_gold0 = gs.resources.get_amount("elves", "gold")
	# Status queries aren't orders: a foreign cabinet stays silent on them
	# ("" -> normal chat), but refuses every order-form verb.
	for line: String in ["threaten the gnomes", "scout the gnomes",
			"make peace with the gnomes", "send the gnomes 100 gold tribute",
			"patrol the north border"]:
		var ack := rv.try_order(foreign, line)
		_check("foreign refuses: " + line, ack != "")
	_check("foreign stays silent on questions",
		rv.try_order(foreign, "report on the war") == "")
	_check("foreign: no proposals filed", gs.proposals.proposals.is_empty())
	_check("foreign: no gold moved",
		gs.resources.get_amount("elves", "gold") == elf_gold0)
	_free_world(parts)


## --- persistence ----------------------------------------------------------


func _test_clarification_save_roundtrip() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	gs.found_town("humans", "Otherton", Vector2(3000, 3000))
	rv.try_order(adv, "build a farm")
	_check("clarify save: pending", not (rv._clarifications as Dictionary).is_empty())
	var d: Dictionary = rv.to_dict()
	var gs2: GameState = parts[0]
	var rv2 := SimRulersVoice.new(gs2)
	rv2.from_dict(d)
	_check("clarify save: survives",
		not (rv2._clarifications as Dictionary).is_empty())
	_free_world(parts)


func _test_patrol_save_roundtrip() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	for i: int in 2:
		_soldier(gs, "humans", 1, Vector2(2000 + i * 10, 2000))
	rv.try_order(adv, "patrol the border")
	_check("patrol save: tracked", not (rv._patrols as Dictionary).is_empty())
	var d: Dictionary = rv.to_dict()
	var rv2 := SimRulersVoice.new(gs)
	rv2.from_dict(d)
	_check("patrol save: survives",
		not (rv2._patrols as Dictionary).is_empty())
	_free_world(parts)


## --- stubs ----------------------------------------------------------------


func _barracks(gs: GameState) -> Dictionary:
	return gs.add_building({"type": "barracks", "faction": "humans",
		"town_id": 1, "position": Vector2(2100, 2000), "alive": true,
		"complete": true, "progress": 1.0, "hp": 800.0, "max_hp": 800.0})


## Minimal phone stand-in: records npc_message calls.
class _StubPhone:
	extends RefCounted
	var _gs = null
	var sent: Array = []

	func _init(gs) -> void:
		_gs = gs

	func npc_message(unit_id: int, text: String) -> void:
		sent.append({"unit_id": unit_id, "text": text})


## Minimal court stand-in: carries a real SimPolicies.
class _StubCourt:
	extends RefCounted
	var policies = null

	func _init(gs) -> void:
		policies = SimPolicies.new(gs, self)
