extends SceneTree
## Cursing Gnomes — Ruler's Voice headless tests (Jeremy 2026-10-06).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_rulers_voice.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers:
##   - cabinet detection: player advisors + guild master take orders;
##     foreign cabinets refuse (sovereignty); villagers aren't cabinet.
##   - each order family parses and executes with the right args:
##     build (real blueprints, player_placed), train (by_player queue),
##     muster/stand down, war (proposal-gated, never surprise), tax,
##     festival.
##   - validation: unaffordable / unknown -> plain refusal, no promise.
##   - report-back: build completion DMs the advisor's thread; stall
##     watchdog fires.
##   - chit-chat passes through ("") to the normal conversation engine.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Ruler's Voice tests ===")
	_test_cabinet_detection()
	_test_build_order()
	_test_build_unaffordable()
	_test_build_unknown_passthrough()
	_test_train_order()
	_test_train_no_count_sets_priority()
	_test_war_gated_by_proposal()
	_test_war_self_refused()
	_test_muster()
	_test_stand_down()
	_test_tax_raise()
	_test_tax_set_value()
	_test_focus_food()
	_test_festival()
	_test_foreign_refusal()
	_test_chitchat_passthrough()
	_test_report_back_build_done()
	_test_report_back_build_stalled()
	_test_save_roundtrip()
	_test_plea_fires_on_losses()
	_test_plea_accept_sues_for_peace()
	_test_plea_deny_rearms_next_tier()
	_test_plea_no_spam_same_tier()
	_test_plea_command_post_loss()
	_test_treasury_drain_warning()
	_test_strategic_brief()
	_test_proposal_brief_attached()
	_test_war_order_questioned_when_unwise()
	_test_ai_war_no_plea()
	_test_casualty_signal_tracked()
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


func _villager(gs: GameState, faction: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": "farmer", "town_id": 1,
		"position": Vector2(2000, 2020), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "speed": 95.0, "name": "Test Villager"})


func _barracks(gs: GameState) -> Dictionary:
	return gs.add_building({"type": "barracks", "faction": "humans",
		"town_id": 1, "position": Vector2(2100, 2000), "alive": true,
		"complete": true, "progress": 1.0, "hp": 800.0, "max_hp": 800.0})


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


## --- cabinet detection ----------------------------------------------------


func _test_cabinet_detection() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var gm := _advisor(gs, "humans", "guild_master")
	var foreign := _advisor(gs, "elves", "advisor_war")
	var vil := _villager(gs, "humans")
	_check("cabinet: player treasury advisor", SimRulersVoice.is_cabinet(gs, adv))
	_check("cabinet: player guild master", SimRulersVoice.is_cabinet(gs, gm))
	_check("cabinet: foreign advisor is not cabinet",
		not SimRulersVoice.is_cabinet(gs, foreign))
	_check("cabinet: foreign advisor flagged foreign",
		SimRulersVoice.is_foreign_cabinet(gs, foreign))
	_check("cabinet: player advisor not foreign",
		not SimRulersVoice.is_foreign_cabinet(gs, adv))
	_check("cabinet: villager is not cabinet",
		not SimRulersVoice.is_cabinet(gs, vil))
	_free_world(parts)


## --- build orders ---------------------------------------------------------


func _test_build_order() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var before := gs.buildings.size()
	var ack := rv.try_order(adv, "build 3 farms")
	_check("build: ack non-empty", ack != "")
	_check("build: ack mentions farm", ack.to_lower().contains("farm"))
	_check("build: 3 blueprints placed", gs.buildings.size() == before + 3)
	var tagged := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "farm" \
				and bool(b.get("player_placed", false)):
			tagged += 1
	_check("build: blueprints tagged player_placed", tagged == 3)
	_check("build: pending tracked", rv._pending.size() == 1)
	_free_world(parts)


func _test_build_unaffordable() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	# Drain the coffers.
	gs.resources.spend("humans", {"gold": 5000.0, "wood": 5000.0,
		"oil": 5000.0, "food": 5000.0})
	var before := gs.buildings.size()
	var ack := rv.try_order(adv, "build a barracks")
	_check("build broke: refusal non-empty", ack != "")
	_check("build broke: says can't afford",
		ack.to_lower().contains("can't afford"))
	_check("build broke: nothing placed", gs.buildings.size() == before)
	_free_world(parts)


func _test_build_unknown_passthrough() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	_check("build unknown: not an order",
		rv.try_order(adv, "build a moonbase") == "")
	_free_world(parts)


## --- train orders ---------------------------------------------------------


func _test_train_order() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "guild_master")
	_barracks(gs)
	var ack := rv.try_order(adv, "train 5 soldiers")
	_check("train: ack non-empty", ack != "")
	_check("train: ack mentions soldier", ack.to_lower().contains("soldier"))
	_free_world(parts)


