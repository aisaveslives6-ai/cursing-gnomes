extends SceneTree
## Cursing Gnomes — Milestone 3b buildings/walls/territory tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_buildings2.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes buildings2 tests ===")
	_test_territory()
	_test_building_cap()
	_test_new_uniques()
	_test_restaurants()
	_test_categories()
	_test_wall_drag()
	_test_star_fort()
	_test_border_walls()
	_test_interior_bathrooms()
	_test_crew_of()
	_test_gov_buildings()
	_test_bridge_drag()
	_test_boats()
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


func _new_world(factions: Array[String]) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	var sys := {
		"gs": gs,
		"buildings": SimBuildings.new(gs),
		"wall_drag": WallDrag.new(),
		"bridge_drag": BridgeDrag.new(),
		"border": BorderWalls.new(gs),
		"interiors": SimInteriors.new(gs),
	}
	return sys


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


func _give(w: Dictionary, faction: String, amount: float = 100000.0) -> void:
	var gs: GameState = w["gs"]
	for res: String in Config.RESOURCES:
		gs.resources.add_resource(faction, res, amount, true)


const MAP_RECT := Rect2(-100000, -100000, 200000, 200000)


## --- Territory claims --------------------------------------------------------

func _test_territory() -> void:
	var w := _new_world(["humans", "ogres"])
	var gs: GameState = w["gs"]
	_give(w, "humans")
	_give(w, "ogres")
	_found(w, "humans")  # completed hall at (500,500) claims 520px
	# Claim owner.
	_check("terr: humans own their hall ground",
		SimTerritory.claim_owner_at(gs.buildings, Vector2(600, 500)) == "humans")
	_check("terr: wilds unclaimed",
		SimTerritory.claim_owner_at(gs.buildings, Vector2(5000, 5000)) == "")
	_check("terr: TERRITORY_R 520",
		SimTerritory.claim_owner_at(gs.buildings, Vector2(500 + 519, 500)) == "humans")
	_check("terr: beyond radius unclaimed",
		SimTerritory.claim_owner_at(gs.buildings, Vector2(500 + 521, 500)) == "")
	# Enemy-territory placement rule (HTML canPlaceBuilding): foreign builds
	# blocked, walls exempt, own builds fine.
	_check("terr: ogre house in human land blocked",
		not SimBuildings.can_place_at(gs.buildings, "house", Vector2(600, 500),
			MAP_RECT, "ogres"))
	_check("terr: ogre wall in human land allowed",
		SimBuildings.can_place_at(gs.buildings, "wall", Vector2(600, 500),
			MAP_RECT, "ogres"))
	_check("terr: human house in own land allowed",
		SimBuildings.can_place_at(gs.buildings, "house", Vector2(600, 500),
			MAP_RECT, "humans"))
	_check("terr: ogre house in wilds allowed",
		SimBuildings.can_place_at(gs.buildings, "house", Vector2(5000, 5000),
			MAP_RECT, "ogres"))
	# Incomplete halls claim nothing.
	var w2 := _new_world(["elves"])
	_give(w2, "elves")
	var gs2: GameState = w2["gs"]
	var town2: Dictionary = gs2.found_town("elves", "T", Vector2(500, 500))
	(w2["buildings"] as SimBuildings).place_blueprint(
		"town_hall", "elves", int(town2["id"]), Vector2(500, 500))
	_check("terr: incomplete hall claims nothing",
		SimTerritory.claim_owner_at(gs2.buildings, Vector2(600, 500)) == "")
	# Named regions: two far halls = two regions with names from the pool.
	var town3: Dictionary = gs2.found_town("elves", "T2", Vector2(5000, 5000))
	var h2: Dictionary = (w2["buildings"] as SimBuildings).place_blueprint(
		"town_hall", "elves", int(town3["id"]), Vector2(5000, 5000))
	h2["complete"] = true
	var h1: Dictionary = (w2["buildings"] as SimBuildings).place_blueprint(
		"town_hall", "elves", int(town2["id"]), Vector2(500, 500))
	h1["complete"] = true
	var regions: Array = SimTerritory.compute_regions(gs2.buildings)
	# Two far halls = two faction clusters, plus the unclaimed 4x3 sectors
	# (HTML getRegions parity): sector (0,0) is claimed by the (500,500)
	# hall, the other 11 are wild.
	_check("terr: two far halls -> two clusters + eleven sectors",
		regions.size() == 13)
	var faction_regions: Array = regions.filter(func(r: Dictionary) -> bool:
		return String(r.get("race", "")) != "")
	_check("terr: two faction clusters", faction_regions.size() == 2)
	_check("terr: region names from pool",
		String(regions[0]["name"]) != "" and String(regions[1]["name"]) != ""
		and String(regions[0]["name"]) != String(regions[1]["name"]))
	_free_world(w)
	_free_world(w2)


