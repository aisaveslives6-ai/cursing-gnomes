extends SceneTree
## Cursing Gnomes — AI command-post (Battlefront) tests (Jeremy 2026-10-06).
##
## The AI director treats towns, monasteries, and dark crystals ALL as
## command posts: claims unclaimed ones, assaults war-enemy-held ones via
## the proposal protocol, and reinforces threatened own ones. Monasteries
## stay the top war priority via SimCommandPosts.VALUE.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_post_ai.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _phone_asks: Array = []
var _decided: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes post-AI tests ===")
	_test_unified_targeting_value_order()
	_test_unclaimed_crystal_claim_party()
	_test_threatened_crystal_guard()
	_test_threatened_own_town_guard()
	_test_assault_proposal_for_war_held_crystal()
	_test_march_expiry_on_capture()
	_test_guard_expiry_on_loss()
	_test_monastery_still_top_priority()
	_test_peacetime_town_not_targeted()
	_test_maneuver_branch_uses_all_posts()
	_test_legacy_marks_still_set()
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


## Fresh headless game: player = humans; proposals + director +
## monasteries + crystals + command_posts wired like World does.
func _make_game() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.proposals = SimProposals.new(gs)
	var mons := SimMonasteries.new()
	mons.setup(gs)
	gs.monasteries = mons
	var crys := SimDarkCrystals.new()
	crys.setup(gs)
	gs.crystals = crys
	var cps := SimCommandPosts.new()
	cps.setup(gs)
	gs.command_posts = cps
	var director := SimAIDirector.new(gs)
	gs.ai_director = director
	_phone_asks.clear()
	_decided.clear()
	gs.bus.strategic_proposal.connect(func(p: Dictionary) -> void:
		_phone_asks.append(p))
	gs.bus.strategic_proposal_decided.connect(
		func(p: Dictionary, approved: bool) -> void:
			_decided.append([p, approved]))
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


func _monastery(gs: GameState, mid: int, owner: String,
		pos: Vector2) -> Dictionary:
	var m := {"id": mid, "god_id": "test_god_%d" % mid, "position": pos,
		"owner": owner, "progress": {}, "contested": false,
		"contested_by": "", "name": "Test Monastery %d" % mid}
	(gs.monasteries.monasteries as Array).append(m)
	return m


func _crystal(gs: GameState, cid: int, owner: String,
		pos: Vector2) -> Dictionary:
	var c := {"id": cid, "position": pos, "owner": owner, "progress": {},
		"contested": false, "contested_by": "",
		"name": "Test Crystal %d" % cid}
	(gs.crystals.crystals as Array).append(c)
	return c


func _st(gs: GameState, director: SimAIDirector,
		faction: String) -> Dictionary:
	return director._analyze(faction, director._hall(faction))


## Monasteries outrank crystals in the unified target score (VALUE 3.0 > 1.0).
func _test_unified_targeting_value_order() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_monastery(gs, 1, "", Vector2(1500, 1500))  # ~707px from gnomes hall
	_crystal(gs, 1, "", Vector2(1500, 1200))    # ~538px from gnomes hall
	var t: Dictionary = director._best_post_target("gnomes",
		director._command_post_list(), Vector2(1000, 1000))
	_check("unified target: monastery beats crystal",
		String(t.get("kind", "")) == "monastery")
	_free_game(parts)


## An unclaimed crystal gets a claim party without any proposal.
func _test_unclaimed_crystal_claim_party() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_crystal(gs, 2, "", Vector2(1400, 1000))
	_army(gs, "gnomes", 10, Vector2(1000, 1000))
	var st: Dictionary = _st(gs, director, "gnomes")
	director._seek_command_posts("gnomes", st)
	var claimed := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if int(u.get("crystal_march", -1)) == 2:
			claimed += 1
	_check("unclaimed crystal gets claim party (4)",
		claimed == director.POST_CLAIM_PARTY)
	_check("claim party needs no proposal", _phone_asks.is_empty()
		and _decided.is_empty())
	_free_game(parts)


## A threatened OWN crystal gets proportional guard reinforcements.
func _test_threatened_crystal_guard() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# Crystal far from the gnomes hall so only IT is threatened.
	_crystal(gs, 3, "gnomes", Vector2(3000, 1000))
	# 4 enemies threatening our crystal -> ceil(4*1.3)+2 = 8 defenders.
	_army(gs, "ogres", 4, Vector2(3050, 1000))
	_army(gs, "gnomes", 12, Vector2(1000, 1000))
	var st: Dictionary = _st(gs, director, "gnomes")
	director._seek_command_posts("gnomes", st)
	var reinforced := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		var g := u.get("post_guard", {}) as Dictionary
		if String(g.get("kind", "")) == "crystal" \
				and int(g.get("id", -1)) == 3:
			reinforced += 1
	_check("threatened own crystal reinforced proportionally",
		reinforced == 8)
	_free_game(parts)


## A threatened OWN town (hall) gets guard reinforcements too.
func _test_threatened_own_town_guard() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# 2 enemies near the gnomes hall -> ceil(2*1.3)+2 = 5 defenders.
	_army(gs, "ogres", 2, Vector2(1050, 1000))
	_army(gs, "gnomes", 12, Vector2(1300, 1000))
	var st: Dictionary = _st(gs, director, "gnomes")
	director._seek_command_posts("gnomes", st)
	var reinforced := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		var g := u.get("post_guard", {}) as Dictionary
		if String(g.get("kind", "")) == "town":
			reinforced += 1
	_check("threatened own town reinforced", reinforced == 5)
	_free_game(parts)


