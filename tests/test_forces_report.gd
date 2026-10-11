extends SceneTree
## Cursing Gnomes — C67 live muster-roll DM routing + LORD SEETHES publishing.
##
## HTML parity (fix79/index.html):
##   - ~104125: the Guild Master and the Financial Adviser answer
##     "how many X" / troop-report DMs with LIVE per-job counts via
##     liveUnitCount67 — never a stale or generic reply.
##   - ~61085: a lord threatened 2+ times seethes — gazNews('LORD SEETHES', ...).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_forces_report.gd
##
## Exit code 0 = all passed, 1 = any failure.

var _passed := 0
var _failed := 0


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + test_name)


func _seethes_count(court: SimRoyalCourt) -> int:
	var n := 0
	for s in court.stories:
		if String(s.get("headline", "")) == "LORD SEETHES":
			n += 1
	return n


func _seethes_body(court: SimRoyalCourt) -> String:
	for s in court.stories:
		if String(s.get("headline", "")) == "LORD SEETHES":
			return String(s.get("story", ""))
	return ""


func _initialize() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.units.append({"id": 11, "alive": true, "faction": "humans", "job": "soldier"})
	gs.units.append({"id": 12, "alive": true, "faction": "humans", "job": "soldier"})
	gs.units.append({"id": 13, "alive": true, "faction": "humans", "job": "archer"})

	var phone := SimPhone.new(gs)

	# --- Guild Master DM: troop questions answered with live counts ---
	var gm := {"id": 21, "alive": true, "faction": "humans", "job": "guild_master",
		"mind": {"gov_role": "guild_master", "persona": "pragmatic", "name": "Guildmaster Gert"}}
	var a1: String = phone._forces_report_reply(gm, "how many soldiers do we have?")
	_check("guild master: answers how-many", a1.begins_with("Live forces report"))
	_check("guild master: live soldier count", "Soldier: 2" in a1)
	var a2: String = phone._forces_report_reply(gm, "troop report")
	_check("guild master: full report", "Archer: 1" in a2 and "Guard: 0" in a2)
	_check("guild master: non-question falls through",
		phone._forces_report_reply(gm, "hello") == "")

	# --- Financial Adviser DM: same live answering ---
	var adv := {"id": 22, "alive": true, "faction": "humans", "job": "adviser",
		"mind": {"gov_role": "adviser", "persona": "pragmatic", "name": "Penny Pincher"}}
	var a3: String = phone._forces_report_reply(adv, "army report")
	_check("adviser: army report",
		a3.begins_with("Live forces report") and "Soldier: 2" in a3)
	var a4: String = phone._forces_report_reply(adv, "how many archers")
	_check("adviser: single-job count", a4 == "Live forces report — Archer: 1.")

	# --- Full _npc_reply routing: troop questions reach the forces path ---
	var r1: String = phone._npc_reply(gm, "troop report")
	_check("npc_reply: guild master troop question routed", "Live forces report" in r1)
	# Recruit commands still win for the guild master (existing behavior intact).
	var r2: String = phone._npc_reply(gm, "recruit more soldiers")
	_check("npc_reply: recruit command not swallowed", "Live forces report" not in r2)

	# --- LORD SEETHES: the flag is consumed and a Gazette story publishes ---
	var court := SimRoyalCourt.new(gs)
	phone._court = court
	var lord := {"id": 31, "alive": true, "faction": "gnomes", "job": "lord",
		"mind": {"gov_role": "lord", "persona": "proud", "name": "Lord Vex"}}
	phone._court_reply(lord, "I will crush you, worm", "lord")
	_check("seethes: no story after first threat", _seethes_count(court) == 0)
	phone._court_reply(lord, "I will crush you, worm", "lord")
	_check("seethes: story published after second threat", _seethes_count(court) == 1)
	_check("seethes: body names the lord",
		"Lord Vex was heard swearing vengeance" in _seethes_body(court))
	# Standing glyph rule (test_gazette_glyphs.gd): no emoji/tofu in stories.
	var tofu := false
	var body := _seethes_body(court)
	for i in range(body.length()):
		if body.unicode_at(i) > 0x2500:
			tofu = true
	_check("seethes: story glyph-free (no tofu)", not tofu)

	# --- Court characters answer troop questions with NO open petition ---
	# HTML ~61055: "how many X" / troop reports to mayor/lord/commander get
	# live per-job counts even outside petition verdicts (routed in
	# _npc_reply, not just _court_reply).
	var lord2 := {"id": 41, "alive": true, "faction": "humans", "job": "lord",
		"mind": {"gov_role": "lord", "persona": "proud", "name": "Lord Vex"}}
	var r3: String = phone._npc_reply(lord2, "how many soldiers do we have?")
	_check("npc_reply: lord how-many answered live",
		"muster rolls" in r3 and "Soldier: 2" in r3)
	var r4: String = phone._npc_reply(lord2, "troop report")
	_check("npc_reply: lord troop report", "Archer: 1" in r4)
	# Non-questions still fall through to the full engine (no muster text).
	var r5: String = phone._npc_reply(lord2, "hello there")
	_check("npc_reply: lord greeting not swallowed", "muster rolls" not in r5)

	print("Forces-report tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
