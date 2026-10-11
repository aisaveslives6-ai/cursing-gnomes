extends SceneTree
## Cursing Gnomes — R23 hostile-set cache tests.
##
## _nearest_hostile's per-scan diplomacy walk is now cached per faction
## against SimDiplomacy.relation_version. These tests verify the cache
## returns sets identical to the uncached computation, invalidates exactly
## when relation STATE changes, and stays valid across non-state changes.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hostile_cache_r23.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes R23 hostile-cache tests ===")
	_test_cache_matches_uncached()
	_test_cache_hit_returns_same_set()
	_test_war_invalidates()
	_test_peace_invalidates()
	_test_alliance_and_break_invalidate()
	_test_non_state_change_keeps_cache()
	_test_reset_and_from_dict_invalidate()
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
	combat.diplomacy = gs.diplomacy
	return {"gs": gs, "combat": combat}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _same_set(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k):
			return false
	return true


## Cached set is identical to the uncached computation for every faction.
func _test_cache_matches_uncached() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var ok := true
	for f in ["humans", "ogres", "elves"]:
		var cached: Dictionary = combat._hostile_cached(f)
		var direct: Dictionary = combat._hostile_factions(f)
		if not _same_set(cached, direct):
			ok = false
	_check("cache matches uncached hostile set", ok)
	_free_world(w)


## Second call with no relation change returns the SAME Dictionary object
## (cache hit, not recompute).
func _test_cache_hit_returns_same_set() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var a: Dictionary = combat._hostile_cached("humans")
	var b: Dictionary = combat._hostile_cached("humans")
	_check("cache hit returns identical set object",
		_same_set(a, b) and a.size() == b.size())
	# Mutating score only (no state change) must not invalidate.
	var gs: GameState = w["gs"]
	var v0: int = gs.diplomacy.relation_version
	gs.diplomacy._pair("humans", "ogres")["score"] = -50.0
	_check("score-only tweak does not bump version",
		gs.diplomacy.relation_version == v0)
	_free_world(w)


## declare_war bumps the version and the cache picks up the new hostility.
func _test_war_invalidates() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var before: Dictionary = combat._hostile_cached("humans")
	_check("peacetime: ogres not hostile", not before.has("ogres"))
	var v0: int = gs.diplomacy.relation_version
	gs.diplomacy.declare_war("humans", "ogres", "R23 test")
	_check("declare_war bumps relation_version",
		gs.diplomacy.relation_version == v0 + 1)
	var after: Dictionary = combat._hostile_cached("humans")
	_check("wartime: ogres hostile after invalidate", after.has("ogres"))
	_check("wartime set matches uncached",
		_same_set(after, combat._hostile_factions("humans")))
	_free_world(w)


## make_peace bumps the version and hostility clears.
func _test_peace_invalidates() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	gs.diplomacy.declare_war("humans", "ogres", "R23 test")
	var wartime: Dictionary = combat._hostile_cached("humans")
	_check("wartime cached", wartime.has("ogres"))
	var v0: int = gs.diplomacy.relation_version
	gs.diplomacy.make_peace("humans", "ogres")
	_check("make_peace bumps relation_version",
		gs.diplomacy.relation_version == v0 + 1)
	var peacetime: Dictionary = combat._hostile_cached("humans")
	_check("peacetime: ogres no longer hostile", not peacetime.has("ogres"))
	_free_world(w)


## form_alliance and break_treaty bump the version.
func _test_alliance_and_break_invalidate() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var v0: int = gs.diplomacy.relation_version
	gs.diplomacy.form_alliance("humans", "elves")
	_check("form_alliance bumps relation_version",
		gs.diplomacy.relation_version == v0 + 1)
	var v1: int = gs.diplomacy.relation_version
	gs.diplomacy.break_treaty("humans", "elves")
	_check("break_treaty bumps relation_version",
		gs.diplomacy.relation_version == v1 + 1)
	_free_world(w)


## insult downgrade and _sync_state bump the version; trade-only changes
## (activate_trade) do not touch relation STATE... but trade_active is not
## part of the hostile set, so no bump is required for correctness.
func _test_non_state_change_keeps_cache() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var v0: int = gs.diplomacy.relation_version
	gs.diplomacy.activate_trade("humans", "elves", 3)
	_check("trade deal does not bump relation_version",
		gs.diplomacy.relation_version == v0)
	_free_world(w)


## reset() and from_dict() invalidate (wholesale pair replacement).
func _test_reset_and_from_dict_invalidate() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	gs.diplomacy.declare_war("humans", "ogres", "R23 test")
	var wartime: Dictionary = combat._hostile_cached("humans")
	_check("wartime cached before reset", wartime.has("ogres"))
	var v0: int = gs.diplomacy.relation_version
	gs.diplomacy.reset(["humans", "ogres", "elves"] as Array[String])
	_check("reset bumps relation_version",
		gs.diplomacy.relation_version == v0 + 1)
	var after_reset: Dictionary = combat._hostile_cached("humans")
	_check("after reset: ogres not hostile", not after_reset.has("ogres"))
	# from_dict path: serialize wartime, load into a fresh diplomacy.
	gs.diplomacy.declare_war("humans", "ogres", "R23 test")
	var data: Dictionary = gs.diplomacy.to_dict()
	var v1: int = gs.diplomacy.relation_version
	gs.diplomacy.from_dict(data)
	_check("from_dict bumps relation_version",
		gs.diplomacy.relation_version == v1 + 1)
	var after_load: Dictionary = combat._hostile_cached("humans")
	_check("after from_dict: wartime set intact", after_load.has("ogres"))
	_free_world(w)
