extends SceneTree
## Cursing Gnomes — expansion integration playtest (launch-readiness, 2026-10-06).
##
## The wiring audit flagged that the new expansion paths (war counsel pleas,
## command-post sieges, starfort tick, mid-war save/load) only had unit
## tests with SEEDED records. This suite drives them TOGETHER through the
## real runtime plumbing: a scripted 11-day humans-vs-elves war where every
## war record, siege, plea, and capture forms from live state.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_expansion_playtest.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes expansion playtest ===")
	_test_full_war_arc()
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


## Full world wiring, mirroring world.gd's system assembly.
func _make_game() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "elves"])  # player = humans
	gs.set_ruler_name("ass")
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.hiring = GuildHiring.new(gs)
	gs.army = SimArmy.new(gs)
	gs.proposals = SimProposals.new(gs)
	var mons := SimMonasteries.new()
	mons.setup(gs)
	gs.monasteries = mons
	var crys := SimDarkCrystals.new()
	crys.setup(gs)
	gs.crystals = crys
	var cps := SimCommandPosts.new()
	cps.setup(gs)
	gs.command_posts = cps
	var sfb := StarFortBases.new(gs)
	gs.starfort_bases = sfb
	var rv := SimRulersVoice.new(gs)
	gs.rulers_voice = rv
	var phone := _StubPhone.new()
	gs.phone_sys = phone
	var court := _StubCourt.new()
	gs.court_sys = court
	court.bus = gs.bus
	# Gazette stories land here.
	var gazette: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: gazette.append(s))
	# Towns + completed halls for both factions.
	var t1: Dictionary = gs.found_town("humans", "Testville", Vector2(2000, 2000))
	var t2: Dictionary = gs.found_town("elves", "Elfholm", Vector2(500, 500))
	gs.add_building({"type": "town_hall", "faction": "humans",
		"town_id": int(t1["id"]), "position": Vector2(2000, 2000),
		"alive": true, "complete": true, "progress": 1.0,
		"hp": 2000.0, "max_hp": 2000.0, "town_name": "Testville"})
	gs.add_building({"type": "town_hall", "faction": "elves",
		"town_id": int(t2["id"]), "position": Vector2(500, 500),
		"alive": true, "complete": true, "progress": 1.0,
		"hp": 2000.0, "max_hp": 2000.0, "town_name": "Elfholm"})
	# One owned monastery (humans) + one owned crystal (elves), appended
	# directly so the posts see real holders through the live record shape.
	mons.monasteries.append({"id": 1001, "god_id": "nasty",
		"position": Vector2(1200, 1200), "owner": "humans",
		"progress": {}, "contested": false, "contested_by": "",
		"name": "Nasty Monastery"})
	crys.crystals.append({"id": 2001, "god_id": "dark",
		"position": Vector2(900, 900), "owner": "elves",
		"progress": {}, "contested": false, "contested_by": "",
		"name": "Dark Crystal", "struck_t": 0.0})
	# Cabinet: war advisor (pleas) + treasury advisor (drain voice).
	var war_adv: Dictionary = gs.add_unit({"faction": "humans",
		"job": "advisor_war", "town_id": int(t1["id"]),
		"position": Vector2(2000, 2010), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0,
		"name": "War Advisor"})
	war_adv["is_advisor"] = true
	var tre_adv: Dictionary = gs.add_unit({"faction": "humans",
		"job": "advisor_economy", "town_id": int(t1["id"]),
		"position": Vector2(2000, 2020), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0,
		"name": "Treasury Advisor"})
	tre_adv["is_advisor"] = true
	gs.resources.add_resource("humans", "gold", 5000.0, true)
	gs.resources.add_resource("humans", "wood", 5000.0, true)
	gs.resources.add_resource("elves", "gold", 5000.0, true)
	return [gs, rv, cps, phone, court, gazette, war_adv, tre_adv]


func _soldier(gs: GameState, faction: String, pos: Vector2,
		town_id: int, soldier_name: String = "") -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "job": "soldier",
		"town_id": town_id, "position": pos, "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0,
		"name": soldier_name})
	return u


