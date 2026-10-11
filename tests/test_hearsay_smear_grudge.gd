extends SceneTree
## Cursing Gnomes — smear→grudge ledger tests (Jeremy 2026-10-10 hearsay
## flesh-out).
##
## Rumor-borne fury feeds the conversation grudge ledger, completing the
## emotional arc: smear -> grudge -> apology -> forgiveness. A player smear
## the target hears lands like a direct insult (insult parity, +8);
## defenders and told-targets carry half weight (+4); the amused and the
## neutral carry none. NPC-sourced smears never touch the player-directed
## ledger (the target's fury lands on the liar, not the crown). Slur
## smears seed nothing (the hard line holds — verified by the existing
## slur guardrail tests, re-asserted here for the ledger path).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_smear_grudge.gd
##
## Exit code 0 = all passed, 1 = any failure.


const FACTIONS := ["humans", "ogres", "elves", "gnomes", "undead"]

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes smear-grudge tests ===")
	_test_target_hears_player_smear_grudge()
	_test_defender_hears_player_smear_grudge()
	_test_rival_hears_player_smear_no_grudge()
	_test_neutral_hears_player_smear_no_grudge()
	_test_npc_smear_target_no_player_grudge()
	_test_repeat_smear_stacks_like_insults()
	_test_grudge_decays_over_days()
	_test_no_phone_no_crash()
	_test_slur_smear_seeds_no_grudge()
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
	var farr: Array[String] = []
	farr.assign(FACTIONS)
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.set_ruler_name("ass")
	return gs


func _new_phone(gs: GameState):
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return phone


func _spawn(gs: GameState, faction: String, unit_name: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true,
		"name": unit_name, "mind": {}})


## Find a hearer/target pair whose stance clears (or stays inside) a band.
func _find_pair(gs: GameState, hearer_faction: String,
		target_faction: String, band: String) -> Array:
	var hearers: Array = []
	var targets: Array = []
	for i in range(12):
		hearers.append(_spawn(gs, hearer_faction, "H%d" % i))
		targets.append(_spawn(gs, target_faction, "T%d" % i))
	for h in hearers:
		for t in targets:
			var s: float = SimLikesDislikes.npc_stance(h,
				{"id": int(t.get("id", 0)),
					"faction": target_faction, "name": "Tx",
					"is_leader": false}, gs)
			if band == "high" and s >= 0.3:
				return [h, t]
			if band == "low" and s <= -0.3:
				return [h, t]
			if band == "mid" and absf(s) < 0.3:
				return [h, t]
	return []


func _smear_target_dict(tid: int, faction: String) -> Dictionary:
	return {"name": "Tx", "id": tid, "faction": faction,
		"is_leader": false, "key": "npc:%d" % tid, "insult": "idiot",
		"phrase": "is an idiot"}


# --- Smear -> grudge ledger ------------------------------------------


func _test_target_hears_player_smear_grudge() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var target := _spawn(gs, "ogres", "Grak")
	var tid := int(target.get("id", 0))
	_check("grudge: target starts clean",
		phone.conversation.grudge_strength(tid, gs) == 0.0)
	var r: Dictionary = hs.seed_player_smear(
		_smear_target_dict(tid, "ogres"), "Tx is an idiot", "idiot", tid)
	_check("grudge: smear seeded", not r.is_empty())
	_check("grudge: target holds insult-weight grudge",
		phone.conversation.grudge_strength(tid, gs) == 8.0)
	gs.queue_free()


func _test_defender_hears_player_smear_grudge() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	# Same faction: loyalty (+0.4) usually clears the defend threshold.
	var pair := _find_pair(gs, "ogres", "ogres", "high")
	_check("grudge: found like-pair", not pair.is_empty())
	if pair.is_empty():
		gs.queue_free()
		return
	var hearer: Dictionary = pair[0]
	var target: Dictionary = pair[1]
	var tid := int(target.get("id", 0))
	var hid := int(hearer.get("id", 0))
	hs.seed_player_smear(
		_smear_target_dict(tid, "ogres"), "Tx is an idiot", "idiot", hid)
	_check("grudge: defender holds half-weight grudge",
		phone.conversation.grudge_strength(hid, gs) == 4.0)
	gs.queue_free()


func _test_rival_hears_player_smear_no_grudge() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.diplomacy.declare_war("elves", "ogres", "test")
	var pair := _find_pair(gs, "elves", "ogres", "low")
	_check("grudge: found dislike-pair", not pair.is_empty())
	if pair.is_empty():
		gs.queue_free()
		return
	var hearer: Dictionary = pair[0]
	var target: Dictionary = pair[1]
	var tid := int(target.get("id", 0))
	var hid := int(hearer.get("id", 0))
	hs.seed_player_smear(
		_smear_target_dict(tid, "ogres"), "Tx is an idiot", "idiot", hid)
	# The rival is amused and warms to the player — no grudge.
	_check("grudge: rival holds no grudge",
		phone.conversation.grudge_strength(hid, gs) == 0.0)
	gs.queue_free()


