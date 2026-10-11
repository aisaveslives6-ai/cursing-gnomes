extends SceneTree
## Cursing Gnomes — MR SMART BITCH phone tutor tests (Jeremy 2026-10-11).
##
## Proves: the contact registers in my_contacts (name/sub/pfp like the
## ASSFACE block); key routing maps UID -> thread key and resolves the
## pseudo-unit (pfp "smartbitch"); send_leader_message intercepts the
## "smartbitch" tag and message routing returns a non-empty reply through
## the typing queue; 10+ spot-check questions get answers referencing REAL
## systems (verified terms: "urges" not "whims", "16" cap, "surveyed",
## "Treasury", "28", "Ethos Games", ...); the topics menu branches into
## numbered follow-ups; NPC "what does X like" answers match REAL
## SimLikesDislikes.for_unit output; "do A and B get along" uses real
## npc_stance; ZERO IRL hate slurs across every dialogue line
## (SimHateSpeech.is_hate_slur); persona markers present; save/load
## round-trips the draw state.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_smart_bitch.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Mr Smart Bitch tests ===")
	_test_key_routing()
	_test_contact_registered()
	_test_routing_returns_reply()
	_test_topic_answers()
	_test_menu_branching()
	_test_npc_likes_real_data()
	_test_npc_stance_real_data()
	_test_npc_profile()
	_test_honest_unknown()
	_test_no_hate_slurs()
	_test_persona_markers()
	_test_save_load()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	gs.ruler_name = "ass"
	var phone := SimPhone.new(gs)
	return {"gs": gs, "phone": phone}


func _make_unit(uid: int, uname: String, faction: String) -> Dictionary:
	return {
		"id": uid,
		"faction": faction,
		"name": uname,
		"display_name": uname,
		"town": "",
		"job": "worker",
		"alive": true,
		"gender": "m",
		"mind": {"name": uname, "traits": {"persona": "pragmatic"}},
	}


## 1. Key routing mirrors the assface pattern.
func _test_key_routing() -> void:
	var w := _new_world()
	var phone = w["phone"]
	_check("key_for(uid) maps to thread key",
		phone._key_for(SimSmartBitch.UID) == SimSmartBitch.KEY)
	var u: Dictionary = phone._unit_for_key(SimSmartBitch.KEY)
	_check("unit_for_key resolves pseudo-unit", not u.is_empty())
	_check("pseudo-unit pfp resolves via _leader_pfp",
		String(u.get("_leader_pfp", "")) == "smartbitch")
	_check("thread header name",
		phone.leader_name_for_key(SimSmartBitch.KEY) == "Mr Smart Bitch")
	_check("is_blocked_key starts false",
		not phone.is_blocked_key(SimSmartBitch.KEY))
	_check("constants sane", SimSmartBitch.KEY == "leader_smartbitch"
		and SimSmartBitch.FACTION_TAG == "smartbitch"
		and SimSmartBitch.UID == -696969)


## 2. Contact registered in my_contacts with the spec'd dict.
func _test_contact_registered() -> void:
	var w := _new_world()
	var phone = w["phone"]
	(phone.state["added"] as Array).append(SimSmartBitch.KEY)
	var found := {}
	for c: Dictionary in phone.my_contacts():
		if String(c.get("key", "")) == SimSmartBitch.KEY:
			found = c
	_check("contact registered", not found.is_empty())
	_check("contact name", String(found.get("name", "")) == "Mr Smart Bitch")
	_check("contact sub",
		String(found.get("sub", "")) == "Knows everything. Judges you anyway.")
	_check("contact pfp", String(found.get("pfp", "")) == "smartbitch")
	_check("contact unit_id", int(found.get("unit_id", 0)) == SimSmartBitch.UID)


