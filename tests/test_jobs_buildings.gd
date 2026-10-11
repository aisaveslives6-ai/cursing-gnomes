extends SceneTree
## Cursing Gnomes — Milestone 3 headless jobs & buildings tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_jobs_buildings.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes jobs & buildings tests ===")
	_test_job_registry()
	_test_blueprint_placement()
	_test_construction()
	_test_gather_haul()
	_test_gold_vein()
	_test_farmer()
	_test_clinic_staffing()
	_test_fire_station_staffing()
	_test_repair()
	_test_doctor_heal()
	_test_placement_validity()
	_test_work_sim_caps()
	_test_new_building_ports()
	_test_faction_uniques()
	_test_guild_hall_staffing()
	_test_guard_house_staffing()
	_test_farmhouse_food()
	_test_repair_shop_bonus()
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
	var sys := {
		"gs": gs,
		"buildings": SimBuildings.new(gs),
		"ai": WorkerAI.new(gs),
	}
	return sys


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _found(w: Dictionary, faction: String) -> Dictionary:
	var gs: GameState = w["gs"]
	var town: Dictionary = gs.found_town(faction, "T", Vector2(500, 500))
	# A completed town hall doubles as the haul drop-off.
	var hall: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		"town_hall", faction, int(town["id"]), Vector2(500, 500))
	hall["complete"] = true
	hall["progress"] = 1.0
	return town


func _give(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	# Bypass caps: tests need full grants (town_hall alone costs 100 oil).
	for res: String in Config.RESOURCES:
		gs.resources.add_resource(faction, res, 1000.0, true)


## --- Job registry ----------------------------------------------------------

func _test_job_registry() -> void:
	_check("jobs: woodcutter known", JobDefs.is_job("woodcutter"))
	_check("jobs: bogus unknown", not JobDefs.is_job("ninja"))
	_check("jobs: woodcutter civilian", JobDefs.is_civilian("woodcutter"))
	_check("jobs: doctor service", JobDefs.is_service("doctor"))
	_check("jobs: soldier military", JobDefs.is_military("soldier"))
	_check("jobs: woodcutter gathers wood",
		JobDefs.gather_resource("woodcutter") == "wood")
	_check("jobs: soldier gathers nothing",
		JobDefs.gather_resource("soldier") == "")
	_check("jobs: name lookup", JobDefs.job_name("firefighter") == "Firefighter")
	_check("jobs: military roster non-empty",
		JobDefs.jobs_in_category("military").size() >= 6)


## --- Blueprint placement ---------------------------------------------------

func _test_blueprint_placement() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "humans")
	var tid: int = int(town["id"])
	var wood_before: float = gs.resources.get_amount("humans", "wood")

	var b: Dictionary = bs.place_blueprint("house", "humans", tid, Vector2(600, 500))
	_check("place: blueprint created", not b.is_empty())
	_check("place: starts incomplete", not b.get("complete", true))
	_check("place: progress 0", float(b.get("progress", -1.0)) == 0.0)
	_check("place: wood deducted",
		gs.resources.get_amount("humans", "wood")
		< wood_before)

	# Barracks costs 120w/100s/60g — drain gold so it's unaffordable.
	gs.resources.add_resource("humans", "gold", -1000.0)
	var poor: Dictionary = bs.place_blueprint("barracks", "humans", tid,
		Vector2(700, 500))
	_check("place: unaffordable rejected", poor.is_empty())
	_check("place: block reason", bs.last_block_reason == "unaffordable")

	var weird: Dictionary = bs.place_blueprint("death_star", "humans", tid,
		Vector2(700, 500))
	_check("place: unknown type rejected", weird.is_empty())
	_free_world(w)


## --- Construction ----------------------------------------------------------

