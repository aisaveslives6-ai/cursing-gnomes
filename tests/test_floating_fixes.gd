extends SceneTree
## Cursing Gnomes — gate 3 (nothing floating) regression tests, 2026-10-06.
##
## 1. Monastery + dark-crystal ownership/capture rings draw as iso-squashed
##    ground ellipses (0.62, the game's ground-decal convention) whose bottom
##    edge kisses the ground point — not screen-space circles dipping ~50px
##    below it like a floating halo.
## 2. The force-field shimmer is a dome over the building: its sweep angles
##    always stay within [PI, TAU] (top half), never dipping underground.
## 3. Wildfire flames bottom-align on the ground point at every intensity —
##    the centered 64px frame no longer renders half-underground.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_floating_fixes.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes floating-fixes tests ===")
	_test_ring_geometry()
	_test_dome_angles()
	_test_wildfire_grounding()
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


func _test_ring_geometry() -> void:
	# Both nodes share the ground-decal squash convention.
	_check("monastery ring squash is 0.62",
		is_equal_approx(MonasteryNode.RING_SQUASH, 0.62))
	_check("crystal ring squash is 0.62",
		is_equal_approx(CrystalNode.RING_SQUASH, 0.62))
	# Ring bottom kisses the ground point (old bug: +50px below it).
	var mb: float = MonasteryNode.ring_bottom()
	_check("monastery ring bottom near ground (got %s)" % mb,
		mb >= -5.0 and mb <= 14.0)
	var cb: float = CrystalNode.ring_bottom()
	_check("crystal ring bottom near ground (got %s)" % cb,
		cb >= -5.0 and cb <= 14.0)
	# Ring top still arcs well above the footprint base (wraps the site).
	var mtop: float = MonasteryNode.RING_CY - MonasteryNode.RING_SQUASH * MonasteryNode.RING_RX
	_check("monastery ring top above building (got %s)" % mtop, mtop < -40.0)
	var ctop: float = CrystalNode.RING_CY - CrystalNode.RING_SQUASH * CrystalNode.RING_RX
	_check("crystal ring top above building (got %s)" % ctop, ctop < -40.0)
	# Ring is wider than the 160px footprint so it encircles it.
	_check("monastery ring wider than footprint",
		MonasteryNode.RING_RX * 2.0 > 160.0)
	_check("crystal ring wider than footprint",
		CrystalNode.RING_RX * 2.0 > 160.0)


func _test_dome_angles() -> void:
	# Sweep the shimmer across many timestamps: it must never leave the
	# top half of the ellipse ([PI, TAU]).
	for t: float in [0.0, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 100.0]:
		var m: Vector2 = MonasteryNode.dome_shimmer_angles(t)
		_check("monastery dome start in top half at t=%s" % t,
			m.x >= PI - 0.001 and m.x <= TAU + 0.001)
		_check("monastery dome end in top half at t=%s" % t,
			m.y >= PI - 0.001 and m.y <= TAU + 0.001)
		_check("monastery dome sweep is a real arc at t=%s" % t,
			m.y - m.x > 0.5)
		var c: Vector2 = CrystalNode.dome_shimmer_angles(t)
		_check("crystal dome start in top half at t=%s" % t,
			c.x >= PI - 0.001 and c.x <= TAU + 0.001)
		_check("crystal dome end in top half at t=%s" % t,
			c.y >= PI - 0.001 and c.y <= TAU + 0.001)
	# The sweep actually moves (not a frozen pose).
	var a0: Vector2 = MonasteryNode.dome_shimmer_angles(0.0)
	var a1: Vector2 = MonasteryNode.dome_shimmer_angles(1.0)
	_check("monastery dome sweep animates",
		not is_equal_approx(a0.x, a1.x))


func _test_wildfire_grounding() -> void:
	var fx := CombatFX.new()
	root.add_child(fx)
	# Intensity 50 -> s = 0.35 + 0.5*0.85 = 0.775; flame base must sit
	# on the ground point: pos.y + 32*s ~= 0.
	fx.spawn_fire(7, Vector2(100, 200))
	fx.update_fire(7, 50.0, 0.1)
	var slot: Dictionary = fx.get("_fire_nodes").get(7, {})
	_check("wildfire slot exists", not slot.is_empty())
	var spr: Sprite2D = slot.get("sprite")
	_check("wildfire sprite exists", spr != null)
	if spr != null:
		var s: float = 0.35 + 50.0 / 100.0 * 0.85
		_check("wildfire scale follows intensity (got %s)" % spr.scale.x,
			is_equal_approx(spr.scale.x, s))
		var bottom: float = spr.position.y + CombatFX.FIRE_HALF_H * s
		_check("wildfire flame base on ground (bottom=%s)" % bottom,
			absf(bottom) < 1.0)
		_check("wildfire not centered on ground point",
			spr.position.y < -1.0)
	# Zero intensity: smallest flame still bottom-aligned.
	fx.update_fire(7, 0.0, 0.1)
	var s0: float = 0.35
	var bottom0: float = spr.position.y + CombatFX.FIRE_HALF_H * s0
	_check("wildfire min-intensity base on ground (bottom=%s)" % bottom0,
		absf(bottom0) < 1.0)
	fx.clear_fire(7)
	_check("wildfire cleared", fx.get("_fire_nodes").is_empty())
	fx.queue_free()
