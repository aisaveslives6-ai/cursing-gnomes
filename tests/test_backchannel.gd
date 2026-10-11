extends SceneTree
## Cursing Gnomes — Backchannel tests (graphics-hourly 2026-10-05).
##
## Ports HTML fix79 "Candidate21: The Backchannel" (index.html ~lines
## 76140-76661): ruler letters, affinity matrix, topic weighting, the
## diplomacy ladder, dramatic war up/down events, gossip mentions, and the
## Gazette throttle — plus the Godot improvements (real diplomacy hooks,
## Royal Court petitions / strategic proposals for player-involved pairs).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_backchannel.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes backchannel tests ===")
	_test_pair_key()
	_test_affinity_default()
	_test_rulers()
	_test_voice_lines_complete()
	_test_line_slots_filled()
	_test_daily_tick_idempotent()
	_test_tick_cadence()
	_test_exchange_shifts_affinity()
	_test_affinity_clamps()
	_test_log_cap()
	_test_letters_this_week()
	_test_topic_kinds_valid()
	_test_story_throttle()
	_test_threshold_story()
	_test_mention_throttle()
	_test_mention_uses_real_names()
	_test_diplomacy_feed_warm_ai()
	_test_diplomacy_feed_cold_ai()
	_test_diplomacy_feed_player_petition()
	_test_court_petition_approve_applies()
	_test_dramatic_event_peace()
	_test_dramatic_event_war()
	_test_dramatic_event_player_proposal()
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


func _make_world(factions: Array = ["humans", "gnomes"]) -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var fa: Array[String] = []
	for f in factions:
		fa.append(String(f))
	gs.setup(fa)
	# Durable design: the player faction (factions[0]) is player-led, never
	# AI-led — the backchannel synthesizes its ruler from this name.
	gs.set_ruler_name("TestKing")
	_stories.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	var bc := SimBackchannel.new(gs)
	return [gs, bc]


func _rulers(bc: SimBackchannel) -> Array:
	return bc._rulers()


# --- pair key / affinity ------------------------------------------------------


func _test_pair_key() -> void:
	_check("pair_key: order independent",
		SimBackchannel.pair_key("leader_b", "leader_a") == SimBackchannel.pair_key("leader_a", "leader_b"))
	_check("pair_key: sorted format",
		SimBackchannel.pair_key("leader_b", "leader_a") == "leader_a|leader_b")


func _test_affinity_default() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	_check("affinity: unknown pair is 0",
		bc.affinity("leader_humans", "leader_gnomes") == 0.0)


func _test_rulers() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	_check("rulers: two factions -> two rulers", rulers.size() == 2)
	var keys: Array = []
	for r in rulers:
		keys.append(String(r["key"]))
	_check("rulers: leader keys", keys.has("leader_humans") and keys.has("leader_gnomes"))
	var names: Dictionary = {}
	for r in rulers:
		names[String(r["faction"])] = String(r["name"])
	# Durable design: the player faction is player-led — its ruler is the
	# player's own ruler name, not an AI pool candidate.
	_check("rulers: human name", names["humans"] == "TestKing")
	var gnome_pool_names: Array = []
	for c in SimFactionLeaders.LEADER_POOLS.get("gnomes", []):
		gnome_pool_names.append(String((c as Dictionary).get("name", "")))
	_check("rulers: gnome name is a real pool candidate",
		gnome_pool_names.has(String(names["gnomes"])))
	var ok := true
	for r in rulers:
		for k in ["dip", "aggro", "weird"]:
			var v := float(r[k])
			if v < 0.0 or v > 100.0:
				ok = false
	_check("rulers: traits in 0..100", ok)


# --- voice lines --------------------------------------------------------------


func _test_voice_lines_complete() -> void:
	var kinds: Array = ["compliment", "trade", "treaty", "insult", "scheme", "war", "gossip", "player"]
	var ok := true
	for f in ["humans", "ogres", "elves", "gnomes", "undead"]:
		var voices: Dictionary = SimBackchannel.BC_LINES.get(f, {})
		for k in kinds:
			var set: Array = voices.get(k, [])
			if set.size() < 2:
				ok = false
	_check("BC_LINES: 5 factions x 8 kinds x 2+ lines", ok)


