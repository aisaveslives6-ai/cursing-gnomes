extends SceneTree
## Cursing Gnomes — god-system performance regression tests (Jeremy 2026-10-04).
##
## Guards the 60fps optimization pass for the Seven Monasteries + Seven Dark
## Crystals: per-faction attack/combo caches (no per-attack rebuild), cache
## invalidation on capture/load, off-screen culling on the visual nodes,
## cached god defs + crystal shard layouts (no per-draw rebuild), and
## allocation-free effect-timer ticks for units without cooldowns.
##
## Run: Godot --headless --path . -s res://tests/test_god_perf.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


class _FakeCombat extends RefCounted:
	var gs = null
	func can_fight(a: String, b: String) -> bool:
		return a != b
	func damage_unit(uid: int, dmg: float, sf: String, aid: int = -1,
			kind: String = "") -> bool:
		return false
	func damage_building(_bid: int, _dmg: float, _sf: String) -> void:
		pass
	func fire_projectile(from_pos: Vector2, target_id: int,
			target_pos: Vector2, kind: String, dmg: float, splash: float,
			faction: String, speed: float) -> Dictionary:
		return {"id": 1, "kind": kind, "position": from_pos,
			"target_id": target_id, "target_pos": target_pos, "dmg": dmg,
			"splash": splash, "faction": faction, "speed": speed,
			"alive": true}


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("  FAIL: ", name)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_magic_cache()
	_test_magic_cache_invalidation()
	_test_dark_cache()
	_test_combo_cache()
	_test_cache_invalidation_on_load()
	_test_monastery_node_culling()
	_test_crystal_node_culling()
	_test_crystal_shard_cache()
	_test_effect_timers_no_cooldown_key()
	_test_corruption_sweep()
	print("god_perf: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	return gs


func _new_mons(gs: GameState) -> SimMonasteries:
	var mons := SimMonasteries.new()
	mons.setup(gs)
	var fc := _FakeCombat.new()
	fc.gs = gs
	mons.combat = fc
	gs.monasteries = mons
	mons.monasteries = [
		{"id": 1, "god_id": "auriel", "position": Vector2(1000, 1000),
			"owner": "humans", "progress": {}, "contested": false,
			"contested_by": "", "name": "M1"},
		{"id": 2, "god_id": "volkar", "position": Vector2(3000, 3000),
			"owner": "", "progress": {}, "contested": false,
			"contested_by": "", "name": "M2"},
	]
	return mons


func _new_crys(gs: GameState) -> SimDarkCrystals:
	var crys := SimDarkCrystals.new()
	crys.setup(gs)
	var fc := _FakeCombat.new()
	fc.gs = gs
	crys.combat = fc
	gs.crystals = crys
	crys.crystals = [
		{"id": 1, "god_id": "vexmor", "position": Vector2(1000, 1000),
			"owner": "humans", "progress": {}, "contested": false,
			"contested_by": "", "name": "C1", "struck_t": 0.0},
		{"id": 2, "god_id": "gigglespit", "position": Vector2(3000, 3000),
			"owner": "gnomes", "progress": {}, "contested": false,
			"contested_by": "", "name": "C2", "struck_t": 0.0},
	]
	return crys


## get_magic_attacks must return the SAME cached array on repeat calls
## (no per-attack rebuild = no per-attack allocation).
func _test_magic_cache() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	var a1 := mons.get_magic_attacks("humans")
	var a2 := mons.get_magic_attacks("humans")
	_check(a1.size() == 1, "perf: humans has 1 magic attack")
	_check(is_same(a1, a2), "perf: magic attacks cached (same instance)")
	_check(mons.get_magic_attacks("gnomes").is_empty(),
		"perf: gnomes has no magic attacks")
	gs.queue_free()


## Capture must invalidate the cache: old owner loses, new owner gains.
func _test_magic_cache_invalidation() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	_check(mons.get_magic_attacks("humans").size() == 1,
		"perf: pre-capture humans has attacks")
	var m: Dictionary = mons.monasteries[0]
	mons._capture(m, "gnomes")
	_check(mons.get_magic_attacks("humans").is_empty(),
		"perf: post-capture humans cache invalidated")
	var g_attacks := mons.get_magic_attacks("gnomes")
	_check(g_attacks.size() == 1
		and String(g_attacks[0]["god_id"]) == "auriel",
		"perf: post-capture gnomes gains auriel")
	gs.queue_free()


## get_dark_attacks must return the SAME cached array on repeat calls.
func _test_dark_cache() -> void:
	var gs := _new_game()
	var crys := _new_crys(gs)
	var a1 := crys.get_dark_attacks("humans")
	var a2 := crys.get_dark_attacks("humans")
	_check(a1.size() == 1, "perf: humans has 1 dark attack")
	_check(is_same(a1, a2), "perf: dark attacks cached (same instance)")
	var g1 := crys.get_dark_attacks("gnomes")
	_check(g1.size() == 1 and String(g1[0]["god_id"]) == "gigglespit",
		"perf: gnomes has gigglespit")
	gs.queue_free()


## get_active_combos cached; has_combo (per-hit path) uses the cache.
func _test_combo_cache() -> void:
	var gs := _new_game()
	var crys := _new_crys(gs)
	var c1 := crys.get_active_combos("humans")
	var c2 := crys.get_active_combos("humans")
	_check(is_same(c1, c2), "perf: combos cached (same instance)")
	_check(not crys.has_combo("humans", "Cruel Eclipse"),
		"perf: no Cruel Eclipse with only vexmor")
	# Give humans gigglespit too -> Cruel Eclipse (vexmor+gigglespit).
	var c: Dictionary = crys.crystals[1]
	crys._capture(c, "humans")
	_check(crys.has_combo("humans", "Cruel Eclipse"),
		"perf: Cruel Eclipse active after 2nd capture (cache invalidated)")
	gs.queue_free()


## from_dict (save/load) must invalidate caches too.
func _test_cache_invalidation_on_load() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	mons.get_magic_attacks("humans")  # prime cache
	var d := mons.to_dict()
	(d["monasteries"] as Array)[0]["owner"] = "gnomes"
	mons.from_dict(d)
	_check(mons.get_magic_attacks("humans").is_empty(),
		"perf: load invalidates magic cache")
	_check(mons.get_magic_attacks("gnomes").size() == 1,
		"perf: load restores gnomes attacks")
	var crys := _new_crys(gs)
	crys.get_dark_attacks("humans")  # prime cache
	var d2 := crys.to_dict()
	(d2["crystals"] as Array)[0]["owner"] = ""
	crys.from_dict(d2)
	_check(crys.get_dark_attacks("humans").is_empty(),
		"perf: load invalidates dark cache")
	gs.queue_free()


## MonasteryNode.set_culled stops _process and hides (60fps culling).
func _test_monastery_node_culling() -> void:
	var mn := MonasteryNode.new()
	root.add_child(mn)
	mn.setup(1, "auriel", Vector2(500, 500))
	mn.set_culled(true)
	_check(not mn.visible, "perf: culled monastery hidden")
	_check(not mn.is_processing(), "perf: culled monastery _process off")
	mn.set_culled(false)
	_check(mn.visible, "perf: unculled monastery visible")
	_check(mn.is_processing(), "perf: unculled monastery _process on")
	# Cached god def (no per-draw linear search).
	_check(not (mn._g as Dictionary).is_empty()
		and String((mn._g as Dictionary).get("id", "")) == "auriel",
		"perf: monastery god def cached")
	mn.queue_free()


## CrystalNode.set_culled stops _process and hides (60fps culling).
func _test_crystal_node_culling() -> void:
	var cn := CrystalNode.new()
	root.add_child(cn)
	cn.setup(1, "vexmor", Vector2(500, 500))
	cn.set_culled(true)
	_check(not cn.visible, "perf: culled crystal hidden")
	_check(not cn.is_processing(), "perf: culled crystal _process off")
	cn.set_culled(false)
	_check(cn.visible, "perf: unculled crystal visible")
	_check(cn.is_processing(), "perf: unculled crystal _process on")
	_check(not (cn._g as Dictionary).is_empty()
		and String((cn._g as Dictionary).get("id", "")) == "vexmor",
		"perf: crystal god def cached")
	cn.queue_free()


## Crystal shard layout computed once in setup (was 10 dicts per redraw).
func _test_crystal_shard_cache() -> void:
	var cn := CrystalNode.new()
	root.add_child(cn)
	cn.setup(3, "raijuk", Vector2.ZERO)
	_check((cn._shards as Array).size() == 5,
		"perf: crystal shard layout cached (5 shards)")
	var cn2 := CrystalNode.new()
	root.add_child(cn2)
	cn2.setup(4, "morrga", Vector2.ZERO)
	_check((cn2._shards as Array).size() == 5
		and not is_same(cn._shards, cn2._shards),
		"perf: per-god shard layouts are distinct")
	cn.queue_free()
	cn2.queue_free()


## _tick_effect_timers must not create cooldown dicts for units that
## have none (the has() guard = zero per-frame allocation when idle).
func _test_effect_timers_no_cooldown_key() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	var crys := _new_crys(gs)
	gs.add_unit({"faction": "humans", "job": "worker", "alive": true,
		"position": Vector2(100, 100), "hp": 100.0})
	mons._tick_effect_timers(0.016)
	crys._tick_effect_timers(0.016)
	var u: Dictionary = gs.units[0]
	_check(not u.has("magic_cd"),
		"perf: monastery tick adds no magic_cd key when idle")
	_check(not u.has("dark_cd"),
		"perf: crystal tick adds no dark_cd key when idle")
	# Units WITH cooldowns still tick down and clear.
	u["magic_cd"] = {"auriel": 0.001}
	u["dark_cd"] = {"vexmor": 0.001}
	mons._tick_effect_timers(0.016)
	crys._tick_effect_timers(0.016)
	_check(not u.has("magic_cd"), "perf: expired magic_cd cleared")
	_check(not u.has("dark_cd"), "perf: expired dark_cd cleared")
	gs.queue_free()


## Corruption sweep still drifts traits with per-faction caching.
func _test_corruption_sweep() -> void:
	var gs := _new_game()
	var crys := _new_crys(gs)
	gs.add_unit({"faction": "humans", "job": "worker", "alive": true,
		"position": Vector2(100, 100), "hp": 100.0,
		"mind": {"traits": {"violence": 0.1}}, "corr_drift": 0.0})
	crys._tick_corruption()
	var u: Dictionary = gs.units[0]
	_check(float(u.get("corr_drift", 0.0)) > 0.0,
		"perf: corruption sweep still drifts traits")
	gs.queue_free()