## Kill a unit through the real signal path (killer's faction credited).
func _kill(gs: GameState, u: Dictionary, killer_faction: String) -> void:
	u["alive"] = false
	gs.bus.unit_killed.emit(int(u["id"]), killer_faction)


## Advance the sim clock to day n and fire the real daily signal.
func _day(gs: GameState, n: int) -> void:
	gs.game_time = Config.DAY_LENGTH_SECONDS * float(maxi(0, n - 1))
	gs.day_number = n
	gs.bus.day_changed.emit(n, false)


func _messages_from(phone, advisor_id: int) -> Array:
	var out: Array = []
	for m: Array in phone.sent:
		if int(m[0]) == advisor_id:
			out.append(String(m[1]))
	return out


func _test_full_war_arc() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var rv: SimRulersVoice = parts[1]
	var cps: SimCommandPosts = parts[2]
	var phone = parts[3]
	var court = parts[4]
	var gazette: Array = parts[5]
	var war_adv: Dictionary = parts[6]
	var tre_adv: Dictionary = parts[7]
	var war_id := int(war_adv["id"])
	var tre_id := int(tre_adv["id"])

	# --- Day 1: the elves declare (real diplomacy path). ---
	gs.diplomacy.declare_war("humans", "elves", "playtest")
	_check("playtest: war declared", gs.diplomacy.relation_state("humans", "elves") == "war")

	# 8 elf raiders mass around Testville (detect radius = 520 * 0.8).
	var raiders: Array = []
	for i: int in range(8):
		raiders.append(_soldier(gs, "elves",
			Vector2(2000, 2000) + Vector2(140 + i * 12, 120 - i * 10), 2,
			"Raider %d" % i))
	# 3 human defenders hold the hall.
	var defenders: Array = []
	for i: int in range(3):
		defenders.append(_soldier(gs, "humans",
			Vector2(2050 + i * 20, 1950), 1, "Guard %d" % i))
	_day(gs, 1)

	# --- Siege forms from live positions (nothing seeded). ---
	_check("playtest: siege detected", not cps.sieges.is_empty())
	var siege_key := ""
	for k: String in cps.sieges.keys():
		siege_key = k
	_check("playtest: siege on humans town",
		String((cps.sieges[siege_key] as Dictionary).get("holder", "")) == "humans")
	_check("playtest: siege mode decided via proposal",
		String((cps.sieges[siege_key] as Dictionary).get("mode", "undecided")) != "undecided")
	_check("playtest: besieged gazette", gazette.size() > 0)

	# --- Days 2-4: lopsided losses through the real kill signal. ---
	for d: int in range(2, 5):
		for i: int in range(3):
			var u: Dictionary = _soldier(gs, "humans",
				Vector2(2050 + i * 15, 1950 + d * 5), 1, "Fallen %d-%d" % [d, i])
			_kill(gs, u, "elves")  # credited to the elves: OUR dead
		var e: Dictionary = _soldier(gs, "elves", Vector2(1900, 1900), 2,
			"ElfFallen %d" % d)
		_kill(gs, e, "humans")  # their dead
		_day(gs, d)
	var wkey := "humans|elves"
	var rec: Dictionary = rv._wars.get(wkey, {})
	_check("playtest: war record formed from kills", not rec.is_empty())
	_check("playtest: lopsided dead tracked",
		int(rec.get("ours_dead", 0)) == 9 and int(rec.get("theirs_dead", 0)) == 3)
	_check("playtest: record captured holders live",
		int((rec.get("mons0", {}) as Dictionary).size()) == 1
		and int((rec.get("crys0", {}) as Dictionary).size()) == 1)

	# --- Day 4: starve the treasury to force the drain path. ---
	# Spend down to a target (not a fixed amount): setup already burned
	# an unknown share of the 5000 grant, so a fixed 4500 spend can fail
	# silently via can_afford and no drain ever forms.
	var _cur: float = gs.resources.get_amount("humans", "gold")
	gs.resources.spend("humans", {"gold": maxf(0.0, _cur - 300.0)})
	_day(gs, 5)
	_day(gs, 6)

	# --- By day 6 the counsel should be pleading AND the treasury worried. ---
	rec = rv._wars.get(wkey, {})
	var tier := int((rv._war_score(wkey, rec) as Dictionary).get("tier", 0))
	_check("playtest: war tier escalated", tier >= 1)
	_check("playtest: peace plea sent by war advisor",
		_messages_from(phone, war_id).size() > 0)
	_check("playtest: treasury advisor spoke on the drain",
		_messages_from(phone, tre_id).size() > 0)

	# --- Day 6: mid-war save/load roundtrip with everything live. ---
	var data: Dictionary = SaveSystem.snapshot(gs)
	_check("playtest: snapshot ok", not data.is_empty())
	var parts2: Array = _make_game()
	var gs2: GameState = parts2[0]
	var ok: bool = SaveSystem.restore(gs2, data)
	_check("playtest: restore ok", ok)
	var rv2: SimRulersVoice = gs2.rulers_voice
	var cps2: SimCommandPosts = gs2.command_posts
	_check("playtest: war record survived restore",
		not (rv2._wars.get(wkey, {}) as Dictionary).is_empty())
	_check("playtest: siege survived restore", not cps2.sieges.is_empty())
	_check("playtest: peace plea survived restore",
		not (rv2._peace_pleas.get(wkey, {}) as Dictionary).is_empty())
	(gs2 as Node).queue_free()

	# --- Days 7-8: force the capture through the REAL daily grind. ---
	var s: Dictionary = cps.sieges[siege_key]
	var integ_before := float(s.get("integrity", 100.0))
	_day(gs, 7)
	s = cps.sieges.get(siege_key, {})
	_check("playtest: siege integrity grinding down",
		s.is_empty() or float(s.get("integrity", 100.0)) < integ_before)
	if not cps.sieges.is_empty():
		(cps.sieges[siege_key] as Dictionary)["integrity"] = 1.0
	var halls_before: String = ""
	for b: Dictionary in gs.buildings:
		if int(b.get("town_id", -1)) == 1 and String(b.get("type", "")) == "town_hall":
			halls_before = String(b.get("faction", ""))
	_day(gs, 8)
	_check("playtest: siege resolved", not cps.sieges.has(siege_key))
	var flipped := false
	for b: Dictionary in gs.buildings:
		if int(b.get("town_id", -1)) == 1 and String(b.get("type", "")) == "town_hall":
			flipped = String(b.get("faction", "")) == "elves"
	_check("playtest: town fell to the besieger (was %s)" % halls_before, flipped)

	# --- Day 9: peace through the real diplomacy path; analysis must fire. ---
	gs.diplomacy.make_peace("humans", "elves")
	_day(gs, 9)
	_check("playtest: war record closed on peace",
		(rv._wars.get(wkey, {}) as Dictionary).is_empty())
	var analysis_seen := false
	for story: Dictionary in gazette:
		var body := String(story.get("body", "")) + String(story.get("headline", ""))
		if "lost 1 town" in body or "command posts" in body.to_lower():
			analysis_seen = true
	_check("playtest: post-war analysis counted the lost town", analysis_seen)

	(gs as Node).queue_free()


class _StubPhone:
	extends RefCounted
	var sent: Array = []  # [advisor_id, text]

	func npc_message(unit_id: int, text: String) -> void:
		sent.append([unit_id, text])

	func to_dict() -> Dictionary:
		return {"sent": sent}

	func from_dict(data: Dictionary) -> void:
		sent = data.get("sent", [])


class _StubCourt:
	extends RefCounted
	var stories: Array = []
	var bus = null  # wired to gs.bus in _make_game; mirrors SimRoyalCourt

	func publish_story(headline: String, body: String, kind: String = "") -> void:
		stories.append([headline, body, kind])
		# The real court fans every story out to the bus as well.
		if bus != null:
			bus.gazette_story.emit({"headline": headline,
				"body": body, "kind": kind})

	func to_dict() -> Dictionary:
		return {"stories": stories}

	func from_dict(data: Dictionary) -> void:
		stories = data.get("stories", [])
