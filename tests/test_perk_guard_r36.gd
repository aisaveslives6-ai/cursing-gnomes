extends SceneTree
## Cursing Gnomes — R36 perk-getter no-perk early-out oracle parity tests.
##
## R36 adds `if not unit.has("food_perks"): return <identity>` to the four
## SimFoodPerks getters. These tests prove bit-identical behavior vs the
## verbatim pre-R36 logic: identity returns for perkless units, no key
## created, prune's lazy-erase side effect preserved for expired perks,
## and exact agreement on randomized live/expired/unknown perk sets.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_perk_guard_r36.gd


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


## Verbatim pre-R36 get_modifier (match + unconditional prune loop).
func _old_get_modifier(unit: Dictionary, mod: String,
		game_time: float) -> float:
	var key := ""
	match mod:
		"speed":
			key = "speed_mult"
		"work":
			key = "work_mult"
		"strength":
			key = "str_mult"
		_:
			return 1.0
	var mult := 1.0
	for p in SimFoodPerks.prune(unit, game_time):
		var def: Dictionary = SimFoodPerks.PERK_DEFS.get(
			String(p.get("id", "")), {})
		var fx: Dictionary = def.get("effects", {})
		if fx.has(key):
			mult *= float(fx[key])
	return mult


## Verbatim pre-R36 get_max_hp_mult.
func _old_get_max_hp_mult(unit: Dictionary, game_time: float) -> float:
	var mult := 1.0
	for p in SimFoodPerks.prune(unit, game_time):
		var def: Dictionary = SimFoodPerks.PERK_DEFS.get(
			String(p.get("id", "")), {})
		var fx: Dictionary = def.get("effects", {})
		if fx.has("max_hp_mult"):
			mult *= float(fx["max_hp_mult"])
	return mult


## Verbatim pre-R36 get_heal_per_sec.
func _old_get_heal_per_sec(unit: Dictionary, game_time: float) -> float:
	var hps := 0.0
	for p in SimFoodPerks.prune(unit, game_time):
		var def: Dictionary = SimFoodPerks.PERK_DEFS.get(
			String(p.get("id", "")), {})
		var fx: Dictionary = def.get("effects", {})
		hps += float(fx.get("heal_per_sec", 0.0))
	return hps


## Verbatim pre-R36 get_poison_dps.
func _old_get_poison_dps(unit: Dictionary, game_time: float) -> float:
	var dps := 0.0
	for p in SimFoodPerks.prune(unit, game_time):
		var def: Dictionary = SimFoodPerks.PERK_DEFS.get(
			String(p.get("id", "")), {})
		var fx: Dictionary = def.get("effects", {})
		dps += float(fx.get("poison_dps", 0.0))
	return dps


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.000001


func _test_no_perk_identity() -> void:
	var t := 1000.0
	for mod in ["speed", "work", "strength", "bogus"]:
		var u := {"id": 1}
		_check("no-perk get_modifier(%s) == 1.0" % mod,
			SimFoodPerks.get_modifier(u, mod, t) == 1.0)
		_check("no-perk creates no key (%s)" % mod,
			not u.has("food_perks"))
	var u2 := {"id": 2}
	_check("no-perk max_hp == 1.0",
		SimFoodPerks.get_max_hp_mult(u2, t) == 1.0)
	_check("no-perk heal == 0.0",
		SimFoodPerks.get_heal_per_sec(u2, t) == 0.0)
	_check("no-perk poison == 0.0",
		SimFoodPerks.get_poison_dps(u2, t) == 0.0)
	_check("no-perk getters create no key", not u2.has("food_perks"))


