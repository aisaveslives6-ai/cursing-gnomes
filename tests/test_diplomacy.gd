extends SceneTree
## Cursing Gnomes — Milestone 8 headless diplomacy tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_diplomacy.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes diplomacy tests ===")
	_test_defaults()
	_test_war_declaration()
	_test_war_enables_combat()
	_test_alliance_prevents_combat()
	_test_neutral_no_combat()
	_test_monster_always_hostile()
	_test_tribute_accepted()
	_test_tribute_refused()
	_test_alliance_ai_logic()
	_test_grudge_blocks_alliance()
	_test_break_treaty_reputation()
	_test_trade_agreement()
	_test_peace()
	_test_morale_effects()
	_test_court_routing()
	_test_gazette_reports()
	_test_diplomacy_ui()
	_test_save_roundtrip()
	_test_insult_war_thresholds()
	_test_real_slur_universal_war()
	_test_real_slur_overrides_hatred()
	_test_real_slur_breaks_alliance()
	_test_fantasy_slur_pileon()
	_test_fantasy_slur_offended()
	_test_fantasy_slur_self_target()
	_test_hate_insult_pools()
	_test_slur_detection_boundaries()
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


## Fresh game + diplomacy + combat (combat NOT wired to diplomacy by
## default — each test wires it explicitly where needed).
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var dip: SimDiplomacy = gs.diplomacy
	var combat := SimCombat.new(gs)
	return {"gs": gs, "dip": dip, "combat": combat}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	return (w["gs"] as GameState).spawner.spawn_unit(faction, job, -1, pos)


## --- defaults ---------------------------------------------------------------


func _test_defaults() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	_check("default: humans/ogres neutral",
		dip.relation_state("humans", "ogres") == "neutral")
	_check("default: score zero",
		dip.relation_score("elves", "gnomes") == 0.0)
	_check("default: combat disabled (neutral)",
		not dip.combat_enabled("humans", "ogres"))
	_check("default: no combat with self",
		not dip.combat_enabled("humans", "humans"))
	_check("default: trade multiplier 1.0",
		dip.trade_multiplier("humans", "ogres") == 1.0)
	_check("default: morale 70", dip.morale_of("humans") == 70.0)
	_check("default: reputation 60", dip.reputation_of("ogres") == 60.0)
	_check("default: unknown faction neutral",
		dip.relation_state("humans", "nope") == "neutral")
	_free_world(w)


## --- war --------------------------------------------------------------------


func _test_war_declaration() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	var wars: Array = []
	gs.bus.war_declared.connect(
		func(a: String, b: String): wars.append([a, b]))
	var r: Dictionary = dip.declare_war("humans", "ogres", "testing")
	_check("war: declared ok", bool(r.get("ok", false)))
	_check("war: state war",
		dip.relation_state("humans", "ogres") == "war")
	_check("war: combat enabled",
		dip.combat_enabled("humans", "ogres"))
	_check("war: combat not enabled vs third party",
		not dip.combat_enabled("humans", "elves"))
	_check("war: signal emitted", wars.size() == 1)
	_check("war: double declaration refused",
		not bool(dip.declare_war("humans", "ogres").get("ok", true)))
	_check("war: self war refused",
		not bool(dip.declare_war("humans", "humans").get("ok", true)))
	_free_world(w)


func _test_war_enables_combat() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	var combat: SimCombat = w["combat"]
	combat.diplomacy = dip  # wire it: diplomacy now gates combat
	dip.declare_war("humans", "ogres")
	var s: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var e: Dictionary = _spawn(w, "ogres", "worker", Vector2(30, 0))
	_check("war combat: can_fight true",
		combat.can_fight("humans", "ogres"))
	# (Perf R15: idle aggro scans are staggered — allow ticks to acquire.)
	for t in range(4):
		combat.tick_unit(s, 1.0)
		if String(s.get("combat_state", "")) == "attacking":
			break
	_check("war combat: soldier engages",
		String(s.get("combat_state", "")) == "attacking")
	var _eunit: Dictionary = gs.get_unit(int(e["id"]))
	_check("war combat: enemy hurt",
		float(_eunit.get("hp", 0.0)) < float(_eunit.get("max_hp", 1.0)))
	_free_world(w)