## --- Building hard cap 180 ---------------------------------------------------

func _test_building_cap() -> void:
	var w := _new_world(["humans"])
	var bs: SimBuildings = w["buildings"]
	_give(w, "humans")
	_found(w, "humans")
	var ok := 0
	for i: int in range(190):
		var b: Dictionary = bs.place_blueprint("wall", "humans", 1,
			Vector2(2000 + i * 40, 2000))
		if not b.is_empty():
			ok += 1
	_check("cap: 180 walls place", ok == 180)
	_check("cap: count_capped 180",
		SimBuildings.count_capped((w["gs"] as GameState).buildings) == 180)
	var over: Dictionary = bs.place_blueprint("wall", "humans", 1,
		Vector2(9000, 9000))
	_check("cap: 181st blocked", over.is_empty())
	_check("cap: block reason", bs.last_block_reason == "building_cap")
	# Halls are exempt (town centers).
	var town: Dictionary = (w["gs"] as GameState).found_town(
		"humans", "T2", Vector2(9000, 9000))
	var hall: Dictionary = bs.place_blueprint("town_hall", "humans",
		int(town["id"]), Vector2(9000, 9000))
	_check("cap: hall exempt", not hall.is_empty())
	_free_world(w)


## --- Faction uniques (elves + undead additions) --------------------------------

func _test_new_uniques() -> void:
	var w := _new_world(["elves", "undead", "humans"])
	var bs: SimBuildings = w["buildings"]
	for f: String in ["elves", "undead", "humans"]:
		_give(w, f)
		_found(w, f)
	# Elf unique.
	var tl: Dictionary = bs.place_blueprint("tome_library", "elves", 0,
		Vector2(1500, 500))
	_check("unique: tome_library places for elves", not tl.is_empty())
	var tl_bad: Dictionary = bs.place_blueprint("tome_library", "humans", 0,
		Vector2(1600, 500))
	_check("unique: tome_library blocked for humans", tl_bad.is_empty())
	_check("unique: tome_library reason",
		bs.last_block_reason == "wrong_faction")
	# Undead uniques.
	var nec: Dictionary = bs.place_blueprint("necropolis", "undead", 0,
		Vector2(1500, 600))
	_check("unique: necropolis places for undead", not nec.is_empty())
	var nec_bad: Dictionary = bs.place_blueprint("necropolis", "elves", 0,
		Vector2(1600, 600))
	_check("unique: necropolis blocked for elves", nec_bad.is_empty())
	var cafe: Dictionary = bs.place_blueprint("soul_cafe", "undead", 0,
		Vector2(1500, 700))
	_check("unique: soul_cafe places for undead", not cafe.is_empty())
	var cafe_bad: Dictionary = bs.place_blueprint("soul_cafe", "humans", 0,
		Vector2(1600, 700))
	_check("unique: soul_cafe blocked for humans", cafe_bad.is_empty())
	# Helpers.
	_check("unique: helper library/elves",
		SimBuildings.faction_may_build("tome_library", "elves"))
	_check("unique: helper necropolis/humans blocked",
		not SimBuildings.faction_may_build("necropolis", "humans"))
	_check("unique: military routing necropolis",
		SimZoning.suggested_zone_for("necropolis") == "M")
	_check("unique: military routing tome_library",
		SimZoning.suggested_zone_for("tome_library") == "M")
	_free_world(w)


## --- Per-race restaurants ------------------------------------------------------

