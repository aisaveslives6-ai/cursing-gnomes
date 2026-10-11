extends SceneTree
## Cursing Gnomes — hero destination marker tests (graphics-hourly 2026-10-05).
##
## Ports HTML drawHeroDestMarker (fix79 index.html:49584): a yellow X
## (stroke '#ffeb3b', lineWidth 3, arms ±10px) inside a circle (r 8) at the
## hero's ordered destination, alpha = min(1, life), life 1.2 s, inView 20px
## cull. Verifies the HTML-verbatim math plus the Godot improvements
## (attack-kind red marker, spawn pop, single-marker replace, idle hide).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hero_dest_marker.gd
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


func _test_constants() -> void:
	# HTML-verbatim numbers.
	_check("const: life 1.2", _approx(HeroDestMarker.MARK_LIFE, 1.2))
	_check("const: X half 10", _approx(HeroDestMarker.X_HALF, 10.0))
	_check("const: circle r 8", _approx(HeroDestMarker.CIRCLE_R, 8.0))
	_check("const: line width 3", _approx(HeroDestMarker.LINE_W, 3.0))
	_check("const: move color #ffeb3b",
		HeroDestMarker.MOVE_COL == Color8(0xff, 0xeb, 0x3b))
	_check("const: view margin 20", _approx(HeroDestMarker.VIEW_MARGIN, 20.0))


func _test_draw_params() -> void:
	# Birth (life = max): alpha 1, pop starts at 0.6.
	var p0 := HeroDestMarker.draw_params(HeroDestMarker.MARK_LIFE)
	_check("params: birth alpha 1", _approx(float(p0["alpha"]), 1.0))
	_check("params: birth pop 0.6", _approx(float(p0["pop"]), 0.6))
	# Mid-life (life = 1.0): alpha still 1 (min(1, life)), pop done.
	var pm := HeroDestMarker.draw_params(1.0)
	_check("params: mid alpha 1", _approx(float(pm["alpha"]), 1.0))
	_check("params: mid pop 1.0", _approx(float(pm["pop"]), 1.0))
	# Fade zone (life = 0.4): alpha 0.4.
	var pf := HeroDestMarker.draw_params(0.4)
	_check("params: fade alpha = life", _approx(float(pf["alpha"]), 0.4))
	# Death (life = 0): alpha 0.
	var p1 := HeroDestMarker.draw_params(0.0)
	_check("params: death alpha 0", _approx(float(p1["alpha"]), 0.0))
	# Clamp: life above max can't exceed alpha 1.
	var pc := HeroDestMarker.draw_params(99.0)
	_check("params: alpha clamped to 1", _approx(float(pc["alpha"]), 1.0))
	# Pop midpoint: at age 0.06 (half of 0.12), pop = 0.8.
	var pp := HeroDestMarker.draw_params(HeroDestMarker.MARK_LIFE - 0.06)
	_check("params: pop blooms 0.6 -> 1.0", _approx(float(pp["pop"]), 0.8))


func _test_colors() -> void:
	_check("color: move is yellow",
		HeroDestMarker.color_for("move") == HeroDestMarker.MOVE_COL)
	_check("color: attack is red",
		HeroDestMarker.color_for("attack") == HeroDestMarker.ATTACK_COL)
	_check("color: unknown falls back to move",
		HeroDestMarker.color_for("bogus") == HeroDestMarker.MOVE_COL)


func _mk() -> HeroDestMarker:
	var m := HeroDestMarker.new()
	root.add_child(m)
	return m


func _test_push_and_lifecycle() -> void:
	var m := _mk()
	_check("push: no marker initially", not m.has_marker())
	m.push(Vector2(100, 200), "move")
	_check("push: marker present", m.has_marker())
	_check("push: visible while alive", m.visible)
	m.push(Vector2(300, 400), "move")
	_check("push: single marker replaces (pos updated)",
		(m._marker as Dictionary).get("pos") == Vector2(300, 400))
	# Tick half the life: still alive.
	for i in range(30):
		m._process(0.02)
	_check("tick: alive at half life", m.has_marker())
	# Tick past death: gone, idle cost disabled.
	for i in range(40):
		m._process(0.02)
	_check("tick: dead after life expires", not m.has_marker())
	_check("tick: hidden when idle", not m.visible)
	_check("tick: process disabled when idle", not m.is_processing())
	# Re-push after death works.
	m.push(Vector2(1, 1), "attack")
	_check("push: re-push after death works", m.has_marker())
	_check("push: attack kind stored",
		String((m._marker as Dictionary).get("kind")) == "attack")
	# Bogus kind normalizes to move.
	m.push(Vector2(2, 2), "nope")
	_check("push: bogus kind -> move",
		String((m._marker as Dictionary).get("kind")) == "move")
	m.queue_free()


func _test_z_index() -> void:
	var m := HeroDestMarker.new()
	_check("node: z_index 60 (above tap ripples at 50)", m.z_index == 60)
	m.free()


func _init() -> void:
	_test_constants()
	_test_draw_params()
	_test_colors()
	_test_push_and_lifecycle()
	_test_z_index()
	print("hero_dest_marker: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("  - ", f)
		quit(1)
	else:
		quit(0)
