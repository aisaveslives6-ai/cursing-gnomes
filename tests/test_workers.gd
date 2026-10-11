extends SceneTree
## Cursing Gnomes — Milestone 3 headless workers / hiring / housing tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_workers.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes workers/hiring/housing tests ===")
	_test_job_registry_completion()
	_test_workplace_table()
	_test_desk_claim_release()
	_test_station_work_and_shifts()
	_test_officer_appointments()
	_test_roster_hiring()
	_test_barracks_beds()
	_test_training_queue()
	_test_housing_counts()
	_test_homeless_migration()
	_test_homestead()
	_test_buy_home()
	_test_work_priority()
	_test_roadbuilder()
	_test_fire_dispatch_untouched()
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
	var w := {
		"gs": gs,
		"buildings": SimBuildings.new(gs),
		"ai": WorkerAI.new(gs),
		"hiring": GuildHiring.new(gs),
		"housing": SimHousing.new(gs),
	}
	return w


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _found(w: Dictionary, faction: String) -> Dictionary:
	var gs: GameState = w["gs"]
	var town: Dictionary = gs.found_town(faction, "T", Vector2(500, 500))
	var hall: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		"town_hall", faction, int(town["id"]), Vector2(500, 500))
	hall["complete"] = true
	hall["progress"] = 1.0
	return town


func _give(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	for res: String in Config.RESOURCES:
		gs.resources.add_resource(faction, res, 10000.0, true)


## Sets the clock to an hour of day (0-24).
func _set_hour(w: Dictionary, hour: float) -> void:
	(w["gs"] as GameState).game_time = hour / 24.0 * Config.DAY_LENGTH_SECONDS


## --- Job registry completion -----------------------------------------------

func _test_job_registry_completion() -> void:
	for job: String in ["shopkeeper", "cashier", "barkeep", "innkeeper",
			"smith", "repairman", "fisher"]:
		_check("jobs: %s known + civilian" % job,
			JobDefs.is_job(job) and JobDefs.is_civilian(job))
	for job2: String in ["adviser", "clerk", "diplomat", "watchcaptain"]:
		_check("jobs: %s known + service" % job2,
			JobDefs.is_job(job2) and JobDefs.is_service(job2))
	_check("jobs: fisher gathers food",
		JobDefs.gather_resource("fisher") == "food")
	_check("jobs: guild master still service",
		JobDefs.is_service("guild_master"))
	_check("jobs: bogus still unknown", not JobDefs.is_job("ninja"))


## --- Workplace table + coverage slots ---------------------------------------

func _test_workplace_table() -> void:
	_check("workplace: shopkeeper is station job",
		JobDefs.is_station_job("shopkeeper"))
	_check("workplace: adviser is desk job",
		JobDefs.is_desk_job("adviser"))
	_check("workplace: woodcutter not station",
		not JobDefs.is_station_job("woodcutter"))
	# MISS 15: slots = ceil(openHours / 8) * base.
	_check("slots: shop 12h -> 2", JobDefs.slots_for("shop", 1) == 2)
	_check("slots: fire station 24h -> 3", JobDefs.slots_for("fire_station", 1) == 3)
	_check("slots: barracks 24h base2 -> 6",
		JobDefs.slots_for("barracks", 2) == 6)
	_check("slots: town hall 10h -> 2",
		JobDefs.slots_for("town_hall", 1) == 2)


## --- Desk claiming ----------------------------------------------------------

func _test_desk_claim_release() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "humans")
	var tid: int = int(town["id"])
	var hall: Dictionary = gs.buildings[0]
	ai.ensure_desks(hall)
	var desks: Array = hall["desks"]
	_check("desk: hall has cubicles", desks.size() >= 2)
	var u1: Dictionary = gs.spawner.spawn_unit("humans", "worker", tid,
		Vector2(500, 520))
	var u2: Dictionary = gs.spawner.spawn_unit("humans", "worker", tid,
		Vector2(500, 530))
	_check("desk: u1 claims", ai.claim_desk(u1, hall))
	_check("desk: u2 claims", ai.claim_desk(u2, hall))
	var d1: int = int((u1["_desk"] as Dictionary).get("desk_id", -1))
	var d2: int = int((u2["_desk"] as Dictionary).get("desk_id", -1))
	_check("desk: no sharing", d1 != d2)
	_check("desk: distinct ids", d1 >= 0 and d2 >= 0)
	# Stale claims die with the job.
	WorkerAI.assign_job(u1, "woodcutter")
	_check("desk: released on reassign", not u1.has("_desk"))
	_free_world(w)


