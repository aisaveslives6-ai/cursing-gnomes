## Cursing Gnomes — NPC mood system tests (Jeremy 2026-10-04).
## Tests persistent moods (SimMood), the 100-replies-per-mood pools
## (SimMoodReplies), mood-colored hearsay, and Messenger wiring.
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
	print("\n=== Cursing Gnomes mood tests ===")
	_test_mood_basics()
	_test_mood_nudge()
	_test_mood_decay()
	_test_mood_feeds_from_emotion()
	_test_mood_traits_drift()
	_test_mood_tone()
	_test_reply_pools()
	_test_reply_pick()
	_test_hearsay_mood_openers()
	_test_conversation_wiring()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _make_unit(uid: int = 1) -> Dictionary:
	return {"id": uid, "faction": "gnome", "display_name": "TestNPC"}


## --- SimMood basics ---------------------------------------------------------

func _test_mood_basics() -> void:
	var sm := SimMood.new()
	var u := _make_unit()
	_check("new unit is neutral", sm.dominant(u) == "neutral")
	_check("new unit intensity 0", sm.intensity(u) == 0.0)
	_check("mood dict stored on unit", u.has("mood"))
	_check("MOODS has 7 entries", SimMood.MOODS.size() == 7)
	_check("MOODS includes neutral", SimMood.MOODS.has("neutral"))
	# ensure() is idempotent — doesn't clobber an existing mood.
	sm.nudge(u, "happy", 0.5)
	var before: float = sm.intensity(u)
	sm.ensure(u)
	_check("ensure keeps existing mood", sm.dominant(u) == "happy"
		and is_equal_approx(sm.intensity(u), before))


func _test_mood_nudge() -> void:
	var sm := SimMood.new()
	var u := _make_unit()
	# Unknown moods and "neutral" are ignored.
	sm.nudge(u, "ecstatic", 0.9)
	_check("unknown mood ignored", sm.dominant(u) == "neutral")
	sm.nudge(u, "neutral", 0.9)
	_check("neutral nudge ignored", sm.dominant(u) == "neutral")
	# Same mood strengthens.
	sm.nudge(u, "angry", 0.4)
	_check("nudge sets mood", sm.dominant(u) == "angry")
	_check("nudge sets intensity", is_equal_approx(sm.intensity(u), 0.4))
	sm.nudge(u, "angry", 0.3)
	_check("same mood strengthens", is_equal_approx(sm.intensity(u), 0.7))
	# Clamp at 1.0.
	sm.nudge(u, "angry", 0.9)
	_check("intensity clamps at 1", sm.intensity(u) <= 1.0)
	# A stronger different mood displaces a weak one.
	var u2 := _make_unit(2)
	sm.nudge(u2, "sad", 0.3)
	sm.nudge(u2, "happy", 0.8)
	_check("stronger mood displaces weaker", sm.dominant(u2) == "happy")
	# A weaker different mood just takes the edge off.
	var u3 := _make_unit(3)
	sm.nudge(u3, "angry", 0.8)
	sm.nudge(u3, "sad", 0.2)
	_check("weaker mood keeps current", sm.dominant(u3) == "angry")
	_check("weaker mood softens intensity",
		sm.intensity(u3) < 0.8 and sm.intensity(u3) > 0.0)


func _test_mood_decay() -> void:
	var sm := SimMood.new()
	var u := _make_unit()
	sm.nudge(u, "proud", 1.0)
	# Small tick barely dents it (moods last hours/days, not seconds).
	sm.tick(u, 1.0)
	_check("mood survives 1s tick", sm.dominant(u) == "proud")
	_check("mood decays slowly", sm.intensity(u) < 1.0)
	# A huge tick burns it out to neutral.
	sm.tick(u, 100000.0)
	_check("mood decays to neutral", sm.dominant(u) == "neutral")
	_check("intensity resets", sm.intensity(u) == 0.0)
	_check("tick returns mood name", sm.tick(u, 1.0) == "neutral")