func _test_neutral_hears_player_smear_no_grudge() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var pair := _find_pair(gs, "gnomes", "ogres", "mid")
	_check("grudge: found neutral-pair", not pair.is_empty())
	if pair.is_empty():
		gs.queue_free()
		return
	var hearer: Dictionary = pair[0]
	var target: Dictionary = pair[1]
	var tid := int(target.get("id", 0))
	var hid := int(hearer.get("id", 0))
	hs.seed_player_smear(
		_smear_target_dict(tid, "ogres"), "Tx is an idiot", "idiot", hid)
	_check("grudge: neutral holds no grudge",
		phone.conversation.grudge_strength(hid, gs) == 0.0)
	gs.queue_free()


func _test_npc_smear_target_no_player_grudge() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var liar := _spawn(gs, "ogres", "Liar")
	var target := _spawn(gs, "ogres", "Victim")
	var lid := int(liar.get("id", 0))
	var tid := int(target.get("id", 0))
	# NPC-invented smear: the target's fury lands on the liar, never the
	# player — the player-directed ledger must stay clean.
	var r: Dictionary = hs.seed_rumor("Word is Victim is an idiot.",
		"smear", "smear:%d" % tid, 0.65, -1, false, "false")
	r["player_sourced"] = false
	r["source_id"] = lid
	r["source_name"] = "Liar"
	r["target_id"] = tid
	r["target_name"] = "Victim"
	r["target_faction"] = "ogres"
	r["target_is_leader"] = false
	hs._on_heard(target, r, {})
	_check("grudge: npc-smear target holds no player grudge",
		phone.conversation.grudge_strength(tid, gs) == 0.0)
	_check("grudge: npc-smear liar holds no player grudge",
		phone.conversation.grudge_strength(lid, gs) == 0.0)
	gs.queue_free()


func _test_repeat_smear_stacks_like_insults() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var target := _spawn(gs, "ogres", "Grak")
	var tid := int(target.get("id", 0))
	hs.seed_player_smear(
		_smear_target_dict(tid, "ogres"), "Tx is an idiot", "idiot", tid)
	# Each seed_player_smear call is a distinct player speech act — the
	# rumor dedups to one object (see _test_rant_dedups), but the
	# offense is fresh each time, exactly like repeated chat insults
	# stacking insult_count and grudge in the ledger.
	hs.seed_player_smear(
		_smear_target_dict(tid, "ogres"), "Tx is an idiot", "idiot", tid)
	_check("grudge: repeat smears stack like repeat insults",
		phone.conversation.grudge_strength(tid, gs) == 16.0)
	gs.queue_free()


func _test_grudge_decays_over_days() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var target := _spawn(gs, "ogres", "Grak")
	var tid := int(target.get("id", 0))
	hs.seed_player_smear(
		_smear_target_dict(tid, "ogres"), "Tx is an idiot", "idiot", tid)
	gs.set("day_number", 5)
	# 4 days x 0.5 decay = 2.0 off the 8.0 insult-weight grudge.
	_check("grudge: ledger decay applies to rumor grudges",
		phone.conversation.grudge_strength(tid, gs) == 6.0)
	gs.queue_free()


func _test_no_phone_no_crash() -> void:
	var gs := _new_gs()
	# Bare sim: no phone attached — the grudge path must stay silent.
	var hs = SimHearsay.new(gs)
	var target := _spawn(gs, "ogres", "Grak")
	var tid := int(target.get("id", 0))
	var r: Dictionary = hs.seed_player_smear(
		_smear_target_dict(tid, "ogres"), "Tx is an idiot", "idiot", tid)
	_check("grudge: bare-sim smear seeds without crashing",
		not r.is_empty())
	gs.queue_free()


func _test_slur_smear_seeds_no_grudge() -> void:
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	var target := _spawn(gs, "ogres", "Grak")
	var tid := int(target.get("id", 0))
	# The hard line: slur text never becomes a smear rumor (routed to
	# the slur cascade instead), so the ledger path is never reached.
	var r: Dictionary = hs.seed_player_smear(
		{"name": "Tx", "id": tid, "faction": "ogres", "is_leader": false,
			"key": "npc:%d" % tid, "insult": "slur",
			"phrase": "was slurred by the crown"},
		"Tx is a kike", "kike", tid)
	_check("grudge: slur seeds no smear", r.is_empty())
	_check("grudge: slur seeds no ledger entry",
		phone.conversation.grudge_strength(tid, gs) == 0.0)
	gs.queue_free()
