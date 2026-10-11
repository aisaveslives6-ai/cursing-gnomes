extends SceneTree
## Cursing Gnomes — wagon dealership + vehicle purchase gossip tests
## (Jeremy 2026-10-11 hearsay flesh-out).
##
## Jeremy's 2026-10-10 direct order put personal vehicles on the roads
## (wagon dealerships where citizens spend their OWN coins, assigned
## parking lots, real driving physics) and the grapevine was DEAF to it —
## nobody talked about the new dealership or who just bought wheels. Now:
##  - a "wagon_dealership" building_placed seeds a RICH kind-"vehicle"
##    opening rumor (heat 0.55 tavern talk, TRUTH_TRUE, no front page)
##  - bus.vehicle_bought (emitted once per completed sale by
##    SimDealership._close_sale: buyer id, vehicle type, price) seeds a
##    RICH kind-"vehicle" rumor per buyer (heat 0.5, TRUTH_TRUE,
##    subject-dedup "vehiclebought:<id>" — a second purchase refreshes)
##  - the vehicle reaction matrix: the buyer brags ("vehicle_proud"),
##    the unhinged covet the wheels ("vehicle_thrill"), the buyer's
##    faction admires — or envies if they couldn't afford it
##    ("vehicle_envy", grumpy); rivals mock the show-off
##    ("vehicle_mock"); everyone else just enjoys the news. Unhinged x1.5.
##  - spread motivation: the buyer brag-spreads (+2/+0.1), their faction
##    admires (+1/+0.05), rivals mock-spread (+1/+0.1), dealer openings
##    are told straight
##  - witnessed fact — joins the slur/famine/season/weather/brigade
##    doubt-immunity club (nobody doubts new wheels); old saves without
##    vehicle_kind fall through to the generic path
##  - all 6 new memory types registered in SimMemories.TYPES with weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_vehicle.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay vehicle gossip tests ===")
	_test_dealer_opening_seeds_rumor()
	_test_opening_heat_bounds()
	_test_opening_truth_and_press()
	_test_unowned_dealer_seeds_nothing()
	_test_generic_building_unaffected()
	_test_purchase_seeds_rumor()
	_test_purchase_heat_truth()
	_test_dead_buyer_seeds_nothing()
	_test_repeat_purchase_refreshes_not_duplicates()
	_test_second_buyer_separate_rumor()
	_test_buyer_proud()
	_test_faction_admires()
	_test_poor_envies()
	_test_rival_mocks()
	_test_unhinged_thrills()
	_test_neutral_gets_news()
	_test_opening_reaction()
	_test_spread_motivation()
	_test_memory_types_registered()
	_test_doubt_immunity()
	_test_old_save_fallthrough()
	_test_signal_connected()
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


func _spawn(gs: GameState, faction: String, pos: Vector2 = Vector2.ZERO,
		mind: Dictionary = {}) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "alive": true,
		"mind": mind})
	u["position"] = pos
	return u


func _unhinged_mind() -> Dictionary:
	return {"traits": {"unhinged": 1.0}}


func _open_dealer(gs: GameState, faction: String) -> void:
	gs.bus.building_placed.emit({"type": "wagon_dealership",
		"faction": faction, "name": "Wagon Dealership"})


func _buy(gs: GameState, buyer_id: int, vtype: String, price: float) -> void:
	gs.bus.vehicle_bought.emit(buyer_id, vtype, price)


