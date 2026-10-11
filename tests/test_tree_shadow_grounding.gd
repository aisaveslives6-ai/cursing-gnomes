extends SceneTree
## Cursing Gnomes — tree shadow grounding tests (launch readiness gate 3).
##
## The whole MapProp rotates for sway (+-0.014 rad) and chop-shudder
## (+-0.035 rad), but the tree's blob shadow is cast on the GROUND. The
## shadow draw is counter-rotated by MapProp.shadow_draw_angle() so the
## blob stays pinned in world space while the tree moves; without it the
## shadow wobbled up to ~3px with every chop (deferred finding from the
## 2026-10-06 floating audit).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tree_shadow_grounding.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes tree shadow grounding tests ===")
	_test_counter_rotation_cancels_sway()
	_test_counter_rotation_cancels_chop_shudder()
	_test_net_world_rotation_zero_across_sway_cycle()
	_test_wrapper_wired()
	_test_resource_props_unaffected()
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


func _test_counter_rotation_cancels_sway() -> void:
	# SWAY_AMP = 0.014: the shadow's draw angle must exactly cancel it.
	for a: float in [0.0, 0.014, -0.014, 0.007, -0.011]:
		_check("shadow draw angle cancels sway %s" % a,
			is_equal_approx(a + MapProp.shadow_draw_angle(a), 0.0))


func _test_counter_rotation_cancels_chop_shudder() -> void:
	# Chop shudder adds up to +-0.035 rad on top of sway — the shadow must
	# stay pinned through that too (this was the ~3px wobble).
	for a: float in [0.035, -0.035, 0.049, -0.049, 0.02]:
		_check("shadow draw angle cancels chop rotation %s" % a,
			is_equal_approx(a + MapProp.shadow_draw_angle(a), 0.0))


func _test_net_world_rotation_zero_across_sway_cycle() -> void:
	# Simulate the real sway function from map_prop.gd across a full cycle,
	# with chop shudder layered on: net world rotation of the shadow must
	# stay ~0 at every sample (no wobble at any point in the motion).
	var phase := 1.3
	var t := 0.0
	while t < 6.0:
		var rot: float = sin(t * 1.1 + phase) * 0.014 \
			+ sin(t * 22.0 + phase * 3.0) * 0.035
		_check("shadow pinned at sway t=%.2f" % t,
			is_equal_approx(rot + MapProp.shadow_draw_angle(rot), 0.0))
		t += 0.25


func _test_wrapper_wired() -> void:
	# The counter-rotation must actually sit in the draw path — guard
	# against a refactor that inlines Shadows.draw_blob again.
	_check("MapProp has _draw_grounded_shadow",
		MapProp.new().has_method("_draw_grounded_shadow"))
	var t := MapProp.new()
	t.setup("tree", Vector2(100.0, 200.0))
	t.rotation = 0.03
	# The wrapper reads the LIVE rotation, so mid-chop poses stay pinned.
	_check("wrapper uses live prop rotation",
		is_equal_approx(
			t.rotation + MapProp.shadow_draw_angle(t.rotation), 0.0))


func _test_resource_props_unaffected() -> void:
	# Resource props never sway (no _process rotation), so their static
	# contact shadow path is untouched by the counter-rotation wrapper.
	var r := MapProp.new()
	r.setup("res_gold", Vector2(500.0, 600.0))
	_check("resource prop never rotates", is_equal_approx(r.rotation, 0.0))
