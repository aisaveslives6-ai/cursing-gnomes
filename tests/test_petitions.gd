extends SceneTree
## Cursing Gnomes — tool/equipment + shop petition chain headless tests
## (Jeremy 2026-10-04).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_petitions.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: tool defs (HTML-verbatim names/prices), job->tool mapping,
## inventory/equip, tool purchase (gold deducted, equipped), petition filing
## when no store exists, AI adviser auto-approve when affordable, deny when
## broke, build_request signal for the player faction, player Approve/Deny
## resolution, adviser daily proactivity, and open-petition dedupe.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _build_requests: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes petition-chain tests ===")
	_test_tool_defs()
	_test_tool_for_job()
	_test_inventory_and_equip()
	_test_buy_tool()
	_test_petition_filed_when_no_store()
	_test_ai_approves_when_affordable()
	_test_ai_denies_when_broke()
	_test_player_gets_build_request()
	_test_player_resolve()
	_test_advisor_proactivity()
	_test_advisor_proactivity_all_shops()
	_test_advisor_shop_thresholds()
	_test_player_shop_popup()
	_test_petition_dedupe()
	_test_shop_walk_setup()
	_test_deny_cooldown()
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


## Fresh headless game: player = humans; petitions wired like World does.
func _make_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])
	gs.petitions = SimPetitions.new(gs)
	return gs


func _unit(gs: GameState, faction: String, job: String,
		pos: Vector2 = Vector2(500, 500)) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 55.0})


func _adviser(gs: GameState, faction: String) -> Dictionary:
	var u := _unit(gs, faction, "worker", Vector2(520, 520))
	SimArmy.assign_gov_role(u, "adviser")
	return u


func _store(gs: GameState, faction: String, btype: String = "shop") -> Dictionary:
	return gs.add_building({"type": btype, "faction": faction, "town_id": 1,
		"position": Vector2(600, 600), "alive": true, "complete": true,
		"progress": 1.0, "hp": 400.0, "max_hp": 400.0})


func _rich(gs: GameState, faction: String) -> void:
	gs.resources.add_resource(faction, "gold", 500.0)
	gs.resources.add_resource(faction, "wood", 500.0)


## --- Tool catalog ------------------------------------------------------------

func _test_tool_defs() -> void:
	# HTML fix79 TOOL_DEFS54, verbatim.
	_check("axe name", SimPetitions.tool_name("axe") == "Woodsman's Axe")
	_check("axe price", SimPetitions.tool_price("axe") == 25.0)
	_check("pickaxe name", SimPetitions.tool_name("pickaxe") == "Miner's Pickaxe")
	_check("pickaxe price", SimPetitions.tool_price("pickaxe") == 30.0)
	_check("hoe", SimPetitions.tool_name("hoe") == "Field Hoe"
		and SimPetitions.tool_price("hoe") == 18.0)
	_check("hammer", SimPetitions.tool_name("hammer") == "Smith's Hammer"
		and SimPetitions.tool_price("hammer") == 22.0)
	_check("fishingrod", SimPetitions.tool_name("fishingrod") == "Fishing Rod"
		and SimPetitions.tool_price("fishingrod") == 15.0)
	_check("unknown price", SimPetitions.tool_price("laser") == -1.0)


func _test_tool_for_job() -> void:
	# HTML TOOL_FOR_TASK54 ported to Godot job keys.
	_check("miner->pickaxe", SimPetitions.tool_for_job("miner") == "pickaxe")
	_check("woodcutter->axe", SimPetitions.tool_for_job("woodcutter") == "axe")
	_check("fisher->rod", SimPetitions.tool_for_job("fisher") == "fishingrod")
	_check("farmer->hoe", SimPetitions.tool_for_job("farmer") == "hoe")
	_check("builder->hammer", SimPetitions.tool_for_job("builder") == "hammer")
	_check("warrior->none", SimPetitions.tool_for_job("warrior") == "")


## --- Inventory / equipment ---------------------------------------------------