func _test_alliance_prevents_combat() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	var combat: SimCombat = w["combat"]
	combat.diplomacy = dip
	dip.form_alliance("humans", "ogres")
	_check("alliance: state allied",
		dip.relation_state("humans", "ogres") == "allied")
	_check("alliance: combat disabled",
		not dip.combat_enabled("humans", "ogres"))
	_check("alliance: can_fight false",
		not combat.can_fight("humans", "ogres"))
	_check("alliance: trade bonus +20%",
		is_equal_approx(dip.trade_multiplier("humans", "ogres"), 1.2))
	var s: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var e: Dictionary = _spawn(w, "ogres", "worker", Vector2(30, 0))
	combat.tick_unit(s, 1.0)
	_check("alliance: no friendly fire (idle)",
		String(s.get("combat_state", "")) == "idle")
	var _aunit: Dictionary = gs.get_unit(int(e["id"]))
	_check("alliance: ally unhurt",
		float(_aunit.get("hp", 0.0)) == float(_aunit.get("max_hp", 1.0)))
	# Towers hold fire too.
	var t: Dictionary = gs.add_building({
		"type": "guard_tower", "faction": "humans", "town_id": -1,
		"position": Vector2(0, 0), "complete": true, "progress": 1.0,
		"hp": 650.0, "max_hp": 650.0,
	})
	combat.tick_towers(3.0)
	_check("alliance: tower holds fire", combat.projectiles.is_empty())
	_free_world(w)


func _test_neutral_no_combat() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	combat.diplomacy = w["dip"]
	var s: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var e: Dictionary = _spawn(w, "ogres", "worker", Vector2(30, 0))
	combat.tick_unit(s, 1.0)
	_check("neutral: soldier does not engage",
		String(s.get("combat_state", "")) == "idle")
	var _nunit: Dictionary = gs.get_unit(int(e["id"]))
	_check("neutral: stranger unhurt",
		float(_nunit.get("hp", 0.0)) == float(_nunit.get("max_hp", 1.0)))
	_free_world(w)


func _test_monster_always_hostile() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	combat.diplomacy = w["dip"]
	_check("monster: hostile to all",
		combat.can_fight("monster", "humans"))
	_check("monster: all hostile to monster",
		combat.can_fight("elves", "monster"))
	_check("monster: same faction safe",
		not combat.can_fight("humans", "humans"))
	# Legacy static fallback (no diplomacy wired): free-for-all.
	var c2 := SimCombat.new(w["gs"])
	_check("fallback: free-for-all without diplomacy",
		c2.can_fight("humans", "ogres"))
	_free_world(w)


## --- tribute ------------------------------------------------------------------


func _test_tribute_accepted() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	# Humans strong (3 soldiers), ogres weak and meek -> scared, pays.
	for i: int in range(3):
		_spawn(w, "humans", "soldier", Vector2(i * 10, 0))
	dip.set_faction_traits("ogres", {"brave": 0.1, "friendly": 0.5,
		"proud": 0.2, "diligent": 0.5, "crude": 0.5})
	gs.resources.add_resource("ogres", "gold", 100.0)
	var paid: Array = []
	gs.bus.tribute_paid.connect(
		func(f: String, t: String, r: String, a: float): paid.append(a))
	var res: Dictionary = dip.demand_tribute("humans", "ogres", "gold", 30.0)
	_check("tribute: accepted", bool(res.get("accepted", false)))
	_check("tribute: paid 30", float(res.get("paid", 0.0)) == 30.0)
	_check("tribute: ogres lost gold",
		gs.resources.get_amount("ogres", "gold") == 70.0)
	_check("tribute: humans gained gold",
		gs.resources.get_amount("humans", "gold") == 30.0)
	_check("tribute: signal emitted", paid == [30.0])
	_free_world(w)


