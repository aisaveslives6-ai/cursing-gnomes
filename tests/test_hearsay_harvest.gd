extends SceneTree
## Cursing Gnomes — bumper/lean harvest gossip tests (Jeremy 2026-10-10).
##
## STAGED by the hearsay flesh-out wake: bus.farm_harvested fired on every
## tile harvest and the mill heard NOTHING. Now:
##  - bumper hauls (>= 85 food, top of the natural 60-100 range) seed a
##    RICH kind-"harvest" rumor (faction + haul recorded, TRUTH_TRUE,
##    heat 0.6 tavern talk — below PRESS_HEAT 0.85, no front page)
##  - lean hauls (< 55 food, only reachable when something's wrong —
##    borg -15%, flood mud) seed a mock-worthy lean rumor (heat 0.55)
##  - normal hauls stay quiet — farm business, not gossip
##  - repeat hauls refresh the rumor via subject dedup (no twin per
##    harvest), Squabble posts only on the fresh seed
##  - the harvest reaction matrix: the fed faction is proud, rivals are
##    envious, neutrals just enjoy the news; the lean faction is
##    embarrassed, rivals mock the empty granary. Unhinged x1.5.
##  - spread motivation: the lean faction buries, rivals gloat-spread;
##    the bumper faction brag-spreads, everyone else tells it straight
##  - missing plot / ownerless plot / missing roster fall back gracefully
##  - all 4 new memory types registered in SimMemories.TYPES with weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_harvest.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay harvest gossip tests ===")
	_test_bumper_seeds_rumor()
	_test_lean_seeds_rumor()
	_test_normal_haul_stays_quiet()
	_test_ownerless_plot_seeds_nothing()
	_test_below_press_heat()
	_test_truth_true()
	_test_repeat_harvest_refreshes_not_duplicates()
	_test_fed_faction_proud()
	_test_rival_envious()
	_test_neutral_enjoys_news()
	_test_lean_faction_embarrassed()
	_test_lean_rival_mocks()
	_test_unhinged_amplified()
	_test_spread_motivation()
	_test_memory_types_registered()
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
	var farming = load("res://scripts/sim/farming.gd").new(gs)
	gs.set("farming", farming)
	return [gs, phone, phone.hearsay]


func _spawn(gs: GameState, faction: String, pos: Vector2 = Vector2.ZERO,
		mind: Dictionary = {}) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "alive": true,
		"mind": mind})
	u["position"] = pos
	return u


func _unhinged_mind() -> Dictionary:
	return {"traits": {"unhinged": 1.0}}


func _plot(gs: GameState, plot_id: int, faction: String) -> void:
	gs.farming.plots.append({"id": plot_id, "faction": faction})


func _harvest(gs: GameState, plot_id: int, food: float) -> void:
	gs.bus.farm_harvested.emit(plot_id, food, 3.0)


func _rumor(hs, subject: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "harvest" \
				and String(r.get("subject", "")) == subject:
			return r
	return {}


func _count_harvest(hs) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "harvest":
			n += 1
	return n


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _test_bumper_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "elves")
	_harvest(gs, 7, 92.0)
	var r := _rumor(hs, "harvest:elves:bumper")
	_check("bumper harvest seeds a rumor", not r.is_empty())
	_check("subject keys faction+type",
		String(r.get("subject", "")) == "harvest:elves:bumper")
	_check("haul recorded", int(r.get("harvest_food", 0)) == 92)
	_check("type recorded", String(r.get("harvest_type", "")) == "bumper")
	_check("faction recorded",
		String(r.get("harvest_faction", "")) == "elves")
	_check("text names the fields",
		String(r.get("text", "")).find("fields") >= 0)


func _test_lean_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "ogres")
	_harvest(gs, 7, 48.0)
	var r := _rumor(hs, "harvest:ogres:lean")
	_check("lean harvest seeds a rumor", not r.is_empty())
	_check("lean heat is tavern talk",
		is_equal_approx(float(r.get("heat", 0.0)), 0.55))
	_check("type recorded", String(r.get("harvest_type", "")) == "lean")


func _test_normal_haul_stays_quiet() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "elves")
	_harvest(gs, 7, 75.0)
	_harvest(gs, 7, 60.0)
	_harvest(gs, 7, 84.0)
	_check("normal hauls seed nothing", _count_harvest(hs) == 0)


func _test_ownerless_plot_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "")
	_harvest(gs, 7, 99.0)
	_harvest(gs, 999, 99.0)
	_check("ownerless/missing plot seeds nothing", _count_harvest(hs) == 0)


func _test_below_press_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "elves")
	_harvest(gs, 7, 92.0)
	_plot(gs, 8, "ogres")
	_harvest(gs, 8, 48.0)
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "harvest":
			_check("harvest never reaches the press",
				float(r.get("heat", 0.0)) < hs.PRESS_HEAT)


func _test_truth_true() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "elves")
	_harvest(gs, 7, 92.0)
	var r := _rumor(hs, "harvest:elves:bumper")
	_check("bumper haul is confirmed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)


func _test_repeat_harvest_refreshes_not_duplicates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "elves")
	_harvest(gs, 7, 92.0)
	_harvest(gs, 7, 95.0)
	_check("good season shares one rumor", _count_harvest(hs) == 1)
	var r := _rumor(hs, "harvest:elves:bumper")
	r["heat"] = 0.2  # simulate daily decay between harvests
	_harvest(gs, 7, 99.0)
	_check("repeat bumper refreshes cooled heat",
		is_equal_approx(float(r.get("heat", 0.0)), 0.6))


