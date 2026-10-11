extends SceneTree
## Cursing Gnomes — Milestone 4 headless combat & disaster tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_combat.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes combat & disaster tests ===")
	_test_hostility()
	_test_melee_kill()
	_test_guard_leash()
	_test_archer_projectile()
	_test_cannon_splash()
	_test_guard_tower()
	_test_damage_building()
	_test_giant_ass()
	_test_giant_ass_singleton()
	_test_moose_moons_and_leaves()
	_test_bandit_raid()
	_test_wizard_and_cat()
	_test_fire_burns()
	_test_fire_spread()
	_test_firefighter_extinguish()
	_test_fire_truck_dispatch()
	_test_corpse_purge()
	_test_siege_targets_building()
	_test_siege_damage_mult()
	_test_musketeer_ranged()
	_test_warlock_ranged()
	_test_deploy_to_building()
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


## Fresh game + combat + disaster systems.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var combat := SimCombat.new(gs)
	var disasters := DisasterSim.new(gs, combat)
	return {"gs": gs, "combat": combat, "disasters": disasters}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


func _hall(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	var b: Dictionary = gs.add_building({
		"type": "town_hall", "faction": faction, "town_id": -1,
		"position": pos, "complete": true, "progress": 1.0,
		"hp": 1200.0, "max_hp": 1200.0,
	})
	return b


## --- hostility ------------------------------------------------------------


func _test_hostility() -> void:
	_check("hostile: same faction not hostile",
		not SimCombat.is_hostile("humans", "humans"))
	_check("hostile: different factions hostile",
		SimCombat.is_hostile("humans", "ogres"))
	_check("hostile: monster hostile to all",
		SimCombat.is_hostile("monster", "elves"))
	_check("hostile: all hostile to monster",
		SimCombat.is_hostile("gnomes", "monster"))
	_check("hostile: undead fights humans",
		SimCombat.is_hostile("undead", "humans"))


## --- melee -----------------------------------------------------------------


func _test_melee_kill() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var killed: Array = []
	gs.bus.unit_killed.connect(func(id: int, src: String): killed.append(id))
	var s: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var e: Dictionary = _spawn(w, "elves", "worker", Vector2(30, 0))
	_check("melee: units spawned", not s.is_empty() and not e.is_empty())
	var eid: int = int(e["id"])
	# Soldier (15 dmg / 1 s) vs 180 hp elf worker: ~12 attacks.
	for i: int in range(20):
		combat.tick_unit(s, 1.0)
		if not gs.get_unit(eid).get("alive", false):
			break
	_check("melee: enemy died", not gs.get_unit(eid).get("alive", true))
	_check("melee: unit_killed emitted", killed.has(eid))
	_check("melee: attacker marked attacking",
		String(s.get("combat_state", "")) == "attacking"
		or String(s.get("combat_state", "")) == "idle")
	_free_world(w)


func _test_guard_leash() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var g: Dictionary = _spawn(w, "humans", "guard", Vector2(200, 0))
	combat.tick_unit(g, 0.0)  # sets guard_post = spawn pos... reset it
	g["guard_post"] = Vector2(0, 0)
	g["position"] = Vector2(200, 0)
	var e: Dictionary = _spawn(w, "ogres", "soldier", Vector2(300, 0))
	# Enemy 300 px from post: beyond the 150 leash -> guard walks home.
	# (Perf R15: idle aggro scans are staggered at 20Hz — allow ticks.)
	for t in range(4):
		combat.tick_unit(g, 1.0)
	var gp: Vector2 = g.get("position", Vector2(200, 0))
	_check("guard: walks home past leash", gp.x < 200.0)
	_check("guard: state returning",
		String(g.get("combat_state", "")) == "returning")
	# Enemy close to post: guard engages.
	e["position"] = Vector2(30, 0)
	g["position"] = Vector2(0, 0)
	g["attack_cd"] = 0.0
	for t in range(4):
		combat.tick_unit(g, 1.0)
		if String(g.get("combat_state", "")) == "attacking":
			break
	_check("guard: engages near post",
		String(g.get("combat_state", "")) == "attacking")
	_free_world(w)


## --- ranged ----------------------------------------------------------------


func _test_archer_projectile() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var fired: Array = []
	gs.bus.projectile_fired.connect(func(p: Dictionary): fired.append(p))
	var a: Dictionary = _spawn(w, "humans", "archer", Vector2(0, 0))
	var e: Dictionary = _spawn(w, "elves", "worker", Vector2(200, 0))
	# (Perf R15: idle aggro scans are staggered — allow ticks to acquire.)
	for t in range(4):
		combat.tick_unit(a, 2.0)
		if fired.size() == 1:
			break
	_check("archer: projectile fired", fired.size() == 1)
	_check("archer: kind arrow", String(fired[0].get("kind", "")) == "arrow")
	# 200 px at 700 px/s: ~0.3 s to land.
	combat.tick(0.5)
	_check("archer: projectile resolved", combat.projectiles.is_empty())
	_check("archer: enemy hurt",
		float(gs.get_unit(int(e["id"])).get("hp", 180.0)) < 180.0)
	_free_world(w)


func _test_cannon_splash() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var c: Dictionary = _spawn(w, "humans", "cannoneer", Vector2(0, 0))
	var e1: Dictionary = _spawn(w, "ogres", "worker", Vector2(500, 0))
	var e2: Dictionary = _spawn(w, "ogres", "worker", Vector2(520, 0))
	var e3: Dictionary = _spawn(w, "ogres", "worker", Vector2(900, 0))
	# (Perf R15: idle aggro scans are staggered — allow ticks to acquire.)
	for t in range(4):
		combat.tick_unit(c, 5.0)  # fires at e1 (nearest)
		if combat.projectiles.size() == 1:
			break
	_check("cannon: fired", combat.projectiles.size() == 1)
	var p: Dictionary = combat.projectiles[0]
	_check("cannon: kind cannonball",
		String(p.get("kind", "")) == "cannonball")
	_check("cannon: splash 180", float(p.get("splash", 0.0)) == 180.0)
	# 500 px at 450 px/s.
	combat.tick(0.6)
	combat.tick(0.6)
	_check("cannon: resolved", combat.projectiles.is_empty())
	_check("cannon: direct target hurt",
		float(gs.get_unit(int(e1["id"])).get("hp", 550.0)) < 550.0)
	_check("cannon: splash hurt neighbor",
		float(gs.get_unit(int(e2["id"])).get("hp", 550.0)) < 550.0)
	_check("cannon: far unit unhurt",
		float(gs.get_unit(int(e3["id"])).get("hp", 550.0)) == 550.0)
	_free_world(w)


func _test_guard_tower() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var fired: Array = []
	gs.bus.projectile_fired.connect(func(p: Dictionary): fired.append(p))
	var t: Dictionary = gs.add_building({
		"type": "guard_tower", "faction": "humans", "town_id": -1,
		"position": Vector2(0, 0), "complete": true, "progress": 1.0,
		"hp": 650.0, "max_hp": 650.0,
	})
	var e: Dictionary = _spawn(w, "ogres", "soldier", Vector2(100, 0))
	combat.tick_towers(2.5)
	_check("tower: fired at hostile", fired.size() == 1)
	combat.tick(0.5)  # 100 px at 650 px/s
	_check("tower: enemy hurt",
		float(gs.get_unit(int(e["id"])).get("hp", 550.0)) < float(gs.get_unit(int(e["id"])).get("max_hp", 550.0)))
	# Blueprint (incomplete) towers stay silent. Silence the live tower
	# first so only the blueprint could possibly fire.
	t["tower_cd"] = 999.0
	var t2: Dictionary = gs.add_building({
		"type": "guard_tower", "faction": "humans", "town_id": -1,
		"position": Vector2(2000, 2000), "complete": false,
		"progress": 0.5, "hp": 650.0, "max_hp": 650.0,
	})
	var e2: Dictionary = _spawn(w, "ogres", "soldier", Vector2(2050, 2000))
	var before: int = fired.size()
	combat.tick_towers(5.0)
	_check("tower: blueprint silent", fired.size() == before)
	_free_world(w)


func _test_damage_building() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var destroyed: Array = []
	gs.bus.building_destroyed.connect(func(b: Dictionary): destroyed.append(b))
	var b: Dictionary = gs.add_building({
		"type": "house", "faction": "ogres", "town_id": -1,
		"position": Vector2(0, 0), "complete": true,
		"hp": 400.0, "max_hp": 400.0,
	})
	var bid: int = int(b["id"])
	_check("building: damaged not destroyed",
		not combat.damage_building(bid, 100.0, "humans"))
	_check("building: hp reduced",
		float(gs.buildings[0].get("hp", 0.0)) == 300.0)
	_check("building: destroyed at zero",
		combat.damage_building(bid, 500.0, "humans"))
	_check("building: record removed", gs.buildings.is_empty())
	_check("building: destroyed emitted", destroyed.size() == 1)
	_free_world(w)


## --- disasters: monsters ----------------------------------------------------


func _test_giant_ass() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var disasters: DisasterSim = w["disasters"]
	var spawned: Array = []
	gs.bus.disaster_spawned.connect(
		func(kind: String, pos: Vector2): spawned.append(kind))
	var a: Dictionary = disasters.spawn("giant_ass", Vector2(500, 500))
	_check("ass: spawned", not a.is_empty())
	_check("ass: 1200 hp", float(a.get("hp", 0.0)) == 1200.0)
	_check("ass: monster faction",
		String(a.get("faction", "")) == "monster")
	_check("ass: announced", spawned.has("giant_ass"))
	# Smasher seeks: put a hall nearby, ass should walk to it.
	_hall(w, "humans", Vector2(600, 500))
	var p0: Vector2 = a.get("position", Vector2.ZERO)
	disasters.tick(1.0)
	var p1: Vector2 = a.get("position", Vector2.ZERO)
	_check("ass: advances on target", p1.distance_to(p0) > 1.0)
	# Budget spent -> leaving.
	a["age"] = 200.0
	disasters.tick(0.1)
	_check("ass: starts leaving", bool(a.get("leaving", false)))
	# Teleport to its exit target -> removed from the world.
	a["wander_target"] = a.get("position", Vector2.ZERO)
	var aid: int = int(a["id"])
	disasters.tick(0.1)
	_check("ass: left the map", gs.get_unit(aid).is_empty())
	_free_world(w)


func _test_giant_ass_singleton() -> void:
	var w: Dictionary = _new_world()
	var disasters: DisasterSim = w["disasters"]
	var a1: Dictionary = disasters.spawn("giant_ass", Vector2(100, 100))
	var a2: Dictionary = disasters.spawn("giant_ass", Vector2(200, 200))
	_check("ass: first spawns", not a1.is_empty())
	_check("ass: second refused while one lives", a2.is_empty())
	_free_world(w)


func _test_moose_moons_and_leaves() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var disasters: DisasterSim = w["disasters"]
	var mooned: Array = []
	gs.bus.moose_mooned.connect(func(h: Dictionary): mooned.append(h))
	var m: Dictionary = disasters.spawn("thicc_moose", Vector2(0, 0))
	_check("moose: 800 hp", float(m.get("hp", 0.0)) == 800.0)
	_check("moose: harmless", float(m.get("dmg", -1.0)) == 0.0)
	var halls: Array = []
	for i: int in range(3):
		halls.append(_hall(w, "humans", Vector2(1000 + i * 500, 1000)))
	for h: Dictionary in halls:
		m["position"] = (h.get("position", Vector2.ZERO)
			as Vector2) + Vector2(50, 0)
		m["moon_pause"] = 0.0
		disasters.tick(0.1)
	_check("moose: mooned 3 halls", mooned.size() == 3)
	_check("moose: leaves after 3 moons", bool(m.get("leaving", false)))
	_free_world(w)


func _test_bandit_raid() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var disasters: DisasterSim = w["disasters"]
	var combat: SimCombat = w["combat"]
	var first: Dictionary = disasters.spawn("bandit_raid",
		Vector2(500, 500))
	_check("bandits: raid spawns", not first.is_empty())
	var n := 0
	for u: Dictionary in gs.units:
		if String(u.get("job", "")) == "bandit" and u.get("alive", false):
			n += 1
	# HTML BanditRaid parity: pack of 5-8 (2026-10-04).
	_check("bandits: 5-8 raiders", n >= 5 and n <= 8)
	var again: Dictionary = disasters.spawn("bandit_raid",
		Vector2(900, 900))
	_check("bandits: one raid at a time", again.is_empty())
	# Bandits fight through the combat AI (military job).
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(520, 500))
	# (Perf R15: idle aggro scans are staggered — allow ticks to acquire.)
	for t in range(4):
		combat.tick_unit(first, 2.0)
		if String(first.get("combat_state", "")) != "idle":
			break
	_check("bandits: engage via combat",
		String(first.get("combat_state", "")) != "idle")
	_free_world(w)


