extends SceneTree
## Cursing Gnomes — hearsay beastloss gossip tests (Jeremy 2026-10-10).
##
## bus.animal_died was a deaf thread: herds starved and wolves fed while
## the mill heard nothing. Now:
##  - a farm animal starving seeds a RICH kind-"beastloss" rumor naming
##    the herd's faction (subject "beastloss:<faction>:starved", shared
##    per faction so a starvation wave refreshes one rumor instead of
##    spamming); TRUTH_TRUE, heat 0.55, Squabble post on the fresh seed
##  - hard gates: farm deaths need cause "starved" (slaughter is farm
##    business) and a faction-owned plot; wild deaths only gossip when
##    "slain" (predator drama, shared "beastloss:wild:slain" wolf-drama
##    rumor, TRUTH_UNKNOWN, heat 0.5); wild starvations stay quiet
##  - famine tie-in: a starving herd during a live famine rumor reads as
##    one story — heat 0.65 and grimmer text
##  - the beastloss reaction matrix: the hungry herd's own faction is
##    shamed (beastloss_shame, mocked), rivals gloat (beastloss_glee),
##    everyone else is amused (beastloss_news, helped); a wolf kill
##    leaves wariness (beastloss_wary, disaster) — the unhinged find it
##    all hilarious (glee). Unhinged x1.5.
##  - spread motivation: the shamed faction buries its hungry-herd
##    gossip, rivals gloat-spread it, wolf news travels straight
##  - all 4 new memory types registered in SimMemories.TYPES with weights
##  - heat stays below PRESS_HEAT (tavern talk, never the front page)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_beastloss.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay beastloss gossip tests ===")
	_test_farm_starved_seeds_rumor()
	_test_farm_unknown_cause_seeds_nothing()
	_test_farm_ownerless_plot_seeds_nothing()
	_test_wild_slain_seeds_rumor()
	_test_wild_starved_seeds_nothing()
	_test_repeat_starvation_refreshes_not_duplicates()
	_test_below_press_heat()
	_test_famine_tie_in()
	_test_same_faction_shamed()
	_test_rival_gloats()
	_test_neutral_amused()
	_test_unhinged_same_faction_gloats()
	_test_unhinged_amplified()
	_test_wild_slain_wary()
	_test_unhinged_wild_glee()
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


func _die(gs: GameState, plot_id: int, animal_id: int, cause: String,
		atype: String) -> void:
	gs.bus.animal_died.emit(plot_id, animal_id, cause, atype)


func _rumor(hs, subject: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "beastloss" \
				and String(r.get("subject", "")) == subject:
			return r
	return {}


func _count_beastloss(hs) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "beastloss":
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


func _test_farm_starved_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "starved", "cow")
	var r := _rumor(hs, "beastloss:elves:starved")
	_check("starved farm beast seeds a rumor", not r.is_empty())
	_check("subject keys faction+cause",
		String(r.get("subject", "")) == "beastloss:elves:starved")
	_check("starvation is confirmed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("heat is tavern talk",
		is_equal_approx(float(r.get("heat", 0.0)), 0.55))
	_check("cause recorded", String(r.get("beastloss_cause", "")) == "starved")
	_check("faction recorded", String(r.get("beastloss_faction", "")) == "elves")
	_check("beast recorded", String(r.get("beastloss_beast", "")) == "cow")
	_check("text names the pastures",
		String(r.get("text", "")).find("pastures") >= 0)


func _test_farm_unknown_cause_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "butchered", "cow")
	_check("non-starved farm death seeds nothing", _count_beastloss(hs) == 0)


func _test_farm_ownerless_plot_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "")
	_die(gs, 7, 101, "starved", "cow")
	_die(gs, 999, 102, "starved", "pig")
	_check("ownerless/missing plot seeds nothing", _count_beastloss(hs) == 0)


func _test_wild_slain_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_die(gs, -1, 202, "slain", "sheep")
	var r := _rumor(hs, "beastloss:wild:slain")
	_check("slain wild beast seeds wolf-drama", not r.is_empty())
	_check("wild kill is unverified talk",
		String(r.get("truth", "")) == hs.TRUTH_UNKNOWN)
	_check("wild heat is quiet",
		is_equal_approx(float(r.get("heat", 0.0)), 0.5))
	_check("slain cause recorded", String(r.get("beastloss_cause", "")) == "slain")
	_check("text names the wolves",
		String(r.get("text", "")).find("Wolves") >= 0)


