extends SceneTree
## Cursing Gnomes — AI betrayal tests (diplomacy).
##
## The HTML AI never attacked friends (war32AiWarTick: "never attack
## friends"); the Godot port deliberately improves on that: treacherous
## factions (high aggro, low honor) may betray an alliance, principled
## ones (elves) never do, and the player always gets a warning petition
## instead of a silent knife.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_diplomacy_betrayal.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes diplomacy betrayal tests ===")
	_test_honorable_never_betray()
	_test_no_instant_backstab()
	_test_betrayal_fires()
	_test_grudge_motive()
	_test_betrayal_consequences()
	_test_player_warning_petition()
	_test_betrayal_petition_bribe()
	_test_betrayal_petition_war()
	_test_betrayal_cooldown()
	_test_save_roundtrip()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	return {"gs": gs, "dip": gs.diplomacy}


func _court_world() -> Dictionary:
	var w: Dictionary = _new_world()
	var court := SimRoyalCourt.new(w["gs"])
	court.diplomacy = w["dip"]
	(w["dip"] as SimDiplomacy).court = court
	return {"gs": w["gs"], "dip": w["dip"], "court": court}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	return (w["gs"] as GameState).spawner.spawn_unit(faction, job, -1, pos)


## Form an alliance and age it past the no-instant-backstabbing window.
func _aged_alliance(dip: SimDiplomacy, a: String, b: String) -> void:
	dip.form_alliance(a, b)
	var rec: Dictionary = dip._pair(a, b)
	rec["allied_since_day"] = -20


## Ogres get overwhelming strength over gnomes (10 soldiers vs 1).
func _ogres_dominant(w: Dictionary) -> void:
	for i: int in range(10):
		_spawn(w, "ogres", "soldier", Vector2(100 + i * 8, 0))
	_spawn(w, "gnomes", "soldier", Vector2(400, 0))


func _consider(dip: SimDiplomacy, a: String, b: String) -> void:
	dip._ai_consider_betrayal(a, b, dip.faction_traits(a),
		dip.military_strength(a), dip.military_strength(b))


## --- the oathkeepers --------------------------------------------------------


func _test_honorable_never_betray() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	# Elves (honor 1.0) allied with gnomes, elves overwhelmingly stronger.
	_aged_alliance(dip, "elves", "gnomes")
	for i: int in range(12):
		_spawn(w, "elves", "soldier", Vector2(100 + i * 8, 0))
	_spawn(w, "gnomes", "soldier", Vector2(400, 0))
	for i: int in range(60):
		_consider(dip, "elves", "gnomes")
	_check("betrayal: principled elves never betray",
		dip.relation_state("elves", "gnomes") == "allied")
	_free_world(w)


func _test_no_instant_backstab() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	# Ogres would love to betray (default traits: aggro 1.0, honor 0.60)
	# but the ink is still wet on the treaty signed today (day 1).
	dip.form_alliance("ogres", "gnomes")
	_ogres_dominant(w)
	for i: int in range(60):
		_consider(dip, "ogres", "gnomes")
	_check("betrayal: no backstabbing a fresh alliance",
		dip.relation_state("ogres", "gnomes") == "allied")
	_free_world(w)


## --- the knife --------------------------------------------------------------


func _test_betrayal_fires() -> void:
	var w: Dictionary = _court_world()
	var dip: SimDiplomacy = w["dip"]
	dip.set_faction_traits("ogres", {
		"aggro": 1.0, "honor_value": 0.0, "brave": 1.0,
		"friendly": 0.2, "proud": 0.6, "tribute_value": 0.95})
	_aged_alliance(dip, "ogres", "gnomes")
	_ogres_dominant(w)
	var fired := false
	for i: int in range(400):
		_consider(dip, "ogres", "gnomes")
		if dip.relation_state("ogres", "gnomes") == "war":
			fired = true
			break
	_check("betrayal: treacherous ogres turn on a weak ally", fired)
	_free_world(w)


func _test_grudge_motive() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	# No strength advantage at all — but the gnomes wronged the ogres
	# once, and old wounds fester under the treaty.
	dip.set_faction_traits("ogres", {
		"aggro": 1.0, "honor_value": 0.0, "brave": 1.0,
		"friendly": 0.2, "proud": 0.6, "tribute_value": 0.95})
	_aged_alliance(dip, "ogres", "gnomes")
	# Two past wrongs outweigh the warmth of the signed treaty (+1.5).
	dip._record("ogres", "gnomes", "war_declared", "gnomes")
	dip._record("ogres", "gnomes", "war_declared", "gnomes")
	var fired := false
	for i: int in range(400):
		_consider(dip, "ogres", "gnomes")
		if dip.relation_state("ogres", "gnomes") == "war":
			fired = true
			break
	_check("betrayal: festering grudge is motive enough", fired)
	_free_world(w)


func _test_betrayal_consequences() -> void:
	var w: Dictionary = _court_world()
	var dip: SimDiplomacy = w["dip"]
	var court: SimRoyalCourt = w["court"]
	_aged_alliance(dip, "ogres", "gnomes")
	var rep_before: float = dip.reputation_of("ogres")
	var res: Dictionary = dip._betray("ogres", "gnomes")
	_check("betrayal: war declared", bool(res.get("ok", false)))
	_check("betrayal: state is war",
		dip.relation_state("ogres", "gnomes") == "war")
	_check("betrayal: reputation cost",
		dip.reputation_of("ogres") < rep_before)
	_check("betrayal: victim holds a grudge",
		dip.grudge_against("gnomes", "ogres") < -1.0)
	var headlines: String = " ".join(
		(court.stories.map(func(s: Dictionary) -> String:
			return String(s.get("headline", "")))))
	_check("betrayal: Gazette runs a BETRAYAL! headline",
		headlines.contains("BETRAYAL!"))
	_free_world(w)


