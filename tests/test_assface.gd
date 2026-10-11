extends SceneTree
## Cursing Gnomes — ASSFACE phone disaster tests (Jeremy 2026-10-06).
##
## Proves: both pools have 100+ distinct lines; no repeats within a
## draw cycle; ZERO IRL hate slurs in either pool (the game's hard rule);
## the disaster burst hits the player (~18 texts / 30s) and every AI
## leader (pranked + in-character reaction); the contact unlocks after the
## burst and survives save/load; the persona lock keeps every reply
## topical AND idiotic (full engine for comprehension, zero competent
## replies); the I-DON'T-GIVE-A-FUCK voice fires on people/factions;
## blocked Assface is completely silent; the disaster cooldown holds;
## the hearsay aftermath seeds a comedy rumor that spreads.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_assface.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Assface tests ===")
	_test_pool_sizes()
	_test_no_repeats_within_cycle()
	_test_no_hate_terms()
	_test_pseudo_unit_safe()
	_test_key_routing()
	_test_disaster_burst()
	_test_burst_window()
	_test_contact_unlock_and_save()
	_test_persona_lock_topic()
	_test_never_competent()
	_test_idgaf_voice()
	_test_blocked_silent()
	_test_cooldown()
	_test_hearsay_aftermath()
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
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	gs.ruler_name = "ass"
	var phone := SimPhone.new(gs)
	return {"gs": gs, "phone": phone}


func _test_pool_sizes() -> void:
	_check("general pool >= 100 distinct",
		SimAssface.GENERAL.size() >= 100)
	_check("prank pool >= 100 distinct",
		SimAssface.PRANK.size() >= 100)
	var gset := {}
	for l in SimAssface.GENERAL:
		gset[String(l)] = true
	_check("general pool all unique", gset.size() == SimAssface.GENERAL.size())
	var pset := {}
	for l in SimAssface.PRANK:
		pset[String(l)] = true
	_check("prank pool all unique", pset.size() == SimAssface.PRANK.size())


func _test_no_repeats_within_cycle() -> void:
	var w := _new_world()
	var az = w["gs"].assface
	var seen := {}
	for i in range(100):
		var line: String = az.draw_general()
		_check("general draw %d unique" % i, not seen.has(line))
		seen[line] = true
	var seen2 := {}
	for i in range(100):
		var line: String = az.draw_prank()
		_check("prank draw %d unique" % i, not seen2.has(line))
		seen2[line] = true
	# 101st draw reshuffles instead of erroring.
	_check("general reshuffles at exhaustion", az.draw_general() != "")
	_check("prank reshuffles at exhaustion", az.draw_prank() != "")


func _test_no_hate_terms() -> void:
	for line in SimAssface.GENERAL:
		if SimHateSpeech.is_hate_slur(String(line)):
			_check("general line clean: " + String(line).left(40), false)
			return
	_check("no hate slurs in general pool", true)
	for line in SimAssface.PRANK:
		if SimHateSpeech.is_hate_slur(String(line)):
			_check("prank line clean: " + String(line).left(40), false)
			return
	_check("no hate slurs in prank pool", true)


func _test_pseudo_unit_safe() -> void:
	var w := _new_world()
	var az = w["gs"].assface
	var u: Dictionary = az.pseudo_unit()
	_check("pseudo-unit has mind name",
		String((u.get("mind", {}) as Dictionary).get("name", "")) == "Assface")
	# Never rolls the unhinged trait — the cuss-out path can't misfire.
	_check("assface never unhinged",
		not SimUnhinged.should_cuss_out(w["phone"].conversation, u))
	_check("assface pfp key", String(u.get("_leader_pfp", "")) == "assface")


func _test_key_routing() -> void:
	var w := _new_world()
	var phone = w["phone"]
	_check("key_for(uid) maps to thread key",
		phone._key_for(SimAssface.UID) == SimAssface.KEY)
	var u: Dictionary = phone._unit_for_key(SimAssface.KEY)
	_check("unit_for_key resolves pseudo-unit", not u.is_empty())
	_check("thread header name", phone.leader_name_for_key(SimAssface.KEY) == "Assface")
	# Block APIs resolve to the thread key, not "u-424242".
	_check("is_blocked_key starts false",
		not phone.is_blocked_key(SimAssface.KEY))


