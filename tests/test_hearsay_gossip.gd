extends SceneTree
## Cursing Gnomes — hearsay gossip-reaction tests (Jeremy 2026-10-08).
##
## Covers the hearsay flesh-out run: the gossip rumor reaction matrix.
## Yapper-grade tavern talk about a named citizen was the last dead-end
## rumor (no emotion, default-strength memory, nobody reacted). Now:
##  - the victim is mortified ("gossiped_about_me", mood down, mocked)
##  - rivals cackle ("mocked_gossip_victim", mood up, liked the topic)
##  - friends defend ("defended_gossip_victim", mood down, insulted)
##  - neutrals are mildly amused (generic heard_rumor, small mood bump)
##  - unhinged NPCs feel it 1.5x (matching the smear/war paths)
##  - unparsable subjects (old saves) fall back to the generic path
##  - the press never prints tavern gossip (PRESS_EXCLUDE_KINDS)
##  - spread zeal is relationship-driven: rivals push it, friends kill it
##  - the victim id rides the subject ("gossip:<unit_id>") — no
##    cross-file edits, parsed by _gossip_victim_id
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_gossip.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay gossip-reaction tests ===")
	_test_victim_mortified()
	_test_rival_cackles()
	_test_friend_defends()
	_test_neutral_amused()
	_test_unhinged_amplified()
	_test_unparsable_subject_generic_no_crash()
	_test_press_excludes_gossip()
	_test_spread_motivation_relationship()
	_test_victim_id_parse()
	_test_seed_path_wires_reaction()
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


func _harness() -> Array:
	var gs := _new_gs()
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return [gs, phone, phone.hearsay]


func _spawn(gs: GameState, faction: String, unhinged: bool = false) -> Dictionary:
	var mind: Dictionary = {}
	if unhinged:
		mind = {"traits": {"unhinged": 1.0}}
	return gs.add_unit({"faction": faction, "alive": true, "mind": mind})


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	# Memories live on the unit dict; a fresh SimMemories reads them.
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _gossip_rumor(hs, vid: int) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "gossip" \
				and String(r.get("subject", "")) == "gossip:%d" % vid:
			return r
	return {}


## Spawn units in faction_b until one has npc_stance vs a inside [lo, hi].
func _find_stance(gs: GameState, a: Dictionary, faction_b: String,
		lo: float, hi: float) -> Dictionary:
	var likes = load("res://scripts/sim/likes_dislikes.gd")
	for i in 200:
		var cand: Dictionary = _spawn(gs, faction_b)
		var s: float = likes.npc_stance(cand, a, gs)
		if s >= lo and s <= hi:
			return cand
	return {}


func _test_victim_mortified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	var r: Dictionary = hs.seed_rumor(
		"Yapper the gossip gnome swears Testy the ogre lost an argument with a chicken.",
		"gossip", "gossip:%d" % vid, 0.65, -1, false,
		hs.TRUTH_UNKNOWN)
	# The victim hears it at seed time (knower-less seed still routes the
	# first hear through _on_heard when a knower is attached below).
	hs._on_heard(victim, r, {})
	_check("victim remembers gossiped_about_me",
		_recalled(victim, "gossiped_about_me", vid) > 0.0)
	_check("victim mortified (mocked -> sad)",
		_emotion(victim) == "sad")
	_check("victim mood drops on own gossip",
		conv.ruler_mood(vid) < 0.0)


func _test_rival_cackles() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	gs.bus.war_declared.emit("elves", "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	var r: Dictionary = hs.seed_rumor("gossip text", "gossip",
		"gossip:%d" % vid, 0.65, -1, false, hs.TRUTH_UNKNOWN)
	var likes = load("res://scripts/sim/likes_dislikes.gd")
	_check("war rumor seeded as side effect", not hs.state["rumors"].is_empty())
	var rival: Dictionary = _find_stance(gs, victim, "elves", -1.0, -0.3)
	_check("rival found (stance <= -0.3)",
		not rival.is_empty() \
		and likes.npc_stance(rival, victim, gs) <= -0.3)
	if rival.is_empty():
		return
	var rid2 := int(rival.get("id", 0))
	hs._on_heard(rival, r, {})
	_check("rival remembers mocked_gossip_victim",
		_recalled(rival, "mocked_gossip_victim", vid) > 0.0)
	_check("rival amused (liked_topic -> happy)",
		_emotion(rival) == "happy")
	_check("rival mood rises on rival's gossip",
		conv.ruler_mood(rid2) > 0.0)


func _test_friend_defends() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	var r: Dictionary = hs.seed_rumor("gossip text", "gossip",
		"gossip:%d" % vid, 0.65, -1, false, hs.TRUTH_UNKNOWN)
	var friend: Dictionary = _find_stance(gs, victim, "ogres", 0.3, 1.0)
	_check("friend found (stance >= 0.3)", not friend.is_empty())
	if friend.is_empty():
		return
	var fid := int(friend.get("id", 0))
	hs._on_heard(friend, r, {})
	_check("friend remembers defended_gossip_victim",
		_recalled(friend, "defended_gossip_victim", vid) > 0.0)
	_check("friend offended on victim's behalf (insulted -> angry)",
		_emotion(friend) == "angry")
	_check("friend mood drops defending",
		conv.ruler_mood(fid) < 0.0)


