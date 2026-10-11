extends SceneTree
## Cursing Gnomes — visible aid caravans (Jeremy 2026-10-11 tap-menu order:
## "Aid missions visibly travel, deliver, return").
##
## send_player_resources() no longer teleports goods between stockpiles: the
## goods leave the sender's stockpile onto a real aidwagon (driving physics,
## prefers roads like every other vehicle) that hauls them to the
## recipient's hall. Delivery — and the relations boost with it — happens
## when the wagon ARRIVES, not when it leaves. Then the wagon drives home
## and stands down (despawned).
##
## Covers: dispatch spawns a driving aidwagon (goods debited up front, NOT
## credited yet); delivery on arrival (credit + relations + return leg);
## return arrival despawns the wagon and closes the shipment; lost wagons
## fail the shipment without crashing; war still blocks; no-hall fallback
## keeps the old abstract transfer; save/load round-trips shipments;
## the daily anti-spam cap still holds.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_aid_caravan.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed := 0
var _failed := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes aid caravan tests ===")
	_test_dispatch_spawns_wagon()
	_test_delivery_on_arrival()
	_test_return_and_stand_down()
	_test_lost_wagon()
	_test_war_blocks()
	_test_no_hall_fallback()
	_test_save_load()
	_test_daily_cap()
	print("=== aid caravan: %d passed, %d failed ===" % [_passed, _failed])
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


## Fresh headless game: player = humans; halls for humans + elves; vehicles
## wired like world.gd does.
func _make_game() -> GameState:
	var gs := GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres", "elves", "undead"])
	gs.disaster_aid = SimDisasterAid.new(gs)
	gs.vehicles = SimVehicles.new(gs)
	gs.add_building({"type": "town_hall", "faction": "humans",
		"position": Vector2(100, 100), "alive": true, "complete": true,
		"hp": 2000.0, "max_hp": 2000.0})
	gs.add_building({"type": "town_hall", "faction": "elves",
		"position": Vector2(2000, 100), "alive": true, "complete": true,
		"hp": 2000.0, "max_hp": 2000.0})
	gs.resources.add_resource("humans", "food", 500.0)
	return gs


func _aid(gs: GameState) -> SimDisasterAid:
	return gs.disaster_aid as SimDisasterAid


func _sv(gs: GameState) -> SimVehicles:
	return gs.get("vehicles") as SimVehicles


func _wagon_of(s: Dictionary, gs: GameState) -> Dictionary:
	return _sv(gs).vehicle_by_id(int(s.get("vehicle_id", -1)))


func _test_dispatch_spawns_wagon() -> void:
	var gs := _make_game()
	var r: Dictionary = _aid(gs).send_player_resources("elves", "food", 100.0)
	_check("dispatch ok", bool(r.get("ok", false)))
	_check("sent amount reported", float(r.get("sent", 0.0)) == 100.0)
	_check("sender stockpile debited at dispatch",
		gs.resources.get_amount("humans", "food") == 400.0)
	_check("recipient NOT credited before arrival",
		gs.resources.get_amount("elves", "food") == 0.0)
	var s: Dictionary = r.get("shipment", {})
	_check("shipment record returned", not s.is_empty())
	_check("shipment active", String(s.get("status", "")) == "active")
	_check("shipment outbound", String(s.get("phase", "")) == "outbound")
	var w := _wagon_of(s, gs)
	_check("aidwagon spawned", not w.is_empty())
	_check("wagon type is aidwagon", String(w.get("type", "")) == "aidwagon")
	_check("wagon belongs to sender", String(w.get("faction", "")) == "humans")
	_check("wagon driving", String(w.get("state", "")) == "driving")
	_check("wagon has the recipient hall as target",
		(w.get("target", Vector2.ZERO) as Vector2).distance_to(
			Vector2(2000, 100)) < 1.0)


func _test_delivery_on_arrival() -> void:
	var gs := _make_game()
	var before: float = gs.diplomacy.relation_score("elves", "humans")
	var r: Dictionary = _aid(gs).send_player_resources("elves", "food", 100.0)
	var s: Dictionary = r.get("shipment", {})
	var w := _wagon_of(s, gs)
	_check("relations not warmed before arrival",
		gs.diplomacy.relation_score("elves", "humans") == before)
	w["pos"] = Vector2(2000, 100)  # fast-forward: at the recipient's hall
	_aid(gs).tick(1.0)
	_check("recipient credited on arrival",
		gs.resources.get_amount("elves", "food") == 100.0)
	_check("relations warmed on arrival",
		gs.diplomacy.relation_score("elves", "humans") > before)
	_check("shipment heading home", String(s.get("phase", "")) == "return")
	var w2 := _wagon_of(s, gs)
	_check("wagon driving home", String(w2.get("state", "")) == "driving")
	_check("wagon target is home",
		(w2.get("target", Vector2.ZERO) as Vector2).distance_to(
			Vector2(100, 100)) < 1.0)


