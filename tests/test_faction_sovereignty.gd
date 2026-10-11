extends SceneTree
## Cursing Gnomes — faction sovereignty headless tests (Jeremy 2026-10-04).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_faction_sovereignty.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers:
##   - advisor mode: the AI director thinks for the player faction (no free
##     AI-bank drip; buildings + training via the same blueprint/queue path),
##     player blueprints defer AI building, player-queued training lines are
##     skipped, adviser actions surface a subtle Gazette note, and units with
##     player_order are untouched by maneuvers;
##   - sovereignty: direct-control attempts on foreign factions are refused
##     by that faction's leader (voiced lines, memory logged, order blocked)
##     across every player order entry point (SimArmy stances/draft/muster/
##     deploy/warlord/weapon upgrades, GuildHiring.queue_training);
##   - own-faction orders keep working exactly as before;
##   - the issue_command diplomacy channel is unaffected.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes faction sovereignty tests ===")
	_test_advisor_thinks_for_player()
	_test_advisor_no_bank_drip()
	_test_advisor_defers_to_player_blueprints()
	_test_advisor_skips_player_queued_training()
	_test_advisor_note()
	_test_advisor_respects_player_orders()
	_test_refusal_lines()
	_test_foreign_orders_refused()
	_test_own_orders_work()
	_test_queue_training_sovereignty()
	_test_issue_command_unaffected()
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
	gs.army = SimArmy.new(gs)
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
	gs.resources.add_resource(faction, "oil", gold, true)


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


## --- Advisor mode ------------------------------------------------------------


func _test_advisor_thinks_for_player() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "humans", 2000, 2000)
	var before := gs.buildings.size()
	director._think("humans")
	var placed := gs.buildings.size() - before
	_check("advisor: think places buildings for the player", placed >= 1)
	var hall: Dictionary = director._hall("humans")
	var queued: int = (hall.get("train_queue", []) as Array).size()
	_check("advisor: think queues training for the player", queued >= 1)
	_free_world(parts)


func _test_advisor_no_bank_drip() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# Broke AI faction gets the free floors + drip (HTML verbatim).
	director._ai_bank("gnomes")
	_check("advisor: AI bank still funds AI factions",
		gs.resources.get_amount("gnomes", "gold") == 168.0)
	# The player faction gets NOTHING from the AI bank — advisers spend
	# real money only.
	gs.resources.add_resource("humans", "gold", 100.0, true)
	gs.resources.add_resource("humans", "wood", 100.0, true)
	director._think("humans")
	_check("advisor: no free drip for the player",
		gs.resources.get_amount("humans", "gold") <= 100.0)
	_free_world(parts)


func _test_advisor_defers_to_player_blueprints() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "humans", 5000, 5000)
	var hall_pos: Vector2 = Vector2(2000, 500)
	# The player placed their own barracks blueprint near the hall.
	var mine: Dictionary = gs.add_building({"type": "barracks",
		"faction": "humans", "town_id": 1,
		"position": hall_pos + Vector2(120, 0), "alive": true,
		"complete": false, "progress": 0.1, "player_placed": true,
		"hp": 500.0, "max_hp": 500.0})
	_check("defer: blueprint tagged", not mine.is_empty())
	# The adviser tries to place a barracks right next to it -> refused.
	var near: Dictionary = director._place("humans", "barracks", 1,
		hall_pos + Vector2(180, 40))
	_check("defer: adviser won't compete with player blueprint",
		near.is_empty())
	# Far away is fine — the advisers still build.
	var far: Dictionary = director._place("humans", "barracks", 1,
		hall_pos + Vector2(900, 900))
	_check("defer: adviser still builds elsewhere", not far.is_empty())
	# AI factions are never deferred by anything.
	_fund(gs, "gnomes", 5000, 5000)
	var ai_spot: Dictionary = director._place("gnomes", "barracks", 1,
		Vector2(1100, 1100))
	_check("defer: AI factions unaffected", not ai_spot.is_empty())
	_free_world(parts)


