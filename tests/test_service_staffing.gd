extends SceneTree
## Cursing Gnomes — service staffing town-cap regression test (Jeremy 2026-10-03).
##
## Jeremy reported the guild master never spawns ("Nothing spawns. It doesn't
## even function"). Root cause: "guild_master" (and "guard") were missing from
## Config.ESSENTIAL_JOBS, so once a town filled to POP_CAP_TOWN, tick_service's
## spawn_unit hit the per-town cap and silently returned {} on every 10 s retry.
## Firefighters/doctors already bypassed the town cap; the guild hall and guard
## house are in the same auto-staff category (SimBuildings.SERVICE_BUILDINGS),
## so their service jobs get the same bypass. Faction/global caps (Jeremy's
## 48/240 law) are still enforced by check_spawn — this changes only the
## per-town gate.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_service_staffing.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes service staffing town-cap tests ===")
	_test_guild_master_spawns_in_full_town()
	_test_guards_spawn_in_full_town()
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


## Fresh game + systems bundle.
func _new_world(factions: Array[String]) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	var w := {
		"gs": gs,
		"buildings": SimBuildings.new(gs),
	}
	return w


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _found(w: Dictionary, faction: String) -> int:
	var gs: GameState = w["gs"]
	var town: Dictionary = gs.found_town(faction, "T", Vector2(500, 500))
	var hall: Dictionary = (w["buildings"] as SimBuildings).place_blueprint(
		"town_hall", faction, int(town["id"]), Vector2(500, 500))
	hall["complete"] = true
	hall["progress"] = 1.0
	return int(town["id"])


func _give(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	for res: String in Config.RESOURCES:
		gs.resources.add_resource(faction, res, 10000.0, true)


## Fills the town to exactly POP_CAP_TOWN with ordinary workers, places the
## given service building completed, ticks staffing, and returns the spawned
## units with the wanted job. The point: staffing must succeed anyway.
func _staff_in_full_town(w: Dictionary, faction: String, tid: int,
		btype: String, job: String) -> Array[Dictionary]:
	var gs: GameState = w["gs"]
	var bs: SimBuildings = w["buildings"]
	# Fill to the town cap with ordinary workers (they do NOT bypass it).
	var pos := Vector2(520, 520)
	var filled := 0
	for i: int in range(Config.POP_CAP_TOWN):
		var u: Dictionary = gs.spawner.spawn_unit(
			faction, "worker", tid, pos + Vector2(i * 4.0, 0.0))
		if u.is_empty():
			break
		filled += 1
	# The bypass gate: check_spawn must allow the service job in a full
	# town (before the unit itself exists — the per-job cap would block a
	# second guild master afterward, which is correct behavior).
	_check("check_spawn ok in full town: " + job,
		gs.spawner.check_spawn(faction, job, tid) == "ok")
	# Place + complete the service building, then tick staffing once.
	var b: Dictionary = bs.place_blueprint(btype, faction, tid,
		Vector2(700, 500))
	b["complete"] = true
	b["_staff_next_try"] = 0.0
	bs.tick_service(b, 0.016)
	# Collect spawned units of the wanted job.
	var out: Array[Dictionary] = []
	for u: Dictionary in gs.units:
		if String(u.get("job", "")) == job:
			out.append(u)
	_check("town filled to cap (%s)" % btype, filled == Config.POP_CAP_TOWN)
	return out


func _test_guild_master_spawns_in_full_town() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var tid: int = _found(w, "gnomes")
	var made: Array[Dictionary] = _staff_in_full_town(
		w, "gnomes", tid, "guild_hall", "guild_master")
	_check("gm spawns in full town", made.size() == 1)
	if not made.is_empty():
		_check("gm job", String(made[0].get("job", "")) == "guild_master")
		_check("gm gov role pinned (phone My Government)",
			String((made[0].get("mind", {}) as Dictionary).get("gov_role", ""))
			== "guild_master")
	# check_spawn agrees: guild master is allowed in a full town.
	var gs: GameState = w["gs"]
	# Faction/global caps still hold (Jeremy's law: 48/240).
	var fp: int = gs.population.get_faction_pop("gnomes")
	_check("faction cap holds", fp <= Config.POP_CAP_FACTION)
	_free_world(w)


func _test_guards_spawn_in_full_town() -> void:
	var w := _new_world(["gnomes"])
	_give(w, "gnomes")
	var tid: int = _found(w, "gnomes")
	var made: Array[Dictionary] = _staff_in_full_town(
		w, "gnomes", tid, "guard_house", "guard")
	_check("guards spawn in full town",
		made.size() == Config.GUARDS_PER_HOUSE)
	var gs: GameState = w["gs"]
	var fp: int = gs.population.get_faction_pop("gnomes")
	_check("faction cap holds", fp <= Config.POP_CAP_FACTION)
	_free_world(w)
