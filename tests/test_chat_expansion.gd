## Cursing Gnomes — LANE 4 chat comprehension expansion tests (2026-10-06).
## 1. Multi-turn thread context: "why did you say that?" quotes the NPC's
##    actual last statement from thread history.
## 2. Emotional arcs: per-NPC grudge strength with per-day decay;
##    apologies accepted when the grudge is low, deflected when hot;
##    personality-matched thresholds (proud = harder, friendly = easier).
## 3. Compliments: affection up + personality-matched reply.
## 4. World questions from live game state: "who rules the elves?" names
##    the live leader; "are we at war?" uses the peace pool with no wars;
##    "how is the town doing?" reports the live town count.
## 5. NPC-initiated DMs: hot rumors about the player make NPCs DM first;
##    blocked NPCs stay silent; one DM per NPC per rumor.
## Keeps: "im gonna piss" crude-not-threat, directed piss stays a threat,
## insult_why recall of the most recent insult.
extends SceneTree


class FakeDiplomacy extends RefCounted:
	var state := "peace"
	func relation_state(_a: String, _b: String) -> String:
		return state


class FakeLeaders extends RefCounted:
	func all_leaders() -> Array:
		return [
			{"faction": "gnome", "name": "Thane Grumblecuss"},
			{"faction": "elf", "name": "Aeliana"},
			{"faction": "human", "name": "King Aldric"},
			{"faction": "ogre", "name": "Gruk"},
			{"faction": "undead", "name": "Morghul"},
		]


class FakeHearsay extends RefCounted:
	var rumors: Array = []
	func live_rumors(limit: int = 6) -> Array:
		return rumors.slice(0, limit)


class FakePhone extends RefCounted:
	var hearsay = null
	var blocked_ids: Array = []
	var sent: Array = []
	func is_blocked(uid: int) -> bool:
		return blocked_ids.has(uid)
	func npc_message(uid: int, text: String) -> void:
		sent.append({"uid": uid, "text": text})


var _passed := 0
var _failed := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", name)


func _init() -> void:
	print("\n=== Cursing Gnomes chat expansion (LANE 4) tests ===")
	_test_thread_why_said()
	_test_grudge_decay()
	_test_apology_deflect_then_accept()
	_test_apology_personality()
	_test_compliment()
	_test_world_questions()
	_test_rumor_dm()
	_test_rumor_dm_blocked_silent()
	_test_piss_kept()
	_test_insult_why_kept()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _make_gs(day: int = 1) -> Dictionary:
	return {
		"ruler_name": "TestRuler",
		"player_faction": "gnomes",
		"day_number": day,
		"resources": {"get_amount": func(_f, _r): return 100.0},
		"diplomacy": FakeDiplomacy.new(),
		"faction_leaders": FakeLeaders.new(),
		"towns": {},
	}


func _make_unit(faction: String = "gnome", uid: int = 1) -> Dictionary:
	return {
		"id": uid,
		"faction": faction,
		"display_name": "TestNPC",
		"name": "TestNPC",
		"alive": true,
	}


func _make_proud_unit(uid: int) -> Dictionary:
	var u := _make_unit("gnome", uid)
	u["mind"] = {"traits": {"proud": 0.95, "friendly": 0.1,
		"persona": "proud"}}
	return u


func _make_friendly_unit(uid: int) -> Dictionary:
	var u := _make_unit("gnome", uid)
	u["mind"] = {"traits": {"proud": 0.1, "friendly": 0.95,
		"persona": "jolly"}}
	return u


## 1. Multi-turn thread context.
func _test_thread_why_said() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 201)
	var r1 := conv.reply(unit, "you smell like sausage", gs)
	_check("insult answered", not String(r1["text"]).is_empty())
	var first_npc := String(r1["text"])
	# "why did you say that?" must resolve against the thread history —
	# the reply quotes the NPC's actual last statement.
	var r2 := conv.reply(unit, "why did you say that?", gs)
	_check("why-said intent", String(r2["intent"]) == "followup_why")
	var txt := String(r2["text"])
	_check("quotes last NPC statement", txt.contains(first_npc.left(40)))
	_check("no raw {said} token", not txt.contains("{said}"))
	_check("no raw {name} token", not txt.contains("{name}"))
	# Plain "why?" still elaborates on the last intent (old behavior kept).
	var r3 := conv.reply(unit, "tell me about taxes", gs)
	var r4 := conv.reply(unit, "why?", gs)
	_check("plain why? still elaborates",
		String(r4["intent"]) == "followup_why"
		and not String(r4["text"]).is_empty())
	_check("plain why? does not take the quote path",
		not String(r4["text"]).contains("I said"))


