extends SceneTree
## Cursing Gnomes — unemployment + surrender/truce tests (Jeremy 2026-10-04).
##
## HTML evidence (~/workspace/build-staging/fix79/index.html, searched
## 2026-10-04): "unemploy*" has NO dedicated mechanic — the 28 hits are
## flavor/joke strings ("My doves are unemployed!", "What do you call a
## sober gnome? Unemployed.") plus two code comments in the hiring roster.
## The real joblessness mechanics live in the guild system: earnWage pays
## nothing with no job or while seeking (line 33793), guildSpawnInit57
## spawns units jobless with no coins and walks them to the guild hall,
## processSeekers57 routes every jobless adult to the hall, guildAssign57
## assigns a job on arrival, rosterBestCandidate57 hires trained-first then
## seekers then the willing unemployed and NEVER hires criminals/the jailed/
## children/office-holders, stationTick57 and jobWorkRole57 give seekers no
## station work and no gathering. Surrender is a full system: surrenderTick62
## (war 12+ days, AI loser, war32Score <= -30), surrenderTribute62
## (round(gold*0.1+200) clamped 100..1500), tributeMove62, surrenderResolve62
## (accept: tribute + peace + ruler mood +10; refuse: chronicle + gazette +
## ruler mood -12; either way the offer key is marked done — never re-offered
## for that war), surrenderReply62 ("surrender yes"/"surrender no" text
## replies), offerPeace62 (player offers peace; AI accepts when score > -20,
## outmatched < 0.75x, or 25% whim; spurned = -4 relations + gazette),
## agri62Save/agri62Load persist offers+done.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_unemployment_surrender.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes unemployment/surrender tests ===")
	_test_unemployed_job_def()
	_test_lay_off()
	_test_lay_off_protects_officers()
	_test_workplace_loss_detection()
	_test_unemployed_seeks_guild_hall()
	_test_hiring_prioritizes_seekers()
	_test_hiring_excludes_criminals()
	_test_unemployed_earns_no_wages()
	_test_unemployed_keeps_urges()
	_test_truce_on_peace()
	_test_truce_blocks_war()
	_test_truce_expires()
	_test_surrender_tribute_formula()
	_test_surrender_offer()
	_test_surrender_accept()
	_test_surrender_refuse()
	_test_surrender_no_double_offer()
	_test_surrender_not_reoffered_after_refuse()
	_test_surrender_fresh_offer_new_war()
	_test_surrender_requires_war()
	_test_surrender_save_roundtrip()
	_test_surrender_done_save_roundtrip()
	_test_offer_peace_accepted()
	_test_offer_peace_spurned()
	_test_offer_peace_requires_war()
	_test_peace_offer_dm_hook()
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
	# World owns hiring (world.gd); mirror that here so the sweep exists.
	if gs.hiring == null:
		gs.hiring = GuildHiring.new(gs)
	return {"gs": gs, "dip": gs.diplomacy, "hiring": gs.hiring}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	return (w["gs"] as GameState).spawner.spawn_unit(faction, job, -1, pos)


