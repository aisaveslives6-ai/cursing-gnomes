extends SceneTree
## Tests for the phone's custom keyboard: SimKeyboardDict (autocorrect,
## learning, suggestions) and PhoneKeyboard (themes, input).
##
## Run: Godot --headless --path . -s res://tests/test_phone_keyboard.gd

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
	# Isolate from the real save file — tests must not pollute it.
	SimKeyboardDict.set_save_path_override("user://test_keyboard_dict.cfg")
	DirAccess.remove_absolute("user://test_keyboard_dict.cfg")
	_test_dict_basics()
	_test_autocorrect_levels()
	_test_context_awareness()
	_test_correction_memory()
	_test_style_adaptation()
	_test_learning()
	_test_suggestions()
	_test_suggestion_cache()
	_test_keyboard_themes()
	_test_keyboard_input()
	_test_realtime_correction()
	_test_learning_despite_correction()
	_test_marks_and_revert()
	_test_manual_revert()
	_test_learning_persistence()
	_test_key_sizes()
	_test_key_glow_release()
	_test_learn_dialog_names_typed_word()
	_test_review_dialog_buttons()
	_test_review_dialog_revert_button()
	_test_learn_dialog_tap_outside()
	_test_keyboard_safe_bottom_lift()
	print("test_phone_keyboard: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


# --- dictionary basics ------------------------------------------------------------

func _test_dict_basics() -> void:
	var d := SimKeyboardDict.new()
	d.aggression = "medium"
	_check(d.is_known("hello"), "dict knows hello")
	_check(d.is_known("gnome"), "dict knows game term gnome")
	_check(d.is_known("lol"), "dict knows slang lol")
	_check(d.is_known("u"), "dict knows slang u")
	_check(not d.is_known("zxqvwx"), "dict flags unknown word")
	_check(d.is_known(""), "empty word is known (no correction)")
	_check(d.base_word_count() > 200, "base dict has substantial vocabulary")


# --- autocorrect aggression levels --------------------------------------------------

func _test_autocorrect_levels() -> void:
	# Low: never auto-replaces.
	var d := SimKeyboardDict.new()
	d.aggression = "low"
	_check(d.autocorrect("teh") == "", "low never corrects")
	_check(d.autocorrect("teh", "in") == "", "low never corrects with context")

	# Medium: obvious single-char typos.
	d.aggression = "medium"
	var m1 := d.autocorrect("teh")
	_check(m1 == "the", "medium fixes teh->the (got '%s')" % m1)
	_check(d.autocorrect("zxqvwx") == "", "medium leaves unknown words alone")

	# High: aggressive correction.
	d.aggression = "high"
	var h1 := d.autocorrect("gane", "video")
	_check(h1 == "game", "high fixes gane->game with context (got '%s')" % h1)

	# Aggressive: rewrites with confidence.
	d.aggression = "aggressive"
	var a1 := d.autocorrect("attak", "we")
	_check(a1 == "attack", "aggressive fixes attak->attack (got '%s')" % a1)

	# Known words are never "corrected".
	d.aggression = "aggressive"
	_check(d.autocorrect("hello") == "", "known words never corrected")
	_check(d.autocorrect("lol") == "", "slang never corrected")


# --- context awareness (bigrams) -------------------------------------------------------

func _test_context_awareness() -> void:
	var d := SimKeyboardDict.new()
	d.aggression = "high"
	# Teach: "attack the dragon" several times.
	for i in 3:
		d.note_word_typed("attack")
		d.note_word_typed("the")
		d.note_word_typed("dragon")
		d.note_sentence_end()
	# Now "dragom" after "the" should prefer "dragon" via bigram fit.
	var c := d.autocorrect("dragom", "the")
	_check(c == "dragon", "bigram context picks dragon (got '%s')" % c)
	# Suggestions should rank bigram followers first.
	var s: Array = d.suggestions("dr", "the", 3)
	_check(s.size() > 0 and String(s[0]) == "dragon",
		"suggestion ranks bigram follower first (got %s)" % str(s))


# --- correction memory (overrides) ---------------------------------------------------------

func _test_correction_memory() -> void:
	var d := SimKeyboardDict.new()
	d.aggression = "high"
	# User types "teh" a lot — it becomes trusted.
	for i in 5:
		d.note_word_typed("teh")
	# Now autocorrect should NOT "fix" teh — the user types it deliberately.
	var c := d.autocorrect("teh")
	_check(c == "", "frequent user word not corrected (got '%s')" % c)
	# Explicit override: user reverts our correction.
	var d2 := SimKeyboardDict.new()
	d2.aggression = "high"
	d2.note_correction_overridden("teh", "the")
	_check(d2.is_correction_blocked("teh", "the"), "override recorded")
	_check(d2.autocorrect("teh") == "", "blocked correction not repeated")


# --- style adaptation --------------------------------------------------------------------------

func _test_style_adaptation() -> void:
	var d := SimKeyboardDict.new()
	_check(d.slang_affinity() == 0.0, "slang affinity starts at 0")
	for i in 5:
		d.note_word_typed("lol")
		d.note_word_typed("lmao")
	_check(d.slang_affinity() > 0.3, "slang affinity rises with slang use")
	# Slang suggestions boosted when affinity is high.
	var s: Array = d.suggestions("lm", "", 3)
	var has_lmao := false
	for x in s:
		if String(x) == "lmao":
			has_lmao = true
	_check(has_lmao, "slang suggestion boosted (got %s)" % str(s))


# --- word learning -------------------------------------------------------------------------------

func _test_learning() -> void:
	var d := SimKeyboardDict.new()
	d.aggression = "medium"
	d.auto_learn = false
	# Type an unknown word 3 times -> "prompt".
	_check(d.note_word_typed("zork") == "", "1st use: no prompt")
	_check(d.note_word_typed("zork") == "", "2nd use: no prompt")
	_check(d.note_word_typed("zork") == "prompt", "3rd use: prompt")
	# Add it, then it's known and suggested.
	d.add_learned_word("zork")
	_check(d.is_known("zork"), "learned word is known")
	_check(d.is_learned("zork"), "learned word flagged learned")
	var s: Array = d.suggestions("zo", "", 3)
	_check(s.has("zork"), "learned word appears in suggestions")
	# Delete it.
	_check(d.remove_learned_word("zork"), "remove returns true")
	_check(not d.is_learned("zork"), "removed word no longer learned")
	_check(not d.remove_learned_word("zork"), "double remove returns false")
	# Auto-learn mode.
	var d2 := SimKeyboardDict.new()
	d2.auto_learn = true
	d2.note_word_typed("blorpt")
	d2.note_word_typed("blorpt")
	_check(d2.note_word_typed("blorpt") == "learned", "auto-learn learns silently")
	_check(d2.is_learned("blorpt"), "auto-learned word stored")
	# Junk is ignored.
	_check(d2.note_word_typed("x") == "", "single char ignored")
	_check(d2.note_word_typed("123") == "", "numbers ignored")


# --- suggestions ------------------------------------------------------------------------------------

func _test_suggestions() -> void:
	var d := SimKeyboardDict.new()
	var s: Array = d.suggestions("hel", "", 3)
	_check(s.has("hello"), "prefix suggestion works")
	_check(s.size() <= 3, "suggestion limit respected")
	_check(d.suggestions("", "", 3).is_empty(), "empty partial -> no suggestions")
	# Learned words rank first.
	d.add_learned_word("helicopterish")
	var s2: Array = d.suggestions("hel", "", 5)
	_check(s2.size() > 0 and String(s2[0]) == "helicopterish",
		"learned word ranks first (got %s)" % str(s2))


# --- suggestion candidate cache (Jeremy 2026-10-06 keyboard lag fix) -------------------
# suggestions() runs per keystroke; the candidate pool is cached and only
# rebuilt when the vocabulary changes. These pin the invalidation paths.

func _test_suggestion_cache() -> void:
	var d := SimKeyboardDict.new()
	# Warm the cache with a call.
	_check(not d.suggestions("hel", "", 3).is_empty(), "cache warms on first call")
	# Add a learned word AFTER the cache is warm — it must appear.
	d.add_learned_word("zqxjk")
	var s: Array = d.suggestions("zqx", "", 3)
	_check(s.has("zqxjk"), "newly learned word visible after cache warm (got %s)" % str(s))
	# Remove it — it must disappear (no stale cache).
	_check(d.remove_learned_word("zqxjk"), "remove returns true")
	var s2: Array = d.suggestions("zqx", "", 3)
	_check(not s2.has("zqxjk"), "removed word gone, no stale cache (got %s)" % str(s2))
	# Substring (non-prefix) matches still work for 3+ char partials.
	var d2 := SimKeyboardDict.new()
	d2.add_learned_word("xyabcmn")
	var s3: Array = d2.suggestions("abc", "", 5)
	_check(s3.has("xyabcmn"), "substring match works for 3+ chars (got %s)" % str(s3))
	# Short partials only do prefix matches (perf gate).
	var s4: Array = d2.suggestions("bc", "", 10)
	var only_prefix := true
	for w in s4:
		if not String(w).begins_with("bc"):
			only_prefix = false
	_check(only_prefix, "2-char partials are prefix-only (got %s)" % str(s4))
	# Repeated calls are consistent (cache reuse, not rebuild drift).
	var a: Array = d.suggestions("hel", "", 3)
	var b: Array = d.suggestions("hel", "", 3)
	_check(a == b, "repeated suggestions consistent")


# --- keyboard themes -----------------------------------------------------------------------------------

func _test_keyboard_themes() -> void:
	var kb := PhoneKeyboard.new()
	_check(PhoneKeyboard.THEME_ORDER.size() >= 5, "at least 5 themes")
	_check(kb.current_theme() == "dark", "default theme is dark")
	kb.set_kb_theme("ogre")
	_check(kb.current_theme() == "ogre", "theme switches")
	kb.set_kb_theme("nonexistent")
	_check(kb.current_theme() == "ogre", "invalid theme ignored")
	for tid in PhoneKeyboard.THEME_ORDER:
		var tname := kb.theme_name(String(tid))
		_check(tname != String(tid), "theme %s has a display name" % tid)
	kb.free()


# --- keyboard input simulation --------------------------------------------------------------------------

func _test_keyboard_input() -> void:
	var kb := PhoneKeyboard.new()
	var root := Node.new()
	root.add_child(kb)
	# Fake field: any Control with a .text property works.
	var field := LineEdit.new()
	root.add_child(field)
	kb.open_for(field, 1.0)
	_check(kb.is_open(), "keyboard opens")
	# Simulate typing via the internal insert path.
	kb._insert_raw("h")
	kb._insert_raw("i")
	_check(field.text == "hi", "typing writes to field")
	kb._backspace()
	_check(field.text == "h", "backspace works")
	# Space triggers word completion + learning pipeline.
	field.text = "helo"
	kb._complete_word()
	# "helo" is a typo of "hello" — medium aggression should fix it.
	_check(field.text.strip_edges() == "hello",
		"space autocorrects helo->hello (got '%s')" % field.text)
	kb.close()
	_check(not kb.is_open(), "keyboard closes")
	root.free()


# --- real-time per-word correction (Jeremy 2026-10-05) ----------------------------------------------

func _test_realtime_correction() -> void:
	var d := SimKeyboardDict.new()
	d.aggression = "medium"
	# Crude words are in the base dictionary now — never "corrected".
	_check(d.is_known("butt"), "butt is a known word")
	_check(d.autocorrect("butt") == "", "butt is never corrected")
	_check(d.is_known("asshole"), "asshole is a known word")
	_check(d.autocorrect("asshole") == "", "asshole is never corrected")
	# Space triggers correction immediately (not deferred to send).
	var parts: Array = _new_open_keyboard()
	var kb: PhoneKeyboard = parts[0]
	var root: Node = parts[1]
	var field: LineEdit = parts[2]
	field.text = "helo"
	kb._on_space()
	_check(field.text == "hello ", "space corrects in real time (got '%s')" % field.text)
	kb.close()
	root.free()


# --- learning tracks what you TYPED, not the correction -------------------------------------------------
## Regression test for Jeremy 2026-10-05: typing "butt" repeatedly never
## learned it, because only the corrected word was recorded.

func _test_learning_despite_correction() -> void:
	var d := SimKeyboardDict.new()
	d.aggression = "medium"
	d.auto_learn = false
	# "teh" -> corrected to "the", but the TYPED word still counts.
	_check(d.note_word_typed("the", "teh") == "", "typed-word 1st use: no prompt")
	_check(d.note_word_typed("the", "teh") == "", "typed-word 2nd use: no prompt")
	_check(d.note_word_typed("the", "teh") == "prompt",
		"typed-word 3rd use: prompt (correction must not swallow learning)")
	# The typed word gains frequency, so medium stops "correcting" it.
	_check(d.word_frequency("teh") >= 3, "typed word gains frequency")
	var d2 := SimKeyboardDict.new()
	d2.aggression = "medium"
	for i in 4:
		d2.note_word_typed("the", "teh")
	_check(d2.autocorrect("teh") == "", "adopted typo stops being corrected")
	# The learn prompt names the TYPED word, not the correction.
	var d3 := SimKeyboardDict.new()
	d3.auto_learn = false
	d3.note_word_typed("the", "teh")
	d3.note_word_typed("the", "teh")
	_check(d3.note_word_typed("the", "teh") == "prompt", "prompt fires")
	_check(d3.last_prompt_word == "teh",
		"prompt names the typed word (got '%s')" % d3.last_prompt_word)


# --- blue-underline marks + tap-to-review + save ----------------------------------------------------------

func _new_open_keyboard() -> Array:
	# Fresh save file per keyboard test — learned words and the
	# never-correct list persist to disk, so reset for isolation.
	DirAccess.remove_absolute("user://test_keyboard_dict.cfg")
	var kb := PhoneKeyboard.new()
	var root := Node.new()
	root.add_child(kb)
	var field := LineEdit.new()
	root.add_child(field)
	kb.dict.aggression = "medium"
	kb.open_for(field, 1.0)
	return [kb, root, field]


func _test_marks_and_revert() -> void:
	var parts: Array = _new_open_keyboard()
	var kb: PhoneKeyboard = parts[0]
	var root: Node = parts[1]
	var field: LineEdit = parts[2]
	# Type "helo", hit space -> corrected, blue-underline mark recorded.
	field.text = "helo"
	kb._complete_word()
	_check(field.text == "hello ", "space corrects helo->hello (got '%s')" % field.text)
	var marks: Array = kb.autocorrect_marks()
	_check(marks.size() == 1, "one blue-underline mark (got %d)" % marks.size())
	var m: Dictionary = marks[0]
	_check(String(m.get("typed")) == "helo" and String(m.get("corrected")) == "hello",
		"mark records typed+corrected")
	_check(int(m.get("start")) == 0 and int(m.get("end")) == 5,
		"mark covers the corrected word")
	# Tap the mark -> "did you mean X or Y?" dialog.
	kb._on_mark_tapped(m)
	_check(kb._learn_dialog != null, "tap opens did-you-mean dialog")
	# Pick the original typing -> reverts, blacklists, asks to save.
	kb._revert_mark(m)
	_check(field.text == "helo ", "revert restores original (got '%s')" % field.text)
	_check(kb.autocorrect_marks().is_empty(), "mark cleared after revert")
	_check(kb.dict.is_correction_blocked("helo", "hello"),
		"revert blacklists the correction")
	_check(kb.dict.autocorrect("helo") == "",
		"blacklisted correction never repeats")
	_check(kb._learn_dialog != null, "save-word dialog shown after revert")
	# Save it -> learned permanently.
	kb._confirm_save_word("helo")
	_check(kb.dict.is_learned("helo"), "saved word is learned")
	_check(kb.dict.is_known("helo"), "saved word is known")
	_check(kb._learn_dialog == null, "dialog dismissed after save")
	kb.close()
	root.free()


func _test_manual_revert() -> void:
	var parts: Array = _new_open_keyboard()
	var kb: PhoneKeyboard = parts[0]
	var root: Node = parts[1]
	var field: LineEdit = parts[2]
	field.text = "helo"
	kb._complete_word()
	_check(field.text == "hello ", "corrected first (got '%s')" % field.text)
	# User backspaces the corrected word and retypes their version.
	for i in 6:
		kb._backspace()
	_check(field.text == "", "backspaced clean")
	field.text = "helo"
	kb._complete_word()
	_check(field.text == "helo ",
		"manual revert keeps original (got '%s')" % field.text)
	_check(kb.dict.is_correction_blocked("helo", "hello"),
		"manual revert blacklists the correction")
	_check(kb._learn_dialog != null, "save dialog offered after manual revert")
	kb._dismiss_learn_dialog()
	# Typing it again later is never corrected.
	field.text = "helo helo"
	kb._complete_word()
	_check(field.text == "helo helo ",
		"repeat typing not corrected (got '%s')" % field.text)
	kb.close()
	root.free()


# --- persistence: learned words + never-correct list -------------------------------------------------------

func _test_learning_persistence() -> void:
	DirAccess.remove_absolute("user://test_keyboard_dict.cfg")
	var d := SimKeyboardDict.new()
	d.note_correction_overridden("teh", "the")
	d.add_learned_word("zork")
	d.save_dict()
	var d2 := SimKeyboardDict.new()
	d2.load_dict()
	_check(d2.is_correction_blocked("teh", "the"), "blacklist survives save/load")
	_check(d2.is_learned("zork"), "learned words survive save/load")
	# High aggression: the blocked correction must not repeat (other
	# distance-1 candidates like "tbh" are a separate ranking matter).
	d2.aggression = "high"
	_check(d2.autocorrect("teh") == "", "loaded blacklist blocks correction")
	var blocks: Array = d2.correction_blocks()
	_check(blocks.size() == 1 and String(blocks[0][0]) == "teh"
		and String(blocks[0][1]) == "the", "correction_blocks lists the entry")
	_check(d2.remove_correction_block("teh", "the"), "remove block returns true")
	_check(not d2.is_correction_blocked("teh", "the"), "block removed")
	_check(not d2.remove_correction_block("teh", "the"), "double remove false")
	d2.clear_correction_blocks()
	_check(d2.correction_blocks().is_empty(), "clear empties the list")


# --- key sizes (Jeremy 2026-10-05: bigger keys) ------------------------------------------------------------------

func _test_key_sizes() -> void:
	var kb := PhoneKeyboard.new()
	var k := kb._make_key("Q", Color.WHITE, Color.BLACK)
	_check(k.custom_minimum_size.y >= 88.0,
		"keys are large, >=88px tall (got %s)" % k.custom_minimum_size.y)
	k.free()
	kb.free()


# --- Jeremy 2026-10-06 (polish round 2): the stuck-glow bug -------------------
# On touch screens the last-tapped key stayed highlighted (hover stylebox
# stuck: Godot's emulated mouse never leaves the key). button_up must
# force-drop the hover state.

func _test_key_glow_release() -> void:
	var kb := PhoneKeyboard.new()
	var k := kb._make_key("Q", Color(0.2, 0.2, 0.24), Color.WHITE)
	# Wiring: release -> glow fix, press -> pop.
	_check(k.button_down.is_connected(kb._key_press_pop.bind(k)),
		"key button_down wired to _key_press_pop")
	_check(k.button_up.is_connected(kb._key_release_glow.bind(k)),
		"key button_up wired to _key_release_glow")
	# The fix itself: headless-safe, no tree needed.
	k.mouse_filter = Control.MOUSE_FILTER_STOP
	kb._key_release_glow(k)
	_check(k.mouse_filter == Control.MOUSE_FILTER_STOP,
		"after release, key ends with MOUSE_FILTER_STOP (hover dropped)")
	# Desktop still gets hover feedback — the hover stylebox survives.
	_check(k.get_theme_stylebox("hover") != null,
		"key hover stylebox still present for desktop")
	# Pretty overhaul: hairline border on the key.
	var sb: StyleBoxFlat = k.get_theme_stylebox("normal") as StyleBoxFlat
	_check(sb != null and sb.border_width_left >= 1,
		"key has hairline border (polish round 2)")
	# Invalid keys are a no-op, not a crash.
	kb._key_release_glow(null)
	k.free()
	kb._key_release_glow(k)  # freed key: no-op, no crash
	kb.free()


# --- learn dialog names the typed word, not the correction -------------------------------------------------

func _test_learn_dialog_names_typed_word() -> void:
	var parts: Array = _new_open_keyboard()
	var kb: PhoneKeyboard = parts[0]
	var root: Node = parts[1]
	var field: LineEdit = parts[2]
	kb.dict.auto_learn = false
	field.text = "teh"
	kb._complete_word()  # -> "the "
	field.text = "the teh"
	kb._complete_word()  # -> "the the "
	field.text = "the the teh"
	kb._complete_word()  # 3rd "teh" -> prompt
	_check(kb._pending_learn == "teh",
		"learn dialog names the typed word (got '%s')" % kb._pending_learn)
	kb._dismiss_learn_dialog()
	kb.close()
	root.free()


# --- dialog buttons work end-to-end + accepting a correction ----------------------------

func _test_review_dialog_buttons() -> void:
	var parts: Array = _new_open_keyboard()
	var kb: PhoneKeyboard = parts[0]
	var root: Node = parts[1]
	var field: LineEdit = parts[2]
	# "teh" -> "the" with a mark; tap it to open the review dialog.
	field.text = "teh"
	kb._complete_word()
	var marks: Array = kb.autocorrect_marks()
	_check(marks.size() == 1, "mark recorded for dialog test")
	kb._on_mark_tapped(marks[0])
	_check(kb._learn_dialog != null, "review dialog opened")
	var btn_row: HBoxContainer = kb._learn_dialog.get_meta("btn_row")
	_check(btn_row.get_child_count() == 2, "dialog has keep + revert buttons")
	# Button 0 = keep the correction: mark cleared, text untouched.
	var keep_btn: Button = btn_row.get_child(0)
	keep_btn.pressed.emit()
	_check(field.text == "the ", "keeping correction leaves text (got '%s')" % field.text)
	_check(kb.autocorrect_marks().is_empty(), "mark cleared after keeping")
	_check(kb._learn_dialog == null, "dialog dismissed after keeping")
	kb.close()
	root.free()


func _test_review_dialog_revert_button() -> void:
	var parts: Array = _new_open_keyboard()
	var kb: PhoneKeyboard = parts[0]
	var root: Node = parts[1]
	var field: LineEdit = parts[2]
	field.text = "teh"
	kb._complete_word()
	var marks: Array = kb.autocorrect_marks()
	kb._on_mark_tapped(marks[0])
	var btn_row: HBoxContainer = kb._learn_dialog.get_meta("btn_row")
	# Button 1 = take back the original: reverts + blacklists + save dialog.
	var revert_btn: Button = btn_row.get_child(1)
	revert_btn.pressed.emit()
	_check(field.text == "teh ", "revert button restores original (got '%s')" % field.text)
	_check(kb.dict.is_correction_blocked("teh", "the"),
		"revert button blacklists the correction")
	_check(kb._learn_dialog != null, "save-word dialog follows revert")
	# Save it from the dialog button.
	var save_row: HBoxContainer = kb._learn_dialog.get_meta("btn_row")
	var save_btn: Button = save_row.get_child(0)
	save_btn.pressed.emit()
	_check(kb.dict.is_learned("teh"), "save button learns the word")
	_check(kb._learn_dialog == null, "dialog dismissed after save")
	kb.close()
	root.free()


# --- Jeremy 2026-10-06 (launch readiness): keyboard safe-bottom lift --------
# The custom keyboard is a PhoneUI child, outside the safe-inset content
# column — its bottom sheet used to sit flush on the phone's bottom edge,
# under the drawn home-indicator pill and the real iOS home-indicator zone.
# It must lift by the shell's safe-bottom inset.

class _FakePhone extends Node:
	var bottom := 0.0

	func phone_safe_bottom() -> float:
		return bottom


func _test_keyboard_safe_bottom_lift() -> void:
	DirAccess.remove_absolute("user://test_keyboard_dict.cfg")
	var shell := _FakePhone.new()
	shell.bottom = 72.0
	var kb := PhoneKeyboard.new()
	shell.add_child(kb)
	var field := LineEdit.new()
	shell.add_child(field)
	kb.dict.aggression = "medium"
	kb.open_for(field, 1.0)
	_check(kb._panel != null, "kb lift: panel built")
	_check(kb._panel.offset_bottom == -72.0,
		"kb lift: panel bottom lifted by safe inset (got %s)" % kb._panel.offset_bottom)
	_check(kb._panel.offset_top < -72.0,
		"kb lift: panel top above the lifted bottom (got %s)" % kb._panel.offset_top)
	# Fallback: a parent without the hook keeps the old flush layout.
	var plain := Node.new()
	var kb2 := PhoneKeyboard.new()
	plain.add_child(kb2)
	var field2 := LineEdit.new()
	plain.add_child(field2)
	kb2.open_for(field2, 1.0)
	_check(kb2._panel.offset_bottom == 0.0,
		"kb lift: no hook -> panel flush (got %s)" % kb2._panel.offset_bottom)
	# PhoneUI exposes its stored inset.
	var ui := PhoneUI.new()
	_check(ui.phone_safe_bottom() == 72.0,
		"kb lift: PhoneUI default safe bottom 72 (got %s)" % ui.phone_safe_bottom())
	kb.close()
	kb2.close()
	shell.free()
	plain.free()
	ui.free()


# --- learn-dialog tap-outside -----------------------------------------------------

## Jeremy's tap-outside-to-close rule: the keyboard's "Add word to
## dictionary?" dialog dismisses when the dim outside the card is tapped —
## the dim is no longer dead. Tap-outside = "Not now" (word not learned).
func _test_learn_dialog_tap_outside() -> void:
	var parts: Array = _new_open_keyboard()
	var kb: PhoneKeyboard = parts[0]
	var root: Node = parts[1]
	kb._show_learn_dialog("zork")
	var dlg: Control = kb._learn_dialog
	_check(dlg != null, "learn dialog: popup shown")
	if dlg == null:
		kb.close()
		root.free()
		return
	var dim: ColorRect = null
	for c in dlg.get_children():
		if c is ColorRect:
			dim = c
			break
	_check(dim != null, "learn dialog: dim present")
	_check(dim.gui_input.get_connections().size() > 0,
		"learn dialog: dim wired for tap-outside")
	# Buttons still exist (explicit choice paths preserved).
	var btn_row: HBoxContainer = dlg.get_meta("btn_row")
	_check(btn_row.get_child_count() == 2, "learn dialog: both buttons kept")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	dim.gui_input.emit(touch)
	_check(kb._learn_dialog == null, "learn dialog: tap outside dismisses")
	_check(not kb.dict.is_learned("zork"),
		"learn dialog: tap outside does not learn the word")
	kb.close()
	root.free()
