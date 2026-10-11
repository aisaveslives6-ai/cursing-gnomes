extends SceneTree
## Cursing Gnomes — vehicle building-collision grid tests.
## Perf 2026-10-10 (massive-dev, AAA 60fps): _blocked_by_building scanned ALL
## buildings per driving vehicle per frame (21.4ms/frame at 30v x 300b).
## The spatial grid must give BIT-IDENTICAL answers to the old linear scan
## under every mutation pattern, and the separation early-out must not
## change behavior.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_vehicle_grids.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes vehicle grid tests ===")
	_test_grid_matches_linear()
	_test_grid_matches_linear_stress()
	_test_invalidation_on_size_change()
	_test_live_liveness_no_size_change()
	_test_bridge_exempt()
	_test_separation_early_out()
	_test_drive_into_building_stops()
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


## Verbatim copy of the pre-grid _blocked_by_building logic (the oracle).
func _linear_blocked(bs: Array, pos: Vector2, radius: float) -> bool:
	for b in bs:
		var bd: Dictionary = b
		if not bool(bd.get("alive", false)) \
				or not bool(bd.get("complete", false)):
			continue
		if String(bd.get("type", "")) == "bridge":
			continue
		var fr: float = SimBuildings.footprint(String(bd.get("type", ""))) \
			+ radius
		if pos.distance_squared_to(
				bd.get("position", Vector2.ZERO)) < fr * fr:
			return true
	return false


func _new_sv() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0,
		"size_tiles": Vector2i(128, 128), "tile_size": 32.0,
		"terrain": PackedByteArray()}
	var sv := SimVehicles.new(gs)
	return {"gs": gs, "sv": sv}


func _seed_buildings(gs: GameState, rng: RandomNumberGenerator,
		count: int) -> void:
	var types := ["house", "town_hall", "farm", "shop", "barracks",
		"bridge"]
	for i in count:
		var t: String = types[i % types.size()]
		gs.buildings.append({"type": t, "faction": "humans",
			"position": Vector2(rng.randf_range(100, 4000),
				rng.randf_range(100, 4000)),
			"alive": (i % 11) != 0, "complete": (i % 7) != 0})


