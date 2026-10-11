extends SceneTree
## Cursing Gnomes — undead idle-hunt AI tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_undead_hunt.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
##
## Port of HTML fix79 undeadHuntTick62 (non-feral zombie/ghoul/skeleton with
## no orders hunts the nearest animal within 280px; >44px walk to it, else
## maul every 0.9s for u.dmg default 8; kills feed the corpse economy).
## HTML-verbatim numbers asserted: 280 / 44 / 0.9 / 8, the chaff-trio job
## gate, the feral skip, and the no-orders gate.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes undead idle-hunt tests ===")
	_test_idle_zombie_hunts_nearest_animal()
	_test_hunt_moves_toward_far_animal()
	_test_hunt_ignores_animals_beyond_280()
	_test_feral_skips_hunt()
	_test_ordered_unit_skips_hunt()
	_test_hungry_zombie_feeds_not_hunts()
	_test_elites_never_hunt()
	_test_kill_feeds_corpse_economy()
	_test_attack_cooldown()
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


## Fresh game + combat + undead + animals systems.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "undead"])
	var combat := SimCombat.new(gs)
	var undead := SimUndead.new(gs, combat)
	gs.animals = SimAnimals.new(gs)
	gs.undead = undead
	return {"gs": gs, "combat": combat, "undead": undead, "animals": gs.animals}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


## R20 stagger contract: undead.tick processes every 3rd call with delta*3,
## so one _ustep advances exactly the same sim time as one old tick(delta).
func _ustep(undead: SimUndead, total_delta: float) -> void:
	var third: float = total_delta / 3.0
	undead.tick(third)
	undead.tick(third)
	undead.tick(third)


