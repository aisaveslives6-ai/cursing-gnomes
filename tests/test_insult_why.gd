## Cursing Gnomes — insult_why + piss-threat regression tests.
## Bug 1 (2026-10-06): "what offended you there?" got "I didn't understand
## a word of that" — the NPC must recall the actual insult from memory.
## Bug 2 (2026-10-06): "im gonna piss" was parsed as a THREAT — bare
## "piss" (I need to urinate, crude) must not route to threat; only
## directed forms ("piss on you/your") are threats.
extends SceneTree


var _passed := 0
var _failed := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", name)


func _init() -> void:
	print("\n=== Cursing Gnomes insult_why / piss-threat tests ===")
	_test_insult_why_parsing()
	_test_insult_why_recall()
	_test_insult_why_no_memory()
	_test_insult_why_pools()
	_test_piss_not_threat()
	_test_piss_directed_still_threat()
	_test_piss_end_to_end()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _make_gs() -> Dictionary:
	return {
		"ruler_name": "TestRuler",
		"player_faction": "gnomes",
		"resources": {"get_amount": func(_f, _r): return 100.0},
	}


func _make_unit(faction: String = "gnome", uid: int = 1) -> Dictionary:
	return {
		"id": uid,
		"faction": faction,
		"display_name": "TestNPC",
		"name": "TestNPC",
	}


func _test_insult_why_parsing() -> void:
	var conv := SimConversation.new()
	var qs := [
		"what offended you there?",
		"why are you offended",
		"why are you mad at me",
		"what did i say",
		"what was offensive",
		"what made you angry",
		"why the attitude",
		"whats your problem",
		"what did i do",
	]
	for q in qs:
		var r: Dictionary = conv.parse_intent(q)
		_check("insult_why parsed: %s" % q, r["intent"] == "insult_why")


func _test_insult_why_recall() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 101)
	# Insult the NPC first (records the insult in episodic memory).
	var r1 := conv.reply(unit, "you smell like sausage", gs)
	_check("insult intent detected", String(r1["intent"]) == "insult")
	# Ask what offended them — the reply must quote the actual insult.
	var r2 := conv.reply(unit, "what offended you there?", gs)
	_check("insult_why intent", String(r2["intent"]) == "insult_why")
	var txt := String(r2["text"])
	_check("reply quotes the insult", txt.contains("you smell like sausage"))
	_check("no raw {insult} token leaks", not txt.contains("{insult}"))


func _test_insult_why_no_memory() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	# Fresh NPC with no insults on record — must deflect, not leak a token.
	var unit := _make_unit("gnome", 102)
	var r := conv.reply(unit, "what offended you?", gs)
	_check("insult_why intent (no memory)", String(r["intent"]) == "insult_why")
	var txt := String(r["text"])
	_check("fallback has text", not txt.is_empty())
	_check("no raw {insult} token leaks (fallback)",
		not txt.contains("{insult}"))


func _test_insult_why_pools() -> void:
	for race in ["gnome", "human", "elf", "ogre"]:
		var pool := ConversationResponses.get_pool("insult_why", race)
		_check("insult_why pool: %s" % race, not pool.is_empty())
		var none_pool := ConversationResponses.get_pool("insult_why_none",
			race)
		_check("insult_why_none pool: %s" % race, not none_pool.is_empty())
	# Every insult_why line must carry the {insult} token so the hook
	# always has something to substitute.
	for race in ["gnome", "human", "elf", "ogre"]:
		for line in ConversationResponses.get_pool("insult_why", race):
			_check("insult_why line has {insult} token",
				String(line).contains("{insult}"))


func _test_piss_not_threat() -> void:
	var conv := SimConversation.new()
	for t in ["im gonna piss", "mmmm im gonna piss", "piss", "piss off",
			"i need to piss"]:
		var r: Dictionary = conv.parse_intent(t)
		_check("not threat: %s" % t, r["intent"] != "threat")


func _test_piss_directed_still_threat() -> void:
	var conv := SimConversation.new()
	for t in ["gonna piss on you", "im gonna piss on your shoes",
			"im going to piss on you", "piss on you", "piss on your boots"]:
		var r: Dictionary = conv.parse_intent(t)
		_check("still threat: %s" % t, r["intent"] == "threat")
	# Unrelated threats unaffected.
	for t in ["i will kill you", "im gonna wreck you", "gonna sue you"]:
		var r2: Dictionary = conv.parse_intent(t)
		_check("threat intact: %s" % t, r2["intent"] == "threat")


func _test_piss_end_to_end() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 103)
	# "im gonna piss" must NOT produce a threat reply — it routes to the
	# Common Tongue swear reaction (crude, not threatening).
	var r := conv.reply(unit, "mmmm im gonna piss", gs)
	_check("piss reply is not threat", String(r["intent"]) != "threat")
	var txt := String(r["text"]).to_lower()
	_check("piss reply is crude/swear-voiced",
		txt.contains("piss") or txt.contains("filthy")
		or txt.contains("foul"))
	# A directed piss threat still gets the threat pool.
	var r2 := conv.reply(unit, "im gonna piss on your shoes", gs)
	_check("directed piss is threat", String(r2["intent"]) == "threat")
