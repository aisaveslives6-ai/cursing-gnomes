extends SceneTree
## Cursing Gnomes — hydro/flood disaster tests (HTML STAGE3 hydrology port).
##
## Covers: water body construction, rain-driven level rise, warning-before-
## flood sequencing, building damage + destruction + Gazette, NPC flight to
## high ground (sim flag + mind movement), crop washout, recede + mud,
## mud growth penalty, save/load round trip, draw info, no-map safety.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hydro.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []
var _spawned: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes hydro/flood tests ===")
	_test_bodies_build()
	_test_rain_raises_levels()
	_test_warning_before_flood()
	_test_building_damage()
	_test_building_destroyed_gazette()
	_test_npc_flight()
	_test_mind_flood_flee()
	_test_crop_washout()
	_test_recede_and_mud()
	_test_mud_growth_penalty()
	_test_save_load()
	_test_draw_info()
	_test_no_map_safe()
	_test_force_flood()
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


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.map_data = {
		"water_bodies": [
			{"kind": "lake", "pos": Vector2(500, 500), "radius": 100.0},
			{"kind": "river",
				"points": PackedVector2Array(
					[Vector2(100, 900), Vector2(400, 900),
						Vector2(700, 900)]),
				"width": 55.0},
		],
		"tile_size": 32.0,
	}
	return gs


func _new_hydro(gs: GameState) -> HydroSim:
	var combat := SimCombat.new(gs)
	var h := HydroSim.new(gs, combat)
	h.setup_bounds(Rect2(0, 0, 2000, 2000))
	_stories.clear()
	_spawned.clear()
	gs.bus.gazette_story.connect(_on_story)
	gs.bus.disaster_spawned.connect(_on_spawned)
	return h


func _on_story(s: Dictionary) -> void:
	_stories.append(s)


func _on_spawned(kind: String, pos: Vector2) -> void:
	_spawned.append([kind, pos])


func _add_building(gs: GameState, pos: Vector2, hp: float = 400.0) -> Dictionary:
	return gs.add_building({
		"faction": "humans", "type": "house", "town_id": -1,
		"position": pos, "alive": true, "hp": hp, "max_hp": hp,
		"complete": true,
	})


func _add_unit(gs: GameState, pos: Vector2) -> Dictionary:
	return gs.add_unit({
		"faction": "humans", "job": "worker", "town_id": -1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
	})


## ---- water bodies -------------------------------------------------------

func _test_bodies_build() -> void:
	var gs := _new_game()
	var h := _new_hydro(gs)
	var bs := h.bodies()
	_check("two bodies built", bs.size() == 2)
	_check("lake defaults", is_equal_approx(float(bs[0].get("level", 0.0)),
		0.5) and not bool(bs[0].get("flooding", true)))
	_check("river defaults", String(bs[1].get("kind", "")) == "river"
		and is_equal_approx(float(bs[1].get("level", 0.0)), 0.5))


## ---- rain drives levels ---------------------------------------------------

func _test_rain_raises_levels() -> void:
	var gs := _new_game()
	gs.seasons = SimSeasons.new(gs)
	gs.seasons.weather = "storm"
	var h := _new_hydro(gs)
	var before := HydroSim.level_of(h.bodies()[0])
	# 30 s of storm: wet_acc climbs, level follows.
	for i in 60:
		h.tick(0.5)
	var after := HydroSim.level_of(h.bodies()[0])
	_check("storm raises lake level", after > before)
	# Rivers react faster than lakes (HTML: rivers fill fast).
	var rlvl := HydroSim.level_of(h.bodies()[1])
	_check("river fills at least as fast", rlvl >= after - 0.05)


## ---- warning always fires before flood -------------------------------------

func _test_warning_before_flood() -> void:
	var gs := _new_game()
	var h := _new_hydro(gs)
	var b: Dictionary = h.bodies()[0]
	# Jump straight past both thresholds in one step — the warning gate
	# must still fire first (structural, HTML parity).
	b["level"] = 1.20
	h._flood_step(b, 0.01)
	_check("warning fired", bool(b.get("warned", false)))
	_check("not yet flooding", not bool(b.get("flooding", false)))
	_check("warning gazette", _stories.size() == 1
		and String(_stories[0].get("headline", "")) == "FLOOD WARNING")
	h._flood_step(b, 0.01)
	_check("flooding after warning step", bool(b.get("flooding", false)))
	_check("flood gazette", _stories.size() == 2
		and String(_stories[1].get("headline", "")) == "FLOOD!")


