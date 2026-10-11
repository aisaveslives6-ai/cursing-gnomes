extends SceneTree
## Gazette tests — HTML parity (fix79/index.html).
## Tests the SimGazette system: archetype classification, cartoon selection,
## newspaper restyle (sections/reporters/captions), two-way chat.

var _passed := 0
var _failed := 0
var GazetteScript := load("res://scripts/sim/gazette.gd")


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + name)


func _initialize() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	# day_number 250 -> year 3 (120 days/year)
	gs.day_number = 250
	var gaz: RefCounted = GazetteScript.new(gs)

	# --- Archetype classification (HTML GAZETTE_ARCH_RES) ---
	_check(gaz.archetype_for("War Declared!", "The kingdom declares war") == "war",
		"archetype: war")
	_check(gaz.archetype_for("Giant Ass Attacks", "A giant ass flattened the hall") == "disaster",
		"archetype: disaster (giant ass)")
	_check(gaz.archetype_for("Royal Wedding", "A joyous wedding ceremony") == "wedding",
		"archetype: wedding")
	_check(gaz.archetype_for("Market Day", "Grand market opens") == "market",
		"archetype: market")
	_check(gaz.archetype_for("Nothing Happens", "A quiet day in the realm") == "",
		"archetype: no match -> empty")
	_check(gaz.archetype_for("Rogue Wizard Spotted", "A wild mage appeared") == "wizard",
		"archetype: wizard")
	_check(gaz.archetype_for("Trial Begins", "The verdict was guilty") == "trial",
		"archetype: trial")
	_check(gaz.archetype_for("Flood!", "The flood waters recede") == "flood",
		"archetype: flood")

	# --- Cartoon selection (HTML gazetteCartoonURI) ---
	var war_story := {"headline": "War Declared!", "story": "The kingdom declares war on the elves", "day": 5}
	var cartoon: String = gaz.cartoon_path_for(war_story)
	_check(cartoon.begins_with("res://assets/ui/gazette_cartoons/gaz_war_"),
		"cartoon: war story gets war cartoon")
	_check(cartoon.ends_with(".jpg"), "cartoon: ends with .jpg")

	# Deterministic: same story -> same cartoon.
	var cartoon2: String = gaz.cartoon_path_for(war_story)
	_check(cartoon == cartoon2, "cartoon: deterministic")

	# No archetype -> no cartoon.
	var quiet := {"headline": "Nothing", "story": "A quiet day", "day": 1}
	_check(gaz.cartoon_path_for(quiet) == "", "cartoon: no match -> empty")

	# --- Newspaper restyle (HTML STAGE20-3) ---
	_check(gaz.section_for(war_story) == "War Desk", "section: war -> War Desk")
	var wed := {"headline": "Royal Wedding", "story": "They tied the knot", "day": 1}
	_check(gaz.section_for(wed) == "Society Pages", "section: wedding -> Society Pages")
	var kick := {"headline": "X", "story": "Y", "day": 1, "kicker": "Custom Desk"}
	_check(gaz.section_for(kick) == "Custom Desk", "section: kicker override")
	_check(gaz.section_for(quiet) == "Town Crier", "section: default -> Town Crier")

	var reporter: String = gaz.reporter_for(war_story)
	_check(reporter in GazetteScript.REPORTERS, "reporter: from HTML list: " + reporter)
	_check(gaz.reporter_for(war_story) == reporter, "reporter: deterministic")

	_check(gaz.caption_for(war_story) == GazetteScript.CAPTIONS["war"],
		"caption: war")
	_check(gaz.caption_for(quiet) == GazetteScript.CAPTIONS["_default"],
		"caption: default")

	_check(gaz.issue_line(5) == "Vol. 3 — No. 5", "issue_line: Vol. 3 — No. 5")

	var article: Dictionary = gaz.article_for(war_story, true)
	_check(article["section"] == "War Desk", "article: section")
	_check(article["byline"] == reporter, "article: byline")
	_check(article["lead"] == true, "article: lead flag")
	_check(str(article["cartoon_path"]).begins_with("res://"), "article: cartoon_path")

	# --- Two-way chat (HTML gazParseIntent / gazCraftReply) ---
	_check(gaz.parse_intent("yes, I agree") == "agree", "intent: agree")
	_check(gaz.parse_intent("no, never") == "refuse", "intent: refuse")
	_check(gaz.parse_intent("what is this?") == "question", "intent: question")
	_check(gaz.parse_intent("I will kill you") == "threaten", "intent: threaten")
	_check(gaz.parse_intent("can you lower the price?") == "haggle", "intent: haggle")
	_check(gaz.parse_intent("hello there") == "greet", "intent: greet")
	_check(gaz.parse_intent("blargh flargh") == "unknown", "intent: unknown")

	_check(GazetteScript.persona_voice("jolly") == "chuckling heartily",
		"persona: jolly")
	_check(GazetteScript.persona_voice("nonexistent") == "plainly",
		"persona: default")

	var char := {"name": "Mayor Bob", "role": "mayor", "race": "human",
		"persona": "worried", "mood": 50.0}
	var pending := {"text": "Give us food?", "choices": [{"outcome": "Food given."}]}
	var reply: Dictionary = GazetteScript.craft_reply(char, "agree", "yes", pending)
	_check("wise decree" in str(reply["text"]).to_lower(), "reply: agree text")
	_check(bool(reply["resolved"]), "reply: agree resolves")
	_check(float(char["mood"]) > 50.0, "reply: agree boosts mood")

	var char2 := {"name": "Lord Vex", "role": "lord", "race": "elf",
		"persona": "haughty", "mood": 50.0}
	var reply2: Dictionary = GazetteScript.craft_reply(char2, "threaten", "I will destroy you", {})
	_check("Threats, cousin?" in str(reply2["text"]), "reply: lord threaten text")
	_check(float(char2["mood"]) < 50.0, "reply: threaten drops mood")

	var char3 := {"name": "Cmdr Jane", "role": "commander", "race": "human",
		"persona": "loyal", "mood": 50.0}
	var reply3: Dictionary = GazetteScript.craft_reply(char3, "greet", "hello", {})
	_check("says Cmdr Jane" in str(reply3["text"]), "reply: greet includes name")

	_check(GazetteScript.hash_str("test") == GazetteScript.hash_str("test"),
		"hash: deterministic")
	_check(GazetteScript.hash_str("a") != GazetteScript.hash_str("b"),
		"hash: different inputs differ")

	# --- C67 live muster-roll (HTML liveUnitCount67) ---
	gs.units.append({"id": 101, "alive": true, "faction": "humans", "job": "soldier"})
	gs.units.append({"id": 102, "alive": true, "faction": "humans", "job": "soldier"})
	gs.units.append({"id": 103, "alive": true, "faction": "humans", "job": "archer"})
	gs.units.append({"id": 104, "alive": false, "faction": "humans", "job": "soldier"})
	gs.units.append({"id": 105, "alive": true, "faction": "gnomes", "job": "soldier"})
	gs.units.append({"id": 106, "alive": true, "faction": "humans", "job": "spirit",
		"summoned": true})
	_check(GazetteScript.live_unit_count(gs, "humans", "soldier") == 2,
		"muster: live soldiers = 2 (dead, foreign, summoned excluded)")
	_check(GazetteScript.live_unit_count(gs, "humans", "archer") == 1,
		"muster: live archers = 1")
	_check(GazetteScript.live_unit_count(gs, "gnomes", "soldier") == 1,
		"muster: faction filter")
	_check(GazetteScript.live_unit_count(gs, "humans", "mage") == 0,
		"muster: zero count")
	_check(GazetteScript.live_unit_count(null, "humans", "soldier") == 0,
		"muster: null game state -> 0")
	# Queued training counts too (HTML countUnitType infinite-production fix).
	gs.buildings.append({"id": 201, "alive": true, "faction": "humans",
		"train_queue": [{"unit_type": "soldier", "time_left": 3.0},
			{"unit_type": "mage", "time_left": 5.0}]})
	gs.buildings.append({"id": 202, "alive": true, "faction": "gnomes",
		"train_queue": [{"unit_type": "soldier", "time_left": 1.0}]})
	_check(GazetteScript.live_unit_count(gs, "humans", "soldier") == 3,
		"muster: queued training counts")
	_check(GazetteScript.live_unit_count(gs, "humans", "mage") == 1,
		"muster: queued mage counts")
	_check(GazetteScript.live_unit_count(gs, "gnomes", "soldier") == 2,
		"muster: foreign queue does not leak")

	var roster: Array = GazetteScript.muster_roster()
	_check(not roster.is_empty(), "muster: roster non-empty")
	_check("soldier" in roster and "archer" in roster and "mage" in roster,
		"muster: roster has core fighters")
	_check(not ("bandit" in roster) and not ("spirit" in roster),
		"muster: roster excludes bandit/spirit")
	var all_mil := true
	for j in roster:
		if not JobDefs.is_military(String(j)):
			all_mil = false
	_check(all_mil, "muster: roster all military")

	_check(GazetteScript.forces_job_word("how many soldiers do we have?") == "soldier",
		"muster: word soldiers")
	_check(GazetteScript.forces_job_word("HOW MANY SWORDSMEN") == "swordsman",
		"muster: word swordsmen (case-insensitive)")
	_check(GazetteScript.forces_job_word("how many axemen") == "axeman",
		"muster: word axemen")
	_check(GazetteScript.forces_job_word("how many towns") == "",
		"muster: word towns -> empty")
	_check(GazetteScript.is_forces_question("give me a troop report") == true,
		"muster: troop report is a forces question")
	_check(GazetteScript.is_forces_question("how is our army") == true,
		"muster: how is our army is a forces question")
	_check(GazetteScript.is_forces_question("report our forces") == true,
		"muster: report our forces is a forces question")
	_check(GazetteScript.is_forces_question("hello there") == false,
		"muster: greeting is not a forces question")

	# Court question handler: troop questions get LIVE answers — never the
	# generic fallback — and are checked BEFORE pending petition text (HTML order).
	var char4 := {"name": "Cmdr Jane", "role": "commander", "race": "humans",
		"persona": "loyal", "mood": 50.0}
	var reply4: Dictionary = GazetteScript.craft_reply(char4, "question",
		"how many soldiers do we have?", {}, gs)
	var t4 := str(reply4["text"])
	_check("muster rolls" in t4, "muster: court answer opens with muster rolls")
	_check("Soldier: 3" in t4, "muster: court answer has live soldier count")
	var reply5: Dictionary = GazetteScript.craft_reply(char4, "question",
		"troop report", {}, gs)
	_check("Guard: 0" in str(reply5["text"]) and "Mage: 1" in str(reply5["text"]),
		"muster: full report lists roster with live counts")
	var reply6: Dictionary = GazetteScript.craft_reply(char4, "question",
		"what is the weather?", {}, gs)
	_check("The realm turns" in str(reply6["text"]),
		"muster: non-troop question still generic")
	var reply7: Dictionary = GazetteScript.craft_reply(char4, "question",
		"troop report", {})
	_check("The realm turns" in str(reply7["text"]),
		"muster: no game state -> generic fallback")
	var pendq := {"text": "Give us food?", "choices": [{"outcome": "Food given."}]}
	var reply8: Dictionary = GazetteScript.craft_reply(char4, "question",
		"how many soldiers?", pendq, gs)
	_check("muster rolls" in str(reply8["text"]),
		"muster: troop question beats pending petition text")
	# Guild Master / Financial Adviser phrasing (HTML guild path ~104125).
	_check(GazetteScript.adviser_forces_answer(gs, "humans", "how many mages?").begins_with("Live forces report"),
		"muster: adviser answer phrasing")
	_check("Mage: 1" in GazetteScript.adviser_forces_answer(gs, "humans", "how many mages?"),
		"muster: adviser answer has live count")
	_check(GazetteScript.adviser_forces_answer(gs, "humans", "hello") == "",
		"muster: adviser non-question -> empty")

	# lord_seethes flag: lord threatened twice -> true; once -> false;
	# non-lord roles never set it.
	var lord := {"name": "Lord Vex", "role": "lord", "race": "elf",
		"persona": "proud", "mood": 50.0}
	var r1: Dictionary = GazetteScript.craft_reply(lord, "threaten", "I will crush you", {})
	_check(not bool(r1.get("lord_seethes", false)), "seethes: first threat -> false")
	var r2: Dictionary = GazetteScript.craft_reply(lord, "threaten", "I will crush you", {})
	_check(bool(r2.get("lord_seethes", false)), "seethes: second threat -> true")
	var mayor2 := {"name": "Mayor Bob", "role": "mayor", "race": "human",
		"persona": "worried", "mood": 50.0}
	var r3: Dictionary = GazetteScript.craft_reply(mayor2, "threaten", "I will crush you", {})
	var r4: Dictionary = GazetteScript.craft_reply(mayor2, "threaten", "I will crush you", {})
	_check(not bool(r3.get("lord_seethes", false)) and not bool(r4.get("lord_seethes", false)),
		"seethes: mayor never seethes")

	print("Gazette tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