func _test_neutral_amused() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	var r: Dictionary = hs.seed_rumor("gossip text", "gossip",
		"gossip:%d" % vid, 0.65, -1, false, hs.TRUTH_UNKNOWN)
	var neutral: Dictionary = _find_stance(gs, victim, "ogres", -0.29, 0.29)
	_check("neutral found", not neutral.is_empty())
	if neutral.is_empty():
		return
	var nid := int(neutral.get("id", 0))
	hs._on_heard(neutral, r, {})
	_check("neutral gets generic heard_rumor memory",
		_recalled(neutral, "heard_rumor", int(r.get("id", 0))) > 0.0)
	_check("neutral gets no gossiped_about_me memory",
		_recalled(neutral, "gossiped_about_me", vid) == 0.0)
	_check("neutral mood rises a little on tavern talk",
		conv.ruler_mood(nid) > 0.0)


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var calm: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres", true)
	var cvid := int(calm.get("id", 0))
	var wvid := int(wild.get("id", 0))
	var rc: Dictionary = hs.seed_rumor("gossip text", "gossip",
		"gossip:%d" % cvid, 0.65, -1, false, hs.TRUTH_UNKNOWN)
	var rw: Dictionary = hs.seed_rumor("gossip text 2", "gossip",
		"gossip:%d" % wvid, 0.65, -1, false, hs.TRUTH_UNKNOWN)
	hs._on_heard(calm, rc, {})
	hs._on_heard(wild, rw, {})
	var calm_delta: float = conv.ruler_mood(cvid)
	var wild_delta: float = conv.ruler_mood(wvid)
	_check("unhinged victim mortified 1.5x",
		wild_delta < calm_delta \
		and is_equal_approx(wild_delta, calm_delta * 1.5))


func _test_unparsable_subject_generic_no_crash() -> void:
	var h: Array = _harness()
	var hs = h[2]
	var gs: GameState = h[0]
	var u: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("old gossip", "gossip", "gossip",
		0.65, -1, false, hs.TRUTH_UNKNOWN)
	hs._on_heard(u, r, {})  # must not crash
	_check("unparsable subject falls back to generic heard_rumor",
		_recalled(u, "heard_rumor", int(r.get("id", 0))) > 0.0)
	_check("no victim memory on unparsable subject",
		_recalled(u, "gossiped_about_me", 0) == 0.0)


func _test_press_excludes_gossip() -> void:
	var h: Array = _harness()
	var hs = h[2]
	var gs: GameState = h[0]
	var u: Dictionary = _spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("chicken gossip", "gossip",
		"gossip:%d" % int(u.get("id", 0)), 0.95, int(u.get("id", 0)),
		false, hs.TRUTH_UNKNOWN)
	_check("hot gossip never press-eligible", not hs._press_eligible(r))


func _test_spread_motivation_relationship() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.war_declared.emit("elves", "ogres")
	var victim: Dictionary = _spawn(gs, "ogres")
	var vid := int(victim.get("id", 0))
	var r: Dictionary = hs.seed_rumor("gossip text", "gossip",
		"gossip:%d" % vid, 0.65, -1, false, hs.TRUTH_UNKNOWN)
	var rival: Dictionary = _find_stance(gs, victim, "elves", -1.0, -0.3)
	var friend: Dictionary = _find_stance(gs, victim, "ogres", 0.3, 1.0)
	_check("motivation pair found",
		not rival.is_empty() and not friend.is_empty())
	if rival.is_empty() or friend.is_empty():
		return
	var m_rival: Dictionary = hs._spread_motivation(rival, r)
	_check("rival spreads gossip gleefully (cap+1)",
		int(m_rival.get("cap_delta", 0)) == 1)
	_check("rival heats gossip up",
		float(m_rival.get("heat_delta", 0.0)) > 0.0)
	var m_friend: Dictionary = hs._spread_motivation(friend, r)
	_check("friend suppresses gossip (cap-1)",
		int(m_friend.get("cap_delta", 0)) == -1)
	_check("friend cools gossip down",
		float(m_friend.get("heat_delta", 0.0)) < 0.0)
	var r2: Dictionary = hs.seed_rumor("old gossip", "gossip", "gossip",
		0.65, -1, false, hs.TRUTH_UNKNOWN)
	var m_broken: Dictionary = hs._spread_motivation(rival, r2)
	_check("unparsable subject: neutral motivation",
		int(m_broken.get("cap_delta", 9)) == 0 \
		and is_equal_approx(float(m_broken.get("heat_delta", 9.0)), 0.0))


func _test_victim_id_parse() -> void:
	var h: Array = _harness()
	var hs = h[2]
	_check("parses gossip:42", hs._gossip_victim_id({"subject": "gossip:42"}) == 42)
	_check("gossip without id -> 0",
		hs._gossip_victim_id({"subject": "gossip"}) == 0)
	_check("other subject -> 0",
		hs._gossip_victim_id({"subject": "smear:7"}) == 0)
	_check("missing subject -> 0", hs._gossip_victim_id({}) == 0)


func _test_seed_path_wires_reaction() -> void:
	# The gnome's exact seed call: victim as first knower hears it at
	# seed time and is mortified immediately — no dead-end gossip.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var conv = h[1].get("conversation")
	var victim: Dictionary = _spawn(gs, "humans")
	var vid := int(victim.get("id", 0))
	var vname := String(victim.get("display_name", victim.get("name", "someone")))
	var vjob := String(victim.get("job", "citizen"))
	var text := "Yapper the gossip gnome swears " \
		+ "%s the %s got stuck in a barrel. Twice. Same barrel." % [vname, vjob]
	var r: Dictionary = hs.seed_rumor(text, "gossip", "gossip:%d" % vid,
		0.65, vid, false, hs.TRUTH_UNKNOWN)
	_check("gnome seed produces a live gossip rumor", not r.is_empty())
	_check("victim is first knower", (r.get("knowers", []) as Array).has(vid))
	_check("victim mortified at seed time",
		_recalled(victim, "gossiped_about_me", vid) > 0.0)
	_check("victim mood dropped at seed time", conv.ruler_mood(vid) < 0.0)
	_check("gossip truth stays unknown", String(r.get("truth", "")) == "unknown")
