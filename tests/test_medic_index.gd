extends SceneTree
## Cursing Gnomes — tick_medics patient-index equivalence + perf tests.
## Perf 2026-10-04 (30-min pass): tick_medics() was O(doctors x units) per
## physics tick (every doctor re-scanned ALL units). The optimization builds
## a patient index once per tick and scans only that. This test proves the
## indexed version is behavior-identical to the original brute-force scan:
## the ORIGINAL body is preserved below as _tick_medics_oracle and both are
## run on identically-seeded worlds; end states and unit_said emissions must
## match exactly (selection, weighting, tie-breaks, revive/heal effects).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_medic_index.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes medic-index equivalence tests ===")
	_test_equivalence_seeds()
	_test_no_patients()
	_test_no_doctors()
	_test_all_downed_same_faction()
	_test_tie_distance_first_wins()
	_test_cross_faction_ignored()
	_test_doctor_contention()
	_test_perf()
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


# ---------------------------------------------------------------- oracle ---
# VERBATIM copy of combat.tick_medics() as it existed before the patient-index
# optimization (2026-10-04). The reference oracle: brute-force per-doctor scan
# of all units. Keep in sync with history only — do NOT "fix" this copy.
func _tick_medics_oracle(combat: SimCombat, delta: float) -> void:
	var _gs: GameState = combat._gs
	for m: Dictionary in _gs.units:
		if not m.get("alive", false):
			continue
		var mjob: String = String(m.get("job", ""))
		if mjob != "doctor" and mjob != "cleric":
			continue
		var mpos: Vector2 = m.get("position", Vector2.ZERO)
		var faction: String = String(m.get("faction", ""))
		var patient: Dictionary = {}
		var best_d2: float = 800.0 * 800.0
		for u: Dictionary in _gs.units:
			if not u.get("alive", false):
				continue
			# Downed units first; injured limb-loss victims (seek_doctor)
			# second — HTML medic heals both.
			if not SimCombat.is_downed(u) and not bool(u.get("seek_doctor", false)):
				continue
			if String(u.get("faction", "")) != faction:
				continue
			var d2: float = mpos.distance_squared_to(
				u.get("position", Vector2.ZERO))
			# Prefer the truly downed: weight their distance lower.
			if not SimCombat.is_downed(u):
				d2 *= 4.0
			if d2 < best_d2:
				best_d2 = d2
				patient = u
		if patient.is_empty():
			continue
		var ppos: Vector2 = patient.get("position", Vector2.ZERO)
		if mpos.distance_to(ppos) <= 40.0:
			if SimCombat.is_downed(patient):
				if combat.revive_unit(int(patient.get("id", 0))):
					# Clerics purge the zombie plague on revive
					# (HTML: doctors & clerics cure the infection).
					if mjob == "cleric":
						(patient as Dictionary).erase("infected")
					_gs.bus.unit_said.emit(int(m.get("id", 0)),
						"You're going to be fine!")
			elif bool(patient.get("seek_doctor", false)):
				# HTML doctor heal: full hp, blood restored, bleeding
				# stopped. Limbs stay lost (permanent).
				patient["hp"] = float(patient.get("max_hp", 100.0))
				patient["blood"] = 100.0
				patient["bleed_rate"] = 0.0
				patient["injured"] = false
				patient["seek_doctor"] = false
				patient["blood_trail_cd"] = 0.0
				_gs.bus.unit_said.emit(int(m.get("id", 0)),
					"You're going to be fine!")
		else:
			var spd: float = float(m.get("speed", 90.0)) * 3.2
			combat._walk_to(m, ppos, spd, delta)


# ------------------------------------------------------------- harness ---
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves"])
	var combat := SimCombat.new(gs)
	var said: Array = []
	gs.bus.unit_said.connect(func(id: int, text: String): said.append([id, text]))
	return {"gs": gs, "combat": combat, "said": said}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _make_unit(uid: int, faction: String, job: String, pos: Vector2,
		downed: bool, seek_doctor: bool) -> Dictionary:
	return {
		"id": uid, "alive": true, "faction": faction, "job": job,
		"position": pos, "downed": downed, "downed_timer": 0.0,
		"downed_by": -1, "seek_doctor": seek_doctor,
		"hp": 40.0 if (downed or seek_doctor) else 100.0, "max_hp": 100.0,
		"blood": 60.0, "bleed_rate": 1.0 if seek_doctor else 0.0,
		"injured": seek_doctor, "blood_trail_cd": 0.0, "speed": 90.0,
		"combat_state": "idle", "combat_target": -1, "infected": true,
	}


