extends SceneTree
## Cursing Gnomes — Rumors app on the phone (Jeremy 2026-10-06: every
## routine is now hearsay/chat + the phone controls the whole game).
##
## Covers:
##   - HOME_APPS contains the rumors app (label + resolvable icon texture),
##     appended last (army at index 10, rumors at 11).
##   - open_app("rumors") opens the rumors screen; back target is home;
##     back chevron returns home.
##   - The rumors screen renders live SimHearsay.live_rumors() cards
##     (heat tag, kind tag, text, meta line) — hottest first.
##   - Empty rumor mill shows the quiet-streets empty state, not a crash.
##   - Sparse/malformed rumor dicts render with fallbacks, never a crash.
##   - With no hearsay wired, the screen says so instead of crashing.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_phone_rumors.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes phone rumors-app tests ===")
	_test_rumors_app_registered()
	_test_rumors_app_opens()
	_test_rumors_app_no_hearsay_safe()
	_test_rumors_cards_render()
	_test_rumors_empty_state()
	_test_rumors_sparse_dict_safe()
	_test_rumors_heat_and_kind_tags()
	_test_rumors_home_order_includes_rumors()
	_test_war_tag_gating()
	_test_build_dedups_identical_texts()
	_test_meta_line_named_attribution()
	_test_cards_claim_full_width()
	# Async tests last: _initialize awaits them so the summary print and
	# quit() run after their checks land.
	await _test_war_tag_end_to_end_with_diplomacy()
	await _test_rumor_list_scrollable_and_compact()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])  # player = humans
	var s := SimSeasons.new(gs)
	s.reset()
	gs.seasons = s
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	return {"gs": gs, "phone": phone, "court": court}


func _new_ui(w: Dictionary) -> PhoneUI:
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(w["gs"], w["phone"], w["court"])
	return ui


func _collect_texts(ui: PhoneUI) -> Array[String]:
	var out: Array[String] = []
	var stack: Array = [ui]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out.append((n as Label).text)
		for c in n.get_children():
			stack.append(c)
	return out


func _rumors_entry() -> Array:
	for a in PhoneUI.HOME_APPS:
		if String(a[0]) == "rumors":
			return a
	return []


func _test_rumors_app_registered() -> void:
	_check("rumors app registered", not _rumors_entry().is_empty())
	var e := _rumors_entry()
	_check("rumors label", String(e[1]) == "Rumors")
	_check("rumors icon path", String(e[2]) == "res://assets/ui/phone/app_rumors.png")
	_check("rumors icon exists", ResourceLoader.exists(String(e[2])))
	_check("rumors icon loads", load(String(e[2])) is Texture2D)
	# Append-last convention: army stays pinned at 10, rumors at 11 (last).
	_check("army still canonical index 10",
		String(PhoneUI.HOME_APPS[10][0]) == "army")
	_check("rumors canonical index 11",
		String(PhoneUI.HOME_APPS[11][0]) == "rumors")
	_check("rumors is last app",
		String(PhoneUI.HOME_APPS[PhoneUI.HOME_APPS.size() - 1][0]) == "rumors")


func _test_rumors_app_opens() -> void:
	var w := _new_world()
	var ui := _new_ui(w)
	ui.open_app("rumors")
	_check("rumors screen", ui.current_screen() == "rumors")
	_check("rumors back target home", ui._back_target_for("rumors") == "home")
	ui._on_status_back()
	_check("back from rumors goes home", ui.current_screen() == "home")
	ui.queue_free()
	w["gs"].queue_free()


func _test_rumors_app_no_hearsay_safe() -> void:
	# No hearsay wired: screen must explain, not crash.
	var w := _new_world()
	w["phone"].hearsay = null
	var ui := _new_ui(w)
	ui.open_app("rumors")
	_check("rumors screen without hearsay", ui.current_screen() == "rumors")
	var texts := _collect_texts(ui)
	var joined := "\n".join(texts)
	_check("no-hearsay notice", joined.find("The taverns are closed.") >= 0)
	ui.queue_free()
	w["gs"].queue_free()


func _test_rumors_cards_render() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	phone.hearsay.seed_rumor(
		"The test whisper about the old mill.", "war", "elves", 0.9, -1)
	var ui := _new_ui(w)
	ui.open_app("rumors")
	var texts := _collect_texts(ui)
	var joined := "\n".join(texts)
	_check("rumor text shown", joined.find("The test whisper about the old mill.") >= 0)
	_check("heat tag shown", joined.find("HOT") >= 0)
	_check("kind tag shown", joined.find("WAR") >= 0)
	_check("meta line shown", joined.find("day ") >= 0)
	ui.queue_free()
	w["gs"].queue_free()


func _test_rumors_empty_state() -> void:
	var box := VBoxContainer.new()
	root.add_child(box)
	PhoneRumors.build(box, [])
	var texts: Array[String] = []
	var stack: Array = [box]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			texts.append((n as Label).text)
		for c in n.get_children():
			stack.append(c)
	var joined := "\n".join(texts)
	_check("empty state text", joined.find("Quiet streets.") >= 0)
	box.queue_free()


