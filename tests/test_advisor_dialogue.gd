extends SceneTree
## Cursing Gnomes — advisor dialogue trees + Treasury deal-tracking tests
## (Jeremy 2026-10-11).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_advisor_dialogue.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers:
##   - each advisor opens a voiced topic menu ("talk"/"report"/"advice"/
##     "what's on your mind"/name); topics answer with LIVE numbers;
##     number and keyword picks navigate; follow-ups go deeper.
##   - Treasury deal intents end-to-end via message text: propose ->
##     signed; "how are my deals" reflects it; ledger; trade advice;
##     auto-manage on/off; cancel by id and by faction; counter accept.
##   - non-Treasury advisors redirect deal talk; foreign cabinets refuse
##     deal commands (sovereignty); real orders still execute through a
##     pending menu.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes advisor dialogue tests ===")
	_test_treasury_menu()
	_test_treasury_topic_live_numbers()
	_test_treasury_followup()
	_test_war_tree()
	_test_civic_tree()
	_test_guild_tree()
	_test_clerk_tree()
	_test_keyword_jump()
	_test_deal_propose_and_report()
	_test_deal_ledger_and_advice()
	_test_auto_manage_toggle()
	_test_cancel_by_id_and_faction()
	_test_counter_accept()
	_test_non_treasury_redirect()
	_test_foreign_refusal()
	_test_orders_survive_menu()
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


## Fresh headless game, wired like World: player = humans.
func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "elves"])
	gs.set_ruler_name("ass")
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.trade_deals = SimTradeDeals.new(gs)
	gs.hiring = GuildHiring.new(gs)
	gs.army = SimArmy.new(gs)
	gs.population = SimPopulation.new(gs)
	gs.court_sys = _StubCourt.new(gs)
	gs.phone_sys = _StubPhone.new(gs)
	var rv := SimRulersVoice.new(gs)
	gs.rulers_voice = rv
	gs.found_town("humans", "Testville", Vector2(2000, 2000))
	gs.found_town("elves", "Elftown", Vector2(500, 500))
	gs.add_building({"type": "town_hall", "faction": "humans", "town_id": 1,
		"position": Vector2(2000, 2000), "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
	gs.add_building({"type": "farm", "faction": "humans", "town_id": 1,
		"position": Vector2(2050, 2000), "alive": true, "complete": true,
		"progress": 1.0, "hp": 500.0, "max_hp": 500.0})
	gs.add_building({"type": "lumber_camp", "faction": "humans",
		"town_id": 1, "position": Vector2(2100, 2000), "alive": true,
		"complete": true, "progress": 1.0, "hp": 500.0, "max_hp": 500.0})
	gs.add_building({"type": "oil_pump", "faction": "humans",
		"town_id": 1, "position": Vector2(2150, 2000), "alive": true,
		"complete": true, "progress": 1.0, "hp": 500.0, "max_hp": 500.0})
	# Population: real units for live-number assertions.
	for i: int in range(6):
		_add_unit(gs, "humans", "farmer", 1)
	for i: int in range(4):
		_add_unit(gs, "humans", "soldier", 1)
	_add_unit(gs, "humans", "woodcutter", 1)
	_add_unit(gs, "humans", "shopkeeper", 1)
	# Capped adds (storage caps apply: gold 1500, wood 1200, food 600,
	# oil 200 in this world — no stock buildings).
	gs.resources.add_resource("humans", "gold", 5000.0)
	gs.resources.add_resource("humans", "wood", 5000.0)
	gs.resources.add_resource("humans", "food", 5000.0)
	gs.resources.add_resource("humans", "oil", 5000.0)
	gs.resources.add_resource("elves", "gold", 5000.0)
	gs.resources.add_resource("elves", "wood", 5000.0)
	gs.resources.add_resource("elves", "food", 5000.0)
	gs.resources.add_resource("elves", "oil", 5000.0)
	gs.diplomacy.adjust_score("humans", "elves", 60.0)
	return [gs, rv]


func _add_unit(gs: GameState, faction: String, job: String,
		town_id: int) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": job, "town_id": town_id,
		"position": Vector2(2000, 2010), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "speed": 95.0, "name": "Test Unit"})


