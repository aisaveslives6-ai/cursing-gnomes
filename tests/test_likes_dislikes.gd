## Cursing Gnomes — likes/dislikes engine tests.
## Tests per-NPC tastes, reaction detection, explicit expressions,
## emotion/memory/mood integration, greeting callbacks, and gossip.
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
	print("\n=== Cursing Gnomes likes/dislikes tests ===")
	_test_tastes()
	_test_reactions()
	_test_expressions()
	_test_effects()
	_test_greeting_callback()
	_test_engine_wiring()
	_test_conversation_hook()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _make_unit(uid: int, faction: String) -> Dictionary:
	return {"id": uid, "faction": faction, "name": "TestNPC"}


func _make_gs() -> Dictionary:
	return {"ruler_name": "TestRuler", "player_faction": "gnomes",
		"game_time": 100.0, "day_number": 5}


func _make_mem() -> Dictionary:
	return {"history": [], "last_intent": "", "last_topic": "", "last_you": "",
		"prev_you": "", "mood": 0.0, "met": true, "lex_pending": false,
		"lex_word": "", "insult_count": 0}


## Find a unit id whose tastes include the topic (deterministic search).
func _find_with(faction: String, topic: String, in_likes: bool) -> Dictionary:
	for uid in range(1, 400):
		var u := _make_unit(uid, faction)
		var t: Dictionary = SimLikesDislikes.for_unit(u)
		var arr: Array = t.get("likes" if in_likes else "dislikes", [])
		if arr.has(topic):
			return u
	return {}


func _test_tastes() -> void:
	# Deterministic: same id -> same tastes
	var a: Dictionary = SimLikesDislikes.for_unit(_make_unit(42, "ogres"))
	var b: Dictionary = SimLikesDislikes.for_unit(_make_unit(42, "ogres"))
	_check("deterministic likes", a["likes"] == b["likes"])
	_check("deterministic dislikes", a["dislikes"] == b["dislikes"])
	# 3-5 each
	_check("3-5 likes", a["likes"].size() >= 3 and a["likes"].size() <= 5)
	_check("3-5 dislikes", a["dislikes"].size() >= 3 and a["dislikes"].size() <= 5)
	# No overlap
	var overlap := false
	for t in a["likes"]:
		if (a["dislikes"] as Array).has(t):
			overlap = true
	_check("no like/dislike overlap", not overlap)
	# Faction flavor: most ogres like war, most elves like nature
	var ogre_war := 0
	var elf_nature := 0
	for uid in range(1, 51):
		if (SimLikesDislikes.for_unit(_make_unit(uid, "ogres"))["likes"] as Array).has("war"):
			ogre_war += 1
		if (SimLikesDislikes.for_unit(_make_unit(uid, "elves"))["likes"] as Array).has("nature"):
			elf_nature += 1
	_check("ogres mostly like war", ogre_war >= 25)
	_check("elves mostly like nature", elf_nature >= 25)
	# Label lists are non-empty strings
	var labels: Array = SimLikesDislikes.likes_label_list(_make_unit(7, "gnomes"))
	_check("label list non-empty", labels.size() >= 3 and String(labels[0]) != "")


func _test_reactions() -> void:
	var ogre := _find_with("ogres", "war", true)
	_check("found ogre who likes war", not ogre.is_empty())
	var r: Dictionary = SimLikesDislikes.react(ogre, "I love war and fighting!")
	_check("love war -> love", String(r.get("type", "")) == "love")
	r = SimLikesDislikes.react(ogre, "I hate war, it's awful")
	_check("hate war -> offended", String(r.get("type", "")) == "offended")
	# Ogre who dislikes peace
	var ogre2 := _find_with("ogres", "peace", false)
	_check("found ogre who dislikes peace", not ogre2.is_empty())
	r = SimLikesDislikes.react(ogre2, "I love peace and quiet")
	_check("love peace -> disgusted", String(r.get("type", "")) == "disgusted")
	r = SimLikesDislikes.react(ogre2, "I hate peace, it's boring")
	_check("hate peace -> bond", String(r.get("type", "")) == "bond")
	# Neutral mention still triggers mild reaction
	r = SimLikesDislikes.react(ogre2, "what do you think about peace?")
	_check("neutral peace mention -> mention_dislike",
		String(r.get("type", "")) == "mention_dislike")
	# Unrelated text -> no reaction
	r = SimLikesDislikes.react(ogre, "the sky is blue today")
	_check("unrelated -> no reaction", r.is_empty())
	# Topic strength present
	r = SimLikesDislikes.react(ogre, "war is great")
	_check("reaction has topic", String(r.get("topic", "")) == "war")


func _test_expressions() -> void:
	var u := _make_unit(1, "gnomes")
	for rtype in ["love", "bond", "offended", "disgusted", "mention_like", "mention_dislike"]:
		var line: String = SimLikesDislikes.express(u, {"type": rtype})
		_check("express " + rtype + " non-empty", line != "")
	# Pools have 10+ variants each
	_check("love pool 10+", SimLikesDislikes.LOVE_LINES.size() >= 10)
	_check("bond pool 10+", SimLikesDislikes.BOND_LINES.size() >= 10)
	_check("offended pool 10+", SimLikesDislikes.OFFENDED_LINES.size() >= 10)
	_check("disgusted pool 10+", SimLikesDislikes.DISGUSTED_LINES.size() >= 10)
	_check("mention_like pool 10+", SimLikesDislikes.MENTION_LIKE_LINES.size() >= 10)
	_check("mention_dislike pool 10+", SimLikesDislikes.MENTION_DISLIKE_LINES.size() >= 10)


