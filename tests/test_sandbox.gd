extends SceneTree
## Cursing Gnomes — sandbox observe-mode headless tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_sandbox.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _frame: int = 0
var _world: Node = null


func _initialize() -> void:
	print("=== Cursing Gnomes sandbox observe-mode tests ===")
	_test_begin_observe_only()
	_test_census()
	_test_last_civ_standing()
	_test_soft_end_announced_once()
	_test_director_boost()
	_test_director_troops()
	_test_director_war_peace()
	_test_director_ally()
	_test_director_war_target()
	_test_hall_position()
	_test_director_weather()
	_test_director_time()
	_test_director_disasters()
	_test_director_clear_fires()
	_test_director_expand()
	# The world scene's _ready() only fires once frames run, so the
	# observe-only boot test is deferred to _process (frame 2).
	var ps: PackedScene = load("res://scenes/world/world.tscn")
	_check("world scene loads", ps != null)
	if ps != null:
		_world = ps.instantiate()
		root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_test_world_sandbox_boot()
		print("=== %d passed, %d failed ===" % [_passed, _failed])
		for f: String in _failures:
			print("  FAIL: ", f)
		quit(1 if _failed > 0 else 0)
		return true
	return false


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## Two-faction world with halls + units for census/end checks.
func _new_sandbox() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var factions: Array[String] = ["humans", "gnomes"]
	gs.setup(factions)
	# A player faction is set by default; sandbox boots observe-only.
	gs.player_faction = "humans"
	for f in factions:
		var town: Dictionary = gs.found_town(f, "Town",
			Vector2(1000, 1000) if f == "humans" else Vector2(3000, 3000))
		gs.add_building({"type": "town_hall", "faction": f,
			"town_id": int(town["id"]), "alive": true, "complete": true,
			"position": Vector2(1000, 1000) if f == "humans"
			else Vector2(3000, 3000)})
		for i in range(3):
			gs.add_unit({"faction": f, "job": "worker", "town_id": -1,
				"position": Vector2.ZERO, "alive": true,
				"hp": 100.0, "max_hp": 100.0})
	var sb := SimSandbox.new(gs)
	return [gs, sb]


func _test_begin_observe_only() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	_check("begin: active", sb.active)
	_check("begin: no player faction (observe-only)",
		gs.player_faction == "")
	_check("begin: focus defaults to first active faction",
		sb.focus_race == "humans")
	sb.set_focus("gnomes")
	_check("begin: focus switches", sb.focus_race == "gnomes")
	sb.set_focus("bogus")
	_check("begin: focus rejects unknown faction",
		sb.focus_race == "gnomes")
	sb.begin()  # idempotent
	_check("begin: idempotent", sb.active and gs.player_faction == "")
	gs.free()


func _test_census() -> void:
	var parts: Array = _new_sandbox()
	var sb: SimSandbox = parts[1]
	sb.begin()
	var c: Dictionary = sb.faction_census("humans")
	_check("census: pop counted", int(c.get("pop", -1)) == 3)
	_check("census: halls counted", int(c.get("halls", -1)) == 1)
	_check("census: hall count helper", sb.hall_count("gnomes") == 1)
	parts[0].free()


func _test_last_civ_standing() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	_check("last-civ: empty while two stand",
		sb.last_civ_standing() == "")
	# Raze the gnome hall — humans stand alone.
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == "gnomes":
			b["alive"] = false
	_check("last-civ: single survivor named",
		sb.last_civ_standing() == "humans")
	# Incomplete halls don't count.
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == "humans":
			b["complete"] = false
	_check("last-civ: ruined hall counts as fallen",
		sb.last_civ_standing() == "")
	gs.free()


func _test_soft_end_announced_once() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	# Raze the gnome hall so humans stand alone.
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == "gnomes":
			b["alive"] = false
	var fired: Array[String] = []
	sb.sim_complete.connect(func(w: String) -> void: fired.append(w))
	sb._grace = 0.0  # skip the boot grace in tests
	sb.tick(0.1)
	sb.tick(0.1)
	sb.tick(0.1)
	_check("soft-end: announced once", fired.size() == 1)
	_check("soft-end: winner named", fired[0] == "humans")
	# Two factions standing: no announcement.
	var parts2: Array = _new_sandbox()
	var sb2: SimSandbox = parts2[1]
	sb2.begin()
	var fired2: Array = []
	sb2.sim_complete.connect(func(w: String) -> void: fired2.append(w))
	sb2._grace = 0.0
	sb2.tick(1.0)
	_check("soft-end: silent while two stand", fired2.is_empty())
	gs.free()
	parts2[0].free()