func _build_random(w: Dictionary, seed: int, n_units: int) -> void:
	var gs: GameState = w["gs"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var factions: Array[String] = ["humans", "ogres", "elves"]
	var jobs: Array[String] = ["doctor", "cleric", "worker", "soldier",
		"worker", "worker", "soldier"]
	for i in range(n_units):
		var faction: String = factions[rng.randi_range(0, 2)]
		var job: String = jobs[rng.randi_range(0, jobs.size() - 1)]
		var pos := Vector2(rng.randf_range(-600.0, 600.0),
			rng.randf_range(-600.0, 600.0))
		var roll: float = rng.randf()
		var downed: bool = roll < 0.08
		var seek: bool = (not downed) and roll < 0.14
		gs.units.append(_make_unit(1000 + i, faction, job, pos, downed, seek))


func _snapshot(gs: GameState) -> Array[String]:
	var out: Array[String] = []
	for u: Dictionary in gs.units:
		var keys: Array = u.keys()
		keys.sort()
		var parts: Array[String] = []
		for k: String in keys:
			parts.append("%s=%s" % [k, str(u[k])])
		out.append(";".join(parts))
	return out


func _compare_worlds(label: String, wa: Dictionary, wb: Dictionary) -> void:
	var sa: Array[String] = _snapshot(wa["gs"])
	var sb: Array[String] = _snapshot(wb["gs"])
	_check(label + ": same unit count", sa.size() == sb.size())
	var n: int = mini(sa.size(), sb.size())
	for i in range(n):
		if sa[i] != sb[i]:
			_check(label + ": unit %d identical end state" % i, false)
			return
	_check(label + ": identical end states", true)
	var aa: Array = wa["said"]
	var ab: Array = wb["said"]
	_check(label + ": same unit_said emission count", aa.size() == ab.size())
	var m: int = mini(aa.size(), ab.size())
	for i in range(m):
		if aa[i][0] != ab[i][0] or aa[i][1] != ab[i][1]:
			_check(label + ": unit_said #%d identical" % i, false)
			return
	_check(label + ": identical unit_said sequence", true)


# ---------------------------------------------------------------- tests ---
func _test_equivalence_seeds() -> void:
	for seed in [7, 42, 1337, 9001, 55555]:
		var wa: Dictionary = _new_world()
		var wb: Dictionary = _new_world()
		_build_random(wa, seed, 60)
		_build_random(wb, seed, 60)
		(wa["combat"] as SimCombat).tick_medics(1.0 / 60.0)
		_tick_medics_oracle(wb["combat"], 1.0 / 60.0)
		_compare_worlds("equiv seed %d" % seed, wa, wb)
		_free_world(wa)
		_free_world(wb)


func _test_no_patients() -> void:
	var wa: Dictionary = _new_world()
	var wb: Dictionary = _new_world()
	_build_random(wa, 11, 40)
	_build_random(wb, 11, 40)
	for w: Dictionary in [wa, wb]:
		for u: Dictionary in (w["gs"] as GameState).units:
			u["downed"] = false
			u["seek_doctor"] = false
	(wb["gs"] as GameState).units[0]["job"] = "doctor"
	(wa["gs"] as GameState).units[0]["job"] = "doctor"
	(wa["combat"] as SimCombat).tick_medics(1.0 / 60.0)
	_tick_medics_oracle(wb["combat"], 1.0 / 60.0)
	_compare_worlds("no patients", wa, wb)
	_free_world(wa)
	_free_world(wb)


func _test_no_doctors() -> void:
	var wa: Dictionary = _new_world()
	var wb: Dictionary = _new_world()
	_build_random(wa, 12, 40)
	_build_random(wb, 12, 40)
	for w: Dictionary in [wa, wb]:
		for u: Dictionary in (w["gs"] as GameState).units:
			if String(u.get("job", "")) == "doctor" or String(u.get("job", "")) == "cleric":
				u["job"] = "worker"
	(wa["combat"] as SimCombat).tick_medics(1.0 / 60.0)
	_tick_medics_oracle(wb["combat"], 1.0 / 60.0)
	_compare_worlds("no doctors", wa, wb)
	_free_world(wa)
	_free_world(wb)


func _test_all_downed_same_faction() -> void:
	var wa: Dictionary = _new_world()
	var wb: Dictionary = _new_world()
	for w: Dictionary in [wa, wb]:
		var gs: GameState = w["gs"]
		gs.units.append(_make_unit(1, "humans", "doctor", Vector2.ZERO, false, false))
		gs.units.append(_make_unit(2, "humans", "cleric", Vector2(10, 0), false, false))
		for i in range(10):
			gs.units.append(_make_unit(100 + i, "humans", "soldier",
				Vector2(20 + i * 5, i * 3), true, false))
	(wa["combat"] as SimCombat).tick_medics(1.0 / 60.0)
	_tick_medics_oracle(wb["combat"], 1.0 / 60.0)
	_compare_worlds("all downed", wa, wb)
	# Doctor must have revived exactly one patient (nearest = id 100).
	_check("all downed: nearest revived",
		not bool((wa["gs"] as GameState).get_unit(100).get("downed", true)))
	_free_world(wa)
	_free_world(wb)


func _test_tie_distance_first_wins() -> void:
	var wa: Dictionary = _new_world()
	var wb: Dictionary = _new_world()
	for w: Dictionary in [wa, wb]:
		var gs: GameState = w["gs"]
		gs.units.append(_make_unit(1, "humans", "doctor", Vector2.ZERO, false, false))
		# Two patients at exactly the same distance: unit order decides.
		gs.units.append(_make_unit(2, "humans", "worker", Vector2(30, 0), true, false))
		gs.units.append(_make_unit(3, "humans", "worker", Vector2(-30, 0), true, false))
	(wa["combat"] as SimCombat).tick_medics(1.0 / 60.0)
	_tick_medics_oracle(wb["combat"], 1.0 / 60.0)
	_compare_worlds("tie distance", wa, wb)
	_check("tie: first-in-order patient revived",
		not bool((wa["gs"] as GameState).get_unit(2).get("downed", true)))
	_check("tie: second patient still downed",
		bool((wa["gs"] as GameState).get_unit(3).get("downed", false)))
	_free_world(wa)
	_free_world(wb)


func _test_cross_faction_ignored() -> void:
	var wa: Dictionary = _new_world()
	var wb: Dictionary = _new_world()
	for w: Dictionary in [wa, wb]:
		var gs: GameState = w["gs"]
		gs.units.append(_make_unit(1, "humans", "doctor", Vector2.ZERO, false, false))
		gs.units.append(_make_unit(2, "ogres", "soldier", Vector2(10, 0), true, false))
		gs.units.append(_make_unit(3, "humans", "worker", Vector2(500, 0), true, false))
	(wa["combat"] as SimCombat).tick_medics(1.0 / 60.0)
	_tick_medics_oracle(wb["combat"], 1.0 / 60.0)
	_compare_worlds("cross faction", wa, wb)
	# Enemy patient untouched; doctor walks toward own-faction patient.
	_check("cross faction: enemy still downed",
		bool((wa["gs"] as GameState).get_unit(2).get("downed", false)))
	_free_world(wa)
	_free_world(wb)


func _test_doctor_contention() -> void:
	# Two doctors, one patient: first revives, second must find nothing new.
	var wa: Dictionary = _new_world()
	var wb: Dictionary = _new_world()
	for w: Dictionary in [wa, wb]:
		var gs: GameState = w["gs"]
		gs.units.append(_make_unit(1, "humans", "doctor", Vector2.ZERO, false, false))
		gs.units.append(_make_unit(2, "humans", "cleric", Vector2(5, 0), false, false))
		gs.units.append(_make_unit(3, "humans", "worker", Vector2(10, 0), true, false))
	(wa["combat"] as SimCombat).tick_medics(1.0 / 60.0)
	_tick_medics_oracle(wb["combat"], 1.0 / 60.0)
	_compare_worlds("doctor contention", wa, wb)
	_check("contention: patient revived once",
		not bool((wa["gs"] as GameState).get_unit(3).get("downed", true)))
	_check("contention: exactly one revive message",
		(wa["said"] as Array).size() == 1)
	_free_world(wa)
	_free_world(wb)


func _test_perf() -> void:
	var wa: Dictionary = _new_world()
	var wb: Dictionary = _new_world()
	_build_random(wa, 4242, 240)
	_build_random(wb, 4242, 240)
	# Warm up.
	(wa["combat"] as SimCombat).tick_medics(1.0 / 60.0)
	_tick_medics_oracle(wb["combat"], 1.0 / 60.0)
	var iters := 20
	var t0: int = Time.get_ticks_msec()
	for i in range(iters):
		(wa["combat"] as SimCombat).tick_medics(1.0 / 60.0)
	var t_new: int = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	for i in range(iters):
		_tick_medics_oracle(wb["combat"], 1.0 / 60.0)
	var t_old: int = Time.get_ticks_msec() - t0
	print("MEDIC_PERF new=%dms old=%dms over %d iters (240 units)" % [t_new, t_old, iters])
	_check("perf: indexed not slower than brute force", t_new <= t_old)
	_free_world(wa)
	_free_world(wb)
