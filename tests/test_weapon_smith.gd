extends SceneTree
## Cursing Gnomes — fighter weapon shopping (HTML tryBuyWeapon port).
##
## Covers the AI-first phase Economy AI checklist item "equipment":
## idle fighters spend their OWN coins at a weaponsmith for +1
## weapon_level (HTML-verbatim: level < 3, 0.004 roll, nearest complete
## smith within 500 px, walk to within 50 px, personal coins, 40/80/140
## gold price, any faction's smith). The faction treasury is never
## touched, so there is no sovereignty question for the player faction.
## Deliberate deviations from HTML: guards hold their posts; the unit
## must be order-free (no player_order, deployment, disaster hunt, or
## withdrawal); a smith of a faction we're at war with is skipped.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_weapon_smith.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes weapon smith tests ===")
	_test_find_shop_nearest()
	_test_find_shop_skips_incomplete()
	_test_find_shop_range_limit()
	_test_find_shop_skips_war_enemy()
	_test_trip_blocked_guards_and_orders()
	_test_trip_starts_seeded()
	_test_purchase_pays_coins()
	_test_purchase_broke_no_sale()
	_test_purchase_maxed_no_trip()
	_test_trip_aborts_on_player_order()
	_test_damage_scales_with_level()
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


## Fresh game + combat only; captures speech bubbles.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var combat := SimCombat.new(gs)
	combat.diplomacy = gs.diplomacy  # world.gd wires this in live games
	gs.bus.unit_said.connect(func(uid: int, text: String) -> void:
		_said.append([uid, text]))
	return {"gs": gs, "combat": combat}


func _free_world(w: Dictionary) -> void:
	_said.clear()
	(w["gs"] as GameState).free()


func _soldier(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, "soldier", -1, pos)


func _smith(w: Dictionary, faction: String, pos: Vector2,
		complete: bool = true) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({"type": "weaponsmith", "faction": faction,
		"town_id": 1, "position": pos, "alive": true, "complete": complete,
		"progress": 1.0 if complete else 0.3, "hp": 400.0, "max_hp": 400.0})


func _stats(w: Dictionary) -> Dictionary:
	var combat: SimCombat = w["combat"]
	return SimCombat.MILITARY_STATS["soldier"]


## --- shop finding ------------------------------------------------------------


func _test_find_shop_nearest() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _soldier(w, "humans", Vector2(100, 100))
	_smith(w, "humans", Vector2(400, 100))  # 300 px away
	var far := _smith(w, "elves", Vector2(150, 100))  # 50 px, other faction
	var got: Dictionary = combat._find_weapon_shop(
		u["position"], "humans")
	_check("nearest smith wins (any faction serves anyone)",
		int(got.get("id", -1)) == int(far.get("id", -2)))
	_free_world(w)


func _test_find_shop_skips_incomplete() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _soldier(w, "humans", Vector2(100, 100))
	_smith(w, "humans", Vector2(120, 100), false)  # under construction
	var got: Dictionary = combat._find_weapon_shop(
		u["position"], "humans")
	_check("incomplete smith ignored", got.is_empty())
	_free_world(w)


func _test_find_shop_range_limit() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _soldier(w, "humans", Vector2(100, 100))
	_smith(w, "humans", Vector2(700, 100))  # 600 px > 500 seek range
	var got: Dictionary = combat._find_weapon_shop(
		u["position"], "humans")
	_check("smith beyond 500 px ignored", got.is_empty())
	_free_world(w)


func _test_find_shop_skips_war_enemy() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	gs.diplomacy.declare_war("humans", "ogres", "test")
	var u := _soldier(w, "humans", Vector2(100, 100))
	_smith(w, "ogres", Vector2(150, 100))  # close, but we're at war
	var got: Dictionary = combat._find_weapon_shop(
		u["position"], "humans")
	_check("war-enemy smith skipped", got.is_empty())
	# A neutral faction's smith is still fine.
	var elf_smith := _smith(w, "elves", Vector2(150, 100))
	got = combat._find_weapon_shop(u["position"], "humans")
	_check("neutral smith still served",
		int(got.get("id", -1)) == int(elf_smith.get("id", -2)))
	_free_world(w)


## --- trip gating -------------------------------------------------------------