func _advisor(gs: GameState, faction: String, job: String) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "job": job,
		"town_id": 1, "position": Vector2(2000, 2010), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0,
		"name": "Test Advisor"})
	u["is_advisor"] = true
	return u


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


class _StubCourt:
	extends RefCounted
	var policies = null

	func _init(gs) -> void:
		policies = SimPolicies.new(gs, self)


## --- dialogue trees ---------------------------------------------------------


func _test_treasury_menu() -> void:
	var parts := _make_world()
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(parts[0], "humans", "advisor_economy")
	var menu: String = rv.try_order(adv, "talk")
	_check("treasury: menu opens on talk", menu != "")
	_check("treasury: menu lists Treasury", menu.contains("1. Treasury"))
	_check("treasury: menu lists Trade deals", menu.contains("Trade deals"))
	_check("treasury: menu lists 4 topics",
		menu.contains("4. Warnings"))
	_check("treasury: voice says boss", menu.contains("boss"))
	# Alternate opener: advisor's name.
	var adv2 := _advisor(parts[0], "humans", "advisor_economy")
	var menu2: String = rv.try_order(adv2, "test advisor")
	_check("treasury: menu opens on name", menu2.contains("1. Treasury"))
	_free_world(parts)


func _test_treasury_topic_live_numbers() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var gold := int(gs.resources.get_amount("humans", "gold"))
	var wood := int(gs.resources.get_amount("humans", "wood"))
	rv.try_order(adv, "talk")
	var ans: String = rv.try_order(adv, "1")
	_check("treasury: topic 1 answers", ans != "")
	_check("treasury: real gold shown", ans.contains("%dg gold" % gold))
	_check("treasury: real wood shown", ans.contains("%d wood" % wood))
	_check("treasury: tax rate shown", ans.contains("Taxes at 10%"))
	_check("treasury: follow-ups offered", ans.contains("Where does the gold go?"))
	_check("treasury: back offered", ans.contains("Back to topics"))
	_free_world(parts)


func _test_treasury_followup() -> void:
	var parts := _make_world()
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(parts[0], "humans", "advisor_economy")
	rv.try_order(adv, "talk")
	rv.try_order(adv, "1")
	var fup: String = rv.try_order(adv, "1")
	_check("treasury: follow-up answers", fup.contains("Gold in:"))
	_check("treasury: follow-up shows upkeep", fup.contains("Gold out:"))
	# Back re-opens the topic menu.
	var back: String = rv.try_order(adv, "back")
	_check("treasury: back re-opens menu", back.contains("1. Treasury"))
	_free_world(parts)


func _test_war_tree() -> void:
	var parts := _make_world()
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(parts[0], "humans", "advisor_war")
	var menu: String = rv.try_order(adv, "what's on your mind")
	_check("war: menu opens", menu.contains("Army strength"))
	_check("war: blunt greeting", menu.contains("Blades or borders?"))
	var ans: String = rv.try_order(adv, "1")
	_check("war: army topic answers", ans.contains("Blades:"))
	_check("war: real soldier count", ans.contains("4 standing"))
	var fup: String = rv.try_order(adv, "2")
	_check("war: train advice answers", fup.contains("under arms"))
	_check("war: train advice grounded", fup.contains("4 soldiers"))
	_free_world(parts)


func _test_civic_tree() -> void:
	var parts := _make_world()
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(parts[0], "humans", "advisor_civic")
	var menu: String = rv.try_order(adv, "report")
	_check("civic: menu opens", menu.contains("People & housing"))
	_check("civic: warm greeting", menu.contains("Always a joy"))
	var ans: String = rv.try_order(adv, "people")
	_check("civic: keyword pick works", ans.contains("souls under your care"))
	_check("civic: real pop shown", ans.contains("13 souls"))
	_check("civic: town named", ans.contains("Testville"))
	_free_world(parts)


