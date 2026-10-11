extends SceneTree
## Cursing Gnomes — government advisor spawn tests (Jeremy 2026-10-04).
##
## HTML ensureGovernmentDistrict spawns one advisor per role per faction with
## the government district. The Godot build had only the data contract
## (SimBuildings.GOV_ADVISOR_ROLES) and no spawning at all, so Jeremy saw no
## advisors on the diplomacy board. Spawner.spawn_government_staff() ports it.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gov_advisors.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes government-advisor tests ===")
	_test_spawn_four_roles()
	_test_flags_and_positions()
	_test_idempotent_per_hall()
	_test_skips_existing_role()
	_test_job_registry()
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


func _new_game() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	var out := {"gs": gs, "spawner": Spawner.new(gs)}
	return out


func _free_game(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _hall(pos: Vector2) -> Dictionary:
	return {"position": pos, "complete": true}


func _test_spawn_four_roles() -> void:
	var w := _new_game()
	var gs: GameState = w["gs"]
	var sp: Spawner = w["spawner"]
	var town: Dictionary = gs.found_town("humans", "T", Vector2(500, 500))
	var spawned: Array = sp.spawn_government_staff(
		"humans", int(town["id"]), _hall(Vector2(500, 500)))
	_check("adv: spawns 4 staff", spawned.size() == 4)
	var jobs: Array[String] = []
	for u: Dictionary in spawned:
		jobs.append(String(u.get("job", "")))
	_check("adv: economy advisor spawned", "advisor_economy" in jobs)
	_check("adv: war advisor spawned", "advisor_war" in jobs)
	_check("adv: civic advisor spawned", "advisor_civic" in jobs)
	_check("adv: clerk spawned", "clerk" in jobs)
	_check("adv: faction stamped", spawned[0].get("faction", "") == "humans")
	_free_game(w)


func _test_flags_and_positions() -> void:
	var w := _new_game()
	var gs: GameState = w["gs"]
	var sp: Spawner = w["spawner"]
	var town: Dictionary = gs.found_town("humans", "T", Vector2(500, 500))
	var spawned: Array = sp.spawn_government_staff(
		"humans", int(town["id"]), _hall(Vector2(500, 500)))
	# HTML: hall.x - 40 + i * 28, hall.y - cell * 2.5 (cell = 96 -> -240).
	var want := [
		Vector2(460, 260), Vector2(488, 260),
		Vector2(516, 260), Vector2(544, 260),
	]
	var flags_ok := true
	var pos_ok := true
	var role_ok := true
	for i: int in range(spawned.size()):
		var u: Dictionary = spawned[i]
		if not bool(u.get("is_advisor", false)) \
				or bool(u.get("is_worker", true)):
			flags_ok = false
		if String(u.get("advisor_role", "")) == "":
			role_ok = false
		var p: Vector2 = u.get("position", Vector2.ZERO)
		if p.distance_to(want[i]) > 0.001:
			pos_ok = false
	_check("adv: is_advisor true, is_worker false", flags_ok)
	_check("adv: advisor_role label stamped", role_ok)
	_check("adv: HTML spawn offsets", pos_ok)
	_free_game(w)


func _test_idempotent_per_hall() -> void:
	var w := _new_game()
	var gs: GameState = w["gs"]
	var sp: Spawner = w["spawner"]
	var town: Dictionary = gs.found_town("humans", "T", Vector2(500, 500))
	var hall := _hall(Vector2(500, 500))
	var first: Array = sp.spawn_government_staff(
		"humans", int(town["id"]), hall)
	var second: Array = sp.spawn_government_staff(
		"humans", int(town["id"]), hall)
	_check("adv: first call spawns 4", first.size() == 4)
	_check("adv: second call spawns 0 (idempotent)",
		second.is_empty())
	_check("adv: still exactly 4 advisor units in game state",
		_count_advisors(gs, "humans") == 4)
	_free_game(w)


func _test_skips_existing_role() -> void:
	var w := _new_game()
	var gs: GameState = w["gs"]
	var sp: Spawner = w["spawner"]
	var town: Dictionary = gs.found_town("humans", "T", Vector2(500, 500))
	# Pre-existing living economy advisor: the staff pass must not double it.
	var pre: Dictionary = sp.spawn_unit(
		"humans", "advisor_economy", int(town["id"]), Vector2(500, 500))
	pre["is_advisor"] = true
	var spawned: Array = sp.spawn_government_staff(
		"humans", int(town["id"]), _hall(Vector2(500, 500)))
	var jobs: Array[String] = []
	for u: Dictionary in spawned:
		jobs.append(String(u.get("job", "")))
	_check("adv: skips already-staffed role", spawned.size() == 3
		and not ("advisor_economy" in jobs))
	_check("adv: exactly one economy advisor total",
		_count_job(gs, "humans", "advisor_economy") == 1)
	_free_game(w)


func _test_job_registry() -> void:
	# Advisor jobs must be known service jobs so staffing/category logic
	# never sees an unknown job id.
	_check("adv: economy job registered",
		JobDefs.job_name("advisor_economy") == "Treasury Advisor")
	_check("adv: advisor jobs are service",
		JobDefs.is_service("advisor_economy")
		and JobDefs.is_service("advisor_war")
		and JobDefs.is_service("advisor_civic"))
	_check("adv: roles match buildings contract",
		(SimBuildings.GOV_ADVISOR_ROLES as Array).size() == 4)


func _count_advisors(gs: GameState, faction: String) -> int:
	var n := 0
	for u: Dictionary in gs.units:
		if u.get("alive", false) and bool(u.get("is_advisor", false)) \
				and String(u.get("faction", "")) == faction:
			n += 1
	return n


func _count_job(gs: GameState, faction: String, job: String) -> int:
	var n := 0
	for u: Dictionary in gs.units:
		if u.get("alive", false) \
				and String(u.get("faction", "")) == faction \
				and String(u.get("job", "")) == job:
			n += 1
	return n
