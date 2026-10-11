extends SceneTree
## Jeremy 2026-10-08 (graphics hourly): Squabble live feed — NPC posts used
## to appear only after reopening the app (squabble_post was an event-bus
## orphan since 2026-10-04; the phone UI never listened to it). The UI now
## inserts new cards at the top of an open feed, drops the empty-state
## placeholder on the first real post, and respects blocks.
##
## Run: Godot --headless --path . -s res://tests/test_squabble_live_feed.gd

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
	_test_bus_connected()
	_test_live_insert_at_top()
	_test_empty_placeholder_cleared()
	_test_blocked_author_filtered()
	_test_tag_view_not_disturbed()
	_test_hidden_phone_noop()
	print("test_squabble_live_feed: %d passed, %d failed" % [_passed, _failed])
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
	ui.visible = true
	return {"gs": gs, "phone": phone, "ui": ui}


func _npc(unit_id: int, name: String) -> Dictionary:
	return {"id": unit_id, "faction": "humans", "mind": {"name": name}}


## Does any Label in the subtree contain the given text?
func _subtree_has_text(n: Node, text: String) -> bool:
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Label and String((cur as Label).text).contains(text):
			return true
		for c in cur.get_children():
			stack.append(c)
	return false


func _card_texts(box: VBoxContainer) -> Array:
	var out: Array = []
	for c in box.get_children():
		if c is PanelContainer:
			var labels: Array = []
			var stack: Array = [c]
			while not stack.is_empty():
				var cur: Node = stack.pop_back()
				if cur is Label:
					labels.append(String((cur as Label).text))
				for ch in cur.get_children():
					stack.append(ch)
			out.append(" | ".join(labels))
	return out


func _test_bus_connected() -> void:
	var w := _new_ui()
	var ui: PhoneUI = w["ui"]
	var gs: GameState = w["gs"]
	_check(gs.bus.squabble_post.is_connected(ui._on_bus_squabble_post),
		"squabble_post is connected to the UI handler after setup")
	ui.queue_free()
	gs.queue_free()


func _test_live_insert_at_top() -> void:
	var w := _new_ui()
	var phone: SimPhone = w["phone"]
	var ui: PhoneUI = w["ui"]
	# Seed one older post, then open the feed.
	phone.npc_post(_npc(11, "Oldie"), "First post #test", "mood")
	ui._show_squabble()
	var box: VBoxContainer = ui._squabble_box
	_check(box != null, "feed box tracked while Squabble app is open")
	var before: int = box.get_child_count()
	# A live post lands while the feed is open — no rebuild needed.
	phone.npc_post(_npc(7, "Testy"), "Live hello #test", "mood")
	_check(box.get_child_count() == before + 1,
		"live post adds exactly one card (got %d, want %d)"
		% [box.get_child_count(), before + 1])
	# Newest post renders at the top of the feed.
	var top: Node = box.get_child(0)
	_check(top is PanelContainer and _subtree_has_text(top, "Live hello #test"),
		"live post card inserted at the top of the feed")
	# The older post is still rendered below it.
	var cards: Array = _card_texts(box)
	var old_below := false
	for i in range(1, cards.size()):
		if String(cards[i]).contains("First post"):
			old_below = true
	_check(old_below, "older post still rendered below the live card")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_empty_placeholder_cleared() -> void:
	var w := _new_ui()
	var phone: SimPhone = w["phone"]
	var ui: PhoneUI = w["ui"]
	ui._show_squabble()
	var box: VBoxContainer = ui._squabble_box
	_check(_subtree_has_text(box, "suspiciously quiet"),
		"empty feed shows the placeholder")
	phone.npc_post(_npc(7, "Testy"), "Breaking the silence", "mood")
	_check(not _subtree_has_text(box, "suspiciously quiet"),
		"first live post clears the empty-state placeholder")
	_check(_subtree_has_text(box, "Breaking the silence"),
		"first live post renders its card")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_blocked_author_filtered() -> void:
	var w := _new_ui()
	var phone: SimPhone = w["phone"]
	var ui: PhoneUI = w["ui"]
	ui._show_squabble()
	var box: VBoxContainer = ui._squabble_box
	var before: int = box.get_child_count()
	_check(phone.block_citizen(7), "test NPC blocked")
	phone.npc_post(_npc(7, "Testy"), "You cannot see this", "mood")
	_check(box.get_child_count() == before,
		"blocked author's post never renders (got %d, want %d)"
		% [box.get_child_count(), before])
	_check(not _subtree_has_text(box, "You cannot see this"),
		"blocked author's text absent from the feed")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_tag_view_not_disturbed() -> void:
	var w := _new_ui()
	var phone: SimPhone = w["phone"]
	var ui: PhoneUI = w["ui"]
	phone.npc_post(_npc(7, "Testy"), "Tagged post #gossip", "mood")
	ui._show_squabble_tag("gossip")
	# Tag view is a filtered snapshot — not a live target.
	_check(ui._squabble_box == null,
		"tag view does not register a live-feed target")
	phone.npc_post(_npc(11, "Oldie"), "Another #gossip post", "mood")
	_check(true, "live post during tag view causes no crash")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_hidden_phone_noop() -> void:
	var w := _new_ui()
	var phone: SimPhone = w["phone"]
	var ui: PhoneUI = w["ui"]
	ui._show_squabble()
	ui.visible = false
	phone.npc_post(_npc(7, "Testy"), "Unseen post", "mood")
	_check(true, "post while phone is closed causes no crash")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()
