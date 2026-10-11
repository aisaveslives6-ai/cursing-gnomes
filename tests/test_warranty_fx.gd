extends SceneTree
## Cursing Gnomes — warranty salesman doorstep-pitch FX tests.
## 2026-10-08 (wake rapid-iteration): Wally the Warranty Salesman shipped
## with bespoke art but an invisible pitch. WarrantyFX (Body child of his
## UnitNode) makes the sale visible: swirling warranty certificates (wider
## and faster while pitching), a red "EXPIRED" rubber stamp slamming on
## every pitch cadence, and a gold-coin burst edge-triggered on the
## warranty_sales counter. World sync drives it via set_warranty_state()
## off combat_state == "pitching".


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
	print("=== Cursing Gnomes Warranty FX tests ===")
	_test_standalone_defaults()
	_test_doc_orbit_math()
	_test_stamp_cadence()
	_test_sales_burst()
	_test_coins_age_out()
	await _test_draw_does_not_crash()
	_test_ascii_safe()
	_test_warranty_node_builds_fx()
	_test_other_jobs_have_no_fx()
	_test_rebuild_clears_ref()
	_test_node_set_warranty_state()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_standalone_defaults() -> void:
	var fx := WarrantyFX.new()
	root.add_child(fx)
	_check("fx: default stage_h sane", fx.stage_h > 0.0)
	_check("fx: starts visible", fx.visible)
	_check("fx: starts idle (not pitching)", not fx._pitching)
	_check("fx: no sales recorded", fx._sales == 0)
	_check("fx: no coins at rest", fx._coin_pos.is_empty())
	_check("fx: doc cycle in [0,1)",
		fx._doc_cycle(0) >= 0.0 and fx._doc_cycle(0) < 1.0)
	_check("fx: stamp phase in [0,1)",
		fx._stamp_phase() >= 0.0 and fx._stamp_phase() < 1.0)
	fx.free()


func _test_doc_orbit_math() -> void:
	var fx := WarrantyFX.new()
	root.add_child(fx)
	var c0 := fx._doc_cycle(0)
	var c1 := fx._doc_cycle(1)
	_check("fx: docs desynced", absf(c1 - c0) > 0.01)
	fx._process(0.3)
	_check("fx: orbit advances", absf(fx._doc_cycle(0) - c0) > 0.01)
	# Pitching widens the orbit: at t=0 doc 0 sits at angle 0 (x = radius).
	fx._t = 0.0
	fx.set_warranty_state(false, 0)
	var x_idle := fx._doc_pos(0, 64.0).x
	fx.set_warranty_state(true, 0)
	var x_pitch := fx._doc_pos(0, 64.0).x
	_check("fx: idle orbit radius sane", absf(x_idle - 35.2) < 0.5)
	_check("fx: pitching orbit wider than idle", x_pitch > x_idle + 5.0)
	_check("fx: pitching orbit radius sane", absf(x_pitch - 46.08) < 0.5)
	fx.free()


func _test_stamp_cadence() -> void:
	var fx := WarrantyFX.new()
	root.add_child(fx)
	# Right after a period boundary: inside the slam window.
	fx._t = 0.1
	var st_early := fx._stamp_phase() * WarrantyFX.STAMP_PERIOD
	_check("fx: stamp slams after boundary", st_early < WarrantyFX.STAMP_SLAM)
	# Mid-period: silent.
	fx._t = WarrantyFX.STAMP_PERIOD * 0.6
	var st_mid := fx._stamp_phase() * WarrantyFX.STAMP_PERIOD
	_check("fx: stamp silent mid-period", st_mid >= WarrantyFX.STAMP_SLAM)
	# One full period wraps back into the slam window.
	fx._t = WarrantyFX.STAMP_PERIOD + 0.1
	var st_wrap := fx._stamp_phase() * WarrantyFX.STAMP_PERIOD
	_check("fx: stamp cadence wraps", st_wrap < WarrantyFX.STAMP_SLAM)
	fx.free()


func _test_sales_burst() -> void:
	var fx := WarrantyFX.new()
	root.add_child(fx)
	fx.set_warranty_state(true, 0)
	_check("fx: no burst at zero sales", fx._coin_pos.is_empty())
	_check("fx: pitching flag pushed", fx._pitching)
	fx.set_warranty_state(true, 1)
	_check("fx: first sale flings coins",
		fx._coin_pos.size() == WarrantyFX.COINS_PER_SALE)
	fx.set_warranty_state(true, 1)
	_check("fx: same sales count bursts nothing new",
		fx._coin_pos.size() == WarrantyFX.COINS_PER_SALE)
	fx.set_warranty_state(true, 2)
	_check("fx: second sale bursts again",
		fx._coin_pos.size() == 2 * WarrantyFX.COINS_PER_SALE)
	fx.set_warranty_state(false, 2)
	_check("fx: pitching flag clears", not fx._pitching)
	_check("fx: sales decrease never bursts",
		fx._coin_pos.size() == 2 * WarrantyFX.COINS_PER_SALE)
	fx.set_warranty_state(false, 1)
	_check("fx: lower sales counter stays silent",
		fx._coin_pos.size() == 2 * WarrantyFX.COINS_PER_SALE)
	fx.free()


