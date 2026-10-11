extends SceneTree
## Cursing Gnomes — Milestone 4 headless army & war tests.
##
## Covers the COMBAT+ARMIES domain port: downed/knockout, combat
## micro-tactics, war horn SFX, army stances, draft/muster/deploy, warlord,
## AI offensive campaigns, war-weariness collapse, war intel, conquered-hall
## keep-or-rename, faction-correct starting weapons, weaponsmith upgrades,
## and gov_role assignment for the phone's "My Government" section.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_army.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes army & war tests ===")
	_test_downed_state()
	_test_downed_civilian_dies()
	_test_bleed_out()
	_test_medic_revive()
	_test_cover_damage_mult()
	_test_firearm_parity()
	_test_war_horn()
	_test_stance_guard()
	_test_stance_auto_clears()
	_test_stance_lead()
	_test_draft()
	_test_muster()
	_test_deploy_target_priority()
	_test_warlord()
	_test_weapon_upgrade()
	_test_strength_intel()
	_test_collapse_one_sided()
	_test_collapse_mutual()
	_test_consider_war()
	_test_aggression_mods()
	_test_aggression_consider_war()
	_test_aggression_low_never()
	_test_conquest_prompt()
	_test_government()
	_test_flank_tactic()
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


## Fresh game + combat + army systems.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var combat := SimCombat.new(gs)
	var army := SimArmy.new(gs)
	army.diplomacy = gs.diplomacy
	return {"gs": gs, "combat": combat, "army": army}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


func _hall(w: Dictionary, faction: String, pos: Vector2,
		name: String = "Hall") -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({
		"type": "town_hall", "faction": faction, "town_id": -1,
		"town_name": name,
		"position": pos, "complete": true, "progress": 1.0,
		"hp": 1200.0, "max_hp": 1200.0,
	})


## --- downed / knockout -----------------------------------------------------

func _test_downed_state() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var a := _spawn(w, "humans", "soldier", Vector2(0, 0))
	var b := _spawn(w, "ogres", "soldier", Vector2(10, 0))
	combat.damage_unit(int(b["id"]), 9999.0, "humans", int(a["id"]))
	b = (w["gs"] as GameState).get_unit(int(b["id"]))
	_check("downed: fighter with attacker goes down not dead",
		bool(b.get("alive", false)) and bool(b.get("downed", false)))
	_check("downed: hp zeroed", float(b.get("hp", -1.0)) == 0.0)
	_check("downed: timer ~60s", absf(float(b.get("downed_timer", 0.0)) - 60.0) < 0.01)
	_check("downed: is_downed true", combat.is_downed(b))
	_free_world(w)


func _test_downed_civilian_dies() -> void:
	# Civilians are not knocked out — they die (matches test_combat melee).
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var a := _spawn(w, "humans", "soldier", Vector2(0, 0))
	var b := _spawn(w, "ogres", "worker", Vector2(10, 0))
	combat.damage_unit(int(b["id"]), 9999.0, "humans", int(a["id"]))
	b = (w["gs"] as GameState).get_unit(int(b["id"]))
	_check("downed: civilian dies outright",
		not bool(b.get("alive", true)) and not bool(b.get("downed", false)))
	_free_world(w)


func _test_bleed_out() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var a := _spawn(w, "humans", "soldier", Vector2(0, 0))
	var b := _spawn(w, "ogres", "soldier", Vector2(10, 0))
	combat.damage_unit(int(b["id"]), 9999.0, "humans", int(a["id"]))
	b = (w["gs"] as GameState).get_unit(int(b["id"]))
	b["downed_timer"] = 0.5
	combat.tick(1.0)
	b = (w["gs"] as GameState).get_unit(int(b["id"]))
	_check("downed: bleed-out kills when timer expires",
		not bool(b.get("alive", true)))
	_free_world(w)


