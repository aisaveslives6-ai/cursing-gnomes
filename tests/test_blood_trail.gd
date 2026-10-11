extends SceneTree
## Cursing Gnomes — blood-trail tests (HTML bloodTrailCd parity).
##
## fix79/index.html: Unit.rollInjury runs on EVERY survived hit and always
## sets `bloodTrailCd = 8` — even light hits leave a trail while the unit is
## injured. The injured unit drips blood particles while the timer runs.
## Godot port:
##   - SimCombat.roll_injury sets blood_trail_cd = 8.0 on any survived hit.
##   - Dead units never trail (damage_unit's kill path returns first).
##   - SimCombat.tick decrements the timer to 0.
##   - CombatFX.blood allocates a "blood" FX without growing the pool.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_blood_trail.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var combat := SimCombat.new(gs)
	return {"gs": gs, "combat": combat}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, hp_frac: float) -> Dictionary:
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1, Vector2(500, 500))
	var mhp: float = float(u.get("max_hp", 100.0))
	u["hp"] = mhp * hp_frac
	return u


func _initialize() -> void:
	print("=== Cursing Gnomes blood-trail tests ===")
	_run.call_deferred()


func _run() -> void:
	_test_heavy_hit_starts_trail()
	_test_light_hit_sets_trail()
	_test_dead_unit_no_trail()
	_test_trail_ticks_down()
	_test_fx_blood_allocates()
	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


## A hit that drops the unit below 45% max hp starts the 8 s trail.
func _test_heavy_hit_starts_trail() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u := _spawn(w, 0.5)
	var uid: int = int(u.get("id", 0))
	var mhp: float = float(u.get("max_hp", 100.0))
	combat.damage_unit(uid, mhp * 0.2, "ogres", -1, "melee")
	var rec: Dictionary = gs.get_unit(uid)
	_check("heavy hit: unit survived", bool(rec.get("alive", false)))
	_check("heavy hit: hp below 45%",
		float(rec.get("hp", 0.0)) < mhp * 0.45)
	_check("heavy hit: blood_trail_cd == 8.0",
		is_equal_approx(float(rec.get("blood_trail_cd", 0.0)), 8.0))
	_free_world(w)


## HTML parity: rollInjury runs on EVERY survived hit and always sets
## bloodTrailCd = 8 — even a light hit leaves the unit injured and trailing.
func _test_light_hit_sets_trail() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u := _spawn(w, 1.0)
	var uid: int = int(u.get("id", 0))
	var mhp: float = float(u.get("max_hp", 100.0))
	combat.damage_unit(uid, mhp * 0.2, "ogres", -1, "melee")
	var rec: Dictionary = gs.get_unit(uid)
	_check("light hit: hp at/above 45%",
		float(rec.get("hp", 0.0)) >= mhp * 0.45)
	_check("light hit: injury still sets blood trail (HTML rollInjury)",
		is_equal_approx(float(rec.get("blood_trail_cd", 0.0)), 8.0))
	_free_world(w)


## A killing blow never leaves a trail behind.
func _test_dead_unit_no_trail() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u := _spawn(w, 0.5)
	var uid: int = int(u.get("id", 0))
	combat.damage_unit(uid, 99999.0, "ogres", -1, "melee")
	var rec: Dictionary = gs.get_unit(uid)
	_check("killing blow: unit dead", not bool(rec.get("alive", false)))
	_check("killing blow: no blood trail",
		float(rec.get("blood_trail_cd", 0.0)) <= 0.0)
	_free_world(w)


## combat.tick counts the trail timer down to zero.
func _test_trail_ticks_down() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u := _spawn(w, 0.5)
	var uid: int = int(u.get("id", 0))
	var mhp: float = float(u.get("max_hp", 100.0))
	combat.damage_unit(uid, mhp * 0.2, "ogres", -1, "melee")
	_check("trail: armed", float(gs.get_unit(uid).get("blood_trail_cd", 0.0)) > 0.0)
	combat.tick(3.0)
	_check("trail: ticked down to 5.0",
		is_equal_approx(float(gs.get_unit(uid).get("blood_trail_cd", 0.0)), 5.0))
	combat.tick(10.0)
	_check("trail: clamped at 0",
		is_equal_approx(float(gs.get_unit(uid).get("blood_trail_cd", 0.0)), 0.0))
	_free_world(w)


## CombatFX.blood allocates a pooled "blood" FX without growing the pool.
func _test_fx_blood_allocates() -> void:
	var fx := CombatFX.new()
	root.add_child(fx)
	await process_frame
	fx.blood(Vector2(100, 200))
	await process_frame
	_check("fx.blood: allocates a busy slot", _busy_slots(fx) > 0)
	_check("fx.blood: pool size unchanged", fx.get_child_count() == CombatFX.FX_POOL)
	fx.free()


## Count busy FX slots via the pool (no public accessor needed).
func _busy_slots(fx: CombatFX) -> int:
	var n: int = 0
	for s: Dictionary in fx.get("_pool"):
		if bool(s.get("busy", false)):
			n += 1
	return n
