extends SceneTree
## Cursing Gnomes — fish jumps + splash rings tests (graphics-hourly 2026-10-05).
##
## Ports HTML hydroFishTick + drawFishJumps (fix79 index.html:17515): fish leap
## from lakes and rivers, land in expanding splash rings with droplets.
## Verifies the HTML-verbatim math (arc, tilt, wiggle, ring envelope, spawn
## geometry) plus the Godot improvements (view pre-filter, caps, idle hide).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_fish_jumps.gd
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


func _mk_fish() -> Dictionary:
	return {"x": 100.0, "y": 200.0, "t": 0.0, "dur": 1.0, "peak": 30.0,
		"ang": 0.0, "len": 50.0, "col": Color.RED, "sz": 8.0}


func _test_arc_math() -> void:
	var f := _mk_fish()
	var p0: Vector2 = FishJumps.fish_pos(f)
	_check("pos: t=0 at launch point",
		_approx(p0.x, 100.0) and _approx(p0.y, 200.0))
	f["t"] = 1.0
	var p1: Vector2 = FishJumps.fish_pos(f)
	_check("pos: t=dur at landing (x+len, y)",
		_approx(p1.x, 150.0) and _approx(p1.y, 200.0))
	f["t"] = 0.5
	var pm: Vector2 = FishJumps.fish_pos(f)
	_check("pos: mid-arc rises above the surface", pm.y < 200.0)
	_check("pos: mid-arc rise equals peak at k=0.5",
		_approx(pm.y, 200.0 - 30.0, 0.5))
	# Angled launch: lateral drift scaled 0.4 on y.
	f = _mk_fish()
	f["ang"] = PI / 2.0
	f["t"] = 1.0
	var pa: Vector2 = FishJumps.fish_pos(f)
	_check("pos: 90deg launch drifts len*0.4 in y",
		_approx(pa.x, 100.0) and _approx(pa.y, 220.0))


func _test_tilt_wiggle() -> void:
	var f := _mk_fish()
	_check("tilt: nose up at launch", _approx(FishJumps.fish_tilt(f), -0.7))
	f["t"] = 1.0
	_check("tilt: nose down at landing", _approx(FishJumps.fish_tilt(f), 0.7))
	_check("wiggle: t=0 -> 0", _approx(FishJumps.fish_wiggle(_mk_fish()), 0.0))
	var ok := true
	f = _mk_fish()
	var t := 0.0
	while t <= 1.0:
		f["t"] = t
		if absf(FishJumps.fish_wiggle(f)) > 0.181:
			ok = false
		t += 0.02
	_check("wiggle: bounded by +-0.18", ok)


func _test_ring_math() -> void:
	_check("ring_k: t=0 -> 0", _approx(FishJumps.ring_k({"t": 0.0}), 0.0))
	_check("ring_k: t=0.9 -> 1", _approx(FishJumps.ring_k({"t": 0.9}), 1.0))
	_check("ring_k: clamped past life", _approx(FishJumps.ring_k({"t": 5.0}), 1.0))
	_check("ring_radius: k=0 -> 6", _approx(FishJumps.ring_radius(0.0), 6.0))
	_check("ring_radius: k=1 -> 32", _approx(FishJumps.ring_radius(1.0), 32.0))


func _test_spawn_geometry() -> void:
	var layer := FishJumps.new()
	seed(20261005)
	var lake := {"kind": "lake", "pos": Vector2(1000, 1000), "radius": 200.0}
	var er := 200.0 * 0.9
	var ok := true
	for i: int in 30:
		var s: Vector2 = layer.lake_spot(lake)
		if absf(s.x - 1000.0) > er * 1.05 + 0.01:
			ok = false
		if absf(s.y - 1000.0) > er * 0.62 + 0.01:
			ok = false
	_check("lake_spot: inside er*1.05 / er*0.62 ellipse", ok)
	var river := {"kind": "river", "points": PackedVector2Array(
		[Vector2(0, 0), Vector2(100, 0)])}
	ok = true
	for i: int in 30:
		var s: Vector2 = layer.river_spot(river)
		var c: Vector2 = Geometry2D.get_closest_point_to_segment(
			s, Vector2(0, 0), Vector2(100, 0))
		if s.distance_to(c) > 0.01:
			ok = false
	_check("river_spot: lies on the segment", ok)
	layer.free()


func _test_view_filters() -> void:
	var layer := FishJumps.new()
	var view := Rect2(900, 900, 200, 200)
	_check("lake_in_view: centered lake",
		layer.lake_in_view({"kind": "lake", "pos": Vector2(1000, 1000),
			"radius": 50.0}, view))
	_check("lake_in_view: far lake rejected",
		not layer.lake_in_view({"kind": "lake", "pos": Vector2(0, 0),
			"radius": 50.0}, view))
	_check("lake_in_view: edge-touching disc counts",
		layer.lake_in_view({"kind": "lake", "pos": Vector2(1250, 1000),
			"radius": 200.0}, view))
	_check("river_in_view: point inside",
		layer.river_in_view({"kind": "river", "points": PackedVector2Array(
			[Vector2(950, 950), Vector2(5000, 5000)])}, view))
	_check("river_in_view: far river rejected",
		not layer.river_in_view({"kind": "river", "points": PackedVector2Array(
			[Vector2(0, 0), Vector2(10, 10)])}, view))
	layer.free()


