extends SceneTree
## Cursing Gnomes — hearsay caravan-gossip tests (Jeremy 2026-10-08).
##
## Covers the hearsay flesh-out run: the Captain Funky Pants caravan
## visit was the last dead-end rumor — the Gazette story seeded thin
## talk (kind "trade", heat 0.5, no reactions, nobody cared). Now:
##  - bus.trader_arrived seeds a RICH visit rumor (town attached, truth
##    TRUE, first-hand witnesses standing near the caravan)
##  - the arrival Gazette story dedups against it (no double-seed)
##  - bus.trade_done records deals on the live rumor (capped at 12)
##  - bus.trader_left folds departure in as a last-call heat rush, and
##    the departure Gazette story does NOT seed a second rumor
##  - the host town buzzes (trader_visited, mood up, happy)
##  - dealers brag (trader_deal, mood up) even from foreign factions
##  - late hearers with no deal regret missing it (missed_caravan, sad)
##  - proud/haughty NPCs sniff at the rabble (trader_sniffed, disgusted)
##  - unhinged NPCs feel it 1.5x (matching smear/war/gossip paths)
##  - spread zeal: the host town pushes caravan news; others just gossip
##  - cross-border: caravan talk trickles like any other happy news
##  - kind tables: trade -> helped emotion, 0.5 memory strength
##  - arrival heat (0.7) reaches the ruler bar but not the press bar
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_trader.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay caravan-gossip tests ===")
	_test_arrival_seeds_rich_rumor()
	_test_witnesses_near_caravan()
	_test_arrival_story_dedups()
	_test_departure_folds_no_double_rumor()
	_test_trade_done_records_and_caps_deals()
	_test_trade_done_without_rumor_no_crash()
	_test_host_town_buzzes()
	_test_dealer_brags()
	_test_missed_caravan_regret()
	_test_foreign_curiosity()
	_test_proud_sniffs()
	_test_unhinged_amplified()
	_test_spread_motivation()
	_test_crossborder_trickle()
	_test_kind_tables()
	_test_memory_types_registered()
	_test_heat_bars()
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


func _spawn(gs: GameState, faction: String, mind: Dictionary = {}) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true, "mind": mind})


func _add_town(gs: GameState, tid: int, faction: String, pos: Vector2,
		name: String) -> void:
	gs.towns[tid] = {"id": tid, "faction": faction, "position": pos,
		"name": name}


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _trader_rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "trade" \
				and bool(r.get("trader_visit", false)):
			return r
	return {}


func _count_trader_rumors(hs) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "trade" \
				and bool(r.get("trader_visit", false)):
			n += 1
	return n


func _arrive(hs, gs: GameState) -> Dictionary:
	_add_town(gs, 7, "ogres", Vector2(1000, 1000), "Grumbletown")
	gs.bus.trader_arrived.emit("Captain Funky Pants", Vector2(1050, 1100))
	return _trader_rumor(hs)


