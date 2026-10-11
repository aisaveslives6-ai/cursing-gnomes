extends SceneTree
## Cursing Gnomes — third-party war reaction tests (diplomacy).
##
## Checklist item: "War/peace responses: factions react to declarations".
## ruler_react_to only fired when the PLAYER declared or received war; the
## rest of the world stayed silent when two AI factions went at it. Now every
## third-party faction answers a declaration based on where it stands:
## allies of the victim condemn the aggressor (-12), allies of the aggressor
## chill the victim (-10), friends of the victim condemn (-8), enemies of the
## victim quietly cheer (+6), neutrals fret (voice only). One reaction per
## war per faction, never nudging a pair currently at war, and the player
## faction gets score shifts but no auto voice lines.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_war_reactions.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes third-party war reaction tests ===")
	_test_ally_of_victim_condemns()
	_test_ally_of_aggressor_chills_victim()
	_test_friend_of_victim_condemns()
	_test_enemy_of_victim_cheers()
	_test_neutral_no_score_shift()
	_test_dedupe_one_per_war()
	_test_at_war_pair_untouched()
	_test_player_gets_scores_no_voice()
	_test_lines_for_all_factions()
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


func _test_ally_of_victim_condemns() -> void:
	var w := _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.form_alliance("elves", "gnomes")
	_check("ally-of-victim alliance formed", dip.relation_state("elves", "gnomes") == "allied")
	dip.declare_war("ogres", "gnomes")
	_check("ally of victim condemns aggressor -12",
		is_equal_approx(dip.relation_score("elves", "ogres"), -12.0))
	_check("ally of victim still allied with victim",
		dip.relation_state("elves", "gnomes") == "allied")
	_check("war pair score pinned at -80",
		is_equal_approx(dip.relation_score("ogres", "gnomes"), -80.0))


func _test_ally_of_aggressor_chills_victim() -> void:
	var w := _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.form_alliance("undead", "ogres")
	dip.declare_war("ogres", "gnomes")
	# Standing by the aggressor chills the victim: the (undead, gnomes)
	# pair drops from 0 to -10 while the alliance itself holds at 75.
	_check("ally of aggressor chills victim -10",
		is_equal_approx(dip.relation_score("undead", "gnomes"), -10.0))
	_check("ally of aggressor keeps alliance",
		dip.relation_state("undead", "ogres") == "allied")


func _test_friend_of_victim_condemns() -> void:
	var w := _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip._adjust_relation_score("elves", "gnomes", 30.0)
	dip.declare_war("ogres", "gnomes")
	_check("friend of victim condemns aggressor -8",
		is_equal_approx(dip.relation_score("elves", "ogres"), -8.0))


func _test_enemy_of_victim_cheers() -> void:
	var w := _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip._adjust_relation_score("undead", "gnomes", -30.0)
	dip.declare_war("ogres", "gnomes")
	_check("enemy of victim cheers aggressor +6",
		is_equal_approx(dip.relation_score("undead", "ogres"), 6.0))


func _test_neutral_no_score_shift() -> void:
	var w := _new_world()
	var dip: SimDiplomacy = w["dip"]
	# Elves are neutral to everyone here: fret branch = voice only, maybe.
	dip.declare_war("ogres", "gnomes")
	_check("neutral third party score untouched (aggressor)",
		is_equal_approx(dip.relation_score("elves", "ogres"), 0.0))
	_check("neutral third party score untouched (victim)",
		is_equal_approx(dip.relation_score("elves", "gnomes"), 0.0))


func _test_dedupe_one_per_war() -> void:
	var w := _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.form_alliance("elves", "gnomes")
	dip.declare_war("ogres", "gnomes")
	var after_first: float = dip.relation_score("elves", "ogres")
	# Re-invoking the reaction pass for the same war must not stack.
	dip._third_party_war_reactions("ogres", "gnomes")
	dip._third_party_war_reactions("ogres", "gnomes")
	_check("one reaction per war per faction (no stacking)",
		is_equal_approx(dip.relation_score("elves", "ogres"), after_first))


func _test_at_war_pair_untouched() -> void:
	var w := _new_world()
	var dip: SimDiplomacy = w["dip"]
	dip.declare_war("elves", "ogres")  # elves already at war with the aggressor
	dip.form_alliance("elves", "gnomes")
	dip.declare_war("ogres", "gnomes")
	# Elves are allied with the victim, but their score with ogres is pinned
	# at -80 by the existing war — the reaction must not nudge it.
	_check("at-war pair score not nudged",
		is_equal_approx(dip.relation_score("elves", "ogres"), -80.0))


func _test_player_gets_scores_no_voice() -> void:
	var w := _new_world()
	var dip: SimDiplomacy = w["dip"]
	# In the harness the player faction is "humans" (first in setup list).
	_check("harness player is humans",
		String((w["gs"] as GameState).player_faction) == "humans")
	# Attach a court so voiced reactions land in queryable stories.
	var court := SimRoyalCourt.new(w["gs"])
	court.diplomacy = dip
	dip.court = court
	# Elves are warm to the victim so their voice line must publish.
	dip._adjust_relation_score("elves", "gnomes", 30.0)
	dip._adjust_relation_score("humans", "gnomes", 30.0)
	dip.declare_war("ogres", "gnomes")
	_check("player score shifts like anyone else",
		is_equal_approx(dip.relation_score("humans", "ogres"), -8.0))
	var headlines: Array = court.stories.map(
		func(s: Dictionary) -> String: return String(s.get("headline", "")))
	var player_voiced := false
	var elf_voiced := false
	for h: String in headlines:
		if "Humans of the Humans reacts" in h:
			player_voiced = true
		if "Elves of the Elves reacts" in h:
			elf_voiced = true
	_check("player faction gets no auto voice line", not player_voiced)
	_check("third-party AI voice line still publishes", elf_voiced)


func _test_lines_for_all_factions() -> void:
	var w := _new_world()
	var dip: SimDiplomacy = w["dip"]
	var factions := ["humans", "ogres", "elves", "gnomes", "undead"]
	var stances := ["stand_victim", "stand_aggressor", "condemn", "cheer", "fret"]
	var all_ok := true
	for f: String in factions:
		for s: String in stances:
			var line: String = dip._war_news_line(f, s, "ogres", "gnomes")
			if line == "" or not ("Ogres" in line or "OGRES" in line) \
					or not ("Gnomes" in line or "GNOMES" in line):
				all_ok = false
	_check("voiced line for every faction x stance, naming both sides", all_ok)