func _test_tribute_refused() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	# Ogres proud + stronger than humans -> refuse.
	for i: int in range(5):
		_spawn(w, "ogres", "soldier", Vector2(i * 10, 0))
	_spawn(w, "humans", "soldier", Vector2(500, 0))
	dip.set_faction_traits("ogres", {"brave": 0.9, "friendly": 0.2,
		"proud": 1.0, "diligent": 0.5, "crude": 0.5})
	gs.resources.add_resource("ogres", "gold", 100.0)
	var refused: Array = []
	gs.bus.tribute_refused.connect(
		func(d: String, t: String): refused.append(d))
	var res: Dictionary = dip.demand_tribute("humans", "ogres", "gold", 30.0)
	_check("tribute: refused", not bool(res.get("accepted", true)))
	_check("tribute: nothing paid", float(res.get("paid", 1.0)) == 0.0)
	_check("tribute: gold untouched",
		gs.resources.get_amount("ogres", "gold") == 100.0)
	_check("tribute: refused signal", refused == ["humans"])
	_check("tribute: relations worsened",
		dip.relation_score("humans", "ogres") < 0.0)
	# Allies don't pay tribute, period.
	dip.form_alliance("humans", "ogres")
	var r2: Dictionary = dip.demand_tribute("humans", "ogres", "gold", 10.0)
	_check("tribute: allies exempt", not bool(r2.get("ok", true)))
	_free_world(w)


## --- alliances & AI -------------------------------------------------------------


func _test_alliance_ai_logic() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	# Friendly target + warm score -> accepts.
	dip.set_faction_traits("ogres", {"brave": 0.3, "friendly": 0.9,
		"proud": 0.2, "diligent": 0.5, "crude": 0.5})
	dip.adjust_score("humans", "ogres", 40.0)
	_check("alliance AI: friendly accepts",
		dip.ai_accepts_alliance("humans", "ogres"))
	var r: Dictionary = dip.propose_alliance("humans", "ogres")
	_check("alliance: proposal accepted", bool(r.get("accepted", false)))
	_check("alliance: state allied",
		dip.relation_state("humans", "ogres") == "allied")
	# Cold score -> refuses.
	dip.break_treaty("humans", "ogres")
	dip.adjust_score("humans", "elves", -50.0)
	_check("alliance AI: cold refuses",
		not dip.ai_accepts_alliance("humans", "elves"))
	var r2: Dictionary = dip.propose_alliance("humans", "elves")
	_check("alliance: proposal refused",
		not bool(r2.get("accepted", true)))
	# No allying mid-war.
	dip.declare_war("humans", "gnomes")
	var r3: Dictionary = dip.propose_alliance("humans", "gnomes")
	_check("alliance: refused at war", not bool(r3.get("ok", true)))
	_free_world(w)


func _test_grudge_blocks_alliance() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.set_faction_traits("ogres", {"brave": 0.3, "friendly": 1.0,
		"proud": 0.1, "diligent": 0.5, "crude": 0.5})
	# Fresh war wounds: even the friendliest target won't ally yet.
	dip.declare_war("humans", "ogres", "testing")
	dip.make_peace("humans", "ogres")
	_check("grudge: ogres resent humans",
		dip.grudge_against("ogres", "humans") < -0.5)
	dip.adjust_score("humans", "ogres", 90.0)  # sweeten all you want
	_check("grudge: blocks alliance despite warm score",
		not dip.ai_accepts_alliance("humans", "ogres"))
	_check("grudge: proposal refused",
		not bool(dip.propose_alliance("humans", "ogres").get(
			"accepted", true)))
	# Betrayal leaves its own grudge (broken oath vs signing warmth).
	dip.form_alliance("humans", "elves")
	dip.break_treaty("humans", "elves")
	_check("grudge: betrayal resented",
		dip.grudge_against("elves", "humans") < 0.0)
	_free_world(w)


