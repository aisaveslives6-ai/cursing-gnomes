extends SceneTree
## Cursing Gnomes — Forecast/Weather app scroll-safety tests (Jeremy 2026-10-10).
##
## Jeremy: "a lot of menus don't have proper scroll." The Forecast calendar
## and Weather apps render into a ScrollContainer, but the month grid's
## ~42 day cells (Labels / Panels / spacer Controls / disaster Buttons, all
## default-STOP) covered most of the viewport, so drags starting on the grid
## died before reaching the scroll — the same dead-zone class as the rumors
## cards (fixed 2026-10-07). This suite pins the PASS+IGNORE convention for
## both apps:
##   - tappable disaster surfaces (grid day buttons, upcoming-disaster rows)
##     are PASS: drags scroll the list, taps still open the response panel
##     (Godot-safe: no mid-scroll tap-fire).
##   - every display-only cell, label, banner, and card is IGNORE.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_forecast_scroll.gd
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
	# DisasterSim is owned by World; build one directly so the tappable
	# disaster surfaces (grid day buttons, disaster rows) exist.
	var combat := SimCombat.new(gs)
	var dz := DisasterSim.new(gs, combat)
	gs.disasters = dz
	# One upcoming, unfired disaster: seeds both the grid button and the row.
	dz.forecast[15] = {"type": "moose", "label": "Thicc Moose", "done": false}
	# SimSeasons is owned by World; build one directly so the calendar and
	# weather apps render their full content instead of the closed-office stub.
	gs.seasons = SimSeasons.new(gs)
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
	print("=== Cursing Gnomes forecast scroll tests ===")
	_test_calendar_grid_filters()
	_test_forecast_row_filter()
	_test_disaster_rows_filters()
	_test_weather_app_filters()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	(_w["ui"] as PhoneUI).queue_free()
	(_w["gs"] as GameState).queue_free()
	quit(1 if _failed > 0 else 0)


func _ui() -> PhoneUI:
	return _w["ui"] as PhoneUI


## Current screen container (_show_* rebuilds it per screen).
func _screen_root() -> Control:
	return _ui().get("_root") as Control


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n as ScrollContainer
	for c in n.get_children():
		var s := _find_scroll(c)
		if s != null:
			return s
	return null


func _descendants(n: Node, out: Array) -> void:
	for c in n.get_children():
		out.append(c)
		_descendants(c, out)


## Scroll-safety convention: tappable Buttons are PASS (drags scroll, taps
## fire); display-only Panels/Labels/plain Controls are IGNORE. Pure layout
## containers (VBox/HBox/Grid, non-Panel) are skipped — the sibling audit
## owns their filters.
func _assert_scroll_safe(nodes: Array, name: String) -> void:
	for n in nodes:
		if n is Button:
			_check((n as Button).mouse_filter == Control.MOUSE_FILTER_PASS,
				"%s: tappable button is PASS" % name)
		elif n is PanelContainer:
			_check((n as PanelContainer).mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"%s: display panel is IGNORE" % name)
		elif n is Label:
			_check((n as Label).mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"%s: label is IGNORE" % name)
		elif n is Control and not (n is Container):
			_check((n as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"%s: plain control is IGNORE (%s)" % [name, n.get_class()])


func _count_buttons(nodes: Array) -> int:
	var c := 0
	for n in nodes:
		if n is Button:
			c += 1
	return c


## --- Forecast calendar -------------------------------------------------------


func _test_calendar_grid_filters() -> void:
	var ui := _ui()
	ui._show_calendar()
	var sc := _find_scroll(_screen_root())
	_check(sc != null, "forecast: content wrapped in a ScrollContainer")
	if sc == null:
		return
	var grid: GridContainer = null
	var snodes: Array = []
	_descendants(sc, snodes)
	for n in snodes:
		if n is GridContainer:
			grid = n as GridContainer
			break
	_check(grid != null, "forecast: month grid present")
	if grid == null:
		return
	var gnodes: Array = []
	_descendants(grid, gnodes)
	# 7 weekday headers + spacers + 30 day cells: the grid is the dominant
	# viewport surface, so every cell must be scroll-safe.
	_check(gnodes.size() >= 37, "forecast: grid has all cells (%d)" % gnodes.size())
	_assert_scroll_safe(gnodes, "forecast grid")
	_check(_count_buttons(gnodes) >= 1,
		"forecast: at least one disaster day button (seeded)")
	# Banners and plain-text rows under the grid share the same convention.
	var box: VBoxContainer = sc.get_child(0) as VBoxContainer
	var labels: Array = []
	for ch in box.get_children():
		if ch is Label:
			labels.append(ch)
	_check(labels.size() >= 3, "forecast: banner labels present (%d)" % labels.size())
	_assert_scroll_safe(labels, "forecast banner")
	_check(ui._forecast_row("No disasters on the horizon.") is Label,
		"forecast: _forecast_row returns a Label")


func _test_forecast_row_filter() -> void:
	var l := _ui()._forecast_row("No disasters on the horizon.")
	_check(l.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"forecast row: plain-text label is IGNORE (drags scroll)")


func _test_disaster_rows_filters() -> void:
	var ui := _ui()
	var box := VBoxContainer.new()
	root.add_child(box)
	ui._forecast_disaster_rows(box)
	var rows: Array = box.get_children()
	_check(_count_buttons(rows) >= 1,
		"disaster rows: at least one tappable row (seeded disaster)")
	var all: Array = []
	_descendants(box, all)
	_assert_scroll_safe(all, "disaster row")
	box.queue_free()


## --- Weather app -------------------------------------------------------------


func _test_weather_app_filters() -> void:
	var ui := _ui()
	ui._show_weather()
	var sc := _find_scroll(_screen_root())
	_check(sc != null, "weather: content wrapped in a ScrollContainer")
	if sc == null:
		return
	var nodes: Array = []
	_descendants(sc, nodes)
	_assert_scroll_safe(nodes, "weather app")
	_check(_count_buttons(nodes) == 0,
		"weather: no buttons inside the scroll (display-only app)")
