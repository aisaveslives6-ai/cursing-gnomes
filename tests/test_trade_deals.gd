extends SceneTree
## Cursing Gnomes — faction trade deals headless tests (Jeremy 2026-10-11).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_trade_deals.gd
##
## Exit code 0 = all passed, 1 = any failure.
## Covers: validation, AI accept/counter/refuse (incl. war refusal),
## execution/ledger accuracy, daily deals, cancellation, counter accept/decline,
## auto-manage guardrails (never war enemies, never below reserve floor),
## treasury report/advice, and save/load round-trip.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes trade-deal tests ===")
	_test_validation()
	_test_accept_and_execute()
	_test_war_refusal()
	_test_counter_flow()
	_test_insult_refusal()
	_test_daily_deal()
	_test_war_cancels_daily()
	_test_cancel()
	_test_ledger()
	_test_treasury_report()
	_test_trade_advice()
	_test_auto_manage_guards()
	_test_save_load()
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


## Fresh headless game: player = humans; trade deals wired like World does.
func _make_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "elves", "ogres"])
	gs.trade_deals = SimTradeDeals.new(gs)
	return gs


func _rich(gs: GameState, faction: String) -> void:
	gs.resources.add_resource(faction, "gold", 1500.0)
	gs.resources.add_resource(faction, "wood", 1000.0)
	gs.resources.add_resource(faction, "food", 1000.0)
	gs.resources.add_resource(faction, "oil", 500.0)


func _friends(gs: GameState) -> void:
	gs.diplomacy.adjust_score("humans", "elves", 60.0)
	gs.diplomacy.adjust_score("humans", "ogres", 40.0)


## --- validation ---------------------------------------------------------------

func _test_validation() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_friends(gs)
	var td = gs.trade_deals
	var r: Dictionary = td.propose("humans", "humans", {"gold": 10.0},
		{"wood": 10.0})
	_check("same faction invalid", not bool(r.get("ok", true)))
	r = td.propose("humans", "dwarves", {"gold": 10.0}, {"wood": 10.0})
	_check("unknown faction invalid", not bool(r.get("ok", true)))
	r = td.propose("humans", "elves", {}, {"wood": 10.0})
	_check("empty offer invalid", not bool(r.get("ok", true)))
	r = td.propose("humans", "elves", {"gold": 999999.0}, {"wood": 10.0})
	_check("unaffordable invalid", not bool(r.get("ok", true)))
	r = td.propose("humans", "elves", {"gold": 10.0}, {"wood": 10.0},
		"weekly", 1)
	_check("bad mode invalid", not bool(r.get("ok", true)))
	gs.queue_free()


## --- accept + execute ----------------------------------------------------------

func _test_accept_and_execute() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_rich(gs, "elves")
	_friends(gs)
	var td = gs.trade_deals
	var h_gold0: float = gs.resources.get_amount("humans", "gold")
	var e_wood0: float = gs.resources.get_amount("elves", "wood")
	# Generous: 200 gold (200v) for 100 wood (60v) — well above the bar.
	var r: Dictionary = td.propose("humans", "elves", {"gold": 200.0},
		{"wood": 100.0}, "once", 1)
	_check("generous accepted", String(r.get("verdict", "")) == "accept")
	_check("humans paid gold",
		gs.resources.get_amount("humans", "gold") < h_gold0 - 199.0)
	_check("humans got wood",
		gs.resources.get_amount("humans", "wood") >= 1000.0 + 99.0)
	_check("elves got gold",
		gs.resources.get_amount("elves", "gold") >= 1000.0 + 199.0)
	_check("elves lost wood",
		gs.resources.get_amount("elves", "wood") < e_wood0 - 99.0)
	var d: Dictionary = r.get("deal", {})
	_check("deal completed", String(d.get("status", "")) == "completed")
	gs.queue_free()


## --- war refusal -----------------------------------------------------------------

func _test_war_refusal() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_rich(gs, "ogres")
	var td = gs.trade_deals
	gs.diplomacy.declare_war("humans", "ogres", "test")
	var r: Dictionary = td.propose("humans", "ogres", {"gold": 500.0},
		{"wood": 10.0}, "once", 1)
	_check("war refuses", String(r.get("verdict", "")) == "refuse")
	_check("war refusal mentions war",
		String(r.get("msg", "")).to_lower().find("war") >= 0)
	gs.queue_free()


## --- counter flow -------------------------------------------------------------------

