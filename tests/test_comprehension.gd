## Cursing Gnomes — NPC comprehension regression tests (Jeremy 2026-10-06).
##
## Covers the "he's not understanding much" bug cluster from the iPhone
## screenshots:
##   1. Empty name slots ("I'm !" / "it's friend") — HTML _subst token parity.
##   2. "what are you doing?" misparsed as who_are_you (tie-break).
##   3. Pronoun garbling in the fact-echo path ("show you" vs "show me").
##   4. Single words ("ass") hitting the didn't-understand fallback.
##   5. Leader greeting self-addressing ("Ah, Warlord Grak! Come in!").
## Plus: the 24 corrupted response pools restored from fix79, and the
## Common Tongue word-reaction brain (CANDIDATE23) now ported.
extends SceneTree


const CT := preload("res://scripts/sim/common_tongue.gd")


var _passed := 0
var _failed := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", name)


func _letters(s: String) -> int:
	var n := 0
	for ch in s:
		var c := String(ch)
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z"):
			n += 1
	return n


func _init() -> void:
	print("\n=== Cursing Gnomes comprehension tests ===")
	_test_tie_break()
	_test_substitute()
	_test_greeting_no_self_address()
	_test_pools_restored()
	_test_common_tongue()
	_test_identity_guard()
	_test_pronouns()
	_test_name_set()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _make_gs() -> Dictionary:
	return {
		"ruler_name": "ass",
		"player_faction": "gnomes",
		"day_number": 3,
		"resources": {"gold": 250.0},
	}


func _make_unit() -> Dictionary:
	# Real unit shape: the name lives in mind.name, NOT top-level.
	return {
		"id": 7,
		"faction": "gnome",
		"mind": {"name": "Snag"},
		"job": "worker",
		"work_state": "gathering",
		"gather_kind": "wood",
		"town": "Snagville",
	}


func _make_leader() -> Dictionary:
	return {
		"id": -42,
		"faction": "ogre",
		"name": "Warlord Grak",
		"display_name": "Warlord Grak",
		"job": "ruler",
		"mind": {"name": "Warlord Grak", "gov_role": "leader"},
	}


## Bug 2: "what are you doing?" must not parse as who_are_you.
func _test_tie_break() -> void:
	var conv := SimConversation.new()
	_check("doing -> what_are_you_doing",
		conv.parse_intent("what are you doing?")["intent"] == "what_are_you_doing")
	_check("whatcha doing -> what_are_you_doing",
		conv.parse_intent("whatcha doing")["intent"] == "what_are_you_doing")
	_check("what are you? still who_are_you",
		conv.parse_intent("what are you?")["intent"] == "who_are_you")
	_check("who are you -> who_are_you",
		conv.parse_intent("who are you")["intent"] == "who_are_you")
	# End-to-end: the reply answers with the real sim activity.
	var rep: Dictionary = conv.reply(_make_unit(), "what are you doing?",
		_make_gs())
	_check("doing reply intent", rep["intent"] == "what_are_you_doing")
	_check("doing reply names the activity",
		String(rep["text"]).contains("chopping wood"))
	_check("doing reply has no raw tokens",
		not String(rep["text"]).contains("{"))


## Bug 1: HTML _subst token parity — {name} is the PLAYER, {rname} the NPC.
func _test_substitute() -> void:
	var conv := SimConversation.new()
	var unit := _make_unit()
	var gs := _make_gs()
	var s: String = conv._substitute(
		"Oh great, it's {name}. I'm {rname}, {rulerTitle} of the {ppl}.",
		unit, gs)
	_check("{name} is the ruler", s.contains("it's ass."))
	_check("{rname} is the NPC", s.contains("I'm Snag,"))
	_check("{rulerTitle} is the job", s.contains("worker of the"))
	_check("{ppl} people word", s.contains("the gnomes."))
	var s2: String = conv._substitute("Right now? {doing}, {name}.", unit,
		gs)
	_check("{doing} grounded in sim", s2 == "Right now? chopping wood, ass.")
	var s3: String = conv._substitute("I'm {rulerName}! Ruler of the {ppl}.",
		unit, gs)
	_check("no empty slots", s3 == "I'm Snag! Ruler of the gnomes.")
	_check("no raw tokens leak", not s3.contains("{"))


## Bug 5: the leader must address the PLAYER, not itself.
func _test_greeting_no_self_address() -> void:
	var conv := SimConversation.new()
	var line: String = conv._substitute("Ah, {name}! Come in! Mind the traps.",
		_make_leader(), _make_gs())
	_check("greeting addresses player",
		line == "Ah, ass! Come in! Mind the traps.")
	_check("greeting never self-addresses", not line.contains("Grak"))