func _test_grid_matches_linear() -> void:
	var w := _new_sv()
	var gs: GameState = w["gs"]
	var sv: SimVehicles = w["sv"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010
	_seed_buildings(gs, rng, 120)
	var radii := [9.0, 11.0, 13.0, 14.0]
	var mismatches := 0
	for i in 200:
		var pos := Vector2(rng.randf_range(0, 4096), rng.randf_range(0, 4096))
		var r: float = radii[i % radii.size()]
		var grid: bool = sv._blocked_by_building(pos, r)
		var lin: bool = _linear_blocked(gs.buildings, pos, r)
		if grid != lin:
			mismatches += 1
	_check("grid==linear: 200 random probes, 120 mixed buildings",
		mismatches == 0)
	gs.queue_free()


func _test_grid_matches_linear_stress() -> void:
	# Boundary probes hugging building edges + negative-adjacent cells.
	var w := _new_sv()
	var gs: GameState = w["gs"]
	var sv: SimVehicles = w["sv"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	_seed_buildings(gs, rng, 300)
	var mismatches := 0
	var probes := 0
	for b in gs.buildings:
		var bd: Dictionary = b
		var bp: Vector2 = bd.get("position", Vector2.ZERO)
		var fr := SimBuildings.footprint(String(bd.get("type", "")))
		for k in 8:
			var ang := TAU * float(k) / 8.0
			# Just inside and just outside the block radius.
			for off in [-1.5, 1.5]:
				var pos: Vector2 = bp + Vector2(cos(ang), sin(ang)) \
					* (fr + 14.0 + off)
				probes += 1
				if sv._blocked_by_building(pos, 14.0) \
						!= _linear_blocked(gs.buildings, pos, 14.0):
					mismatches += 1
	_check("grid==linear: %d edge probes, 300 buildings" % probes,
		mismatches == 0)
	gs.queue_free()


func _test_invalidation_on_size_change() -> void:
	var w := _new_sv()
	var gs: GameState = w["gs"]
	var sv: SimVehicles = w["sv"]
	var pos := Vector2(2000, 2000)
	_check("invalidation: empty field not blocked",
		not sv._blocked_by_building(pos, 14.0))
	# Direct append (the pattern tests and some systems use) changes size.
	gs.buildings.append({"type": "house", "faction": "humans",
		"position": pos, "alive": true, "complete": true})
	_check("invalidation: appended building blocks after size change",
		sv._blocked_by_building(pos, 14.0))
	gs.buildings.clear()
	_check("invalidation: cleared field not blocked",
		not sv._blocked_by_building(pos, 14.0))
	gs.queue_free()


func _test_live_liveness_no_size_change() -> void:
	var w := _new_sv()
	var gs: GameState = w["gs"]
	var sv: SimVehicles = w["sv"]
	var pos := Vector2(2000, 2000)
	var bd := {"type": "house", "faction": "humans", "position": pos,
		"alive": true, "complete": false}
	gs.buildings.append(bd)
	_check("liveness: incomplete blueprint does not block",
		not sv._blocked_by_building(pos, 14.0))
	# Completion flips no size — the grid must still pick it up because
	# liveness is read live.
	bd["complete"] = true
	_check("liveness: completion flip (no size change) blocks",
		sv._blocked_by_building(pos, 14.0))
	# Demolition flag, still no size change.
	bd["alive"] = false
	_check("liveness: destroyed building does not block",
		not sv._blocked_by_building(pos, 14.0))
	gs.queue_free()


func _test_bridge_exempt() -> void:
	var w := _new_sv()
	var gs: GameState = w["gs"]
	var sv: SimVehicles = w["sv"]
	var pos := Vector2(2000, 2000)
	gs.buildings.append({"type": "bridge", "faction": "humans",
		"position": pos, "alive": true, "complete": true})
	_check("bridge: exempt from blocking",
		not sv._blocked_by_building(pos, 14.0))
	gs.queue_free()


func _test_separation_early_out() -> void:
	var w := _new_sv()
	var gs: GameState = w["gs"]
	var sv: SimVehicles = w["sv"]
	# Two overlapping parked vehicles: first tick separates (fleet dirty),
	# then the O(n^2) pass must not run again while nothing moves.
	var a: Dictionary = sv.spawn_vehicle("wagon", Vector2(500, 500), "humans")
	var b: Dictionary = sv.spawn_vehicle("cart", Vector2(500, 500), "humans")
	sv.tick(1.0 / 60.0)
	_check("separation: overlapping parked pair pushed apart",
		(a.get("pos", Vector2.ZERO) as Vector2).distance_to(
			b.get("pos", Vector2.ZERO)) > 1.0)
	var passes_after_first: int = sv.separation_passes
	for i in 10:
		sv.tick(1.0 / 60.0)
	_check("separation: parked fleet runs no further passes",
		sv.separation_passes == passes_after_first)
	# Driving re-arms it.
	sv.drive_to(int(a["id"]), Vector2(3000, 3000))
	var before: int = sv.separation_passes
	sv.tick(1.0 / 60.0)
	_check("separation: driving vehicle re-arms the pass",
		sv.separation_passes > before)
	gs.queue_free()


func _test_drive_into_building_stops() -> void:
	var w := _new_sv()
	var gs: GameState = w["gs"]
	var sv: SimVehicles = w["sv"]
	var bpos := Vector2(2000, 2000)
	gs.buildings.append({"type": "town_hall", "faction": "humans",
		"position": bpos, "alive": true, "complete": true})
	var fr := SimBuildings.footprint("town_hall")
	var v: Dictionary = sv.spawn_vehicle("wagon", Vector2(1500, 2000), "humans")
	sv.drive_to(int(v["id"]), Vector2(2500, 2000))  # straight through
	var entered := false
	for i in 600:
		sv.tick(1.0 / 60.0)
		var p: Vector2 = v.get("pos", Vector2.ZERO)
		if p.distance_to(bpos) < fr + 14.0 - 0.5:
			entered = true
			break
		if String(v.get("state", "")) == SimVehicles.STATE_PARKED \
				and not bool(v.get("has_target", true)):
			break
	_check("drive: vehicle never enters the building footprint", not entered)
	gs.queue_free()
