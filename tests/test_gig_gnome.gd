extends SceneTree
## Cursing Gnomes — Gig Gnome disaster tests (wake 2026-10-07:
## gig_gnome).
##
## Covers: singleton rule, label, most-populous-town targeting, arrival
## story flag, delivery-anxiety stress aura, delivery-fee skimming
## (clamped, never negative, broke-faction guilt trip), coward's flee
## from soldiers (ledger closed, "fled" note, tip refund), budget expiry
## -> "DELIVERY NEVER CAME" story, slain -> ledger closed with fee
## refund + "TIP EXPECTED" story, and the no-town edge case.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gig_gnome.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Gig Gnome tests ===")
	_test_singleton_and_label()
	_test_picks_most_populous_town()
	_test_anxiety_stress_aura()
	_test_delivery_fee_skim()
	_test_broke_faction_no_negative()
	_test_flees_from_soldiers()
	_test_budget_never_delivered()
	_test_slain_refunds_fees()
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
	gs.disasters = d
	return d


func _add_town(gs: GameState, tid: int, faction: String, pos: Vector2) -> void:
	gs.towns[tid] = {"id": tid, "faction": faction, "name": "T%d" % tid,
		"position": pos}


func _add_citizen(gs: GameState, faction: String, tid: int,
		pos: Vector2, job: String = "worker") -> Dictionary:
	var u: Dictionary = gs.add_unit({
		"faction": faction, "job": job, "town_id": tid,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"stress": 10.0,
	})
	return u


func _new_driver_world() -> Array:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_add_town(gs, 100, "humans", Vector2(1000, 1000))
	_add_town(gs, 200, "humans", Vector2(3000, 3000))
	# Town 100 is the populous one: 5 citizens. Town 200: 1 citizen.
	for i in 5:
		_add_citizen(gs, "humans", 100, Vector2(1000 + i * 10, 1000))
	_add_citizen(gs, "humans", 200, Vector2(3000, 3000))
	return [gs, d]


func _test_singleton_and_label() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var a: Dictionary = d.spawn("gig_gnome", Vector2(500, 500))
	_check("driver: spawns", not a.is_empty())
	_check("driver: label", d._label_for("gig_gnome") == "Gig Gnome")
	_check("driver: log opened", int(a.get("disaster_log_id", -1)) > 0)
	var b: Dictionary = d.spawn("gig_gnome", Vector2(600, 600))
	_check("driver: singleton (second refused)", b.is_empty())


func _test_picks_most_populous_town() -> void:
	var parts: Array = _new_driver_world()
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("gig_gnome", Vector2(100, 100))
	d.tick(0.2)  # first tick: pick town + announce
	var center: Vector2 = u.get("driver_center", Vector2(-1, -1))
	_check("driver: targets most populous town (100)",
		center.distance_to(Vector2(1000, 1000)) < 1.0)
	_check("driver: arrival story announced",
		bool(u.get("driver_announced", false)))
	_check("driver: town name recorded",
		String(u.get("driver_town_name", "")) == "T100")
	_check("driver: faction recorded",
		String(u.get("driver_faction", "")) == "humans")


func _test_anxiety_stress_aura() -> void:
	var parts: Array = _new_driver_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("gig_gnome", Vector2(100, 100))
	d.tick(0.2)
	# Park the driver in the plaza; a calm citizen stands next to him.
	u["position"] = Vector2(1000, 1000)
	var w: Dictionary = _add_citizen(gs, "humans", 100, Vector2(1010, 1000))
	_check("driver: citizen starts calm",
		float(w.get("stress", -1.0)) == 10.0)
	d.tick(1.0)
	_check("driver: delivering state",
		String(u.get("combat_state", "")) == "delivering")
	_check("driver: anxiety stresses citizens (%.1f)" % float(w.get("stress", 0.0)),
		float(w.get("stress", 0.0)) > 10.0)
	_check("driver: anxiety never exceeds 100",
		float(w.get("stress", 0.0)) <= 100.0)
	_check("driver: doom tracked",
		float(u.get("driver_doomed", 0.0)) > 0.0)