func _test_inventory_and_equip() -> void:
	var gs := _make_game()
	var u := _unit(gs, "gnomes", "miner")
	_check("no tool at spawn", not SimPetitions.unit_has_tool(u, "pickaxe"))
	_check("equip fails unowned", not SimPetitions.equip_tool(u, "pickaxe"))
	var inv: Dictionary = SimPetitions.ensure_inventory(u)
	inv["pickaxe"] = 1
	_check("has in pack", SimPetitions.unit_has_tool(u, "pickaxe"))
	_check("equip works", SimPetitions.equip_tool(u, "pickaxe"))
	_check("equipped set", String(u.get("equipped_tool", "")) == "pickaxe")
	_check("pack decremented", int(inv.get("pickaxe", -1)) == 0)
	inv["axe"] = 1
	_check("swap equips axe", SimPetitions.equip_tool(u, "axe"))
	_check("old tool back in pack",
		String(u.get("equipped_tool", "")) == "axe"
		and int(inv.get("pickaxe", 0)) == 1)
	gs.queue_free()


func _test_buy_tool() -> void:
	var gs := _make_game()
	_rich(gs, "gnomes")
	var u := _unit(gs, "gnomes", "miner")
	var before: float = gs.resources.get_amount("gnomes", "gold")
	_check("buy succeeds", gs.petitions.buy_tool(u, "pickaxe"))
	_check("gold deducted",
		is_equal_approx(gs.resources.get_amount("gnomes", "gold"),
			before - 30.0))
	_check("equipped after buy",
		String(u.get("equipped_tool", "")) == "pickaxe")
	_check("has after buy", SimPetitions.unit_has_tool(u, "pickaxe"))
	gs.queue_free()


## --- Petition filing ---------------------------------------------------------

func _test_petition_filed_when_no_store() -> void:
	var gs := _make_game()
	_rich(gs, "gnomes")
	var miner := _unit(gs, "gnomes", "miner")
	# No shop building anywhere: the unit petitions for a general store.
	# (AI faction + full treasury: the adviser approves immediately.)
	var res: String = gs.petitions.try_supply_tool(miner)
	_check("petitioned", res == "petitioned")
	_check("petition filed", gs.petitions.petitions.size() == 1)
	var p: Dictionary = gs.petitions.petitions[0]
	_check("petition fields",
		String(p.get("faction", "")) == "gnomes"
		and String(p.get("building_type", "")) == "general_store"
		and int(p.get("from_unit_id", 0)) == int(miner.get("id", 0))
		and String(p.get("origin", "")) == "unit")
	gs.queue_free()


## --- AI adviser review -------------------------------------------------------

func _test_ai_approves_when_affordable() -> void:
	var gs := _make_game()
	_rich(gs, "gnomes")
	_adviser(gs, "gnomes")
	var miner := _unit(gs, "gnomes", "miner")
	var p: Dictionary = gs.petitions.request_shop_build(
		"gnomes", "general_store", int(miner.get("id", 0)), "unit")
	_check("ai approved", String(p.get("status", "")) == "approved")
	_check("blueprint placed", int(p.get("building_id", -1)) >= 0)
	var found := false
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "general_store" \
				and String(b.get("faction", "")) == "gnomes" \
				and not bool(b.get("complete", false)):
			found = true
	_check("general_store blueprint in world", found)
	# Cost was paid: 500 - 40 gold, 500 - 90 wood.
	_check("gold spent",
		is_equal_approx(gs.resources.get_amount("gnomes", "gold"), 460.0))
	_check("wood spent",
		is_equal_approx(gs.resources.get_amount("gnomes", "wood"), 410.0))
	gs.queue_free()


func _test_ai_denies_when_broke() -> void:
	var gs := _make_game()
	# Ledgers start at 0: the adviser must deny.
	_adviser(gs, "gnomes")
	_unit(gs, "gnomes", "miner")
	var p: Dictionary = gs.petitions.request_shop_build(
		"gnomes", "general_store", -1, "unit")
	_check("ai denied", String(p.get("status", "")) == "denied")
	_check("deny reason", String(p.get("reason", "")) == "unaffordable")
	var found := false
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "general_store":
			found = true
	_check("no blueprint placed", not found)
	gs.queue_free()