func _test_medic_revive() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var a := _spawn(w, "humans", "soldier", Vector2(0, 0))
	var b := _spawn(w, "ogres", "soldier", Vector2(10, 0))
	combat.damage_unit(int(b["id"]), 9999.0, "humans", int(a["id"]))
	var doc := _spawn(w, "ogres", "doctor", Vector2(100, 0))
	var max_hp: float = float(b["max_hp"])
	combat.tick_medics(1.0)  # rush to the patient
	combat.tick_medics(1.0)  # arrive + revive
	b = (w["gs"] as GameState).get_unit(int(b["id"]))
	_check("medic: revives downed ally",
		bool(b.get("alive", false)) and not bool(b.get("downed", false)))
	_check("medic: full hp restored", absf(float(b.get("hp", 0.0)) - max_hp) < 0.01)
	doc = (w["gs"] as GameState).get_unit(int(doc["id"]))
	_check("medic: doctor moved to patient",
		(doc.get("position", Vector2.ZERO) as Vector2).distance_to(
			b.get("position", Vector2.ZERO)) < 45.0)
	_free_world(w)


## --- micro-tactics ----------------------------------------------------------

func _test_cover_damage_mult() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var a := _spawn(w, "ogres", "archer", Vector2(0, 0))
	var b := _spawn(w, "humans", "archer", Vector2(200, 0))
	b["in_cover"] = true
	# Humans archer has faction stats: hp = floor(200 * 0.85) = 170.
	var start_hp: float = float(b.get("hp", 0.0))
	combat.damage_unit(int(b["id"]), 50.0, "ogres", int(a["id"]))
	b = (w["gs"] as GameState).get_unit(int(b["id"]))
	_check("cover: damage x0.65 in cover",
		absf(float(b.get("hp", 0.0)) - (start_hp - 50.0 * 0.65)) < 0.01)
	_free_world(w)


func _test_flank_tactic() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var gs: GameState = w["gs"]
	gs.diplomacy.declare_war("humans", "ogres", "test")
	var cmd := _spawn(w, "humans", "soldier", Vector2(75, 0))
	var s := _spawn(w, "humans", "soldier", Vector2(75, 0))
	var t := _spawn(w, "ogres", "soldier", Vector2(100, 0))
	s["tactic_cmd"] = int(cmd["id"])
	s["formation_slot"] = 2  # wing 2 = right flank
	# Contact older than FIX_DURATION (2.2 s) -> the wing peels off.
	# (game_time must be positive or the negative timestamp resets contact.)
	gs.game_time = 10.0
	s["tactic_contact_t"] = gs.game_time - SimCombat.FIX_DURATION - 1.0
	# (Perf R15: idle aggro scans are staggered — allow ticks to acquire.)
	for tick_i in range(4):
		combat.tick_unit(s, 0.1)
		if String(s.get("tactic", "")) == "flank_right":
			break
	# Flank destination: target + perp*140, perp of (target - commander).
	# Jeremy 2026-10-04: 0.55x global speed multiplier — threshold relaxed.
	var dest := Vector2(100, 140)
	var d: float = (s.get("position", Vector2.ZERO) as Vector2).distance_to(dest)
	_check("tactics: old contact flanks the wing", d < 140.0
		and String(s.get("tactic", "")) == "flank_right")
	# Fresh contact -> FIX: hold the line.
	s["tactic_contact_t"] = gs.game_time
	# (Perf R15: engaged units scan every tick — tactic updates immediately.)
	combat.tick_unit(s, 0.1)
	_check("tactics: fresh contact fixes in place",
		String(s.get("tactic", "")) == "fix")
	_free_world(w)


## --- war horn ----------------------------------------------------------------

func _test_war_horn() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var gs: GameState = w["gs"]
	var hits: Array = []
	gs.bus.sfx_spatial.connect(
		func(sfx_name: String, _pos: Vector2, _vel: Vector2) -> void:
			hits.append(sfx_name))
	var a := _spawn(w, "humans", "soldier", Vector2(0, 0))
	var b := _spawn(w, "ogres", "soldier", Vector2(10, 0))
	var stats: Dictionary = SimCombat.MILITARY_STATS["soldier"]
	combat._attack(a, b, stats)
	combat._attack(a, b, stats)  # within 20s cooldown: silent
	var horns := 0
	for h in hits:
		if h == "war_horn":
			horns += 1
	_check("war_horn: first attack sounds the horn once", horns == 1)
	_free_world(w)


