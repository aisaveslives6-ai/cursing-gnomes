extends SceneTree
## Cursing Gnomes — fishing engine tests (Jeremy 2026-10-06).
##
## Ports the dropped fix79 fisher engine: a fisher works the nearest
## stocked lake (gatherType 'fish'), casts every 1.1s for up to 8 fish,
## and the catch lands at their feet as a food pickup collected by the
## walk-over magnet. No rod = 25% catch via the tool supply flow.
## Lake stocks (80–200) respawn at 2.5/s and roundtrip through save/load.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_fishing.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes fishing tests ===")
	_test_assign_to_lake()
	_test_nearest_stocked_lake()
	_test_empty_lake_falls_back()
	_test_no_hydro_falls_back()
	_test_catch_spawns_food_pickup()
	_test_no_rod_quarter_catch()
	_test_rod_full_catch()
	_test_fished_out_goes_idle()
	_test_full_carry_hauls_home()
	_test_magnet_collects_food()
	_test_fish_regen()
	_test_fish_save_roundtrip()
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


## Fresh game + hydro with two lakes, fisher-ready.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = {
		"water_bodies": [
			{"kind": "lake", "pos": Vector2(500, 500), "radius": 100.0},
			{"kind": "lake", "pos": Vector2(1500, 1500), "radius": 120.0},
		],
		"tile_size": 32.0,
	}
	var combat := SimCombat.new(gs)
	var hydro := HydroSim.new(gs, combat)
	hydro.setup_bounds(Rect2(0, 0, 2000, 2000))
	gs.hydro = hydro
	var w := {
		"gs": gs,
		"buildings": SimBuildings.new(gs),
		"ai": WorkerAI.new(gs),
		"hydro": hydro,
	}
	gs.found_town("humans", "T", Vector2(300, 300))
	return w


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _new_fisher(w: Dictionary, pos: Vector2) -> Dictionary:
	return {
		"id": 7, "alive": true, "job": "fisher", "faction": "humans",
		"position": pos, "work_state": "idle", "work_site": -1,
		"carrying": {}, "carry_cap": 10.0,
	}


func _lakes(w: Dictionary) -> Array:
	return (w["hydro"] as HydroSim).bodies()


func _test_assign_to_lake() -> void:
	var w := _new_world()
	var u := _new_fisher(w, Vector2(100, 100))
	(w["ai"] as WorkerAI).tick_unit(u, w["buildings"], 1.0 / 60.0)
	_check("fishing: fisher heads to the lake", String(u["work_state"]) == "to_lake")
	_check("fishing: shore target set near lake",
		(u["work_target_pos"] as Vector2).distance_to(Vector2(500, 500)) < 120.0)
	_check("fishing: lake recorded", not (u.get("_lake", {}) as Dictionary).is_empty())
	_free_world(w)


func _test_nearest_stocked_lake() -> void:
	var w := _new_world()
	var lakes := _lakes(w)
	# Fish out the near lake — the fisher must skip it for the far one.
	(lakes[0] as Dictionary)["fish"] = 0.0
	var u := _new_fisher(w, Vector2(100, 100))
	(w["ai"] as WorkerAI).tick_unit(u, w["buildings"], 1.0 / 60.0)
	_check("fishing: skips empty lake",
		String(u["work_state"]) == "to_lake")
	_check("fishing: targets the stocked lake",
		((u["_lake"] as Dictionary).get("pos", Vector2.ZERO) as Vector2)
		== Vector2(1500, 1500))
	_free_world(w)


func _test_empty_lake_falls_back() -> void:
	var w := _new_world()
	var lakes := _lakes(w)
	for l in lakes:
		(l as Dictionary)["fish"] = 0.0
	var u := _new_fisher(w, Vector2(100, 100))
	(w["ai"] as WorkerAI).tick_unit(u, w["buildings"], 1.0 / 60.0)
	# No stocked lake: old behavior (farm fallback) preserved, not a stall.
	_check("fishing: empty lakes fall back, never to_lake",
		String(u["work_state"]) != "to_lake")
	_free_world(w)