## --- Player faction: phone popup ---------------------------------------------

func _test_player_gets_build_request() -> void:
	var gs := _make_game()
	_rich(gs, "humans")  # player faction
	_adviser(gs, "humans")
	_build_requests.clear()
	gs.bus.build_request.connect(func(p: Dictionary) -> void:
		_build_requests.append(p))
	_unit(gs, "humans", "miner")
	var p: Dictionary = gs.petitions.request_shop_build(
		"humans", "general_store", -1, "unit")
	_check("player petition stays open",
		String(p.get("status", "")) == "open")
	_check("build_request emitted", _build_requests.size() == 1)
	_check("emitted petition id matches",
		int((_build_requests[0] as Dictionary).get("id", 0))
			== int(p.get("id", 0)))
	gs.queue_free()


func _test_player_resolve() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_adviser(gs, "humans")
	_unit(gs, "humans", "miner")
	var p: Dictionary = gs.petitions.request_shop_build(
		"humans", "general_store", -1, "unit")
	var pid := int(p.get("id", 0))
	_check("approve resolves", gs.petitions.resolve_petition(pid, true))
	_check("approved", String(p.get("status", "")) == "approved")
	_check("blueprint placed", int(p.get("building_id", -1)) >= 0)
	# Deciding twice is a no-op.
	_check("double resolve rejected",
		not gs.petitions.resolve_petition(pid, false))
	# A denied petition places nothing.
	var p2: Dictionary = gs.petitions.request_shop_build(
		"humans", "blacksmith", -1, "unit")
	var pid2 := int(p2.get("id", 0))
	gs.petitions.resolve_petition(pid2, false)
	_check("deny status", String(p2.get("status", "")) == "denied")
	_check("deny places nothing", int(p2.get("building_id", -1)) == -1)
	gs.queue_free()


## --- Adviser proactivity -----------------------------------------------------

func _test_advisor_proactivity() -> void:
	var gs := _make_game()
	_rich(gs, "ogres")
	_adviser(gs, "ogres")
	_unit(gs, "ogres", "miner")  # needs a pickaxe, has none
	gs.petitions._on_day(2, false)
	# AI faction + full treasury: the adviser files and it is approved.
	var filed := false
	for p: Dictionary in gs.petitions.petitions:
		if String(p.get("origin", "")) == "advisor" \
				and String(p.get("building_type", "")) == "general_store" \
				and String(p.get("faction", "")) == "ogres":
			filed = true
	_check("advisor filed petition", filed)
	# No petition when a shop already exists.
	_store(gs, "ogres", "shop")
	gs.petitions.petitions.clear()
	gs.petitions._on_day(3, false)
	_check("no petition when store exists",
		gs.petitions.open_petition("ogres", "general_store").is_empty())
	gs.queue_free()


func _test_advisor_proactivity_all_shops() -> void:
	# Jeremy 2026-10-04: "All shops should work like this" — the financial
	# adviser proactively petitions for weaponsmiths and restaurants too,
	# not just the general store. (Filed petitions auto-approve for AI
	# factions, so we look in the petition log, not just the open queue.)
	var gs := _make_game()
	_rich(gs, "ogres")
	gs.resources.add_resource("ogres", "oil", 500.0)
	_adviser(gs, "ogres")
	for i in range(3):
		_unit(gs, "ogres", "soldier", Vector2(500 + i * 10, 500))
	gs.petitions._on_day(4, false)
	var smith := _filed(gs, "ogres", "weaponsmith")
	_check("smith petition filed", not smith.is_empty())
	_check("smith approved for AI", String(smith.get("status", "")) == "approved")
	_check("smith blueprint placed", int(smith.get("building_id", -1)) >= 0)
	# The blueprint is still in flight: no duplicate petition tomorrow.
	gs.petitions._on_day(5, false)
	_check("no duplicate smith while in flight",
		_filed_count(gs, "ogres", "weaponsmith") == 1)
	# Grow the faction: a restaurant petition follows at 10+ population.
	for i in range(7):
		_unit(gs, "ogres", "worker", Vector2(600 + i * 5, 600))
	gs.petitions._on_day(6, false)
	var resto := _filed(gs, "ogres", "restaurant")
	_check("restaurant petition filed", not resto.is_empty())
	_check("restaurant approved for AI",
		String(resto.get("status", "")) == "approved")
	gs.queue_free()