func _test_wizard_and_cat() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var disasters: DisasterSim = w["disasters"]
	var wiz: Dictionary = disasters.spawn("rogue_wizard",
		Vector2(300, 300))
	_check("wizard: spawned", not wiz.is_empty())
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(350, 300))
	disasters.tick(0.1)
	# Wizard in range should cast (projectile), fizzle his wild surge
	# (dizzy, no projectile), or close distance.
	var cast: bool = not (w["combat"] as SimCombat).projectiles.is_empty() \
		or String(wiz.get("combat_state", "")) in ["attacking", "dizzy"]
	_check("wizard: casts at victims", cast)
	var cat: Dictionary = disasters.spawn("cardboard_cat", Vector2(0, 0))
	_check("cat: spawned", not cat.is_empty())
	cat["age"] = 999.0
	disasters.tick(0.1)
	_check("cat: leaves on budget", bool(cat.get("leaving", false)))
	_free_world(w)


## --- disasters: fire ---------------------------------------------------------


func _test_fire_burns() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var disasters: DisasterSim = w["disasters"]
	var started: Array = []
	gs.bus.fire_started.connect(func(f: Dictionary): started.append(f))
	var f: Dictionary = disasters.ignite(Vector2(0, 0), 100.0)
	_check("fire: ignites", not f.is_empty())
	_check("fire: announced", started.size() == 1)
	var u: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	var b: Dictionary = gs.add_building({
		"type": "house", "faction": "humans", "town_id": -1,
		"position": Vector2(20, 0), "complete": true,
		"hp": 400.0, "max_hp": 400.0,
	})
	disasters.tick(0.5)  # one fire tick
	_check("fire: burns units",
		float(gs.get_unit(int(u["id"])).get("hp", 200.0)) < float(gs.get_unit(int(u["id"])).get("max_hp", 200.0)))
	_check("fire: burns buildings",
		float(gs.buildings[0].get("hp", 400.0)) < 400.0)
	_check("fire: marks building burning",
		bool(gs.buildings[0].get("on_fire", false)))
	_free_world(w)


