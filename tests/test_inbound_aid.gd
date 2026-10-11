extends SceneTree
## Cursing Gnomes — inbound aid caravans (Jeremy 2026-10-11 tap-menu order:
## "Aid missions visibly travel, deliver, return" — BOTH directions).
##
## Tap-menu "Request Aid" used to teleport food from the donor's stockpile
## straight to the player (diplomacy.pay_tribute). Now SimDisasterAid
## .request_inbound_aid() dispatches a REAL relief wagon from the donor's
## hall: the donor debits its own stockpile at dispatch, and the player is
## credited — with the relations boost — only when the wagon ARRIVES at the
## player's hall. Then the wagon drives home and stands down.
##
## Covers: cold-relations decline (-2 score, no wagon, no stockpile moved);
## empty donor stores decline (polite, no penalty); dispatch debits donor at
## once but does NOT credit the player; delivery on arrival (credit +
## relations + return leg); return arrival despawns the wagon and closes
## the shipment; lost wagons fail without crashing; war blocks; no-hall
## fallback keeps the old abstract transfer.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_inbound_aid.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed := 0
var _failed := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes inbound aid tests ===")
	_test_cold_relations_decline()
	_test_empty_stores_decline()
	_test_dispatch_debits_donor()
	_test_delivery_on_arrival()
	_test_return_and_stand_down()
	_test_lost_wagon()
	_test_war_blocks()
	_test_no_hall_fallback()
	print("=== inbound aid: %d passed, %d failed ===" % [_passed, _failed])
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


## Fresh headless game: player = humans (default first faction); halls for
## humans + elves; vehicles wired like world.gd does. The ELVES are the
## donor here; relations default to neutral 0 (below the 30 help gate).
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
	gs.resources.add_resource("elves", "food", 500.0)
	return gs


## Warm the elves toward the player past the 30-point help gate.
func _warm(gs: GameState) -> void:
	gs.diplomacy.adjust_score("elves", "humans", 40.0)


func _aid(gs: GameState) -> SimDisasterAid:
	return gs.disaster_aid as SimDisasterAid


func _sv(gs: GameState) -> SimVehicles:
	return gs.get("vehicles") as SimVehicles


func _wagon_of(s: Dictionary, gs: GameState) -> Dictionary:
	return _sv(gs).vehicle_by_id(int(s.get("vehicle_id", -1)))


func _test_cold_relations_decline() -> void:
	var gs := _make_game()
	var before: float = gs.diplomacy.relation_score("elves", "humans")
	var r: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("cold decline not ok", not bool(r.get("ok", false)))
	_check("cold decline message mentions cold",
		String(r.get("msg", "")).to_lower().contains("cold"))
	_check("decline costs 2 relation points",
		gs.diplomacy.relation_score("elves", "humans") == before - 2.0)
	_check("decline spawns no wagon", _sv(gs).vehicles.is_empty())
	_check("decline moves no donor stockpile",
		gs.resources.get_amount("elves", "food") == 500.0)
	_check("decline credits no player food",
		gs.resources.get_amount("humans", "food") == 0.0)


func _test_empty_stores_decline() -> void:
	var gs := _make_game()
	_warm(gs)
	gs.resources.add_resource("elves", "food", -500.0)
	var before: float = gs.diplomacy.relation_score("elves", "humans")
	var r: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("empty stores not ok", not bool(r.get("ok", false)))
	_check("empty stores message mentions stores",
		String(r.get("msg", "")).to_lower().contains("stores"))
	_check("empty stores: no score penalty",
		gs.diplomacy.relation_score("elves", "humans") == before)
	_check("empty stores spawns no wagon", _sv(gs).vehicles.is_empty())


func _test_dispatch_debits_donor() -> void:
	var gs := _make_game()
	_warm(gs)
	var r: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("dispatch ok", bool(r.get("ok", false)))
	_check("sent amount reported", float(r.get("sent", 0.0)) == 100.0)
	_check("donor stockpile debited at dispatch",
		gs.resources.get_amount("elves", "food") == 400.0)
	_check("player NOT credited before arrival",
		gs.resources.get_amount("humans", "food") == 0.0)
	var s: Dictionary = r.get("shipment", {})
	_check("shipment record returned", not s.is_empty())
	_check("shipment active", String(s.get("status", "")) == "active")
	_check("shipment outbound", String(s.get("phase", "")) == "outbound")
	var w := _wagon_of(s, gs)
	_check("aidwagon spawned", not w.is_empty())
	_check("wagon type is aidwagon", String(w.get("type", "")) == "aidwagon")
	_check("wagon belongs to donor", String(w.get("faction", "")) == "elves")
	_check("wagon driving", String(w.get("state", "")) == "driving")
	_check("wagon has the PLAYER hall as target",
		(w.get("target", Vector2.ZERO) as Vector2).distance_to(
			Vector2(100, 100)) < 1.0)


