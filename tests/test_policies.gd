extends SceneTree
## Cursing Gnomes — Milestone 7 headless NPC social / government / policies tests.
##
## Covers: SimPolicies (seven governments, tax, guards, anarchy, curfew,
## borders, festivals, approval/strikes/riots, elections, guild quotas,
## save round-trip), NPC blocking (block/unblock/toggle, feed filtering,
## silencing), SimHearsay (seed/spread/decay/reach-ruler, event posts),
## domestic petitions (generation + decision effects), PhoneUI policies app
## + Gazette tabs smoke.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_policies.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes policies / social tests ===")
	_test_governments()
	_test_tax_income()
	_test_tax_setter_side_effects()
	_test_guard_upkeep_and_desertion()
	_test_anarchy()
	_test_curfew_borders()
	_test_festivals()
	_test_approval_strike_riot()
	_test_elections()
	_test_quotas()
	_test_policies_save_roundtrip()
	_test_blocking()
	_test_block_ruler()
	_test_hearsay()
	_test_hearsay_reach_ruler()
	_test_event_posts()
	_test_domestic_petitions()
	_test_court_mood()
	_test_ui_smoke()
	_test_government_labels_iphone_safe()
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


## --- harness ------------------------------------------------------------------

## Fresh game + social systems. Towns use int ids (policies API is int-keyed).
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.towns[1] = {"id": 1, "name": "Town0", "faction": "humans",
		"pos": Vector2.ZERO, "owner": "humans"}
	gs.towns[2] = {"id": 2, "name": "Gnomestad", "faction": "gnomes",
		"pos": Vector2(300, 0), "owner": "gnomes"}
	for r: String in ["gold", "food", "wood"]:
		gs.resources.add_resource("humans", r, 1000.0, true)
	var mind := SimMind.new(gs)
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	return {"gs": gs, "mind": mind, "phone": phone, "court": court}


func _spawn(w: Dictionary, faction: String, job: String,
		town_id: int = 1) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, job, town_id,
		Vector2(100, 100))
	mind.ensure(u)
	return u


func _spawn_role(w: Dictionary, job: String, role: String) -> Dictionary:
	var u := _spawn(w, "humans", job)
	(u.get("mind", {}) as Dictionary)["gov_role"] = role
	return u


func _stories_of_kind(court: SimRoyalCourt, kind: String) -> Array:
	var out: Array = []
	for s: Dictionary in court.news_feed():
		if String(s.get("kind", "")) == kind:
			out.append(s)
	return out


## --- governments ---------------------------------------------------------------

func _test_governments() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	_check("court owns policies", pol != null)
	_check("seven governments", SimPolicies.GOV_ORDER.size() == 7)
	for key: String in SimPolicies.GOV_ORDER:
		_check("gov def exists: " + key, not pol.gov_def(key).is_empty())
	_check("default government is monarchy", pol.gov_key() == "monarchy")
	_check("default tax 10", int(pol.state["tax"]) == 10)
	_check("default no anarchy", not bool(pol.state["anarchy"]))
	_check("default guard none", str(pol.state["guard"]) == "none")
	_check("default borders open", str(pol.state["borders"]) == "open")
	_check("default no curfew", not bool(pol.state["curfew"]))
	_check("default approval 60", pol.approval_for(1) == 60.0)
	var gs: GameState = w["gs"]
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	_check("set government democracy", pol.set_government("democracy"))
	_check("government switched", pol.gov_key() == "democracy")
	var fee: float = 500.0 * 0.5  # monarchy policyCost 0.5
	_check("government switch charged fee",
		gs.resources.get_amount("humans", "gold") <= gold_before - fee + 0.01)
	_check("approval -12 on switch", pol.approval_for(1) == 48.0)
	_check("happiness dipped on switch", float(pol.state["happiness"]) < 62.0)
	var proclaimed := false
	for s: Dictionary in _stories_of_kind(court, "court"):
		if String(s.get("headline", "")).find("PROCLAIMED") >= 0:
			proclaimed = true
	_check("government proclamation in Gazette", proclaimed)