func _test_wild_starved_seeds_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_die(gs, -1, 202, "starved", "boar")
	_check("wild starvation stays quiet", _count_beastloss(hs) == 0)


func _test_repeat_starvation_refreshes_not_duplicates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "starved", "cow")
	_die(gs, 7, 102, "starved", "pig")
	_check("starvation wave shares one rumor", _count_beastloss(hs) == 1)
	var r := _rumor(hs, "beastloss:elves:starved")
	r["heat"] = 0.2  # simulate daily decay between deaths
	_die(gs, 7, 103, "starved", "goat")
	_check("repeat death refreshes cooled heat",
		is_equal_approx(float(r.get("heat", 0.0)), 0.55))


func _test_below_press_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "starved", "cow")
	_die(gs, -1, 202, "slain", "sheep")
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "beastloss":
			_check("beastloss never reaches the press",
				float(r.get("heat", 0.0)) < hs.PRESS_HEAT)


func _test_famine_tie_in() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	var fr = hs.seed_rumor("famine!", "famine", "famine:elves", 0.9, -1,
		false, hs.TRUTH_TRUE)
	fr["famine_faction"] = "elves"
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "starved", "cow")
	var r := _rumor(hs, "beastloss:elves:starved")
	_check("famine bumps the heat",
		is_equal_approx(float(r.get("heat", 0.0)), 0.65))
	_check("famine text is grimmer",
		String(r.get("text", "")).find("granaries bare") >= 0)


func _test_same_faction_shamed() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "starved", "cow")
	var r := _rumor(hs, "beastloss:elves:starved")
	var elf := _spawn(gs, "elves")
	var uid := int(elf.get("id", 0))
	hs._on_heard(elf, r, {})
	_check("herd's faction remembers shame",
		_recalled(elf, "beastloss_shame", int(r.get("id", 0))) > 0.0)
	_check("shame dips mood", conv.ruler_mood(uid) < 0.0)
	_check("mocked lands as sad", _emotion(elf) == "sad")


func _test_rival_gloats() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("elves", "ogres", "test")
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "starved", "cow")
	var r := _rumor(hs, "beastloss:elves:starved")
	var ogre := _spawn(gs, "ogres")
	var uid := int(ogre.get("id", 0))
	hs._on_heard(ogre, r, {})
	_check("rival remembers gloating",
		_recalled(ogre, "beastloss_glee", int(r.get("id", 0))) > 0.0)
	_check("gloating lifts mood", conv.ruler_mood(uid) > 0.0)
	_check("rival mocks", _emotion(ogre) == "sad")


func _test_neutral_amused() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "starved", "cow")
	var r := _rumor(hs, "beastloss:elves:starved")
	var gnome := _spawn(gs, "gnomes")
	var uid := int(gnome.get("id", 0))
	hs._on_heard(gnome, r, {})
	_check("neutral remembers the news",
		_recalled(gnome, "beastloss_news", int(r.get("id", 0))) > 0.0)
	_check("neutral is amused", conv.ruler_mood(uid) > 0.0)
	_check("neutral feels happy", _emotion(gnome) == "happy")


func _test_unhinged_same_faction_gloats() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "starved", "cow")
	var r := _rumor(hs, "beastloss:elves:starved")
	var wild := _spawn(gs, "elves", Vector2.ZERO, _unhinged_mind())
	var uid := int(wild.get("id", 0))
	hs._on_heard(wild, r, {})
	_check("unhinged finds own herd's shame hilarious",
		_recalled(wild, "beastloss_glee", int(r.get("id", 0))) > 0.0)
	_check("unhinged mood rises", conv.ruler_mood(uid) > 0.0)


func _unhinged_rival_mood() -> Array:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	gs.diplomacy.declare_war("elves", "ogres", "test")
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "starved", "cow")
	var r := _rumor(hs, "beastloss:elves:starved")
	return [gs, hs, conv, r]