func _place_building(w: Dictionary, btype: String, faction: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	var b := {"id": gs.buildings.size() + 1000, "type": btype,
		"faction": faction, "position": pos, "alive": true,
		"complete": true, "town_id": -1}
	gs.buildings.append(b)
	return b


## --- unemployment -----------------------------------------------------------


func _test_unemployed_job_def() -> void:
	_check("unemployed is a job", JobDefs.is_job("unemployed"))
	_check("unemployed is civilian",
		JobDefs.category("unemployed") == "civilian")
	_check("unemployed has a dot color",
		JobDefs.JOB_DOT_COLORS.has("unemployed"))


func _test_lay_off() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	var u: Dictionary = _spawn(w, "humans", "shopkeeper", Vector2(100, 100))
	u["station"] = {"job": "shopkeeper", "building_id": 999}
	hiring.lay_off(u, "testing")
	_check("lay_off sets unemployed job",
		String(u.get("job", "")) == "unemployed")
	_check("lay_off clears station", (u.get("station", {}) as Dictionary).is_empty())
	_check("lay_off is detected", hiring.is_unemployed(u))
	_check("unemployed counted", hiring.unemployed_count("humans") == 1)
	# Idempotent.
	hiring.lay_off(u)
	_check("lay_off idempotent", hiring.unemployed_count("humans") == 1)
	_free_world(w)


func _test_lay_off_protects_officers() -> void:
	var w: Dictionary = _new_world()
	var hiring: GuildHiring = w["hiring"]
	var gm: Dictionary = _spawn(w, "humans", "guild_master", Vector2(100, 100))
	(gm.get("mind", {}) as Dictionary)["gov_role"] = "guild_master"
	# Ensure mind dict exists for the gov_role check.
	if not gm.has("mind"):
		gm["mind"] = {"gov_role": "guild_master"}
	hiring.lay_off(gm)
	_check("officer not laid off",
		String(gm.get("job", "")) == "guild_master")
	_free_world(w)


func _test_workplace_loss_detection() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	var shop: Dictionary = _place_building(w, "shop", "humans", Vector2(200, 200))
	var u: Dictionary = _spawn(w, "humans", "shopkeeper", Vector2(200, 200))
	u["station"] = {"job": "shopkeeper",
		"building_id": int(shop["id"]), "spot": "counter", "act": "tending"}
	# Destroy the shop.
	shop["alive"] = false
	hiring._detect_workplace_loss()
	_check("workplace loss -> unemployed", hiring.is_unemployed(u))
	_check("station cleared on loss",
		(u.get("station", {}) as Dictionary).is_empty())
	_free_world(w)


func _test_unemployed_seeks_guild_hall() -> void:
	var w: Dictionary = _new_world()
	var hiring: GuildHiring = w["hiring"]
	var hall: Dictionary = _place_building(w, "guild_hall", "humans",
		Vector2(500, 500))
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	hiring.lay_off(u)
	hiring._update_unemployed()
	_check("seeker gets a seek target", u.has("_seek_pos"))
	var seek: Vector2 = u.get("_seek_pos", Vector2(-1, -1))
	_check("seek target near the hall",
		seek.distance_to(hall.get("position", Vector2.ZERO)) < 100.0)
	_free_world(w)


func _test_hiring_prioritizes_seekers() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	# A shop with an open cashier slot (storage hires cashiers).
	var storage: Dictionary = _place_building(w, "storage", "humans",
		Vector2(300, 300))
	# One unemployed seeker far away, one worker right next to the shop.
	var seeker: Dictionary = _spawn(w, "humans", "worker", Vector2(900, 900))
	hiring.lay_off(seeker)
	var laborer: Dictionary = _spawn(w, "humans", "worker", Vector2(305, 305))
	# Extra workers so the quota doesn't block hiring the laborer.
	for i: int in range(6):
		_spawn(w, "humans", "worker", Vector2(100 + i * 10, 100))
	hiring._hire_open_slots(12.0)
	# The seeker should be hired first despite being farther.
	_check("seeker hired into open slot",
		String(seeker.get("job", "")) == "cashier")
	_check("seeker no longer unemployed", not hiring.is_unemployed(seeker))
	_free_world(w)


func _test_unemployed_keeps_urges() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	hiring.lay_off(u)
	# Mind tick still decays urges for the unemployed. (World owns the mind
	# system; mirror that here.)
	# Perf 2026-10-05 (R14): background decay runs on a 3-slice stagger, so
	# one full stagger cycle covers it — the decay itself is unchanged.
	var mind: SimMind = SimMind.new(gs)
	mind.ensure(u)
	var e0: float = float((u["urges"] as Dictionary).get("energy", 100.0))
	for i: int in range(3):
		mind.tick_unit(u, 10.0)
	var e1: float = float((u["urges"] as Dictionary).get("energy", 100.0))
	_check("unemployed urges still decay", e1 < e0)
	_free_world(w)


## --- truce ------------------------------------------------------------------


func _test_truce_on_peace() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("humans", "ogres", "testing")
	dip.make_peace("humans", "ogres")
	_check("truce active after peace", dip.truce_active("humans", "ogres"))
	_check("truce lasts 45 days", dip.truce_days_left("humans", "ogres") == 45)
	_free_world(w)


func _test_truce_blocks_war() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("humans", "ogres", "testing")
	dip.make_peace("humans", "ogres")
	var res: Dictionary = dip.declare_war("humans", "ogres", "revenge")
	_check("war blocked during truce", not bool(res.get("ok", true)))
	_check("still neutral", dip.relation_state("humans", "ogres") == "neutral")
	# Ogres can't declare on humans either.
	var res2: Dictionary = dip.declare_war("ogres", "humans", "revenge")
	_check("war blocked both directions", not bool(res2.get("ok", true)))
	_free_world(w)


func _test_truce_expires() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("humans", "ogres", "testing")
	dip.make_peace("humans", "ogres")
	# Fast-forward 45 days.
	gs.day_number += 45
	_check("truce expired", not dip.truce_active("humans", "ogres"))
	_check("no days left", dip.truce_days_left("humans", "ogres") == 0)
	var res: Dictionary = dip.declare_war("humans", "ogres", "revenge")
	_check("war allowed after truce", bool(res.get("ok", false)))
	_free_world(w)


## --- surrender --------------------------------------------------------------


func _test_surrender_tribute_formula() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	# HTML: max(100, min(1500, round(gold * 0.1 + 200))).
	gs.resources.add_resource("ogres", "gold", 1000.0, true)
	_check("tribute formula",
		dip.surrender_tribute_amount("ogres", "humans") == 300)
	# Clamp low.
	var w2: Dictionary = _new_world()
	var dip2: SimDiplomacy = w2["dip"]
	_check("tribute floor", dip2.surrender_tribute_amount("ogres", "humans") == 200)
	_free_world(w2)
	_free_world(w)


func _test_surrender_offer() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")
	var offered: Array = []
	(w["gs"] as GameState).bus.surrender_offered.connect(
		func(l: String, _ww: String): offered.append(l))
	var res: Dictionary = dip.offer_surrender("ogres", "humans")
	_check("offer created", bool(res.get("ok", false)))
	_check("offer has tribute", int(res.get("tribute", 0)) >= 100)
	_check("offer signal fired", offered == ["ogres"])
	_check("one pending offer", dip.pending_surrender_offers().size() == 1)
	_free_world(w)


func _test_surrender_accept() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")
	gs.resources.add_resource("ogres", "gold", 2000.0, true)
	var humans_gold0: float = gs.resources.get_amount("humans", "gold")
	var accepted: Array = []
	gs.bus.surrender_accepted.connect(
		func(l: String, ww: String): accepted.append([l, ww]))
	var res: Dictionary = dip.offer_surrender("ogres", "humans")
	var r2: Dictionary = dip.resolve_surrender(String(res["offer_id"]), true)
	_check("accept ok", bool(r2.get("ok", false)))
	_check("war ended", dip.relation_state("ogres", "humans") == "neutral")
	_check("tribute moved",
		gs.resources.get_amount("humans", "gold") > humans_gold0)
	_check("truce set", dip.truce_active("ogres", "humans"))
	_check("accepted signal", accepted == [["ogres", "humans"]])
	_check("offer cleared", dip.pending_surrender_offers().is_empty())
	_free_world(w)


func _test_surrender_refuse() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")
	var res: Dictionary = dip.offer_surrender("ogres", "humans")
	var r2: Dictionary = dip.resolve_surrender(String(res["offer_id"]), false)
	_check("refuse ok", bool(r2.get("ok", false)))
	_check("war continues", dip.relation_state("ogres", "humans") == "war")
	_check("no truce on refuse", not dip.truce_active("ogres", "humans"))
	_check("offer cleared", dip.pending_surrender_offers().is_empty())
	_free_world(w)


func _test_surrender_no_double_offer() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")
	var r1: Dictionary = dip.offer_surrender("ogres", "humans")
	var r2: Dictionary = dip.offer_surrender("ogres", "humans")
	_check("first offer ok", bool(r1.get("ok", false)))
	_check("second offer blocked", not bool(r2.get("ok", true)))
	_free_world(w)


func _test_surrender_requires_war() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	var res: Dictionary = dip.offer_surrender("ogres", "humans")
	_check("no surrender without war", not bool(res.get("ok", true)))
	var res2: Dictionary = dip.offer_surrender("humans", "humans")
	_check("no self surrender", not bool(res2.get("ok", true)))
	_free_world(w)


func _test_surrender_save_roundtrip() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")
	dip.make_peace("ogres", "humans")  # sets truce
	dip.declare_war("elves", "gnomes", "testing")
	dip.offer_surrender("elves", "gnomes")
	var data: Dictionary = dip.to_dict()
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var dip2: SimDiplomacy = gs2.diplomacy
	dip2.from_dict(data)
	_check("save: truce restored", dip2.truce_active("ogres", "humans"))
	_check("save: truce days", dip2.truce_days_left("ogres", "humans") == 45)
	_check("save: offer restored",
		dip2.pending_surrender_offers().size() == 1)
	var o: Dictionary = dip2.pending_surrender_offers()[0]
	_check("save: offer parties",
		String(o.get("loser", "")) == "elves" \
		and String(o.get("winner", "")) == "gnomes")
	gs2.free()
	_free_world(w)


## --- new parity tests (Workstream B, 2026-10-04) -------------------------------


## HTML rosterBestCandidate57: criminals and the jailed are never hired.
func _test_hiring_excludes_criminals() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	var storage: Dictionary = _place_building(w, "storage", "humans",
		Vector2(300, 300))
	var crook: Dictionary = _spawn(w, "humans", "worker", Vector2(900, 900))
	hiring.lay_off(crook)
	(court.crime.ensure_rec(crook))["criminal"] = true
	var lag: Dictionary = _spawn(w, "humans", "worker", Vector2(902, 902))
	hiring.lay_off(lag)
	(court.crime.ensure_rec(lag))["jailedUntil"] = 999.0
	var clean: Dictionary = _spawn(w, "humans", "worker", Vector2(904, 904))
	hiring.lay_off(clean)
	for i: int in range(6):
		_spawn(w, "humans", "worker", Vector2(100 + i * 10, 100))
	hiring._hire_open_slots(12.0)
	_check("criminal seeker not hired", hiring.is_unemployed(crook))
	_check("jailed seeker not hired", hiring.is_unemployed(lag))
	_check("clean seeker hired", not hiring.is_unemployed(clean))
	_free_world(w)


## HTML earnWage: no job / seeking => no pay. The unemployed tick path must
## never credit coins.
func _test_unemployed_earns_no_wages() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var hiring: GuildHiring = w["hiring"]
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	hiring.lay_off(u)
	var ai: WorkerAI = WorkerAI.new(gs)
	var c0: float = float(u.get("coins", 0.0))
	for i: int in range(20):
		ai._tick_unemployed(u, 1.0)
	_check("unemployed earns no coins", float(u.get("coins", 0.0)) == c0)
	_free_world(w)


## HTML agri62State.done: a refused surrender is never re-offered for the
## same war.
func _test_surrender_not_reoffered_after_refuse() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")
	var r1: Dictionary = dip.offer_surrender("ogres", "humans")
	_check("offer ok", bool(r1.get("ok", false)))
	dip.resolve_surrender(String(r1["offer_id"]), false)
	var r2: Dictionary = dip.offer_surrender("ogres", "humans")
	_check("no re-offer after refuse", not bool(r2.get("ok", true)))
	_free_world(w)


## A NEW war between the same pair gets a fresh offer (HTML keys the done
## set per war).
func _test_surrender_fresh_offer_new_war() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")
	var r1: Dictionary = dip.offer_surrender("ogres", "humans")
	dip.resolve_surrender(String(r1["offer_id"]), false)
	dip.make_peace("ogres", "humans")
	gs.day_number += 60  # let the 45-day truce expire
	dip.declare_war("ogres", "humans", "testing again")
	var r2: Dictionary = dip.offer_surrender("ogres", "humans")
	_check("fresh offer in new war", bool(r2.get("ok", false)))
	_free_world(w)


## The answered-offer set survives save/load (HTML agri62Save/agri62Load).
func _test_surrender_done_save_roundtrip() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")
	var r1: Dictionary = dip.offer_surrender("ogres", "humans")
	dip.resolve_surrender(String(r1["offer_id"]), false)
	var data: Dictionary = dip.to_dict()
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var dip2: SimDiplomacy = gs2.diplomacy
	dip2.from_dict(data)
	var r2: Dictionary = dip2.offer_surrender("ogres", "humans")
	_check("done survives save", not bool(r2.get("ok", true)))
	gs2.free()
	_free_world(w)


## HTML offerPeace62: the crown offers peace; a non-hateful AI accepts
## (score > -20 leg), the war ends, a truce is signed.
func _test_offer_peace_accepted() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")  # score -80
	dip.adjust_score("ogres", "humans", 100.0)  # -> 20: not hateful
	var res: Dictionary = dip.offer_peace("ogres")
	_check("peace offered ok", bool(res.get("ok", false)))
	_check("peace accepted", bool(res.get("accepted", false)))
	_check("war ended", dip.relation_state("ogres", "humans") == "neutral")
	_check("truce set", dip.truce_active("ogres", "humans"))
	_free_world(w)


## HTML offerPeace62: a hateful, un-outmatched AI spurns the offer — war
## grinds on, relations -4. The 25% whim leg is pinned via the global seed.
func _test_offer_peace_spurned() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")  # score -80: hateful
	_spawn(w, "ogres", "soldier", Vector2(100, 100))
	_spawn(w, "humans", "soldier", Vector2(200, 200))  # equal strength
	var s := 1
	while s < 100000:
		seed(s)
		if randf() >= 0.25:
			break
		s += 1
	_check("found calm seed", s < 100000)
	seed(s)
	var score0: float = dip.relation_score("ogres", "humans")
	var res: Dictionary = dip.offer_peace("ogres")
	_check("peace offered ok", bool(res.get("ok", false)))
	_check("peace spurned", not bool(res.get("accepted", true)))
	_check("war continues", dip.relation_state("ogres", "humans") == "war")
	_check("spurn costs 4 points",
		is_equal_approx(dip.relation_score("ogres", "humans"), score0 - 4.0))
	_free_world(w)


## offerPeace62 requires an actual war (and a distinct target).
func _test_offer_peace_requires_war() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	var res: Dictionary = dip.offer_peace("ogres")
	_check("no peace offer without war", not bool(res.get("ok", true)))
	var res2: Dictionary = dip.offer_peace("humans")
	_check("no peace offer to self", not bool(res2.get("ok", true)))
	_free_world(w)


## HTML surrenderReply62 trigger: typing "peace offer" to a ruler runs the
## real diplomacy offer instead of flavor text.
func _test_peace_offer_dm_hook() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "humans", "testing")
	dip.adjust_score("ogres", "humans", 100.0)  # guarantee acceptance
	var reply: String = gs.faction_leaders.reply_to("ogres", "humans",
		"peace offer, please")
	_check("dm peace offer ends war",
		dip.relation_state("ogres", "humans") == "neutral")
	_check("dm reply reports outcome",
		reply.to_lower().contains("banners"))
	# No war: the ruler says so instead of pretending.
	var reply2: String = gs.faction_leaders.reply_to("elves", "humans",
		"peace offer")
	_check("dm peace offer without war refused",
		reply2.to_lower().contains("not at war"))
	_free_world(w)