func _test_fed_faction_proud() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_plot(gs, 7, "elves")
	_harvest(gs, 7, 92.0)
	var r := _rumor(hs, "harvest:elves:bumper")
	var elf := _spawn(gs, "elves")
	var uid := int(elf.get("id", 0))
	hs._on_heard(elf, r, {})
	_check("fed faction remembers pride",
		_recalled(elf, "harvest_pride", int(r.get("id", 0))) > 0.0)
	_check("pride lifts mood", conv.ruler_mood(uid) > 0.0)
	_check("pride feels happy", _emotion(elf) == "happy")


func _test_rival_envious() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("elves", "ogres", "test")
	_plot(gs, 7, "elves")
	_harvest(gs, 7, 92.0)
	var r := _rumor(hs, "harvest:elves:bumper")
	var ogre := _spawn(gs, "ogres")
	var uid := int(ogre.get("id", 0))
	hs._on_heard(ogre, r, {})
	_check("rival remembers envy",
		_recalled(ogre, "harvest_envy", int(r.get("id", 0))) > 0.0)
	_check("envy dips mood", conv.ruler_mood(uid) < 0.0)
	_check("envy feels sad", _emotion(ogre) == "sad")


func _test_neutral_enjoys_news() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_plot(gs, 7, "elves")
	_harvest(gs, 7, 92.0)
	var r := _rumor(hs, "harvest:elves:bumper")
	var gnome := _spawn(gs, "gnomes")
	var uid := int(gnome.get("id", 0))
	hs._on_heard(gnome, r, {})
	_check("neutral remembers the news",
		_recalled(gnome, "harvest_news", int(r.get("id", 0))) > 0.0)
	_check("neutral is pleased", conv.ruler_mood(uid) > 0.0)
	_check("neutral feels happy", _emotion(gnome) == "happy")


func _test_lean_faction_embarrassed() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_plot(gs, 7, "ogres")
	_harvest(gs, 7, 48.0)
	var r := _rumor(hs, "harvest:ogres:lean")
	var ogre := _spawn(gs, "ogres")
	var uid := int(ogre.get("id", 0))
	hs._on_heard(ogre, r, {})
	_check("lean faction remembers the mockery",
		_recalled(ogre, "harvest_mock", int(r.get("id", 0))) > 0.0)
	_check("embarrassment dips mood", conv.ruler_mood(uid) < 0.0)
	_check("embarrassment feels sad", _emotion(ogre) == "sad")


func _test_lean_rival_mocks() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("ogres", "elves", "test")
	_plot(gs, 7, "ogres")
	_harvest(gs, 7, 48.0)
	var r := _rumor(hs, "harvest:ogres:lean")
	var elf := _spawn(gs, "elves")
	var uid := int(elf.get("id", 0))
	hs._on_heard(elf, r, {})
	_check("rival remembers mocking the lean haul",
		_recalled(elf, "harvest_mock", int(r.get("id", 0))) > 0.0)
	_check("mockery lifts mood", conv.ruler_mood(uid) > 0.0)
	_check("rival feels sad-happy (mocked event)", _emotion(elf) == "sad")


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_plot(gs, 7, "elves")
	_harvest(gs, 7, 92.0)
	var r := _rumor(hs, "harvest:elves:bumper")
	var sane := _spawn(gs, "elves")
	var wild := _spawn(gs, "elves", Vector2.ZERO, _unhinged_mind())
	hs._on_heard(sane, r, {})
	hs._on_heard(wild, r, {})
	var sane_mood = conv.ruler_mood(int(sane.get("id", 0)))
	var wild_mood = conv.ruler_mood(int(wild.get("id", 0)))
	_check("unhinged feels the bumper 1.5x",
		wild_mood > sane_mood and absf(wild_mood - sane_mood * 1.5) < 0.01)


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "ogres")
	_harvest(gs, 7, 48.0)
	var r := _rumor(hs, "harvest:ogres:lean")
	gs.diplomacy.declare_war("ogres", "elves", "test")
	var ogre := _spawn(gs, "ogres")
	var elf := _spawn(gs, "elves")
	var gnome := _spawn(gs, "gnomes")
	_check("lean faction buries the gossip",
		float(hs._spread_motivation(ogre, r).get("cap_delta", 0.0)) < 0.0)
	_check("rival gloat-spreads the lean haul",
		float(hs._spread_motivation(elf, r).get("cap_delta", 0.0)) > 0.0)
	_check("neutral tells it straight",
		is_equal_approx(float(hs._spread_motivation(gnome, r).get("cap_delta", 0.0)), 0.0))
	_plot(gs, 9, "elves")
	_harvest(gs, 9, 92.0)
	var rb := _rumor(hs, "harvest:elves:bumper")
	_check("bumper faction brag-spreads",
		float(hs._spread_motivation(elf, rb).get("cap_delta", 0.0)) > 0.0)


func _test_memory_types_registered() -> void:
	var mem = load("res://scripts/sim/memories.gd")
	_check("harvest types registered",
		"harvest_pride" in mem.TYPES and "harvest_envy" in mem.TYPES \
		and "harvest_mock" in mem.TYPES and "harvest_news" in mem.TYPES)
	_check("harvest weights set",
		mem.REL_WEIGHT.has("harvest_pride") \
		and mem.REL_WEIGHT.has("harvest_envy") \
		and mem.REL_WEIGHT.has("harvest_mock") \
		and mem.REL_WEIGHT.has("harvest_news"))
