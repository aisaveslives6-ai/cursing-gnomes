extends SceneTree
## Cursing Gnomes — doomscroller screen-glow FX tests.
## 2026-10-08 (wake graphics-hourly): Milo the Doomscroller shipped with
## bespoke art but a static baked-in phone glow. DoomscrollFX (Body child
## of his UnitNode) adds the living screen: a blue-white glow breathing on
## his face that dips and spikes on every thumb-flick, feed streaks rising
## across the phone screen, and a rare notification ping. Always scrolling
## while Milo lives — no sim toggle.


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


func _initialize() -> void:
	await process_frame
	print("=== Cursing Gnomes Doomscroll FX tests ===")
	_test_standalone_defaults()
	_test_flick_phase_math()
	_test_streak_cycle_math()
	_test_glow_mult_shape()
	await _test_draw_does_not_crash()
	_test_ascii_safe()
	_test_doomscroller_node_builds_fx()
	_test_other_jobs_have_no_fx()
	_test_rebuild_clears_ref()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_standalone_defaults() -> void:
	var fx := DoomscrollFX.new()
	root.add_child(fx)
	_check("fx: default stage_h sane", fx.stage_h > 0.0)
	_check("fx: starts visible (always scrolling)", fx.visible)
	_check("fx: flick phase in [0,1)", fx._flick_phase() >= 0.0 and fx._flick_phase() < 1.0)
	_check("fx: glow multiplier positive", fx._glow_mult() > 0.0)
	fx.free()


func _test_flick_phase_math() -> void:
	var fx := DoomscrollFX.new()
	root.add_child(fx)
	var p0 := fx._flick_phase()
	fx._process(0.45)  # half a tick
	var p1 := fx._flick_phase()
	_check("fx: flick phase advances", absf(p1 - p0) > 0.2)
	fx._process(DoomscrollFX.SCROLL_TICK)
	# One full tick wraps back near the start.
	_check("fx: flick phase wraps after one tick",
		absf(fx._flick_phase() - p1) < 0.05)
	fx.free()


func _test_streak_cycle_math() -> void:
	var fx := DoomscrollFX.new()
	root.add_child(fx)
	var c0 := fx._streak_cycle(0)
	_check("fx: streak cycle in [0,1)", c0 >= 0.0 and c0 < 1.0)
	var c1 := fx._streak_cycle(1)
	_check("fx: streaks desynced", absf(c1 - c0) > 0.01)
	fx._process(0.2)
	var c_mid := fx._streak_cycle(0)
	_check("fx: streak cycle advances", absf(c_mid - c0) > 0.01)
	fx._process(DoomscrollFX.STREAK_CYCLE)
	_check("fx: streak cycle wraps after one period",
		absf(fx._streak_cycle(0) - c_mid) < 0.05)
	fx.free()


func _test_glow_mult_shape() -> void:
	var fx := DoomscrollFX.new()
	root.add_child(fx)
	# Start off the ping window (a ping fires at _t=0 and would inflate
	# the baseline): at _t=1.8 the flick phase is ~0 (deepest dip).
	fx._t = 1.8
	var m0 := fx._glow_mult()
	fx._process(DoomscrollFX.SCROLL_TICK * 0.5)
	var m1 := fx._glow_mult()
	_check("fx: glow recovers after the flick dip", m1 > m0)
	# Ping flash: just before a period boundary the multiplier is calm.
	fx._t = DoomscrollFX.PING_PERIOD - 0.5
	var calm := fx._glow_mult()
	fx._t = DoomscrollFX.PING_PERIOD + 0.01
	var ping := fx._glow_mult()
	_check("fx: notification ping flashes brighter", ping > calm + 0.2)
	fx.free()


func _test_draw_does_not_crash() -> void:
	var fx := DoomscrollFX.new()
	root.add_child(fx)
	fx.stage_h = 80.0
	for i in 12:
		fx._process(0.15)
	fx.queue_redraw()
	await process_frame
	_check("fx: engine-driven _draw runs clean", true)
	# Zero stage_h must stay silent (guard, no div-by-zero art).
	fx.stage_h = 0.0
	fx._process(0.1)
	fx.queue_redraw()
	await process_frame
	_check("fx: zero stage_h draws nothing, no crash", true)
	fx.free()


func _test_ascii_safe() -> void:
	# Jeremy's iPhone tofu rule: no glyph/emoji anywhere in the FX source.
	var src := FileAccess.get_file_as_string(
		"res://scripts/world/doomscroll_fx.gd")
	var bad := 0
	for i in src.length():
		if src.unicode_at(i) > 0x2500:
			bad += 1
	_check("fx: source ASCII-only (no tofu risk)", bad == 0)


func _make_node(p_job: String) -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(700 + _passed, "gnomes", p_job, Vector2(100, 100), "m")
	return un


func _test_doomscroller_node_builds_fx() -> void:
	var un := _make_node("doomscroller")
	_check("doomscroller: screen-glow FX built",
		un._doomscroll_fx != null and is_instance_valid(un._doomscroll_fx))
	_check("doomscroller: FX is a Body child",
		un._doomscroll_fx != null and un._doomscroll_fx.get_parent() == un._body)
	_check("doomscroller: FX stage_h matches monster scale",
		un._doomscroll_fx != null
		and absf(un._doomscroll_fx.stage_h - un._monster_scale()) < 0.01)
	_check("doomscroller: FX renders above the sprite",
		un._doomscroll_fx != null and un._sprite != null
		and un._doomscroll_fx.z_index > un._sprite.z_index)
	un.free()


func _test_other_jobs_have_no_fx() -> void:
	for j in ["karaoke_barbarian", "booze_ooze", "seagull_swarm", "worker", "mlm_bro"]:
		var un := _make_node(j)
		_check("no-fx job %s: no doomscroll FX" % j, un._doomscroll_fx == null)
		un.free()


func _test_rebuild_clears_ref() -> void:
	var un := _make_node("doomscroller")
	var old_fx: DoomscrollFX = un._doomscroll_fx
	_check("rebuild: FX present before rebuild", old_fx != null)
	un._build()
	# Rebuild frees the old Body subtree: the ref must not dangle —
	# _build recreates the rig for the still-doomscroller job.
	_check("rebuild: ref points at a fresh live instance",
		un._doomscroll_fx != null and is_instance_valid(un._doomscroll_fx)
		and un._doomscroll_fx != old_fx)
	un.free()
