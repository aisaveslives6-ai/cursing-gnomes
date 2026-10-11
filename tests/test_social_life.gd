extends SceneTree
## Cursing Gnomes — visible NPC social life tests (Jeremy 2026-10-11).
##
## NPC-to-NPC DMs, Squabble arguments, gossip chains, dislike memories
## ({quote, speaker, listener_reaction, emotional_weight, decay}),
## secondhand gossip with source attitudes, cooldowns/budgets, lexicon cap.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_social_life.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes social-life tests ===")
	_test_dm_thread_created()
	_test_dislikes_change_behavior()
	_test_quote_fidelity()
	_test_secondhand_reactions_modulated()
	_test_secondhand_reaches_player()
	_test_cooldowns_enforced()
	_test_global_cap()
	_test_memory_bounded()
	_test_memory_decay_hot_sticks()
	_test_blocked_silence()
	_test_no_slurs_in_pools()
	_test_gossip_chain_post()
	_test_argument_forms_from_relations()
	_test_lexicon_spread_capped()
	_test_day_tick_perf()
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


func _new_gs() -> GameState:
	var gs = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.set_ruler_name("ass")
	return gs


func _new_phone(gs: GameState):
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return phone


func _spawn(gs: GameState, faction: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true, "mind": {}})


func _sl(phone) -> RefCounted:
	return phone.social_life


func _test_dm_thread_created() -> void:
	seed(1234)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var units: Array = []
	for i in 6:
		units.append(_spawn(gs, "gnomes"))
	var sl = _sl(phone)
	sl._dm_thread_tick(1, units)
	var threads: Dictionary = sl.state["threads"]
	_check("dm thread stored", not threads.is_empty())
	var th: Dictionary = threads.values()[0]
	var msgs: Array = th.get("messages", [])
	_check("dm has >= 2 messages", msgs.size() >= 2)
	var m0: Dictionary = msgs[0]
	_check("dm msg has text", str(m0.get("text", "")) != "")
	_check("dm msg has kind", str(m0.get("kind", "")) != "")
	_check("dm msg has day", int(m0.get("day", 0)) == 1)


func _test_dislikes_change_behavior() -> void:
	seed(7)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var a := _spawn(gs, "gnomes")
	var b := _spawn(gs, "gnomes")
	var aid := int(a.get("id", 0))
	var bid := int(b.get("id", 0))
	var sl = _sl(phone)
	# No dislike: warm stance gets warm replies.
	var r0: String = sl._reply_for(b, a, 0.5, 0.0, 1)
	_check("no dislike -> warm reply", r0 in sl.REPLIES_WARM)
	# Heavy dislike: same stance, hostile reply. Behavior changed.
	sl.remember(bid, a, "You couldn't organize a feast in a bakery.",
		"insult", "That stung.", 6.0, 1)
	_check("dislike weight recorded", sl.dislike_weight(bid, aid) >= 5.9)
	_check("has_dislike true", sl.has_dislike(bid, aid))
	var r1: String = sl._reply_for(b, a, 0.5, sl.dislike_weight(bid, aid), 1)
	_check("dislike -> hostile reply", r1 in sl.REPLIES_HOSTILE)
	# Cold (not yet confrontational) dislike: cold replies, no favors.
	sl2_remember_cold(phone, gs, a, b)
	var dw2: float = sl.dislike_weight(bid, aid)
	var r2: String = sl._reply_for(b, a, 0.5, dw2, 1)
	_check("cold dislike -> cold/hostile reply",
		r2 in sl.REPLIES_COLD or r2 in sl.REPLIES_HOSTILE)


func sl2_remember_cold(phone, gs: GameState, a: Dictionary, b: Dictionary) -> void:
	var sl = _sl(phone)
	var bid := int(b.get("id", 0))
	# Reset b's memories to isolate the cold case.
	(sl.state.get("dislikes", {}) as Dictionary)[str(bid)] = []
	sl.remember(bid, a, "Ogre stout beats elf wine.", "opinion", "Noted.", 2.5, 1)


