extends SceneTree
## Cursing Gnomes — cinematic loading-screen remake tests (Jeremy 2026-10-10:
## "buggy as hell, completely redo it").
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_loading_screen.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
##
## Covers the remake:
##  - screen is a top CanvasLayer, animates through the boot freeze
##  - studio card const present; intro is skippable via tap
##  - set_progress is REAL: clamps, is monotonic (never runs backwards),
##    labels track; the painted fill lerps toward it (never snaps)
##  - bind_world poll backup drives progress with NO signal connected
##  - tips come from the MENU_TIPS pool, never repeat back-to-back
##  - finish() is idempotent, completes the fade and frees the screen
##  - safe insets are headless-safe
##  - BootScene logic: back-ease, camera sweep, bounded particles
##  - World's staged boot still emits monotonic stages + boot_finished
##    (the real-progress plumbing the screen reads)


const _LS := preload("res://scripts/ui/loading_screen.gd")


class FakeWorld extends Node:
	var boot_frac := 0.0
	var boot_label := "test"
	var booted := false


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _frame: int = 0
var _phase: int = 0
var _screen: LoadingScreen = null
var _world: Node = null
var _stages: Array = []
var _finished := false


func _initialize() -> void:
	print("=== Cursing Gnomes loading-screen remake tests ===")
	_screen = _LS.new()
	root.add_child(_screen)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _run_ui_tests() -> void:
	_check("screen is a CanvasLayer above the menu", _screen.layer >= 200)
	_check("screen animates through the boot freeze",
		_screen.process_mode == Node.PROCESS_MODE_ALWAYS)
	_check("studio card name present", LoadingScreen.STUDIO_NAME != "")
	_check("title const intact", LoadingScreen._TITLE == "CURSING GNOMES")
	_check("scene node built", _screen._scene != null)
	_check("scene has a font (HD text)", _screen._scene._font != null)
	_check("progress labels built",
		_screen._stage_lbl != null and _screen._pct_lbl != null
		and _screen._tip_lbl != null)
	_check("bar rect laid out", _screen._scene.bar_rect.size.x > 100.0)

	# Intro skip: a tap during the studio card jumps to the reveal.
	_screen._t = 0.5
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	_screen._unhandled_input(ev)
	_check("tap skips the studio card", _screen._skipped_intro)
	_screen._process(0.016)
	_check("skip jumps to the reveal", _screen._t >= LoadingScreen._T_STUDIO)

	# Real progress: clamps, monotonic, labels track.
	_screen.set_progress(0.5, "Carving the land…")
	_check("frac tracks real progress", is_equal_approx(_screen._frac, 0.5))
	_check("percent label tracks", _screen._pct_lbl.text == "50%")
	_check("stage label tracks", _screen._stage_lbl.text == "Carving the land…")
	_screen.set_progress(0.3, "earlier")
	_check("bar never runs backwards", is_equal_approx(_screen._frac, 0.5))
	_check("stage keeps the latest label",
		_screen._stage_lbl.text == "earlier")
	_screen.set_progress(1.25, "x")
	_check("frac clamps at 1.0", is_equal_approx(_screen._frac, 1.0))
	_screen.set_progress(-0.5, "x")
	_check("frac never drops below peak", is_equal_approx(_screen._frac, 1.0))
	# Fresh screen for the lerp/poll checks below.
	_screen.queue_free()
	_screen = _LS.new()
	root.add_child(_screen)

	# Painted fill lerps toward real progress (never snaps).
	_screen.set_progress(0.8, "Working…")
	_check("fill starts below target", _screen._bar_shown < 0.8)
	_screen._process(0.5)
	_check("fill chases target",
		_screen._bar_shown > 0.0 and _screen._bar_shown <= 0.8)
	for i: int in 10:
		_screen._process(0.5)
	_check("fill converges", is_equal_approx(_screen._bar_shown, 0.8))

	# Poll backup: NO signal connected, the world object alone drives it.
	var fake := FakeWorld.new()
	root.add_child(fake)
	_screen.bind_world(fake)
	fake.boot_frac = 0.42
	fake.boot_label = "Waking the gnomes…"
	_screen._process(0.016)
	_check("poll backup reads boot_frac",
		is_equal_approx(_screen._frac, 0.8)) # monotonic: keeps the peak
	fake.boot_frac = 0.9
	_screen._process(0.016)
	_check("poll backup advances the bar",
		is_equal_approx(_screen._frac, 0.9))
	_check("poll backup reads boot_label",
		_screen._stage_lbl.text.begins_with("Waking the gnomes"))
	fake.booted = true
	_screen._process(0.016)
	_check("poll backup notices boot completion",
		_screen._frac >= 0.88)
	# Freed world unbinds itself — no crash.
	fake.free() # immediate: queue_free defers past the manual _process call
	_screen._process(0.016)
	_check("dead world unbinds cleanly", _screen._world == null)

	# Tips: from the pool, never back-to-back.
	_check("tip label has a tip", _screen._tip_lbl.text.begins_with("TIP:"))
	var prev := ""
	var repeated := false
	var in_pool := true
	for i: int in 14:
		_screen._rotate_tip()
		var tip: String = _screen._tip_lbl.text
		if tip == prev:
			repeated = true
		if not tip.begins_with("TIP:"):
			in_pool = false
		prev = tip
	_check("all rotated tips from the MENU_TIPS pool", in_pool)
	_check("no back-to-back tip repeats", not repeated)

	# Headless DisplayServer has no safe area — must not crash.
	var ins: Vector4 = _screen._safe_insets(Vector2(1170, 2532))
	_check("safe insets return a Vector4", ins is Vector4)

	# BootScene pure logic.
	var bs: _LS.BootScene = _screen._scene
	_check("back-ease starts at 0", is_equal_approx(bs._back_ease(0.0), 0.0))
	_check("back-ease ends at 1", is_equal_approx(bs._back_ease(1.0), 1.0))
	_check("back-ease overshoots (weight)",
		bs._back_ease(0.7) > 1.0)
	bs.t = LoadingScreen._T_STUDIO
	var cam0 := bs._cam(1.0)
	bs.t = LoadingScreen._T_STUDIO + LoadingScreen._T_SWEEP
	var cam1 := bs._cam(1.0)
	_check("camera sweep travels", cam0 < cam1)
	_check("camera settles near zero", absf(cam1) < 1.0)
	bs.tick(0.016, Vector2(1170, 2532))
	_check("tick advances marchers", bs._march[0] > 0.14)
	_check("particle arrays bounded",
		bs._smoke.size() <= 24 and bs._dust.size() <= 16)
	# Portrait phone layout: dune top stays clear of the progress UI so
	# the hero gnome never ends up behind the bar.
	bs.bar_rect = Rect2(43, 687, 304, 20)
	var dt := bs._dune_top(Vector2(390, 844), 0.75)
	_check("dune clears the progress bar", dt + 86.0 * 0.75 < 687.0)
	bs.bar_rect = Rect2()
	_check("dune defaults to 0.80H",
		is_equal_approx(bs._dune_top(Vector2(1280, 800), 1.0), 640.0))

	# Drive frames so _draw() executes on the dummy renderer (would print
	# SCRIPT ERROR on any bad draw call — checked in the gate output).
	_screen._t = 3.0
	for i: int in 5:
		_screen._process(0.016)
	_check("screen survives frames", is_instance_valid(_screen))

	# finish(): idempotent, completes the fade, frees.
	# NOTE: queue_free() only deletes at frame end, so the fade-out is
	# verified across REAL frames in _process (phase 1), not here.
	_screen.finish()
	_screen.finish() # second call must be a no-op
	_check("finish marks finishing", _screen._finishing)
	_check("finish sets full bar", is_equal_approx(_screen._frac, 1.0))
	_phase = 1 # _process watches the fade complete, then boots the world