func _test_restaurants() -> void:
	_check("eat: human", SimBuildings.eatery_name("humans") == "Cheese Shop")
	_check("eat: ogre", SimBuildings.eatery_name("ogres") == "Ogre Fried Turkey")
	_check("eat: elf", SimBuildings.eatery_name("elves") == "Gilded Acorn")
	_check("eat: gnome", SimBuildings.eatery_name("gnomes") == "Taco Bastard")
	_check("eat: undead", SimBuildings.eatery_name("undead") == "Soul Café")
	_check("eat: fallback", SimBuildings.eatery_name("???") == "Tavern")
	_check("eat: display_name undead",
		SimBuildings.display_name("restaurant", "undead") == "Soul Café")
	_check("eat: display_name human",
		SimBuildings.display_name("restaurant", "humans") == "Cheese Shop")
	_check("eat: dish taco", String(SimBuildings.eatery_dish("gnomes")["id"]) == "taco")
	_check("eat: dish soul brew",
		String(SimBuildings.eatery_dish("undead")["name"]) == "Soul Brew")
	# Restaurant places and completes for every faction.
	var w := _new_world(["humans", "ogres", "elves", "gnomes", "undead"])
	var bs: SimBuildings = w["buildings"]
	for f: String in ["humans", "ogres", "elves", "gnomes", "undead"]:
		_give(w, f)
		var town: Dictionary = _found(w, f)
		var r: Dictionary = bs.place_blueprint("restaurant", f, int(town["id"]),
			Vector2(600, 500))
		_check("eat: restaurant places for %s" % f, not r.is_empty())
		_check("eat: restaurant completes for %s" % f,
			bs.tick_construction(r, 500.0, 1.0))
	_free_world(w)


## --- Build-menu category tabs ---------------------------------------------------

func _test_categories() -> void:
	_check("cat: zones tab exists",
		SimBuildings.BUILD_TABS[0][0] == "zones")
	_check("cat: 5 tabs", SimBuildings.BUILD_TABS.size() == 5)
	_check("cat: house -> homes", SimBuildings.build_category("house") == "homes")
	_check("cat: inn -> homes", SimBuildings.build_category("inn") == "homes")
	_check("cat: zone_R -> zones", SimBuildings.build_category("zone_R") == "zones")
	_check("cat: barracks -> military",
		SimBuildings.build_category("barracks") == "military")
	_check("cat: cannon_foundry -> military",
		SimBuildings.build_category("cannon_foundry") == "military")
	_check("cat: tome_library -> military",
		SimBuildings.build_category("tome_library") == "military")
	_check("cat: necropolis -> military",
		SimBuildings.build_category("necropolis") == "military")
	_check("cat: nuke_silo -> military",
		SimBuildings.build_category("nuke_silo") == "military")
	_check("cat: clinic -> services",
		SimBuildings.build_category("clinic") == "services")
	_check("cat: wall -> services", SimBuildings.build_category("wall") == "services")


## --- Wall drag-to-place -----------------------------------------------------------

func _test_wall_drag() -> void:
	# A 440px drag = 10 segments at 44px spacing.
	var plan: Dictionary = WallDrag.plan_path(Vector2(0, 0), Vector2(440, 0),
		[], "humans", MAP_RECT)
	_check("drag: 10 segments", (plan["segments"] as Array).size() == 10)
	_check("drag: all valid", int(plan.get("valid_count", 0)) == 10)
	# Deterministic boundaries: segment i+1 starts exactly where i ends.
	var segs: Array = plan["segments"]
	var s0: Dictionary = segs[0]
	var s1: Dictionary = segs[1]
	_check("drag: shared boundary x",
		absf(float(s0["x1"]) - float(s1["x0"])) < 0.001)
	_check("drag: leg end verbatim",
		absf(float((segs[9] as Dictionary)["x1"]) - 440.0) < 0.001)
	# Endpoints snap to existing walls within 78px.
	var existing: Array = [{"alive": true, "type": "wall", "faction": "humans",
		"position": Vector2(44, 0)}]
	var plan2: Dictionary = WallDrag.plan_path(Vector2(50, 0), Vector2(500, 0),
		existing, "humans", MAP_RECT)
	_check("drag: start snaps to wall",
		(plan2["start"] as Vector2).distance_to(Vector2(44, 0)) < 0.001)
	# Tap = one segment.
	var tap: Dictionary = WallDrag.plan_tap(Vector2(2000, 2000), [],
		"humans", MAP_RECT)
	_check("tap: exactly 1 segment", (tap.get("segments", []) as Array).size() == 1)
	_check("tap: valid", int(tap.get("valid_count", 0)) == 1)
	# Commit: each segment becomes a staged blueprint (not instantly done).
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "humans")
	var res: Dictionary = (w["wall_drag"] as WallDrag).commit(bs, plan,
		"humans", int(town["id"]), {})
	_check("drag: commit places 10", (res.get("placed", []) as Array).size() == 10)
	var staged := true
	var tagged := true
	for b: Dictionary in res.get("placed", []):
		if b.get("complete", true):
			staged = false
		if String(b.get("wall_run_id", "")) == "":
			tagged = false
	_check("drag: segments staged (incomplete)", staged)
	_check("drag: segments tagged with run id", tagged)
	_check("drag: run id returned", String(res.get("run_id", "")) != "")
	# Walls build in stages: tick_construction raises them over time.
	var first: Dictionary = (res.get("placed", []) as Array)[0]
	_check("drag: staged wall completes via tick",
		bs.tick_construction(first, 500.0, 1.0))
	_free_world(w)


