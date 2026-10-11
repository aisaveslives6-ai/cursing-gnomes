extends SceneTree
## Cursing Gnomes — Postworks expansion tests (Jeremy 2026-10-06, Lane 3).
##
## Covers the command-post expansion: garrison orders (assign/recall,
## sovereignty, UI counts), post upgrades (costs, HP, capture slowdown),
## auras (monastery faith ward, crystal attunement, town tithe), sieges
## (detection, starvation drain, capture, lifting), supply (drain, wagon
## resupply, desertion), AI feints, and save/load round-trip.
##
## Run: ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##   --path ~/workspace/godot-cursing-gnomes -s res://tests/test_postworks.gd


var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("  FAIL: ", name)


func _initialize() -> void:
	_test_garrison_assign()
	_test_garrison_sovereignty()
	_test_garrison_ai()
	_test_garrison_recall()
	_test_garrison_ui_count()
	_test_garrison_rejects_civilians()
	_test_upgrade_post()
	_test_upgrade_maxed()
	_test_upgrade_broke()
	_test_upgrade_capture_mult()
	_test_monastery_aura()
	_test_aura_skips_enemies()
	_test_crystal_aura()
	_test_town_tithe()
	_test_siege_detection()
	_test_siege_no_peace()
	_test_siege_starve_drain()
	_test_siege_starvation_capture()
	_test_siege_lifts()
	_test_supply_drain()
	_test_supply_wagon()
	_test_supply_player_no_spend()
	_test_supply_desertion()
	_test_siege_choice_proposal()
	_test_siege_choice_deny_weak()
	_test_feint()
	_test_feint_expiry()
	_test_value_order()
	_test_ai_garrison_topup()
	_test_save_roundtrip()
	print("test_postworks: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## Fresh game: humans = player. Posts + proposals wired.
func _make_game(factions: Array[String] = ["humans", "gnomes"]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	gs.day_number = 10
	var mons := SimMonasteries.new()
	mons.setup(gs)
	gs.monasteries = mons
	var crys := SimDarkCrystals.new()
	crys.setup(gs)
	gs.crystals = crys
	var cps := SimCommandPosts.new()
	cps.setup(gs)
	gs.command_posts = cps
	gs.proposals = SimProposals.new(gs)
	gs.resources.add_resource("humans", "wood", 5000.0, true)
	gs.resources.add_resource("humans", "gold", 5000.0, true)
	gs.resources.add_resource("humans", "food", 5000.0, true)
	gs.resources.add_resource("gnomes", "wood", 5000.0, true)
	gs.resources.add_resource("gnomes", "gold", 5000.0, true)
	gs.resources.add_resource("gnomes", "food", 5000.0, true)
	return gs


func _hall(gs: GameState, faction: String, pos: Vector2,
		bid_name: String = "Testville") -> Dictionary:
	var hall := gs.add_building({"type": "town_hall", "faction": faction,
		"position": pos, "alive": true, "complete": true,
		"hp": 2000.0, "max_hp": 2000.0, "town_id": 100,
		"town_name": bid_name})
	gs.towns[100] = {"id": 100, "name": bid_name, "faction": faction}
	return hall


func _soldier(gs: GameState, faction: String, pos: Vector2,
		job: String = "soldier") -> Dictionary:
	return gs.add_unit({"faction": faction, "job": job, "position": pos,
		"alive": true, "hp": 100.0, "max_hp": 100.0})


func _monastery(gs: GameState, mid: int, owner: String,
		pos: Vector2) -> void:
	(gs.monasteries.monasteries as Array).append({"id": mid,
		"god_id": "auriel", "position": pos, "owner": owner,
		"progress": {}, "contested": false, "contested_by": "",
		"name": "Monastery %d" % mid})


func _crystal(gs: GameState, cid: int, owner: String, pos: Vector2) -> void:
	(gs.crystals.crystals as Array).append({"id": cid,
		"god_id": "vexmor", "position": pos, "owner": owner,
		"progress": {}, "contested": false, "contested_by": "",
		"name": "Crystal %d" % cid})


func _cps(gs: GameState) -> SimCommandPosts:
	return gs.command_posts as SimCommandPosts


# ---- garrisons ---------------------------------------------------------------

func _test_garrison_assign() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	for i in 4:
		_soldier(gs, "humans", Vector2(2000 + i * 10, 500))
	var r: Dictionary = _cps(gs).assign_garrison("humans", "town",
		int(hall["id"]), [], true)
	_check(bool(r.get("ok", false)), "garrison: assign ok")
	_check(int(r.get("assigned", 0)) == 4, "garrison: 4 assigned")
	var marked := 0
	for u in gs.units:
		var ud := u as Dictionary
		var pg := ud.get("post_garrison", {}) as Dictionary
		if int(pg.get("id", -1)) == int(hall["id"]):
			marked += 1
			_check(String((ud.get("player_order", {}) as Dictionary).get(
				"kind", "")) == "garrison", "garrison: order channel")
			_check(ud.has("move_target"), "garrison: move order")
	_check(marked == 4, "garrison: marks on all 4")
	gs.free()


func _test_garrison_sovereignty() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "gnomes", Vector2(1000, 1000))
	_soldier(gs, "gnomes", Vector2(1000, 1000))
	# The (human) player may not garrison the gnomes' post.
	var r: Dictionary = _cps(gs).assign_garrison("gnomes", "town",
		int(hall["id"]), [], true)
	_check(not bool(r.get("ok", false)), "garrison: foreign refused")
	gs.free()


func _test_garrison_ai() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "gnomes", Vector2(1000, 1000))
	for i in 3:
		_soldier(gs, "gnomes", Vector2(1000 + i * 10, 1000))
	# The faction's own brain commanding its own troops: allowed.
	var r: Dictionary = _cps(gs).assign_garrison("gnomes", "town",
		int(hall["id"]), [], false)
	_check(bool(r.get("ok", false)), "garrison: AI self-command ok")
	_check(int(r.get("assigned", 0)) == 3, "garrison: AI assigned 3")
	gs.free()


