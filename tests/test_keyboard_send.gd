extends SceneTree
## Regression tests for Allison's 2026-10-06 verdict, part 2: pressing Send
## rewrote the trailing word before sending (an ogre thought she wanted war).
## Send must complete the word for LEARNING but never autocorrect it — what
## she typed is what gets sent. Corrections happen on Space (reviewable).
##
## Separate file so it never collides with test_phone_keyboard.gd /
## test_keyboard_vocab.gd edits.
##
## Run: Godot --headless --path . -s res://tests/test_keyboard_send.gd

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
	SimKeyboardDict.set_save_path_override("user://test_keyboard_send.cfg")
	DirAccess.remove_absolute("user://test_keyboard_send.cfg")
	_test_send_keeps_typo_word()
	_test_send_keeps_typo_high_aggression()
	_test_space_still_corrects()
	_test_send_honors_manual_revert()
	_test_send_still_learns()
	print("test_keyboard_send: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _make_kb(aggression: String) -> Array:
	# Returns [kb, field, root]. Caller must root.free() when done.
	DirAccess.remove_absolute("user://test_keyboard_send.cfg")
	var kb := PhoneKeyboard.new()
	var root := Node.new()
	root.add_child(kb)
	var field := LineEdit.new()
	root.add_child(field)
	kb.dict.aggression = aggression
	kb.open_for(field, 1.0)
	return [kb, field, root]


func _test_send_keeps_typo_word() -> void:
	# The core bug: "teh" + Send became "the" with no review. Now it stays.
	var parts: Array = _make_kb("medium")
	var kb: PhoneKeyboard = parts[0]
	var field: LineEdit = parts[1]
	var root: Node = parts[2]
	var flag := [false]
	kb.send_pressed.connect(func() -> void: flag[0] = true)
	field.text = "teh"
	kb._on_send()
	_check(flag[0], "send signal fired")
	_check(field.text == "teh ",
		"send keeps typo word as typed (got '%s')" % field.text)
	_check(kb.autocorrect_marks().is_empty(),
		"no correction marks from send")
	kb.close()
	root.free()


func _test_send_keeps_typo_high_aggression() -> void:
	# Even at high aggression, Send must not rewrite.
	var parts: Array = _make_kb("high")
	var kb: PhoneKeyboard = parts[0]
	var field: LineEdit = parts[1]
	var root: Node = parts[2]
	field.text = "i gane"
	kb._on_send()
	_check(field.text == "i gane ",
		"high aggression send keeps typo (got '%s')" % field.text)
	kb.close()
	root.free()


func _test_space_still_corrects() -> void:
	# Control: Space (not Send) still autocorrects — the fix is send-only.
	var parts: Array = _make_kb("medium")
	var kb: PhoneKeyboard = parts[0]
	var field: LineEdit = parts[1]
	var root: Node = parts[2]
	field.text = "teh"
	kb._complete_word()
	_check(field.text == "the ",
		"space still corrects teh->the (got '%s')" % field.text)
	_check(kb.autocorrect_marks().size() == 1,
		"space correction leaves a review mark")
	kb.close()
	root.free()


func _test_send_honors_manual_revert() -> void:
	# Space corrects teh->the; user backspaces and retypes teh; Send must
	# honor the revert (keep "teh") and remember the override.
	var parts: Array = _make_kb("medium")
	var kb: PhoneKeyboard = parts[0]
	var field: LineEdit = parts[1]
	var root: Node = parts[2]
	field.text = "teh"
	kb._complete_word()
	_check(field.text == "the ", "setup: space corrected (got '%s')" % field.text)
	# Backspace the correction away, retype the original.
	kb._backspace()
	kb._backspace()
	kb._backspace()
	kb._backspace()
	kb._insert_raw("teh")
	kb._on_send()
	_check(field.text == "teh ",
		"send honors the manual revert (got '%s')" % field.text)
	_check(kb.dict.is_correction_blocked("teh", "the"),
		"revert on send blacklists the correction")
	kb.close()
	root.free()


func _test_send_still_learns() -> void:
	# Send skips autocorrect but must NOT skip learning: typing an unknown
	# word 3x across sends still triggers the "Add word?" prompt path.
	var parts: Array = _make_kb("medium")
	var kb: PhoneKeyboard = parts[0]
	var field: LineEdit = parts[1]
	var root: Node = parts[2]
	for i in 3:
		kb.open_for(field, 1.0)
		field.text = "zqxwv"
		kb._on_send()
	_check(kb.dict.word_frequency("zqxwv") == 3,
		"send feeds the frequency model (got %d)" % kb.dict.word_frequency("zqxwv"))
	kb.close()
	root.free()
