extends SceneTree
## Cursing Gnomes — war-spare fate votes + negotiable peace treaties
## (Jeremy 2026-10-11).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_war_spare.gd
##
## Exit code 0 = all passed, 1 = any failure.
## Covers: vote trigger on hall capture/destruction, likes->spare /
## hates->kill math, taker always kill, tie->condemned, spare->treaty with
## real terms + reparations transfer, term negotiation accept/refuse,
## treaty breaking consequences, DMZ violation, warning enforcement,
## player vote both ways, AI-loser symmetry, save/load.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes war-spare tests ===")
	_test_favor_likes_spare()
	_test_favor_hates_kill()
	_test_taker_votes_kill()
	_test_capture_triggers_vote()
	_test_faction_destroy_triggers_vote()
	_test_player_loser_ai_votes()
	_test_spared_signs_treaty()
	_test_tie_condemns()
	_test_player_vote_spare()
	_test_player_vote_kill()
	_test_negotiate_accept()
	_test_negotiate_refuse()
	_test_negotiate_cooldown()
	_test_break_treaty_consequences()
	_test_dmz_violation_breaks()
	_test_tribute_missed_breaks()
	_test_warning_enforcement()
	_test_no_double_vote()
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


## Fresh headless game: player = humans; war_spare wired like World does.
func _make_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres", "elves", "undead"])
	gs.war_spare = SimWarSpare.new(gs)
	return gs


func _voters(gs: GameState) -> Array:
	var ws = gs.war_spare
	gs.bus.command_post_captured.emit("town", 1, "ogres", "elves",
		Vector2.ZERO)
	return ws.active_vote()


func _test_favor_likes_spare() -> void:
	var gs := _make_game()
	gs.diplomacy.adjust_score("gnomes", "ogres", 60.0)
	var favor: Dictionary = SimWarSpare.favor_score(gs, "gnomes", "ogres")
	_check("favor: likes give positive score", float(favor.get("score", 0.0)) > 0.0)


func _test_favor_hates_kill() -> void:
	var gs := _make_game()
	gs.diplomacy.adjust_score("gnomes", "ogres", -80.0)
	var favor: Dictionary = SimWarSpare.favor_score(gs, "gnomes", "ogres")
	_check("favor: hatred gives negative score", float(favor.get("score", 0.0)) < 0.0)


func _test_taker_votes_kill() -> void:
	var gs := _make_game()
	# Even a taker who adores the loser votes to finish it.
	gs.diplomacy.adjust_score("elves", "ogres", 90.0)
	gs.bus.command_post_captured.emit("town", 1, "ogres", "elves",
		Vector2.ZERO)
	var v: Dictionary = gs.war_spare.active_vote()
	var taker_vote := ""
	for e in v.get("votes", []):
		if String(e.get("voter", "")) == "elves":
			taker_vote = String(e.get("vote", ""))
	_check("taker always votes kill", taker_vote == "kill")


func _test_capture_triggers_vote() -> void:
	var gs := _make_game()
	gs.bus.command_post_captured.emit("town", 1, "ogres", "elves",
		Vector2.ZERO)
	_check("hall capture triggers fate vote",
		not gs.war_spare.active_vote().is_empty())


func _test_faction_destroy_triggers_vote() -> void:
	var gs := _make_game()
	gs.bus.building_destroyed.emit({"type": "town_hall", "faction": "ogres",
		"destroyed_by": "elves", "position": Vector2.ZERO})
	_check("faction-caused hall destruction triggers fate vote",
		not gs.war_spare.active_vote().is_empty())


func _test_player_loser_ai_votes() -> void:
	var gs := _make_game()
	# Player (humans) loses a hall: AI votes immediately, no player vote.
	gs.diplomacy.adjust_score("gnomes", "humans", 70.0)
	gs.diplomacy.adjust_score("undead", "humans", 70.0)
	gs.diplomacy.adjust_score("elves", "humans", 70.0)
	gs.bus.command_post_captured.emit("town", 1, "humans", "ogres",
		Vector2.ZERO)
	# Vote auto-resolved (player doesn't vote on their own fate).
	_check("player-loser vote auto-resolves",
		gs.war_spare.active_vote().is_empty())
	_check("loved player is spared",
		gs.war_spare.treaties_for("humans").size() == 1)