## --- Star fort ---------------------------------------------------------------------

func _test_star_fort() -> void:
	var center := Vector2(3000, 3000)
	var plan: Dictionary = StarFort.plan(center, 170.0)
	_check("star: 5 corner towers", (plan["tower_pts"] as Array).size() == 5)
	_check("star: 9 base slots", (plan["slots"] as Array).size() == 9)
	_check("star: 4 gap roads", (plan["roads"] as Array).size() == 4)
	# The 4 gaps are real openings: no wall point near each road midpoint.
	var gaps_open := true
	for road: Dictionary in plan.get("roads", []):
		var mid := Vector2(
			(float(road["x1"]) + float(road["x2"])) * 0.5,
			(float(road["y1"]) + float(road["y2"])) * 0.5)
		for p: Vector2 in plan.get("wall_pts", []):
			if p.distance_to(mid) < 40.0:
				gaps_open = false
	_check("star: 4 openings are gaps, not walls", gaps_open)
	# Walls pushed well out: every wall point is beyond the base slots.
	# (The star's inner re-entrant corners sit at 0.62*R by design.)
	var well_out := true
	for p2: Vector2 in plan.get("wall_pts", []):
		if p2.distance_to(center) < 100.0:
			well_out = false
	_check("star: walls pushed out past base buildings", well_out)
	# Slot types match the HTML star_fort plan.
	var types: Array = []
	for sl: Dictionary in plan.get("slots", []):
		types.append(String(sl.get("type", "")))
	_check("star: has medic_camp slot", "medic_camp" in types)
	_check("star: has cannon_foundry slot", "cannon_foundry" in types)
	_check("star: has equip_camp slot", "equip_camp" in types)
	_check("star: 3 aa_towers",
		types.count("aa_tower") == 3 and types.count("barracks") == 2)
	# Commit: towers + wall runs + slots + military zone.
	var w := _new_world(["ogres"])
	_give(w, "ogres")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "ogres")
	var made: Dictionary = StarFort.new().commit(gs, bs, plan, "ogres",
		int(town["id"]), w["wall_drag"])
	_check("star: commit places buildings",
		(made.get("buildings", []) as Array).size() >= 14)
	_check("star: paints military zone",
		String((made.get("zone", {}) as Dictionary).get("type", "")) == "M")
	# Corner towers are guard towers tagged with the fort plan.
	var towers := 0
	for b: Dictionary in made.get("buildings", []):
		if String(b.get("type", "")) == "guard_tower" \
				and String(b.get("fort_plan", "")) == "star":
			towers += 1
	_check("star: 5 corner towers committed", towers == 5)
	_free_world(w)


## --- Border-wall AI -------------------------------------------------------------------

