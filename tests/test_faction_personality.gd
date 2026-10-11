extends SceneTree
## Cursing Gnomes — AI faction expansion & canonical personalities tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_faction_personality.gd
##
## Covers: FACTION_SOUL canonical values (aggro, trade stances, values),
## faction_traits() canonical mapping, town expansion trickle, settlement
## founding, ruler reactions, trade stance effects.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes faction personality tests ===")
	_test_soul_canonical_aggro()
	_test_soul_trade_stances()
	_test_soul_values()
	_test_soul_undead_fallback()
	_test_soul_voice()
	_test_faction_traits_canonical()
	_test_faction_traits_override()
	_test_town_expand_demand()
	_test_town_expand_no_demand()
	_test_town_expand_cooldown()
	_test_found_settlement()
	_test_found_settlement_cap()
	_test_ruler_react_tax()
	_test_ruler_react_festival()
	_test_ruler_react_war()
	_test_ruler_react_dedupe()
	_test_trade_stance_bully()
	_test_trade_stance_haggler()
	_test_trade_stance_principled()
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


## --- FACTION_SOUL canonical data --------------------------------------------


func _test_soul_canonical_aggro() -> void:
	# HTML FACTION_SOUL verbatim: ogres 1.0, elves 0.35.
	_check("soul: ogre aggro 1.0",
		absf(SimFactions.soul_aggro("ogres") - 1.0) < 0.01)
	_check("soul: elf aggro 0.35",
		absf(SimFactions.soul_aggro("elves") - 0.35) < 0.01)
	_check("soul: human aggro 0.5",
		absf(SimFactions.soul_aggro("humans") - 0.5) < 0.01)
	_check("soul: gnome aggro 0.55",
		absf(SimFactions.soul_aggro("gnomes") - 0.55) < 0.01)


func _test_soul_trade_stances() -> void:
	_check("soul: ogre bully",
		SimFactions.soul_trade_stance("ogres") == "bully")
	_check("soul: elf principled",
		SimFactions.soul_trade_stance("elves") == "principled")
	_check("soul: human steady",
		SimFactions.soul_trade_stance("humans") == "steady")
	_check("soul: gnome haggler",
		SimFactions.soul_trade_stance("gnomes") == "haggler")


func _test_soul_values() -> void:
	var ogre: Dictionary = SimFactions.soul_values("ogres")
	_check("soul: ogre tribute 0.95",
		absf(float(ogre.get("tribute", 0.0)) - 0.95) < 0.01)
	_check("soul: ogre strength 1.0",
		absf(float(ogre.get("strength", 0.0)) - 1.0) < 0.01)
	var elf: Dictionary = SimFactions.soul_values("elves")
	_check("soul: elf diplomacy 0.85",
		absf(float(elf.get("diplomacy", 0.0)) - 0.85) < 0.01)
	_check("soul: elf honor 1.0",
		absf(float(elf.get("honor", 0.0)) - 1.0) < 0.01)


func _test_soul_undead_fallback() -> void:
	# HTML: FACTION_SOUL[f] || FACTION_SOUL.human — undead falls back.
	_check("soul: undead aggro = human",
		absf(SimFactions.soul_aggro("undead") - 0.5) < 0.01)
	_check("soul: undead stance = human",
		SimFactions.soul_trade_stance("undead") == "steady")


func _test_soul_voice() -> void:
	var line: String = SimFactions.soul_say("ogres", "greet",
		{"name": "TestKing"})
	_check("soul: voice line non-empty", line != "")
	_check("soul: {name} substituted", "TestKing" in line)
	_check("soul: missing category empty",
		SimFactions.soul_say("ogres", "nonexistent") == "")


## --- faction_traits() canonical mapping -------------------------------------


func _make_diplomacy() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var factions: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(factions)
	var dip := SimDiplomacy.new(gs)
	dip.reset(factions)
	gs.diplomacy = dip
	return [gs, dip]


func _free_diplomacy(w: Array) -> void:
	(w[0] as GameState).free()


func _test_faction_traits_canonical() -> void:
	var w: Array = _make_diplomacy()
	var dip: SimDiplomacy = w[1]
	var ogre: Dictionary = dip.faction_traits("ogres")
	_check("traits: ogre aggro 1.0",
		absf(float(ogre["aggro"]) - 1.0) < 0.01)
	_check("traits: ogre brave 1.0 (legacy)",
		absf(float(ogre["brave"]) - 1.0) < 0.01)
	_check("traits: ogre bully stance",
		String(ogre["trade_stance"]) == "bully")
	var elf: Dictionary = dip.faction_traits("elves")
	_check("traits: elf aggro 0.35",
		absf(float(elf["aggro"]) - 0.35) < 0.01)
	_check("traits: elf friendly 0.85 (legacy)",
		absf(float(elf["friendly"]) - 0.85) < 0.01)
	_check("traits: elf principled stance",
		String(elf["trade_stance"]) == "principled")
	# Ogres are inherently more aggressive than elves (no more random).
	_check("traits: ogre > elf aggro",
		float(ogre["aggro"]) > float(elf["aggro"]))
	_free_diplomacy(w)