func _test_effects() -> void:
	var gs := _make_gs()
	# Love: mood up, happy emotion, positive memory
	var u := _make_unit(11, "gnomes")
	var mem := _make_mem()
	SimLikesDislikes.apply_effects(u, {"type": "love", "topic": "jokes"}, mem, gs)
	_check("love bumps mood up", float(mem["mood"]) > 0.0)
	_check("love sets happy emotion",
		String((u.get("emotion", {}) as Dictionary).get("name", "")) == "happy")
	_check("love records memory", (u.get("memories", []) as Array).size() == 1)
	_check("love memory type",
		String((u["memories"] as Array)[0].get("type", "")) == "loved_topic")
	_check("love notes topic", (mem.get("loved_topics", []) as Array).has("jokes"))
	_check("love flags gossip", (u.get("last_ld_reaction", {}) as Dictionary).get("type") == "love")
	# Offended: mood down, angry emotion, negative memory
	var u2 := _make_unit(12, "ogres")
	var mem2 := _make_mem()
	SimLikesDislikes.apply_effects(u2, {"type": "offended", "topic": "war"}, mem2, gs)
	_check("offended drops mood", float(mem2["mood"]) < 0.0)
	_check("offended sets angry emotion",
		String((u2.get("emotion", {}) as Dictionary).get("name", "")) == "angry")
	_check("offended memory type",
		String((u2["memories"] as Array)[0].get("type", "")) == "hated_topic")
	# Grudge threshold: tank the mood repeatedly
	var u3 := _make_unit(13, "elves")
	var mem3 := _make_mem()
	for i in range(5):
		SimLikesDislikes.apply_effects(u3, {"type": "offended", "topic": "nature"}, mem3, gs)
	_check("grudge forms at low mood", bool(mem3.get("grudge_ruler", false)))
	# Fondness threshold
	var u4 := _make_unit(14, "humans")
	var mem4 := _make_mem()
	for i in range(6):
		SimLikesDislikes.apply_effects(u4, {"type": "love", "topic": "food"}, mem4, gs)
	_check("fondness forms at high mood", bool(mem4.get("fond_ruler", false)))


func _test_greeting_callback() -> void:
	var u := _make_unit(21, "gnomes")
	var mem := _make_mem()
	mem["loved_topics"] = ["jokes"]
	# With a mocked randf we can't force it; just verify it returns a String
	# and that empty topics -> empty callback.
	var cb: String = SimLikesDislikes.greeting_callback(u, mem)
	_check("callback returns string", cb is String)
	var mem2 := _make_mem()
	_check("no topics -> empty callback",
		SimLikesDislikes.greeting_callback(u, mem2) == "")
	mem2["grudge_ruler"] = true
	var g: String = SimLikesDislikes.greeting_callback(u, mem2)
	var gl := g.to_lower()
	_check("grudge greeting is cold",
		gl.contains("still") or gl.contains("whatever") or gl.contains("you again"))


func _test_engine_wiring() -> void:
	# Emotion engine has the new events
	_check("liked_topic event mapped",
		SimEmotion.EVENT_MAP.has("liked_topic"))
	_check("disliked_topic event mapped",
		SimEmotion.EVENT_MAP.has("disliked_topic"))
	# Memory system has the new types
	_check("loved_topic memory type", "loved_topic" in SimMemories.TYPES)
	_check("hated_topic memory type", "hated_topic" in SimMemories.TYPES)
	_check("loved_topic positive weight",
		float(SimMemories.REL_WEIGHT.get("loved_topic", 0.0)) > 0.0)
	_check("hated_topic negative weight",
		float(SimMemories.REL_WEIGHT.get("hated_topic", 0.0)) < 0.0)


func _test_conversation_hook() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	# Ogre who likes war hears "I love war" -> reply contains explicit expression
	var ogre := _find_with("ogres", "war", true)
	_check("ogre test subject found", not ogre.is_empty())
	var res: Dictionary = conv.reply(ogre, "I absolutely love war!", gs)
	var text: String = String(res.get("text", ""))
	# The expression should be in the reply (one of the LOVE_LINES).
	# Note: _apply_tone may add its own flavor prefix ~35% of the time,
	# so check containment, not begins_with.
	var has_expr := false
	for line in SimLikesDislikes.LOVE_LINES:
		if line in text:
			has_expr = true
			break
	_check("love expression prepended in reply", has_expr)
	# Mood moved on the conversation memory
	var mem: Dictionary = conv._get_memory(int(ogre["id"]))
	_check("conversation mood bumped", float(mem.get("mood", 0.0)) > 0.0)
	# Tone coloring runs without crashing (may or may not prefix)
	var res2: Dictionary = conv.reply(ogre, "hello there", gs)
	_check("plain reply still works", String(res2.get("text", "")) != "")