## ---- building damage ---------------------------------------------------------

func _test_building_damage() -> void:
	var gs := _new_game()
	var h := _new_hydro(gs)
	var b: Dictionary = h.bodies()[0]
	# House 60 px from lake center: inside the flood zone at full flood
	# (lake eff r at 1.2 = 100*1.35 = 135 + spill 480+).
	var bd := _add_building(gs, Vector2(700, 500), 400.0)
	h.force_flood(0)
	_check("force flood floods", bool(b.get("flooding", false)))
	# 2 game-hours of flooding: 26+60*0.2 = 38/hp per hour -> ~76 dmg.
	h._flood_damage(b, 2.0)
	_check("building marked flooded", bool(bd.get("flooded", false)))
	_check("building took damage",
		float(bd.get("hp", 400.0)) < 400.0
		and float(bd.get("hp", 0.0)) > 200.0)
	# A far-away house is untouched.
	var far := _add_building(gs, Vector2(1500, 1500), 400.0)
	h._flood_damage(b, 2.0)
	_check("distant building safe",
		is_equal_approx(float(far.get("hp", 0.0)), 400.0)
		and not bool(far.get("flooded", false)))


func _test_building_destroyed_gazette() -> void:
	var gs := _new_game()
	var h := _new_hydro(gs)
	var b: Dictionary = h.bodies()[0]
	var bd := _add_building(gs, Vector2(700, 500), 10.0)
	_stories.clear()
	h.force_flood(0)
	h._flood_damage(b, 5.0)  # overwhelming damage
	_check("weak building destroyed", not gs.buildings.has(bd))
	var headlines: Array = []
	for s in _stories:
		headlines.append(String(s.get("headline", "")))
	_check("claims gazette published",
		headlines.has("FLOOD CLAIMS A BUILDING"))


## ---- NPC flight --------------------------------------------------------------

func _test_npc_flight() -> void:
	var gs := _new_game()
	var h := _new_hydro(gs)
	var b: Dictionary = h.bodies()[0]
	var u := _add_unit(gs, Vector2(700, 500))  # inside flood zone
	var calm := _add_unit(gs, Vector2(1500, 1500))  # dry
	h.force_flood(0)
	h._flood_damage(b, 0.5)
	_check("unit flagged flood_flee", bool(u.get("flood_flee", false)))
	_check("unit got dry target",
		(u.get("flood_target", Vector2(-1, -1)) as Vector2).x >= 0.0)
	_check("dry unit not flagged", not bool(calm.get("flood_flee", false)))
	# Combat-engaged units hold position (HTML parity).
	var fighter := _add_unit(gs, Vector2(700, 520))
	fighter["combat_target"] = 7
	h._flood_damage(b, 0.5)
	_check("fighter holds position", not bool(fighter.get("flood_flee",
		false)))


func _test_mind_flood_flee() -> void:
	var gs := _new_game()
	var h := _new_hydro(gs)
	gs.hydro = h
	var mind := SimMind.new(gs)
	h.setup_bounds(Rect2(0, 0, 2000, 2000))
	var b: Dictionary = h.bodies()[0]
	var u := _add_unit(gs, Vector2(700, 500))
	mind.ensure(u)
	h.force_flood(0)
	h._flood_damage(b, 0.5)
	_check("mind sees flood flag", bool(u.get("flood_flee", false)))
	var start := (u.get("position", Vector2.ZERO) as Vector2)
	var busy := mind.tick_unit(u, 1.0)
	_check("mind reports busy while fleeing", busy)
	var moved := (u.get("position", Vector2.ZERO) as Vector2) \
		.distance_to(start)
	_check("unit moved toward dry ground", moved > 0.5)
	# Teleport to dry land: the flag clears and normal AI resumes.
	u["position"] = Vector2(1500, 1500)
	_check("flag clears when dry", not mind.tick_unit(u, 1.0)
		and not bool(u.get("flood_flee", false)))


## ---- crops ---------------------------------------------------------------------

func _test_crop_washout() -> void:
	var gs := _new_game()
	gs.farming = SimFarming.new(gs)
	var h := _new_hydro(gs)
	var b: Dictionary = h.bodies()[0]
	var plot: Dictionary = gs.farming.create_plot("humans", Vector2(700, 500), -1, true)
	plot["tiles"][0]["crop"] = {"g": 0.8, "watered": true, "waterT": 5.0}
	h.force_flood(0)
	h._flood_damage(b, 0.5)
	_check("plot marked flooded", bool(plot.get("flooded", false)))
	_check("crop washed out",
		is_equal_approx(float(plot["tiles"][0]["crop"].get("g", 1.0)), 0.0))