func _test_tax_income() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	for i: int in 10:
		_spawn(w, "humans", "worker")
	var eff: float = float(pol.gov_def().get("taxEff", 1.0))
	var expected: int = int(round(10.0 * 0.10 * 3.0 * eff))
	_check("tax income 10 workers @10pct x3 (=%d)" % expected,
		pol.projected_tax_income() == expected)
	pol.set_tax(40)
	_check("tax income scales to 40%", pol.projected_tax_income() == expected * 4)
	var gs: GameState = w["gs"]
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	pol.daily_tick()
	var delta: float = gs.resources.get_amount("humans", "gold") - gold_before
	var law_inc: int = pol.law_income()  # Jeremy 2026-10-11: licensed vice pays too
	_check("daily tick banked tax+law income (delta %.1f)" % delta,
		int(round(delta)) == expected * 4 + law_inc)


func _test_tax_setter_side_effects() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	pol.state["anarchy"] = true
	pol.state["tax"] = 0
	pol.set_tax(20)
	_check("setting tax > 0 ends anarchy", not bool(pol.state["anarchy"]))
	_check("tax set to 20", int(pol.state["tax"]) == 20)
	var decreed := false
	for s: Dictionary in _stories_of_kind(court, "court"):
		if String(s.get("headline", "")) == "TAX DECREE":
			decreed = true
	_check("tax decree posted to Gazette", decreed)
	pol.set_tax(99)
	_check("tax clamped to 40", int(pol.state["tax"]) == 40)
	pol.set_tax(-5)
	_check("tax clamped to 0", int(pol.state["tax"]) == 0)


func _test_guard_upkeep_and_desertion() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	court.attach_phone(w["phone"])
	var s := _spawn(w, "humans", "soldier")
	_check("set guard militia", pol.set_guard("militia"))
	_check("soldier volunteered as guard",
		bool((s.get("mind", {}) as Dictionary).get("is_guard", false)))
	_check("guards on duty", pol.guard_units().size() >= 1)
	pol.set_guard("professional")
	_check("professional guard got HP bonus (max_hp %.1f)"
		% float(s.get("max_hp", 0.0)), float(s.get("max_hp", 0.0)) > 100.0)
	# Broke treasury + no tax income -> desertion on the daily tick.
	gs.resources.add_resource("humans", "gold", -999999.0)
	pol.set_tax(0)
	var happ: float = float(pol.state["happiness"])
	pol.daily_tick()
	_check("guards desert when treasury empty", str(pol.state["guard"]) == "none")
	_check("happiness dipped on desertion", float(pol.state["happiness"]) < happ)
	_check("deserters stood down",
		not bool((s.get("mind", {}) as Dictionary).get("is_guard", true)))
	var deserted := false
	for st: Dictionary in _stories_of_kind(court, "court"):
		if String(st.get("headline", "")).find("DESERT") >= 0:
			deserted = true
	_check("desertion posted to Gazette", deserted)


func _test_anarchy() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	pol.set_guard("militia")
	pol.set_tax(20)
	_check("declare anarchy", pol.toggle_anarchy())
	_check("anarchy flag on", bool(pol.state["anarchy"]))
	_check("anarchy zeroes tax", int(pol.state["tax"]) == 0)
	_check("anarchy disbands guard", str(pol.state["guard"]) == "none")
	_check("no guards during anarchy", not pol.set_guard("militia"))
	_check("anarchy multiplies crime (x%.2f)" % pol.crime_pressure_mult(),
		pol.crime_pressure_mult() >= 1.7)
	_check("lift anarchy", pol.toggle_anarchy())
	_check("anarchy flag off", not bool(pol.state["anarchy"]))


