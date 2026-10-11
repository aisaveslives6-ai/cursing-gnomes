extends SceneTree
## Cursing Gnomes — R20 undead-tick stagger tests (2026-10-05).
##
## Perf R20: SimUndead.tick ran a full unit scan every frame (~0.36ms/f
## probe-verified) plus nested plague-cloud scans, flesh-farm scans, corpse
## decay and per-unit infection/ghoul/zombie/hunt work. It now processes every
## 3rd call (20Hz) with delta*3. These tests pin the stagger contract:
##   - ticks 1 and 2 are skipped; the 3rd processes (_tick_frame cadence)
##   - timers move by exactly delta*3 on a processed tick (corpse t, plague t,
##     inf.t, raise_cd, zhunger drain, _hunt_cd, feral_cd)
##   - _roll() compounds per-second rates exactly over the 3 skipped frames
##   - movement averages identical (speed * step per processed _ustep)
##   - infection turn boundary still exact at 25 s
##   - plague nested scan still infects through the stagger (statistical)
##   - _tick_frame is ephemeral (not in to_dict/from_dict)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_undead_stagger.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes undead-stagger (R20) tests ===")
	seed(20261005)
	_test_cadence_skips_two_then_processes()
	_test_timer_parity_delta3()
	_test_roll_rate_statistics()
	_test_infection_turn_boundary()
	_test_movement_parity()
	_test_plague_infect_through_stagger()
	_test_ephemeral_counter()
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


## --- harness (mirrors test_undead_hunt.gd) ------------------------------------

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


## --- contract -----------------------------------------------------------------


func _test_cadence_skips_two_then_processes() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	undead.corpses.append({"x": 0.0, "y": 0.0, "race": "human",
		"job": "worker", "t": 50.0})
	undead.tick(1.0)
	_check("stagger: 1st tick skipped",
		float(undead.corpses[0].get("t", 0.0)) == 50.0)
	undead.tick(1.0)
	_check("stagger: 2nd tick skipped",
		float(undead.corpses[0].get("t", 0.0)) == 50.0)
	undead.tick(1.0)
	_check("stagger: 3rd tick decays corpse by 3x delta",
		absf(float(undead.corpses[0].get("t", 0.0)) - 47.0) < 0.0001)
	_free_world(w)


func _test_timer_parity_delta3() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	# Plague cloud timer.
	undead.plague_clouds.append({"x": 0.0, "y": 0.0, "t": 8.0})
	# Infection incubation timer on a living unit.
	var gs: GameState = w["gs"]
	var victim: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(500, 500))
	undead.infect_unit(victim, "test")
	# Necromancer raise cooldown.
	var necro: Dictionary = _spawn(w, "necromancer", Vector2(0, 0))
	necro["raise_cd"] = 999.0  # keep the raise roll quiet
	# Normal zombie: hunger + hunt cooldown parity (needs prey in range for
	# _hunt_cd to decay — hunt returns before the decay when nothing is near).
	var zom: Dictionary = _spawn(w, "zombie", Vector2(0, 0))
	_boar(w, Vector2(100, 0))
	zom["_hunt_cd"] = 1.5
	var zh0: float = float(zom.get("zhunger", 0.0))
	# Feral zombie far from everyone: feral_cd parity (feral_cd only decays
	# inside _tick_feral; the scan finds no units so no attack/cd reset).
	var fzom: Dictionary = _spawn(w, "zombie", Vector2(900, 900))
	fzom["zhunger"] = 5.0
	fzom["feral"] = true
	fzom["feral_cd"] = 2.0
	_ustep(undead, 1.0)  # processed once with delta = 1.0
	_check("timers: plague cloud decays by 1.0",
		absf(float(undead.plague_clouds[0].get("t", 0.0)) - 7.0) < 0.0001)
	_check("timers: infection t grows by 1.0",
		absf(float((victim["infected"] as Dictionary).get("t", 0.0)) - 1.0)
		< 0.0001)
	_check("timers: raise_cd decays by 1.0",
		absf(float(necro.get("raise_cd", 0.0)) - 998.0) < 0.0001)
	_check("timers: feral_cd decays by 1.0",
		absf(float(fzom.get("feral_cd", 0.0)) - 1.0) < 0.0001)
	_check("timers: feral state holds (zhunger still critical)",
		bool(fzom.get("feral", false)))
	_check("timers: _hunt_cd decays by 1.0",
		absf(float(zom.get("_hunt_cd", 0.0)) - 0.5) < 0.0001)
	var drain: float = SimUndead.HUNGER_DRAIN_PER_S
	_check("timers: zhunger drains exactly drain*1.0",
		absf(float(zom.get("zhunger", 0.0)) - (zh0 - drain)) < 0.0001)
	# Corpse expiry still flows through the stagger: t hits 0 -> removed.
	undead.corpses.append({"x": 10.0, "y": 10.0, "race": "human",
		"job": "worker", "t": 0.5})
	_ustep(undead, 1.0)
	_check("timers: corpse with 0.5 s expires after a 1.0 s step",
		undead.corpses.is_empty())
	_free_world(w)