## The most recent petition record for a faction+type, or {}.
func _filed(gs: GameState, faction: String, btype: String) -> Dictionary:
	var out: Dictionary = {}
	for p: Dictionary in gs.petitions.petitions:
		if String(p.get("faction", "")) == faction \
				and String(p.get("building_type", "")) == btype:
			out = p
	return out


func _filed_count(gs: GameState, faction: String, btype: String) -> int:
	var n := 0
	for p: Dictionary in gs.petitions.petitions:
		if String(p.get("faction", "")) == faction \
				and String(p.get("building_type", "")) == btype:
			n += 1
	return n


func _test_advisor_shop_thresholds() -> void:
	# Below the need thresholds the adviser stays quiet (no popup spam).
	var gs := _make_game()
	_rich(gs, "gnomes")
	gs.resources.add_resource("gnomes", "oil", 500.0)
	_adviser(gs, "gnomes")
	_unit(gs, "gnomes", "soldier")
	_unit(gs, "gnomes", "soldier")  # 2 < 3: no war band yet
	for i in range(6):
		_unit(gs, "gnomes", "worker")  # 9 pop < 10
	gs.petitions._on_day(4, false)
	_check("no smith below threshold",
		gs.petitions.open_petition("gnomes", "weaponsmith").is_empty())
	_check("no restaurant below threshold",
		gs.petitions.open_petition("gnomes", "restaurant").is_empty())
	# The general-store trigger is unchanged: a tool-less miner + no shop.
	_unit(gs, "gnomes", "miner")
	gs.petitions._on_day(5, false)
	_check("store trigger intact",
		not _filed(gs, "gnomes", "general_store").is_empty())
	gs.queue_free()


func _test_player_shop_popup() -> void:
	# Player faction: the adviser asks via the phone popup (build_request),
	# Jeremy taps Approve/Deny — never auto-built.
	var gs := _make_game()
	_rich(gs, "humans")  # player faction
	gs.resources.add_resource("humans", "oil", 500.0)
	_adviser(gs, "humans")
	_build_requests.clear()
	gs.bus.build_request.connect(func(p: Dictionary) -> void:
		_build_requests.append(p))
	for i in range(3):
		_unit(gs, "humans", "soldier", Vector2(500 + i * 10, 500))
	gs.petitions._on_day(4, false)
	var asked := false
	for p in _build_requests:
		if String((p as Dictionary).get("building_type", "")) == "weaponsmith":
			asked = true
	_check("player asked about weaponsmith", asked)
	var smith = gs.petitions.open_petition("humans", "weaponsmith")
	_check("player smith stays open", String(smith.get("status", "")) == "open")
	gs.queue_free()


## --- Dedupe + shop walk ------------------------------------------------------

func _test_petition_dedupe() -> void:
	var gs := _make_game()
	_rich(gs, "gnomes")
	_adviser(gs, "gnomes")
	var a := _unit(gs, "gnomes", "miner")
	var b := _unit(gs, "gnomes", "woodcutter")
	var p1: Dictionary = gs.petitions.request_shop_build(
		"gnomes", "blacksmith", int(a.get("id", 0)), "unit")
	# Second unit's petition for the same type returns the open one.
	var p2: Dictionary = gs.petitions.request_shop_build(
		"gnomes", "blacksmith", int(b.get("id", 0)), "unit")
	_check("dedupe same id", int(p1.get("id", 0)) == int(p2.get("id", 0)))
	_check("one petition total", gs.petitions.petitions.size() == 1)
	gs.queue_free()