func _start_staged_boot() -> void:
	var ps: PackedScene = load("res://scenes/world/world.tscn")
	_check("world scene loads", ps != null)
	if ps == null:
		print("=== %d passed, %d failed ===" % [_passed, _failed])
		quit(1)
		return
	_world = ps.instantiate()
	_world.set("staged_boot", true)
	_world.boot_progress.connect(_on_stage)
	_world.boot_finished.connect(_on_finished)
	root.add_child(_world)


func _on_stage(frac: float, label: String) -> void:
	_stages.append([frac, label])


func _on_finished() -> void:
	_finished = true


func _finish_boot_tests() -> void:
	_check("staged boot finished", _finished)
	_check("booted flag set", bool(_world.get("booted")))
	_check("tree unpaused after boot", not paused)
	_check("stage signals fired", _stages.size() >= 6)
	var mono := true
	var last := -1.0
	for s: Array in _stages:
		if float(s[0]) < last - 0.0001:
			mono = false
		last = float(s[0])
	_check("stage fracs monotonic", mono)
	_check("final stage frac is 1.0", is_equal_approx(float(_stages.back()[0]), 1.0))
	var labels: Array[String] = []
	for s: Array in _stages:
		labels.append(str(s[1]))
	_check("land stage labeled", labels.has("Carving the land…"))
	_check("world fully booted (game)", _world.get("game") != null)
	_check("world fully booted (map)", not (_world.get("map_data") as Dictionary).is_empty())
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _process(_delta: float) -> bool:
	_frame += 1
	if _phase == 0 and _frame >= 2:
		_run_ui_tests() # ends with finish(); _phase = 1
	elif _phase == 1:
		# The finish fade runs on real frames (queue_free deletes at frame
		# end). Once the screen is gone, the fade completed: verify, then
		# boot the world.
		if not is_instance_valid(_screen):
			_check("screen freed after finish fade", true)
			_screen = null
			_start_staged_boot()
			_phase = 2
		elif _frame > 1500:
			_check("screen freed after finish fade", false)
			_screen = null
			_start_staged_boot()
			_phase = 2
	elif _phase == 2 and (_finished or _frame > 1500):
		_phase = 3
		_finish_boot_tests()
		return true
	return false
