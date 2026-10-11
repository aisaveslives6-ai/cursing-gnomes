extends SceneTree
## Cursing Gnomes — Cliffs Update headless tests.
##
## Ports of the HTML's cliff mechanics (from fix79/index.html):
##   cgLevelForElev81  — elevation -> discrete level 0..6
##   cgCliffBlocked    — |level diff| > 1 blocks movement
##   cgHighGroundMul83 — +15% damage/level downhill, capped +45%
##   cgHillShade82     — higher ground reads lighter
##   CLIFFS83          — slope-aware movement costs
##   CLIFFDETECT       — fleeing units slide along cliff edges
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_cliffs.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes cliffs tests ===")
	_test_level_formula()
	_test_hill_shade()
	_test_high_ground_mult()
	_test_cliff_blocked()
	_test_try_step_slide()
	_test_empty_map_data()
	_test_melee_high_ground_damage()
	_test_generated_levels()
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


## Synthetic 8x8 level grid. `high` tiles form a sheer wall at column 4.
func _fake_map(wall_level: int = 3) -> Dictionary:
	var levels := PackedByteArray()
	levels.resize(64)
	for i in 64:
		levels[i] = 1
	for y in 8:
		levels[y * 8 + 4] = wall_level
	return {"levels": levels, "size_tiles": Vector2i(8, 8), "tile_size": 32}


func _test_level_formula() -> void:
	# HTML's cgLevelForElev81, ported exactly.
	_check("water below 0.30 -> 0", Cliffs.level_for_elev(0.2) == 0)
	_check("0.29 -> 0", Cliffs.level_for_elev(0.29) == 0)
	_check("0.30 -> 1", Cliffs.level_for_elev(0.30) == 1)
	_check("0.39 -> 1", Cliffs.level_for_elev(0.39) == 1)
	_check("0.40 -> 2", Cliffs.level_for_elev(0.40) == 2)
	_check("0.55 -> 3", Cliffs.level_for_elev(0.55) == 3)
	_check("0.85 -> 6", Cliffs.level_for_elev(0.85) == 6)
	_check("1.50 clamps to 6", Cliffs.level_for_elev(1.5) == 6)
	_check("negative -> 0", Cliffs.level_for_elev(-0.5) == 0)


func _test_hill_shade() -> void:
	# HTML's cgHillShade82: 1 + (L-1) * 0.045 for L > 1.
	_check("L1 -> 1.0", Cliffs.hill_shade_mult(1) == 1.0)
	_check("L0 -> 1.0", Cliffs.hill_shade_mult(0) == 1.0)
	_check("L2 -> 1.045", absf(Cliffs.hill_shade_mult(2) - 1.045) < 0.0001)
	_check("L6 -> 1.225", absf(Cliffs.hill_shade_mult(6) - 1.225) < 0.0001)


func _test_high_ground_mult() -> void:
	# HTML's cgHighGroundMul83: +15%/level downhill, capped at 3 (+45%).
	var md := _fake_map(4)  # wall column is L4, rest L1
	var hi := Vector2(4 * 32 + 16, 16)  # on the wall (L4)
	var lo := Vector2(16, 16)           # lowland (L1)
	_check("3 levels down -> 1.45",
		absf(Cliffs.high_ground_mult(md, hi, lo) - 1.45) < 0.0001)
	var md2 := _fake_map(2)
	var hi2 := Vector2(4 * 32 + 16, 16)
	_check("1 level down -> 1.15",
		absf(Cliffs.high_ground_mult(md2, hi2, lo) - 1.15) < 0.0001)
	_check("uphill -> 1.0",
		Cliffs.high_ground_mult(md, lo, hi) == 1.0)
	_check("flat -> 1.0",
		Cliffs.high_ground_mult(md, lo, Vector2(48, 16)) == 1.0)


func _test_cliff_blocked() -> void:
	# HTML's cgCliffBlocked: |dL| > 1 is a sheer cliff.
	var md := _fake_map(3)  # wall L3 vs L1 -> dL = 2
	var a := Vector2(3 * 32 + 16, 16)  # L1
	var b := Vector2(4 * 32 + 16, 16)  # L3
	_check("climb 2 levels blocked", Cliffs.cliff_blocked(md, a, b))
	_check("drop 2 levels blocked", Cliffs.cliff_blocked(md, b, a))
	var md1 := _fake_map(2)  # wall L2 vs L1 -> dL = 1
	var b1 := Vector2(4 * 32 + 16, 16)
	_check("climb 1 level allowed", not Cliffs.cliff_blocked(md1, a, b1))
	_check("drop 1 level allowed", not Cliffs.cliff_blocked(md1, b1, a))
	_check("flat allowed", not Cliffs.cliff_blocked(md1, a, Vector2(48, 16)))


