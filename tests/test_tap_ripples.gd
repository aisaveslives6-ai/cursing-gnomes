extends SceneTree
## Cursing Gnomes — tap ripple touch-feedback tests (graphics-hourly 2026-10-05).
##
## Ports HTML pushTapRipple / tickTapRipples / drawTapRipples (fix79
## index.html ~line 2914400): every world tap answers with a visible gold
## ring (fluid, alive). Verifies the HTML-verbatim math (life 0.45, cap 12,
## k = 1 - life/max, alpha 0.75*(1-k), lineWidth 3*(1-k)+1, radius 8+k*34,
## stroke #ffe082, inView 60px margin) plus the Godot improvements
## (inner echo ring math, idle hide/process disable).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tap_ripples.gd
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


func _test_draw_params() -> void:
	# Birth (life = max): k = 0 -> full alpha, radius 8, width 4.
	var p0 := TapRipples.draw_params(TapRipples.RIPPLE_LIFE)
	_check("params: birth k = 0", _approx(float(p0["k"]), 0.0))
	_check("params: birth alpha 0.75", _approx(float(p0["alpha"]), 0.75))
	_check("params: birth radius 8", _approx(float(p0["radius"]), 8.0))
	_check("params: birth width 4", _approx(float(p0["width"]), 4.0))
	# Death (life = 0): k = 1 -> invisible, radius 42, width 1.
	var p1 := TapRipples.draw_params(0.0)
	_check("params: death k = 1", _approx(float(p1["k"]), 1.0))
	_check("params: death alpha 0", _approx(float(p1["alpha"]), 0.0))
	_check("params: death radius 42", _approx(float(p1["radius"]), 42.0))
	_check("params: death width 1", _approx(float(p1["width"]), 1.0))
	# Midpoint (life = max/2): k = 0.5.
	var pm := TapRipples.draw_params(TapRipples.RIPPLE_LIFE * 0.5)
	_check("params: mid k = 0.5", _approx(float(pm["k"]), 0.5))
	_check("params: mid alpha 0.375", _approx(float(pm["alpha"]), 0.375))
	_check("params: mid radius 25", _approx(float(pm["radius"]), 25.0))
	_check("params: mid width 2.5", _approx(float(pm["width"]), 2.5))
	# Monotone progressions.
	_check("params: radius grows, width shrinks, alpha fades",
		float(p0["radius"]) < float(pm["radius"])
		and float(pm["radius"]) < float(p1["radius"])
		and float(p0["width"]) > float(pm["width"])
		and float(pm["width"]) > float(p1["width"])
		and float(p0["alpha"]) > float(pm["alpha"])
		and float(pm["alpha"]) > float(p1["alpha"]))
	# Clamp: negative life saturates at death state.
	var pc := TapRipples.draw_params(-1.0)
	_check("params: negative life clamps k to 1",
		_approx(float(pc["k"]), 1.0) and _approx(float(pc["alpha"]), 0.0))


func _test_html_constants() -> void:
	_check("const: RIPPLE_LIFE 0.45 (HTML)", _approx(TapRipples.RIPPLE_LIFE, 0.45))
	_check("const: MAX_RIPPLES 12 (HTML)", TapRipples.MAX_RIPPLES == 12)
	_check("const: stroke color #ffe082 (HTML)",
		TapRipples.RING_COL == Color8(0xff, 0xe0, 0x82))
	_check("const: start radius 8, grow 34 (HTML)",
		_approx(TapRipples.START_RADIUS, 8.0)
		and _approx(TapRipples.RADIUS_GROW, 34.0))
	_check("const: width 3*(1-k)+1 (HTML)",
		_approx(TapRipples.START_WIDTH, 1.0)
		and _approx(TapRipples.WIDTH_SHRINK, 3.0)
		and _approx(TapRipples.START_WIDTH + TapRipples.WIDTH_SHRINK, 4.0))
	_check("const: max alpha 0.75 (HTML)", _approx(TapRipples.MAX_ALPHA, 0.75))
	_check("const: view margin 60 (HTML inView)", _approx(TapRipples.VIEW_MARGIN, 60.0))


func _test_push_cap() -> void:
	var layer := TapRipples.new()
	_check("starts with zero ripples", layer.ripple_count() == 0)
	layer.push(Vector2(10, 20))
	_check("push adds one ripple", layer.ripple_count() == 1)
	var r: Dictionary = layer._ripples[0]
	_check("pushed ripple stores world pos", (r["pos"] as Vector2) == Vector2(10, 20))
	_check("pushed ripple starts at full life",
		_approx(float(r["life"]), TapRipples.RIPPLE_LIFE))
	# Overflow: oldest dropped first.
	for i in range(TapRipples.MAX_RIPPLES):
		layer.push(Vector2(100 + i, 200))
	_check("cap holds at MAX_RIPPLES", layer.ripple_count() == TapRipples.MAX_RIPPLES)
	var oldest: Dictionary = layer._ripples[0]
	_check("oldest entry evicted first", (oldest["pos"] as Vector2) == Vector2(100, 200))
	layer.free()


func _test_lifecycle() -> void:
	var layer := TapRipples.new()
	layer.push(Vector2(0, 0))
	_check("push wakes processing", layer.is_processing())
	layer._process(0.1)
	_check("tick drains life",
		_approx(float((layer._ripples[0] as Dictionary)["life"]),
			TapRipples.RIPPLE_LIFE - 0.1))
	_check("still alive at 0.35s of life", layer.ripple_count() == 1)
	# HTML splices when life <= 0; 0.45 total = 0.1 + 0.35.
	layer._process(0.35)
	_check("dies when life hits zero", layer.ripple_count() == 0)
	_check("idle disables processing", not layer.is_processing())
	_check("idle hides the node", not layer.visible)
	layer.push(Vector2(5, 5))
	_check("re-push re-enables processing", layer.is_processing())
	_check("re-push shows the node again", layer.visible)
	# Mixed ages: dead removed, live kept.
	layer._process(0.2)
	layer.push(Vector2(6, 6))
	layer._process(0.25)  # first ripple now dead, second alive
	_check("mixed ages: only dead removed", layer.ripple_count() == 1)
	_check("survivor is the second push",
		((layer._ripples[0] as Dictionary)["pos"] as Vector2) == Vector2(6, 6))
	layer.free()


func _test_node_basics() -> void:
	var layer := TapRipples.new()
	_check("z_index above units/props (0)", layer.z_index == 50)
	_check("camera unset by default", layer._camera == null)
	_check("visible rect empty without camera", layer._visible_rect() == Rect2())
	var cam := Camera2D.new()
	layer.set_camera(cam)
	_check("set_camera stores camera", layer._camera == cam)
	cam.free()
	layer.free()


func _initialize() -> void:
	_test_draw_params()
	_test_html_constants()
	_test_push_cap()
	_test_lifecycle()
	_test_node_basics()
	print("tap_ripples: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("FAILURES: ", _failures)
	quit(1 if _failed > 0 else 0)
