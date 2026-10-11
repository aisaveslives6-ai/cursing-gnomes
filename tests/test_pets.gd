extends SceneTree
## Cursing Gnomes — pet cat tests (Jeremy 2026-10-07, NPC life deep pass).
##
## Stray cats spawn near towns; a stray "chooses" a nearby civilian and
## becomes their pet (follows, purrs: social/mood urge lift, eats 1
## food/day). Hunters/undead never target pets; wolves may. A dead pet
## grieves its owner; a dead owner releases the cat. The wild herd —
## pets included — round-trips through save/load.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_pets.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes pet-cat tests ===")
	_test_registry()
	_test_seed_cats()
	_test_adoption()
	_test_military_not_adopted()
	_test_one_pet_per_owner()
	_test_follow()
	_test_teleport()
	_test_purr()
	_test_no_starve()
	_test_owner_death_releases()
	_test_pet_death_grief()
	_test_daily_feeding()
	_test_nearest_wild_skips_pets()
	_test_save_roundtrip()
	_test_cat_art()
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


func _new_stack() -> Array:
	# Returns [gs, animals] with a wired SimAnimals.
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var a := SimAnimals.new(gs)
	a._rng.seed = 20261007
	gs.animals = a
	return [gs, a]


func _civ(gs: GameState, pos: Vector2, faction: String = "humans",
		job: String = "worker") -> Dictionary:
	return gs.add_unit({
		"faction": faction, "job": job, "alive": true,
		"position": pos, "name": "Testy",
		"urges": {"hunger": 60.0, "energy": 60.0, "hygiene": 60.0,
			"social": 50.0, "mood": 50.0, "bladder": 60.0},
	})


func _adopted_cat(gs: GameState, a, opos: Vector2, cpos: Vector2) -> Array:
	# Returns [cat, owner] with adoption forced through (ticks until pet).
	var owner := _civ(gs, opos)
	var cat: Dictionary = a.spawn_wild("cat", cpos)
	for i in 200:
		a.tick(0.1)
		if bool(cat.get("pet", false)):
			break
	return [cat, owner]


## ---- registry ---------------------------------------------------------------

func _test_registry() -> void:
	_check("cat registered", SimAnimals.ANIMAL_TYPES.has("cat"))
	var cat: Dictionary = SimAnimals.ANIMAL_TYPES["cat"]
	_check("cat label", String(cat["label"]) == "Cat")
	_check("cat fast", float(cat["speed_mul"]) > 1.5)
	_check("cat small", float(cat["size"]) < 8.0)
	_check("wolf hunts cats",
		"cat" in SimAnimals.PREDATORS.get("wolf", []))
	_check("cat names", SimAnimals.CAT_NAMES.size() >= 20)
	_check("prancey first", SimAnimals.CAT_NAMES[0] == "Prancey")
	_check("cat no yield", float(SimAnimals.DAILY_YIELD.get("cat", 0.0)) == 0.0)


## ---- seeding ----------------------------------------------------------------

func _test_seed_cats() -> void:
	var pack: Array = _new_stack()
	var a = pack[1]
	var centers := [Vector2(2000, 2000)]
	a.seed_wildlife(centers, func(_p: Vector2) -> bool: return false,
		4000.0, 4000.0)
	var cats := 0
	for an in a.wild:
		if String(an.get("type", "")) == "cat":
			cats += 1
			var d: float = (an.get("position", Vector2.ZERO) as Vector2) \
				.distance_to(centers[0])
			_check("cat near town", d >= SimAnimals.CAT_SPAWN_MIN_D - 1.0
				and d <= SimAnimals.CAT_SPAWN_MAX_D + 1.0)
	_check("cats seeded", cats == SimAnimals.CATS_PER_TOWN)


## ---- adoption ---------------------------------------------------------------

func _test_adoption() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(150, 100))
	var cat: Dictionary = res[0]
	var owner: Dictionary = res[1]
	_check("adopted", bool(cat.get("pet", false)))
	_check("owner id", int(cat.get("owner_id", -1)) == int(owner["id"]))
	_check("has name", String(cat.get("pet_name", "")) != "")
	_check("faction set", String(cat.get("faction", "")) == "humans")


func _test_military_not_adopted() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	# Only a soldier nearby: the cat must stay a stray.
	_civ(gs, Vector2(100, 100), "humans", "soldier")
	var cat: Dictionary = a.spawn_wild("cat", Vector2(150, 100))
	for i in 200:
		a.tick(0.1)
	_check("soldier not adopted", not bool(cat.get("pet", false)))


func _test_one_pet_per_owner() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(150, 100))
	var owner: Dictionary = res[1]
	_check("first adopted", bool((res[0] as Dictionary).get("pet", false)))
	# A second stray near the same lone gnome: no double adoption.
	var cat2: Dictionary = a.spawn_wild("cat", Vector2(160, 100))
	for i in 200:
		a.tick(0.1)
	_check("no second pet", not bool(cat2.get("pet", false)))
	_check("owner has pet", a._owner_has_pet(int(owner["id"])))


## ---- follow -----------------------------------------------------------------

func _test_follow() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(150, 100))
	var cat: Dictionary = res[0]
	var owner: Dictionary = res[1]
	_check("adopted for follow", bool(cat.get("pet", false)))
	# Walk the owner away; the cat should close the distance (it may
	# arrive and clear move_target — arrival is success, not failure).
	owner["position"] = Vector2(500, 100)
	var d0: float = (cat.get("position", Vector2.ZERO) as Vector2) \
		.distance_to(Vector2(500, 100))
	for i in 30:
		a.tick(0.1)
	var d1: float = (cat.get("position", Vector2.ZERO) as Vector2) \
		.distance_to(Vector2(500, 100))
	_check("follows owner", d1 < d0)
	_check("catches up", d1 <= SimAnimals.PET_FOLLOW_R + 5.0)