func _test_border_walls() -> void:
	# AI race auto-commits its region ring.
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	_found(w, "gnomes")
	(w["border"] as BorderWalls).tick("gnomes", false, bs, w["wall_drag"])
	var ai_walls := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "wall" and bool(b.get("ai_wall", false)):
			ai_walls += 1
	_check("border: AI commits region ring", ai_walls > 20)
	# Ring stands off the town: every AI wall is >= 1400*0.9 from the hall.
	var standoff := true
	for b2: Dictionary in gs.buildings:
		if String(b2.get("type", "")) == "wall" and bool(b2.get("ai_wall", false)):
			if (b2.get("position", Vector2.ZERO) as Vector2).distance_to(
					Vector2(500, 500)) < 1400.0 * 0.9:
				standoff = false
	_check("border: ring stands off the town", standoff)
	# The ring has an opening: the largest angular gap between consecutive
	# AI walls is far wider than the regular 44px spacing.
	var angles: Array = []
	for b3: Dictionary in gs.buildings:
		if String(b3.get("type", "")) == "wall" and bool(b3.get("ai_wall", false)):
			var v: Vector2 = (b3.get("position", Vector2.ZERO) as Vector2) \
				- Vector2(500, 500)
			angles.append(v.angle())
	angles.sort()
	var max_gap := 0.0
	for i: int in range(angles.size()):
		var a0: float = angles[i]
		var a1: float = angles[(i + 1) % angles.size()]
		var d: float = a1 - a0
		if d < 0.0:
			d += TAU
		max_gap = max(max_gap, d)
	_check("border: opening gap in ring", max_gap > 0.2)
	_free_world(w)
	# Player race: unanswered regions queue the prompt; Raise auto-commits,
	# Skip never asks again.
	var w2 := _new_world(["humans"])
	_give(w2, "humans")
	var gs2: GameState = w2["gs"]
	var bs2: SimBuildings = w2["buildings"]
	var bw: BorderWalls = w2["border"]
	_found(w2, "humans")
	bw.tick("humans", true, bs2, w2["wall_drag"])
	_check("border: player gets prompt queued",
		(bw.pending as Array).size() == 1)
	var rname: String = String((bw.pending[0] as Dictionary).get("region_name", ""))
	_check("border: prompt names a region", rname != "")
	# No walls yet for the player race (prompt unanswered).
	var pre := 0
	for b4: Dictionary in gs2.buildings:
		if String(b4.get("type", "")) == "wall" and bool(b4.get("ai_wall", false)):
			pre += 1
	_check("border: no player walls before answer", pre == 0)
	# Skip: policy remembered, prompt cleared, no walls.
	bw.answer(rname, false, bs2, w2["wall_drag"])
	_check("border: skip clears prompt", (bw.pending as Array).is_empty())
	_check("border: skip policy stored", String(bw.policy.get(rname, "")) == "skip")
	bw.cooldowns.clear()
	bw.tick("humans", true, bs2, w2["wall_drag"])
	_check("border: skip never re-asks", (bw.pending as Array).is_empty())
	var after_skip := 0
	for b5: Dictionary in gs2.buildings:
		if String(b5.get("type", "")) == "wall" and bool(b5.get("ai_wall", false)):
			after_skip += 1
	_check("border: skip commits nothing", after_skip == 0)
	# Raise on a fresh policy: auto-commits.
	var w3 := _new_world(["elves"])
	_give(w3, "elves")
	var gs3: GameState = w3["gs"]
	var bs3: SimBuildings = w3["buildings"]
	var bw3: BorderWalls = w3["border"]
	_found(w3, "elves")
	bw3.tick("elves", true, bs3, w3["wall_drag"])
	var rname3: String = String((bw3.pending[0] as Dictionary).get("region_name", ""))
	bw3.answer(rname3, true, bs3, w3["wall_drag"])
	_check("border: raise policy stored", String(bw3.policy.get(rname3, "")) == "raise")
	var raised := 0
	for b6: Dictionary in gs3.buildings:
		if String(b6.get("type", "")) == "wall" and bool(b6.get("ai_wall", false)):
			raised += 1
	_check("border: raise commits the ring", raised > 20)
	# Policy survives save/load (to_dict/from_dict), pending does not.
	var saved: Dictionary = bw3.to_dict()
	var bw4 := BorderWalls.new(gs3)
	bw4.from_dict(saved)
	_check("border: policy round-trips",
		String(bw4.policy.get(rname3, "")) == "raise")
	_check("border: pending not persisted", (bw4.pending as Array).is_empty())
	bw4.reset_for_new_game()
	_check("border: new game resets policy", (bw4.policy as Dictionary).is_empty())
	_free_world(w2)
	_free_world(w3)


## --- Interiors: bathrooms in ALL enterable buildings -------------------------------------

func _test_interior_bathrooms() -> void:
	var w := _new_world(["humans"])
	var intr: SimInteriors = w["interiors"]
	var missing: Array = []
	for btype: String in SimInteriors.ENTERABLE:
		var b: Dictionary = {"type": btype, "faction": "humans", "id": 1,
			"complete": true, "alive": true}
		var kinds := {}
		for p: Dictionary in intr.furniture_of(b):
			kinds[String(p.get("kind", ""))] = true
		for need: String in ["toilet", "sink", "tub"]:
			if not kinds.has(need):
				missing.append("%s lacks %s" % [btype, need])
	_check("interior: every enterable plan has toilet+sink+tub",
		missing.is_empty())
	if not missing.is_empty():
		print("    missing: ", missing)
	# Named rooms exist on the eatery plan.
	var rb: Dictionary = {"type": "restaurant", "faction": "gnomes", "id": 2,
		"complete": true, "alive": true}
	var rooms := {}
	for p2: Dictionary in intr.furniture_of(rb):
		rooms[String(p2.get("room", ""))] = true
	_check("interior: eatery has named rooms",
		rooms.has("Kitchen") and rooms.has("Dining") and rooms.has("Bath"))
	_free_world(w)


## --- Builder crew visibility ---------------------------------------------------------------