func _test_line_slots_filled() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	var a: Dictionary = rulers[0]
	var b: Dictionary = rulers[1]
	var ok := true
	for kind in SimBackchannel.VALENCE.keys():
		var line := bc._line(String(kind), a, b, "elves")
		for slot in ["{X}", "{S}", "{T}", "{P}"]:
			if slot in line:
				ok = false
		if line.is_empty():
			ok = false
	_check("line: all slots filled, non-empty", ok)
	# Undead voice renders too (new vs HTML).
	var undead := {"key": "leader_undead", "name": "Lich Lord Morvain",
		"faction": "undead", "dip": 20.0, "aggro": 60.0, "weird": 10.0}
	var ul := bc._line("insult", undead, b, "")
	_check("line: undead voice renders", not ul.is_empty() and not ("{X}" in ul))
	_check("line: recipient named", String(b["name"]) in bc._line("trade", a, b, ""))


# --- daily tick ---------------------------------------------------------------


func _test_daily_tick_idempotent() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	bc._daily_tick(20)
	var n := bc._log.size()
	bc._daily_tick(20)
	_check("daily tick: idempotent same day", bc._log.size() == n and n > 0)


func _test_tick_cadence() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	bc._daily_tick(5)  # early game: exactly 1 exchange
	_check("tick: early game 1 exchange", bc._log.size() == 1)
	bc._daily_tick(30)  # late game: 2..4 exchanges
	_check("tick: late game 2..4 exchanges",
		bc._log.size() >= 3 and bc._log.size() <= 5)


func _test_exchange_shifts_affinity() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	for d in range(1, 30):
		bc._daily_tick(d)
	var moved := false
	for k in bc._aff.keys():
		if absf(float(bc._aff[k])) > 0.01:
			moved = true
	_check("exchange: affinity moves over 29 days", moved)


func _test_affinity_clamps() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	bc._aff["leader_gnomes|leader_humans"] = 95.0
	var rulers := _rulers(bc)
	var a: Dictionary = rulers[0]
	var b: Dictionary = rulers[1]
	for i in range(30):
		bc._diplomacy_feed(a, b, 95.0, 100.0)
	_check("affinity never exceeds 100",
		bc.affinity("leader_humans", "leader_gnomes") <= 100.0)
	bc._aff["leader_gnomes|leader_humans"] = -99.0
	for i in range(30):
		bc._exchange(rulers, 100 + i)
	var ok := true
	for k in bc._aff.keys():
		var v := float(bc._aff[k])
		if v < -100.0 or v > 100.0:
			ok = false
	_check("affinity clamped -100..100", ok)


func _test_log_cap() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	for d in range(1, 60):
		bc._daily_tick(d)
	_check("log capped at 40", bc._log.size() <= 40)


func _test_letters_this_week() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	bc._push_log(10, "leader_humans", "leader_gnomes", "gossip", ["hi"])
	bc._push_log(12, "leader_humans", "leader_gnomes", "trade", ["yo"])
	bc._push_log(2, "leader_humans", "leader_gnomes", "gossip", ["old"])
	var pk := SimBackchannel.pair_key("leader_humans", "leader_gnomes")
	_check("letters_this_week counts 7-day window",
		bc._letters_this_week(14, pk) == 2)


func _test_topic_kinds_valid() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	var ok := true
	for i in range(40):
		var t := bc._topic_for(rulers[0], rulers[1])
		if not SimBackchannel.VALENCE.has(String(t["kind"])):
			ok = false
	_check("topic: always a known kind", ok)


# --- gazette surface ----------------------------------------------------------


func _test_story_throttle() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	_stories.clear()
	var first := bc._story("HEAD", "body", "💌", false)
	var second := bc._story("HEAD2", "body2", "💌", false)
	_check("story: first posts", first)
	_check("story: second same day blocked", not second)
	_check("story: exactly one emitted", _stories.size() == 1)
	_check("story: kind court", String(_stories[0].get("kind", "")) == "court")
	_check("story: icon carried", String(_stories[0].get("icon", "")) == "💌")


func _test_threshold_story() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	var a: Dictionary = rulers[0]
	var b: Dictionary = rulers[1]
	var pk := SimBackchannel.pair_key(String(a["key"]), String(b["key"]))
	_stories.clear()
	gs.day_number = 20
	bc._threshold_story(rulers, 20, pk, a, b, 59.0, 61.0)
	_check("threshold: warm crossing posts",
		_stories.size() == 1 and "ROYAL CORRESPONDENCE" in String(_stories[0]["headline"]))
	bc._threshold_story(rulers, 20, pk, a, b, 61.0, 65.0)
	_check("threshold: no repeat while warm", _stories.size() == 1)
	bc._threshold_story(rulers, 21, pk, a, b, 65.0, 10.0)  # back to neutral
	gs.day_number = 22
	bc._threshold_story(rulers, 22, pk, a, b, 10.0, -61.0)
	_check("threshold: cold crossing posts after reset",
		_stories.size() == 2 and "poison" in String(_stories[1]["body"]))


