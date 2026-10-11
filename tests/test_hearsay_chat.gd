extends SceneTree
## Cursing Gnomes — hearsay-in-Messenger tests (Jeremy 2026-10-04).
##
## NPCs bring up rumors/gossip during Messenger conversations.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_chat.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay-in-chat tests ===")
	_test_gossip_no_rumors_no_crash()
	_test_gossip_mentions_hot_rumor()
	_test_gossip_not_every_time()
	_test_gossip_no_repeat()
	_test_confront_player_rumor()
	_test_shorten()
	_test_forecast_posted_seeds_rumor()
	_test_forecast_posted_empty_no_crash()
	_test_forecast_fired_seeds_rumor()
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


func _new_gs() -> Dictionary:
	var gs = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.set_ruler_name("ass")
	return {"gs": gs}


func _new_phone(gs: GameState):
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return phone


func _spawn(gs: GameState, faction: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true, "mind": {}})


func _test_gossip_no_rumors_no_crash() -> void:
	var d: Dictionary = _new_gs()
	var gs: GameState = d["gs"]
	var phone = _new_phone(gs)
	var u: Dictionary = _spawn(gs, "humans")
	var conv = load("res://scripts/sim/conversation.gd").new()
	# No rumors seeded — should not crash, should not add gossip.
	var res: Dictionary = conv.reply(u, "hello", gs)
	_check("no crash without rumors", String(res.get("text", "")) != "")
	gs.queue_free()


func _test_gossip_mentions_hot_rumor() -> void:
	var d: Dictionary = _new_gs()
	var gs: GameState = d["gs"]
	var phone = _new_phone(gs)
	# Seed a hot rumor.
	phone.hearsay.seed_rumor("The thicc moose mooned the human town hall!", "disaster", "moose", 0.9)
	var u: Dictionary = _spawn(gs, "humans")
	var conv = load("res://scripts/sim/conversation.gd").new()
	# Try multiple times — gossip is 30% chance.
	var mentioned := false
	for i in range(20):
		var mem: Dictionary = {}
		var g: String = conv._hearsay_gossip(u, "humans", mem, gs)
		if g != "":
			mentioned = true
			break
	_check("hot rumor mentioned", mentioned)
	gs.queue_free()


func _test_gossip_not_every_time() -> void:
	var d: Dictionary = _new_gs()
	var gs: GameState = d["gs"]
	var phone = _new_phone(gs)
	phone.hearsay.seed_rumor("Something happened somewhere.", "misc", "", 0.5)
	var u: Dictionary = _spawn(gs, "humans")
	var conv = load("res://scripts/sim/conversation.gd").new()
	# With 30% chance, some calls should return empty.
	var empties := 0
	for i in range(20):
		var mem: Dictionary = {}
		if conv._hearsay_gossip(u, "humans", mem, gs) == "":
			empties += 1
	_check("not every reply has gossip", empties > 0)
	gs.queue_free()


func _test_gossip_no_repeat() -> void:
	var d: Dictionary = _new_gs()
	var gs: GameState = d["gs"]
	var phone = _new_phone(gs)
	phone.hearsay.seed_rumor("The moose did a thing.", "disaster", "moose", 0.9)
	var u: Dictionary = _spawn(gs, "humans")
	var conv = load("res://scripts/sim/conversation.gd").new()
	var mem: Dictionary = {}
	var first: String = conv._hearsay_gossip(u, "humans", mem, gs)
	# Same memory dict — second call should not repeat the same rumor.
	var count := 0
	for i in range(10):
		var g: String = conv._hearsay_gossip(u, "humans", mem, gs)
		if g == first and first != "":
			count += 1
	_check("no repeat gossip", count == 0 or first == "")
	gs.queue_free()


func _test_confront_player_rumor() -> void:
	var d: Dictionary = _new_gs()
	var gs: GameState = d["gs"]
	var phone = _new_phone(gs)
	# Seed a rumor ABOUT the player.
	phone.hearsay.seed_rumor("The ruler ass is a racist.", "scandal", "ass", 1.0)
	var u: Dictionary = _spawn(gs, "elves")
	var conv = load("res://scripts/sim/conversation.gd").new()
	var mem: Dictionary = {}
	var g: String = conv._hearsay_gossip(u, "elves", mem, gs)
	# Player rumors take priority — should confront.
	_check("player rumor confronted", g != "")
	gs.queue_free()


func _test_shorten() -> void:
	var conv = load("res://scripts/sim/conversation.gd").new()
	var short: String = conv._shorten("hi")
	_check("short unchanged", short == "hi")
	var long_text: String = "x".repeat(200)
	var shortened: String = conv._shorten(long_text)
	_check("long shortened", shortened.length() < 200 and shortened.ends_with("..."))


## Jeremy 2026-10-04: the monthly disaster forecast posted/fired with
## nobody listening — hearsay now gossips about it (HTML
## generateDisasterCalendar / processCalendarDisasters systemMsg parity).
func _test_forecast_posted_seeds_rumor() -> void:
	var d: Dictionary = _new_gs()
	var gs: GameState = d["gs"]
	var phone = _new_phone(gs)
	_spawn(gs, "gnomes")  # author for the Squabble post
	var before_posts: int = (phone.state["posts"] as Array).size()
	gs.bus.disaster_forecast_posted.emit({
		12: {"type": "giant_ass", "label": "Giant Ass", "done": false},
		5: {"type": "bandit_raid", "label": "Bandit Raid", "done": false},
	})
	var found := false
	for r in phone.hearsay.state["rumors"]:
		var rd: Dictionary = r
		var t: String = String(rd.get("text", ""))
		if String(rd.get("kind", "")) == "forecast" \
				and t.find("Giant Ass") >= 0 and t.find("day 12") >= 0 \
				and t.find("Bandit Raid") >= 0 and t.find("day 5") >= 0:
			found = true
	_check("forecast posted seeds rumor", found)
	_check("forecast posted squabble post",
		(phone.state["posts"] as Array).size() == before_posts + 1)
	gs.queue_free()


func _test_forecast_posted_empty_no_crash() -> void:
	var d: Dictionary = _new_gs()
	var gs: GameState = d["gs"]
	var phone = _new_phone(gs)
	var before: int = (phone.hearsay.state["rumors"] as Array).size()
	gs.bus.disaster_forecast_posted.emit({})
	_check("empty forecast seeds nothing",
		(phone.hearsay.state["rumors"] as Array).size() == before)
	gs.queue_free()


func _test_forecast_fired_seeds_rumor() -> void:
	var d: Dictionary = _new_gs()
	var gs: GameState = d["gs"]
	var phone = _new_phone(gs)
	_spawn(gs, "gnomes")  # author for the Squabble post
	var before_posts: int = (phone.state["posts"] as Array).size()
	gs.bus.disaster_forecast_fired.emit("Giant Ass")
	var found := false
	for r in phone.hearsay.state["rumors"]:
		var rd: Dictionary = r
		if String(rd.get("kind", "")) == "forecast" \
				and String(rd.get("text", "")).find("Giant Ass") >= 0:
			found = true
	_check("forecast fired seeds rumor", found)
	_check("forecast fired squabble post",
		(phone.state["posts"] as Array).size() == before_posts + 1)
	gs.queue_free()