func _test_crew_of() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "humans")
	var b: Dictionary = bs.place_blueprint("house", "humans", int(town["id"]),
		Vector2(600, 500))
	var u1: Dictionary = gs.spawner.spawn_unit("humans", "builder",
		int(town["id"]), Vector2(590, 500))
	u1["work_state"] = "building"
	u1["work_building"] = int(b["id"])
	var u2: Dictionary = gs.spawner.spawn_unit("humans", "woodcutter",
		int(town["id"]), Vector2(580, 500))
	var crew: Array = SimBuildings.crew_of(gs.units, int(b["id"]))
	_check("crew: assigned builder listed", crew.has(int(u1["id"])))
	_check("crew: uninvolved unit not listed", not crew.has(int(u2["id"])))
	_check("crew: wrong building empty",
		SimBuildings.crew_of(gs.units, 99999).is_empty())
	_free_world(w)


## --- Government district (gov_* offices) ------------------------------------------------

func _test_gov_buildings() -> void:
	# Registry: HTML COSTS / hpMap / sizeMap values.
	var c: Dictionary = SimBuildings.cost_of("gov_office")
	_check("gov: office cost", float(c.get("wood", 0)) == 60.0
		and float(c.get("oil", 0)) == 40.0 and float(c.get("gold", 0)) == 80.0)
	c = SimBuildings.cost_of("gov_treasury")
	_check("gov: treasury cost", float(c.get("wood", 0)) == 55.0
		and float(c.get("gold", 0)) == 90.0)
	c = SimBuildings.cost_of("gov_war_office")
	_check("gov: war office cost", float(c.get("wood", 0)) == 70.0
		and float(c.get("gold", 0)) == 100.0)
	c = SimBuildings.cost_of("gov_justice")
	_check("gov: justice cost", float(c.get("wood", 0)) == 60.0
		and float(c.get("gold", 0)) == 85.0)
	_check("gov: hp", float((SimBuildings.BUILDINGS["gov_office"] as Dictionary).get("hp", 0)) == 500.0
		and float((SimBuildings.BUILDINGS["gov_treasury"] as Dictionary).get("hp", 0)) == 520.0
		and float((SimBuildings.BUILDINGS["gov_war_office"] as Dictionary).get("hp", 0)) == 540.0
		and float((SimBuildings.BUILDINGS["gov_justice"] as Dictionary).get("hp", 0)) == 500.0)
	_check("gov: sizes", SimBuildings.footprint("gov_office") == 56.0
		and SimBuildings.footprint("gov_treasury") == 58.0
		and SimBuildings.footprint("gov_war_office") == 58.0
		and SimBuildings.footprint("gov_justice") == 56.0)
	# Helpers.
	_check("gov: is_gov_building", SimBuildings.is_gov_building("gov_office")
		and SimBuildings.is_gov_building("gov_justice")
		and not SimBuildings.is_gov_building("courthouse"))
	_check("gov: not player-buildable",
		not SimBuildings.is_player_buildable("gov_office")
		and not SimBuildings.is_player_buildable("gov_treasury")
		and SimBuildings.is_player_buildable("house"))
	_check("gov: 4 advisor roles",
		(SimBuildings.GOV_ADVISOR_ROLES as Array).size() == 4)
	# District auto-lay around the hall: free, complete, is_gov, right spots.
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "humans")
	var hall: Dictionary = {}
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "town_hall":
			hall = b
	var placed: Array = bs.lay_government_district("humans", hall,
		int(town["id"]))
	_check("gov: district lays 4 offices", placed.size() == 4)
	var want := {
		"gov_office": Vector2(500 - 192, 500 - 288),
		"gov_treasury": Vector2(500 + 192, 500 - 288),
		"gov_war_office": Vector2(500 - 192, 500 - 384),
		"gov_justice": Vector2(500 + 192, 500 - 384),
	}
	var spots_ok := true
	var live_ok := true
	for p: Dictionary in placed:
		var t: String = String(p.get("type", ""))
		if not want.has(t):
			spots_ok = false
		elif (p.get("position", Vector2.ZERO) as Vector2).distance_to(
				want[t]) > 0.001:
			spots_ok = false
		if not bool(p.get("complete", false)) or not bool(p.get("is_gov", false)):
			live_ok = false
		if String(p.get("faction", "")) != "humans":
			live_ok = false
	_check("gov: offices at district offsets", spots_ok)
	_check("gov: offices free + complete + is_gov", live_ok)
	_check("gov: district counts toward cap",
		SimBuildings.count_capped(gs.buildings) == 4)
	# Idempotent: second call lays nothing.
	var again: Array = bs.lay_government_district("humans", hall,
		int(town["id"]))
	_check("gov: district lay is idempotent", again.is_empty()
		and SimBuildings.count_capped(gs.buildings) == 4)
	# Decisions: 5 known ids, deterministic pick.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var ids := {}
	for i: int in range(20):
		ids[String(SimBuildings.pick_gov_decision(rng).get("id", ""))] = true
	_check("gov: 5 decision ids",
		ids.size() == 5 and ids.has("draft") and ids.has("tax")
		and ids.has("peace") and ids.has("artillery") and ids.has("rations"))
	# Interiors: enterable, advisor cubicles present, bathrooms (the shared
	# bathroom test covers the trio; here we check the office content).
	var intr: SimInteriors = w["interiors"]
	for gt: String in SimBuildings.GOV_OFFICE_TYPES:
		_check("gov: enterable " + gt, SimInteriors.is_enterable(gt))
	var gb: Dictionary = {"type": "gov_office", "faction": "humans", "id": 7,
		"complete": true, "alive": true}
	var desks := 0
	var dividers := 0
	var seal := ""
	for p2: Dictionary in intr.furniture_of(gb):
		if String(p2.get("label", "")) == "Advisor's Desk":
			desks += 1
		if String(p2.get("kind", "")) == "divider":
			dividers += 1
		if String(p2.get("label", "")) == "Town Hall Seal":
			seal = "Town Hall Seal"
	_check("gov: 2 advisor cubicles", desks == 2 and dividers >= 4)
	_check("gov: seal painting", seal == "Town Hall Seal")
	var tb: Dictionary = {"type": "gov_treasury", "faction": "humans", "id": 8,
		"complete": true, "alive": true}
	var tseal := ""
	for p3: Dictionary in intr.furniture_of(tb):
		if String(p3.get("label", "")) == "Treasury Seal":
			tseal = "Treasury Seal"
	_check("gov: treasury seal", tseal == "Treasury Seal")
	_free_world(w)