func _test_break_treaty_reputation() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	var broken: Array = []
	(w["gs"] as GameState).bus.treaty_broken.connect(
		func(b: String, o: String): broken.append(b))
	dip.form_alliance("humans", "ogres")
	var rep_before: float = dip.reputation_of("humans")
	var r: Dictionary = dip.break_treaty("humans", "ogres")
	_check("break: ok", bool(r.get("ok", false)))
	_check("break: back to neutral",
		dip.relation_state("humans", "ogres") == "neutral")
	_check("break: reputation hit",
		dip.reputation_of("humans") < rep_before)
	_check("break: signal emitted", broken == ["humans"])
	_check("break: nothing to break refused",
		not bool(dip.break_treaty("humans", "elves").get("ok", true)))
	# Betraying an ally via war declaration also costs reputation.
	dip.form_alliance("humans", "gnomes")
	var rep2: float = dip.reputation_of("humans")
	dip.declare_war("humans", "gnomes", "betrayal")
	_check("break: war on ally costs reputation",
		dip.reputation_of("humans") < rep2)
	_free_world(w)


func _test_trade_agreement() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	dip.set_faction_traits("ogres", {"brave": 0.3, "friendly": 0.8,
		"proud": 0.2, "diligent": 0.5, "crude": 0.5})
	dip.adjust_score("humans", "ogres", 20.0)
	var signed: Array = []
	gs.bus.trade_signed.connect(
		func(a: String, b: String): signed.append(a))
	var r: Dictionary = dip.sign_trade_agreement("humans", "ogres", 3)
	_check("trade: accepted", bool(r.get("accepted", false)))
	_check("trade: deal active", dip.has_trade_deal("humans", "ogres"))
	_check("trade: rate improved",
		dip.trade_multiplier("humans", "ogres") > 1.0)
	_check("trade: signal emitted", signed == ["humans"])
	# Daily caravan exchange moves real resources at the improved rate.
	gs.resources.add_resource("humans", "wood", 200.0)
	gs.resources.add_resource("ogres", "gold", 200.0)
	var ow: float = gs.resources.get_amount("ogres", "wood")
	var hg: float = gs.resources.get_amount("humans", "gold")
	gs.day_number = 2
	dip.tick(0.1)
	_check("trade: caravan delivered wood to ogres",
		gs.resources.get_amount("ogres", "wood") > ow)
	_check("trade: caravan delivered gold to humans",
		gs.resources.get_amount("humans", "gold") > hg)
	# War blocks trade.
	dip.declare_war("humans", "elves")
	var r2: Dictionary = dip.sign_trade_agreement("humans", "elves")
	_check("trade: refused at war", not bool(r2.get("ok", true)))
	_free_world(w)


func _test_peace() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("humans", "ogres")
	var peaces: Array = []
	gs.bus.peace_made.connect(
		func(a: String, b: String): peaces.append(a))
	var r: Dictionary = dip.make_peace("humans", "ogres")
	_check("peace: ok", bool(r.get("ok", false)))
	_check("peace: neutral again",
		dip.relation_state("humans", "ogres") == "neutral")
	_check("peace: combat disabled",
		not dip.combat_enabled("humans", "ogres"))
	_check("peace: signal emitted", peaces == ["humans"])
	_check("peace: not-at-war refused",
		not bool(dip.make_peace("humans", "elves").get("ok", true)))
	_free_world(w)


