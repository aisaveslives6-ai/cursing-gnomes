## Cursing Gnomes — chatx mood/affect engine tests.
## Covers the HTML fix79 chatx port: citizen episodic memory, grudge/
## favor, affection tiers, the 22-mood engine, mood events, line data,
## cheese mania, and the SimConversation integration.
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
	print("\n=== Cursing Gnomes chatx mood tests ===")
	_test_mood_lines_data()
	_test_citizen_memory()
	_test_citizen_relationship()
	_test_mood_engine()
	_test_mood_events()
	_test_mood_lines_pick()
	_test_conversation_integration()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _make_gs() -> Dictionary:
	return {
		"ruler_name": "TestRuler",
		"player_faction": "gnomes",
		"day_number": 10,
		"resources": {"get_amount": func(_f, _r): return 100.0},
	}


func _make_unit(faction: String = "gnome", uid: int = 1) -> Dictionary:
	return {
		"id": uid,
		"faction": faction,
		"display_name": "TestNPC",
		"name": "TestNPC",
		"hunger": 80,
		"energy": 80,
		"job": "worker",
		"workload": 20,
	}


## ---------------------------------------------------------------- data

func _test_mood_lines_data() -> void:
	_check("22 moods", ChatxMoodLines.LINES.size() == 22)
	for mood in ChatxMoodLines.LINES:
		var grp: Dictionary = ChatxMoodLines.LINES[mood]
		for f in ["gnome", "human", "elf", "ogre"]:
			_check("pool %s/%s >= 4 lines" % [mood, f],
				(grp.get(f, []) as Array).size() >= 4)
	_check("22 asides", ChatxMoodLines.ASIDES.size() == 22)
	for mood in ChatxMoodLines.ASIDES:
		_check("aside %s == 2" % mood,
			(ChatxMoodLines.ASIDES[mood] as Array).size() == 2)
	# Cheese injection (HTML cheeseManiaInject parity)
	var joyful_human: Array = ChatxMoodLines.LINES["joyful"]["human"]
	_check("human joyful has cheese lines", joyful_human.size() == 6)
	_check("gouda line injected",
		joyful_human.has("This is the happiest I've been since the great gouda of last spring!"))
	var gnome_joyful: Array = ChatxMoodLines.LINES["joyful"]["gnome"]
	_check("taco pride injected",
		gnome_joyful.has("Tacos beat everything. Gnome science proved it."))
	_check("24 cheese lines", ChatxMoodLines.CHEESE_LINES.size() == 24)
	_check("12 cheese screams", ChatxMoodLines.CHEESE_SCREAMS.size() == 12)
	# iPhone tofu rule: ASCII only
	var bad := 0
	for mood in ChatxMoodLines.LINES:
		for f in (ChatxMoodLines.LINES[mood] as Dictionary):
			for line in (ChatxMoodLines.LINES[mood][f] as Array):
				for ch in String(line):
					if ch.unicode_at(0) > 127:
						bad += 1
	_check("mood lines ASCII-only", bad == 0)


## ------------------------------------------------------- citizen memory