## 2. Grudges fade over game days.
func _test_grudge_decay() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs(1)
	var unit := _make_unit("gnome", 202)
	conv.reply(unit, "you smell like sausage", gs)
	var g1: float = conv.grudge_strength(202, gs)
	_check("insult raises grudge", g1 > 0.0)
	# 32 days later the grudge has fully decayed (8 pts at 0.5/day).
	var gs_late := _make_gs(33)
	var g2: float = conv.grudge_strength(202, gs_late)
	_check("grudge decays to zero over days", g2 <= 0.0)
	# Partial decay: 8 days later an 8-pt grudge is halved.
	var conv2 := SimConversation.new()
	var unit2 := _make_unit("gnome", 203)
	conv2.reply(unit2, "you smell like sausage", _make_gs(1))
	var g3: float = conv2.grudge_strength(203, _make_gs(9))
	_check("grudge partially decays", g3 > 0.0 and g3 < 8.0)


## 3. Apology arc: hot grudge -> deflected; cooled grudge -> accepted.
func _test_apology_deflect_then_accept() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs(1)
	var unit := _make_unit("gnome", 204)
	# Two insults = 16 grudge pts: too hot to forgive.
	conv.reply(unit, "you smell like sausage", gs)
	conv.reply(unit, "you are a pathetic clown", gs)
	_check("grudge is hot", conv.grudge_strength(204, gs) > 8.0)
	var r1 := conv.reply(unit, "i'm sorry", gs)
	_check("apology intent", String(r1["intent"]) == "apology")
	var t1 := String(r1["text"]).to_lower()
	_check("hot grudge deflects",
		t1.contains("cheap") or t1.contains("not yet")
		or t1.contains("syllables") or t1.contains("believe them"))
	_check("deflected apology softens grudge a little",
		conv.grudge_strength(204, gs) < 16.0)
	# 40 days later the grudge is gone -> accepted.
	var r2 := conv.reply(unit, "i'm sorry", _make_gs(41))
	var t2 := String(r2["text"]).to_lower()
	_check("cooled grudge accepts",
		t2.contains("accept") or t2.contains("forgiven"))
	_check("accepted apology clears grudge",
		conv.grudge_strength(204, _make_gs(41)) <= 0.0)


## 4. Personality-matched apology thresholds.
func _test_apology_personality() -> void:
	# Proud NPC: one insult (8 pts) is over their 5-pt threshold.
	var conv := SimConversation.new()
	var proud := _make_proud_unit(205)
	conv.reply(proud, "you smell like sausage", _make_gs(1))
	var rp := conv.reply(proud, "i'm sorry", _make_gs(1))
	var tp := String(rp["text"]).to_lower()
	_check("proud NPC deflects one insult",
		tp.contains("cheap") or tp.contains("not yet")
		or tp.contains("syllables") or tp.contains("believe them"))
	# Friendly NPC: one insult (8 pts) is under their 11-pt threshold.
	var conv2 := SimConversation.new()
	var friendly := _make_friendly_unit(206)
	conv2.reply(friendly, "you smell like sausage", _make_gs(1))
	var rf := conv2.reply(friendly, "i'm sorry", _make_gs(1))
	_check("friendly NPC accepts one insult",
		String(rf["text"]).to_lower().contains("accept")
		or String(rf["text"]).to_lower().contains("forgiven"))


## 5. Compliments: affection up + personality-matched reply.
func _test_compliment() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var proud := _make_proud_unit(207)
	var ckey := SimChatxCitizen.key_for(207)
	var before: float = conv.chatx_cit.aff(ckey)
	var r := conv.reply(proud, "you're smart", gs)
	_check("compliment intent", String(r["intent"]) == "compliment_npc")
	_check("compliment raises affection",
		conv.chatx_cit.aff(ckey) > before)
	_check("proud NPC basks",
		String(r["text"]).contains("I KNOW")
		or String(r["text"]).contains("complete package"))
	# Warm NPC gets the warm pool.
	var conv2 := SimConversation.new()
	var friendly := _make_friendly_unit(208)
	var r2 := conv2.reply(friendly, "i like you", _make_gs())
	var t2 := String(r2["text"]).to_lower()
	_check("warm NPC glows",
		t2.contains("blush") or t2.contains("kind")
		or t2.contains("sweetling") or t2.contains("genuinely"))


