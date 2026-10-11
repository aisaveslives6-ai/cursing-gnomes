extends SceneTree
## Cursing Gnomes — rubble pile tests (graphics-hourly 2026-10-05).
##
## Ports HTML spawnRubble / rubble aging tick / tapClearRubble /
## drawRubbleMound (fix79 index.html, "AoE-style rubble piles where buildings
## fell (tap to clear)"). Verifies the HTML-verbatim numbers (pile fields,
## size default 36, cap 60 oldest-first, age += dt, fade past 150 s at
## 0.5/s, fade alpha min(1, life*3), clear radius max(30, size*0.7),
## dust while age < 4, smoke while age < 25, seeded stone/beam scatter)
## plus the Godot improvements (drawn dust puffs instead of the '💨' emoji
## floating texts, idle hide/process disable, camera culling margin).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_rubble.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


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


func _approx(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) < eps


func _make_building(pos: Vector2, size: float = 40.0) -> Dictionary:
	return {"position": pos, "size": size, "race": "gnome", "type": "hall"}


func _test_html_constants() -> void:
	_check("cap is 60", RubbleLayer.MAX_PILES == 60)
	_check("fade starts at 150 s", _approx(RubbleLayer.FADE_AGE, 150.0))
	_check("fade rate 0.5/s", _approx(RubbleLayer.FADE_RATE, 0.5))
	_check("dust while age < 4", _approx(RubbleLayer.DUST_AGE, 4.0))
	_check("smoke while age < 25", _approx(RubbleLayer.SMOKE_AGE, 25.0))
	_check("clear base radius 30", _approx(RubbleLayer.CLEAR_BASE, 30.0))
	_check("default size 36", _approx(RubbleLayer.DEFAULT_SIZE, 36.0))
	_check("view margin 40", _approx(RubbleLayer.VIEW_MARGIN, 40.0))


func _test_spawn() -> void:
	var layer := RubbleLayer.new()
	var p: Dictionary = layer.spawn(_make_building(Vector2(100, 200), 44.0))
	_check("spawn returns pile", not p.is_empty())
	_check("pos recorded", (p["pos"] as Vector2) == Vector2(100, 200))
	_check("size recorded", _approx(float(p["size"]), 44.0))
	_check("race recorded", String(p["race"]) == "gnome")
	_check("type recorded", String(p["type"]) == "hall")
	_check("life starts at 1", _approx(float(p["life"]), 1.0))
	_check("age starts at 0", _approx(float(p["age"]), 0.0))
	_check("seed in 0..100", float(p["seed"]) >= 0.0 and float(p["seed"]) <= 100.0)
	_check("pile_count 1", layer.pile_count() == 1)
	# Size defaults to 36 when the building dict has no size (b.size || 36).
	var p2: Dictionary = layer.spawn({"position": Vector2.ZERO})
	_check("missing size -> 36", _approx(float(p2["size"]), 36.0))
	layer.free()


func _test_cap() -> void:
	var layer := RubbleLayer.new()
	for i in range(65):
		layer.spawn(_make_building(Vector2(i * 10, 0)))
	_check("capped at 60", layer.pile_count() == 60)
	var first: Dictionary = layer._piles[0]
	_check("oldest dropped first", (first["pos"] as Vector2) == Vector2(50, 0))
	var last: Dictionary = layer._piles[59]
	_check("newest kept", (last["pos"] as Vector2) == Vector2(640, 0))
	layer.free()


func _test_step_aging() -> void:
	var layer := RubbleLayer.new()
	var p: Dictionary = layer.spawn(_make_building(Vector2.ZERO))
	# No fade before 150 s: age accumulates, life stays 1.
	layer.step(60.0)
	_check("age accumulates", _approx(float(p["age"]), 60.0))
	_check("no fade before 150 s", _approx(float(p["life"]), 1.0))
	layer.step(90.0)  # age = 150, not yet past it
	_check("no fade at exactly 150 s", _approx(float(p["life"]), 1.0))
	_check("pile survives", layer.pile_count() == 1)
	# Past 150 s: life -= dt * 0.5 (2-second fade).
	layer.step(1.0)  # age = 151
	_check("fade past 150 s", _approx(float(p["life"]), 0.5))
	layer.step(1.0)  # age = 152, life -> 0
	_check("removed at life <= 0", layer.pile_count() == 0)
	layer.free()


func _test_step_removed_count() -> void:
	var layer := RubbleLayer.new()
	for i in range(3):
		layer.spawn(_make_building(Vector2(i * 50, 0)))
	var removed: int = layer.step(160.0)
	_check("removal count reported", removed == 3)
	_check("all piles gone", layer.pile_count() == 0)
	layer.free()


func _test_dust_spawning() -> void:
	var layer := RubbleLayer.new()
	layer.spawn(_make_building(Vector2(50, 50)))
	# delta 0.2 -> dust chance 0.15 * 0.2 * 60 = 1.8, always spawns, and the
	# 0.6 s puff survives the same step's _step_puffs(0.2) (deterministic).
	layer.step(0.2)
	_check("settling dust spawns while age < 4", layer._puffs.size() >= 1)
	# Past the dust window: no new puffs (existing ones only decay).
	(layer._piles[0] as Dictionary)["age"] = 5.0
	var before: int = layer._puffs.size()
	layer.step(0.2)
	_check("no dust past age 4", layer._puffs.size() <= before)
	layer.free()