## 3. Message routing: send -> non-empty reply lands in the typing queue.
func _test_routing_returns_reply() -> void:
	var w := _new_world()
	var phone = w["phone"]
	phone.send_leader_message(SimSmartBitch.FACTION_TAG, "hello")
	_check("reply queued via leader routing", not phone._pending.is_empty())
	var reply_text := String((phone._pending.back() as Dictionary).get("reply_text", ""))
	_check("reply non-empty", reply_text != "")
	_check("reply has voice", "Smart Bitch" in reply_text or "ruler" in reply_text.to_lower() or "ass" in reply_text.to_lower())


## 4. Spot-checks: 10+ questions -> answers referencing REAL systems.
## Pools have multiple variants, so each case lists ACCEPTABLE real terms
## and we draw up to 3 times (without replacement) for a hit.
func _test_topic_answers() -> void:
	var w := _new_world()
	var sb := SimSmartBitch.new(w["gs"])
	var cases := [
		# [question, acceptable real terms]
		["how do i build things", ["water", "star fort", "drag"]],
		["tell me about oil", ["oil pump", "pumpjack", "industrial"]],
		["how do trade deals work", ["Treasury", "ledger"]],
		["what are urges", ["urges"]],
		["tell me about whims", ["URGE"]],  # correction fires
		["what is the unit cap", ["16", "240"]],
		["add a new disaster", ["28", "frozen"]],
		["can i buy gold with real money", ["bullshit", "microtransaction"]],
		["how do roads work", ["surveyed", "graded", "paved"]],
		["tell me about vehicles", ["motor pool", "dealership"]],
		["who are my advisors", ["Ruler's Voice", "Treasury"]],
		["what's new", ["Ethos Games"]],
		["tell me about the music", ["composing", "composed", "Jeremy"]],
		["who made this game", ["Ethos Games"]],
		["how does the phone work", ["Bastard OS", "back button"]],
		["what are festivals", ["refund", "cooldown"]],
		["give me strategy tips", ["lumber camps", "command post"]],
		["tell me about war counsel", ["Messenger", "Accept/Deny"]],
		["how does the tutorial work", ["First Reign", "skip"]],
		["how do i save", ["save", "grudges"]],
	]
	for c in cases:
		var q := String(c[0])
		var terms: Array = c[1]
		var hit := false
		var any_text := ""
		for _i in range(3):
			var ans: String = sb.reply(q, "ass")
			any_text = ans
			if ans == "":
				continue
			for t in terms:
				if String(t).to_lower() in ans.to_lower():
					hit = true
					break
			if hit:
				break
		_check("answer non-empty: '%s'" % q, any_text != "")
		_check("answer references real system for '%s'" % q, hit)
	# "urges not whims" hard rule on the NPC answer (variant 0 mentions
	# "whims" only to correct it — the term used is always "urges").
	var urges_hit := false
	for _i in range(3):
		var urges: String = sb.reply("tell me about npc urges", "ass")
		if "urges" in urges.to_lower():
			urges_hit = true
	_check("npc answer says urges", urges_hit)


## 5. Topics menu -> numbered follow-ups branch for real.
func _test_menu_branching() -> void:
	var w := _new_world()
	var sb := SimSmartBitch.new(w["gs"])
	var menu: String = sb.reply("help", "ass")
	_check("menu lists numbered topics", "1." in menu and "Military" in menu)
	var deep: String = sb.reply("5", "ass")
	_check("menu 5 -> military answer", "tap-to-command" in deep.to_lower())
	_check("military arms sub-menu", "war counsel" in deep.to_lower())
	var sub: String = sb.reply("1", "ass")
	_check("sub-menu 1 -> war counsel", "Messenger" in sub)