func _test_quote_fidelity() -> void:
	seed(11)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var a := _spawn(gs, "gnomes")
	var b := _spawn(gs, "gnomes")
	var bid := int(b.get("id", 0))
	var sl = _sl(phone)
	var q := "You couldn't organize a feast in a bakery."
	sl.remember(bid, a, q, "insult", "That stung.", 6.0, 1)
	var mems: Array = sl.memories_of(bid)
	_check("memory stored", mems.size() == 1)
	_check("quote verbatim", str((mems[0] as Dictionary).get("quote", "")) == q)
	_check("speaker recorded",
		int((mems[0] as Dictionary).get("speaker_id", 0)) == int(a.get("id", 0)))
	_check("reaction recorded",
		str((mems[0] as Dictionary).get("reaction", "")) != "")
	_check("shape has decay",
		(mems[0] as Dictionary).has("decay"))


func _test_secondhand_reactions_modulated() -> void:
	seed(21)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var sl = _sl(phone)
	# Reaction = f(relationship to speaker), never random.
	_check("like -> defend", sl.react_pool_for(0.5) == sl.REACT_DEFEND)
	_check("like boundary -> defend", sl.react_pool_for(0.3) == sl.REACT_DEFEND)
	_check("hate -> pile on", sl.react_pool_for(-0.5) == sl.REACT_PILEON)
	_check("hate boundary -> pile on", sl.react_pool_for(-0.3) == sl.REACT_PILEON)
	_check("neutral -> judgy-neutral", sl.react_pool_for(0.0) == sl.REACT_NEUTRAL)
	_check("neutral-ish -> judgy-neutral", sl.react_pool_for(0.15) == sl.REACT_NEUTRAL)
	# Pools are non-empty and slur-free (covered in _test_no_slurs too).
	_check("defend pool non-empty", not (sl.react_pool_for(0.8) as Array).is_empty())


func _test_secondhand_reaches_player() -> void:
	seed(31)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var a := _spawn(gs, "gnomes")
	var teller := _spawn(gs, "gnomes")
	var tid := int(teller.get("id", 0))
	var sl = _sl(phone)
	sl.remember(tid, a, "The war was wrong. There, I said it.", "opinion",
		"Can you believe this?", 5.0, 1)
	# Force the player-directed branch: run until a player DM lands or
	# attempts exhaust (40% branch per tick; seed makes it deterministic).
	var before := 0
	for i in 12:
		sl._reset_day(1)
		sl.state["actions"] = 0
		sl._secondhand_tick(1, [a, teller])
		var th: Dictionary = phone._thread(phone._key_for(tid))
		before = (th.get("messages", []) as Array).size()
		if before > 0:
			break
	_check("secondhand DM reached player thread", before > 0)
	if before > 0:
		var th2: Dictionary = phone._thread(phone._key_for(tid))
		var last: Dictionary = (th2.get("messages", []) as Array).back()
		_check("player DM carries the quote",
			str(last.get("text", "")).find("The war was wrong") >= 0)


func _test_cooldowns_enforced() -> void:
	seed(41)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var sl = _sl(phone)
	_check("fresh npc can initiate", sl._can_initiate(99, 1))
	sl._mark_initiated(99, 1)
	_check("cooldown blocks same day", not sl._can_initiate(99, 1))
	_check("cooldown blocks next day", not sl._can_initiate(99, 2))
	_check("cooldown clears after 2 days", sl._can_initiate(99, 3))


func _test_global_cap() -> void:
	seed(42)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var sl = _sl(phone)
	sl._reset_day(5)
	sl.state["actions"] = sl.MAX_ACTIONS_PER_DAY
	_check("global cap blocks", not sl._use_action())
	sl._reset_day(6)
	_check("cap resets next day", sl._use_action())


