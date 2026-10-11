extends SceneTree
## Cursing Gnomes — life-sim tests (Jeremy 2026-10-04: NPC life simulation).
##
## Covers the four life-sim work items:
##   1. Active gathering — gatherers seek deposits, gather until full or
##      depleted, then haul back.
##   2. Daily routines — off-shift units rest/socialize instead of freezing.
##   3. Population control — Spawner.faction_needs_unit gates training.
##   4. Housing buying — units with coins buy for-sale homes and move in.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_life_sim.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes life-sim tests ===")
	_test_gather_task_assigned()
	_test_gather_until_depleted_then_haul()
	_test_no_gather_when_no_deposits()
	_test_offshift_downtime_rest()
	_test_offshift_downtime_socialize()
	_test_needs_idle_workers()
	_test_needs_military_threat()
	_test_needs_countryside_full()
	_test_home_purchase()
	_test_buy_flag_cleared()
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


## Fresh game + systems bundle used by every test.
func _new_world(factions: Array[String]) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	var housing := SimHousing.new(gs)
	gs.housing = housing  # world.gd normally wires this
	var sys := {
		"gs": gs,
		"buildings": SimBuildings.new(gs),
		"ai": WorkerAI.new(gs),
		"housing": housing,
	}
	return sys


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


## --- 1. Active gathering ---------------------------------------------------

func _test_gather_task_assigned() -> void:
	var w := _new_world(["humans"])
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var bs: SimBuildings = w["buildings"]
	# Jeremy 2026-10-05: oil rocks are gone (oil comes from pumps) —
	# miners work gold veins now.
	var site: Dictionary = gs.add_work_site({
		"kind": "gold_vein", "position": Vector2(100, 100), "amount": 50.0})
	var u: Dictionary = gs.spawner.spawn_unit("humans", "miner", -1,
		Vector2(90, 100))
	ai.tick_unit(u, bs, 1.0)  # idle -> pick task
	_check("gather: miner assigned to_resource",
		String(u.get("work_state", "")) == "to_resource")
	_check("gather: miner targets the vein",
		int(u.get("work_site", -1)) == int(site.get("id", -2)))
	ai.tick_unit(u, bs, 1.0)  # arrive -> gathering
	_check("gather: miner gathering on arrival",
		String(u.get("work_state", "")) == "gathering")
	ai.tick_unit(u, bs, 1.0)  # gather tick
	var carrying: Dictionary = u.get("carrying", {})
	_check("gather: miner hauls gold from vein",
		float(carrying.get("gold", 0.0)) > 0.0)
	_check("gather: vein depleted by the swing",
		float(site.get("amount", 50.0)) < 50.0)
	_free_world(w)


func _test_gather_until_depleted_then_haul() -> void:
	var w := _new_world(["humans"])
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var bs: SimBuildings = w["buildings"]
	var site: Dictionary = gs.add_work_site({
		"kind": "tree", "position": Vector2(200, 200), "amount": 5.0})
	var u: Dictionary = gs.spawner.spawn_unit("humans", "woodcutter", -1,
		Vector2(195, 200))
	u["work_state"] = "gathering"
	u["work_site"] = int(site.get("id", -1))
	u["carrying"] = {}
	# Jeremy 2026-10-05: trees no longer trickle wood into inventories.
	# Chopping damages the tree; when chopped through it is felled and
	# bursts into wood pickups.
	for i: int in range(30):
		if float(site.get("amount", 0.0)) <= 0.0:
			break
		ai.tick_unit(u, bs, 1.0)
	_check("gather: tree depleted by continuous work",
		float(site.get("amount", 1.0)) <= 0.0)
	_check("gather: tree felled", bool(site.get("felled", false)))
	_check("gather: no trickle into inventory while chopping",
		float((u.get("carrying", {}) as Dictionary).get("wood", 0.0)) == 0.0)
	_check("gather: burst into wood pickups", not gs.pickups.is_empty())
	var pickups_before: int = gs.pickups.size()
	# The chopper collects the burst by walking over it, then hauls it back
	# (no hall, so the drop-off credits the ledger directly — collection
	# and haul happen across these ticks).
	var wood_before: float = gs.resources.get_amount("humans", "wood")
	ai.tick_unit(u, bs, 1.0)
	_check("gather: woodcutter collected the pickups",
		gs.pickups.size() < pickups_before)
	ai.tick_unit(u, bs, 1.0)
	_check("gather: hauled wood reached the faction ledger",
		gs.resources.get_amount("humans", "wood") > wood_before)
	_check("gather: carrying cleared after haul",
		(u.get("carrying", {}) as Dictionary).is_empty())
	_check("gather: haul paid a personal wage",
		float(u.get("coins", 0.0)) > 0.0)
	# Full inventory mid-gather also triggers the haul.
	u["work_state"] = "gathering"
	u["carrying"] = {"wood": 10.0}
	var coins_before: float = float(u.get("coins", 0.0))
	ai.tick_unit(u, bs, 1.0)
	_check("gather: full inventory stops gathering",
		String(u.get("work_state", "")) != "gathering")
	_check("gather: full-inventory haul paid a wage",
		float(u.get("coins", 0.0)) > coins_before)
	_free_world(w)


