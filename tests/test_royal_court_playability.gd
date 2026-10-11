extends SceneTree
## Cursing Gnomes — royal court playability headless tests (Jeremy 2026-10-05).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_royal_court_playability.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers the full court loop with no dead ends:
##   government promotion (mayor/adviser/lord/commander all assigned),
##   every domestic petition template reachable and handled,
##   lord petitions (lord_levy / lord_raid / lord_plot_rumor) generate once
##   lords exist, honest shortfall stories when the crown cannot pay
##   (no silent resolves), the crimewave petition's three options,
##   petition_decided + gazette_story signals fire, and save/load round-trips
##   petitions and stories.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []
var _decided: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes royal-court playability tests ===")
	_test_government_promotes_lord()
	_test_lord_templates_reachable()
	_test_every_template_handled()
	_test_shortfall_is_honest()
	_test_crimewave_options()
	_test_full_petition_loop()
	_test_save_load_round_trip()
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


## Two factions; player = humans.
func _make_gs() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	_stories.clear()
	_decided.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	gs.bus.petition_decided.connect(
		func(p: Dictionary, _c: String) -> void: _decided.append(int(p.get("id", -1))))
	return gs


func _unit(gs: GameState, faction: String, job: String) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": job, "town_id": 1,
		"position": Vector2(200, 200), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "mind": {}})


func _gov_roles(gs: GameState) -> Dictionary:
	var out := {}
	for u: Dictionary in gs.units:
		var r := String((u.get("mind", {}) as Dictionary).get("gov_role", ""))
		if r != "":
			out[r] = int(u.get("id", -1))
	return out


## Craft a domestic petition for a template id (bypasses the daily RNG).
func _force_petition(court: SimRoyalCourt, gs: GameState, tpl_id: String,
		opt_idx: int = 0) -> Dictionary:
	var role := ""
	var opts: Array[String] = []
	for tpl: Dictionary in SimRoyalCourt.DOMESTIC_TEMPLATES:
		if String(tpl.get("id", "")) == tpl_id:
			role = String(tpl.get("role", ""))
			for o: Variant in tpl.get("options", []):
				opts.append(String(o))
	if role == "" or opts.is_empty():
		return {}
	var holder: Dictionary = {}
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == gs.player_faction \
				and String((u.get("mind", {}) as Dictionary).get("gov_role", "")) == role:
			holder = u
			break
	if holder.is_empty():
		return {}
	var p: Dictionary = court.petition(holder, tpl_id, "test plea", opts)
	p["tpl"] = tpl_id
	return p


## Government must promote mayor, adviser, LORD and commander — lords were
## designed as a gov role (phone GOV_RANK, lord_* petition templates) but
## were never promoted, leaving three petition templates dead.
func _test_government_promotes_lord() -> void:
	var gs := _make_gs()
	for i: int in 6:
		_unit(gs, "humans", "worker")
	for i: int in 2:
		_unit(gs, "humans", "soldier")
		_unit(gs, "humans", "guard")
	var army := SimArmy.new(gs)
	army.ensure_government("humans")
	var roles := _gov_roles(gs)
	_check("lord promoted", roles.has("lord"))
	_check("mayor promoted", roles.has("mayor"))
	_check("adviser promoted", roles.has("adviser"))
	_check("commander promoted", roles.has("commander"))
	_check("lord is a distinct unit",
		int(roles.get("lord", -1)) != int(roles.get("mayor", -2)))


## With a lord in office, the lord templates must be generatable and their
## effects must land.
func _test_lord_templates_reachable() -> void:
	# 2026-10-08 de-flake: generate_domestic_petition() draws uniformly from
	# 7-8 eligible templates, so 40 draws can miss one specific template
	# (~1-6% observed on "lord_raid generatable" across gate runs). Fixed seed
	# pins the draw sequence (precedent: test_artillery_undead, test_fishing).
	seed(20261008)
	var gs := _make_gs()
	for i: int in 6:
		_unit(gs, "humans", "worker")
	for i: int in 2:
		_unit(gs, "humans", "soldier")
		_unit(gs, "humans", "guard")
	var army := SimArmy.new(gs)
	army.ensure_government("humans")
	var court := SimRoyalCourt.new(gs)
	# Lord petitions appear in the daily candidate pool once a lord exists.
	var seen := {}
	for i: int in 40:
		var p: Dictionary = court.generate_domestic_petition()
		if not p.is_empty():
			seen[String(p.get("tpl", ""))] = true
			court.decide(int(p.get("id", -1)), 1)  # refuse, keep the board moving
	_check("lord_levy generatable", seen.has("lord_levy"))
	_check("lord_raid generatable", seen.has("lord_raid"))
	# lord_levy grant deducts 200 gold when affordable.
	gs.resources.add_resource("humans", "gold", 1000.0)
	var before: float = gs.resources.get_amount("humans", "gold")
	var p: Dictionary = _force_petition(court, gs, "lord_levy")
	var story: Dictionary = court.decide(int(p.get("id", -1)), 0)
	_check("lord_levy resolved", bool(p.get("resolved", false)))
	_check("lord_levy deducts 200g",
		is_equal_approx(gs.resources.get_amount("humans", "gold"), before - 200.0))
	_check("lord_levy publishes a story", not story.is_empty())
	# lord_raid grant yields 120 food.
	var f0: float = gs.resources.get_amount("humans", "food")
	p = _force_petition(court, gs, "lord_raid")
	court.decide(int(p.get("id", -1)), 0)
	_check("lord_raid grants 120 food",
		is_equal_approx(gs.resources.get_amount("humans", "food"), f0 + 120.0))
	# lord_plot_rumor unlocks once a lord's mood sours below -20.
	var lord: Dictionary = {}
	for u: Dictionary in gs.units:
		if String((u.get("mind", {}) as Dictionary).get("gov_role", "")) == "lord":
			lord = u
			break
	court.bump_court_mood(lord, -30.0)
	var rumor_tpl := {}
	for tpl: Dictionary in SimRoyalCourt.DOMESTIC_TEMPLATES:
		if String(tpl.get("id", "")) == "lord_plot_rumor":
			rumor_tpl = tpl
	_check("lordangry condition trips when the lord sours",
		court._template_when_ok(rumor_tpl))
	p = _force_petition(court, gs, "lord_plot_rumor")
	var mood_before: float = SimRoyalCourt.court_mood_of(lord)
	story = court.decide(int(p.get("id", -1)), 0)
	_check("lord_plot_rumor grant resolves with a story", not story.is_empty())
	_check("lord_plot_rumor soothes the lord",
		is_equal_approx(SimRoyalCourt.court_mood_of(lord), minf(mood_before + 18.0, 100.0)))


