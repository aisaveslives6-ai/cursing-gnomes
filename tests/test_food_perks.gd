extends SceneTree
## Cursing Gnomes — restaurant perk/dish system tests (Jeremy 2026-10-04).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_food_perks.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes food_perks tests ===")
	_test_dish_definitions()
	_test_building_definitions()
	_test_apply_and_modifier()
	_test_expiry()
	_test_refresh_not_stack()
	_test_instant_effects()
	_test_poison_and_horror()
	_test_prune_efficiency()
	_test_ui_helpers()
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


func _mk_unit() -> Dictionary:
	return {
		"id": 1, "alive": true, "faction": "gnomes",
		"hp": 100.0, "max_hp": 100.0,
		"urges": {"hunger": 50.0, "mood": 50.0, "energy": 50.0},
		"position": Vector2.ZERO, "speed": 36.0,
	}


func _test_dish_definitions() -> void:
	# All 10 perk restaurants have dish definitions.
	_check("dishes: 10 perk restaurants",
		SimFoodPerks.PERK_DISHES.size() == 10)
	_check("dishes: types list matches",
		SimFoodPerks.PERK_RESTAURANT_TYPES.size() == 10)
	for btype: String in SimFoodPerks.PERK_RESTAURANT_TYPES:
		_check("dish: is_perk_restaurant " + btype,
			SimFoodPerks.is_perk_restaurant(btype))
		var dish: Dictionary = SimFoodPerks.dish_for(btype)
		_check("dish: has perk_id " + btype, dish.has("perk_id"))
		_check("dish: perk def exists " + btype,
			SimFoodPerks.PERK_DEFS.has(String(dish.get("perk_id", ""))))
	# Original restaurant type is NOT a perk restaurant.
	_check("dishes: plain restaurant not perk",
		not SimFoodPerks.is_perk_restaurant("restaurant"))
	_check("dishes: unknown type not perk",
		not SimFoodPerks.is_perk_restaurant("house"))


func _test_building_definitions() -> void:
	# All 10 new buildings exist in the BUILDINGS table.
	for btype: String in SimFoodPerks.PERK_RESTAURANT_TYPES:
		_check("bld: defined " + btype, SimBuildings.BUILDINGS.has(btype))
		var b: Dictionary = SimBuildings.BUILDINGS.get(btype, {})
		_check("bld: has name " + btype, String(b.get("name", "")) != "")
		_check("bld: has costs " + btype, (b.get("costs", {}) as Dictionary).size() > 0)
	# Spot-check the funny names Jeremy asked for.
	_check("bld: Taco Bastard Drive-Thru name",
		String((SimBuildings.BUILDINGS.get("bastard_drivethru", {}) as Dictionary).get("name", "")) == "Taco Bastard Drive-Thru")
	_check("bld: Ogre Sausage name",
		String((SimBuildings.BUILDINGS.get("ogre_sausage_shop", {}) as Dictionary).get("name", "")) == "Ogre Sausage")
	_check("bld: Grave Snacks name",
		String((SimBuildings.BUILDINGS.get("grave_snacks", {}) as Dictionary).get("name", "")) == "Grave Snacks")


func _test_apply_and_modifier() -> void:
	var u := _mk_unit()
	# Salad bar: Rabbit Food Rush = 1.15x speed, 0% poison (deterministic).
	SimFoodPerks.apply_dish(u, "salad_bar", 1000.0)
	_check("apply: perk stored", u.has("food_perks"))
	_check("apply: exactly one perk",
		(u.get("food_perks", []) as Array).size() == 1)
	var spd: float = SimFoodPerks.get_modifier(u, "speed", 1000.0)
	_check("apply: speed mult 1.15", absf(spd - 1.15) < 0.001)
	# Strength unaffected by Rabbit Food Rush.
	_check("apply: strength mult 1.0",
		absf(SimFoodPerks.get_modifier(u, "strength", 1000.0) - 1.0) < 0.001)
	# Unknown modifier returns 1.0.
	_check("apply: unknown mod 1.0",
		absf(SimFoodPerks.get_modifier(u, "bogus", 1000.0) - 1.0) < 0.001)
	# Non-perk restaurant does nothing.
	var u2 := _mk_unit()
	SimFoodPerks.apply_dish(u2, "restaurant", 1000.0)
	_check("apply: plain restaurant no perks", not u2.has("food_perks"))
	SimFoodPerks.apply_dish(u2, "house", 1000.0)
	_check("apply: unknown btype no perks", not u2.has("food_perks"))


func _test_expiry() -> void:
	var u := _mk_unit()
	SimFoodPerks.apply_dish(u, "bastard_drivethru", 1000.0)
	var day: float = Config.DAY_LENGTH_SECONDS
	# Still active just before expiry.
	_check("expiry: active before",
		absf(SimFoodPerks.get_modifier(u, "speed", 1000.0 + day - 1.0) - 1.35) < 0.001)
	# Expired after duration.
	_check("expiry: gone after",
		absf(SimFoodPerks.get_modifier(u, "speed", 1000.0 + day + 1.0) - 1.0) < 0.001)
	# Pruned from the dict.
	_check("expiry: pruned", not u.has("food_perks"))
	_check("expiry: active_perks empty",
		SimFoodPerks.active_perks(u, 1000.0 + day + 1.0).is_empty())