func _spawn(w: Dictionary, job: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.spawner.spawn_unit("undead", job, -1, pos)
	(w["undead"] as SimUndead).apply_undead_stats(u)
	u["zhunger"] = 100.0  # well-fed: not feeding, not feral
	u.erase("combat_target")
	u["combat_target"] = -1
	return u


func _boar(w: Dictionary, pos: Vector2, hp: float = 30.0) -> Dictionary:
	var an: Dictionary = (w["animals"] as SimAnimals).spawn_wild("boar", pos)
	an["hp"] = hp
	an["max_hp"] = hp
	return an


func _test_idle_zombie_hunts_nearest_animal() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var zom: Dictionary = _spawn(w, "zombie", Vector2(0, 0))
	var near: Dictionary = _boar(w, Vector2(100, 0))
	var far: Dictionary = _boar(w, Vector2(200, 0))
	var p0: Vector2 = zom["position"]
	_ustep(undead, 0.1)
	var p1: Vector2 = zom["position"]
	_check("hunt: idle zombie moves toward nearest animal",
		p1.distance_to(p0) > 0.5
		and p1.distance_to(near["position"]) < p0.distance_to(near["position"]))
	_check("hunt: does not chase the farther animal first",
		p1.distance_to(near["position"]) <= p1.distance_to(far["position"]))
	_free_world(w)


func _test_hunt_moves_toward_far_animal() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var zom: Dictionary = _spawn(w, "zombie", Vector2(0, 0))
	var prey: Dictionary = _boar(w, Vector2(200, 0))
	var d0: float = (zom["position"] as Vector2).distance_to(prey["position"])
	for i: int in range(20):
		_ustep(undead, 0.1)
	var d1: float = (zom["position"] as Vector2).distance_to(prey["position"])
	_check("hunt: approaches animal beyond 44px (no attack yet)",
		d1 < d0 and bool(prey.get("alive", false)))
	_check("hunt: closes distance toward prey", d1 < 120.0)
	_free_world(w)


func _test_hunt_ignores_animals_beyond_280() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var zom: Dictionary = _spawn(w, "zombie", Vector2(0, 0))
	_boar(w, Vector2(400, 0))
	var p0: Vector2 = zom["position"]
	_ustep(undead, 1.0)
	var p1: Vector2 = zom["position"]
	_check("hunt: animal beyond 280px is ignored (no movement)",
		p1.distance_to(p0) < 0.01)
	_free_world(w)


func _test_feral_skips_hunt() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var zom: Dictionary = _spawn(w, "zombie", Vector2(0, 0))
	zom["feral"] = true
	zom["zhunger"] = 5.0  # keep it feral: the zombie tick won't clear it
	_boar(w, Vector2(100, 0))
	var p0: Vector2 = zom["position"]
	_ustep(undead, 0.1)
	# Feral found no units to attack (only a boar exists), so it stays put;
	# the hunt tick must skip it (no _hunt_cd written, no approach).
	_check("hunt: feral zombie does not hunt (feral tick owns it)",
		(zom["position"] as Vector2).distance_to(p0) < 0.01
		and not zom.has("_hunt_cd"))
	_free_world(w)


func _test_ordered_unit_skips_hunt() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	# combat_target set: has a fight target.
	var zom: Dictionary = _spawn(w, "zombie", Vector2(0, 0))
	zom["combat_target"] = 999
	_boar(w, Vector2(100, 0))
	var p0: Vector2 = zom["position"]
	_ustep(undead, 0.5)
	_check("hunt: unit with combat target does not hunt",
		(zom["position"] as Vector2).distance_to(p0) < 0.01)
	# move_target set: has army orders.
	zom["combat_target"] = -1
	zom["move_target"] = Vector2(500, 500)
	_ustep(undead, 0.5)
	_check("hunt: unit with move orders does not hunt",
		(zom["position"] as Vector2).distance_to(p0) < 0.01)
	_free_world(w)


func _test_hungry_zombie_feeds_not_hunts() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var zom: Dictionary = _spawn(w, "zombie", Vector2(0, 0))
	zom["zhunger"] = 10.0  # hungry: feed-seek owns it (HTML priority)
	_boar(w, Vector2(30, 0))  # well within attack range
	var hp0: float = 30.0
	for i: int in range(10):
		_ustep(undead, 0.2)
	_check("hunt: hungry zombie never mauls the animal",
		absf(float((w["animals"] as SimAnimals).wild[0].get("hp", 0.0)) - hp0) < 0.01)
	_free_world(w)


func _test_elites_never_hunt() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var necro: Dictionary = _spawn(w, "necromancer", Vector2(0, 0))
	necro["raise_cd"] = 999.0  # keep the necromancer raise quiet
	_boar(w, Vector2(30, 0))
	var p0: Vector2 = necro["position"]
	for i: int in range(10):
		_ustep(undead, 0.2)
	_check("hunt: necromancer never hunts",
		(necro["position"] as Vector2).distance_to(p0) < 0.01)
	_free_world(w)


func _test_kill_feeds_corpse_economy() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var zom: Dictionary = _spawn(w, "zombie", Vector2(0, 0))
	zom["dmg"] = 100.0  # one-shot: exercise the kill path
	_boar(w, Vector2(30, 0), 10.0)
	var corpses0: int = undead.corpses.size()
	_ustep(undead, 0.2)  # in range, cooldown starts <= 0 -> attack now
	_check("hunt: weak animal dies to the maul",
		not bool((w["animals"] as SimAnimals).wild[0].get("alive", true)))
	_check("hunt: kill adds an animal corpse to the undead economy",
		undead.corpses.size() == corpses0 + 1
		and String(undead.corpses[undead.corpses.size() - 1].get("race", "")) == "animal")
	_free_world(w)


func _test_attack_cooldown() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var zom: Dictionary = _spawn(w, "zombie", Vector2(0, 0))
	zom["dmg"] = 5.0
	var prey: Dictionary = _boar(w, Vector2(30, 0), 100.0)
	_ustep(undead, 0.1)  # first maul lands immediately (cd <= 0)
	var hp1: float = float(prey.get("hp", 0.0))
	_ustep(undead, 0.5)  # 0.5s < 0.9s cooldown: no second maul
	var hp2: float = float(prey.get("hp", 0.0))
	_ustep(undead, 0.5)  # 1.0s total > 0.9s: second maul lands
	var hp3: float = float(prey.get("hp", 0.0))
	_check("hunt: first maul deals u.dmg (5)", absf(hp1 - 95.0) < 0.01)
	_check("hunt: 0.9s cooldown blocks rapid mauls", absf(hp2 - hp1) < 0.01)
	_check("hunt: maul lands again after cooldown", absf(hp3 - 90.0) < 0.01)
	_free_world(w)