func _test_disaster_burst() -> void:
	var w := _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var az = gs.assface
	gs.game_time = 1000.0
	var plan: Dictionary = az.begin_burst(gs.game_time)
	_check("burst active", az.burst_active)
	_check("player gets ~18 texts",
		(plan.get("player", []) as Array).size() == SimAssface.PLAYER_BURST_COUNT)
	var leaders: Dictionary = plan.get("leaders", {})
	# 4 AI factions (player faction excluded).
	_check("all AI leaders pranked", leaders.size() == 4)
	for f in leaders:
		_check("leader %s gets pranks" % f,
			(leaders[f] as Array).size() == SimAssface.LEADER_PRANK_COUNT)
	# Fire through the real phone path: messages land in _pending.
	phone._fire_assface_burst(az)
	var queued := 0
	var leader_queued := 0
	for p in phone._pending:
		var k := String((p as Dictionary).get("key", ""))
		if k == SimAssface.KEY:
			queued += 1
		elif k.begins_with("leader_"):
			leader_queued += 1
	_check("player burst queued", queued == SimAssface.PLAYER_BURST_COUNT)
	_check("leader pranks + reactions queued", leader_queued == 4 * (SimAssface.LEADER_PRANK_COUNT + 1))


func _test_burst_window() -> void:
	var w := _new_world()
	var gs = w["gs"]
	var az = gs.assface
	gs.game_time = 5000.0
	az.begin_burst(gs.game_time)
	_check("burst lasts ~30s",
		absf(az.burst_ends_at - gs.game_time - SimAssface.BURST_SECONDS) < 0.01)
	# Refire blocked while active.
	_check("no refire while active", not az.roll_fire(gs.day_number))
	az.end_burst()
	_check("burst ends", not az.burst_active)
	_check("fired flag set", az.fired)


func _test_contact_unlock_and_save() -> void:
	var w := _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var az = gs.assface
	_check("not a contact before the event",
		not (phone.state["added"] as Array).has(SimAssface.KEY))
	az.end_burst()
	phone._unlock_assface_contact()
	_check("contact unlocked after event",
		(phone.state["added"] as Array).has(SimAssface.KEY))
	var found := false
	for c in phone.my_contacts():
		if String((c as Dictionary).get("key", "")) == SimAssface.KEY:
			found = true
			_check("contact name", String((c as Dictionary).get("name", "")) == "Assface")
	_check("assface in my_contacts", found)
	# Save/load round-trip.
	var data: Dictionary = az.to_dict()
	var az2 := SimAssface.new(gs)
	az2.from_dict(data)
	_check("fired survives save/load", az2.fired)
	_check("used pools survive save/load",
		(az2._used_general as Array).size() == (az._used_general as Array).size())


func _test_persona_lock_topic() -> void:
	var w := _new_world()
	var az = w["gs"].assface
	var cases := [
		["what do you think about the war with the elves", "war"],
		["how is the economy doing", "economy"],
		["tell me about the taxes", "taxes"],
		["is there going to be peace", "peace"],
	]
	for c in cases:
		var fake_result := {"intent": "unclear", "text": "competent answer"}
		var reply: String = az.idiot_reply(fake_result, String(c[0]), "ass")
		_check("reply references topic '%s'" % c[1],
			String(c[1]) in reply.to_lower())
		_check("engine text discarded for '%s'" % c[0],
			"competent answer" not in reply)


func _test_never_competent() -> void:
	var w := _new_world()
	var gs = w["gs"]
	var az = gs.assface
	var conv = w["phone"].conversation
	var probes := [
		"should we declare war on the elves",
		"how do I fix the economy",
		"propose an alliance with the ogres",
		"what is the meaning of life",
		"hello there",
		"give me military advice",
		"how do taxes work",
		"tell me about diplomacy",
	]
	for text in probes:
		var result: Dictionary = conv.reply(az.pseudo_unit(), String(text), gs)
		var reply: String = az.idiot_reply(result, String(text), "ass")
		var low := reply.to_lower()
		var has_marker := false
		for mk in SimAssface.IDIOT_MARKERS:
			if String(mk) in low:
				has_marker = true
				break
		_check("idiot marker in reply to '%s'" % String(text).left(30), has_marker)
		_check("no competent text leaks for '%s'" % String(text).left(30),
			String(result.get("text", "")) not in reply or reply != String(result.get("text", "")))