func _test_no_gather_when_no_deposits() -> void:
	var w := _new_world(["humans"])
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var bs: SimBuildings = w["buildings"]
	var u: Dictionary = gs.spawner.spawn_unit("humans", "woodcutter", -1,
		Vector2(300, 300))
	ai.tick_unit(u, bs, 1.0)
	_check("gather: woodcutter idles when no trees exist",
		String(u.get("work_state", "")) == "idle")
	_free_world(w)


## --- 2. Daily routines -----------------------------------------------------

func _test_offshift_downtime_rest() -> void:
	var w := _new_world(["humans"])
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(400, 400))
	u["urges"] = {"hunger": 60.0, "energy": 20.0, "hygiene": 60.0,
		"social": 60.0, "mood": 60.0, "bladder": 60.0}
	u["work_state"] = "off_shift"
	ai.tick_off_shift(u, 1.0)
	_check("downtime: tired worker picks the rest plan",
		String((u.get("_downtime", {}) as Dictionary).get("plan", "")) == "rest")
	_check("downtime: resting recovers energy",
		float((u.get("urges", {}) as Dictionary).get("energy", 0.0)) > 20.0)
	# A fresh plan is picked each off-shift, and cleared on shift resume.
	u.erase("_downtime")
	ai.tick_off_shift(u, 1.0)
	_check("downtime: plan re-picked while still off shift",
		not (u.get("_downtime", {}) as Dictionary).is_empty())
	_free_world(w)


func _test_offshift_downtime_socialize() -> void:
	var w := _new_world(["humans"])
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	# An inn in reach of the lonely worker.
	var inn: Dictionary = gs.add_building({
		"type": "inn", "faction": "humans", "town_id": -1,
		"position": Vector2(900, 400), "alive": true, "complete": true,
		"residents": []})
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(400, 400))
	u["urges"] = {"hunger": 60.0, "energy": 80.0, "hygiene": 60.0,
		"social": 20.0, "mood": 40.0, "bladder": 60.0}
	u["work_state"] = "off_shift"
	ai.tick_off_shift(u, 1.0)
	_check("downtime: lonely worker picks the socialize plan",
		String((u.get("_downtime", {}) as Dictionary).get("plan", "")) == "socialize")
	_check("downtime: socialize target is the inn",
		((u.get("_downtime", {}) as Dictionary).get("target", Vector2.ZERO)
			as Vector2).distance_to(inn.get("position", Vector2.ZERO)) < 1.0)
	var pos_before: Vector2 = u.get("position", Vector2.ZERO)
	ai.tick_off_shift(u, 1.0)
	_check("downtime: worker walks toward the inn",
		(u.get("position", Vector2.ZERO) as Vector2).distance_to(pos_before) > 0.0)
	_free_world(w)


## --- 3. Population control -------------------------------------------------