func _test_curfew_borders() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	_check("impose curfew", pol.toggle_curfew())
	_check("curfew on", bool(pol.state["curfew"]))
	_check("curfew reduces crime", pol.crime_pressure_mult() < 1.0)
	_check("lift curfew", pol.toggle_curfew())
	_check("curfew off", not bool(pol.state["curfew"]))
	_check("close borders", pol.set_borders("closed"))
	_check("borders closed", str(pol.state["borders"]) == "closed")
	var closed := false
	for s: Dictionary in _stories_of_kind(court, "court"):
		if String(s.get("headline", "")) == "BORDERS CLOSED":
			closed = true
	_check("border decree posted", closed)


func _test_festivals() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	var happ: float = float(pol.state["happiness"])
	var res: String = pol.hold_festival(1)
	_check("festival held ('%s')" % res, res.find("Festival held!") == 0)
	_check("festival raised happiness", float(pol.state["happiness"]) > happ)
	_check("7-day festival cooldown", int(pol.state["festival_cd"]) == 7)
	_check("cooldown blocks second festival",
		pol.hold_festival(1).find("cooldown") >= 0)
	pol.state["festival_cd"] = 0  # schedule path also honors the cooldown
	var sres: String = pol.schedule_festival(1, 2)
	_check("festival scheduled ('%s')" % sres, sres.find("scheduled") >= 0)
	_check("one scheduled", pol.scheduled_festivals().size() == 1)
	var fid: int = int((pol.scheduled_festivals()[0] as Dictionary).get("id", 0))
	_check("festival cancelled with refund", pol.cancel_festival(fid))
	_check("schedule empty after cancel", pol.scheduled_festivals().is_empty())
	# A scheduled festival fires on its day.
	pol.state["festival_cd"] = 0
	pol.schedule_festival(1, 1)
	_check("second festival on the calendar", pol.scheduled_festivals().size() == 1)
	var h2: float = float(pol.state["happiness"])
	var gs: GameState = w["gs"]
	gs.day_number = 2
	pol.daily_tick()
	_check("scheduled festival fired (happiness %.1f -> %.1f)"
		% [h2, float(pol.state["happiness"])],
		float(pol.state["happiness"]) > h2)


func _test_approval_strike_riot() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	pol.set_approval(1, 20.0)
	pol.daily_tick()
	_check("approval <25 -> strike flag", bool(pol.state["strike"]))
	_check("work_mult 0.7 during strike",
		is_zero_approx(pol.work_mult() - 0.7))
	pol.set_approval(1, 10.0)
	(pol.state["unrest"] as Dictionary)["1"] = 0
	pol.daily_tick()
	_check("riot reset approval to 32", pol.approval_for(1) == 32.0)
	_check("riot set 5-day unrest cooldown",
		int((pol.state["unrest"] as Dictionary)["1"]) == gs.day_number + 5)
	var riot := false
	for s: Dictionary in _stories_of_kind(court, "court"):
		if String(s.get("headline", "")).find("RIOT") >= 0:
			riot = true
	_check("riot posted to Gazette", riot)


func _test_elections() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	_check("switch to democracy", pol.set_government("democracy"))
	gs.day_number = 30
	pol.daily_tick()
	_check("election day recorded", int(pol.state["election_day"]) == 30)
	var elected := false
	for s: Dictionary in _stories_of_kind(court, "court"):
		if String(s.get("headline", "")).find("ELECT") >= 0:
			elected = true
	_check("election story posted", elected)
	_check("happiness not tanked by a won election (%.1f)"
		% float(pol.state["happiness"]),
		float(pol.state["happiness"]) >= 60.0)


