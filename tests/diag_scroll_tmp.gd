extends SceneTree
## Diagnostic v2: does a touch-drag starting on a card reach the ScrollContainer?
## Run: --headless --path . -s res://tests/diag_scroll_tmp.gd

var _got: Array = []


func _initialize() -> void:
	print("=== scroll diagnostic v2 ===")
	root.size = Vector2i(390, 844)
	await process_frame
	await process_frame
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var mind := SimMind.new(gs)
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	for i in range(25):
		var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
			Vector2(100 + i * 8, 100))
		mind.ensure(u)
		phone.add_contact(int(u["id"]))
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	ui.open_app("messenger")
	await process_frame
	await process_frame
	var sc: ScrollContainer = null
	var stack: Array = [ui]
	while not stack.is_empty() and sc == null:
		var n: Node = stack.pop_back()
		if n is ScrollContainer:
			sc = n
			break
		for ch in n.get_children():
			stack.append(ch)
	if sc == null:
		print("NO SCROLLCONTAINER")
		quit(1)
		return
	print("sc.size = ", sc.size, " content = ",
		(sc.get_child(0) as Control).get_combined_minimum_size())
	sc.gui_input.connect(func(ev: InputEvent) -> void:
		_got.append(ev.get_class()))
	# Find first card center.
	var box: Control = sc.get_child(0)
	var card: Control = null
	for ch in box.get_children():
		if ch is PanelContainer and (ch as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			card = ch
			break
	var cpos: Vector2 = card.get_global_rect().get_center()
	print("card center = ", cpos)
	var card_got: Array = []
	card.gui_input.connect(func(ev: InputEvent) -> void:
		card_got.append(ev.get_class()))
	# Sanity: does push_input deliver a mouse press to the card at all?
	var mb := InputEventMouseButton.new()
	mb.position = cpos
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	root.push_input(mb)
	await process_frame
	print("events reaching card.gui_input via push_input: ", card_got)
	# Push a full touch sequence through the viewport.
	var t := InputEventScreenTouch.new()
	t.position = cpos
	t.pressed = true
	t.index = 0
	root.push_input(t)
	await process_frame
	for i in range(5):
		var d := InputEventScreenDrag.new()
		d.position = cpos + Vector2(0, -20.0 * (i + 1))
		d.relative = Vector2(0, -20)
		d.index = 0
		root.push_input(d)
		await process_frame
	var t2 := InputEventScreenTouch.new()
	t2.position = cpos + Vector2(0, -100)
	t2.pressed = false
	t2.index = 0
	root.push_input(t2)
	await process_frame
	print("events reaching sc.gui_input: ", _got)
	print("scroll_vertical = ", sc.scroll_vertical)
	print("=== done ===")
	quit(0)
