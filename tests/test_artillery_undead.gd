extends SceneTree
## Cursing Gnomes — Milestone 5 artillery + undead death-economy tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_artillery_undead.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
##
## Numbers asserted here are the HTML build's verbatim mechanics (fix79):
## vehicles (spawnVehicleAtDepot / fireArtyVehicle / updateArtyVehicles),
## crews (mountVehicle / dismountVehicle / ensureArtyCrew), AA (aa_tower /
## anti_nuke blocks), soul essence + corpses + necromancy (C61), ghoul feeding,
## plague clouds, flesh farms, zombie hunger (C62).


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes artillery + undead tests ===")
	_test_vehicle_stats()
	_test_vehicle_training()
	_test_vehicle_pool_cap()
	_test_crew_mount_dismount()
	_test_crew_auto_assign()
	_test_vehicle_fire()
	_test_rocket_salvo()
	_test_jumbo_warhead()
	_test_vehicle_cookoff()
	_test_aa_tower()
	_test_aa_ignores_nukes()
	_test_anti_nuke()
	_test_death_corpse_and_soul()
	_test_soul_costs_and_gating()
	_test_necro_raise()
	_test_raise_respects_caps()
	_test_ghoul_feed()
	_test_plague_cloud_and_infection()
	_test_melee_infection()
	_test_flesh_farm()
	_test_zombie_hunger_and_feral()
	_test_corpse_expiry()
	_test_undead_roster_stats()
	_test_save_roundtrip()
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


## Fresh game + combat + artillery + undead systems.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "undead"])
	var combat := SimCombat.new(gs)
	var arty := SimArtillery.new(gs, combat)
	var undead := SimUndead.new(gs, combat)
	return {"gs": gs, "combat": combat, "arty": arty, "undead": undead}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


## R20 stagger contract: undead.tick processes every 3rd call with delta*3,
## so one _ustep advances exactly the same sim time as one old tick(delta).
func _ustep(undead: SimUndead, total_delta: float) -> void:
	var third: float = total_delta / 3.0
	undead.tick(third)
	undead.tick(third)
	undead.tick(third)