func _test_tap_clear() -> void:
	var layer := RubbleLayer.new()
	layer.spawn(_make_building(Vector2(100, 100), 36.0))
	# size 36 -> clear radius max(30, 25.2) = 30.
	var hit: Dictionary = layer.tap_clear(Vector2(115, 110))
	_check("tap within radius clears", not hit.is_empty())
	_check("cleared pile returned", (hit["pos"] as Vector2) == Vector2(100, 100))
	_check("pile removed", layer.pile_count() == 0)
	_check("clear spawns 6 dust puffs", layer._puffs.size() == 6)
	layer.free()


func _test_tap_clear_miss() -> void:
	var layer := RubbleLayer.new()
	layer.spawn(_make_building(Vector2(100, 100), 36.0))
	var miss: Dictionary = layer.tap_clear(Vector2(500, 500))
	_check("tap far away clears nothing", miss.is_empty())
	_check("pile survives a miss", layer.pile_count() == 1)
	layer.free()


func _test_tap_clear_big_radius() -> void:
	var layer := RubbleLayer.new()
	layer.spawn(_make_building(Vector2(200, 200), 100.0))
	# size 100 -> clear radius max(30, 70) = 70.
	var hit: Dictionary = layer.tap_clear(Vector2(260, 200))
	_check("big piles use size * 0.7 radius", not hit.is_empty())
	layer.free()


func _test_tap_clear_newest_first() -> void:
	var layer := RubbleLayer.new()
	layer.spawn(_make_building(Vector2(300, 300), 36.0))
	layer.spawn(_make_building(Vector2(305, 305), 36.0))
	var hit: Dictionary = layer.tap_clear(Vector2(302, 302))
	_check("newest pile cleared first", (hit["pos"] as Vector2) == Vector2(305, 305))
	_check("older pile survives", layer.pile_count() == 1)
	layer.free()


func _test_fade_alpha() -> void:
	_check("fade alpha full at life 1", _approx(RubbleLayer.fade_alpha(1.0), 1.0))
	_check("fade alpha min(1, life*3)", _approx(RubbleLayer.fade_alpha(0.2), 0.6))
	_check("fade alpha 0 at life 0", _approx(RubbleLayer.fade_alpha(0.0), 0.0))
	_check("fade alpha never negative", RubbleLayer.fade_alpha(-1.0) >= 0.0)


func _test_seeded() -> void:
	var a: float = RubbleLayer.seeded(12.5, 3.0)
	var b: float = RubbleLayer.seeded(12.5, 3.0)
	_check("seeded scatter deterministic", _approx(a, b))
	var c: float = RubbleLayer.seeded(99.0, 3.0)
	_check("different seeds differ", not _approx(a, c))
	_check("scatter in 0..1", a >= 0.0 and a < 1.0)


func _test_stone_beam_params() -> void:
	var st := RubbleLayer.stone_params(7.25, 40.0, 2)
	var sp: Vector2 = st["pos"]
	_check("stone x within scatter band", absf(sp.x) <= 40.0 * 0.65 + 0.01)
	_check("stone y above ground line", sp.y <= 40.0 * 0.3 + 0.01 and sp.y >= -40.0 * 0.2 - 0.01)
	var sr: float = float(st["size"])
	_check("stone size >= 3", sr >= 3.0)
	var st2 := RubbleLayer.stone_params(7.25, 40.0, 2)
	_check("stone params deterministic", (st2["pos"] as Vector2) == sp)
	var bm := RubbleLayer.beam_params(7.25, 40.0, 1)
	var w: float = float(bm["width"])
	_check("beam width 3..6", w >= 3.0 and w <= 6.0)
	_check("beam endpoints finite", (bm["from"] as Vector2).is_finite() and (bm["to"] as Vector2).is_finite())


func _test_smoke_pos() -> void:
	var s := 40.0
	var p1 := RubbleLayer.smoke_pos(5.0, s, 10.0)
	var p2 := RubbleLayer.smoke_pos(5.0, s, 10.0)
	_check("smoke pos deterministic", p1 == p2)
	_check("smoke sways within +/-8", absf(p1.x) <= 8.0)
	_check("smoke rises up to 36 px", p1.y <= -s * 0.5 and p1.y >= -s * 0.5 - 36.0)


func _test_ellipse_helpers() -> void:
	var e := RubbleLayer._ellipse(Vector2(10, 20), 8.0, 4.0, 12)
	_check("ellipse has n points", e.size() == 12)
	var h := RubbleLayer._half_ellipse(Vector2.ZERO, 8.0, 4.0, 12)
	_check("half ellipse closes the arc", h.size() == 13)
	var all_up := true
	for pt: Vector2 in h:
		if pt.y > 0.01:
			all_up = false
	_check("half ellipse stays above center", all_up)


func _test_node_basics() -> void:
	var layer := RubbleLayer.new()
	_check("z_index below units/buildings", layer.z_index == -40)
	_check("camera unset by default", layer._camera == null)
	_check("visible rect empty without camera", layer._visible_rect() == Rect2())
	var cam := Camera2D.new()
	layer.set_camera(cam)
	_check("set_camera stores camera", layer._camera == cam)
	cam.free()
	layer.free()


func _initialize() -> void:
	_test_html_constants()
	_test_spawn()
	_test_cap()
	_test_step_aging()
	_test_step_removed_count()
	_test_dust_spawning()
	_test_tap_clear()
	_test_tap_clear_miss()
	_test_tap_clear_big_radius()
	_test_tap_clear_newest_first()
	_test_fade_alpha()
	_test_seeded()
	_test_stone_beam_params()
	_test_smoke_pos()
	_test_ellipse_helpers()
	_test_node_basics()
	print("rubble: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("FAILURES: ", _failures)
	quit(1 if _failed > 0 else 0)