func _test_return_and_stand_down() -> void:
	var gs := _make_game()
	var r: Dictionary = _aid(gs).send_player_resources("elves", "food", 100.0)
	var s: Dictionary = r.get("shipment", {})
	var vid := int(s.get("vehicle_id", -1))
	var w := _wagon_of(s, gs)
	w["pos"] = Vector2(2000, 100)
	_aid(gs).tick(1.0)
	var w2 := _wagon_of(s, gs)
	w2["pos"] = Vector2(100, 100)  # fast-forward: back at the home hall
	_aid(gs).tick(1.0)
	_check("shipment done after return", String(s.get("status", "")) == "done")
	_check("wagon despawned on stand-down",
		_sv(gs).vehicle_by_id(vid).is_empty())


func _test_lost_wagon() -> void:
	var gs := _make_game()
	var r: Dictionary = _aid(gs).send_player_resources("elves", "food", 100.0)
	var s: Dictionary = r.get("shipment", {})
	_sv(gs).despawn_vehicle(int(s.get("vehicle_id", -1)))
	_aid(gs).tick(1.0)  # must not crash on the missing vehicle
	_check("lost wagon marks shipment lost",
		String(s.get("status", "")) == "lost")
	_check("no delivery when the wagon is lost",
		gs.resources.get_amount("elves", "food") == 0.0)
	_check("sender already paid (goods left at dispatch)",
		gs.resources.get_amount("humans", "food") == 400.0)


func _test_war_blocks() -> void:
	var gs := _make_game()
	gs.diplomacy.declare_war("humans", "elves", "test")
	var r: Dictionary = _aid(gs).send_player_resources("elves", "food", 100.0)
	_check("resource aid blocked at war", not bool(r.get("ok", false)))
	_check("no wagon spawned at war", _sv(gs).vehicles.is_empty())
	_check("no stockpile moved at war",
		gs.resources.get_amount("humans", "food") == 500.0)


func _test_no_hall_fallback() -> void:
	# No halls and no vehicle system: the old abstract transfer keeps aid
	# working in the degenerate case (this is also the path the existing
	# test_power_tap suite exercises, so it must stay green).
	var gs := GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres", "elves", "undead"])
	gs.disaster_aid = SimDisasterAid.new(gs)
	gs.resources.add_resource("humans", "food", 500.0)
	var r: Dictionary = (gs.disaster_aid as SimDisasterAid) \
		.send_player_resources("elves", "food", 100.0)
	_check("fallback dispatch ok", bool(r.get("ok", false)))
	_check("fallback flagged abstract", bool(r.get("abstract", false)))
	_check("fallback credits immediately",
		gs.resources.get_amount("elves", "food") == 100.0)


func _test_save_load() -> void:
	var gs := _make_game()
	var r: Dictionary = _aid(gs).send_player_resources("elves", "food", 100.0)
	var s: Dictionary = r.get("shipment", {})
	var vid := int(s.get("vehicle_id", -1))
	var data: Dictionary = _aid(gs).to_dict()
	var aid2 := SimDisasterAid.new(gs)
	aid2.from_dict(data)
	_check("shipment survives save/load", aid2._shipments.size() == 1)
	var s2: Dictionary = aid2._shipments[0]
	_check("vehicle id survives", int(s2.get("vehicle_id", -1)) == vid)
	_check("status survives", String(s2.get("status", "")) == "active")
	_check("phase survives", String(s2.get("phase", "")) == "outbound")
	var w: Dictionary = _sv(gs).vehicle_by_id(vid)
	w["pos"] = Vector2(2000, 100)
	aid2.tick(1.0)
	_check("reloaded shipment still delivers",
		gs.resources.get_amount("elves", "food") == 100.0)


func _test_daily_cap() -> void:
	var gs := _make_game()
	var ok := 0
	for i in 4:
		var rr: Dictionary = _aid(gs).send_player_resources(
			"elves", "food", 10.0)
		if bool(rr.get("ok", false)):
			ok += 1
	_check("daily cap allows 3, blocks 4th", ok == 3)
