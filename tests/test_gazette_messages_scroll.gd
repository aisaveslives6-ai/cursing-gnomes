extends SceneTree
## Cursing Gnomes — Gazette Messages scroll test (Jeremy 2026-10-10,
## menu-scroll audit).
##
## _show_gazette_messages used to build TWO ScrollContainers (open
## petitions + decided history), each SIZE_EXPAND_FILL — Godot splits the
## phone screen 50/50, so the open petitions (crown decisions: war, peace,
## builds) were squeezed into half the screen whenever history existed.
## Both sections must now share ONE full-height scroll, open petitions on
## top, with every petition card and its decision buttons inside it.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gazette_messages_scroll.gd
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
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court, gs.diplomacy)
	_w = {"gs": gs, "phone": phone, "court": court, "ui": ui}
	_run.call_deferred()


func _ui() -> PhoneUI:
	return _w["ui"] as PhoneUI


func _court() -> SimRoyalCourt:
	return _w["court"] as SimRoyalCourt


func _run() -> void:
	await process_frame
	await process_frame
	print("=== Cursing Gnomes gazette-messages scroll tests ===")
	_test_single_scroll_both_sections()
	_test_empty_state()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	(_w["ui"] as PhoneUI).queue_free()
	(_w["gs"] as GameState).queue_free()
	quit(1 if _failed > 0 else 0)


func _scrolls_under(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is ScrollContainer:
			out.append(c)
		_scrolls_under(c, out)


func _texts_under(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		_texts_under(c, out)


func _seed_petitions() -> void:
	var court := _court()
	var unit := {"id": 7, "faction": "gnomes", "mind": {}}
	var opts: Array[String] = ["Yes", "No"]
	court.petition(unit, "build", "Build a well by the north road?",
		opts)
	var done: Dictionary = court.petition(unit, "tax",
		"Lower the turnip tax?", opts)
	done["resolved"] = true
	done["choice"] = 0


func _test_single_scroll_both_sections() -> void:
	var ui := _ui()
	_seed_petitions()
	ui._clear()
	ui._show_gazette_messages()
	var rootc: Node = ui.get("_root")
	var scrolls: Array = []
	_scrolls_under(rootc, scrolls)
	_check(scrolls.size() == 1,
		"messages: exactly one ScrollContainer (was two, 50/50 split), got %d"
		% scrolls.size())
	if scrolls.is_empty():
		ui._clear()
		_court().petitions.clear()
		return
	var sc: ScrollContainer = scrolls[0]
	_check(sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"messages: horizontal scroll stays disabled")
	var box: VBoxContainer = sc.get_child(0)
	var texts: Array = []
	_texts_under(box, texts)
	var open_idx := texts.find("Petitions awaiting the crown")
	var hist_idx := texts.find("Decided")
	_check(open_idx >= 0, "messages: open-petitions section present in scroll")
	_check(hist_idx >= 0, "messages: decided-history section present in scroll")
	_check(open_idx >= 0 and hist_idx >= 0 and open_idx < hist_idx,
		"messages: open petitions listed above decided history")
	# The open petition's decision buttons must live inside the scroll.
	var btns: Array = []
	_collect_button_texts(box, btns)
	_check("Yes" in btns and "No" in btns,
		"messages: open petition Yes/No buttons inside the single scroll")
	ui._clear()
	_court().petitions.clear()


func _collect_button_texts(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button:
			out.append((c as Button).text)
		_collect_button_texts(c, out)


func _test_empty_state() -> void:
	var ui := _ui()
	_court().petitions.clear()
	ui._clear()
	ui._show_gazette_messages()
	var rootc: Node = ui.get("_root")
	var scrolls: Array = []
	_scrolls_under(rootc, scrolls)
	_check(scrolls.is_empty(),
		"messages: no scroll needed when there is nothing to list")
	var texts: Array = []
	_texts_under(rootc, texts)
	_check("No petitions. The court is suspiciously quiet." in texts,
		"messages: empty-state label shown")
	ui._clear()
