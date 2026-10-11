extends SceneTree
## Cursing Gnomes — R19 faction-tick stagger tests (2026-10-05).
##
## Perf R19: SimFactions.tick ran a full unit scan every frame (~0.38ms/f
## probe-verified): snare decay, aura decay, summon expiry, warlock summon
## rolls, warlord aura pulses. It now processes every 3rd call (20Hz) with
## delta*3. These tests pin the stagger contract:
##   - ticks 1 and 2 are skipped; the 3rd processes (_tick_frame cadence)
##   - timers decay by exactly delta*3 on a processed tick (snare, aura,
##     summon life, warlock cooldown)
##   - warlord aura still marks allies with the pulse on the 3rd tick
##   - snare expiry + speed restore still flow through the stagger
##   - spirit expiry still flows through the stagger
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_faction_stagger.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes faction-stagger (R19) tests ===")
	seed(20261005)
	_test_cadence_skips_two_then_processes()
	_test_timer_parity_delta3()
	_test_warlord_aura_on_third_tick()
	_test_snare_expiry_through_stagger()
	_test_spirit_expiry_through_stagger()
	_test_ephemeral_counter()
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


## --- harness (mirrors test_faction_rosters.gd) --------------------------------

func _new_world(faction_ids: Array) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var typed: Array[String] = []
	typed.assign(faction_ids)
	gs.setup(typed)
	var fac := SimFactions.new(gs)
	gs.factions = fac
	return {"gs": gs, "factions": fac}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


## --- contract -----------------------------------------------------------------


func _test_cadence_skips_two_then_processes() -> void:
	var w: Dictionary = _new_world(["elves", "humans"])
	var fac: SimFactions = w["factions"]
	var tgt: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	tgt["speed"] = 130.0
	tgt["_snare_base"] = 130.0
	tgt["snare_t"] = 6.0
	fac.tick(1.0)
	_check("stagger: 1st tick skipped", float(tgt.get("snare_t", 0.0)) == 6.0)
	fac.tick(1.0)
	_check("stagger: 2nd tick skipped", float(tgt.get("snare_t", 0.0)) == 6.0)
	fac.tick(1.0)
	_check("stagger: 3rd tick decays by 3x delta",
		absf(float(tgt.get("snare_t", 0.0)) - 3.0) < 0.0001)
	_free_world(w)


func _test_timer_parity_delta3() -> void:
	var w: Dictionary = _new_world(["elves"])
	var fac: SimFactions = w["factions"]
	# Warlock cooldown decays by d3 on the processed tick. Idle (not
	# attacking) so the summon roll is skipped and can't reset the cd.
	var wk: Dictionary = _spawn(w, "elves", "warlock", Vector2(0, 0))
	wk["summon_cd"] = 5.0
	fac.tick(1.0)
	_check("cd: skipped on 1st tick", float(wk.get("summon_cd", 0.0)) == 5.0)
	fac.tick(1.0)
	fac.tick(1.0)
	_check("cd: decayed by 3.0 on processed tick",
		absf(float(wk.get("summon_cd", 0.0)) - 2.0) < 0.0001)
	# Aura decay parity.
	var aura: Dictionary = _spawn(w, "elves", "worker", Vector2(50, 0))
	aura["aura61"] = 2.0
	fac.tick(0.5)
	fac.tick(0.5)
	fac.tick(0.5)
	_check("aura: decayed by 1.5 on processed tick",
		absf(float(aura.get("aura61", 0.0)) - 0.5) < 0.0001)
	_free_world(w)


func _test_warlord_aura_on_third_tick() -> void:
	var w: Dictionary = _new_world(["ogres", "humans"])
	var fac: SimFactions = w["factions"]
	var wl: Dictionary = _spawn(w, "ogres", "warlord", Vector2(0, 0))
	var ally: Dictionary = _spawn(w, "ogres", "clubber", Vector2(100, 0))
	var foe: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 0))
	fac.tick(0.5)
	fac.tick(0.5)
	_check("aura: no pulse before 3rd tick",
		float(ally.get("aura61", 0.0)) == 0.0)
	fac.tick(0.5)  # processed with d3 = 1.5
	# Pulse marks the ally with 3.0; the same processed tick then decays
	# the ally by 1.5 (warlord is iterated before the later-spawned ally).
	_check("aura: ally marked on 3rd tick",
		absf(float(ally.get("aura61", 0.0)) - 1.5) < 0.01)
	_check("aura: warlord not self-marked",
		float(wl.get("aura61", 0.0)) == 0.0)
	_check("aura: foe not marked", float(foe.get("aura61", 0.0)) == 0.0)
	_free_world(w)


func _test_snare_expiry_through_stagger() -> void:
	var w: Dictionary = _new_world(["elves", "humans"])
	var fac: SimFactions = w["factions"]
	var tgt: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	tgt["speed"] = 65.0
	tgt["_snare_base"] = 130.0
	tgt["snare_t"] = 6.0
	# 6 ticks of 1.0 = two processed steps of d3 = 3.0 -> 6.0 - 6.0 = 0.
	for i: int in range(6):
		fac.tick(1.0)
	_check("snare: expires through stagger", not tgt.has("snare_t"))
	_check("snare: base speed restored",
		float(tgt.get("speed", 0.0)) == 130.0)
	_free_world(w)


func _test_spirit_expiry_through_stagger() -> void:
	var w: Dictionary = _new_world(["elves"])
	var fac: SimFactions = w["factions"]
	var s: Dictionary = _spawn(w, "elves", "ranger", Vector2(0, 0))
	s["is_summon"] = true
	s["summon_life"] = 0.05
	fac.tick(0.1)
	fac.tick(0.1)
	_check("summon: alive after skipped ticks",
		bool(s.get("alive", false)))
	fac.tick(0.1)  # processed with d3 = 0.3 -> 0.05 - 0.3 kills
	_check("summon: expires on processed tick",
		not bool(s.get("alive", true)))
	_free_world(w)


func _test_ephemeral_counter() -> void:
	# The stagger counter is plain state on the instance, not save data:
	# SimFactions carries no to_dict/from_dict (verified here), so there
	# is no save/load path to keep in sync.
	var w: Dictionary = _new_world(["humans"])
	var fac: SimFactions = w["factions"]
	_check("counter: no save path on SimFactions",
		not fac.has_method("to_dict"))
	_check("counter: starts at 0", fac._tick_frame == 0)
	fac.tick(0.1)
	_check("counter: 1 after first tick", fac._tick_frame == 1)
	fac.tick(0.1)
	fac.tick(0.1)
	_check("counter: resets after processing", fac._tick_frame == 0)
	_free_world(w)
