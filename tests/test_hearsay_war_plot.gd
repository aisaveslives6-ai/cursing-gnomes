extends SceneTree
## Cursing Gnomes — hearsay war-plot tests (Jeremy 2026-10-08).
##
## Covers the hearsay flesh-out run: declare-war PROPOSAL rumors are no
## longer dead-end gossip. The proposal's target is recorded (side_a =
## plotter, side_b = target, war_plot=true) and the realm reacts in
## character via _war_plot_reaction:
##   - live plot: the TARGET's people fear the looming drums (mood down,
##     "attacked" emotion — brave NPCs get angry via stands_ground
##     parity); the PLOTTER's people grimly anticipate (mood up)
##   - denied plot: tavern comedy (plot_denied) — the would-be target
##     breathes relief, the plotters get roasted, everyone laughs
##   - anyone else, or a plot with no recorded target: generic reception
##   - an approved plot that becomes a real war clears war_plot and routes
##     to the full war matrix
##   - unhinged NPCs feel it 1.5x, matching the war path
##   - war_plot/plot_denied survive save/load; old saves backfill false
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_war_plot.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay war-plot tests ===")
	_test_plot_seeds_sides_and_names_target()
	_test_plot_target_fears()
	_test_plot_plotter_anticipates()
	_test_plot_third_party_generic()
	_test_plot_unhinged_amplified()
	_test_plot_denied_comedy()
	_test_plot_denied_fresh_seeds_sides()
	_test_plot_becomes_real_war()
	_test_plot_no_target_generic()
	_test_plot_save_roundtrip()
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


func _harness() -> Array:
	var gs := _new_gs()
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return [gs, phone, phone.hearsay]


func _spawn(gs: GameState, faction: String, unhinged: bool = false) -> Dictionary:
	var mind: Dictionary = {}
	if unhinged:
		mind = {"traits": {"unhinged": 1.0}}
	return gs.add_unit({"faction": faction, "alive": true, "mind": mind})


func _plot_rumor(hs) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "war" \
				and bool(r.get("war_plot", false)):
			return r
	return {}


func _seed_plot(gs: GameState, target: String = "ogres") -> void:
	var details: Dictionary = {}
	if target != "":
		details = {"target": target}
	gs.bus.strategic_proposal.emit({
		"id": 7, "faction": "elves", "kind": "declare_war",
		"details": details, "day": 1, "status": "open",
	})


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	# Memories live on the unit dict; a fresh SimMemories reads them.
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _test_plot_seeds_sides_and_names_target() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_seed_plot(gs, "ogres")
	var r: Dictionary = _plot_rumor(hs)
	_check("plot rumor seeded", not r.is_empty())
	_check("plot records plotter as side_a", String(r.get("side_a", "")) == "elves")
	_check("plot records target as side_b", String(r.get("side_b", "")) == "ogres")
	_check("plot marks war_plot", bool(r.get("war_plot", false)))
	_check("plot not denied", not bool(r.get("plot_denied", false)))
	_check("plot text names the target",
		String(r.get("text", "")).contains("Ogres"))
	gs.queue_free()


func _test_plot_target_fears() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var target: Dictionary = _spawn(gs, "ogres")
	var tid := int(target.get("id", 0))
	_seed_plot(gs, "ogres")
	var r: Dictionary = _plot_rumor(hs)
	var mood_before: float = conv.ruler_mood(tid)
	hs._on_heard(target, r, {})
	_check("target mood drops on war-plot news", conv.ruler_mood(tid) < mood_before)
	_check("target scared or angry (brave)", _emotion(target) == "scared" \
		or _emotion(target) == "angry")
	_check("target remembers war_plotted_on_us",
		_recalled(target, "war_plotted_on_us", int(r.get("id", 0))) > 0.0)
	gs.queue_free()


