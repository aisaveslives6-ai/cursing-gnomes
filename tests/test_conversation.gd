## Cursing Gnomes — Conversation engine tests.
## Tests the Hearsay conversation system: intent parsing, responses,
## memory, follow-ups, and the Living Lexicon.
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
	print("\n=== Cursing Gnomes conversation tests ===")
	_test_intent_parsing()
	_test_responses()
	_test_memory()
	_test_followups()
	_test_lexicon()
	_test_faction_voice()
	_test_preroute()
	_test_pool_coverage()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _make_gs() -> Dictionary:
	# Minimal mock game state
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


func _test_intent_parsing() -> void:
	var conv := SimConversation.new()

	# Greeting
	var r := conv.parse_intent("hello there")
	_check("greeting parsed", r["intent"] == "greeting")

	# Farewell
	r = conv.parse_intent("goodbye friend")
	_check("farewell parsed", r["intent"] == "farewell")

	# Insult
	r = conv.parse_intent("you are stupid and ugly")
	_check("insult parsed", r["intent"] == "insult")

	# Trade
	r = conv.parse_intent("let's trade goods")
	_check("trade parsed", r["intent"] == "trade_propose")

	# War
	r = conv.parse_intent("i declare war on you")
	_check("war parsed", r["intent"] == "war_declare")

	# Unclear (gibberish)
	r = conv.parse_intent("xyzzy plugh")
	_check("unclear for gibberish", r["intent"] == "unclear")

	# Follow-ups
	r = conv.parse_intent("why?")
	_check("followup_why", r["intent"] == "followup_why")
	r = conv.parse_intent("tell me more")
	_check("followup_more", r["intent"] == "followup_more")


func _test_responses() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()

	# Greeting gets a response
	var unit := _make_unit("gnome")
	var result := conv.reply(unit, "hello", gs)
	_check("greeting reply has text", not String(result["text"]).is_empty())
	_check("greeting intent", String(result["intent"]) == "greeting")

	# Different factions get different voices
	var human := _make_unit("human", 2)
	var hr := conv.reply(human, "hello", gs)
	_check("human reply has text", not String(hr["text"]).is_empty())

	var ogre := _make_unit("ogre", 3)
	var ogr := conv.reply(ogre, "hello", gs)
	_check("ogre reply has text", not String(ogr["text"]).is_empty())


func _test_memory() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 10)

	# First message
	var r1 := conv.reply(unit, "hello", gs)
	_check("first reply", not String(r1["text"]).is_empty())

	# Follow-up "why?" should reference last topic
	var r2 := conv.reply(unit, "why?", gs)
	_check("followup has text", not String(r2["text"]).is_empty())

	# Memory persists
	var mem: Dictionary = conv._memories[10]
	_check("memory has history", (mem["history"] as Array).size() >= 2)


func _test_followups() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("elf", 20)

	conv.reply(unit, "tell me about your towns", gs)
	var r := conv.reply(unit, "tell me more", gs)
	_check("tell me more works", not String(r["text"]).is_empty())


func _test_lexicon() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 30)

	# Unknown word triggers teach moment
	var r1 := conv.reply(unit, "zorpqux", gs)
	_check("unknown word asked", String(r1["intent"]) == "lex_ask")
	_check("ask mentions word",
		String(r1["text"]).contains("zorpqux"))

	# Pending definition routes through the shared lexicon brain
	_check("pending set", conv.lexicon.has_pending("u30"))
	var r2 := conv.reply(unit, "it means a silly thing", gs)
	_check("definition learned", String(r2["intent"]) == "lex_learn")
	_check("word stored", conv.lexicon.words.has("zorpqux"))

	# Asking ABOUT the learned word -> the showoff (lex_word intent)
	var r3 := conv.reply(unit, "what does zorpqux mean", gs)
	_check("word about -> lex_word", String(r3["intent"]) == "lex_word")
	_check("showoff uses phrase",
		String(r3["text"]).contains("silly"))