func _test_trip_blocked_guards_and_orders() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _soldier(w, "humans", Vector2(100, 100))
	_check("plain soldier not blocked",
		not combat._weapon_trip_blocked(u))
	u["job"] = "guard"
	_check("guard blocked (holds post)", combat._weapon_trip_blocked(u))
	u["job"] = "soldier"
	u["player_order"] = {"type": "guard"}
	_check("player order blocked", combat._weapon_trip_blocked(u))
	u["player_order"] = {}
	u["deployed_for_war"] = true
	_check("war deployment blocked", combat._weapon_trip_blocked(u))
	u["deployed_for_war"] = false
	u["disaster_hunt_id"] = 99
	_check("disaster hunt blocked", combat._weapon_trip_blocked(u))
	u["disaster_hunt_id"] = -1
	u["withdrawing"] = true
	_check("withdrawal blocked", combat._weapon_trip_blocked(u))
	_free_world(w)


func _test_trip_starts_seeded() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _soldier(w, "humans", Vector2(100, 100))
	u["coins"] = 60.0
	_smith(w, "humans", Vector2(300, 100))
	seed(1234)
	var started := false
	for i in 2000:
		if combat._tick_weapon_smith(u, _stats(w), 1.0 / 60.0):
			if int(u.get("_smith_id", -1)) >= 0:
				started = true
				break
	_check("idle soldier eventually starts a smith trip", started)
	_free_world(w)


## --- purchase ----------------------------------------------------------------


func _test_purchase_pays_coins() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _soldier(w, "gnomes", Vector2(100, 100))
	u["coins"] = 60.0
	var s := _smith(w, "gnomes", Vector2(120, 100))  # within 50 px
	u["_smith_id"] = int(s["id"])
	_check("purchase tick consumed",
		combat._tick_weapon_smith(u, _stats(w), 1.0 / 60.0))
	_check("weapon_level 0 -> 1", int(u.get("weapon_level", -1)) == 1)
	_check("40 coins paid from personal purse",
		is_equal_approx(float(u.get("coins", -1.0)), 20.0))
	_check("trip flag cleared", not u.has("_smith_id"))
	_check("gnome purchase bubble",
		_said.size() == 1 and String(_said[0][1])
		== "New steel. About fucking time.")
	_free_world(w)


func _test_purchase_broke_no_sale() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _soldier(w, "humans", Vector2(100, 100))
	u["coins"] = 10.0  # can't afford the 40-gold level 1
	var s := _smith(w, "humans", Vector2(120, 100))
	u["_smith_id"] = int(s["id"])
	combat._tick_weapon_smith(u, _stats(w), 1.0 / 60.0)
	_check("broke soldier stays at level 0",
		int(u.get("weapon_level", -1)) == 0)
	_check("no coins taken", is_equal_approx(
		float(u.get("coins", -1.0)), 10.0))
	_check("no bubble when broke", _said.is_empty())
	_free_world(w)


func _test_purchase_maxed_no_trip() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _soldier(w, "humans", Vector2(100, 100))
	u["coins"] = 500.0
	u["weapon_level"] = 3
	_smith(w, "humans", Vector2(120, 100))
	seed(999)
	var tripped := false
	for i in 500:
		if combat._tick_weapon_smith(u, _stats(w), 1.0 / 60.0):
			tripped = true
			break
	_check("maxed soldier never shops", not tripped)
	_check("coins untouched", is_equal_approx(
		float(u.get("coins", -1.0)), 500.0))
	_free_world(w)


func _test_trip_aborts_on_player_order() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _soldier(w, "humans", Vector2(100, 100))
	u["coins"] = 60.0
	var s := _smith(w, "humans", Vector2(400, 100))
	u["_smith_id"] = int(s["id"])
	# Player issues an order mid-trip: the trip must die, not resume.
	u["player_order"] = {"type": "guard"}
	var consumed: bool = combat._tick_weapon_smith(
		u, _stats(w), 1.0 / 60.0)
	_check("order aborts trip flag", not u.has("_smith_id"))
	_check("aborted trip consumes nothing", not consumed)
	_free_world(w)


func _test_damage_scales_with_level() -> void:
	var w := _new_world()
	var combat: SimCombat = w["combat"]
	var u := _soldier(w, "humans", Vector2(100, 100))
	_check("level 0 damage mult is 1.0",
		is_equal_approx(combat._weapon_dmg_mult(u), 1.0))
	u["weapon_level"] = 1
	_check("level 1 damage mult is 1.08",
		is_equal_approx(combat._weapon_dmg_mult(u), 1.08))
	u["weapon_level"] = 3
	_check("level 3 damage mult is 1.24",
		is_equal_approx(combat._weapon_dmg_mult(u), 1.24))
	_free_world(w)