func _test_plot_plotter_anticipates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var plotter: Dictionary = _spawn(gs, "elves")
	var pid := int(plotter.get("id", 0))
	_seed_plot(gs, "ogres")
	var r: Dictionary = _plot_rumor(hs)
	var mood_before: float = conv.ruler_mood(pid)
	hs._on_heard(plotter, r, {})
	_check("plotter mood rises on war-plot news", conv.ruler_mood(pid) > mood_before)
	_check("plotter likes the news", _emotion(plotter) == "happy")
	_check("plotter remembers war_plotting",
		_recalled(plotter, "war_plotting", int(r.get("id", 0))) > 0.0)
	gs.queue_free()


func _test_plot_third_party_generic() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var neutral: Dictionary = _spawn(gs, "undead")
	_seed_plot(gs, "ogres")
	var r: Dictionary = _plot_rumor(hs)
	hs._on_heard(neutral, r, {})
	_check("third party gets generic reception",
		_recalled(neutral, "heard_rumor", int(r.get("id", 0))) > 0.0)
	_check("third party gets no plot memories",
		_recalled(neutral, "war_plotted_on_us", int(r.get("id", 0))) == 0.0 \
		and _recalled(neutral, "war_plotting", int(r.get("id", 0))) == 0.0)
	gs.queue_free()


func _test_plot_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	var sane: Dictionary = _spawn(gs, "ogres")
	var wild: Dictionary = _spawn(gs, "ogres", true)
	var sid := int(sane.get("id", 0))
	var wid := int(wild.get("id", 0))
	_seed_plot(gs, "ogres")
	var r: Dictionary = _plot_rumor(hs)
	var sane_before: float = conv.ruler_mood(sid)
	var wild_before: float = conv.ruler_mood(wid)
	hs._on_heard(sane, r, {})
	hs._on_heard(wild, r, {})
	var sane_drop: float = sane_before - conv.ruler_mood(sid)
	var wild_drop: float = wild_before - conv.ruler_mood(wid)
	_check("unhinged target fears the plot 1.5x harder", wild_drop > sane_drop)
	gs.queue_free()


func _test_plot_denied_comedy() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_seed_plot(gs, "ogres")
	var would_be_target: Dictionary = _spawn(gs, "ogres")
	var plotter: Dictionary = _spawn(gs, "elves")
	var bystander: Dictionary = _spawn(gs, "undead")
	var tid := int(would_be_target.get("id", 0))
	var pid := int(plotter.get("id", 0))
	var bid := int(bystander.get("id", 0))
	gs.bus.strategic_proposal_decided.emit({
		"id": 7, "faction": "elves", "kind": "declare_war",
		"details": {"target": "ogres"}, "day": 1, "status": "denied",
	}, false)
	var r: Dictionary = hs._live_rumor("war", "elves")
	_check("denied plot keeps one rumor", not r.is_empty())
	_check("denied plot flags plot_denied", bool(r.get("plot_denied", false)))
	_check("denied plot text still roasts",
		String(r.get("text", "")).contains("chickened out"))
	var t_before: float = conv.ruler_mood(tid)
	var p_before: float = conv.ruler_mood(pid)
	var b_before: float = conv.ruler_mood(bid)
	hs._on_heard(would_be_target, r, {})
	hs._on_heard(plotter, r, {})
	hs._on_heard(bystander, r, {})
	_check("would-be target breathes relief (mood up)",
		conv.ruler_mood(tid) > t_before)
	_check("would-be target remembers war_plot_dead",
		_recalled(would_be_target, "war_plot_dead", int(r.get("id", 0))) > 0.0)
	_check("plotter embarrassed (mood down)", conv.ruler_mood(pid) < p_before)
	_check("plotter remembers war_plot_chickened",
		_recalled(plotter, "war_plot_chickened", int(r.get("id", 0))) > 0.0)
	_check("plotter mocked (sad, or angry if proud)",
		_emotion(plotter) == "sad" or _emotion(plotter) == "angry")
	_check("bystander laughs (mood up)", conv.ruler_mood(bid) > b_before)
	gs.queue_free()