func _test_no_hydro_falls_back() -> void:
	var w := _new_world()
	(w["gs"] as GameState).hydro = null
	var u := _new_fisher(w, Vector2(100, 100))
	(w["ai"] as WorkerAI).tick_unit(u, w["buildings"], 1.0 / 60.0)
	_check("fishing: null hydro falls back safely",
		String(u["work_state"]) != "to_lake")
	_free_world(w)


func _test_catch_spawns_food_pickup() -> void:
	# 2026-10-08 de-flake: same Stinky Gizmundo 2% roll as _test_no_rod_quarter_catch
	# (work.gd `_roll_gizmundo(randf())` replaces the haul with kind "gizmundo" /
	# amount 12.0 ~1 run in 50, failing the kind + amount checks below).
	# Fixed seed pins the draw (precedent: test_artillery_undead).
	seed(20261008)
	var w := _new_world()
	var lakes := _lakes(w)
	var lake: Dictionary = lakes[0]
	var before := float(lake.get("fish", 0.0))
	var u := _new_fisher(w, Vector2(500, 420))
	u["work_state"] = "fishing"
	u["_lake"] = lake
	u["_fish_timer"] = 99.0
	u["equipped_tool"] = "fishingrod"
	(w["ai"] as WorkerAI).tick_unit(u, w["buildings"], 1.5)
	var gs: GameState = w["gs"]
	_check("fishing: catch spawns a pickup", not gs.pickups.is_empty())
	var p: Dictionary = gs.pickups[gs.pickups.size() - 1]
	_check("fishing: pickup is food", String(p.get("kind", "")) == "food")
	_check("fishing: full catch with rod", float(p.get("amount", 0.0)) == 8.0)
	_check("fishing: lake stock depletes",
		float(lake.get("fish", 0.0)) == before - 8.0)
	_check("fishing: keeps fishing while stocked",
		String(u["work_state"]) == "fishing")
	_free_world(w)


func _test_no_rod_quarter_catch() -> void:
	# 2026-10-07 de-flake: the Stinky Gizmundo 2% roll (work.gd) fires on
	# randf() and replaces the haul ~1 run in 50, failing the amount check
	# below. Fixed seed pins the draw (precedent: test_artillery_undead).
	seed(20261007)
	var w := _new_world()
	var lake: Dictionary = _lakes(w)[0]
	var u := _new_fisher(w, Vector2(500, 420))
	u["work_state"] = "fishing"
	u["_lake"] = lake
	u["_fish_timer"] = 99.0
	# No rod equipped: 25% catch (8 -> 2). Bare test: petitions is null,
	# so the supply flow is a no-op and the fisher keeps casting.
	(w["ai"] as WorkerAI).tick_unit(u, w["buildings"], 1.5)
	var gs: GameState = w["gs"]
	_check("fishing: no rod yields a catch", not gs.pickups.is_empty())
	var p: Dictionary = gs.pickups[gs.pickups.size() - 1]
	_check("fishing: no rod = 25% catch", float(p.get("amount", 0.0)) == 2.0)
	_free_world(w)


func _test_rod_full_catch() -> void:
	# 2026-10-08 de-flake: same Stinky Gizmundo 2% roll (see
	# _test_catch_spawns_food_pickup) — a lucky draw would yield amount 12.0
	# instead of the expected 3.0. Fixed seed pins the draw.
	seed(20261008)
	var w := _new_world()
	var lake: Dictionary = _lakes(w)[0]
	(lake as Dictionary)["fish"] = 3.0  # small stock: min(8, stock)
	var u := _new_fisher(w, Vector2(500, 420))
	u["work_state"] = "fishing"
	u["_lake"] = lake
	u["_fish_timer"] = 99.0
	u["equipped_tool"] = "fishingrod"
	(w["ai"] as WorkerAI).tick_unit(u, w["buildings"], 1.5)
	var gs: GameState = w["gs"]
	var p: Dictionary = gs.pickups[gs.pickups.size() - 1]
	_check("fishing: catch clamped to remaining stock",
		float(p.get("amount", 0.0)) == 3.0)
	_check("fishing: fished-out lake idles",
		String(u["work_state"]) == "idle")
	_free_world(w)


