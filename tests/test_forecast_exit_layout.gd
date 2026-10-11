extends SceneTree
## Cursing Gnomes — Forecast P0 regression tests (Jeremy 2026-10-11 iPhone).
##
## 1. Crash on exit: leaving the Forecast menu must never strand or crash.
##    The header back button is freed by the teardown its own press
##    triggers, so navigation is deferred — the emitter must finish its
##    signal on a live node. Pins: header-back exit, nav-back exit, and
##    repeated open/exit cycles all land on home cleanly.
## 2. Disaster-row text layout: each upcoming-disaster row must have real
##    height and rows must not overlap (was: Button is not a Container, so
##    rows collapsed to 0px and every disaster name + "in N days" line
##    piled on top of each other, colliding with the Festivals header).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_forecast_exit_layout.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed := 0
var _failed := 0
var _failures: Array[String] = []
var _gs: GameState
var _ui: PhoneUI


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		push_error("FAIL: " + name)


func _init() -> void:
	_gs = GameState.new()
	root.add_child(_gs)
	_gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var combat := SimCombat.new(_gs)
	var dz := DisasterSim.new(_gs, combat)
	_gs.disasters = dz
	dz.forecast[15] = {"type": "moose", "label": "Thicc Moose", "done": false}
	dz.forecast[18] = {"type": "raid", "label": "Bandit Raid", "done": false}
	dz.forecast[22] = {"type": "moose", "label": "Black Moose", "done": false}
	_gs.seasons = SimSeasons.new(_gs)
	var phone := SimPhone.new(_gs)
	var court := SimRoyalCourt.new(_gs)
	_ui = PhoneUI.new()
	root.add_child(_ui)
	_ui.setup(_gs, phone, court, _gs.diplomacy)
	_run.call_deferred()


func _disaster_rows() -> Array:
	var out: Array = []
	var stack: Array = [(_ui.get("_screen_host") as Node)]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and n.get_parent() is VBoxContainer \
				and (n as Button).text == "" \
				and n.get_child_count() == 1 \
				and n.get_child(0) is HBoxContainer:
			out.append(n)
		for c: Node in n.get_children():
			stack.append(c)
	# VBox order = top to bottom; sort by position to be sure.
	out.sort_custom(func(a: Button, b: Button) -> bool:
		return a.position.y < b.position.y)
	return out


func _header_back() -> Button:
	var host: Node = _ui.get("_screen_host")
	var rootc: Node = host.get_child(0)
	for c: Node in rootc.get_children():
		if c is PanelContainer:
			for cc: Node in c.get_children():
				if cc is HBoxContainer and cc.get_child_count() > 0 \
						and cc.get_child(0) is Button:
					return cc.get_child(0) as Button
	return null


func _run() -> void:
	await process_frame
	await process_frame
	print("=== Cursing Gnomes forecast exit/layout P0 tests ===")
	await _test_disaster_row_layout()
	await _test_exit_header_back()
	await _test_exit_nav_back()
	await _test_row_tap_deferred()
	await _test_exit_cycles()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	_ui.queue_free()
	_gs.queue_free()
	quit(1 if _failed > 0 else 0)


func _test_disaster_row_layout() -> void:
	_ui.open_app("calendar")
	await process_frame
	await process_frame
	var rows: Array = _disaster_rows()
	_check(rows.size() >= 3, "disaster rows exist (%d found)" % rows.size())
	var prev_bottom := -1.0
	for b: Button in rows:
		var r := b.get_rect()
		_check(r.size.y >= 40.0,
			"row has real height (%.1fpx)" % r.size.y)
		_check(b.get_combined_minimum_size().y >= 40.0,
			"row min height sane (%.1fpx)" % b.get_combined_minimum_size().y)
		if prev_bottom >= 0.0:
			_check(r.position.y >= prev_bottom - 0.5,
				"rows do not overlap (y=%.1f prev_bottom=%.1f)" \
				% [r.position.y, prev_bottom])
		prev_bottom = r.position.y + r.size.y
		# The inner visual row must fill the button, not overflow it.
		var inner := b.get_child(0) as Control
		_check(absf(inner.size.y - r.size.y) <= 2.0,
			"inner row fills button (%.1f vs %.1f)" % [inner.size.y, r.size.y])


func _test_exit_header_back() -> void:
	_ui.open_app("calendar")
	await process_frame
	await process_frame
	var back := _header_back()
	_check(back != null, "header back button found")
	if back == null:
		return
	back.pressed.emit()
	# Navigation is deferred — the emitter must outlive its own signal.
	await process_frame
	await process_frame
	_check(_ui.current_screen() == "home",
		"header back exits to home (screen=%s)" % _ui.current_screen())


func _test_exit_nav_back() -> void:
	_ui.open_app("calendar")
	await process_frame
	_ui._on_status_back()
	await process_frame
	await process_frame
	_check(_ui.current_screen() == "home",
		"nav back exits to home (screen=%s)" % _ui.current_screen())


func _test_row_tap_deferred() -> void:
	_ui.open_app("calendar")
	await process_frame
	await process_frame
	var rows: Array = _disaster_rows()
	_check(not rows.is_empty(), "row available for tap test")
	if rows.is_empty():
		return
	(rows[0] as Button).pressed.emit()
	await process_frame
	await process_frame
	_check(_ui.current_screen() == "disaster_response",
		"disaster row tap opens response (screen=%s)" % _ui.current_screen())
	# And back out of the response screen cleanly.
	_ui._on_status_back()
	await process_frame
	await process_frame
	_check(_ui.current_screen() == "home",
		"response screen backs out to home (screen=%s)" % _ui.current_screen())


func _test_exit_cycles() -> void:
	for i in 5:
		_ui.open_app("calendar")
		await process_frame
		var back := _header_back()
		if back != null:
			back.pressed.emit()
		await process_frame
		await process_frame
		_check(_ui.current_screen() == "home",
			"cycle %d exits cleanly (screen=%s)" % [i, _ui.current_screen()])
