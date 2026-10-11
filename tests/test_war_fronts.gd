extends SceneTree
## Cursing Gnomes — war front tests (Jeremy 2026-10-05: AI-first phase,
## military AI checklist item "attack": prosecuting a war AFTER the strike).
##
## The strike is one wave; real wars need follow-through. Covers:
##   - _launch_strike marks committed troops with war_front + records the front
##   - reinforcement waves replace losses below 60% of launch strength
##   - no reinforcement at/above the threshold
##   - no reinforcement while home is physically threatened
##   - home-guard floor: the nearest home troops are never stripped
##   - withdrawing troops don't count as committed
##   - troops that reach home are unmarked and must rest before re-deploy
##   - player faction: adviser Gazette warning, never auto-reinforcement
##   - stand-down on peace: marks cleared, survivors march home
##   - wars begun outside a campaign (betrayal etc.) get a first wave
##   - adopting marked survivors from an untracked front (loaded save)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_war_fronts.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


const GNOME_HALL := Vector2(1000, 1000)
const OGRE_HALL := Vector2(3000, 3000)
const HUMAN_HALL := Vector2(2000, 500)
const FAR_POST := Vector2(2500, 2500)  # >900px from any hall


func _initialize() -> void:
	print("=== Cursing Gnomes war front tests ===")
	_test_strike_records_front()
	_test_reinforcement_replaces_losses()
	_test_no_reinforcement_at_strength()
	_test_no_reinforcement_when_home_threatened()
	_test_home_guard_floor()
	_test_withdrawing_not_committed()
	_test_home_rest_unmarks()
	_test_player_gets_warning_not_troops()
	_test_stand_down_on_peace()
	_test_first_wave_for_sudden_war()
	_test_adopt_marked_survivors()
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
	gs.day_number = 20
	_stories.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void:
		_stories.append(s))
	_hall(gs, "humans", HUMAN_HALL)
	_hall(gs, "gnomes", GNOME_HALL)
	_hall(gs, "ogres", OGRE_HALL)
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


func _st(parts: Array, faction: String) -> Dictionary:
	var director: SimAIDirector = parts[1]
	return director._analyze(faction, director._hall(faction))


func _marked(gs: GameState, faction: String, key: String) -> Array:
	var out := []
	for u: Dictionary in gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("war_front", "")) == key:
			out.append(u)
	return out


func _kill_some(marked: Array, n: int) -> void:
	var k := 0
	for u: Dictionary in marked:
		if k >= n:
			break
		u["alive"] = false
		k += 1


func _front_at(parts: Array, pos: Vector2, key: String, n: int) -> void:
	# n marked troops already fighting at the front (far from home).
	var gs: GameState = parts[0]
	for i in n:
		var u := _unit(gs, "gnomes", "soldier",
			pos + Vector2(i * 9.0, 0.0))
		u["war_front"] = key
		u["move_target"] = pos + Vector2(40.0, 0.0)


func _headlines(with: String) -> int:
	var n := 0
	for s: Dictionary in _stories:
		if String(s.get("headline", "")) == with:
			n += 1
	return n


func _test_strike_records_front() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_army(gs, "gnomes", 20, GNOME_HALL)
	_army(gs, "ogres", 3, OGRE_HALL)
	director._launch_strike("gnomes", "ogres", _st(parts, "gnomes"))
	_check("strike records the front",
		director._war_fronts.has("gnomes|ogres"))
	var front: Dictionary = director._war_fronts.get("gnomes|ogres", {})
	_check("front strength matches marchers",
		int(front.get("strength", 0)) == 20)
	_check("front target is the enemy",
		String(front.get("target", "")) == "ogres")
	_check("front pos is the enemy hall",
		(front.get("pos", Vector2.ZERO) as Vector2) \
			.distance_to(OGRE_HALL) < 1.0)
	_check("all marchers carry the war_front mark",
		_marked(gs, "gnomes", "gnomes|ogres").size() == 20)
	_free_game(parts)