func _test_construction() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "gnomes")
	var tid: int = int(town["id"])
	var b: Dictionary = bs.place_blueprint("house", "gnomes", tid, Vector2(600, 500))

	# A builder walks to the blueprint and raises it. House build_time 25 s
	# at 1.0 power; simulate 60 s of AI ticks at 60 Hz.
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.spawner.spawn_unit("gnomes", "builder", tid,
		Vector2(590, 500))
	var done := false
	for i: int in range(3600):
		ai.tick_unit(u, bs, 1.0 / 60.0)
		if b.get("complete", false):
			done = true
			break
	_check("build: blueprint completes", done)
	_check("build: progress 1", float(b.get("progress", 0.0)) >= 1.0)
	_free_world(w)


## --- Gather & haul ---------------------------------------------------------

func _test_gather_haul() -> void:
	var w := _new_world(["elves"])
	_give(w, "elves")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "elves")
	var tid: int = int(town["id"])
	# Tree site right next to the hall: short walk, fast test.
	gs.add_work_site({"kind": "tree", "position": Vector2(520, 500),
		"amount": 60.0, "yield": 60.0})
	var u: Dictionary = gs.spawner.spawn_unit("elves", "woodcutter", tid,
		Vector2(510, 500))
	u["equipped_tool"] = "axe"  # full chop rate (no-tool penalty is 25%)
	var wood_before: float = gs.resources.get_amount("elves", "wood")
	# 60 s of AI: walk, fell the tree (60 @ 2.5/s = 24 s), collect the
	# burst, haul back. Jeremy 2026-10-05: trees burst into pickups —
	# nothing trickles mid-chop, so the ledger only moves after the fell.
	for i: int in range(3600):
		ai.tick_unit(u, bs, 1.0 / 60.0)
	var wood_after: float = gs.resources.get_amount("elves", "wood")
	_check("gather: wood increased", wood_after > wood_before)
	_check("gather: tree felled",
		bool(gs.work_sites[0].get("felled", false)))
	_free_world(w)


## Miners on gold veins haul gold, not stone.
func _test_gold_vein() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "humans")
	var tid: int = int(town["id"])
	gs.add_work_site({"kind": "gold_vein", "position": Vector2(520, 500),
		"amount": 100.0})
	var u: Dictionary = gs.spawner.spawn_unit("humans", "miner", tid,
		Vector2(510, 500))
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	for i: int in range(3600):
		ai.tick_unit(u, bs, 1.0 / 60.0)
	_check("gold: gold increased",
		gs.resources.get_amount("humans", "gold") > gold_before)
	_free_world(w)


## Farmers work farm buildings (infinite food source).
func _test_farmer() -> void:
	var w := _new_world(["ogres"])
	_give(w, "ogres")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "ogres")
	var tid: int = int(town["id"])
	var farm: Dictionary = bs.place_blueprint("farm", "ogres", tid,
		Vector2(560, 500))
	farm["complete"] = true
	var u: Dictionary = gs.spawner.spawn_unit("ogres", "farmer", tid,
		Vector2(550, 500))
	# Drain to zero: storage caps would clamp production gains otherwise.
	gs.resources.add_resource("ogres", "food", -99999.0)
	var food_before: float = gs.resources.get_amount("ogres", "food")
	for i: int in range(3600):
		ai.tick_unit(u, bs, 1.0 / 60.0)
	_check("farm: food increased",
		gs.resources.get_amount("ogres", "food") > food_before)
	_free_world(w)


## --- Service buildings -----------------------------------------------------

func _test_clinic_staffing() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "humans")
	var tid: int = int(town["id"])
	var clinic: Dictionary = bs.place_blueprint("clinic", "humans", tid,
		Vector2(600, 500))
	clinic["complete"] = true
	clinic["_staff_next_try"] = 0.0  # force the throttle open
	bs.tick_service(clinic, 0.016)
	_check("clinic: doctor spawned",
		gs.population.count_job("humans", "doctor") == 1)
	# Second tick must NOT spawn another (job cap = 1).
	clinic["_staff_next_try"] = 0.0
	bs.tick_service(clinic, 0.016)
	_check("clinic: still exactly 1 doctor",
		gs.population.count_job("humans", "doctor") == 1)
	_free_world(w)


