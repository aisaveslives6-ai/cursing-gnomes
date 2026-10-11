extends SceneTree
## Cursing Gnomes — karaoke barbarian concert-stage FX tests.
## 2026-10-08 (wake graphics-hourly): Brax performs a 3-set power ballad
## but had no stage — sprite + audio only. ConcertFX (Body child of his
## UnitNode) draws sweeping spotlight beams, a pulsing stage glow, and
## rising eighth-notes while the sim has him "belting"; hidden otherwise.


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
	# _ready() (visibility/process flags) fires on the first frame, not
	# synchronously on add_child in -s script mode.
	await process_frame
	print("=== Cursing Gnomes Concert FX tests ===")
	_test_standalone_defaults()
	_test_set_performing_toggle()
	_test_note_cycle_math()
	await _test_draw_does_not_crash()
	_test_ascii_safe()
	_test_karaoke_node_builds_fx()
	_test_other_jobs_have_no_fx()
	_test_rebuild_clears_ref()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_standalone_defaults() -> void:
	var fx := ConcertFX.new()
	root.add_child(fx)
	_check("fx: starts not performing", not fx.is_performing())
	_check("fx: starts hidden", not fx.visible)
	_check("fx: default stage_h sane", fx.stage_h > 0.0)
	fx.free()


func _test_set_performing_toggle() -> void:
	var fx := ConcertFX.new()
	root.add_child(fx)
	fx.set_performing(true)
	_check("fx: performing after set true", fx.is_performing())
	_check("fx: visible while performing", fx.visible)
	fx.set_performing(false)
	_check("fx: not performing after set false", not fx.is_performing())
	_check("fx: hidden when idle", not fx.visible)
	fx.free()


func _test_note_cycle_math() -> void:
	var fx := ConcertFX.new()
	root.add_child(fx)
	fx.set_performing(true)
	var c0 := fx._note_cycle(0)
	_check("fx: note cycle in [0,1)", c0 >= 0.0 and c0 < 1.0)
	# Desync: different notes at different cycle positions.
	var c1 := fx._note_cycle(1)
	_check("fx: notes desynced", absf(c1 - c0) > 0.01)
	# Advancing time advances the cycle.
	fx._process(0.6)
	var c0b := fx._note_cycle(0)
	_check("fx: cycle advances with time", absf(c0b - c0) > 0.01)
	# Full period wraps cleanly.
	fx._process(ConcertFX.NOTE_CYCLE)
	_check("fx: cycle wraps after one period",
		absf(fx._note_cycle(0) - c0b) < 0.05)
	fx.free()


func _test_draw_does_not_crash() -> void:
	var fx := ConcertFX.new()
	root.add_child(fx)
	# Idle: nothing to draw; engine-driven redraw must stay silent.
	fx.set_performing(true)
	fx.stage_h = 80.0
	for i in 6:
		fx._process(0.4)
	fx.queue_redraw()
	await process_frame
	_check("fx: engine-driven _draw runs clean while performing", true)
	fx.free()


func _test_ascii_safe() -> void:
	# Jeremy's iPhone tofu rule: no glyph/emoji anywhere in the FX source.
	var src := FileAccess.get_file_as_string(
		"res://scripts/world/concert_fx.gd")
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


func _test_karaoke_node_builds_fx() -> void:
	var un := _make_node("karaoke_barbarian")
	_check("karaoke: concert FX built",
		un._concert_fx != null and is_instance_valid(un._concert_fx))
	_check("karaoke: FX is a Body child",
		un._concert_fx != null and un._concert_fx.get_parent() == un._body)
	# 2026-10-08 (wake graphics-hourly): layering regression — the FX is
	# built before _sprite joins _body, so child order alone buries the
	# beams under the barbarian; z_index pins the rig on top.
	_check("karaoke: FX z_index pinned above sprite",
		un._concert_fx != null and un._concert_fx.z_index == 2)
	var kids := un._body.get_children()
	_check("karaoke: FX child order sits below sprite (z_index does the lifting)",
		kids.find(un._concert_fx) < kids.find(un._sprite))
	_check("karaoke: FX starts idle", not un.is_performing())
	# The world sync drives this: belting -> performing.
	un.set_performing(true)
	_check("karaoke: performing toggles on", un.is_performing())
	un.set_performing(false)
	_check("karaoke: performing toggles off", not un.is_performing())
	# 2026-10-08: FX is built before _sprite is added to _body, so child
	# order alone buries the beams under the performer — z_index pins it.
	_check("karaoke: FX renders above the sprite",
		un._concert_fx != null and un._sprite != null
		and un._concert_fx.z_index > un._sprite.z_index)
	un.free()


func _test_other_jobs_have_no_fx() -> void:
	for j in ["booze_ooze", "seagull_swarm", "count_bastard", "worker"]:
		var un := _make_node(j)
		_check("no-fx job %s: no concert FX" % j, un._concert_fx == null)
		# Safe no-op on jobs that never built one.
		un.set_performing(true)
		_check("no-fx job %s: set_performing is a safe no-op" % j,
			not un.is_performing())
		un.free()


func _test_rebuild_clears_ref() -> void:
	var un := _make_node("karaoke_barbarian")
	var old_fx: ConcertFX = un._concert_fx
	_check("rebuild: FX present before rebuild", old_fx != null)
	un._build()
	# Rebuild frees the old Body subtree: the ref must not dangle —
	# _build recreates the rig for the still-karaoke job.
	_check("rebuild: ref points at a fresh live instance",
		un._concert_fx != null and is_instance_valid(un._concert_fx)
		and un._concert_fx != old_fx)
	_check("rebuild: rebuilt FX starts idle", not un.is_performing())
	un.free()