func _test_director_boost() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	var before: float = gs.resources.get_amount("gnomes", "gold")
	sb.boost_race("gnomes")
	_check("boost: +5000 gold",
		gs.resources.get_amount("gnomes", "gold") == before + 5000.0)
	_check("boost: +5000 wood",
		gs.resources.get_amount("gnomes", "wood") == 5000.0)
	_check("boost: +2000 food",
		gs.resources.get_amount("gnomes", "food") == 2000.0)
	gs.free()


func _test_director_troops() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	var before: int = gs.units.size()
	var spawned: int = sb.spawn_troops("gnomes")
	_check("troops: one per roster job",
		spawned == SimSandbox.SANDBOX_JOBS["gnomes"].size())
	_check("troops: units added",
		gs.units.size() == before + spawned)
	var jobs := {}
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == "gnomes" \
				and String(u.get("job", "")) != "worker":
			jobs[String(u.get("job", ""))] = true
	_check("troops: gnome roster spawned",
		jobs.has("axeman") and jobs.has("mage") \
		and jobs.has("tinker_mech") and jobs.has("saboteur"))
	# 96-unit global guard (HTML POPCAP11).
	while gs.units.size() < 96:
		gs.add_unit({"faction": "humans", "job": "worker", "town_id": -1,
			"position": Vector2.ZERO, "alive": true,
			"hp": 100.0, "max_hp": 100.0})
	_check("troops: refused at cap", sb.spawn_troops("humans") == 0)
	gs.free()


func _test_director_war_peace() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	sb.war_all()
	_check("war: all pairs at war",
		gs.diplomacy.relation_state("humans", "gnomes") == "war")
	sb.force_peace_all()
	_check("peace: wars ended",
		gs.diplomacy.relation_state("humans", "gnomes") == "neutral")
	gs.free()


func _test_director_ally() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	sb.war_all()
	sb.ally_all()
	_check("ally: all pairs allied",
		gs.diplomacy.relation_state("humans", "gnomes") == "allied")
	gs.free()


func _test_director_war_target() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	sb.force_peace_all()
	var target: String = sb.war_target("humans")
	_check("war_target: returns another faction",
		target != "" and target != "humans")
	_check("war_target: focus at war with target",
		gs.diplomacy.relation_state("humans", target) == "war")
	gs.free()


func _test_hall_position() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	# Humans hall at (1000, 1000); gnomes hall at (3000, 3000).
	var hp: Vector2 = sb.hall_position("humans")
	_check("hall_position: humans hall found",
		hp.distance_to(Vector2(1000, 1000)) < 1.0)
	_check("hall_position: unknown faction -> ZERO",
		sb.hall_position("bogus") == Vector2.ZERO)
	gs.free()


## Observe-only world boot (the backlog item: sandbox used to boot a
## playable gnomes game). An empty player faction must arm the director,
## hide the standard RTS chrome, and show the director HUD.
func _test_world_sandbox_boot() -> void:
	if _world == null:
		_check("world boot: world instantiated", false)
		return
	_world.configure("", "")
	_check("world boot: player faction stays empty",
		String(_world.get("game").player_faction) == "")
	var sb = _world.get("sandbox")
	_check("world boot: sandbox director created",
		sb != null and bool(sb.get("active")))
	var hud = _world.get("hud")
	_check("world boot: hud present", hud != null)
	if hud == null:
		return
	_check("world boot: director HUD built",
		hud.get("_sb_panel") != null and hud.get("_sb_panel").visible)
	_check("world boot: top bar hidden",
		hud.get("_top_bar") == null or not hud.get("_top_bar").visible)
	_check("world boot: side tabs hidden",
		hud.get("_side_tab_bar") == null or not hud.get("_side_tab_bar").visible)
	_check("world boot: director wired to sandbox",
		hud.get("_sandbox") == sb)


## Weather/time director (HTML w_*/day/night/skip_day parity).
func _test_director_weather() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	# No seasons sim wired: refused, no crash.
	_check("weather: refused without seasons sim",
		not sb.set_weather("storm"))
	gs.seasons = SimSeasons.new(gs)
	_check("weather: storm forced",
		sb.set_weather("storm") and String(gs.seasons.weather) == "storm")
	_check("weather: snow forced",
		sb.set_weather("snow") and String(gs.seasons.weather) == "snow")
	_check("weather: clear forced",
		sb.set_weather("clear") and String(gs.seasons.weather) == "clear")
	_check("weather: unknown kind rejected",
		not sb.set_weather("lava") and String(gs.seasons.weather) == "clear")
	gs.free()