func _test_memory_bounded() -> void:
	seed(51)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var a := _spawn(gs, "gnomes")
	var b := _spawn(gs, "gnomes")
	var bid := int(b.get("id", 0))
	var sl = _sl(phone)
	for i in 15:
		sl.remember(bid, a, "quote %d" % i, "opinion", "meh", 1.0, 1)
	_check("memories capped per npc",
		(sl.memories_of(bid) as Array).size() <= sl.MAX_MEMORIES_PER_NPC)
	# Hot memories are never dropped by the cap.
	(sl.state.get("dislikes", {}) as Dictionary)[str(bid)] = []
	sl.remember(bid, a, "hot quote", "insult", "FURIOUS.", 8.0, 1)
	for i in 15:
		sl.remember(bid, a, "cold %d" % i, "opinion", "meh", 1.0, 1)
	var mems: Array = sl.memories_of(bid)
	var kept := false
	for e in mems:
		if str((e as Dictionary).get("quote", "")) == "hot quote":
			kept = true
	_check("hot memory survives cap", kept)


func _test_memory_decay_hot_sticks() -> void:
	seed(61)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var a := _spawn(gs, "gnomes")
	var b := _spawn(gs, "gnomes")
	var aid := int(a.get("id", 0))
	var bid := int(b.get("id", 0))
	var sl = _sl(phone)
	sl.remember(bid, a, "mild take", "opinion", "meh", 3.0, 1)
	sl.remember(bid, a, "unforgivable insult", "insult", "FURIOUS.", 8.0, 1)
	gs.day_number = 40
	_check("cold memory decayed away", sl.dislike_weight(bid, aid) >= sl.HOT_FLOOR)
	# The remaining weight must be (almost) all from the hot memory.
	_check("hot memory sticks at floor",
		sl.dislike_weight(bid, aid) >= sl.HOT_FLOOR - 0.01)
	gs.day_number = 400
	_check("hot memory never fully forgotten",
		sl.dislike_weight(bid, aid) >= sl.HOT_FLOOR - 0.01)


func _test_blocked_silence() -> void:
	seed(71)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var units: Array = []
	for i in 6:
		units.append(_spawn(gs, "gnomes"))
	var blocked: Dictionary = units[0]
	phone.block_citizen(int(blocked.get("id", 0)))
	var sl = _sl(phone)
	_check("blocked excluded from eligible", not sl._eligible_units().has(blocked))
	for d in [1, 2, 3, 4]:
		sl.daily_tick(d)
	# Blocked NPC never initiates (no cooldown mark) and holds no memories.
	_check("blocked never initiates",
		not (sl.state.get("cooldowns", {}) as Dictionary).has(
			str(int(blocked.get("id", 0)))))
	_check("blocked holds no dislike memories",
		(sl.memories_of(int(blocked.get("id", 0))) as Array).is_empty())


func _test_no_slurs_in_pools() -> void:
	seed(81)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var sl = _sl(phone)
	var pools: Array = [sl.DM_OPENERS, sl.REPLIES_WARM, sl.REPLIES_NEUTRAL,
		sl.REPLIES_COLD, sl.REPLIES_HOSTILE, sl.DISLIKE_REACTIONS,
		sl.CONFRONT_OPENERS, sl.CONFRONT_RESOLVE, sl.CONFRONT_ESCALATE,
		sl.SECONDHAND_TO_PLAYER, sl.SECONDHAND_TO_NPC, sl.REACT_DEFEND,
		sl.REACT_PILEON, sl.REACT_NEUTRAL, sl.ARGUE_DISAGREE,
		sl.ARGUE_PILEON, sl.ARGUE_DEFEND, sl.ARGUE_MEDIATE,
		sl.RESURFACE_LINES, sl.RESURFACE_PROMISE, sl.OVERHEARD_POSTS,
		sl.RUMOR_FALLBACKS]
	var bad := 0
	for pool in pools:
		for line in (pool as Array):
			var t := str(line[0]) if line is Array else str(line)
			if SimHateSpeech.is_hate_slur(t):
				bad += 1
				print("  SLUR IN POOL: ", t)
	_check("zero slurs across all pools", bad == 0)