func _test_garrison_recall() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	for i in 2:
		_soldier(gs, "humans", Vector2(2000 + i * 10, 500))
	_cps(gs).assign_garrison("humans", "town", int(hall["id"]), [], true)
	var r: Dictionary = _cps(gs).recall_garrison("humans", "town",
		int(hall["id"]), true)
	_check(bool(r.get("ok", false)), "garrison: recall ok")
	_check(int(r.get("recalled", 0)) == 2, "garrison: 2 recalled")
	var left := 0
	for u in gs.units:
		if (u as Dictionary).has("post_garrison"):
			left += 1
	_check(left == 0, "garrison: marks cleared")
	gs.free()


func _test_garrison_ui_count() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	for i in 3:
		_soldier(gs, "humans", Vector2(2000 + i * 10, 500))
	_cps(gs).assign_garrison("humans", "town", int(hall["id"]), [], true)
	var p: Dictionary = _cps(gs).find_post("town", int(hall["id"]))
	_check(int(p.get("garrison", -1)) == 3, "garrison: UI count 3")
	_check(String(p.get("aura", "")) != "", "garrison: aura label present")
	gs.free()


func _test_garrison_rejects_civilians() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	var civ := _soldier(gs, "humans", Vector2(2000, 500), "farmer")
	var r: Dictionary = _cps(gs).assign_garrison("humans", "town",
		int(hall["id"]), [int(civ["id"])], true)
	_check(bool(r.get("ok", false)), "garrison: call ok")
	_check(int(r.get("assigned", 0)) == 0, "garrison: civilians rejected")
	gs.free()


# ---- upgrades -----------------------------------------------------------------

func _test_upgrade_post() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	var wood0: float = gs.resources.get_amount("humans", "wood")
	var r: Dictionary = _cps(gs).upgrade_post("humans", "town",
		int(hall["id"]), true)
	_check(bool(r.get("ok", false)), "upgrade: ok")
	_check(int(r.get("level", 0)) == 1, "upgrade: level 1")
	_check(String(r.get("name", "")) == "Palisade", "upgrade: palisade")
	_check(gs.resources.get_amount("humans", "wood") < wood0,
		"upgrade: wood spent")
	_check(float(hall.get("max_hp", 0.0)) > 0.0, "upgrade: max HP set")
	_check(is_equal_approx(float(hall.get("max_hp", 0.0)), 2600.0),
		"upgrade: hall +30% max HP")
	var p: Dictionary = _cps(gs).find_post("town", int(hall["id"]))
	_check(int(p.get("upgrade", 0)) == 1, "upgrade: UI level")
	gs.free()


func _test_upgrade_maxed() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	_cps(gs).upgrades["town:%d" % int(hall["id"])] = 3
	var r: Dictionary = _cps(gs).upgrade_post("humans", "town",
		int(hall["id"]), true)
	_check(not bool(r.get("ok", false)), "upgrade: maxed refused")
	gs.free()


