extends SceneTree
## Jeremy 2026-10-07 (graphics/UI hourly): inline Accept/Deny buttons on
## Messenger threads while a war-counsel plea / advisor debate / peace-terms
## counter is pending for that advisor. The buttons send "accept"/"deny"
## through the exact same path as a typed reply (SimPhone.send_message ->
## _npc_reply -> SimRulersVoice.try_order), so verdicts behave identically.
##
## Run: Godot --headless --path . -s res://tests/test_counsel_buttons.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("FAIL: ", test_name)


func _initialize() -> void:
	_test_no_rulers_voice_no_buttons()
	_test_no_pending_no_buttons()
	_test_pending_plea_detected()
	_test_non_unit_thread_no_buttons()
	_test_button_row_structure()
	_test_accept_answers_plea()
	_test_deny_answers_plea()
	_test_answered_plea_hides_buttons()
	_test_rendered_thread_shows_buttons()
	print("test_counsel_buttons: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.hiring = GuildHiring.new(gs)
	gs.army = SimArmy.new(gs)
	var phone := SimPhone.new(gs)
	gs.phone_sys = phone
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	var rv := SimRulersVoice.new(gs)
	gs.rulers_voice = rv
	# Pleas only exist mid-war; the accept path files a real surrender
	# offer, which requires a declared war in diplomacy.
	gs.diplomacy.declare_war("humans", "elves", "test")
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	return [gs, rv, phone, ui]


func _free_world(parts: Array) -> void:
	(parts[3] as PhoneUI).queue_free()
	(parts[0] as GameState).queue_free()


func _advisor(gs: GameState, job: String) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": "humans", "job": job,
		"town_id": 1, "position": Vector2(2000, 2010), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0,
		"name": "Test Advisor"})
	return u


func _seed_plea(rv: SimRulersVoice, aid: int) -> void:
	rv._peace_pleas["humans|elves"] = {"tier": 1, "state": "pending",
		"advisor_id": aid, "foe": "elves", "day": 2, "had_drain": false}
	# The accept path files a surrender offer only when the war record
	# exists (real flow always seeds it alongside the plea).
	rv._wars["humans|elves"] = {"foe": "elves", "start_day": 1,
		"ours_dead": 30, "theirs_dead": 5, "towns0": {}, "mons0": {},
		"crys0": {}, "halls0": {"ours": 1, "theirs": 1},
		"gold_hist": [5000.0, 5000.0, 5000.0]}


func _plea_state(rv: SimRulersVoice) -> String:
	var rec: Dictionary = rv._peace_pleas.get("humans|elves", {})
	return String(rec.get("state", ""))


func _accepted(rv: SimRulersVoice) -> bool:
	return _plea_state(rv) == "accepted"


func _denied(rv: SimRulersVoice) -> bool:
	return _plea_state(rv) == "denied"


func _test_no_rulers_voice_no_buttons() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var ui: PhoneUI = parts[3]
	var wa := _advisor(gs, "advisor_war")
	gs.rulers_voice = null
	ui._thread_key = "u%d" % int(wa.get("id", 0))
	_check("no rulers_voice: no buttons", ui._counsel_pending_uid() == 0)
	_free_world(parts)


func _test_no_pending_no_buttons() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var ui: PhoneUI = parts[3]
	var wa := _advisor(gs, "advisor_war")
	ui._thread_key = "u%d" % int(wa.get("id", 0))
	_check("no pending plea: no buttons", ui._counsel_pending_uid() == 0)
	_free_world(parts)


func _test_pending_plea_detected() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var ui: PhoneUI = parts[3]
	var wa := _advisor(gs, "advisor_war")
	var aid: int = int(wa.get("id", 0))
	_seed_plea(rv, aid)
	ui._thread_key = "u%d" % aid
	_check("pending plea: advisor uid detected",
		ui._counsel_pending_uid() == aid)
	_free_world(parts)


func _test_non_unit_thread_no_buttons() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var ui: PhoneUI = parts[3]
	var wa := _advisor(gs, "advisor_war")
	_seed_plea(rv, int(wa.get("id", 0)))
	ui._thread_key = "leader_elves"
	_check("leader thread: no buttons", ui._counsel_pending_uid() == 0)
	ui._thread_key = ""
	_check("empty thread key: no buttons", ui._counsel_pending_uid() == 0)
	_free_world(parts)


func _test_button_row_structure() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var ui: PhoneUI = parts[3]
	var wa := _advisor(gs, "advisor_war")
	var row: Control = ui._counsel_button_row(int(wa.get("id", 0)))
	var labels: Array = []
	_collect_button_labels(row, labels)
	_check("row: has Accept button", "Accept" in labels)
	_check("row: has Deny button", "Deny" in labels)
	_check("row: exactly two buttons", labels.size() == 2)
	row.queue_free()
	_free_world(parts)


func _collect_button_labels(c: Node, out: Array) -> void:
	if c is Button:
		out.append((c as Button).text)
	for ch in c.get_children():
		_collect_button_labels(ch, out)


func _test_accept_answers_plea() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var ui: PhoneUI = parts[3]
	var wa := _advisor(gs, "advisor_war")
	var aid: int = int(wa.get("id", 0))
	_seed_plea(rv, aid)
	ui._thread_key = "u%d" % aid
	# The tapped Accept path: identical to typing "accept".
	ui._counsel_answer(aid, "accept")
	_check("accept: plea answered",
		_accepted(rv))
	var offers: Array = gs.diplomacy.pending_surrender_offers()
	var filed := false
	for o: Dictionary in offers:
		if String(o.get("loser", "")) == "humans" \
				and String(o.get("winner", "")) == "elves":
			filed = true
	_check("accept: surrender offer filed", filed)
	_check("accept: buttons hidden after answer",
		ui._counsel_pending_uid() == 0)
	_free_world(parts)


func _test_deny_answers_plea() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var ui: PhoneUI = parts[3]
	var wa := _advisor(gs, "advisor_war")
	var aid: int = int(wa.get("id", 0))
	_seed_plea(rv, aid)
	ui._thread_key = "u%d" % aid
	ui._counsel_answer(aid, "deny")
	_check("deny: plea answered",
		_denied(rv))
	_check("deny: buttons hidden after answer",
		ui._counsel_pending_uid() == 0)
	_free_world(parts)


func _test_answered_plea_hides_buttons() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var ui: PhoneUI = parts[3]
	var wa := _advisor(gs, "advisor_war")
	var aid: int = int(wa.get("id", 0))
	_seed_plea(rv, aid)
	rv._peace_pleas["humans|elves"]["state"] = "accepted"
	ui._thread_key = "u%d" % aid
	_check("answered plea: no buttons", ui._counsel_pending_uid() == 0)
	_free_world(parts)


func _test_rendered_thread_shows_buttons() -> void:
	var parts := _make_world()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var ui: PhoneUI = parts[3]
	var wa := _advisor(gs, "advisor_war")
	var aid: int = int(wa.get("id", 0))
	_seed_plea(rv, aid)
	ui.open_thread("u%d" % aid)
	var labels: Array = []
	_collect_button_labels(ui, labels)
	_check("rendered thread: Accept button present", "Accept" in labels)
	_check("rendered thread: Deny button present", "Deny" in labels)
	_free_world(parts)
