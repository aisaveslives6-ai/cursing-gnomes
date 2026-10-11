extends SceneTree
## Cursing Gnomes — cel-shaded 3D wall tests (2026-10-06).
##
## Jeremy: "put 3d walls in that are cel shaded so they still look cartoon."
## WallMesh3D renders each wall segment as a real 3D volume (box body +
## crenellated merlons, oriented along wall_angle) projected into the 2D
## isometric canvas with stepped cel bands and ink outlines. Pure geometry
## helpers are unit-tested directly; the BuildingNode wiring (flat sprite
## skipped, damage-band redraws, draw smoke) is tested with live nodes.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_wall_mesh3d.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== Cursing Gnomes wall-mesh3d tests ===")
	_test_damage_band()
	_test_hp_frac()
	_test_ground_corners()
	_test_top_corners()
	_test_near_side()
	_test_side_shade()
	_test_merlon_layout()
	await _test_wall_node_wiring()
	await _test_draw_smoke()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_damage_band() -> void:
	_check("pristine at full hp", WallMesh3D.damage_band(1.0) == 0)
	_check("pristine above 0.66", WallMesh3D.damage_band(0.67) == 0)
	_check("cracked at 0.66", WallMesh3D.damage_band(0.66) == 1)
	_check("cracked above 0.33", WallMesh3D.damage_band(0.34) == 1)
	_check("ruined at 0.33", WallMesh3D.damage_band(0.33) == 2)
	_check("ruined at zero", WallMesh3D.damage_band(0.0) == 2)


func _test_hp_frac() -> void:
	_check("full hp -> 1.0",
		is_equal_approx(WallMesh3D.hp_frac(900.0, 900.0), 1.0))
	_check("half hp -> 0.5",
		is_equal_approx(WallMesh3D.hp_frac(450.0, 900.0), 0.5))
	_check("zero hp -> 0.0",
		is_equal_approx(WallMesh3D.hp_frac(0.0, 900.0), 0.0))
	_check("zero max_hp -> 1.0 (no div-by-zero)",
		is_equal_approx(WallMesh3D.hp_frac(100.0, 0.0), 1.0))
	_check("negative hp clamps to 0.0",
		is_equal_approx(WallMesh3D.hp_frac(-50.0, 900.0), 0.0))
	_check("overheal clamps to 1.0",
		is_equal_approx(WallMesh3D.hp_frac(1000.0, 900.0), 1.0))


func _test_ground_corners() -> void:
	# angle 0: segment along +X. hl = 44/2 + 7 = 29, hw = 7.
	var gc := WallMesh3D.ground_corners(0.0, 44.0, 14.0)
	_check("four corners", gc.size() == 4)
	_check("A = (-29,-7)", (gc[0] as Vector2).is_equal_approx(Vector2(-29, -7)))
	_check("B = (29,-7)", (gc[1] as Vector2).is_equal_approx(Vector2(29, -7)))
	_check("C = (29,7)", (gc[2] as Vector2).is_equal_approx(Vector2(29, 7)))
	_check("D = (-29,7)", (gc[3] as Vector2).is_equal_approx(Vector2(-29, 7)))
	_check("A == -C (centered)", (gc[0] as Vector2).is_equal_approx(-(gc[2] as Vector2)))
	_check("B == -D (centered)", (gc[1] as Vector2).is_equal_approx(-(gc[3] as Vector2)))
	# 90 degrees: segment along +Y, corners rotated.
	var gc90 := WallMesh3D.ground_corners(PI * 0.5, 44.0, 14.0)
	_check("angle 90: A = (7,-29)",
		(gc90[0] as Vector2).is_equal_approx(Vector2(7, -29)))


func _test_top_corners() -> void:
	var gc := WallMesh3D.ground_corners(0.3, 44.0, 14.0)
	var tc := WallMesh3D.top_corners(gc, 36.0)
	_check("four top corners", tc.size() == 4)
	for i in range(4):
		var g: Vector2 = gc[i]
		var t: Vector2 = tc[i]
		_check("top corner %d raised by height" % i,
			is_equal_approx(t.x, g.x) and is_equal_approx(t.y, g.y - 36.0))


func _test_near_side() -> void:
	_check("angle 0: +perp side nearer", WallMesh3D.near_side(0.0) == 1)
	_check("angle PI: -perp side nearer", WallMesh3D.near_side(PI) == -1)