func _test_advisor_skips_player_queued_training() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_fund(gs, "humans", 2000, 2000)
	var hall: Dictionary = director._hall("humans")
	# The player explicitly queued a worker (by_player marks the order).
	_check("train: player queues a worker",
		gs.hiring.queue_training(hall, "worker", true))
	_check("train: line marked as player order",
		director._player_queued(hall, "worker"))
	var workers_before := 0
	for job: Dictionary in hall.get("train_queue", []):
		if String(job.get("unit_type", "")) == "worker":
			workers_before += 1
	var st: Dictionary = director._analyze("humans", hall)
	director._train("humans", hall, st)
	var workers_after := 0
	for job2: Dictionary in hall.get("train_queue", []):
		if String(job2.get("unit_type", "")) == "worker":
			workers_after += 1
	_check("train: adviser doesn't duplicate the player's line",
		workers_after == workers_before)
	# Sanity: without a player order the adviser queues normally.
	var hall2: Dictionary = _hall(gs, "gnomes", Vector2(1000, 1000))
	_fund(gs, "gnomes", 2000, 2000)
	var st2: Dictionary = director._analyze("gnomes", hall2)
	director._train("gnomes", hall2, st2)
	_check("train: AI factions train normally",
		(hall2.get("train_queue", []) as Array).size() >= 1)
	_free_world(parts)


func _test_advisor_note() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_stories.clear()
	director._advisor_note("humans", "barracks")
	_check("note: gazette story emitted", _stories.size() == 1)
	var story: Dictionary = _stories[0]
	_check("note: headline", String(story.get("headline", "")) == "ADVISER'S WORK")
	_check("note: mentions the building",
		String(story.get("body", "")).contains("Barracks"))
	# Throttled: same building type, same day -> no repeat.
	director._advisor_note("humans", "barracks")
	_check("note: throttled per type per day", _stories.size() == 1)
	# A full adviser placement announces significant buildings.
	_fund(gs, "humans", 5000, 5000)
	_stories.clear()
	director._advisor_note_day.clear()
	var bp: Dictionary = director._place("humans", "barracks", 1,
		Vector2(2600, 900))
	_check("note: adviser placement announces", not bp.is_empty()
		and _stories.size() == 1)
	# Routine buildings (houses) stay quiet.
	_stories.clear()
	director._advisor_note("humans", "house")
	_check("note: routine buildings stay quiet", _stories.is_empty())
	_free_world(parts)


func _test_advisor_respects_player_orders() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var mine: Dictionary = _unit(gs, "humans", "soldier", Vector2(2100, 600))
	mine["player_order"] = {"type": "move"}  # the player ordered this one
	# Enemy pressure triggers the muster...
	_unit(gs, "ogres", "soldier", Vector2(2050, 520))
	_unit(gs, "ogres", "soldier", Vector2(2060, 530))
	_unit(gs, "ogres", "soldier", Vector2(2040, 540))
	var hall: Dictionary = director._hall("humans")
	director._muster_defense("humans", hall,
		director._analyze("humans", hall))
	_check("orders: player-ordered unit keeps its orders",
		(mine.get("move_target", Vector2.INF) as Vector2) == Vector2.INF
		and not bool(mine.get("defend_mode", false)))
	# ...while an unordered soldier musters normally.
	var free: Dictionary = _unit(gs, "humans", "soldier", Vector2(2200, 700))
	director._threat_prev.clear()
	director._muster_defense("humans", hall,
		director._analyze("humans", hall))
	_check("orders: unordered units still muster",
		(free.get("move_target", Vector2.INF) as Vector2) != Vector2.INF)
	_free_world(parts)


## --- Sovereignty -------------------------------------------------------------


func _test_refusal_lines() -> void:
	# Every leader has a voiced line. The ogre pool includes Jeremy's
	# example phrasing (two lines, picked at random).
	var saw_ogre := false
	for i in 12:
		if SimFactionLeaders.control_refusal_line("ogres").contains("ogre"):
			saw_ogre = true
	_check("voice: ogre line", saw_ogre)
	for f: String in ["humans", "ogres", "elves", "gnomes", "undead"]:
		var line: String = SimFactionLeaders.control_refusal_line(f)
		_check("voice: %s has a refusal line" % f, not line.is_empty())
	# Unknown faction falls back gracefully.
	var fb: String = SimFactionLeaders.control_refusal_line("nope")
	_check("voice: generic fallback", fb == SimFactionLeaders.CONTROL_REFUSAL_FALLBACK)