## ---- recede + mud ---------------------------------------------------------------

func _test_recede_and_mud() -> void:
	var gs := _new_game()
	var h := _new_hydro(gs)
	var b: Dictionary = h.bodies()[0]
	var bd := _add_building(gs, Vector2(700, 500), 400.0)
	h.force_flood(0)
	h._flood_damage(b, 0.5)
	_check("flooded flag set", bool(bd.get("flooded", false)))
	# Dry spell: level falls below the recede line.
	b["level"] = 0.5
	b["wet_acc"] = 0.0
	_stories.clear()
	h._flood_step(b, 0.01)
	_check("flood ended", not bool(b.get("flooding", false)))
	_check("flooded flag cleared", not bool(bd.get("flooded", false)))
	_check("mud stamped", h.mud_patches.size() == 1)
	var headlines: Array = []
	for s in _stories:
		headlines.append(String(s.get("headline", "")))
	_check("recede gazette", headlines.has("WATERS RECEDE"))


func _test_mud_growth_penalty() -> void:
	var gs := _new_game()
	gs.farming = SimFarming.new(gs)
	var plot: Dictionary = gs.farming.create_plot("humans", Vector2(700, 500), -1, true)
	plot["tiles"][0]["crop"] = {"g": 0.0, "watered": true, "waterT": 99.0}
	# No mud: baseline growth.
	gs.farming.tick(10.0)
	var clean_g := float(plot["tiles"][0]["crop"].get("g", 0.0))
	plot["tiles"][0]["crop"]["g"] = 0.0
	# Mud: halved growth.
	plot["mud_until"] = gs.game_time + 99999.0
	gs.farming.tick(10.0)
	var mud_g := float(plot["tiles"][0]["crop"].get("g", 0.0))
	_check("mud halves growth",
		mud_g > 0.0 and is_equal_approx(mud_g * 2.0, clean_g))


## ---- save / load ------------------------------------------------------------------

func _test_save_load() -> void:
	var gs := _new_game()
	var h := _new_hydro(gs)
	var b: Dictionary = h.bodies()[0]
	b["level"] = 1.1
	b["wet_acc"] = 0.7
	b["warned"] = true
	b["flooding"] = true
	h.mud_patches.append({"pos": Vector2(1, 2), "radius": 50.0,
		"until": 1234.0})
	var data := h.to_dict()
	var gs2 := _new_game()
	var h2 := _new_hydro(gs2)
	h2.from_dict(data)
	var b2: Dictionary = h2.bodies()[0]
	_check("level saved", is_equal_approx(float(b2.get("level", 0.0)), 1.1))
	_check("wet_acc saved", is_equal_approx(float(b2.get("wet_acc", 0.0)),
		0.7))
	_check("flags saved", bool(b2.get("warned", false))
		and bool(b2.get("flooding", false)))
	_check("mud saved", h2.mud_patches.size() == 1
		and is_equal_approx(
			float(h2.mud_patches[0].get("until", 0.0)), 1234.0))


## ---- draw info / safety / force -------------------------------------------------------

func _test_draw_info() -> void:
	var gs := _new_game()
	var h := _new_hydro(gs)
	_check("quiet when calm", h.flood_draw_info().is_empty())
	h.force_flood(0)
	var info := h.flood_draw_info()
	_check("draw info when flooding", info.size() == 1)
	_check("draw info fields",
		float(info[0].get("spill", 0.0)) > 100.0
		and bool(info[0].get("flooding", false)))


func _test_no_map_safe() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	# No map_data at all: tick must be a safe no-op (headless parity).
	var h := _new_hydro(gs)
	h.tick(1.0)
	h.tick(60.0)
	_check("no bodies without map", h.bodies().is_empty())
	_check("is_dry without bodies", h.is_dry(Vector2(100, 100)))


func _test_force_flood() -> void:
	var gs := _new_game()
	var h := _new_hydro(gs)
	_stories.clear()
	h.force_flood(1)  # the river
	var b: Dictionary = h.bodies()[1]
	_check("river forced to flood", bool(b.get("flooding", false))
		and HydroSim.level_of(b) >= HydroSim.HYDRO_FLOOD)
	_check("force emits flood event", _spawned.size() == 1
		and String(_spawned[0][0]) == "flood")
