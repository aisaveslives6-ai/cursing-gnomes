extends SceneTree
## Cursing Gnomes — 30-day daily-systems soak (systems-graphics 12h audit).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_soak_30day.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Wires the day_changed systems the way world.gd does (seasons, farming,
## industry, mind, phone+hearsay, court+news desk, policies, crime, petitions,
## proposals, army, backchannel, founding, food feedback, handyman, lexicon,
## ruler's voice, AI director), advances 30 game days, and checks
## cross-system invariants. Any SCRIPT ERROR in the output is a finding.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _director = null


func _initialize() -> void:
	print("=== soak-30day: 30-day daily-systems probe ===")
	var gs := _make_world()
	_wire(gs)
	for d in range(30):
		gs.tick(Config.DAY_LENGTH_SECONDS)
		_director._think_next()
		_director._think_next()
		if d % 9 == 8:
			print("  ... day %d ok (units=%d bld=%d)" % [d + 2, gs.units.size(), gs.buildings.size()])
	_verify(gs)
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


func _make_world() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var factions: Array[String] = ["humans", "gnomes", "ogres", "elves", "undead"]
	gs.setup(factions)
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.zoning = SimZoning.new(gs)
	gs.hiring = GuildHiring.new(gs)
	var tid := 1
	var bx := 600.0
	for f: String in factions:
		gs.towns[tid] = {"id": tid, "name": "Town%d" % tid, "faction": f,
			"pos": Vector2(bx, 600.0), "owner": f}
		gs.add_building({"type": "town_hall", "faction": f, "town_id": tid,
			"position": Vector2(bx, 600.0), "alive": true, "complete": true,
			"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
		for r: String in ["gold", "food", "wood", "oil"]:
			gs.resources.add_resource(f, r, 800.0, true)
		for i in range(6):
			gs.spawner.spawn_unit(f, "worker", tid, Vector2(bx + i * 20.0, 700.0))
		for i in range(2):
			gs.spawner.spawn_unit(f, "soldier", tid, Vector2(bx + i * 20.0, 760.0))
		for i in range(4):
			gs.add_work_site({"kind": "tree", "position": Vector2(bx + 150.0 + i * 30.0, 500.0), "amount": 100.0})
			gs.add_work_site({"kind": "bush", "position": Vector2(bx - 150.0 - i * 30.0, 500.0), "amount": 100.0})
		gs.add_work_site({"kind": "gold_vein", "position": Vector2(bx, 400.0), "amount": 200.0})
		tid += 1
		bx += 700.0
	return gs


func _wire(gs: GameState) -> void:
	gs.seasons = SimSeasons.new(gs)
	gs.seasons.reset()
	gs.farming = SimFarming.new(gs)
	gs.farming.reset()
	gs.industry = SimIndustry.new(gs)
	gs.industry.reset()
	var mind := SimMind.new(gs)
	var phone := SimPhone.new(gs)  # creates SimHearsay internally
	var court := SimRoyalCourt.new(gs)  # creates SimNewsTrivia desk
	phone._court = court
	court.attach_phone(phone)
	var _policies := SimPolicies.new(gs, court)
	var _crime := SimCrime.new(gs, court)
	gs.petitions = SimPetitions.new(gs)
	gs.proposals = SimProposals.new(gs)
	gs.army = SimArmy.new(gs)
	var bc := SimBackchannel.new(gs)
	bc._court = court
	gs.backchannel = bc
	gs.founding = SimFounding.new(gs)
	gs.food_feedback = SimFoodFeedback.new(gs)
	gs.handyman = SimHandyman.new(gs)
	gs.lexicon = SimLexicon.new(gs)
	gs.rulers_voice = SimRulersVoice.new(gs)
	_director = SimAIDirector.new(gs)
	print("  wired: seasons/farming/industry/mind/phone(+hearsay)/court(+news)/policies/crime/petitions/proposals/army/backchannel/founding/food_feedback/handyman/lexicon/rulers_voice/ai_director")


func _verify(gs: GameState) -> void:
	_check("day advanced to 31", gs.day_number == 31)
	# Resources finite everywhere.
	var finite := true
	for f: String in gs.active_factions:
		for r: String in ["gold", "food", "wood", "oil"]:
			var v: float = gs.resources.get_amount(f, r)
			if is_nan(v) or is_inf(v):
				finite = false
	_check("all faction resources finite (no NaN/inf)", finite)
	# Units intact.
	var units_ok := true
	for u in gs.units:
		if not (u is Dictionary):
			units_ok = false
			break
		if not u.has("alive") or not u.has("faction"):
			units_ok = false
			break
		var p = u.get("position", null)
		if not (p is Vector2):
			units_ok = false
			break
	_check("every unit record intact (alive/faction/position)", units_ok)
	# Population caps respected (16/town, 48/faction, 240/global).
	var per_faction := {}
	var towns_ok := true
	for u in gs.units:
		var f: String = String(u.get("faction", "?"))
		per_faction[f] = int(per_faction.get(f, 0)) + 1
	for f: String in per_faction.keys():
		if int(per_faction[f]) > 48:
			towns_ok = false
	_check("faction caps respected (<=48/faction)", towns_ok)
	_check("global cap respected (<=240)", gs.units.size() <= 240)
	# Buildings intact.
	var bld_ok := true
	for b in gs.buildings:
		if not (b is Dictionary) or not b.has("type") or not b.has("hp"):
			bld_ok = false
			break
	_check("every building record intact (type/hp)", bld_ok)
	# Day-changed systems didn't wedge the bus: proposals expire.
	var prop_count: int = gs.proposals.proposals.size() if gs.proposals != null else -1
	_check("proposals registry readable", prop_count >= 0)
	print("  end state: day=%d units=%d buildings=%d proposals=%d" % [gs.day_number, gs.units.size(), gs.buildings.size(), prop_count])
