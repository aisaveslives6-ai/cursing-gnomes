extends SceneTree
## Cursing Gnomes — CPU optimization regression tests (Jeremy 2026-10-04).
##
## Jeremy: "I want all focus on optimization. Let's not stop until 60fps
## without losing any features"
##
## Guards the round-2 CPU optimizations (structural verification):
##   1. combat._tick_bleed: early-out before _ensure_gore_fields
##   2. unit_node.set_limb_state: integer bitmask (not string format)
##   3. combat blood trails: 10Hz throttle accumulator exists
##   4. phone._mark_seen: 1Hz throttle accumulator exists
##   5. pathfinding: map key cache variables exist
##   6. monasteries: effect timer 10Hz throttle exists
##   7. dark crystals: effect timer 10Hz throttle exists
##
## Run: Godot --headless --path . -s res://tests/test_cpu_opt.gd


var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("  FAIL: ", name)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_limb_bitmask_type()
	_test_blood_throttle_var()
	_test_phone_seen_var()
	_test_pathfinding_cache_vars()
	_test_monastery_fx_var()
	_test_crystal_fx_var()
	_test_source_patterns()
	print("cpu_opt: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## 2. Limb state uses integer bitmask.
func _test_limb_bitmask_type() -> void:
	var src := _read("res://scripts/world/unit_node.gd")
	# Must use integer bitmask, not string formatting
	_check('key |= 8' in src, "limbs: uses integer bitmask (key |= 8)")
	_check('key == 15' in src, "limbs: compares int 15 (was string 1111)")
	var un = load("res://scripts/world/unit_node.gd").new()
	_check(un._last_limbs_key == -1, "limbs: _last_limbs_key init to -1 (int)")
	_check(typeof(un._last_limbs_key) == TYPE_INT, "limbs: _last_limbs_key is int")
	un.queue_free()


## 3. Blood trail throttle accumulator.
func _test_blood_throttle_var() -> void:
	var src := _read("res://scripts/sim/combat.gd")
	_check("var _blood_accum" in src, "blood: _blood_accum variable exists")


## 4. Phone seen throttle.
func _test_phone_seen_var() -> void:
	var src := _read("res://scripts/sim/phone.gd")
	_check("var _seen_last_t" in src, "phone: _seen_last_t variable exists")


## 5. Pathfinding key cache.
func _test_pathfinding_cache_vars() -> void:
	var src := _read("res://scripts/sim/pathfinding.gd")
	_check("_cached_map_key" in src, "pathfinding: _cached_map_key exists")
	_check("_cached_key_size" in src, "pathfinding: _cached_key_size exists")


## 6. Monastery FX throttle.
func _test_monastery_fx_var() -> void:
	var src := _read("res://scripts/sim/monasteries.gd")
	_check("var _fx_accum" in src, "monasteries: _fx_accum variable exists")


## 7. Crystal FX throttle.
func _test_crystal_fx_var() -> void:
	var src := _read("res://scripts/sim/dark_crystals.gd")
	_check("var _fx_accum" in src, "crystals: _fx_accum variable exists")


## Verify the actual code patterns (early-outs, throttles).
func _test_source_patterns() -> void:
	var combat_src := _read("res://scripts/sim/combat.gd")
	# _tick_bleed must check injured/bleed BEFORE _ensure_gore_fields
	var bleed_pos := combat_src.find("func _tick_bleed")
	var ensure_pos := combat_src.find("_ensure_gore_fields(u)", bleed_pos)
	var early_pos := combat_src.find('u.get("injured", false)', bleed_pos)
	_check(early_pos > 0 and early_pos < ensure_pos,
		"bleed: early-out check comes before _ensure_gore_fields")
	# Blood trails throttled
	_check("_blood_accum >= 0.1" in combat_src,
		"blood: 10Hz throttle gate present")
	# Phone throttled
	var phone_src := _read("res://scripts/sim/phone.gd")
	_check("now_t - _seen_last_t >= 1.0" in phone_src,
		"phone: 1Hz throttle gate present")
	# Monasteries throttled
	var mon_src := _read("res://scripts/sim/monasteries.gd")
	_check("_fx_accum >= 0.1" in mon_src,
		"monasteries: 10Hz throttle gate present")
	# Crystals throttled
	var cry_src := _read("res://scripts/sim/dark_crystals.gd")
	_check("_fx_accum >= 0.1" in cry_src,
		"crystals: 10Hz throttle gate present")


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var content := f.get_as_text()
	f.close()
	return content