func _test_counter_flow() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_rich(gs, "elves")
	_friends(gs)
	var td = gs.trade_deals
	# Slightly light: 50 gold (50v) for 100 wood (60v) — fair 0.83, elves
	# are not needy; accept_bar 1.0 (not haggler) -> counter.
	var r: Dictionary = td.propose("humans", "elves", {"gold": 50.0},
		{"wood": 100.0}, "once", 1)
	_check("light offer countered",
		String(r.get("verdict", "")) == "counter")
	var d: Dictionary = r.get("deal", {})
	_check("counter status", String(d.get("status", "")) == "countered")
	var cr: Dictionary = d.get("counter_request", {})
	_check("counter asks more wood", float(cr.get("wood", 0.0)) > 100.0)
	# Accept the counter: resources move.
	var h_wood0: float = gs.resources.get_amount("humans", "wood")
	var a: Dictionary = td.accept_counter(int(d.get("id", 0)))
	_check("counter accepted", bool(a.get("ok", false)))
	_check("counter wood arrived",
		gs.resources.get_amount("humans", "wood") > h_wood0)
	_check("deal active->completed",
		String(td.get_deal(int(d.get("id", 0))).get("status", "")) == "completed")
	# Decline path.
	r = td.propose("humans", "elves", {"gold": 50.0}, {"wood": 100.0},
		"once", 1)
	d = r.get("deal", {})
	var dec: Dictionary = td.decline_counter(int(d.get("id", 0)))
	_check("counter declined", bool(dec.get("ok", false)))
	_check("declined status refused",
		String(td.get_deal(int(d.get("id", 0))).get("status", "")) == "refused")
	gs.queue_free()


## --- insult refusal -------------------------------------------------------------------

func _test_insult_refusal() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_rich(gs, "elves")
	_friends(gs)
	var td = gs.trade_deals
	# 10 gold (10v) for 500 wood (300v) — fair 0.03 -> refuse.
	var r: Dictionary = td.propose("humans", "elves", {"gold": 10.0},
		{"wood": 500.0}, "once", 1)
	_check("insult refused", String(r.get("verdict", "")) == "refuse")
	_check("refusal has voice", String(r.get("msg", "")).length() > 8)
	gs.queue_free()


## --- daily deals -------------------------------------------------------------------

func _test_daily_deal() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_rich(gs, "elves")
	_friends(gs)
	var td = gs.trade_deals
	# 300 gold for 100 wood/day x3 — proposer must hold 900 gold. Rich = 1000.
	var h_wood0: float = gs.resources.get_amount("humans", "wood")
	var r: Dictionary = td.propose("humans", "elves", {"gold": 300.0},
		{"wood": 100.0}, "daily", 3)
	_check("daily accepted", String(r.get("verdict", "")) == "accept")
	var d: Dictionary = r.get("deal", {})
	_check("daily active", String(d.get("status", "")) == "active")
	_check("days_left 2 after first leg", int(d.get("days_left", -1)) == 2)
	# Simulate two more days (wood cap 1200 bounds the total: 1000+300->1200).
	gs.bus.day_changed.emit(2, false)
	gs.bus.day_changed.emit(3, false)
	_check("daily legs delivered",
		gs.resources.get_amount("humans", "wood") > h_wood0 + 150.0)
	_check("daily completed",
		String(td.get_deal(int(d.get("id", 0))).get("status", "")) == "completed")
	gs.queue_free()


func _test_war_cancels_daily() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_rich(gs, "elves")
	_friends(gs)
	var td = gs.trade_deals
	var r: Dictionary = td.propose("humans", "elves", {"gold": 300.0},
		{"wood": 100.0}, "daily", 5)
	var d: Dictionary = r.get("deal", {})
	gs.diplomacy.declare_war("humans", "elves", "test")
	gs.bus.day_changed.emit(2, false)
	_check("war cancels daily",
		String(td.get_deal(int(d.get("id", 0))).get("status", "")) == "cancelled")
	gs.queue_free()


## --- cancel -------------------------------------------------------------------

func _test_cancel() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_rich(gs, "elves")
	_friends(gs)
	var td = gs.trade_deals
	var r: Dictionary = td.propose("humans", "elves", {"gold": 300.0},
		{"wood": 100.0}, "daily", 5)
	var d: Dictionary = r.get("deal", {})
	var c: Dictionary = td.cancel_deal(int(d.get("id", 0)), "humans")
	_check("cancel ok", bool(c.get("ok", false)))
	_check("cancelled status",
		String(td.get_deal(int(d.get("id", 0))).get("status", "")) == "cancelled")
	gs.queue_free()


