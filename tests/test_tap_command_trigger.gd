extends SceneTree
## Cursing Gnomes — tap-to-command trigger tests (Jeremy 2026-10-09).
##
## Jeremy's spec: "tap-to-command means the ENTIRE military goes on a tap
## ('It should just command your entire military to go')" — NO unit
## selection required. Covers the menu trigger contract:
##
## - show_command_menu opens on an empty-ground tap when the player has
##   >= 1 commandable military unit (title shows the headcount).
## - show_command_menu stays CLOSED when the player has no military
##   (no menu spam for a fresh town).
## - If the army is lost between menu-open and button-press, Move /
##   Attack-Move flash an honest hint and keep the menu open (no silent
##   failure).
## - Move / Attack-Move issue to the whole military and close the menu.
## - The world._on_tapped precedence (harvest tap -> gather menu before
##   the command check) is enforced by nearest_harvest_site pick math:
##   a tap near a harvestable node finds the node, and the command menu
##   only fires when no node is in range.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tap_command_trigger.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	print("=== Cursing Gnomes tap-command trigger tests ===")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_menu_opens_with_military()
	_test_menu_stays_closed_without_military()
	_test_move_honest_hint_keeps_menu_open()
	_test_attack_move_honest_hint_keeps_menu_open()
	_test_move_orders_whole_military_and_closes()
	_test_dead_units_excluded_from_gate()
	_test_order_all_move_zero_military_returns_zero()
	_test_harvest_site_pick_math()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## Fresh world: player = humans, combat + tap_command wired, HUD built.
func _new_hud() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	gs.player_faction = "humans"
	var combat := SimCombat.new(gs)
	gs.set("combat", combat)
	var tap := SimTapCommand.new(gs)
	gs.set("tap_command", tap)
	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	return {"gs": gs, "tap": tap, "hud": hud}


func _free_hud(w: Dictionary) -> void:
	(w["hud"] as Hud).free()
	(w["gs"] as GameState).free()


func _soldier(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, "soldier", -1, pos)
	u["hp"] = float(u.get("max_hp", 100.0))
	u["attack_cd"] = 0.0
	return u


## Menu opens when the player has commandable military (title = headcount).
func _test_menu_opens_with_military() -> void:
	var w: Dictionary = _new_hud()
	var hud: Hud = w["hud"]
	_soldier(w, "humans", Vector2(100, 100))
	_soldier(w, "humans", Vector2(200, 200))
	hud.show_command_menu(Vector2(500, 500))
	_check("menu opens with military", hud._cmd_menu.visible)
	_check("menu title shows headcount",
		hud._cmd_title.text == "Command Military (2)")
	_free_hud(w)


## Menu stays closed when the player has no military — no menu spam.
func _test_menu_stays_closed_without_military() -> void:
	var w: Dictionary = _new_hud()
	var hud: Hud = w["hud"]
	hud.show_command_menu(Vector2(500, 500))
	_check("menu stays closed with zero military",
		not hud._cmd_menu.visible)
	_free_hud(w)


## Army dies after the menu opened: Move flashes the honest hint and the
## menu stays open (no silent close).
func _test_move_honest_hint_keeps_menu_open() -> void:
	var w: Dictionary = _new_hud()
	var hud: Hud = w["hud"]
	var u: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	hud.show_command_menu(Vector2(500, 500))
	_check("menu open before army lost", hud._cmd_menu.visible)
	u["alive"] = false
	hud._on_command_move()
	_check("move: honest hint flashed",
		hud._hint_label.text == Hud.NO_ARMY_HINT)
	_check("move: menu stays open for retry", hud._cmd_menu.visible)
	_free_hud(w)


## Same for Attack-Move.
func _test_attack_move_honest_hint_keeps_menu_open() -> void:
	var w: Dictionary = _new_hud()
	var hud: Hud = w["hud"]
	var u: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	hud.show_command_menu(Vector2(500, 500))
	u["alive"] = false
	hud._on_command_attack_move()
	_check("attack-move: honest hint flashed",
		hud._hint_label.text == Hud.NO_ARMY_HINT)
	_check("attack-move: menu stays open for retry", hud._cmd_menu.visible)
	_free_hud(w)


## Move orders the whole military, closes the menu, confirms with a hint.
func _test_move_orders_whole_military_and_closes() -> void:
	var w: Dictionary = _new_hud()
	var hud: Hud = w["hud"]
	var u1: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	var u2: Dictionary = _soldier(w, "humans", Vector2(200, 200))
	hud.show_command_menu(Vector2(900, 900))
	hud._on_command_move()
	_check("move: both units ordered",
		SimTapCommand.order_type_of(u1) == "move"
		and SimTapCommand.order_type_of(u2) == "move")
	_check("move: menu closed", not hud._cmd_menu.visible)
	_check("move: confirmation hint",
		hud._hint_label.text == "Move order: 2 units marching.")
	_free_hud(w)


## The world's n > 0 gate: dead units must not count toward the trigger.
func _test_dead_units_excluded_from_gate() -> void:
	var w: Dictionary = _new_hud()
	var tap: SimTapCommand = w["tap"]
	var hud: Hud = w["hud"]
	var u: Dictionary = _soldier(w, "humans", Vector2(100, 100))
	_check("gate: live soldier counted", tap.all_military_ids().size() == 1)
	u["alive"] = false
	_check("gate: dead soldier excluded", tap.all_military_ids().is_empty())
	hud.show_command_menu(Vector2(500, 500))
	_check("gate: menu closed when army dead", not hud._cmd_menu.visible)
	_free_hud(w)


## order_all_move with an empty roster returns 0 (defense in depth).
func _test_order_all_move_zero_military_returns_zero() -> void:
	var w: Dictionary = _new_hud()
	var tap: SimTapCommand = w["tap"]
	_check("order_all_move zero military -> 0",
		tap.order_all_move(Vector2(900, 900)) == 0)
	_check("order_all_attack_move zero military -> 0",
		tap.order_all_attack_move(Vector2(900, 900)) == 0)
	_free_hud(w)


## Harvest-tap precedence math: a tap near a harvestable node resolves to
## the node (world._on_tapped checks this BEFORE the command menu), and a
## far tap resolves to nothing (command menu may fire).
func _test_harvest_site_pick_math() -> void:
	var sites: Array = [
		{"kind": "tree", "amount": 50.0, "position": Vector2(100, 100)},
		{"kind": "gold_vein", "amount": 0.0, "position": Vector2(200, 200)},
		{"kind": "quarry", "amount": 50.0, "position": Vector2(300, 300)},
	]
	var near: Dictionary = World.nearest_harvest_site(
		sites, Vector2(110, 110), 60.0)
	_check("harvest: near tree picked", not near.is_empty()
		and String(near.get("kind", "")) == "tree")
	var depleted: Dictionary = World.nearest_harvest_site(
		sites, Vector2(210, 210), 60.0)
	_check("harvest: depleted vein skipped", depleted.is_empty())
	var wrong_kind: Dictionary = World.nearest_harvest_site(
		sites, Vector2(310, 310), 60.0)
	_check("harvest: non-harvest kind skipped", wrong_kind.is_empty())
	var far: Dictionary = World.nearest_harvest_site(
		sites, Vector2(900, 900), 60.0)
	_check("harvest: far tap finds nothing (command menu fires)",
		far.is_empty())