func _test_train_no_count_sets_priority() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "guild_master")
	var ack := rv.try_order(adv, "recruit more warriors")
	_check("train priority: ack non-empty", ack != "")
	_check("train priority: mentions warriors",
		ack.to_lower().contains("warrior"))
	_free_world(parts)


## --- military orders ------------------------------------------------------


func _test_war_gated_by_proposal() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var ack := rv.try_order(adv, "attack the elves")
	_check("war: ack non-empty", ack != "")
	_check("war: ack mentions approval/seal",
		ack.to_lower().contains("approv") or ack.to_lower().contains("seal"))
	# A proposal exists and is OPEN — never auto-executed.
	var found := false
	var is_open := false
	for p: Dictionary in gs.proposals.proposals:
		if String(p.get("kind", "")) == "declare_war":
			found = true
			is_open = String(p.get("status", "")) == "open"
	_check("war: proposal created", found)
	_check("war: proposal still open (not surprise war)", is_open)
	_check("war: not already at war",
		gs.diplomacy.relation_state("humans", "elves") != "war")
	_free_world(parts)


func _test_war_self_refused() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var ack := rv.try_order(adv, "attack the humans")
	_check("war self: refused", ack != "")
	_check("war self: no proposal created", gs.proposals.proposals.is_empty())
	_free_world(parts)


func _test_muster() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	# Give the player some soldiers to muster.
	for i: int in 3:
		gs.add_unit({"faction": "humans", "job": "soldier", "town_id": 1,
			"position": Vector2(2000 + i * 10, 2000), "alive": true,
			"hp": 100.0, "max_hp": 100.0, "speed": 95.0})
	var ack := rv.try_order(adv, "muster the army")
	_check("muster: ack non-empty", ack != "")
	_check("muster: ack mentions troops", ack.to_lower().contains("troop"))
	_free_world(parts)


func _test_stand_down() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	var ack := rv.try_order(adv, "stand down")
	_check("stand down: ack non-empty", ack != "")
	_check("stand down: stance set to guard",
		gs.army.get_stance("humans") == "guard")
	_free_world(parts)


## --- economy orders -------------------------------------------------------


func _test_tax_raise() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var before: int = int(gs.court_sys.policies.state.get("tax", 10))
	var ack := rv.try_order(adv, "raise taxes")
	_check("tax: ack non-empty", ack != "")
	_check("tax: raised by 5", int(gs.court_sys.policies.state.get("tax", 0)) == before + 5)
	_free_world(parts)


func _test_tax_set_value() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var ack := rv.try_order(adv, "set taxes to 15")
	_check("tax set: ack non-empty", ack != "")
	_check("tax set: tax is 15", int(gs.court_sys.policies.state.get("tax", 0)) == 15)
	_free_world(parts)


func _test_focus_food() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var ack := rv.try_order(adv, "focus on food")
	_check("focus: ack non-empty", ack != "")
	_check("focus: ack mentions farmers", ack.to_lower().contains("farmer"))
	_free_world(parts)


## --- civic orders ---------------------------------------------------------


func _test_festival() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_civic")
	var ack := rv.try_order(adv, "hold a festival")
	_check("festival: ack non-empty", ack != "")
	_check("festival: ack mentions festival",
		ack.to_lower().contains("festival"))
	_free_world(parts)


## --- sovereignty ----------------------------------------------------------


func _test_foreign_refusal() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var foreign := _advisor(gs, "elves", "advisor_economy")
	var before := gs.buildings.size()
	var ack := rv.try_order(foreign, "build 3 farms")
	_check("foreign: refusal non-empty", ack != "")
	_check("foreign: nothing built for them", gs.buildings.size() == before)
	# Small talk with a foreign advisor is NOT refused.
	_check("foreign: chitchat passes through",
		rv.try_order(foreign, "how are you today") == "")
	_free_world(parts)


func _test_chitchat_passthrough() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	_check("chitchat: not an order", rv.try_order(adv, "how are you") == "")
	_check("chitchat: villager not cabinet",
		rv.try_order(_villager(gs, "humans"), "build 3 farms") == "")
	_free_world(parts)


## --- report-back ----------------------------------------------------------


func _test_report_back_build_done() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	rv.try_order(adv, "build 2 farms")
	_check("report: pending tracked", rv._pending.size() == 1)
	# Complete the blueprints, then tick a day.
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "farm" \
				and not bool(b.get("complete", false)):
			b["complete"] = true
	gs.bus.day_changed.emit(2, false)
	var phone = gs.phone_sys
	_check("report: DM sent", phone.sent.size() == 1)
	_check("report: DM says done",
		String(phone.sent[0].get("text", "")).to_lower().contains("done"))
	_check("report: pending cleared", rv._pending.is_empty())
	_free_world(parts)