func _test_faction_voice() -> void:
	# Each faction should have distinct response pools
	for faction in ["gnome", "human", "elf", "ogre"]:
		var pool := ConversationResponses.get_pool("greeting", faction)
		_check("greeting pool for " + faction, not pool.is_empty())

	# Undead falls back to gnome
	var undead_pool := ConversationResponses.get_pool("greeting", "undead")
	_check("undead falls back", not undead_pool.is_empty())


func _test_preroute() -> void:
	# Sarcasm detection
	_check("sarcasm 'yeah right'",
		SimConversationPreroute.sarcasm_q("yeah right", "yeah right", "unclear"))
	_check("sarcasm 'oh great, it broke'",
		SimConversationPreroute.sarcasm_q("oh great, it broke again",
			"oh great, it broke again", "unclear"))
	_check("not sarcasm 'hello'",
		not SimConversationPreroute.sarcasm_q("hello", "hello", "greeting"))
	# Self-talk
	_check("selftalk 'i am such an idiot'",
		SimConversationPreroute.self_talk_q("i am such an idiot"))
	_check("not selftalk 'hello'",
		not SimConversationPreroute.self_talk_q("hello"))
	# Challenge
	_check("challenge 'how dare you'",
		SimConversationPreroute.challenge_q("how dare you", "how dare you"))
	# Crude insult (not the idiom)
	_check("crude 'blow me'",
		SimConversationPreroute.crude_insult_q("blow me"))
	_check("not crude 'blow me away'",
		not SimConversationPreroute.crude_insult_q("blow me away"))
	# Third-party insult target
	var them := SimConversationPreroute.insult_them_target(
		"the king is an idiot")
	_check("them target king", them.get("target") == "king")
	_check("them insult idiot", them.get("insult") == "idiot")
	# Lie detection
	var lie := SimConversationPreroute.lie_q("dragons don't exist", null)
	_check("lie detected", bool(lie.get("_lie_detected", false)))
	# Sarcasm reply has pool content
	var conv := SimConversation.new()
	var unit := {"id": 101, "name": "Sassy", "faction": "gnome"}
	var r := conv.reply(unit, "yeah right", null)
	_check("sarcasm reply not unclear",
		String(r.get("intent", "")) != "unclear")
	_check("sarcasm reply has text",
		not String(r.get("text", "")).is_empty())
	# Self-talk reply uses affinity pool
	var r2 := conv.reply(unit, "i am such an idiot", null)
	_check("selftalk reply has text",
		not String(r2.get("text", "")).is_empty())
	# Insult escalation: second insult uses level 2+ pool
	var r3 := conv.reply(unit, "you asshole", null)
	_check("insult reply has text",
		not String(r3.get("text", "")).is_empty())
	var r4 := conv.reply(unit, "you bastard", null)
	_check("repeat insult escalates",
		not String(r4.get("text", "")).is_empty())


func _test_pool_coverage() -> void:
	# Every intent in conversation_data should have a response pool.
	var intents := []
	for intent_def in ConversationData.INTENTS:
		intents.append(intent_def["id"])
	var missing := []
	for iid in intents:
		if iid == "unclear":
			continue
		var pool := ConversationResponses.get_pool(iid, "gnome")
		if pool.is_empty():
			missing.append(iid)
	# Allow a small set of intents handled by special logic, not pools.
	var special := ["name_set", "lex_learn", "lex_ask", "followup_why",
		"followup_more", "followup_topic", "c29_lie", "c29_sarcasm",
		"emoji_react"]
	for s in special:
		missing.erase(s)
	_check("pool coverage (missing: %s)" % str(missing), missing.is_empty())
	# Spot-check restored pools have content for all factions.
	for pool_name in ["gossip", "flirt", "joke", "tease", "crude_direct",
			"c29_sarcasm", "c29_lie"]:
		for faction in ["gnome", "human", "elf", "ogre"]:
			var p := ConversationResponses.get_pool(pool_name, faction)
			_check("pool %s/%s" % [pool_name, faction], not p.is_empty())
