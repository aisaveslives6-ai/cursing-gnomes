extends SceneTree
## Cursing Gnomes — AI faction director (HTML aiThink port) headless tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ai_director.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: round-robin think cadence + player skip, AI bank floors/drip,
## maneuver selection (defend/raid/eco_war/fortify/expand), siege muster +
## alarm escalation, raid march, eco-war mine contest, M-zone garrison,
## AI construction drip, strategic build queue (max 2/think on essentials,
## oil pumps on their own 1/think income lane, unfinished cap,
## house hard-gate), agri plan, training doctrine, air defenses, daily plans,
## and save/load round-trip.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes AI director tests ===")
	_test_round_robin_advisor_mode()
	_test_ai_bank()
	_test_maneuver_defend()
	_test_maneuver_raid()
	_test_maneuver_eco_war()
	_test_maneuver_fortify()
	_test_maneuver_expand()
	_test_muster_defense()
	_test_muster_alarm_escalation()
	_test_raid_march()
	_test_garrison()
	_test_build_drip()
	_test_build_queue_places()
	_test_build_queue_max_two()
	_test_build_queue_unfinished_cap()
	_test_house_hard_gate()
	_test_agri_free()
	_test_agri_seedshop()
	_test_training_workers()
	_test_training_barracks()
	_test_air_defenses_free()
	_test_air_defenses_paid()
	_test_daily_plan()
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


## Two AI factions + the player. Halls at fixed spots; map 4096x4096.
func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.zoning = SimZoning.new(gs)
	gs.hiring = GuildHiring.new(gs)
	var director := SimAIDirector.new(gs)
	_stories.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	_hall(gs, "gnomes", Vector2(1000, 1000))
	_hall(gs, "ogres", Vector2(3000, 3000))
	_hall(gs, "humans", Vector2(2000, 500))
	return [gs, director]


func _hall(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "town_hall", "faction": faction,
		"town_id": 1, "position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})


func _unit(gs: GameState, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0})


func _bld(gs: GameState, faction: String, btype: String, pos: Vector2,
		complete: bool = true) -> Dictionary:
	return gs.add_building({"type": btype, "faction": faction, "town_id": 1,
		"position": pos, "alive": true, "complete": complete,
		"progress": 1.0 if complete else 0.5,
		"hp": 500.0, "max_hp": 500.0})


func _fund(gs: GameState, faction: String, gold: float,
		wood: float) -> void:
	gs.resources.add_resource(faction, "gold", gold, true)
	gs.resources.add_resource(faction, "wood", wood, true)


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


## Live oil-pump blueprints of a faction (for the essentials-budget test).
func _pump_count(gs: GameState, faction: String) -> int:
	var n := 0
	for b: Dictionary in gs.buildings:
		if bool(b.get("alive", false)) \
				and String(b.get("faction", "")) == faction \
				and String(b.get("type", "")) == "oil_pump":
			n += 1
	return n


## Jeremy 2026-10-04 advisor mode: the player faction thinks too (round
## robin, sorted LAST like HTML's playerRace), but gets no free AI-bank
## funding — the advisers develop with real money only.
func _test_round_robin_advisor_mode() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "gnomes", 500, 500)
	_fund(gs, "humans", 500, 500)
	var h_before: float = gs.resources.get_amount("humans", "gold")
	var g_bld_before := director._count_build("gnomes", "house") \
		+ director._count_build("gnomes", "aa_tower")
	director.tick(2.8)  # one faction thinks (gnomes; the player goes last)
	# The AI acted (bank drip + buildings/training); exact gold moves with
	# spending, so activity is the signal, not the balance.
	var g_bld_after := director._count_build("gnomes", "house") \
		+ director._count_build("gnomes", "aa_tower")
	_check("think: AI faction develops", g_bld_after > g_bld_before)
	_check("advisor: player thinks last (untouched after 1 tick)",
		gs.resources.get_amount("humans", "gold") == h_before)
	director.tick(2.8)  # ogres think
	_check("advisor: player still untouched after 2 ticks",
		gs.resources.get_amount("humans", "gold") == h_before)
	director.tick(2.8)  # humans (player) think in ADVISOR MODE
	# No free AI-bank drip for the player (HTML verbatim): gold can only
	# stay flat or drop from real adviser spending.
	_check("advisor: no free bank drip for the player",
		gs.resources.get_amount("humans", "gold") <= h_before)
	# ...but the advisers DID work: buildings placed and/or training queued.
	var h_bld := director._count_build("humans", "barracks") \
		+ director._count_build("humans", "storage") \
		+ director._count_build("humans", "house") \
		+ director._count_build("humans", "aa_tower")
	var hall: Dictionary = director._hall("humans")
	var queued: int = (hall.get("train_queue", []) as Array).size()
	_check("advisor: player faction develops", h_bld >= 1 or queued >= 1)
	_free_world(parts)