func _test_citizen_memory() -> void:
	var cit := SimChatxCitizen.new()
	# Record + dedup: same kind+text+day bumps rep, returns false
	_check("record ok",
		cit.record("u1", "insult", "you stink", -1, {"day": 5, "player": true}))
	_check("dedup false",
		not cit.record("u1", "insult", "you stink", -1, {"day": 5, "player": true}))
	var arr: Array = cit.records["u1"]
	_check("one record", arr.size() == 1)
	_check("rep bumped", int(arr[0]["rep"]) == 2)
	# Valence clamping
	cit.record("u1", "praise", "nice hat", 99, {"day": 5, "player": true})
	_check("valence clamped", int(cit.records["u1"][1]["v"]) == 1)
	# Text truncated to 140
	cit.record("u1", "chat", "x".repeat(200), 0, {"day": 5})
	_check("text truncated", String(cit.records["u1"][2]["t"]).length() == 140)
	# Grudge: intensity-weighted, recency-weighted
	var cit2 := SimChatxCitizen.new()
	cit2.record("u2", "harm", "stole my pie", -1,
		{"day": 8, "player": true, "intensity": 3})
	# weight = 3 * max(1, 4 - min(3, 2/10)) = 3*4 = 12
	_check("grudge fresh", cit2.grudge("u2", 10) == 12)
	# 25 days later: weight = 3 * max(1, 4 - min(3, 27/10)) = 3*2 = 6
	_check("grudge decayed", cit2.grudge("u2", 35) == 6)
	# Non-player harms don't count
	cit2.record("u2", "harm", "a wolf bit me", -1, {"day": 10})
	_check("grudge player-only", cit2.grudge("u2", 10) == 12)
	# Favor mirrors grudge
	cit2.record("u2", "gift", "gave me gold", 1,
		{"day": 10, "player": true, "intensity": 2})
	_check("favor", cit2.favor("u2", 10) == 8)
	# Unprompted: strongest OLD player memory (not today)
	cit2.record("u2", "chat", "nice weather", 1,
		{"day": 9, "player": true, "intensity": 1})
	var um := cit2.unprompted("u2", 10)
	_check("unprompted picks strongest old",
		String(um.get("t", "")) == "stole my pie")
	_check("unprompted_line",
		cit2.unprompted_line("u2", 10).begins_with("Remember when stole my pie?"))
	# Prune: neutral observations fall off before player memories
	var cit3 := SimChatxCitizen.new()
	for i in range(90):
		cit3.record("u3", "saw", "saw a bird %d" % i, 0, {"day": 1})
	cit3.record("u3", "insult", "you insulted me", -1,
		{"day": 1, "player": true, "intensity": 3})
	for i in range(20):
		cit3.record("u3", "saw", "saw a cloud %d" % i, 0, {"day": 2})
	_check("cap enforced", (cit3.records["u3"] as Array).size() == 96)
	var kept := false
	for m in cit3.records["u3"]:
		if String((m as Dictionary).get("t", "")) == "you insulted me":
			kept = true
	_check("player memory survives prune", kept)


func _test_citizen_relationship() -> void:
	var cit := SimChatxCitizen.new()
	# Affection clamp
	cit.aff_delta("u1", 200.0)
	_check("aff clamps high", cit.aff("u1") == 100.0)
	cit.aff_delta("u1", -500.0)
	_check("aff clamps low", cit.aff("u1") == -100.0)
	# Tiers (HTML buckets)
	_check("tier hostile", cit.aff_tier("u1", false, false) == "hostile")
	cit.aff_delta("u1", 70.0)  # -30
	_check("tier cold", cit.aff_tier("u1", false, false) == "cold")
	cit.aff_delta("u1", 40.0)  # 10
	_check("tier neutral", cit.aff_tier("u1", false, false) == "neutral")
	cit.aff_delta("u1", 40.0)  # 50
	_check("tier warm", cit.aff_tier("u1", false, false) == "warm")
	cit.aff_delta("u1", 40.0)  # 90
	_check("tier devoted", cit.aff_tier("u1", false, false) == "devoted")
	_check("blocked -> hostile", cit.aff_tier("u1", true, false) == "hostile")
	_check("at war -> hostile", cit.aff_tier("u1", false, true) == "hostile")
	# Witness moves affection and records
	var cit2 := SimChatxCitizen.new()
	cit2.witness("u2", "theft", "saw the player steal", -1, {"day": 3})
	_check("witness hurts", cit2.aff("u2") == -3.0)
	_check("witness recorded", (cit2.records["u2"] as Array).size() == 1)
	# Willingness gates (HTML formulas)
	_check("trade hostile", is_equal_approx(cit.trade_willing("hostile", "", 0), 0.15))
	_check("trade devoted", is_equal_approx(cit.trade_willing("devoted", "", 0), 1.0))
	_check("trade angry halves",
		is_equal_approx(cit.trade_willing("warm", "angry", 3), 0.85 * 0.5))
	_check("trade joyful lifts",
		is_equal_approx(cit.trade_willing("warm", "joyful", 3), minf(1.0, 0.85 * 1.2)))
	_check("info hostile", is_equal_approx(cit.info_willing("hostile", "", 0), 0.1))
	_check("greet hostile", is_equal_approx(cit.greet_odds("hostile", "", 0), 0.25))
	_check("greet joyful lifts",
		is_equal_approx(cit.greet_odds("neutral", "joyful", 3), minf(1.0, 0.8 * 1.25)))
	_check("bark angry", is_equal_approx(cit.bark_weight("angry", 3), 1.6))
	_check("bark sad", is_equal_approx(cit.bark_weight("sad", 3), 0.5))
	_check("bark calm", is_equal_approx(cit.bark_weight("angry", 1), 1.0))
	# Save/load
	var d := cit2.to_dict()
	var cit3 := SimChatxCitizen.new()
	cit3.from_dict(d)
	_check("affection round-trip", cit3.aff("u2") == -3.0)
	_check("records round-trip", (cit3.records["u2"] as Array).size() == 1)