## The 24 corrupted pools + 3 flat pools + c28d_nevermet are real lines again.
func _test_pools_restored() -> void:
	var pools := ["sleep", "tribute_demand", "advice_moral", "calendar_info",
		"compliment_npc", "economy_how", "explain_how", "help_offer",
		"opinion_prefer", "remember_ask", "tax_how", "war_how",
		"followup_more_generic", "romance_proposition_devoted", "negate",
		"c25_clarify_again", "c25_clarify_talking", "c25_understand",
		"person_unknown", "what_are_you_doing", "c29_lie", "c29_wrongname",
		"threat_hostile", "c28d_nevermet"]
	var short_ok := ["No.", "NO!", "no."]
	for pid in pools:
		var ok := true
		var n := 0
		for fac in ["gnome", "human", "elf", "ogre"]:
			var arr: Array = ConversationResponses.get_pool(pid, fac)
			n += arr.size()
			for line in arr:
				if _letters(String(line)) < 3 and not String(line) in short_ok:
					ok = false
		_check("pool %s has real lines (%d)" % [pid, n], ok and n > 0)
	for pid in ["c29_iyo_cold_1", "c29_iyo_hurt_3", "c29_iyo_standard_2"]:
		var arr: Array = ConversationResponses.get_pool(pid, "gnome")
		var ok := arr.size() >= 2
		for line in arr:
			if _letters(String(line)) < 3:
				ok = false
		_check("flat pool %s restored" % pid, ok)
	# Spot check: the doing pool actually answers with {doing}.
	var dpool: Array = ConversationResponses.get_pool("what_are_you_doing",
		"gnome")
	var has_doing := false
	for line in dpool:
		if String(line).contains("{doing}"):
			has_doing = true
	_check("doing pool uses {doing}", has_doing)


## Bug 4: Common Tongue — single everyday words get real reactions.
func _test_common_tongue() -> void:
	_check("ct match ass", CT.match("ass").get("cat") == "crude")
	_check("ct match multiword",
		CT.match("no cap").get("cat") == "slang_modern")
	_check("ct no match", CT.match("xylophone").is_empty())
	var used := {}
	var r1: Dictionary = CT.react("ass", "gnome", used)
	_check("ct react text", String(r1.get("text", "")).contains("ass"))
	_check("ct react no-repeat ledger", not used.is_empty())
	# End-to-end: "ass" never hits the didn't-understand fallback.
	var conv := SimConversation.new()
	var rep: Dictionary = conv.reply(_make_unit(), "ass", _make_gs())
	_check("ass not unclear", rep["intent"] != "unclear")
	_check("ass not lex_ask", rep["intent"] != "lex_ask")
	_check("ass reply is a real reaction",
		not String(rep["text"]).contains("didn't understand"))
	_check("ass reply has no raw tokens", not String(rep["text"]).contains("{"))


## Bug 3: "i'm going to X" is a plan, not an identity — no "Noted — you're
## going to show you."
func _test_identity_guard() -> void:
	var Flow := preload("res://scripts/sim/conversation_flow.gd")
	var mem := {}
	var ack: String = Flow.learn("im gonna show you my cock", mem)
	_check("verb phrase not learned as identity",
		not ack.contains("you're going to show you"))
	_check("verb phrase learns nothing", ack == "")
	var mem2 := {}
	var ack2: String = Flow.learn("i'm a blacksmith", mem2)
	_check("real identity still learned", ack2.contains("blacksmith"))


## Pronoun flip when echoing the player's self-description.
func _test_pronouns() -> void:
	var Flow := preload("res://scripts/sim/conversation_flow.gd")
	_check("your -> my", Flow._swap_pronouns("your friend") == "my friend")
	_check("you -> me", Flow._swap_pronouns("see you soon") == "see me soon")
	_check("no false flip", Flow._swap_pronouns("a blacksmith") == "a blacksmith")
	var mem := {}
	var ack: String = Flow.learn("i'm your best friend", mem)
	_check("identity echo flips pronouns", ack.contains("you're my best friend"))


## name_set renders the NEW name (HTML parity), no raw {name} leaks.
func _test_name_set() -> void:
	var conv := SimConversation.new()
	var rep: Dictionary = conv.reply(_make_unit(), "my name is Bob",
		_make_gs())
	_check("name_set intent", rep["intent"] == "name_set")
	_check("new name rendered", String(rep["text"]).contains("Bob"))
	_check("no raw name token", not String(rep["text"]).contains("{name}"))
