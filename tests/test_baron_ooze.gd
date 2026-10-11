extends SceneTree
## Cursing Gnomes — Baron von Foam flesh-out tests (wake massive-dev
## 2026-10-07: the Sentient Beer Puddle gets the Gristlethwaite treatment).
##
## Covers: named identity (const + arrival headline + greeting), drunkenness
## build-up/decay in the aura, drunk_work_mult formula (incl. hangover
## equivalence + floor), drink tracking (rounds/drunkards/peak), the
## "too drunk to work" Gazette beat (announced once), slurred-line
## escalation at avg drunk >= 50, beer-soaked buildings (soak + lingering
## half-rate party), hangovers on departure, the slain burst, the missing
## departed hook (ledger closes, TALLY note), the Gazette branch, and the
## no-town no-crash fallback.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_baron_ooze.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []  # [unit_id, text] from bus.unit_said


func _initialize() -> void:
	print("=== Cursing Gnomes Baron von Foam tests ===")
	_test_consts()
	_test_work_mult()
	_test_arrival()
	_test_drunk_builds()
	_test_drunk_decays()
	_test_drink_tracking()
	_test_drunk_beat_once()
	_test_slurred_escalation()
	_test_soak()
	_test_soaked_lingers()
	_test_soak_dries()
	_test_hangover_departed()
	_test_slain_burst()
	_test_departed_hook_wired()
	_test_gazette_branch()
	_test_no_town_no_crash()
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


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	return gs


func _new_disasters(gs: GameState) -> DisasterSim:
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	d.setup_bounds(Rect2(0, 0, 4000, 4000))
	_said.clear()
	gs.bus.unit_said.connect(_on_unit_said)
	return d


func _on_unit_said(unit_id: int, text: String) -> void:
	_said.append([unit_id, text])


func _add_building(gs: GameState, btype: String, faction: String,
		town_id: int, pos: Vector2) -> Dictionary:
	return gs.add_building({
		"faction": faction, "type": btype, "town_id": town_id,
		"position": pos, "alive": true, "complete": true,
	})


func _add_citizen(gs: GameState, faction: String, pos: Vector2,
		job: String = "worker", hp: float = 100.0) -> Dictionary:
	return gs.add_unit({
		"faction": faction, "job": job, "town_id": -1,
		"position": pos, "alive": true, "hp": hp, "max_hp": hp,
	})


func _spawn_ooze(gs: GameState, d: DisasterSim, pos: Vector2) -> Dictionary:
	# A hall pins the town pick so the ooze stays put for the test.
	_add_building(gs, "hall", "humans", 1, Vector2(500, 500))
	return d.spawn("booze_ooze", pos)


func _said_texts() -> Array[String]:
	var out: Array[String] = []
	for s in _said:
		out.append(String(s[1]))
	return out


## ---- identity ------------------------------------------------------------


func _test_consts() -> void:
	_check("name const",
		DisasterSim.OOZE_NAME == "Baron von Foam")
	_check("arrive pool", not DisasterSim.OOZE_ARRIVE_LINES.is_empty())
	_check("party pool", DisasterSim.OOZE_LINES.size() >= 6)
	_check("slurred pool", not DisasterSim.OOZE_SLURRED_LINES.is_empty())
	_check("drunk burst pool", not DisasterSim.OOZE_DRUNK_BURSTS.is_empty())
	_check("soak pool", not DisasterSim.OOZE_SOAK_LINES.is_empty())


func _test_work_mult() -> void:
	_check("sober works full",
		is_equal_approx(DisasterSim.drunk_work_mult({}), 1.0))
	_check("drunk 50 halves-ish",
		is_equal_approx(DisasterSim.drunk_work_mult({"drunk": 50.0}), 0.7))
	_check("drunk 100 floors at 0.4",
		is_equal_approx(DisasterSim.drunk_work_mult({"drunk": 100.0}), 0.4))
	_check("drunk 200 still floors",
		is_equal_approx(DisasterSim.drunk_work_mult({"drunk": 200.0}), 0.4))
	_check("hangover counts as drunk 40",
		is_equal_approx(
			DisasterSim.drunk_work_mult({"hangover_t": 60.0}), 1.0 - 40.0 * 0.006))
	_check("hangover never beats real drunk",
		is_equal_approx(
			DisasterSim.drunk_work_mult({"drunk": 80.0, "hangover_t": 60.0}),
			1.0 - 80.0 * 0.006))


func _test_arrival() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_said.clear()
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	d.tick(0.2)
	_check("arrival announced", bool(u.get("ooze_announced", false)))
	var greeted := false
	for t: String in _said_texts():
		if t in DisasterSim.OOZE_ARRIVE_LINES:
			greeted = true
	_check("arrival greeting", greeted)
	_check("greeted once", bool(u.get("ooze_greeted", false)))
	_said.clear()
	d.tick(0.2)
	var greeted_again := false
	for t2: String in _said_texts():
		if t2 in DisasterSim.OOZE_ARRIVE_LINES:
			greeted_again = true
	_check("greeting not repeated", not greeted_again)