func _test_side_shade() -> void:
	# Shadow toward -X means the sun sits toward +X.
	var sun_east := {"dx": -1.0, "dy": 0.0, "up": true}
	_check("sun-facing normal -> lit band",
		WallMesh3D.side_shade(Vector2(1, 0), sun_east) == WallMesh3D.SIDE_LIT)
	_check("away normal -> dark band",
		WallMesh3D.side_shade(Vector2(-1, 0), sun_east) == WallMesh3D.SIDE_DK)
	_check("edge-on normal -> mid band",
		WallMesh3D.side_shade(Vector2(0, 1), sun_east) == WallMesh3D.SIDE_MID)
	var night := {"dx": 0.0, "dy": 0.0, "up": false}
	_check("night -> darkened band",
		WallMesh3D.side_shade(Vector2(1, 0), night)
			== WallMesh3D.SIDE_DK.darkened(0.25))


func _test_merlon_layout() -> void:
	var pristine := WallMesh3D.merlon_layout(44.0, 0, 5)
	_check("44px wall -> 2 merlons", pristine.size() == 2)
	var all_full := true
	for m in pristine:
		if float((m as Dictionary)["h"]) < WallMesh3D.MERLON_H - 0.01:
			all_full = false
	_check("pristine merlons full height", all_full)
	_check("merlons symmetric about center",
		is_equal_approx(float((pristine[0] as Dictionary)["off"]),
			-float((pristine[1] as Dictionary)["off"])))
	var cracked := WallMesh3D.merlon_layout(44.0, 1, 5)
	_check("cracked keeps both merlons", cracked.size() == 2)
	var ruined := WallMesh3D.merlon_layout(44.0, 2, 5)
	_check("ruined loses merlons", ruined.size() < 2)
	for m in ruined:
		_check("ruined merlons are stubs",
			float((m as Dictionary)["h"]) < WallMesh3D.MERLON_H * 0.5)
	# Determinism: same seed -> same layout.
	var again := WallMesh3D.merlon_layout(44.0, 1, 5)
	_check("layout deterministic per seed",
		float((cracked[0] as Dictionary)["h"])
			== float((again[0] as Dictionary)["h"]))


func _make_wall_node(bid: int, rec: Dictionary) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(bid, "wall", "gnomes", Vector2(200, 200))
	n.record = rec
	return n


func _test_wall_node_wiring() -> void:
	# The flat wall_strip sprite is gone: walls draw procedurally now.
	var n := _make_wall_node(4242, {"complete": true, "hp": 900.0,
		"max_hp": 900.0, "wall_angle": 0.7})
	_check("wall node builds no sprite", n._sprite == null)
	root.add_child(n)
	await process_frame
	await process_frame
	_check("full hp -> damage band 0", n._wall_dmg_band == 0)
	n.record["hp"] = 500.0
	await process_frame
	await process_frame
	_check("mid hp -> damage band 1", n._wall_dmg_band == 1)
	n.record["hp"] = 100.0
	await process_frame
	await process_frame
	_check("low hp -> damage band 2", n._wall_dmg_band == 2)
	n.queue_free()
	await process_frame


func _test_draw_smoke() -> void:
	# Exercise every wall draw path headless: pristine / cracked / ruined /
	# blueprint / night sun. A script error here fails the run.
	var cfgs := [
		{"complete": true, "hp": 900.0, "max_hp": 900.0, "wall_angle": 0.0},
		{"complete": true, "hp": 500.0, "max_hp": 900.0, "wall_angle": 1.2},
		{"complete": true, "hp": 50.0, "max_hp": 900.0, "wall_angle": -0.6},
		{"complete": false, "progress": 0.4, "hp": 900.0, "max_hp": 900.0,
			"wall_angle": 2.2},
	]
	var bid := 5000
	for cfg in cfgs:
		var n := _make_wall_node(bid, cfg)
		root.add_child(n)
		n.queue_redraw()
		bid += 1
	await process_frame
	await process_frame
	_check("all wall draw paths executed without errors", true)
	for c in root.get_children():
		if c is BuildingNode and (c as BuildingNode).building_id >= 5000:
			c.queue_free()
	await process_frame