## Every template id in DOMESTIC_TEMPLATES must have a working handler:
## decide() resolves it and returns a real story on the affordable path.
func _test_every_template_handled() -> void:
	var gs := _make_gs()
	for i: int in 8:
		_unit(gs, "humans", "worker")
	for i: int in 2:
		_unit(gs, "humans", "soldier")
		_unit(gs, "humans", "guard")
	var army := SimArmy.new(gs)
	army.ensure_government("humans")
	var court := SimRoyalCourt.new(gs)
	gs.resources.add_resource("humans", "gold", 5000.0)
	gs.resources.add_resource("humans", "food", 5000.0)
	for tpl: Dictionary in SimRoyalCourt.DOMESTIC_TEMPLATES:
		var tid := String(tpl.get("id", ""))
		var p: Dictionary = _force_petition(court, gs, tid)
		_check("template %s has a role-holder" % tid, not p.is_empty())
		if p.is_empty():
			continue
		var story: Dictionary = court.decide(int(p.get("id", -1)), 0)
		_check("template %s resolves" % tid, bool(p.get("resolved", false)))
		_check("template %s yields a story" % tid, not story.is_empty())


## Granting what the crown cannot afford must say so loudly — no silent
## resolves with a misleading "the crown's answer" headline.
func _test_shortfall_is_honest() -> void:
	var gs := _make_gs()
	for i: int in 6:
		_unit(gs, "humans", "worker")
	for i: int in 2:
		_unit(gs, "humans", "soldier")
	var army := SimArmy.new(gs)
	army.ensure_government("humans")
	var court := SimRoyalCourt.new(gs)
	# Bare stores: mayor_grain grant must fail loudly, spending nothing.
	gs.resources.add_resource("humans", "food", -100000.0)
	gs.resources.add_resource("humans", "gold", -100000.0)
	var f0: float = gs.resources.get_amount("humans", "food")
	_check("test starts with <60 food", f0 < 60.0)
	var p: Dictionary = _force_petition(court, gs, "mayor_grain")
	var story: Dictionary = court.decide(int(p.get("id", -1)), 0)
	_check("shortfall petition still resolves", bool(p.get("resolved", false)))
	_check("shortfall story is THE CROWN FALTERS",
		String(story.get("headline", "")) == "THE CROWN FALTERS")
	_check("shortfall spends no food",
		is_equal_approx(gs.resources.get_amount("humans", "food"), f0))
	_check("shortfall sours the petitioner",
		SimRoyalCourt.court_mood_of(_holder(gs, "mayor")) < 0.0)
	# Bare coffers: lord_levy grant must fail loudly too.
	var g0: float = gs.resources.get_amount("humans", "gold")
	_check("test starts with <200 gold", g0 < 200.0)
	p = _force_petition(court, gs, "lord_levy")
	story = court.decide(int(p.get("id", -1)), 0)
	_check("lord shortfall headline honest",
		String(story.get("headline", "")) == "THE CROWN FALTERS")
	_check("lord shortfall spends no gold",
		is_equal_approx(gs.resources.get_amount("humans", "gold"), g0))
	# A failed festival grant (bare coffers) must not pretend it happened.
	p = _force_petition(court, gs, "mayor_festival_ask")
	story = court.decide(int(p.get("id", -1)), 0)
	_check("festival shortfall honest",
		String(story.get("headline", "")) == "THE CROWN FALTERS")