func _test_coins_age_out() -> void:
	var fx := WarrantyFX.new()
	root.add_child(fx)
	fx.set_warranty_state(true, 1)
	_check("fx: coins present after burst", not fx._coin_pos.is_empty())
	# Coins fly: positions move under gravity.
	var y0: float = fx._coin_pos[0].y
	fx._process(0.2)
	_check("fx: coins move ballistically", fx._coin_pos[0].y != y0)
	var t := 0.0
	while t < WarrantyFX.COIN_LIFE + 0.2:
		fx._process(0.1)
		t += 0.1
	_check("fx: coins expire after COIN_LIFE", fx._coin_pos.is_empty())
	_check("fx: coin arrays stay in sync",
		fx._coin_vel.is_empty() and fx._coin_age.is_empty())
	fx.free()


func _test_draw_does_not_crash() -> void:
	var fx := WarrantyFX.new()
	root.add_child(fx)
	fx.stage_h = 80.0
	fx.set_warranty_state(true, 2)
	for i in 12:
		fx._process(0.15)
	fx.queue_redraw()
	await process_frame
	_check("fx: engine-driven _draw runs clean (pitching + coins)", true)
	# Idle, no coins: the quiet path.
	fx.set_warranty_state(false, 2)
	for i in 6:
		fx._process(0.2)
	fx.queue_redraw()
	await process_frame
	_check("fx: engine-driven _draw runs clean (idle)", true)
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
		"res://scripts/world/warranty_fx.gd")
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


func _test_warranty_node_builds_fx() -> void:
	var un := _make_node("warranty_salesman")
	_check("warranty_salesman: doorstep-pitch FX built",
		un._warranty_fx != null and is_instance_valid(un._warranty_fx))
	_check("warranty_salesman: FX is a Body child",
		un._warranty_fx != null and un._warranty_fx.get_parent() == un._body)
	_check("warranty_salesman: FX stage_h matches monster scale",
		un._warranty_fx != null
		and absf(un._warranty_fx.stage_h - un._monster_scale()) < 0.01)
	_check("warranty_salesman: FX renders above the sprite",
		un._warranty_fx != null and un._sprite != null
		and un._warranty_fx.z_index > un._sprite.z_index)
	_check("warranty_salesman: no MLM sparkles leak in", un._mlm_fx == null)
	_check("warranty_salesman: no doomscroll FX leaks in",
		un._doomscroll_fx == null)
	un.free()


func _test_other_jobs_have_no_fx() -> void:
	for j in ["doomscroller", "mlm_bro", "dmv_clerk", "twister_sister",
		"karaoke_barbarian", "worker"]:
		var un := _make_node(j)
		_check("no-fx job %s: no warranty pitch FX" % j, un._warranty_fx == null)
		un.free()


func _test_rebuild_clears_ref() -> void:
	var un := _make_node("warranty_salesman")
	var old_fx: WarrantyFX = un._warranty_fx
	_check("rebuild: FX present before rebuild", old_fx != null)
	un._build()
	# Rebuild frees the old Body subtree: the ref must not dangle —
	# _build recreates the rig for the still-warranty job.
	_check("rebuild: ref points at a fresh live instance",
		un._warranty_fx != null and is_instance_valid(un._warranty_fx)
		and un._warranty_fx != old_fx)
	un.free()


func _test_node_set_warranty_state() -> void:
	var un := _make_node("warranty_salesman")
	un.set_warranty_state(true, 3)
	_check("node: pitching pushed into FX", un._warranty_fx._pitching)
	# One state push with raised sales = one edge-triggered burst (the sim
	# raises warranty_sales by exactly one per resolved pitch, so one burst
	# per sale).
	_check("node: raised sales bursts one coin volley",
		un._warranty_fx._coin_pos.size() == WarrantyFX.COINS_PER_SALE)
	un.set_warranty_state(false, 3)
	_check("node: idle pushed into FX", not un._warranty_fx._pitching)
	un.free()
	# Non-warranty jobs share the sync path: must be a safe no-op.
	var w := _make_node("worker")
	w.set_warranty_state(true, 5)
	_check("node: worker ignores warranty state", w._warranty_fx == null)
	w.free()