func _test_quotas() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	_check("default worker quota 3", pol.quota_for(1, "worker") == 3)
	_check("adjust quota up", pol.adjust_quota(1, "worker", 2))
	_check("quota raised to 5", pol.quota_for(1, "worker") == 5)
	pol.adjust_quota(1, "worker", -20)
	_check("delta clamped at -8 (quota %d)" % pol.quota_for(1, "worker"),
		pol.quota_for(1, "worker") == 0)
	for i: int in 3:
		_spawn(w, "humans", "worker")
	_check("freeze quota at headcount", pol.freeze_quota(1, "worker"))
	_check("frozen quota is 3", pol.quota_for(1, "worker") == 3)
	var rep: Dictionary = pol.quota_report(1)
	_check("quota report: full",
		str((rep.get("worker", {}) as Dictionary).get("status", "")) == "full")
	_check("quota report counts 3 workers",
		int((rep.get("worker", {}) as Dictionary).get("count", 0)) == 3)


func _test_policies_save_roundtrip() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var pol = court.policies
	pol.set_tax(30)
	pol.set_guard("militia")
	pol.toggle_curfew()
	pol.adjust_quota(1, "mage", 4)
	var d: Dictionary = pol.to_dict()
	var w2 := _new_world()
	var court2: SimRoyalCourt = w2["court"]
	court2.policies.from_dict(d)
	_check("tax survived save", int(court2.policies.state["tax"]) == 30)
	_check("guard survived save", str(court2.policies.state["guard"]) == "militia")
	_check("curfew survived save", bool(court2.policies.state["curfew"]))
	_check("quota delta survived save", court2.policies.quota_for(1, "mage") == 4)


## --- blocking -------------------------------------------------------------------

func _test_blocking() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var a := _spawn(w, "humans", "worker")
	var aid: int = int(a["id"])
	phone.add_contact(aid)
	_check("block citizen", phone.block_citizen(aid))
	_check("citizen blocked", phone.is_blocked(aid))
	_check("send to blocked returns empty", phone.send_message(aid, "hello?") == "")
	# npc_message from a blocked citizen is dropped (void — check no thread).
	phone.npc_message(aid, "hi")
	_check("npc message from blocked dropped",
		not (phone.state.get("threads", {}) as Dictionary).has("u%d" % aid))
	# Blocked author's Squabble post is hidden from the feed.
	phone.npc_post(a, "I am silenced!")
	var shown := false
	for p: Dictionary in phone.feed():
		if str(p.get("text", "")).find("silenced") >= 0:
			shown = true
	_check("blocked post hidden from feed", not shown)
	_check("unblock", phone.unblock(aid))
	_check("unblocked", not phone.is_blocked(aid))
	# Jeremy 2026-10-04: send_message is async now — check the thread
	# got the player message instead of a return value.
	phone.send_message(aid, "hello again")
	var th: Dictionary = phone._thread("u%d" % aid)
	var has_player_msg := false
	for m: Dictionary in th["messages"]:
		if String(m.get("from", "")) == "player":
			has_player_msg = true
	_check("can send after unblock", has_player_msg)
	_check("toggle blocks", phone.toggle_block(aid) and phone.is_blocked(aid))
	_check("toggle unblocks", phone.toggle_block(aid) and not phone.is_blocked(aid))


func _test_block_ruler() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var a := _spawn(w, "humans", "worker")
	var aid: int = int(a["id"])
	_check("ruler blocks citizen", phone.block_ruler(aid))
	_check("blocked", phone.is_blocked(aid))
	# Angry farewell was delivered before the block landed.
	var th: Dictionary = (phone.state.get("threads", {}) as Dictionary).get(
		"u%d" % aid, {})
	_check("farewell DM delivered before block",
		not (th.get("messages", []) as Array).is_empty())


## --- hearsay ---------------------------------------------------------------------

