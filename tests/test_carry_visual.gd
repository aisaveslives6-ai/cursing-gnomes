extends SceneTree
## Cursing Gnomes — visible carry-load bundle tests.
## (Jeremy 2026-10-06 animation pass, gate #3: units hauling a full carry to
## a dropoff walked empty-handed while the sim's carrying{} said they held
## 10 units of resource — a visible dead end. The shoulder bundle uses the
## SAME deposit/icon art as the ground pickups, so ground -> shoulder ->
## stockpile is one continuous sprite; it rides as a Body child and inherits
## the WALK bounce, rock and squash from anim.apply_to(_body) exactly.)
##
## Covers:
##   - travel + carry_kind -> WALK + bundle visible (deposit art first)
##   - travel + no carry kind -> bundle hidden
##   - bundle hidden during swing/gather/station/idle loops (load is on the
##     ground being harvested, not mid-swing)
##   - missing art kind -> bundle hidden, kind cleared (never a white square)
##   - food (no deposit sprite) falls back to the HUD icon
##   - bundle is a Body child (inherits the walk bounce — no frozen sliding)
##   - bundle mirrors to the facing-side shoulder (flip_h)
##   - 4-arg set_work_state callers still work (optional 5th param)
##   - boats skip the bundle overlay entirely
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_carry_visual.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes carry-load bundle tests ===")
	_test_travel_shows_bundle()
	_test_travel_no_carry_hides()
	_test_swing_loops_hide()
	_test_missing_art_hides()
	_test_food_icon_fallback()
	_test_body_child_inherits_bounce()
	_test_shoulder_mirror()
	_test_four_arg_callers()
	_test_boats_skip()
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
		print("  FAIL: ", test_name)


func _make_node() -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(66, "gnomes", "worker", Vector2(100, 100), "m")
	return un


func _test_travel_shows_bundle() -> void:
	var un := _make_node()
	un.set_work_state("to_dropoff", "", "axe", "", "wood")
	_check("carry: to_dropoff+wood -> WALK", un.anim.state == UnitAnimator.WALK)
	un._update_tool(1.0 / 60.0)
	_check("carry: bundle kind recorded", un._load_kind == "wood")
	_check("carry: bundle visible", un._load_pivot.visible)
	_check("carry: bundle has deposit texture",
		un._load_sprite.texture != null)
	_check("carry: owned tool still carried at hand",
		un._tool_kind == "axe" and un._tool_pivot.visible)
	un.free()


func _test_travel_no_carry_hides() -> void:
	var un := _make_node()
	un.set_work_state("to_dropoff", "", "", "", "")
	_check("carry: to_dropoff empty-handed -> WALK",
		un.anim.state == UnitAnimator.WALK)
	_check("carry: bundle hidden when nothing carried",
		not un._load_pivot.visible)
	# Re-show, then clear: the next sync must hide it.
	un.set_work_state("to_dropoff", "", "", "", "gold")
	_check("carry: gold bundle shows", un._load_pivot.visible)
	un.set_work_state("idle")
	_check("carry: bundle cleared after arrival",
		not un._load_pivot.visible and un._load_kind == "")
	un.free()


func _test_swing_loops_hide() -> void:
	var un := _make_node()
	# A stale carry kind must never ride a swing loop.
	un.set_work_state("gathering", "tree", "", "", "wood")
	un._update_tool(1.0 / 60.0)
	_check("carry: gathering hides bundle",
		not un._load_pivot.visible)
	un.set_work_state("building", "", "hammer", "", "wood")
	_check("carry: building hides bundle", not un._load_pivot.visible)
	un.set_work_state("working", "", "", "sit", "wood")
	_check("carry: seated work hides bundle", not un._load_pivot.visible)
	un.set_work_state("idle", "", "", "", "wood")
	_check("carry: idle hides stale bundle", not un._load_pivot.visible)
	un.free()


func _test_missing_art_hides() -> void:
	var un := _make_node()
	un.set_work_state("to_dropoff", "", "", "", "adamantine")
	_check("carry: unknown kind -> no crash",
		un.anim.state == UnitAnimator.WALK)
	_check("carry: unknown kind -> bundle hidden",
		not un._load_pivot.visible)
	_check("carry: unknown kind -> kind cleared (never a white square)",
		un._load_kind == "")
	un.free()


func _test_food_icon_fallback() -> void:
	var un := _make_node()
	# No deposit_food.png exists — the HUD icon is the fallback.
	un.set_work_state("to_dropoff", "", "", "", "food")
	_check("carry: food falls back to icon art", un._load_kind == "food")
	un._update_tool(1.0 / 60.0)
	_check("carry: food bundle visible", un._load_pivot.visible)
	un.free()


func _test_body_child_inherits_bounce() -> void:
	var un := _make_node()
	un.set_work_state("to_dropoff", "", "", "", "oil")
	_check("carry: bundle is a Body child (rides walk bounce)",
		un._load_pivot.get_parent() == un._body)
	# The bundle must move with the body, never hold a frozen offset: the
	# WALK bounce displaces the Body vertically each frame.
	un.anim.state_t = 0.0
	un.anim.apply_to(un._body)
	var y0: float = un._body.position.y
	# A quarter into the walk bounce (period ~0.7 s at t*9.0) the body must
	# have lifted — the bundle, as a Body child, rides along.
	un.anim.state_t = 0.17
	un.anim.apply_to(un._body)
	_check("carry: walk bounce moves the body (bundle rides it)",
		un._body.position.y != y0)
	un.free()


func _test_shoulder_mirror() -> void:
	var un := _make_node()
	un.set_work_state("to_dropoff", "", "", "", "wood")
	un._sprite.flip_h = false
	un._update_tool(1.0 / 60.0)
	_check("carry: shoulder on facing side (right)",
		un._load_pivot.position.x > 0.0)
	un._sprite.flip_h = true
	un._update_tool(1.0 / 60.0)
	_check("carry: shoulder mirrors on facing left",
		un._load_pivot.position.x < 0.0)
	un.free()


func _test_four_arg_callers() -> void:
	# All existing callers use 4 args — the 5th is optional and must not
	# break them or change their behavior.
	var un := _make_node()
	un.set_work_state("to_dropoff", "", "axe", "")
	_check("carry: 4-arg call still walks", un.anim.state == UnitAnimator.WALK)
	_check("carry: 4-arg call shows no bundle", not un._load_pivot.visible)
	un.set_work_state("gathering", "tree", "", "")
	_check("carry: 4-arg gather still chops",
		un.anim.state == UnitAnimator.CHOP)
	un.free()


func _test_boats_skip() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(67, "gnomes", "fishing_boat", Vector2(100, 100), "m")
	un.set_work_state("to_dropoff", "", "", "", "wood")
	_check("carry: boats skip the bundle overlay", un._load_kind == "")
	un._update_tool(1.0 / 60.0)  # must not crash on the null pivot
	_check("carry: boats survive the per-frame mirror", true)
	un.free()