func _test_upgrade_broke() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	gs.resources.add_resource("humans", "wood", -999999.0)
	gs.resources.add_resource("humans", "gold", -999999.0)
	var r: Dictionary = _cps(gs).upgrade_post("humans", "town",
		int(hall["id"]), true)
	_check(not bool(r.get("ok", false)), "upgrade: broke refused")
	_check(String(r.get("reason", "")) == "cannot afford",
		"upgrade: reason afford")
	gs.free()


func _test_upgrade_capture_mult() -> void:
	var gs := _make_game()
	_monastery(gs, 1, "humans", Vector2(2000, 2000))
	_check(_cps(gs).capture_time_mult("monastery", 1) == 1.0,
		"upgrade: base mult 1.0")
	_cps(gs).upgrades["monastery:1"] = 1
	_check(_cps(gs).capture_time_mult("monastery", 1) == 1.5,
		"upgrade: palisade slows capture 1.5x")
	gs.free()


# ---- auras ---------------------------------------------------------------------

func _test_monastery_aura() -> void:
	var gs := _make_game()
	_monastery(gs, 1, "humans", Vector2(2000, 2000))
	var troops: Array = []
	for i in 3:
		troops.append(_soldier(gs, "humans",
			Vector2(2000 + i * 20, 2000)))
	_cps(gs).daily_tick()
	for t in troops:
		_check(int((t as Dictionary).get("faith_aura", -1)) == 10,
			"aura: faith mark")
		_check(float((t as Dictionary).get("shield_hp", 0.0)) >= 30.0,
			"aura: ward granted")
	_check(gs.diplomacy.morale_of("humans") > 70.0,
		"aura: faction morale lifted")
	gs.free()


func _test_aura_skips_enemies() -> void:
	var gs := _make_game()
	_monastery(gs, 1, "humans", Vector2(2000, 2000))
	var foe := _soldier(gs, "gnomes", Vector2(2000, 2000))
	_cps(gs).daily_tick()
	_check(not foe.has("faith_aura"), "aura: enemies not blessed")
	gs.free()


func _test_crystal_aura() -> void:
	var gs := _make_game()
	_crystal(gs, 1, "humans", Vector2(3000, 3000))
	var mage := _soldier(gs, "humans", Vector2(3000, 3000), "mage")
	var grunt := _soldier(gs, "humans", Vector2(3000, 3000))
	_cps(gs).daily_tick()
	_check(int(mage.get("crystal_attuned", -1)) == 10,
		"aura: mage attuned")
	_check(not grunt.has("crystal_attuned"), "aura: grunts not attuned")
	gs.free()


func _test_town_tithe() -> void:
	var gs := _make_game()
	_hall(gs, "humans", Vector2(2000, 500))
	# Park gold below the storage cap so the tithe is visible.
	gs.resources.add_resource("humans", "gold", -999999.0)
	gs.resources.add_resource("humans", "gold", 100.0)
	_cps(gs).daily_tick()
	_check(gs.resources.get_amount("humans", "gold") == 108.0,
		"aura: town tithe +8 gold")
	gs.free()


# ---- sieges ---------------------------------------------------------------------

func _war(gs: GameState) -> void:
	gs.diplomacy.declare_war("gnomes", "humans", "test")


func _test_siege_detection() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	_war(gs)
	for i in 3:
		_soldier(gs, "gnomes", Vector2(2000, 700 + i * 10))
	_cps(gs).daily_tick()
	var s: Dictionary = _cps(gs).siege_of("town", int(hall["id"]))
	_check(not s.is_empty(), "siege: detected")
	_check(String(s.get("attacker", "")) == "gnomes", "siege: attacker")
	gs.free()


func _test_siege_no_peace() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	for i in 5:
		_soldier(gs, "gnomes", Vector2(2000, 700 + i * 10))
	_cps(gs).daily_tick()
	_check(_cps(gs).siege_of("town", int(hall["id"])).is_empty(),
		"siege: no siege in peacetime")
	gs.free()


func _test_siege_starve_drain() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	_war(gs)
	for i in 3:
		_soldier(gs, "gnomes", Vector2(2000, 700 + i * 10))
	_cps(gs).daily_tick()
	_cps(gs).set_siege_mode("gnomes", "town", int(hall["id"]), "starve")
	var sup0 := _cps(gs).supply_of("town", int(hall["id"]))
	_cps(gs).daily_tick()
	var s: Dictionary = _cps(gs).siege_of("town", int(hall["id"]))
	_check(float(s.get("integrity", 100.0)) < 100.0,
		"siege: integrity drains")
	_check(_cps(gs).supply_of("town", int(hall["id"])) < sup0,
		"siege: supply drains")
	gs.free()


