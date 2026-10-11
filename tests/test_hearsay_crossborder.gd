extends SceneTree
## Cursing Gnomes — hearsay border-crossing grapevine tests
## (Jeremy 2026-10-08, hearsay flesh-out run).
##
## Rumors used to circulate inside ONE faction forever: a teller only ever
## picked same-faction hearers, so the attacked side of a war often never
## heard the drums via the mill. Now every knower gets one cross-faction
## tell attempt per day, routed by kind and relationship.
##  - war news: the OTHER recorded side hears it (plots reach the
##    would-be target; conquests reach the loser's/taker's kin)
##  - slur/scandal + diplomacy news: allied realms
##  - disaster/death: allied realms
##  - everything else: a trickle into non-war realms
##  - only war news crosses a war border
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_crossborder.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay-crossborder tests ===")
	_test_war_cross_target_sides()
	_test_war_plot_cross_target()
	_test_conquest_cross_target()
	_test_war_no_sides_no_cross()
	_test_dip_news_allied()
	_test_dip_news_no_ally_no_cross()
	_test_slur_scandal_allied()
	_test_misc_trickle_open()
	_test_misc_all_war_no_cross()
	_test_war_reaches_attacked_faction()
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


func _spawn(gs: GameState, faction: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "alive": true})


func _war_rumor() -> Dictionary:
	return {"kind": "war", "side_a": "gnomes", "side_b": "ogres"}


func _test_war_cross_target_sides() -> void:
	var gs := _new_gs()
	var hs = _new_phone(gs).hearsay
	var r := _war_rumor()
	gs.diplomacy.declare_war("gnomes", "ogres")
	var t1: Dictionary = hs._cross_target({"faction": "gnomes"}, r)
	_check("war: declarer-side teller reaches the attacked faction",
		String(t1.get("faction", "")) == "ogres")
	var t2: Dictionary = hs._cross_target({"faction": "ogres"}, r)
	_check("war: attacked-side teller reaches the declarer faction",
		String(t2.get("faction", "")) == "gnomes")
	var t3: Dictionary = hs._cross_target({"faction": "elves"}, r)
	_check("war: third-party teller carries it to the attacked side",
		String(t3.get("faction", "")) == "ogres")
	_check("war cross chance is bounded (0.5)",
		float(t1.get("chance", 0.0)) == 0.5)
	gs.queue_free()


func _test_war_plot_cross_target() -> void:
	var gs := _new_gs()
	var hs = _new_phone(gs).hearsay
	var r := {"kind": "war", "side_a": "gnomes", "side_b": "ogres",
		"war_plot": true}
	var t1: Dictionary = hs._cross_target({"faction": "gnomes"}, r)
	_check("war plot: reaches the would-be target's taverns",
		String(t1.get("faction", "")) == "ogres")
	var r2 := {"kind": "war", "side_a": "gnomes", "side_b": "ogres",
		"plot_denied": true}
	var t2: Dictionary = hs._cross_target({"faction": "elves"}, r2)
	_check("denied plot: the would-be target hears the comedy",
		String(t2.get("faction", "")) == "ogres")
	gs.queue_free()


func _test_conquest_cross_target() -> void:
	var gs := _new_gs()
	var hs = _new_phone(gs).hearsay
	var r := {"kind": "war", "holder_old": "ogres", "holder_new": "gnomes"}
	var t1: Dictionary = hs._cross_target({"faction": "gnomes"}, r)
	_check("conquest: taker's kin tell the loser's kin of the shame",
		String(t1.get("faction", "")) == "ogres")
	var t2: Dictionary = hs._cross_target({"faction": "ogres"}, r)
	_check("conquest: loser's kin tell the taker's kin of the pride",
		String(t2.get("faction", "")) == "gnomes")
	var t3: Dictionary = hs._cross_target({"faction": "elves"}, r)
	_check("conquest: third party carries it to the loser's kin",
		String(t3.get("faction", "")) == "ogres")
	gs.queue_free()


func _test_war_no_sides_no_cross() -> void:
	var gs := _new_gs()
	var hs = _new_phone(gs).hearsay
	var t: Dictionary = hs._cross_target({"faction": "gnomes"}, {"kind": "war"})
	_check("war rumor with no recorded sides crosses nowhere",
		String(t.get("faction", "")) == "")
	gs.queue_free()