func _test_reinforcement_replaces_losses() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_army(gs, "gnomes", 20, GNOME_HALL)
	director._launch_strike("gnomes", "ogres", _st(parts, "gnomes"))
	_army(gs, "gnomes", 10, FAR_POST)  # reserves, far from home
	_kill_some(_marked(gs, "gnomes", "gnomes|ogres"), 15)
	director._war_front_tick("gnomes", _st(parts, "gnomes"))
	var marked := _marked(gs, "gnomes", "gnomes|ogres")
	# 5 survivors + wave min(20-5, 6) = 6; no home guard (reserves far).
	_check("losses replaced by a wave", marked.size() == 11)
	var wave_heads := 0
	for u: Dictionary in marked:
		if int(u.get("id", 0)) > 20:  # the reserves (unit ids start at 1)
			wave_heads += 1
			_check("wave marches on the enemy hall",
				(u.get("move_target", Vector2.ZERO) as Vector2) \
					.distance_to(OGRE_HALL) < 400.0)
	_check("wave troops found", wave_heads == 6)
	_check("reinforcement gazetted", _headlines("REINFORCEMENTS") == 1)
	_free_game(parts)


func _test_no_reinforcement_at_strength() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_army(gs, "gnomes", 20, GNOME_HALL)
	director._launch_strike("gnomes", "ogres", _st(parts, "gnomes"))
	_army(gs, "gnomes", 10, FAR_POST)
	_kill_some(_marked(gs, "gnomes", "gnomes|ogres"), 5)
	director._war_front_tick("gnomes", _st(parts, "gnomes"))
	# 15 committed >= 20*0.6: front holds, no wave.
	_check("no wave when the front holds",
		_marked(gs, "gnomes", "gnomes|ogres").size() == 15)
	_check("no reinforcement headline", _headlines("REINFORCEMENTS") == 0)
	_free_game(parts)


func _test_no_reinforcement_when_home_threatened() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_army(gs, "gnomes", 20, GNOME_HALL)
	director._launch_strike("gnomes", "ogres", _st(parts, "gnomes"))
	_army(gs, "gnomes", 10, FAR_POST)
	_kill_some(_marked(gs, "gnomes", "gnomes|ogres"), 15)
	# Ogre raiders at the gnome hall: physical home threat.
	_army(gs, "ogres", 3, GNOME_HALL + Vector2(100, 0))
	_check("home reads as threatened",
		director._front_home_threatened("gnomes", GNOME_HALL))
	director._war_front_tick("gnomes", _st(parts, "gnomes"))
	_check("no wave while home is threatened",
		_marked(gs, "gnomes", "gnomes|ogres").size() == 5)
	_check("no reinforcement headline", _headlines("REINFORCEMENTS") == 0)
	_free_game(parts)


