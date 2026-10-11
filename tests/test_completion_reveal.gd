extends SceneTree
## Cursing Gnomes — building completion-reveal tests.
## 2026-10-08 (wake graphics-hourly): a finished building popped from
## translucent blueprint to full art with no transition. The
## blueprint->complete edge now plays a one-shot rise: the building rises
## out of the ground over 0.8 s (ease-out cubic) with an expanding dust ring
## + six seeded dust puffs at the base. Walls are excluded (drag-place
## chains complete dozens at once).


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
	print("=== Cursing Gnomes Completion Reveal tests ===")
	_test_pure_math()
	_test_trigger_edge()
	_test_reveal_run()
	_test_wall_excluded()
	_test_complete_on_load_stays_silent()
	_test_no_retrigger()
	_test_sprite_null_safe()
	await _test_draw_does_not_crash()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_pure_math() -> void:
	_check("reveal: wall excluded", not BuildingNode.reveal_allowed_for("wall"))
	_check("reveal: farm allowed", BuildingNode.reveal_allowed_for("farm"))
	_check("reveal: empty btype excluded",
		not BuildingNode.reveal_allowed_for(""))
	_check("reveal: k starts at 0", BuildingNode.reveal_k_for(0.8) == 0.0)
	_check("reveal: k ends at 1", BuildingNode.reveal_k_for(0.0) == 1.0)
	_check("reveal: k clamps high", BuildingNode.reveal_k_for(99.0) == 0.0)
	_check("reveal: k clamps low", BuildingNode.reveal_k_for(-1.0) == 1.0)
	_check("reveal: ease(0)=0", BuildingNode.reveal_ease(0.0) == 0.0)
	_check("reveal: ease(1)=1", BuildingNode.reveal_ease(1.0) == 1.0)
	var mid := BuildingNode.reveal_ease(0.5)
	_check("reveal: ease-out bursts early (ease(0.5) > 0.5)", mid > 0.5)
	_check("reveal: alpha starts translucent",
		is_equal_approx(BuildingNode.reveal_alpha_for(0.0), 0.45))
	_check("reveal: alpha ends solid",
		is_equal_approx(BuildingNode.reveal_alpha_for(1.0), 1.0))
	var r0 := BuildingNode.reveal_ring_radius_for(40.0, 0.0)
	var r1 := BuildingNode.reveal_ring_radius_for(40.0, 1.0)
	_check("reveal: ring starts positive", r0 > 0.0)
	_check("reveal: ring expands", r1 > r0)
	_check("reveal: ring alpha fades in",
		is_equal_approx(BuildingNode.reveal_ring_alpha_for(0.0), 0.55))
	_check("reveal: ring alpha fades out",
		is_equal_approx(BuildingNode.reveal_ring_alpha_for(1.0), 0.0))
	_check("reveal: puff alpha fades",
		BuildingNode.reveal_puff_alpha_for(1.0) == 0.0)
	_check("reveal: puff radius shrinks",
		BuildingNode.reveal_puff_radius_for(40.0, 1.0)
			< BuildingNode.reveal_puff_radius_for(40.0, 0.0))
	var pa := BuildingNode.reveal_puff_pos(0, 40.0, 0.0, 1.23)
	var pb := BuildingNode.reveal_puff_pos(0, 40.0, 0.0, 1.23)
	_check("reveal: puff pos deterministic", pa == pb)
	var pc := BuildingNode.reveal_puff_pos(3, 40.0, 0.0, 1.23)
	_check("reveal: puffs spread around the base", pa != pc)
	# Ground-plane ellipse: x-radius 0.55*fp at k=0, 1.5*fp at k=1.
	_check("reveal: puff k=0 inside start ring", pa.length() <= 40.0 * 0.56)
	var pd := BuildingNode.reveal_puff_pos(1, 40.0, 1.0, 0.0)
	_check("reveal: puff k=1 inside end ring", pd.length() <= 40.0 * 1.51)
	# y is squashed to the ground plane: |y| <= ring radius * 0.55.
	_check("reveal: puff y squashed to ground plane",
		absf(pd.y) <= 40.0 * 1.5 * 0.55 + 0.01)


func _make_node(btype: String, bid: int) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(bid, btype, "gnomes", Vector2(100, 100))
	root.add_child(n)
	return n