func _test_try_step_slide() -> void:
	# HTML's CLIFFDETECT: slide along the edge (x-only, then y-only).
	var md := _fake_map(3)
	var pos := Vector2(3 * 32 + 16, 3 * 32 + 16)  # L1, left of wall
	# Straight into the wall: x-only blocked, y-only is a no-op here
	# (step.y == 0), so the unit holds position.
	var stuck: Vector2 = Cliffs.try_step(md, pos, Vector2(40, 0))
	_check("sheer wall holds position", stuck == pos)
	# Diagonal into the wall: x-only blocked, y-only slides along it.
	var slid: Vector2 = Cliffs.try_step(md, pos, Vector2(40, 40))
	_check("slides along cliff edge (y)",
		slid == Vector2(pos.x, pos.y + 40))
	# Open ground: full step.
	var free: Vector2 = Cliffs.try_step(md, pos, Vector2(-20, 10))
	_check("open ground full step", free == pos + Vector2(-20, 10))


func _test_empty_map_data() -> void:
	# No level grid (old saves, bare sim tests): everything neutral.
	var md := {}
	_check("empty level_at -> 0", Cliffs.level_at(md, Vector2(100, 100)) == 0)
	_check("empty lift -> 0.0", Cliffs.lift_at(md, Vector2(100, 100)) == 0.0)
	_check("empty high ground -> 1.0",
		Cliffs.high_ground_mult(md, Vector2.ZERO, Vector2(50, 50)) == 1.0)
	_check("empty not blocked",
		not Cliffs.cliff_blocked(md, Vector2.ZERO, Vector2(5000, 5000)))
	var s: Vector2 = Cliffs.try_step(md, Vector2(10, 10), Vector2(5, 5))
	_check("empty try_step passes through", s == Vector2(15, 15))


func _test_melee_high_ground_damage() -> void:
	# End-to-end: SimCombat._attack applies the high-ground edge.
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	gs.map_data = _fake_map(4)  # wall L4 vs lowland L1
	var combat := SimCombat.new(gs)
	var target := {
		"id": 7, "faction": "ogres", "alive": true, "hp": 200.0,
		"position": Vector2(16, 16),  # L1
	}
	gs.units.append(target)
	var attacker := {
		"id": 9, "faction": "humans", "alive": true, "hp": 200.0,
		"position": Vector2(4 * 32 + 16, 16),  # L4: 3 levels up
	}
	var stats := {"dmg": 100.0, "ranged": false, "cooldown": 1.0,
		"splash": 0.0}
	combat._attack(attacker, target, stats)
	# 100 * 1.45 = 145 -> hp 55.
	_check("melee downhill +45%",
		absf(float(target["hp"]) - 55.0) < 0.01)
	# Uphill: no bonus, no penalty.
	target["hp"] = 200.0
	attacker["position"] = Vector2(16, 16)
	target["position"] = Vector2(4 * 32 + 16, 16)
	combat._attack(attacker, target, stats)
	_check("melee uphill no bonus",
		absf(float(target["hp"]) - 100.0) < 0.01)
	gs.queue_free()


func _test_generated_levels() -> void:
	# Full MapGen: stepped mountains exist, water is 0, starts are flat,
	# no pillar artifacts, cliff faces exist for the renderer.
	var gen := MapGen.new()
	var md: Dictionary = gen.generate(["humans", "ogres"], 424242)
	_check("levels present", md.has("levels"))
	var levels: PackedByteArray = md["levels"]
	_check("levels 128x128", levels.size() == 128 * 128)
	var terrain: PackedByteArray = md["terrain"]
	var maxl := 0
	var faces := 0
	var pillars := 0
	for ty in 128:
		for tx in 128:
			var lv: int = levels[ty * 128 + tx]
			maxl = maxi(maxl, lv)
			if MapGen.is_water(terrain[ty * 128 + tx]):
				if lv != 0:
					_check("water always level 0", false)
			# Adjacent cliff faces + pillar check.
			var nmax := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nx: int = tx + dx
					var ny: int = ty + dy
					if nx < 0 or ny < 0 or nx >= 128 or ny >= 128:
						continue
					var nl: int = levels[ny * 128 + nx]
					nmax = maxi(nmax, nl)
					if absi(lv - nl) >= 1 and lv > 0 and nl >= 0:
						faces += 1
			if lv - nmax >= 2:
				pillars += 1
	_check("mountains reach level 3+", maxl >= 3)
	_check("cliff faces exist", faces > 0)
	_check("no pillar artifacts", pillars == 0)
	# Faction starts are flattened to level 1 (buildable).
	var starts: Dictionary = md["faction_starts"]
	var flat_ok := true
	for f in starts:
		var sp: Vector2 = starts[f]
		var lv: int = Cliffs.level_at(md, sp)
		if lv != 1:
			flat_ok = false
	_check("starts flattened to L1", flat_ok)
