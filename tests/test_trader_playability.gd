extends SceneTree
## Cursing Gnomes — Captain Funky Pants playability headless tests
## (launch-readiness 2026-10-06, gate 1: systems playable & functional).
##
## The trader loop was sim-complete but player-dead: trader_arrived /
## trader_left had zero listeners, the funky_pants68.png sprite was unused,
## and trade()/deposit() had no game-code callers. These tests pin the
## closed loop:
##   - arrival spawns the caravan visual at funky_pos; departure despawns it
##   - save/load self-heal (funky_on_map already true at setup -> spawns)
##   - arrival/departure publish Gazette stories (HTML systemMsg parity)
##   - panel deal/deposit defs match the HTML #funky-trade-panel verbatim
##   - deal success/failure paths (goods, caravan stock, warehouse room,
##     caravan gone) with the HTML-verbatim messages
##   - deposit success/failure paths
##   - tap on the caravan opens the panel; tap elsewhere / while placing does not
##   - layer follows funky_pos and flips the sprite with travel direction
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_trader_playability.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


## Duck-typed camera double: tapped signal + screen_to_world, no viewport.
class _FakeCam extends RefCounted:
	signal tapped(screen_pos: Vector2)
	var world_point := Vector2.ZERO
	func screen_to_world(_sp: Vector2) -> Vector2:
		return world_point


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes trader playability tests ===")
	_test_arrival_spawns_visual()
	_test_departure_despawns_and_closes_panel()
	_test_save_load_self_heal()
	_test_arrival_gazette_story()
	_test_departure_gazette_story()
	_test_deal_defs_verbatim()
	_test_deposit_defs_verbatim()
	_test_deal_success()
	_test_deal_not_enough_goods()
	_test_deal_sold_out()
	_test_deal_no_warehouse_space()
	_test_deal_caravan_gone()
	_test_deposit_success()
	_test_deposit_not_enough()
	_test_tap_opens_panel()
	_test_tap_adventure_guard()
	_test_tap_miss_and_placing_guard()
	_test_tap_outside_closes_panel()
	_test_layer_follows_and_flips()
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


## Fresh game with industry (player_faction defaults to "humans").
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves"])
	_stories.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	var ind := SimIndustry.new(gs)
	gs.industry = ind
	ind.reset()
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	gs.resources.add_resource("humans", "wood", 1000.0, true)
	gs.resources.add_resource("humans", "food", 1000.0, true)
	gs.resources.add_resource("humans", "oil", 1000.0, true)
	gs.resources.add_resource("humans", "seeds", 1000.0, true)
	return {"gs": gs, "ind": ind}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _new_layer(w: Dictionary, cam) -> TraderLayer:
	var gs: GameState = w["gs"]
	var tl := TraderLayer.new()
	root.add_child(tl)
	tl.setup(gs.bus, w["ind"], cam, null, gs)
	return tl


## --- arrival / departure ------------------------------------------------------


func _test_arrival_spawns_visual() -> void:
	var w := _new_world()
	var tl := _new_layer(w, null)
	_check("arrival: hidden before", not tl.is_trader_here())
	_check("arrival: node invisible before", not tl.visible)
	var ind: SimIndustry = w["ind"]
	ind._begin_visit()
	_check("arrival: on map after", tl.is_trader_here())
	_check("arrival: node visible after", tl.visible)
	_check("arrival: node at funky_pos",
		tl.position.distance_to(ind.funky_pos) < 1.0)
	tl.queue_free()
	_free_world(w)


func _test_departure_despawns_and_closes_panel() -> void:
	var w := _new_world()
	var tl := _new_layer(w, null)
	var ind: SimIndustry = w["ind"]
	ind._begin_visit()
	(tl.get("_panel") as TraderPanel).open()
	_check("departure: panel open", (tl.get("_panel") as TraderPanel).is_open())
	ind._end_visit()
	_check("departure: off map", not tl.is_trader_here())
	_check("departure: node hidden", not tl.visible)
	_check("departure: panel closed",
		not (tl.get("_panel") as TraderPanel).is_open())
	tl.queue_free()
	_free_world(w)