## --- the player always gets a warning ---------------------------------------


## Build the player-facing scenario: ogres allied with the player's
## humans, treacherous, dominant, treaty aged. Returns the world plus the
## betrayal petition (or {} when none fired — a test failure).
func _player_betrayal_setup() -> Dictionary:
	var w: Dictionary = _court_world()
	var gs: GameState = w["gs"]
	var dip: SimDiplomacy = w["dip"]
	var court: SimRoyalCourt = w["court"]
	dip.set_faction_traits("ogres", {
		"aggro": 1.0, "honor_value": 0.0, "brave": 1.0,
		"friendly": 0.2, "proud": 0.6, "tribute_value": 0.95})
	_aged_alliance(dip, "ogres", "humans")  # humans = player faction
	_ogres_dominant(w)
	# The strength motive needs the victim to field at least one soldier.
	_spawn(w, "humans", "soldier", Vector2(500, 0))
	# An envoy must exist to carry the warning to the court.
	_spawn(w, "ogres", "worker", Vector2(200, 200))
	gs.resources.add_resource("humans", "gold", 200.0)
	var petition := {}
	for i: int in range(400):
		_consider(dip, "ogres", "humans")
		for p: Dictionary in court.petitions:
			if String(p.get("kind", "")) == "betrayal" \
					and not bool(p.get("resolved", false)):
				petition = p
				break
		if not petition.is_empty():
			break
	return {"gs": gs, "dip": dip, "court": court, "petition": petition,
		"world": w}


func _test_player_warning_petition() -> void:
	var s: Dictionary = _player_betrayal_setup()
	var dip: SimDiplomacy = s["dip"]
	_check("betrayal: player gets a warning petition",
		not (s["petition"] as Dictionary).is_empty())
	_check("betrayal: no silent knife — still allied while petition is open",
		dip.relation_state("ogres", "humans") == "allied")
	_free_world(s["world"])


func _test_betrayal_petition_bribe() -> void:
	var s: Dictionary = _player_betrayal_setup()
	var gs: GameState = s["gs"]
	var dip: SimDiplomacy = s["dip"]
	var court: SimRoyalCourt = s["court"]
	var petition: Dictionary = s["petition"]
	_check("betrayal bribe: petition exists", not petition.is_empty())
	if petition.is_empty():
		_free_world(s["world"])
		return
	var humans_gold: float = gs.resources.get_amount("humans", "gold")
	var ogre_gold: float = gs.resources.get_amount("ogres", "gold")
	court.decide(int(petition["id"]), 0)  # "Bribe them (60 gold)"
	_check("betrayal bribe: alliance holds",
		dip.relation_state("ogres", "humans") == "allied")
	_check("betrayal bribe: gold moved",
		gs.resources.get_amount("humans", "gold") == humans_gold - 60.0 \
		and gs.resources.get_amount("ogres", "gold") == ogre_gold + 60.0)
	_free_world(s["world"])


func _test_betrayal_petition_war() -> void:
	var s: Dictionary = _player_betrayal_setup()
	var dip: SimDiplomacy = s["dip"]
	var court: SimRoyalCourt = s["court"]
	var petition: Dictionary = s["petition"]
	_check("betrayal war: petition exists", not petition.is_empty())
	if petition.is_empty():
		_free_world(s["world"])
		return
	court.decide(int(petition["id"]), 1)  # "Let them come"
	_check("betrayal war: spurned ally declares war",
		dip.relation_state("ogres", "humans") == "war")
	_check("betrayal war: betrayer pays the infamy price",
		dip.reputation_of("ogres") < 60.0)
	_free_world(s["world"])


func _test_betrayal_cooldown() -> void:
	var s: Dictionary = _player_betrayal_setup()
	var dip: SimDiplomacy = s["dip"]
	var court: SimRoyalCourt = s["court"]
	var petition: Dictionary = s["petition"]
	if petition.is_empty():
		_check("betrayal cooldown: petition exists", false)
		_free_world(s["world"])
		return
	court.decide(int(petition["id"]), 0)  # bribe: loyalty bought
	# The AI simmers down: no second warning petition right away.
	var rec: Dictionary = dip._pair("ogres", "humans")
	_check("betrayal cooldown: quiet period recorded",
		int(rec.get("betrayal_cooldown_until", 0)) > 1)
	for i: int in range(60):
		_consider(dip, "ogres", "humans")
	var second := false
	for p: Dictionary in court.petitions:
		if String(p.get("kind", "")) == "betrayal" \
				and not bool(p.get("resolved", false)):
			second = true
	_check("betrayal cooldown: no repeat petition during quiet period",
		not second)
	_free_world(s["world"])


## --- persistence ------------------------------------------------------------


func _test_save_roundtrip() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.form_alliance("elves", "gnomes")
	var data: Dictionary = dip.to_dict()
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var dip2: SimDiplomacy = gs2.diplomacy
	dip2.from_dict(data)
	_check("betrayal save: alliance restored",
		dip2.relation_state("elves", "gnomes") == "allied")
	var rec2: Dictionary = dip2._pair("elves", "gnomes")
	_check("betrayal save: allied_since_day restored",
		int(rec2.get("allied_since_day", -1)) == 1)
	gs2.free()
	_free_world(w)