func _test_fire_station_staffing() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "gnomes")
	var tid: int = int(town["id"])
	# Fill the town to 8/8 first — essential bypass must still staff 2.
	for i: int in range(8):
		gs.spawner.spawn_unit("gnomes", "worker", tid, Vector2(i * 10, 480))
	var fs: Dictionary = bs.place_blueprint("fire_station", "gnomes", tid,
		Vector2(600, 500))
	fs["complete"] = true
	fs["_staff_next_try"] = 0.0
	bs.tick_service(fs, 0.016)
	_check("fire: 2 firefighters staffed",
		gs.population.count_job("gnomes", "firefighter") == 2)
	_check("fire: town over 8 via bypass",
		gs.population.get_town_pop(tid) == 10)
	# Third must be blocked by the per-job cap.
	fs["_staff_next_try"] = 0.0
	bs.tick_service(fs, 0.016)
	_check("fire: still exactly 2",
		gs.population.count_job("gnomes", "firefighter") == 2)
	_free_world(w)


## --- Repair & heal ---------------------------------------------------------

func _test_repair() -> void:
	var w := _new_world(["elves"])
	_give(w, "elves")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "elves")
	var tid: int = int(town["id"])
	var b: Dictionary = bs.place_blueprint("house", "elves", tid, Vector2(600, 500))
	b["complete"] = true
	b["hp"] = 100.0  # damaged (max 400)
	var u: Dictionary = gs.spawner.spawn_unit("elves", "builder", tid,
		Vector2(590, 500))
	for i: int in range(1800):
		ai.tick_unit(u, bs, 1.0 / 60.0)
	_check("repair: hp restored", float(b.get("hp", 0.0)) >= float(b.get("max_hp", 1.0)))
	_free_world(w)


func _test_doctor_heal() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "humans")
	var tid: int = int(town["id"])
	var patient: Dictionary = gs.spawner.spawn_unit("humans", "worker", tid,
		Vector2(520, 500))
	patient["hp"] = 20.0
	var doc: Dictionary = gs.spawner.spawn_unit("humans", "doctor", tid,
		Vector2(510, 500))
	for i: int in range(1800):
		ai.tick_unit(doc, bs, 1.0 / 60.0)
	_check("doctor: patient healed",
		float(patient.get("hp", 0.0)) > 20.0)
	_free_world(w)


## --- Placement validity ----------------------------------------------------

func _test_placement_validity() -> void:
	var w := _new_world(["ogres"])
	_give(w, "ogres")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "ogres")
	var tid: int = int(town["id"])
	var map_rect := Rect2(0, 0, 4096, 4096)
	# Hall is at (500,500) with footprint 46.
	_check("place_at: overlapping hall rejected",
		not SimBuildings.can_place_at(gs.buildings, "house", Vector2(510, 510),
			map_rect))
	_check("place_at: clear spot accepted",
		SimBuildings.can_place_at(gs.buildings, "house", Vector2(700, 700),
			map_rect))
	_check("place_at: off-map rejected",
		not SimBuildings.can_place_at(gs.buildings, "house", Vector2(-50, 500),
			map_rect))
	# Walls chain with each other: overlapping an existing wall is legal.
	var wall_list: Array = [ {"alive": true, "type": "wall",
		"position": Vector2(800, 800)} ]
	_check("place_at: wall-on-wall overlap ok",
		SimBuildings.can_place_at(wall_list, "wall", Vector2(805, 805),
			map_rect))
	_check("place_at: wall-on-hall rejected",
		not SimBuildings.can_place_at(gs.buildings, "wall", Vector2(505, 505),
			map_rect))
	_free_world(w)


## --- Full work sim: caps hold, nobody stuck ---------------------------------

