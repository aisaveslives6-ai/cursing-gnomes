extends SceneTree
## Cursing Gnomes — hiring batch index tests (R21).
##
## The 4 s hiring batch builds a per-faction unit index so the per-position
## scans (scan_positions holders, _best_candidate seekers/laborers/quota,
## _farm_seekers) iterate the faction's slice instead of all units.
## These tests pin the contract: index contents, order, fallback outside a
## batch, determinism of hiring outcomes, and quota memo correctness.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hiring_batch_index.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hiring batch index tests ===")
	_test_faction_units_matches_manual_filter()
	_test_fallback_outside_batch()
	_test_index_cleared_after_batch()
	_test_hiring_deterministic()
	_test_quota_memo_consistent()
	_test_scan_positions_standalone()
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


## Two identical seeded worlds for determinism checks.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	gs.farming = SimFarming.new(gs)
	var hiring := GuildHiring.new(gs)
	gs.hiring = hiring
	seed(90210)
	var bx := 0.0
	for f: String in ["humans", "ogres"]:
		for bt: String in ["town_hall", "shop", "shop", "storage", "clinic"]:
			bx += 211.0
			gs.add_building({"type": bt, "faction": f, "alive": true,
				"complete": true, "town_id": 0,
				"position": Vector2(500.0 + bx, 500.0)})
		for i in 20:
			gs.add_unit({"faction": f, "job": "worker", "town_id": 0,
				"position": Vector2(randf() * 3000.0, randf() * 3000.0),
				"alive": true, "hp": 100.0, "max_hp": 100.0,
				"home": {"alive": true}})
		for i in 6:
			gs.add_unit({"faction": f, "job": "unemployed", "town_id": 0,
				"position": Vector2(randf() * 3000.0, randf() * 3000.0),
				"alive": true, "hp": 100.0, "max_hp": 100.0,
				"home": {"alive": true}})
		# One dead unit: the index must skip it.
		var dead: Dictionary = gs.add_unit({"faction": f, "job": "worker",
			"town_id": 0, "position": Vector2(10, 10), "alive": false,
			"hp": 0.0, "max_hp": 100.0, "home": {"alive": true}})
		dead["alive"] = false
	return {"gs": gs, "hiring": hiring}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _manual_filter(gs: GameState, faction: String) -> Array:
	var out: Array = []
	for u: Dictionary in gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == faction:
			out.append(int(u.get("id", -1)))
	return out


func _test_faction_units_matches_manual_filter() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	hiring._begin_batch()
	for f: String in ["humans", "ogres"]:
		var got: Array = []
		for u: Dictionary in hiring._faction_units(f):
			got.append(int(u.get("id", -1)))
		_check("index: %s matches manual filter, _gs.units order" % f,
			got == _manual_filter(gs, f))
	_check("index: unknown faction -> empty",
		(hiring._faction_units("gnomes") as Array).is_empty())
	hiring._end_batch()
	_free_world(w)


func _test_fallback_outside_batch() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	# No batch active: _faction_units filters _gs.units directly.
	for f: String in ["humans", "ogres"]:
		var got: Array = []
		for u: Dictionary in hiring._faction_units(f):
			got.append(int(u.get("id", -1)))
		_check("fallback: %s matches manual filter" % f,
			got == _manual_filter(gs, f))
	_free_world(w)


func _test_index_cleared_after_batch() -> void:
	var w: Dictionary = _new_world()
	var hiring: GuildHiring = w["hiring"]
	hiring.tick(4.0, 12.0)
	_check("index: cleared after batch", hiring._batch_units.is_empty())
	_check("index: quota cache cleared after batch",
		hiring._quota_cache.is_empty())
	_free_world(w)


func _snapshot(gs: GameState) -> Dictionary:
	var snap: Dictionary = {}
	for u: Dictionary in gs.units:
		var st: Dictionary = u.get("station", {})
		snap[int(u.get("id", -1))] = "%s|%d" % [
			String(u.get("job", "")),
			int(st.get("building_id", -1))]
	return snap


func _test_hiring_deterministic() -> void:
	var w1: Dictionary = _new_world()
	var w2: Dictionary = _new_world()
	(w1["hiring"] as GuildHiring).tick(4.0, 12.0)
	(w2["hiring"] as GuildHiring).tick(4.0, 12.0)
	var s1: Dictionary = _snapshot(w1["gs"])
	var s2: Dictionary = _snapshot(w2["gs"])
	_check("hiring: identical seeded batches hire identically", s1 == s2)
	# And something was actually hired (not a vacuous pass).
	var hired := 0
	for k in s1.keys():
		if String(s1[k]).begins_with("shopkeeper|") \
				or String(s1[k]).begins_with("cashier|") \
				or String(s1[k]).begins_with("clerk|"):
			hired += 1
	_check("hiring: batch filled positions (hired=%d)" % hired, hired > 0)
	_free_world(w1)
	_free_world(w2)


func _test_quota_memo_consistent() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	hiring._begin_batch()
	var p: Dictionary = {"faction": "humans", "town_id": 0}
	var q1: int = hiring._worker_quota(p)
	var q2: int = hiring._worker_quota(p)
	_check("quota: memoized value stable", q1 == q2 and q1 > 0)
	_check("quota: cache has humans|0", hiring._quota_cache.has("humans|0"))
	hiring._end_batch()
	_free_world(w)


func _test_scan_positions_standalone() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	# Standalone (no batch): fallback path must still find positions.
	var positions: Array = hiring.scan_positions()
	_check("scan_positions: finds positions standalone",
		positions.size() > 0)
	var jobs: Dictionary = {}
	for p: Dictionary in positions:
		jobs[String(p["job"])] = true
	_check("scan_positions: shopkeeper among them", jobs.has("shopkeeper"))
	_free_world(w)