func _test_save_load_self_heal() -> void:
	var w := _new_world()
	var ind: SimIndustry = w["ind"]
	ind._begin_visit()
	# Simulate a loaded save: fresh layer, bus signals will NOT refire.
	var tl := TraderLayer.new()
	root.add_child(tl)
	tl.setup((w["gs"] as GameState).bus, ind, null, null, w["gs"])
	_check("self-heal: spawns when funky_on_map at setup", tl.is_trader_here())
	_check("self-heal: node at funky_pos",
		tl.position.distance_to(ind.funky_pos) < 1.0)
	tl.queue_free()
	_free_world(w)


## --- gazette parity ------------------------------------------------------------


func _test_arrival_gazette_story() -> void:
	var w := _new_world()
	(w["ind"] as SimIndustry)._begin_visit()
	var found := false
	for s in _stories:
		if String(s.get("headline", "")).begins_with(
				"Captain Funky Pants' caravan has arrived"):
			found = true
	_check("arrival: gazette story published", found)
	_free_world(w)


func _test_departure_gazette_story() -> void:
	var w := _new_world()
	var ind: SimIndustry = w["ind"]
	ind._begin_visit()
	_stories.clear()
	ind._end_visit()
	var found := false
	for s in _stories:
		if String(s.get("headline", "")).begins_with(
				"Captain Funky Pants packs up"):
			found = true
	_check("departure: gazette story published", found)
	_free_world(w)


## --- panel defs (HTML verbatim) -------------------------------------------------


func _test_deal_defs_verbatim() -> void:
	var want := [
		["gold", 50.0, "wood", 80.0],
		["wood", 60.0, "gold", 40.0],
		["gold", 40.0, "food", 50.0],
		["food", 30.0, "seeds", 15.0],
		["gold", 80.0, "oil", 25.0],
		["oil", 20.0, "gold", 70.0],
	]
	_check("deals: 6 defs", TraderPanel.DEAL_DEFS.size() == 6)
	for i in want.size():
		var d: Dictionary = TraderPanel.DEAL_DEFS[i]
		var e: Array = want[i]
		_check("deal %d verbatim" % i,
			String(d["give"]) == e[0] and float(d["give_amt"]) == e[1] \
			and String(d["take"]) == e[2] and float(d["take_amt"]) == e[3])


func _test_deposit_defs_verbatim() -> void:
	var want := [["wood", 50.0], ["gold", 50.0], ["food", 30.0]]
	_check("deposits: 3 defs", TraderPanel.DEPOSIT_DEFS.size() == 3)
	for i in want.size():
		var d: Dictionary = TraderPanel.DEPOSIT_DEFS[i]
		_check("deposit %d verbatim" % i,
			String(d["res"]) == want[i][0] and float(d["amt"]) == want[i][1])


## --- deal economy -----------------------------------------------------------------


func _deal_panel(w: Dictionary) -> TraderPanel:
	var tl := _new_layer(w, null)
	(w["ind"] as SimIndustry)._begin_visit()
	return tl.get("_panel") as TraderPanel


func _test_deal_success() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var ind: SimIndustry = w["ind"]
	var p := _deal_panel(w)
	var g0: float = gs.resources.get_amount("humans", "gold")
	var w0: float = gs.resources.get_amount("humans", "wood")
	var s0: float = float(ind.funky_stock["wood"])
	var msg: String = p.attempt_deal(0)  # 50 gold -> 80 wood
	_check("deal: success message",
		msg == "Funky Pants: \"Pleasure doin' business!\"")
	_check("deal: player paid gold",
		is_equal_approx(gs.resources.get_amount("humans", "gold"), g0 - 50.0))
	_check("deal: player got wood",
		is_equal_approx(gs.resources.get_amount("humans", "wood"), w0 + 80.0))
	_check("deal: caravan stock moved",
		is_equal_approx(float(ind.funky_stock["gold"]), 400.0 + 50.0) \
		and is_equal_approx(float(ind.funky_stock["wood"]), s0 - 80.0))
	(p.get_parent() as TraderLayer).queue_free()
	_free_world(w)