func _test_director_time() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	gs.seasons = SimSeasons.new(gs)
	sb.set_time_of_day(10.0)  # HTML 'day'
	_check("time: day -> 10:00",
		absf(gs.seasons.hour_of_day() - 10.0) < 0.01)
	_check("time: same game day", gs.day_number == 1)
	sb.set_time_of_day(22.0)  # HTML 'night'
	_check("time: night -> 22:00",
		absf(gs.seasons.hour_of_day() - 22.0) < 0.01)
	sb.skip_day()  # HTML skip_day: +1 day, 08:00
	_check("time: skip_day advances the calendar", gs.day_number == 2)
	_check("time: skip_day lands at 08:00",
		absf(gs.seasons.hour_of_day() - 8.0) < 0.01)
	gs.free()


## Wires the disasters sim the way world.gd does (game.disasters is
## World-owned, null on a bare GameState).
func _new_disasters(gs: GameState) -> void:
	var combat := SimCombat.new(gs)
	gs.disasters = DisasterSim.new(gs, combat)


func _test_director_disasters() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	# No disasters sim wired: refused, no crash.
	_check("disaster: refused without disasters sim",
		sb.spawn_disaster("butt") == "")
	_new_disasters(gs)
	var r: String = sb.spawn_disaster("butt")
	_check("disaster: butt -> giant_ass", r == "giant_ass")
	var found := false
	for u: Dictionary in gs.units:
		if String(u.get("job", "")) == "giant_ass" \
				and bool(u.get("alive", false)):
			found = true
	_check("disaster: giant ass unit spawned", found)
	_check("disaster: singleton refused twice",
		sb.spawn_disaster("butt") == "")
	_check("disaster: bandits -> raid",
		sb.spawn_disaster("bandits") == "bandit_raid")
	_check("disaster: fire -> 8 wildfires",
		sb.spawn_disaster("fire") == "wildfire" \
			and gs.disasters.fires.size() == 8)
	# Volcano needs valid terrain; either it erupts or no site was found.
	var v: String = sb.spawn_disaster("volcano")
	_check("disaster: volcano handled", v == "volcano" or v == "")
	_check("disaster: unknown kind rejected",
		sb.spawn_disaster("nuke") == "")
	gs.free()


func _test_director_clear_fires() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	_new_disasters(gs)
	gs.disasters.ignite(Vector2(500, 500), 60.0)
	gs.disasters.ignite(Vector2(600, 600), 60.0)
	for b: Dictionary in gs.buildings:
		b["on_fire"] = true
	var n: int = sb.clear_fires()
	_check("clear_fires: all fires out",
		n == 2 and gs.disasters.fires.is_empty())
	var still_burning := false
	for b: Dictionary in gs.buildings:
		if bool(b.get("on_fire", false)):
			still_burning = true
	_check("clear_fires: buildings no longer burning", not still_burning)
	# No disasters sim: still clears building flags, no crash.
	var parts2: Array = _new_sandbox()
	var sb2: SimSandbox = parts2[1]
	sb2.begin()
	for b: Dictionary in parts2[0].buildings:
		b["on_fire"] = true
	_check("clear_fires: works without disasters sim",
		sb2.clear_fires() == 0)
	gs.free()
	parts2[0].free()


func _test_director_expand() -> void:
	var parts: Array = _new_sandbox()
	var gs: GameState = parts[0]
	var sb: SimSandbox = parts[1]
	sb.begin()
	var before: float = gs.resources.get_amount("gnomes", "gold")
	sb.force_expand("gnomes")
	_check("expand: boost delivered",
		gs.resources.get_amount("gnomes", "gold") == before + 5000.0)
	# Zone development: an empty R zone near the hall grows one house.
	gs.resources.add_resource("gnomes", "oil", 500.0, true)
	var z: Dictionary = gs.zoning.paint_zone("R", "gnomes",
		Rect2(2800, 2800, 400, 400))
	_check("expand: zone painted", not z.is_empty())
	sb.force_expand("gnomes")
	var houses := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == "gnomes" \
				and String(b.get("type", "")) == "house":
			houses += 1
	_check("expand: one house blueprint placed", houses == 1)
	# Serialization: an incomplete site blocks new lots (HTML gate).
	sb.force_expand("gnomes")
	var houses2 := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == "gnomes" \
				and String(b.get("type", "")) == "house":
			houses2 += 1
	_check("expand: no second lot while site incomplete", houses2 == 1)
	gs.free()
