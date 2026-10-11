## Cursing Gnomes — Living Lexicon tests.
## HTML fix79 parity restoration: NPCs learn the player's words, remember them
## across saves, show them off in chat, accept corrections, and spread them
## as daily gossip. Mere mentions never trigger vocabulary commentary.
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
	print("\n=== Cursing Gnomes lexicon tests ===")
	_test_teach_flow()
	_test_persistence()
	_test_showoff_and_second_npc()
	_test_correction()
	_test_cancel()
	_test_passing_mention()
	_test_wants_first()
	_test_daily_tick()
	_test_backchannel_shape()
	_test_known_word_gate()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _make_gs() -> Dictionary:
	return {
		"ruler_name": "TestRuler",
		"player_faction": "gnomes",
		"day_number": 5,
		"resources": {"get_amount": func(_f, _r): return 100.0},
	}


func _make_unit(faction: String = "gnome", uid: int = 1) -> Dictionary:
	return {
		"id": uid,
		"faction": faction,
		"display_name": "TestNPC",
		"name": "TestNPC",
	}


func _test_teach_flow() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 1)

	# Unknown word -> the NPC asks what it means (HTML LexiconHook ask).
	var r1 := conv.reply(unit, "zorpqux", gs)
	_check("ask intent", String(r1["intent"]) == "lex_ask")
	_check("ask names word",
		String(r1["text"]).contains("zorpqux"))
	_check("pending recorded", conv.lexicon.has_pending("u1"))

	# The definition is learned, with keywords AND the natural phrase.
	var r2 := conv.reply(unit, "it means a silly made-up creature", gs)
	_check("learn intent", String(r2["intent"]) == "lex_learn")
	_check("word stored", conv.lexicon.words.has("zorpqux"))
	var e: Dictionary = conv.lexicon.words["zorpqux"]
	_check("keywords extracted",
		String(e["meaning"]).contains("silly"))
	_check("natural phrase kept",
		String(e["phrase"]).contains("silly made-up creature"))
	_check("taught_by recorded", String(e["taught_by"]) == "u1")
	_check("pending cleared", not conv.lexicon.has_pending("u1"))

	# Asking ABOUT the word -> the showoff (lex_word), preferring the phrase.
	var r3 := conv.reply(unit, "what does zorpqux mean", gs)
	_check("word-about intent", String(r3["intent"]) == "lex_word")
	_check("showoff uses phrase",
		String(r3["text"]).contains("silly made-up creature"))
	_check("uses counted", int(e["uses"]) == 1)
	_check("shown_by recorded",
		(e["shown_by"] as Array).has("u1"))


func _test_persistence() -> void:
	var lx := SimLexicon.new()
	lx.learn_word("zorp", ["attack"], "u7", 5, "Knackers")
	var d := lx.to_dict()
	var lx2 := SimLexicon.new()
	lx2.from_dict(d)
	_check("word survives round-trip", lx2.words.has("zorp"))
	var e: Dictionary = lx2.words["zorp"]
	_check("meaning survives", String(e["meaning"]) == "attack")
	_check("taught_by survives", String(e["taught_by"]) == "u7")
	_check("day survives", int(e["day"]) == 5)
	_check("teacher name survives",
		String(e["teacher_name"]) == "Knackers")
	# Baseline seeds are re-applied on load and never clobber taught words.
	_check("seed baseline present", lx2.words.has("gonna"))
	_check("taught word not a seed",
		not bool(lx2.words["zorp"].get("seed", false)))


func _test_showoff_and_second_npc() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 1)
	conv.lexicon.learn_word("zorp", ["attack"], "u1", 5, "TestNPC")

	# First NPC: deterministic showoff line.
	var r1 := conv.reply(unit, "what does zorp mean", gs)
	_check("first ask showoff intent",
		String(r1["intent"]) == "lex_word")
	_check("showoff signature line",
		String(r1["text"]).contains("Look at me, learning"))

	# Same NPC asked again: plain reminder, never another showoff.
	var r1b := conv.reply(unit, "what does zorp mean", gs)
	_check("repeat ask lex_word", String(r1b["intent"]) == "lex_word")
	_check("no second showoff",
		not String(r1b["text"]).contains("Look at me, learning"))
	_check("reminder still explains",
		String(r1b["text"]).contains("zorp"))

	# A different NPC gets their own first showoff (HTML: shownBy is per-NPC).
	var unit2 := _make_unit("gnome", 2)
	unit2["display_name"] = "OtherNPC"
	var r2 := conv.reply(unit2, "what does zorp mean", gs)
	_check("second npc lex_word", String(r2["intent"]) == "lex_word")
	_check("second npc showoff",
		String(r2["text"]).contains("zorp"))
	var e: Dictionary = conv.lexicon.words["zorp"]
	_check("both npcs in shown_by",
		(e["shown_by"] as Array).has("u1")
		and (e["shown_by"] as Array).has("u2"))