func _test_mood_feeds_from_emotion() -> void:
	var sm := SimMood.new()
	var emo := SimEmotion.new()
	var u := _make_unit()
	# Strong anger hardens into an angry mood.
	emo.notify(u, "insulted", 1.5)  # intensity clamps to 1.0
	sm.feed_from_emotion(u)
	_check("strong anger feeds angry mood", sm.dominant(u) == "angry")
	_check("fed mood has some intensity", sm.intensity(u) > 0.0)
	# Weak emotions don't move the needle.
	var u2 := _make_unit(2)
	emo.notify(u2, "ate_well")  # intensity 0.35 < FEED_THRESHOLD
	sm.feed_from_emotion(u2)
	_check("weak emotion ignored", sm.dominant(u2) == "neutral")
	# Neutral emotion does nothing.
	var u3 := _make_unit(3)
	u3["emotion"] = {"name": "neutral", "intensity": 0.0, "ttl": 0.0}
	sm.feed_from_emotion(u3)
	_check("neutral emotion ignored", sm.dominant(u3) == "neutral")
	# Repeated grief becomes a sad mood (the friend-died case).
	var u4 := _make_unit(4)
	emo.notify(u4, "friend_died")  # sad 0.7
	sm.feed_from_emotion(u4)
	_check("grief feeds sad mood", sm.dominant(u4) == "sad")


func _test_mood_traits_drift() -> void:
	var sm := SimMood.new()
	# A held mood blocks the personality drift.
	var u := _make_unit(7)
	u["mind"] = {"traits": SimPersonality.traits_for(7, "gnome")}
	sm.nudge(u, "angry", 0.9)
	sm.drift_from_traits(u)
	_check("strong mood blocks drift", sm.dominant(u) == "angry")
	# With no mood, a very friendly NPC drifts happy.
	var u2 := _make_unit(8)
	u2["mind"] = {"traits": {
		"brave": 0.5, "friendly": 1.0, "diligent": 0.5,
		"crude": 0.5, "proud": 0.1, "criminal": 0.1, "violent": 0.0,
		"name": "Drifty",
	}}
	sm.drift_from_traits(u2)
	_check("friendly NPC drifts happy", sm.dominant(u2) == "happy")
	# A very violent NPC drifts angry.
	var u3 := _make_unit(9)
	u3["mind"] = {"traits": {
		"brave": 0.5, "friendly": 0.0, "diligent": 0.5,
		"crude": 0.5, "proud": 0.1, "criminal": 0.1, "violent": 1.0,
		"name": "Grumpy",
	}}
	sm.drift_from_traits(u3)
	_check("violent NPC drifts angry", sm.dominant(u3) == "angry")


func _test_mood_tone() -> void:
	var sm := SimMood.new()
	var u := _make_unit()
	_check("neutral mood tone flat", sm.tone(u) == "flat")
	sm.nudge(u, "happy", 0.6)
	_check("happy mood tone cheerful", sm.tone(u) == "cheerful")
	var u2 := _make_unit(2)
	sm.nudge(u2, "proud", 0.6)
	_check("proud mood tone cheerful", sm.tone(u2) == "cheerful")
	var u3 := _make_unit(3)
	sm.nudge(u3, "angry", 0.6)
	_check("angry mood tone grumpy", sm.tone(u3) == "grumpy")
	var u4 := _make_unit(4)
	sm.nudge(u4, "disgusted", 0.6)
	_check("disgusted mood tone grumpy", sm.tone(u4) == "grumpy")
	var u5 := _make_unit(5)
	sm.nudge(u5, "scared", 0.6)
	_check("scared mood tone fearful", sm.tone(u5) == "fearful")
	var u6 := _make_unit(6)
	sm.nudge(u6, "sad", 0.6)
	_check("sad mood tone fearful", sm.tone(u6) == "fearful")


## --- SimMoodReplies ---------------------------------------------------------