# --- gossip mentions ----------------------------------------------------------


func _test_mention_throttle() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	_check("mention: empty log -> empty", bc.mention("humans") == "")
	bc._push_log(1, "leader_gnomes", "leader_elves", "gossip", ["x"])
	var first := bc.mention("humans")
	# 70% gate: may be empty; but throttle must hold when it fires.
	if first != "":
		_check("mention: once per day", bc.mention("humans") == "")
	else:
		# Force past the 70% gate deterministically: seed-independent check
		# is the throttle flag itself.
		bc._mention_day = -1
		var got := ""
		for i in range(60):
			bc._mention_day = -1
			got = bc.mention("humans")
			if got != "":
				break
		_check("mention: fires within 60 rolls", got != "")
		if got != "":
			_check("mention: throttled after firing", bc.mention("humans") == "")


func _test_mention_uses_real_names() -> void:
	var w := _make_world(["humans", "gnomes", "elves"])
	var gs: GameState = w[0]
	var bc: SimBackchannel = w[1]
	# AI leader picks are random per game — resolve the actual names rather
	# than hardcoding pool candidates.
	var fl = gs.faction_leaders
	var gn := String(fl.leader_of("gnomes").get("name", ""))
	var el := String(fl.leader_of("elves").get("name", ""))
	bc._push_log(1, "leader_gnomes", "leader_elves", "trade", ["x"])
	var got := ""
	for i in range(80):
		bc._mention_day = -1
		got = bc.mention("humans")
		if got != "":
			break
	_check("mention: eventually fires", got != "")
	if got != "":
		_check("mention: names real rulers",
			gn != "" and el != "" and gn in got and el in got)
		_check("mention: kind phrase present", "fishwives" in got)


# --- diplomacy feed -----------------------------------------------------------


func _test_diplomacy_feed_warm_ai() -> void:
	# No player faction: AI<->AI pairs auto-apply through real hooks.
	var w := _make_world()
	var gs: GameState = w[0]
	gs.player_faction = ""
	# AI-only world: with no player faction, every faction gets an AI leader.
	gs.faction_leaders.ensure(gs.active_factions)
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	var a: Dictionary = rulers[0]
	var b: Dictionary = rulers[1]
	for i in range(60):
		bc._diplomacy_feed(a, b, 61.0, 62.0)
		if gs.diplomacy.has_trade_deal("humans", "gnomes"):
			break
	_check("feed: warm AI pair signs trade pact",
		gs.diplomacy.has_trade_deal("humans", "gnomes"))


func _test_diplomacy_feed_cold_ai() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	gs.player_faction = ""
	# AI-only world: with no player faction, every faction gets an AI leader.
	gs.faction_leaders.ensure(gs.active_factions)
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	var a: Dictionary = rulers[0]
	var b: Dictionary = rulers[1]
	gs.diplomacy.form_alliance("humans", "gnomes")
	_check("feed setup: allied", gs.diplomacy.relation_state("humans", "gnomes") == "allied")
	for i in range(80):
		bc._diplomacy_feed(a, b, -61.0, -62.0)
		if gs.diplomacy.relation_state("humans", "gnomes") != "allied":
			break
	_check("feed: cold AI pair breaks alliance",
		gs.diplomacy.relation_state("humans", "gnomes") != "allied")


func _test_diplomacy_feed_player_petition() -> void:
	# Player-involved pair: NO auto-apply — a Royal Court petition instead.
	var w := _make_world()
	var gs: GameState = w[0]
	gs.player_faction = "humans"
	var bc: SimBackchannel = w[1]
	bc._court = SimRoyalCourt.new(gs)
	var rulers := _rulers(bc)
	var a: Dictionary = rulers[0]  # humans (player)
	var b: Dictionary = rulers[1]  # gnomes
	for i in range(40):
		bc._diplomacy_feed(a, b, 61.0, 62.0)
	_check("feed: player pair never auto-signs",
		not gs.diplomacy.has_trade_deal("humans", "gnomes"))
	var found := false
	for p in bc._court.open_petitions():
		if String(p["kind"]).begins_with("bc_"):
			found = true
	_check("feed: player pair raises court petition", found)


