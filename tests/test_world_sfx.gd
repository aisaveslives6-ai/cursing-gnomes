extends SceneTree
## Cursing Gnomes — world SFX wiring tests (Jeremy 2026-10-07 wake audio
## lane: "Sound the world" — the SFX engine had a full arsenal of
## synthesized sounds but several gameplay moments were silent).
##
## Covers: melee contact "hit" (projectile impacts already sound via the
## world layer, so ranged direct hits must NOT double-sound); melee
## throttle (8 per 0.1 s bucket); building destroyed -> "explode";
## construction complete -> "build"; monster arrival -> its signature sting
## (giant_ass -> "ass_arrive");
## bandit raid arrival -> "war_horn"; volcano eruption -> "explode";
## wildfire ignition -> "fire" (throttled 4 per 1 s bucket);
## war declaration -> "war_horn"; hall capture -> "war_horn".
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_world_sfx.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _sfx: Array = []  # [name, pos] records from bus.sfx_spatial


func _initialize() -> void:
	print("=== Cursing Gnomes world SFX tests ===")
	_test_melee_hit_sounds()
	_test_ranged_no_double_sound()
	_test_melee_throttle()
	_test_building_destroyed_sounds()
	_test_construction_complete_sounds()
	_test_monster_arrival_sounds()
	_test_bandit_raid_sounds()
	_test_volcano_eruption_sounds()
	_test_fire_ignition_sounds()
	_test_fire_ignition_throttle()
	_test_war_declaration_sounds()
	_test_hall_capture_sounds()
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


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	_sfx.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	return gs


func _on_sfx(sfx_name: String, pos: Vector2, _vel: Vector2) -> void:
	_sfx.append([sfx_name, pos])