func _test_hearsay() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	_check("phone owns hearsay engine", hear != null)
	var a := _spawn(w, "humans", "worker")
	var b := _spawn(w, "humans", "worker")
	_check("second citizen spawned", int(b["id"]) != int(a["id"]))
	var r0: int = hear.live_rumors(40).size()
	var r: Dictionary = hear.seed_rumor("Festival was amazing!", "festival",
		"Town0", 0.9, int(a["id"]))
	# Cold-start ambient rumors (hearsay.gd seeds Day-1 gossip at _init) mean
	# a fresh world is no longer rumor-free — assert the seed added one.
	_check("rumor seeded", hear.live_rumors(40).size() == r0 + 1)
	hear._spread(r)
	_check("rumor spread to more knowers (%d)" % (r["knowers"] as Array).size(),
		(r["knowers"] as Array).size() >= 1)
	var h0: float = float(r.get("heat", 0.0))
	hear.daily_tick()
	_check("rumor decayed (%.3f -> %.3f)" % [h0, float(r.get("heat", 0.0))],
		float(r.get("heat", 0.0)) < h0)
	# Blocked NPCs neither hear nor tell.
	phone.block_citizen(int(a["id"]))
	var r2: Dictionary = hear.seed_rumor("Secret plans!", "crime", "Town0",
		0.95, int(b["id"]))
	for i: int in 30:
		hear._spread(r2)
	_check("blocked citizen never learned the rumor",
		not (r2["knowers"] as Array).has(int(a["id"])))


func _test_hearsay_reach_ruler() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	var a := _spawn(w, "humans", "worker")
	var r: Dictionary = hear.seed_rumor("War with the gnomes!", "war",
		"Town0", 1.0, int(a["id"]))
	hear._maybe_reach_ruler(r)
	_check("rumor marked reached_ruler", bool(r.get("reached_ruler", false)))
	var found := false
	for key: Variant in (phone.state.get("threads", {}) as Dictionary):
		for m: Dictionary in ((phone.state["threads"] as Dictionary)[key]
				as Dictionary).get("messages", []):
			if str(m.get("text", "")).find("War with the gnomes!") >= 0:
				found = true
	_check("hot rumor reached the ruler as a DM", found)


func _test_event_posts() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	court.attach_phone(phone)
	_spawn(w, "humans", "worker")  # someone has to post
	var hear = phone.hearsay
	var before: int = phone.feed().size()
	gs.diplomacy.declare_war("humans", "gnomes", "by royal decree")
	_check("war declaration -> Squabble post", phone.feed().size() > before)
	var warpost := false
	for p: Dictionary in phone.feed():
		if str(p.get("kind", "")) == "war":
			warpost = true
	_check("war post has war kind", warpost)
	_check("war spawned a rumor", hear.live_rumors(40).size() >= 1)
	# Festival -> Squabble flavor post.
	var b4: int = phone.feed().size()
	court.policies.hold_festival(1)
	_check("festival -> Squabble post", phone.feed().size() > b4)


## --- domestic petitions ------------------------------------------------------------

func _test_domestic_petitions() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	court.attach_phone(w["phone"])
	_spawn_role(w, "worker", "mayor")
	_spawn_role(w, "soldier", "commander")
	_spawn_role(w, "worker", "lord")
	var kinds := {}
	for d: int in 40:
		gs.day_number = d + 1
		var p: Dictionary = court.generate_domestic_petition()
		if not p.is_empty():
			kinds[String(p.get("tpl", ""))] = true
	_check("multiple domestic petition kinds generated (%d: %s)"
		% [kinds.size(), str(kinds.keys())], kinds.size() >= 2)
	# Decide one: effects apply (mayor_grain: -60 food, +happiness).
	var target := {}
	for p: Dictionary in court.open_petitions():
		if String(p.get("tpl", "")) == "mayor_grain":
			target = p
	if target.is_empty():
		for p: Dictionary in court.open_petitions():
			target = p
			break
	_check("a petition is open to decide", not target.is_empty())
	if not target.is_empty():
		var pid: int = int(target["id"])
		var food_before: float = gs.resources.get_amount("humans", "food")
		court.decide(pid, 0)
		var resolved := false
		for q: Dictionary in court.petitions:
			if int(q["id"]) == pid and bool(q.get("resolved", false)):
				resolved = true
		_check("petition resolved by decision", resolved)
		if String(target.get("tpl", "")) == "mayor_grain":
			_check("grain dole cost 60 food (%.1f -> %.1f)"
				% [food_before, gs.resources.get_amount("humans", "food")],
				gs.resources.get_amount("humans", "food") <= food_before - 60.0 + 0.01)
		_check("decided petition in history",
			court.petition_history(10).size() >= 1)