func _test_shop_walk_setup() -> void:
	var gs := _make_game()
	_rich(gs, "gnomes")
	_adviser(gs, "gnomes")
	var shop := _store(gs, "gnomes", "general_store")
	var miner := _unit(gs, "gnomes", "miner", Vector2(100, 100))
	var res: String = gs.petitions.try_supply_tool(miner)
	_check("walks to shop", res == "to_shop")
	_check("work_state set", String(miner.get("work_state", "")) == "to_shop")
	_check("shop target", int(miner.get("_shop_target", -1))
		== int(shop.get("id", -1)))
	_check("tool wanted", String(miner.get("_tool_wanted", "")) == "pickaxe")
	_check("target pos is shop",
		(miner.get("work_target_pos", Vector2.ZERO) as Vector2)
			== (shop.get("position", Vector2.ZERO) as Vector2))
	gs.queue_free()


## --- Denial cooldowns ----------------------------------------------------------

func _test_deny_cooldown() -> void:
	var gs := _make_game()
	_rich(gs, "humans")  # player faction
	_adviser(gs, "humans")
	_unit(gs, "humans", "miner")
	var p: Dictionary = gs.petitions.request_shop_build(
		"humans", "general_store", -1, "unit")
	var pid := int(p.get("id", 0))
	_check("player petition open", String(p.get("status", "")) == "open")
	gs.petitions.resolve_petition(pid, false)  # Jeremy taps Deny.
	# Re-filing the same day returns nothing (no popup spam).
	var p2: Dictionary = gs.petitions.request_shop_build(
		"humans", "general_store", -1, "unit")
	_check("deny cooldown blocks refile", p2.is_empty())
	# Three days later the adviser may ask again.
	gs.day_number += 3
	var p3: Dictionary = gs.petitions.request_shop_build(
		"humans", "general_store", -1, "unit")
	_check("cooldown expires", not p3.is_empty())
	# AI denials retry after one day.
	var gs2 := _make_game()
	_adviser(gs2, "gnomes")
	_unit(gs2, "gnomes", "miner")  # broke: unaffordable -> denied
	gs2.petitions.request_shop_build("gnomes", "general_store", -1, "unit")
	var q2: Dictionary = gs2.petitions.request_shop_build(
		"gnomes", "general_store", -1, "unit")
	_check("ai deny cooldown blocks", q2.is_empty())
	gs2.day_number += 1
	_rich(gs2, "gnomes")  # treasury recovered
	var q3: Dictionary = gs2.petitions.request_shop_build(
		"gnomes", "general_store", -1, "unit")
	_check("ai refiles next day", not q3.is_empty())
	_check("ai approves when rich", String(q3.get("status", "")) == "approved")
	gs.queue_free()
	gs2.queue_free()


## --- Save/load round-trip --------------------------------------------------------

func _test_save_load() -> void:
	var gs := _make_game()
	_rich(gs, "humans")
	_adviser(gs, "humans")
	_unit(gs, "humans", "miner")
	var p: Dictionary = gs.petitions.request_shop_build(
		"humans", "general_store", -1, "unit")
	_check("open before save", String(p.get("status", "")) == "open")
	var data: Dictionary = gs.petitions.to_dict()
	var gs2 := _make_game()
	gs2.petitions.from_dict(data)
	_check("petition restored", gs2.petitions.petitions.size() == 1)
	var rp: Dictionary = gs2.petitions.petitions[0]
	_check("fields survive",
		String(rp.get("building_type", "")) == "general_store"
		and String(rp.get("status", "")) == "open")
	_check("re-ask armed after load", not bool(rp.get("asked_player", true)))
	_check("seq survives",
		int(gs2.petitions._petition_seq) == int(gs.petitions._petition_seq))
	gs.queue_free()
	gs2.queue_free()