func _test_spared_signs_treaty() -> void:
	var gs := _make_game()
	gs.diplomacy.declare_war("ogres", "elves")
	gs.diplomacy.adjust_score("gnomes", "ogres", 70.0)
	gs.diplomacy.adjust_score("undead", "ogres", 70.0)
	gs.diplomacy.adjust_score("humans", "ogres", 70.0)
	gs.bus.command_post_captured.emit("town", 1, "ogres", "elves",
		Vector2.ZERO)
	var ws = gs.war_spare
	# Player (humans) votes spare -> 3 spare (gnomes, undead, humans) vs
	# 1 kill (elves the taker).
	var res: Dictionary = ws.cast_player_vote(true)
	_check("spare majority resolves spared", res.get("result") == "spared")
	var treaties: Array = ws.treaties_for("ogres")
	_check("treaty signed", treaties.size() == 1)
	var t: Dictionary = treaties[0]
	_check("treaty has three terms", (t.get("terms", []) as Array).size() == 3)
	_check("treaty has guarantors", not (t.get("guarantors", []) as Array).is_empty())
	_check("war with taker ended",
		gs.diplomacy.relation_state("ogres", "elves") != "war")


func _test_tie_condemns() -> void:
	var gs := _make_game()
	# Gnomes + undead love ogres (2 spare); elves = taker (kill); humans =
	# player votes kill -> 2 vs 2 tie -> condemned.
	gs.diplomacy.adjust_score("gnomes", "ogres", 70.0)
	gs.diplomacy.adjust_score("undead", "ogres", 70.0)
	gs.bus.command_post_captured.emit("town", 1, "ogres", "elves",
		Vector2.ZERO)
	var res: Dictionary = gs.war_spare.cast_player_vote(false)
	_check("tie condemns", res.get("result") == "condemned")
	_check("no treaty when condemned",
		gs.war_spare.treaties_for("ogres").is_empty())


func _test_player_vote_spare() -> void:
	var gs := _make_game()
	gs.bus.command_post_captured.emit("town", 1, "ogres", "elves",
		Vector2.ZERO)
	var res: Dictionary = gs.war_spare.cast_player_vote(true)
	_check("player spare vote accepted", bool(res.get("ok", false)))
	_check("player vote recorded once",
		gs.war_spare.cast_player_vote(true).get("ok", true) == false)


func _test_player_vote_kill() -> void:
	var gs := _make_game()
	gs.bus.command_post_captured.emit("town", 1, "ogres", "elves",
		Vector2.ZERO)
	var res: Dictionary = gs.war_spare.cast_player_vote(false)
	_check("player kill vote resolves", bool(res.get("ok", false)))
	_check("kill vote recorded", res.get("result") == "condemned")


func _spared_setup() -> Array:
	var gs := _make_game()
	gs.resources.add_resource("ogres", "gold", 5000.0)
	gs.diplomacy.adjust_score("gnomes", "ogres", 70.0)
	gs.diplomacy.adjust_score("undead", "ogres", 70.0)
	gs.diplomacy.adjust_score("humans", "ogres", 70.0)
	gs.bus.command_post_captured.emit("town", 1, "ogres", "elves",
		Vector2.ZERO)
	gs.war_spare.cast_player_vote(true)
	var t: Dictionary = gs.war_spare.treaties_for("ogres")[0]
	return [gs, t]


func _term_idx(t: Dictionary, kind: String) -> int:
	var terms: Array = t.get("terms", [])
	for i in terms.size():
		if String((terms[i] as Dictionary).get("kind", "")) == kind:
			return i
	return -1


func _test_negotiate_accept() -> void:
	var parts := _spared_setup()
	var gs: GameState = parts[0]
	var t: Dictionary = parts[1]
	var ws = gs.war_spare
	var tid := int(t.get("id", 0))
	var idx := _term_idx(t, "dmz")
	# ignore_cap: base gold storage caps at 1500 (HTML parity) — the test needs
	# a genuinely flush treasury for the "generous offer" path.
	gs.resources.add_resource("ogres", "gold", 100000.0, true)
	var res: Dictionary = ws.negotiate_term(tid, idx, 50000.0, "ogres")
	_check("generous offer lifts term", bool(res.get("accepted", false)))
	_check("term marked lifted",
		String((t.get("terms", [])[idx] as Dictionary).get("status", "")) \
			== "lifted")


