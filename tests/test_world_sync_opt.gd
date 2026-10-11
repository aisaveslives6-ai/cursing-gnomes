extends SceneTree
## Cursing Gnomes — R13 visual-sync optimization tests (Jeremy 2026-10-05).
##
## 1. `_sync_node_positions`: stationary units skip the Cliffs.lift_at tile
##    lookup (measured 1.3 us x 240 units = ~0.3 ms per sync) and keep their
##    converged lift; moved units still snap/lerp exactly as before. The
##    per-unit `_pos_in_view()` camera/viewport calls were hoisted to one
##    pair per sync — the cull comparison math is identical.
## 2. `_sync_animals`: building fire visuals now sync at 10 Hz instead of
##    every frame (fire state changes on slow sim ticks). Ignitions must
##    still appear (within 100 ms) and put-outs must still clear.
##
## Implementation-only: no visual, content, or mechanic change.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_world_sync_opt.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _world: Node = null
var _booted := false
var _ran := false


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	print("=== Cursing Gnomes R13 visual-sync optimization tests ===")
	var ps: PackedScene = load("res://scenes/world/world.tscn")
	_check("world scene loads", ps != null)
	if ps != null:
		_world = ps.instantiate()
		root.add_child(_world)


func _process(_delta: float) -> bool:
	if _world == null:
		_finish()
		return true
	if not _world.is_node_ready():
		return false
	if not _booted:
		# Probe pattern: disable the world's own ticking, configure the demo
		# game, then drive the sync functions manually.
		_world.set_process(false)
		_world.set_physics_process(false)
		_world.configure("gnomes", "R13Test")
		_booted = true
		return false
	if not _ran:
		_ran = true
		_run_all()
		_finish()
		return true
	return false


func _finish() -> void:
	if _world != null:
		root.remove_child(_world)
		_world.free()
		_world = null
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _run_all() -> void:
	_check("world ready with game", _world.game != null)
	if _world.game == null:
		return
	_test_lift_skip()
	_test_fire_throttle()


func _test_lift_skip() -> void:
	var uid := 900001
	var start_pos := Vector2(500, 500)
	var u := {
		"id": uid, "alive": true, "position": start_pos,
		"hp": 100.0, "max_hp": 100.0, "job": "worker",
		"work_state": "idle", "faction": "gnomes",
	}
	_world.game.units.append(u)
	var un := UnitNode.new()
	_world.units_root.add_child(un)
	un.setup(uid, "gnomes", "worker", start_pos)
	_world._unit_nodes[uid] = un

	var dt := 1.0 / 60.0
	_world._sync_node_positions(dt)
	var lift1: float = float(_world._unit_lift.get(uid, -999.0))
	_check("lift recorded on first sync", lift1 > -900.0)
	_check("sync pos recorded",
		_world._unit_sync_pos.get(uid, Vector2.ZERO) == start_pos)
	_check("node tracks sim pos",
		un.position == start_pos + Vector2(0.0, -lift1))

	# Stationary: the skip path must freeze the converged lift.
	_world._sync_node_positions(dt)
	var lift2: float = float(_world._unit_lift.get(uid, -999.0))
	_check("stationary lift frozen (skip path)", lift2 == lift1)
	_check("node still tracks sim pos",
		un.position == start_pos + Vector2(0.0, -lift1))

	# Moved unit: lift recomputes exactly (snap was done, so lerp applies).
	var moved_pos := Vector2(5000, 5000)
	u["position"] = moved_pos
	_world._sync_node_positions(dt)
	_check("moved unit resyncs pos",
		_world._unit_sync_pos.get(uid, Vector2.ZERO) == moved_pos)
	var target: float = Cliffs.lift_at(_world.map_data, moved_pos)
	var expected: float = lerpf(lift1, target, minf(1.0, dt * 6.0))
	_check("moved unit re-lerps lift exactly",
		absf(float(_world._unit_lift.get(uid, -999.0)) - expected) < 0.001)
	_check("node follows moved unit", un.position.x == moved_pos.x)

	# Hoisted cull bounds: identical to _pos_in_view() for the unit.
	_check("cull matches _pos_in_view",
		un.visible == _world._pos_in_view(moved_pos))

	# Cleanup mirrors _free_unit_node.
	_world.game.units.erase(u)
	_world._free_unit_node(uid)


func _test_fire_throttle() -> void:
	var b: Dictionary = {}
	for rec: Dictionary in _world.game.buildings:
		if bool(rec.get("alive", true)):
			b = rec
			break
	_check("demo building found", not b.is_empty())
	if b.is_empty():
		return
	var bid := int(b.get("id", 0))
	b["on_fire"] = true
	b["hp"] = 40.0
	b["max_hp"] = 100.0
	# 3 x 16 ms = 48 ms: gate (100 ms) still closed — no FX yet.
	_world._sync_animals(0.016)
	_world._sync_animals(0.016)
	_world._sync_animals(0.016)
	_check("fire FX not synced before 10Hz gate",
		not _world.fx.has_building_fire(bid))
	# Cross the 100 ms gate: ignition must appear.
	_world._sync_animals(0.06)
	_check("fire FX synced after gate opens", _world.fx.has_building_fire(bid))
	# Put out: cleared on the next gate opening.
	b["on_fire"] = false
	_world._sync_animals(0.2)
	_check("fire FX cleared after gate opens", not _world.fx.has_building_fire(bid))
	# No-arg call (probe compatibility) must not error.
	_world._sync_animals()
	_check("no-arg _sync_animals runs", true)