## --- Bridge drag tool ---------------------------------------------------------------------

func _test_bridge_drag() -> void:
	var always_water := func(_p: Vector2) -> bool: return true
	var never_water := func(_p: Vector2) -> bool: return false
	# A 300px drag = 10 segments at 30px spacing (over water).
	var plan: Dictionary = BridgeDrag.plan_path(Vector2(0, 100),
		Vector2(300, 100), [], MAP_RECT, always_water)
	_check("bridge: 10 segments", (plan["segments"] as Array).size() == 10)
	_check("bridge: all valid", int(plan.get("valid_count", 0)) == 10)
	var segs: Array = plan["segments"]
	_check("bridge: 30px spacing",
		absf(float((segs[1] as Dictionary)["x0"]) - float((segs[0] as Dictionary)["x0"]) - 30.0) < 0.001)
	_check("bridge: per-segment cost",
		float((plan["per_segment_cost"] as Dictionary).get("wood", 0)) == 10.0
		and float((plan["per_segment_cost"] as Dictionary).get("gold", 0)) == 2.0)
	_check("bridge: total cost 10x",
		float((plan["total_cost"] as Dictionary).get("wood", 0)) == 100.0
		and float((plan["total_cost"] as Dictionary).get("gold", 0)) == 20.0)
	# Placement rules (HTML canPlaceBridge).
	_check("bridge: dry land rejected",
		int((BridgeDrag.plan_path(Vector2(0, 100), Vector2(300, 100), [],
			MAP_RECT, never_water) as Dictionary).get("valid_count", -1)) == 0)
	var stacked: Array = [{"alive": true, "type": "bridge", "faction": "humans",
		"position": Vector2(60, 100)}]
	var plan2: Dictionary = BridgeDrag.plan_path(Vector2(0, 100),
		Vector2(300, 100), stacked, MAP_RECT, always_water)
	_check("bridge: stacked segment invalid",
		int(plan2.get("valid_count", -1)) < 10)
	_check("bridge: can_place rejects overlap",
		not BridgeDrag.can_place_bridge(
			[{"alive": true, "type": "house", "faction": "humans",
				"position": Vector2(60, 100)}],
			Vector2(60, 100), MAP_RECT, always_water))
	_check("bridge: can_place rejects off-map",
		not BridgeDrag.can_place_bridge([], Vector2(-100000, -100000),
			MAP_RECT, always_water))
	# Tap = one segment.
	var tap: Dictionary = BridgeDrag.plan_tap(Vector2(500, 100), [],
		MAP_RECT, always_water)
	_check("bridge: tap 1 segment",
		(tap.get("segments", []) as Array).size() == 1
		and int(tap.get("valid_count", 0)) == 1)
	# Commit: staged blueprints tagged with the run id.
	var w := _new_world(["humans"])
	_give(w, "humans")
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	var town: Dictionary = _found(w, "humans")
	var res: Dictionary = (w["bridge_drag"] as BridgeDrag).commit(bs, plan,
		"humans", int(town["id"]), {})
	_check("bridge: commit places 10",
		(res.get("placed", []) as Array).size() == 10)
	var staged := true
	var tagged := true
	for b: Dictionary in res.get("placed", []):
		if b.get("complete", true):
			staged = false
		if String(b.get("bridge_run_id", "")) == "":
			tagged = false
	_check("bridge: segments staged (incomplete)", staged)
	_check("bridge: segments tagged with run id", tagged)
	var first: Dictionary = (res.get("placed", []) as Array)[0]
	# bridge_at: only completed decks within 34px are walkable. The first
	# deck is still staged here, so nothing is walkable yet.
	_check("bridge: staged deck not walkable",
		(SimBuildings.bridge_at(gs.buildings, first.get("position",
			Vector2.ZERO)) as Dictionary).is_empty())
	_check("bridge: staged deck completes via tick",
		bs.tick_construction(first, 500.0, 1.0))
	_check("bridge: completed deck walkable",
		not (SimBuildings.bridge_at(gs.buildings, first.get("position",
			Vector2.ZERO)) as Dictionary).is_empty())
	_check("bridge: beyond 34px not walkable",
		(SimBuildings.bridge_at(gs.buildings,
			(first.get("position", Vector2.ZERO) as Vector2) + Vector2(100, 0))
			as Dictionary).is_empty())
	# Menu routing: bridge tool lives in the Roads tab (HTML buildCat).
	_check("bridge: category roads", SimBuildings.build_category("bridge") == "roads")
	_check("bridge: tool category roads",
		SimBuildings.build_category("bridge_drag") == "roads")
	_check("bridge: dock category roads",
		SimBuildings.build_category("fishing_dock") == "roads")
	_check("bridge: pier category roads",
		SimBuildings.build_category("pier") == "roads")
	_free_world(w)