func _test_arrival_seeds_rich_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	_check("rich rumor carries the town", String(r.get("trader_town", "")) == "Grumbletown")
	_check("rich rumor carries the town faction", String(r.get("trader_faction", "")) == "ogres")
	_check("rich rumor carries the trader name", String(r.get("trader_name", "")) == "Captain Funky Pants")
	_check("rich rumor is witnessed fact", String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("rich rumor heat 0.7", absf(float(r.get("heat", 0.0)) - 0.7) < 0.001)
	_check("rich rumor deals start empty", (r.get("deals", []) as Array).is_empty())
	_check("rich rumor not yet gone", not bool(r.get("trader_gone", false)))


func _test_witnesses_near_caravan() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var near: Dictionary = _spawn(gs, "ogres")
	near["position"] = Vector2(1060, 1110)
	var nid := int(near.get("id", 0))
	var far: Dictionary = _spawn(gs, "ogres")
	far["position"] = Vector2(5000, 5000)
	var fid := int(far.get("id", 0))
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	_check("nearby NPC is a first-hand witness",
		(r.get("witnesses", []) as Array).has(nid))
	_check("far NPC is not a witness",
		not (r.get("witnesses", []) as Array).has(fid))
	_check("nearby NPC is a knower",
		(r.get("knowers", []) as Array).has(nid))


func _test_arrival_story_dedups() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_arrive(hs, gs)
	# industry.gd's exact arrival Gazette headline.
	gs.bus.gazette_story.emit({
		"day": 1,
		"headline": "Captain Funky Pants' caravan has arrived — limited stock!",
		"body": "The traveling trader's caravan is visiting the region.",
		"kind": "trade",
	})
	_check("arrival story does not double-seed", _count_trader_rumors(hs) == 1)


func _test_departure_folds_no_double_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	var heat_before := float(r.get("heat", 0.0))
	gs.bus.trader_left.emit("Captain Funky Pants")
	_check("departure marks the rumor gone", bool(r.get("trader_gone", false)))
	_check("departure bumps heat (last-call rush)",
		float(r.get("heat", 0.0)) > heat_before)
	# industry.gd's exact departure Gazette headline.
	gs.bus.gazette_story.emit({
		"day": 1,
		"headline": "Captain Funky Pants packs up the caravan",
		"body": "The traveling trader has moved on.",
		"kind": "trade",
	})
	_check("departure story does not seed a second rumor",
		_count_trader_rumors(hs) == 1)


func _test_trade_done_records_and_caps_deals() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	gs.bus.trade_done.emit("ogres", "wood", "gold", 50.0, 40.0)
	gs.bus.trade_done.emit("elves", "food", "oil", 30.0, 10.0)
	var deals: Array = r.get("deals", [])
	_check("deals recorded", deals.size() == 2)
	_check("deal carries the faction",
		String((deals[0] as Dictionary).get("faction", "")) == "ogres")
	_check("deal carries the take",
		String((deals[0] as Dictionary).get("take", "")) == "gold")
	for i in 20:
		gs.bus.trade_done.emit("ogres", "wood", "gold", 10.0, 8.0)
	_check("deals capped at 12", (r.get("deals", []) as Array).size() == 12)


func _test_trade_done_without_rumor_no_crash() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# No arrival — a trade with no visit must not crash or seed a visit rumor.
	gs.bus.trade_done.emit("ogres", "wood", "gold", 50.0, 40.0)
	_check("no visit rumor seeded by an orphan trade", _trader_rumor(hs).is_empty())


func _test_host_town_buzzes() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var u: Dictionary = _spawn(gs, "ogres")
	var uid := int(u.get("id", 0))
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	hs._on_heard(u, r, {})
	_check("host-town NPC remembers the visit",
		_recalled(u, "trader_visited", int(r.get("id", 0))) > 0.0)
	_check("host-town NPC mood rises", conv.ruler_mood(uid) > 0.0)
	_check("host-town NPC happy (helped -> happy)", _emotion(u) == "happy")


func _test_dealer_brags() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var u: Dictionary = _spawn(gs, "elves")
	var uid := int(u.get("id", 0))
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	gs.bus.trade_done.emit("elves", "food", "oil", 30.0, 10.0)
	hs._on_heard(u, r, {})
	_check("dealer remembers the steal",
		_recalled(u, "trader_deal", int(r.get("id", 0))) > 0.0)
	_check("dealer mood rises on the bargain", conv.ruler_mood(uid) > 0.0)


func _test_missed_caravan_regret() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var u: Dictionary = _spawn(gs, "elves")
	var uid := int(u.get("id", 0))
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	gs.bus.trader_left.emit("Captain Funky Pants")
	hs._on_heard(u, r, {})
	_check("latecomer remembers missing it",
		_recalled(u, "missed_caravan", int(r.get("id", 0))) > 0.0)
	_check("latecomer mood drops", conv.ruler_mood(uid) < 0.0)
	_check("latecomer sad (mocked -> sad)", _emotion(u) == "sad")


func _test_foreign_curiosity() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var u: Dictionary = _spawn(gs, "elves")
	var uid := int(u.get("id", 0))
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	hs._on_heard(u, r, {})
	_check("foreign NPC notes the visit",
		_recalled(u, "trader_visited", int(r.get("id", 0))) > 0.0)
	_check("foreign NPC mildly pleased", conv.ruler_mood(uid) > 0.0)


func _test_proud_sniffs() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var u: Dictionary = _spawn(gs, "ogres", {"traits": {"proud": 1.0}})
	var uid := int(u.get("id", 0))
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	hs._on_heard(u, r, {})
	_check("proud NPC sniffs at the rabble",
		_recalled(u, "trader_sniffed", int(r.get("id", 0))) > 0.0)
	_check("proud NPC does NOT buzz", conv.ruler_mood(uid) < 0.0)
	_check("proud NPC disgusted (grossed_out -> disgusted)",
		_emotion(u) == "disgusted")


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var calm: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres", {"traits": {"unhinged": 1.0}})
	var cid := int(calm.get("id", 0))
	var wid := int(wild.get("id", 0))
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	hs._on_heard(calm, r, {})
	hs._on_heard(wild, r, {})
	_check("unhinged NPC buzzes harder than a calm one",
		conv.ruler_mood(wid) > conv.ruler_mood(cid))


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var host: Dictionary = _spawn(gs, "ogres")
	var foreigner: Dictionary = _spawn(gs, "elves")
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	var m_host: Dictionary = hs._spread_motivation(host, r)
	var m_for: Dictionary = hs._spread_motivation(foreigner, r)
	_check("host town pushes caravan news", int(m_host.get("cap_delta", 0)) == 1)
	_check("host town heat bump", float(m_host.get("heat_delta", 0.0)) > 0.0)
	_check("foreigners just gossip",
		int(m_for.get("cap_delta", 0)) == 0 \
		and absf(float(m_for.get("heat_delta", 0.0))) < 0.0001)


func _test_crossborder_trickle() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var u: Dictionary = _spawn(gs, "ogres")
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	var tgt: Dictionary = hs._cross_target(u, r)
	_check("caravan talk trickles cross-border at 0.04",
		absf(float(tgt.get("chance", -1.0)) - 0.04) < 0.0001)


func _test_kind_tables() -> void:
	var h: Array = _harness()
	var hs = h[2]
	_check("trade emotion is helped", String(hs.KIND_EMOTION.get("trade", "")) == "helped")
	_check("trade memory strength 0.5",
		absf(float(hs.KIND_MEM_STRENGTH.get("trade", -1.0)) - 0.5) < 0.0001)


func _test_memory_types_registered() -> void:
	var mems = load("res://scripts/sim/memories.gd")
	for t: String in ["trader_visited", "trader_deal", "missed_caravan", "trader_sniffed"]:
		_check("memory type registered: %s" % t, t in mems.TYPES)
		_check("memory weight set: %s" % t, mems.REL_WEIGHT.has(t))


func _test_heat_bars() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var r := _arrive(hs, gs)
	_check("arrival seeds a rumor", not r.is_empty())
	if r.is_empty():
		return
	_check("arrival reaches the ruler bar",
		float(r.get("heat", 0.0)) >= hs.RULER_HEAT)
	_check("arrival does not hit the press bar by default",
		float(r.get("heat", 0.0)) < hs.PRESS_HEAT)
	_check("arrival not press-excluded by kind",
		not (String(r.get("kind", "")) in hs.PRESS_EXCLUDE_KINDS))