## --- Station work + shifts --------------------------------------------------

func _test_station_work_and_shifts() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "gnomes")
	var tid: int = int(town["id"])
	var shop: Dictionary = bs.place_blueprint("shop", "gnomes", tid,
		Vector2(600, 500))
	shop["complete"] = true
	var u: Dictionary = gs.spawner.spawn_unit("gnomes", "shopkeeper", tid,
		Vector2(590, 500))
	u["station"] = {"job": "shopkeeper", "building_id": int(shop["id"]),
		"spot": "counter", "act": "tending the shop"}
	# On shift (noon): walks to the shop and works.
	_set_hour(w, 12.0)
	for i: int in range(600):
		ai.tick_unit(u, bs, 1.0 / 60.0)
	_check("station: working at shop",
		String(u.get("work_state", "")) == "working")
	_check("station: counter pose",
		String(u.get("work_pose", "")) == "use")
	_check("station: wages earned", float(u.get("coins", 0.0)) > 20.0)
	# Off shift (midnight): stands down, no desk held.
	_set_hour(w, 0.0)
	ai.tick_unit(u, bs, 1.0 / 60.0)
	_check("station: off-shift idle",
		String(u.get("work_state", "")) == "idle")
	_free_world(w)


## --- Officer appointments ---------------------------------------------------

func _test_officer_appointments() -> void:
	var w := _new_world(["elves"])
	_give(w, "elves")
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	var town: Dictionary = _found(w, "elves")
	var tid: int = int(town["id"])
	for i: int in range(6):
		gs.spawner.spawn_unit("elves", "worker", tid,
			Vector2(480 + i * 8, 480))
	# Run the hiring sweep (throttled 4 s).
	for i: int in range(300):
		hiring.tick(1.0 / 60.0, 12.0)
	var adviser: Dictionary = {}
	var captain: Dictionary = {}
	for u: Dictionary in gs.units:
		var role: String = String((u.get("mind", {}) as Dictionary).get("gov_role", ""))
		if role == "adviser":
			adviser = u
		elif role == "watch_captain":
			captain = u
	_check("officer: adviser appointed", not adviser.is_empty())
	_check("officer: adviser job", String(adviser.get("job", "")) == "adviser")
	_check("officer: adviser stationed at hall",
		int((adviser.get("station", {}) as Dictionary).get("building_id", -1))
		== int((gs.buildings[0] as Dictionary).get("id", -2)))
	_check("officer: watch captain appointed", not captain.is_empty())
	_check("officer: watchcaptain job",
		String(captain.get("job", "")) == "watchcaptain")
	# Guild master: auto-staffed, then given the guild-hall office + home.
	var bs: SimBuildings = w["buildings"]
	var gh: Dictionary = bs.place_blueprint("guild_hall", "elves", tid,
		Vector2(700, 500))
	gh["complete"] = true
	gh["_staff_next_try"] = 0.0
	bs.tick_service(gh, 0.016)
	for i: int in range(300):
		hiring.tick(1.0 / 60.0, 12.0)
	var gm: Dictionary = {}
	for u2: Dictionary in gs.units:
		if String(u2.get("job", "")) == "guild_master":
			gm = u2
	_check("officer: guild master exists", not gm.is_empty())
	_check("officer: gm gov role",
		String((gm.get("mind", {}) as Dictionary).get("gov_role", "")) == "guild_master")
	_check("officer: gm office is guild hall",
		int((gm.get("station", {}) as Dictionary).get("building_id", -1))
		== int(gh.get("id", -2)))
	_check("officer: gm lives in guild hall",
		int((gm.get("home", {}) as Dictionary).get("id", -2))
		== int(gh.get("id", -2)))
	_free_world(w)


## --- Roster hiring -----------------------------------------------------------

func _hired_shopkeeper_ids() -> Array:
	# Fresh world, run one hiring sweep, return sorted shopkeeper unit ids.
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var hiring: GuildHiring = w["hiring"]
	var town: Dictionary = _found(w, "humans")
	var tid: int = int(town["id"])
	var shop: Dictionary = bs.place_blueprint("shop", "humans", tid,
		Vector2(600, 500))
	shop["complete"] = true
	for i: int in range(8):
		gs.spawner.spawn_unit("humans", "worker", tid,
			Vector2(480 + i * 8, 480))
	for i: int in range(300):
		hiring.tick(1.0 / 60.0, 12.0)
	var ids: Array = []
	var shop_id: int = int(shop.get("id", -1))
	var ok: bool = gs.population.count_job("humans", "shopkeeper") == 2
	for u: Dictionary in gs.units:
		if String(u.get("job", "")) == "shopkeeper":
			ids.append(int(u.get("id", 0)))
			if int((u.get("station", {}) as Dictionary).get("building_id", -1)) \
					!= shop_id:
				ok = false
	ids.sort()
	_free_world(w)
	return [ids, ok]


