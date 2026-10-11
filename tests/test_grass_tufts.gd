extends SceneTree
## Cursing Gnomes — grass sway animation tests (graphics-hourly 2026-10-04).
##
## Covers: default wind state, set_wind clamping, sway_offset purity
## (determinism, zero-wind stillness, downwind lean, per-tuft phase ripple,
## time-driven motion), _process clock advance + hidden early-out, refresh
## visibility gating (unchanged HTML-parity rules), and the self-contained
## wind read from a parent world node (no world.gd wiring).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_grass_tufts.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


class FakeSeasons:
	var wind_dir := 1.2
	var wind_speed := 1.5


class FakeGame:
	var seasons = null


class FakeWorld:
	extends Node
	var game = null


func _initialize() -> void:
	print("=== Cursing Gnomes grass-tuft sway tests ===")
	_test_defaults()
	_test_set_wind_clamp()
	_test_sway_zero_wind()
	_test_sway_deterministic()
	_test_sway_moves_with_time()
	_test_sway_lean_downwind()
	_test_sway_phase_ripple()
	_test_process_clock()
	_test_process_hidden_noop()
	_test_refresh_gating()
	_test_read_wind_fake_world()
	_test_read_wind_no_parent_safe()
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


func _test_defaults() -> void:
	var g := GrassTufts.new()
	_check("sway: default wind dir 0", g._wind_dir == 0.0)
	_check("sway: default wind speed 0.4", g._wind_speed == 0.4)
	_check("sway: clock starts 0", g._time == 0.0)
	g.free()


func _test_set_wind_clamp() -> void:
	var g := GrassTufts.new()
	g.set_wind(2.0, 1.5)
	_check("sway: set_wind dir stored", g._wind_dir == 2.0)
	_check("sway: set_wind speed stored", g._wind_speed == 1.5)
	g.set_wind(0.0, 9.0)
	_check("sway: speed clamps to 2", g._wind_speed == 2.0)
	g.set_wind(0.0, -3.0)
	_check("sway: speed clamps to 0", g._wind_speed == 0.0)
	g.free()


func _test_sway_zero_wind() -> void:
	var off := GrassTufts.sway_offset(Vector2(100, 200), 5.0, 0.7, 0.0)
	_check("sway: zero wind -> zero offset", off == Vector2.ZERO)


func _test_sway_deterministic() -> void:
	var a := GrassTufts.sway_offset(Vector2(100, 200), 5.0, 0.7, 1.0)
	var b := GrassTufts.sway_offset(Vector2(100, 200), 5.0, 0.7, 1.0)
	_check("sway: pure function, same in/out", a == b)


func _test_sway_moves_with_time() -> void:
	var a := GrassTufts.sway_offset(Vector2(100, 200), 5.0, 0.7, 1.0)
	var b := GrassTufts.sway_offset(Vector2(100, 200), 6.3, 0.7, 1.0)
	_check("sway: offset changes with time", a != b)


func _test_sway_lean_downwind() -> void:
	# wind_dir = 0 -> east (+X). Lean (2.4px at full wind) always beats the
	# wobble (1.6px), so offset.x must stay positive through the cycle.
	var ok := true
	for i in range(16):
		var off := GrassTufts.sway_offset(Vector2(50, 50), float(i) * 0.7, 0.0, 1.0)
		if off.x <= 0.0:
			ok = false
	_check("sway: lean follows wind_dir (east)", ok)
	# wind_dir = PI/2 -> south (+Y): offset.y stays positive.
	ok = true
	for i in range(16):
		var off := GrassTufts.sway_offset(Vector2(50, 50), float(i) * 0.7, PI * 0.5, 1.0)
		if off.y <= 0.0:
			ok = false
	_check("sway: lean follows wind_dir (south)", ok)


func _test_sway_phase_ripple() -> void:
	# Neighboring tufts must not march in lockstep: different base -> phase
	# differs -> wobble differs.
	var a := GrassTufts.sway_offset(Vector2(0, 0), 5.0, 0.7, 1.0)
	var b := GrassTufts.sway_offset(Vector2(10, 0), 5.0, 0.7, 1.0)
	_check("sway: per-tuft phase ripple", a != b)


func _test_process_clock() -> void:
	var g := GrassTufts.new()
	root.add_child(g)
	var cam := Camera2D.new()
	cam.zoom = Vector2(1, 1)
	root.add_child(cam)
	g.refresh(cam, "high", false)
	_check("sway: visible under high/zoom/no-winter", g.visible)
	g._process(0.5)
	_check("sway: _process advances clock", g._time == 0.5)
	g._process(0.5)
	_check("sway: clock keeps advancing", g._time == 1.0)
	g.free()
	cam.free()


func _test_process_hidden_noop() -> void:
	var g := GrassTufts.new()
	root.add_child(g)
	var cam := Camera2D.new()
	cam.zoom = Vector2(1, 1)
	root.add_child(cam)
	g.refresh(cam, "high", false)
	g.visible = false
	g._process(0.5)
	_check("sway: hidden _process does not advance clock", g._time == 0.0)
	g.free()
	cam.free()


func _test_refresh_gating() -> void:
	var cam := Camera2D.new()
	cam.zoom = Vector2(1, 1)
	root.add_child(cam)
	var g := GrassTufts.new()
	root.add_child(g)
	# Winter kills it (HTML parity).
	g.refresh(cam, "high", true)
	_check("sway: hidden in winter", not g.visible)
	# Low detail kills it.
	g.refresh(cam, "low", false)
	_check("sway: hidden on low detail", not g.visible)
	# Zoomed out kills it (HTML camZoom >= 0.85).
	cam.zoom = Vector2(0.5, 0.5)
	g.refresh(cam, "ultra", false)
	_check("sway: hidden when zoomed out", not g.visible)
	# Ultra + zoomed in + summer shows it.
	cam.zoom = Vector2(1, 1)
	g.refresh(cam, "ultra", false)
	_check("sway: shown on ultra/zoomed/summer", g.visible)
	g.free()
	cam.free()


func _test_read_wind_fake_world() -> void:
	var world := FakeWorld.new()
	var game := FakeGame.new()
	game.seasons = FakeSeasons.new()
	world.game = game
	root.add_child(world)
	var g := GrassTufts.new()
	world.add_child(g)
	g.set_wind(0.0, 0.0)
	g._read_wind()
	_check("sway: reads wind_dir from parent world", g._wind_dir == 1.2)
	_check("sway: reads wind_speed from parent world", g._wind_speed == 1.5)
	world.free()


func _test_read_wind_no_parent_safe() -> void:
	var g := GrassTufts.new()
	g.set_wind(0.9, 1.1)
	g._read_wind()  # no parent: must not crash, keeps override
	_check("sway: no parent keeps override dir", g._wind_dir == 0.9)
	_check("sway: no parent keeps override speed", g._wind_speed == 1.1)
	g.free()
