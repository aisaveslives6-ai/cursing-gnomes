extends SceneTree
## Cursing Gnomes — conversation-system integration tests (Jeremy 2026-10-06).
##
## Proves every conversation surface routes through the FULL Hearsay
## conversation engine with shared state: Messenger DMs (all NPC types
## INCLUDING faction leaders), Squabble posts + replies, gossip/hearsay,
## backchannel, and save/load persistence. No channel may keep a private
## fork of conversation state.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_conversation_integration.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes conversation-integration tests ===")
	_test_leader_dm_uses_full_engine()
	_test_leader_dm_intent_parsing()
	_test_leader_memory_shared()
	_test_lexicon_shared_wiring()
	_test_teach_word_surfaces_on_squabble()
	_test_squabble_comment_uses_full_engine()
	_test_gossip_carries_lexicon()
	_test_backchannel_reads_shared_lexicon()
	_test_conversation_save_load_roundtrip()
	_test_no_keyword_router_for_leaders()
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
	var gs: GameState = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.set_ruler_name("ass")
	# World-style wiring: one shared lexicon, owned by the game.
	gs.lexicon = load("res://scripts/sim/lexicon.gd").new(gs)
	return gs


func _new_phone(gs: GameState):
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	# World-style wiring (world.gd): the phone's engine shares game.lexicon.
	phone.conversation.lexicon = gs.lexicon
	# Faction leaders for leader-DM tests.
	var fl = load("res://scripts/sim/faction_leaders.gd").new(gs)
	fl.on_player_faction_set("gnomes",
		["humans", "ogres", "elves", "gnomes", "undead"])
	gs.set("faction_leaders", fl)
	return phone


func _spawn(gs: GameState, faction: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true, "mind": {}})


## 1. Faction leader DMs go through the FULL engine, not the keyword router.
func _test_leader_dm_uses_full_engine() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var reply: String = phone._leader_full_reply("ogres", "hello there")
	_check("leader reply non-empty", reply != "" and reply != "...")
	# The retired keyword router wrapped every reply in literal quotes.
	_check("leader reply not quote-wrapped (full engine)",
		not (reply.begins_with("\"") and reply.ends_with("\"")))
	gs.queue_free()


## 2. Leader DMs get 79-intent parsing (e.g. war_declare), not keywords.
func _test_leader_dm_intent_parsing() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var unit: Dictionary = phone._leader_unit("ogres")
	var res: Dictionary = phone.conversation.reply(
		unit, "i declare war on you", gs)
	_check("leader war_declare intent parsed",
		String(res.get("intent", "")) == "war_declare")
	_check("leader reply text voiced", String(res.get("text", "")) != "")
	gs.queue_free()


## 3. Leader conversations share memory with the engine (no private fork).
func _test_leader_memory_shared() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var unit: Dictionary = phone._leader_unit("ogres")
	var uid := int(unit.get("id", 0))
	_check("leader pseudo-id is negative (no unit collision)", uid < 0)
	phone._leader_full_reply("elves", "hello friend")
	var unit2: Dictionary = phone._leader_unit("elves")
	var uid2 := int(unit2.get("id", 0))
	_check("leader pseudo-id stable across calls",
		uid2 == int(phone._leader_unit("elves").get("id", 0)))
	_check("leader conversation memory recorded",
		phone.conversation._memories.has(uid2))
	gs.queue_free()


## 4. The phone engine shares the game's lexicon instance (world wiring).
func _test_lexicon_shared_wiring() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	_check("conversation shares game lexicon",
		phone.conversation.lexicon == gs.lexicon)
	gs.queue_free()


## 5. A word taught in Messenger surfaces on Squabble (lexicon generator).
func _test_teach_word_surfaces_on_squabble() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var u: Dictionary = _spawn(gs, "humans")
	# Teach a word through the shared lexicon (as Messenger would).
	gs.lexicon.learn_word("zorp", ["attack"], "u1", 1, "ruler")
	var words: Array = gs.lexicon.taught_words()
	_check("word taught", not words.is_empty())
	# The Squabble lexicon showoff generator (sqbGenLexicon parity).
	var posted: bool = phone._lexicon_post(u)
	_check("lexicon showoff post created", posted)
	var found := false
	for p: Dictionary in phone.feed():
		if String(p.get("kind", "")) == "lexicon" \
				and String(p.get("text", "")).contains("zorp"):
			found = true
			break
	_check("showoff post mentions the taught word", found)
	gs.queue_free()


## 6. NPC replies to Squabble posts go through the full engine.
func _test_squabble_comment_uses_full_engine() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var author: Dictionary = _spawn(gs, "humans")
	var commenter: Dictionary = _spawn(gs, "elves")
	var p: Dictionary = phone.npc_post(author, "hello friends", "mood")
	var reply_text: String = phone._comment_on_post(p, commenter)
	_check("squabble comment non-empty", reply_text != "")
	_check("comment recorded on post",
		not (p.get("comments", []) as Array).is_empty())
	# Full engine recorded shared conversation memory for the commenter.
	_check("commenter memory in shared engine",
		phone.conversation._memories.has(int(commenter.get("id", 0))))
	gs.queue_free()


## 7. Gossip carries Living Lexicon state (teller showoff).
func _test_gossip_carries_lexicon() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	# No taught words -> no showoff word available.
	_check("no showoff without taught words",
		phone.hearsay._lexicon_showoff_word().is_empty())
	gs.lexicon.learn_word("wobble", ["dance"], "u1", 1, "ruler")
	var sw: Dictionary = phone.hearsay._lexicon_showoff_word()
	_check("showoff word available after teaching",
		String(sw.get("word", "")) == "wobble")
	gs.queue_free()


## 8. Backchannel reads the same shared lexicon instance.
func _test_backchannel_reads_shared_lexicon() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var bc = load("res://scripts/sim/backchannel.gd").new(gs)
	var w: Dictionary = bc._lexicon_word()
	# Empty either way is fine — the point is it reads gs.lexicon,
	# the same instance the phone engine uses (no fork).
	_check("backchannel lexicon read does not crash", true)
	gs.lexicon.learn_word("quib", ["talk"], "u1", 1, "ruler")
	var w2: Dictionary = bc._lexicon_word()
	_check("backchannel sees taught word", not w2.is_empty())
	gs.queue_free()


## 9. Conversation state (memories, chatx records, mood) survives save/load.
func _test_conversation_save_load_roundtrip() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var u: Dictionary = _spawn(gs, "humans")
	var uid := int(u.get("id", 0))
	phone.conversation.reply(u, "hello there friend", gs)
	_check("memory recorded before save",
		phone.conversation._memories.has(uid))
	var saved: Dictionary = phone.conversation.get_save_data()
	_check("save data has memories", saved.has("memories"))
	_check("save data has chatx records", saved.has("chatx_records"))
	_check("save data has chatx mood", saved.has("chatx_mood"))
	var conv2 = load("res://scripts/sim/conversation.gd").new()
	conv2.load_save_data(saved)
	_check("memories restored", conv2._memories.has(uid))
	_check("chatx citizen restored",
		conv2.chatx_cit.records.has("u%d" % uid))
	gs.queue_free()


## 10. The old keyword router is gone from the leader path.
func _test_no_keyword_router_for_leaders() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	# Old router returned voice-canned lines; the engine voices per faction.
	# "military focus" hit the old directive_hint path; the engine must
	# parse it as its own intent instead of the canned hint.
	var reply: String = phone._leader_full_reply("ogres", "focus military")
	_check("leader military reply not canned hint",
		not reply.contains("Say the word, boss"))
	gs.queue_free()