func _test_refresh_not_stack() -> void:
	var u := _mk_unit()
	# Use salad_bar (0% poison) for determinism.
	SimFoodPerks.apply_dish(u, "salad_bar", 1000.0)
	# Eating again refreshes instead of stacking.
	SimFoodPerks.apply_dish(u, "salad_bar", 1500.0)
	var perks: Array = u.get("food_perks", [])
	var rush_count := 0
	for p in perks:
		if p is Dictionary and String(p.get("id", "")) == "rabbit_food_rush":
			rush_count += 1
	_check("refresh: no duplicate rush", rush_count == 1)
	# Multiplier still single (not 1.15^2).
	_check("refresh: speed still 1.15",
		absf(SimFoodPerks.get_modifier(u, "speed", 1500.0) - 1.15) < 0.01)


func _test_instant_effects() -> void:
	# Moonberry Tart: +30 mood instant.
	var u := _mk_unit()
	u["faction"] = "elves"
	SimFoodPerks.apply_dish(u, "moonberry_lounge", 1000.0)
	_check("instant: mood boosted",
		float((u.get("urges", {}) as Dictionary).get("mood", 0.0)) >= 79.9)
	# Dew Tea: +40 energy instant.
	var u2 := _mk_unit()
	u2["faction"] = "elves"
	SimFoodPerks.apply_dish(u2, "dewdrop_diner", 1000.0)
	_check("instant: energy boosted",
		float((u2.get("urges", {}) as Dictionary).get("energy", 0.0)) >= 89.9)
	# Mood clamps at 100.
	var u3 := _mk_unit()
	(u3["urges"] as Dictionary)["mood"] = 95.0
	u3["faction"] = "elves"
	SimFoodPerks.apply_dish(u3, "moonberry_lounge", 1000.0)
	_check("instant: mood clamps 100",
		float((u3.get("urges", {}) as Dictionary).get("mood", 0.0)) <= 100.0)


func _test_poison_and_horror() -> void:
	# Force poison by stubbing: apply the poison perk directly.
	var u := _mk_unit()
	SimFoodPerks._apply_perk(u, "food_poisoning", "test", 1000.0, Config.DAY_LENGTH_SECONDS)
	_check("poison: dps > 0",
		SimFoodPerks.get_poison_dps(u, 1000.0) > 0.0)
	_check("poison: speed penalty",
		SimFoodPerks.get_modifier(u, "speed", 1000.0) < 1.0)
	# Poison expires after half a day.
	_check("poison: expires",
		SimFoodPerks.get_poison_dps(u, 1000.0 + Config.DAY_LENGTH_SECONDS) <= 0.0)
	# Horror: living unit eating finger sandwiches.
	var u2 := _mk_unit()
	u2["faction"] = "humans"
	SimFoodPerks.apply_dish(u2, "grave_snacks", 1000.0)
	var has_horror := false
	for p in (u2.get("food_perks", []) as Array):
		if p is Dictionary and String(p.get("id", "")) == "horrified":
			has_horror = true
	_check("horror: living gets horrified", has_horror)
	_check("horror: mood dropped",
		float((u2.get("urges", {}) as Dictionary).get("mood", 60.0)) < 50.0)
	# Undead are NOT horrified.
	var u3 := _mk_unit()
	u3["faction"] = "undead"
	SimFoodPerks.apply_dish(u3, "grave_snacks", 1000.0)
	var undead_horror := false
	for p in (u3.get("food_perks", []) as Array):
		if p is Dictionary and String(p.get("id", "")) == "horrified":
			undead_horror = true
	_check("horror: undead immune", not undead_horror)


func _test_prune_efficiency() -> void:
	# Units without perks: prune is a cheap no-op.
	var u := _mk_unit()
	_check("prune: no perks key", SimFoodPerks.prune(u, 1000.0).is_empty())
	_check("prune: no key created", not u.has("food_perks"))
	_check("prune: modifiers 1.0 without perks",
		absf(SimFoodPerks.get_modifier(u, "speed", 1000.0) - 1.0) < 0.001)
	# Meat Sweats heal + max HP.
	var u2 := _mk_unit()
	SimFoodPerks._apply_perk(u2, "meat_sweats", "test", 1000.0, Config.DAY_LENGTH_SECONDS)
	_check("meat: heal per sec",
		SimFoodPerks.get_heal_per_sec(u2, 1000.0) > 0.0)
	_check("meat: max hp mult 1.2",
		absf(SimFoodPerks.get_max_hp_mult(u2, 1000.0) - 1.2) < 0.001)


func _test_ui_helpers() -> void:
	var u := _mk_unit()
	SimFoodPerks.apply_dish(u, "bastard_drivethru", 1000.0)
	var perks: Array = SimFoodPerks.active_perks(u, 1000.0)
	_check("ui: active_perks non-empty", not perks.is_empty())
	var first: Dictionary = perks[0]
	_check("ui: has name", String(first.get("name", "")) != "")
	_check("ui: has desc", String(first.get("desc", "")) != "")
	_check("ui: secs_left positive", float(first.get("secs_left", 0.0)) > 0.0)
	# Time formatting: no emoji, plain text.
	_check("ui: hours fmt", SimFoodPerks.format_time_left(7200.0) == "2.0h left")
	_check("ui: minutes fmt", SimFoodPerks.format_time_left(300.0) == "5m left")
	_check("ui: seconds fmt", SimFoodPerks.format_time_left(45.0) == "45s left")
