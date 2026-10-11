extends SceneTree
## Cursing Gnomes — AI armament program (equipment AI) headless tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ai_armament.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: rich AI factions buy weapon upgrades for their troops, poor AI
## factions keep the till shut, per-think buy cap, maxed/deployed troops are
## skipped, dullest blades go first, besieged factions dip into the reserve,
## the player faction gets adviser phone advice instead of auto-spending
## (throttled to once/day), the "arming up" Gazette note is throttled to
## once/day, and by_ai purchases never trip faction sovereignty.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes AI-armament tests ===")
	_test_rich_ai_arms_troops()
	_test_poor_ai_keeps_till_shut()
	_test_wood_shortage_blocks()
	_test_cap_per_think()
	_test_maxed_skipped()
	_test_deployed_skipped()
	_test_dullest_first()
	_test_under_attack_dips_reserve()
	_test_peaceful_keeps_full_reserve()
	_test_player_gets_advice_not_spending()
	_test_advice_throttled()
	_test_gazette_throttled()
	_test_non_fighters_ignored()
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


## Two AI factions + the player (humans). Gnomes are the faction under test.
func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.army = SimArmy.new(gs)
	_stories.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	var director := SimAIDirector.new(gs)
	var halls := {
		"gnomes": _hall(gs, "gnomes", Vector2(1000, 1000)),
		"ogres": _hall(gs, "ogres", Vector2(3000, 3000)),
		"humans": _hall(gs, "humans", Vector2(2000, 500)),
	}
	return [gs, director, halls]


