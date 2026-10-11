extends SceneTree
## Cursing Gnomes — inside-building hiding tests.
## Jeremy 2026-10-08 (wake deep-systems): units with inside_building_id > 0
## (siege hiding via interiors.enter, urge sleep, etc.) must vanish from
## the main map. The interior_entered/exited signals were emitted but
## nothing hid the sprite — a silent failure. UnitNode.set_inside() +
## world sync wiring fixes it; the interior_view shows occupants when
## the building is opened.


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
	await process_frame
	print("=== Cursing Gnomes inside-hiding tests ===")
	await _test_starts_visible()
	await _test_inside_hides()
	await _test_exit_shows()
	await _test_inside_beats_culling()
	await _test_culled_stays_hidden_when_inside_clears()
	await _test_idempotent()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _make_node() -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	# _ready flags settle on the first frame; await before asserting.
	return un


func _test_starts_visible() -> void:
	var un := _make_node()
	await process_frame
	_check("inside: starts not inside", not un._inside)
	_check("inside: starts visible", un.visible)
	un.free()


func _test_inside_hides() -> void:
	var un := _make_node()
	await process_frame
	un.set_inside(true)
	_check("inside: set_inside(true) hides", not un.visible)
	_check("inside: flag set", un._inside)
	un.free()


func _test_exit_shows() -> void:
	var un := _make_node()
	await process_frame
	un.set_inside(true)
	un.set_inside(false)
	_check("inside: set_inside(false) shows again", un.visible)
	_check("inside: flag cleared", not un._inside)
	un.free()


func _test_inside_beats_culling() -> void:
	var un := _make_node()
	await process_frame
	# Culled (off-screen) then goes inside: stays hidden.
	un.set_culled(true)
	un.set_inside(true)
	_check("inside: culled+inside stays hidden", not un.visible)
	# Comes back on-screen but still inside: stays hidden.
	un.set_culled(false)
	_check("inside: unculled but inside stays hidden", not un.visible)
	# Exits the building while on-screen: visible.
	un.set_inside(false)
	_check("inside: exit while on-screen shows", un.visible)
	un.free()


func _test_culled_stays_hidden_when_inside_clears() -> void:
	var un := _make_node()
	await process_frame
	# Inside then culled (scrolls off-screen while inside).
	un.set_inside(true)
	un.set_culled(true)
	# Exits while off-screen: stays hidden (culling wins).
	un.set_inside(false)
	_check("inside: exit while culled stays hidden", not un.visible)
	# Scrolls back on-screen: visible.
	un.set_culled(false)
	_check("inside: unculled after exit shows", un.visible)
	un.free()


func _test_idempotent() -> void:
	var un := _make_node()
	await process_frame
	# Repeated calls don't toggle or error.
	un.set_inside(true)
	un.set_inside(true)
	_check("inside: double set_inside(true) stays hidden", not un.visible)
	un.set_inside(false)
	un.set_inside(false)
	_check("inside: double set_inside(false) stays visible", un.visible)
	un.free()
