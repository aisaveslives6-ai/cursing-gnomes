extends SceneTree
## Cursing Gnomes — inbound aid request rate limits (follow-up to the
## 2026-10-11 inbound-aid caravan work).
##
## The outbound tap-menu aid path caps dispatches at 3/recipient/day via
## _player_aid_day ("so aid can't be spammed for infinite relations"), but
## the inbound "Request Aid" path had NO cap: every tap drained up to 100
## food from the donor's stockpile and, on delivery, granted +8 relations
## (which also feeds the war-spare aid_given kindness history). A player
## could strip-mine an ally's entire food store and farm unlimited
## goodwill by tapping repeatedly.
##
## SimDisasterAid.request_inbound_aid() now caps at INBOUND_AID_PER_DAY (2)
## successful requests per donor per game day. Failed requests (cold
## relations, empty stores, war) never consume quota — same as the
## outbound path. Quotas are per-donor and reset on the next game day.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_inbound_aid_limits.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed := 0
var _failed := 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes inbound aid limit tests ===")
	_test_third_request_same_day_refused()
	_test_quota_resets_next_day()
	_test_failed_requests_dont_consume_quota()
	_test_separate_quotas_per_donor()
	_test_cap_value_is_two()
	print("=== inbound aid limits: %d passed, %d failed ===" % [_passed, _failed])
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


## Fresh headless game: player = humans; halls for humans + elves (+ gnomes
## when asked); vehicles wired like world.gd does. Elves start with 500 food.
func _make_game(with_gnome_hall: bool = false) -> GameState:
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
	if with_gnome_hall:
		gs.add_building({"type": "town_hall", "faction": "gnomes",
			"position": Vector2(100, 2000), "alive": true, "complete": true,
			"hp": 2000.0, "max_hp": 2000.0})
		gs.resources.add_resource("gnomes", "food", 500.0)
	gs.resources.add_resource("elves", "food", 500.0)
	return gs


## Warm a donor past the 30-point help gate.
func _warm(gs: GameState, donor: String) -> void:
	gs.diplomacy.adjust_score(donor, "humans", 40.0)


func _aid(gs: GameState) -> SimDisasterAid:
	return gs.disaster_aid as SimDisasterAid


func _wagon_count(gs: GameState) -> int:
	return (gs.vehicles as SimVehicles).vehicles.size()


func _test_third_request_same_day_refused() -> void:
	var gs := _make_game()
	_warm(gs, "elves")
	var r1: Dictionary = _aid(gs).request_inbound_aid("elves")
	var r2: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("first request ok", bool(r1.get("ok", false)))
	_check("second request ok", bool(r2.get("ok", false)))
	_check("two wagons rolling", _wagon_count(gs) == 2)
	_check("donor debited 200", gs.resources.get_amount("elves", "food") == 300.0)
	var r3: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("third request refused", not bool(r3.get("ok", false)))
	_check("refusal says they've given all they can",
		String(r3.get("msg", "")).find("all they can spare") >= 0)
	_check("no third wagon", _wagon_count(gs) == 2)
	_check("no further debit on refusal",
		gs.resources.get_amount("elves", "food") == 300.0)
	gs.queue_free()


func _test_quota_resets_next_day() -> void:
	var gs := _make_game()
	_warm(gs, "elves")
	_aid(gs).request_inbound_aid("elves")
	_aid(gs).request_inbound_aid("elves")
	var refused: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("capped before day rollover", not bool(refused.get("ok", false)))
	gs.day_number += 1
	var r: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("request ok again next day", bool(r.get("ok", false)))
	_check("donor debited again next day",
		gs.resources.get_amount("elves", "food") == 200.0)
	gs.queue_free()


func _test_failed_requests_dont_consume_quota() -> void:
	var gs := _make_game()
	# Cold declines (relations 0 < 30) must not eat the quota.
	for i in 3:
		var cold: Dictionary = _aid(gs).request_inbound_aid("elves")
		_check("cold decline %d still refused" % (i + 1),
			not bool(cold.get("ok", false)))
	_warm(gs, "elves")
	# Empty-stores decline must not eat the quota either.
	gs.resources.add_resource("elves", "food", -500.0)
	var empty: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("empty-stores decline", not bool(empty.get("ok", false)))
	gs.resources.add_resource("elves", "food", 500.0)
	var r1: Dictionary = _aid(gs).request_inbound_aid("elves")
	var r2: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("first request ok after failed ones", bool(r1.get("ok", false)))
	_check("second request ok after failed ones", bool(r2.get("ok", false)))
	var r3: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("third still capped", not bool(r3.get("ok", false)))
	gs.queue_free()


func _test_separate_quotas_per_donor() -> void:
	var gs := _make_game(true)
	_warm(gs, "elves")
	_warm(gs, "gnomes")
	_aid(gs).request_inbound_aid("elves")
	_aid(gs).request_inbound_aid("elves")
	var capped: Dictionary = _aid(gs).request_inbound_aid("elves")
	_check("elves capped at two", not bool(capped.get("ok", false)))
	var r: Dictionary = _aid(gs).request_inbound_aid("gnomes")
	_check("gnomes still give (separate quota)", bool(r.get("ok", false)))
	_check("gnome donor debited",
		gs.resources.get_amount("gnomes", "food") == 400.0)
	_check("elf donor untouched by gnome request",
		gs.resources.get_amount("elves", "food") == 300.0)
	gs.queue_free()


func _test_cap_value_is_two() -> void:
	# Pins the constant: exactly INBOUND_AID_PER_DAY successes, then refusal.
	_check("INBOUND_AID_PER_DAY is 2",
		SimDisasterAid.INBOUND_AID_PER_DAY == 2)
	var gs := _make_game()
	_warm(gs, "elves")
	var oks := 0
	for i in 4:
		if bool(_aid(gs).request_inbound_aid("elves").get("ok", false)):
			oks += 1
	_check("exactly two successes out of four taps", oks == 2)
	gs.queue_free()