func _test_ai_bank() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# Broke AI: floors kick in (gold<400 -> +150, wood<350 -> +120) + drip.
	_check("bank: starts at zero", gs.resources.get_amount("gnomes", "gold") == 0.0)
	director._ai_bank("gnomes")
	_check("bank: gold floor+drip", gs.resources.get_amount("gnomes", "gold") == 168.0)
	_check("bank: wood floor+drip", gs.resources.get_amount("gnomes", "wood") == 134.0)
	_check("bank: food drip", gs.resources.get_amount("gnomes", "food") == 4.0)
	# Funded AI: drip only.
	_fund(gs, "ogres", 1000, 1000)
	director._ai_bank("ogres")
	_check("bank: funded drip gold", gs.resources.get_amount("ogres", "gold") == 1018.0)
	_check("bank: funded drip wood", gs.resources.get_amount("ogres", "wood") == 1014.0)
	_free_world(parts)


func _test_maneuver_defend() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	for i in 4:
		_unit(gs, "ogres", "soldier", Vector2(1100 + i * 20, 1050))
	var st: Dictionary = director._analyze("gnomes", director._hall("gnomes"))
	_check("maneuver: under attack -> defend", st["maneuver"] == "defend")
	_free_world(parts)


func _test_maneuver_raid() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	for i in 12:
		_unit(gs, "gnomes", "soldier", Vector2(900 + i * 10, 900))
	var st: Dictionary = director._analyze("gnomes", director._hall("gnomes"))
	_check("maneuver: at war + strong -> raid", st["maneuver"] == "raid")
	_free_world(parts)


func _test_maneuver_eco_war() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	for i in 8:  # strong enough to skip fortify
		_unit(gs, "gnomes", "soldier", Vector2(900 + i * 10, 900))
	for i in 2:
		var vein: Vector2 = Vector2(1300 + i * 60, 1000)
		gs.add_work_site({"kind": "gold_vein", "position": vein, "amount": 150.0})
		_unit(gs, "ogres", "worker", vein + Vector2(-30, 0))  # enemy nearer
	var st: Dictionary = director._analyze("gnomes", director._hall("gnomes"))
	_check("maneuver: 2 contested veins -> eco_war", st["maneuver"] == "eco_war")
	_free_world(parts)


func _test_maneuver_fortify() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	for i in 2:  # tiny army -> fortify
		_unit(gs, "gnomes", "soldier", Vector2(900 + i * 10, 900))
	var st: Dictionary = director._analyze("gnomes", director._hall("gnomes"))
	_check("maneuver: weak army -> fortify", st["maneuver"] == "fortify")
	_free_world(parts)


func _test_maneuver_expand() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "gnomes", 500, 500)
	for i in 8:
		_unit(gs, "gnomes", "soldier", Vector2(900 + i * 10, 900))
	for i in 4:
		_unit(gs, "gnomes", "worker", Vector2(950 + i * 10, 1050))
	var st: Dictionary = director._analyze("gnomes", director._hall("gnomes"))
	_check("maneuver: healthy peacetime -> expand", st["maneuver"] == "expand")
	_free_world(parts)


func _test_muster_defense() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var s: Dictionary = _unit(gs, "gnomes", "soldier", Vector2(2000, 2000))
	_unit(gs, "ogres", "soldier", Vector2(1050, 1000))
	_unit(gs, "ogres", "soldier", Vector2(1080, 1020))
	director._think("gnomes")
	_check("muster: defend_mode set", bool(s.get("defend_mode", false)))
	var mt: Vector2 = s.get("move_target", Vector2.INF)
	_check("muster: ring move target near hall",
		mt != Vector2.INF and mt.distance_to(Vector2(1000, 1000)) < 500.0)
	_free_world(parts)


func _test_muster_alarm_escalation() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_unit(gs, "ogres", "soldier", Vector2(1050, 1000))
	_unit(gs, "ogres", "soldier", Vector2(1080, 1020))
	director._think("gnomes")
	_check("alarm: gazette on escalation", _stories.size() >= 1)
	var n := _stories.size()
	director._think("gnomes")  # same threat level: no re-alarm
	_check("alarm: no repeat without escalation", _stories.size() == n)
	_free_world(parts)


