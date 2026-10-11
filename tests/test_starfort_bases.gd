extends SceneTree
## Cursing Gnomes — StarFortBases tick-system tests.
##
## StarFort (plan + commit) existed with no caller: the AI scattered
## barracks/camps individually around towns, violating Jeremy's
## 2026-09-26 star-fort rule. StarFortBases is the call site (BorderWalls
## pattern): one auto-committed star fort per AI town once it holds a real
## military presence; the player race is never auto-built for.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_starfort_bases.gd

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


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
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0, "water_bodies": []}
	return {
		"gs": gs,
		"bases": StarFortBases.new(gs),
		"buildings": SimBuildings.new(gs),
		"wall_drag": WallDrag.new(),
	}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _give(w: Dictionary, faction: String, amount: float = 100000.0) -> void:
	var gs: GameState = w["gs"]
	for res: String in Config.RESOURCES:
		gs.resources.add_resource(faction, res, amount, true)


## Direct-cost-free building (bypasses treasury so affordability tests
## control resources exactly).
func _add(w: Dictionary, faction: String, btype: String, town_id: int,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	var b: Dictionary = gs.add_building({
		"type": btype, "faction": faction, "town_id": town_id,
		"position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 400.0, "max_hp": 400.0,
	})
	return b


func _town(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	var town: Dictionary = gs.found_town(faction, "T", pos)
	var hall: Dictionary = _add(w, faction, "town_hall", int(town["id"]), pos)
	return {"town": town, "hall": hall}


func _fort_buildings(gs: GameState, faction: String) -> Array:
	var out: Array = []
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == faction \
				and String(b.get("fort_plan", "")) == "star":
			out.append(b)
	return out


func _tick(w: Dictionary, faction: String, is_player: bool) -> void:
	(w["bases"] as StarFortBases).tick(faction, is_player,
		w["buildings"], w["wall_drag"])


func _initialize() -> void:
	_test_ai_builds_fort()
	_test_player_never_auto_built()
	_test_no_military_no_fort()
	_test_no_duplicate_fort()
	_test_broke_no_fort()
	_test_avoids_water()
	_test_save_load_roundtrip()
	_test_cooldown_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("FAILURES: ", _failures)
	quit(1 if _failed > 0 else 0)


## --- tests ------------------------------------------------------------------


func _test_ai_builds_fort() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var gs: GameState = w["gs"]
	var t := _town(w, "gnomes", Vector2(2000, 2000))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(2100, 2050))
	_add(w, "gnomes", "cannon_foundry", int(t["town"]["id"]), Vector2(1900, 1950))
	_tick(w, "gnomes", false)
	var made: Array = _fort_buildings(gs, "gnomes")
	_check("ai: fort committed (walls+towers+slots)", made.size() >= 14)
	var towers := 0
	var walls := 0
	var slots := 0
	for b: Dictionary in made:
		match String(b.get("type", "")):
			"guard_tower":
				towers += 1
			"wall":
				walls += 1
			_:
				slots += 1
	_check("ai: 5 corner guard towers", towers == 5)
	_check("ai: wall ring raised", walls >= 12)
	_check("ai: 9 base buildings inside", slots == 9)
	# Recorded against the hall.
	_check("ai: fort recorded for the hall",
		(w["bases"] as StarFortBases).forts.has(int(t["hall"]["id"])))
	# The fort stands off the town: center ~850px from the hall.
	var rec: Dictionary = (w["bases"] as StarFortBases).forts[int(t["hall"]["id"])]
	var c := (rec.get("center", Vector2.ZERO) as Vector2)
	_check("ai: fort pushed out from the hall",
		c.distance_to(Vector2(2000, 2000)) > 600.0)
	# Military district zone painted at the fort.
	_check("ai: military zone painted",
		gs.zoning.zone_at(c, "gnomes") == SimZoning.MILITARY)
	_free_world(w)


func _test_player_never_auto_built() -> void:
	var w := _new_world(["humans"])
	_give(w, "humans")
	var t := _town(w, "humans", Vector2(2000, 2000))
	_add(w, "humans", "barracks", int(t["town"]["id"]), Vector2(2100, 2050))
	_add(w, "humans", "barracks", int(t["town"]["id"]), Vector2(1900, 1950))
	_tick(w, "humans", true)
	_check("player: never auto-built",
		_fort_buildings(w["gs"], "humans").is_empty())
	_check("player: no fort recorded",
		(w["bases"] as StarFortBases).forts.is_empty())
	_free_world(w)


func _test_no_military_no_fort() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	_town(w, "gnomes", Vector2(2000, 2000))
	_tick(w, "gnomes", false)
	_check("no military: no fort",
		_fort_buildings(w["gs"], "gnomes").is_empty())
	# One military building is below the threshold.
	_free_world(w)
	w = _new_world(["gnomes"])
	_give(w, "gnomes")
	var t := _town(w, "gnomes", Vector2(2000, 2000))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(2100, 2050))
	(w["bases"] as StarFortBases).cooldowns.clear()
	_tick(w, "gnomes", false)
	_check("one barracks: still no fort",
		_fort_buildings(w["gs"], "gnomes").is_empty())
	_free_world(w)