func _test_roll_rate_statistics() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	# _roll(1.2, 0.1) must match P(>=1 success in 3 frames) exactly:
	# 1 - (1 - 1.2*0.1/3)^3 = 1 - 0.96^3 = 0.115264.
	var expected: float = 1.0 - pow(1.0 - 1.2 * 0.1 / 3.0, 3.0)
	_check("roll: closed form sanity",
		absf(expected - 0.115264) < 0.000001)
	var hits: int = 0
	var n: int = 20000
	for i: int in range(n):
		if undead._roll(1.2, 0.1):
			hits += 1
	var observed: float = float(hits) / float(n)
	_check("roll: sampled rate within 5 sigma of exact compounding",
		absf(observed - expected) < 0.012)
	_free_world(w)


func _test_infection_turn_boundary() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var gs: GameState = w["gs"]
	var victim: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(500, 500))
	undead.infect_unit(victim, "test")
	(victim["infected"] as Dictionary)["t"] = 24.0
	_ustep(undead, 1.0)  # t -> 25.0, exactly the INFECT_TURN_TIME boundary
	_check("infection: turns at exactly 25 s through the stagger",
		String(victim.get("faction", "")) == "undead"
		and String(victim.get("job", "")) == "zombie")
	_free_world(w)


func _test_movement_parity() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	# Zombie (speed 57) hunts a boar at 200 px: one _ustep(1.0) processes
	# once with delta = 1.0, so it must close exactly 57 px like the old
	# per-frame tick(1.0) did.
	var zom: Dictionary = _spawn(w, "zombie", Vector2(0, 0))
	_boar(w, Vector2(200, 0))
	var d0: float = ((zom["position"] as Vector2) - Vector2(200, 0)).length()
	_ustep(undead, 1.0)
	var d1: float = ((zom["position"] as Vector2) - Vector2(200, 0)).length()
	var expected: float = float(
		SimUndead.UNDEAD_ROSTER["zombie"]["speed"]) * 1.0
	_check("movement: hunt closes exactly speed*step per processed tick",
		absf((d0 - d1) - expected) < 0.01)
	_free_world(w)


func _test_plague_infect_through_stagger() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var gs: GameState = w["gs"]
	undead.plague_clouds.append({"x": 0.0, "y": 0.0,
		"t": float(SimUndead.PLAGUE_DURATION)})
	var victim: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(10, 0))
	# Per _ustep(0.5): p = 1-(1-1.2*0.5/3)^3 = 0.488; 20 steps miss with
	# probability 0.512^20 ~ 1e-6. Seeded run is deterministic anyway.
	var infected: bool = false
	for i: int in range(20):
		_ustep(undead, 0.5)
		if victim.has("infected"):
			infected = true
			break
	_check("plague: nested scan still infects through the stagger", infected)
	_free_world(w)


func _test_ephemeral_counter() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	_check("stagger: fresh instance counter starts at 0",
		int(undead._tick_frame) == 0)
	undead.tick(0.1)
	_check("stagger: skipped ticks still advance the counter",
		int(undead._tick_frame) == 1)
	var d: Dictionary = undead.to_dict()
	_check("stagger: counter not persisted in to_dict",
		not d.has("_tick_frame"))
	var undead2 := SimUndead.new(w["gs"], w["combat"])
	undead2.from_dict(d)
	_check("stagger: counter resets to 0 after load",
		int(undead2._tick_frame) == 0)
	# RefCounted: no manual free needed; the gs teardown releases it.
	_free_world(w)