func _test_delivery_fee_skim() -> void:
	var parts: Array = _new_driver_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	gs.resources.add_resource("humans", "gold", 1000.0)
	var u: Dictionary = d.spawn("gig_gnome", Vector2(100, 100))
	d.tick(0.2)
	u["position"] = Vector2(1000, 1000)  # parked in the plaza
	var before: float = gs.resources.get_amount("humans", "gold")
	d.tick(21.0)  # first fee fires at fee_cd 20s: 5% of 1000 -> clamped 25
	var after: float = gs.resources.get_amount("humans", "gold")
	_check("driver: fee skimmed 25 gold (%.0f -> %.0f)" % [before, after],
		is_equal_approx(before - after, 25.0))
	_check("driver: fees tracked",
		float(u.get("driver_fees", 0.0)) > 0.0)
	_check("driver: no negative gold", after >= 0.0)


func _test_broke_faction_no_negative() -> void:
	var parts: Array = _new_driver_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	# Faction starts with no gold: the driver guilt-trips, never skims.
	var u: Dictionary = d.spawn("gig_gnome", Vector2(100, 100))
	d.tick(0.2)
	u["position"] = Vector2(1000, 1000)
	d.tick(21.0)
	_check("driver: broke faction stays at 0",
		gs.resources.get_amount("humans", "gold") == 0.0)
	_check("driver: broke faction accrues no fees",
		float(u.get("driver_fees", 0.0)) == 0.0)


func _test_flees_from_soldiers() -> void:
	var parts: Array = _new_driver_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	gs.resources.add_resource("humans", "gold", 1000.0)
	var u: Dictionary = d.spawn("gig_gnome", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	# A soldier closes in before the first tick finishes targeting.
	_add_citizen(gs, "humans", 100, Vector2(150, 120), "soldier")
	d.tick(0.2)
	_check("driver: fled flag", bool(u.get("driver_fled", false)))
	_check("driver: leaving", bool(u.get("leaving", false)))
	_check("driver: fled story announced",
		bool(u.get("driver_fled_story", false)))
	_check("driver: tip refunded (+30g)",
		gs.resources.get_amount("humans", "gold") == 1030.0)
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("driver: flee closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).find("fled") >= 0:
			saw = true
	_check("driver: 'fled' note filed", saw)


func _test_budget_never_delivered() -> void:
	var parts: Array = _new_driver_world()
	var d: DisasterSim = parts[1]
	var u: Dictionary = d.spawn("gig_gnome", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["age"] = 99999.0  # the order was never real
	d.tick(0.2)
	_check("driver: leaving after budget", bool(u.get("leaving", false)))
	_check("driver: DELIVERY NEVER CAME story",
		bool(u.get("driver_shame_story", false)))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("driver: shame closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).find("never delivered") >= 0:
			saw = true
	_check("driver: 'never delivered' note filed", saw)


func _test_slain_refunds_fees() -> void:
	var parts: Array = _new_driver_world()
	var gs: GameState = parts[0]
	var d: DisasterSim = parts[1]
	gs.resources.add_resource("humans", "gold", 1000.0)
	var u: Dictionary = d.spawn("gig_gnome", Vector2(100, 100))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["position"] = Vector2(1000, 1000)
	d.tick(21.0)  # skim 25g
	_check("driver: fees skimmed before slaying",
		float(u.get("driver_fees", 0.0)) > 0.0)
	u["alive"] = false
	d.tick(0.3)
	_check("driver: slain refunds fees (back to 1000)",
		gs.resources.get_amount("humans", "gold") == 1000.0)
	_check("driver: TIP EXPECTED story",
		bool(u.get("driver_slain_story", false)))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("driver: slain closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).find("fees refunded") >= 0:
			saw = true
	_check("driver: 'fees refunded' note filed", saw)


func _test_no_town_no_crash() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("gig_gnome", Vector2(100, 100))
	d.tick(0.5)
	_check("driver: no towns -> delivers at spawn, no crash",
		not u.is_empty() and bool(u.get("driver_announced", false)))
	# No faction to skim from: the fee timer must not crash or go negative.
	d.tick(21.0)
	_check("driver: no faction -> no crash, no phantom fees",
		gs.resources.get_amount("humans", "gold") == 0.0)
