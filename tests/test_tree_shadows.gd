extends SceneTree
## Cursing Gnomes — tree ground-shadow tests (launch readiness gates 1+3).
##
## Trees were the only common world prop with no ground shadow, so groves
## read as pasted onto the terrain. MapProp now draws a sun-driven blob
## shadow for "tree" props via Shadows.draw_blob, with the same quantized
## shadow_key pattern as UnitNode/BuildingNode: _process recomputes the key
## and only calls queue_redraw() when it changes (the sun drifts over the
## 8-minute day, so redraws are rare and cheap).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tree_shadows.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes tree shadow tests ===")
	_test_setup_initializes_shadow_key()
	_test_process_updates_key_when_sun_moves()
	_test_process_keeps_key_when_sun_still()
	_test_resource_prop_not_affected()
	_test_shadow_constants_sane()
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


func _make_tree(p_pos: Vector2) -> MapProp:
	var t := MapProp.new()
	t.setup("tree", p_pos)
	return t


func _test_setup_initializes_shadow_key() -> void:
	var pos := Vector2(123.0, 456.0)
	var t := _make_tree(pos)
	_check("setup seeds _shadow_key from current sun",
		t._shadow_key == Shadows.shadow_key(pos))


func _test_process_updates_key_when_sun_moves() -> void:
	var t := _make_tree(Vector2(200.0, 300.0))
	var before: int = t._shadow_key
	Shadows.set_phase(0.75)  # jump the sun well past the 0.0005 threshold
	t._process(0.016)
	_check("sun move changes the tree shadow key",
		t._shadow_key != before)
	_check("key matches live shadow_key after _process",
		t._shadow_key == Shadows.shadow_key(t.position))
	Shadows.set_phase(0.25)  # restore day sun for other suites


func _test_process_keeps_key_when_sun_still() -> void:
	var t := _make_tree(Vector2(200.0, 300.0))
	var before: int = t._shadow_key
	t._process(0.016)
	t._process(0.016)
	_check("stable sun leaves the shadow key alone (no redraw churn)",
		t._shadow_key == before)


func _test_resource_prop_not_affected() -> void:
	var r := MapProp.new()
	r.setup("res_gold", Vector2(500.0, 600.0))
	# Resource nodes keep their static contact shadow; they never joined
	# the sun-driven shadow-key system.
	_check("resource prop has no shadow key of its own",
		r._shadow_key == 0)


func _test_shadow_constants_sane() -> void:
	_check("tree shadow footprint positive and modest",
		MapProp.TREE_SHADOW_FOOTPRINT > 10.0
		and MapProp.TREE_SHADOW_FOOTPRINT < 60.0)
	_check("tree shadow alpha in (0,1]",
		MapProp.TREE_SHADOW_ALPHA > 0.0
		and MapProp.TREE_SHADOW_ALPHA <= 1.0)
