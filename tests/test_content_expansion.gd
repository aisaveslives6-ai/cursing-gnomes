## Cursing Gnomes — Content expansion tests (2026-10-04 wake pass, Workstream A).
## Verifies 129 fresh content lines across the conversation pools and
## enforces Jeremy's charm rules:
##   - roast lines carry {ruler} as a runtime placeholder and pass the
##     ruler name through VERBATIM (never baked, never trimmed)
##   - no "whims"/"whimsical" anywhere in new content (the system is "urges")
##   - all new lines are ASCII-only (iPhone renders emoji as tofu)
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
	print("\n=== Cursing Gnomes content expansion tests ===")
	_test_dialogue_pools()
	_test_dialogue_contexts()
	_test_mood_pools()
	_test_response_pools()
	_test_flow_pools()
	_test_roast_placeholder()
	_test_charm_rules()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _test_dialogue_pools() -> void:
	_check("roast pool grew to 30", SimDialogue.ROAST_RULER.size() == 30)
	_check("roast pool minimum", SimDialogue.ROAST_RULER.size() >= 27)
	_check("disaster pool has 12", SimDialogue.DISASTER_REACT.size() == 12)
	_check("squabble pool has 16", SimDialogue.SQUABBLE_POST.size() == 16)
	_check("wicked pool has 14", SimDialogue.WICKED_WHISPER.size() == 14)


func _test_dialogue_contexts() -> void:
	var gs := GameState.new()
	gs.ruler_name = "ass"
	var unit := {"id": 7, "display_name": "TestNPC", "mind": {},
		"emotion": {"name": "neutral"}, "job": "worker"}
	for ctx in ["roast_ruler", "squabble_post", "disaster", "wicked"]:
		var line: String = SimDialogue.line_for(gs, unit, ctx)
		_check("context '%s' returns a line" % ctx, not line.is_empty())
		_check("context '%s' has no raw tokens" % ctx,
			not ("{ruler}" in line or "{name}" in line))


func _test_mood_pools() -> void:
	_check("happy pool 117", SimMoodReplies.pool_size("happy") == 117)
	_check("angry pool 108", SimMoodReplies.pool_size("angry") == 108)
	_check("sad pool 105", SimMoodReplies.pool_size("sad") == 105)
	_check("scared pool 109", SimMoodReplies.pool_size("scared") == 109)
	_check("proud pool still 105", SimMoodReplies.pool_size("proud") == 105)
	_check("disgusted pool still 101", SimMoodReplies.pool_size("disgusted") == 101)
	_check("neutral pool still 102", SimMoodReplies.pool_size("neutral") == 102)


func _test_response_pools() -> void:
	for fac in ["gnome", "human", "elf", "ogre"]:
		_check("insult pool %s grew to 9" % fac,
			ConversationResponses.get_pool("insult", fac).size() == 9)
		_check("war_threaten pool %s grew to 8" % fac,
			ConversationResponses.get_pool("war_threaten", fac).size() == 8)


func _test_flow_pools() -> void:
	for fac in ["gnome", "human", "elf", "ogre", "undead"]:
		_check("engaged questions %s grew to 7" % fac,
			(SimConversationFlow.ENGAGED_QUESTIONS[fac] as Array).size() == 7)
		_check("deep questions %s grew to 6" % fac,
			(SimConversationFlow.DEEP_QUESTIONS[fac] as Array).size() == 6)
		_check("closing lines %s grew to 3" % fac,
			(SimConversationFlow.CLOSING_LINES[fac] as Array).size() == 3)
	_check("default bridges grew to 8",
		(SimConversationFlow.BRIDGES["default"] as Array).size() == 8)


## Jeremy's naming law: every roast line carries {ruler} and the name
## passes through verbatim — "ass" and an unrelated name alike.
func _test_roast_placeholder() -> void:
	var gs := GameState.new()
	var unit := {"id": 3, "display_name": "TestNPC", "mind": {},
		"emotion": {"name": "neutral"}, "job": "worker"}
	for i in range(SimDialogue.ROAST_RULER.size()):
		var raw: String = SimDialogue.ROAST_RULER[i]
		_check("roast %d has {ruler} placeholder" % i, "{ruler}" in raw)
		var as_ass: String = raw.replace("{ruler}", "ass")
		_check("roast %d passes 'ass' through" % i, "ass" in as_ass)
		_check("roast %d leaves no raw token (ass)" % i, not ("{ruler}" in as_ass))
		var as_fake: String = raw.replace("{ruler}", "JeremyBaker42")
		_check("roast %d passes 'JeremyBaker42' through" % i,
			"JeremyBaker42" in as_fake)
		_check("roast %d leaves no raw token (fake)" % i,
			not ("{ruler}" in as_fake))
	# End-to-end through line_for with the real ruler name.
	gs.ruler_name = "ass"
	var line: String = SimDialogue.line_for(gs, unit, "roast_ruler")
	_check("line_for roast contains 'ass'", "ass" in line)
	_check("line_for roast has no raw token", not ("{ruler}" in line))
	gs.ruler_name = "JeremyBaker42"
	var line2: String = SimDialogue.line_for(gs, unit, "roast_ruler")
	_check("line_for roast contains 'JeremyBaker42'", "JeremyBaker42" in line2)


## Collect exactly the new lines (tails of grown pools + whole new pools).
func _new_lines() -> Array:
	var out: Array = []
	out.append_array(SimDialogue.ROAST_RULER.slice(12))
	out.append_array(SimDialogue.DISASTER_REACT)
	out.append_array(SimDialogue.SQUABBLE_POST)
	out.append_array(SimDialogue.WICKED_WHISPER)
	out.append_array((SimMoodReplies.REPLIES["happy"] as Array).slice(111))
	out.append_array((SimMoodReplies.REPLIES["angry"] as Array).slice(102))
	out.append_array((SimMoodReplies.REPLIES["sad"] as Array).slice(101))
	out.append_array((SimMoodReplies.REPLIES["scared"] as Array).slice(105))
	for fac in ["gnome", "human", "elf", "ogre"]:
		out.append_array(
			(ConversationResponses.get_pool("insult", fac) as Array).slice(6))
		out.append_array(
			(ConversationResponses.get_pool("war_threaten", fac) as Array).slice(6))
	for fac in ["gnome", "human", "elf", "ogre", "undead"]:
		out.append_array(
			(SimConversationFlow.ENGAGED_QUESTIONS[fac] as Array).slice(5))
		out.append_array(
			(SimConversationFlow.DEEP_QUESTIONS[fac] as Array).slice(4))
		out.append_array(
			(SimConversationFlow.CLOSING_LINES[fac] as Array).slice(2))
	out.append_array((SimConversationFlow.BRIDGES["default"] as Array).slice(4))
	return out


func _test_charm_rules() -> void:
	var lines := _new_lines()
	_check("129 new lines total", lines.size() == 129)
	_check("at least 100 new lines", lines.size() >= 100)
	var seen := {}
	for i in range(lines.size()):
		var line := String(lines[i])
		_check("new line %d non-empty" % i, not line.strip_edges().is_empty())
		_check("new line %d no whims" % i,
			not ("whims" in line.to_lower()))
		var ascii_ok := true
		for ci in range(line.length()):
			if line.unicode_at(ci) > 127:
				ascii_ok = false
				break
		_check("new line %d ascii-only" % i, ascii_ok)
		_check("new line %d unique" % i, not seen.has(line))
		seen[line] = true