func _test_delivery_on_arrival() -> void:
	var gs := _make_game()
	_warm(gs)
	var before: float = gs.diplomacy.relation_score("humans", "elves")
	var r: Dictionary = _aid(gs).request_inbound_aid("elves")
	var s: Dictionary = r.get("shipment", {})
	var w := _wagon_of(s, gs)
	_check("relations not warmed before arrival",
		gs.diplomacy.relation_score("humans", "elves") == before)
	w["pos"] = Vector2(100, 100)  # fast-forward: at the player's hall
	_aid(gs).tick(1.0)
	_check("player credited on arrival",
		gs.resources.get_amount("humans", "food") == 100.0)
	_check("relations warmed on arrival",
		gs.diplomacy.relation_score("humans", "elves") > before)
	_check("shipment heading home", String(s.get("phase", "")) == "return")
	var w2 := _wagon_of(s, gs)
	_check("wagon driving home", String(w2.get("state", "")) == "driving")
	_check("wagon target is donor home",
		(w2.get("target", Vector2.ZERO) as Vector2).distance_to(
			Vector2(2000, 100)) < 1.0)


func _test_return_and_stand_down() -> void:
	var gs := _make_game()
	_warm(gs)
	var r: Dictionary = _aid(gs).request_inbound_aid("elves")
	var s: Dictionary = r.get("shipment", {})
	var vid := int(s.get("vehicle_id", -1))
	var w := _wagon_of(s, gs)
	w["pos"] = Vector2(100, 100)
	_aid(gs).tick(1.0)
	var w2 := _wagon_of(s, gs)
	w2["pos"] = Vector2(2000, 100)  # fast-forward: back at the donor hall
	_aid(gs).tick(1.0)
	_check("shipment done after return", String(s.get("status", "")) == "done")
	_check("wagon despawned on stand-down",
		_sv(gs).vehicle_by_id(vid).is_empty())


func _test_lost_wagon() -> void:
	var gs := _make_game()
	_warm(gs)
	var r: Dictionary = _aid(gs).request_inbound_aid("elves")
	var s: Dictionary = r.get("shipment", {})
	_sv(gs).despawn_vehicle(int(s.get("vehicle_id", -1)))
	_aid(gs).tick(1.0)  # must not crash on the missing vehicle
	_check("lost wagon marks shipment lost",
		String(s.get("status", "")) == "lost")
	_check("no delivery when the wagon is lost",
		gs.resources.get_amount("humans", "food") == 0.0)
	_check("donor already paid (goods left at dispatch)",
		gs.resources.get_amount("elves", "food") == 400.0)


func _test_war_blocks() -> void:
	var gs := _make_game()
	_warm(gs)
	gs.diplomacy.declare_war("humans", "elves", "test")
	var r: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("inbound aid blocked at war", not bool(r.get("ok", false)))
	_check("no wagon spawned at war", _sv(gs).vehicles.is_empty())
	_check("no stockpile moved at war",
		gs.resources.get_amount("elves", "food") == 500.0)


func _test_no_hall_fallback() -> void:
	# No halls and no vehicle system: the old abstract transfer keeps the
	# request working in the degenerate case.
	var gs := GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres", "elves", "undead"])
	gs.disaster_aid = SimDisasterAid.new(gs)
	gs.resources.add_resource("elves", "food", 500.0)
	_warm(gs)
	var r: Dictionary = (gs.disaster_aid as SimDisasterAid) \
		.request_inbound_aid("elves")
	_check("fallback dispatch ok", bool(r.get("ok", false)))
	_check("fallback flagged abstract", bool(r.get("abstract", false)))
	_check("fallback credits player immediately",
		gs.resources.get_amount("humans", "food") == 100.0)
	_check("fallback warms relations",
		gs.diplomacy.relation_score("humans", "elves") > 40.0)