func _test_correction() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 3)
	conv.lexicon.learn_word("zorp", ["run away"], "u3", 5, "TestNPC")

	# "no, I meant X" re-teaches the last taught word (HTML correction path).
	var r := conv.reply(unit, "no, i meant to attack things", gs)
	_check("correction intent", String(r["intent"]) == "lex_correct")
	var e: Dictionary = conv.lexicon.words["zorp"]
	_check("meaning corrected",
		String(e["meaning"]).contains("attack"))

	# Correction as the pending answer learns the pending word.
	var r1 := conv.reply(unit, "wobbleflop", gs)
	_check("ask for wobbleflop", String(r1["intent"]) == "lex_ask")
	var r2 := conv.reply(unit, "no, i meant a shaky dance", gs)
	_check("pending correction learned",
		String(r2["intent"]) == "lex_learn")
	_check("wobbleflop stored",
		conv.lexicon.words.has("wobbleflop"))


func _test_cancel() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 4)
	var r1 := conv.reply(unit, "snazzlefrazzle", gs)
	_check("ask for snazzlefrazzle", String(r1["intent"]) == "lex_ask")
	var r2 := conv.reply(unit, "never mind", gs)
	_check("cancel intent", String(r2["intent"]) == "lex_learn")
	_check("cancel clears pending",
		not conv.lexicon.has_pending("u4"))
	_check("cancelled word not stored",
		not conv.lexicon.words.has("snazzlefrazzle"))


func _test_passing_mention() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 5)
	conv.lexicon.learn_word("zorp", ["attack"], "u5", 5, "TestNPC")

	# A mere mention is NOT a vocabulary moment — the sentence's intent governs.
	var r := conv.reply(unit, "i'm gonna zorp your house", gs)
	_check("mention is not lex_word",
		String(r["intent"]) != "lex_word")
	_check("mention gets a real reply",
		not String(r["text"]).is_empty())


func _test_wants_first() -> void:
	var lx := SimLexicon.new()
	_check("correction wants first",
		lx.wants_first("no, i meant something else"))
	_check("wrong wants first", lx.wants_first("that's wrong"))
	_check("not quite wants first", lx.wants_first("not quite"))
	_check("fact wants first", lx.wants_first("my dog is rex"))
	_check("greeting does not", not lx.wants_first("hello there"))
	_check("no pending initially", not lx.has_pending("u9"))


func _test_daily_tick() -> void:
	var gs := {
		"ruler_name": "TestRuler",
		"day_number": 10,
		"units": [
			{"id": 1, "display_name": "Teacher", "faction": "gnome"},
			{"id": 2, "display_name": "Student", "faction": "gnome"},
		],
	}
	var lx := SimLexicon.new()
	lx.bind(gs)
	lx.learn_word("blorp", ["dance"], "u1", 5, "Teacher")

	# Spread: one word overheard by one NPC, once per day.
	var txt := lx.daily_tick()
	_check("spread produces gossip", txt.contains("blorp"))
	_check("spread recorded",
		(lx.words["blorp"]["known_by"] as Array).has("u2"))
	_check("spread count", int(lx.words["blorp"]["spread"]) == 1)
	_check("one spread per day", lx.daily_tick() == "")

	# Words younger than 2 days are not spread candidates.
	var lx2 := SimLexicon.new()
	lx2.bind(gs)
	lx2.learn_word("fresh", ["new"], "u1", 10, "Teacher")
	_check("fresh word not spread", lx2.daily_tick() == "")


func _test_backchannel_shape() -> void:
	var lx := SimLexicon.new()
	lx.learn_word("zorp", ["attack"], "u1", 5, "Knackers")
	var tw: Array = lx.taught_words()
	_check("taught_words non-empty", not tw.is_empty())
	var found := false
	for w in tw:
		var d: Dictionary = w
		if String(d.get("word", "")) == "zorp":
			found = true
			_check("meaning present",
				String(d.get("meaning", "")) != "")
			_check("taught_by present",
				String(d.get("taught_by", "")) != "")
	_check("zorp in taught_words", found)


## Jeremy 2026-10-06: the original knew every ordinary word via its
## dictionary cascade (English wordfreq, Urban Dictionary, Wikipedia
## titles, Common Tongue seeds) — NPCs must NEVER ask to be taught words
## like "butt". Full audit ported into assets/data/lexicon_known.txt.
func _test_known_word_gate() -> void:
	var lx := SimLexicon.new()
	# The reported case: "butt ass" must yield no teachable unknown.
	_check("butt ass: nothing to teach", lx.salient_unknown("butt ass") == "")
	_check("butt is known", SimLexicon.is_known_word("butt"))
	# Spot-check the ported lists: swears, slang, anatomy, urban, CT seeds.
	for w in ["shit", "fuck", "damn", "hell", "crap", "piss", "dick",
			"tits", "wank", "bollocks", "arse", "goon", "whore", "slut",
			"cunt", "cock", "wanker", "dumbass", "yeet", "rizz", "skibidi"]:
		_check("known: %s" % w, SimLexicon.is_known_word(w))
	# Stopwords were and are known.
	_check("hello known", SimLexicon.is_known_word("hello"))
	# The full cascade actually loaded (English 88k + urban 300k + wiki
	# 150k + CT seeds, deduplicated).
	_check("known-word list loaded", SimLexicon.known_word_count() > 400000)
	# Fabricated strings are still teachable — the gate didn't swallow them.
	_check("fabricated not known", not SimLexicon.is_known_word("zqxjkvwx"))
	_check("fabricated teachable",
		lx.salient_unknown("teach me zqxjkvwx") == "zqxjkvwx")
	# A fabricated word next to real words: only the fabrication surfaces.
	_check("mixed picks fabrication",
		lx.salient_unknown("you are a butt flibbertygibbit") == "flibbertygibbit")
