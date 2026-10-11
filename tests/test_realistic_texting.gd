extends SceneTree
## Cursing Gnomes — realistic texting tests (Jeremy 2026-10-04).
##
## Typing indicators, send delays, read receipts, online status.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_realistic_texting.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes realistic texting tests ===")
	_test_send_queues_reply()
	_test_typing_indicator_shows()
	_test_typing_indicator_clears_on_delivery()
	_test_reply_delivered_after_delay()
	_test_message_status_flow()
	_test_read_receipts()
	_test_longer_message_longer_typing()
	_test_online_status()
	_test_presence_text()
	_test_npc_initiated_no_typing()
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


func _new_world() -> Dictionary:
	var gs = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(farr)
	gs.player_faction = "gnomes"
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	return {"gs": gs, "phone": phone}


func _spawn(w: Dictionary, faction: String) -> Dictionary:
	var gs = w["gs"]
	return gs.add_unit({"faction": faction, "alive": true, "mind": {}})


func _test_send_queues_reply() -> void:
	var w: Dictionary = _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var u: Dictionary = _spawn(w, "humans")
	phone.send_message(int(u["id"]), "hello")
	# Reply is queued, not instant — only the player's message exists.
	var th: Dictionary = phone._thread("u%d" % int(u["id"]))
	_check("player msg queued", (th["messages"] as Array).size() == 1)
	_check("pending queue has reply", phone._pending.size() == 1)
	gs.queue_free()


func _test_typing_indicator_shows() -> void:
	var w: Dictionary = _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var u: Dictionary = _spawn(w, "humans")
	phone.send_message(int(u["id"]), "hello")
	# Before SEND_DELAY: no typing yet.
	_check("no typing before delay", not phone.is_typing("u%d" % int(u["id"])))
	# After SEND_DELAY: typing shows.
	gs.game_time += 1.0
	phone.tick(0.0)
	_check("typing shows after delay", phone.is_typing("u%d" % int(u["id"])))
	gs.queue_free()


func _test_typing_indicator_clears_on_delivery() -> void:
	var w: Dictionary = _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var u: Dictionary = _spawn(w, "humans")
	phone.send_message(int(u["id"]), "hello")
	gs.game_time += 10.0
	phone.tick(0.0)
	_check("typing cleared after delivery",
		not phone.is_typing("u%d" % int(u["id"])))
	_check("queue empty after delivery", phone._pending.is_empty())
	gs.queue_free()


func _test_reply_delivered_after_delay() -> void:
	var w: Dictionary = _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var u: Dictionary = _spawn(w, "humans")
	phone.send_message(int(u["id"]), "hello")
	gs.game_time += 10.0
	phone.tick(0.0)
	var th: Dictionary = phone._thread("u%d" % int(u["id"]))
	_check("reply delivered", (th["messages"] as Array).size() == 2)
	var reply: Dictionary = (th["messages"] as Array)[1]
	_check("reply from npc", String(reply.get("from", "")) == "npc")
	_check("reply non-empty", String(reply.get("text", "")) != "")
	_check("unread incremented", int(th["unread"]) == 1)
	gs.queue_free()


func _test_message_status_flow() -> void:
	var w: Dictionary = _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var u: Dictionary = _spawn(w, "humans")
	phone.send_message(int(u["id"]), "hello")
	var th: Dictionary = phone._thread("u%d" % int(u["id"]))
	var msg: Dictionary = (th["messages"] as Array)[0]
	# Player's message starts as "sending", flips to "delivered" when queued.
	_check("starts sending or delivered",
		String(msg.get("status", "")) in ["sending", "delivered"])
	gs.queue_free()


func _test_read_receipts() -> void:
	var w: Dictionary = _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var u: Dictionary = _spawn(w, "humans")
	phone.send_message(int(u["id"]), "hello")
	# Fast-forward past SEEN_DELAY and tick.
	gs.game_time += 10.0
	phone.tick(0.0)
	var th: Dictionary = phone._thread("u%d" % int(u["id"]))
	var msg: Dictionary = (th["messages"] as Array)[0]
	_check("player msg seen after delay", String(msg.get("status", "")) == "seen")
	gs.queue_free()


func _test_longer_message_longer_typing() -> void:
	var short_dur: float = SimPhone.typing_duration("hi")
	var long_dur: float = SimPhone.typing_duration(
		"This is a much longer message that should take more time to type out.")
	_check("longer message = longer typing", long_dur > short_dur)
	_check("typing capped", long_dur <= SimPhone.TYPING_MAX)
	_check("typing has floor", short_dur >= SimPhone.TYPING_BASE)


func _test_online_status() -> void:
	var w: Dictionary = _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var u: Dictionary = _spawn(w, "humans")
	# Fresh contact with a recent message counts as online.
	phone.send_message(int(u["id"]), "hello")
	_check("recent contact online", phone.is_online("u%d" % int(u["id"])))
	gs.queue_free()


func _test_presence_text() -> void:
	var w: Dictionary = _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var u: Dictionary = _spawn(w, "humans")
	phone.send_message(int(u["id"]), "hello")
	var pres: String = phone.presence_text("u%d" % int(u["id"]))
	_check("presence non-empty", pres != "")
	_check("presence online or seen",
		pres == "online" or pres.begins_with("last seen"))
	gs.queue_free()


func _test_npc_initiated_no_typing() -> void:
	var w: Dictionary = _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var u: Dictionary = _spawn(w, "humans")
	# NPC-initiated messages arrive instantly (no typing — they're events).
	phone.npc_message(int(u["id"]), "Hey, something happened!")
	var th: Dictionary = phone._thread("u%d" % int(u["id"]))
	_check("npc msg instant", (th["messages"] as Array).size() == 1)
	_check("no typing for npc-initiated",
		not phone.is_typing("u%d" % int(u["id"])))
	gs.queue_free()