func _test_morale_effects() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	var mh: float = dip.morale_of("humans")
	var mo: float = dip.morale_of("ogres")
	dip.declare_war("humans", "ogres")
	_check("morale: attacker drops", dip.morale_of("humans") < mh)
	_check("morale: defender drops more", dip.morale_of("ogres") < mo)
	_check("morale: defender drops most",
		dip.morale_of("ogres") < dip.morale_of("humans"))
	dip.make_peace("humans", "ogres")
	_check("morale: peace restores",
		dip.morale_of("humans") > mh - 5.0)
	dip.form_alliance("humans", "elves")
	_check("morale: alliance lifts",
		dip.morale_of("humans") > 70.0 - 1.0)
	_free_world(w)


## --- court + gazette integration --------------------------------------------------


func _court_world() -> Dictionary:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var court := SimRoyalCourt.new(gs)
	court.diplomacy = w["dip"]
	return {"gs": gs, "dip": w["dip"], "court": court}


func _test_court_routing() -> void:
	var w: Dictionary = _court_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	var court: SimRoyalCourt = w["court"]
	var u: Dictionary = _spawn(w, "ogres", "worker", Vector2(0, 0))
	# Alliance petition accepted -> real alliance in diplomacy.
	var p: Dictionary = court.petition(u, "alliance",
		"An envoy seeks alliance.", ["Accept alliance", "Refuse"])
	court.decide(int(p["id"]), 0)
	_check("court: alliance petition -> allied",
		dip.relation_state("humans", "ogres") == "allied")
	_check("court: legacy relations synced",
		court.relation_of("ogres") > 50)
	# Threat petition defied -> real war.
	var u2: Dictionary = _spawn(w, "elves", "worker", Vector2(50, 0))
	var p2: Dictionary = court.petition(u2, "threat",
		"An envoy threatens.", ["Defy them", "Pay 40 gold"])
	court.decide(int(p2["id"]), 0)
	_check("court: threat defied -> war",
		dip.relation_state("humans", "elves") == "war")
	_check("court: at_war true", court.at_war("elves"))
	# Tribute petition accepted -> real gold moves.
	gs.resources.add_resource("gnomes", "gold", 100.0)
	var u3: Dictionary = _spawn(w, "gnomes", "worker", Vector2(100, 0))
	var p3: Dictionary = court.petition(u3, "tribute",
		"An envoy offers tribute.", ["Accept tribute", "Refuse"])
	p3["tribute_amount"] = 60.0
	court.decide(int(p3["id"]), 0)
	_check("court: tribute gold arrived",
		gs.resources.get_amount("humans", "gold") == 60.0)
	_check("court: tribute gold left",
		gs.resources.get_amount("gnomes", "gold") == 40.0)
	_free_world(w)


func _test_gazette_reports() -> void:
	var w: Dictionary = _court_world()
	var dip: SimDiplomacy = w["dip"]
	var court: SimRoyalCourt = w["court"]
	(w["dip"] as SimDiplomacy).court = court
	dip.declare_war("ogres", "elves", "testing")
	dip.form_alliance("humans", "gnomes")
	var kinds: Array = []
	for s: Dictionary in court.stories:
		kinds.append(String(s.get("kind", "")))
	_check("gazette: war reported", kinds.has("war"))
	_check("gazette: alliance reported", kinds.has("court"))
	var headlines: String = " ".join(
		(court.stories.map(func(s: Dictionary) -> String:
			return String(s.get("headline", "")))))
	_check("gazette: war headline names factions",
		headlines.contains("Ogres") and headlines.contains("Elves"))
	_free_world(w)


## --- treaty UI (phone app, headless build) ------------------------------------------


func _ui_buttons(node: Node, out: Array) -> void:
	for c: Node in node.get_children():
		if c is Button:
			out.append(c)
		_ui_buttons(c, out)


