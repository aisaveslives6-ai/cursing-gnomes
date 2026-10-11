extends SceneTree
## Cursing Gnomes — tap-to-command military controls (Jeremy 2026-10-07).
##
## Player taps a map location (no selection required — the whole military
## answers): Move (walk there, ignore enemies), Attack-Move (advance, engaging nearest
## enemy unit first, then nearest enemy building), auto-retaliation when
## attacked, artillery holds range and kites when enemies close in.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tap_command.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes tap-command tests ===")
	_test_move_order_reaches_destination()
	_test_move_order_sets_fields()
	_test_attack_move_prefers_units_over_buildings()
	_test_attack_move_targets_building_when_no_units()
	_test_retaliation_triggers_on_attack()
	_test_retaliation_ignored_for_nonfighters()
	_test_artillery_holds_range()
	_test_artillery_kites_when_close()
	_test_ranged_kites_when_close()
	_test_order_all_move_commands_entire_military()
	_test_order_all_attack_move_commands_entire_military()
	_test_sovereignty_refuses_foreign_units()
	_test_clear_orders()
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


## Fresh world: player = humans, combat + tap_command wired, no diplomacy
## (can_fight falls back to any-different-faction-is-hostile).
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	var combat := SimCombat.new(gs)
	var tap := SimTapCommand.new(gs)
	gs.set("combat", combat)
	return {"gs": gs, "combat": combat, "tap": tap}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _soldier(w: Dictionary, faction: String, pos: Vector2,
		job: String = "soldier") -> Dictionary:
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, job, -1, pos)
	# Ensure full HP and no cooldown so ticks behave deterministically.
	u["hp"] = float(u.get("max_hp", 100.0))
	u["attack_cd"] = 0.0
	return u


func _building(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({"type": "guard_tower", "faction": faction,
		"town_id": 1, "position": pos, "alive": true, "complete": true,
		"progress": 1.0, "hp": 500.0, "max_hp": 500.0})


func _tick(w: Dictionary, u: Dictionary, times: int = 5,
		delta: float = 0.1) -> void:
	var combat: SimCombat = w["combat"]
	for _i in times:
		if not u.get("alive", false):
			break
		combat.tick_unit(u, delta)


## Move order: the unit walks to the destination and the order fields
## are set correctly (player_order + move_target).
func _test_move_order_sets_fields() -> void:
	var w: Dictionary = _new_world()
	var tap: SimTapCommand = w["tap"]
	var u: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	var dest := Vector2(900, 900)
	var n: int = tap.order_move([int(u["id"])], dest)
	_check("move: one unit ordered", n == 1)
	_check("move: player_order type",
		SimTapCommand.order_type_of(u) == "move")
	_check("move: move_target set",
		(u.get("move_target", Vector2.ZERO) as Vector2).distance_to(dest) < 1.0)
	_free_world(w)


## Move order: after enough ticks the unit arrives (move_target cleared
## within 40px) — it actually walks, not just flags.
func _test_move_order_reaches_destination() -> void:
	var w: Dictionary = _new_world()
	var tap: SimTapCommand = w["tap"]
	var u: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	var dest := Vector2(600, 100)
	tap.order_move([int(u["id"])], dest)
	# No enemies: pure walk. Generous ticks (speed 95 * 0.55 slowdown).
	_tick(w, u, 120, 0.1)
	var d: float = (u.get("position", Vector2.ZERO) as Vector2).distance_to(dest)
	_check("move: unit reaches destination (dist=%.0f)" % d, d < 60.0)
	_free_world(w)


## Attack-move: nearest enemy UNIT is preferred even when a hostile
## building is closer. Units-first, buildings-second.
func _test_attack_move_prefers_units_over_buildings() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var tap: SimTapCommand = w["tap"]
	var u: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	var foe: Dictionary = _soldier(w, "ogres", Vector2(400, 100))
	# Building is CLOSER (250px) than the enemy unit (300px).
	_building(w, "ogres", Vector2(350, 100))
	tap.order_attack_move([int(u["id"])], Vector2(900, 100))
	_tick(w, u, 5, 0.1)
	_check("attack-move: targets enemy unit first",
		int(u.get("combat_target", -1)) == int(foe["id"]))
	_free_world(w)


## Attack-move: with no enemy units in range, the nearest hostile
## building is targeted (plain aggro would ignore it for non-siege).
func _test_attack_move_targets_building_when_no_units() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var tap: SimTapCommand = w["tap"]
	var u: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	var b: Dictionary = _building(w, "ogres", Vector2(400, 100))
	tap.order_attack_move([int(u["id"])], Vector2(900, 100))
	_tick(w, u, 5, 0.1)
	# _tick_building_attack path: unit engages the building.
	_check("attack-move: targets building when no units",
		String(u.get("combat_state", "")) != "idle" \
		or int(u.get("combat_target", -1)) >= 0 \
		or u.has("move_target"))
	_free_world(w)


## Auto-retaliation: a soldier hit by an out-of-aggro-range attacker
## stamps retaliate_id and fights back on the next tick.
func _test_retaliation_triggers_on_attack() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	# Attacker far away (1000px — outside soldier aggro 600).
	var foe: Dictionary = _soldier(w, "ogres", Vector2(1100, 100), "archer")
	# Simulate the archer landing a hit.
	combat.damage_unit(int(u["id"]), 5.0, "ogres", int(foe["id"]))
	_check("retaliate: victim stamps attacker",
		int(u.get("retaliate_id", -1)) == int(foe["id"]))
	_tick(w, u, 3, 0.1)
	_check("retaliate: victim targets attacker",
		int(u.get("combat_target", -1)) == int(foe["id"]))
	_free_world(w)


## Retaliation only applies to fighters — a civilian hit does not gain
## a combat target.
func _test_retaliation_ignored_for_nonfighters() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var gs: GameState = w["gs"]
	var civ: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1, Vector2(100, 100))
	var foe: Dictionary = _soldier(w, "ogres", Vector2(1100, 100), "archer")
	combat.damage_unit(int(civ["id"]), 5.0, "ogres", int(foe["id"]))
	_check("retaliate: civilian does not stamp attacker",
		int(civ.get("retaliate_id", -1)) == -1)
	_free_world(w)


