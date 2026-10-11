extends SceneTree
## Cursing Gnomes — farm auto-plot tests (2026-10-05 launch-readiness, gate 1).
##
## Only the single free starting plot (world.gd _spawn_demo) ever existed:
## nothing else called create_plot, so every farm/farmhouse beyond the first
## was a decorative building with no working field — for the player AND the
## AI. SimFarming now grows one working field per completed farm/farmhouse
## on a slow reconcile pass. These tests pin that wiring:
##   - a completed farm gets a linked plot after the reconcile interval,
##   - no duplicates on repeated passes, blueprints/dead/flesh farms excluded,
##   - the nearby unlinked starting plot is adopted, not duplicated,
##   - neighboring farms each get their own field,
##   - building_id links survive save/load,
##   - the auto-plot is a real working plot (plant -> harvest pays food).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_farm_plot_autocreate.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes farm auto-plot tests ===")
	_test_completed_farm_gets_plot()
	_test_no_duplicate_on_repass()
	_test_blueprint_gets_no_plot()
	_test_dead_farm_gets_no_plot()
	_test_flesh_farm_gets_no_plot()
	_test_nearby_unlinked_plot_adopted()
	_test_distant_unlinked_plot_not_adopted()
	_test_neighboring_farms_each_get_field()
	_test_farmhouse_gets_plot()
	_test_save_load_keeps_links()
	_test_auto_plot_grows_food()
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
	return gs


func _farm(gs: GameState, faction: String, pos: Vector2,
		btype: String = "farm", complete: bool = true,
		alive: bool = true) -> Dictionary:
	return gs.add_building({"type": btype, "faction": faction,
		"position": pos, "alive": alive, "complete": complete})


func _tick_reconcile(f: SimFarming) -> void:
	# Push past the reconcile interval twice for margin.
	f.tick(SimFarming.PLOT_RECONCILE_INTERVAL + 1.0)


func _plots_for(f: SimFarming, faction: String) -> Array:
	var out: Array = []
	for p: Dictionary in f.plots:
		if String(p.get("faction", "")) == faction:
			out.append(p)
	return out


## ---- core -----------------------------------------------------------------


func _test_completed_farm_gets_plot() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var b := _farm(gs, "humans", Vector2(500, 500))
	_check("no plot before reconcile", _plots_for(f, "humans").is_empty())
	_tick_reconcile(f)
	var ps := _plots_for(f, "humans")
	_check("one plot after reconcile", ps.size() == 1)
	_check("plot linked to building",
		int(ps[0].get("building_id", -1)) == int(b.get("id", -2)))
	_check("plot near the farm",
		(ps[0].get("position", Vector2.ZERO) as Vector2).distance_to(
			Vector2(500, 500)) < 200.0)
	_check("plot free (no wood charged)",
		int(ps[0].get("seed_bin", 0)) == SimFarming.START_SEED_BIN)


func _test_no_duplicate_on_repass() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	_farm(gs, "humans", Vector2(500, 500))
	_tick_reconcile(f)
	_tick_reconcile(f)
	_tick_reconcile(f)
	_check("still exactly one plot", _plots_for(f, "humans").size() == 1)


func _test_blueprint_gets_no_plot() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	_farm(gs, "humans", Vector2(500, 500), "farm", false)  # blueprint
	_tick_reconcile(f)
	_check("blueprint gets no plot", _plots_for(f, "humans").is_empty())


func _test_dead_farm_gets_no_plot() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	_farm(gs, "humans", Vector2(500, 500), "farm", true, false)  # razed
	_tick_reconcile(f)
	_check("dead farm gets no plot", _plots_for(f, "humans").is_empty())


func _test_flesh_farm_gets_no_plot() -> void:
	var gs := _new_game(["undead"])
	var f := SimFarming.new(gs)
	_farm(gs, "undead", Vector2(500, 500), "flesh_farm")
	_tick_reconcile(f)
	_check("flesh farm gets no crop plot", _plots_for(f, "undead").is_empty())


## ---- adoption / neighbors -------------------------------------------------


func _test_nearby_unlinked_plot_adopted() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	# The demo-farm shape: unlinked starting plot ~128px from the farm.
	_farm(gs, "humans", Vector2(500, 500))
	f.create_plot("humans", Vector2(500 - 45, 500 - 120), -1, true)
	_tick_reconcile(f)
	_check("starting plot adopted, not duplicated",
		_plots_for(f, "humans").size() == 1)


func _test_distant_unlinked_plot_not_adopted() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	_farm(gs, "humans", Vector2(500, 500))
	f.create_plot("humans", Vector2(2000, 2000), -1, true)
	_tick_reconcile(f)
	var ps := _plots_for(f, "humans")
	_check("distant plot kept plus new field", ps.size() == 2)
	var linked := 0
	for p: Dictionary in ps:
		if int(p.get("building_id", -1)) >= 0:
			linked += 1
	_check("exactly one linked field", linked == 1)


func _test_neighboring_farms_each_get_field() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var a := _farm(gs, "humans", Vector2(500, 500))
	var b := _farm(gs, "humans", Vector2(650, 500))  # 150px apart
	_tick_reconcile(f)
	var ps := _plots_for(f, "humans")
	_check("two neighboring farms -> two fields", ps.size() == 2)
	var ids := {}
	for p: Dictionary in ps:
		ids[int(p.get("building_id", -1))] = true
	_check("fields linked to distinct farms",
		ids.has(int(a.get("id", -2))) and ids.has(int(b.get("id", -3))))


func _test_farmhouse_gets_plot() -> void:
	var gs := _new_game(["elves"])
	var f := SimFarming.new(gs)
	_farm(gs, "elves", Vector2(900, 900), "farmhouse")
	_tick_reconcile(f)
	_check("farmhouse gets a field",
		_plots_for(f, "elves").size() == 1)


## ---- persistence / function -----------------------------------------------


func _test_save_load_keeps_links() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var b := _farm(gs, "humans", Vector2(500, 500))
	_tick_reconcile(f)
	var data := f.to_dict()
	var f2 := SimFarming.new(gs)
	f2.from_dict(data)
	var ps: Array = []
	for p: Dictionary in f2.plots:
		if String(p.get("faction", "")) == "humans":
			ps.append(p)
	_check("link survives save/load", ps.size() == 1
		and int(ps[0].get("building_id", -1)) == int(b.get("id", -2)))
	# A loaded game must not re-create the field.
	_tick_reconcile(f2)
	var ps2: Array = []
	for p: Dictionary in f2.plots:
		if String(p.get("faction", "")) == "humans":
			ps2.append(p)
	_check("no duplicate after load", ps2.size() == 1)


func _test_auto_plot_grows_food() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	_farm(gs, "humans", Vector2(500, 500))
	_tick_reconcile(f)
	var ps := _plots_for(f, "humans")
	_check("field exists for chore test", ps.size() == 1)
	if ps.is_empty():
		return
	var plot: Dictionary = ps[0]
	var chore := f.plot_chore(plot)
	_check("field offers a plant chore",
		String(chore.get("action", "")) == "plant")
	_check("plant succeeds", f.plant(plot, int(chore.get("tile", 0))))
	f.tick(2.0 * Config.DAY_LENGTH_SECONDS)  # grow to maturity
	var food_before = gs.resources.get_amount("humans", "food")
	f.harvest(plot, int(chore.get("tile", 0)))
	_check("harvest pays food",
		gs.resources.get_amount("humans", "food") > food_before)
