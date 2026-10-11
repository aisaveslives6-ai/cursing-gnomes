extends SceneTree
## Cursing Gnomes — disaster monster marker tests (graphics-hourly 2026-10-05).
##
## Ports HTML drawDisasterMarkers (fix79 index.html:14557): pulsing red "!"
## diamonds over live monsters when zoomed out (camZoom < 0.75), with
## screen-edge arrows for off-screen monsters. The "!" is vector-drawn
## (bar + dot), never a font glyph — iPhone web-export tofu risk.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_disaster_markers.gd
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


func _test_pulse_math() -> void:
	_check("pulse: t=0 -> 0.6", _approx(DisasterMarkers.pulse_for(0.0), 0.6))
	_check("pulse: sin peak -> 1.0",
		_approx(DisasterMarkers.pulse_for(PI / 10.0), 1.0))
	_check("pulse: sin trough -> 0.2",
		_approx(DisasterMarkers.pulse_for(3.0 * PI / 10.0), 0.2))
	# Bounded HTML-verbatim envelope.
	var ok := true
	var t := 0.0
	while t < 2.0:
		var p: float = DisasterMarkers.pulse_for(t)
		if p < 0.199 or p > 1.001:
			ok = false
		t += 0.05
	_check("pulse: stays in [0.2, 1.0]", ok)
	_check("radius: pulse 0.6 -> 24.2",
		_approx(DisasterMarkers.diamond_radius(0.6), 24.2))
	_check("radius: pulse 1.0 -> 27.0",
		_approx(DisasterMarkers.diamond_radius(1.0), 27.0))
	_check("alpha: pulse 0.6 -> 0.352",
		_approx(DisasterMarkers.diamond_alpha(0.6), 0.352))
	_check("alpha: pulse 0 -> 0.22",
		_approx(DisasterMarkers.diamond_alpha(0.0), 0.22))


func _test_zoom_gate() -> void:
	_check("gate: 0.5 shows", DisasterMarkers.shows_at_zoom(0.5))
	_check("gate: 0.74 shows", DisasterMarkers.shows_at_zoom(0.74))
	_check("gate: 0.75 hides (HTML >= 0.75 returns)",
		not DisasterMarkers.shows_at_zoom(0.75))
	_check("gate: 1.0 hides", not DisasterMarkers.shows_at_zoom(1.0))
	_check("gate: 0.08 (paper-map zoom) shows",
		DisasterMarkers.shows_at_zoom(0.08))


func _test_screen_math() -> void:
	var s: Vector2 = DisasterMarkers.world_to_screen(
		Vector2(100, 100), Vector2.ZERO, 0.5, Vector2(800, 600))
	_check("world_to_screen: (100,100)@0.5 -> (450,350)",
		_approx(s.x, 450.0) and _approx(s.y, 350.0))
	var s2: Vector2 = DisasterMarkers.world_to_screen(
		Vector2(200, 0), Vector2(200, 0), 0.25, Vector2(800, 600))
	_check("world_to_screen: cam-centered -> view center",
		_approx(s2.x, 400.0) and _approx(s2.y, 300.0))
	var c: Vector2 = DisasterMarkers.edge_clamp(
		Vector2(-100, 700), Vector2(800, 600))
	_check("edge_clamp: (-100,700) -> (34,566)",
		_approx(c.x, 34.0) and _approx(c.y, 566.0))
	var c2: Vector2 = DisasterMarkers.edge_clamp(
		Vector2(400, 300), Vector2(800, 600))
	_check("edge_clamp: inside stays", c2 == Vector2(400, 300))
	var a: float = DisasterMarkers.arrow_angle(
		Vector2(900, 300), Vector2(766, 300))
	_check("arrow_angle: due east -> 0", _approx(a, 0.0))
	var a2: float = DisasterMarkers.arrow_angle(
		Vector2(100, -50), Vector2(100, 34))
	_check("arrow_angle: due north -> -PI/2", _approx(a2, -PI / 2.0))


