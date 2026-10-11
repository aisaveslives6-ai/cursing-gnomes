extends SceneTree
## SC1-style title screen (Jeremy 2026-10-08): clean vertical button stack,
## ONE thin tips overlay line at the bottom (his "Tips?" — the full band
## stays gone), banner as overlay modal only, living background.

var _passed := 0
var _failed := 0
var _menu: MainMenu


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + name)


func _buttons_in_order(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button and (c as Button).visible:
			out.append((c as Button).text)
		_buttons_in_order(c, out)


func _collect_tip_labels(n: Node, out: Array) -> void:
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is Label and (x as Label).text.begins_with("TIP:"):
			out.append(x)
		for c in x.get_children():
			stack.push_back(c)


func _has_tip_label(n: Node) -> bool:
	var out: Array = []
	_collect_tip_labels(n, out)
	return not out.is_empty()


func _init() -> void:
	_menu = MainMenu.new()
	root.add_child(_menu)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var menu := _menu
	_check(menu._screen == "title", "boots to title screen")

	# SC1 button order: New Game, Continue, Saved Worlds, Sandbox Observe,
	# Adventure Mode, then Settings / Credits / Hearsay.
	var texts: Array = []
	_buttons_in_order(menu._refit_vbox, texts)
	var i_new := texts.find("New Game")
	var i_con := texts.find("Continue")
	var i_wor := texts.find("Saved Worlds")
	var i_san := texts.find("Sandbox Observe")
	var i_adv := texts.find("Adventure Mode")
	var i_set := texts.find("Settings")
	var i_cre := texts.find("Credits")
	var i_hea := texts.find("Hearsay")
	_check(i_new >= 0, "New Game button present")
	_check(i_wor >= 0, "Saved Worlds button present")
	_check(i_san >= 0, "Sandbox Observe button present")
	_check(i_adv >= 0, "Adventure Mode button present")
	_check(i_set >= 0, "Settings button present")
	_check(i_cre >= 0, "Credits button present")
	_check(i_hea >= 0, "Hearsay button present")
	_check(i_new < i_wor and i_wor < i_san and i_san < i_adv,
		"big buttons in SC1 order: New Game < Saved Worlds < Sandbox Observe < Adventure Mode")
	if i_con >= 0:
		_check(i_new < i_con and i_con < i_wor, "Continue sits between New Game and Saved Worlds")
	else:
		_passed += 1  # hidden with no saves — acceptable headless
	_check(i_adv < i_set and i_set < i_cre and i_cre < i_hea,
		"small row after big stack: Settings < Credits < Hearsay")

	# Jeremy 2026-10-08 ("Tips?"): ONE thin tips line is back on the title —
	# overlay only, never in the layout. The old full band stays gone.
	var tip_labels: Array = []
	_collect_tip_labels(menu, tip_labels)
	_check(tip_labels.size() == 1, "exactly one TIP: overlay line on title")
	if tip_labels.size() == 1:
		var tl: Label = tip_labels[0]
		_check(tl.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"tip line never eats taps")
		_check(tl.autowrap_mode == TextServer.AUTOWRAP_OFF and tl.clip_text,
			"tip line is single-line, clipped")
		var tlp := tl.get_parent()
		var tip_in_vbox := false
		while tlp != null:
			if tlp == menu._refit_vbox:
				tip_in_vbox = true
				break
			tlp = tlp.get_parent()
		_check(not tip_in_vbox, "tip line is NOT inline in the title VBox")
		_check(tl.get_parent() == menu._root, "tip line is a _root overlay")

	# Banner is an overlay modal, not inline in the layout.
	_check(menu._banner != null and is_instance_valid(menu._banner),
		"update banner present (overlay, version change)")
	_check(menu._banner_overlay != null and is_instance_valid(menu._banner_overlay),
		"banner overlay wrapper present")
	var bp := menu._banner.get_parent()
	var in_vbox := false
	while bp != null:
		if bp == menu._refit_vbox:
			in_vbox = true
			break
		bp = bp.get_parent()
	_check(not in_vbox, "banner is NOT inline in the title VBox")
	menu._dismiss_banner()
	_check(menu._banner == null, "banner dismisses on tap")
	_check(menu._banner_overlay == null or not is_instance_valid(menu._banner_overlay),
		"banner overlay freed on dismiss")

	# Logo: real texture on device, styled fallback headless.
	_check(menu._logo_rect != null or _has_fallback_logo(menu),
		"logo (or headless fallback) present")

	# Living background: Ken Burns + themed particles wired.
	var src := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_check(src.contains("BG_ZOOM_PERIOD"), "Ken Burns zoom constants present")
	_check(src.contains("_bg_rect.scale = Vector2(_z, _z)"), "Ken Burns zoom applied per-frame")
	_check(src.contains("func _theme_particle_params"), "scene-themed particles present")
	_check(src.contains("func _build_theme_particles"), "theme particle layer built")
	_check(src.contains("_on_sc1_hover"), "button hover breathe wired")
	_check(src.contains("func _sc1_button"), "SC1 button factory present")
	_check(src.contains("func _maybe_show_banner_overlay"), "banner overlay function present")

	# Tips kept for loading screens, off the title.
	_check(MainMenu.random_tip().begins_with("TIP:"), "random_tip() serves loading screens")

	print("test_sc1_title: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _has_fallback_logo(n: Node) -> bool:
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is Label and (x as Label).text == MainMenu.TITLE:
			return true
		for c in x.get_children():
			stack.push_back(c)
	return false