func _test_siege_starvation_capture() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	_war(gs)
	for i in 3:
		_soldier(gs, "gnomes", Vector2(2000, 700 + i * 10))
	_cps(gs).daily_tick()
	_cps(gs).set_siege_mode("gnomes", "town", int(hall["id"]), "starve")
	(_cps(gs).sieges["town:%d" % int(hall["id"])] as Dictionary)[
		"integrity"] = 1.0
	# Keep the gnomes broke so their AI doesn't upgrade the prize mid-test.
	gs.resources.add_resource("gnomes", "wood", -999999.0)
	gs.resources.add_resource("gnomes", "gold", -999999.0)
	_cps(gs).daily_tick()
	_check(String(hall.get("faction", "")) == "gnomes",
		"siege: starved hall flips")
	_check(float(hall.get("hp", 0.0)) == 500.0,
		"siege: flip at 25% HP")
	_check(_cps(gs).siege_of("town", int(hall["id"])).is_empty(),
		"siege: record cleared after fall")
	gs.free()


func _test_siege_lifts() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	_war(gs)
	var foes: Array = []
	for i in 3:
		foes.append(_soldier(gs, "gnomes", Vector2(2000, 700 + i * 10)))
	_cps(gs).daily_tick()
	_check(not _cps(gs).siege_of("town", int(hall["id"])).is_empty(),
		"siege: begins")
	for f in foes:
		(f as Dictionary)["position"] = Vector2(50, 50)
	_cps(gs).daily_tick()
	_cps(gs).daily_tick()
	_check(_cps(gs).siege_of("town", int(hall["id"])).is_empty(),
		"siege: lifts when attackers leave")
	gs.free()


# ---- supply ---------------------------------------------------------------------

func _test_supply_drain() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	_check(_cps(gs).supply_of("town", int(hall["id"])) == 100.0,
		"supply: starts full")
	_cps(gs).daily_tick()
	_check(_cps(gs).supply_of("town", int(hall["id"])) < 100.0,
		"supply: drains daily")
	gs.free()


func _test_supply_wagon() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "gnomes", Vector2(1000, 1000))
	_cps(gs).supply["town:%d" % int(hall["id"])] = 10.0
	_cps(gs).daily_tick()
	_check(_cps(gs).supply_of("town", int(hall["id"])) > 10.0,
		"supply: AI wagon resupplies")
	gs.free()


func _test_supply_player_no_spend() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	_cps(gs).supply["town:%d" % int(hall["id"])] = 10.0
	_cps(gs).daily_tick()
	# Drains to 9, but the advisers never spend the ruler's treasury.
	_check(_cps(gs).supply_of("town", int(hall["id"])) == 9.0,
		"supply: player treasury untouched")
	gs.free()


func _test_supply_desertion() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	seed(20261006)
	for i in 4:
		_soldier(gs, "humans", Vector2(2000 + i * 10, 500))
	_cps(gs).assign_garrison("humans", "town", int(hall["id"]), [], true)
	_cps(gs).supply["town:%d" % int(hall["id"])] = 0.0
	for d in 60:
		_cps(gs).daily_tick()
	var left := 0
	for u in gs.units:
		if (u as Dictionary).has("post_garrison"):
			left += 1
	_check(left < 4, "supply: starving garrison deserts")
	gs.free()


# ---- AI: feints ------------------------------------------------------------------

func _test_siege_choice_proposal() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	_war(gs)
	for i in 5:
		_soldier(gs, "gnomes", Vector2(2000, 700 + i * 10))
	_cps(gs).daily_tick()
	# The AI attacker's choice auto-resolves through the proposal protocol.
	var found := {}
	for p in gs.proposals.proposals:
		if String(p.get("kind", "")) == "siege_choice":
			found = p
	_check(not found.is_empty(), "siege: choice proposal filed")
	_check(String(found.get("status", "")) == "executed",
		"siege: AI choice auto-resolved")
	var s: Dictionary = _cps(gs).siege_of("town", int(hall["id"]))
	_check(String(s.get("mode", "undecided")) != "undecided",
		"siege: approved doctrine applied")
	gs.free()


func _test_siege_choice_deny_weak() -> void:
	var gs := _make_game()
	var hall := _hall(gs, "humans", Vector2(2000, 500))
	_war(gs)
	for i in 3:
		_soldier(gs, "gnomes", Vector2(2000, 700 + i * 10))
	_cps(gs).daily_tick()
	var found := {}
	for p in gs.proposals.proposals:
		if String(p.get("kind", "")) == "siege_choice":
			found = p
	_check(String(found.get("status", "")) == "denied",
		"siege: weak force denied")
	var s: Dictionary = _cps(gs).siege_of("town", int(hall["id"]))
	_check(String(s.get("mode", "undecided")) == "undecided",
		"siege: denied siege stays undecided")
	gs.free()

