extends SceneTree
## Cursing Gnomes — R35 water-check elision oracle parity tests.
##
## R35 hoists WaterNav.is_water_at's inputs in SimPathfinder._build_nav
## (_pf_wterr/_pf_wsx/_pf_wsy/_pf_wtile/_pf_has_water) and uses the
## zero-dict-get WaterNav.is_water_at_fast in _steer + the move_routed
## arrival branch. These tests prove bit-identical behavior vs the old
## dict-get path: agreement of is_water_at_fast with is_water_at over
## water/dry/empty/degenerate maps and out-of-bounds positions, correct
## _pf_has_water, oracle agreement of the new gate expression with the
## verbatim old expression, and movement behavior (land units never
## enter water; swimming flags match).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_r35_water_elision.gd


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


func _water_map() -> Dictionary:
	# 16x16, tile 32; a 4x4 water blob (TILE_WATER=1) in the middle.
	var n := 16
	var terrain := PackedByteArray()
	terrain.resize(n * n)
	var levels := PackedByteArray()
	levels.resize(n * n)
	for i in n * n:
		levels[i] = 1
	for ty in range(6, 10):
		for tx in range(6, 10):
			terrain[ty * n + tx] = 1
	return {"terrain": terrain, "levels": levels,
		"size_tiles": Vector2i(n, n), "tile_size": 32}


func _dry_map() -> Dictionary:
	var n := 16
	var terrain := PackedByteArray()
	terrain.resize(n * n)
	var levels := PackedByteArray()
	levels.resize(n * n)
	for i in n * n:
		levels[i] = 1
	return {"terrain": terrain, "levels": levels,
		"size_tiles": Vector2i(n, n), "tile_size": 32}


func _new_pf(map_data: Dictionary) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = map_data
	var pf := SimPathfinder.new(gs)
	pf.unlimited_budget = true
	gs.set("pathfinder", pf)
	return {"gs": gs, "pf": pf}


