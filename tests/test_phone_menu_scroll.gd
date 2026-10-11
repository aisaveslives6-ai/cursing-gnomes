extends SceneTree
## Cursing Gnomes — phone menu-scroll audit tests (Jeremy 2026-10-10).
##
## Jeremy: "a lot of menus don't have proper scroll." This suite pins the
## phone-side fixes:
##   - all four system modals (build request, strategic proposal, diplomacy
##     confirm, insult input) cap their dialog height and scroll — a long
##     adviser brief must never push Approve (a war decision!) off-screen,
##     and the insult dialog's Send/Cancel must stay reachable.
##   - Gazette article / petition / Squabble post / diplomacy cards use the
##     _thread_item PASS+IGNORE convention: drags starting on a card scroll
##     the list instead of dying on a STOP dead-zone; buttons stay STOP
##     (Godot-safe: no mid-scroll tap-fire).
##   - home-screen tiles no longer accept_event() the press, so the home
##     ScrollContainer can claim drags; tap still opens the app, a drag
##     past HOME_DRAG_SLOP still kills the tap.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_phone_menu_scroll.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed := 0
var _failed := 0
var _failures: Array[String] = []
var _w: Dictionary = {}


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		push_error("FAIL: " + name)


func _init() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court, gs.diplomacy)
	_w = {"gs": gs, "phone": phone, "court": court, "ui": ui}
	_run.call_deferred()


func _run() -> void:
	# Let the tree settle so viewport-dependent code paths work.
	await process_frame
	await process_frame
	print("=== Cursing Gnomes phone menu-scroll tests ===")
	_test_modal_scroll_tall_capped()
	_test_modal_scroll_short_hugs()
	_test_strategic_modal_scrolls()
	_test_insult_modal_scrolls()
	_test_article_card_filters()
	_test_petition_card_filters()
	_test_post_card_filters()
	_test_diplo_card_filters()
	_test_home_tap_still_fires()
	_test_home_drag_kills_tap()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	(_w["ui"] as PhoneUI).queue_free()
	(_w["gs"] as GameState).queue_free()
	quit(1 if _failed > 0 else 0)


func _ui() -> PhoneUI:
	return _w["ui"] as PhoneUI


## --- modal scroll caps -------------------------------------------------------


func _make_dialog(child_count: int, child_h: float) -> Array:
	var dlg := PanelContainer.new()
	root.add_child(dlg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dlg.add_child(vbox)
	for i in child_count:
		var b := Button.new()
		b.text = "row %d" % i
		b.custom_minimum_size = Vector2(0, child_h)
		vbox.add_child(b)
	return [dlg, vbox]


func _test_modal_scroll_tall_capped() -> void:
	var ui := _ui()
	var parts := _make_dialog(20, 110.0)
	var dlg: PanelContainer = parts[0]
	var vbox: VBoxContainer = parts[1]
	var scroll := ui._cap_modal_scroll(dlg, vbox)
	_check(scroll != null, "modal: helper returns a ScrollContainer")
	_check(dlg.get_child(0) == scroll, "modal: scroll inserted under dlg")
	_check(scroll.get_child(0) == vbox, "modal: vbox reparented into scroll")
	_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"modal: horizontal scroll stays disabled")
	var cap: float = ui.get("_phone_h") * 0.78
	_check(scroll.custom_minimum_size.y <= cap + 1.0,
		"modal: tall dialog capped to 78%% phone height (%.0f <= %.0f)"
		% [scroll.custom_minimum_size.y, cap])
	_check(scroll.custom_minimum_size.y < vbox.get_combined_minimum_size().y,
		"modal: capped dialog shorter than content, so it scrolls")
	dlg.queue_free()


func _test_modal_scroll_short_hugs() -> void:
	var ui := _ui()
	var parts := _make_dialog(1, 44.0)
	var dlg: PanelContainer = parts[0]
	var vbox: VBoxContainer = parts[1]
	var scroll := ui._cap_modal_scroll(dlg, vbox)
	_check(absf(scroll.custom_minimum_size.y - 44.0) < 1.0,
		"modal: short dialog hugs its content (%.0f)" % scroll.custom_minimum_size.y)
	dlg.queue_free()


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n as ScrollContainer
	for c in n.get_children():
		var s := _find_scroll(c)
		if s != null:
			return s
	return null


func _test_strategic_modal_scrolls() -> void:
	var ui := _ui()
	var brief := ""
	for i in 40:
		brief += "Scout line %d: the enemy masses beyond the ridge. " % i
	ui.show_strategic_proposal({"id": 71, "kind": "declare_war",
		"details": {"target": "elves", "brief": brief}})
	var overlay := ui.get_child(ui.get_child_count() - 1)
	var scroll := _find_scroll(overlay)
	_check(scroll != null, "strategic modal: content wrapped in a ScrollContainer")
	if scroll != null:
		var cap: float = ui.get("_phone_h") * 0.78
		_check(scroll.custom_minimum_size.y <= cap + 1.0,
			"strategic modal: dialog capped with a 40-line brief")
	ui._dismiss_modal(overlay)