func _add_unit(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_unit({
		"faction": faction, "job": "soldier", "town_id": -1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
	})


func _names() -> Array:
	var out: Array = []
	for r: Array in _sfx:
		out.append(r[0])
	return out


## --- melee -------------------------------------------------------------------


func _test_melee_hit_sounds() -> void:
	var gs := _new_game(["humans", "ogres"])
	var combat := SimCombat.new(gs)
	var a := _add_unit(gs, "ogres", Vector2(100, 100))
	var v := _add_unit(gs, "humans", Vector2(120, 100))
	combat.damage_unit(int(v["id"]), 5.0, "ogres", int(a["id"]), "")
	_check("melee: hit sounded", _names().has("hit"))
	var at: Vector2 = _sfx[_sfx.size() - 1][1]
	_check("melee: at victim pos",
		at.distance_to(Vector2(120, 100)) < 1.0)
	gs.free()


func _test_ranged_no_double_sound() -> void:
	# Projectile impacts sound via world._on_projectile_hit — a direct
	# ranged damage_unit call (kind != "") must not double-sound.
	var gs := _new_game(["humans", "ogres"])
	var combat := SimCombat.new(gs)
	var a := _add_unit(gs, "ogres", Vector2(100, 100))
	var v := _add_unit(gs, "humans", Vector2(300, 100))
	combat.damage_unit(int(v["id"]), 5.0, "ogres", int(a["id"]), "arrow")
	_check("ranged: no melee hit sound", not _names().has("hit"))
	gs.free()


func _test_melee_throttle() -> void:
	# A big battle lands dozens of melee hits per tick — cap the sounds
	# so the 16-voice spatial pool isn't exhausted.
	var gs := _new_game(["humans", "ogres"])
	var combat := SimCombat.new(gs)
	var a := _add_unit(gs, "ogres", Vector2(100, 100))
	var v := _add_unit(gs, "humans", Vector2(120, 100))
	for i in 20:
		combat.damage_unit(int(v["id"]), 1.0, "ogres", int(a["id"]), "")
		v["hp"] = 100.0  # keep the victim standing for all 20 hits
	var hits: int = 0
	for n: String in _names():
		if n == "hit":
			hits += 1
	_check("melee: throttled to 8 per bucket",
		hits == SimCombat.SFX_MELEE_PER_BUCKET)
	gs.free()


## --- buildings ---------------------------------------------------------------


func _test_building_destroyed_sounds() -> void:
	var gs := _new_game(["humans", "ogres"])
	var combat := SimCombat.new(gs)
	var b := gs.add_building({
		"type": "house", "faction": "humans",
		"position": Vector2(400, 400), "alive": true, "complete": true,
		"hp": 400.0, "max_hp": 400.0,
	})
	_check("destroyed: damage returns true",
		combat.damage_building(int(b["id"]), 99999.0, "ogres"))
	_check("destroyed: explode sounded", _names().has("explode"))
	gs.free()


func _test_construction_complete_sounds() -> void:
	var gs := _new_game(["humans"])
	var sb := SimBuildings.new(gs)
	var b := gs.add_building({
		"type": "house", "faction": "humans",
		"position": Vector2(500, 500), "alive": true, "complete": false,
		"progress": 0.99, "hp": 400.0, "max_hp": 400.0,
	})
	_check("construction: completes",
		sb.tick_construction(b, 100.0, 1.0))
	_check("construction: build sounded", _names().has("build"))
	gs.free()


## --- disasters ---------------------------------------------------------------


func _new_disasters(gs: GameState) -> DisasterSim:
	var combat := SimCombat.new(gs)
	return DisasterSim.new(gs, combat)


func _test_monster_arrival_sounds() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	d.spawn("giant_ass", Vector2(100, 100))
	# 2026-10-07: every named disaster gets its own signature sting — the
	# Giant Ass arrives on "ass_arrive", not the generic "boom".
	_check("monster: ass_arrive sounded", _names().has("ass_arrive"))
	gs.free()


func _test_bandit_raid_sounds() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	d.spawn("bandit_raid", Vector2(200, 200))
	_check("bandits: war horn sounded", _names().has("war_horn"))
	gs.free()


func _test_volcano_eruption_sounds() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	_check("volcano: erupts", d.erupt_volcano_at(Vector2(2048, 2048)))
	_check("volcano: explode sounded", _names().has("explode"))
	gs.free()


func _test_fire_ignition_sounds() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	d.ignite(Vector2(300, 300), 60.0)
	_check("fire: ignition sounded", _names().has("fire"))
	gs.free()


func _test_fire_ignition_throttle() -> void:
	# Volcano blasts + 2 Hz spread ticks can light many fires at once.
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	for i in 10:
		d.ignite(Vector2(300 + i * 200.0, 300), 60.0)
	var fires: int = 0
	for n: String in _names():
		if n == "fire":
			fires += 1
	_check("fire: throttled to 4 per bucket",
		fires == DisasterSim.SFX_FIRE_PER_BUCKET)
	gs.free()


## --- war ---------------------------------------------------------------------


func _test_war_declaration_sounds() -> void:
	var gs := _new_game(["humans", "ogres"])
	var dip: SimDiplomacy = gs.diplomacy
	_check("war: declared",
		bool(dip.declare_war("humans", "ogres", "testing").get("ok", false)))
	_check("war: horn sounded", _names().has("war_horn"))
	gs.free()


func _test_hall_capture_sounds() -> void:
	var gs := _new_game(["humans", "ogres"])
	var hall := {
		"id": 1, "type": "town_hall", "faction": "ogres",
		"position": Vector2(500, 500), "alive": true, "complete": true,
		"hp": 1200.0, "max_hp": 1200.0, "town_id": 101,
		"town_name": "Testville",
	}
	gs.buildings.append(hall)
	gs.building_by_id[1] = hall
	var combat := SimCombat.new(gs)
	combat.damage_building(1, 5000.0, "humans")
	_check("capture: hall flips",
		String(hall.get("faction", "")) == "humans")
	_check("capture: horn sounded", _names().has("war_horn"))
	gs.free()