func _test_court_mood() -> void:
	var w := _new_world()
	var court: SimRoyalCourt = w["court"]
	var u := _spawn_role(w, "worker", "mayor")
	_check("default court mood 0", SimRoyalCourt.court_mood_of(u) == 0.0)
	court.bump_court_mood(u, 30.0)
	_check("mood bumped", SimRoyalCourt.court_mood_of(u) == 30.0)
	court.bump_court_mood(u, 200.0)
	_check("mood clamped at 100", SimRoyalCourt.court_mood_of(u) == 100.0)
	court.bump_court_mood(u, -300.0)
	_check("mood clamped at -100", SimRoyalCourt.court_mood_of(u) == -100.0)


## --- UI smoke -----------------------------------------------------------------------

func _test_ui_smoke() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var phone: SimPhone = w["phone"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court, null)
	_check("UI setup ok", ui.is_setup())
	_check("starts on home", ui.current_screen() == "home")
	ui.open_app("policies")
	_check("policies app opens", ui.current_screen() == "policies")
	ui.open_app("gazette")
	_check("gazette opens", ui.current_screen() == "gazette")
	ui._gaz_tab = "messages"
	ui._show_gazette()
	_check("gazette messages tab renders", ui.current_screen() == "gazette")
	ui._gaz_tab = "policies"
	ui._show_gazette()
	_check("gazette policies tab renders", ui.current_screen() == "gazette")
	# Block button present in thread view (Jeremy 2026-10-04: now a compact
	# header button, not a full-width button — search recursively).
	var a := _spawn(w, "humans", "worker")
	phone.add_contact(int(a["id"]))
	ui.open_thread("u%d" % int(a["id"]))
	var found_block := false
	var stack: Array = [ui._root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			var t: String = String((n as Button).text)
			# iPhone-safe contract: plain text, no emoji prefixes (emoji render as
			# missing-glyph boxes in the web export on iPhone).
			if t == "Block" or t == "Unblock":
				found_block = true
		for ch: Node in n.get_children():
			stack.append(ch)
	_check("block/unblock button present in thread view", found_block)
	ui.queue_free()


## iPhone-safe contract for the Policies app government picker:
## cards must show the plain government name (emoji icon prefixes render
## as missing-glyph tofu boxes in the web export on iPhone), and no label
## anywhere on the policies screen may carry an emoji/pictograph glyph.
## (Redesigned 2026-10-05: picker cards are Buttons whose names live in
## child Labels, not Button.text.)
func _test_government_labels_iphone_safe() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var phone: SimPhone = w["phone"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court, null)
	ui.open_app("policies")
	var labels: Array = []
	_collect_labels(ui._root, labels)
	var gov_names := {}
	for key: String in SimPolicies.GOV_ORDER:
		var gdef: Dictionary = SimPolicies.GOVERNMENTS.get(key, {})
		gov_names[str(gdef.get("name", ""))] = true
	var found_gov := {}
	var found_anarchy := false
	for l in labels:
		var t: String = String((l as Label).text)
		for c in t:
			# Emoji/pictographs live above U+2500; typographic chars
			# (· — − ×) are covered by the default font and stay.
			_check("no emoji glyph in policies label: " + t,
				c.unicode_at(0) <= 0x2500)
		if gov_names.has(t):
			found_gov[t] = true
		if t == "ANARCHY":
			found_anarchy = true
	_check("all 7 governments render picker cards",
		found_gov.size() == 7)
	_check("anarchy card present", found_anarchy)
	ui.queue_free()


func _collect_labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n)
	for ch: Node in n.get_children():
		_collect_labels(ch, out)