func _test_needs_idle_workers() -> void:
	var w := _new_world(["humans"])
	var gs: GameState = w["gs"]
	var u1: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(100, 100))
	var u2: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(120, 100))
	u1["work_state"] = "idle"
	u2["work_state"] = "idle"
	_check("needs: no new worker while two sit idle",
		not gs.spawner.faction_needs_unit("humans", "worker"))
	u2["alive"] = false  # one left — below the surplus threshold
	_check("needs: worker wanted again when hands are busy",
		gs.spawner.faction_needs_unit("humans", "worker"))
	u1["work_state"] = "gathering"  # busy, not idle
	_check("needs: busy workers don't block training",
		gs.spawner.faction_needs_unit("humans", "worker"))
	_free_world(w)


func _test_needs_military_threat() -> void:
	var w := _new_world(["humans", "ogres"])
	var gs: GameState = w["gs"]
	for i: int in range(16):
		gs.spawner.spawn_unit("humans", "soldier", -1,
			Vector2(100.0 + i * 10.0, 100))
	# Humans: race floor 16, no enemies -> 16 < 16 is false.
	_check("needs: army at the peacetime floor needs nothing",
		not gs.spawner.faction_needs_unit("humans", "soldier"))
	for i: int in range(20):
		gs.spawner.spawn_unit("ogres", "soldier", -1,
			Vector2(3000.0 + i * 10.0, 3000))
	# 20 enemies -> target ceil(20*1.35)+4 = 31 -> 16 < 31 is true.
	_check("needs: outnumbered army wants soldiers",
		gs.spawner.faction_needs_unit("humans", "soldier"))
	# Caps still rule: a full faction needs nothing.
	gs.population  # touch for clarity; caps tested via check_spawn elsewhere
	_free_world(w)


func _test_needs_countryside_full() -> void:
	var w := _new_world(["humans"])
	var gs: GameState = w["gs"]
	for i: int in range(15):
		gs.add_building({
			"type": "house", "faction": "humans", "town_id": -1,
			"position": Vector2(2000.0 + i * 100.0, 2000.0),
			"alive": true, "complete": true, "countryside": true,
			"residents": []})
	_check("needs: no civilians when countryside is full",
		not gs.spawner.faction_needs_unit("humans", "worker"))
	_check("needs: essential services still wanted when full",
		gs.spawner.faction_needs_unit("humans", "doctor"))
	_free_world(w)


## --- 4. Housing buying -----------------------------------------------------

func _test_home_purchase() -> void:
	var w := _new_world(["humans"])
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	var house: Dictionary = gs.add_building({
		"type": "house", "faction": "humans", "town_id": -1,
		"position": Vector2(500, 500), "alive": true, "complete": true,
		"residents": []})
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(520, 500))
	u["coins"] = 500.0
	var uid: int = int(u.get("id", 0))
	var price: float = SimHousing.LIST_BASE_PRICE \
		+ SimBuildings.footprint("house")
	housing.tick(1.0)
	_check("buy: homeless worker bought the listed home",
		not (u.get("home", {}) as Dictionary).is_empty())
	_check("buy: deed transferred to the buyer",
		int(house.get("owner_unit", -2)) == uid)
	_check("buy: house no longer for sale",
		not bool(house.get("for_sale", true)))
	var residents: Array = house.get("residents", [])
	_check("buy: buyer is a resident", uid in residents)
	_check("buy: coins deducted at the listed price",
		is_equal_approx(float(u.get("coins", 0.0)), 500.0 - price))
	_free_world(w)


func _test_buy_flag_cleared() -> void:
	var w := _new_world(["humans"])
	var gs: GameState = w["gs"]
	var housing: SimHousing = w["housing"]
	# Stale flag from an interrupted purchase, no houses listed anywhere.
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(600, 600))
	u["coins"] = 1.0
	u["_buying_home"] = true
	housing.tick(1.0)
	_check("buy: stale buying flag cleared when no home is available",
		not u.has("_buying_home"))
	_free_world(w)