func _test_teleport() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(150, 100))
	var cat: Dictionary = res[0]
	var owner: Dictionary = res[1]
	# Owner across the map: the cat "finds" them instead of walking.
	owner["position"] = Vector2(3000, 3000)
	for i in 30:
		a.tick(0.1)
	var d: float = (cat.get("position", Vector2.ZERO) as Vector2) \
		.distance_to(Vector2(3000, 3000))
	_check("teleport catch-up", d < SimAnimals.PET_TELEPORT_R)


## ---- purr -------------------------------------------------------------------

func _test_purr() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(120, 100))
	var cat: Dictionary = res[0]
	var owner: Dictionary = res[1]
	var urges: Dictionary = owner["urges"]
	var s0 := float(urges["social"])
	var m0 := float(urges["mood"])
	# Keep them close for a few seconds of purring.
	for i in 50:
		owner["position"] = Vector2(100, 100)
		cat["position"] = Vector2(120, 100)
		cat.erase("move_target")
		a.tick(0.1)
	_check("social lifts", float(urges["social"]) > s0)
	_check("mood lifts", float(urges["mood"]) > m0)


## ---- hunger -----------------------------------------------------------------

func _test_no_starve() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(150, 100))
	var cat: Dictionary = res[0]
	cat["hunger"] = 0.0
	for i in 100:
		a.tick(0.5)
	_check("pet never starves", bool(cat.get("alive", false)))


func _test_daily_feeding() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(150, 100))
	var cat: Dictionary = res[0]
	gs.resources.add_resource("humans", "food", 50.0)
	var f0: float = gs.resources.get_ledger("humans").get("food", 0.0)
	cat["hunger"] = 10.0
	a._new_day([])
	_check("bowl filled", float(cat.get("hunger", 0.0)) == SimAnimals.FEED_HUNGER)
	var f1: float = gs.resources.get_ledger("humans").get("food", 0.0)
	_check("tithe taken",
		is_equal_approx(f0 - f1, SimAnimals.PET_FOOD_PER_DAY))
	# Broke faction: no deduction, no crash.
	gs.resources.spend("humans", {"food": f1})
	cat["hunger"] = 10.0
	a._new_day([])
	_check("broke no crash", float(cat.get("hunger", 0.0)) == 10.0)


## ---- loss -------------------------------------------------------------------

func _test_owner_death_releases() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(150, 100))
	var cat: Dictionary = res[0]
	var owner: Dictionary = res[1]
	owner["alive"] = false
	for i in 30:
		a.tick(0.1)
	_check("released to stray", not bool(cat.get("pet", false)))
	_check("keeps name", String(cat.get("pet_name", "")) != "")


func _test_pet_death_grief() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(150, 100))
	var cat: Dictionary = res[0]
	var owner: Dictionary = res[1]
	var urges: Dictionary = owner["urges"]
	urges["mood"] = 80.0
	a._kill_wild(cat, "slain")
	_check("grief hit",
		float(urges["mood"]) <= 80.0 - SimAnimals.PET_GRIEF_MOOD + 1.0)


## ---- hunters skip pets -------------------------------------------------------

func _test_nearest_wild_skips_pets() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(150, 100))
	var cat: Dictionary = res[0]
	var boar: Dictionary = a.spawn_wild("boar", Vector2(400, 100))
	var found: Dictionary = a.nearest_wild(Vector2(150, 100), 800.0)
	_check("pet skipped",
		int(found.get("id", -1)) != int(cat.get("id", -1)))
	_check("boar found", int(found.get("id", -1)) == int(boar.get("id", -1)))
	# Explicit opt-in still sees the pet (wolf-grid path uses its own scan).
	var found_all: Dictionary = a.nearest_wild(Vector2(150, 100), 800.0, false)
	_check("opt-in sees pet",
		int(found_all.get("id", -1)) == int(cat.get("id", -1)))


## ---- save/load ---------------------------------------------------------------

func _test_save_roundtrip() -> void:
	var pack: Array = _new_stack()
	var gs: GameState = pack[0]
	var a = pack[1]
	var res: Array = _adopted_cat(gs, a, Vector2(100, 100), Vector2(150, 100))
	var cat: Dictionary = res[0]
	var data: Dictionary = a.to_dict()
	_check("wild saved", (data.get("wild", []) as Array).size() >= 1)
	var a2 := SimAnimals.new(gs)
	a2.from_dict(data)
	_check("herd restored", a2.wild.size() == a.wild.size())
	var rc: Dictionary = {}
	for an in a2.wild:
		if int(an.get("id", -1)) == int(cat.get("id", -1)):
			rc = an
	_check("pet flag survives", bool(rc.get("pet", false)))
	_check("owner survives",
		int(rc.get("owner_id", -1)) == int(cat.get("owner_id", -1)))
	_check("name survives",
		String(rc.get("pet_name", "")) == String(cat.get("pet_name", "")))
	_check("id counter", a2._next_animal_id == a._next_animal_id)
	# Legacy save: no "animals" section -> empty herd, no crash.
	var a3 := SimAnimals.new(gs)
	a3.from_dict({})
	_check("legacy empty", a3.wild.is_empty())


## ---- art ---------------------------------------------------------------------

func _test_cat_art() -> void:
	_check("cat.png exists", ResourceLoader.exists("res://assets/art/animals/cat.png"))
