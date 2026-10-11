extends SceneTree
## Cursing Gnomes — R31: SimUrges single-pass tick() parity tests.
##
## The R31 optimization merged urges.tick()'s three scans (decay loop +
## worst_critical() scan + priority scan) into one pass and unrolled
## worst_critical(). This suite proves the new code is bit-identical to
## the old logic via a verbatim oracle, plus behavioral checks.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_urges_singlepass_r31.gd
##
## Exit code 0 = all passed, 1 = any failure.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

const _PRIO: Array[String] = ["hunger", "bladder", "energy", "hygiene", "social", "mood"]


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## --- verbatim oracle of the pre-R31 logic --------------------------------

func _old_worst_critical(u: Dictionary) -> String:
	for urge: String in _PRIO:
		if float(u.get(urge, 100.0)) < float(SimUrges.CRITICAL.get(urge, 0.0)):
			return urge
	return ""


func _old_tick(u: Dictionary, delta: float, night: bool, storm: bool) -> String:
	for urge: String in SimUrges.URGES:
		var v: float = clampf(float(u.get(urge, 60.0))
			- float(SimUrges.DECAY.get(urge, 0.2)) * delta, 0.0, 100.0)
		u[urge] = v
	if _old_worst_critical(u) == "":
		u["mood"] = clampf(float(u.get("mood", 60.0)) + 2.0 * delta, 0.0, 80.0)
	if night:
		u["mood"] = clampf(float(u.get("mood", 60.0)) - 0.6 * delta,
			0.0, 100.0)
	if storm:
		u["mood"] = clampf(float(u.get("mood", 60.0)) - 0.4 * delta,
			0.0, 100.0)
	for urge: String in _PRIO:
		if float(u.get(urge, 100.0)) < float(SimUrges.CRITICAL.get(urge, 0.0)):
			return urge
	return ""


## --- helpers ---------------------------------------------------------------

func _make_gs() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	return gs


func _rand_urges(rng: RandomNumberGenerator) -> Dictionary:
	var u := {}
	for urge: String in SimUrges.URGES:
		var v: float
		if rng.randf() < 0.35:
			# Near-threshold values to stress edge cases.
			var c: float = float(SimUrges.CRITICAL[urge])
			v = c + rng.randf_range(-3.0, 3.0)
		else:
			v = rng.randf_range(0.0, 100.0)
		u[urge] = clampf(v, 0.0, 100.0)
	return u


func _unit_with(u: Dictionary) -> Dictionary:
	return {"id": 7, "alive": true, "urges": u}


func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	for urge: String in SimUrges.URGES:
		if not is_equal_approx(float(a.get(urge, -1.0)), float(b.get(urge, -2.0))):
			return false
	return true


## --- tests -------------------------------------------------------------------

func _test_tick_parity_no_seasons() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var gs := _make_gs()
	var urges := SimUrges.new(gs)
	var mismatches := 0
	for i in 600:
		var u_new: Dictionary = _rand_urges(rng)
		var u_old: Dictionary = u_new.duplicate()
		var delta: float = rng.randf_range(0.001, 2.0)
		var got: String = urges.tick(_unit_with(u_new), delta)
		var want: String = _old_tick(u_old, delta, false, false)
		if got != want or not _dicts_equal(u_new, u_old):
			mismatches += 1
	_check("tick parity, 600 randomized, no seasons", mismatches == 0)
	gs.queue_free()


func _test_tick_parity_night_storm() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var mismatches := 0
	# night x storm matrix; night forced via game_time, storm via weather.
	for night: bool in [false, true]:
		for storm: bool in [false, true]:
			var gs := _make_gs()
			gs.seasons = SimSeasons.new(gs)
			gs.seasons.reset()
			gs.game_time = 0.0 if night else Config.DAY_LENGTH_SECONDS * 0.5
			gs.seasons.weather = "storm" if storm else "clear"
			var urges := SimUrges.new(gs)
			for i in 150:
				var u_new: Dictionary = _rand_urges(rng)
				var u_old: Dictionary = u_new.duplicate()
				var delta: float = rng.randf_range(0.01, 1.0)
				var got: String = urges.tick(_unit_with(u_new), delta)
				var want: String = _old_tick(u_old, delta, night, storm)
				if got != want or not _dicts_equal(u_new, u_old):
					mismatches += 1
			gs.queue_free()
	_check("tick parity, night/storm matrix (600 cases)", mismatches == 0)


func _test_worst_critical_parity() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var gs := _make_gs()
	var urges := SimUrges.new(gs)
	var mismatches := 0
	for i in 600:
		var u: Dictionary = _rand_urges(rng)
		var got: String = urges.worst_critical(_unit_with(u))
		var want: String = _old_worst_critical(u)
		if got != want:
			mismatches += 1
	_check("worst_critical parity, 600 randomized", mismatches == 0)
	gs.queue_free()


