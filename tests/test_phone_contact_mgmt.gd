extends SceneTree
## Tests for Jeremy 2026-10-06 contact features (phone polish round 2):
##  1. World popup (UnitInfoPanel) shows the NPC's pfp + a Message button
##     that emits message_unit -> the phone opens a Messenger thread.
##  2. Thread header add-to-contacts toggle (sim API it drives).
##  3. Long-press on a My Contacts row opens the manage menu
##     (Remove contact / Block) instead of opening the chat.
##  4. Settings app blocked list, with Unblock per entry.
##
## Run: Godot --headless --path . -s res://tests/test_phone_contact_mgmt.gd

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
	_test_contact_roundtrip()
	_test_block_roundtrip()
	_test_contact_menu()
	_test_settings_blocked_list()
	_test_thread_item_longpress()
	_test_world_popup_message()
	print("test_phone_contact_mgmt: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var mind := SimMind.new(gs)
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	return {"gs": gs, "mind": mind, "phone": phone, "court": court}


func _spawn(w: Dictionary, faction: String, job: String) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, job, -1, Vector2(100, 100))
	mind.ensure(u)
	return u


func _new_ui(w: Dictionary) -> PhoneUI:
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(w["gs"], w["phone"], w["court"])
	return ui


func _find_button(n: Node, label_text: String) -> Button:
	# queue_free() is deferred — skip zombies from the previous screen.
	if n.is_queued_for_deletion():
		return null
	if n is Button and (n as Button).text == label_text:
		return n as Button
	for c: Node in n.get_children():
		var b: Button = _find_button(c, label_text)
		if b != null:
			return b
	return null


func _test_contact_roundtrip() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var u := _spawn(w, "humans", "worker")
	var uid: int = int(u["id"])
	_check(phone.add_contact(uid), "add_contact returns true")
	_check(phone.is_contact(uid), "is_contact after add")
	_check(not phone.add_contact(uid), "add_contact dup returns false")
	_check(phone.remove_contact(uid), "remove_contact returns true")
	_check(not phone.is_contact(uid), "is_contact false after remove")
	_check(not phone.remove_contact(uid), "remove_contact missing returns false")
	(w["gs"] as GameState).queue_free()


func _test_block_roundtrip() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var u := _spawn(w, "humans", "worker")
	var uid: int = int(u["id"])
	var key := "u%d" % uid
	phone.add_contact(uid)
	_check(phone.block_citizen(uid), "block_citizen returns true")
	_check(phone.is_blocked(uid), "is_blocked after block")
	_check(phone.blocked_keys().has(key), "blocked_keys lists the NPC")
	_check(not phone.is_contact(uid), "blocked NPC leaves contacts")
	# Jeremy 2026-09-28: blocking fully silences them.
	_check(phone.send_message(uid, "hello?") == "",
		"send to blocked NPC returns empty (silenced)")
	_check(phone.unblock(uid), "unblock returns true")
	_check(not phone.is_blocked(uid), "not blocked after unblock")
	_check(not phone.unblock(uid), "unblock again returns false")
	(w["gs"] as GameState).queue_free()


func _test_contact_menu() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var ui := _new_ui(w)
	var u := _spawn(w, "humans", "worker")
	var uid: int = int(u["id"])
	var key := "u%d" % uid
	phone.add_contact(uid)
	var card := Control.new()
	ui.add_child(card)
	ui._show_contact_menu(key, card)
	_check(ui._contact_menu != null and is_instance_valid(ui._contact_menu),
		"long-press opens the contact menu")
	var rm: Button = _find_button(ui._contact_menu, "Remove contact")
	var blk: Button = _find_button(ui._contact_menu, "Block")
	_check(rm != null, "menu has Remove contact")
	_check(blk != null, "menu has Block")
	# Remove contact via the menu button.
	rm.pressed.emit()
	_check(not phone.is_contact(uid), "menu Remove contact removes the NPC")
	_check(ui._contact_menu == null, "menu dismisses after action")
	# Block via the menu button.
	phone.add_contact(uid)
	ui._show_contact_menu(key, card)
	blk = _find_button(ui._contact_menu, "Block")
	blk.pressed.emit()
	_check(phone.is_blocked(uid), "menu Block blocks the NPC")
	_check(not phone.is_contact(uid), "blocked NPC leaves contacts")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_settings_blocked_list() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var ui := _new_ui(w)
	var u := _spawn(w, "humans", "worker")
	var uid: int = int(u["id"])
	phone.block_citizen(uid)
	ui._show_settings()
	var unb: Button = _find_button(ui, "Unblock")
	_check(unb != null, "Settings blocked list shows an Unblock button")
	unb.pressed.emit()
	_check(not phone.is_blocked(uid), "Unblock button unblocks the NPC")
	ui._show_settings()
	_check(_find_button(ui, "Unblock") == null,
		"no Unblock buttons once the list is empty")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_thread_item_longpress() -> void:
	var w := _new_world()
	var ui := _new_ui(w)
	var tapped: Array = []
	var menued: Array = []
	var card: PanelContainer = ui._thread_item("Nora", "hi", 0,
		func() -> void: tapped.append(1),
		{}, "", "",
		func(_c: Control) -> void: menued.append(1))
	ui.add_child(card)
	# Long hold: press, backdate the press timestamp 700ms, release.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(10, 10)
	card.gui_input.emit(press)
	card.set_meta("_press_msec", Time.get_ticks_msec() - 700)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(10, 10)
	card.gui_input.emit(release)
	_check(menued.size() == 1, "long-press opens the context menu")
	_check(tapped.is_empty(), "long-press does NOT open the chat")
	# Short tap: menu stays shut, chat opens.
	tapped.clear()
	menued.clear()
	card.gui_input.emit(press)
	card.gui_input.emit(release)
	_check(tapped.size() == 1, "short tap opens the chat")
	_check(menued.is_empty(), "short tap does NOT open the menu")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_world_popup_message() -> void:
	var w := _new_world()
	var u := _spawn(w, "ogres", "warrior")
	var uid: int = int(u["id"])
	var panel := UnitInfoPanel.new()
	root.add_child(panel)
	panel._build()  # headless: _ready fires a frame later; _build is idempotent
	var got: Array = []
	panel.message_unit.connect(func(mid: int) -> void: got.append(mid))
	panel.show_unit(u)
	var msg: Button = _find_button(panel, "Message")
	_check(msg != null, "world popup has a Message button")
	var has_pfp := false
	var stack: Array = [panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is TextureRect:
			has_pfp = true
		for c: Node in n.get_children():
			stack.append(c)
	_check(has_pfp, "world popup shows the NPC's pfp")
	msg.pressed.emit()
	_check(got == [uid], "Message button emits message_unit with the NPC id")
	# Enemy NPCs get the same treatment (Jeremy: even enemies).
	var e := _spawn(w, "undead", "warrior")
	panel.show_unit(e, "", -1.0, true)
	_check(_find_button(panel, "Message") != null,
		"enemy popup also has a Message button")
	panel.queue_free()
	(w["gs"] as GameState).queue_free()