func _spawn(w: Dictionary, faction: String, job: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


func _give(w: Dictionary, faction: String) -> void:
	var gs: GameState = w["gs"]
	gs.resources.add_resource(faction, "gold", 10000.0, true)
	gs.resources.add_resource(faction, "wood", 10000.0, true)


func _building(w: Dictionary, btype: String, faction: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({
		"type": btype, "faction": faction, "town_id": -1,
		"position": pos, "complete": true, "progress": 1.0,
		"hp": 900.0, "max_hp": 900.0,
	})


## --- vehicle stats (HTML verbatim) ------------------------------------------


func _test_vehicle_stats() -> void:
	var st: Dictionary = SimArtillery.VEHICLE_STATS
	_check("arty: grape range 900", float(st["grape_cannon"]["range"]) == 900.0)
	_check("arty: grape dmg 35", float(st["grape_cannon"]["dmg"]) == 35.0)
	_check("arty: grape cooldown 1.8", float(st["grape_cannon"]["cooldown"]) == 1.8)
	_check("arty: grape cost 60g/40w",
		st["grape_cannon"]["cost"] == {"gold": 60.0, "wood": 40.0})
	_check("arty: field range 1800", float(st["field_cannon"]["range"]) == 1800.0)
	_check("arty: field dmg 45", float(st["field_cannon"]["dmg"]) == 45.0)
	_check("arty: field cooldown 2.5", float(st["field_cannon"]["cooldown"]) == 2.5)
	_check("arty: field cost 70g/45w",
		st["field_cannon"]["cost"] == {"gold": 70.0, "wood": 45.0})
	_check("arty: siege range 12000", float(st["siege_rocket"]["range"]) == 12000.0)
	_check("arty: siege salvo 18-22",
		int(st["siege_rocket"]["salvo_min"]) == 18
		and int(st["siege_rocket"]["salvo_max"]) == 22)
	_check("arty: siege cost 90g/55w",
		st["siege_rocket"]["cost"] == {"gold": 90.0, "wood": 55.0})
	_check("arty: jumbo range 14000", float(st["jumbo_rocket"]["range"]) == 14000.0)
	_check("arty: jumbo warhead 280/320",
		float(st["jumbo_rocket"]["warhead_dmg"]) == 280.0
		and float(st["jumbo_rocket"]["warhead_splash"]) == 320.0)
	_check("arty: jumbo cooldown 60", float(st["jumbo_rocket"]["cooldown"]) == 60.0)
	_check("arty: jumbo cost 160g/100w",
		st["jumbo_rocket"]["cost"] == {"gold": 160.0, "wood": 100.0})
	_check("arty: heavy range 5000", float(st["heavy_artillery"]["range"]) == 5000.0)
	_check("arty: heavy dmg 70", float(st["heavy_artillery"]["dmg"]) == 70.0)
	_check("arty: heavy cost 100g/70w",
		st["heavy_artillery"]["cost"] == {"gold": 100.0, "wood": 70.0})
	_check("arty: vehicle hp 220",
		float(st["field_cannon"]["hp"]) == 220.0)
	_check("arty: five vehicle types", SimArtillery.VEHICLE_TYPES.size() == 5)


## --- training ----------------------------------------------------------------


func _test_vehicle_training() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var arty: SimArtillery = w["arty"]
	_give(w, "humans")
	_check("train: can afford grape",
		arty.can_train_vehicle("humans", "grape_cannon"))
	var g0: float = gs.resources.get_amount("humans", "gold")
	_check("train: queued", arty.train_vehicle("humans", "grape_cannon", -1,
		Vector2(500, 500)))
	_check("train: 60 gold deducted",
		gs.resources.get_amount("humans", "gold") == g0 - 60.0)
	# Train time 2.8 s — tick it out.
	for i: int in range(30):
		arty.tick(0.1)
	var vs: Array = arty.vehicles_of("humans")
	_check("train: vehicle delivered", vs.size() == 1)
	_check("train: parked on delivery", bool(vs[0].get("parked", false)))
	_check("train: hp 220", float(vs[0].get("hp", 0.0)) == 220.0)
	_check("train: type grape", String(vs[0].get("type", "")) == "grape_cannon")
	# Unaffordable: broke faction cannot train.
	_check("train: broke blocked",
		not arty.train_vehicle("undead", "jumbo_rocket", -1, Vector2(0, 0)))
	_check("train: block reason", arty.last_block_reason == "cant_afford")
	_free_world(w)


func _test_vehicle_pool_cap() -> void:
	var w: Dictionary = _new_world()
	var arty: SimArtillery = w["arty"]
	_give(w, "humans")
	for i: int in range(24):
		arty._create_vehicle("humans", "grape_cannon", -1, Vector2(100 + i, 100))
	_check("pool: 24 parked", arty.vehicles_of("humans").size() == 24)
	_check("pool: 25th blocked",
		not arty.train_vehicle("humans", "grape_cannon", -1, Vector2(0, 0)))
	_check("pool: block reason pool_full", arty.last_block_reason == "pool_full")
	_free_world(w)


## --- crew ---------------------------------------------------------------------


func _test_crew_mount_dismount() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var arty: SimArtillery = w["arty"]
	var v: Dictionary = arty._create_vehicle("humans", "field_cannon", -1,
		Vector2(500, 500))
	var c1: Dictionary = _spawn(w, "humans", "worker", Vector2(490, 500))
	var c2: Dictionary = _spawn(w, "humans", "worker", Vector2(510, 500))
	var c3: Dictionary = _spawn(w, "humans", "worker", Vector2(520, 500))
	_check("crew: mount 1", arty.mount_crew(c1, v))
	_check("crew: mount 2", arty.mount_crew(c2, v))
	_check("crew: 3rd refused (max 2)", not arty.mount_crew(c3, v))
	_check("crew: unparked on mount", not bool(v.get("parked", true)))
	_check("crew: job artillery_crew", String(c1.get("job", "")) == "artillery_crew")
	_check("crew: dmg >= 14", float(c1.get("dmg", 0.0)) >= 14.0)
	_check("crew: range = piece range",
		float(c1.get("crew_range", 0.0)) == 1800.0)
	_check("crew: driver set", int(v.get("driver_id", -1)) == int(c1.get("id", 0)))
	arty.dismount_crew(c1)
	arty.dismount_crew(c2)
	_check("crew: empty vehicle re-parks", bool(v.get("parked", false)))
	_check("crew: flags cleared", not bool(c1.get("artillery", true)))
	_free_world(w)


func _test_crew_auto_assign() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var arty: SimArtillery = w["arty"]
	var v: Dictionary = arty._create_vehicle("humans", "grape_cannon", -1,
		Vector2(500, 500))
	# No free units: ensure_crew spawns dedicated 80-hp gunners via Spawner.
	arty.ensure_crew(v)
	_check("crew: auto-filled to 2", (v.get("crew", []) as Array).size() == 2)
	for uid in v.get("crew", []):
		var u: Dictionary = gs.get_unit(int(uid))
		_check("crew: gunner hp 80", float(u.get("hp", 0.0)) == 80.0)
		_check("crew: gunner counts as unit",
			String(u.get("faction", "")) == "humans"
			and u.get("alive", false))
	_free_world(w)


## --- firing ---------------------------------------------------------------------


func _test_vehicle_fire() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var arty: SimArtillery = w["arty"]
	var v: Dictionary = arty._create_vehicle("humans", "field_cannon", -1,
		Vector2(0, 0))
	v["position"] = Vector2(0, 0)  # _create_vehicle parks at the motor pool
	var gunner: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	arty.mount_crew(gunner, v)
	var foe: Dictionary = _spawn(w, "undead", "skeleton", Vector2(500, 0))
	arty.tick(0.5)
	_check("fire: cannonball fired", combat.projectiles.size() > 0)
	var p: Dictionary = combat.projectiles[0]
	_check("fire: kind cannonball", String(p.get("kind", "")) == "cannonball")
	_check("fire: dmg 45", float(p.get("dmg", 0.0)) == 45.0)
	_check("fire: splash 110", float(p.get("splash", 0.0)) == 110.0)
	_check("fire: cooldown 2.5 set",
		float(v.get("cool", 0.0)) > 0.0 and float(v.get("cool", 0.0)) <= 2.5)
	# Grape: anti-infantry wide splash.
	var w2: Dictionary = _new_world()
	var combat2: SimCombat = w2["combat"]
	var arty2: SimArtillery = w2["arty"]
	var g: Dictionary = arty2._create_vehicle("humans", "grape_cannon", -1,
		Vector2(0, 0))
	g["position"] = Vector2(0, 0)
	var g2: Dictionary = _spawn(w2, "humans", "worker", Vector2(10, 0))
	arty2.mount_crew(g2, g)
	_spawn(w2, "undead", "zombie", Vector2(300, 0))
	arty2.tick(0.5)
	_check("fire: grape fired", combat2.projectiles.size() > 0)
	var gp: Dictionary = combat2.projectiles[0]
	_check("fire: kind grape", String(gp.get("kind", "")) == "grape")
	_check("fire: grape splash 90", float(gp.get("splash", 0.0)) == 90.0)
	_free_world(w)
	_free_world(w2)


func _test_rocket_salvo() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var arty: SimArtillery = w["arty"]
	var v: Dictionary = arty._create_vehicle("humans", "siege_rocket", -1,
		Vector2(0, 0))
	v["position"] = Vector2(0, 0)
	var gunner: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	arty.mount_crew(gunner, v)
	_building(w, "town_hall", "undead", Vector2(8000, 0))
	var launched: Array = []
	gs.bus.projectile_fired.connect(func(p: Dictionary) -> void:
		if String(p.get("kind", "")) == "rocket":
			launched.append(1))
	arty.tick(0.5)
	_check("salvo: started", not (v.get("salvo", {}) as Dictionary).is_empty())
	# Drip-fire the whole salvo (~3 s) then the 60 s reload.
	for i: int in range(60):
		arty.tick(0.1)
		combat.tick(0.1)
	_check("salvo: 18-22 rockets launched",
		launched.size() >= 18 and launched.size() <= 22)
	_check("salvo: 60 s reload after", float(v.get("cool", 0.0)) > 30.0)
	_free_world(w)


func _test_jumbo_warhead() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var arty: SimArtillery = w["arty"]
	var v: Dictionary = arty._create_vehicle("humans", "jumbo_rocket", -1,
		Vector2(0, 0))
	v["position"] = Vector2(0, 0)
	var gunner: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	arty.mount_crew(gunner, v)
	_building(w, "town_hall", "undead", Vector2(9000, 0))
	arty.tick(0.5)
	_check("jumbo: warhead fired", combat.projectiles.size() == 1)
	var p: Dictionary = combat.projectiles[0]
	_check("jumbo: kind jumbo_rocket", String(p.get("kind", "")) == "jumbo_rocket")
	_check("jumbo: dmg 280", float(p.get("dmg", 0.0)) == 280.0)
	_check("jumbo: splash 320", float(p.get("splash", 0.0)) == 320.0)
	_check("jumbo: 60 s cooldown", float(v.get("cool", 0.0)) > 30.0)
	_free_world(w)


func _test_vehicle_cookoff() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var arty: SimArtillery = w["arty"]
	var v: Dictionary = arty._create_vehicle("humans", "field_cannon", -1,
		Vector2(0, 0))
	v["position"] = Vector2(0, 0)
	var gunner: Dictionary = _spawn(w, "humans", "worker", Vector2(0, 0))
	arty.mount_crew(gunner, v)
	var bystander: Dictionary = _spawn(w, "undead", "skeleton", Vector2(50, 0))
	var vid: int = int(v.get("id", 0))
	_check("cookoff: destroyed at 0 hp",
		arty.damage_vehicle(vid, 220.0, "undead"))
	_check("cookoff: vehicle dead", not bool(v.get("alive", true)))
	_check("cookoff: crew died with the piece",
		not bool(gs.get_unit(int(gunner.get("id", 0))).get("alive", true)))
	_check("cookoff: bystander hurt",
		float(gs.get_unit(int(bystander.get("id", 0))).get("hp", 9999.0)) < 220.0)
	_free_world(w)


## --- air defense ---------------------------------------------------------------


func _test_aa_tower() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var arty: SimArtillery = w["arty"]
	_building(w, "aa_tower", "humans", Vector2(500, 0))
	# Hostile rocket flying at the human base.
	combat.fire_projectile(Vector2(1500, 0), -1, Vector2(0, 0),
		"rocket", 70.0, 100.0, "undead", 300.0)
	arty.tick(0.2)
	_check("aa: interceptor launched", arty.interceptors.size() == 1)
	# Let the 2200 px/s interceptor catch the 300 px/s rocket.
	for i: int in range(40):
		arty.tick(0.1)
		combat.tick(0.1)
		if arty.interceptors.is_empty():
			break
	var missile_alive: bool = false
	for p: Dictionary in combat.projectiles:
		if String(p.get("kind", "")) == "rocket" and p.get("alive", false):
			missile_alive = true
	_check("aa: missile intercepted", not missile_alive)
	_check("aa: interceptor spent", arty.interceptors.is_empty())
	_free_world(w)


func _test_aa_ignores_nukes() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var arty: SimArtillery = w["arty"]
	_building(w, "aa_tower", "humans", Vector2(500, 0))
	combat.fire_projectile(Vector2(1500, 0), -1, Vector2(0, 0),
		"nuke", 500.0, 400.0, "undead", 300.0)
	arty.tick(0.5)
	_check("aa: nukes need anti_nuke (no launch)",
		arty.interceptors.is_empty())
	_free_world(w)


func _test_anti_nuke() -> void:
	var w: Dictionary = _new_world()
	var combat: SimCombat = w["combat"]
	var arty: SimArtillery = w["arty"]
	_building(w, "anti_nuke", "humans", Vector2(500, 0))
	combat.fire_projectile(Vector2(1500, 0), -1, Vector2(0, 0),
		"nuke", 500.0, 400.0, "undead", 300.0)
	arty.tick(0.2)
	_check("antinuke: interceptor launched", arty.interceptors.size() == 1)
	for i: int in range(40):
		arty.tick(0.1)
		combat.tick(0.1)
		if arty.interceptors.is_empty():
			break
	var nuke_alive: bool = false
	for p: Dictionary in combat.projectiles:
		if String(p.get("kind", "")) == "nuke" and p.get("alive", false):
			nuke_alive = true
	_check("antinuke: nuke intercepted", not nuke_alive)
	_free_world(w)


## --- undead death economy -------------------------------------------------------


func _kill(w: Dictionary, unit: Dictionary, by: String) -> void:
	var combat: SimCombat = w["combat"]
	combat.damage_unit(int(unit.get("id", 0)), 99999.0, by)


func _test_death_corpse_and_soul() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var undead: SimUndead = w["undead"]
	var human: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	_kill(w, human, "undead")
	_check("death: corpse left", undead.corpses.size() == 1)
	_check("death: corpse t 50",
		float(undead.corpses[0].get("t", 0.0)) == 50.0)
	_check("death: corpse remembers job",
		String(undead.corpses[0].get("job", "")) == "worker")
	# Undead death recycles 3 soul.
	var zom: Dictionary = _spawn(w, "undead", "zombie", Vector2(200, 200))
	_kill(w, zom, "humans")
	_check("soul: undead death +3", undead.get_soul("undead") == 3.0)
	# Living death within 500 px of a living undead unit: +2.
	var watcher: Dictionary = _spawn(w, "undead", "skeleton", Vector2(300, 300))
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(350, 300))
	_kill(w, victim, "undead")
	_check("soul: nearby living death +2", undead.get_soul("undead") == 5.0)
	# Far death: no soul.
	var far: Dictionary = _spawn(w, "humans", "worker", Vector2(5000, 5000))
	_kill(w, far, "undead")
	_check("soul: far death none", undead.get_soul("undead") == 5.0)
	_free_world(w)


func _test_soul_costs_and_gating() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	_check("soul: wraith 15", undead.soul_cost("wraith") == 15.0)
	_check("soul: necromancer 25", undead.soul_cost("necromancer") == 25.0)
	_check("soul: plaguebearer 10", undead.soul_cost("plaguebearer") == 10.0)
	_check("soul: bone_golem 40", undead.soul_cost("bone_golem") == 40.0)
	_check("soul: lich 60", undead.soul_cost("lich") == 60.0)
	_check("soul: chaff free", undead.soul_cost("skeleton") == 0.0)
	undead.add_soul("undead", 20.0)
	_check("soul: gate blocks wraith at 20... wraith costs 15, allowed",
		undead.train_elite("undead", "wraith"))
	_check("soul: 5 left after wraith", undead.get_soul("undead") == 5.0)
	_check("soul: necromancer blocked at 5",
		not undead.train_elite("undead", "necromancer"))
	_check("soul: nothing spent on block", undead.get_soul("undead") == 5.0)
	_free_world(w)


func _test_necro_raise() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var undead: SimUndead = w["undead"]
	undead.add_soul("undead", 20.0)
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	_kill(w, victim, "undead")
	var necro: Dictionary = _spawn(w, "undead", "necromancer", Vector2(120, 100))
	undead.apply_undead_stats(necro)
	var corpses0: int = undead.corpses.size()
	_check("raise: corpse available", corpses0 == 1)
	_check("raise: succeeds", undead.try_necro_raise(necro))
	_check("raise: corpse consumed", undead.corpses.size() == corpses0 - 1)
	_check("raise: 10 soul spent", undead.get_soul("undead") == 10.0)
	_check("raise: 6 s cooldown", float(necro.get("raise_cd", 0.0)) == 6.0)
	var raised: Dictionary = {}
	for u: Dictionary in gs.units:
		if bool(u.get("raised", false)):
			raised = u
	_check("raise: unit raised", not raised.is_empty())
	_check("raise: skeleton or zombie",
		String(raised.get("job", "")) in ["skeleton", "zombie"])
	_check("raise: undead faction", String(raised.get("faction", "")) == "undead")
	# Broke necromancer cannot raise.
	undead.add_soul("undead", -10.0)
	var victim2: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	_kill(w, victim2, "undead")
	necro["raise_cd"] = 0.0
	_check("raise: blocked without soul", not undead.try_necro_raise(necro))
	_free_world(w)


func _test_raise_respects_caps() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	undead.add_soul("undead", 1000.0)
	# Fill the undead faction to its 48 cap.
	for i: int in range(48):
		_spawn(w, "undead", "skeleton", Vector2(1000 + i * 10, 1000))
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	_kill(w, victim, "undead")
	var necro: Dictionary = _spawn(w, "humans", "worker", Vector2(120, 100))
	necro["faction"] = "undead"
	necro["job"] = "necromancer"
	_check("raise: blocked at faction cap", not undead.try_necro_raise(necro))
	_check("raise: soul untouched", undead.get_soul("undead") == 1000.0)
	_free_world(w)


func _test_ghoul_feed() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	_kill(w, victim, "undead")
	var ghoul: Dictionary = _spawn(w, "undead", "ghoul", Vector2(110, 100))
	undead.apply_undead_stats(ghoul)
	ghoul["hp"] = float(ghoul["max_hp"]) - 50.0
	var hp0: float = float(ghoul["hp"])
	_ustep(undead, 0.1)
	_check("ghoul: corpse eaten", undead.corpses.is_empty())
	_check("ghoul: healed +35", float(ghoul["hp"]) == hp0 + 35.0)
	_free_world(w)


func _test_plague_cloud_and_infection() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var pb: Dictionary = _spawn(w, "undead", "plaguebearer", Vector2(200, 200))
	_kill(w, pb, "humans")
	_check("plague: cloud on death", undead.plague_clouds.size() == 1)
	_check("plague: cloud lasts 8 s",
		float(undead.plague_clouds[0].get("t", 0.0)) == 8.0)
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(210, 200))
	# Infect quickly: tick until infected (chance 1.2/s).
	var infected: bool = false
	for i: int in range(100):
		_ustep(undead, 0.1)
		if victim.has("infected"):
			infected = true
			break
	_check("plague: victim infected", infected)
	# 25 s incubation -> turns into a zombie.
	for i: int in range(260):
		_ustep(undead, 0.1)
	_check("plague: victim turned", String(victim.get("faction", "")) == "undead")
	_check("plague: turned as zombie", String(victim.get("job", "")) == "zombie")
	_check("plague: turned_from remembered",
		String(victim.get("turned_from", "")) == "humans")
	# Cloud dissipates.
	for i: int in range(100):
		_ustep(undead, 0.1)
	_check("plague: cloud gone", undead.plague_clouds.is_empty())
	_free_world(w)