## ---- drunkenness ---------------------------------------------------------


func _test_drunk_builds() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	var near := _add_citizen(gs, "humans", Vector2(120, 100))
	var far := _add_citizen(gs, "humans", Vector2(3000, 3000))
	d.tick(1.0)
	var nd: float = float(near.get("drunk", 0.0))
	_check("drunk builds in aura", nd > 0.0)
	# Net rate: aura +6/s minus ambient decay 1.5/s in the same tick.
	var net_rate: float = DisasterSim.OOZE_DRUNK_RATE \
		- DisasterSim.OOZE_DRUNK_DECAY
	_check("drunk rate sane", absf(nd - net_rate * 1.0) < 0.01)
	_check("far citizen stays sober",
		float(far.get("drunk", 0.0)) == 0.0)
	_check("stress wiped", float(near.get("stress", 1.0)) == 0.0)


func _test_drunk_decays() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var x := _add_citizen(gs, "humans", Vector2(3000, 3000))
	x["drunk"] = 60.0
	d.tick(2.0)  # ambient decay runs even with no ooze around
	var after: float = float(x.get("drunk", 0.0))
	_check("drunk decays",
		absf(after - (60.0 - DisasterSim.OOZE_DRUNK_DECAY * 2.0)) < 0.01)
	var ho := _add_citizen(gs, "humans", Vector2(3000, 3100))
	ho["hangover_t"] = 100.0
	d.tick(2.0)
	_check("hangover decays",
		absf(float(ho.get("hangover_t", 0.0)) - 98.0) < 0.01)


func _test_drink_tracking() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	var x := _add_citizen(gs, "humans", Vector2(120, 100))
	# Net 4.5 drunk/s: 12 s -> 54, crossing 25 (one round) and 50 (a drunkard).
	# (Peak is captured mid-tick before ambient decay: 6*12 = 72.)
	d.tick(12.0)
	_check("one round poured", int(u.get("ooze_drinks_poured", 0)) == 1)
	_check("one drunkard", int(u.get("ooze_drunkards", 0)) == 1)
	_check("peak tracked",
		absf(float(u.get("ooze_peak_drunk", 0.0)) - 72.0) < 0.01)
	# Second citizen joins late: crossings count per citizen.
	var y := _add_citizen(gs, "humans", Vector2(110, 110))
	d.tick(12.0)
	_check("two rounds", int(u.get("ooze_drinks_poured", 0)) == 2)
	_check("two drunkards", int(u.get("ooze_drunkards", 0)) == 2)


func _test_drunk_beat_once() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	var x := _add_citizen(gs, "humans", Vector2(120, 100))
	x["drunk"] = 79.0
	d.tick(0.5)  # crosses 80 -> the beat fires
	_check("drunk beat announced", bool(u.get("ooze_drunk_beat", false)))
	d.tick(1.0)
	_check("beat fires once", bool(u.get("ooze_drunk_beat", false)))


func _test_slurred_escalation() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	var x := _add_citizen(gs, "humans", Vector2(120, 100))
	x["drunk"] = 60.0  # avg aura drunk >= 50 -> slurred pool
	u["shout_cd"] = 0.0
	_said.clear()
	d.tick(0.2)
	var slurred := false
	for t: String in _said_texts():
		if t in DisasterSim.OOZE_SLURRED_LINES:
			slurred = true
	_check("slurred pool when crowd is drunk", slurred)
	# Sober crowd -> the straight party pool.
	var gs2 := _new_game(["humans"])
	var d2 := _new_disasters(gs2)
	var u2 := _spawn_ooze(gs2, d2, Vector2(100, 100))
	_add_citizen(gs2, "humans", Vector2(120, 100))
	u2["shout_cd"] = 0.0
	_said.clear()
	d2.tick(0.2)
	var straight := false
	for t2: String in _said_texts():
		if t2 in DisasterSim.OOZE_LINES:
			straight = true
	_check("straight pool when crowd is sober", straight)


## ---- beer soak -----------------------------------------------------------


func _test_soak() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	var b := _add_building(gs, "house", "humans", 1, Vector2(150, 100))
	u["soak_cd"] = 0.0
	_said.clear()
	d.tick(0.2)
	_check("building soaked", float(b.get("beer_soak_t", 0.0)) > 0.0)
	_check("soak counted", int(u.get("ooze_soaked", 0)) == 1)
	var soaked_shout := false
	for t: String in _said_texts():
		if t in DisasterSim.OOZE_SOAK_LINES:
			soaked_shout = true
	_check("soak shout", soaked_shout)
	# Soaked buildings are not re-soaked while wet.
	u["soak_cd"] = 0.0
	d.tick(0.2)
	_check("no double soak", int(u.get("ooze_soaked", 0)) == 1)