func _test_roster_hiring() -> void:
	var r1: Array = _hired_shopkeeper_ids()
	var r2: Array = _hired_shopkeeper_ids()
	# Roster scan: a completed shop publishes a 2-slot shopkeeper position.
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "humans")
	var shop: Dictionary = bs.place_blueprint("shop", "humans",
		int(town["id"]), Vector2(600, 500))
	shop["complete"] = true
	var shop_pos: Dictionary = {}
	for p: Dictionary in (GuildHiring.new(gs) as GuildHiring).scan_positions():
		if String(p.get("job", "")) == "shopkeeper":
			shop_pos = p
	_check("roster: shopkeeper position scanned", not shop_pos.is_empty())
	_check("roster: shop slots = 2", int(shop_pos.get("slots", 0)) == 2)
	_free_world(w)
	_check("hire: 2 shopkeepers staffed + stationed",
		bool(r1[1]) and (r1[0] as Array).size() == 2)
	_check("hire: deterministic across runs", (r1[0] as Array) == (r2[0] as Array))


## --- Barracks beds ------------------------------------------------------------

func _test_barracks_beds() -> void:
	_check("barracks: 25 beds law", Config.BARRACKS_BEDS == 25)
	var w := _new_world(["ogres"])
	_give(w, "ogres")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var hiring: GuildHiring = w["hiring"]
	var town: Dictionary = _found(w, "ogres")
	var tid: int = int(town["id"])
	var br: Dictionary = bs.place_blueprint("barracks", "ogres", tid,
		Vector2(600, 500))
	br["complete"] = true
	var s: Dictionary = gs.spawner.spawn_unit("ogres", "soldier", tid,
		Vector2(590, 500))
	var bed: Dictionary = hiring.assign_barracks_bed(s)
	_check("barracks: bunk assigned", not bed.is_empty())
	_check("barracks: home set",
		int((s.get("home", {}) as Dictionary).get("id", -1))
		== int(bed.get("id", -2)))
	# Least-full wins: second barracks takes the next soldier.
	var br2: Dictionary = bs.place_blueprint("barracks", "ogres", tid,
		Vector2(700, 500))
	br2["complete"] = true
	var s2: Dictionary = gs.spawner.spawn_unit("ogres", "soldier", tid,
		Vector2(590, 510))
	var bed2: Dictionary = hiring.assign_barracks_bed(s2)
	_check("barracks: least-full barracks",
		int(bed2.get("id", -1)) == int(br2.get("id", -2)))
	var dem: Dictionary = hiring.barracks_demand("ogres")
	_check("barracks: demand beds 50", int(dem.get("beds", 0)) == 50)
	_check("barracks: demand assigned 2", int(dem.get("assigned", 0)) == 2)
	_check("barracks: no shortfall", int(dem.get("shortfall", 0)) == 0)
	_free_world(w)


## --- Training queue -------------------------------------------------------------

func _test_training_queue() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var hiring: GuildHiring = w["hiring"]
	var town: Dictionary = _found(w, "humans")
	var tid: int = int(town["id"])
	var br: Dictionary = bs.place_blueprint("barracks", "humans", tid,
		Vector2(600, 500))
	br["complete"] = true
	_check("train: barracks trains soldiers",
		GuildHiring.can_train("barracks", "soldier"))
	_check("train: barracks can't train workers",
		not GuildHiring.can_train("barracks", "worker"))
	_check("train: hall trains workers",
		GuildHiring.can_train("town_hall", "worker"))
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	_check("train: queued", hiring.queue_training(br, "soldier"))
	_check("train: cost charged",
		gs.resources.get_amount("humans", "gold") < gold_before)
	# Fill the queue to the max of 5; the 6th job is rejected.
	_check("train: archer queued", hiring.queue_training(br, "archer"))
	_check("train: ranger queued", hiring.queue_training(br, "ranger"))
	_check("train: mage queued", hiring.queue_training(br, "mage"))
	_check("train: cannoneer queued", hiring.queue_training(br, "cannoneer"))
	_check("train: 6th job rejected (queue full)",
		not hiring.queue_training(br, "guard"))
	_check("train: block reason", hiring.last_train_block == "queue_full")
	# Tick the queue to graduation (soldier: 3.8 s).
	for i: int in range(600):
		hiring.tick(1.0 / 60.0, 12.0)
	_check("train: soldier graduated",
		gs.population.count_job("humans", "soldier") == 1)
	_check("train: graduate housed in barracks",
		not (gs.units[gs.units.size() - 1] as Dictionary).get("home", {}).is_empty())
	# Unaffordable training is rejected up front.
	gs.resources.add_resource("humans", "gold", -100000.0)
	var broke: bool = hiring.queue_training(br, "guard")
	_check("train: unaffordable rejected", not broke)
	_check("train: block reason unaffordable",
		hiring.last_train_block == "unaffordable")
	_free_world(w)