func _test_work_sim_caps() -> void:
	var w := _new_world(["humans", "ogres", "elves", "gnomes"])
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var jobs: Array[String] = ["worker", "woodcutter", "miner", "farmer", "builder"]
	for f: String in ["humans", "ogres", "elves", "gnomes"]:
		_give(w, f)
		var town: Dictionary = _found(w, f)
		var tid: int = int(town["id"])
		# Scatter sites near each town.
		for i: int in range(6):
			gs.add_work_site({"kind": "tree",
				"position": Vector2(500 + i * 30, 540), "amount": 200.0})
		for i: int in range(8):
			var u: Dictionary = gs.spawner.spawn_unit(f, jobs[i % jobs.size()],
				tid, Vector2(480 + i * 8, 480))
		# A couple of blueprints to build.
		bs.place_blueprint("house", f, tid, Vector2(620, 520))
		bs.place_blueprint("farm", f, tid, Vector2(420, 560))
	# 60 simulated seconds at 60 Hz: work, build, haul, staff.
	var stuck := 0
	for i: int in range(3600):
		for u: Dictionary in gs.units:
			ai.tick_unit(u, bs, 1.0 / 60.0)
		for b: Dictionary in gs.buildings:
			var bt: String = String(b.get("type", ""))
			if bt == "clinic" or bt == "fire_station":
				b["complete"] = true
				b["_staff_next_try"] = 0.0
				bs.tick_service(b, 1.0 / 60.0)
	_check("sim: global cap holds", gs.population.get_global_pop() <= 96)
	for f: String in ["humans", "ogres", "elves", "gnomes"]:
		_check("sim: faction cap holds %s" % f,
			gs.population.get_faction_pop(f) <= 24)
	# Nobody stuck: every unit either idle-with-nothing-to-do or mid-task.
	for u: Dictionary in gs.units:
		var st: String = String(u.get("work_state", "idle"))
		if not st in ["idle", "to_resource", "gathering", "to_dropoff",
				"to_build", "building", "to_repair", "repairing",
				"to_patient", "healing"]:
			stuck += 1
	_check("sim: no stuck units", stuck == 0)
	_free_world(w)

## --- New building ports (Milestone 3b) ---------------------------------------

## Every ported building places, deducts cost, and completes — all 5 factions.
func _test_new_building_ports() -> void:
	var generics: Array[String] = ["aa_tower", "bathhouse", "courthouse",
		"farmhouse", "fishing_dock", "guard_house", "guild_hall", "hall",
		"horse_stable", "repair_shop", "storage", "stock_gold", "stock_wood",
		"stock_food", "stock_oil", "stock_seeds", "well", "windmill"]
	for f: String in ["humans", "ogres", "elves", "gnomes", "undead"]:
		var w := _new_world([f])
		var gs: GameState = w["gs"]
		var bs: SimBuildings = w["buildings"]
		for res: String in Config.RESOURCES:
			gs.resources.add_resource(f, res, 5000.0, true)
		var town: Dictionary = _found(w, f)
		var tid: int = int(town["id"])
		var x := 700.0
		for bt: String in generics:
			var wood_before: float = gs.resources.get_amount(f, "wood")
			var b: Dictionary = bs.place_blueprint(bt, f, tid, Vector2(x, 500))
			_check("port: %s places for %s" % [bt, f], not b.is_empty())
			if b.is_empty():
				continue
			_check("port: %s costs wood %s" % [bt, f],
				gs.resources.get_amount(f, "wood") < wood_before)
			_check("port: %s has name %s" % [bt, f],
				SimBuildings.building_name(bt) != bt)
			var done: bool = bs.tick_construction(b, 500.0, 1.0)
			_check("port: %s completes %s" % [bt, f], done)
			_check("port: %s progress 1 %s" % [bt, f],
				float(b.get("progress", 0.0)) >= 1.0)
			x += 120.0
		_free_world(w)


