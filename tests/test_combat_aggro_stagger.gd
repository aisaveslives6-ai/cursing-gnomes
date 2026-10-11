extends SceneTree
## Cursing Gnomes — combat idle-scan stagger (perf R15) tests.
##
## Two implementation-only optimizations in SimCombat:
##  1. _hostile_factions(): hostile-faction set snapshotted once per scan,
##     hoisting the per-candidate diplomacy lookup out of _nearest_hostile's
##     inner loop. Must match per-candidate can_fight() exactly.
##  2. Idle-scan stagger: order-free soldiers (no hunt, no deploy, no active
##     target) run _nearest_hostile every 3rd AI slice (_aggro_cd counter,
##     staggered by id) instead of every slice. Engaged/hunting/deployed
##     units scan every slice — combat behavior unchanged.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_combat_aggro_stagger.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes combat aggro-stagger tests ===")
	_test_hostile_set_parity()
	_test_hostile_set_war_peace()
	_test_aggro_cd_init_stagger()
	_test_idle_scans_every_third()
	_test_idle_still_acquires_target()
	_test_engaged_scans_every_tick()
	_test_hunt_skips_stagger()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves"])
	var combat := SimCombat.new(gs)
	# Wire diplomacy like world.gd does (line 223); without it can_fight
	# falls back to is_hostile (any two factions = hostile).
	combat.diplomacy = gs.diplomacy
	return {"gs": gs, "combat": combat}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _soldier(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, "soldier", -1, pos)
	u["alive"] = true
	return u


## _hostile_factions must agree with per-candidate can_fight for every faction.
func _test_hostile_set_parity() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var gs: GameState = w["gs"]
	gs.diplomacy.declare_war("humans", "ogres", "test")
	for f in ["humans", "ogres", "elves"]:
		var hs: Dictionary = combat._hostile_factions(String(f))
		for other in ["humans", "ogres", "elves", "monster"]:
			var via_set: bool = hs.has(other)
			var via_call: bool = combat.can_fight(String(f), other)
			_check("hostile set parity %s vs %s" % [f, other],
				via_set == via_call)
	_free_world(w)


## War/peace reflected: ogres hostile to humans when at war, elves not.
func _test_hostile_set_war_peace() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var gs: GameState = w["gs"]
	gs.diplomacy.declare_war("humans", "ogres", "test")
	var hs: Dictionary = combat._hostile_factions("humans")
	_check("ogres hostile when at war", hs.has("ogres"))
	_check("elves not hostile when at peace", not hs.has("elves"))
	_check("humans not hostile to self", not hs.has("humans"))
	_check("monster always hostile", hs.has("monster"))
	_free_world(w)


## _aggro_cd initializes staggered by unit id.
func _test_aggro_cd_init_stagger() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var seen := {}
	for i in range(6):
		var s: Dictionary = _soldier(w, "humans", Vector2(i * 10.0, 0.0))
		combat.tick_unit(s, 1.0 / 60.0)
		var cd: int = int(s.get("_aggro_cd", -99))
		_check("aggro_cd in 0..2 (unit %d)" % i, cd >= 0 and cd <= 2)
		seen[int(s.get("id", 0)) % 3] = true
	# All three stagger phases represented across 6 units.
	_check("stagger phases distributed", seen.size() == 3)
	_free_world(w)


## Idle soldier: exactly one aggro scan per 3 ticks (counter cycles 0->2->1->0).
func _test_idle_scans_every_third() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var s: Dictionary = _soldier(w, "humans", Vector2(0, 0))
	# No enemies anywhere: the soldier stays idle; observe the counter.
	combat.tick_unit(s, 1.0 / 60.0)  # _ensure_fields runs; first stagger step
	var seq: Array = []
	for t in range(9):
		seq.append(int(s.get("_aggro_cd", -99)))
		combat.tick_unit(s, 1.0 / 60.0)
	# The counter must cycle with period 3 (one scan per 3 ticks).
	var period_ok := true
	for t in range(6):
		if int(seq[t]) != int(seq[t + 3]):
			period_ok = false
	_check("aggro_cd cycles with period 3", period_ok)
	# And the soldier stayed idle the whole time (no phantom targets).
	_check("idle soldier stays idle", String(s.get("combat_state", "")) == "idle")
	_check("idle soldier has no target", int(s.get("combat_target", -2)) == -1)
	_free_world(w)


## Idle soldier still acquires a nearby enemy — within 3 ticks (stagger delay).
func _test_idle_still_acquires_target() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var gs: GameState = w["gs"]
	gs.diplomacy.declare_war("humans", "ogres", "test")
	var s: Dictionary = _soldier(w, "humans", Vector2(0, 0))
	var e: Dictionary = _soldier(w, "ogres", Vector2(100, 0))
	combat._invalidate_unit_grid()
	var acquired := false
	for t in range(4):
		combat.tick_unit(s, 1.0 / 60.0)
		if int(s.get("combat_target", -1)) == int(e.get("id", -2)):
			acquired = true
			break
	_check("idle soldier acquires enemy within stagger window", acquired)
	_free_world(w)


## Engaged soldier (active combat_target): stagger block skipped, scans run.
func _test_engaged_scans_every_tick() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var gs: GameState = w["gs"]
	gs.diplomacy.declare_war("humans", "ogres", "test")
	var s: Dictionary = _soldier(w, "humans", Vector2(0, 0))
	var e: Dictionary = _soldier(w, "ogres", Vector2(100, 0))
	# Simulate an engaged soldier: active target recorded.
	s["combat_target"] = int(e.get("id", 0))
	s["_aggro_cd"] = 2  # would-be skip if stagger applied
	combat._invalidate_unit_grid()
	combat.tick_unit(s, 1.0 / 60.0)
	# Stagger must NOT have touched the counter for an engaged unit.
	_check("engaged unit bypasses stagger", int(s.get("_aggro_cd", -99)) == 2)
	# And it still sees its enemy (scan ran, target re-acquired).
	_check("engaged unit keeps target",
		int(s.get("combat_target", -1)) == int(e.get("id", -2)))
	_free_world(w)


## Disaster-hunt order: stagger skipped (hunt path takes precedence anyway).
func _test_hunt_skips_stagger() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var s: Dictionary = _soldier(w, "humans", Vector2(0, 0))
	s["disaster_hunt_id"] = 424242  # dead/gone prey id
	s["_aggro_cd"] = 2
	combat.tick_unit(s, 1.0 / 60.0)
	# Hunt id cleared (prey gone), stagger counter untouched.
	_check("hunt clears dead prey id", int(s.get("disaster_hunt_id", -2)) == -1)
	_check("hunt path bypasses stagger", int(s.get("_aggro_cd", -99)) == 2)
	_free_world(w)
