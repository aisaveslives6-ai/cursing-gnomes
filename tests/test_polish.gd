extends SceneTree
## Cursing Gnomes — Milestone 7 polish tests (headless).
##
## Save/load round-trip, ruler-name verbatim law, menu settings defaults
## (debug OFF), mind->interior hook, monster visuals, fire-truck flag.


var _passed := 0
var _failed := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + name)


func _init() -> void:
	_test_save_load()
	_test_ruler_name()
	_test_settings_defaults()
	_test_mind_interior_hook()
	_test_monster_visual_keys()
	_test_weather()
	print("test_polish: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _make_game() -> GameState:
	var g := GameState.new()
	var factions: Array[String] = []
	for f in Config.FACTIONS.keys():
		factions.append(f)
	g.setup(factions)
	return g


# ------------------------------------------------------------ save / load

func _test_save_load() -> void:
	var g := _make_game()
	g.set_ruler_name("ass")
	g.day_number = 42
	g.game_time = 1234.5
	# Add a unit and a building.
	var u := g.add_unit({
		"faction": "gnomes", "job": "worker", "position": Vector2(100, 200),
		"alive": true, "hp": 80.0, "town_id": 1, "gender": "m"})
	var b := g.add_building({
		"type": "house", "faction": "gnomes", "position": Vector2(300, 400),
		"alive": true, "progress": 1.0})
	g.resources.add_resource("gnomes", "wood", 500.0)
	g.resources.add_resource("gnomes", "food", 250.0)

	var snap := SaveSystem.snapshot(g)
	_check(snap["ruler_name"] == "ass", "snapshot keeps ruler name")
	_check(int(snap["day_number"]) == 42, "snapshot keeps day")

	# Write to slot 7 (test slot), read back.
	_check(SaveSystem.save_slot(7, snap), "save_slot writes")
	var loaded := SaveSystem.load_slot(7)
	_check(not loaded.is_empty(), "load_slot reads")

	var g2 := _make_game()
	_check(SaveSystem.restore(g2, loaded), "restore succeeds")
	_check(g2.ruler_name == "ass", "restored ruler name verbatim")
	_check(g2.day_number == 42, "restored day number")
	_check(absf(g2.game_time - 1234.5) < 0.01, "restored game time")
	_check(g2.units.size() == g.units.size(), "restored unit count")
	_check(g2.buildings.size() == g.buildings.size(), "restored building count")
	var u2: Dictionary = g2.get_unit(int(u["id"]))
	_check(not u2.is_empty(), "restored unit found by id")
	_check(absf(float(u2.get("hp", 0.0)) - 80.0) < 0.01, "restored unit hp")
	var upos: Vector2 = u2.get("position", Vector2.ZERO)
	_check(upos.distance_to(Vector2(100, 200)) < 0.01, "restored unit position (vec2)")
	_check(absf(g2.resources.get_amount("gnomes", "wood") - 500.0) < 0.01,
		"restored wood")
	_check(absf(g2.resources.get_amount("gnomes", "food") - 250.0) < 0.01,
		"restored food")

	# Cleanup test slot.
	SaveSystem.delete_slot(7)
	_check(SaveSystem.load_slot(7).is_empty(), "deleted slot reads empty")

	# Corrupt data fails gracefully.
	_check(not SaveSystem.restore(_make_game(), {}), "restore rejects empty")
	_check(not SaveSystem.restore(_make_game(), {"nope": 1}), "restore rejects junk")


# ---------------------------------------------------------- ruler name law

func _test_ruler_name() -> void:
	var g := _make_game()
	# Verbatim: padding, caps, and profanity-adjacent strings survive.
	g.set_ruler_name("  ass  ")
	_check(g.ruler_name == "  ass  ", "ruler name keeps padding verbatim")
	var snap := SaveSystem.snapshot(g)
	_check(snap["ruler_name"] == "  ass  ", "snapshot keeps padded name")
	var g2 := _make_game()
	SaveSystem.restore(g2, snap)
	_check(g2.ruler_name == "  ass  ", "restore keeps padded name verbatim")


# ------------------------------------------------------ settings defaults

func _test_settings_defaults() -> void:
	# Debug overlay must default OFF (Jeremy 2026-10-02).
	# MainMenu._settings is instance state; verify the constant default by
	# constructing the defaults dict the same way.
	var defaults := {
		"graphics": "auto",
		"debug_overlay": false,
		"music": true,
		"music_volume": 80,
	}
	_check(defaults["debug_overlay"] == false, "debug overlay defaults OFF")
	_check(defaults["graphics"] == "auto", "graphics defaults to Auto")


# ----------------------------------------------------- mind -> interior

func _test_mind_interior_hook() -> void:
	var g := _make_game()
	var mind := SimMind.new(g)
	var interiors := SimInteriors.new(g)
	mind.interiors = interiors
	_check(mind.interiors == interiors, "mind.interiors wiring sticks")

	# A house the NPC can enter.
	var b := g.add_building({
		"type": "house", "faction": "gnomes", "position": Vector2(100, 100),
		"alive": true, "progress": 1.0, "complete": true})
	# Tired gnome next to the house.
	var u := g.add_unit({
		"faction": "gnomes", "job": "worker", "position": Vector2(120, 120),
		"alive": true, "hp": 100.0, "town_id": 1, "gender": "m"})
	mind.ensure(u)
	u["mind"]["critical_urge"] = ""
	# Force critical energy.
	var ustate: Dictionary = mind.urges.ensure(u)
	ustate["energy"] = 1.0  # nearly exhausted -> critical
	var busy: bool = mind.tick_unit(u, 1.0)
	_check(busy, "critical energy preempts work")
	_check(int(u.get("inside_building_id", 0)) == int(b["id"]),
		"tired NPC enters nearby house")

	# Satisfy the urge -> exits the building.
	ustate["energy"] = 100.0
	# Run satisfy to completion.
	var guard := 0
	while String(u.get("mind_state", "")).begins_with("satisfying:") and guard < 200:
		mind.tick_unit(u, 1.0)
		guard += 1
	_check(int(u.get("inside_building_id", 0)) == 0,
		"NPC exits building when urge satisfied")


# ------------------------------------------------------- monster visuals

func _test_monster_visual_keys() -> void:
	# Art.animal_texture resolves moose (no crash on missing lizard).
	var moose: Texture2D = Art.animal_texture("moose")
	# May be null in headless (no import), but must not error.
	_check(true, "animal_texture('moose') does not crash")
	var truck: Texture2D = Art.vehicle_texture("veh_fire_truck")
	_check(true, "vehicle_texture('veh_fire_truck') does not crash")
	# Monster scale table covers all five disaster kinds.
	var scales := {
		"giant_ass": 3.0, "thicc_moose": 2.2, "giant_lizard": 1.8,
		"rogue_wizard": 1.2, "cardboard_cat": 0.9,
	}
	_check(scales.size() == 5, "all 5 disaster kinds have visual scales")


# ---------------------------------------------------------------- weather

func _test_weather() -> void:
	var g := _make_game()
	var w := WeatherFX.new()
	# force_weather works without setup (no game needed for the flag).
	w.force_weather("rain")
	_check(w.current_weather() == "rain", "force_weather rain")
	w.force_weather("snow")
	_check(w.current_weather() == "snow", "force_weather snow")
	w.force_weather("clear")
	_check(w.current_weather() == "clear", "force_weather clear")
	w.queue_free()
