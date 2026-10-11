extends SceneTree
## Cursing Gnomes — strategic layer tests (Jeremy 2026-10-04: "AI plays
## the game, player approves").
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_strategy.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: proposal protocol (player signal + phone loop, AI auto-resolve),
## deny cooldowns, proposal expiry, war campaign phases scout -> buildup ->
## strike, buildup telegraphing, monastery assault force scaling, monastery
## reinforcement, sue-for-peace, expand-territory, and buildup bias.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _phone_asks: Array = []
var _decided: Array = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes strategy tests ===")
	_test_player_proposal_emits_signal()
	_test_player_approve_executes()
	_test_player_deny_cooldown()
	_test_proposal_expiry()
	_test_ai_war_auto_approves()
	_test_ai_war_denies_when_weak()
	_test_no_phone_signal_for_ai()
	_test_campaign_phases()
	_test_buildup_warns_player()
	_test_monastery_assault_scales()
	_test_monastery_reinforce()
	_test_assault_one_ask_per_day()
	_test_sue_for_peace_ai()
	_test_expand_territory_ai()
	_test_major_buildup_bias()
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


## Fresh headless game: player = humans; proposals + director + monasteries
## wired like World does.
func _make_game() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.proposals = SimProposals.new(gs)
	var mons := SimMonasteries.new()
	mons.setup(gs)
	gs.monasteries = mons
	var director := SimAIDirector.new(gs)
	gs.ai_director = director
	_phone_asks.clear()
	_decided.clear()
	_stories.clear()
	gs.bus.strategic_proposal.connect(func(p: Dictionary) -> void:
		_phone_asks.append(p))
	gs.bus.strategic_proposal_decided.connect(
		func(p: Dictionary, approved: bool) -> void:
			_decided.append([p, approved]))
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void:
		_stories.append(s))
	_hall(gs, "humans", Vector2(2000, 500))
	_hall(gs, "gnomes", Vector2(1000, 1000))
	_hall(gs, "ogres", Vector2(3000, 3000))
	return [gs, director]