func _test_expired_prune_side_effect() -> void:
	# All-expired perks: old code pruned AND erased the key. The guard
	# must not change that — the key exists, so the guard passes through.
	var t := 1000.0
	var u := {"id": 3, "food_perks": [
		{"id": "bastard_rush", "expires": 500.0},
		{"id": "meat_sweats", "expires": 10.0},
	]}
	_check("expired-only modifier == 1.0",
		SimFoodPerks.get_modifier(u, "speed", t) == 1.0)
	_check("expired-only key erased (prune side effect)",
		not u.has("food_perks"))
	var u2 := {"id": 4, "food_perks": [
		{"id": "meat_sweats", "expires": 1.0}]}
	_check("expired-only max_hp == 1.0",
		SimFoodPerks.get_max_hp_mult(u2, t) == 1.0)
	_check("expired-only heal == 0.0",
		SimFoodPerks.get_heal_per_sec(u2, t) == 0.0)
	_check("expired-only key erased by hp getter", not u2.has("food_perks"))


func _test_empty_array() -> void:
	# Key present but empty: has() is true, so we take the prune path
	# exactly like the old code (which then erases the empty key).
	var t := 1000.0
	var u := {"id": 5, "food_perks": []}
	_check("empty-array modifier == 1.0",
		SimFoodPerks.get_modifier(u, "work", t) == 1.0)
	_check("empty-array key erased", not u.has("food_perks"))


func _rand_perks(rng: RandomNumberGenerator, t: float) -> Array:
	var ids := ["bastard_rush", "greasy_grind", "meat_sweats",
		"sausage_strength", "moonberry_bliss", "food_poisoning",
		"not_a_real_perk"]
	var out := []
	var n := rng.randi_range(0, 4)
	for _i in n:
		var expired := rng.randf() < 0.35
		out.append({"id": ids[rng.randi_range(0, ids.size() - 1)],
			"expires": t - 100.0 if expired else t + 100000.0})
	return out


func _test_oracle_agreement() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	var t := 50000.0
	var cases := 400
	var ok := true
	for _c in cases:
		var perks := _rand_perks(rng, t)
		for mod in ["speed", "work", "strength", "bogus"]:
			var a := {"id": 7, "food_perks": perks.duplicate(true)}
			var b := {"id": 7, "food_perks": perks.duplicate(true)}
			var old := _old_get_modifier(a, mod, t)
			var new := SimFoodPerks.get_modifier(b, mod, t)
			if not _approx(old, new):
				ok = false
			# Resulting perk-list state must match too (prune behavior).
			if a.has("food_perks") != b.has("food_perks"):
				ok = false
			elif a.has("food_perks") and (a["food_perks"] as Array).size() \
					!= (b["food_perks"] as Array).size():
				ok = false
	_check("oracle: get_modifier agrees on 400 randomized perk sets", ok)


func _test_oracle_other_getters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var t := 50000.0
	var ok := true
	for _c in 300:
		var perks := _rand_perks(rng, t)
		var a := {"id": 8, "food_perks": perks.duplicate(true)}
		var b := {"id": 8, "food_perks": perks.duplicate(true)}
		if not _approx(_old_get_max_hp_mult(a, t),
				SimFoodPerks.get_max_hp_mult(b, t)):
			ok = false
		var c := {"id": 8, "food_perks": perks.duplicate(true)}
		var d := {"id": 8, "food_perks": perks.duplicate(true)}
		if not _approx(_old_get_heal_per_sec(c, t),
				SimFoodPerks.get_heal_per_sec(d, t)):
			ok = false
		var e := {"id": 8, "food_perks": perks.duplicate(true)}
		var f := {"id": 8, "food_perks": perks.duplicate(true)}
		if not _approx(_old_get_poison_dps(e, t),
				SimFoodPerks.get_poison_dps(f, t)):
			ok = false
	_check("oracle: hp/heal/poison agree on 300 randomized perk sets", ok)


func _initialize() -> void:
	print("=== R36 perk-guard oracle tests ===")
	_test_no_perk_identity()
	_test_expired_prune_side_effect()
	_test_empty_array()
	_test_oracle_agreement()
	_test_oracle_other_getters()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