func _test_guild_tree() -> void:
	var parts := _make_world()
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(parts[0], "humans", "guild_master")
	var menu: String = rv.try_order(adv, "talk")
	_check("guild: menu opens", menu.contains("Training queues"))
	var ans: String = rv.try_order(adv, "2")
	_check("guild: queues topic answers", ans.contains("training") or ans.contains("Training"))
	var adv2 := _advisor(parts[0], "humans", "guild_master")
	rv.try_order(adv2, "talk")
	var shops: String = rv.try_order(adv2, "3")
	_check("guild: shops topic counts buildings", shops.contains("shops and stores"))
	_check("guild: shops topic counts staff", shops.contains("shop-folk"))
	_free_world(parts)


func _test_clerk_tree() -> void:
	var parts := _make_world()
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(parts[0], "humans", "clerk")
	var menu: String = rv.try_order(adv, "talk")
	_check("clerk: menu opens", menu.contains("The draft"))
	_check("clerk: nervous voice", menu.contains("Y-yes"))
	var ans: String = rv.try_order(adv, "3")
	_check("clerk: paperwork mentions triplicate", ans.contains("triplicate"))
	var adv2 := _advisor(parts[0], "humans", "clerk")
	rv.try_order(adv2, "talk")
	var rules: String = rv.try_order(adv2, "rules")
	_check("clerk: rules keyword pick", rules.contains("sovereignty"))
	_free_world(parts)


func _test_keyword_jump() -> void:
	var parts := _make_world()
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(parts[0], "humans", "advisor_war")
	# No menu open: a bare topic keyword jumps straight to the topic.
	# (Elves are friendly here, so the answer is the quiet-borders line.)
	var ans: String = rv.try_order(adv, "threats")
	_check("jump: war threats keyword", ans.to_lower().contains("borders"))
	# ...but a real order still wins over the keyword layer.
	var ans2: String = rv.try_order(adv, "muster the army")
	_check("jump: real order not swallowed", ans2 != "" and not ans2.contains("Blades or borders?"))
	_free_world(parts)


## --- Treasury deal-tracking ---------------------------------------------------


func _test_deal_propose_and_report() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	# Make headroom under the wood cap so the incoming wood lands.
	gs.resources.add_resource("humans", "wood", -300.0, true)
	# Generous: 200 gold (200v) for 100 wood (60v) — AI accepts.
	var gold0: float = gs.resources.get_amount("humans", "gold")
	var wood0: float = gs.resources.get_amount("humans", "wood")
	var ack: String = rv.try_order(adv,
		"trade with the elves: offer 200 gold for 100 wood")
	_check("deal: propose ack non-empty", ack != "")
	_check("deal: signed", ack.contains("Deal signed"))
	_check("deal: gold moved",
		gs.resources.get_amount("humans", "gold") <= gold0 - 199.0)
	_check("deal: wood received",
		gs.resources.get_amount("humans", "wood") >= wood0 + 99.0)
	var rep: String = rv.try_order(adv, "how are my deals")
	_check("deal: report reflects signing", rep.contains("1 completed"))
	_free_world(parts)


func _test_deal_ledger_and_advice() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	rv.try_order(adv, "trade with the elves: offer 200 gold for 100 wood")
	var led: String = rv.try_order(adv, "show me the ledger")
	_check("deal: ledger shows deal #1", led.contains("#1"))
	var ta: String = rv.try_order(adv, "what should I trade")
	_check("deal: trade advice answers", ta != "")
	_check("deal: advice grounded in surplus",
		ta.to_lower().contains("gold") or ta.to_lower().contains("surplus") \
		or ta.to_lower().contains("balanced"))
	_free_world(parts)