func _test_melee_infection() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var zom: Dictionary = _spawn(w, "undead", "zombie", Vector2(0, 0))
	var target: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	var hit: bool = false
	for i: int in range(60):
		if undead.maybe_infect_on_hit(zom, target):
			hit = true
			break
	_check("melee: zombie hit infects (35%)", hit)
	var skel: Dictionary = _spawn(w, "undead", "skeleton", Vector2(0, 0))
	var target2: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	var skel_hit: bool = false
	for i: int in range(20):
		if undead.maybe_infect_on_hit(skel, target2):
			skel_hit = true
			break
	_check("melee: skeletons do not infect", not skel_hit)
	_free_world(w)


func _test_flesh_farm() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var farm: Dictionary = _building(w, "flesh_farm", "undead", Vector2(0, 0))
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(500, 0))
	_kill(w, victim, "undead")
	_ustep(undead, 0.1)
	_check("flesh: corpse hauled", undead.corpses.is_empty())
	_check("flesh: meat +1", int(farm.get("meat", 0)) == 1)
	# Stock caps at 12.
	farm["meat"] = 12
	var victim2: Dictionary = _spawn(w, "humans", "worker", Vector2(500, 0))
	_kill(w, victim2, "undead")
	_ustep(undead, 0.1)
	_check("flesh: meat capped at 12", int(farm.get("meat", 0)) == 12)
	_check("flesh: corpse left when full", undead.corpses.size() == 1)
	# Hungry zombie eats meat.
	var zom: Dictionary = _spawn(w, "undead", "zombie", Vector2(10, 0))
	undead.apply_undead_stats(zom)
	zom["zhunger"] = 10.0
	_ustep(undead, 0.5)
	_check("flesh: zombie ate meat", int(farm.get("meat", 0)) == 11)
	_check("flesh: zhunger restored",
		float(zom.get("zhunger", 0.0)) > 55.0)
	_free_world(w)