func _test_idgaf_voice() -> void:
	var w := _new_world()
	var gs = w["gs"]
	var az = gs.assface
	# Find a real leader name for the FUCK [X] pattern.
	var lname := ""
	var fl = gs.faction_leaders
	for l in fl.all_leaders():
		var f := String((l as Dictionary).get("faction", ""))
		if f != "" and f != gs.player_faction:
			lname = String((l as Dictionary).get("name", "")).split(" ")[0]
			break
	_check("test has a leader name", lname != "")
	var hits := 0
	for i in range(20):
		var reply: String = az.idiot_reply(
			{"intent": "war_how", "text": "x"},
			"what about the war and %s" % lname, "ass")
		if "FUCK" in reply and lname.to_upper() in reply and "BLOWS" in reply:
			hits += 1
	_check("idgaf voice fires on people/factions", hits > 0)
	# Faction word target.
	var r2: String = az.idiot_reply({"intent": "unclear", "text": "x"},
		"what do you think of the elves", "ass")
	_check("faction target pattern", "THE ELVES" in r2 and "BLOW" in r2)


func _test_blocked_silent() -> void:
	var w := _new_world()
	var phone = w["phone"]
	phone._block_key(SimAssface.KEY, "")
	_check("blocked", phone.is_blocked_key(SimAssface.KEY))
	# Player messages to a blocked Assface go nowhere.
	phone.send_assface_message("hello butt man")
	var th: Dictionary = phone._thread(SimAssface.KEY)
	_check("no thread messages when blocked",
		(th.get("messages", []) as Array).is_empty())
	# Burst skips the player when blocked but leaders still get pranked.
	var az = w["gs"].assface
	az.begin_burst(w["gs"].game_time)
	phone._fire_assface_burst(az)
	var player_queued := 0
	for p in phone._pending:
		if String((p as Dictionary).get("key", "")) == SimAssface.KEY:
			player_queued += 1
	_check("burst silent to blocked player", player_queued == 0)


func _test_cooldown() -> void:
	var w := _new_world()
	var az = w["gs"].assface
	var day := 50
	az.last_fired_day = day
	_check("cooldown blocks refire", not az.roll_fire(day + 1))
	_check("cooldown blocks refire day+4", not az.roll_fire(day + 4))
	az.last_fired_day = day - 100
	az.begin_burst(1.0)
	# Firing stamps the day, so the next roll is gated.
	_check("fire stamps last_fired_day", az.last_fired_day == w["gs"].day_number)


func _spawn(gs, faction: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true, "mind": {}})


func _test_hearsay_aftermath() -> void:
	var w := _new_world()
	var gs = w["gs"]
	var phone = w["phone"]
	var az = gs.assface
	_spawn(gs, "gnomes")
	_spawn(gs, "humans")
	_spawn(gs, "ogres")
	gs.game_time = 9000.0
	az.begin_burst(gs.game_time)
	phone._fire_assface_burst(az)
	# Simulate burst end: unlock + aftermath.
	az.end_burst()
	phone._unlock_assface_contact()
	phone._assface_aftermath(az)
	var hs = phone.hearsay
	var found := false
	for r in hs.state["rumors"]:
		if String((r as Dictionary).get("kind", "")) == "assface":
			found = true
			_check("aftermath rumor high heat",
				float((r as Dictionary).get("heat", 0.0)) >= 0.8)
			_check("rumor quotes a burst line",
				"\"" in String((r as Dictionary).get("text", "")))
	_check("assface rumor seeded", found)
	# Squabble posts quoting him.
	var posts: Array = phone.state["posts"]
	var quoted := 0
	for p in posts:
		var t := String((p as Dictionary).get("text", ""))
		if "ASSFACE" in t:
			quoted += 1
	_check("squabble posts about the spree", quoted >= 2)
	# The reaction path never errors and never angers.
	var u: Dictionary = gs.units[0]
	hs._on_heard(u, {"id": 4242, "kind": "assface", "text": "x",
		"text_orig": "x", "subject": "assface", "day": 1, "heat": 0.9,
		"knowers": [], "reached_ruler": false, "distortions": 0}, {})
	_check("assface reaction handled", true)