## --- Housing counts --------------------------------------------------------------

func _test_housing_counts() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var housing: SimHousing = w["housing"]
	var town: Dictionary = _found(w, "gnomes")
	var tid: int = int(town["id"])
	for i: int in range(3):
		var h: Dictionary = bs.place_blueprint("house", "gnomes", tid,
			Vector2(600 + i * 80, 500))
		h["complete"] = true
	_check("housing: town count 3",
		housing.town_house_count("gnomes", tid) == 3)
	_check("housing: countryside 0",
		housing.countryside_house_count("gnomes") == 0)
	# A flagged countryside house counts rural, not town.
	var ch: Dictionary = bs.place_blueprint("house", "gnomes", -1,
		Vector2(2000, 2000))
	ch["complete"] = true
	ch["countryside"] = true
	_check("housing: countryside 1",
		housing.countryside_house_count("gnomes") == 1)
	_check("housing: town still 3",
		housing.town_house_count("gnomes", tid) == 3)
	_free_world(w)


## --- Homeless migration --------------------------------------------------------------

func _test_homeless_migration() -> void:
	var w := _new_world(["elves"])
	_give(w, "elves")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var housing: SimHousing = w["housing"]
	var town: Dictionary = _found(w, "elves")
	var tid: int = int(town["id"])
	# Fill the town to 15 houses (cap).
	for i: int in range(15):
		var h: Dictionary = bs.place_blueprint("house", "elves", tid,
			Vector2(600 + (i % 5) * 80, 560 + (i / 5) * 80))
		h["complete"] = true
	_check("migration: town at cap",
		housing.town_house_count("elves", tid) == 15)
	# A homeless civilian with no affordable home migrates out.
	var u: Dictionary = gs.spawner.spawn_unit("elves", "worker", tid,
		Vector2(500, 520))
	u["coins"] = 0.0
	housing.tick(1.0 / 60.0)
	_check("migration: walking out",
		(u.get("_country_move", Vector2(-1, -1)) as Vector2).x >= 0.0)
	_free_world(w)


## --- Survival-craft homestead --------------------------------------------------------------

func _test_homestead() -> void:
	var w := _new_world(["ogres"])
	_give(w, "ogres")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var housing: SimHousing = w["housing"]
	var town: Dictionary = _found(w, "ogres")
	var tid: int = int(town["id"])
	# Town at cap (15) so the homestead gate opens for homeless civilians.
	for i: int in range(15):
		var th: Dictionary = bs.place_blueprint("house", "ogres", tid,
			Vector2(600 + (i % 5) * 80, 560 + (i / 5) * 80))
		th["complete"] = true
	# Countryside nearly full: one slot left for the self-built house.
	for i: int in range(15):
		var ch: Dictionary = bs.place_blueprint("house", "ogres", -1,
			Vector2(3000 + (i % 5) * 80, 3000 + (i / 5) * 80))
		ch["complete"] = true
		ch["countryside"] = true
	(gs.buildings[gs.buildings.size() - 1] as Dictionary)["alive"] = false
	_check("homestead: country 14/15",
		housing.countryside_house_count("ogres") == 14)
	# The unit is already out in the wild (migrated earlier); personal
	# gathering nodes nearby.
	gs.add_work_site({"kind": "tree", "position": Vector2(1560, 1500),
		"amount": 500.0})
	gs.add_work_site({"kind": "rock", "position": Vector2(1580, 1520),
		"amount": 500.0})
	var u: Dictionary = gs.spawner.spawn_unit("ogres", "worker", tid,
		Vector2(1550, 1500))
	u["coins"] = 0.0
	# Run housing ticks: gather (18 swings x 2.6 s) then build.
	for i: int in range(60 * 150):
		housing.tick(1.0 / 60.0)
		if housing.countryside_house_count("ogres") == 15:
			break
	_check("homestead: house raised",
		housing.countryside_house_count("ogres") == 15)
	# The new house is owned by the unit, not for sale.
	var mine: Dictionary = {}
	for b: Dictionary in gs.buildings:
		if int(b.get("owner_unit", -1)) == int(u.get("id", 0)):
			mine = b
	_check("homestead: owner recorded", not mine.is_empty())
	_check("homestead: not for sale", not bool(mine.get("for_sale", true)))
	_check("homestead: countryside flag", bool(mine.get("countryside", false)))
	_free_world(w)