func _test_unhinged_amplified() -> void:
	var a: Array = _unhinged_rival_mood()
	var hs1 = a[1]
	var conv1 = a[2]
	var r1: Dictionary = a[3]
	var plain = _spawn(a[0], "ogres")
	var uid1 := int(plain.get("id", 0))
	hs1._on_heard(plain, r1, {})
	var m1: float = conv1.ruler_mood(uid1)
	var b: Array = _unhinged_rival_mood()
	var hs2 = b[1]
	var conv2 = b[2]
	var r2: Dictionary = b[3]
	var wild = _spawn(b[0], "ogres", Vector2.ZERO, _unhinged_mind())
	var uid2 := int(wild.get("id", 0))
	hs2._on_heard(wild, r2, {})
	var m2: float = conv2.ruler_mood(uid2)
	_check("plain rival gloats", m1 > 0.0)
	_check("unhinged gloats 1.5x harder", is_equal_approx(m2, m1 * 1.5))


func _test_wild_slain_wary() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_die(gs, -1, 202, "slain", "sheep")
	var r := _rumor(hs, "beastloss:wild:slain")
	var human := _spawn(gs, "humans")
	var uid := int(human.get("id", 0))
	hs._on_heard(human, r, {})
	_check("wolf kill leaves wariness",
		_recalled(human, "beastloss_wary", int(r.get("id", 0))) > 0.0)
	_check("wariness dips mood", conv.ruler_mood(uid) < 0.0)
	_check("disaster lands as scared", _emotion(human) == "scared")


func _test_unhinged_wild_glee() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_die(gs, -1, 202, "slain", "sheep")
	var r := _rumor(hs, "beastloss:wild:slain")
	var wild := _spawn(gs, "humans", Vector2.ZERO, _unhinged_mind())
	var uid := int(wild.get("id", 0))
	hs._on_heard(wild, r, {})
	_check("unhinged loves wolf drama",
		_recalled(wild, "beastloss_glee", int(r.get("id", 0))) > 0.0)
	_check("unhinged mood rises", conv.ruler_mood(uid) > 0.0)


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	gs.diplomacy.declare_war("elves", "ogres", "test")
	_plot(gs, 7, "elves")
	_die(gs, 7, 101, "starved", "cow")
	_die(gs, -1, 202, "slain", "sheep")
	var rs := _rumor(hs, "beastloss:elves:starved")
	var rw := _rumor(hs, "beastloss:wild:slain")
	var elf := _spawn(gs, "elves")
	var ogre := _spawn(gs, "ogres")
	var gnome := _spawn(gs, "gnomes")
	var m_elf: Dictionary = hs._spread_motivation(elf, rs)
	_check("shamed faction buries the gossip",
		int(m_elf.get("cap_delta", 0)) == -1 \
		and is_equal_approx(float(m_elf.get("heat_delta", 0.0)), -0.1))
	var m_ogre: Dictionary = hs._spread_motivation(ogre, rs)
	_check("rival gloat-spreads it",
		int(m_ogre.get("cap_delta", 0)) == 1 \
		and is_equal_approx(float(m_ogre.get("heat_delta", 0.0)), 0.1))
	var m_gnome: Dictionary = hs._spread_motivation(gnome, rs)
	_check("neutral tells starved talk straight",
		int(m_gnome.get("cap_delta", 9)) == 0 \
		and is_equal_approx(float(m_gnome.get("heat_delta", 9.0)), 0.0))
	var m_wolf: Dictionary = hs._spread_motivation(gnome, rw)
	_check("wolf news travels straight",
		int(m_wolf.get("cap_delta", 9)) == 0 \
		and is_equal_approx(float(m_wolf.get("heat_delta", 9.0)), 0.0))


func _test_memory_types_registered() -> void:
	var mem = load("res://scripts/sim/memories.gd")
	for t: String in ["beastloss_shame", "beastloss_glee",
			"beastloss_wary", "beastloss_news"]:
		_check("memory type registered: " + t, mem.TYPES.has(t))
		_check("memory weight set: " + t, mem.REL_WEIGHT.has(t))