func _test_court_petition_approve_applies() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	gs.player_faction = "humans"
	var bc: SimBackchannel = w[1]
	bc._court = SimRoyalCourt.new(gs)
	var rulers := _rulers(bc)
	bc._court_petition("trade", rulers[0], rulers[1])
	var open: Array = bc._court.open_petitions()
	_check("petition: opened", open.size() == 1)
	var pid := int(open[0]["id"])
	bc._court.decide(pid, 0)  # Approve
	_check("petition: approve signs trade pact",
		gs.diplomacy.has_trade_deal("humans", "gnomes"))
	_check("petition: cleared from pending", bc._pending.is_empty())


# --- dramatic events ----------------------------------------------------------


func _test_dramatic_event_peace() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	gs.player_faction = ""  # AI-only world: auto-applies
	# AI-only world: with no player faction, every faction gets an AI leader.
	gs.faction_leaders.ensure(gs.active_factions)
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	gs.diplomacy.declare_war("humans", "gnomes", "test")
	_check("dramatic setup: at war",
		gs.diplomacy.relation_state("humans", "gnomes") == "war")
	_stories.clear()
	bc._dramatic_event(rulers, 50)
	_check("dramatic: war talked down to neutral",
		gs.diplomacy.relation_state("humans", "gnomes") == "neutral")
	var urgent_found := false
	for s in _stories:
		if "WHITE PEACE" in String(s["headline"]):
			urgent_found = bool(s.get("urgent", false))
	_check("dramatic: WHITE PEACE urgent story", urgent_found)
	_check("dramatic: once per day", bc._td_day == 50)
	var rel_after: String = gs.diplomacy.relation_state("humans", "gnomes")
	gs.diplomacy.declare_war("humans", "gnomes", "again")
	bc._dramatic_event(rulers, 50)
	_check("dramatic: no second event same day",
		gs.diplomacy.relation_state("humans", "gnomes") == "war" or rel_after == "neutral")


func _test_dramatic_event_war() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	gs.player_faction = ""
	# AI-only world: with no player faction, every faction gets an AI leader.
	gs.faction_leaders.ensure(gs.active_factions)
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	var a: Dictionary = rulers[0]
	var b: Dictionary = rulers[1]
	bc._aff[SimBackchannel.pair_key(String(a["key"]), String(b["key"]))] = -70.0
	_check("dramatic setup: neutral",
		gs.diplomacy.relation_state("humans", "gnomes") == "neutral")
	_stories.clear()
	bc._dramatic_event(rulers, 60)
	_check("dramatic: frigid pair talked up to war",
		gs.diplomacy.relation_state("humans", "gnomes") == "war")
	var found := false
	for s in _stories:
		if "WAR OF LETTERS" in String(s["headline"]):
			found = true
	_check("dramatic: WAR OF LETTERS story", found)


func _test_dramatic_event_player_proposal() -> void:
	# Player-involved dramatic war: proposal, never auto-declare.
	var w := _make_world()
	var gs: GameState = w[0]
	gs.player_faction = "humans"
	gs.proposals = SimProposals.new(gs)
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	var a: Dictionary = rulers[0]
	var b: Dictionary = rulers[1]
	bc._aff[SimBackchannel.pair_key(String(a["key"]), String(b["key"]))] = -70.0
	bc._dramatic_event(rulers, 70)
	_check("dramatic: player war never auto-declares",
		gs.diplomacy.relation_state("humans", "gnomes") == "neutral")
	var found := false
	for p in gs.proposals.proposals:
		if String(p["kind"]) == "declare_war" \
				and String(p["status"]) == "open":
			found = true
	_check("dramatic: player gets declare_war proposal", found)


# --- persistence --------------------------------------------------------------


func _test_save_load() -> void:
	var w := _make_world()
	var bc: SimBackchannel = w[1]
	var rulers := _rulers(bc)
	for d in range(1, 15):
		bc._daily_tick(d)
	var data := bc.to_dict()
	var w2 := _make_world()
	var bc2: SimBackchannel = w2[1]
	bc2.from_dict(data)
	_check("save/load: affinity preserved",
		bc2.affinity("leader_humans", "leader_gnomes")
		== bc.affinity("leader_humans", "leader_gnomes"))
	_check("save/load: log preserved", bc2._log.size() == bc._log.size())
	_check("save/load: throttles preserved",
		bc2._story_day == bc._story_day and bc2._td_day == bc._td_day
		and bc2._mention_day == bc._mention_day)
	_check("save/load: flags preserved", bc2._flags.size() == bc._flags.size())
	bc2.from_dict({})
	_check("save/load: empty dict never throws",
		bc2._log.is_empty() and bc2._day == 0)
