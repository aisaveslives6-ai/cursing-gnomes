extends SceneTree
## Cursing Gnomes — Twister Sister funnel-spin FX tests.
## 2026-10-08 (wake graphics-hourly): Twister Sister shipped with bespoke
## glam-metal tornado art but a STATIC funnel. TwisterSisterFX (Body child
## of her UnitNode) adds the living vortex: rotating spiral bands around
## the funnel (top bands faster), a debris ring of roof tiles and planks
## orbiting the base that bulges on every fling-aura cadence (FLING_TICK =
## the sim's 0.5s aura), a ground dust skirt that keeps the funnel
## grounded, and a crackling lightning bolt inside. Always spinning while
## she rampages — no sim toggle.


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
	print("=== Cursing Gnomes Twister Sister FX tests ===")
	_test_standalone_defaults()
	_test_debris_cycle_math()
	_test_surge_math()
	_test_bands()
	_test_dust_cycle()
	_test_lightning()
	await _test_draw_does_not_crash()
	_test_ascii_safe()
	_test_twister_node_builds_fx()
	_test_other_jobs_have_no_fx()
	_test_rebuild_clears_ref()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_standalone_defaults() -> void:
	var fx := TwisterSisterFX.new()
	root.add_child(fx)
	_check("fx: default stage_h sane", fx.stage_h > 0.0)
	_check("fx: starts visible (always spinning)", fx.visible)
	_check("fx: surge phase in [0,1)",
		fx._surge_phase() >= 0.0 and fx._surge_phase() < 1.0)
	_check("fx: debris cycle in [0,1)",
		fx._debris_cycle(0) >= 0.0 and fx._debris_cycle(0) < 1.0)
	_check("fx: dust cycle in [0,1)",
		fx._dust_cycle(0) >= 0.0 and fx._dust_cycle(0) < 1.0)
	fx.free()


func _test_debris_cycle_math() -> void:
	var fx := TwisterSisterFX.new()
	root.add_child(fx)
	var c0 := fx._debris_cycle(0)
	var c1 := fx._debris_cycle(1)
	_check("fx: debris flecks desynced", absf(c1 - c0) > 0.01)
	fx._process(0.2)
	var c_mid := fx._debris_cycle(0)
	_check("fx: debris orbit advances", absf(c_mid - c0) > 0.01)
	fx._process(TwisterSisterFX.DEBRIS_PERIOD)
	_check("fx: debris orbit wraps after one period",
		absf(fx._debris_cycle(0) - c_mid) < 0.05)
	# Debris hugs the base: near ground level, below mid-funnel.
	fx._t = 0.0
	var p := fx._debris_pos(0, 100.0)
	_check("fx: debris stays below mid-funnel", p.y > -55.0)
	_check("fx: debris orbits off-center", absf(p.x) > 1.0)
	fx.free()


func _test_surge_math() -> void:
	var fx := TwisterSisterFX.new()
	root.add_child(fx)
	# Silent just before the tick, max right at the tick.
	fx._t = TwisterSisterFX.FLING_TICK * 0.9
	var s_weak := fx._surge()
	fx._t = TwisterSisterFX.FLING_TICK + 0.01
	var s_hit := fx._surge()
	_check("fx: surge peaks at the fling tick", s_hit > s_weak)
	# The ring bulges outward under surge.
	fx._t = TwisterSisterFX.FLING_TICK + 0.01
	var p_hot := fx._debris_pos(0, 100.0)
	fx._t = TwisterSisterFX.FLING_TICK * 0.5
	var p_cool := fx._debris_pos(0, 100.0)
	_check("fx: surge bulges the debris ring",
		p_hot.abs().x + absf(p_hot.y) > p_cool.abs().x + absf(p_cool.y))
	fx.free()


func _test_bands() -> void:
	var fx := TwisterSisterFX.new()
	root.add_child(fx)
	# Funnel narrows at the base: lower bands are smaller circles.
	_check("fx: base band tighter than top band",
		fx._band_radius(0) < fx._band_radius(2))
	# Bands stack upward: y rises with band index (smaller y).
	_check("fx: bands stack bottom to top",
		fx._band_y(0, 100.0) > fx._band_y(2, 100.0))
	# Top bands spin faster than the base.
	var ph0_before := fx._band_phase(0)
	var ph2_before := fx._band_phase(2)
	fx._process(0.1)
	var adv0: float = fx._band_phase(0) - ph0_before
	var adv2: float = fx._band_phase(2) - ph2_before
	_check("fx: bands advance", adv0 > 0.0 and adv2 > 0.0)
	_check("fx: top band spins faster than base", adv2 > adv0)
	_check("fx: phases stay in [0,1)",
		fx._band_phase(0) >= 0.0 and fx._band_phase(0) < 1.0
		and fx._band_phase(2) >= 0.0 and fx._band_phase(2) < 1.0)
	fx.free()