## ------------------------------------------------------------ mood engine

func _test_mood_engine() -> void:
	_check("22 moods", SimChatxMood.MOODS.size() == 22)
	_check("gnome baseline amused",
		SimChatxMood.baseline("gnome")["m"] == "amused")
	_check("ogre baseline excited",
		SimChatxMood.baseline("ogre")["m"] == "excited")
	_check("race_of plural", SimChatxMood.race_of("ogres") == "ogre")
	_check("race_of elves", SimChatxMood.race_of("elves") == "elf")
	_check("undead baseline human",
		SimChatxMood.faction_of("undead") == "human")
	_check("unknown -> gnome", SimChatxMood.faction_of("klingon") == "gnome")

	var mood := SimChatxMood.new()
	# set/get round-trip
	_check("set ok", mood.set_mood("u1", "angry", 3, "test cause", 10))
	_check("set rejects bogus", not mood.set_mood("u1", "hyper", 3, "x", 10))
	var st := mood.get_mood("u1", 10, {"faction": "gnome"})
	_check("get angry", st["m"] == "angry" and int(st["i"]) == 3)
	# Day decay: explicit state loses 1/day
	st = mood.get_mood("u1", 12, {"faction": "gnome"})
	_check("decays", int(st["i"]) == 1)
	st = mood.get_mood("u1", 13, {"faction": "gnome"})
	_check("clears at zero", st["cause"] != "test cause")
	# compute: grudge >= 8 -> bitter (bw=3 -> i=2)
	var c := mood.compute({"grudge": 9, "favor": 0, "tier": "neutral",
		"hunger": 80, "energy": 80, "has_job": true, "workload": 10,
		"at_war": false, "festival": false, "faction": "gnome"})
	_check("grudge bitter", c["m"] == "bitter" and int(c["i"]) == 2)
	# hunger < 20 -> angry 2 ; energy < 20 -> exhausted 3
	c = mood.compute({"grudge": 0, "favor": 0, "tier": "neutral",
		"hunger": 10, "energy": 80, "has_job": true, "workload": 10,
		"at_war": false, "festival": false, "faction": "gnome"})
	_check("hungry angry", c["m"] == "angry")
	c = mood.compute({"grudge": 0, "favor": 0, "tier": "neutral",
		"hunger": 80, "energy": 5, "has_job": true, "workload": 10,
		"at_war": false, "festival": false, "faction": "gnome"})
	_check("tired exhausted", c["m"] == "exhausted" and int(c["i"]) == 2)
	# no job -> bored (human: no temperament bonus to tie-break)
	c = mood.compute({"grudge": 0, "favor": 0, "tier": "neutral",
		"hunger": 80, "energy": 80, "has_job": false,
		"at_war": false, "festival": false, "faction": "human"})
	_check("jobless bored", c["m"] == "bored")
	# at war -> anxious ; festival -> excited
	c = mood.compute({"grudge": 0, "favor": 0, "tier": "neutral",
		"hunger": 80, "energy": 80, "has_job": true, "workload": 10,
		"at_war": true, "festival": false, "faction": "human"})
	_check("war anxious", c["m"] == "anxious")
	c = mood.compute({"grudge": 0, "favor": 0, "tier": "neutral",
		"hunger": 80, "energy": 80, "has_job": true, "workload": 10,
		"at_war": false, "festival": true, "faction": "human"})
	_check("festival excited", c["m"] == "excited")
	# faction temperament: ogre runs hot
	c = mood.compute({"grudge": 0, "favor": 0, "tier": "neutral",
		"hunger": 80, "energy": 80, "has_job": true, "workload": 10,
		"at_war": false, "festival": false, "faction": "ogre"})
	_check("ogre temperament", c["m"] == "excited")
	# unprompted death -> grieving 5
	c = mood.compute({"grudge": 0, "favor": 0, "tier": "neutral",
		"unprompted_kind": "death", "unprompted_v": -1, "unprompted_it": 3,
		"hunger": 80, "energy": 80, "has_job": true, "workload": 10,
		"at_war": false, "festival": false, "faction": "human"})
	_check("death grieving", c["m"] == "grieving" and int(c["i"]) == 3)
	# devoted tier -> joyful
	c = mood.compute({"grudge": 0, "favor": 0, "tier": "devoted",
		"hunger": 80, "energy": 80, "has_job": true, "workload": 10,
		"at_war": false, "festival": false, "faction": "human"})
	_check("devoted joyful", c["m"] == "joyful")
	# nothing scores -> {} (caller falls back to baseline). Humans have
	# no temperament bonus, so a bare human life computes empty.
	c = mood.compute({"grudge": 0, "favor": 0, "tier": "neutral",
		"hunger": 80, "energy": 80, "has_job": true, "workload": 10,
		"at_war": false, "festival": false, "faction": "human"})
	_check("empty compute", c.is_empty())
	st = mood.get_mood("fresh", 10, {"faction": "human"})
	_check("baseline fallback", st["m"] == "content" and st["cause"] == "baseline")
	# pack/unpack
	mood.set_mood("u9", "lovesick", 4, "test", 10)
	var packed := mood.pack()
	var mood2 := SimChatxMood.new()
	mood2.unpack(packed)
	var st2 := mood2.get_mood("u9", 10, {"faction": "gnome"})
	_check("pack round-trip", st2["m"] == "lovesick" and int(st2["i"]) == 4)