func _test_zombie_hunger_and_feral() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var zom: Dictionary = _spawn(w, "undead", "zombie", Vector2(0, 0))
	undead.apply_undead_stats(zom)
	zom["zhunger"] = 50.0
	_ustep(undead, 60.0)
	_check("hunger: drains over time",
		float(zom.get("zhunger", 60.0)) < 50.0)
	# Starving zombie weakens.
	zom["zhunger"] = 10.0
	var dmg0: float = float(zom.get("dmg", 0.0))
	_ustep(undead, 0.1)
	_check("hunger: starving weakens dmg",
		float(zom.get("dmg", 0.0)) < dmg0)
	# Critical hunger -> feral.
	zom["zhunger"] = 5.0
	# Pin RNG: the feral transition is _roll()-gated per processed tick in
	# undead.gd (exact 3-frame compounding of the old randf() < delta*0.25),
	# so an unseeded suite flakes ~1 in 150 runs.
	seed(20261003)
	var feral: bool = false
	for i: int in range(200):
		_ustep(undead, 0.1)
		if bool(zom.get("feral", false)):
			feral = true
			break
	_check("hunger: critical hunger goes feral", feral)
	_free_world(w)


func _test_corpse_expiry() -> void:
	var w: Dictionary = _new_world()
	var undead: SimUndead = w["undead"]
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 100))
	_kill(w, victim, "undead")
	_check("corpse: created", undead.corpses.size() == 1)
	_ustep(undead, 51.0)
	_check("corpse: expires after 50 s", undead.corpses.is_empty())
	_free_world(w)