## 6. NPC likes come from REAL SimLikesDislikes data.
func _test_npc_likes_real_data() -> void:
	var w := _new_world()
	var gs = w["gs"]
	var u := _make_unit(101, "Testy McTestface", "gnomes")
	(gs.units as Array).append(u)
	var sb := SimSmartBitch.new(gs)
	var ans: String = sb.reply("what does Testy McTestface like", "ass")
	_check("likes answer non-empty", ans != "")
	var tastes: Dictionary = SimLikesDislikes.for_unit(u)
	for t in tastes.get("likes", []):
		var label := SimLikesDislikes.topic_label(String(t))
		_check("answer cites real like '%s'" % label,
			label.to_lower() in ans.to_lower())
	for t in tastes.get("dislikes", []):
		var label := SimLikesDislikes.topic_label(String(t))
		_check("answer cites real dislike '%s'" % label,
			label.to_lower() in ans.to_lower())


## 7. "do A and B get along" uses real npc_stance.
func _test_npc_stance_real_data() -> void:
	var w := _new_world()
	var gs = w["gs"]
	(gs.units as Array).append(_make_unit(102, "Alice Test", "gnomes"))
	(gs.units as Array).append(_make_unit(103, "Bob Test", "gnomes"))
	var sb := SimSmartBitch.new(gs)
	var ans: String = sb.reply("do Alice Test and Bob Test get along", "ass")
	_check("stance answer non-empty", ans != "")
	var verdicts := ["thick as thieves", "get along fine", "neutral",
		"frosty", "want each other dead"]
	var hit := false
	for v in verdicts:
		if v in ans.to_lower():
			hit = true
	_check("stance answer worded from real stance", hit)


## 8. Profile pulls persona + tastes from real data.
func _test_npc_profile() -> void:
	var w := _new_world()
	var gs = w["gs"]
	(gs.units as Array).append(_make_unit(104, "Proudy Pants", "elves"))
	var sb := SimSmartBitch.new(gs)
	var ans: String = sb.reply("tell me about Proudy Pants", "ass")
	_check("profile non-empty", ans != "")
	_check("profile cites persona",
		SimPersonality.persona_of(_make_unit(104, "Proudy Pants", "elves")) in ans)
	# Unknown name -> honest, no invention (fallback pool, multi-draw).
	var honest := false
	for _i in range(3):
		var nope: String = sb.reply("tell me about Nobody Here", "ass")
		if "won't make" in nope or "don't track" in nope \
				or "hallucinate" in nope:
			honest = true
	_check("unknown npc honest", honest)


## 9. Honest unknowns, never invented mechanics.
func _test_honest_unknown() -> void:
	var w := _new_world()
	var sb := SimSmartBitch.new(w["gs"])
	var honest := false
	for _i in range(3):
		var ans: String = sb.reply("what is the airspeed velocity of a coconut", "ass")
		if "won't make it up" in ans or "don't track" in ans \
				or "refuse to hallucinate" in ans:
			honest = true
	_check("fallback honest", honest)


## 10. ZERO IRL hate slurs across every dialogue line (the game's hard line).
func _test_no_hate_slurs() -> void:
	var lines: Array = SimSmartBitch.all_lines()
	_check("line pool non-trivial", lines.size() >= 60)
	var bad := 0
	for line in lines:
		if SimHateSpeech.is_hate_slur(String(line)):
			bad += 1
			print("  SLUR HIT: ", String(line).substr(0, 80))
	_check("no hate slurs in any line", bad == 0)


## 11. Persona markers: self-aware, fourth-wall-breaking voice.
func _test_persona_markers() -> void:
	var blob := "\n".join(SimSmartBitch.all_lines()).to_lower()
	for m in SimSmartBitch.PERSONA_MARKERS:
		_check("persona marker '%s' present" % m,
			String(m).to_lower() in blob)


## 12. Save/load round-trips draw state.
func _test_save_load() -> void:
	var w := _new_world()
	var sb := SimSmartBitch.new(w["gs"])
	sb.reply("who are you", "ass")
	var d: Dictionary = sb.to_dict()
	var sb2 := SimSmartBitch.new(w["gs"])
	sb2.from_dict(d)
	_check("save/load keeps draw state",
		(sb2.to_dict().get("used", {}) as Dictionary).size() \
			== (d.get("used", {}) as Dictionary).size())