## Faction uniques are locked to their faction.
func _test_faction_uniques() -> void:
	var w := _new_world(["humans", "gnomes", "ogres", "undead"])
	var bs: SimBuildings = w["buildings"]
	for f: String in ["humans", "gnomes", "ogres", "undead"]:
		_give(w, f)
		_found(w, f)
	var ok_cases: Array = [
		["knights_castle", "humans"], ["mage_spire", "gnomes"],
		["war_hut", "ogres"], ["flesh_farm", "undead"],
	]
	for c: Array in ok_cases:
		var b: Dictionary = bs.place_blueprint(String(c[0]), String(c[1]), 0,
			Vector2(600, 500))
		_check("unique: %s places for %s" % [c[0], c[1]], not b.is_empty())
	var bad_cases: Array = [
		["knights_castle", "gnomes"], ["knights_castle", "undead"],
		["mage_spire", "humans"], ["war_hut", "elves"],
		["flesh_farm", "humans"],
	]
	for c2: Array in bad_cases:
		var b2: Dictionary = bs.place_blueprint(String(c2[0]), String(c2[1]), 0,
			Vector2(600, 500))
		_check("unique: %s blocked for %s" % [c2[0], c2[1]], b2.is_empty())
		_check("unique: %s reason %s" % [c2[0], c2[1]],
			bs.last_block_reason == "wrong_faction")
	_check("unique: helper farm/elves",
		SimBuildings.faction_may_build("farm", "elves"))
	_check("unique: helper castle/ogres blocked",
		not SimBuildings.faction_may_build("knights_castle", "ogres"))
	_free_world(w)


## Guild halls auto-staff exactly 1 guild master.
func _test_guild_hall_staffing() -> void:
	var w := _new_world(["elves"])
	_give(w, "elves")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "elves")
	var tid: int = int(town["id"])
	var gh: Dictionary = bs.place_blueprint("guild_hall", "elves", tid,
		Vector2(600, 500))
	gh["complete"] = true
	gh["_staff_next_try"] = 0.0
	bs.tick_service(gh, 0.016)
	_check("guild: 1 guild master staffed",
		gs.population.count_job("elves", "guild_master") == 1)
	gh["_staff_next_try"] = 0.0
	bs.tick_service(gh, 0.016)
	_check("guild: still exactly 1",
		gs.population.count_job("elves", "guild_master") == 1)
	_check("guild: job is service",
		JobDefs.is_service("guild_master"))
	_free_world(w)


## Guard houses auto-staff 2 guards (town-capped, no essential bypass).
func _test_guard_house_staffing() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "humans")
	var tid: int = int(town["id"])
	var gh: Dictionary = bs.place_blueprint("guard_house", "humans", tid,
		Vector2(600, 500))
	gh["complete"] = true
	gh["_staff_next_try"] = 0.0
	bs.tick_service(gh, 0.016)
	_check("guardhouse: 2 guards staffed",
		gs.population.count_job("humans", "guard") == 2)
	gh["_staff_next_try"] = 0.0
	bs.tick_service(gh, 0.016)
	_check("guardhouse: still exactly 2",
		gs.population.count_job("humans", "guard") == 2)
	_free_world(w)


## Farmers work farmhouses (50% faster than plain farms).
func _test_farmhouse_food() -> void:
	# Farmhouse vs farm, identical geometry: farmhouse must yield more.
	var w1 := _new_world(["humans"])
	_give(w1, "humans")
	var gs1: GameState = w1["gs"]
	var bs1: SimBuildings = w1["buildings"]
	var ai1: WorkerAI = w1["ai"]
	var t1: Dictionary = _found(w1, "humans")
	var farm: Dictionary = bs1.place_blueprint("farm", "humans",
		int(t1["id"]), Vector2(560, 500))
	farm["complete"] = true
	var u1: Dictionary = gs1.spawner.spawn_unit("humans", "farmer",
		int(t1["id"]), Vector2(550, 500))
	var w2 := _new_world(["gnomes"])
	_give(w2, "gnomes")
	var gs2: GameState = w2["gs"]
	var bs2: SimBuildings = w2["buildings"]
	var ai2: WorkerAI = w2["ai"]
	var t2: Dictionary = _found(w2, "gnomes")
	var fh: Dictionary = bs2.place_blueprint("farmhouse", "gnomes",
		int(t2["id"]), Vector2(560, 500))
	fh["complete"] = true
	var u2: Dictionary = gs2.spawner.spawn_unit("gnomes", "farmer",
		int(t2["id"]), Vector2(550, 500))
	# Drain to zero: storage caps would clamp production gains otherwise.
	gs1.resources.add_resource("humans", "food", -99999.0)
	gs2.resources.add_resource("gnomes", "food", -99999.0)
	var food1: float = gs1.resources.get_amount("humans", "food")
	var food2: float = gs2.resources.get_amount("gnomes", "food")
	for i: int in range(3600):
		ai1.tick_unit(u1, bs1, 1.0 / 60.0)
		ai2.tick_unit(u2, bs2, 1.0 / 60.0)
	var gain1: float = gs1.resources.get_amount("humans", "food") - food1
	var gain2: float = gs2.resources.get_amount("gnomes", "food") - food2
	_check("farmhouse: food gained", gain2 > 0.0)
	_check("farmhouse: beats plain farm", gain2 > gain1)
	_free_world(w1)
	_free_world(w2)


