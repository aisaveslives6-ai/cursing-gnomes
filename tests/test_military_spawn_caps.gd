extends SceneTree
## Cursing Gnomes — military spawn vs town cap regression tests.
##
## Jeremy 2026-10-06: "They don't even spawn in an army." Root cause:
## SimPopulation.can_spawn_in_town() enforced the 16-unit town cap on
## military graduates, so barracks training in a full town completed and
## silently dropped the graduate. Military is barracks-housed (25 beds),
## not town-housed, so it bypasses the TOWN cap like essential services.
## Faction (48) and global (240) caps still apply to military.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_military_spawn_caps.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes military spawn cap tests ===")
	_test_soldier_spawns_in_full_town()
	_test_worker_still_capped_in_full_town()
	_test_military_blocked_at_faction_cap()
	_test_graduate_drop_notifies()
	_test_archer_ranger_mage_bypass_town_cap()
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


## World with a real town at the 16-unit civilian cap and a barracks in it.
func _full_town_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	gs.player_faction = "humans"
	var hiring := GuildHiring.new(gs)
	gs.hiring = hiring
	seed(1234)
	gs.resources.add_resource("humans", "gold", 100000.0, true)
	gs.resources.add_resource("humans", "wood", 100000.0, true)
	# Real town record so check_spawn's bad_town gate passes.
	gs.towns[7] = {"id": 7, "name": "Testville", "faction": "humans"}
	# Fill the town to exactly the 16-unit cap with civilians.
	for i in 16:
		var u: Dictionary = gs.spawner.spawn_unit(
			"humans", "worker", 7, Vector2(i * 10, 0))
		assert(not u.is_empty(), "setup: civilian spawn failed")
	# Complete barracks in the full town.
	var b: Dictionary = {
		"id": 9001, "type": "barracks", "faction": "humans",
		"alive": true, "complete": true, "town_id": 7,
		"position": Vector2(100, 100),
	}
	gs.buildings.append(b)
	return {"gs": gs, "hiring": hiring, "barracks": b}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


## THE BUG: soldier training in a 16/16 town must produce a soldier.
func _test_soldier_spawns_in_full_town() -> void:
	var w: Dictionary = _full_town_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	var b: Dictionary = w["barracks"]
	_check("town is at cap", gs.population.get_town_pop(7) == 16)
	_check("military bypasses town cap",
		gs.population.can_spawn_in_town(7, "soldier"))
	hiring._maintain_military()
	_check("training queued", not hiring._train_queue(b).is_empty())
	for i in 400:
		hiring._tick_training(0.5)
		if hiring._train_queue(b).is_empty():
			break
	var soldiers := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == "humans" \
				and String(u.get("job", "")) == "soldier":
			soldiers += 1
	_check("soldier graduate spawned in full town", soldiers == 1)
	_check("no silent drop recorded",
		not String(hiring.last_train_block).begins_with("graduate_blocked"))
	_free_world(w)


## Civilians must STILL respect the town cap (bypass is military-only).
func _test_worker_still_capped_in_full_town() -> void:
	var w: Dictionary = _full_town_world()
	var gs: GameState = w["gs"]
	_check("worker still town-capped",
		not gs.population.can_spawn_in_town(7, "worker"))
	_check("check_spawn blocks worker",
		gs.spawner.check_spawn("humans", "worker", 7) == "town_capped")
	_free_world(w)


## Faction cap (48) still blocks military — Jeremy's law stands.
func _test_military_blocked_at_faction_cap() -> void:
	var w: Dictionary = _full_town_world()
	var gs: GameState = w["gs"]
	# Top the faction up to 48 (16 in town + 32 countryside).
	for i in 32:
		var u: Dictionary = gs.spawner.spawn_unit(
			"humans", "worker", -1, Vector2(500 + i * 10, 0))
		assert(not u.is_empty(), "setup: countryside spawn failed")
	_check("faction at cap", gs.population.get_faction_pop("humans") == 48)
	_check("military still faction-capped",
		gs.spawner.check_spawn("humans", "soldier", 7) == "faction_capped")
	_free_world(w)


## When a graduate IS dropped (faction cap), it must not be silent.
func _test_graduate_drop_notifies() -> void:
	var w: Dictionary = _full_town_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	var b: Dictionary = w["barracks"]
	for i in 32:
		gs.spawner.spawn_unit("humans", "worker", -1, Vector2(500 + i * 10, 0))
	var stories: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: stories.append(s))
	hiring._maintain_military()
	_check("training queued at faction cap",
		not hiring._train_queue(b).is_empty())
	for i in 600:
		hiring._tick_training(0.5)
		if hiring._train_queue(b).is_empty():
			break
	_check("queue drained after retries", hiring._train_queue(b).is_empty())
	_check("drop reason recorded",
		String(hiring.last_train_block) == "graduate_blocked_faction_capped")
	var notified := false
	for s: Dictionary in stories:
		if String(s.get("headline", "")) == "TRAINING WASTED":
			notified = true
	_check("TRAINING WASTED gazette emitted", notified)
	_free_world(w)


## All military jobs bypass the town cap, not just soldier.
func _test_archer_ranger_mage_bypass_town_cap() -> void:
	var w: Dictionary = _full_town_world()
	var gs: GameState = w["gs"]
	for job in ["soldier", "archer", "ranger", "mage", "cannoneer"]:
		_check("military bypass: " + job,
			gs.population.can_spawn_in_town(7, job))
	_check("guard still bypasses (essential)", 
		gs.population.can_spawn_in_town(7, "guard"))
	_free_world(w)