func _test_mood_events() -> void:
	var mood := SimChatxMood.new()
	var expect := {
		"praise": "proud", "thanks": "grateful", "apology": "content",
		"forgiveness": "grateful", "joke_request": "amused", "dare": "excited",
		"acknowledgment": "content", "crude_direct": "angry",
	}
	for intent in expect:
		mood.apply_event("u1", intent, "neutral", false, 10)
		_check("event %s -> %s" % [intent, expect[intent]],
			String(mood.states["u1"]["m"]) == String(expect[intent]))
	# insult: neutral -> angry, hostile/cold/hot -> vengeful
	mood.apply_event("u1", "insult", "neutral", false, 10)
	_check("insult neutral angry", String(mood.states["u1"]["m"]) == "angry")
	mood.apply_event("u1", "insult", "hostile", false, 10)
	_check("insult hostile vengeful", String(mood.states["u1"]["m"]) == "vengeful")
	mood.apply_event("u1", "insult", "neutral", true, 10)
	_check("insult hot vengeful", String(mood.states["u1"]["m"]) == "vengeful")
	# threat: hot -> angry, else afraid
	mood.apply_event("u1", "threat", "neutral", true, 10)
	_check("threat hot angry", String(mood.states["u1"]["m"]) == "angry")
	mood.apply_event("u1", "threat", "neutral", false, 10)
	_check("threat cold afraid", String(mood.states["u1"]["m"]) == "afraid")
	# romance: devoted -> lovesick, hostile -> bitter, neutral -> amused
	mood.apply_event("u1", "romance_proposition", "devoted", false, 10)
	_check("romance devoted", String(mood.states["u1"]["m"]) == "lovesick")
	mood.apply_event("u1", "romance_proposition", "hostile", false, 10)
	_check("romance hostile", String(mood.states["u1"]["m"]) == "bitter")
	mood.apply_event("u1", "romance_proposition", "neutral", false, 10)
	_check("romance neutral", String(mood.states["u1"]["m"]) == "amused")
	# love declaration
	mood.apply_event("u1", "love_declaration", "cold", false, 10)
	_check("love cold angry", String(mood.states["u1"]["m"]) == "angry")
	mood.apply_event("u1", "love_declaration", "warm", false, 10)
	_check("love warm lovesick", String(mood.states["u1"]["m"]) == "lovesick")
	_check("love intensity 4", int(mood.states["u1"]["i"]) == 4)


