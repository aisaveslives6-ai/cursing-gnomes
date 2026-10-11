extends SceneTree
## Cursing Gnomes — MLM bro opportunity-sparkles FX tests.
## 2026-10-08 (wake rapid-iteration): Chad the MLM Bro shipped with bespoke
## art but an invisible pitch. MLMBroFX (Body child of his UnitNode) adds the
## visible opportunity: golden sparkle motes rising off the briefcase, a
## pitch-pulse ring expanding on every aura cadence (MLM_AURA_CD), and a
## periodic briefcase "diamond shimmer" glint. Always pitching while Chad
## lives — no sim toggle.


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
	print("=== Cursing Gnomes MLM Bro FX tests ===")
	_test_standalone_defaults()
	_test_spark_cycle_math()
	_test_ring_shape()
	_test_glint()
	await _test_draw_does_not_crash()
	_test_ascii_safe()
	_test_mlm_node_builds_fx()
	_test_other_jobs_have_no_fx()
	_test_rebuild_clears_ref()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_standalone_defaults() -> void:
	var fx := MLMBroFX.new()
	root.add_child(fx)
	_check("fx: default stage_h sane", fx.stage_h > 0.0)
	_check("fx: starts visible (always pitching)", fx.visible)
	_check("fx: spark cycle in [0,1)",
		fx._spark_cycle(0) >= 0.0 and fx._spark_cycle(0) < 1.0)
	_check("fx: ring phase in [0,1)",
		fx._ring_phase() >= 0.0 and fx._ring_phase() < 1.0)
	_check("fx: ring radius positive", fx._ring_radius() > 0.0)
	fx.free()


func _test_spark_cycle_math() -> void:
	var fx := MLMBroFX.new()
	root.add_child(fx)
	var c0 := fx._spark_cycle(0)
	var c1 := fx._spark_cycle(1)
	_check("fx: sparks desynced", absf(c1 - c0) > 0.01)
	fx._process(0.3)
	var c_mid := fx._spark_cycle(0)
	_check("fx: spark cycle advances", absf(c_mid - c0) > 0.01)
	fx._process(MLMBroFX.SPARK_CYCLE)
	_check("fx: spark cycle wraps after one period",
		absf(fx._spark_cycle(0) - c_mid) < 0.05)
	# Sparks rise: later in the cycle the mote sits higher (smaller y).
	fx._t = 0.0
	var y0 := fx._spark_pos(0, 60.0).y
	fx._t = MLMBroFX.SPARK_CYCLE * 0.5
	var y1 := fx._spark_pos(0, 60.0).y
	_check("fx: sparks rise as the cycle advances", y1 < y0)
	fx.free()


func _test_ring_shape() -> void:
	var fx := MLMBroFX.new()
	root.add_child(fx)
	# The pitch pulse expands: mid-tick radius exceeds the just-born ring.
	fx._t = 0.0
	var r0 := fx._ring_radius()
	fx._t = MLMBroFX.PITCH_TICK * 0.5
	var r1 := fx._ring_radius()
	_check("fx: pitch ring expands over the tick", r1 > r0)
	# One full tick wraps back near the start radius.
	fx._t = MLMBroFX.PITCH_TICK
	var r2 := fx._ring_radius()
	_check("fx: pitch ring wraps after one period", absf(r2 - r0) < 0.5)
	# Ring is pitch-sized, not aura-sized: a visible pulse, not a 240px halo.
	fx._t = MLMBroFX.PITCH_TICK * 0.99
	_check("fx: max ring stays near the body (no aura-size halo)",
		fx._ring_radius() < fx.stage_h * 1.5)
	fx.free()


func _test_glint() -> void:
	var fx := MLMBroFX.new()
	root.add_child(fx)
	# Silent mid-period, flashing right after a period boundary.
	fx._t = MLMBroFX.GLINT_PERIOD * 0.5
	_check("fx: glint silent mid-period", fx._glint_alpha() == 0.0)
	fx._t = MLMBroFX.GLINT_PERIOD + 0.01
	_check("fx: briefcase glints after the boundary",
		fx._glint_alpha() > 0.5)
	fx.free()


func _test_draw_does_not_crash() -> void:
	var fx := MLMBroFX.new()
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
		"res://scripts/world/mlm_bro_fx.gd")
	var bad := 0
	for i in src.length():
		if src.unicode_at(i) > 0x2500:
			bad += 1
	_check("fx: source ASCII-only (no tofu risk)", bad == 0)


func _make_node(p_job: String) -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(900 + _passed, "gnomes", p_job, Vector2(100, 100), "m")
	return un


func _test_mlm_node_builds_fx() -> void:
	var un := _make_node("mlm_bro")
	_check("mlm_bro: opportunity-sparkles FX built",
		un._mlm_fx != null and is_instance_valid(un._mlm_fx))
	_check("mlm_bro: FX is a Body child",
		un._mlm_fx != null and un._mlm_fx.get_parent() == un._body)
	_check("mlm_bro: FX stage_h matches monster scale",
		un._mlm_fx != null
		and absf(un._mlm_fx.stage_h - un._monster_scale()) < 0.01)
	_check("mlm_bro: FX renders above the sprite",
		un._mlm_fx != null and un._sprite != null
		and un._mlm_fx.z_index > un._sprite.z_index)
	_check("mlm_bro: no doomscroll FX leaks in",
		un._doomscroll_fx == null)
	un.free()


func _test_other_jobs_have_no_fx() -> void:
	for j in ["doomscroller", "karaoke_barbarian", "worker",
			"warranty_salesman", "dmv_clerk"]:
		var un := _make_node(j)
		_check("no-fx job %s: no MLM sparkles" % j, un._mlm_fx == null)
		un.free()


func _test_rebuild_clears_ref() -> void:
	var un := _make_node("mlm_bro")
	var old_fx: MLMBroFX = un._mlm_fx
	_check("rebuild: FX present before rebuild", old_fx != null)
	un._build()
	# Rebuild frees the old Body subtree: the ref must not dangle —
	# _build recreates the rig for the still-MLM job.
	_check("rebuild: ref points at a fresh live instance",
		un._mlm_fx != null and is_instance_valid(un._mlm_fx)
		and un._mlm_fx != old_fx)
	un.free()