func _test_trigger_edge() -> void:
	var n := _make_node("farm", 101)
	n.record = {"complete": false, "hp": 100.0, "max_hp": 100.0}
	n._process(0.016)
	_check("reveal: blueprint does not trigger", n._reveal_t == 0.0)
	var base_y := n._sprite.position.y if n._sprite != null else 0.0
	n.record = {"complete": true, "hp": 100.0, "max_hp": 100.0}
	n._process(0.016)
	_check("reveal: completion edge triggers",
		n._reveal_t > 0.0 and n._reveal_t <= 0.8)
	_check("reveal: base y captured before the rise",
		is_equal_approx(n._reveal_base_y, base_y))
	n.free()


func _test_reveal_run() -> void:
	var n := _make_node("barracks", 102)
	n.record = {"complete": false, "hp": 100.0, "max_hp": 100.0}
	n._process(0.016)
	n.record = {"complete": true, "hp": 100.0, "max_hp": 100.0}
	n._process(0.016)
	var base_y := n._reveal_base_y
	# Mid-reveal: still raised, alpha between blueprint and solid.
	n._process(0.2)
	n._process(0.2)
	var mid_y := n._sprite.position.y
	var mid_a := n._sprite.modulate.a
	_check("reveal: mid-rise sprite is above base", mid_y > base_y)
	_check("reveal: mid-rise alpha ramping", mid_a > 0.45 and mid_a < 1.0)
	# Run it out: exact restore, no drift, no translucency leak.
	for i in range(20):
		n._process(0.1)
	_check("reveal: timer finishes", n._reveal_t == 0.0)
	_check("reveal: sprite y restored exactly",
		is_equal_approx(n._sprite.position.y, base_y))
	_check("reveal: alpha restored solid",
		is_equal_approx(n._sprite.modulate.a, 1.0))
	n.free()


func _test_wall_excluded() -> void:
	var n := _make_node("wall", 103)
	n.record = {"complete": false, "hp": 900.0, "max_hp": 900.0}
	n._process(0.016)
	n.record = {"complete": true, "hp": 900.0, "max_hp": 900.0}
	n._process(0.016)
	_check("reveal: wall completion stays silent", n._reveal_t == 0.0)
	n.free()


func _test_complete_on_load_stays_silent() -> void:
	# Nodes built for an already-complete record (game load, initial
	# placement) must not replay the reveal.
	var n := _make_node("farm", 104)
	n.record = {"complete": true, "hp": 100.0, "max_hp": 100.0}
	n._process(0.016)
	_check("reveal: complete-on-load stays silent", n._reveal_t == 0.0)
	n.free()


func _test_no_retrigger() -> void:
	var n := _make_node("farm", 105)
	n.record = {"complete": false, "hp": 100.0, "max_hp": 100.0}
	n._process(0.016)
	n.record = {"complete": true, "hp": 100.0, "max_hp": 100.0}
	n._process(0.016)
	for i in range(20):
		n._process(0.1)
	_check("reveal: finished once", n._reveal_t == 0.0)
	# Later ticks on the same complete record must not re-trigger.
	n._process(0.016)
	n._process(0.016)
	_check("reveal: no re-trigger on steady complete", n._reveal_t == 0.0)
	n.free()


func _test_sprite_null_safe() -> void:
	# Programmer-art / missing-art path: no sprite, dust still plays, no crash.
	var n := _make_node("farm", 106)
	n._sprite = null
	n.on_construction_finished()
	_check("reveal: null sprite triggers dust timer", n._reveal_t == 0.8)
	n._process(0.1)
	_check("reveal: null sprite survives a step", n._reveal_t < 0.8)
	n.free()


func _test_draw_does_not_crash() -> void:
	var n := _make_node("farm", 107)
	n.record = {"complete": false, "hp": 100.0, "max_hp": 100.0}
	n._process(0.016)
	n.record = {"complete": true, "hp": 100.0, "max_hp": 100.0}
	n._process(0.016)
	# Engine-driven redraw while the reveal plays (ring + puffs in _draw).
	n.queue_redraw()
	await process_frame
	n._process(0.4)
	n.queue_redraw()
	await process_frame
	_check("reveal: _draw survives the reveal", is_instance_valid(n))
	n.free()