func _test_report_back_build_stalled() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	rv.try_order(adv, "build 2 farms")
	# 13 days pass with blueprints incomplete.
	gs.set("day_number", 14)
	gs.bus.day_changed.emit(14, false)
	var phone = gs.phone_sys
	_check("stall: DM sent", phone.sent.size() == 1)
	_check("stall: DM mentions stalled",
		String(phone.sent[0].get("text", "")).to_lower().contains("stall"))
	_free_world(parts)


func _test_save_roundtrip() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	rv.try_order(adv, "build 2 farms")
	var d := rv.to_dict()
	var rv2 := SimRulersVoice.new(gs)
	rv2.from_dict(d)
	_check("save: pending survives", rv2._pending.size() == 1)
	_check("save: kind survives",
		String(rv2._pending[0].get("kind", "")) == "build")
	_free_world(parts)


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


## --- war counsel ------------------------------------------------------------


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
	}
	return key


func _start_test_war(gs: GameState) -> void:
	gs.diplomacy.declare_war("humans", "elves", "test")


func _test_plea_fires_on_losses() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	_seed_war(rv, "elves", 30, 5)
	gs.bus.day_changed.emit(2, false)
	var phone = gs.phone_sys
	_check("plea: DM sent on lopsided losses", phone.sent.size() == 1)
	var txt := String(phone.sent[0].get("text", ""))
	_check("plea: cites casualty numbers",
		txt.contains("30") and txt.contains("5"))
	_check("plea: has ACCEPT/DENY",
		txt.contains("ACCEPT") and txt.contains("DENY"))
	_check("plea: from war advisor",
		int(phone.sent[0].get("unit_id", 0)) == int(wa.get("id", 0)))
	_free_world(parts)


func _test_plea_accept_sues_for_peace() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	_seed_war(rv, "elves", 30, 5)
	gs.bus.day_changed.emit(2, false)
	var ack := rv.try_order(wa, "accept")
	_check("plea accept: ack non-empty", ack != "")
	var offers: Array = gs.diplomacy.pending_surrender_offers()
	var filed := false
	for o: Dictionary in offers:
		if String(o.get("loser", "")) == "humans" \
				and String(o.get("winner", "")) == "elves":
			filed = true
	_check("plea accept: surrender offer filed", filed)
	_free_world(parts)


func _test_plea_deny_rearms_next_tier() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var wa := _advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	# Tier 1: lopsided casualties only (45 pts).
	_seed_war(rv, "elves", 30, 5)
	gs.bus.day_changed.emit(2, false)
	var phone = gs.phone_sys
	_check("plea deny: first plea sent", phone.sent.size() == 1)
	var ack := rv.try_order(wa, "deny")
	_check("plea deny: grim ack", ack != "" and ack.to_lower().contains("fight on"))
	# Same tier next day: no new plea.
	gs.bus.day_changed.emit(3, false)
	_check("plea deny: no re-plea at same tier", phone.sent.size() == 1)
	# Worsen: lose a town (25 pts -> tier 2).
	gs.towns[1]["faction"] = "elves"
	rv._wars["humans|elves"]["towns0"] = {1: "humans"}
	gs.bus.day_changed.emit(4, false)
	_check("plea deny: re-pleads at worse tier", phone.sent.size() == 2)
	var txt2 := String(phone.sent[1].get("text", ""))
	_check("plea deny: second plea cites town loss",
		txt2.to_lower().contains("town"))
	_free_world(parts)


func _test_plea_no_spam_same_tier() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	_seed_war(rv, "elves", 30, 5)
	gs.bus.day_changed.emit(2, false)
	gs.bus.day_changed.emit(3, false)
	gs.bus.day_changed.emit(4, false)
	_check("plea: one DM per tier, no spam",
		(gs.phone_sys as _StubPhone).sent.size() == 1)
	_free_world(parts)


func _test_plea_command_post_loss() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_advisor(gs, "humans", "advisor_war")
	_start_test_war(gs)
	# No casualties, but we lost our town: 25 pts -> tier 1.
	gs.towns[1]["faction"] = "elves"
	var key := _seed_war(rv, "elves", 0, 0)
	rv._wars[key]["towns0"] = {1: "humans"}
	gs.bus.day_changed.emit(2, false)
	var phone = gs.phone_sys
	_check("plea: town loss triggers plea", phone.sent.size() == 1)
	_check("plea: reasons mention town",
		String(phone.sent[0].get("text", "")).to_lower().contains("town"))
	_free_world(parts)