func _test_deal_not_enough_goods() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var p := _deal_panel(w)
	gs.resources.spend("humans", {"gold": 990.0})  # 10 left, deal needs 50
	var msg: String = p.attempt_deal(0)
	_check("deal: not-enough message", msg == "Not enough gold.")
	(p.get_parent() as TraderLayer).queue_free()
	_free_world(w)


func _test_deal_sold_out() -> void:
	var w := _new_world()
	var ind: SimIndustry = w["ind"]
	var p := _deal_panel(w)
	ind.funky_stock["wood"] = 10.0  # deal needs 80
	var msg: String = p.attempt_deal(0)
	_check("deal: sold-out message", msg == "Funky is out of wood.")
	(p.get_parent() as TraderLayer).queue_free()
	_free_world(w)


func _test_deal_no_warehouse_space() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var p := _deal_panel(w)
	# Fill wood to the cap so the 80-wood take cannot fit.
	var cap: float = gs.resources.get_cap("humans", "wood")
	gs.resources.add_resource("humans", "wood", cap, true)
	var msg: String = p.attempt_deal(0)
	_check("deal: no-space message", msg == "No warehouse space for wood!")
	(p.get_parent() as TraderLayer).queue_free()
	_free_world(w)


func _test_deal_caravan_gone() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var p := TraderPanel.new()
	root.add_child(p)
	p.setup(gs)
	# Caravan never arrived: open() refuses and attempt_deal reports gone.
	p.open()
	_check("deal: panel stays closed when caravan away", not p.is_open())
	var msg: String = p.attempt_deal(0)
	_check("deal: caravan-gone message", msg == "Caravan is gone.")
	p.queue_free()
	_free_world(w)


func _test_deposit_success() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var ind: SimIndustry = w["ind"]
	var p := _deal_panel(w)
	var w0: float = gs.resources.get_amount("humans", "wood")
	var s0: float = float(ind.funky_stock["wood"])
	var msg: String = p.attempt_deposit(0)  # 50 wood
	_check("deposit: success message",
		msg == "Deposited 50 wood with Funky Pants")
	_check("deposit: player paid",
		is_equal_approx(gs.resources.get_amount("humans", "wood"), w0 - 50.0))
	_check("deposit: caravan stock grew",
		is_equal_approx(float(ind.funky_stock["wood"]), s0 + 50.0))
	(p.get_parent() as TraderLayer).queue_free()
	_free_world(w)


func _test_deposit_not_enough() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var p := _deal_panel(w)
	gs.resources.spend("humans", {"wood": 990.0})  # 10 left, needs 50
	var msg: String = p.attempt_deposit(0)
	_check("deposit: not-enough message", msg == "Not enough wood")
	(p.get_parent() as TraderLayer).queue_free()
	_free_world(w)


## --- tap routing ------------------------------------------------------------------


func _test_tap_opens_panel() -> void:
	var w := _new_world()
	var ind: SimIndustry = w["ind"]
	ind._begin_visit()
	var cam := _FakeCam.new()
	var tl := _new_layer(w, cam)
	var panel := tl.get("_panel") as TraderPanel
	cam.world_point = ind.funky_pos + Vector2(10, 5)  # inside TAP_RADIUS
	cam.tapped.emit(Vector2(400, 300))
	_check("tap: panel opens on caravan tap", panel.is_open())
	tl.queue_free()
	_free_world(w)


func _test_tap_adventure_guard() -> void:
	var w := _new_world()
	var ind: SimIndustry = w["ind"]
	ind._begin_visit()
	var cam := _FakeCam.new()
	var tl := TraderLayer.new()
	root.add_child(tl)
	tl.setup((w["gs"] as GameState).bus, ind, cam, null, w["gs"],
		func() -> bool: return true)  # adventure input active
	var panel := tl.get("_panel") as TraderPanel
	cam.world_point = ind.funky_pos
	cam.tapped.emit(Vector2(400, 300))
	_check("tap: adventure guard blocks panel", not panel.is_open())
	tl.queue_free()
	_free_world(w)


