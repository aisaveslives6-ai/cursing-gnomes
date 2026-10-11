extends SceneTree
## Cursing Gnomes — family life-decision failsafe tests (2026-10-08).
##
## SimFamily._tick_decisions was a documented-but-never-built stub: a player
## petition left unanswered in the Royal Court hung the citizen's life
## decision forever and could wedge the 6-slot queue. The failsafe now
## sweeps petitions older than DECISION_STALE_DAYS through court.decide
## (the exact player-tap path: card closes, ruling story, outcome applies).
## A StubCourt emulates the real court's petition/decide contract against
## the real event bus, so the full loop is exercised.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_family_decisions.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


class StubCourt extends RefCounted:
	## Minimal stand-in for SimRoyalCourt: keeps petition cards, and decide()
	## marks the card resolved and emits petition_decided synchronously,
	## exactly like the real court (which is what closes the loop into
	## SimFamily._on_petition_decided).
	var _bus: Object
	var _seq := 100
	var cards: Array = []

	func _init(bus: Object) -> void:
		_bus = bus

	func petition(_from_unit: Dictionary, kind: String, _text: String,
			options: Array) -> Dictionary:
		var p := {"id": _seq, "kind": kind, "options": options.duplicate(),
			"resolved": false, "choice": -1}
		_seq += 1
		cards.append(p)
		return p

	func decide(petition_id: int, option_index: int) -> Dictionary:
		for p: Dictionary in cards:
			if int(p.get("id", -1)) == petition_id \
					and not bool(p.get("resolved", false)):
				p["resolved"] = true
				p["choice"] = option_index
				var opts: Array = p.get("options", [])
				var choice := String(opts[option_index]) \
					if option_index < opts.size() else ""
				_bus.petition_decided.emit(p, choice)
				return {"story": true}
		return {}


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes family decision-failsafe tests ===")
	_test_stale_leave_allowed()
	_test_stale_leave_refused()
	_test_fresh_petition_survives()
	_test_sweep_wired_into_tick()
	_test_stale_join_allowed()
	_test_queue_stamps_day()
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


func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	_said.clear()
	_stories.clear()
	gs.bus.unit_said.connect(func(uid: int, text: String) -> void: _said.append([uid, text]))
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	var fam := SimFamily.new(gs)
	fam._court = StubCourt.new(gs.bus)
	return [gs, fam]


func _worker(gs: GameState, faction: String, pos: Vector2, gender: String) -> Dictionary:
	var u := gs.add_unit({"faction": faction, "job": "worker", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 30.0, "gender": gender, "is_worker": true})
	return u


func _leave_decision(u: Dictionary, auto_yes: float) -> Dictionary:
	return {"kind": "leave", "unit_id": int(u.get("id", -1)),
		"faction": String(u.get("faction", "")),
		"title": "test leave", "body": "test body", "auto_yes": auto_yes}


func _court_card(fam: SimFamily) -> Dictionary:
	var court: StubCourt = fam._court
	_check("court: exactly one card", court.cards.size() == 1)
	return court.cards[0] if not court.cards.is_empty() else {}


func _test_stale_leave_allowed() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _worker(gs, "humans", Vector2(100, 100), "m")
	fam.ensure(u)
	fam._queue_life_decision(_leave_decision(u, 1.0))  # auto_yes=1 -> allow
	_check("leave-allow: pending queued", fam._pending.size() == 1)
	gs.day_number += 3  # past DECISION_STALE_DAYS (2.0)
	fam._tick_decisions(4.0)
	_check("leave-allow: pending drained", fam._pending.is_empty())
	_check("leave-allow: court card resolved",
		bool(_court_card(fam).get("resolved", false)))
	_check("leave-allow: unit became adventurer", bool(u.get("adventurer", false)))
	_check("leave-allow: job adventurer", String(u.get("job", "")) == "adventurer")


func _test_stale_leave_refused() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _worker(gs, "humans", Vector2(100, 100), "m")
	fam.ensure(u)
	fam._queue_life_decision(_leave_decision(u, 0.0))  # auto_yes=0 -> refuse
	gs.day_number += 5
	fam._tick_decisions(4.0)
	_check("leave-refuse: pending drained", fam._pending.is_empty())
	_check("leave-refuse: court card resolved",
		bool(_court_card(fam).get("resolved", false)))
	_check("leave-refuse: unit did NOT leave", not bool(u.get("adventurer", false)))
	_check("leave-refuse: unit stays worker", String(u.get("job", "")) == "worker")
	var stayed := false
	for s: Array in _said:
		if String(s[1]) == "Fine. I'll stay.":
			stayed = true
	_check("leave-refuse: grudging-stay line spoken", stayed)


func _test_fresh_petition_survives() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _worker(gs, "humans", Vector2(100, 100), "m")
	fam.ensure(u)
	fam._queue_life_decision(_leave_decision(u, 1.0))
	# Same day: well under DECISION_STALE_DAYS.
	fam._tick_decisions(4.0)
	_check("fresh: still pending", fam._pending.size() == 1)
	_check("fresh: court card still open",
		not bool(_court_card(fam).get("resolved", false)))
	_check("fresh: unit untouched", not bool(u.get("adventurer", false)))
	# One day later: still fresh.
	gs.day_number += 1
	fam._tick_decisions(4.0)
	_check("fresh+1d: still pending", fam._pending.size() == 1)


func _test_sweep_wired_into_tick() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _worker(gs, "humans", Vector2(100, 100), "m")
	fam.ensure(u)
	fam._queue_life_decision(_leave_decision(u, 1.0))
	gs.day_number += 3
	fam.tick(2.0)  # below DECISION_TICK (4.0): no sweep yet
	_check("tick-wire: no sweep below cadence", fam._pending.size() == 1)
	fam.tick(2.5)  # accumulator 4.5 >= 4.0: sweep fires
	_check("tick-wire: sweep fired via tick", fam._pending.is_empty())
	_check("tick-wire: unit became adventurer", bool(u.get("adventurer", false)))


func _test_stale_join_allowed() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var adv := _worker(gs, "humans", Vector2(100, 100), "m")
	fam.ensure(adv)
	adv["adventurer"] = true
	adv["job"] = "adventurer"
	fam._queue_life_decision({"kind": "join", "unit_id": int(adv.get("id", -1)),
		"faction": "humans", "new_faction": "gnomes",
		"title": "test join", "body": "test body", "auto_yes": 1.0})
	gs.day_number += 4
	fam._tick_decisions(4.0)
	_check("join-allow: pending drained", fam._pending.is_empty())
	_check("join-allow: faction switched",
		String(adv.get("faction", "")) == "gnomes")
	_check("join-allow: no longer adventurer",
		not bool(adv.get("adventurer", false)))
	_check("join-allow: enters labor market",
		String(adv.get("job", "")) == "unemployed")


func _test_queue_stamps_day() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _worker(gs, "humans", Vector2(100, 100), "m")
	fam.ensure(u)
	gs.day_number = 42
	fam._queue_life_decision(_leave_decision(u, 0.5))
	var stamped := true
	for pid in fam._pending.keys():
		var d: Dictionary = fam._pending[pid]
		if int(d.get("_queued_day", -1)) != 42:
			stamped = false
	_check("queue: _queued_day stamped", stamped and not fam._pending.is_empty())
