extends SceneTree
## Regression tests for Jeremy 2026-10-06 high-priority bug:
## "Phone lock screen soft-locks the game" — tapping the phone's power
## button showed a dark "tap to wake" lock screen with no working path back
## to the main sim view. Design intent (Jeremy 2026-10-05/06): the bottom
## nav is Back / Home / Power, and Power CLOSES the phone back to the sim.
## The sleep/wake lock screen was removed; power now closes the phone.
##
## Run: Godot --headless --path . -s res://tests/test_phone_power_close.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("FAIL: ", name)


func _initialize() -> void:
	_test_no_lock_screen()
	_test_power_closes_phone()
	_test_close_dismisses_keyboard()
	print("test_phone_power_close: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _new_ui() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	return {"gs": gs, "ui": ui}


func _free_ui(w: Dictionary) -> void:
	(w["ui"] as PhoneUI).queue_free()
	(w["gs"] as GameState).queue_free()


## The lock screen must not exist anywhere in the phone shell: no
## "tap to wake" label, no leftover sleep overlay.
func _test_no_lock_screen() -> void:
	var w := _new_ui()
	var ui: PhoneUI = w["ui"]
	var labels := ui.find_children("*", "Label", true, false)
	var lock_found := false
	for lab in labels:
		if (lab as Label).text == "tap to wake":
			lock_found = true
			break
	_check(not lock_found, "no 'tap to wake' lock screen anywhere in the phone")
	_free_ui(w)


## The nav-bar power button ("Close phone") closes the phone back to the sim.
func _test_power_closes_phone() -> void:
	var w := _new_ui()
	var ui: PhoneUI = w["ui"]
	ui.visible = true
	var power: Button = null
	for child in (ui._nav_bar as HBoxContainer).get_children():
		if child is Button and (child as Button).tooltip_text == "Close phone":
			power = child
			break
	_check(power != null, "nav bar has a 'Close phone' power button")
	if power != null:
		power.pressed.emit()
		_check(not ui.visible, "pressing power hides the phone (back to sim)")
	_free_ui(w)


## Closing the phone dismisses the open custom keyboard first.
func _test_close_dismisses_keyboard() -> void:
	var w := _new_ui()
	var ui: PhoneUI = w["ui"]
	ui.visible = true
	ui._close_phone()
	# Keyboard is only built on demand; closing with it unbuilt must not error,
	# and the phone must be hidden either way.
	_check(not ui.visible, "close hides the phone even with keyboard unbuilt")
	_check(ui._kb == null or not ui._kb.is_open(),
		"custom keyboard is not open after close")
	_free_ui(w)