func _test_diplomacy_ui() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court, dip)
	ui.open_app("diplomacy")
	_check("ui: diplomacy screen opens", ui.current_screen() == "diplomacy")
	var btns: Array = []
	_ui_buttons(ui, btns)
	var war_btn: Button = null
	var labels: Array = []
	for b: Button in btns:
		labels.append(String(b.text))
		if String(b.text).contains("Declare War") and war_btn == null:
			war_btn = b
	_check("ui: war button present", war_btn != null)
	_check("ui: alliance button present",
		labels.any(func(t: String) -> bool: return t.contains("Alliance")))
	_check("ui: trade button present",
		labels.any(func(t: String) -> bool: return t.contains("Trade Deal")))
	_check("ui: tribute button present",
		labels.any(func(t: String) -> bool: return t.contains("Tribute")))
	# Tapping Declare War shows a confirmation (first card = ogres).
	# Jeremy 2026-10-03: destructive actions need a safety gate.
	war_btn.pressed.emit()
	# Find the confirmation dialog and press "Yes, declare war".
	var confirmed := false
	for child: Node in ui.get_children():
		if child is PanelContainer:
			var c := child.get_child(0) as CenterContainer
			if c != null:
				var dlg: PanelContainer = (c.get_child(0) as PanelContainer)
				var vbox: VBoxContainer = dlg.get_child(0)
				for sub: Node in vbox.get_children():
					if sub is Button and "declare war" in String(
							(sub as Button).text).to_lower() \
							and String((sub as Button).text) != "Declare War":
						(sub as Button).pressed.emit()
						confirmed = true
						break
				break
	_check("ui: confirm dialog shown", confirmed)
	_check("ui: war declared via button",
		dip.relation_state("humans", "ogres") == "war")
	_check("ui: screen refreshed after action",
		ui.current_screen() == "diplomacy")
	ui.free()
	_free_world(w)


func _test_save_roundtrip() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("humans", "ogres")
	dip.form_alliance("elves", "gnomes")
	dip.sign_trade_agreement("elves", "gnomes", 5, true)
	dip.break_treaty("humans", "elves")  # no treaty -> no-op, stays neutral
	var data: Dictionary = dip.to_dict()
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var dip2: SimDiplomacy = gs2.diplomacy
	dip2.from_dict(data)
	_check("save: war restored",
		dip2.relation_state("humans", "ogres") == "war")
	_check("save: alliance restored",
		dip2.relation_state("elves", "gnomes") == "allied")
	_check("save: trade deal restored",
		dip2.has_trade_deal("elves", "gnomes"))
	_check("save: score restored",
		dip2.relation_score("humans", "ogres") == -80.0)
	_check("save: morale restored",
		dip2.morale_of("humans") == dip.morale_of("humans"))
	gs2.free()
	_free_world(w)


## Jeremy 2026-10-04: every faction needs more than a couple of insults
## before any war roll is even possible. Below the threshold, war is
## impossible no matter what the RNG says; gnomes never snap at all.
func _test_insult_war_thresholds() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.insult("humans", "ogres")
	_check("insult: 1st insult vs ogres cannot start war",
		dip.relation_state("humans", "ogres") != "war")
	dip.insult("humans", "ogres")
	_check("insult: 2nd insult vs ogres cannot start war",
		dip.relation_state("humans", "ogres") != "war")
	_check("insult: relationship score still damaged",
		dip.relation_score("humans", "ogres") < 0.0)
	_free_world(w)
	# Humans are fearful: 4 insults cannot start war.
	w = _new_world()
	dip = w["dip"]
	for i in 4:
		dip.insult("ogres", "humans")
	_check("insult: 4 insults vs humans cannot start war",
		dip.relation_state("ogres", "humans") != "war")
	_free_world(w)
	# Elves take a lot: 6 insults cannot start war.
	w = _new_world()
	dip = w["dip"]
	for i in 6:
		dip.insult("ogres", "elves")
	_check("insult: 6 insults vs elves cannot start war",
		dip.relation_state("ogres", "elves") != "war")
	_free_world(w)
	# Gnomes never declare war over insults — they roast you back.
	w = _new_world()
	dip = w["dip"]
	for i in 20:
		dip.insult("ogres", "gnomes")
	_check("insult: 20 insults vs gnomes never start war",
		dip.relation_state("ogres", "gnomes") != "war")
	_free_world(w)
	# At/above threshold the war roll is live: with a fixed seed, three
	# insults against ogres provokes at least one feud across 20 courts.
	seed(20261004)
	var wars: int = 0
	for i in 20:
		var w2: Dictionary = _new_world()
		var d2: SimDiplomacy = w2["dip"]
		for j in 3:
			d2.insult("humans", "ogres")
		if d2.relation_state("humans", "ogres") == "war":
			wars += 1
		_free_world(w2)
	_check("insult: 3rd insult vs ogres can provoke war (seeded)",
		wars > 0)


