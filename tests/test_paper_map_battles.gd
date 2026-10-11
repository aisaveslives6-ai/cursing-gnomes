extends SceneTree
## Cursing Gnomes — paper map battle marker tests.
##
## HTML parity (fix79 buildPaperMapCache): the paper map draws a clash marker
## wherever opposing forces meet — every 3rd unit sampled, marker fires when
## an alive non-downed unit of a different faction is within clash radius,
## max 14 markers, deduped within 50 cache-px. Covers
## PaperMap.battle_markers() (pure logic); the draw pass itself just maps
## those world positions through _world_to_map and strokes crossed swords.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_paper_map_battles.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes paper map battle marker tests ===")
	_test_clash_detected()
	_test_same_faction_no_marker()
	_test_far_enemies_no_marker()
	_test_dead_unit_no_marker()
	_test_downed_enemy_no_marker()
	_test_lookahead_window()
	_test_marker_cap()
	_test_dedup()
	_test_empty()
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


func _unit(faction: String, pos: Vector2, alive := true,
		downed := false) -> Dictionary:
	return {"faction": faction, "position": pos, "alive": alive,
		"downed": downed}


func _test_clash_detected() -> void:
	var units: Array = [
		_unit("gnomes", Vector2(100, 100)),
		_unit("ogres", Vector2(110, 110)),
	]
	var marks: Array[Vector2] = PaperMap.battle_markers(
		units, Vector2(4096, 4096))
	_check("clash: one marker", marks.size() == 1)
	if marks.size() == 1:
		_check("clash: marker at sampled unit",
			marks[0].distance_to(Vector2(100, 100)) < 1.0)


func _test_same_faction_no_marker() -> void:
	var units: Array = [
		_unit("gnomes", Vector2(100, 100)),
		_unit("gnomes", Vector2(110, 110)),
	]
	_check("same faction: no marker",
		PaperMap.battle_markers(units, Vector2(4096, 4096)).is_empty())


func _test_far_enemies_no_marker() -> void:
	var units: Array = [
		_unit("gnomes", Vector2(100, 100)),
		_unit("ogres", Vector2(1000, 1000)),
	]
	_check("far enemies: no marker",
		PaperMap.battle_markers(units, Vector2(4096, 4096)).is_empty())


func _test_dead_unit_no_marker() -> void:
	var units: Array = [
		_unit("gnomes", Vector2(100, 100), false),
		_unit("ogres", Vector2(110, 110)),
	]
	_check("dead sampled unit: no marker",
		PaperMap.battle_markers(units, Vector2(4096, 4096)).is_empty())


func _test_downed_enemy_no_marker() -> void:
	var units: Array = [
		_unit("gnomes", Vector2(100, 100)),
		_unit("ogres", Vector2(110, 110), true, true),
	]
	_check("downed enemy: no marker",
		PaperMap.battle_markers(units, Vector2(4096, 4096)).is_empty())


func _test_lookahead_window() -> void:
	# Enemy 61 slots later is outside the i+60 lookahead (HTML parity).
	var units: Array = [_unit("gnomes", Vector2(100, 100))]
	for k in 60:
		units.append(_unit("gnomes", Vector2(2000, 2000)))
	units.append(_unit("ogres", Vector2(110, 110)))
	_check("enemy beyond lookahead: no marker",
		PaperMap.battle_markers(units, Vector2(4096, 4096)).is_empty())


func _test_marker_cap() -> void:
	# 20 well-separated clashes; HTML caps at 14 markers.
	var units: Array = []
	for k in 20:
		var bx := 500.0 * k + 50.0
		units.append(_unit("gnomes", Vector2(bx, 100)))
		units.append(_unit("ogres", Vector2(bx + 10, 100)))
		units.append(_unit("gnomes", Vector2(3000, 3000)))
	var marks: Array[Vector2] = PaperMap.battle_markers(
		units, Vector2(4096, 4096))
	_check("cap: exactly 14 markers", marks.size() == 14)


func _test_dedup() -> void:
	# Two clashes 50 world units apart (< 186 dedup radius) merge to one.
	var units: Array = [
		_unit("gnomes", Vector2(100, 100)),
		_unit("ogres", Vector2(110, 110)),
		_unit("gnomes", Vector2(3000, 3000)),
		_unit("gnomes", Vector2(150, 100)),
		_unit("ogres", Vector2(160, 100)),
		_unit("gnomes", Vector2(3000, 3100)),
	]
	var marks: Array[Vector2] = PaperMap.battle_markers(
		units, Vector2(4096, 4096))
	_check("dedup: one marker", marks.size() == 1)


func _test_empty() -> void:
	_check("empty: no markers",
		PaperMap.battle_markers([], Vector2(4096, 4096)).is_empty())
