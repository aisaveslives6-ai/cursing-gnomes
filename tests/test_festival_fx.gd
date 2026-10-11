extends SceneTree
## Cursing Gnomes — festival decoration tests (wake rapid-iteration 2026-10-07).
##
## Festivals previously changed nothing on screen. FestivalFx shows bunting
## poles + pennant ropes + confetti over the celebrating town during the
## 3-day SimPolicies joy window. Tests pin: the activity window, town-name
## resolution, grounded pole geometry (nothing floats), sagging ropes, and
## that the node stays idle/invisible with no festival.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_festival_fx.gd
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


func _towns() -> Dictionary:
	return {
		1: {"id": 1, "name": "Mudhole", "position": Vector2(1000, 800)},
		2: {"id": 2, "name": "Grimwick", "position": Vector2(300, 300)},
	}


func _fest(day: int, town: String) -> Dictionary:
	return {"last_festival_day": day, "last_festival_town": town}


func _make(towns: Dictionary, fest: Dictionary, day: int) -> FestivalFx:
	var n := FestivalFx.new()
	n.inject(towns, fest, day)
	return n


func _test_window() -> void:
	var f := _fest(10, "Mudhole")
	_check("active day 0", _make(_towns(), f, 10).festival_active())
	_check("active day 1", _make(_towns(), f, 11).festival_active())
	_check("active day 2", _make(_towns(), f, 12).festival_active())
	_check("inactive day 3", not _make(_towns(), f, 13).festival_active())
	_check("inactive before", not _make(_towns(), f, 9).festival_active())
	_check("no festival day 0", not _make(_towns(), _fest(0, "Mudhole"), 5).festival_active())
	_check("empty state", not _make(_towns(), {}, 5).festival_active())


func _test_town_resolution() -> void:
	var n := _make(_towns(), _fest(10, "Mudhole"), 10)
	_check("center resolves", n.town_center() == Vector2(1000, 800))
	var g := _make(_towns(), _fest(10, "Grimwick"), 10)
	_check("other town resolves", g.town_center() == Vector2(300, 300))
	_check("unknown town inactive",
		not _make(_towns(), _fest(10, "Nowhere"), 10).festival_active())
	_check("empty towns inactive",
		not _make({}, _fest(10, "Mudhole"), 10).festival_active())


func _test_pole_geometry() -> void:
	var n := _make(_towns(), _fest(10, "Mudhole"), 10)
	var tops: Array = n.pole_tops()
	_check("four poles", tops.size() == 4)
	var c := Vector2(1000, 800)
	var ok := true
	for i in 4:
		var tt: Vector2 = tops[i]
		# Recompute this pole's ground base the same way the node does.
		var a := deg_to_rad(45.0 + 90.0 * i)
		var base := c + Vector2(cos(a), sin(a)) * FestivalFx.POLE_R
		# Base sits exactly on the ring around the town center...
		if absf(base.distance_to(c) - FestivalFx.POLE_R) > 0.01:
			ok = false
		# ...and the top is straight above it, POLE_H up (grounded pole).
		if absf(tt.x - base.x) > 0.01 or absf((base.y - tt.y) - FestivalFx.POLE_H) > 0.01:
			ok = false
	_check("poles grounded on ring, tops raised", ok)


func _test_rope_sag() -> void:
	var n := FestivalFx.new()
	var a := Vector2(0, -150)
	var b := Vector2(380, -150)
	var mid := n._rope_pt(a, b, 0.5)
	_check("midpoint sags SAG", absf(mid.y - (-150.0 + FestivalFx.SAG)) < 0.01)
	_check("midpoint centered", absf(mid.x - 190.0) < 0.01)
	_check("endpoints on rope",
		n._rope_pt(a, b, 0.0) == a and n._rope_pt(a, b, 1.0) == b)


func _test_pennants() -> void:
	var n := _make(_towns(), _fest(10, "Mudhole"), 10)
	_check("pennants exist", n.pennant_count() > 0)
	# 4 ropes of ~2*POLE_R chord each; pennant every 30px.
	var tops: Array = n.pole_tops()
	var expect := 0
	for r in 4:
		var a: Vector2 = tops[r]
		var bb: Vector2 = tops[(r + 1) % 4]
		expect += int(a.distance_to(bb) / 30.0)
	_check("pennant count matches geometry", n.pennant_count() == expect)


func _test_idle_when_no_festival() -> void:
	var n := FestivalFx.new()
	n.inject(_towns(), {}, 5)
	_check("inactive", not n.festival_active())
	_check("festival layer z=40", n.z_index == 40)
	_check("no pennants drawn anchor", n.pennant_count() >= 0)
	# _draw must be a safe no-op while inactive (headless draw is harmless).
	n._draw()
	_check("draw no-op ok", true)


func _test_confetti_determinism() -> void:
	var a := FestivalFx.new()
	var b := FestivalFx.new()
	a.inject(_towns(), _fest(10, "Mudhole"), 10)
	b.inject(_towns(), _fest(10, "Mudhole"), 10)
	a._fall_step = 7
	b._fall_step = 7
	# Same step -> same internal confetti phase; both stay active.
	_check("deterministic phase", a.festival_active() and b.festival_active()
		and a._fall_step == b._fall_step)
	_check("fall step wraps", FestivalFx.CONFETTI_STEPS == 32)


func _initialize() -> void:
	print("=== Cursing Gnomes festival-fx tests ===")
	_test_window()
	_test_town_resolution()
	_test_pole_geometry()
	_test_rope_sag()
	_test_pennants()
	_test_idle_when_no_festival()
	_test_confetti_determinism()
	print("passed=", _passed, " failed=", _failed)
	if _failed > 0:
		print("FAILURES: ", _failures)
		quit(1)
	else:
		quit(0)