func _rumor(hs, subject: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "vehicle" \
				and String(r.get("subject", "")) == subject:
			return r
	return {}


func _count_vehicle(hs) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "vehicle":
			n += 1
	return n


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _test_dealer_opening_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_open_dealer(gs, "gnomes")
	var r := _rumor(hs, "dealeropened")
	_check("dealer opening seeds a rumor", not r.is_empty())
	_check("opening records the faction",
		String(r.get("vehicle_faction", "")) == "gnomes")
	_check("opening is vehicle_kind opened",
		String(r.get("vehicle_kind", "")) == "opened")


func _test_opening_heat_bounds() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_open_dealer(gs, "gnomes")
	var r := _rumor(hs, "dealeropened")
	_check("opening stays tavern talk",
		float(r.get("heat", 0.0)) < hs.PRESS_HEAT)
	_check("opening never spawns an advisor proposal",
		float(r.get("heat", 0.0)) < hs.QUEST_HEAT)


func _test_opening_truth_and_press() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_open_dealer(gs, "gnomes")
	var r := _rumor(hs, "dealeropened")
	_check("opening is confirmed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("opening is not press-eligible",
		not bool(r.get("press_ok", true)))


func _test_unowned_dealer_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_open_dealer(gs, "")
	_check("factionless dealer seeds nothing", _count_vehicle(hs) == 0)


func _test_generic_building_unaffected() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.building_placed.emit({"type": "town_hall", "faction": "gnomes",
		"name": "Town Hall"})
	var found := false
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "building":
			found = true
	_check("town hall still seeds generic building talk", found)
	_check("no vehicle rumor from a town hall", _count_vehicle(hs) == 0)


func _test_purchase_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "wagon", 60.0)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	_check("purchase seeds a rumor", not r.is_empty())
	_check("purchase records the buyer",
		int(r.get("vehicle_buyer", 0)) == bid)
	_check("purchase records the type",
		String(r.get("vehicle_type", "")) == "wagon")
	_check("purchase records the price",
		is_equal_approx(float(r.get("vehicle_price", 0.0)), 60.0))
	_check("purchase records the faction",
		String(r.get("vehicle_faction", "")) == "gnomes")


func _test_purchase_heat_truth() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "carriage", 100.0)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	_check("purchase stays tavern talk",
		float(r.get("heat", 0.0)) < hs.PRESS_HEAT)
	_check("purchase never spawns an advisor proposal",
		float(r.get("heat", 0.0)) < hs.QUEST_HEAT)
	_check("purchase is confirmed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("purchase is not press-eligible",
		not bool(r.get("press_ok", true)))


func _test_dead_buyer_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_buy(gs, 99999, "wagon", 60.0)
	_check("dead buyer seeds nothing", _count_vehicle(hs) == 0)


func _test_repeat_purchase_refreshes_not_duplicates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "cart", 35.0)
	_buy(gs, bid, "wagon", 60.0)
	_check("one buyer shares one purchase rumor", _count_vehicle(hs) == 1)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	r["heat"] = 0.2  # simulate daily decay between purchases
	_buy(gs, bid, "wagon", 60.0)
	_check("repeat purchase refreshes cooled heat",
		is_equal_approx(float(r.get("heat", 0.0)), 0.5))


func _test_second_buyer_separate_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var b1 := _spawn(gs, "gnomes")
	var b2 := _spawn(gs, "gnomes")
	_buy(gs, int(b1.get("id", 0)), "cart", 35.0)
	_buy(gs, int(b2.get("id", 0)), "carriage", 100.0)
	_check("separate buyers seed separate rumors", _count_vehicle(hs) == 2)


func _test_buyer_proud() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "wagon", 60.0)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	hs._on_heard(buyer, r, {})
	_check("buyer remembers pride",
		_recalled(buyer, "vehicle_proud", int(r.get("id", 0))) > 0.0)
	_check("pride feels happy", _emotion(buyer) == "happy")


func _test_faction_admires() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "wagon", 60.0)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	var mate := _spawn(gs, "gnomes")
	mate["coins"] = 500.0
	hs._on_heard(mate, r, {})
	_check("rich factionmate remembers the news",
		_recalled(mate, "vehicle_news", int(r.get("id", 0))) > 0.0)
	_check("admiration feels happy", _emotion(mate) == "happy")


func _test_poor_envies() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "carriage", 100.0)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	var poor := _spawn(gs, "gnomes")
	poor["coins"] = 5.0
	hs._on_heard(poor, r, {})
	_check("poor factionmate remembers envy",
		_recalled(poor, "vehicle_envy", int(r.get("id", 0))) > 0.0)
	_check("envy feels grumpy", _emotion(poor) == "angry")


func _test_rival_mocks() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "wagon", 60.0)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	var ogre := _spawn(gs, "ogres")
	hs._on_heard(ogre, r, {})
	_check("rival remembers mockery",
		_recalled(ogre, "vehicle_mock", int(r.get("id", 0))) > 0.0)


