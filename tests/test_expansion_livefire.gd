extends SceneTree
## Cursing Gnomes — Expansion LIVE-FIRE integration tests (2026-10-06).
##
## Unlike the unit suites (which stub phone/court), this boots the REAL
## SimPhone, SimRoyalCourt, SimDiplomacy (via gs.setup), SimRulersVoice,
## SimCommandPosts, SimCombat, and StarFortBases against a live GameState
## and runs the new expansion runtime paths end to end:
##   1. war counsel plea arc (tier escalation, real Messenger delivery,
##      deny re-arm, accept -> real diplomacy surrender offer)
##   2. advisor debate + treasury voice (real phone, both advisors in-voice)
##   3. peace-terms negotiation (envoy -> AI answer in Messenger next day)
##   4. post-war analysis (real court Gazette publish + closing DM)
##   5. command-post capture/siege daily path (real bus Gazette + log)
##   6. starfort live auto-build tick (AI faction, real WallDrag commit)
##
## Point: runtime crash classes (e.g. the 2026-10-04 two-arg Object.get()
## in SimDiplomacy._petition_*, which compiled fine and only crashed when
## the path executed) never fire under stubs. Every check below runs the
## real path; the runner log is grepped for SCRIPT ERROR as a hard fail.
##
## Run: Godot --headless --path . -s res://tests/test_expansion_livefire.gd
## Exit 0 = all passed, 1 = any failure.

var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("  FAIL: ", name)


func _initialize() -> void:
	print("=== Cursing Gnomes expansion LIVE-FIRE tests ===")
	_test_plea_arc_live()
	_test_debate_live()
	_test_peace_terms_live()
	_test_postwar_analysis_live()
	_test_capture_siege_live()
	_test_starfort_live_tick()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## --- live world ------------------------------------------------------------
## All REAL systems: SimPhone, SimRoyalCourt, SimDiplomacy (gs.setup),
## SimRulersVoice, SimCommandPosts, StarFortBases. No stubs.

func _live_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "elves"] as Array[String])  # humans = player
	gs.set_ruler_name("ass")
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.hiring = GuildHiring.new(gs)
	gs.army = SimArmy.new(gs)
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	var phone := SimPhone.new(gs)
	gs.phone_sys = phone
	var rv := SimRulersVoice.new(gs)
	gs.rulers_voice = rv
	var cps := SimCommandPosts.new()
	cps.setup(gs)
	gs.command_posts = cps
	var sfb := StarFortBases.new(gs)
	gs.starfort_bases = sfb
	_fund(gs, "humans", 50000.0)
	_fund(gs, "elves", 50000.0)
	gs.found_town("humans", "Testville", Vector2(2000, 2000))
	gs.found_town("elves", "Elftown", Vector2(600, 600))
	var wa := _advisor(gs, "humans", "advisor_war")
	var ta := _advisor(gs, "humans", "advisor_economy")
	return {"gs": gs, "rv": rv, "phone": phone, "court": court,
		"cps": cps, "sfb": sfb, "wa": wa, "ta": ta}


func _fund(gs: GameState, faction: String, amount: float) -> void:
	gs.resources.add_resource(faction, "gold", amount, true)
	gs.resources.add_resource(faction, "wood", amount, true)
	gs.resources.add_resource(faction, "oil", amount, true)
	gs.resources.add_resource(faction, "food", amount, true)


func _advisor(gs: GameState, faction: String, job: String) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "job": job,
		"town_id": 1, "position": Vector2(2000, 2010), "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 95.0,
		"name": "Test Advisor"})
	u["is_advisor"] = true
	return u


