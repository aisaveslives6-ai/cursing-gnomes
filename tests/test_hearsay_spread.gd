extends SceneTree
## Cursing Gnomes — hearsay spread-dynamics tests (Jeremy 2026-10-06).
##
## Covers the hearsay flesh-out run: spread zeal.
##  - unhinged NPCs are super-spreaders (wider caps, louder rolls)
##  - _spread_motivation: amused tellers push smears about disliked
##    targets harder; reluctant tellers barely whisper dirt about friends
##  - slur/scandal condemnation is contagious (wider caps)
##  - neutral rumors / targetless smears: no motivation delta
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_spread.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay-spread tests ===")
	_test_unhinged_super_spreader()
	_test_motivation_branches()
	_test_motivation_slur_scandal_misc()
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


func _new_gs() -> GameState:
	var gs = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.set_ruler_name("ass")
	return gs


func _new_phone(gs: GameState):
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return phone


func _spawn(gs: GameState, faction: String, mind: Dictionary = {}) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true, "mind": mind})


func _told_count(gs: GameState, unhinged: bool) -> int:
	# Flaked-proofing like the per-knower test: seed deterministically so
	# both runs draw the identical RNG stream up to the normal cap — the
	# unhinged knower's extra attempts can only ever ADD tells, never
	# remove them. Sim mechanics untouched.
	seed(20261006)
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var mind := {}
	if unhinged:
		mind = {"traits": {"unhinged": 1.0}}
	var knower: Dictionary = _spawn(gs, "gnomes", mind)
	for i in range(40):
		_spawn(gs, "gnomes")
	var r: Dictionary = hs.seed_rumor("News travels at the speed of gossip.",
		"news", "zealtest", 1.0, int(knower.get("id", 0)))
	hs.daily_tick()
	return (r["knowers"] as Array).size() - 1  # minus the original knower


func _test_unhinged_super_spreader() -> void:
	var gs_normal := _new_gs()
	var normal_told: int = _told_count(gs_normal, false)
	gs_normal.queue_free()
	var gs_unhinged := _new_gs()
	var unhinged_told: int = _told_count(gs_unhinged, true)
	gs_unhinged.queue_free()
	_check("unhinged knower spreads strictly wider than normal knower",
		unhinged_told > normal_told)
	print("  (info) normal told %d, unhinged told %d" % [normal_told, unhinged_told])


func _test_motivation_branches() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var teller: Dictionary = _spawn(gs, "gnomes")
	var target_u: Dictionary = _spawn(gs, "ogres")
	var tid: int = int(target_u.get("id", 0))
	# Gnomes at war with ogres: the teller's stance on an ogre target is
	# strongly negative (war -0.5 + personal hash) — amused territory.
	gs.diplomacy.declare_war("gnomes", "ogres")
	var r: Dictionary = hs.seed_rumor("The crown says Grak is a buffoon.",
		"smear", "grak", 0.8)
	r["target_id"] = tid
	r["target_name"] = "Grak"
	r["target_faction"] = "ogres"
	r["target_is_leader"] = true
	var stance := SimLikesDislikes.npc_stance(teller,
		{"id": tid, "name": "Grak", "faction": "ogres", "is_leader": true}, gs)
	var m: Dictionary = hs._spread_motivation(teller, r)
	if stance <= -0.3:
		_check("amused smear: cap up", int(m.get("cap_delta", 0)) == 1)
		_check("amused smear: heat up", float(m.get("heat_delta", 0.0)) > 0.0)
	elif stance >= 0.3:
		_check("reluctant smear: cap down", int(m.get("cap_delta", 0)) == -1)
		_check("reluctant smear: heat down", float(m.get("heat_delta", 0.0)) < 0.0)
	else:
		_check("neutral smear: no delta",
			int(m.get("cap_delta", 9)) == 0
			and float(m.get("heat_delta", 9.0)) == 0.0)
	gs.queue_free()


func _test_motivation_slur_scandal_misc() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var ku: Dictionary = _spawn(gs, "gnomes")
	var m1: Dictionary = hs._spread_motivation(ku, {"kind": "slur"})
	_check("slur condemnation spreads wider", int(m1.get("cap_delta", 0)) == 1)
	var m2: Dictionary = hs._spread_motivation(ku, {"kind": "scandal"})
	_check("scandal spreads wider", int(m2.get("cap_delta", 0)) == 1)
	var m3: Dictionary = hs._spread_motivation(ku, {"kind": "news"})
	_check("news has no motivation delta",
		int(m3.get("cap_delta", 9)) == 0
		and float(m3.get("heat_delta", 9.0)) == 0.0)
	var m4: Dictionary = hs._spread_motivation(ku, {"kind": "smear"})
	_check("smear without target has no delta",
		int(m4.get("cap_delta", 9)) == 0)
	gs.queue_free()
