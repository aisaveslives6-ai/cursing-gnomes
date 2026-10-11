extends SceneTree
## Cursing Gnomes — R27 warlord aura cache tests.
##
## Perf R27: _warlord_nearby() used to linear-scan ALL units on every attack
## (~134us/call); it now reads a per-tick faction->positions cache. These
## checks pin behavior parity: the cache finds the same warlords, applies
## the same x1.25 aura, skips self/downend/dead/enemy-faction warlords, and
## works on first use (AI slices run before combat.tick on frame 1).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_warlord_aura_r27.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes R27 warlord aura cache tests ===")
	_test_aura_applies_with_warlord_near()
	_test_aura_damage_ratio()
	_test_no_aura_when_warlord_far()
	_test_no_self_aura()
	_test_no_aura_from_dead_or_downed_warlord()
	_test_no_aura_from_enemy_warlord()
	_test_cache_rebuilds_on_promotion()
	_test_lazy_build_before_first_tick()
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
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	var combat := SimCombat.new(gs)
	return {"gs": gs, "combat": combat}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


## One melee attack's deterministic hp delta (soldier vs soldier, same map).
func _attack_delta(combat: SimCombat, a: Dictionary,
		t: Dictionary) -> float:
	var before: float = float(t.get("hp", 0.0))
	a["attack_cd"] = 0.0
	combat._attack(a, t, SimCombat.MILITARY_STATS["soldier"])
	return before - float(t.get("hp", 0.0))


func _test_aura_applies_with_warlord_near() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var a: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var t: Dictionary = _spawn(w, "ogres", "soldier", Vector2(40, 0))
	t["hp"] = 10000.0
	t["max_hp"] = 10000.0
	var wl: Dictionary = _spawn(w, "humans", "soldier", Vector2(100, 0))
	wl["warlord"] = true
	combat.tick(1.0 / 60.0)  # refresh cache
	_check("aura: warlord within 320px detected",
		combat._warlord_nearby(Vector2(0, 0), "humans", int(a.get("id", -1))))
	_free_world(w)


func _test_aura_damage_ratio() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var a: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var t: Dictionary = _spawn(w, "ogres", "soldier", Vector2(40, 0))
	t["hp"] = 10000.0
	t["max_hp"] = 10000.0
	var wl: Dictionary = _spawn(w, "humans", "soldier", Vector2(100, 0))
	wl["warlord"] = true
	combat.tick(1.0 / 60.0)
	var with_aura: float = _attack_delta(combat, a, t)
	wl["position"] = Vector2(5000, 5000)
	combat.tick(1.0 / 60.0)
	var without_aura: float = _attack_delta(combat, a, t)
	_check("aura: damage x1.25 with warlord near",
		absf(with_aura - without_aura * SimCombat.WARLORD_AURA_MUL) < 0.01)
	_free_world(w)


func _test_no_aura_when_warlord_far() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var a: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var wl: Dictionary = _spawn(w, "humans", "soldier", Vector2(5000, 5000))
	wl["warlord"] = true
	combat.tick(1.0 / 60.0)
	_check("aura: warlord 5000px away not detected",
		not combat._warlord_nearby(Vector2(0, 0), "humans",
			int(a.get("id", -1))))
	_free_world(w)


func _test_no_self_aura() -> void:
	# Old code skipped the attacker's own record (a warlord never auras
	# itself); the cache must preserve that.
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var wl: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	wl["warlord"] = true
	combat.tick(1.0 / 60.0)
	_check("aura: warlord does not aura itself",
		not combat._warlord_nearby(Vector2(0, 0), "humans",
			int(wl.get("id", -1))))
	_free_world(w)


func _test_no_aura_from_dead_or_downed_warlord() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var a: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var dead: Dictionary = _spawn(w, "humans", "soldier", Vector2(50, 0))
	dead["warlord"] = true
	dead["alive"] = false
	var downed: Dictionary = _spawn(w, "humans", "soldier", Vector2(60, 0))
	downed["warlord"] = true
	downed["downed"] = true
	combat.tick(1.0 / 60.0)
	_check("aura: dead/downed warlords ignored",
		not combat._warlord_nearby(Vector2(0, 0), "humans",
			int(a.get("id", -1))))
	_free_world(w)


func _test_no_aura_from_enemy_warlord() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var a: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var ew: Dictionary = _spawn(w, "ogres", "soldier", Vector2(50, 0))
	ew["warlord"] = true
	combat.tick(1.0 / 60.0)
	_check("aura: enemy warlord not detected for humans",
		not combat._warlord_nearby(Vector2(0, 0), "humans",
			int(a.get("id", -1))))
	_check("aura: enemy warlord detected for ogres",
		combat._warlord_nearby(Vector2(0, 0), "ogres",
			int(a.get("id", -1))))
	_free_world(w)


func _test_cache_rebuilds_on_promotion() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var a: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var future: Dictionary = _spawn(w, "humans", "soldier", Vector2(50, 0))
	combat.tick(1.0 / 60.0)
	_check("aura: no aura before promotion",
		not combat._warlord_nearby(Vector2(0, 0), "humans",
			int(a.get("id", -1))))
	future["warlord"] = true
	combat.tick(1.0 / 60.0)
	_check("aura: aura appears after promotion + tick",
		combat._warlord_nearby(Vector2(0, 0), "humans",
			int(a.get("id", -1))))
	_free_world(w)


func _test_lazy_build_before_first_tick() -> void:
	# AI slices call tick_unit before combat.tick on frame 1; the first
	# _warlord_nearby must still find warlords (lazy build).
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var a: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var wl: Dictionary = _spawn(w, "humans", "soldier", Vector2(100, 0))
	wl["warlord"] = true
	_check("aura: found on first use without tick()",
		combat._warlord_nearby(Vector2(0, 0), "humans",
			int(a.get("id", -1))))
	_free_world(w)