func _test_raid_march() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var troops := []
	for i in 12:
		troops.append(_unit(gs, "gnomes", "soldier", Vector2(900 + i * 10, 900)))
	director._think("gnomes")
	var marched := 0
	for t: Dictionary in troops:
		var mt: Vector2 = t.get("move_target", Vector2.INF)
		if mt != Vector2.INF and mt.distance_to(Vector2(3000, 3000)) < 400.0:
			marched += 1
	_check("raid: troops march on enemy hall", marched >= 10)
	_free_world(parts)


func _test_garrison() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.zones.append({"id": 1, "type": "M", "faction": "gnomes",
		"position": Vector2(1400, 1400)})
	for i in 8:
		_unit(gs, "gnomes", "soldier", Vector2(900 + i * 10, 900))
	_fund(gs, "gnomes", 500, 500)
	var st: Dictionary = director._analyze("gnomes", director._hall("gnomes"))
	_check("garrison: maneuver not raid/defend",
		st["maneuver"] != "raid" and st["maneuver"] != "defend")
	director._garrison("gnomes", st)
	var held := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		var mt: Vector2 = u.get("move_target", Vector2.INF)
		if mt != Vector2.INF and mt.distance_to(Vector2(1400, 1400)) < 200.0:
			held += 1
	_check("garrison: idle troops hold the fort", held >= 6)
	_free_world(parts)


func _test_build_drip() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var b: Dictionary = _bld(gs, "gnomes", "barracks", Vector2(1200, 1200), false)
	director._ai_build_drip("gnomes")
	_check("drip: progress advances",
		absf(float(b.get("progress", 0.0)) - 0.58) < 0.001)
	b["progress"] = 0.96
	director._ai_build_drip("gnomes")
	_check("drip: completes at 1.0", bool(b.get("complete", false)))
	_free_world(parts)


func _test_build_queue_places() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "gnomes", 2000, 2000)
	for i in 8:
		_unit(gs, "gnomes", "soldier", Vector2(900 + i * 10, 900))
	for i in 4:
		_unit(gs, "gnomes", "worker", Vector2(950 + i * 10, 1050))
	var before := gs.buildings.size()
	director._think("gnomes")
	var placed := gs.buildings.size() - before
	_check("queue: places buildings", placed >= 1)
	# (max-2 applies to _build_essentials alone; _think also runs the
	# agri plan, training doctrine, and air defenses — covered separately)
	_free_world(parts)


func _test_build_queue_max_two() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "gnomes", 99999, 99999)
	for i in 8:
		_unit(gs, "gnomes", "soldier", Vector2(900 + i * 10, 900))
	for i in 4:
		_unit(gs, "gnomes", "worker", Vector2(950 + i * 10, 1050))
	var before := gs.buildings.size()
	var before_pump := _pump_count(gs, "gnomes")
	director._build_essentials("gnomes", director._hall("gnomes"),
		director._analyze("gnomes", director._hall("gnomes")))
	var placed := gs.buildings.size() - before
	var placed_pump := _pump_count(gs, "gnomes") - before_pump
	# Jeremy 2026-10-08: oil pumps ride outside the 2/think essentials
	# budget — they are income infrastructure (the faction's only oil
	# source), capped at 1/think by the single queue entry. The essentials
	# hard cap still holds: no construction spam beyond it.
	_check("queue: hard cap 2 on essentials even when rich",
		placed - placed_pump <= 2)
	_check("queue: at most 1 pump per think", placed_pump <= 1)
	_free_world(parts)


func _test_build_queue_unfinished_cap() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "gnomes", 99999, 99999)
	for i in 8:
		_bld(gs, "gnomes", "house", Vector2(1200 + i * 30, 1200), false)
	var before := gs.buildings.size()
	var before_pump := _pump_count(gs, "gnomes")
	director._build_essentials("gnomes", director._hall("gnomes"),
		director._analyze("gnomes", director._hall("gnomes")))
	var placed := gs.buildings.size() - before
	var placed_pump := _pump_count(gs, "gnomes") - before_pump
	# Jeremy 2026-10-08: the unfinished cap still paces construction, but
	# oil pumps (the faction's only oil income) bypass it — a busy early
	# think could otherwise starve the pump queue indefinitely while the
	# starting oil burned away.
	_check("queue: blocked at 8 unfinished (non-pump)",
		placed - placed_pump == 0)
	_check("queue: income pump bypasses the unfinished cap",
		placed_pump == 1)
	_free_world(parts)


func _test_house_hard_gate() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# 2 houses = 10 beds for a tiny pop: no house should queue.
	for i in 2:
		_bld(gs, "gnomes", "house", Vector2(500 + i * 25, 500))
	_check("houses: no demand", not director._needs_more_housing("gnomes"))
	# 30 homeless units: demand appears.
	for i in 30:
		_unit(gs, "gnomes", "worker", Vector2(900 + i * 5, 900))
	_check("houses: demand detected", director._needs_more_housing("gnomes"))
	_free_world(parts)


