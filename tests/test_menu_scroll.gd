extends SceneTree
## Regression test: main menu must scroll when content overflows the viewport.
## Jeremy 2026-10-04: "the whole fuckin menu is bigger than the screen and
## has no scroll." Root cause: _new_screen() used a CenterContainer inside the
## ScrollContainer — CenterContainer does NOT expand for children taller than
## itself, so the ScrollContainer saw a viewport-sized child and never
## scrolled while the VBox content overflowed invisibly.
##
## Fix: outer is now a VBoxContainer with custom_minimum_size = viewport
## (centers short content via ALIGNMENT_CENTER) that grows when content is
## taller (enabling ScrollContainer scrolling).

var _passed := 0
var _failed := 0
var _menu: MainMenu


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + name)


func _init() -> void:
	_menu = MainMenu.new()
	root.add_child(_menu)
	_run.call_deferred()


func _find_scroll(m: MainMenu) -> ScrollContainer:
	for c in m._root.get_children():
		if c is ScrollContainer:
			return c
	return null


func _run() -> void:
	await process_frame
	await process_frame
	var menu := _menu

	# Walk to the faction screen (the one Jeremy reported broken).
	menu._show_faction(false)
	await process_frame
	await process_frame

	var scroll := _find_scroll(menu)
	_check(scroll != null, "faction screen has a ScrollContainer")
	if scroll == null:
		_done()
		return
	_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"horizontal scroll stays disabled")

	# The direct child of the ScrollContainer must NOT be a CenterContainer
	# (it clips tall content instead of growing).
	var outer: Control = null
	if scroll.get_child_count() > 0:
		outer = scroll.get_child(0) as Control
	_check(outer != null, "scroll has an outer content box")
	if outer == null:
		_done()
		return
	_check(not (outer is CenterContainer),
		"outer box is not a CenterContainer (must expand for tall content)")

	# Simulate tall content: the outer box must grow beyond the viewport so
	# the ScrollContainer offers scrolling.
	var vp: Vector2 = menu.get_viewport().get_visible_rect().size
	var vbox := outer as VBoxContainer
	_check(vbox != null, "outer box is a VBoxContainer")
	if vbox != null:
		_check(vbox.alignment == BoxContainer.ALIGNMENT_CENTER,
			"outer box centers short content vertically")
		# Minimum is at least viewport-sized (short menus still center).
		_check(vbox.custom_minimum_size.y >= vp.y - 1.0,
			"outer box minimum height covers viewport")

	# The inner content column (_refit_vbox) must be a descendant of outer.
	var inner := menu._refit_vbox
	_check(inner != null and is_instance_valid(inner), "inner content column exists")
	if inner != null:
		_check(inner.is_ancestor_of(inner) or outer.is_ancestor_of(inner) or inner == outer or _is_descendant_of(outer, inner),
			"inner column lives inside the scrolling outer box")

	# Tall-content simulation: add a spacer taller than the viewport and
	# verify the outer box's combined minimum exceeds the viewport height,
	# which is what makes ScrollContainer scroll.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, vp.y * 2.0)
	inner.add_child(spacer)
	await process_frame
	await process_frame
	var need: float = outer.get_combined_minimum_size().y
	_check(need > vp.y,
		"tall content makes outer box exceed viewport (scroll enabled), need=%.0f vp=%.0f" % [need, vp.y])
	spacer.queue_free()

	_done()


func _is_descendant_of(ancestor: Node, n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false


func _done() -> void:
	print("test_menu_scroll: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)