func _test_fire_spread() -> void:
	var w: Dictionary = _new_world()
	var disasters: DisasterSim = w["disasters"]
	var gs: GameState = w["gs"]
	gs.add_work_site({"kind": "tree", "position": Vector2(50, 0),
		"amount": 60.0})
	disasters.ignite(Vector2(0, 0), 100.0)
	# Spread rolls at 35% per fire per 0.5 s: 40 ticks ~= certain.
	for i: int in range(40):
		disasters.tick(0.5)
		if disasters.fires.size() > 1:
			break
	_check("fire: spreads to trees", disasters.fires.size() > 1)
	_free_world(w)


func _test_firefighter_extinguish() -> void:
	var w: Dictionary = _new_world()
	var disasters: DisasterSim = w["disasters"]
	var f: Dictionary = disasters.ignite(Vector2(0, 0), 60.0)
	var ff: Dictionary = _spawn(w, "humans", "firefighter", Vector2(60, 0))
	disasters.tick_firefighter(ff, 1.0)
	_check("firefighter: extinguishing",
		String(ff.get("work_state", "")) == "extinguishing")
	disasters.tick_firefighter(ff, 1.0)
	_check("fire: put out", disasters.fires.is_empty())
	_free_world(w)


func _test_fire_truck_dispatch() -> void:
	var w: Dictionary = _new_world()
	var disasters: DisasterSim = w["disasters"]
	disasters.ignite(Vector2(0, 0), 80.0)
	# 500 px away: beyond TRUCK_MIN_DIST -> rides the truck.
	var ff: Dictionary = _spawn(w, "humans", "firefighter", Vector2(500, 0))
	disasters.tick_firefighter(ff, 1.0)
	_check("truck: dispatched", bool(ff.get("on_truck", false)))
	var p0 := Vector2(500, 0)
	var p1: Vector2 = ff.get("position", p0)
	_check("truck: fast response", p0.distance_to(p1) > 150.0)
	# Close fire: on foot.
	disasters.fires.clear()
	disasters.ignite(Vector2(560, 0), 80.0)
	ff["position"] = Vector2(500, 0)
	disasters.tick_firefighter(ff, 0.1)
	_check("truck: on foot when close", not bool(ff.get("on_truck", true)))
	_free_world(w)


