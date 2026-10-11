extends SceneTree
## Cursing Gnomes — staffed eatery income tests.
##
## Covers the AI-first phase economy AI checklist item "eatery income"
## (port of HTML fix79 eateryIncomeTick, verbatim economics):
##   - every ~33 sim-seconds, each completed, living, STAFFED eatery pays
##     its faction 3-6 gold — but only 07:00-22:00
##   - "staffed" = a living shopkeeper whose station record points at the
##     building (GuildHiring._holder_matches parity)
##   - restaurant + soul_cafe (undead faction-unique eatery) both earn;
##     restaurants are now on the JobDefs.WORKPLACES roster so the guild
##     master actually staffs them (HTML ROSTER57 parity)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_eatery_income.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes eatery income tests ===")
	_test_roster_covers_eateries()
	_test_open_hours()
	_test_staffed_pays()
	_test_unstaffed_pays_nothing()
	_test_incomplete_pays_nothing()
	_test_dead_shopkeeper_pays_nothing()
	_test_wrong_faction_pays_nothing()
	_test_night_pays_nothing()
	_test_soul_cafe_pays_undead()
	_test_payout_cadence()
	_test_two_payouts_accumulate()
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


## Fresh game + industry. setup() starts at midday (12:00, kitchens open).
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var industry := SimIndustry.new(gs)
	return {"gs": gs, "industry": industry}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _set_hour(w: Dictionary, hour: float) -> void:
	var gs: GameState = w["gs"]
	gs.game_time = hour / 24.0 * Config.DAY_LENGTH_SECONDS


func _eatery(w: Dictionary, btype: String, faction: String,
		complete: bool = true) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({
		"type": btype, "faction": faction, "town_id": -1,
		"position": Vector2(5000, 5000), "complete": complete,
		"progress": 1.0 if complete else 0.5,
		"alive": true, "hp": 450.0, "max_hp": 450.0,
	})


func _shopkeeper(w: Dictionary, faction: String, building_id: int,
		alive: bool = true) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_unit({
		"faction": faction, "job": "shopkeeper", "town_id": -1,
		"position": Vector2(5010, 5010), "alive": alive,
		"hp": 100.0, "max_hp": 100.0,
		"station": {"job": "shopkeeper", "building_id": building_id},
	})


func _gold(w: Dictionary, faction: String) -> float:
	return (w["gs"] as GameState).resources.get_amount(faction, "gold")


## --- roster -----------------------------------------------------------------

func _test_roster_covers_eateries() -> void:
	var shop_types: Array = []
	for e: Dictionary in JobDefs.WORKPLACES:
		if String(e.get("job", "")) == "shopkeeper":
			shop_types.append_array(e.get("types", []))
	_check("roster: shopkeeper covers restaurant", "restaurant" in shop_types)
	_check("roster: shopkeeper covers soul_cafe", "soul_cafe" in shop_types)


func _test_open_hours() -> void:
	_check("open hours: restaurant listed",
		JobDefs.OPEN_HOURS.has("restaurant"))
	_check("open hours: soul_cafe listed",
		JobDefs.OPEN_HOURS.has("soul_cafe"))


## --- payouts ----------------------------------------------------------------

func _test_staffed_pays() -> void:
	var w := _new_world()
	var b := _eatery(w, "restaurant", "humans")
	_shopkeeper(w, "humans", int(b["id"]))
	var before := _gold(w, "humans")
	(w["industry"] as SimIndustry).tick(34.0)
	var earned := _gold(w, "humans") - before
	_check("staffed: pays 3-6 gold", earned >= 3.0 and earned <= 6.0)
	_free_world(w)


func _test_unstaffed_pays_nothing() -> void:
	var w := _new_world()
	_eatery(w, "restaurant", "humans")
	var before := _gold(w, "humans")
	(w["industry"] as SimIndustry).tick(34.0)
	_check("unstaffed: pays nothing", _gold(w, "humans") == before)
	_free_world(w)


func _test_incomplete_pays_nothing() -> void:
	var w := _new_world()
	var b := _eatery(w, "restaurant", "humans", false)
	_shopkeeper(w, "humans", int(b["id"]))
	var before := _gold(w, "humans")
	(w["industry"] as SimIndustry).tick(34.0)
	_check("incomplete: pays nothing", _gold(w, "humans") == before)
	_free_world(w)


func _test_dead_shopkeeper_pays_nothing() -> void:
	var w := _new_world()
	var b := _eatery(w, "restaurant", "humans")
	_shopkeeper(w, "humans", int(b["id"]), false)
	var before := _gold(w, "humans")
	(w["industry"] as SimIndustry).tick(34.0)
	_check("dead shopkeeper: pays nothing", _gold(w, "humans") == before)
	_free_world(w)


func _test_wrong_faction_pays_nothing() -> void:
	var w := _new_world()
	var b := _eatery(w, "restaurant", "humans")
	_shopkeeper(w, "ogres", int(b["id"]))
	var before := _gold(w, "humans")
	(w["industry"] as SimIndustry).tick(34.0)
	_check("wrong faction staff: pays nothing", _gold(w, "humans") == before)
	_free_world(w)


func _test_night_pays_nothing() -> void:
	var w := _new_world()
	_set_hour(w, 23.0)
	var b := _eatery(w, "restaurant", "humans")
	_shopkeeper(w, "humans", int(b["id"]))
	var before := _gold(w, "humans")
	(w["industry"] as SimIndustry).tick(34.0)
	_check("night (23:00): pays nothing", _gold(w, "humans") == before)
	_free_world(w)


func _test_soul_cafe_pays_undead() -> void:
	var w := _new_world()
	var b := _eatery(w, "soul_cafe", "undead")
	_shopkeeper(w, "undead", int(b["id"]))
	var before := _gold(w, "undead")
	(w["industry"] as SimIndustry).tick(34.0)
	var earned := _gold(w, "undead") - before
	_check("soul_cafe: pays undead 3-6 gold", earned >= 3.0 and earned <= 6.0)
	_free_world(w)


func _test_payout_cadence() -> void:
	var w := _new_world()
	var b := _eatery(w, "restaurant", "humans")
	_shopkeeper(w, "humans", int(b["id"]))
	var before := _gold(w, "humans")
	(w["industry"] as SimIndustry).tick(10.0)
	_check("cadence: no payout before 33s", _gold(w, "humans") == before)
	(w["industry"] as SimIndustry).tick(24.0)
	var earned := _gold(w, "humans") - before
	_check("cadence: payout fires at 33s", earned >= 3.0 and earned <= 6.0)
	_free_world(w)


func _test_two_payouts_accumulate() -> void:
	var w := _new_world()
	var b := _eatery(w, "restaurant", "humans")
	_shopkeeper(w, "humans", int(b["id"]))
	var before := _gold(w, "humans")
	(w["industry"] as SimIndustry).tick(34.0)
	(w["industry"] as SimIndustry).tick(34.0)
	var earned := _gold(w, "humans") - before
	_check("two payouts: 6-12 gold total", earned >= 6.0 and earned <= 12.0)
	_free_world(w)
