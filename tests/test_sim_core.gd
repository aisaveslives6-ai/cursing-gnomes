extends SceneTree
## Cursing Gnomes — Milestone 1 headless sim-core tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_sim_core.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes sim-core tests ===")
	_test_faction_cap()
	_test_town_cap()
	_test_global_cap()
	_test_essential_bypass()
	_test_spam()
	_test_resources()
	_test_events()
	_test_day_night()
	_test_invalid_spawns()
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


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	return gs


func _found(gs: GameState, faction: String, town_name: String) -> Dictionary:
	return gs.found_town(faction, town_name, Vector2(100, 100))


## Spawning 200 workers for one faction must stop at 48 (Jeremy's faction law, 2026-10-02: more units).
func _test_faction_cap() -> void:
	var factions: Array[String] = ["humans"]
	var gs := _new_game(factions)
	var town: Dictionary = _found(gs, "humans", "Testville")
	var ok_count: int = 0
	for i: int in range(100):
		# Spread across fake towns is unnecessary here; countryside spawns skip
		# the town cap so this purely tests the faction cap.
		var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1, Vector2(i, 0))
		if not u.is_empty():
			ok_count += 1
	_check("faction_cap: exactly 48 spawned", ok_count == 48)
	_check("faction_cap: pop reads 48", gs.population.get_faction_pop("humans") == 48)
	_check("faction_cap: 49th blocked as faction_capped",
		gs.spawner.check_spawn("humans", "worker", -1) == "faction_capped")
	gs.free()


## Spawning 40 workers into one town must stop at 16 (Jeremy's town law, 2026-10-02: more units).
func _test_town_cap() -> void:
	var factions: Array[String] = ["gnomes"]
	var gs := _new_game(factions)
	var town: Dictionary = _found(gs, "gnomes", "Gnomeregan")
	var town_id: int = int(town["id"])
	var ok_count: int = 0
	for i: int in range(40):
		var u: Dictionary = gs.spawner.spawn_unit("gnomes", "worker", town_id, Vector2(i, 0))
		if not u.is_empty():
			ok_count += 1
	_check("town_cap: exactly 16 spawned", ok_count == 16)
	_check("town_cap: town pop reads 16", gs.population.get_town_pop(town_id) == 16)
	_check("town_cap: 17th blocked as town_capped",
		gs.spawner.check_spawn("gnomes", "worker", town_id) == "town_capped")
	gs.free()


## 5 factions x 100 spawns must stop at 240 globally (Jeremy's global law, 2026-10-02: more units).
func _test_global_cap() -> void:
	var factions: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	var gs := _new_game(factions)
	for f: String in factions:
		_found(gs, f, f + "_town")
	var total: int = 0
	for f: String in factions:
		for i: int in range(100):
			var u: Dictionary = gs.spawner.spawn_unit(f, "worker", -1, Vector2(i, 0))
			if not u.is_empty():
				total += 1
		_check("global_cap: faction %s at 48" % f, gs.population.get_faction_pop(f) == 48)
	_check("global_cap: 240 total spawned", total == 240)
	_check("global_cap: global pop reads 240", gs.population.get_global_pop() == 240)
	_check("global_cap: extra spawn blocked",
		gs.spawner.check_spawn("humans", "worker", -1) != "ok")
	_check("global_cap: blocked spawn returns {}",
		gs.spawner.spawn_unit("humans", "worker", -1, Vector2.ZERO).is_empty())
	gs.free()


## Essential services bypass the per-town cap (Jeremy 2026-10-02 ruling):
## a full town (8/8) must still accept 2 firefighters + 1 doctor, then block.
func _test_essential_bypass() -> void:
	var factions: Array[String] = ["ogres"]
	var gs := _new_game(factions)
	var town: Dictionary = _found(gs, "ogres", "Ogrimmar")
	var town_id: int = int(town["id"])
	for i: int in range(8):
		gs.spawner.spawn_unit("ogres", "worker", town_id, Vector2(i, 0))
	_check("essential: town full at 8", gs.population.get_town_pop(town_id) == 8)
	var ff1: Dictionary = gs.spawner.spawn_unit("ogres", "firefighter", town_id, Vector2.ZERO)
	var ff2: Dictionary = gs.spawner.spawn_unit("ogres", "firefighter", town_id, Vector2.ZERO)
	var ff3: Dictionary = gs.spawner.spawn_unit("ogres", "firefighter", town_id, Vector2.ZERO)
	_check("essential: 1st firefighter spawns in full town", not ff1.is_empty())
	_check("essential: 2nd firefighter spawns in full town", not ff2.is_empty())
	_check("essential: 3rd firefighter blocked (2/dept max)", ff3.is_empty())
	_check("essential: 3rd blocked as job_capped",
		gs.spawner.last_block_reason == "job_capped")
	var doc1: Dictionary = gs.spawner.spawn_unit("ogres", "doctor", town_id, Vector2.ZERO)
	var doc2: Dictionary = gs.spawner.spawn_unit("ogres", "doctor", town_id, Vector2.ZERO)
	_check("essential: 1st doctor spawns in full town", not doc1.is_empty())
	_check("essential: 2nd doctor blocked (1/clinic max)", doc2.is_empty())
	_check("essential: town pop is 8+2+1=11", gs.population.get_town_pop(town_id) == 11)
	# Killing a firefighter must free the slot (respawn allowed).
	gs.kill_unit(int(ff1["id"]))
	var ff4: Dictionary = gs.spawner.spawn_unit("ogres", "firefighter", town_id, Vector2.ZERO)
	_check("essential: firefighter respawns after one dies", not ff4.is_empty())
	gs.free()