func _test_undead_roster_stats() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var undead: SimUndead = w["undead"]
	var r: Dictionary = SimUndead.UNDEAD_ROSTER
	# HTML job-branch multipliers.
	_check("roster: zombie hp x2.0", float(r["zombie"]["hp_mul"]) == 2.0)
	_check("roster: ghoul speed 1.45x base",
		float(r["ghoul"]["speed"]) == 138.0)  # 95 * 1.45 = 137.75 ~ 138
	_check("roster: wraith life drain", float(r["wraith"]["life_drain"]) == 0.5)
	_check("roster: necromancer range 240", float(r["necromancer"]["range"]) == 240.0)
	_check("roster: lich range 260", float(r["lich"]["range"]) == 260.0)
	_check("roster: bone_golem siege", bool(r["bone_golem"]["siege"]))
	# apply_undead_stats on a spawned unit (undead race hp 220).
	var zom: Dictionary = _spawn(w, "undead", "zombie", Vector2(0, 0))
	undead.apply_undead_stats(zom)
	_check("stats: zombie hp 440", float(zom.get("hp", 0.0)) == 440.0)
	_check("stats: zombie dmg 16", float(zom.get("dmg", 0.0)) == 16.0)  # 15*1.1=16.5 floor
	var skel: Dictionary = _spawn(w, "undead", "skeleton", Vector2(0, 0))
	undead.apply_undead_stats(skel)
	_check("stats: skeleton hp 198", float(skel.get("hp", 0.0)) == 198.0)
	var necro: Dictionary = _spawn(w, "undead", "necromancer", Vector2(0, 0))
	undead.apply_undead_stats(necro)
	_check("stats: necromancer range 240", float(necro.get("range", 0.0)) == 240.0)
	_free_world(w)