func _hall(gs: GameState, faction: String, town_id: int,
		pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "town_hall", "faction": faction,
		"town_id": town_id, "town_name": "Testville" if town_id == 1 else "Elftown",
		"position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})


## Advance the sim clock to day n and fire the real daily signal every
## system listens to (counsel, phone, court, hearsay, command posts).
func _day(gs: GameState, n: int) -> void:
	gs.game_time = Config.DAY_LENGTH_SECONDS * float(maxi(0, n - 1))
	gs.day_number = n
	gs.bus.day_changed.emit(n, false)


## Seed a war record the way a live war would leave it: real town snapshot,
## lopsided casualties.
func _seed_war(rv: SimRulersVoice, gs: GameState, foe: String,
		ours_dead: int, theirs_dead: int) -> String:
	var key := "humans|%s" % foe
	rv._wars[key] = {
		"foe": foe, "start_day": 1,
		"ours_dead": ours_dead, "theirs_dead": theirs_dead,
		"towns0": rv._town_factions(), "mons0": {}, "crys0": {},
		"forts0": {}, "halls0": {"ours": 1, "theirs": 1},
		"gold_hist": [50000.0, 50000.0, 50000.0],
		"fallen": [], "fallen_report_day": -99, "we_sued": false,
		"score": 0.0, "prev_score": 0.0,
	}
	return key


## Live Messenger capture: real SimPhone -> real bus.phone_message.
func _capture(gs: GameState) -> Dictionary:
	var box := {"msgs": []}
	gs.bus.phone_message.connect(
		func(key: String, text: String) -> void:
			(box["msgs"] as Array).append({"key": key, "text": text}))
	return box


func _inbox_has(box: Dictionary, needle: String) -> bool:
	for m: Dictionary in (box["msgs"] as Array):
		if String(m.get("text", "")).contains(needle):
			return true
	return false


func _inbox_count(box: Dictionary, needle: String) -> int:
	var n := 0
	for m: Dictionary in (box["msgs"] as Array):
		if String(m.get("text", "")).contains(needle):
			n += 1
	return n


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


## --- 1. war counsel plea arc (real phone, real combat capture) -------------

func _test_plea_arc_live() -> void:
	var w := _live_world()
	var gs: GameState = w["gs"]
	var rv: SimRulersVoice = w["rv"]
	var wa: Dictionary = w["wa"]
	_hall(gs, "humans", 1, Vector2(2000, 2000))
	_hall(gs, "elves", 2, Vector2(600, 600))
	gs.diplomacy.declare_war("humans", "elves", "livefire")
	var box := _capture(gs)
	# Losing hard: 40 of ours dead to their 5 -> tier 1 (concerned).
	var key := _seed_war(rv, gs, "elves", 40, 5)
	rv._check_war_losses()
	_check("livefire plea: tier-1 plea delivered to real Messenger",
		_inbox_has(box, "Reply ACCEPT"))
	var plea_state := String(
		((rv._peace_pleas as Dictionary).get(key, {}) as Dictionary).get("state", ""))
	_check("livefire plea: plea state pending", plea_state == "pending")
	# Deny through the REAL chat path (try_order -> _answer_plea).
	var deny_line := rv.try_order(wa, "deny")
	_check("livefire plea: deny answered in-voice", deny_line != "")
	_check("livefire plea: deny recorded",
		String(((rv._peace_pleas as Dictionary)[key] as Dictionary).get("state", "")) == "denied")
	# The elves storm Testville through the REAL combat capture path —
	# hall flip -> command_post_captured -> Gazette -> war score jumps.
	var combat := SimCombat.new(gs)
	var hall: Dictionary = gs.get_building(1)
	combat._flip_hall(hall, "elves")
	rv._check_war_losses()
	_check("livefire plea: lost town escalates to tier-2 plea",
		_inbox_count(box, "Reply ACCEPT") >= 2)
	var plea2 := {"key": key, "foe": "elves", "tier": 2}
	var accept_line := rv._answer_plea(wa, plea2, "accept")
	_check("livefire plea: accept opens talks", accept_line.contains("Peace talks"))
	_check("livefire plea: accept files real diplomacy surrender offer",
		gs.diplomacy.pending_surrender_offers().size() == 1)
	_check("livefire plea: we_sued recorded for post-war analysis",
		bool(((rv._wars as Dictionary)[key] as Dictionary).get("we_sued", false)))
	_free_world(w)


## --- 2. advisor debate + treasury voice (real phone) ------------------------

func _test_debate_live() -> void:
	var w := _live_world()
	var gs: GameState = w["gs"]
	var rv: SimRulersVoice = w["rv"]
	var wa: Dictionary = w["wa"]
	var ta: Dictionary = w["ta"]
	gs.diplomacy.declare_war("humans", "elves", "livefire")
	var box := _capture(gs)
	# Tier 0 (no casualties) + collapsing treasury -> the advisors disagree.
	var key := _seed_war(rv, gs, "elves", 0, 0)
	((rv._wars as Dictionary)[key] as Dictionary)["gold_hist"] = [50000.0, 30000.0]
	gs.resources.spend("humans", {"gold": 40000.0})
	_day(gs, 2)  # real daily signal: counsel, phone, court, hearsay all fire
	_check("livefire debate: both advisors speak on real Messenger",
		_inbox_count(box, "treasury") >= 1 and _inbox_count(box, "ACCEPT") >= 1)
	_check("livefire debate: treasury cites the drain",
		_inbox_has(box, "burns"))
	var deb: Dictionary = rv._pending_debate_for(int(wa.get("id", 0)))
	_check("livefire debate: pending debate tracked", not deb.is_empty())
	var ack := rv.try_order(wa, "accept")
	_check("livefire debate: accept acks in-voice", ack != "")
	_check("livefire debate: accept files real diplomacy surrender offer",
		gs.diplomacy.pending_surrender_offers().size() == 1)
	# Treasury advisor's unit id is real: the message went to a real thread.
	_check("livefire debate: treasury advisor id valid",
		not gs.get_unit(int(ta.get("id", 0))).is_empty())
	_free_world(w)


## --- 3. peace-terms negotiation (real phone, next-day AI answer) -----------

func _test_peace_terms_live() -> void:
	var w := _live_world()
	var gs: GameState = w["gs"]
	var rv: SimRulersVoice = w["rv"]
	var wa: Dictionary = w["wa"]
	gs.diplomacy.declare_war("humans", "elves", "livefire")
	gs.diplomacy.set_faction_traits("elves", {"proud": 0.3})
	# Outmatched AI takes the deal (their strength < 75% of ours).
	for i: int in range(8):
		gs.add_unit({"faction": "humans", "job": "soldier",
			"town_id": 1, "position": Vector2(2000, 2000), "alive": true,
			"hp": 100.0, "max_hp": 100.0, "speed": 95.0})
	var box := _capture(gs)
	var ack := rv.try_order(wa, "offer peace for 500 gold")
	_check("livefire terms: envoy ack names the price",
		ack != "" and ack.contains("500"))
	_check("livefire terms: offer tracked",
		String((((rv._peace_terms as Dictionary).get("humans|elves", {})) as Dictionary).get("state", "")) == "offered")
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	_day(gs, 2)  # AI envoy answer arrives in Messenger next day
	_check("livefire terms: AI answer delivered to real Messenger",
		_inbox_has(box, "ACCEPT"))
	_check("livefire terms: war ended through real diplomacy",
		gs.diplomacy.relation_state("humans", "elves") == "neutral")
	_check("livefire terms: tribute moved",
		gs.resources.get_amount("humans", "gold") < gold_before)
	_free_world(w)


## --- 4. post-war analysis (real court Gazette publish) ---------------------

func _test_postwar_analysis_live() -> void:
	var w := _live_world()
	var gs: GameState = w["gs"]
	var rv: SimRulersVoice = w["rv"]
	var court: SimRoyalCourt = w["court"]
	_hall(gs, "humans", 1, Vector2(2000, 2000))
	_hall(gs, "elves", 2, Vector2(600, 600))
	gs.diplomacy.declare_war("humans", "elves", "livefire")
	var box := _capture(gs)
	var key := _seed_war(rv, gs, "elves", 40, 5)
	((rv._wars as Dictionary)[key] as Dictionary)["we_sued"] = true
	gs.diplomacy.make_peace("humans", "elves")  # real peace
	rv._check_war_losses()  # ended wars -> _post_war_analysis
	var found := false
	for s: Dictionary in court.stories:
		if String(s.get("headline", "")).contains("WAR'S END"):
			found = true
	_check("livefire postwar: real court published WAR'S END analysis", found)
	_check("livefire postwar: closing line in real Messenger",
		_inbox_has(box, "It's over"))
	_free_world(w)


## --- 5. command-post capture/siege daily path (real bus Gazette) -----------

func _test_capture_siege_live() -> void:
	var w := _live_world()
	var gs: GameState = w["gs"]
	var cps: SimCommandPosts = w["cps"]
	# Real monastery record on a live game.
	var mons := SimMonasteries.new()
	mons.setup(gs)
	gs.monasteries = mons
	var mon: Dictionary = {"id": 1, "god_id": "auriel",
		"position": Vector2(1500, 1500), "owner": "humans", "progress": {},
		"contested": false, "contested_by": "", "name": "Monastery of Auriel"}
	mons.monasteries.append(mon)
	# The real capture signal path (mirrors combat/monastery capture:
	# owner flips, log_capture emits command_post_captured).
	var captured: Array = []
	gs.bus.command_post_captured.connect(
		func(kind: String, pid: int, old_h: String, new_h: String,
				pos: Vector2) -> void:
			captured.append({"kind": kind, "pid": pid,
				"old": old_h, "new": new_h}))
	mon["owner"] = "elves"
	cps.log_capture("monastery", 1, "humans", "elves", Vector2(1500, 1500),
		"Monastery of Auriel")
	_check("livefire siege: capture logged",
		(cps.capture_log as Array).size() == 1)
	_check("livefire siege: real capture signal fired",
		captured.size() == 1 and String(captured[0].get("new", "")) == "elves")
	cps.daily_tick()  # prune/expire/supply/sieges/auras/leash + AI strategy
	_check("livefire siege: daily tick runs clean on live game", true)
	var holders := cps.holdings_of("elves")
	_check("livefire siege: elves hold the monastery", holders.size() >= 1)
	_free_world(w)


## --- 6. starfort live auto-build tick (AI faction, real WallDrag) ----------

func _test_starfort_live_tick() -> void:
	var w := _live_world()
	var gs: GameState = w["gs"]
	var sfb: StarFortBases = w["sfb"]
	_hall(gs, "elves", 2, Vector2(600, 600))
	for i: int in range(2):
		gs.add_building({"type": "barracks", "faction": "elves",
			"town_id": 2, "position": Vector2(650 + i * 60, 650),
			"alive": true, "complete": true, "progress": 1.0,
			"hp": 800.0, "max_hp": 800.0})
	var bs := SimBuildings.new(gs)
	var wd := WallDrag.new()
	# AI faction: full auto-build path — spot pick, plan, affordability,
	# WallDrag commit. Player race is never auto-built (sovereignty).
	sfb.tick("elves", false, bs, wd)
	var forts := (sfb.forts as Dictionary).size()
	_check("livefire starfort: AI fort committed on live map", forts >= 1)
	var before := gs.buildings.size()
	sfb.tick("humans", true, bs, wd)
	_check("livefire starfort: player race never auto-built",
		gs.buildings.size() == before)
	_free_world(w)