func _test_dip_news_allied() -> void:
	var gs := _new_gs()
	var hs = _new_phone(gs).hearsay
	gs.diplomacy.form_alliance("gnomes", "elves")
	var r := {"kind": "news", "dip": "trade"}
	var t: Dictionary = hs._cross_target({"faction": "gnomes"}, r)
	_check("diplomacy news: merchant caravans carry it to the ally",
		String(t.get("faction", "")) == "elves")
	_check("diplomacy news cross chance is 0.15",
		float(t.get("chance", 0.0)) == 0.15)
	gs.queue_free()


func _test_dip_news_no_ally_no_cross() -> void:
	var gs := _new_gs()
	var hs = _new_phone(gs).hearsay
	# No alliances formed: relations default to neutral — no ally, no cross.
	var r := {"kind": "news", "dip": "peace"}
	var t: Dictionary = hs._cross_target({"faction": "gnomes"}, r)
	_check("diplomacy news with no ally crosses nowhere",
		String(t.get("faction", "")) == "")
	gs.queue_free()


func _test_slur_scandal_allied() -> void:
	var gs := _new_gs()
	var hs = _new_phone(gs).hearsay
	gs.diplomacy.form_alliance("gnomes", "elves")
	var t1: Dictionary = hs._cross_target({"faction": "gnomes"}, {"kind": "slur"})
	_check("slur condemnation crosses into the allied realm",
		String(t1.get("faction", "")) == "elves")
	var t2: Dictionary = hs._cross_target({"faction": "gnomes"}, {"kind": "scandal"})
	_check("scandal crosses into the allied realm",
		String(t2.get("faction", "")) == "elves")
	gs.queue_free()


func _test_misc_trickle_open() -> void:
	var gs := _new_gs()
	var hs = _new_phone(gs).hearsay
	gs.diplomacy.declare_war("gnomes", "ogres")
	var t: Dictionary = hs._cross_target({"faction": "gnomes"}, {"kind": "misc"})
	var tf := String(t.get("faction", ""))
	_check("trader trickle: never crosses a war border", tf != "ogres")
	_check("trader trickle: goes to a non-war realm",
		tf == "elves" or tf == "humans" or tf == "undead")
	_check("trader trickle chance is a trickle (0.04)",
		float(t.get("chance", 0.0)) == 0.04)
	gs.queue_free()


func _test_misc_all_war_no_cross() -> void:
	var gs := _new_gs()
	var hs = _new_phone(gs).hearsay
	for f: String in ["ogres", "elves", "humans", "undead"]:
		gs.diplomacy.declare_war("gnomes", f)
	var t: Dictionary = hs._cross_target({"faction": "gnomes"}, {"kind": "misc"})
	_check("trader gossip stays home when every border is war",
		String(t.get("faction", "")) == "")
	gs.queue_free()


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	# Memories live on the unit dict; a fresh SimMemories reads them.
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _test_war_reaches_attacked_faction() -> void:
	# Full-mill integration: a war rumor seeded among the declarers must
	# cross the border so the attacked side fears the drums — the branch
	# that used to sit nearly dead.
	seed(20261008)
	var gs := _new_gs()
	var phone = _new_phone(gs)
	var hs = phone.hearsay
	gs.diplomacy.declare_war("gnomes", "ogres")
	var knower: Dictionary = _spawn(gs, "gnomes")
	for i in range(30):
		_spawn(gs, "gnomes")
	var ogres: Array = []
	for i in range(10):
		ogres.append(_spawn(gs, "ogres"))
	var r: Dictionary = hs.seed_rumor(
		"WAR with the ogres! The drums beat day and night.",
		"war", "ogres", 1.0, int(knower.get("id", 0)))
	r["side_a"] = "gnomes"
	r["side_b"] = "ogres"
	for day in range(8):
		hs.daily_tick()
	var rid: int = int(r.get("id", 0))
	var ogre_knower: Dictionary = {}
	for o: Dictionary in ogres:
		if (r["knowers"] as Array).has(int(o.get("id", 0))):
			ogre_knower = o
			break
	_check("war news crosses the border: an ogre becomes a knower",
		not ogre_knower.is_empty())
	if not ogre_knower.is_empty():
		_check("attacked side fears the drums (war_on_us memory)",
			_recalled(ogre_knower, "war_on_us", rid) > 0.0)
	gs.queue_free()