func _make_layer(cam_zoom: float, positions: PackedVector2Array) -> DisasterMarkers:
	var cam := Camera2D.new()
	cam.position = Vector2.ZERO
	cam.zoom = Vector2(cam_zoom, cam_zoom)
	root.add_child(cam)
	var m := DisasterMarkers.new()
	root.add_child(m)
	m.set_meta("cam", cam)
	m.set_camera(cam)
	m.set_provider(func() -> PackedVector2Array: return positions)
	return m


func _free_layer(m: DisasterMarkers) -> void:
	(m.get_meta("cam") as Camera2D).free()
	m.free()


func _test_node_gating() -> void:
	# Zoomed in: layer hides itself, no commands built.
	var m1 := _make_layer(1.0, PackedVector2Array([Vector2(100, 100)]))
	await process_frame
	await process_frame
	_check("node: zoom 1.0 hides layer", not m1.visible)
	_check("node: zoom 1.0 builds nothing",
		m1._diamonds.is_empty() and m1._arrows.is_empty())
	_free_layer(m1)
	# No monsters: hidden even at far zoom.
	var m2 := _make_layer(0.5, PackedVector2Array())
	await process_frame
	await process_frame
	_check("node: no monsters hides layer", not m2.visible)
	_free_layer(m2)


func _test_node_markers() -> void:
	var view: Vector2 = root.get_visible_rect().size
	# On-screen monster -> diamond at its screen position.
	var wp := Vector2(100, 100)
	var m := _make_layer(0.5, PackedVector2Array([wp]))
	await process_frame
	await process_frame
	_check("node: far zoom shows layer", m.visible)
	_check("node: one on-screen monster -> one diamond",
		m._diamonds.size() == 1 and m._arrows.is_empty())
	var want: Vector2 = DisasterMarkers.world_to_screen(
		wp, Vector2.ZERO, 0.5, view)
	var got: Vector2 = m._diamonds[0]["at"]
	_check("node: diamond at toScreen position",
		_approx(got.x, want.x, 1.0) and _approx(got.y, want.y, 1.0))
	# HTML pulse envelope [0.2, 1.0] -> radius [21.4, 27.0].
	_check("node: diamond radius in [21.4, 27]",
		float(m._diamonds[0]["r"]) >= 21.39
		and float(m._diamonds[0]["r"]) <= 27.01)
	_free_layer(m)
	# Far off-screen monster -> edge arrow, clamped inside the margin.
	var far := Vector2(100000, 100000)
	var m2 := _make_layer(0.5, PackedVector2Array([far]))
	await process_frame
	await process_frame
	_check("node: off-screen monster -> one arrow",
		m2._arrows.size() == 1 and m2._diamonds.is_empty())
	var at: Vector2 = m2._arrows[0]["at"]
	_check("node: arrow clamped to edge margin",
		_approx(at.x, view.x - 34.0, 1.0)
		and _approx(at.y, view.y - 34.0, 1.0))
	_check("node: arrow angle points SE-ish",
		m2._arrows[0]["ang"] > 0.0)
	_free_layer(m2)


func _test_node_cap() -> void:
	# 100 monsters: only MAX_MARKERS commands built, nearest-first.
	var positions := PackedVector2Array()
	for i: int in 100:
		positions.append(Vector2(i * 50.0, 0.0))
	var m := _make_layer(0.5, positions)
	await process_frame
	await process_frame
	var total: int = m._diamonds.size() + m._arrows.size()
	_check("node: cap at MAX_MARKERS", total == DisasterMarkers.MAX_MARKERS)
	# Nearest monster (0,0) must be among the drawn diamonds.
	var nearest_drawn := false
	for d: Dictionary in m._diamonds:
		if (d["at"] as Vector2).distance_to(
				DisasterMarkers.world_to_screen(Vector2.ZERO, Vector2.ZERO,
					0.5, root.get_visible_rect().size)) < 2.0:
			nearest_drawn = true
	_check("node: nearest-first keeps closest monster", nearest_drawn)
	_free_layer(m)


func _initialize() -> void:
	_test_pulse_math()
	_test_zoom_gate()
	_test_screen_math()
	await _test_node_gating()
	await _test_node_markers()
	await _test_node_cap()
	print("test_disaster_markers: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)