## --- stances ------------------------------------------------------------------

func _test_stance_guard() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var s := _spawn(w, "humans", "soldier", Vector2(0, 0))
	army.set_stance("humans", "guard")
	s = (w["gs"] as GameState).get_unit(int(s["id"]))
	_check("stance guard: troops defend", bool(s.get("defend_mode", false)))
	_check("stance guard: recorded", army.get_stance("humans") == "guard")
	_free_world(w)


func _test_stance_auto_clears() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var s := _spawn(w, "humans", "soldier", Vector2(0, 0))
	army.set_stance("humans", "guard")
	army.set_stance("humans", "auto")
	s = (w["gs"] as GameState).get_unit(int(s["id"]))
	_check("stance auto: guard orders cleared",
		(s.get("player_order", {}) as Dictionary).is_empty()
		and not bool(s.get("defend_mode", true)))
	_free_world(w)


func _test_stance_lead() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var s := _spawn(w, "humans", "soldier", Vector2(0, 0))
	_hall(w, "ogres", Vector2(500, 500), "Ogrimmar")
	army.set_stance("humans", "lead")
	s = (w["gs"] as GameState).get_unit(int(s["id"]))
	_check("stance lead: commander marches on enemy hall",
		(s.get("move_target", Vector2.INF) as Vector2).distance_to(
			Vector2(500, 500)) < 1.0)
	_free_world(w)


## --- draft / muster / deploy -----------------------------------------------------

func _test_draft() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	for i in 4:
		_spawn(w, "humans", "worker", Vector2(i * 10, 0))
	var n: int = army.draft("humans", 2)
	var soldiers := 0
	for u: Dictionary in (w["gs"] as GameState).units:
		if String(u.get("faction", "")) == "humans" \
				and String(u.get("job", "")) == "soldier":
			soldiers += 1
	_check("draft: converts civilians to soldiers", n == 2 and soldiers == 2)
	_free_world(w)


func _test_muster() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	_hall(w, "humans", Vector2(0, 0), "Home")
	_spawn(w, "humans", "soldier", Vector2(400, 0))
	_spawn(w, "humans", "soldier", Vector2(-400, 0))
	var n: int = army.muster("humans")
	var rallied := true
	for u: Dictionary in (w["gs"] as GameState).units:
		if String(u.get("job", "")) == "soldier":
			if not bool(u.get("mustering", false)):
				rallied = false
			if (u.get("move_target", Vector2.INF) as Vector2).distance_to(
					Vector2.ZERO) > 90.0:
				rallied = false
	_check("muster: field army rallies at the hall", n == 2 and rallied)
	_free_world(w)


func _test_deploy_target_priority() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	_hall(w, "humans", Vector2(0, 0), "Home")
	var s := _spawn(w, "humans", "soldier", Vector2(0, 0))
	var e := _spawn(w, "ogres", "soldier", Vector2(300, 300))
	army.deploy_for_war("humans", "ogres")
	s = (w["gs"] as GameState).get_unit(int(s["id"]))
	_check("deploy: enemy military targeted first",
		String(s.get("deploy_target_kind", "")) == "unit"
		and int(s.get("deploy_target_id", -1)) == int(e["id"]))
	_free_world(w)


## --- warlord -----------------------------------------------------------------------