func _test_dust_cycle() -> void:
	var fx := TwisterSisterFX.new()
	root.add_child(fx)
	var c0 := fx._dust_cycle(0)
	var c1 := fx._dust_cycle(1)
	_check("fx: dust motes desynced", absf(c1 - c0) > 0.01)
	# Dust drifts outward: the drift radius grows with the cycle
	# (the mote also orbits the funnel, so radius is the contract).
	_check("fx: dust drifts outward",
		fx._dust_radius(0.6, 100.0) > fx._dust_radius(0.0, 100.0))
	fx._t = 0.0
	var d0 := fx._dust_pos(0, 100.0)
	fx._t = TwisterSisterFX.DUST_CYCLE * 0.6
	var d1 := fx._dust_pos(0, 100.0)
	# Dust hugs the ground — the grounding skirt.
	_check("fx: dust pinned near ground",
		absf(d0.y) < 6.0 and absf(d1.y) < 6.0)
	fx.free()


func _test_lightning() -> void:
	var fx := TwisterSisterFX.new()
	root.add_child(fx)
	# Silent mid-period, flashing right after a period boundary.
	fx._t = TwisterSisterFX.LIGHTNING_PERIOD * 0.5
	_check("fx: bolt silent mid-period", fx._bolt_alpha() == 0.0)
	fx._t = TwisterSisterFX.LIGHTNING_PERIOD + 0.01
	_check("fx: bolt flashes after the boundary", fx._bolt_alpha() > 0.5)
	# Bolt shape stable within one flash (seeded per period).
	var p0 := fx._bolt_points(100.0)
	fx._t = TwisterSisterFX.LIGHTNING_PERIOD + 0.05
	var p1 := fx._bolt_points(100.0)
	_check("fx: bolt shape stable within a flash",
		p0.size() > 2 and p0.size() == p1.size()
		and p0[0].distance_to(p1[0]) < 0.01)
	# Bolt lives inside the funnel, below the top band.
	fx._t = TwisterSisterFX.LIGHTNING_PERIOD + 0.01
	for pt in fx._bolt_points(100.0):
		_check("fx: bolt y in funnel (%s)" % str(pt),
			pt.y <= -19.0 and pt.y >= -85.0)
	fx.free()


func _test_draw_does_not_crash() -> void:
	var fx := TwisterSisterFX.new()
	root.add_child(fx)
	fx.stage_h = 128.0
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
		"res://scripts/world/twister_sister_fx.gd")
	var bad := 0
	for i in src.length():
		if src.unicode_at(i) > 0x2500:
			bad += 1
	_check("fx: source ASCII-only (no tofu risk)", bad == 0)


func _make_node(p_job: String) -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(950 + _passed, "gnomes", p_job, Vector2(100, 100), "m")
	return un


func _test_twister_node_builds_fx() -> void:
	var un := _make_node("twister_sister")
	_check("twister_sister: funnel-spin FX built",
		un._twister_fx != null and is_instance_valid(un._twister_fx))
	_check("twister_sister: FX is a Body child",
		un._twister_fx != null and un._twister_fx.get_parent() == un._body)
	_check("twister_sister: FX stage_h matches monster scale",
		un._twister_fx != null
		and absf(un._twister_fx.stage_h - un._monster_scale()) < 0.01)
	_check("twister_sister: FX renders above the sprite",
		un._twister_fx != null and un._sprite != null
		and un._twister_fx.z_index > un._sprite.z_index)
	_check("twister_sister: no MLM FX leaks in",
		un._mlm_fx == null)
	un.free()


func _test_other_jobs_have_no_fx() -> void:
	for j in ["mlm_bro", "doomscroller", "karaoke_barbarian", "worker",
			"dmv_clerk", "gossip_gnome"]:
		var un := _make_node(j)
		_check("no-fx job %s: no twister spin" % j, un._twister_fx == null)
		un.free()


func _test_rebuild_clears_ref() -> void:
	var un := _make_node("twister_sister")
	var old_fx: TwisterSisterFX = un._twister_fx
	_check("rebuild: FX present before rebuild", old_fx != null)
	un._build()
	# Rebuild frees the old Body subtree: the ref must not dangle —
	# _build recreates the rig for the still-twister job.
	_check("rebuild: ref points at a fresh live instance",
		un._twister_fx != null and is_instance_valid(un._twister_fx)
		and un._twister_fx != old_fx)
	un.free()