## Fishing docks feed farmers; flesh farms feed the undead.
func _test_dock_and_flesh_farm() -> void:
	var w := _new_world(["undead", "elves"])
	_give(w, "undead")
	_give(w, "elves")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var tu: Dictionary = _found(w, "undead")
	var te: Dictionary = _found(w, "elves")
	var ff: Dictionary = bs.place_blueprint("flesh_farm", "undead",
		int(tu["id"]), Vector2(560, 500))
	ff["complete"] = true
	var uu: Dictionary = gs.spawner.spawn_unit("undead", "farmer",
		int(tu["id"]), Vector2(550, 500))
	var dock: Dictionary = bs.place_blueprint("fishing_dock", "elves",
		int(te["id"]), Vector2(560, 500))
	dock["complete"] = true
	var ue: Dictionary = gs.spawner.spawn_unit("elves", "farmer",
		int(te["id"]), Vector2(550, 500))
	var food_u: float = gs.resources.get_amount("undead", "food")
	var food_e: float = gs.resources.get_amount("elves", "food")
	for i: int in range(3600):
		ai.tick_unit(uu, bs, 1.0 / 60.0)
		ai.tick_unit(ue, bs, 1.0 / 60.0)
	_check("flesh_farm: undead food increased",
		gs.resources.get_amount("undead", "food") > food_u)
	_check("fishing_dock: elven food increased",
		gs.resources.get_amount("elves", "food") > food_e)
	_free_world(w)


## A nearby completed repair shop speeds up repairs 50%.
func _test_repair_shop_bonus() -> void:
	var results := {}
	for with_shop: bool in [true, false]:
		var w := _new_world(["gnomes"])
		_give(w, "gnomes")
		var bs: SimBuildings = w["buildings"]
		var ai: WorkerAI = w["ai"]
		var town: Dictionary = _found(w, "gnomes")
		var tid: int = int(town["id"])
		var b: Dictionary = bs.place_blueprint("house", "gnomes", tid,
			Vector2(600, 500))
		b["complete"] = true
		b["hp"] = 100.0  # damaged (max 400)
		if with_shop:
			var shop: Dictionary = bs.place_blueprint("repair_shop", "gnomes",
				tid, Vector2(640, 520))
			shop["complete"] = true
		var u: Dictionary = (w["gs"] as GameState).spawner.spawn_unit("gnomes",
			"builder", tid, Vector2(590, 500))
		u["work_state"] = "repairing"
		u["work_building"] = int(b["id"])
		for i: int in range(60):
			ai.tick_unit(u, bs, 1.0 / 60.0)
		results[with_shop] = float(b.get("hp", 0.0))
		_free_world(w)
	_check("repair: shop repairs faster",
		float(results[true]) > float(results[false]))
	# 1 s at 25 hp/s * 1.5 bonus = +37.5 hp.
	_check("repair: shop bonus rate",
		absf(float(results[true]) - 137.5) < 0.01)
	_check("repair: plain rate",
		absf(float(results[false]) - 125.0) < 0.01)