func _test_warlord() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var combat: SimCombat = w["combat"]
	# Jeremy 2026-10-04 faction sovereignty: player command functions only
	# accept the player's own faction ("humans" here) — foreign factions
	# are refused by their leader. The mechanic itself is faction-agnostic.
	var s := _spawn(w, "humans", "soldier", Vector2(0, 0))
	var base_hp: float = float(s.get("max_hp", 0.0))
	var wl: Dictionary = army.promote_warlord("humans")
	_check("warlord: promotes toughest fighter", not wl.is_empty()
		and bool(wl.get("warlord", false)))
	_check("warlord: hp x2.2",
		absf(float(wl.get("max_hp", 0.0)) - base_hp * 2.2) < 0.01)
	_check("warlord: dmg x1.8",
		absf(float(wl.get("dmg_override", 0.0)) - 15.0 * 1.8) < 0.01)
	var ally := _spawn(w, "humans", "soldier", Vector2(50, 0))
	_check("warlord: aura reaches nearby allies",
		combat._warlord_nearby(ally.get("position", Vector2.ZERO), "humans",
			int(ally["id"])))
	_check("warlord: only one per faction",
		army.promote_warlord("humans").is_empty())
	_free_world(w)


## --- weapons ------------------------------------------------------------------------

func _test_firearm_parity() -> void:
	var w := _new_world()
	var s1 := _spawn(w, "ogres", "soldier", Vector2(0, 0))
	var s2 := _spawn(w, "ogres", "soldier", Vector2(10, 0))
	var h1 := _spawn(w, "humans", "soldier", Vector2(20, 0))
	_check("firearms: odd-id ogre gets blunderbuss",
		String(s1.get("firearm", "")) == "shotgun")
	_check("firearms: even-id ogre gets musket",
		String(s2.get("firearm", "")) == "basic")
	_check("firearms: humans get issue rifle",
		String(h1.get("firearm", "")) == "basic")
	_check("firearms: ogre shotgun name is Blunderbuss",
		SimCombat.firearm_name("ogres", "shotgun") == "Blunderbuss")
	_check("firearms: ogre shotgun icon",
		SimCombat.firearm_icon("ogres", "shotgun") == "💥")
	_check("firearms: human basic name is Issue Rifle",
		SimCombat.firearm_name("humans", "basic") == "Issue Rifle")
	_check("firearms: weapon level starts at 0",
		int(s1.get("weapon_level", -1)) == 0)
	_free_world(w)


func _test_weapon_upgrade() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var combat: SimCombat = w["combat"]
	var gs: GameState = w["gs"]
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	gs.resources.add_resource("humans", "wood", 1000.0, true)
	var s := _spawn(w, "humans", "soldier", Vector2(0, 0))
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	_check("upgrade: tier 1 buys", army.buy_weapon_upgrade(int(s["id"])))
	s = gs.get_unit(int(s["id"]))
	_check("upgrade: level increments", int(s.get("weapon_level", 0)) == 1)
	_check("upgrade: gold spent",
		gold_before - gs.resources.get_amount("humans", "gold") == 40.0)
	_check("upgrade: dmg mult 1.08 at level 1",
		absf(combat._weapon_dmg_mult(s) - 1.08) < 0.001)
	s["weapon_level"] = 3
	_check("upgrade: maxed out refuses", not army.buy_weapon_upgrade(int(s["id"])))
	# Broke faction cannot buy (sovereignty: tested on the player's own
	# faction so the refusal path doesn't mask the broke path).
	var s2 := _spawn(w, "humans", "soldier", Vector2(50, 0))
	gs.resources.add_resource("humans", "gold",
		-gs.resources.get_amount("humans", "gold"), true)
	gs.resources.add_resource("humans", "wood",
		-gs.resources.get_amount("humans", "wood"), true)
	_check("upgrade: no funds no sale",
		not army.buy_weapon_upgrade(int(s2["id"])))
	_free_world(w)


## --- intel / collapse / AI war ----------------------------------------------------------