## Jeremy 2026-10-04: the REAL n-word (hard r) is a universal instant war
## crime — ALL five factions, including gnomes, no exceptions.
func _test_real_slur_universal_war() -> void:
	for target in ["ogres", "undead", "elves", "humans", "gnomes"]:
		var w: Dictionary = _new_world()
		var dip: SimDiplomacy = w["dip"]
		# Insulter must differ from target.
		var insulter := "ogres" if target == "humans" else "humans"
		var r: Dictionary = dip.insult(insulter, target, "you nigger")
		_check("slur: n-word vs %s declares instant war" % target,
			dip.relation_state(insulter, target) == "war")
		_check("slur: n-word vs %s returns slur flag" % target,
			bool(r.get("slur", false)))
		_check("slur: n-word vs %s tanks score to -100" % target,
			dip.relation_score(insulter, target) <= -100.0)
		_free_world(w)
	# Case-insensitive, plural, -a variant all trigger.
	for variant in ["NIGGER", "you niggers", "You Nigga"]:
		var w2: Dictionary = _new_world()
		var dip2: SimDiplomacy = w2["dip"]
		dip2.insult("humans", "ogres", variant)
		_check("slur: variant '%s' triggers war" % variant,
			dip2.relation_state("humans", "ogres") == "war")
		_free_world(w2)


## Jeremy 2026-10-04: the real n-word OVERRIDES the "enemy of my enemy"
## rule — even if they hate the targeted faction, they turn on YOU.
func _test_real_slur_overrides_hatred() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	# Ogres at war with elves — but the n-word still means war with the player.
	dip.declare_war("ogres", "elves", "test setup")
	var r: Dictionary = dip.insult("humans", "ogres", "you nigger")
	_check("slur: n-word vs ogres at war with elves still wars the player",
		dip.relation_state("humans", "ogres") == "war")
	_check("slur: n-word never piles on (no pileon flag)",
		not bool(r.get("pileon", false)))
	_free_world(w)


## The real n-word shatters alliances instantly.
func _test_real_slur_breaks_alliance() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.form_alliance("humans", "elves")
	_check("slur setup: alliance formed",
		dip.relation_state("humans", "elves") == "allied")
	dip.insult("humans", "elves", "you nigger")
	_check("slur: n-word vs ally declares instant war",
		dip.relation_state("humans", "elves") == "war")
	_free_world(w)


## Jeremy 2026-10-04: fantasy slur + "enemy of my enemy" — ogres at war with
## elves hear an anti-elf slur, pile on, and like the player MORE.
func _test_fantasy_slur_pileon() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("ogres", "elves", "test setup")
	var before: float = dip.relation_score("humans", "ogres")
	var r: Dictionary = dip.insult("humans", "ogres",
		"those knife-ears are the worst")
	_check("fantasy slur: ogres at war with elves do NOT declare war",
		dip.relation_state("humans", "ogres") != "war")
	_check("fantasy slur: pile-on flag set", bool(r.get("pileon", false)))
	_check("fantasy slur: relationship improves (enemy of my enemy)",
		dip.relation_score("humans", "ogres") > before)
	_check("fantasy slur: pile-on message mentions the insult",
		String(r.get("msg", "")).length() > 20)
	_free_world(w)
	# Hatred (not just war) also triggers pile-on: tank the score.
	var w2: Dictionary = _new_world()
	var dip2: SimDiplomacy = w2["dip"]
	dip2.adjust_score("ogres", "elves", -50.0)
	var r2: Dictionary = dip2.insult("humans", "ogres", "stupid leaf-lickers")
	_check("fantasy slur: ogres hating elves pile on (no war)",
		dip2.relation_state("humans", "ogres") != "war"
		and bool(r2.get("pileon", false)))
	_free_world(w2)