## 1000 mixed spawn attempts: caps must hold everywhere, no crash, no excess.
func _test_spam() -> void:
	var factions: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	var gs := _new_game(factions)
	var town_ids: Dictionary = {}
	for f: String in factions:
		var t: Dictionary = _found(gs, f, f + "_town")
		town_ids[f] = int(t["id"])
	var jobs: Array[String] = ["worker", "warrior", "ranger", "mage", "firefighter", "doctor", "worker"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i: int in range(1000):
		var f: String = factions[rng.randi_range(0, 4)]
		var job: String = jobs[rng.randi_range(0, jobs.size() - 1)]
		var tid: int = int(town_ids[f]) if rng.randf() < 0.7 else -1
		gs.spawner.spawn_unit(f, job, tid, Vector2(rng.randf() * 500, rng.randf() * 500))
	var ok: bool = true
	for f: String in factions:
		if gs.population.get_faction_pop(f) > Config.POP_CAP_FACTION:
			ok = false
		if gs.population.count_job(f, "firefighter") > Config.FIREFIGHTERS_PER_STATION:
			ok = false
		if gs.population.count_job(f, "doctor") > Config.DOCTORS_PER_CLINIC:
			ok = false
	for tid: int in town_ids.values():
		# Town cap is a HOUSING cap: 16 town-housed civilians. Essential
		# services bypass (firefighter/doctor), and military bypasses too —
		# soldiers live in barracks, not town houses (Jeremy 2026-10-06:
		# "they don't even spawn in an army"). Faction/global caps still
		# bound the total.
		var housed := 0
		for u: Dictionary in gs.units:
			if not u.get("alive", false):
				continue
			if int(u.get("town_id", -1)) != tid:
				continue
			var job: String = String(u.get("job", ""))
			if job in Config.ESSENTIAL_JOBS:
				continue
			if JobDefs.is_military(job):
				continue
			housed += 1
		if housed > Config.POP_CAP_TOWN:
			ok = false
	_check("spam: no faction over 48, no job over cap, town housing capped at 16",
		ok)
	_check("spam: global pop exactly 240", gs.population.get_global_pop() == 240)
	gs.free()


## Resource ledger: add, spend (atomic), can_afford.
func _test_resources() -> void:
	var factions: Array[String] = ["elves"]
	var gs := _new_game(factions)
	gs.resources.add_resource("elves", "wood", 100.0)
	_check("resources: add 100 wood", gs.resources.get_amount("elves", "wood") == 100.0)
	_check("resources: spend 30 wood", gs.resources.spend("elves", {"wood": 30.0}))
	_check("resources: 70 wood left", gs.resources.get_amount("elves", "wood") == 70.0)
	_check("resources: cannot afford 1000 wood",
		not gs.resources.can_afford("elves", {"wood": 1000.0}))
	# Atomicity: unaffordable multi-cost spends nothing.
	var spent: bool = gs.resources.spend("elves", {"wood": 50.0, "oil": 10.0})
	_check("resources: multi-cost with 0 stone fails", not spent)
	_check("resources: wood untouched after failed spend",
		gs.resources.get_amount("elves", "wood") == 70.0)
	_check("resources: unknown faction reads 0",
		gs.resources.get_amount("nobody", "wood") == 0.0)
	gs.free()


## EventBus: spawn and death emit exactly once each.
func _test_events() -> void:
	var factions: Array[String] = ["humans"]
	var gs := _new_game(factions)
	var spawned: Array = [0]
	var died: Array = [0]
	gs.bus.unit_spawned.connect(func(_u: Dictionary) -> void: spawned[0] += 1)
	gs.bus.unit_died.connect(func(_id: int, _f: String) -> void: died[0] += 1)
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1, Vector2.ZERO)
	_check("events: unit_spawned fired once", spawned[0] == 1)
	gs.kill_unit(int(u["id"]))
	_check("events: unit_died fired once", died[0] == 1)
	_check("events: dead unit not counted in pop",
		gs.population.get_global_pop() == 0)
	gs.free()


## Day/night cycle advances on tick.
## Jeremy 2026-10-04: new games start at midday (12:00), not midnight.
func _test_day_night() -> void:
	var factions: Array[String] = ["humans"]
	var gs := _new_game(factions)
	_check("daynight: starts day 1, midday (not night)", gs.day_number == 1 and not gs.is_night)
	# Tick 0.4 days (9.6 hours): 12:00 -> 21:36, night falls, still day 1.
	gs.tick(Config.DAY_LENGTH_SECONDS * 0.4)
	_check("daynight: 9.6h later is night, still day 1", gs.is_night and gs.day_number == 1)
	gs.tick(Config.DAY_LENGTH_SECONDS * 0.5)
	_check("daynight: rolled over to day 2", gs.day_number == 2)
	gs.free()


## Invalid spawns are rejected cleanly (no crash, {} returned).
func _test_invalid_spawns() -> void:
	var factions: Array[String] = ["humans"]
	var gs := _new_game(factions)
	_check("invalid: unknown faction blocked",
		gs.spawner.spawn_unit("martians", "worker", -1, Vector2.ZERO).is_empty())
	_check("invalid: unknown faction reason",
		gs.spawner.check_spawn("martians", "worker", -1) == "bad_faction")
	_check("invalid: unknown town blocked",
		gs.spawner.spawn_unit("humans", "worker", 999, Vector2.ZERO).is_empty())
	_check("invalid: unknown town reason",
		gs.spawner.check_spawn("humans", "worker", 999) == "bad_town")
	gs.free()