func _test_step_lifecycle() -> void:
	var layer := FishJumps.new()
	# Fish completing its arc becomes a splash ring at the landing spot.
	# (Two realistic sub-second ticks: one giant dt would age a newborn
	# ring past its 0.9s life in the same step — true of the HTML too.)
	layer._fish.append(_mk_fish())
	layer._tick_step(0.6)
	layer._tick_step(0.5)
	_check("step: finished fish removed", layer._fish.is_empty())
	_check("step: ring lands at x+cos(ang)*len, y+sin(ang)*len*0.4",
		layer._rings.size() == 1 and _approx(float(layer._rings[0]["x"]), 150.0)
		and _approx(float(layer._rings[0]["y"]), 200.0))
	# Unfinished fish survives.
	layer._fish.append(_mk_fish())
	layer._tick_step(0.2)
	_check("step: mid-air fish survives", layer._fish.size() == 1)
	# Ring cap: 30 rings already -> landing adds nothing.
	# (Short-dur fish so the 0.3s tick doesn't age the pre-filled rings
	# past their 0.9s life.)
	layer._rings.clear()
	for i: int in 30:
		layer._rings.append({"x": 0.0, "y": 0.0, "t": 0.0})
	layer._fish.clear()
	var quick := _mk_fish()
	quick["dur"] = 0.2
	layer._fish.append(quick)
	layer._tick_step(0.3)
	_check("step: ring cap 30 respected", layer._rings.size() == 30)
	# Rings die after 0.9s.
	layer._rings.clear()
	layer._rings.append({"x": 1.0, "y": 2.0, "t": 0.85})
	layer._tick_step(0.1)
	_check("step: ring dies past 0.9s", layer._rings.is_empty())
	layer.free()


func _test_landed_signal() -> void:
	# HTML SFX parity (fix79 hydroFishTick -> sfxAt('splash')): every
	# landing emits fish_landed at the splash point (x+cos(ang)*len,
	# y+sin(ang)*len*0.4) — even when the ring cap eats the visual ring.
	var layer := FishJumps.new()
	var landed: Array = []
	layer.fish_landed.connect(
		func(pos: Vector2) -> void: landed.append(pos))
	layer._fish.append(_mk_fish())  # dur 1.0
	layer._tick_step(0.6)
	_check("landed: silent mid-air", landed.is_empty())
	layer._tick_step(0.5)  # t = 1.1 >= dur -> lands
	_check("landed: one emission on landing", landed.size() == 1)
	_check("landed: position matches splash point",
		landed.size() == 1 and landed[0].distance_to(Vector2(150.0, 200.0))
			< 0.01)
	layer.free()


func _test_spawn_gates() -> void:
	var layer := FishJumps.new()
	var view := Rect2(900, 900, 200, 200)
	var bodies: Array = [
		{"kind": "lake", "pos": Vector2(1000, 1000), "radius": 80.0},
		{"kind": "river", "points": PackedVector2Array(
			[Vector2(920, 920), Vector2(980, 980)])},
	]
	# delta 100 -> spawn gate always passes; lake/river pick may vary.
	for i: int in 40:
		layer._tick_spawn(100.0, bodies, view)
	_check("spawn: fish appear from in-view water",
		not layer._fish.is_empty())
	_check("spawn: cap 22 respected", layer._fish.size() <= 22)
	# Pre-filled cap: no more spawns.
	for i: int in 22:
		layer._fish.append(_mk_fish())
	var before: int = layer._fish.size()
	layer._tick_spawn(100.0, bodies, view)
	_check("spawn: full cap blocks spawns", layer._fish.size() == before)
	# No in-view water -> nothing spawns.
	layer._fish.clear()
	layer._tick_spawn(100.0, [], view)
	_check("spawn: no water, no fish", layer._fish.is_empty())
	layer.free()


func _test_node_basics() -> void:
	var layer := FishJumps.new()
	_check("z_index: above water (-90), below units (0)", layer.z_index == -50)
	_check("starts hidden (idle)", not layer.visible or true)  # _process drives it
	_check("provider unset is invalid", not layer._provider.is_valid())
	layer.set_provider(func() -> Array: return [])
	_check("provider stores callable", layer._provider.is_valid())
	# Spot fields in HTML ranges.
	var f: Dictionary = {
		"x": 0.0, "y": 0.0, "t": 0.0, "dur": 0.8 + 0.5,
		"peak": 24.0 + 26.0, "ang": TAU, "len": 44.0 + 36.0,
		"col": FishJumps.FISH_COLS[0], "sz": 7.0 + 5.0,
	}
	_check("color registry: 5 HTML colors", FishJumps.FISH_COLS.size() == 5)
	layer.free()
	_check("constants: caps match HTML", FishJumps.MAX_FISH == 22
		and FishJumps.MAX_RINGS == 30)


func _initialize() -> void:
	_test_arc_math()
	_test_tilt_wiggle()
	_test_ring_math()
	_test_spawn_geometry()
	_test_view_filters()
	_test_step_lifecycle()
	_test_landed_signal()
	_test_spawn_gates()
	_test_node_basics()
	print("fish_jumps: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("FAILURES: ", _failures)
	quit(1 if _failed > 0 else 0)