func _test_auto_manage_toggle() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	var on: String = rv.try_order(adv, "handle my trades")
	_check("deal: auto-manage turns on", bool(gs.trade_deals.auto_manage))
	_check("deal: auto-manage voiced", on.contains("Say less"))
	var off: String = rv.try_order(adv, "stop auto trade")
	_check("deal: auto-manage turns off", not bool(gs.trade_deals.auto_manage))
	_check("deal: stop voiced", off.contains("Standing down"))
	_free_world(parts)


func _test_cancel_by_id_and_faction() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	# Daily deal stays active after signing.
	var ack: String = rv.try_order(adv,
		"trade with the elves: offer 100 wood for 50 gold daily for 5 days")
	_check("deal: daily signed", ack.contains("Deal signed"))
	var act: Array = gs.trade_deals.active_deals_for("humans")
	_check("deal: daily deal active", act.size() == 1)
	var did: int = int((act[0] as Dictionary).get("id", 0))
	var c1: String = rv.try_order(adv, "cancel deal #%d" % did)
	_check("deal: cancel by id", c1.contains("cancelled"))
	# Second daily, cancelled by faction noun.
	rv.try_order(adv,
		"trade with the elves: offer 100 wood for 50 gold daily for 5 days")
	var c2: String = rv.try_order(adv, "cancel the elf deal")
	_check("deal: cancel by faction", c2.contains("cancelled"))
	_check("deal: none active after cancels",
		gs.trade_deals.active_deals_for("humans").is_empty())
	_free_world(parts)


func _test_counter_accept() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	# 30 gold (30v) for 100 wood (60v): fair=0.5 -> counter.
	var ack: String = rv.try_order(adv,
		"trade with the elves: offer 30 gold for 100 wood")
	_check("deal: counter offered", ack.contains("haggling"))
	var take: String = rv.try_order(adv, "accept the counter")
	_check("deal: counter accepted", take.contains("Counter accepted"))
	_free_world(parts)


func _test_non_treasury_redirect() -> void:
	var parts := _make_world()
	var rv: SimRulersVoice = parts[1]
	var war := _advisor(parts[0], "humans", "advisor_war")
	var r1: String = rv.try_order(war, "how are my deals")
	_check("redirect: war sends to treasury", r1.contains("coin-counter"))
	var clk := _advisor(parts[0], "humans", "clerk")
	var r2: String = rv.try_order(clk, "handle my trades")
	_check("redirect: clerk sends to treasury", r2.contains("filing cabinet"))
	_free_world(parts)


func _test_foreign_refusal() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var foreign := _advisor(gs, "elves", "advisor_economy")
	var r1: String = rv.try_order(foreign, "handle my trades")
	_check("foreign: deal command refused", r1 != "")
	_check("foreign: not the treasury ack", not r1.contains("Say less"))
	var r2: String = rv.try_order(foreign, "trade with the humans: offer 10 gold for 10 wood")
	_check("foreign: trade proposal refused", r2 != "" and not r2.contains("Deal signed"))
	# And a normal foreign order still refuses (existing sovereignty).
	var r3: String = rv.try_order(foreign, "build 3 farms")
	_check("foreign: build order still refused", r3 != "" and not r3.contains("farm"))
	_free_world(parts)


func _test_orders_survive_menu() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var adv := _advisor(gs, "humans", "advisor_economy")
	rv.try_order(adv, "talk")
	var before: int = gs.buildings.size()
	var ack: String = rv.try_order(adv, "build 3 farms")
	_check("menu: real order still executes", gs.buildings.size() == before + 3)
	_check("menu: order ack not a menu", not ack.contains("Back to topics"))
	# Menu was cleared by the order: "1" now falls through to chat ("").
	var after: String = rv.try_order(adv, "1")
	_check("menu: cleared after order", after == "")
	_free_world(parts)