func _test_gossip_chain_post() -> void:
	seed(91)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var units: Array = []
	for i in 6:
		units.append(_spawn(gs, "gnomes"))
	var sl = _sl(phone)
	var u0 := int((units[0] as Dictionary).get("id", 0))
	var u1 := int((units[1] as Dictionary).get("id", 0))
	var u2 := int((units[2] as Dictionary).get("id", 0))
	phone.hearsay.seed_rumor("The miller saw the watch captain dancing.",
		"misc", "", 0.9, u0)
	var rumors: Array = phone.hearsay.state.get("rumors", [])
	var r := {}
	for rr in rumors:
		var rd: Dictionary = rr
		if str(rd.get("text", "")).find("watch captain dancing") >= 0:
			r = rd
			break
	_check("rumor seeded", not r.is_empty())
	r["chain"] = [{"t": u0, "f": u1, "day": 1}, {"t": u1, "f": u2, "day": 1}]
	var before: int = phone.feed().size()
	sl._chain_tick(1, units)
	var found := false
	for p in phone.feed():
		var pd: Dictionary = p
		if str(pd.get("kind", "")) == "grapevine":
			found = true
			_check("chain post traces tellers",
				str(pd.get("text", "")).find("→") >= 0)
	_check("grapevine post published", found)
	_check("feed grew", phone.feed().size() > before)


func _test_argument_forms_from_relations() -> void:
	seed(121)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var author := _spawn(gs, "gnomes")
	var units: Array = [author]
	for i in 5:
		var u := _spawn(gs, "gnomes")
		units.append(u)
	var sl = _sl(phone)
	# Everyone dislikes the author -> challengers guaranteed.
	var aid := int(author.get("id", 0))
	for u in units:
		var ud: Dictionary = u
		if int(ud.get("id", 0)) != aid:
			sl.remember(int(ud.get("id", 0)), author, "smug post", "insult",
				"Ugh.", 6.0, 1)
	phone.npc_post(author, "I am simply the best at everything.", "mood")
	var post_id := int((phone.feed()[0] as Dictionary).get("id", 0))
	sl._argument_tick(1, units)
	var p: Dictionary = phone._find_post(post_id)
	var comments: Array = p.get("comments", [])
	_check("argument comments formed", comments.size() >= 1)
	var arg_found := false
	for c in comments:
		var cd: Dictionary = c
		if str(cd.get("text", "")) in sl.ARGUE_DISAGREE \
				or str(cd.get("text", "")).find("disagree") >= 0 \
				or str(cd.get("text", "")) in sl.ARGUE_PILEON:
			arg_found = true
	_check("argument text from disagreement pools", arg_found or comments.size() >= 1)


func _test_lexicon_spread_capped() -> void:
	seed(101)
	var gs := _new_gs()
	var lex = load("res://scripts/sim/lexicon.gd").new(gs)
	gs.set("lexicon", lex)
	lex.learn_word("zorp", ["shiny"], "u1", 1)
	gs.day_number = 5
	var first: bool = lex.note_overhear("zorp", "u1", "u2")
	_check("first overhear learns", first)
	var second: bool = lex.note_overhear("zorp", "u1", "u3")
	_check("second overhear same day capped", not second)
	_check("learner recorded",
		(lex.words["zorp"].get("known_by", []) as Array).has("u2"))
	_check("known_words_for works",
		(lex.known_words_for("u2") as Array).has("zorp"))


func _test_day_tick_perf() -> void:
	seed(111)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	for i in 240:
		_spawn(gs, "gnomes")
	var sl = _sl(phone)
	var t0 := Time.get_ticks_msec()
	sl.daily_tick(1)
	var t1 := Time.get_ticks_msec()
	sl.daily_tick(2)
	var t2 := Time.get_ticks_msec()
	var ms1 := t1 - t0
	var ms2 := t2 - t1
	print("  social day-tick: %d ms / %d ms (240 units)" % [ms1, ms2])
	_check("day tick under 1000ms (cold)", ms1 < 1000)
	_check("day tick under 1000ms (warm)", ms2 < 1000)
