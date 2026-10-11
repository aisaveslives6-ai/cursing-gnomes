extends SceneTree
## Cursing Gnomes — R34 idle-retry-backoff regression tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_idle_retry_r34.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: WorkerAI._pick_task skips the full task scan for
## IDLE_RETRY_TICKS of a unit's own AI slices after a scan that found
## nothing (R34 perf fix); the scan resumes after the backoff expires;
## a successful assignment clears the backoff; the backoff is per-unit.


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
	print("=== Cursing Gnomes idle-retry R34 tests ===")
	_test_backoff_skips_rescan()
	_test_scan_resumes_after_backoff()
	_test_success_clears_backoff()
	_test_backoff_is_per_unit()
	_test_non_idle_unit_unaffected()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	# One town hall so dropoff paths resolve; no patients, no blueprints,
	# no sites — an idle doctor/builder finds nothing to do.
	gs.add_building({"faction": "humans", "type": "town_hall", "alive": true,
		"complete": true, "position": Vector2(2048, 2048)})
	var wai := WorkerAI.new(gs)
	var bld := SimBuildings.new(gs)
	return [gs, wai, bld]


func _doc(gs: GameState, pos: Vector2) -> Dictionary:
	return gs.add_unit({"faction": "humans", "job": "doctor", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 30.0, "work_state": "idle", "carrying": {}, "carry_cap": 10.0})


func _tick(wai: WorkerAI, bld: SimBuildings, u: Dictionary, n: int) -> void:
	for _i in range(n):
		wai.tick_unit(u, bld, 1.0 / 30.0)


func _test_backoff_skips_rescan() -> void:
	var w: Array = _world()
	var wai: WorkerAI = w[1]
	var bld: SimBuildings = w[2]
	var doc: Dictionary = _doc(w[0], Vector2(2000, 2000))
	_tick(wai, bld, doc, 1)
	_check("miss leaves unit idle", String(doc.get("work_state", "")) == "idle")
	_check("miss arms retry_at", int(doc.get("_pick_retry_at", 0)) == 1 + WorkerAI.IDLE_RETRY_TICKS)
	var retry_at: int = int(doc["_pick_retry_at"])
	# A second scan would find the same nothing — it must be skipped, so
	# the clock advancing is the only observable change.
	_tick(wai, bld, doc, 1)
	_check("backoff tick keeps unit idle", String(doc.get("work_state", "")) == "idle")
	_check("backoff does not re-arm retry_at", int(doc.get("_pick_retry_at", 0)) == retry_at)
	_check("per-unit clock advanced", int(doc.get("_ai_ticks", 0)) == 2)


func _test_scan_resumes_after_backoff() -> void:
	var w: Array = _world()
	var gs: GameState = w[0]
	var wai: WorkerAI = w[1]
	var bld: SimBuildings = w[2]
	var doc: Dictionary = _doc(gs, Vector2(2000, 2000))
	_tick(wai, bld, doc, 1)
	# A patient appears while the doctor is in backoff: not noticed yet...
	# (patient placed far away so the doctor stays "to_patient" while
	# walking instead of arriving and switching to "healing" mid-test).
	var pat: Dictionary = gs.add_unit({"faction": "humans", "job": "worker",
		"town_id": 1, "position": Vector2(3000, 3000), "alive": true,
		"hp": 10.0, "max_hp": 100.0, "speed": 30.0, "work_state": "idle",
		"carrying": {}, "carry_cap": 10.0})
	_tick(wai, bld, doc, 1)
	_check("patient during backoff not yet noticed",
		String(doc.get("work_state", "")) == "idle")
	# ...but the scan resumes once the backoff expires — bounded delay,
	# never stuck.
	_tick(wai, bld, doc, WorkerAI.IDLE_RETRY_TICKS)
	_check("scan resumes after backoff", String(doc.get("work_state", "")) == "to_patient")
	_check("resumed scan targets the patient",
		int(doc.get("work_building", -1)) == int(pat.get("id", -2)))


func _test_success_clears_backoff() -> void:
	var w: Array = _world()
	var gs: GameState = w[0]
	var wai: WorkerAI = w[1]
	var bld: SimBuildings = w[2]
	var pat: Dictionary = gs.add_unit({"faction": "humans", "job": "worker",
		"town_id": 1, "position": Vector2(2001, 2001), "alive": true,
		"hp": 10.0, "max_hp": 100.0, "speed": 30.0, "work_state": "idle",
		"carrying": {}, "carry_cap": 10.0})
	var doc: Dictionary = _doc(gs, Vector2(2000, 2000))
	_tick(wai, bld, doc, 1)
	_check("doctor takes the patient", String(doc.get("work_state", "")) == "to_patient")
	_check("success erases retry_at", not doc.has("_pick_retry_at"))


func _test_backoff_is_per_unit() -> void:
	var w: Array = _world()
	var gs: GameState = w[0]
	var wai: WorkerAI = w[1]
	var bld: SimBuildings = w[2]
	var doc_a: Dictionary = _doc(gs, Vector2(2000, 2000))
	_tick(wai, bld, doc_a, 1)  # A scans, finds nothing, enters backoff
	var pat: Dictionary = gs.add_unit({"faction": "humans", "job": "worker",
		"town_id": 1, "position": Vector2(2001, 2001), "alive": true,
		"hp": 10.0, "max_hp": 100.0, "speed": 30.0, "work_state": "idle",
		"carrying": {}, "carry_cap": 10.0})
	var doc_b: Dictionary = _doc(gs, Vector2(1999, 1999))
	_tick(wai, bld, doc_b, 1)  # B is fresh: scans immediately
	_check("fresh unit not blocked by other's backoff",
		String(doc_b.get("work_state", "")) == "to_patient")
	_check("backed-off unit still idle",
		String(doc_a.get("work_state", "")) == "idle")


func _test_non_idle_unit_unaffected() -> void:
	var w: Array = _world()
	var wai: WorkerAI = w[1]
	var bld: SimBuildings = w[2]
	var doc: Dictionary = _doc(w[0], Vector2(2000, 2000))
	# Busy units never enter _pick_task: a walker mid-trip keeps walking.
	doc["work_state"] = "to_resource"
	doc["work_target_pos"] = Vector2(3000, 3000)
	_tick(wai, bld, doc, 5)
	_check("busy unit keeps its state", String(doc.get("work_state", "")) == "to_resource")
	_check("busy unit gets no retry_at", not doc.has("_pick_retry_at"))