func _test_reply_pools() -> void:
	var moods: Array = SimMoodReplies.moods()
	_check("7 mood pools", moods.size() == 7)
	for mood: String in SimMood.MOODS:
		var size: int = SimMoodReplies.pool_size(mood)
		_check("pool %s >= 100 replies" % mood, size >= 100)
	# All replies in a pool are unique.
	for mood: String in moods:
		var pool: Array = SimMoodReplies.REPLIES.get(mood, [])
		var seen := {}
		var dupes := 0
		for line: String in pool:
			if seen.has(line):
				dupes += 1
			seen[line] = true
		_check("pool %s all unique" % mood, dupes == 0)
	# No reply is empty, none contain emoji glyphs (iPhone tofu rule).
	var emoji_found := false
	for mood: String in moods:
		for line: String in SimMoodReplies.REPLIES.get(mood, []):
			if line.strip_edges() == "":
				emoji_found = true
			for c: String in line:
				if c.unicode_at(0) > 0x2500:
					emoji_found = true
	_check("replies non-empty, no glyph junk", not emoji_found)


func _test_reply_pick() -> void:
	for mood: String in SimMood.MOODS:
		var line := SimMoodReplies.pick(mood)
		_check("pick %s non-empty" % mood, line != "")
		_check("pick %s from its pool" % mood,
			SimMoodReplies.REPLIES[mood].has(line))
	# Unknown mood falls back to the neutral pool.
	var fallback := SimMoodReplies.pick("ecstatic")
	_check("unknown mood falls back to neutral",
		SimMoodReplies.REPLIES["neutral"].has(fallback))


## --- Hearsay mood wiring ----------------------------------------------------

func _test_hearsay_mood_openers() -> void:
	var openers: Dictionary = SimHearsay.MOOD_GOSSIP_OPENERS
	for mood: String in SimMood.MOODS:
		_check("hearsay opener pool for %s" % mood, openers.has(mood))
		var pool: Array = openers[mood]
		_check("opener pool %s non-empty" % mood, not pool.is_empty())
		var has_token := false
		for o: String in pool:
			if "{t}" in o:
				has_token = true
		_check("openers for %s have {t} token" % mood, has_token)
	# Mood-colored content checks.
	var angry: Array = openers["angry"]
	var angry_text := " ".join(angry).to_upper()
	_check("angry openers sound furious", "FURIOUS" in angry_text)
	var happy: Array = openers["happy"]
	_check("happy openers sound upbeat",
		"LOVE" in " ".join(happy).to_upper() or "!" in " ".join(happy))


## --- Conversation wiring ----------------------------------------------------

func _test_conversation_wiring() -> void:
	var conv := SimConversation.new()
	var mem := {"mood": 0.0}
	# Neutral mood: line unchanged.
	var u := _make_unit()
	var out := conv._apply_mood_line("Hello.", u, mem, true)
	_check("neutral mood adds nothing", out == "Hello.")
	# Angry mood, forced: a reply gets appended.
	var u2 := _make_unit(2)
	SimMood.new().nudge(u2, "angry", 0.8)
	var out2 := conv._apply_mood_line("Hello.", u2, mem, true)
	_check("angry mood appends a line", out2 != "Hello."
		and out2.begins_with("Hello. "))
	_check("appended line from angry pool",
		SimMoodReplies.REPLIES["angry"].has(out2.trim_prefix("Hello. ")))
	# Sad mood, forced.
	var u3 := _make_unit(3)
	SimMood.new().nudge(u3, "sad", 0.8)
	var out3 := conv._apply_mood_line("Hi.", u3, mem, true)
	_check("sad mood appends a line",
		SimMoodReplies.REPLIES["sad"].has(out3.trim_prefix("Hi. ")))
	# Tokens in mood lines resolve through _substitute (mood line runs
	# before substitution in reply()).
	var u4 := _make_unit(4)
	u4["display_name"] = "Bort"
	SimMood.new().nudge(u4, "happy", 0.8)
	var found_token_line := false
	for line: String in SimMoodReplies.REPLIES["happy"]:
		if "{name}" in line:
			found_token_line = true
			break
	_check("happy pool has {name} token lines", found_token_line)