func _test_tap_miss_and_placing_guard() -> void:
	var w := _new_world()
	var ind: SimIndustry = w["ind"]
	ind._begin_visit()
	var cam := _FakeCam.new()
	var tl := _new_layer(w, cam)
	var panel := tl.get("_panel") as TraderPanel
	# Tap far from the caravan: nothing happens.
	cam.world_point = ind.funky_pos + Vector2(500, 500)
	cam.tapped.emit(Vector2(100, 100))
	_check("tap: miss does not open panel", not panel.is_open())
	# Tap on the caravan while placement is armed: placement wins.
	var tl2 := TraderLayer.new()
	root.add_child(tl2)
	var armed := {"placing": true}
	tl2.setup((w["gs"] as GameState).bus, ind, cam, armed, w["gs"])
	cam.world_point = ind.funky_pos
	cam.tapped.emit(Vector2(400, 300))
	_check("tap: placing guard blocks panel",
		not (tl2.get("_panel") as TraderPanel).is_open())
	# Tap with the caravan gone: nothing happens.
	ind._end_visit()
	cam.world_point = Vector2(2048, 2048)
	cam.tapped.emit(Vector2(400, 300))
	_check("tap: gone caravan does not open panel", not panel.is_open())
	tl.queue_free()
	tl2.queue_free()
	_free_world(w)


## Jeremy 2026-10-05 tap-outside-to-close (the hud.gd scrim idiom): the
## trader panel's dim layer is a full-screen button, so a tap anywhere
## outside the panel dismisses it instead of dying on a dead dim.
func _test_tap_outside_closes_panel() -> void:
	var w := _new_world()
	var p := _deal_panel(w)
	p.open()
	_check("dim: panel open", p.is_open())
	var rootc: Control = p.get("_root")
	_check("dim: root swallows world taps",
		rootc.mouse_filter == Control.MOUSE_FILTER_STOP)
	var dim := rootc.get_child(0)
	_check("dim: tap layer is a Button (scrim idiom)", dim is Button)
	var db := dim as Button
	_check("dim: no text", db.text == "")
	var sb := db.get_theme_stylebox("normal")
	_check("dim: 0.45 black dim style kept",
		sb is StyleBoxFlat \
		and (sb as StyleBoxFlat).bg_color == Color(0, 0, 0, 0.45))
	_check("dim: full-rect anchors",
		db.anchor_right == 1.0 and db.anchor_bottom == 1.0)
	# Tapping the dim dismisses the panel.
	db.pressed.emit()
	_check("dim: tap outside closes panel", not p.is_open())
	_check("dim: panel hidden after tap", not p.visible)
	# Back button still closes too (existing path preserved).
	p.open()
	_check("dim: panel reopened", p.is_open())
	var back: Button = null
	for b in p.find_children("", "Button", true, false):
		if (b as Button).text == "Back":
			back = b as Button
	_check("dim: Back button exists", back != null)
	if back != null:
		back.pressed.emit()
		_check("dim: Back still closes panel", not p.is_open())
	(p.get_parent() as TraderLayer).queue_free()
	_free_world(w)


## --- movement sync ------------------------------------------------------------------


func _test_layer_follows_and_flips() -> void:
	var w := _new_world()
	var ind: SimIndustry = w["ind"]
	var tl := _new_layer(w, null)
	ind._begin_visit()
	var p0: Vector2 = ind.funky_pos
	tl._process(0.016)
	_check("follow: layer tracks funky_pos",
		tl.position.distance_to(ind.funky_pos) < 1.0)
	# Walk right: sprite faces right (no flip).
	ind.funky_pos = p0 + Vector2(60, 0)
	tl._process(0.5)
	_check("facing: right = no flip",
		not (tl.get("_sprite") as Sprite2D).flip_h)
	# Walk left: sprite flips.
	ind.funky_pos = p0 + Vector2(-60, 0)
	tl._process(0.5)
	_check("facing: left = flip",
		(tl.get("_sprite") as Sprite2D).flip_h)
	_check("follow: position synced after wander",
		tl.position.distance_to(ind.funky_pos) < 1.0)
	tl.queue_free()
	_free_world(w)
