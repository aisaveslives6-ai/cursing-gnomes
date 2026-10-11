extends SceneTree
## Regression tests for Allison's 2026-10-06 keyboard verdict:
##   1. Autocorrect mangled ordinary words ("intended", "brothel") because
##      BASE_WORDS only had 809 entries — a real English word wasn't "known".
##   2. Pressing Send rewrote the final word before sending.
##   3. Keyboard lag (autocorrect did a full-pool edit-distance scan per
##      space/send — now 12x bigger vocabulary, so it uses first-char
##      buckets with a full-scan fallback).
##
## Run: Godot --headless --path . -s res://tests/test_keyboard_vocab.gd

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
	SimKeyboardDict.set_save_path_override("user://test_keyboard_vocab.cfg")
	DirAccess.remove_absolute("user://test_keyboard_vocab.cfg")
	_test_vocab_size()
	_test_allison_reported_words()
	_test_send_does_not_rewrite_known_word()
	_test_autocorrect_still_works()
	_test_fallback_wrong_first_letter()
	_test_autocorrect_perf()
	_test_curated_words_survive()
	print("test_keyboard_vocab: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _test_vocab_size() -> void:
	var d := SimKeyboardDict.new()
	_check(d.base_word_count() >= 9000,
		"base vocab >= 9000 (got %d)" % d.base_word_count())


func _test_allison_reported_words() -> void:
	# The two words Allison reported as broken.
	for agg in ["medium", "high", "aggressive"]:
		var d := SimKeyboardDict.new()
		d.aggression = agg
		_check(d.is_known("intended"), "intended is known (%s)" % agg)
		_check(d.autocorrect("intended") == "",
			"intended is never corrected (%s, got '%s')" % [agg, d.autocorrect("intended")])
		_check(d.is_known("brothel"), "brothel is known (%s)" % agg)
		_check(d.autocorrect("brothel") == "",
			"brothel is never corrected (%s, got '%s')" % [agg, d.autocorrect("brothel")])


func _test_send_does_not_rewrite_known_word() -> void:
	# Allison's core complaint: Send rewrote her final word and the ogre
	# thought she wanted war. The final word must survive Send untouched.
	DirAccess.remove_absolute("user://test_keyboard_vocab.cfg")
	var kb := PhoneKeyboard.new()
	var root := Node.new()
	root.add_child(kb)
	var field := LineEdit.new()
	root.add_child(field)
	kb.dict.aggression = "medium"
	kb.open_for(field, 1.0)
	# NOTE: GDScript lambdas capture locals by value — use an Array so the
	# callback can report back.
	var flag := [false]
	kb.send_pressed.connect(func() -> void: flag[0] = true)
	field.text = "i intended"
	kb._on_send()
	_check(flag[0], "send signal fired")
	_check(field.text == "i intended ",
		"send keeps known final word (got '%s')" % field.text)
	_check(kb._pending_correction.is_empty(),
		"no correction marked on send of a known word")
	kb.close()
	root.free()


func _test_autocorrect_still_works() -> void:
	var d := SimKeyboardDict.new()
	d.aggression = "medium"
	_check(d.autocorrect("teh") == "the", "medium still fixes teh->the (got '%s')" % d.autocorrect("teh"))
	_check(d.autocorrect("intendedd") == "intended",
		"medium fixes intendedd->intended (got '%s')" % d.autocorrect("intendedd"))
	_check(d.autocorrect("atack") == "attack",
		"medium fixes atack->attack (got '%s')" % d.autocorrect("atack"))
	_check(d.autocorrect("zxqvwx") == "", "medium leaves garbage alone")


func _test_fallback_wrong_first_letter() -> void:
	# "ntended" (dropped first letter) misses the first-char bucket; the
	# full-pool fallback must still find "intended".
	var d := SimKeyboardDict.new()
	d.aggression = "medium"
	_check(d.autocorrect("ntended") == "intended",
		"fallback fixes ntended->intended (got '%s')" % d.autocorrect("ntended"))


func _test_autocorrect_perf() -> void:
	var d := SimKeyboardDict.new()
	d.aggression = "medium"
	var t0 := Time.get_ticks_msec()
	for i in 12:
		d.autocorrect("intendd")
		d.autocorrect("teh")
		d.autocorrect("zxqvwx")
	var dt := Time.get_ticks_msec() - t0
	_check(dt < 2000,
		"36 autocorrect calls with 10k vocab under 2s (got %d ms)" % dt)


func _test_curated_words_survive() -> void:
	# The hand-picked slang / crude / game-term lists must not be lost in
	# the merge: they're "known" so autocorrect never touches them.
	var d := SimKeyboardDict.new()
	for w in ["lol", "yeet", "rizz", "ass", "bastard", "gnome", "squabble",
			"moose", "thicc", "don't", "urges"]:
		_check(d.is_known(w), "curated word still known: %s" % w)