func _test_home_guard_floor() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var key := "gnomes|ogres"
	director._war_fronts[key] = {"target": "ogres", "strength": 10,
		"pos": OGRE_HALL, "day": 20, "warned": false, "reinf_day": 0}
	_front_at(parts, OGRE_HALL, key, 3)  # committed 3 < 6
	# 10 fresh troops near home, staggered so the nearest are identifiable.
	for i in 10:
		_unit(gs, "gnomes", "soldier", GNOME_HALL + Vector2(i * 10.0, 0.0))
	director._war_front_tick("gnomes", _st(parts, "gnomes"))
	# wave = min(10-3, 6) = 6, but home guard keeps maxi(2, 13*0.4)=5.
	var sent := 0
	var kept_nearest := true
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if not bool(u.get("alive", false)):
			continue
		# The 3 front troops are ~2800px out; newly sent are near home.
		var d: float = (u.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(GNOME_HALL)
		if String(u.get("war_front", "")) == key and d < 900.0:
			sent += 1
			if d < 45.0:
				kept_nearest = false  # a nearest-5 troop was taken
	_check("home guard caps the wave", sent == 5)
	_check("nearest home troops are kept", kept_nearest)
	_free_game(parts)


func _test_withdrawing_not_committed() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var key := "gnomes|ogres"
	director._war_fronts[key] = {"target": "ogres", "strength": 10,
		"pos": OGRE_HALL, "day": 20, "warned": false, "reinf_day": 0}
	_front_at(parts, OGRE_HALL, key, 10)
	var marked := _marked(gs, "gnomes", key)
	for i in 7:
		(marked[i] as Dictionary)["withdrawing"] = true
	_army(gs, "gnomes", 12, FAR_POST)
	director._war_front_tick("gnomes", _st(parts, "gnomes"))
	# committed 3 < 6 -> wave min(10-3, 6) = 6, no home guard (far).
	_check("withdrawing troops trigger replacement",
		_marked(gs, "gnomes", key).size() == 16)
	_free_game(parts)


func _test_home_rest_unmarks() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var key := "gnomes|ogres"
	director._war_fronts[key] = {"target": "ogres", "strength": 10,
		"pos": OGRE_HALL, "day": 20, "warned": false, "reinf_day": 0}
	_front_at(parts, OGRE_HALL, key, 9)
	# One survivor made it home and stays home: rested, not re-deployable.
	var homeboy := _unit(gs, "gnomes", "soldier", GNOME_HALL)
	homeboy["war_front"] = key
	homeboy["move_target"] = GNOME_HALL + Vector2(30, 0)
	director._war_front_tick("gnomes", _st(parts, "gnomes"))
	_check("home survivor is unmarked",
		String(homeboy.get("war_front", "")) == "")
	_check("home survivor must rest",
		int(homeboy.get("front_rest_until", 0)) == 23)
	_check("front still holds at 9", _headlines("REINFORCEMENTS") == 0)
	_free_game(parts)


func _test_player_gets_warning_not_troops() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.diplomacy.declare_war("humans", "ogres", "test")
	var key := "humans|ogres"
	director._war_fronts[key] = {"target": "ogres", "strength": 10,
		"pos": OGRE_HALL, "day": 20, "warned": false, "reinf_day": 0}
	for i in 3:  # 3 committed < 6: faltering
		var u := _unit(gs, "humans", "soldier",
			OGRE_HALL + Vector2(i * 9.0, 0.0))
		u["war_front"] = key
		u["move_target"] = OGRE_HALL + Vector2(40.0, 0.0)
	_army(gs, "humans", 12, FAR_POST)
	director._war_front_tick("humans", _st(parts, "humans"))
	_check("player troops never auto-reinforced",
		_marked(gs, "humans", key).size() == 3)
	_check("adviser warns instead", _headlines("ADVISER'S WARNING") == 1)
	_check("warning flag set",
		bool((director._war_fronts[key] as Dictionary).get("warned", false)))
	director._war_front_tick("humans", _st(parts, "humans"))
	_check("warning fires once", _headlines("ADVISER'S WARNING") == 1)
	_free_game(parts)


func _test_stand_down_on_peace() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var key := "gnomes|ogres"
	director._war_fronts[key] = {"target": "ogres", "strength": 8,
		"pos": OGRE_HALL, "day": 20, "warned": false, "reinf_day": 0}
	_front_at(parts, OGRE_HALL, key, 8)
	gs.diplomacy.make_peace("gnomes", "ogres")
	_check("peace took hold",
		gs.diplomacy.relation_state("gnomes", "ogres") != "war")
	director._war_front_tick("gnomes", _st(parts, "gnomes"))
	_check("front erased at peace", not director._war_fronts.has(key))
	_check("marks cleared", _marked(gs, "gnomes", key).is_empty())
	var homebound := true
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if not bool(u.get("alive", false)):
			continue
		if (u.get("move_target", Vector2.INF) as Vector2) \
				.distance_to(GNOME_HALL) > 400.0:
			homebound = false
	_check("survivors march home", homebound)
	_free_game(parts)


func _test_first_wave_for_sudden_war() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# War with no campaign and no front (betrayal-style): it must march.
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_army(gs, "gnomes", 12, FAR_POST)
	director._war_front_tick("gnomes", _st(parts, "gnomes"))
	_check("sudden war gets a front",
		director._war_fronts.has("gnomes|ogres"))
	var front: Dictionary = director._war_fronts["gnomes|ogres"]
	_check("first wave is 8", int(front.get("strength", 0)) == 8)
	_check("8 troops committed",
		_marked(gs, "gnomes", "gnomes|ogres").size() == 8)
	_free_game(parts)


func _test_adopt_marked_survivors() -> void:
	var parts := _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# Loaded-save shape: war on, marked troops, but no tracked front.
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	var key := "gnomes|ogres"
	_front_at(parts, OGRE_HALL, key, 5)
	_army(gs, "gnomes", 12, FAR_POST)
	director._war_front_tick("gnomes", _st(parts, "gnomes"))
	_check("marked survivors adopted into a front",
		director._war_fronts.has(key))
	var front: Dictionary = director._war_fronts[key]
	_check("adopted strength matches survivors",
		int(front.get("strength", 0)) == 5)
	# 5 < 6 -> a wave follows on the NEXT think, not this one.
	_check("no double-commit on adoption",
		_marked(gs, "gnomes", key).size() == 5)
	_free_game(parts)