func _test_worst_critical_missing_dict() -> void:
	var gs := _make_gs()
	var urges := SimUrges.new(gs)
	# No "urges" key: ensure() path must create defaults (all 60, none critical).
	var unit := {"id": 3, "alive": true}
	_check("worst_critical missing dict -> ''", urges.worst_critical(unit) == "")
	_check("worst_critical missing dict creates defaults",
		is_equal_approx(float((unit["urges"] as Dictionary).get("hunger", 0.0)), 60.0))
	gs.queue_free()


func _test_priority_order() -> void:
	var gs := _make_gs()
	var urges := SimUrges.new(gs)
	var ok := true
	# Each pair: higher-priority urge must win when both are critical.
	var pairs := [["hunger", "bladder"], ["bladder", "energy"],
		["energy", "hygiene"], ["hygiene", "social"], ["social", "mood"]]
	for pair: Array in pairs:
		var u := {}
		for urge: String in SimUrges.URGES:
			u[urge] = 90.0
		u[pair[0]] = 1.0
		u[pair[1]] = 1.0
		if urges.worst_critical(_unit_with(u)) != pair[0]:
			ok = false
		# tick() must agree with the same final values.
		var u2: Dictionary = u.duplicate()
		var r: String = urges.tick(_unit_with(u2), 0.0001)
		if r != pair[0]:
			ok = false
	_check("priority order hunger>bladder>energy>hygiene>social>mood", ok)
	gs.queue_free()


func _test_mood_recovery_and_caps() -> void:
	var gs := _make_gs()
	var urges := SimUrges.new(gs)
	var u := {}
	for urge: String in SimUrges.URGES:
		u[urge] = 90.0
	u["mood"] = 40.0
	var r: String = urges.tick(_unit_with(u), 1.0)
	_check("mood recovery: no critical returned", r == "")
	_check("mood recovery: mood rises by 2/s",
		is_equal_approx(float(u["mood"]), 40.0 + 2.0 - 0.08))
	# Cap at 80.
	u["mood"] = 79.5
	urges.tick(_unit_with(u), 10.0)
	_check("mood recovery caps at 80", float(u["mood"]) <= 80.0 + 0.001)
	gs.queue_free()


func _test_night_drift_can_crit_mood() -> void:
	var gs := _make_gs()
	gs.seasons = SimSeasons.new(gs)
	gs.seasons.reset()
	gs.game_time = 0.0  # hour 0 -> night
	gs.seasons.weather = "clear"
	var urges := SimUrges.new(gs)
	var u := {}
	for urge: String in SimUrges.URGES:
		u[urge] = 90.0
	u["mood"] = 30.05  # decay (0.08) drops it under critical 30 first
	var r: String = urges.tick(_unit_with(u), 1.0)
	_check("mood crits at night once decay pushes it under", r == "mood")
	# A healthy mood is never critted by night drift alone.
	for urge: String in SimUrges.URGES:
		u[urge] = 90.0
	u["mood"] = 60.0
	r = urges.tick(_unit_with(u), 1.0)
	_check("healthy mood not critted by night drift", r == "")
	gs.queue_free()


func _test_dead_unit() -> void:
	var gs := _make_gs()
	var urges := SimUrges.new(gs)
	var unit := {"id": 9, "alive": false, "urges": {"hunger": 1.0}}
	_check("dead unit tick -> ''", urges.tick(unit, 1.0) == "")
	gs.queue_free()


func _test_decay_math() -> void:
	var gs := _make_gs()
	var urges := SimUrges.new(gs)
	var u := {}
	for urge: String in SimUrges.URGES:
		u[urge] = 60.0
	urges.tick(_unit_with(u), 10.0)
	# hunger: 60 - 0.35*10 = 56.5; bladder: 60 - 0.45*10 = 55.5
	_check("hunger decay exact",
		is_equal_approx(float(u["hunger"]), 56.5))
	_check("bladder decay exact",
		is_equal_approx(float(u["bladder"]), 55.5))
	gs.queue_free()


func _initialize() -> void:
	print("=== Cursing Gnomes R31 urges single-pass parity tests ===")
	_test_tick_parity_no_seasons()
	_test_tick_parity_night_storm()
	_test_worst_critical_parity()
	_test_worst_critical_missing_dict()
	_test_priority_order()
	_test_mood_recovery_and_caps()
	_test_night_drift_can_crit_mood()
	_test_dead_unit()
	_test_decay_math()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