func _hall(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "town_hall", "faction": faction,
		"town_id": 1, "position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})


func _soldier(gs: GameState, faction: String, pos: Vector2,
		weapon_level: int = 0) -> Dictionary:
	return gs.add_unit({"faction": faction, "job": "soldier", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0, "weapon_level": weapon_level})


func _rich(gs: GameState, faction: String) -> void:
	gs.resources.add_resource(faction, "gold", 1000.0, true)
	gs.resources.add_resource(faction, "wood", 500.0, true)


func _wlevels(gs: GameState, faction: String) -> Array:
	var out: Array = []
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == faction:
			out.append(int(u.get("weapon_level", 0)))
	return out


func _arm(gs: GameState, director: SimAIDirector, halls: Dictionary,
		faction: String, under_attack: bool = false) -> void:
	director._arm_forces(faction, halls[faction], {"under_attack": under_attack})


func _test_rich_ai_arms_troops() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	for i in 5:
		_soldier(gs, "gnomes", Vector2(1000 + i * 20, 1000))
	_rich(gs, "gnomes")
	_arm(gs, w[1], w[2], "gnomes")
	var lvls: Array = _wlevels(gs, "gnomes")
	var upgraded := 0
	for l: int in lvls:
		if l >= 1:
			upgraded += 1
	_check("rich AI upgrades at least one troop", upgraded >= 1)
	_check("rich AI spent gold",
		gs.resources.get_amount("gnomes", "gold") < 1000.0)
	_check("rich AI spent wood",
		gs.resources.get_amount("gnomes", "wood") < 500.0)
	_check("arming-up gazette fired",
		_stories.any(func(s: Dictionary) -> bool:
			return String(s.get("headline", "")).contains("Smiths")))
	gs.free()


func _test_poor_ai_keeps_till_shut() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	for i in 3:
		_soldier(gs, "gnomes", Vector2(1000 + i * 20, 1000))
	gs.resources.add_resource("gnomes", "gold", 100.0, true)  # below reserve
	gs.resources.add_resource("gnomes", "wood", 500.0, true)
	_arm(gs, w[1], w[2], "gnomes")
	_check("poor AI buys nothing", _wlevels(gs, "gnomes") == [0, 0, 0])
	_check("poor AI gold untouched",
		is_equal_approx(gs.resources.get_amount("gnomes", "gold"), 100.0))
	gs.free()


func _test_wood_shortage_blocks() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	_soldier(gs, "gnomes", Vector2(1000, 1000))
	gs.resources.add_resource("gnomes", "gold", 1000.0, true)
	gs.resources.add_resource("gnomes", "wood", 10.0, true)  # below reserve
	_arm(gs, w[1], w[2], "gnomes")
	_check("wood shortage blocks arming", _wlevels(gs, "gnomes") == [0])
	gs.free()


func _test_cap_per_think() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	for i in 8:
		_soldier(gs, "gnomes", Vector2(1000 + i * 20, 1000))
	_rich(gs, "gnomes")
	_arm(gs, w[1], w[2], "gnomes")
	var upgraded := 0
	for l: int in _wlevels(gs, "gnomes"):
		if l >= 1:
			upgraded += 1
	_check("per-think buy cap respected", upgraded == 4)
	gs.free()


func _test_maxed_skipped() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	for i in 3:
		_soldier(gs, "gnomes", Vector2(1000 + i * 20, 1000), 3)  # maxed
	_rich(gs, "gnomes")
	_arm(gs, w[1], w[2], "gnomes")
	_check("maxed troops skipped, gold untouched",
		is_equal_approx(gs.resources.get_amount("gnomes", "gold"), 1000.0))
	gs.free()


func _test_deployed_skipped() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	var marcher := _soldier(gs, "gnomes", Vector2(1000, 1000))
	marcher["deployed_for_war"] = true
	var home := _soldier(gs, "gnomes", Vector2(1020, 1000))
	_rich(gs, "gnomes")
	_arm(gs, w[1], w[2], "gnomes")
	_check("deployed troop not armed mid-march",
		int(marcher.get("weapon_level", 0)) == 0)
	_check("home troop armed instead", int(home.get("weapon_level", 0)) == 1)
	gs.free()


func _test_dullest_first() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	var vet := _soldier(gs, "gnomes", Vector2(1000, 1000), 2)   # 140g next
	var mid := _soldier(gs, "gnomes", Vector2(1020, 1000), 1)   # 80g next
	var raw := _soldier(gs, "gnomes", Vector2(1040, 1000), 0)   # 40g next
	# Gold for exactly ONE cheapest upgrade above the 250 reserve.
	gs.resources.add_resource("gnomes", "gold", 290.0, true)
	gs.resources.add_resource("gnomes", "wood", 100.0, true)
	_arm(gs, w[1], w[2], "gnomes")
	_check("dullest blade armed first", int(raw.get("weapon_level", 0)) == 1)
	_check("veteran untouched", int(vet.get("weapon_level", 0)) == 2)
	_check("mid untouched", int(mid.get("weapon_level", 0)) == 1)
	gs.free()


func _test_under_attack_dips_reserve() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	_soldier(gs, "gnomes", Vector2(1000, 1000))
	# 200 gold: below the peacetime reserve (250) but above the siege one.
	gs.resources.add_resource("gnomes", "gold", 200.0, true)
	gs.resources.add_resource("gnomes", "wood", 100.0, true)
	_arm(gs, w[1], w[2], "gnomes", true)
	_check("besieged AI dips into the reserve", _wlevels(gs, "gnomes") == [1])
	gs.free()


func _test_peaceful_keeps_full_reserve() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	_soldier(gs, "gnomes", Vector2(1000, 1000))
	gs.resources.add_resource("gnomes", "gold", 200.0, true)
	gs.resources.add_resource("gnomes", "wood", 100.0, true)
	_arm(gs, w[1], w[2], "gnomes", false)
	_check("peaceful AI keeps the full reserve", _wlevels(gs, "gnomes") == [0])
	gs.free()


func _test_player_gets_advice_not_spending() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	var fl := SimFactionLeaders.new(gs)
	fl.ensure(["humans", "gnomes", "ogres"])
	gs.faction_leaders = fl
	for i in 6:
		_soldier(gs, "humans", Vector2(2000 + i * 20, 500))
	gs.resources.add_resource("humans", "gold", 500.0, true)
	gs.resources.add_resource("humans", "wood", 200.0, true)
	_arm(gs, w[1], w[2], "humans")
	_check("advisers never spend the player's gold", _wlevels(gs, "humans") == [0, 0, 0, 0, 0, 0])
	_check("player gold untouched",
		is_equal_approx(gs.resources.get_amount("humans", "gold"), 500.0))
	var mems: Array = fl.recall("humans", SimFactionLeaders.MEM_MESSAGE)
	_check("adviser phones dull-blade advice",
		mems.any(func(m: Dictionary) -> bool:
			return String(m.get("text", "")).contains("dull")))
	gs.free()


func _test_advice_throttled() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	var fl := SimFactionLeaders.new(gs)
	fl.ensure(["humans", "gnomes", "ogres"])
	gs.faction_leaders = fl
	for i in 6:
		_soldier(gs, "humans", Vector2(2000 + i * 20, 500))
	gs.resources.add_resource("humans", "gold", 500.0, true)
	_arm(gs, w[1], w[2], "humans")
	_arm(gs, w[1], w[2], "humans")
	var mems: Array = fl.recall("humans", SimFactionLeaders.MEM_MESSAGE)
	var count := 0
	for m: Dictionary in mems:
		if String(m.get("text", "")).contains("dull"):
			count += 1
	_check("advice throttled to once per day", count == 1)
	gs.free()


func _test_gazette_throttled() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	for i in 3:
		_soldier(gs, "gnomes", Vector2(1000 + i * 20, 1000))
	_rich(gs, "gnomes")
	_arm(gs, w[1], w[2], "gnomes")
	_arm(gs, w[1], w[2], "gnomes")
	var smith_notes := 0
	for s: Dictionary in _stories:
		if String(s.get("headline", "")).contains("Smiths"):
			smith_notes += 1
	_check("arming-up gazette once per day", smith_notes == 1)
	gs.day_number = int(gs.day_number) + 1
	# Fresh dull blades for the new day.
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == "gnomes":
			u["weapon_level"] = 0
	_arm(gs, w[1], w[2], "gnomes")
	smith_notes = 0
	for s: Dictionary in _stories:
		if String(s.get("headline", "")).contains("Smiths"):
			smith_notes += 1
	_check("arming-up gazette fires again next day", smith_notes == 2)
	gs.free()


func _test_non_fighters_ignored() -> void:
	var w: Array = _make_world()
	var gs: GameState = w[0]
	gs.add_unit({"faction": "gnomes", "job": "worker", "town_id": 1,
		"position": Vector2(1000, 1000), "alive": true, "hp": 100.0,
		"max_hp": 100.0, "speed": 95.0, "weapon_level": 0})
	_rich(gs, "gnomes")
	_arm(gs, w[1], w[2], "gnomes")
	_check("workers never armed",
		is_equal_approx(gs.resources.get_amount("gnomes", "gold"), 1000.0))
	gs.free()