func _find_overlay_with_button(ui: PhoneUI, text: String) -> Control:
	for i in range(ui.get_child_count() - 1, -1, -1):
		var ch := ui.get_child(i)
		if _collect_buttons(ch, [text], false):
			return ch as Control
	return null


func _test_insult_modal_scrolls() -> void:
	var ui := _ui()
	ui._diplo_insult_input("elves", "Elves")
	# NOTE: the custom keyboard opens on entry focus and lands after the
	# overlay in the child order — locate the dialog by its Send button.
	var overlay := _find_overlay_with_button(ui, "Send Insult")
	_check(overlay != null, "insult modal: overlay found")
	if overlay == null:
		return
	var scroll := _find_scroll(overlay)
	_check(scroll != null, "insult modal: content wrapped in a ScrollContainer")
	if scroll != null:
		var cap: float = ui.get("_phone_h") * 0.78
		_check(scroll.custom_minimum_size.y <= cap + 1.0,
			"insult modal: dialog capped to 78%% phone height")
		# The Send button must still exist under the scroll (reachable).
		_check(_collect_buttons(overlay, ["Send Insult"], false),
			"insult modal: Send Insult button present under scroll")
	ui._dismiss_modal(overlay)


func _collect_buttons(n: Node, names: Array, found: bool) -> bool:
	if n is Button and (n as Button).text in names:
		return true
	for c in n.get_children():
		if _collect_buttons(c, names, found):
			return true
	return found


## --- card mouse-filter convention --------------------------------------------


func _descendants(n: Node, out: Array) -> void:
	for c in n.get_children():
		out.append(c)
		_descendants(c, out)


func _check_card_convention(card: Control, name: String,
		expect_button: bool) -> void:
	_check(card.mouse_filter == Control.MOUSE_FILTER_PASS,
		"%s: card is PASS (drags scroll)" % name)
	var nodes: Array = []
	_descendants(card, nodes)
	var saw_button := false
	for n in nodes:
		if n is Button:
			saw_button = true
			_check((n as Button).mouse_filter == Control.MOUSE_FILTER_STOP,
				"%s: buttons stay STOP" % name)
		elif n is Label or n is TextureRect or n is Container:
			_check((n as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"%s: non-interactive child IGNORE (%s)" % [name, n.get_class()])
	if expect_button:
		_check(saw_button, "%s: has at least one button" % name)


func _test_article_card_filters() -> void:
	var ui := _ui()
	var card := ui._gazette_article_card({
		"section": "Town Crier", "headline": "Gnomes triumph",
		"byline": "Scoop", "dayline": "Day 3", "story": "A great victory.",
		"cartoon_path": "", "urgent": false, "lead": true})
	_check_card_convention(card, "article card", false)
	card.queue_free()


func _test_petition_card_filters() -> void:
	var ui := _ui()
	var card := ui._petition_card({"id": 3, "from_name": "Bob",
		"role": "peasant", "text": "Please build a well.", "from_key": "",
		"options": ["Yes", "No"]})
	_check_card_convention(card, "petition card", true)
	card.queue_free()


func _test_post_card_filters() -> void:
	var ui := _ui()
	var card := ui._post_card({"id": 1, "author_key": "ruler",
		"author_name": "Ruler", "day": 1, "text": "Hear ye!",
		"comments": [{"author": "Ann", "text": "Nice!"}],
		"likes": 2, "resquabbles": 0, "pfp": ""})
	_check_card_convention(card, "post card", true)
	card.queue_free()


func _test_diplo_card_filters() -> void:
	var ui := _ui()
	var card := ui._diplo_card("elves")
	_check_card_convention(card, "diplo card", true)
	card.queue_free()


## --- home tile gestures --------------------------------------------------------


func _make_grid() -> Array:
	var grid = PhoneUI.HomeGrid.new()
	root.add_child(grid)
	grid.build(null, [["a", "A", ""]], ["a"], 360.0)
	var tile = grid._tiles[0]
	return [grid, tile]


func _test_home_tap_still_fires() -> void:
	var parts := _make_grid()
	var grid = parts[0]
	var tile = parts[1]
	var tapped: Array = []
	grid.app_tapped.connect(func(app_id: String) -> void: tapped.append(app_id))
	grid._tile_pressed(tile, Vector2(10, 10))
	grid._release_anywhere()
	_check(tapped == ["a"], "home: clean press+release still opens the app")
	grid.queue_free()


func _test_home_drag_kills_tap() -> void:
	var parts := _make_grid()
	var grid = parts[0]
	var tile = parts[1]
	var tapped: Array = []
	grid.app_tapped.connect(func(app_id: String) -> void: tapped.append(app_id))
	grid._tile_pressed(tile, Vector2(10, 10))
	grid._press_moved = true  # drag past HOME_DRAG_SLOP: gesture was a scroll
	grid._release_anywhere()
	_check(tapped.is_empty(), "home: drag does not fire the app tap")
	grid.queue_free()