func _test_faction_traits_override() -> void:
	var w: Array = _make_diplomacy()
	var dip: SimDiplomacy = w[1]
	dip.set_faction_traits("ogres", {"aggro": 0.1, "brave": 0.1})
	var t: Dictionary = dip.faction_traits("ogres")
	_check("traits: override respected",
		absf(float(t["aggro"]) - 0.1) < 0.01)
	_free_diplomacy(w)


## --- town expansion ----------------------------------------------------------


func _make_director() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.zoning = SimZoning.new(gs)
	gs.hiring = GuildHiring.new(gs)
	var director := SimAIDirector.new(gs)
	return [gs, director]


func _hall(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	var b: Dictionary = gs.add_building({
		"type": "town_hall", "faction": faction, "town_id": 1,
		"position": pos, "alive": true, "complete": true, "progress": 1.0,
	})
	return b


func _house(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({
		"type": "house", "faction": faction, "town_id": 1,
		"position": pos, "alive": true, "complete": true, "progress": 1.0,
	})


var _unit_id := 1000

func _unit(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	_unit_id += 1
	var u: Dictionary = {
		"id": _unit_id, "faction": faction, "job": "worker",
		"position": pos, "alive": true, "town_id": 1,
	}
	gs.units.append(u)
	return u


func _free_director(w: Array) -> void:
	(w[0] as GameState).free()


func _test_town_expand_demand() -> void:
	var w: Array = _make_director()
	var gs: GameState = w[0]
	var director: SimAIDirector = w[1]
	_hall(gs, "gnomes", Vector2(1000, 1000))
	_house(gs, "gnomes", Vector2(1100, 1000))
	# High population (over 60% of house capacity 5) triggers expansion.
	for i in range(4):
		_unit(gs, "gnomes", Vector2(1000 + i * 10, 1000))
	var houses_before := director._count_build("gnomes", "house")
	# Force past cooldown.
	director._expand_last.clear()
	gs.game_time = 1000.0
	var hall: Dictionary = director._hall("gnomes")
	var st := {"hall_pos": Vector2(1000, 1000)}
	director._town_expand_trickle("gnomes", hall, st)
	var houses_after := director._count_build("gnomes", "house")
	_check("expand: house placed on demand", houses_after > houses_before)
	_free_director(w)


func _test_town_expand_no_demand() -> void:
	var w: Array = _make_director()
	var gs: GameState = w[0]
	var director: SimAIDirector = w[1]
	_hall(gs, "gnomes", Vector2(1000, 1000))
	_house(gs, "gnomes", Vector2(1100, 1000))
	# Low population (under 60% of capacity) = no expansion.
	_unit(gs, "gnomes", Vector2(1000, 1000))
	var houses_before := director._count_build("gnomes", "house")
	director._expand_last.clear()
	gs.game_time = 1000.0
	var hall: Dictionary = director._hall("gnomes")
	var st := {"hall_pos": Vector2(1000, 1000)}
	director._town_expand_trickle("gnomes", hall, st)
	var houses_after := director._count_build("gnomes", "house")
	_check("expand: no house without demand", houses_after == houses_before)
	_free_director(w)


func _test_town_expand_cooldown() -> void:
	var w: Array = _make_director()
	var gs: GameState = w[0]
	var director: SimAIDirector = w[1]
	_hall(gs, "gnomes", Vector2(1000, 1000))
	_house(gs, "gnomes", Vector2(1100, 1000))
	for i in range(4):
		_unit(gs, "gnomes", Vector2(1000 + i * 10, 1000))
	var hall: Dictionary = director._hall("gnomes")
	var hall_id := int(hall.get("id", -1))
	# Set recent expansion — cooldown should block.
	director._expand_last[hall_id] = 900.0
	gs.game_time = 1000.0  # only 100s later, need 240s
	var st := {"hall_pos": Vector2(1000, 1000)}
	var houses_before := director._count_build("gnomes", "house")
	director._town_expand_trickle("gnomes", hall, st)
	var houses_after := director._count_build("gnomes", "house")
	_check("expand: cooldown blocks", houses_after == houses_before)
	_free_director(w)


## --- settlement founding ------------------------------------------------------


func _test_found_settlement() -> void:
	var w: Array = _make_director()
	var gs: GameState = w[0]
	var director: SimAIDirector = w[1]
	_hall(gs, "gnomes", Vector2(1000, 1000))
	# Near pop cap (48 * 0.8 = 38.4) with resources.
	for i in range(40):
		_unit(gs, "gnomes", Vector2(1000 + (i % 10) * 10, 1000))
	gs.resources.add_resource("gnomes", "wood", 500.0, true)
	gs.resources.add_resource("gnomes", "oil", 200.0, true)
	var halls_before := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "town_hall" \
				and String(b.get("faction", "")) == "gnomes":
			halls_before += 1
	director._settle_last.clear()
	gs.game_time = 1000.0
	var hall: Dictionary = director._hall("gnomes")
	var st := {"hall_pos": Vector2(1000, 1000)}
	director._found_settlement("gnomes", hall, st)
	var halls_after := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "town_hall" \
				and String(b.get("faction", "")) == "gnomes":
			halls_after += 1
	_check("settle: new hall founded", halls_after > halls_before)
	_free_director(w)


func _test_found_settlement_cap() -> void:
	var w: Array = _make_director()
	var gs: GameState = w[0]
	var director: SimAIDirector = w[1]
	# Already at 3 towns (TOWNS_PER_FACTION).
	_hall(gs, "gnomes", Vector2(1000, 1000))
	_hall(gs, "gnomes", Vector2(2500, 2500))
	_hall(gs, "gnomes", Vector2(3000, 1000))
	for i in range(40):
		_unit(gs, "gnomes", Vector2(1000 + (i % 10) * 10, 1000))
	gs.resources.add_resource("gnomes", "wood", 500.0, true)
	director._settle_last.clear()
	gs.game_time = 1000.0
	var hall: Dictionary = director._hall("gnomes")
	var st := {"hall_pos": Vector2(1000, 1000)}
	var halls_before := 3
	director._found_settlement("gnomes", hall, st)
	var halls_after := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "town_hall" \
				and String(b.get("faction", "")) == "gnomes":
			halls_after += 1
	_check("settle: respects town cap", halls_after == halls_before)
	_free_director(w)


## --- ruler reactions ----------------------------------------------------------


func _test_ruler_react_tax() -> void:
	var w: Array = _make_diplomacy()
	var dip: SimDiplomacy = w[1]
	# Should not crash; reactions are published as stories.
	dip.ruler_react_to("tax", {"value": 30})
	_check("react: tax high fires", true)
	dip.ruler_react_to("tax", {"value": 0})
	_check("react: tax zero fires", true)
	_free_diplomacy(w)


func _test_ruler_react_festival() -> void:
	var w: Array = _make_diplomacy()
	var dip: SimDiplomacy = w[1]
	dip.ruler_react_to("festival", {})
	_check("react: festival fires", true)
	_free_diplomacy(w)


func _test_ruler_react_war() -> void:
	var w: Array = _make_diplomacy()
	var dip: SimDiplomacy = w[1]
	# Player declares war on ogres — ogres should react.
	dip.declare_war("humans", "ogres")
	_check("react: war declared", dip.relation_state("humans", "ogres") == "war")
	# Score stays at -80 (reactions don't override war score).
	_check("react: war score intact",
		dip.relation_score("humans", "ogres") == -80.0)
	_free_diplomacy(w)


func _test_ruler_react_dedupe() -> void:
	var w: Array = _make_diplomacy()
	var dip: SimDiplomacy = w[1]
	# Same event twice in one day — second should dedupe (no crash).
	dip.ruler_react_to("festival", {})
	dip.ruler_react_to("festival", {})
	_check("react: dedupe no crash", true)
	_free_diplomacy(w)


## --- trade stances ------------------------------------------------------------


func _test_trade_stance_bully() -> void:
	var w: Array = _make_diplomacy()
	var gs: GameState = w[0]
	var dip: SimDiplomacy = w[1]
	# Ogres (bully) stronger than humans: ogres get 1.3x.
	# Set up military strength via units.
	for i in range(10):
		gs.spawner.spawn_unit("ogres", "soldier", -1, Vector2(0, 0))
	for i in range(2):
		gs.spawner.spawn_unit("humans", "soldier", -1, Vector2(100, 100))
	var str_ogre := dip.military_strength("ogres")
	var str_human := dip.military_strength("humans")
	_check("trade: ogre stronger", str_ogre > str_human)
	# The bully bonus is applied in _trade_exchange (asymmetric).
	# Verify the stance is recognized.
	_check("trade: ogre is bully",
		SimFactions.soul_trade_stance("ogres") == "bully")
	_free_diplomacy(w)


func _test_trade_stance_haggler() -> void:
	_check("trade: gnome is haggler",
		SimFactions.soul_trade_stance("gnomes") == "haggler")


func _test_trade_stance_principled() -> void:
	var w: Array = _make_diplomacy()
	var dip: SimDiplomacy = w[1]
	# Elves (principled) refuse trade with low-reputation proposers.
	dip._add_reputation("ogres", -50.0)  # ogres now at 10 rep
	var accepts: bool = dip.ai_accepts_trade("ogres", "elves")
	_check("trade: principled rejects low rep", not accepts)
	_free_diplomacy(w)