func _test_unhinged_thrills() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "wagon", 60.0)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	var wild := _spawn(gs, "elves", Vector2.ZERO, _unhinged_mind())
	hs._on_heard(wild, r, {})
	_check("unhinged remembers the thrill",
		_recalled(wild, "vehicle_thrill", int(r.get("id", 0))) > 0.0)
	_check("thrill feels happy", _emotion(wild) == "happy")


func _test_neutral_gets_news() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "wagon", 60.0)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	var elf := _spawn(gs, "elves")
	hs._on_heard(elf, r, {})
	_check("neutral remembers the news",
		_recalled(elf, "vehicle_news", int(r.get("id", 0))) > 0.0)
	_check("news feels happy", _emotion(elf) == "happy")


func _test_opening_reaction() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_open_dealer(gs, "gnomes")
	var r := _rumor(hs, "dealeropened")
	var gnome := _spawn(gs, "gnomes")
	var elf := _spawn(gs, "elves")
	hs._on_heard(gnome, r, {})
	hs._on_heard(elf, r, {})
	_check("dealer's faction notes the opening",
		_recalled(gnome, "vehicle_dealer_news", int(r.get("id", 0))) > 0.0)
	_check("outsiders note the opening too",
		_recalled(elf, "vehicle_dealer_news", int(r.get("id", 0))) > 0.0)


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "wagon", 60.0)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	var mate := _spawn(gs, "gnomes")
	var ogre := _spawn(gs, "ogres")
	var elf := _spawn(gs, "elves")
	var brag: Dictionary = hs._spread_motivation(buyer, r)
	_check("buyer brag-spreads",
		int(brag.get("cap_delta", 0)) == 2
		and float(brag.get("heat_delta", 0.0)) > 0.0)
	var adm: Dictionary = hs._spread_motivation(mate, r)
	_check("factionmate admires-spreads",
		int(adm.get("cap_delta", 0)) == 1)
	var mck: Dictionary = hs._spread_motivation(ogre, r)
	_check("rival mock-spreads",
		int(mck.get("cap_delta", 0)) == 1)
	var straight: Dictionary = hs._spread_motivation(elf, r)
	_check("neutral tells it straight",
		is_equal_approx(float(straight.get("cap_delta", 0.0)), 0.0))
	_open_dealer(gs, "gnomes")
	var ro := _rumor(hs, "dealeropened")
	var o: Dictionary = hs._spread_motivation(mate, ro)
	_check("dealer opening told straight",
		is_equal_approx(float(o.get("cap_delta", 0.0)), 0.0))


func _test_memory_types_registered() -> void:
	var mem = load("res://scripts/sim/memories.gd")
	for t: String in ["vehicle_proud", "vehicle_envy", "vehicle_mock",
			"vehicle_news", "vehicle_thrill", "vehicle_dealer_news"]:
		_check("memory type registered: " + t, t in mem.TYPES)
		_check("memory weight set: " + t, mem.REL_WEIGHT.has(t))


func _test_doubt_immunity() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var buyer := _spawn(gs, "gnomes")
	var bid := int(buyer.get("id", 0))
	_buy(gs, bid, "wagon", 60.0)
	var r := _rumor(hs, "vehiclebought:%d" % bid)
	var teller := _spawn(gs, "gnomes")
	var hearer := _spawn(gs, "gnomes")
	var clean: float = hs._belief(teller, hearer, r)
	var doubters: Array = []
	for i in 24:
		doubters.append(1000 + i)
	r["doubters"] = doubters
	r["distortions"] = 3
	_check("doubt can't dent witnessed wheels",
		is_equal_approx(hs._belief(teller, hearer, r), clean))


func _test_old_save_fallthrough() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	# A kind-"vehicle" rumor with no vehicle_kind (old save) takes the
	# generic reception path — real memory, default handling.
	var r: Dictionary = hs.seed_rumor("Old wheels talk.", "vehicle",
		"oldwheels", 0.5, -1, false, hs.TRUTH_TRUE)
	var gnome := _spawn(gs, "gnomes")
	hs._on_heard(gnome, r, {})
	_check("old vehicle rumor falls through to generic path",
		_recalled(gnome, "heard_rumor", int(r.get("id", 0))) > 0.0)


func _test_signal_connected() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_check("vehicle_bought is wired to the handler",
		gs.bus.is_connected("vehicle_bought",
			Callable(hs, "_on_vehicle_bought")))