## --- ledger -------------------------------------------------------------------

func _test_ledger() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_rich(gs, "elves")
	_rich(gs, "ogres")
	_friends(gs)
	var td = gs.trade_deals
	td.propose("humans", "elves", {"gold": 200.0}, {"wood": 100.0}, "once", 1)
	td.propose("humans", "ogres", {"gold": 200.0}, {"wood": 100.0}, "once", 1)
	var rows: Array = td.ledger("humans")
	_check("ledger has 2", rows.size() == 2)
	_check("ledger text lists deals",
		td.ledger_text("humans").find("#1") >= 0)
	_check("ogres ledger has 1", td.ledger("ogres").size() == 1)
	var d: Dictionary = rows[0]
	_check("summary mentions gold",
		td.deal_summary(d).find("gold") >= 0)
	gs.queue_free()


## --- treasury report / advice ---------------------------------------------------

func _test_treasury_report() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_rich(gs, "elves")
	_friends(gs)
	var td = gs.trade_deals
	var rep0: String = td.treasury_report("humans")
	_check("empty ledger report", rep0.to_lower().find("empty") >= 0)
	td.propose("humans", "elves", {"gold": 200.0}, {"wood": 100.0}, "once", 1)
	var rep: String = td.treasury_report("humans")
	_check("report counts completed", rep.find("1 completed") >= 0)
	_check("report mentions gold", rep.to_lower().find("gold") >= 0)
	gs.queue_free()


func _test_trade_advice() -> void:
	var gs := _make_game()
	var td = gs.trade_deals
	# Drain food to trigger a SHORT warning; flood wood for surplus.
	gs.resources.add_resource("humans", "food", -900.0)
	gs.resources.add_resource("humans", "wood", 900.0)
	var adv: String = td.trade_advice("humans")
	_check("advice flags short food", adv.find("SHORT on food") >= 0)
	_check("advice flags surplus wood", adv.find("to burn") >= 0)
	gs.queue_free()


## --- auto-manage guardrails ---------------------------------------------------

func _test_auto_manage_guards() -> void:
	var gs := _make_game()
	var td = gs.trade_deals
	# Setup: humans flush with wood, starving for food; elves friendly + stocked.
	gs.resources.add_resource("humans", "wood", 900.0)
	gs.resources.add_resource("humans", "food", -950.0)
	_rich(gs, "elves")
	gs.diplomacy.adjust_score("humans", "elves", 60.0)
	# At war with ogres — auto-manage must never pick them.
	_rich(gs, "ogres")
	gs.diplomacy.declare_war("humans", "ogres", "test")
	td.auto_manage = true
	var res: Dictionary = td.auto_manage_tick()
	_check("auto proposes", bool(res.get("ok", false)))
	var d: Dictionary = res.get("deal", {})
	if not d.is_empty() and String(res.get("verdict", "")) == "accept":
		_check("auto never picks war enemy",
			String(d.get("target", "")) != "ogres")
	# Reserve floor: offer must not breach it.
		var offer: Dictionary = d.get("offer", {})
		for r: String in offer:
			var floor: float = float(SimTradeDeals.RESERVE_FLOOR.get(r, 0.0))
			_check("reserve floor holds %s" % r,
				gs.resources.get_amount("humans", r) >= floor - 0.01)
	# Second tick same day: no double-run.
	var res2: Dictionary = td.auto_manage_tick()
	_check("auto once per day", not bool(res2.get("ok", false)))
	# Auto-manage off by default on a fresh system.
	var gs2 := _make_game()
	_check("auto off by default", not bool(gs2.trade_deals.auto_manage))
	gs2.queue_free()
	gs.queue_free()


## --- save / load -------------------------------------------------------------------

func _test_save_load() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_rich(gs, "elves")
	_friends(gs)
	var td = gs.trade_deals
	td.propose("humans", "elves", {"gold": 300.0}, {"wood": 100.0},
		"daily", 4)
	td.auto_manage = true
	var data: Dictionary = td.to_dict()
	var gs2 := _make_game()
	gs2.trade_deals.from_dict(data)
	_check("deals restored", gs2.trade_deals.ledger("humans").size() == 1)
	_check("auto flag restored", bool(gs2.trade_deals.auto_manage))
	var d: Dictionary = gs2.trade_deals.ledger("humans")[0]
	_check("days_left restored", int(d.get("days_left", -1)) == 3)
	gs.queue_free()
	gs2.queue_free()