func _test_save_roundtrip() -> void:
	var w: Dictionary = _new_world()
	var arty: SimArtillery = w["arty"]
	var undead: SimUndead = w["undead"]
	_give(w, "humans")
	arty._create_vehicle("humans", "field_cannon", -1, Vector2(100, 100))
	var victim: Dictionary = _spawn(w, "humans", "worker", Vector2(200, 200))
	_kill(w, victim, "undead")
	undead.add_soul("undead", 7.0)
	var ad: Dictionary = arty.to_dict()
	var ud: Dictionary = undead.to_dict()
	_check("save: vehicle serialized", (ad["vehicles"] as Array).size() == 1)
	_check("save: corpse serialized", (ud["corpses"] as Array).size() == 1)
	_check("save: soul serialized",
		float((ud["soul"] as Dictionary).get("undead", 0.0)) == 7.0)
	var w2: Dictionary = _new_world()
	var arty2: SimArtillery = w2["arty"]
	var undead2: SimUndead = w2["undead"]
	arty2.from_dict(ad)
	undead2.from_dict(ud)
	_check("save: vehicle restored", arty2.vehicles.size() == 1)
	_check("save: vehicle type kept",
		String(arty2.vehicles[0].get("type", "")) == "field_cannon")
	_check("save: corpse restored", undead2.corpses.size() == 1)
	_check("save: soul restored", undead2.get_soul("undead") == 7.0)
	_free_world(w)
	_free_world(w2)