## 6. World questions answered from live game state.
func _test_world_questions() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 209)
	# "who rules the elves?" names the live leader.
	var r1 := conv.reply(unit, "who rules the elves?", gs)
	_check("rulers intent", String(r1["intent"]) == "question_rulers")
	_check("names live elf leader", String(r1["text"]).contains("Aeliana"))
	# No faction named -> full roster from live state.
	var r2 := conv.reply(unit, "who are the other rulers?", gs)
	_check("roster names leaders",
		String(r2["text"]).contains("Aeliana")
		and String(r2["text"]).contains("Gruk"))
	# "are we at war?" with no wars -> the peace pool.
	var r3 := conv.reply(unit, "are we at war?", gs)
	_check("wars intent", String(r3["intent"]) == "question_wars")
	var low := String(r3["text"]).to_lower()
	_check("peace pool when no wars",
		low.contains("none") or low.contains("no wars")
		or low.contains("zero") or low.contains("peace")
		or low.contains("no active"))
	# "how is the town doing?" reports the live town count.
	var gs2 := _make_gs()
	gs2["towns"] = {
		1: {"faction": "gnome"}, 2: {"faction": "gnome"},
		3: {"faction": "gnome"}, 4: {"faction": "gnome"},
		5: {"faction": "gnome"}, 6: {"faction": "gnome"},
		7: {"faction": "gnome"},
	}
	var r4 := conv.reply(unit, "how is the town doing?", gs2)
	_check("towns intent", String(r4["intent"]) == "question_towns")
	_check("live town count in reply", String(r4["text"]).contains("7"))
	_check("no raw {townCount} token",
		not String(r4["text"]).contains("{townCount}"))


## 7. NPC-initiated DMs from hot player rumors.
func _test_rumor_dm() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	gs["units"] = [_make_unit("gnome", 210)]
	var hs := FakeHearsay.new()
	hs.rumors = [{
		"id": 7, "heat": 0.9, "subject": "testruler", "kind": "scandal",
		"text": "TestRuler torched Thornwall",
	}]
	var phone := FakePhone.new()
	phone.hearsay = hs
	var sent: int = conv.rumor_dm_tick(gs, phone)
	_check("hot player rumor triggers a DM", sent == 1)
	_check("DM delivered", phone.sent.size() == 1)
	var msg: Dictionary = phone.sent[0]
	_check("DM names the rumor",
		String(msg["text"]).contains("torched Thornwall"))
	_check("DM resolves {name}", not String(msg["text"]).contains("{name}"))
	# Second tick: same rumor is not repeated for the same NPC.
	var sent2: int = conv.rumor_dm_tick(gs, phone)
	_check("no repeat DM for same rumor", sent2 == 0
		and phone.sent.size() == 1)
	# Cold rumors (heat < 0.75) don't trigger DMs.
	var conv2 := SimConversation.new()
	var gs2 := _make_gs()
	gs2["units"] = [_make_unit("gnome", 211)]
	var hs2 := FakeHearsay.new()
	hs2.rumors = [{
		"id": 8, "heat": 0.3, "subject": "testruler", "kind": "gossip",
		"text": "TestRuler likes turnips",
	}]
	var phone2 := FakePhone.new()
	phone2.hearsay = hs2
	_check("cold rumor stays quiet", conv2.rumor_dm_tick(gs2, phone2) == 0)


## 8. Blocked NPCs stay completely silent — even for hot rumors.
func _test_rumor_dm_blocked_silent() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	gs["units"] = [_make_unit("gnome", 212)]
	var hs := FakeHearsay.new()
	hs.rumors = [{
		"id": 9, "heat": 0.95, "subject": "testruler", "kind": "scandal",
		"text": "TestRuler torched Thornwall",
	}]
	var phone := FakePhone.new()
	phone.hearsay = hs
	phone.blocked_ids = [212]
	_check("blocked NPC sends nothing",
		conv.rumor_dm_tick(gs, phone) == 0 and phone.sent.is_empty())


## 9. Kept: "im gonna piss" is crude, not a threat.
func _test_piss_kept() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 213)
	for t in ["im gonna piss", "mmmm im gonna piss", "piss"]:
		var r: Dictionary = conv.parse_intent(t)
		_check("not threat: %s" % t, r["intent"] != "threat")
	for t in ["gonna piss on you", "im gonna piss on your shoes"]:
		var r2: Dictionary = conv.parse_intent(t)
		_check("still threat: %s" % t, r2["intent"] == "threat")
	var rr := conv.reply(unit, "mmmm im gonna piss", gs)
	_check("piss reply is not threat", String(rr["intent"]) != "threat")


## 10. Kept: insult_why recalls the most recent insult.
func _test_insult_why_kept() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 214)
	var r1 := conv.reply(unit, "you smell like sausage", gs)
	_check("insult intent detected", String(r1["intent"]) == "insult")
	var r2 := conv.reply(unit, "what offended you there?", gs)
	_check("insult_why intent", String(r2["intent"]) == "insult_why")
	_check("reply quotes the insult",
		String(r2["text"]).contains("you smell like sausage"))