func _test_foreign_orders_refused() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var army: SimArmy = gs.army
	for i in 3:
		_unit(gs, "gnomes", "worker", Vector2(900 + i * 10, 900))
	var gsoldier: Dictionary = _unit(gs, "gnomes", "soldier",
		Vector2(950, 950))
	_fund(gs, "gnomes", 2000, 2000)
	# Every direct-control entry point refuses a foreign faction.
	army.set_stance("gnomes", "guard")
	_check("refuse: stance unchanged", army.get_stance("gnomes") == "auto")
	_check("refuse: draft blocked", army.draft("gnomes") == 0)
	_check("refuse: muster blocked", army.muster("gnomes") == 0)
	_check("refuse: deploy blocked", army.deploy_for_war("gnomes") == 0)
	_check("refuse: warlord blocked", army.promote_warlord("gnomes").is_empty())
	_check("refuse: weapon upgrade blocked",
		not army.buy_weapon_upgrade(int(gsoldier.get("id", -1))))
	# Nothing moved: no gnome was drafted or moved.
	var drafted := false
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == "gnomes" \
				and String(u.get("job", "")) == "soldier" \
				and (u.get("move_target", Vector2.INF) as Vector2) != Vector2.INF:
			drafted = true
	_check("refuse: no gnome unit touched", not drafted)
	# The leader remembers the attempt.
	var mems: Array = gs.faction_leaders.recall("gnomes",
		SimFactionLeaders.MEM_COMMAND)
	_check("refuse: leader logs the attempt", mems.size() >= 1)
	_free_world(parts)


func _test_own_orders_work() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var army: SimArmy = gs.army
	for i in 3:
		_unit(gs, "humans", "worker", Vector2(1900 + i * 10, 400))
	var hsoldier: Dictionary = _unit(gs, "humans", "soldier",
		Vector2(1950, 450))
	_fund(gs, "humans", 2000, 2000)
	# The player's own faction obeys exactly as before.
	army.set_stance("humans", "guard")
	_check("own: stance applies", army.get_stance("humans") == "guard")
	_check("own: draft works", army.draft("humans") > 0)
	_check("own: muster works", army.muster("humans") > 0)
	_check("own: warlord works",
		not army.promote_warlord("humans").is_empty())
	_check("own: weapon upgrade works",
		army.buy_weapon_upgrade(int(hsoldier.get("id", -1))))
	_free_world(parts)


func _test_queue_training_sovereignty() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var foreign: Dictionary = _bld(gs, "gnomes", "barracks",
		Vector2(1200, 1200))
	var own: Dictionary = _bld(gs, "humans", "barracks", Vector2(2100, 600))
	_fund(gs, "gnomes", 2000, 2000)
	_fund(gs, "humans", 2000, 2000)
	# Player-issued training on a FOREIGN barracks: refused by the leader.
	_check("train: foreign barracks refused",
		not gs.hiring.queue_training(foreign, "soldier", true))
	_check("train: refusal recorded",
		gs.hiring.last_train_block == "foreign_sovereign")
	_check("train: foreign queue untouched",
		(foreign.get("train_queue", []) as Array).is_empty())
	# Player-issued training on their OWN barracks: works, marked by_player.
	_check("train: own barracks works",
		gs.hiring.queue_training(own, "soldier", true))
	var q: Array = own.get("train_queue", [])
	_check("train: order marked by_player",
		q.size() == 1 and bool((q[0] as Dictionary).get("by_player", false)))
	# The AI director's own queueing is never refused (by_player=false).
	_check("train: AI queueing unaffected",
		gs.hiring.queue_training(foreign, "soldier"))
	_free_world(parts)


func _test_issue_command_unaffected() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var fl: SimFactionLeaders = gs.faction_leaders
	# Own faction: directed to command directly, as before.
	var own: Dictionary = fl.issue_command("humans", "military")
	_check("diplo: own faction not commandable",
		not bool(own.get("ok", true)))
	# Stranger: refused through the diplomacy channel, as before.
	var stranger: Dictionary = fl.issue_command("gnomes", "military")
	_check("diplo: stranger refused",
		not bool(stranger.get("ok", true))
		and String(stranger.get("msg", "")).contains("Earn our trust"))
	# Ally: accepted through the diplomacy channel, as before.
	gs.diplomacy.form_alliance("humans", "gnomes")
	var ally: Dictionary = fl.issue_command("gnomes", "military")
	_check("diplo: ally accepted", bool(ally.get("ok", false)))
	_check("diplo: directive lands",
		fl.get_directive("gnomes") == "military")
	_free_world(parts)