func _test_rumors_sparse_dict_safe() -> void:
	# Missing/empty fields must render fallbacks, never crash.
	var box := VBoxContainer.new()
	root.add_child(box)
	PhoneRumors.build(box, [{}])
	PhoneRumors.build(box, [{"text": "  ", "kind": "", "heat": 9.9}])
	var texts: Array[String] = []
	var stack: Array = [box]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			texts.append((n as Label).text)
		for c in n.get_children():
			stack.append(c)
	var joined := "\n".join(texts)
	_check("sparse card fallback text", joined.find("too faint to make out") >= 0)
	_check("sparse heat clamped to HOT", joined.find("HOT") >= 0)
	_check("empty kind falls back to WORD", joined.find("WORD") >= 0)
	box.queue_free()


func _test_rumors_heat_and_kind_tags() -> void:
	_check("heat >= 0.7 is HOT", PhoneRumors.heat_tag(0.9) == "HOT")
	_check("heat >= 0.4 is WARM", PhoneRumors.heat_tag(0.5) == "WARM")
	_check("low heat is faint", PhoneRumors.heat_tag(0.1) == "faint")
	_check("kind war", PhoneRumors.kind_label("war") == "WAR")
	_check("kind smear", PhoneRumors.kind_label("smear") == "SMEAR")
	_check("kind life", PhoneRumors.kind_label("life") == "TALK")
	_check("unknown kind capitalized", PhoneRumors.kind_label("harvest_festival") == "Harvest Festival")
	_check("blank kind is WORD", PhoneRumors.kind_label("  ") == "WORD")


func _test_rumors_home_order_includes_rumors() -> void:
	var w := _new_world()
	var ui := _new_ui(w)
	# _load_home_order auto-appends new apps after the saved order.
	_check("home order includes rumors", "rumors" in ui._home_order)
	ui.queue_free()
	w["gs"].queue_free()


## Jeremy 2026-10-06 (iPhone bugfix): WAR tags must reflect live
## diplomacy — stale capture rumors during peacetime are WAR TALK.
func _test_war_tag_gating() -> void:
	var active := func(f: String) -> bool: return f == "elves"
	var quiet := func(_f: String) -> bool: return false
	_check("war tag when faction at war",
		PhoneRumors.war_tag("elves", active) == "WAR")
	_check("war talk when faction at peace",
		PhoneRumors.war_tag("elves", quiet) == "WAR TALK")
	_check("war talk when subject empty",
		PhoneRumors.war_tag("", active) == "WAR TALK")
	_check("war talk when subject blank",
		PhoneRumors.war_tag("   ", active) == "WAR TALK")
	_check("war talk when no war check wired",
		PhoneRumors.war_tag("elves", Callable()) == "WAR TALK")
	# kind_label keeps its unconditional mapping (other callers/tests).
	_check("kind war still WAR via kind_label",
		PhoneRumors.kind_label("war") == "WAR")


## Jeremy 2026-10-06 (iPhone bugfix): identical rumor texts collapse to
## one card — the seed path only dedups when a subject is set.
func _test_build_dedups_identical_texts() -> void:
	var box := VBoxContainer.new()
	root.add_child(box)
	var r1 := {"id": 1, "kind": "war", "subject": "",
		"text": "The miller saw lights in the old mill.", "day": 3,
		"heat": 0.9, "knowers": [], "witnesses": [], "distortions": 0,
		"from_gazette": false, "debunked": false, "verified": false}
	var r2 := r1.duplicate()
	r2["id"] = 2
	r2["heat"] = 0.5
	var r3 := {"id": 3, "kind": "life", "subject": "",
		"text": "The baker's cat had kittens.", "day": 3,
		"heat": 0.4, "knowers": [], "witnesses": [], "distortions": 0,
		"from_gazette": false, "debunked": false, "verified": false}
	PhoneRumors.build(box, [r1, r2, r3])
	var texts: Array[String] = []
	var stack: Array = [box]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			texts.append((n as Label).text)
		for c in n.get_children():
			stack.append(c)
	_check("summary counts deduped rumors",
		"\n".join(texts).find("2 whispers on the wind") >= 0)
	var cards := 0
	for c in box.get_children():
		if c is PanelContainer:
			cards += 1
	_check("duplicate text renders one card", cards == 2)
	box.queue_free()


## Jeremy 2026-10-06 (iPhone bugfix): named source beats raw counts.
func _test_meta_line_named_attribution() -> void:
	var names := {11: "Grak", 22: "Mira"}
	var name_of := func(uid: int) -> String:
		return String(names.get(uid, "a gnome"))
	var r := {"day": 4, "knowers": [11, 22], "witnesses": [],
		"debunked": false, "verified": false, "from_gazette": false,
		"distortions": 0, "kind": "life"}
	var line := PhoneRumors.meta_line(r, Callable(), name_of)
	_check("meta names first knower", line.find("heard from Grak") >= 0)
	_check("meta counts the rest", line.find("(+1 more)") >= 0)
	var rw := {"day": 4, "knowers": [22], "witnesses": [11],
		"debunked": false, "verified": false, "from_gazette": false,
		"distortions": 0, "kind": "life"}
	_check("meta prefers eyewitness",
		PhoneRumors.meta_line(rw, Callable(), name_of).find("seen by Grak") >= 0)
	# Without a name lookup the old count phrasing survives.
	var plain := PhoneRumors.meta_line(r)
	_check("meta without names keeps counts",
		plain.find("2 gnomes whisper it") >= 0)


