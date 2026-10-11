## Cursing Gnomes — Conversation flow tests (Jeremy 2026-10-04).
## "They should be able to carry a conversation too though. And learn.
##  A flow like state."
## Tests the flow state machine (opening -> engaged -> deep / closing),
## thread tracking (repeats, bridges, quotes), NPC questions, learning
## (facts, style, lexicon reuse), session callbacks, and save/load.
extends SceneTree


const Flow := preload("res://scripts/sim/conversation_flow.gd")


var _passed := 0
var _failed := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", name)


func _init() -> void:
	print("\n=== Cursing Gnomes conversation-flow tests ===")
	_test_flow_states()
	_test_farewell_closing()
	_test_session_callback()
	_test_repeat_reference()
	_test_topic_bridge()
	_test_fact_learning()
	_test_favorite_fact()
	_test_style_detection()
	_test_angry_closing()
	_test_questions()
	_test_quote_reference()
	_test_lexicon_reuse()
	_test_trajectory()
	_test_topic_detection()
	_test_save_load()
	_test_flow_result_keys()
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


func _mem_of(conv: SimConversation, uid: int) -> Dictionary:
	return conv._memories[uid]


## --- Flow state machine -------------------------------------------------------

func _test_flow_states() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 101)

	var r1 := conv.reply(unit, "hello", gs)
	_check("turn1 opening", String(r1["flow"]["state"]) == "opening")
	_check("turn1 count", int(r1["flow"]["turn"]) == 1)

	var r2 := conv.reply(unit, "tell me about yourself", gs)
	_check("turn2 engaged", String(r2["flow"]["state"]) == "engaged")

	# Personal topic at turn 3: still engaged (needs turn >= 4 for deep).
	var r3 := conv.reply(unit, "what are your dreams", gs)
	_check("turn3 still engaged", String(r3["flow"]["state"]) == "engaged")

	# Personal topic at turn 4: deep.
	var r4 := conv.reply(unit, "what are your fears", gs)
	_check("turn4 deep", String(r4["flow"]["state"]) == "deep")


func _test_farewell_closing() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("ogre", 102)

	conv.reply(unit, "hello", gs)
	conv.reply(unit, "i love war", gs)
	var r := conv.reply(unit, "goodbye", gs)
	_check("farewell closes", String(r["flow"]["state"]) == "closing")
	_check("closing line present", String(r["text"]).contains("ME GO"))

	# Session archived: fresh state, topics remembered for next time.
	var mem := _mem_of(conv, 102)
	_check("state reset to opening", String(mem["flow_state"]) == "opening")
	_check("turn count reset", int(mem["turn_count"]) == 0)
	_check("topics archived",
		(mem["last_session_topics"] as Array).has("war & fighting"))
	# Long-term memory survives the reset.
	_check("facts survive reset",
		(mem["player_facts"] as Dictionary).has("like_war"))


func _test_session_callback() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("ogre", 103)

	conv.reply(unit, "hello", gs)
	conv.reply(unit, "i love war", gs)
	conv.reply(unit, "goodbye", gs)

	# New conversation: the NPC brings up last session's topic.
	# (Ogres love war, so either the likes greeting callback or the flow
	# session callback fires — both mention the topic label.)
	var r := conv.reply(unit, "hello", gs)
	_check("last-time callback mentions topic",
		String(r["text"]).contains("war & fighting"))
	var mem := _mem_of(conv, 103)
	_check("callback marked done", bool(mem["session_ref_done"]))


func _test_repeat_reference() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 104)

	conv.reply(unit, "i love war", gs)
	var r := conv.reply(unit, "tell me about war", gs)
	var t := String(r["text"])
	_check("repeat reference",
		t.contains("Like I was saying") or t.contains("Like I said before")
		or t.contains("We keep coming back to"))


func _test_topic_bridge() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 105)

	conv.reply(unit, "i love war", gs)
	var r := conv.reply(unit, "i love pie", gs)
	var t := String(r["text"])
	_check("topic bridge",
		t.contains("Speaking of which") or t.contains("That reminds me")
		or t.contains("that reminds me of something")
		or t.contains("Funny you should mention")
		or t.contains("On that note") or t.contains("come to think of it")
		or t.contains("puts me in mind")
		or t.contains("connects to something else"))
	# The new topic was tracked too.
	_check("new topic tracked",
		String(r["flow"]["topic"]) == "food & feasts")


func _test_quote_reference() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 106)

	conv.reply(unit, "i love war", gs)
	conv.reply(unit, "yes", gs)
	# Same intent twice in a row, no topic: quote the earlier reply.
	var r := conv.reply(unit, "yes", gs)
	var t := String(r["text"])
	_check("quotes earlier reply",
		t.contains("Like I told you") or t.contains("Like I said"))


## --- Learning -------------------------------------------------------------------

func _test_fact_learning() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 107)

	var r1 := conv.reply(unit, "i really love war", gs)
	var mem := _mem_of(conv, 107)
	_check("fact stored",
		(mem["player_facts"] as Dictionary).has("like_war"))
	_check("fact acknowledged", String(r1["text"]).contains("Noted"))

	# Saying it again: the NPC remembers you already told them.
	var r2 := conv.reply(unit, "i really love war", gs)
	_check("repeat fact remembered",
		String(r2["text"]).contains("already told me"))


