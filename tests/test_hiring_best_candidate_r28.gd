extends SceneTree
## Cursing Gnomes — R28 _best_candidate single-pass parity tests.
##
## Perf R28 merged the three per-open-slot faction-unit scans in
## GuildHiring._best_candidate (nearest seeker, laborer headcount, nearest
## laborer) into one pass. The old helpers (_nearest_seeker,
## _nearest_laborer) still exist, so this file uses them as the oracle:
## for the same position and world state, the new single-pass choice must
## be the identical unit (or {} under the quota floor).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hiring_best_candidate_r28.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes R28 _best_candidate parity tests ===")
	_test_seeker_first_matches_oracle()
	_test_no_seeker_nearest_laborer()
	_test_quota_floor_returns_empty()
	_test_tie_break_by_id()
	_test_after_hire_mutation()
	_test_dead_units_ignored()
	_test_other_faction_ignored()
	_test_unknown_building_zero_pos()
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


## Oracle: the exact pre-R28 three-scan algorithm, calling the untouched
## old helpers. The expected unit (or {}) for position p.
func _oracle(hiring: GuildHiring, p: Dictionary) -> Dictionary:
	var faction: String = String(p["faction"])
	var b: Dictionary = hiring._building_by_id(int(p["building_id"]))
	var bp: Vector2 = b.get("position", Vector2.ZERO) as Vector2 \
		if not b.is_empty() else Vector2.ZERO
	var seeker: Dictionary = hiring._nearest_seeker(faction, bp)
	if not seeker.is_empty():
		return seeker
	var quota: int = hiring._worker_quota(p)
	var laborers: int = 0
	for u: Dictionary in hiring._gs.units:
		if u.get("alive", false) \
				and String(u.get("faction", "")) == faction \
				and String(u.get("job", "")) == "worker":
			laborers += 1
	if laborers <= quota:
		return {}
	return hiring._nearest_laborer(faction, bp)


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.farming = SimFarming.new(gs)
	var hiring := GuildHiring.new(gs)
	gs.hiring = hiring
	var b: Dictionary = gs.add_building({"type": "shop", "faction": "humans",
		"alive": true, "complete": true, "town_id": 0,
		"position": Vector2(500, 500)})
	seed(424242)
	var jobs := ["worker", "worker", "worker", "unemployed", "soldier"]
	for i in 30:
		gs.add_unit({"faction": "humans", "job": String(jobs[i % jobs.size()]),
			"town_id": 0,
			"position": Vector2(randf() * 3000.0, randf() * 3000.0),
			"alive": true, "hp": 100.0, "max_hp": 100.0,
			"home": {"alive": true}})
	return {"gs": gs, "hiring": hiring,
		"p": {"faction": "humans", "town_id": 0, "job": "shopkeeper",
			"spot": "counter", "act": "serve",
			"building_id": int(b.get("id", -1))}}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _ids_match(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() and b.is_empty():
		return true
	if a.is_empty() or b.is_empty():
		return false
	return int(a.get("id", -1)) == int(b.get("id", -1))


func _test_seeker_first_matches_oracle() -> void:
	var w: Dictionary = _new_world()
	var hiring: GuildHiring = w["hiring"]
	hiring._begin_batch()
	var got: Dictionary = hiring._best_candidate(w["p"])
	var want: Dictionary = _oracle(hiring, w["p"])
	_check("seeker-first choice matches oracle",
		_ids_match(got, want) and not got.is_empty())
	hiring._end_batch()
	_free_world(w)


func _test_no_seeker_nearest_laborer() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	# Remove all unemployed: only workers/soldiers remain.
	for u: Dictionary in gs.units:
		if String(u.get("job", "")) == "unemployed":
			u["job"] = "soldier"
	hiring._begin_batch()
	var got: Dictionary = hiring._best_candidate(w["p"])
	var want: Dictionary = _oracle(hiring, w["p"])
	_check("no-seeker laborer choice matches oracle",
		_ids_match(got, want))
	hiring._end_batch()
	_free_world(w)


func _test_quota_floor_returns_empty() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	# Only 2 workers left: quota floor (2 + pop*0.22, low resources bump it
	# higher) blocks hiring -> {}.
	var kept := 0
	for u: Dictionary in gs.units:
		if String(u.get("job", "")) == "worker" and kept < 2:
			kept += 1
		elif String(u.get("job", "")) == "worker":
			u["job"] = "soldier"
		if String(u.get("job", "")) == "unemployed":
			u["job"] = "soldier"
	hiring._begin_batch()
	var got: Dictionary = hiring._best_candidate(w["p"])
	var want: Dictionary = _oracle(hiring, w["p"])
	_check("quota floor: both return empty",
		got.is_empty() and want.is_empty())
	hiring._end_batch()
	_free_world(w)


func _test_tie_break_by_id() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	# Two equidistant unemployed seekers: lower id must win.
	for u: Dictionary in gs.units:
		u["job"] = "soldier"
		u["position"] = Vector2(9000, 9000)
	var a: Dictionary = gs.add_unit({"faction": "humans", "job": "unemployed",
		"town_id": 0, "position": Vector2(600, 500), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "home": {"alive": true}})
	var bb: Dictionary = gs.add_unit({"faction": "humans", "job": "unemployed",
		"town_id": 0, "position": Vector2(600, 500), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "home": {"alive": true}})
	var lo: int = mini(int(a.get("id", 0)), int(bb.get("id", 0)))
	hiring._begin_batch()
	var got: Dictionary = hiring._best_candidate(w["p"])
	_check("tie-break: lower unit id wins (%d)" % lo,
		int(got.get("id", -1)) == lo)
	hiring._end_batch()
	_free_world(w)


func _test_after_hire_mutation() -> void:
	var w: Dictionary = _new_world()
	var hiring: GuildHiring = w["hiring"]
	hiring._begin_batch()
	for i in 6:
		var got: Dictionary = hiring._best_candidate(w["p"])
		var want: Dictionary = _oracle(hiring, w["p"])
		if not _ids_match(got, want):
			_check("post-hire parity holds (hire %d)" % i, false)
			hiring._end_batch()
			_free_world(w)
			return
		if got.is_empty():
			break
		hiring._hire(w["p"], got)
	_check("post-hire parity holds across 6 hires", true)
	hiring._end_batch()
	_free_world(w)


func _test_dead_units_ignored() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	for u: Dictionary in gs.units:
		u["alive"] = false
	# One dead seeker at the door, one live worker far away.
	gs.add_unit({"faction": "humans", "job": "unemployed", "town_id": 0,
		"position": Vector2(501, 500), "alive": false,
		"hp": 0.0, "max_hp": 100.0, "home": {"alive": true}})
	gs.add_unit({"faction": "humans", "job": "worker", "town_id": 0,
		"position": Vector2(2000, 2000), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "home": {"alive": true}})
	hiring._begin_batch()
	var got: Dictionary = hiring._best_candidate(w["p"])
	var want: Dictionary = _oracle(hiring, w["p"])
	_check("dead units ignored, matches oracle",
		_ids_match(got, want) and got.is_empty())
	hiring._end_batch()
	_free_world(w)


func _test_other_faction_ignored() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	# Foreign seeker camped on the shop door must not be hired.
	gs.add_unit({"faction": "ogres", "job": "unemployed", "town_id": 0,
		"position": Vector2(500, 500), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "home": {"alive": true}})
	hiring._begin_batch()
	var got: Dictionary = hiring._best_candidate(w["p"])
	var want: Dictionary = _oracle(hiring, w["p"])
	_check("foreign faction ignored, matches oracle",
		_ids_match(got, want)
		and String(got.get("faction", "humans")) == "humans")
	hiring._end_batch()
	_free_world(w)


func _test_unknown_building_zero_pos() -> void:
	var w: Dictionary = _new_world()
	var hiring: GuildHiring = w["hiring"]
	var p: Dictionary = {"faction": "humans", "town_id": 0,
		"building_id": -999}
	hiring._begin_batch()
	var got: Dictionary = hiring._best_candidate(p)
	var want: Dictionary = _oracle(hiring, p)
	_check("missing building: zero-pos fallback matches oracle",
		_ids_match(got, want))
	hiring._end_batch()
	_free_world(w)