## --- Buy a home ------------------------------------------------------------------

func _test_buy_home() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var housing: SimHousing = w["housing"]
	var town: Dictionary = _found(w, "humans")
	var tid: int = int(town["id"])
	var h: Dictionary = bs.place_blueprint("house", "humans", tid,
		Vector2(600, 500))
	h["complete"] = true
	housing.tick(1.0 / 60.0)  # lists the empty house for sale
	_check("buy: listed", bool(h.get("for_sale", false)))
	var price: float = float(h.get("price", 0.0))
	_check("buy: price = 100 + footprint", price == 100.0 + 30.0)
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", tid,
		Vector2(590, 500))
	u["coins"] = 500.0
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	for i: int in range(600):
		housing.tick(1.0 / 60.0)
		if int(h.get("owner_unit", -1)) == int(u.get("id", 0)):
			break
	_check("buy: deed transferred",
		int(h.get("owner_unit", -1)) == int(u.get("id", 0)))
	_check("buy: moved in", not (u.get("home", {}) as Dictionary).is_empty())
	_check("buy: coins spent",
		float(u.get("coins", 0.0)) == 500.0 - price)
	_check("buy: price paid to treasury",
		is_equal_approx(gs.resources.get_amount("humans", "gold"),
			gold_before + price))
	_free_world(w)


## --- Faction work priority ----------------------------------------------------------

func _test_work_priority() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "gnomes")
	var tid: int = int(town["id"])
	# Starve gold: the generalist must head for the gold vein.
	gs.resources.add_resource("gnomes", "gold", -99999.0)
	gs.resources.add_resource("gnomes", "wood", 500.0, true)
	gs.add_work_site({"kind": "tree", "position": Vector2(520, 500),
		"amount": 200.0})
	gs.add_work_site({"kind": "gold_vein", "position": Vector2(700, 500),
		"amount": 200.0})
	var u: Dictionary = gs.spawner.spawn_unit("gnomes", "worker", tid,
		Vector2(510, 500))
	ai.tick_unit(u, bs, 1.0 / 60.0)
	var site: Dictionary = gs.get_work_site(int(u.get("work_site", -1)))
	_check("priority: scarcest resource first",
		String(site.get("kind", "")) == "gold_vein")
	_free_world(w)


## --- Roadbuilder ----------------------------------------------------------------------

func _test_roadbuilder() -> void:
	var w := _new_world(["elves"])
	_give(w, "elves")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "elves")
	var tid: int = int(town["id"])
	# Hall is at (500,500); spawn the crew away so they walk an order.
	var u: Dictionary = gs.spawner.spawn_unit("elves", "roadbuilder", tid,
		Vector2(300, 500))
	for i: int in range(1200):
		ai.tick_unit(u, bs, 1.0 / 60.0)
	_check("road: painted records", (ai.roads as Array).size() > 0)
	var first: Dictionary = (ai.roads as Array)[0]
	_check("road: faction tagged",
		String(first.get("faction", "")) == "elves")
	_check("road: type dirt or stone",
		String(first.get("type", "")) in ["dirt", "stone"])
	_free_world(w)


## --- Firefighter dispatch untouched ------------------------------------------------------
## disasters.gd already auto-dispatches firefighters with truck speed;
## WorkerAI must not fight it for the unit.

func _test_fire_dispatch_untouched() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var town: Dictionary = _found(w, "humans")
	var tid: int = int(town["id"])
	var u: Dictionary = gs.spawner.spawn_unit("humans", "firefighter", tid,
		Vector2(500, 520))
	ai.tick_unit(u, w["buildings"], 1.0 / 60.0)
	_check("fire: workerAI holds position",
		String(u.get("work_state", "")) == "idle")
	_free_world(w)