func _free(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _initialize() -> void:
	print("=== R35 water elision tests ===")
	_test_fast_agrees_water_map()
	_test_fast_agrees_dry_map()
	_test_fast_degenerate()
	_test_has_water_flag()
	_test_gate_oracle()
	_test_swimming_oracle()
	_test_land_unit_never_enters_water()
	_test_boat_unit_may_enter_water()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## Verbatim OLD expressions (pre-R35) used as oracles below.
func _old_safety_gate(unit: Dictionary, map_data: Dictionary,
		stepped: Vector2) -> bool:
	return WaterNav.unit_avoids_water(unit) \
		and WaterNav.is_water_at(map_data, stepped)


func _old_swimming(map_data: Dictionary, stepped: Vector2) -> bool:
	return WaterNav.is_water_at(map_data, stepped)


func _new_safety_gate(pf: SimPathfinder, unit: Dictionary,
		stepped: Vector2) -> bool:
	return pf.get("_pf_has_water") and WaterNav.unit_avoids_water(unit) \
		and WaterNav.is_water_at_fast(pf.get("_pf_wterr"),
			pf.get("_pf_wsx"), pf.get("_pf_wsy"), pf.get("_pf_wtile"),
			stepped)


func _new_swimming(pf: SimPathfinder, stepped: Vector2) -> bool:
	return pf.get("_pf_has_water") and WaterNav.is_water_at_fast(
		pf.get("_pf_wterr"), pf.get("_pf_wsx"), pf.get("_pf_wsy"),
		pf.get("_pf_wtile"), stepped)


func _test_fast_agrees_water_map() -> void:
	var m := _water_map()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261006
	var agree := true
	for i in 400:
		# In-bounds, on water blob edges, and out-of-bounds probes.
		var p := Vector2(rng.randf_range(-64.0, 576.0),
			rng.randf_range(-64.0, 576.0))
		var a: bool = WaterNav.is_water_at(m, p)
		var b: bool = WaterNav.is_water_at_fast(m["terrain"],
			16, 16, 32.0, p)
		if a != b:
			agree = false
			print("    disagree at ", p, ": old=", a, " new=", b)
			break
	_check("fast agrees with dict path on water map (400 probes)", agree)


func _test_fast_agrees_dry_map() -> void:
	var m := _dry_map()
	var all_false := true
	for y in range(0, 512, 32):
		for x in range(0, 512, 32):
			var p := Vector2(x + 3.0, y + 7.0)
			if WaterNav.is_water_at_fast(m["terrain"], 16, 16, 32.0, p):
				all_false = false
	_check("fast all-false on dry map", all_false)


func _test_fast_degenerate() -> void:
	var m := _water_map()
	# Empty terrain -> false (matches dict path).
	_check("fast empty terrain false",
		not WaterNav.is_water_at_fast(PackedByteArray(), 16, 16, 32.0,
			Vector2(100, 100)))
	_check("dict empty terrain false",
		not WaterNav.is_water_at({"terrain": PackedByteArray(),
			"size_tiles": Vector2i(16, 16), "tile_size": 32}, Vector2(100, 100)))
	# Missing keys in dict path -> defaults (128,128)/32.0; fast with the
	# same defaults agrees.
	var bare := {"terrain": m["terrain"]}
	var agree := true
	for p in [Vector2(100, 100), Vector2(220, 220), Vector2(-40, -40),
			Vector2(5000, 5000)]:
		if WaterNav.is_water_at(bare, p) \
				!= WaterNav.is_water_at_fast(m["terrain"], 128, 128, 32.0, p):
			agree = false
	_check("fast agrees with dict defaults on keyless map", agree)
	# Non-positive tile -> false both ways.
	_check("fast tile<=0 false",
		not WaterNav.is_water_at_fast(m["terrain"], 16, 16, 0.0,
			Vector2(220, 220)))
	_check("dict tile<=0 false",
		not WaterNav.is_water_at({"terrain": m["terrain"],
			"size_tiles": Vector2i(16, 16), "tile_size": 0}, Vector2(220, 220)))
	# Far out-of-bounds both false.
	_check("fast far OOB false",
		not WaterNav.is_water_at_fast(m["terrain"], 16, 16, 32.0,
			Vector2(1e6, -1e6)))


func _test_has_water_flag() -> void:
	var w1 := _new_pf(_water_map())
	var pf1: SimPathfinder = w1["pf"]
	pf1.call("_ensure_nav")
	_check("has_water true on water map", bool(pf1.get("_pf_has_water")))
	_free(w1)
	var w2 := _new_pf(_dry_map())
	var pf2: SimPathfinder = w2["pf"]
	pf2.call("_ensure_nav")
	_check("has_water false on dry map", not bool(pf2.get("_pf_has_water")))
	_free(w2)
	var w3 := _new_pf({})
	var pf3: SimPathfinder = w3["pf"]
	pf3.call("_ensure_nav")
	_check("has_water false on empty map", not bool(pf3.get("_pf_has_water")))
	_free(w3)


func _test_gate_oracle() -> void:
	# New gate expression == verbatim old expression, water + dry maps,
	# land/boat/fleeing units, seeded random steps.
	var maps := [_water_map(), _dry_map()]
	var map_names := ["water", "dry"]
	for mi_i in maps.size():
		var mi: Dictionary = maps[mi_i]
		var w := _new_pf(mi)
		var pf: SimPathfinder = w["pf"]
		pf.call("_ensure_nav")
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var agree := true
		for i in 300:
			var job := "worker"
			var r := rng.randf()
			if r < 0.2:
				job = "fishing_boat"
			var fleeing := rng.randf() < 0.2
			var unit := {"job": job, "fleeing": fleeing}
			var stepped := Vector2(rng.randf_range(-64.0, 576.0),
				rng.randf_range(-64.0, 576.0))
			var a: bool = _old_safety_gate(unit, mi, stepped)
			var b: bool = _new_safety_gate(pf, unit, stepped)
			if a != b:
				agree = false
				print("    gate disagree: job=", job, " flee=", fleeing,
					" at ", stepped, " old=", a, " new=", b)
				break
		_check("gate oracle agrees (%s)" % map_names[mi_i], agree)
		_free(w)


func _test_swimming_oracle() -> void:
	var maps := [_water_map(), _dry_map()]
	var map_names := ["water", "dry"]
	for mi_i in maps.size():
		var mi: Dictionary = maps[mi_i]
		var w := _new_pf(mi)
		var pf: SimPathfinder = w["pf"]
		pf.call("_ensure_nav")
		var rng := RandomNumberGenerator.new()
		rng.seed = 777
		var agree := true
		for i in 300:
			var p := Vector2(rng.randf_range(-64.0, 576.0),
				rng.randf_range(-64.0, 576.0))
			if _old_swimming(mi, p) != _new_swimming(pf, p):
				agree = false
				break
		_check("swimming oracle agrees (%s)" % map_names[mi_i], agree)
		_free(w)


func _test_land_unit_never_enters_water() -> void:
	var w := _new_pf(_water_map())
	var gs: GameState = w["gs"]
	# Walk straight across the water blob; the safety net must slide
	# along the shore, never stepping into water.
	var unit := {"id": 1, "alive": true, "job": "worker",
		"position": Vector2(64, 240), "speed": 60.0, "faction": "humans"}
	var target := Vector2(448, 240)  # straight through the blob
	var entered := false
	for k in 600:
		WorkerAI.move_unit(gs, unit, target, 1.0 / 60.0)
		var p: Vector2 = unit["position"]
		if WaterNav.is_water_at(gs.map_data, p):
			entered = true
			break
	_check("land unit never steps into water", not entered)
	_check("swimming flag matches water map",
		bool(unit.get("swimming", false)) \
			== WaterNav.is_water_at(gs.map_data, unit["position"]))
	_free(w)


func _test_boat_unit_may_enter_water() -> void:
	var w := _new_pf(_water_map())
	var gs: GameState = w["gs"]
	var unit := {"id": 2, "alive": true, "job": "fishing_boat",
		"position": Vector2(64, 240), "speed": 60.0, "faction": "humans"}
	var target := Vector2(240, 240)  # into the blob
	var got_wet := false
	for k in 600:
		WorkerAI.move_unit(gs, unit, target, 1.0 / 60.0)
		if WaterNav.is_water_at(gs.map_data, unit["position"]):
			got_wet = true
			break
	_check("boat unit may enter water", got_wet)
	_free(w)