## Cards must claim the full list width (expand flag) so wrapped labels
## re-flow at that width instead of staying at narrow min-width wraps.
func _test_cards_claim_full_width() -> void:
	var box := VBoxContainer.new()
	root.add_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PhoneRumors.build(box, [{
		"id": 1, "kind": "war", "subject": "elves",
		"text": "A long rumor text that will wrap across several lines once the card claims the full available width of the list.",
		"day": 3, "heat": 0.8, "knowers": [], "witnesses": [],
		"distortions": 0, "from_gazette": false, "debunked": false,
		"verified": false}])
	var card: PanelContainer = null
	for c in box.get_children():
		if c is PanelContainer:
			card = c
	_check("card rendered", card != null)
	if card != null:
		_check("card claims full width",
			card.size_flags_horizontal == Control.SIZE_EXPAND_FILL)
		var inner: VBoxContainer = card.get_child(0)
		_check("card inner box claims full width",
			inner.size_flags_horizontal == Control.SIZE_EXPAND_FILL)
		var body_ok := false
		var stack: Array = [inner]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is Label and (n as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
				if n.size_flags_horizontal == Control.SIZE_EXPAND_FILL:
					body_ok = true
			for c2 in n.get_children():
				stack.append(c2)
		_check("wrapped labels claim full width", body_ok)
	box.queue_free()


func _new_world_5f() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var s := SimSeasons.new(gs)
	s.reset()
	gs.seasons = s
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	return {"gs": gs, "phone": phone, "court": court, "dip": gs.diplomacy}


## End to end: a war-kind rumor about the elves shows WAR TALK in
## peacetime, WAR once war is declared, WAR TALK again after peace.
## (Third-party war chatter legitimately stays WAR TALK throughout —
## those factions aren't at war themselves.)
## NOTE: open_app calls are separated by a frame — _clear() frees the old
## screen with queue_free(), so collecting texts synchronously would also
## sweep up the stale, not-yet-freed labels.
func _test_war_tag_end_to_end_with_diplomacy() -> void:
	var w := _new_world_5f()
	var phone: SimPhone = w["phone"]
	phone.hearsay.seed_rumor(
		"The elves seized the border mill!", "war", "elves", 0.9, -1)
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(w["gs"], w["phone"], w["court"], w["dip"])
	ui.open_app("rumors")
	await create_timer(0.05).timeout
	var texts := _collect_texts(ui)
	_check("peacetime war rumor is WAR TALK", "WAR TALK" in texts)
	_check("peacetime war rumor is not WAR", not ("WAR" in texts))
	w["dip"].declare_war("humans", "elves", "testing")
	ui.open_app("rumors")
	await create_timer(0.05).timeout
	texts = _collect_texts(ui)
	_check("wartime war rumor is WAR", "WAR" in texts)
	w["dip"].make_peace("humans", "elves")
	ui.open_app("rumors")
	await create_timer(0.05).timeout
	texts = _collect_texts(ui)
	_check("post-peace war rumor back to WAR TALK", "WAR TALK" in texts)
	_check("post-peace war rumor not WAR", not ("WAR" in texts))
	ui.queue_free()
	w["gs"].queue_free()


## The rumors list must actually be scrollable in a 390px viewport, and
## cards must wrap at full width (no 900px-tall cards from min-width wraps).
func _test_rumor_list_scrollable_and_compact() -> void:
	var win := Window.new()
	win.size = Vector2i(390, 844)
	root.add_child(win)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	win.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	sc.add_child(box)
	var rumors: Array = []
	for i in 24:
		rumors.append({
			"id": i, "kind": "war", "subject": "elves",
			"text": "Rumor %d: the elves are massing troops near the border and the drums beat at night while the taverns overflow with nervous whispers." % i,
			"day": 5, "heat": 0.9, "knowers": [], "witnesses": [],
			"distortions": 0, "from_gazette": false, "debunked": false,
			"verified": false})
	PhoneRumors.build(box, rumors)
	# Two frames so the container layout settles (labels re-wrap at the
	# assigned width via minimum_size_changed).
	await create_timer(0.05).timeout
	await create_timer(0.05).timeout
	var sb := sc.get_v_scroll_bar()
	_check("rumor list exceeds viewport (scrollable)",
		sb.max_value > sb.page)
	# Cards claim the full list width (no narrow min-width cards).
	var full_bleed := true
	for c in box.get_children():
		if c is PanelContainer:
			if absf((c as Control).size.x - box.size.x) > 2.0:
				full_bleed = false
	_check("cards are full-bleed", full_bleed)
	win.queue_free()