## Fantasy slur against a faction the court does NOT hate: instant war.
func _test_fantasy_slur_offended() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	# Ogres neutral toward elves — anti-elf slur offends them.
	var r: Dictionary = dip.insult("humans", "ogres",
		"those knife-ears are the worst")
	_check("fantasy slur: ogres neutral to elves declare war",
		dip.relation_state("humans", "ogres") == "war")
	_check("fantasy slur: slur flag set (no pileon)",
		bool(r.get("slur", false)) and not bool(r.get("pileon", false)))
	_free_world(w)


## Slurring the reacting faction directly: instant war, no pile-on.
func _test_fantasy_slur_self_target() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	var r: Dictionary = dip.insult("humans", "elves",
		"you knife-ears are all the same")
	_check("fantasy slur: slurring elves TO elves declares war",
		dip.relation_state("humans", "elves") == "war")
	_check("fantasy slur: self-target never piles on",
		not bool(r.get("pileon", false)))
	_free_world(w)


## Jeremy 2026-10-04: 100 hate insults per faction, all non-empty.
func _test_hate_insult_pools() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	for fac in ["ogres", "elves", "gnomes", "humans", "undead"]:
		var pool: Array = SimDiplomacy.HATE_INSULTS.get(fac, [])
		_check("hate insults: %s has 100" % fac, pool.size() == 100)
		var all_nonempty := true
		var all_have_placeholder := true
		for s in pool:
			if str(s).strip_edges().is_empty():
				all_nonempty = false
			# Most (not necessarily all) use the {enemy} placeholder.
		_check("hate insults: %s all non-empty" % fac, all_nonempty)
		# Random selection works and returns a string.
		var pick: String = str(pool.pick_random())
		_check("hate insults: %s pick_random returns text" % fac,
			not pick.is_empty())
		# Placeholder substitution works.
		var filled: String = pick.replace("{enemy}", "Elves")
		_check("hate insults: %s placeholder fills" % fac,
			not "{enemy}" in filled)
	_free_world(w)


## Slur detection uses word boundaries — no substring false positives,
## and empty text falls back to normal insult flow.
func _test_slur_detection_boundaries() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	# "snigger" contains "nigger" as a substring — must NOT trigger.
	var r: Dictionary = dip.insult("humans", "ogres",
		"I snigger at your jokes")
	_check("slur detect: 'snigger' does not trigger slur war",
		not bool(r.get("slur", false)))
	_check("slur detect: 'snigger' does not start war",
		dip.relation_state("humans", "ogres") != "war")
	_free_world(w)
	# Empty text uses the preset insult path (no slur).
	var w2: Dictionary = _new_world()
	var dip2: SimDiplomacy = w2["dip"]
	var r2: Dictionary = dip2.insult("humans", "ogres", "")
	_check("slur detect: empty text is a normal insult",
		bool(r2.get("ok", false)) and not bool(r2.get("slur", false)))
	_free_world(w2)
	# Custom non-slur text is used as the insult line.
	var w3: Dictionary = _new_world()
	var dip3: SimDiplomacy = w3["dip"]
	var r3: Dictionary = dip3.insult("humans", "ogres", "you smell like cheese")
	_check("slur detect: custom text used in message",
		"cheese" in String(r3.get("msg", "")))
	_free_world(w3)