func _test_strength_intel() -> void:
	# De-flaked 2026-10-11: the intel noise ratio divides two snappedf-rounded
	# values, so tiny raw scores (ogre starting census) round outside the
	# 0.7-1.4x bound on ~half of RNG rolls. Fixed seed, sim mechanics untouched.
	seed(20261011)
	var w := _new_world()
	var army: SimArmy = w["army"]
	var gs: GameState = w["gs"]
	for i in 3:
		_spawn(w, "humans", "soldier", Vector2(i * 10, 0))
	gs.add_building({"type": "guard_tower", "faction": "humans",
		"town_id": -1, "position": Vector2(0, 50), "complete": true,
		"progress": 1.0, "hp": 300.0, "max_hp": 300.0})
	var own: Dictionary = army.own_strength("humans")
	_check("intel: own mil+def score",
		int(own["mil"]) == 3 and int(own["def"]) == 1
		and absf(float(own["score"]) - 3.6) < 0.01)
	var est: Dictionary = army.estimate_strength("ogres", "humans")
	var ratio: float = float(est["score"]) / float(est["raw"])
	_check("intel: estimate noise within 0.7-1.4x", ratio >= 0.7 and ratio < 1.4)
	_free_world(w)


func _test_collapse_one_sided() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var gs: GameState = w["gs"]
	for i in 3:
		_spawn(w, "humans", "soldier", Vector2(i * 10, 0))
	gs.diplomacy.declare_war("humans", "ogres", "test")
	_check("collapse: war declared",
		gs.diplomacy.relation_state("humans", "ogres") == "war")
	var ended: Array[String] = army.collapse_tick()
	_check("collapse: broken side ends the war",
		ended.has("humans|ogres:collapse")
		and gs.diplomacy.relation_state("humans", "ogres") != "war")
	_free_world(w)


func _test_collapse_mutual() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var gs: GameState = w["gs"]
	gs.diplomacy.declare_war("elves", "gnomes", "test")
	var ended: Array[String] = army.collapse_tick()
	_check("collapse: mutual collapse when neither can fight",
		ended.has("elves|gnomes:mutual")
		and gs.diplomacy.relation_state("elves", "gnomes") != "war")
	_free_world(w)


func _test_consider_war() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var gs: GameState = w["gs"]
	for i in 6:
		_spawn(w, "ogres", "soldier", Vector2(i * 10, 0))
	# Weak, wealthy, hated target.
	for i in 2:
		gs.add_building({"type": "house", "faction": "humans", "town_id": -1,
			"position": Vector2(100 + i * 20, 0), "complete": true,
			"progress": 1.0, "hp": 200.0, "max_hp": 200.0})
	gs.diplomacy.adjust_score("ogres", "humans", -60.0)
	gs.diplomacy.set_faction_traits("ogres", {"brave": 0.9, "friendly": 0.1,
		"proud": 0.5, "diligent": 0.5, "crude": 0.9})
	_check("ai war: hateful strong AI picks its target",
		army.consider_war("ogres") == "humans")
	# Peaceful AI with no hate picks nobody.
	gs.diplomacy.set_faction_traits("elves", {"brave": 0.1, "friendly": 0.9,
		"proud": 0.3, "diligent": 0.7, "crude": 0.1})
	_check("ai war: content AI stays home", army.consider_war("elves") == "")
	_free_world(w)


## --- AI aggression settings (Jeremy co-owner design, 2026-10-03) ----------

func _test_aggression_mods() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var gs: GameState = w["gs"]
	# Default (no setting stored): HTML behavior.
	var m: Dictionary = army._aggression_mods()
	_check("aggression: default normal mods",
		bool(m["offensive"]) and int(m["min_day"]) == SimArmy.AI_WAR_MIN_DAY
		and float(m["roll"]) == 0.35 and float(m["threshold_mult"]) == 1.0)
	gs.settings = {"ai_aggression": "high"}
	m = army._aggression_mods()
	_check("aggression: high mods (day 6, 60% roll, 0.7x thresholds)",
		bool(m["offensive"]) and int(m["min_day"]) == 6
		and float(m["roll"]) == 0.60 and float(m["threshold_mult"]) == 0.7)
	gs.settings = {"ai_aggression": "low"}
	m = army._aggression_mods()
	_check("aggression: low is defensive-only", not bool(m["offensive"]))
	gs.settings = {"ai_aggression": "bogus"}
	m = army._aggression_mods()
	_check("aggression: unknown value falls back to normal",
		float(m["roll"]) == 0.35 and float(m["threshold_mult"]) == 1.0)
	_free_world(w)