func _holder(gs: GameState, role: String) -> Dictionary:
	for u: Dictionary in gs.units:
		if String((u.get("mind", {}) as Dictionary).get("gov_role", "")) == role:
			return u
	return {}


## The SimCrime-driven crimewave petition: all three options resolve, and
## the crackdown option fails loudly when broke.
func _test_crimewave_options() -> void:
	var gs := _make_gs()
	for i: int in 6:
		_unit(gs, "humans", "worker")
	var army := SimArmy.new(gs)
	army.ensure_government("humans")
	var court := SimRoyalCourt.new(gs)
	gs.resources.add_resource("humans", "gold", -100000.0)
	# Ignore path.
	var p: Dictionary = court.petition(_holder(gs, "mayor"), "mayor_crimewave",
		"crime!", ["Raise Militia", "Fund Crackdown (120g)", "Ignore"] as Array[String])
	p["tpl"] = "mayor_crimewave"
	var story: Dictionary = court.decide(int(p.get("id", -1)), 2)
	_check("crimewave ignore resolves", bool(p.get("resolved", false)))
	_check("crimewave ignore yields story", not story.is_empty())
	# Crackdown when broke: honest shortfall, no gold spent.
	var g0: float = gs.resources.get_amount("humans", "gold")
	_check("crimewave test starts broke", g0 < 120.0)
	p = court.petition(_holder(gs, "mayor"), "mayor_crimewave",
		"crime!", ["Raise Militia", "Fund Crackdown (120g)", "Ignore"] as Array[String])
	p["tpl"] = "mayor_crimewave"
	story = court.decide(int(p.get("id", -1)), 1)
	_check("crimewave crackdown shortfall honest",
		String(story.get("headline", "")) == "THE CROWN FALTERS")
	_check("crimewave crackdown spends nothing",
		is_equal_approx(gs.resources.get_amount("humans", "gold"), g0))
	# Militia when funded: raises the guard and tells the tale.
	gs.resources.add_resource("humans", "gold", 1000.0)
	p = court.petition(_holder(gs, "mayor"), "mayor_crimewave",
		"crime!", ["Raise Militia", "Fund Crackdown (120g)", "Ignore"] as Array[String])
	p["tpl"] = "mayor_crimewave"
	story = court.decide(int(p.get("id", -1)), 0)
	_check("crimewave militia resolves", bool(p.get("resolved", false)))
	# The success story is published to the Gazette inline (pre-existing
	# behavior); decide() additionally returns the generic ruling.
	_check("crimewave militia story hits the Gazette",
		_stories.any(func(s: Dictionary) -> bool:
			return String(s.get("headline", "")) == "MILITIA RAISED"))
	_check("militia policy engaged",
		String(court.policies.state.get("guard", "none")) == "militia")


## The whole loop: petition -> open list -> decide -> decided signal ->
## gazette story -> history.
func _test_full_petition_loop() -> void:
	var gs := _make_gs()
	_unit(gs, "humans", "worker")
	var court := SimRoyalCourt.new(gs)
	var u: Dictionary = gs.units[0]
	var p: Dictionary = court.petition(u, "supplies", "We need grain.",
		["Grant", "Refuse"] as Array[String])
	_check("petition appears in open list",
		court.open_petitions().any(func(q: Dictionary) -> bool:
			return int(q.get("id", -1)) == int(p.get("id", -1))))
	var story: Dictionary = court.decide(int(p.get("id", -1)), 0)
	_check("petition leaves the open list", court.open_petitions().is_empty())
	_check("petition_decided emitted", _decided.has(int(p.get("id", -1))))
	_check("gazette story emitted",
		_stories.any(func(s: Dictionary) -> bool:
			return String(s.get("headline", "")).contains("Crown Rules")) \
		or not story.is_empty())
	_check("history records the decision",
		court.petition_history(5).any(func(q: Dictionary) -> bool:
			return int(q.get("id", -1)) == int(p.get("id", -1))))
	_check("decide twice is a no-op", court.decide(int(p.get("id", -1)), 0).is_empty())
	_check("decide on unknown id is a no-op", court.decide(424242, 0).is_empty())


## Petitions, stories and sequence counters survive a save/load round-trip.
func _test_save_load_round_trip() -> void:
	var gs := _make_gs()
	_unit(gs, "humans", "worker")
	var court := SimRoyalCourt.new(gs)
	var p: Dictionary = court.petition(gs.units[0], "supplies", "We need grain.",
		["Grant", "Refuse"] as Array[String])
	court.decide(int(p.get("id", -1)), 0)
	court.publish_story("TEST HEADLINE", "Test body.", "court")
	var data: Dictionary = court.to_dict()
	var court2 := SimRoyalCourt.new(gs)
	court2.from_dict(data)
	_check("petitions survive reload", court2.petitions.size() == court.petitions.size())
	_check("resolved flag survives reload",
		bool((court2.petitions[0] as Dictionary).get("resolved", false)))
	_check("stories survive reload", court2.stories.size() == court.stories.size())
	_check("unread count survives reload",
		court2.unread_news() == court.unread_news())
	_check("history intact after reload",
		court2.petition_history(5).size() == court.petition_history(5).size())