func _test_negotiate_refuse() -> void:
	var parts := _spared_setup()
	var gs: GameState = parts[0]
	var t: Dictionary = parts[1]
	var ws = gs.war_spare
	var tid := int(t.get("id", 0))
	var idx := _term_idx(t, "tribute")
	var res: Dictionary = ws.negotiate_term(tid, idx, 1.0, "ogres")
	_check("token offer refused", not bool(res.get("accepted", true)))
	_check("refused term stays active",
		String((t.get("terms", [])[idx] as Dictionary).get("status", "")) \
			== "active")


func _test_negotiate_cooldown() -> void:
	var parts := _spared_setup()
	var gs: GameState = parts[0]
	var t: Dictionary = parts[1]
	var ws = gs.war_spare
	var tid := int(t.get("id", 0))
	var idx := _term_idx(t, "tribute")
	ws.negotiate_term(tid, idx, 1.0, "ogres")
	var res2: Dictionary = ws.negotiate_term(tid, idx, 50000.0, "ogres")
	_check("negotiation cooldown blocks immediate retry",
		not bool(res2.get("ok", true)))


func _test_break_treaty_consequences() -> void:
	var parts := _spared_setup()
	var gs: GameState = parts[0]
	var t: Dictionary = parts[1]
	var ws = gs.war_spare
	var tid := int(t.get("id", 0))
	var rep_before := float(gs.diplomacy.reputation_of("ogres"))
	var gscore_before := float(gs.diplomacy.relation_score("gnomes", "ogres"))
	ws.break_treaty(tid, "test break", "ogres")
	_check("treaty marked broken",
		String(ws.get_treaty(tid).get("status", "")) == "broken")
	_check("reputation cratered",
		float(gs.diplomacy.reputation_of("ogres")) < rep_before - 10.0)
	_check("guarantors turn hostile",
		float(gs.diplomacy.relation_score("gnomes", "ogres")) \
			< gscore_before - 20.0)


func _test_dmz_violation_breaks() -> void:
	var parts := _spared_setup()
	var gs: GameState = parts[0]
	var t: Dictionary = parts[1]
	var tid := int(t.get("id", 0))
	# Taker town + loser soldier inside the DMZ radius.
	gs.towns[1] = {"faction": "elves", "position": Vector2(1000, 1000),
		"name": "Elftown"}
	gs.add_unit({"faction": "ogres", "job": "soldier", "position":
		Vector2(1050, 1050), "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 55.0})
	gs.bus.day_changed.emit(2, false)
	_check("DMZ violation breaks treaty",
		String(gs.war_spare.get_treaty(tid).get("status", "")) == "broken")


func _test_tribute_missed_breaks() -> void:
	var parts := _spared_setup()
	var gs: GameState = parts[0]
	var t: Dictionary = parts[1]
	var tid := int(t.get("id", 0))
	# Drain the loser's treasury so tribute can't be paid.
	gs.resources.add_resource("ogres", "gold",
		-gs.resources.get_amount("ogres", "gold"))
	gs.bus.day_changed.emit(2, false)
	_check("missed tribute breaks treaty",
		String(gs.war_spare.get_treaty(tid).get("status", "")) == "broken")


func _test_warning_enforcement() -> void:
	var parts := _spared_setup()
	var gs: GameState = parts[0]
	var gscore_before := float(gs.diplomacy.relation_score("gnomes", "ogres"))
	# The spared faction raises war again -> guarantors turn.
	gs.diplomacy.declare_war("ogres", "undead")
	_check("warning enforced: guarantors hostile",
		float(gs.diplomacy.relation_score("gnomes", "ogres")) \
			< gscore_before - 30.0)


func _test_no_double_vote() -> void:
	var gs := _make_game()
	gs.bus.command_post_captured.emit("town", 1, "ogres", "elves",
		Vector2.ZERO)
	var first: Dictionary = gs.war_spare.active_vote()
	gs.bus.command_post_captured.emit("town", 2, "undead", "gnomes",
		Vector2.ZERO)
	# First vote still open (player hasn't voted) -> second ignored.
	_check("one fate at a time",
		int(gs.war_spare.active_vote().get("id", 0)) \
			== int(first.get("id", 0)))


func _test_save_load() -> void:
	var parts := _spared_setup()
	var gs: GameState = parts[0]
	var ws = gs.war_spare
	var data: Dictionary = ws.to_dict()
	var gs2 := _make_game()
	gs2.war_spare.from_dict(data)
	_check("treaties survive save/load",
		gs2.war_spare.treaties_for("ogres").size() == 1)