func _test_aggression_consider_war() -> void:
	# Marginal-hate case: brave=0.9 ogres -> aggro 90 -> war_t -52.5 normal,
	# -36.75 high. A -50 score sits between: normal passes, high attacks.
	var w := _new_world()
	var army: SimArmy = w["army"]
	var gs: GameState = w["gs"]
	for i in 6:
		_spawn(w, "ogres", "soldier", Vector2(i * 10, 0))
	for i in 2:
		gs.add_building({"type": "house", "faction": "humans", "town_id": -1,
			"position": Vector2(100 + i * 20, 0), "complete": true,
			"progress": 1.0, "hp": 200.0, "max_hp": 200.0})
	gs.diplomacy.adjust_score("ogres", "humans", -50.0)
	gs.diplomacy.set_faction_traits("ogres", {"brave": 0.9, "friendly": 0.1,
		"proud": 0.5, "diligent": 0.5, "crude": 0.9})
	gs.settings = {"ai_aggression": "normal"}
	_check("aggression: normal AI passes on marginal hate",
		army.consider_war("ogres") == "")
	gs.settings = {"ai_aggression": "high"}
	_check("aggression: high AI takes the marginal war",
		army.consider_war("ogres") == "humans")
	_free_world(w)


func _test_aggression_low_never() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var gs: GameState = w["gs"]
	for i in 6:
		_spawn(w, "ogres", "soldier", Vector2(i * 10, 0))
	gs.diplomacy.adjust_score("ogres", "humans", -90.0)
	gs.settings = {"ai_aggression": "low"}
	gs.day_number = 9999
	army.ai_war_tick()
	var any_war := false
	for a: String in gs.active_factions:
		for b: String in gs.active_factions:
			if a != b and gs.diplomacy.relation_state(a, b) == "war":
				any_war = true
	_check("aggression: low AI declares no wars even when provoked",
		not any_war)
	_free_world(w)


## --- conquest -----------------------------------------------------------------------------

func _test_conquest_prompt() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var combat: SimCombat = w["combat"]
	_hall(w, "ogres", Vector2(500, 500), "Ogrimmar")
	_spawn(w, "humans", "soldier", Vector2(520, 520))  # within 1100 px
	var hall: Dictionary = (w["gs"] as GameState).buildings[0]
	combat.damage_building(int(hall["id"]), 99999.0, "humans")
	var pending: Dictionary = army.pending_conquest()
	_check("conquest: prompt queued when hall falls near player troops",
		not pending.is_empty() and String(pending.get("old_name", "")) == "Ogrimmar")
	_check("conquest: rename applies",
		army.resolve_conquest("Newhold") == "Newhold")
	_check("conquest: queue drained", army.pending_conquest().is_empty())
	_check("conquest: empty name keeps old name",
		army.resolve_conquest("") == "")
	_free_world(w)


## --- government / phone ----------------------------------------------------------------------

func _test_government() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	var gs: GameState = w["gs"]
	_spawn(w, "humans", "worker", Vector2(0, 0))
	_spawn(w, "humans", "worker", Vector2(10, 0))
	_spawn(w, "humans", "soldier", Vector2(20, 0))
	_spawn(w, "humans", "guard", Vector2(30, 0))
	_spawn(w, "humans", "guild_master", Vector2(40, 0))
	army.ensure_government("humans")
	var roles := {}
	for u: Dictionary in gs.units:
		var r: String = SimArmy.gov_role_of(u)
		if r != "":
			roles[r] = true
	for r in ["mayor", "adviser", "commander", "watch_captain",
			"guild_master"]:
		_check("government: %s assigned" % r, roles.has(r))
	var phone := SimPhone.new(gs)
	_check("government: phone My Government populates",
		phone.government_contacts().size() == 5)
	_free_world(w)