func _test_agri_free() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	director._agri("gnomes", director._hall("gnomes"))
	_check("agri: farm placed free", director._count_build("gnomes", "farm") >= 1)
	_check("agri: costs nothing", gs.resources.get_amount("gnomes", "gold") == 0.0)
	_free_world(parts)


func _test_agri_seedshop() -> void:
	# 2026-10-05 launch-readiness: the AI agri plan ends with one seedshop
	# per town, so the shop buy/restock economy runs for AI factions too.
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_bld(gs, "gnomes", "farm", Vector2(600, 600))
	_bld(gs, "gnomes", "farm", Vector2(650, 600))
	_bld(gs, "gnomes", "farmhouse", Vector2(700, 600))
	_bld(gs, "gnomes", "windmill", Vector2(750, 600))
	director._agri("gnomes", director._hall("gnomes"))
	_check("agri: seedshop placed after food plan",
		director._count_build("gnomes", "seedshop") >= 1)
	_free_world(parts)


func _test_training_workers() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "gnomes", 2000, 2000)
	var w1 := _unit(gs, "gnomes", "worker", Vector2(950, 1050))
	var w2 := _unit(gs, "gnomes", "worker", Vector2(960, 1050))
	# Jeremy 2026-10-04: population control — two idle workers means the
	# faction does NOT need another one trained.
	director._think("gnomes")
	var hall: Dictionary = director._hall("gnomes")
	var q: Array = hall.get("train_queue", [])
	var has_worker := false
	for job: Dictionary in q:
		if String(job.get("unit_type", "")) == "worker":
			has_worker = true
	_check("train: idle workers block new worker training", not has_worker)
	# Busy hands don't block — the faction still needs workers.
	w1["work_state"] = "gathering"
	w2["work_state"] = "gathering"
	hall["train_queue"] = []
	director._think("gnomes")
	q = hall.get("train_queue", [])
	has_worker = false
	for job: Dictionary in q:
		if String(job.get("unit_type", "")) == "worker":
			has_worker = true
	_check("train: hall queues workers when hands are busy", has_worker)
	_free_world(parts)
	_free_world(parts)


func _test_training_barracks() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "gnomes", 2000, 2000)
	var br: Dictionary = _bld(gs, "gnomes", "barracks", Vector2(1200, 1200))
	_unit(gs, "gnomes", "soldier", Vector2(900, 900))
	director._think("gnomes")
	var q: Array = br.get("train_queue", [])
	_check("train: barracks queues roster", q.size() >= 1)
	_free_world(parts)


func _test_air_defenses_free() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	director._air_defenses("gnomes", director._hall("gnomes"))
	_check("AA: first towers placed free",
		director._count_build("gnomes", "aa_tower") >= 2)
	_check("AA: free means no spend",
		gs.resources.get_amount("gnomes", "gold") == 0.0)
	_free_world(parts)


func _test_air_defenses_paid() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_bld(gs, "gnomes", "aa_tower", Vector2(1100, 1000))
	_bld(gs, "gnomes", "aa_tower", Vector2(900, 1000))
	var before: float = gs.resources.get_amount("gnomes", "gold")
	director._air_defenses("gnomes", director._hall("gnomes"))
	# Broke: no more towers beyond the 2 free ones.
	_check("AA: broke AI stops at 2",
		director._count_build("gnomes", "aa_tower") == 2)
	_check("AA: nothing spent", gs.resources.get_amount("gnomes", "gold") == before)
	_free_world(parts)


func _test_daily_plan() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_check("plan: default grow", director.plan_goal("gnomes") == "grow")
	_unit(gs, "ogres", "soldier", Vector2(1050, 1000))
	director._refresh_daily_plan("gnomes", director._hall("gnomes"),
		director._analyze("gnomes", director._hall("gnomes")))
	_check("plan: under attack -> defend", director.plan_goal("gnomes") == "defend")
	_free_world(parts)


func _test_save_load() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_unit(gs, "ogres", "soldier", Vector2(1050, 1000))
	director.tick(2.8 * 3)
	var data: Dictionary = director.to_dict()
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans", "gnomes", "ogres"])
	var d2 := SimAIDirector.new(gs2)
	d2.from_dict(data)
	_check("save: race_idx survives", d2.to_dict()["race_idx"] == data["race_idx"])
	_check("save: plans survive",
		(d2.to_dict()["plans"] as Dictionary).has("gnomes"))
	_check("save: threat_prev survives",
		(d2.to_dict()["threat_prev"] as Dictionary).has("gnomes"))
	gs2.queue_free()
	_free_world(parts)