## --- corpses -----------------------------------------------------------------


func _test_corpse_purge() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var purged: Array = []
	gs.bus.unit_purged.connect(func(id: int): purged.append(id))
	var u: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var uid: int = int(u["id"])
	combat.damage_unit(uid, 500.0, "ogres")
	_check("corpse: dead", not gs.get_unit(uid).get("alive", true))
	_check("corpse: lingers at first", not gs.get_unit(uid).is_empty())
	gs.game_time += 21.0
	combat.tick(1.5)  # corpse purge runs on the 1 s accumulator
	_check("corpse: purged after 20 s", gs.get_unit(uid).is_empty())
	_check("corpse: purged emitted", purged.has(uid))
	_free_world(w)


## --- faction siege ------------------------------------------------------------


func _test_siege_targets_building() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	# Treant (siege) with no hostile units nearby should target a building.
	var t: Dictionary = _spawn(w, "elves", "treant", Vector2(0, 0))
	var b: Dictionary = _hall(w, "humans", Vector2(300, 0))
	# Treant has siege flag from apply_faction_stats.
	_check("siege: treant has siege flag", bool(t.get("siege", false)))
	combat.tick_unit(t, 1.0)
	_check("siege: treant advancing on building",
		String(t.get("combat_state", "")) == "advancing"
		or String(t.get("combat_state", "")) == "sieging")
	_check("siege: treant siege_target set",
		int(t.get("siege_target", -1)) == int(b.get("id", -2)))
	_free_world(w)