func _test_fished_out_goes_idle() -> void:
	var w := _new_world()
	var lake: Dictionary = _lakes(w)[0]
	(lake as Dictionary)["fish"] = 0.0
	var u := _new_fisher(w, Vector2(500, 420))
	u["work_state"] = "fishing"
	u["_lake"] = lake
	(w["ai"] as WorkerAI).tick_unit(u, w["buildings"], 1.0 / 60.0)
	_check("fishing: empty lake idles immediately",
		String(u["work_state"]) == "idle")
	_free_world(w)


func _test_full_carry_hauls_home() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	gs.buildings.append({
		"id": 3, "type": "town_hall", "faction": "humans",
		"position": Vector2(300, 300), "alive": true, "complete": true,
	})
	var lake: Dictionary = _lakes(w)[0]
	var u := _new_fisher(w, Vector2(500, 420))
	u["work_state"] = "fishing"
	u["_lake"] = lake
	u["carrying"] = {"food": 10.0}
	(w["ai"] as WorkerAI).tick_unit(u, w["buildings"], 1.0 / 60.0)
	_check("fishing: full load heads to dropoff",
		String(u["work_state"]) == "to_dropoff")
	_free_world(w)


func _test_magnet_collects_food() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	gs.add_pickup({"kind": "food", "amount": 5.0, "position": Vector2(104, 100)})
	gs.add_pickup({"kind": "wood", "amount": 5.0, "position": Vector2(200, 100)})
	var u := _new_fisher(w, Vector2(100, 100))
	u["work_state"] = "fishing"
	u["_lake"] = (_lakes(w) as Array)[0]
	(w["ai"] as WorkerAI).tick_unit(u, w["buildings"], 1.0 / 60.0)
	var carrying: Dictionary = u.get("carrying", {})
	_check("fishing: magnet collects food pickup",
		float(carrying.get("food", 0.0)) == 5.0)
	_check("fishing: magnet still collects wood",
		float(carrying.get("wood", 0.0)) == 0.0)  # out of reach, untouched
	_free_world(w)


func _test_fish_regen() -> void:
	var w := _new_world()
	var hydro: HydroSim = w["hydro"]
	var lake: Dictionary = hydro.bodies()[0]
	var mx := float(lake.get("max_fish", 0.0))
	(lake as Dictionary)["fish"] = 10.0
	hydro.tick(4.0)
	_check("fishing: stocks respawn at 2.5/s",
		abs(float(lake.get("fish", 0.0)) - 20.0) < 0.01)
	(lake as Dictionary)["fish"] = mx - 1.0
	hydro.tick(60.0)
	_check("fishing: regen capped at max_fish",
		float(lake.get("fish", 0.0)) == mx)
	_free_world(w)


func _test_fish_save_roundtrip() -> void:
	var w := _new_world()
	var hydro: HydroSim = w["hydro"]
	var lake: Dictionary = hydro.bodies()[0]
	(lake as Dictionary)["fish"] = 42.0
	(lake as Dictionary)["max_fish"] = 150.0
	var saved := hydro.to_dict()
	(lake as Dictionary)["fish"] = 0.0
	hydro.from_dict(saved)
	_check("fishing: fish survives save/load",
		float(lake.get("fish", 0.0)) == 42.0)
	_check("fishing: max_fish survives save/load",
		float(lake.get("max_fish", 0.0)) == 150.0)
	_free_world(w)