func _test_feint() -> void:
	var gs := _make_game()
	_hall(gs, "humans", Vector2(2000, 500))
	_monastery(gs, 1, "humans", Vector2(1000, 1000))
	_crystal(gs, 1, "humans", Vector2(1500, 1500))
	_war(gs)
	for i in 14:
		_soldier(gs, "gnomes", Vector2(3000 + i * 10, 3000))
	_cps(gs).daily_tick()
	var feinted := 0
	var main_hit := 0
	for u in gs.units:
		var ud := u as Dictionary
		if String(ud.get("faction", "")) != "gnomes":
			continue
		var pm := ud.get("post_march", {}) as Dictionary
		if pm.is_empty():
			continue
		if bool(ud.get("feint", false)):
			feinted += 1
			_check(String(pm.get("kind", "")) == "crystal",
				"feint: probe hits the weak low-value post")
		elif String(pm.get("kind", "")) == "monastery":
			main_hit += 1
	_check(feinted == 3, "feint: 3-troop probe")
	_check(main_hit == 4, "feint: main blow concentrates (4)")
	gs.free()


func _test_feint_expiry() -> void:
	var gs := _make_game()
	var u := _soldier(gs, "gnomes", Vector2(3000, 3000))
	u["post_march"] = {"kind": "crystal", "id": 1}
	u["feint"] = true
	u["feint_day"] = 10
	gs.day_number = 14
	_cps(gs).daily_tick()
	_check(not u.has("feint"), "feint: expires after 3 days")
	_check(not u.has("post_march"), "feint: march mark cleared")
	gs.free()


func _test_value_order() -> void:
	_check(float(SimCommandPosts.VALUE["monastery"]) \
		> float(SimCommandPosts.VALUE["town"]), "value: monastery > town")
	_check(float(SimCommandPosts.VALUE["town"]) \
		> float(SimCommandPosts.VALUE["crystal"]), "value: town > crystal")
	# No game needed: constants only.


func _test_ai_garrison_topup() -> void:
	var gs := _make_game(["humans", "gnomes", "ogres"])
	_crystal(gs, 1, "gnomes", Vector2(1000, 1000))
	gs.resources.add_resource("ogres", "wood", 5000.0, true)
	gs.resources.add_resource("ogres", "gold", 5000.0, true)
	gs.resources.add_resource("ogres", "food", 5000.0, true)
	gs.diplomacy.declare_war("ogres", "gnomes", "test")
	for i in 3:
		_soldier(gs, "ogres", Vector2(1000, 1100 + i * 10))
	for i in 4:
		_soldier(gs, "gnomes", Vector2(500 + i * 10, 500))
	_cps(gs).daily_tick()
	_check(_cps(gs).garrison_of("crystal", 1).size() > 0,
		"ai: threatened post gets garrison top-up")
	gs.free()


# ---- save/load ---------------------------------------------------------------------

func _test_save_roundtrip() -> void:
	var gs := _make_game()
	var cps := _cps(gs)
	cps.upgrades["town:1"] = 2
	cps.supply["town:1"] = 55.5
	cps.sieges["town:1"] = {"attacker": "gnomes", "mode": "starve"}
	cps.garrison_orders["town:1"] = {"faction": "humans"}
	cps._feint_day["gnomes"] = 12
	var d: Dictionary = cps.to_dict()
	var cps2 := SimCommandPosts.new()
	cps2.setup(gs)
	cps2.from_dict(d)
	_check(int(cps2.upgrades.get("town:1", 0)) == 2, "save: upgrades")
	_check(float(cps2.supply.get("town:1", 0.0)) == 55.5, "save: supply")
	_check(String((cps2.sieges.get("town:1", {}) as Dictionary).get(
		"mode", "")) == "starve", "save: sieges")
	_check((cps2.garrison_orders.get("town:1", {}) as Dictionary).get(
		"faction", "") == "humans", "save: garrisons")
	_check(int(cps2._feint_day.get("gnomes", 0)) == 12, "save: feint day")
	# Old saves (capture_log only) still load.
	var cps3 := SimCommandPosts.new()
	cps3.setup(gs)
	cps3.from_dict({"capture_log": []})
	_check(cps3.upgrades.is_empty(), "save: old save defaults")
	gs.free()