func _test_mood_lines_pick() -> void:
	var mood := SimChatxMood.new()
	# Faction-voiced picks
	var line := mood.pick_line("angry", "ogre", "u1")
	var pool: Array = ChatxMoodLines.LINES["angry"]["ogre"]
	_check("ogre angry line in pool", pool.has(line))
	line = mood.pick_line("joyful", "elf", "u1")
	_check("elf joyful line in pool",
		(ChatxMoodLines.LINES["joyful"]["elf"] as Array).has(line))
	# Undead falls back to human pool
	line = mood.pick_line("sad", "undead", "u1")
	_check("undead human fallback",
		(ChatxMoodLines.LINES["sad"]["human"] as Array).has(line))
	_check("bogus mood empty", mood.pick_line("hyper", "gnome", "u1") == "")
	# Anti-repeat: recent window tracks picks
	for i in range(6):
		mood.pick_line("angry", "gnome", "u2")
	_check("recent tracked",
		(mood.recent.get("u2|moodline:angry:chat", []) as Array).size() == 6)
	# Flavor: weak mood never appends
	var base := "Hello there."
	_check("flavor weak unchanged", mood.flavor(base, "angry", 2, "u3") == base)
	# Flavor: strong mood appends an aside sometimes (22%)
	var appended := 0
	for i in range(100):
		var f := mood.flavor(base, "angry", 5, "u4")
		if f != base:
			appended += 1
			_check("aside from pool",
				(ChatxMoodLines.ASIDES["angry"] as Array).has(
					f.trim_prefix(base).strip_edges()))
			break
	_check("flavor strong appends", appended > 0)


## ------------------------------------------------------- integration

func _test_conversation_integration() -> void:
	var conv := SimConversation.new()
	var gs := _make_gs()
	var unit := _make_unit("gnome", 21)

	# Insult drives the affect state + affection + memory
	var r := conv.reply(unit, "you are stupid and ugly", gs)
	_check("insult intent", String(r["intent"]) == "insult")
	var ckey := SimChatxCitizen.key_for(21)
	_check("insult sets angry",
		String(conv.chatx_mood.states[ckey]["m"]) == "angry")
	_check("insult intensity 3", int(conv.chatx_mood.states[ckey]["i"]) == 3)
	_check("affection drops", conv.chatx_cit.aff(ckey) < 0.0)
	_check("memory recorded",
		(conv.chatx_cit.records[ckey] as Array).size() >= 1)

	# Praise flips it
	conv.reply(unit, "you are wise and amazing", gs)
	_check("praise sets proud",
		String(conv.chatx_mood.states[ckey]["m"]) == "proud")
	_check("affection recovers", conv.chatx_cit.aff(ckey) > -4.0)

	# Three insults heat the NPC: threats anger instead of scaring
	var unit2 := _make_unit("human", 22)
	var ckey2 := SimChatxCitizen.key_for(22)
	for i in range(3):
		conv.reply(unit2, "you are stupid", gs)
	conv.reply(unit2, "i will kill you", gs)
	_check("hot threat angers",
		String(conv.chatx_mood.states[ckey2]["m"]) == "angry")

	# Mood-colored greeting: strong angry mood redirects the pool
	var unit3 := _make_unit("gnome", 23)
	var ckey3 := SimChatxCitizen.key_for(23)
	conv.chatx_mood.set_mood(ckey3, "angry", 4, "test", 10)
	var g := conv.reply(unit3, "hello there", gs)
	_check("greeting intent kept", String(g["intent"]) == "greeting")
	var gtext := String(g["text"])
	var gpool: Array = ConversationResponses.get_pool("greeting_mood_angry", "gnome")
	var hit := false
	for line in gpool:
		if gtext.contains(String(line).split(" -- ")[0].left(20)):
			hit = true
	_check("mood greeting used", hit)

	# Strong persistent mood voices a faction line in the reply
	var unit4 := _make_unit("ogre", 24)
	var ckey4 := SimChatxCitizen.key_for(24)
	conv.chatx_mood.set_mood(ckey4, "joyful", 5, "test", 10)
	var j := conv.reply(unit4, "tell me about your town", gs)
	var jtext := String(j["text"])
	var jpool: Array = ChatxMoodLines.LINES["joyful"]["ogre"]
	var jhit := false
	for line in jpool:
		if jtext.contains(String(line)):
			jhit = true
	_check("mood line voiced", jhit)