## --- Fishing boats (naval units trained at the dock) ------------------------------------------

func _test_boats() -> void:
	# Dock trains exactly the two boat jobs (HTML trainOptions).
	_check("boat: dock trains boats",
		SimBuildings.train_options("fishing_dock") == ["fishing_boat", "war_ship"])
	_check("boat: barracks trains nothing here",
		SimBuildings.train_options("barracks").is_empty())
	# Specs: HTML COSTS + TRAIN_TIME + Unit-init multipliers.
	var fb: Dictionary = SimBuildings.boat_spec("fishing_boat")
	_check("boat: fishing cost",
		float((fb.get("train_cost", {}) as Dictionary).get("gold", 0)) == 60.0
		and float((fb.get("train_cost", {}) as Dictionary).get("wood", 0)) == 50.0)
	_check("boat: fishing train time", float(fb.get("train_time", 0)) == 4.5)
	_check("boat: fishing stat mults",
		float(fb.get("hp_mul", 0)) == 0.9 and float(fb.get("dmg_mul", 0)) == 0.3
		and float(fb.get("speed_mul", 0)) == 1.35)
	_check("boat: fishing haul rule",
		float(fb.get("fish_period", 0)) == 2.5
		and int(fb.get("fish_per_haul", 0)) == 10)
	var ws: Dictionary = SimBuildings.boat_spec("war_ship")
	_check("boat: war ship cost",
		float((ws.get("train_cost", {}) as Dictionary).get("gold", 0)) == 150.0
		and float((ws.get("train_cost", {}) as Dictionary).get("wood", 0)) == 110.0)
	_check("boat: war ship train time", float(ws.get("train_time", 0)) == 7.0)
	_check("boat: war ship stat mults",
		float(ws.get("hp_mul", 0)) == 2.6 and float(ws.get("dmg_mul", 0)) == 2.2
		and float(ws.get("range", 0)) == 220.0)
	_check("boat: non-boat empty", SimBuildings.boat_spec("worker").is_empty())
	# Dock + pier are waterfront buildings.
	_check("boat: dock requires water",
		SimBuildings.requires_water("fishing_dock"))
	_check("boat: pier requires water", SimBuildings.requires_water("pier"))
	_check("boat: house dry", not SimBuildings.requires_water("house"))