func _free_game(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


func _hall(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "town_hall", "faction": faction,
		"town_id": 1, "position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})


func _unit(gs: GameState, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0})


func _army(gs: GameState, faction: String, n: int, pos: Vector2) -> void:
	for i in n:
		_unit(gs, faction, "soldier", pos + Vector2(i * 7.0, 0.0))


func _rich(gs: GameState, faction: String, amt: float = 500.0) -> void:
	gs.resources.add_resource(faction, "gold", amt)
	gs.resources.add_resource(faction, "wood", amt)


func _monastery(gs: GameState, mid: int, owner: String,
		pos: Vector2) -> Dictionary:
	var m := {"id": mid, "god_id": "test_god_%d" % mid, "position": pos,
		"owner": owner, "progress": {}, "contested": false,
		"contested_by": "", "name": "Test Monastery %d" % mid}
	(gs.monasteries.monasteries as Array).append(m)
	return m


## --- Proposal protocol -------------------------------------------------------


func _test_player_proposal_emits_signal() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var p: Dictionary = gs.proposals.propose("humans",
		SimProposals.KIND_DECLARE_WAR, {"target": "ogres"})
	_check("player proposal ok", bool(p.get("ok", false)))
	_check("player proposal stays open", String(p.get("status", "")) == "open")
	_check("phone signal emitted", _phone_asks.size() == 1)
	_check("phone signal carries the proposal",
		int((_phone_asks[0] as Dictionary).get("id", -1)) == int(p.get("id", -2)))
	_check("no auto-decision for player", _decided.is_empty())
	_free_game(parts)


func _test_player_approve_executes() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var p: Dictionary = gs.proposals.propose("humans",
		SimProposals.KIND_DECLARE_WAR, {"target": "ogres"})
	var pid := int(p.get("id", -1))
	var res: Dictionary = gs.proposals.resolve_proposal(pid, true, "player")
	_check("approve ok", bool(res.get("ok", false)))
	_check("approved executes",
		String(gs.proposals.get_proposal(pid).get("status", "")) == "executed")
	_check("decision signal approved", _decided.size() == 1
		and bool(_decided[0][1]))
	# Approval authorizes the war campaign: advisers enter buildup.
	var camp: Dictionary = director._war_campaigns.get("humans", {})
	_check("approve authorizes campaign",
		String(camp.get("phase", "")) == "buildup"
		and String(camp.get("target", "")) == "ogres")
	_free_game(parts)


func _test_player_deny_cooldown() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# A scout-phase campaign is waiting on the crown's answer.
	director._war_campaigns["humans"] = {"target": "ogres", "phase": "scout",
		"phase_day": 1, "warned": false}
	var p: Dictionary = gs.proposals.propose("humans",
		SimProposals.KIND_DECLARE_WAR, {"target": "ogres"})
	var pid := int(p.get("id", -1))
	gs.proposals.resolve_proposal(pid, false, "player")
	_check("denied status",
		String(gs.proposals.get_proposal(pid).get("status", "")) == "denied")
	_check("decision signal denied", _decided.size() == 1
		and not bool(_decided[0][1]))
	# The crown said no: the campaign stands down, no re-ask.
	_check("deny drops the campaign",
		not director._war_campaigns.has("humans"))
	var again: Dictionary = gs.proposals.propose("humans",
		SimProposals.KIND_DECLARE_WAR, {"target": "ogres"})
	_check("deny arms cooldown", String(again.get("reason", "")) == "cooldown")
	_check("no second phone ask", _phone_asks.size() == 1)
	_free_game(parts)


func _test_proposal_expiry() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var p: Dictionary = gs.proposals.propose("humans",
		SimProposals.KIND_MAJOR_BUILDUP, {})
	var pid := int(p.get("id", -1))
	gs.day_number += SimProposals.PROPOSAL_TTL_DAYS
	gs.bus.day_changed.emit(gs.day_number, false)
	_check("proposal expires",
		String(gs.proposals.get_proposal(pid).get("status", "")) == "expired")
	var again: Dictionary = gs.proposals.propose("humans",
		SimProposals.KIND_MAJOR_BUILDUP, {})
	_check("expiry arms soft cooldown",
		String(again.get("reason", "")) == "cooldown")
	_free_game(parts)


## --- AI auto-resolution -------------------------------------------------------


func _test_ai_war_auto_approves() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_army(gs, "gnomes", 20, Vector2(1000, 1000))
	_army(gs, "ogres", 3, Vector2(3000, 3000))
	_rich(gs, "ogres")  # war must be worth it (HTML economic viability)
	var p: Dictionary = gs.proposals.propose("gnomes",
		SimProposals.KIND_DECLARE_WAR, {"target": "ogres"})
	_check("AI war approved+executed",
		String(p.get("status", "")) == "executed")
	var camp: Dictionary = director._war_campaigns.get("gnomes", {})
	_check("AI campaign enters buildup",
		String(camp.get("phase", "")) == "buildup")
	_free_game(parts)


func _test_ai_war_denies_when_weak() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	_army(gs, "gnomes", 2, Vector2(1000, 1000))
	_army(gs, "ogres", 20, Vector2(3000, 3000))
	var p: Dictionary = gs.proposals.propose("gnomes",
		SimProposals.KIND_DECLARE_WAR, {"target": "ogres"})
	_check("AI war denied when outmatched",
		String(p.get("status", "")) == "denied")
	var again: Dictionary = gs.proposals.propose("gnomes",
		SimProposals.KIND_DECLARE_WAR, {"target": "ogres"})
	_check("AI deny arms cooldown",
		String(again.get("reason", "")) == "cooldown")
	_free_game(parts)


func _test_no_phone_signal_for_ai() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	_army(gs, "gnomes", 20, Vector2(1000, 1000))
	_army(gs, "ogres", 3, Vector2(3000, 3000))
	_rich(gs, "ogres")
	gs.proposals.propose("gnomes", SimProposals.KIND_DECLARE_WAR,
		{"target": "ogres"})
	_check("AI factions never ring the player's phone", _phone_asks.is_empty())
	_check("AI decision still announced", _decided.size() == 1
		and bool(_decided[0][1]))
	_free_game(parts)


## --- War campaign phases --------------------------------------------------------


func _test_campaign_phases() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_army(gs, "gnomes", 20, Vector2(1000, 1000))
	_army(gs, "ogres", 3, Vector2(3000, 3000))
	_rich(gs, "ogres")
	gs.day_number = 12
	# Seed a scout-phase campaign (grudge established, watching).
	director._war_campaigns["gnomes"] = {"target": "ogres", "phase": "scout",
		"phase_day": 12, "warned": false}
	var hall: Dictionary = director._hall("gnomes")
	var st: Dictionary = director._analyze("gnomes", hall)
	# Still scouting on day 12: no attacks, no proposals.
	director._war_strategy("gnomes", st)
	var camp: Dictionary = director._war_campaigns.get("gnomes", {})
	_check("scout phase holds", String(camp.get("phase", "")) == "scout")
	_check("scout phase is quiet",
		gs.diplomacy.relation_state("gnomes", "ogres") != "war")
	# Day 14: scouting done -> declare_war proposal -> AI approves -> buildup.
	gs.day_number = 14
	director._war_strategy("gnomes", st)
	camp = director._war_campaigns.get("gnomes", {})
	_check("scout -> buildup", String(camp.get("phase", "")) == "buildup")
	_check("buildup bias set", director._has_buildup_bias("gnomes"))
	_check("no war yet during buildup",
		gs.diplomacy.relation_state("gnomes", "ogres") != "war")
	# Strength is overwhelming (20 vs 3): buildup -> strike, war declared,
	# coordinated march orders issued.
	director._war_strategy("gnomes", st)
	_check("buildup -> strike declares war",
		gs.diplomacy.relation_state("gnomes", "ogres") == "war")
	_check("campaign cleared after strike",
		not director._war_campaigns.has("gnomes"))
	var marching := 0
	var at_enemy_hall := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == "gnomes" \
				and u.has("move_target"):
			marching += 1
			var tgt: Vector2 = u.get("move_target", Vector2.INF)
			if tgt.distance_to(Vector2(3000, 3000)) < 400.0:
				at_enemy_hall += 1
	_check("strike issues march orders", marching > 0)
	_check("strike marches on the enemy hall", at_enemy_hall > 0)
	_free_game(parts)


func _test_buildup_warns_player() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_army(gs, "ogres", 5, Vector2(3000, 3000))
	_army(gs, "humans", 40, Vector2(2000, 500))  # too strong to strike
	gs.day_number = 20
	director._war_campaigns["ogres"] = {"target": "humans", "phase": "buildup",
		"phase_day": 20, "warned": false}
	var st: Dictionary = director._analyze("ogres", director._hall("ogres"))
	director._war_strategy("ogres", st)
	var camp: Dictionary = director._war_campaigns.get("ogres", {})
	_check("player warned once", bool(camp.get("warned", false)))
	_check("no premature strike",
		gs.diplomacy.relation_state("ogres", "humans") != "war")
	var warned := false
	for s: Dictionary in _stories:
		if String(s.get("headline", "")) == "SHADOW OF WAR":
			warned = true
	_check("gazette warns of the buildup", warned)
	_free_game(parts)


## --- Monasteries: the central strategic goal ----------------------------------------


func _test_monastery_assault_scales() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var m := _monastery(gs, 7, "ogres", Vector2(2500, 2500))
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	# 6 defenders near the monastery -> force = ceil(6*1.6)+3 = 13.
	_army(gs, "ogres", 6, Vector2(2500, 2500))
	_army(gs, "gnomes", 20, Vector2(1000, 1000))
	var sent: int = director.launch_monastery_assault("gnomes", 7)
	_check("assault scales with defenders", sent == 13)
	var marked := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == "gnomes" \
				and int(u.get("monastery_march", -1)) == 7:
			marked += 1
			var tgt: Vector2 = u.get("move_target", Vector2.INF)
			if tgt.distance_to(Vector2(2500, 2500)) > 200.0:
				marked = -100  # marching somewhere wrong
	_check("assault force marches on the monastery", marked == 13)
	_free_game(parts)


func _test_monastery_reinforce() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var m := _monastery(gs, 3, "gnomes", Vector2(1000, 1100))
	# 4 enemies threatening our monastery -> ceil(4*1.3)+2 = 8 defenders.
	_army(gs, "ogres", 4, Vector2(1000, 1300))
	_army(gs, "gnomes", 12, Vector2(1000, 1000))
	var st: Dictionary = director._analyze("gnomes", director._hall("gnomes"))
	director._seek_monasteries("gnomes", st)
	var reinforced := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == "gnomes" \
				and int(u.get("monastery_guard", -1)) == 3:
			reinforced += 1
	_check("threatened monastery reinforced proportionally", reinforced == 8)
	_free_game(parts)


func _test_assault_one_ask_per_day() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var m := _monastery(gs, 7, "ogres", Vector2(2500, 2500))
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_army(gs, "gnomes", 20, Vector2(1000, 1000))
	gs.day_number = 30
	director._propose_assault("gnomes", m)
	var first = gs.proposals.proposals.size()
	director._propose_assault("gnomes", m)
	_check("assault proposed once per day",
		gs.proposals.proposals.size() == first)
	_free_game(parts)


## --- Other proposal kinds --------------------------------------------------------


func _test_sue_for_peace_ai() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_army(gs, "gnomes", 2, Vector2(1000, 1000))
	_army(gs, "ogres", 20, Vector2(3000, 3000))
	var p: Dictionary = gs.proposals.propose("gnomes",
		SimProposals.KIND_SUE_FOR_PEACE, {"target": "ogres"})
	_check("losing AI sues for peace",
		String(p.get("status", "")) == "executed")
	var offers: Array = gs.diplomacy.pending_surrender_offers()
	var found := false
	for o: Dictionary in offers:
		if String(o.get("loser", "")) == "gnomes" \
				and String(o.get("winner", "")) == "ogres":
			found = true
	_check("surrender offered through diplomacy", found)
	_free_game(parts)


func _test_expand_territory_ai() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	# Population pressure: 40/48 with a funded treasury (town hall costs
	# 150 wood + 100 oil).
	for i in 40:
		_unit(gs, "gnomes", "worker", Vector2(1000, 1000))
	gs.resources.add_resource("gnomes", "gold", 800.0)
	gs.resources.add_resource("gnomes", "wood", 800.0)
	gs.resources.add_resource("gnomes", "oil", 500.0)
	var before := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == "gnomes" \
				and String(b.get("type", "")) == "town_hall":
			before += 1
	var p: Dictionary = gs.proposals.propose("gnomes",
		SimProposals.KIND_EXPAND_TERRITORY, {"position": Vector2(500, 500)})
	_check("expand approved+executed",
		String(p.get("status", "")) == "executed")
	var after := 0
	for b2: Dictionary in gs.buildings:
		if String(b2.get("faction", "")) == "gnomes" \
				and String(b2.get("type", "")) == "town_hall":
			after += 1
	_check("settlement founded on approval", after == before + 1)
	_free_game(parts)


func _test_major_buildup_bias() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var p: Dictionary = gs.proposals.propose("gnomes",
		SimProposals.KIND_MAJOR_BUILDUP, {})
	_check("wartime buildup approved",
		String(p.get("status", "")) == "executed")
	_check("buildup bias active", director._has_buildup_bias("gnomes"))
	# Bias expires on its own.
	gs.day_number += 16
	_check("buildup bias expires", not director._has_buildup_bias("gnomes"))
	_free_game(parts)
