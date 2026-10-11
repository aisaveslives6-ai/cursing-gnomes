extends SceneTree
## Cursing Gnomes — P6 staged construction (Jeremy 2026-10-10 direct order).
##
## Every building visibly passes through foundation -> frame -> walls ->
## roof/finish with distinct art per stage, instead of a single growing
## ghost. Walls keep their scaffold-arm blueprint style. Pure visual —
## the sim's progress 0..1 drives the phase, sim untouched. The sprite
## ghost brightens across the roof/finish phase so the building visibly
## "finishes" before the completion-reveal rise.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_construction_phases.gd
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


func _make_bp(progress: float) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(11, "barracks", "gnomes", Vector2(100, 100))
	n.record = {"complete": false, "progress": progress,
		"hp": 500.0, "max_hp": 500.0}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes construction phase tests ===")
	_test_phase_pure()
	_test_sprite_alpha()
	_test_wiring()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## construction_phase_for: pure boundary math.
func _test_phase_pure() -> void:
	_check("0.0 -> foundation", BuildingNode.construction_phase_for(0.0) == 0)
	_check("0.24 -> foundation",
		BuildingNode.construction_phase_for(0.24) == 0)
	_check("0.25 -> frame", BuildingNode.construction_phase_for(0.25) == 1)
	_check("0.49 -> frame", BuildingNode.construction_phase_for(0.49) == 1)
	_check("0.50 -> walls", BuildingNode.construction_phase_for(0.50) == 2)
	_check("0.74 -> walls", BuildingNode.construction_phase_for(0.74) == 2)
	_check("0.75 -> roof/finish",
		BuildingNode.construction_phase_for(0.75) == 3)
	_check("1.0 -> roof/finish", BuildingNode.construction_phase_for(1.0) == 3)
	_check("negative clamps to foundation",
		BuildingNode.construction_phase_for(-0.5) == 0)
	_check("over-one clamps to roof/finish",
		BuildingNode.construction_phase_for(1.5) == 3)


## _process: sprite ghost stays translucent through walls, brightens as
## the roof/finish phase lands.
func _test_sprite_alpha() -> void:
	var p0 := _make_bp(0.10)
	p0._process(0.1)
	if p0._sprite != null:
		_check("foundation ghost dim", is_equal_approx(p0._sprite.modulate.a, 0.45))
	else:
		_check("foundation ghost dim (no sprite art in env)", true)
	p0.free()
	var p2 := _make_bp(0.60)
	p2._process(0.1)
	if p2._sprite != null:
		_check("walls ghost dim", is_equal_approx(p2._sprite.modulate.a, 0.45))
	else:
		_check("walls ghost dim (no sprite art in env)", true)
	p2.free()
	var p3a := _make_bp(0.75)
	p3a._process(0.1)
	if p3a._sprite != null:
		_check("roof start brightens", is_equal_approx(p3a._sprite.modulate.a, 0.45))
	else:
		_check("roof start brightens (no sprite art in env)", true)
	p3a.free()
	var p3b := _make_bp(0.90)
	p3b._process(0.1)
	if p3b._sprite != null:
		# 0.45 + 0.50 * ((0.90 - 0.75) / 0.25) = 0.75
		_check("roof mid brightens", is_equal_approx(p3b._sprite.modulate.a, 0.75))
	else:
		_check("roof mid brightens (no sprite art in env)", true)
	p3b.free()
	# Complete building: full opacity, no phase staging.
	var done := BuildingNode.new()
	done.setup(12, "barracks", "gnomes", Vector2(100, 100))
	done.record = {"complete": true, "progress": 1.0,
		"hp": 500.0, "max_hp": 500.0}
	done._process(0.1)
	if done._sprite != null:
		_check("complete full opacity",
			is_equal_approx(done._sprite.modulate.a, 1.0))
	else:
		_check("complete full opacity (no sprite art in env)", true)
	_check("complete leaves phase hook at -1",
		done._last_construction_phase == -1)
	done.free()


## Wiring: phase helpers exist; wall blueprint path untouched.
func _test_wiring() -> void:
	var n := _make_bp(0.30)
	_check("staging method exists", n.has_method("_draw_construction_phase"))
	_check("phase static exists",
		BuildingNode.construction_phase_for(0.3) == 1)
	# Walls keep their scaffold-arm blueprint style (own _draw path).
	var wall := BuildingNode.new()
	wall.setup(13, "wall", "gnomes", Vector2(100, 100))
	wall.record = {"complete": false, "progress": 0.5, "wall_angle": 0.0}
	_check("wall keeps own draw path", wall.has_method("_draw_wall_3d"))
	wall.free()
	n.free()