func _test_treasury_drain_warning() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var ta := _advisor(gs, "humans", "advisor_economy")
	_start_test_war(gs)
	# Treasury collapsing: 5000 -> 3000 -> 1000 (1000/day burn).
	var key := _seed_war(rv, "elves", 0, 0)
	rv._wars[key]["gold_hist"] = [5000.0, 3000.0]
	gs.resources.spend("humans", {"gold": 4000.0})
	gs.bus.day_changed.emit(2, false)
	var phone = gs.phone_sys
	var found := false
	for m: Dictionary in phone.sent:
		var txt := String(m.get("text", ""))
		if int(m.get("unit_id", 0)) == int(ta.get("id", 0)) \
				and txt.contains("treasury"):
			found = true
	_check("treasury: advisor warns on drain", found)
	# Throttled: next day, no second warning.
	var n: int = phone.sent.size()
	gs.bus.day_changed.emit(3, false)
	_check("treasury: warning throttled", phone.sent.size() == n)
	_free_world(parts)


func _test_strategic_brief() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	# We outnumber them 4:1.
	for i: int in 4:
		gs.add_unit({"faction": "humans", "job": "soldier", "town_id": 1,
			"position": Vector2(2000, 2000), "alive": true, "hp": 100.0,
			"max_hp": 100.0, "speed": 95.0})
	gs.add_unit({"faction": "elves", "job": "soldier", "town_id": 2,
		"position": Vector2(500, 500), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "speed": 95.0})
	var b := rv.strategic_brief("elves")
	_check("brief: non-empty", String(b.get("text", "")) != "")
	_check("brief: cites outnumbering",
		String(b.get("text", "")).contains("outnumber"))
	_check("brief: not unwise when winning",
		not bool(b.get("unwise", true)))
	# Flip it: they outnumber us.
	for i: int in 10:
		gs.add_unit({"faction": "elves", "job": "soldier", "town_id": 2,
			"position": Vector2(500, 500), "alive": true, "hp": 100.0,
			"max_hp": 100.0, "speed": 95.0})
	var b2 := rv.strategic_brief("elves")
	_check("brief: unwise when outnumbered", bool(b2.get("unwise", false)))
	_free_world(parts)


func _test_proposal_brief_attached() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	gs.add_unit({"faction": "humans", "job": "soldier", "town_id": 1,
		"position": Vector2(2000, 2000), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "speed": 95.0})
	var res: Dictionary = gs.proposals.propose("humans", "declare_war",
		{"target": "elves"})
	_check("proposal: ok", bool(res.get("ok", false)))
	_check("proposal: brief attached",
		String((res.get("details", {}) as Dictionary).get("brief", "")) != "")
	_free_world(parts)


func _test_war_order_questioned_when_unwise() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_war")
	# Elves outnumber us 6:1.
	for i: int in 6:
		gs.add_unit({"faction": "elves", "job": "soldier", "town_id": 2,
			"position": Vector2(500, 500), "alive": true, "hp": 100.0,
			"max_hp": 100.0, "speed": 95.0})
	var ack := rv.try_order(adv, "attack the elves")
	_check("war counsel: questioned when unwise",
		ack.contains("are you SURE"))
	_check("war counsel: still files proposal",
		not gs.proposals.proposals.is_empty())
	_free_world(parts)


func _test_casualty_signal_tracked() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_start_test_war(gs)
	var s1: Dictionary = gs.add_unit({"faction": "humans", "job": "soldier",
		"town_id": 1, "position": Vector2(2000, 2000), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0})
	var s2: Dictionary = gs.add_unit({"faction": "elves", "job": "soldier",
		"town_id": 2, "position": Vector2(500, 500), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0})
	# Elf kills our soldier; we kill theirs. A farmer death doesn't count.
	gs.bus.unit_killed.emit(int(s1.get("id", 0)), "elves")
	gs.bus.unit_killed.emit(int(s2.get("id", 0)), "humans")
	var f: Dictionary = gs.add_unit({"faction": "humans", "job": "farmer",
		"town_id": 1, "position": Vector2(2000, 2000), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0})
	gs.bus.unit_killed.emit(int(f.get("id", 0)), "elves")
	var rec: Dictionary = rv._wars.get("humans|elves", {})
	_check("casualties: war record created", not rec.is_empty())
	_check("casualties: ours counted",
		int(rec.get("ours_dead", 0)) == 1)
	_check("casualties: theirs counted",
		int(rec.get("theirs_dead", 0)) == 1)
	_free_world(parts)


func _test_ai_war_no_plea() -> void:
	var parts := _make_world(["humans", "elves", "ogres"])
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	_advisor(gs, "humans", "advisor_war")
	# Elves vs ogres war — not ours.
	gs.diplomacy.declare_war("elves", "ogres", "test")
	gs.bus.day_changed.emit(2, false)
	_check("ai war: no plea for foreign wars",
		(gs.phone_sys as _StubPhone).sent.is_empty())
	_check("ai war: no war record for foreign wars", rv._wars.is_empty())
	_free_world(parts)