func _test_no_duplicate_fort() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var gs: GameState = w["gs"]
	var t := _town(w, "gnomes", Vector2(2000, 2000))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(2100, 2050))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(1900, 1950))
	var bases: StarFortBases = w["bases"]
	_tick(w, "gnomes", false)
	var n1 := _fort_buildings(gs, "gnomes").size()
	bases.cooldowns.clear()
	_tick(w, "gnomes", false)
	var n2 := _fort_buildings(gs, "gnomes").size()
	_check("dup: second tick builds nothing new", n1 == n2 and n1 > 0)
	_check("dup: one fort recorded", bases.forts.size() == 1)
	_free_world(w)


func _test_broke_no_fort() -> void:
	var w := _new_world(["gnomes"])
	# No _give: treasury is empty after setup.
	var t := _town(w, "gnomes", Vector2(2000, 2000))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(2100, 2050))
	_add(w, "gnomes", "cannon_foundry", int(t["town"]["id"]), Vector2(1900, 1950))
	_tick(w, "gnomes", false)
	_check("broke: no fort committed",
		_fort_buildings(w["gs"], "gnomes").is_empty())
	_check("broke: no fort recorded",
		(w["bases"] as StarFortBases).forts.is_empty())
	_free_world(w)


func _test_avoids_water() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var gs: GameState = w["gs"]
	var t := _town(w, "gnomes", Vector2(2000, 2000))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(2100, 2050))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(1900, 1950))
	# Lake covering the due-east try (spot would be (2850, 2000)).
	var lake_pos := Vector2(2850, 2000)
	gs.map_data["water_bodies"] = [{
		"kind": "lake", "pos": lake_pos, "radius": 300.0}]
	_tick(w, "gnomes", false)
	var bases: StarFortBases = w["bases"]
	_check("water: fort still built elsewhere", bases.forts.size() == 1)
	var rec: Dictionary = bases.forts[int(t["hall"]["id"])]
	var c := (rec.get("center", Vector2.ZERO) as Vector2)
	_check("water: fort center clear of the lake",
		c.distance_to(lake_pos) > 300.0 + StarFort.DEFAULT_RADIUS)
	_free_world(w)


func _test_save_load_roundtrip() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var gs: GameState = w["gs"]
	var t := _town(w, "gnomes", Vector2(2000, 2000))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(2100, 2050))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(1900, 1950))
	var bases: StarFortBases = w["bases"]
	_tick(w, "gnomes", false)
	var d: Dictionary = bases.to_dict()
	var loaded := StarFortBases.new(gs)
	loaded.from_dict(d)
	_check("save: forts preserved", loaded.forts.size() == 1)
	_check("save: cooldowns preserved",
		loaded.cooldowns.get("gnomes", 0.0) == bases.cooldowns["gnomes"])
	var rec: Dictionary = loaded.forts[int(t["hall"]["id"])]
	_check("save: center decoded as Vector2", rec.get("center") is Vector2)
	# Encoded form (as the save system stores it) also decodes.
	var raw: Dictionary = SaveSystem._encode_value(d)
	var loaded2 := StarFortBases.new(gs)
	loaded2.from_dict(SaveSystem._decode_value(raw))
	_check("save: encoded form decodes", loaded2.forts.size() == 1)
	_free_world(w)


func _test_cooldown_gates() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var t := _town(w, "gnomes", Vector2(2000, 2000))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(2100, 2050))
	_add(w, "gnomes", "barracks", int(t["town"]["id"]), Vector2(1900, 1950))
	var bases: StarFortBases = w["bases"]
	bases.tick("gnomes", false, w["buildings"], w["wall_drag"])
	var first_cd := float(bases.cooldowns.get("gnomes", 0.0))
	_check("cooldown: set after tick", first_cd > float(w["gs"].game_time))
	_free_world(w)