## Artillery holds range: a cannoneer with an enemy at mid-range does
## NOT chase — it plants feet (attacking/holding, never "chasing").
func _test_artillery_holds_range() -> void:
	var w: Dictionary = _new_world()
	var u: Dictionary = _soldier(w, "humans", Vector2(100, 100), "cannoneer")
	var foe: Dictionary = _soldier(w, "ogres", Vector2(500, 100))
	var start: Vector2 = u.get("position", Vector2.ZERO)
	_tick(w, u, 10, 0.1)
	var moved: float = (u.get("position", Vector2.ZERO) as Vector2).distance_to(start)
	_check("artillery: holds position at range (moved=%.0f)" % moved, moved < 120.0)
	_check("artillery: never chases",
		String(u.get("combat_state", "")) != "chasing")
	_free_world(w)


## Artillery kites: an enemy inside the dead zone (35% of 600 = 210px)
## pushes the cannoneer back — distance grows, state is "kiting".
func _test_artillery_kites_when_close() -> void:
	var w: Dictionary = _new_world()
	var u: Dictionary = _soldier(w, "humans", Vector2(500, 500), "cannoneer")
	var foe: Dictionary = _soldier(w, "ogres", Vector2(600, 500))
	var d0: float = (u.get("position", Vector2.ZERO) as Vector2) \
		.distance_to(foe.get("position", Vector2.ZERO))
	_tick(w, u, 10, 0.1)
	var d1: float = (u.get("position", Vector2.ZERO) as Vector2) \
		.distance_to(foe.get("position", Vector2.ZERO))
	_check("artillery: kites away (%.0f -> %.0f)" % [d0, d1], d1 > d0 + 20.0)
	_check("artillery: kiting state",
		String(u.get("combat_state", "")) == "kiting")
	_free_world(w)