func _test_soaked_lingers() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	var b := _add_building(gs, "house", "humans", 1, Vector2(150, 100))
	u["soak_cd"] = 0.0
	d.tick(0.2)  # soaks the house
	# The Baron oozes far away; the party should linger at the wet house.
	u["position"] = Vector2(3000, 3000)
	u["ooze_center"] = Vector2(3000, 3000)
	var x := _add_citizen(gs, "humans", Vector2(150, 120))
	d.tick(2.0)
	_check("soaked building keeps party going",
		float(x.get("drunk", 0.0)) > 0.0)


func _test_soak_dries() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var b := _add_building(gs, "house", "humans", 1, Vector2(150, 100))
	b["beer_soak_t"] = 10.0
	d.tick(4.0)  # no ooze around; ambient still dries the building
	_check("soak dries out", float(b.get("beer_soak_t", 0.0)) < 10.0)


## ---- departure: hangovers + ledger ---------------------------------------


func _test_hangover_departed() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	var drunk := _add_citizen(gs, "humans", Vector2(120, 100))
	drunk["drunk"] = 80.0
	var sober := _add_citizen(gs, "humans", Vector2(130, 100))
	d._start_leaving(u)
	_check("drunkard gets hangover",
		is_equal_approx(float(drunk.get("hangover_t", 0.0)),
			DisasterSim.OOZE_HANGOVER_T))
	_check("hangover stress bump",
		float(drunk.get("stress", 0.0)) >= DisasterSim.OOZE_HANGOVER_STRESS)
	_check("sober citizen spared", float(sober.get("hangover_t", 0.0)) == 0.0)
	_check("leaving flagged", bool(u.get("leaving", false)))
	var notes: Array = _notes(d, u)
	var tally := false
	for n in notes:
		if String(n).begins_with("TALLY"):
			tally = true
	_check("departure TALLY filed", tally)


func _test_slain_burst() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	var near := _add_citizen(gs, "humans", Vector2(150, 100))
	var far := _add_citizen(gs, "humans", Vector2(3000, 3000))
	u["alive"] = false
	d._check_dead_disaster(u)
	_check("burst soaks nearby",
		is_equal_approx(float(near.get("drunk", 0.0)),
			DisasterSim.OOZE_SLAIN_BURST_DRUNK))
	_check("burst spares far", float(far.get("drunk", 0.0)) == 0.0)
	var notes: Array = _notes(d, u)
	var splashed := false
	var tally := false
	for n in notes:
		var ns := String(n)
		if ns.begins_with("SPLASHED"):
			splashed = true
		if ns.begins_with("TALLY"):
			tally = true
	_check("slain SPLASHED note", splashed)
	_check("slain TALLY note", tally)
	_check("ledger closed",
		String(d.dlog.get_record(int(u.get("disaster_log_id", -1))).get(
			"status", "")) != "active")


func _test_departed_hook_wired() -> void:
	# The real dead end this run closes: _start_leaving had no booze_ooze
	# branch, so the ledger never closed and no Gazette story published.
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	d.tick(0.2)
	d._start_leaving(u)
	_check("departed hook ran (TALLY)",
		_notes(d, u).any(func(n) -> bool: return String(n).begins_with("TALLY")))
	_check("departed ledger closed",
		String(d.dlog.get_record(int(u.get("disaster_log_id", -1))).get(
			"status", "")) == "left")


func _test_gazette_branch() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	var u := _spawn_ooze(gs, d, Vector2(100, 100))
	d.tick(0.2)
	d._start_leaving(u)
	var headlines: Array[String] = []
	for s: Dictionary in court.stories:
		headlines.append(String(s.get("headline", "")))
	var found := false
	for h: String in headlines:
		if h.begins_with("BARON VON FOAM OOZES ON"):
			found = true
	_check("gazette departure headline", found)
	# Slain headline.
	var gs2 := _new_game(["humans"])
	var d2 := _new_disasters(gs2)
	var court2 := SimRoyalCourt.new(gs2)
	gs2.court_sys = court2
	var u2 := _spawn_ooze(gs2, d2, Vector2(100, 100))
	u2["alive"] = false
	d2._check_dead_disaster(u2)
	var found2 := false
	for s2: Dictionary in court2.stories:
		if String(s2.get("headline", "")).begins_with("BARON VON FOAM SLAIN"):
			found2 = true
	_check("gazette slain headline", found2)


func _test_no_town_no_crash() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	# No buildings at all: town pick falls back to the spawn point.
	var u := d.spawn("booze_ooze", Vector2(100, 100))
	d.tick(1.0)
	_check("no town no crash", bool(u.get("ooze_announced", false)))
	_check("fallback center", u.has("ooze_center"))


func _notes(d: DisasterSim, u: Dictionary) -> Array:
	var log_id: int = int(u.get("disaster_log_id", -1))
	return d.dlog.summary(log_id).get("notes", [])