## A war-enemy-held crystal triggers a command_post_assault proposal.
func _test_assault_proposal_for_war_held_crystal() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_crystal(gs, 4, "ogres", Vector2(2000, 1000))
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_army(gs, "gnomes", 10, Vector2(1000, 1000))
	gs.day_number = 5
	var st: Dictionary = _st(gs, director, "gnomes")
	director._seek_command_posts("gnomes", st)
	# AI factions auto-resolve: the proposal was decided and the assault
	# launched. The phone modal path fires only for the player faction.
	_check("war-held crystal: assault proposed",
		director._assault_proposed.get("gnomes|crystal|4") == 5)
	var kinds: Array = []
	for p: Array in _decided:
		kinds.append(String((p[0] as Dictionary).get("kind", "")))
	_check("war-held crystal: proposal kind is command_post_assault",
		"command_post_assault" in kinds)
	_free_game(parts)


## Assault march marks expire once WE take the post.
func _test_march_expiry_on_capture() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_crystal(gs, 5, "", Vector2(1400, 1000))
	_army(gs, "gnomes", 10, Vector2(1000, 1000))
	var st: Dictionary = _st(gs, director, "gnomes")
	director._seek_command_posts("gnomes", st)
	var marked := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if int(u.get("crystal_march", -1)) == 5:
			marked += 1
	_check("crystal claim march issued", marked > 0)
	# We take the crystal: all march marks must clear on refresh.
	(gs.crystals.crystals[0] as Dictionary)["owner"] = "gnomes"
	director._refresh_post_marches("gnomes",
		{"army": director._army_of("gnomes")})
	var cleared := true
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if u.has("crystal_march") or u.has("post_march"):
			cleared = false
	_check("assault marks expire when the post is taken", cleared)
	_free_game(parts)


## Guard marks expire when we LOSE the post.
func _test_guard_expiry_on_loss() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	# Monastery far from the gnomes hall so only IT is threatened/guarded.
	_monastery(gs, 6, "gnomes", Vector2(3000, 1000))
	_army(gs, "ogres", 3, Vector2(3050, 1000))
	_army(gs, "gnomes", 10, Vector2(1000, 1000))
	var st: Dictionary = _st(gs, director, "gnomes")
	director._seek_command_posts("gnomes", st)
	var guarded := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if u.has("post_guard") and u.has("monastery_guard"):
			guarded += 1
	_check("threatened monastery guarded", guarded > 0)
	# We lose the monastery: guard marks must clear on refresh.
	(gs.monasteries.monasteries[0] as Dictionary)["owner"] = "ogres"
	director._refresh_post_marches("gnomes",
		{"army": director._army_of("gnomes")})
	var cleared := true
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if u.has("monastery_guard"):
			cleared = false
		var pg := u.get("post_guard", {}) as Dictionary
		if String(pg.get("kind", "")) == "monastery":
			cleared = false
	_check("guard marks expire when the post is lost", cleared)
	_free_game(parts)


## War-held monastery outranks war-held crystal at equal distance.
func _test_monastery_still_top_priority() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_monastery(gs, 7, "ogres", Vector2(2000, 1000))  # 1000px away
	_crystal(gs, 7, "ogres", Vector2(1000, 2000))    # 1000px away
	gs.diplomacy.declare_war("gnomes", "ogres", "test")
	_army(gs, "gnomes", 10, Vector2(1000, 1000))
	var t: Dictionary = director._best_post_target("gnomes",
		director._command_post_list(), Vector2(1000, 1000))
	_check("war priority: monastery outranks crystal",
		String(t.get("kind", "")) == "monastery")
	_free_game(parts)


## A non-war enemy town is never a valid target (no peacetime grabs).
func _test_peacetime_town_not_targeted() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var t: Dictionary = director._best_post_target("gnomes",
		director._command_post_list(), Vector2(1000, 1000))
	_check("peacetime: no post target", t.is_empty())
	_free_game(parts)


## The "monastery" maneuver branch now considers ALL post types.
func _test_maneuver_branch_uses_all_posts() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_crystal(gs, 8, "", Vector2(1400, 1000))
	_army(gs, "gnomes", 10, Vector2(1000, 1000))
	var st: Dictionary = _st(gs, director, "gnomes")
	st["maneuver"] = "monastery"
	director._maneuver("gnomes", director._hall("gnomes"), st)
	var marked := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if int(u.get("crystal_march", -1)) == 8:
			marked += 1
	_check("monastery maneuver branch claims crystal", marked > 0)
	_free_game(parts)


## Legacy marks (monastery_march/monastery_guard/crystal_march) are still
## set alongside the unified marks — old flows keep working.
func _test_legacy_marks_still_set() -> void:
	var parts: Array = _make_game()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	_monastery(gs, 9, "", Vector2(1400, 1000))
	_army(gs, "gnomes", 10, Vector2(1000, 1000))
	var st: Dictionary = _st(gs, director, "gnomes")
	director._seek_command_posts("gnomes", st)
	var legacy := 0
	var unified := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "gnomes":
			continue
		if int(u.get("monastery_march", -1)) == 9:
			legacy += 1
		var pm := u.get("post_march", {}) as Dictionary
		if String(pm.get("kind", "")) == "monastery" \
				and int(pm.get("id", -1)) == 9:
			unified += 1
	_check("legacy monastery_march still set", legacy == 4)
	_check("unified post_march set in parallel", unified == 4)
	_free_game(parts)