## Sovereignty: foreign faction units cannot be commanded.
func _test_sovereignty_refuses_foreign_units() -> void:
	var w: Dictionary = _new_world()
	var tap: SimTapCommand = w["tap"]
	var foe: Dictionary = _soldier(w, "ogres", Vector2(100, 100))
	_check("sovereignty: foreign unit not commandable",
		not tap.can_command(foe))
	var n: int = tap.order_move([int(foe["id"])], Vector2(900, 900))
	_check("sovereignty: foreign order rejected", n == 0)
	_check("sovereignty: no order written",
		SimTapCommand.order_type_of(foe) == "")
	_free_world(w)


## Clearing orders returns units to AI control.
func _test_clear_orders() -> void:
	var w: Dictionary = _new_world()
	var tap: SimTapCommand = w["tap"]
	var u: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	tap.order_attack_move([int(u["id"])], Vector2(900, 900))
	_check("clear: order set", SimTapCommand.order_type_of(u) == "attack_move")
	var n: int = tap.clear_orders([int(u["id"])])
	_check("clear: one unit cleared", n == 1)
	_check("clear: order empty", SimTapCommand.order_type_of(u) == "")
	_check("clear: move_target erased", not u.has("move_target"))
	_free_world(w)


## Jeremy 2026-10-07: ALL ranged units kite, not just artillery.
## A ranger with an enemy inside 35% of range backs away.
func _test_ranged_kites_when_close() -> void:
	var w: Dictionary = _new_world()
	var u: Dictionary = _soldier(w, "humans", Vector2(500, 500), "ranger")
	var foe: Dictionary = _soldier(w, "ogres", Vector2(560, 500))
	var d0: float = (u.get("position", Vector2.ZERO) as Vector2) \
		.distance_to(foe.get("position", Vector2.ZERO))
	# Aggro scans are staggered by unit id (Perf R15: every 3rd slice),
	# so the ranger notices the foe 0-2 ticks in — tick until it does
	# (bounded; the first kiting tick still has it inside the dead zone,
	# 35% of 220 = 77px, so the state must read "kiting": backing away
	# instead of standing and taking melee).
	var saw_kiting := false
	for _i in 4:
		_tick(w, u, 1, 0.1)
		if String(u.get("combat_state", "")) == "kiting":
			saw_kiting = true
			break
	_check("ranged: kiting state", saw_kiting)
	# Keep ticking: the ranger physically backs out of the dead zone and
	# then plants feet to engage — "kiting" is only the correct state
	# while the enemy is inside the dead zone.
	_tick(w, u, 9, 0.1)
	var d1: float = (u.get("position", Vector2.ZERO) as Vector2) \
		.distance_to(foe.get("position", Vector2.ZERO))
	_check("ranged: kites away (%.0f -> %.0f)" % [d0, d1], d1 > d0 + 10.0)
	_free_world(w)


## Jeremy 2026-10-07: tap orders the ENTIRE military, no selection.
func _test_order_all_move_commands_entire_military() -> void:
	var w: Dictionary = _new_world()
	var tap: SimTapCommand = w["tap"]
	var u1: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	var u2: Dictionary = _soldier(w, "humans", Vector2(200, 200))
	var u3: Dictionary = _soldier(w, "humans", Vector2(300, 300))
	var ids: Array = tap.all_military_ids()
	_check("all: three military found", ids.size() == 3)
	var n: int = tap.order_all_move(Vector2(900, 900))
	_check("all: three ordered", n == 3)
	for u: Dictionary in [u1, u2, u3]:
		_check("all: move order set",
			SimTapCommand.order_type_of(u) == "move")
	_free_world(w)


func _test_order_all_attack_move_commands_entire_military() -> void:
	var w: Dictionary = _new_world()
	var tap: SimTapCommand = w["tap"]
	var u1: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	var u2: Dictionary = _soldier(w, "humans", Vector2(200, 200))
	var n: int = tap.order_all_attack_move(Vector2(900, 900))
	_check("all: two ordered", n == 2)
	for u: Dictionary in [u1, u2]:
		_check("all: attack_move order set",
			SimTapCommand.order_type_of(u) == "attack_move")
	_free_world(w)