func _test_siege_damage_mult() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var t: Dictionary = _spawn(w, "elves", "treant", Vector2(0, 0))
	var b: Dictionary = _hall(w, "humans", Vector2(50, 0))
	var bid: int = int(b.get("id", 0))
	var start_hp: float = float(b.get("hp", 0.0))
	# Force in-range and attack.
	t["attack_cd"] = 0.0
	combat._attack_building(t, b,
		SimCombat.MILITARY_STATS["treant"])
	b = combat._get_building(bid)
	var dealt: float = start_hp - float(b.get("hp", start_hp))
	# Treant dmg 28 x race 1.0 x siege x2 = ~56.
	_check("siege: treant deals x2 to buildings", dealt >= 50.0)
	_free_world(w)


func _test_musketeer_ranged() -> void:
	var w: Dictionary = _new_world()
	# Musketeer must be in MILITARY_STATS as ranged (not soldier melee).
	var stats: Dictionary = SimCombat.MILITARY_STATS["musketeer"]
	_check("musketeer: is ranged", bool(stats["ranged"]))
	_check("musketeer: range 210", float(stats["range"]) == 210.0)
	_free_world(w)


func _test_warlock_ranged() -> void:
	var w: Dictionary = _new_world()
	var stats: Dictionary = SimCombat.MILITARY_STATS["warlock"]
	_check("warlock: is ranged", bool(stats["ranged"]))
	_check("warlock: range 125", float(stats["range"]) == 125.0)
	# Spawned warlock gets faction stats stamped.
	var wk: Dictionary = _spawn(w, "elves", "warlock", Vector2(0, 0))
	_check("warlock: has summoner flag", bool(wk.get("summoner", false)))
	_free_world(w)


func _test_deploy_to_building() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var gs: GameState = w["gs"]
	# Soldier with a building deploy order should advance on it even with
	# no hostile units around.
	var s: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	var b: Dictionary = _hall(w, "ogres", Vector2(400, 0))
	s["deploy_target_id"] = int(b.get("id", 0))
	s["deploy_target_kind"] = "building"
	combat.tick_unit(s, 1.0)
	_check("deploy: soldier advancing on building",
		String(s.get("combat_state", "")) == "advancing"
		or String(s.get("combat_state", "")) == "sieging")
	_free_world(w)