func _test_plot_denied_fresh_seeds_sides() -> void:
	# Denial with no prior proposal rumor still flags both sides.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.bus.strategic_proposal_decided.emit({
		"id": 9, "faction": "undead", "kind": "declare_war",
		"details": {"target": "humans"}, "day": 1, "status": "denied",
	}, false)
	var r: Dictionary = hs._live_rumor("war", "undead")
	_check("fresh denied rumor seeds", not r.is_empty())
	_check("fresh denied rumor is a flagged plot",
		bool(r.get("war_plot", false)) and bool(r.get("plot_denied", false)))
	_check("fresh denied rumor records sides",
		String(r.get("side_a", "")) == "undead" \
		and String(r.get("side_b", "")) == "humans")
	gs.queue_free()


func _test_plot_becomes_real_war() -> void:
	# The real flow: plot -> approved -> declared. The single rumor clears
	# war_plot and the full war matrix takes over.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_seed_plot(gs, "ogres")
	gs.bus.strategic_proposal_decided.emit({
		"id": 7, "faction": "elves", "kind": "declare_war",
		"details": {"target": "ogres"}, "day": 1, "status": "approved",
	}, true)
	gs.bus.war_declared.emit("elves", "ogres")
	var r: Dictionary = hs._live_rumor("war", "elves")
	_check("declared war reuses the plot rumor", not r.is_empty())
	_check("declared war clears war_plot", not bool(r.get("war_plot", false)))
	_check("declared war keeps both sides",
		String(r.get("side_a", "")) == "elves" \
		and String(r.get("side_b", "")) == "ogres")
	var defender: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(defender, r, {})
	_check("declared war routes to the war matrix (war_on_us)",
		_recalled(defender, "war_on_us", int(r.get("id", 0))) > 0.0)
	_check("no stale plot memory on the defender",
		_recalled(defender, "war_plotted_on_us", int(r.get("id", 0))) == 0.0)
	gs.queue_free()


func _test_plot_no_target_generic() -> void:
	# Defensive: a plot with no recorded target is just news, no crash.
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_seed_plot(gs, "")
	var r: Dictionary = _plot_rumor(hs)
	_check("targetless plot still seeds", not r.is_empty())
	_check("targetless plot has empty sides",
		String(r.get("side_a", "")) == "elves" \
		and String(r.get("side_b", "")) == "")
	var hearer: Dictionary = _spawn(gs, "ogres")
	hs._on_heard(hearer, r, {})
	_check("targetless plot falls through to generic reception",
		_recalled(hearer, "heard_rumor", int(r.get("id", 0))) > 0.0)
	_check("targetless plot leaves no plot memories",
		_recalled(hearer, "war_plotted_on_us", int(r.get("id", 0))) == 0.0)
	gs.queue_free()


func _test_plot_save_roundtrip() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_seed_plot(gs, "ogres")
	var d: Dictionary = hs.to_dict()
	var hs2 = load("res://scripts/sim/hearsay.gd").new(gs)
	hs2.from_dict(d)
	var found := false
	for r: Dictionary in hs2.state["rumors"]:
		if String(r.get("kind", "")) == "war" \
				and bool(r.get("war_plot", false)) \
				and String(r.get("side_a", "")) == "elves" \
				and String(r.get("side_b", "")) == "ogres" \
				and not bool(r.get("plot_denied", false)):
			found = true
	_check("war-plot flags survive save/load roundtrip", found)
	# Old saves: rumors without the new keys backfill to false/false.
	var hs3 = load("res://scripts/sim/hearsay.gd").new(gs)
	hs3.from_dict({"rumors": [{"id": 1, "kind": "war", "subject": "elves",
		"text": "x", "text_orig": "x", "day": 1, "heat": 0.8,
		"knowers": [], "reached_ruler": false, "distortions": 0,
		"from_gazette": false, "published": false, "truth": "unknown",
		"debunked": false, "verified": false, "quest_spawned": false,
		"witnesses": [], "doubters": []}], "seq": 2,
		"last_press_day": 0, "npc_rep": {}, "pending_caches": [],
		"holders": {}})
	var old_r: Dictionary = (hs3.state["rumors"] as Array)[0]
	_check("old saves backfill war_plot=false",
		old_r.has("war_plot") and not bool(old_r.get("war_plot", true)))
	_check("old saves backfill plot_denied=false",
		old_r.has("plot_denied") and not bool(old_r.get("plot_denied", true)))
	gs.queue_free()