func _test_favorite_fact() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("elf", 108)

	var r := conv.reply(unit, "my favorite color is blue", gs)
	var mem := _mem_of(conv, 108)
	_check("favorite fact stored",
		(mem["player_facts"] as Dictionary).has("fav_color"))
	_check("favorite acknowledged",
		String(r["text"]).contains("blue"))


func _test_style_detection() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 109)

	conv.reply(unit, "this damn war", gs)
	conv.reply(unit, "shit, war now", gs)
	conv.reply(unit, "fuck war", gs)
	var mem := _mem_of(conv, 109)
	_check("crude style detected", Flow.style_voice(mem) == "crude")
	_check("style in flow result",
		String(conv.reply(unit, "war", gs)["flow"]["style"]) == "crude")


func _test_lexicon_reuse() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 110)

	conv.reply(unit, "hello", gs)
	var mem := _mem_of(conv, 110)
	# The player taught this NPC a word in a past session (Living Lexicon).
	conv.lexicon.learn_word("zork", ["weird", "gadget"], "u110", 1,
		"TestNPC")
	mem["flow_force_lexuse"] = true
	var r := conv.reply(unit, "how are you", gs)
	_check("learned word reused", String(r["text"]).contains("zork"))
	_check("word use counted",
		int((mem["learned_words_used"] as Dictionary).get("zork", 0)) >= 1)


## --- Mood gating ------------------------------------------------------------------

func _test_angry_closing() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("human", 111)

	conv.reply(unit, "hello", gs)
	# The NPC becomes furious mid-conversation.
	var mem := _mem_of(conv, 111)
	mem["mood"] = -50.0
	unit["emotion"] = {"name": "angry", "intensity": 0.8, "ttl": 60.0}
	var r := conv.reply(unit, "how are you", gs)
	_check("angry npc closes", String(r["flow"]["state"]) == "closing")


## --- Questions ----------------------------------------------------------------------

func _test_questions() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 112)

	conv.reply(unit, "hello", gs)
	conv.reply(unit, "tell me about yourself", gs)
	var mem := _mem_of(conv, 112)
	_check("engaged before questions",
		String(mem["flow_state"]) == "engaged")

	# Forced question (deterministic; production uses probability).
	mem["flow_force_question"] = true
	var r := conv.reply(unit, "what do you think about taxes", gs)
	_check("question asked", bool(mem["last_had_question"]))
	var asked: Array = mem["asked_questions"]
	_check("question recorded", asked.size() >= 1)
	var qtext := String(asked[asked.size() - 1]).replace("{ruler}",
		"TestRuler")
	_check("question in reply text", String(r["text"]).contains(qtext))

	# Next question is different (no immediate repeats).
	conv.reply(unit, "what are your dreams", gs)
	var asked2: Array = (mem["asked_questions"] as Array)
	_check("second question asked", asked2.size() >= 2)
	_check("no immediate repeat",
		String(asked2[asked2.size() - 1]) != String(asked2[asked2.size() - 2]))


## --- Trajectory / topic detection (direct) ----------------------------------------------

func _test_trajectory() -> void:
	_check("warming", Flow.trajectory(
		{"emotional_trajectory": [0.0, 0.0, 0.0, 40.0, 50.0, 60.0]})
		== "warming")
	_check("cooling", Flow.trajectory(
		{"emotional_trajectory": [60.0, 50.0, 40.0, 0.0, 0.0, 0.0]})
		== "cooling")
	_check("steady", Flow.trajectory(
		{"emotional_trajectory": [10.0, 12.0, 11.0, 10.0, 12.0, 11.0]})
		== "steady")
	_check("too short is steady", Flow.trajectory(
		{"emotional_trajectory": [5.0]}) == "steady")


func _test_topic_detection() -> void:
	var unit := _make_unit("gnome", 113)
	_check("war topic",
		Flow.detect_topic(unit, "i love war", "war_declare")
		== "war & fighting")
	_check("war question topic",
		Flow.detect_topic(unit, "tell me about war", "question_wars")
		== "war & fighting")
	_check("peace topic",
		Flow.detect_topic(unit, "let's make peace", "peace_offer")
		== "peace & quiet")
	_check("no topic for greeting",
		Flow.detect_topic(unit, "hello there", "greeting") == "")
	_check("intent topic fallback",
		Flow.detect_topic(unit, "tell me a tale", "story_request")
		== "stories")


## --- Save/load --------------------------------------------------------------------------

func _test_save_load() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 114)

	conv.reply(unit, "hello", gs)
	conv.reply(unit, "i love war", gs)

	var data := conv.get_save_data()
	var conv2 := SimConversation.new()
	conv2.load_save_data(data)
	var mem2: Dictionary = conv2._memories[114]
	_check("flow state survives", String(mem2["flow_state"]) == "engaged")
	_check("turn count survives", int(mem2["turn_count"]) == 2)
	_check("facts survive",
		(mem2["player_facts"] as Dictionary).has("like_war"))
	_check("topics survive",
		(mem2["topics_discussed"] as Array).has("war & fighting"))


func _test_flow_result_keys() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("elf", 115)

	var r := conv.reply(unit, "hello", gs)
	_check("flow key present", r.has("flow"))
	var f: Dictionary = r["flow"]
	for k in ["state", "turn", "topic", "trajectory", "style"]:
		_check("flow has " + k, f.has(k))
