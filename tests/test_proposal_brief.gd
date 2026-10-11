extends SceneTree
## Jeremy 2026-10-06: advisors present REASONS, not verdicts. War/peace
## proposals carry a strategic brief (strength ratios, enemy weakness,
## treasury runway) computed by SimProposals — the phone's strategic
## proposal modal must SHOW the scouts' case between the question and
## the Approve/Deny buttons. No brief -> no extra label (modal unchanged).
##
## Run: Godot --headless --path . -s res://tests/test_proposal_brief.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("FAIL: ", test_name)


func _initialize() -> void:
	_test_war_modal_shows_brief()
	_test_no_brief_no_label()
	_test_peace_modal_shows_brief()
	_test_brief_styling()
	_test_buttons_still_present()
	print("test_proposal_brief: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _make_ui() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	var phone := SimPhone.new(gs)
	gs.phone_sys = phone
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	return [ui]


func _labels_under(node: Node) -> Array:
	var out: Array = []
	_collect_labels(node, out)
	return out


func _collect_labels(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Label:
			out.append(c)
		_collect_labels(c, out)


func _show_war(ui: PhoneUI, brief: String) -> Control:
	var details := {"target": "elves"}
	if brief != "":
		details["brief"] = brief
	ui.show_strategic_proposal({"id": 7, "kind": "declare_war",
		"details": details})
	return ui.get_child(ui.get_child_count() - 1)


func _test_war_modal_shows_brief() -> void:
	var pack: Array = _make_ui()
	var ui: PhoneUI = pack[0]
	var brief := "The scouts report: we outnumber them 3-to-1."
	var overlay := _show_war(ui, brief)
	var found := false
	for lbl in _labels_under(overlay):
		if (lbl as Label).text == brief:
			found = true
	_check("war modal shows the strategic brief", found)
	ui._dismiss_modal(overlay)
	ui.queue_free()


func _test_no_brief_no_label() -> void:
	var pack: Array = _make_ui()
	var ui: PhoneUI = pack[0]
	var overlay := _show_war(ui, "")
	var count := 0
	for lbl in _labels_under(overlay):
		if (lbl as Label).text.begins_with("The scouts report:"):
			count += 1
	_check("war modal without brief adds no brief label", count == 0)
	ui._dismiss_modal(overlay)
	ui.queue_free()


func _test_peace_modal_shows_brief() -> void:
	var pack: Array = _make_ui()
	var ui: PhoneUI = pack[0]
	var brief := "The scouts report: the treasury can fund roughly a 2-day campaign."
	ui.show_strategic_proposal({"id": 8, "kind": "sue_for_peace",
		"details": {"target": "elves", "brief": brief}})
	var overlay := ui.get_child(ui.get_child_count() - 1)
	var found := false
	for lbl in _labels_under(overlay):
		if (lbl as Label).text == brief:
			found = true
	_check("peace modal shows the strategic brief", found)
	ui._dismiss_modal(overlay)
	ui.queue_free()


func _test_brief_styling() -> void:
	var pack: Array = _make_ui()
	var ui: PhoneUI = pack[0]
	var brief := "The scouts report: a truce binds us."
	var overlay := _show_war(ui, brief)
	var lbl: Label = null
	for l in _labels_under(overlay):
		if (l as Label).text == brief:
			lbl = l
	_check("brief label found for styling", lbl != null)
	if lbl != null:
		_check("brief label smaller than the question (FONT_SM=34)",
			lbl.get_theme_font_size("font_size") == 34)
		_check("brief label dimmed (not the bright question color)",
			lbl.get_theme_color("font_color") == Color(0.62, 0.64, 0.68))
		_check("brief label centered",
			lbl.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
		_check("brief label wraps",
			lbl.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART)
	ui._dismiss_modal(overlay)
	ui.queue_free()


func _test_buttons_still_present() -> void:
	var pack: Array = _make_ui()
	var ui: PhoneUI = pack[0]
	var overlay := _show_war(ui, "The scouts report: x.")
	var texts: Array = []
	_collect_buttons(overlay, texts)
	_check("deny button still present", "Deny" in texts)
	_check("approve button still present", "Approve" in texts)
	ui._dismiss_modal(overlay)
	ui.queue_free()


func _collect_buttons(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button:
			out.append((c as Button).text)
		_collect_buttons(c, out)
