extends SceneTree
## Cursing Gnomes — regression tests for Jeremy's 2026-10-04 playtest fixes:
##   Bug 2: new games start at midday (12:00), not midnight.
##   Bug 3: wall-raise prompts ask ONCE per region; the player answers yes/no
##          via hearsay (no 57-message spam).
##
## Run: Godot --headless --path . -s res://tests/test_wall_hearsay.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("  FAIL: ", name)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_midday_start()
	_test_wall_verdict_parsing()
	_test_wall_question_one_ask()
	_test_wall_answer_yes()
	_test_wall_answer_no()
	_test_wall_answer_unclear_keeps_question()
	_test_npc_message_dedup()
	print("test_wall_hearsay: %d passed, %d failed" % [_passed, _failed])
	if not _failures.is_empty():
		push_error("failures: " + str(_failures))
	quit(1 if _failed > 0 else 0)


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	return gs


func _new_phone(gs: GameState) -> SimPhone:
	var phone := SimPhone.new(gs)
	gs.phone_sys = phone
	return phone


func _add_advisor(gs: GameState) -> int:
	var u: Dictionary = gs.add_unit({
		"name": "Tansy", "faction": "humans", "job": "military advisor",
	})
	return int(u.get("id", 0))


## Bug 2: game starts at midday.
func _test_midday_start() -> void:
	var gs := _new_game()
	_check(is_equal_approx(gs.game_time, Config.DAY_LENGTH_SECONDS * 0.5),
		"midday: game_time starts at half a day")
	var s := SimSeasons.new(gs)
	_check(is_equal_approx(s.hour_of_day(), 12.0),
		"midday: hour_of_day() == 12.0 on Day 1")
	_check(gs.day_number == 1, "midday: still Day 1")
	_check(not s.is_night_hour(), "midday: not a night hour")
	gs.queue_free()


## Bug 3: yes/no verdict parsing.
func _test_wall_verdict_parsing() -> void:
	_check(SimPhone._parse_wall_verdict("yes") == 1, "verdict: 'yes' -> 1")
	_check(SimPhone._parse_wall_verdict("Yeah, do it") == 1, "verdict: 'Yeah, do it' -> 1")
	_check(SimPhone._parse_wall_verdict("raise them") == 1, "verdict: 'raise them' -> 1")
	_check(SimPhone._parse_wall_verdict("no") == 0, "verdict: 'no' -> 0")
	_check(SimPhone._parse_wall_verdict("nope, skip") == 0, "verdict: 'nope, skip' -> 0")
	_check(SimPhone._parse_wall_verdict("don't") == 0, "verdict: \"don't\" -> 0")
	_check(SimPhone._parse_wall_verdict("maybe later") == -1, "verdict: 'maybe later' -> -1")
	_check(SimPhone._parse_wall_verdict("what walls?") == -1, "verdict: 'what walls?' -> -1")


## Bug 3: one ask — asking twice only sends one message.
func _test_wall_question_one_ask() -> void:
	var gs := _new_game()
	var phone := _new_phone(gs)
	var aid := _add_advisor(gs)
	phone.ask_wall_question(aid, "Stonehollow", "raise border walls? reply YES or NO.")
	phone.ask_wall_question(aid, "Stonehollow", "raise border walls? reply YES or NO.")
	var th: Dictionary = phone._thread(phone._key_for(aid))
	var msgs: Array = th.get("messages", [])
	_check(msgs.size() == 1, "one-ask: second ask_wall_question does not re-send")
	_check(phone._wall_questions.size() == 1, "one-ask: one pending question recorded")
	gs.queue_free()


## Bug 3: player says yes -> wall_answer emitted with raise=true, question cleared.
func _test_wall_answer_yes() -> void:
	var gs := _new_game()
	var phone := _new_phone(gs)
	var aid := _add_advisor(gs)
	var got: Array = []
	gs.bus.wall_answer.connect(func(region: String, raise: bool) -> void:
		got.append([region, raise]))
	phone.ask_wall_question(aid, "Stonehollow", "raise border walls? reply YES or NO.")
	phone.send_message(aid, "yes, raise them")
	_check(got.size() == 1, "hearsay-yes: wall_answer emitted once")
	if got.size() == 1:
		_check(String(got[0][0]) == "Stonehollow", "hearsay-yes: region matches")
		_check(bool(got[0][1]) == true, "hearsay-yes: raise == true")
	_check(phone._wall_questions.is_empty(), "hearsay-yes: question cleared after answer")
	gs.queue_free()


## Bug 3: player says no -> wall_answer emitted with raise=false.
func _test_wall_answer_no() -> void:
	var gs := _new_game()
	var phone := _new_phone(gs)
	var aid := _add_advisor(gs)
	var got: Array = []
	gs.bus.wall_answer.connect(func(region: String, raise: bool) -> void:
		got.append([region, raise]))
	phone.ask_wall_question(aid, "Stonehollow", "raise border walls? reply YES or NO.")
	phone.send_message(aid, "no, skip it")
	_check(got.size() == 1, "hearsay-no: wall_answer emitted once")
	if got.size() == 1:
		_check(bool(got[0][1]) == false, "hearsay-no: raise == false")
	_check(phone._wall_questions.is_empty(), "hearsay-no: question cleared after answer")
	gs.queue_free()


## Bug 3: unclear reply does NOT consume the question.
func _test_wall_answer_unclear_keeps_question() -> void:
	var gs := _new_game()
	var phone := _new_phone(gs)
	var aid := _add_advisor(gs)
	var got: Array = []
	gs.bus.wall_answer.connect(func(region: String, raise: bool) -> void:
		got.append([region, raise]))
	phone.ask_wall_question(aid, "Stonehollow", "raise border walls? reply YES or NO.")
	phone.send_message(aid, "tell me about the weather")
	_check(got.is_empty(), "hearsay-unclear: no wall_answer for non-yes/no")
	_check(phone._wall_questions.size() == 1, "hearsay-unclear: question still pending")
	gs.queue_free()


## Bug 3 (defense in depth): identical consecutive npc_messages collapse.
func _test_npc_message_dedup() -> void:
	var gs := _new_game()
	var phone := _new_phone(gs)
	var aid := _add_advisor(gs)
	var spam: String = "Stonehollow: raise border walls? (~0 gold)"
	for i in 5:
		phone.npc_message(aid, spam)
	var th: Dictionary = phone._thread(phone._key_for(aid))
	var msgs: Array = th.get("messages", [])
	_check(msgs.size() == 1, "dedup: 5 identical npc_messages collapse to 1")
	# A different message still goes through.
	phone.npc_message(aid, "Something else entirely.")
	_check((phone._thread(phone._key_for(aid)).get("messages", []) as Array).size() == 2,
		"dedup: different text is not collapsed")
	gs.queue_free()
