extends SceneTree
## Cursing Gnomes — Rumors app scroll regression (Jeremy 2026-10-07).
##
## Jeremy on iPhone: "Can't scroll in the rumors app." 24 whispers shown
## but the list would not scroll.
##
## Root cause: every rumor card is a default-STOP PanelContainer. With 24
## full-bleed cards covering the whole viewport, no touch drag ever
## reached the ScrollContainer — drags died on the card under the finger.
## (The existing test_phone_rumors.gd "scrollable" check only proved the
## content overflows the viewport, which was never the broken part.)
##
## Fix contract (PhoneRumors._scroll_safe): every Control in a card
## subtree is MOUSE_FILTER_IGNORE except the Investigate Button subtree,
## which keeps STOP so the button stays tappable.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_rumors_scroll.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes rumors scroll tests ===")
	_test_cards_do_not_swallow_drags()
	_test_investigate_button_stays_tappable()
	_test_cards_without_investigate_also_safe()
	_test_rumors_screen_end_to_end()
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


func _rumor(i: int) -> Dictionary:
	return {
		"id": i, "kind": "war", "subject": "elves",
		"text": "Rumor %d: the elves are massing troops near the border." % i,
		"day": 5, "heat": 0.9, "knowers": [], "witnesses": [],
		"distortions": 0, "from_gazette": false, "debunked": false,
		"verified": false}


## Every Control in the card subtree that is NOT inside a Button must be
## IGNORE — nothing left that can swallow a touch drag before it reaches
## the ScrollContainer.
func _assert_drag_safe(card: PanelContainer, tag: String) -> void:
	var stack: Array = [[card, false]]
	var bad := 0
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var in_button: bool = item[1]
		if n is Button:
			in_button = true
		if n is Control and not in_button:
			if (n as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
				bad += 1
		for c in n.get_children():
			stack.append([c, in_button])
	_check("%s: no drag-swallowing (STOP) controls outside buttons" % tag,
		bad == 0)


func _find_cards(box: VBoxContainer) -> Array:
	var out: Array = []
	for c in box.get_children():
		if c is PanelContainer:
			out.append(c)
	return out


func _find_buttons(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is Button:
			out.append(x)
		for c in x.get_children():
			stack.append(c)
	return out


func _test_cards_do_not_swallow_drags() -> void:
	var box := VBoxContainer.new()
	root.add_child(box)
	var rumors: Array = [_rumor(1), _rumor(2)]
	PhoneRumors.build(box, rumors,
		Callable(), func(_rid: int) -> void: pass)
	var cards := _find_cards(box)
	_check("two cards built", cards.size() == 2)
	for i in cards.size():
		_assert_drag_safe(cards[i], "card %d" % i)
	box.queue_free()


func _test_investigate_button_stays_tappable() -> void:
	var box := VBoxContainer.new()
	root.add_child(box)
	PhoneRumors.build(box, [_rumor(1)],
		Callable(), func(_rid: int) -> void: pass)
	var cards := _find_cards(box)
	_check("card built", cards.size() == 1)
	var buttons := _find_buttons(cards[0])
	_check("investigate button present", buttons.size() == 1)
	if buttons.size() == 1:
		_check("investigate button label",
			(buttons[0] as Button).text == "Investigate")
		# STOP (the default) keeps the button tappable — the fix must not
		# have flipped it to IGNORE.
		_check("investigate button keeps STOP",
			(buttons[0] as Button).mouse_filter == Control.MOUSE_FILTER_STOP)
	box.queue_free()


func _test_cards_without_investigate_also_safe() -> void:
	# Debunked rumors render no Investigate button — the card must still
	# be drag-safe.
	var box := VBoxContainer.new()
	root.add_child(box)
	var r := _rumor(1)
	r["debunked"] = true
	PhoneRumors.build(box, [r])
	var cards := _find_cards(box)
	_check("debunked card built", cards.size() == 1)
	if cards.size() == 1:
		_assert_drag_safe(cards[0], "debunked card")
		_check("debunked card has no button",
			_find_buttons(cards[0]).is_empty())
	box.queue_free()


## End to end through the real phone UI: the rumors screen's cards must
## be drag-safe inside its real ScrollContainer.
func _test_rumors_screen_end_to_end() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var s := SimSeasons.new(gs)
	s.reset()
	gs.seasons = s
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	for i in 6:
		phone.hearsay.seed_rumor(
			"End-to-end whisper %d about the old mill." % i,
			"life", "", 0.5 + 0.05 * i, -1)
	ui.open_app("rumors")
	_check("rumors screen", ui.current_screen() == "rumors")
	var scrolls: Array = []
	var stack: Array = [ui]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is ScrollContainer:
			scrolls.append(n)
		for c in n.get_children():
			stack.append(c)
	_check("rumors screen has a scroll view", scrolls.size() >= 1)
	# Cards live inside the scroll view's box — scope there so header
	# chrome can never pollute the check.
	var cards: Array = []
	if scrolls.size() >= 1:
		var stack2: Array = [scrolls[0]]
		while not stack2.is_empty():
			var n2: Node = stack2.pop_back()
			if n2 is PanelContainer:
				cards.append(n2)
			for c2 in n2.get_children():
				stack2.append(c2)
	_check("rumors screen shows cards", cards.size() >= 6)
	for i in cards.size():
		_assert_drag_safe(cards[i], "screen card %d" % i)
	ui.queue_free()
	gs.queue_free()
